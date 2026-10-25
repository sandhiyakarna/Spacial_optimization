import uuid
import math
from typing import Any, Dict, List, Type
from features.ai.geometry import (
    get_furniture_bbox, OccupancyGrid, compute_reachability, find_path_astar,
    get_furniture_obb, obb_overlap_sat, closest_point_on_obb, OBB2D
)
from features.ai.scoring import calculate_design_score

def generate_recommendations(
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """
    Evaluates layout constraints and generates a list of actionable recommendation cards.
    """
    recommendations = []
    
    # Calculate baseline scores
    baseline = calculate_design_score(room_width, room_length, room_type, furniture, openings)
    overall = baseline['overall_score']
    subscores = baseline['subscores']
    details = baseline['details']
    
    utilization_ratio = details.get('utilization_ratio', 0.0)
    collisions = details.get('collisions', 0)
    out_of_bounds = details.get('out_of_bounds', 0)
    blocked_doors = details.get('blocked_doors', 0)
    blocked_windows = details.get('blocked_windows', 0)
    
    # 0. Style detection
    styles = {}
    for f in furniture:
        f_style = f.get('style')
        if f_style:
            styles[f_style] = styles.get(f_style, 0) + 1
    dominant_style = "Modern"
    if styles:
        dominant_style = max(styles, key=styles.get)
        
    # 1. Door Obstruction Check
    doors = [op for op in openings if op.get('type') == 'door']
    for dr in doors:
        dr_x = dr.get('x', 0.0)
        dr_z = dr.get('y', 0.0) # y represents the Z coordinate in openings JSON
        dr_w = dr.get('width', 80.0)
        
        for f in furniture:
            obb = get_furniture_obb(f)
            gx, gz = closest_point_on_obb(obb, (dr_x, dr_z))
            dist = math.sqrt((gx - dr_x)**2 + (gz - dr_z)**2)
            
            if dist < dr_w:
                # Try moving it 45cm away from the door
                dx = f.get('x', 0.0) - dr_x
                dz = f.get('z', 0.0) - dr_z
                length = (dx**2 + dz**2)**0.5
                if length > 0:
                    sh_x = (dx / length) * 45.0
                    sh_z = (dz / length) * 45.0
                else:
                    sh_x = 45.0
                    sh_z = 0.0
                    
                simulated_furniture = [
                    (other.copy() if other['id'] != f['id'] else {**other, 'x': other['x'] + sh_x, 'z': other['z'] + sh_z})
                    for other in furniture
                ]
                simulated_scores = calculate_design_score(room_width, room_length, room_type, simulated_furniture, openings)
                safety_diff = simulated_scores['subscores']['safety'] - baseline['subscores']['safety']
                
                recommendations.append({
                    "id": str(uuid.uuid4()),
                    "recommendation_type": "Validation",
                    "title": f"Move {f.get('name', 'Furniture')} away from Doorway",
                    "description": f"Shift the {f.get('name', 'furniture')} by {int(abs(sh_x) + abs(sh_z))} cm to unblock the door swing area.",
                    "reason": f"Door swing area clearance is currently obstructed.",
                    "rule_triggered": "Door Clearance Rule",
                    "expected_improvement": "Unobstructed entry and safety compliance.",
                    "score_impact": f"Safety Score +{int(max(5.0, safety_diff))}%",
                    "action": {
                        "action_type": "move",
                        "furniture_id": f['id'],
                        "dx": float(round(sh_x, 1)),
                        "dz": float(round(sh_z, 1)),
                        "rotationY": 0.0
                    }
                })

    # 2. Window Obstruction Check
    windows = [op for op in openings if op.get('type') == 'window']
    for win in windows:
        win_x = win.get('x', 0.0)
        win_z = win.get('y', 0.0)
        for f in furniture:
            obb = get_furniture_obb(f)
            gx, gz = closest_point_on_obb(obb, (win_x, win_z))
            dist = math.sqrt((gx - win_x)**2 + (gz - win_z)**2)
            
            if dist < 50.0:
                # Try moving it 35cm away
                dx = f.get('x', 0.0) - win_x
                dz = f.get('z', 0.0) - win_z
                length = (dx**2 + dz**2)**0.5
                if length > 0:
                    sh_x = (dx / length) * 35.0
                    sh_z = (dz / length) * 35.0
                else:
                    sh_x = 0.0
                    sh_z = 35.0
                    
                simulated_furniture = [
                    (other.copy() if other['id'] != f['id'] else {**other, 'x': other['x'] + sh_x, 'z': other['z'] + sh_z})
                    for other in furniture
                ]
                simulated_scores = calculate_design_score(room_width, room_length, room_type, simulated_furniture, openings)
                lighting_diff = simulated_scores['subscores']['lighting'] - baseline['subscores']['lighting']
                
                recommendations.append({
                    "id": str(uuid.uuid4()),
                    "recommendation_type": "Lighting",
                    "title": f"Unblock Window Space",
                    "description": f"Move {f.get('name')} away from the window to preserve natural light.",
                    "reason": f"Furniture is currently blocking the window light flow.",
                    "rule_triggered": "Window Clearance Rule",
                    "expected_improvement": "Improves natural illumination and ventilation.",
                    "score_impact": f"Lighting Score +{int(max(5.0, lighting_diff))}%",
                    "action": {
                        "action_type": "move",
                        "furniture_id": f['id'],
                        "dx": float(round(sh_x, 1)),
                        "dz": float(round(sh_z, 1)),
                        "rotationY": 0.0
                    }
                })

    # 3. Daylight Obstruction by Tall Furniture Check
    for win in windows:
        win_x = win.get('x', 0.0)
        win_z = win.get('y', 0.0)
        for f in furniture:
            if f.get('height', 100.0) > 100.0:
                dist = ((f.get('x', 0.0) - win_x)**2 + (f.get('z', 0.0) - win_z)**2)**0.5
                if dist < 120.0:
                    dx = f.get('x', 0.0) - win_x
                    dz = f.get('z', 0.0) - win_z
                    length = (dx**2 + dz**2)**0.5
                    sh_x = (dx / length) * 60.0 if length > 0 else 0.0
                    sh_z = (dz / length) * 60.0 if length > 0 else 60.0
                    
                    recommendations.append({
                        "id": str(uuid.uuid4()),
                        "recommendation_type": "Lighting",
                        "title": "Relocate Tall Furniture from Window",
                        "description": f"Move the tall {f.get('name')} away from the window to prevent blocking natural light.",
                        "reason": "Daylight entry is obstructed by tall furniture placed close to the window.",
                        "rule_triggered": "Daylight Obstruction Rule",
                        "expected_improvement": "Maximized natural illumination and ventilation.",
                        "score_impact": "Lighting Score +25%",
                        "action": {
                            "action_type": "move",
                            "furniture_id": f['id'],
                            "dx": float(round(sh_x, 1)),
                            "dz": float(round(sh_z, 1)),
                            "rotationY": 0.0
                        }
                    })

    # 4. Furniture Recommendations by Room Type
    low_room_type = room_type.lower()
    names = [f.get('name', '').lower() for f in furniture]
    
    if 'bedroom' in low_room_type:
        has_bed = any('bed' in n and 'stand' not in n and 'night' not in n for n in names)
        has_stand = any('stand' in n or 'night' in n or 'bedside' in n for n in names)
        has_wardrobe = any('ward' in n or 'dress' in n or 'cabinet' in n or 'closet' in n for n in names)
        has_desk = any('desk' in n or 'table' in n for n in names)
        
        if not has_bed:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Bed",
                "description": "Place a bed as the primary focal point of the bedroom.",
                "reason": "Every bedroom requires a bed to satisfy core functionality.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables bedroom sleep capability.",
                "score_impact": "Functionality Score +30%",
                "action": {
                    "action_type": "add",
                    "category": "Bedroom",
                    "style": dominant_style,
                    "name": f"{dominant_style} Bed"
                }
            })
        elif not has_stand:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Side Nightstand",
                "description": "Place a bedside nightstand adjacent to the Bed.",
                "reason": "Standard bedroom templates recommend bedside storage items.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Complete bedroom functionality and storage access.",
                "score_impact": "Functionality Score +15%",
                "action": {
                    "action_type": "add",
                    "category": "Bedroom",
                    "style": dominant_style,
                    "name": f"{dominant_style} Nightstand"
                }
            })
            
        if not has_wardrobe:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Wardrobe Storage",
                "description": f"Add a {dominant_style} wardrobe or dresser to provide clothes storage.",
                "reason": "Bedroom layout requires storage assets for clothes organization.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Sufficient storage capacity.",
                "score_impact": "Functionality Score +20%",
                "action": {
                    "action_type": "add",
                    "category": "Bedroom",
                    "style": dominant_style,
                    "name": f"{dominant_style} Wardrobe"
                }
            })
            
        if utilization_ratio < 0.25 and not has_desk:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Study Desk & Chair",
                "description": "Place a work/study desk to utilize extra space.",
                "reason": "Spacious bedroom has sufficient capacity for a secondary work area.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Multi-functional room utility.",
                "score_impact": "Functionality Score +10%",
                "action": {
                    "action_type": "add",
                    "category": "Office",
                    "style": dominant_style,
                    "name": f"{dominant_style} Study Desk"
                }
            })

    elif 'living' in low_room_type:
        has_sofa = any('sofa' in n or 'couch' in n or 'loveseat' in n for n in names)
        has_coffee = any('coffee' in n or 'table' in n for n in names)
        has_tv = any('tv' in n or 'television' in n or 'media' in n for n in names)
        
        if not has_sofa:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Living Room Sofa",
                "description": f"Place a comfortable {dominant_style} sofa for primary seating.",
                "reason": "A sofa is the key functional element of a living room.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables hospitality and guest seating.",
                "score_impact": "Functionality Score +30%",
                "action": {
                    "action_type": "add",
                    "category": "Living Room",
                    "style": dominant_style,
                    "name": f"{dominant_style} Sofa"
                }
            })
        elif not has_coffee:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Coffee Table",
                "description": "Place a coffee table in front of the Sofa.",
                "reason": "Standard living rooms benefit from a central coffee table.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Improves hospitality and comfort.",
                "score_impact": "Functionality Score +12%",
                "action": {
                    "action_type": "add",
                    "category": "Living Room",
                    "style": dominant_style,
                    "name": f"{dominant_style} Coffee Table"
                }
            })
            
        if not has_tv:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add TV Console Stand",
                "description": "Place a television media stand against the wall facing the Sofa.",
                "reason": "Media centers serve as common entertainment hubs in living areas.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables entertainment capabilities.",
                "score_impact": "Functionality Score +15%",
                "action": {
                    "action_type": "add",
                    "category": "Living Room",
                    "style": dominant_style,
                    "name": f"{dominant_style} TV Stand"
                }
            })
            
        if utilization_ratio < 0.25 and has_sofa and has_coffee:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Accent Armchair",
                "description": "Introduce an accent armchair to complement sofa seating.",
                "reason": "Spacious living room has room to support additional conversational seating.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Increases seating capacity and comfort.",
                "score_impact": "Functionality Score +10%",
                "action": {
                    "action_type": "add",
                    "category": "Living Room",
                    "style": dominant_style,
                    "name": f"{dominant_style} Accent Chair"
                }
            })

    elif 'office' in low_room_type or 'study' in low_room_type:
        has_desk = any('desk' in n or 'table' in n for n in names)
        has_chair = any('chair' in n or 'seat' in n for n in names)
        has_bookshelf = any('book' in n or 'shelf' in n or 'cabinet' in n for n in names)
        
        if not has_desk:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Work Desk",
                "description": f"Place an ergonomic {dominant_style} desk.",
                "reason": "A study or office requires a desk as a core workspace.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables work activity.",
                "score_impact": "Functionality Score +35%",
                "action": {
                    "action_type": "add",
                    "category": "Office",
                    "style": dominant_style,
                    "name": f"{dominant_style} Desk"
                }
            })
        elif not has_chair:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Office Chair",
                "description": "Place an ergonomic task chair at the desk.",
                "reason": "Office desk workspaces require an ergonomic task chair.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables comfortable sitting posture.",
                "score_impact": "Functionality Score +25%",
                "action": {
                    "action_type": "add",
                    "category": "Office",
                    "style": dominant_style,
                    "name": f"{dominant_style} Chair"
                }
            })
            
        if not has_bookshelf:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Storage Bookshelf",
                "description": "Place a storage cabinet or bookshelf against the wall.",
                "reason": "Workspaces require physical storage for archives, books, and accessories.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Improves study organization.",
                "score_impact": "Functionality Score +15%",
                "action": {
                    "action_type": "add",
                    "category": "Office",
                    "style": dominant_style,
                    "name": f"{dominant_style} Bookshelf"
                }
            })

    elif 'dining' in low_room_type or 'kitchen' in low_room_type:
        has_table = any('table' in n for n in names)
        has_chair = any('chair' in n or 'seat' in n for n in names)
        
        if not has_table:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Dining Table",
                "description": f"Add a central {dominant_style} dining table.",
                "reason": "Dining spaces revolve around a table to enable shared dining.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Enables dining functionality.",
                "score_impact": "Functionality Score +35%",
                "action": {
                    "action_type": "add",
                    "category": "Kitchen",
                    "style": dominant_style,
                    "name": f"{dominant_style} Dining Table"
                }
            })
        elif not has_chair:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Add Dining Chairs",
                "description": "Add dining chairs around the table.",
                "reason": "A dining table requires chairs to be functional.",
                "rule_triggered": "Missing Furniture Rule",
                "expected_improvement": "Provides dining seating.",
                "score_impact": "Functionality Score +25%",
                "action": {
                    "action_type": "add",
                    "category": "Kitchen",
                    "style": dominant_style,
                    "name": f"{dominant_style} Dining Chair"
                }
            })

    # 5. Room Overcrowding/Density Check
    if utilization_ratio > 0.65 and len(furniture) > 1:
        # Find the largest non-essential item (exclude Bed, Sofa)
        largest_item = None
        max_area = 0.0
        for f in furniture:
            f_name = f.get('name', '').lower()
            if 'bed' in f_name or 'sofa' in f_name or 'couch' in f_name:
                continue
            area = f.get('width', 100.0) * f.get('depth', 100.0)
            if area > max_area:
                max_area = area
                largest_item = f
                
        if largest_item:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "AI",
                "title": "Downsize Room Furniture",
                "description": f"Remove the large {largest_item.get('name')} to clear floor space and improve circulation.",
                "reason": "The room is overcrowded, which restricts walkway clearance and layout flow.",
                "rule_triggered": "Room Density Rule",
                "expected_improvement": "Better circulation and spatial comfort.",
                "score_impact": "Space Utilization Score +15%",
                "action": {
                    "action_type": "remove",
                    "furniture_id": largest_item['id']
                }
            })

    # 6. Styling Theme & Material Check
    theme_colors = {
        "scandinavian": {"color": "#E6DFD3", "type": "wood"},
        "industrial": {"color": "#3E3D3D", "type": "metal"},
        "modern": {"color": "#C0C0C0", "type": "metal"},
        "rustic": {"color": "#A0522D", "type": "wood"},
        "minimalist": {"color": "#ECECEC", "type": "plastic"}
    }
    
    style_key = dominant_style.lower()
    theme = theme_colors.get(style_key, theme_colors["modern"])
    
    for f in furniture:
        if f.get('materialColor') is None or f.get('materialType') is None:
            rec_color = theme["color"]
            rec_type = theme["type"]
            
            # Smart overrides based on item name
            f_name = f.get('name', '').lower()
            if "chair" in f_name or "sofa" in f_name or "couch" in f_name:
                if style_key == "industrial":
                    rec_color = "#8B4513" # leather
                    rec_type = "leather"
                else:
                    rec_color = "#3B5998" # blue fabric
                    rec_type = "fabric"
                    
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "Analytics",
                "title": f"Apply Theme Material to {f.get('name')}",
                "description": f"Assign a {rec_type} texture with {rec_color} color to match the {dominant_style} room style.",
                "reason": "Furniture asset has no texture or material attributes applied.",
                "rule_triggered": "Material Suggestion Rule",
                "expected_improvement": "Enhanced visual aesthetics and style coherence.",
                "score_impact": "Aesthetics Score +8%",
                "action": {
                    "action_type": "material",
                    "furniture_id": f['id'],
                    "materialColor": rec_color,
                    "materialType": rec_type
                }
            })

    # Decor & Biophilia Suggestion
    has_decor = any(any(k in n for k in ['plant', 'decor', 'art', 'painting', 'mirror', 'rug']) for n in names)
    if not has_decor and furniture:
        recommendations.append({
            "id": str(uuid.uuid4()),
            "recommendation_type": "Analytics",
            "title": "Introduce Styling Decor",
            "description": f"Add a {dominant_style} house plant or art frame to introduce visual interest.",
            "reason": "Decor and biophilic elements create visual focus and improve room mood.",
            "rule_triggered": "Decor & Biophilia Rule",
            "expected_improvement": "Cohesive style finishing and enhanced aesthetics.",
            "score_impact": "Aesthetics Score +10%",
            "action": {
                "action_type": "add",
                "category": "Decor",
                "style": dominant_style,
                "name": f"{dominant_style} House Plant"
            }
        })

    # 7. Accessibility Suggestions
    grid = OccupancyGrid(room_width, room_length)
    for f in furniture:
        bbox = get_furniture_bbox(f)
        grid.mark_obstacle_rect(bbox['left'], bbox['right'], bbox['top'], bbox['bottom'])
        
    # 7.1 Turning Space Clearance check
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
            
    if not has_turning_space and furniture:
        # Find item closest to room center to shift away
        cx = room_width / 2.0
        cz = room_length / 2.0
        closest_to_center = None
        min_dist = float('inf')
        for f in furniture:
            dist = ((f.get('x', cx) - cx)**2 + (f.get('z', cz) - cz)**2)**0.5
            if dist < min_dist:
                min_dist = dist
                closest_to_center = f
                
        if closest_to_center:
            dx = closest_to_center['x'] - cx
            dz = closest_to_center['z'] - cz
            length = (dx**2 + dz**2)**0.5
            sh_x = (dx / length) * 50.0 if length > 0 else 50.0
            sh_z = (dz / length) * 50.0 if length > 0 else 0.0
            
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "Validation",
                "title": "Clear Wheelchair Turning Space",
                "description": f"Shift the {closest_to_center.get('name')} outwards by 50cm to clear a central wheelchair turning area.",
                "reason": "Accessibility standards require a continuous 150cm diameter turning circle free of obstacles.",
                "rule_triggered": "Turning Space Clearance Rule",
                "expected_improvement": "Enables wheelchair turning navigation compliance.",
                "score_impact": "Accessibility Score +25%",
                "action": {
                    "action_type": "move",
                    "furniture_id": closest_to_center['id'],
                    "dx": float(round(sh_x, 1)),
                    "dz": float(round(sh_z, 1)),
                    "rotationY": 0.0
                }
            })

    # 7.2 Walkway Accessibility (isolated items)
    if doors and furniture:
        start_cell = grid.to_cell(doors[0].get('x', 0.0), doors[0].get('y', 0.0))
        original_start_val = grid.grid[start_cell[0]][start_cell[1]]
        grid.grid[start_cell[0]][start_cell[1]] = 0
        reachable_cells = compute_reachability(grid, start_cell)
        grid.grid[start_cell[0]][start_cell[1]] = original_start_val
        
        blocked_items = []
        for f in furniture:
            bbox = get_furniture_bbox(f)
            adj_cells = []
            i_start, j_start = grid.to_cell(bbox['left'] - 10, bbox['top'] - 10)
            i_end, j_end = grid.to_cell(bbox['right'] + 10, bbox['bottom'] + 10)
            for i in range(i_start, i_end + 1):
                for j in range(j_start, j_end + 1):
                    if grid.is_valid_cell(i, j) and (i == i_start or i == i_end or j == j_start or j == j_end):
                        adj_cells.append((i, j))
            if not any(cell in reachable_cells for cell in adj_cells):
                blocked_items.append(f)
                
        for blocked in blocked_items:
            sc_x, sc_z = grid.to_coords(start_cell[0], start_cell[1])
            dx = sc_x - blocked['x']
            dz = sc_z - blocked['z']
            length = (dx**2 + dz**2)**0.5
            sh_x = (dx / length) * 40.0 if length > 0 else 40.0
            sh_z = (dz / length) * 40.0 if length > 0 else 0.0
            
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "Validation",
                "title": f"Reposition Blocked {blocked.get('name')}",
                "description": f"Move the {blocked.get('name')} closer to the door walkway by 40cm to restore access.",
                "reason": "This furniture is currently isolated and blocked by other assets.",
                "rule_triggered": "Walkway Accessibility Rule",
                "expected_improvement": "Restore reachability and access path for all furniture.",
                "score_impact": "Accessibility Score +20%",
                "action": {
                    "action_type": "move",
                    "furniture_id": blocked['id'],
                    "dx": float(round(sh_x, 1)),
                    "dz": float(round(sh_z, 1)),
                    "rotationY": 0.0
                }
            })

    # 7.3 Disconnected doors
    if len(doors) > 1:
        all_doors_connected = True
        for i in range(len(doors)):
            for j in range(i + 1, len(doors)):
                cell_a = grid.to_cell(doors[i].get('x', 0.0), doors[i].get('y', 0.0))
                cell_b = grid.to_cell(doors[j].get('x', 0.0), doors[j].get('y', 0.0))
                grid.grid[cell_a[0]][cell_a[1]] = 0
                grid.grid[cell_b[0]][cell_b[1]] = 0
                path = find_path_astar(grid, cell_a, cell_b)
                if path is None:
                    all_doors_connected = False
                    break
        if not all_doors_connected:
            recommendations.append({
                "id": str(uuid.uuid4()),
                "recommendation_type": "Validation",
                "title": "Clear Pathway between Entryways",
                "description": "Rearrange furniture to keep the walkway connecting room doorways clear.",
                "reason": "Furniture is obstructing the direct path between the room entryways.",
                "rule_triggered": "Door-to-Door Accessibility Rule",
                "expected_improvement": "Unimpeded transit routes through the room.",
                "score_impact": "Accessibility Score +25%",
                "action": {
                    "action_type": "none"
                }
            })

    # 8. Lighting Adequacy (fixtures check)
    has_light_fixture = any(any(k in n for k in ['lamp', 'light', 'fixture', 'lantern', 'pendant']) for n in names)
    if not has_light_fixture and furniture:
        recommendations.append({
            "id": str(uuid.uuid4()),
            "recommendation_type": "Lighting",
            "title": "Add Ambient Lighting",
            "description": f"Place a {dominant_style} floor lamp or ceiling light fixture in the room.",
            "reason": "Adequate illumination requires dedicated light fixtures for task and ambient use.",
            "rule_triggered": "Lighting Adequacy Rule",
            "expected_improvement": "Proper light coverage and visual comfort during evening hours.",
            "score_impact": "Lighting Score +20%",
            "action": {
                "action_type": "add",
                "category": "Lighting",
                "style": dominant_style,
                "name": f"{dominant_style} Floor Lamp"
            }
        })

    # Default fallback recommendation if none generated
    if not recommendations:
        recommendations.append({
            "id": str(uuid.uuid4()),
            "recommendation_type": "Analytics",
            "title": "Balance Furniture Distribution",
            "description": "Rearrange assets towards the center or empty corners.",
            "reason": "Ensure room weights are balanced to avoid clustering.",
            "rule_triggered": "Balance Scoring Rule",
            "expected_improvement": "Cohesive spacing and better circulation.",
            "score_impact": "Balance Score +5%",
            "action": {
                "action_type": "none"
            }
        })
        
    return recommendations
