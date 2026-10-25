import math
from typing import List, Dict, Any, Tuple
from features.ai.geometry import (
    get_furniture_bbox, OccupancyGrid, compute_reachability, find_path_astar,
    get_furniture_obb, obb_overlap_sat, closest_point_on_obb, mark_obstacle_obb, OBB2D
)

PROHIBITED_ITEMS_BY_ROOM = {
    "kitchen": ["bed", "sofa", "office chair", "desk", "wardrobe", "bookshelf", "tv console", "nightstand"],
    "dining": ["bed", "sofa", "office chair", "desk", "wardrobe", "stove", "kitchen sink", "refrigerator"],
    "bathroom": ["bed", "sofa", "desk", "dining table", "tv console", "wardrobe", "refrigerator", "stove"],
    "bedroom": ["kitchen counter", "kitchen sink", "stove", "refrigerator", "conference table"],
    "office": ["bed", "kitchen counter", "kitchen sink", "stove", "refrigerator", "wardrobe"],
    "study": ["bed", "kitchen counter", "kitchen sink", "stove", "refrigerator", "wardrobe", "dining table"],
    "living": ["bed", "kitchen sink", "stove", "refrigerator", "wardrobe"]
}

def calculate_design_score(
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Evaluates the room layout and computes design subscores, functional completeness,
    compatibility checks, and an overall Design Health score.
    """
    low_room_type = (room_type or "").lower()
    critical_errors = []
    warnings = []
    
    # 1. Furniture Compatibility & Room-Type Sanity Check
    incompatible_items = []
    for f in furniture:
        f_name = f.get('name', '').lower()
        f_cat = f.get('category', '').lower()
        f_role = f.get('role', '').lower()
        
        for r_key, prohibited_list in PROHIBITED_ITEMS_BY_ROOM.items():
            if r_key in low_room_type:
                for prob in prohibited_list:
                    if prob in f_name or (prob == "office chair" and "office" in f_cat and "chair" in f_name):
                        incompatible_items.append(f.get('name', 'Unknown'))
                        break
    
    if incompatible_items:
        critical_errors.append(f"Inappropriate furniture for {room_type}: {', '.join(set(incompatible_items))}")

    # 2. Space Utilization Score
    total_furniture_area = 0.0
    for f in furniture:
        total_furniture_area += f.get('width', 100.0) * f.get('depth', 100.0)
    
    room_area = room_width * room_length
    utilization_ratio = total_furniture_area / room_area if room_area > 0 else 0.0
    
    if 0.25 <= utilization_ratio <= 0.60:
        space_util_score = 100.0
    elif utilization_ratio < 0.25:
        space_util_score = (utilization_ratio / 0.25) * 100.0 if utilization_ratio > 0 else 0.0
        if utilization_ratio < 0.15 and len(furniture) > 0:
            warnings.append("Low space utilization; room could accommodate additional functional zones.")
    elif 0.60 < utilization_ratio <= 0.80:
        space_util_score = 100.0 - ((utilization_ratio - 0.60) / 0.20) * 50.0
        warnings.append("High space utilization; room feels somewhat crowded.")
    else:
        space_util_score = max(0.0, 50.0 - ((utilization_ratio - 0.80) / 0.20) * 50.0)
        critical_errors.append("Excessive space utilization; room is over-cluttered with insufficient floor area.")
        
    space_util_score = float(max(0.0, min(100.0, space_util_score)))

    # 3. Spatial Validity & Safety Score (SAT collision detection)
    collisions = 0
    out_of_bounds = 0
    blocked_doors = 0
    blocked_windows = 0
    
    obbs = [get_furniture_obb(f) for f in furniture]
    
    # Check Collisions between furniture (OBB SAT)
    for i in range(len(obbs)):
        o1 = obbs[i]
        
        # Check wall collision: if any corners lie outside room bounds
        corners = o1.get_corners()
        wall_collision = False
        for cx, cz in corners:
            if cx < -1.0 or cx > room_width + 1.0 or cz < -1.0 or cz > room_length + 1.0:
                wall_collision = True
                break
        if wall_collision:
            out_of_bounds += 1
            critical_errors.append(f"Furniture '{furniture[i].get('name')}' exceeds room perimeter boundaries.")
            
        for j in range(i + 1, len(obbs)):
            o2 = obbs[j]
            has_overlap, _, _ = obb_overlap_sat(o1, o2)
            if has_overlap:
                collisions += 1
                critical_errors.append(f"Collision overlap between '{furniture[i].get('name')}' and '{furniture[j].get('name')}'.")
                
    # Check Door and Window Blockages
    for op in openings:
        op_x = op.get('x', 0.0)
        op_z = op.get('y', 0.0)
        op_w = op.get('width', 80.0)
        op_type = op.get('type', 'door')
        
        for idx, o1 in enumerate(obbs):
            gx, gz = closest_point_on_obb(o1, (op_x, op_z))
            dist = math.sqrt((gx - op_x)**2 + (gz - op_z)**2)
            
            if op_type == 'door':
                if dist < op_w:
                    blocked_doors += 1
                    critical_errors.append(f"Furniture '{furniture[idx].get('name')}' obstructs door entry zone.")
                    break
            elif op_type == 'window':
                if dist < 50.0:
                    blocked_windows += 1
                    warnings.append(f"Furniture '{furniture[idx].get('name')}' is positioned closely in front of window.")
                    break

    safety_score = 100.0 - (collisions * 50.0) - (out_of_bounds * 35.0) - (blocked_doors * 40.0) - (blocked_windows * 15.0)
    safety_score = float(max(0.0, min(100.0, safety_score)))

    # 4. Accessibility & Circulation Score (Rotated Obstacle Grid & Dilated Walkways)
    grid = OccupancyGrid(room_width, room_length)
    for o1 in obbs:
        mark_obstacle_obb(grid, o1)
        
    doors = [op for op in openings if op.get('type') == 'door']
    
    accessibility_rules_passed = 0
    total_accessibility_rules = 5
    
    door_cells = []
    original_door_vals = []
    for d in doors:
        cell = grid.to_cell(d.get('x', 0.0), d.get('y', 0.0))
        door_cells.append(cell)
        original_door_vals.append(grid.grid[cell[0]][cell[1]])
        grid.grid[cell[0]][cell[1]] = 0

    if doors:
        start_cell = door_cells[0]
    else:
        start_cell = grid.to_cell(room_width / 2.0, room_length / 2.0)
        if grid.grid[start_cell[0]][start_cell[1]] != 0:
            for di in range(grid.width_cells):
                for dj in range(grid.length_cells):
                    if grid.grid[di][dj] == 0:
                        start_cell = (di, dj)
                        break
                if grid.grid[start_cell[0]][start_cell[1]] == 0:
                    break
        original_start_val = grid.grid[start_cell[0]][start_cell[1]]
        grid.grid[start_cell[0]][start_cell[1]] = 0
        
    reachable_cells = compute_reachability(grid, start_cell)
    total_walkable_cells = sum(1 for i in range(grid.width_cells) for j in range(grid.length_cells) if grid.grid[i][j] == 0)
    
    reachable_ratio = len(reachable_cells) / total_walkable_cells if total_walkable_cells > 0 else 0.0
    if reachable_ratio >= 0.70:
        accessibility_rules_passed += 1
    else:
        warnings.append("Restricted floor reachability across room segments.")
        
    # Doors connection
    if len(doors) <= 1:
        accessibility_rules_passed += 1
    else:
        all_doors_connected = True
        for cell in door_cells[1:]:
            if cell not in reachable_cells:
                all_doors_connected = False
                break
        if all_doors_connected:
            accessibility_rules_passed += 1
        else:
            critical_errors.append("Path between room doors is obstructed.")
            
    # Furniture reachability
    reachable_furniture_count = 0
    for o1 in obbs:
        cos_r = abs(o1.axis_x[0])
        sin_r = abs(o1.axis_x[1])
        w = o1.width * cos_r + o1.depth * sin_r
        d = o1.width * sin_r + o1.depth * cos_r
        left = o1.cx - w / 2.0
        right = o1.cx + w / 2.0
        top = o1.cz - d / 2.0
        bottom = o1.cz + d / 2.0
        
        adj_cells = []
        i_start, j_start = grid.to_cell(left - 10, top - 10)
        i_end, j_end = grid.to_cell(right + 10, bottom + 10)
        
        for i in range(i_start, i_end + 1):
            for j in range(j_start, j_end + 1):
                if grid.is_valid_cell(i, j) and (i == i_start or i == i_end or j == j_start or j == j_end):
                    adj_cells.append((i, j))
        
        if any(cell in reachable_cells for cell in adj_cells):
            reachable_furniture_count += 1
            
    if len(furniture) == 0 or (reachable_furniture_count / len(furniture)) >= 0.80:
        accessibility_rules_passed += 1
    else:
        warnings.append("One or more furniture units are trapped without direct access pathway.")
        
    # Turning space
    has_turning_space = False
    for i in range(7, grid.width_cells - 7):
        for j in range(7, grid.length_cells - 7):
            is_circle_free = True
            for di in range(-7, 8):
                for dj in range(-7, 8):
                    if di*di + dj*dj <= 49:
                        if grid.grid[i+di][j+dj] != 0:
                            is_circle_free = False
                            break
                if not is_circle_free:
                    break
            if is_circle_free:
                has_turning_space = True
                break
        if has_turning_space:
            break
            
    if has_turning_space or len(furniture) == 0:
        accessibility_rules_passed += 1

    # Walkway Circulation Width (75 cm minimum clearance dilation)
    dilated_grid = OccupancyGrid(room_width, room_length, cell_size=10.0)
    for o1 in obbs:
        mark_obstacle_obb(dilated_grid, o1, padding=37.5)
        
    dilated_start = None
    if doors:
        d = doors[0]
        dx, dz = d.get('x', 0.0), d.get('y', 0.0)
        ci, cj = dilated_grid.to_cell(dx, dz)
        best_dist = float('inf')
        for di in range(max(0, ci - 10), min(dilated_grid.width_cells, ci + 11)):
            for dj in range(max(0, cj - 10), min(dilated_grid.length_cells, cj + 11)):
                if dilated_grid.grid[di][dj] == 0:
                    dist_c = math.sqrt((di - ci)**2 + (dj - cj)**2)
                    if dist_c < best_dist:
                        best_dist = dist_c
                        dilated_start = (di, dj)
    if dilated_start is None:
        for di in range(dilated_grid.width_cells):
            for dj in range(dilated_grid.length_cells):
                if dilated_grid.grid[di][dj] == 0:
                    dilated_start = (di, dj)
                    break
            if dilated_start:
                break
                
    walkway_passed = True
    walkway_coverage = 1.0
    if dilated_start is not None:
        dilated_reachable = compute_reachability(dilated_grid, dilated_start)
        total_dilated_walkable = sum(1 for i in range(dilated_grid.width_cells) for j in range(dilated_grid.length_cells) if dilated_grid.grid[i][j] == 0)
        walkway_coverage = len(dilated_reachable) / total_dilated_walkable if total_dilated_walkable > 0 else 0.0
        if walkway_coverage < 0.35:
            walkway_passed = False
            warnings.append("Circulation walkways are tight or constricted in major pathways.")
    elif len(furniture) > 0:
        walkway_passed = False
        walkway_coverage = 0.0
        warnings.append("Insufficient continuous circulation width across room.")
        
    if walkway_passed or len(furniture) == 0:
        accessibility_rules_passed += 1

    accessibility_score = (accessibility_rules_passed / total_accessibility_rules) * 100.0
    accessibility_score = float(max(0.0, min(100.0, accessibility_score)))
    
    if not walkway_passed and len(furniture) > 0:
        safety_score = max(0.0, safety_score - 25.0)
    
    if doors:
        for cell, val in zip(door_cells, original_door_vals):
            grid.grid[cell[0]][cell[1]] = val
    else:
        grid.grid[start_cell[0]][start_cell[1]] = original_start_val

    # 5. Ergonomics Score
    ergonomic_rules_passed = 0
    total_ergonomic_rules = 0
    
    # Kitchen Ergonomics (Counter, Sink, Stove, Fridge clearances)
    if 'kitchen' in low_room_type:
        counters = [f for f in furniture if 'counter' in f.get('name', '').lower()]
        sinks = [f for f in furniture if 'sink' in f.get('name', '').lower()]
        stoves = [f for f in furniture if 'stove' in f.get('name', '').lower() or 'cook' in f.get('name', '').lower()]
        fridges = [f for f in furniture if 'fridge' in f.get('name', '').lower() or 'refrigerator' in f.get('name', '').lower()]
        
        # Front clearance for counters and appliances (minimum 80 cm working clearance in front)
        for item in counters + sinks + stoves + fridges:
            total_ergonomic_rules += 1
            it_obb = get_furniture_obb(item)
            front_cx = it_obb.cx + (it_obb.ext_z + 40.0) * it_obb.axis_z[0]
            front_cz = it_obb.cz + (it_obb.ext_z + 40.0) * it_obb.axis_z[1]
            front_obb = OBB2D(front_cx, front_cz, it_obb.width, 80.0, it_obb.rotation)
            
            front_clear = True
            for cx, cz in front_obb.get_corners():
                if cx < 0.0 or cx > room_width or cz < 0.0 or cz > room_length:
                    front_clear = False
                    break
            if front_clear:
                ergonomic_rules_passed += 1
                
        # Kitchen Work Triangle Check
        if sinks and stoves and fridges:
            total_ergonomic_rules += 1
            s_pt = (sinks[0]['x'], sinks[0]['z'])
            st_pt = (stoves[0]['x'], stoves[0]['z'])
            f_pt = (fridges[0]['x'], fridges[0]['z'])
            
            d_sink_stove = math.sqrt((s_pt[0] - st_pt[0])**2 + (s_pt[1] - st_pt[1])**2)
            d_sink_fridge = math.sqrt((s_pt[0] - f_pt[0])**2 + (s_pt[1] - f_pt[1])**2)
            d_stove_fridge = math.sqrt((st_pt[0] - f_pt[0])**2 + (st_pt[1] - f_pt[1])**2)
            triangle_perimeter = d_sink_stove + d_sink_fridge + d_stove_fridge
            
            # Efficient kitchen work triangle perimeter is between 300 cm and 800 cm
            if 250.0 <= triangle_perimeter <= 850.0:
                ergonomic_rules_passed += 1
            else:
                warnings.append(f"Kitchen work triangle perimeter ({triangle_perimeter:.0f} cm) is outside recommended range (300-800 cm).")

    # Bed clearances
    beds = [f for f in furniture if 'bed' in f.get('name', '').lower() or f.get('category', '').lower() == 'bedroom']
    for bed in beds:
        total_ergonomic_rules += 1
        bed_obb = get_furniture_obb(bed)
        left_clear = True
        right_clear = True
        
        left_cx = bed_obb.cx - (bed_obb.ext_x + 30.0) * bed_obb.axis_x[0]
        left_cz = bed_obb.cz - (bed_obb.ext_x + 30.0) * bed_obb.axis_x[1]
        left_obb = OBB2D(left_cx, left_cz, 60.0, bed_obb.depth, bed_obb.rotation)
        
        right_cx = bed_obb.cx + (bed_obb.ext_x + 30.0) * bed_obb.axis_x[0]
        right_cz = bed_obb.cz + (bed_obb.ext_x + 30.0) * bed_obb.axis_x[1]
        right_obb = OBB2D(right_cx, right_cz, 60.0, bed_obb.depth, bed_obb.rotation)
        
        for cx, cz in left_obb.get_corners():
            if cx < 0.0 or cx > room_width or cz < 0.0 or cz > room_length:
                left_clear = False
                break
        for cx, cz in right_obb.get_corners():
            if cx < 0.0 or cx > room_width or cz < 0.0 or cz > room_length:
                right_clear = False
                break
                
        for f2 in furniture:
            if f2.get('id') == bed.get('id'):
                continue
            f2_name = f2.get('name', '').lower()
            f2_role = f2.get('role', '').lower()
            if 'stand' in f2_name or 'night' in f2_name or 'bedside' in f2_role or f2_role == 'bedside':
                continue
                
            o2 = get_furniture_obb(f2)
            if left_clear:
                has_overlap, _, _ = obb_overlap_sat(left_obb, o2)
                if has_overlap: left_clear = False
            if right_clear:
                has_overlap, _, _ = obb_overlap_sat(right_obb, o2)
                if has_overlap: right_clear = False
                    
        is_large_bed = bed.get('width', 100.0) >= 160.0
        if is_large_bed:
            if left_clear and right_clear:
                ergonomic_rules_passed += 1
            elif left_clear or right_clear:
                ergonomic_rules_passed += 0.8
        else:
            if left_clear or right_clear:
                ergonomic_rules_passed += 1

    # TV Viewing Distance
    sofas = [f for f in furniture if 'sofa' in f.get('name', '').lower() or 'couch' in f.get('name', '').lower()]
    tvs = [f for f in furniture if 'tv' in f.get('name', '').lower() or 'television' in f.get('name', '').lower() or 'media' in f.get('name', '').lower()]
    if sofas and tvs:
        total_ergonomic_rules += 1
        s = sofas[0]
        t = tvs[0]
        dist = math.sqrt((s.get('x', 0.0) - t.get('x', 0.0))**2 + (s.get('z', 0.0) - t.get('z', 0.0))**2)
        if 150.0 <= dist <= 350.0:
            ergonomic_rules_passed += 1

    # Desk Ergonomics
    desks = [f for f in furniture if 'desk' in f.get('name', '').lower()]
    chairs = [f for f in furniture if 'chair' in f.get('name', '').lower() and f.get('category', '').lower() != 'dining']
    if desks and chairs:
        total_ergonomic_rules += 1
        d = desks[0]
        c = chairs[0]
        dist = math.sqrt((d.get('x', 0.0) - c.get('x', 0.0))**2 + (d.get('z', 0.0) - c.get('z', 0.0))**2)
        if 50.0 <= dist <= 130.0:
            ergonomic_rules_passed += 1

    # Dining Spacing
    dining_tables = [f for f in furniture if 'table' in f.get('name', '').lower() and 'coffee' not in f.get('name', '').lower() and 'desk' not in f.get('name', '').lower()]
    dining_chairs = [f for f in furniture if 'chair' in f.get('name', '').lower() and ('dining' in f.get('name', '').lower() or f.get('category', '').lower() == 'dining')]
    if dining_tables and dining_chairs:
        total_ergonomic_rules += 1
        t = dining_tables[0]
        all_chairs_clear = True
        for dc in dining_chairs:
            dc_x, dc_z = dc.get('x', 0.0), dc.get('z', 0.0)
            dx = dc_x - t.get('x', 0.0)
            dz = dc_z - t.get('z', 0.0)
            length = math.sqrt(dx**2 + dz**2)
            if length > 0:
                p_cx = dc_x + 25.0 * (dx / length)
                p_cz = dc_z + 25.0 * (dz / length)
                p_obb = OBB2D(p_cx, p_cz, 50.0, 50.0, dc.get('rotationY', 0.0))
                for cx, cz in p_obb.get_corners():
                    if cx < 0.0 or cx > room_width or cz < 0.0 or cz > room_length:
                        all_chairs_clear = False
                        break
            else:
                all_chairs_clear = False
        if all_chairs_clear:
            ergonomic_rules_passed += 1

    # Wardrobe front clearance
    wardrobes = [f for f in furniture if 'wardrobe' in f.get('name', '').lower() or 'closet' in f.get('name', '').lower() or 'dresser' in f.get('name', '').lower()]
    for wardrobe in wardrobes:
        total_ergonomic_rules += 1
        w_obb = get_furniture_obb(wardrobe)
        front_cx = w_obb.cx + (w_obb.ext_z + 40.0) * w_obb.axis_z[0]
        front_cz = w_obb.cz + (w_obb.ext_z + 40.0) * w_obb.axis_z[1]
        front_obb = OBB2D(front_cx, front_cz, w_obb.width, 80.0, w_obb.rotation)
        
        front_clear = True
        for cx, cz in front_obb.get_corners():
            if cx < 0.0 or cx > room_width or cz < 0.0 or cz > room_length:
                front_clear = False
                break
        if front_clear:
            ergonomic_rules_passed += 1
            
    ergonomic_score = (ergonomic_rules_passed / total_ergonomic_rules * 100.0) if total_ergonomic_rules > 0 else 100.0
    ergonomic_score = float(max(0.0, min(100.0, ergonomic_score)))

    # 6. Balance & Aesthetics Score
    if len(furniture) == 0:
        balance_score = 100.0
        symmetry_score = 100.0
    else:
        com_x = sum(f.get('x', 0.0) for f in furniture) / len(furniture)
        com_z = sum(f.get('z', 0.0) for f in furniture) / len(furniture)
        dev_x = com_x - room_width / 2.0
        dev_z = com_z - room_length / 2.0
        deviation = math.sqrt((dev_x / room_width)**2 + (dev_z / room_length)**2) if room_width > 0 and room_length > 0 else 0.0
        balance_score = max(0.0, 100.0 - deviation * 200.0)
        
        mid_x = room_width / 2.0
        mirrored_pairs = 0
        for i in range(len(furniture)):
            f1 = furniture[i]
            for j in range(i + 1, len(furniture)):
                f2 = furniture[j]
                if f1.get('category') == f2.get('category'):
                    d1 = f1.get('x', 0.0) - mid_x
                    d2 = f2.get('x', 0.0) - mid_x
                    if abs(d1 + d2) < 40.0:
                        mirrored_pairs += 1
                        break
        symmetry_score = min(100.0, 70.0 + (mirrored_pairs * 15.0))
        
    balance_score = float(max(0.0, min(100.0, balance_score)))
    aesthetics_score = float((balance_score + symmetry_score) / 2.0)

    # 7. Room-Function Completeness & Compatibility Score
    expected_weight = 1.0
    present_weight = 0.0
    
    names = [f.get('name', '').lower() for f in furniture]
    roles = [f.get('role', '').lower() for f in furniture]
    
    if 'kitchen' in low_room_type:
        expected_weight = 5.0
        has_counter = any('counter' in n or 'counter' in r for n, r in zip(names, roles))
        has_sink = any('sink' in n or 'cleaning' in r for n, r in zip(names, roles))
        has_fridge = any('fridge' in n or 'refrigerator' in n or 'food_storage' in r for n, r in zip(names, roles))
        has_stove = any('stove' in n or 'cook' in n or 'cooking' in r for n, r in zip(names, roles))
        has_cabinet = any('cabinet' in n or 'pantry' in n or 'storage' in r for n, r in zip(names, roles))
        
        if has_counter: present_weight += 1.5
        else: critical_errors.append("Missing essential Kitchen Counter / preparation surface.")
        if has_sink: present_weight += 1.5
        else: critical_errors.append("Missing essential Kitchen Sink station.")
        if has_fridge: present_weight += 1.0
        else: critical_errors.append("Missing essential Refrigerator food storage.")
        if has_stove: present_weight += 0.5
        if has_cabinet: present_weight += 0.5

    elif 'dining' in low_room_type:
        expected_weight = 4.0
        has_table = any('table' in n for n in names)
        chair_count = sum(1 for n in names if 'chair' in n)
        has_sideboard = any('cabinet' in n or 'sideboard' in n for n in names)
        
        if has_table: present_weight += 2.0
        else: critical_errors.append("Missing Dining Table.")
        if chair_count >= 2: present_weight += 1.5
        elif chair_count == 1: present_weight += 0.8
        else: critical_errors.append("Missing Dining Chairs.")
        if has_sideboard: present_weight += 0.5

    elif 'bedroom' in low_room_type:
        expected_weight = 4.0
        if any('bed' in n for n in names): present_weight += 2.0
        else: critical_errors.append("Missing Bed.")
        if any('stand' in n or 'night' in n or 'bedside' in n for n in names): present_weight += 1.0
        if any('wardrobe' in n or 'dresser' in n or 'closet' in n for n in names): present_weight += 1.0

    elif 'living' in low_room_type:
        expected_weight = 4.0
        if any('sofa' in n or 'couch' in n for n in names): present_weight += 2.0
        else: critical_errors.append("Missing Sofa seating.")
        if any('coffee' in n or 'table' in n for n in names): present_weight += 1.0
        if any('tv' in n or 'television' in n or 'media' in n for n in names): present_weight += 1.0

    elif any(k in low_room_type for k in ['office', 'manager', 'executive', 'study', 'work']):
        expected_weight = 3.0
        if any('desk' in n for n in names): present_weight += 2.0
        else: critical_errors.append("Missing Work Desk.")
        if any('chair' in n for n in names): present_weight += 1.0
        else: critical_errors.append("Missing Office/Study Chair.")

    elif 'bathroom' in low_room_type or 'restroom' in low_room_type:
        expected_weight = 2.0
        if any('vanity' in n or 'basin' in n for n in names): present_weight += 2.0
        else: critical_errors.append("Missing Bathroom Vanity.")
    else:
        expected_weight = 1.0
        present_weight = 1.0 if len(furniture) > 0 else 0.0

    base_func_score = (present_weight / expected_weight) * 100.0
    
    # Check wall alignment of storage/cabinets/beds
    zoning_rules_checked = 0
    zoning_rules_passed = 0
    for f in furniture:
        f_name = f.get('name', '').lower()
        f_cat = f.get('category', '').lower()
        if 'bed' in f_name or f_cat == 'bedroom':
            obb = get_furniture_obb(f)
            head_x = obb.cx - obb.ext_z * obb.axis_z[0]
            head_z = obb.cz - obb.ext_z * obb.axis_z[1]
            min_head_dist = min(head_z, room_length - head_z, head_x, room_width - head_x)
            zoning_rules_checked += 1
            if min_head_dist <= 25.0:
                zoning_rules_passed += 1
        elif any(k in f_name for k in ['counter', 'sink', 'stove', 'fridge', 'wardrobe', 'cabinet', 'bookshelf', 'vanity']):
            obb = get_furniture_obb(f)
            min_wall_dist = min(
                obb.cx - obb.ext_x,
                room_width - (obb.cx + obb.ext_x),
                obb.cz - obb.ext_z,
                room_length - (obb.cz + obb.ext_z)
            )
            zoning_rules_checked += 1
            if min_wall_dist <= 30.0:
                zoning_rules_passed += 1
                
    zoning_score = (zoning_rules_passed / zoning_rules_checked * 100.0) if zoning_rules_checked > 0 else 100.0
    functionality_score = base_func_score * 0.6 + zoning_score * 0.4
    
    # Severely penalize functionality if incompatible furniture was placed
    if incompatible_items:
        functionality_score = max(0.0, functionality_score - len(incompatible_items) * 35.0)
        
    functionality_score = float(max(0.0, min(100.0, functionality_score)))

    # 8. Lighting Score (Window preservation)
    blocked_window_count = 0
    windows = [op for op in openings if op.get('type') == 'window']
    for win in windows:
        win_x = win.get('x', 0.0)
        win_z = win.get('y', 0.0)
        for o1 in obbs:
            f_height = getattr(o1, 'height', 100.0)
            if f_height > 100.0:
                gx, gz = closest_point_on_obb(o1, (win_x, win_z))
                dist = math.sqrt((gx - win_x)**2 + (gz - win_z)**2)
                if dist < 60.0:
                    blocked_window_count += 1
                    break
    lighting_score = max(0.0, 100.0 - (blocked_window_count * 25.0))

    # 9. Overall Design Health Score Calculation with Hard Quality Gate Caps
    raw_overall_score = (
        0.20 * accessibility_score +
        0.15 * space_util_score +
        0.15 * ergonomic_score +
        0.10 * balance_score +
        0.10 * aesthetics_score +
        0.15 * functionality_score +
        0.15 * safety_score
    )
    
    # HARD QUALITY GATES:
    # If there are critical errors (incompatible furniture, out-of-bounds, collisions, missing essential items),
    # the design score MUST be capped to <= 35% so it CANNOT be rated as "Good Layout" or "Great Design".
    if critical_errors:
        overall_score = min(35.0, raw_overall_score * 0.35)
    elif warnings:
        overall_score = min(88.0, raw_overall_score)
    else:
        overall_score = raw_overall_score
        
    overall_score = float(max(0.0, min(100.0, overall_score)))
    
    # Rating label
    if overall_score >= 85.0 and not critical_errors:
        rating_status = "Great Design"
    elif overall_score >= 70.0 and not critical_errors:
        rating_status = "Good Layout"
    elif overall_score >= 50.0:
        rating_status = "Needs Improvement"
    else:
        rating_status = "Unacceptable / Critical Issues"

    return {
        "overall_score": round(overall_score, 1),
        "rating_status": rating_status,
        "subscores": {
            "space_utilization": round(space_util_score, 1),
            "accessibility": round(accessibility_score, 1),
            "ergonomics": round(ergonomic_score, 1),
            "aesthetics": round(aesthetics_score, 1),
            "balance": round(balance_score, 1),
            "functionality": round(functionality_score, 1),
            "safety": round(safety_score, 1),
            "lighting": round(lighting_score, 1)
        },
        "critical_errors": critical_errors,
        "warnings": warnings,
        "details": {
            "collisions": collisions,
            "out_of_bounds": out_of_bounds,
            "blocked_doors": blocked_doors,
            "blocked_windows": blocked_windows,
            "walkways_clear": walkway_passed,
            "walkway_coverage": round(walkway_coverage * 100.0, 1),
            "utilization_ratio": round(utilization_ratio, 3),
            "item_count": len(furniture),
            "incompatible_items": list(set(incompatible_items))
        }
    }
