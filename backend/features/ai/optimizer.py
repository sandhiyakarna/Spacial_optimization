import math
import random
import time
from typing import List, Dict, Any, Tuple, Optional
from features.ai.scoring import calculate_design_score
from features.ai.geometry import get_furniture_obb, obb_overlap_sat, OBB2D

def evaluate_cost_detailed(
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]]
) -> Tuple[float, float, Dict[str, Any]]:
    """
    Evaluates layout cost. Returns (hard_cost, total_cost, scores_dict).
    """
    scores = calculate_design_score(room_width, room_length, room_type, furniture, openings)
    
    overall = scores['overall_score']
    details = scores['details']
    subscores = scores['subscores']
    
    collisions = details.get('collisions', 0)
    out_of_bounds = details.get('out_of_bounds', 0)
    blocked_doors = details.get('blocked_doors', 0)
    blocked_windows = details.get('blocked_windows', 0)
    walkways_clear = details.get('walkways_clear', True)
    
    accessibility = subscores.get('accessibility', 100.0)
    lighting = subscores.get('lighting', 100.0)
    
    crit_errors = len(scores.get('critical_errors', []))
    
    # Hard cost represents safety and severe spatial constraints
    hard_cost = (
        crit_errors * 2000.0 +
        collisions * 1500.0 +
        out_of_bounds * 800.0 +
        blocked_doors * 800.0 +
        blocked_windows * 300.0 +
        (0.0 if walkways_clear else 800.0)
    )
    
    # Penalty for storage, kitchen, and bathroom fixtures floating away from walls
    storage_penalty = 0.0
    for f in furniture:
        f_name = f.get('name', '').lower()
        if any(k in f_name for k in ['bookshelf', 'cabinet', 'wardrobe', 'dresser', 'storage', 'counter', 'sink', 'stove', 'fridge', 'refrigerator', 'vanity']):
            w = f.get('width', 100.0)
            d = f.get('depth', 100.0)
            dist_to_wall = min(
                f.get('x', 0.0) - w / 2.0,
                room_width - (f.get('x', 0.0) + w / 2.0),
                f.get('z', 0.0) - d / 2.0,
                room_length - (f.get('z', 0.0) + d / 2.0)
            )
            if dist_to_wall > 35.0:
                storage_penalty += (dist_to_wall - 35.0) * 6.0

    # Total cost includes soft objectives
    total_cost = hard_cost + storage_penalty + (
        (100.0 - accessibility) * 20.0 +
        (100.0 - lighting) * 15.0 +
        (100.0 - overall) * 20.0
    )
    
    return hard_cost, total_cost, scores

def is_better_layout(scores_a: Dict[str, Any], scores_b: Dict[str, Any]) -> bool:
    """
    Returns True if layout A is strictly better than layout B based on priority:
    1. Zero critical errors (prohibited furniture, physical impossibilities)
    2. Zero hard collisions & boundary violations
    3. Zero door obstruction
    4. Clear walkways (walkway clearance passed)
    5. Better circulation (accessibility score)
    6. Better ergonomics
    7. Better overall score
    """
    crit_a = len(scores_a.get('critical_errors', []))
    crit_b = len(scores_b.get('critical_errors', []))
    if crit_a != crit_b:
        return crit_a < crit_b

    details_a = scores_a.get('details', {})
    details_b = scores_b.get('details', {})
    
    hard_a = details_a.get('collisions', 0) + details_a.get('out_of_bounds', 0)
    hard_b = details_b.get('collisions', 0) + details_b.get('out_of_bounds', 0)
    if hard_a != hard_b:
        return hard_a < hard_b
        
    doors_a = details_a.get('blocked_doors', 0)
    doors_b = details_b.get('blocked_doors', 0)
    if doors_a != doors_b:
        return doors_a < doors_b

    walk_a = details_a.get('walkways_clear', True)
    walk_b = details_b.get('walkways_clear', True)
    if walk_a != walk_b:
        return walk_a and not walk_b
        
    items_a = details_a.get('item_count', 0)
    items_b = details_b.get('item_count', 0)
    if hard_a == 0 and items_a != items_b:
        return items_a > items_b

    sub_a = scores_a.get('subscores', {})
    sub_b = scores_b.get('subscores', {})
    
    acc_a = sub_a.get('accessibility', 0.0)
    acc_b = sub_b.get('accessibility', 0.0)
    if abs(acc_a - acc_b) > 0.01:
        return acc_a > acc_b
        
    erg_a = sub_a.get('ergonomics', 0.0)
    erg_b = sub_b.get('ergonomics', 0.0)
    if abs(erg_a - erg_b) > 0.01:
        return erg_a > erg_b
        
    return scores_a.get('overall_score', 0.0) > scores_b.get('overall_score', 0.0)

def optimize_layout_simulated_annealing(
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]],
    max_iterations: int = 120,
    initial_temp: float = 100.0,
    cooling_rate: float = 0.92,
    steps_per_temp: int = 4,
    seed: Optional[int] = None,
    num_starts: int = 5,
    locked_ids: Optional[Any] = None
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """
    Refines layout placements using Simulated Annealing optimization with:
    - Functional Group Preservation (Desk + Manager Chair + Visitor Chairs moved as cohesive units)
    - Wall-alignment constraints for storage (cabinets, bookshelves, credenzas)
    - Absolute preservation of locked furniture items
    - Staged Phase 1 (Hard constraints) and Phase 2 (Soft objectives) searches
    - Local randomness seed for deterministic reproducibility
    - Geometry-aware mutation operators
    - Detailed performance reporting
    """
    start_time = time.time()
    
    if not furniture:
        return [], {}
        
    # Standardize locked items set
    active_locked_ids = set()
    if locked_ids:
        active_locked_ids.update(str(lid) for lid in locked_ids)
    for f in furniture:
        if f.get('is_locked') or f.get('isLocked'):
            if f.get('id'):
                active_locked_ids.add(str(f.get('id')))
        
    # Evaluate initial state
    init_hard, init_total, init_scores = evaluate_cost_detailed(
        room_width, room_length, room_type, furniture, openings
    )
    
    best_overall_state = [f.copy() for f in furniture]
    best_overall_scores = init_scores
    
    total_candidates_evaluated = 0
    total_iterations_run = 0

    def identify_clusters(items: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Identifies coupled furniture groups to maintain ergonomic relationships."""
        desk_idx = None
        manager_chair_idx = None
        visitor_chair_indices = []
        storage_indices = []
        bed_idx = None
        nightstand_indices = []
        dining_table_idx = None
        dining_chair_indices = []
        kitchen_indices = []
        
        for i, item in enumerate(items):
            name = item.get('name', '').lower()
            role = item.get('role', '').lower()
            cat = item.get('category', '').lower()
            
            if any(k in name for k in ['counter', 'sink', 'stove', 'fridge', 'refrigerator']) or 'kitchen' in cat or 'kitchen' in role:
                kitchen_indices.append(i)
            elif 'dining table' in name or ('table' in name and 'dining' in cat):
                if dining_table_idx is None:
                    dining_table_idx = i
            elif 'dining chair' in name or ('chair' in name and 'dining' in cat):
                dining_chair_indices.append(i)
            elif 'desk' in name or 'desk' in role:
                if desk_idx is None:
                    desk_idx = i
            elif 'manager' in name or 'exec' in name or role == 'manager_chair':
                if manager_chair_idx is None:
                    manager_chair_idx = i
            elif 'visitor' in name or 'guest' in name or role == 'visitor_chair':
                visitor_chair_indices.append(i)
            elif 'stand' in name or 'night' in name or role == 'bedside':
                nightstand_indices.append(i)
            elif 'bed' in name or role == 'primary_sleep':
                if bed_idx is None:
                    bed_idx = i
            elif any(k in name for k in ['cabinet', 'shelf', 'book', 'wardrobe', 'storage', 'credenza', 'vanity']):
                storage_indices.append(i)
                
        # If manager chair wasn't identified by name/role, check closest chair behind/near desk
        if desk_idx is not None and manager_chair_idx is None:
            desk = items[desk_idx]
            chairs = [
                i for i, it in enumerate(items) 
                if i != desk_idx and i not in visitor_chair_indices and i not in dining_chair_indices and ('chair' in it.get('name', '').lower() or 'seating' in it.get('category', '').lower())
            ]
            if chairs:
                manager_chair_idx = chairs[0]
                
        return {
            "desk_idx": desk_idx,
            "manager_chair_idx": manager_chair_idx,
            "visitor_chair_indices": visitor_chair_indices,
            "storage_indices": storage_indices,
            "bed_idx": bed_idx,
            "nightstand_indices": nightstand_indices,
            "dining_table_idx": dining_table_idx,
            "dining_chair_indices": dining_chair_indices,
            "kitchen_indices": kitchen_indices
        }

    # Loop over multiple start candidates
    for run in range(num_starts):
        run_seed = None if seed is None else (seed + run)
        local_random = random.Random(run_seed)
        
        if run == 0:
            current_state = [f.copy() for f in furniture]
        else:
            current_state = [f.copy() for f in furniture]
            clusters = identify_clusters(current_state)
            desk_idx = clusters["desk_idx"]
            bed_idx = clusters["bed_idx"]
            
            locked_indices = {i for i, it in enumerate(current_state) if str(it.get('id', '')) in active_locked_ids or it.get('is_locked') or it.get('isLocked')}
            
            # 1. Perturb Bed + Nightstands as a coupled unit
            if bed_idx is not None and bed_idx not in locked_indices:
                bed = current_state[bed_idx]
                b_w = bed.get('width', 200.0)
                b_d = bed.get('depth', 220.0)
                
                bed_walls = [0.0, math.pi / 2.0, math.pi, 3.0 * math.pi / 2.0]
                new_b_rot = local_random.choice(bed_walls)
                
                # Position headboard against selected wall
                padding = 15.0
                if abs(new_b_rot) < 0.1: # North wall
                    new_bx = local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_width - b_w / 2.0 - 60.0))
                    new_bz = b_d / 2.0 + padding
                elif abs(new_b_rot - math.pi) < 0.1: # South wall
                    new_bx = local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_width - b_w / 2.0 - 60.0))
                    new_bz = room_length - b_d / 2.0 - padding
                elif abs(new_b_rot - math.pi / 2.0) < 0.1: # West wall
                    new_bx = b_d / 2.0 + padding
                    new_bz = local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_length - b_w / 2.0 - 60.0))
                else: # East wall
                    new_bx = room_width - b_d / 2.0 - padding
                    new_bz = local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_length - b_w / 2.0 - 60.0))
                    
                bed['x'] = float(round(new_bx, 1))
                bed['z'] = float(round(new_bz, 1))
                bed['rotationY'] = float(round(new_b_rot, 4))
                
                # Position nightstands flanking the headboard
                for i, ns_idx in enumerate(clusters["nightstand_indices"][:2]):
                    if ns_idx in locked_indices:
                        continue
                    ns = current_state[ns_idx]
                    ns_w = ns.get('width', 50.0)
                    sign = -1.0 if i == 0 else 1.0
                    lat_dist = (b_w / 2.0 + ns_w / 2.0 + 10.0) * sign
                    
                    if abs(new_b_rot) < 0.1 or abs(new_b_rot - math.pi) < 0.1:
                        ns['x'] = float(round(new_bx + lat_dist, 1))
                        ns['z'] = float(round(new_bz, 1))
                    else:
                        ns['x'] = float(round(new_bx, 1))
                        ns['z'] = float(round(new_bz + lat_dist, 1))
                    ns['rotationY'] = float(round(new_b_rot, 4))

            # 2. Perturb Desk + Chairs as a coupled unit
            if desk_idx is not None and desk_idx not in locked_indices:
                desk = current_state[desk_idx]
                d_w = desk.get('width', 140.0)
                d_d = desk.get('depth', 70.0)
                
                orientations = [0.0, math.pi / 2.0, math.pi, 3.0 * math.pi / 2.0]
                new_rot = local_random.choice(orientations)
                
                margin = 90.0
                new_dx = local_random.uniform(margin, max(margin, room_width - margin))
                new_dz = local_random.uniform(margin, max(margin, room_length - margin))
                
                desk['x'] = float(round(new_dx, 1))
                desk['z'] = float(round(new_dz, 1))
                desk['rotationY'] = float(round(new_rot, 4))
                
                mc_idx = clusters["manager_chair_idx"]
                if mc_idx is not None and mc_idx not in locked_indices:
                    mc = current_state[mc_idx]
                    mc_dist = d_d / 2.0 + mc.get('depth', 60.0) / 2.0 + 35.0
                    mc['x'] = float(round(new_dx - mc_dist * math.sin(new_rot), 1))
                    mc['z'] = float(round(new_dz + mc_dist * math.cos(new_rot), 1))
                    mc['rotationY'] = float(round(new_rot, 4))
                    
                vc_indices = clusters["visitor_chair_indices"]
                if vc_indices:
                    v_dist = d_d / 2.0 + 30.0 + 35.0
                    v_rot = (new_rot + math.pi) % (2.0 * math.pi)
                    v_spacing = min(60.0, max(42.0, d_w * 0.28))
                    for i, vc_idx in enumerate(vc_indices[:2]):
                        if vc_idx in locked_indices:
                            continue
                        vc = current_state[vc_idx]
                        sign = -1.0 if i == 0 else 1.0
                        lat_x = sign * v_spacing * math.cos(new_rot)
                        lat_z = sign * v_spacing * math.sin(new_rot)
                        vc['x'] = float(round(new_dx + v_dist * math.sin(new_rot) + lat_x, 1))
                        vc['z'] = float(round(new_dz - v_dist * math.cos(new_rot) + lat_z, 1))
                        vc['rotationY'] = float(round(v_rot, 4))
                        
            # 3. Place storage items flush along walls
            for st_idx in clusters["storage_indices"]:
                if st_idx in locked_indices:
                    continue
                st = current_state[st_idx]
                st_w = st.get('width', 100.0)
                st_d = st.get('depth', 50.0)
                wall_choice = local_random.choice(['west', 'east', 'south', 'north'])
                padding = 5.0
                effective_d = st_d if st_w > st_d else st_w
                
                if wall_choice == 'west':
                    st['x'] = float(round(effective_d / 2.0 + padding, 1))
                    st['z'] = float(round(local_random.uniform(effective_d + 20.0, room_length - effective_d - 20.0), 1))
                    st['rotationY'] = float(round(math.pi / 2.0, 4))
                elif wall_choice == 'east':
                    st['x'] = float(round(room_width - effective_d / 2.0 - padding, 1))
                    st['z'] = float(round(local_random.uniform(effective_d + 20.0, room_length - effective_d - 20.0), 1))
                    st['rotationY'] = float(round(3.0 * math.pi / 2.0, 4))
                elif wall_choice == 'south':
                    st['z'] = float(round(room_length - effective_d / 2.0 - padding, 1))
                    st['x'] = float(round(local_random.uniform(effective_d + 20.0, room_width - effective_d - 20.0), 1))
                    st['rotationY'] = float(round(math.pi, 4))
                else:
                    st['z'] = float(round(effective_d / 2.0 + padding, 1))
                    st['x'] = float(round(local_random.uniform(effective_d + 20.0, room_width - effective_d - 20.0), 1))
                    st['rotationY'] = 0.0
                    
            # 4. Perturb all other unassigned items
            assigned_indices = set(clusters["storage_indices"] + clusters["nightstand_indices"])
            if bed_idx is not None:
                assigned_indices.add(bed_idx)
            if desk_idx is not None:
                assigned_indices.add(desk_idx)
                if clusters["manager_chair_idx"] is not None:
                    assigned_indices.add(clusters["manager_chair_idx"])
                for vc in clusters["visitor_chair_indices"]:
                    assigned_indices.add(vc)
                    
            for other_idx in range(len(current_state)):
                if other_idx not in assigned_indices and other_idx not in locked_indices:
                    f_other = current_state[other_idx]
                    ow = f_other.get('width', 100.0)
                    od = f_other.get('depth', 100.0)
                    f_other['x'] = float(round(local_random.uniform(ow / 2.0 + 15.0, max(ow / 2.0 + 15.0, room_width - ow / 2.0 - 15.0)), 1))
                    f_other['z'] = float(round(local_random.uniform(od / 2.0 + 15.0, max(od / 2.0 + 15.0, room_length - od / 2.0 - 15.0)), 1))
                    f_other['rotationY'] = float(round(local_random.choice([0.0, math.pi / 2.0, math.pi, 3.0 * math.pi / 2.0]), 4))
                
        # Re-sync bounding boxes
        for f in current_state:
            f['rotation'] = f.get('rotationY', 0.0)
            f['bounding_box'] = {
                "center": [f['x'], f['z']],
                "width": f.get('width', 100.0),
                "depth": f.get('depth', 100.0),
                "rotation": f.get('rotationY', 0.0)
            }
            
        current_hard, current_total, current_scores = evaluate_cost_detailed(
            room_width, room_length, room_type, current_state, openings
        )
        
        best_run_state = [f.copy() for f in current_state]
        best_run_scores = current_scores
        best_run_hard = current_hard
        best_run_total = current_total
        
        temp = initial_temp
        phase = 1 if current_hard > 0 else 2
        
        for iteration in range(max_iterations):
            total_iterations_run += 1
            if temp < 0.1:
                break
                
            for _ in range(steps_per_temp):
                total_candidates_evaluated += 1
                candidate_state = [f.copy() for f in current_state]
                clusters = identify_clusters(candidate_state)
                
                # Exclude locked items from mutation selection
                locked_indices = {i for i, it in enumerate(candidate_state) if str(it.get('id', '')) in active_locked_ids or it.get('is_locked') or it.get('isLocked')}
                mutable_indices = [i for i in range(len(candidate_state)) if i not in locked_indices]
                if not mutable_indices:
                    break
                    
                idx = local_random.choice(mutable_indices)
                target = candidate_state[idx]
                w = target.get('width', 100.0)
                d = target.get('depth', 100.0)
                
                desk_idx = clusters["desk_idx"]
                bed_idx = clusters.get("bed_idx")
                is_workspace_item = (desk_idx is not None and (idx == desk_idx or idx == clusters["manager_chair_idx"] or idx in clusters["visitor_chair_indices"]))
                is_sleep_item = (bed_idx is not None and (idx == bed_idx or idx in clusters.get("nightstand_indices", [])))
                is_storage_item = (idx in clusters["storage_indices"])
                
                if is_sleep_item and local_random.random() < 0.85:
                    # Cohesive sleep cluster mutation
                    bed = candidate_state[bed_idx]
                    b_w = bed.get('width', 200.0)
                    b_d = bed.get('depth', 220.0)
                    
                    sleep_mutation = local_random.choice(['slide_wall', 'switch_wall'])
                    if sleep_mutation == 'slide_wall':
                        curr_rot = bed.get('rotationY', 0.0)
                        if abs(curr_rot - math.pi / 2.0) < 0.2 or abs(curr_rot - 3.0 * math.pi / 2.0) < 0.2:
                            # East or West wall -> slide along Z
                            shift_z = local_random.uniform(-40.0, 40.0)
                            bed['z'] = float(round(max(b_w / 2.0 + 60.0, min(room_length - b_w / 2.0 - 60.0, bed['z'] + shift_z)), 1))
                        else:
                            # North or South wall -> slide along X
                            shift_x = local_random.uniform(-40.0, 40.0)
                            bed['x'] = float(round(max(b_w / 2.0 + 60.0, min(room_width - b_w / 2.0 - 60.0, bed['x'] + shift_x)), 1))
                    elif sleep_mutation == 'switch_wall':
                        bed_walls = [0.0, math.pi / 2.0, math.pi, 3.0 * math.pi / 2.0]
                        new_b_rot = local_random.choice(bed_walls)
                        padding = 15.0
                        if abs(new_b_rot) < 0.1: # North
                            bed['x'] = float(round(local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_width - b_w / 2.0 - 60.0)), 1))
                            bed['z'] = float(round(b_d / 2.0 + padding, 1))
                        elif abs(new_b_rot - math.pi) < 0.1: # South
                            bed['x'] = float(round(local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_width - b_w / 2.0 - 60.0)), 1))
                            bed['z'] = float(round(room_length - b_d / 2.0 - padding, 1))
                        elif abs(new_b_rot - math.pi / 2.0) < 0.1: # West
                            bed['x'] = float(round(b_d / 2.0 + padding, 1))
                            bed['z'] = float(round(local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_length - b_w / 2.0 - 60.0)), 1))
                        else: # East
                            bed['x'] = float(round(room_width - b_d / 2.0 - padding, 1))
                            bed['z'] = float(round(local_random.uniform(b_w / 2.0 + 60.0, max(b_w / 2.0 + 60.0, room_length - b_w / 2.0 - 60.0)), 1))
                        bed['rotationY'] = float(round(new_b_rot, 4))
                        
                    # Re-align nightstands flanking the headboard
                    b_rot = bed.get('rotationY', 0.0)
                    for i, ns_idx in enumerate(clusters.get("nightstand_indices", [])[:2]):
                        ns = candidate_state[ns_idx]
                        ns_w = ns.get('width', 50.0)
                        sign = -1.0 if i == 0 else 1.0
                        lat_dist = (b_w / 2.0 + ns_w / 2.0 + 10.0) * sign
                        if abs(b_rot) < 0.1 or abs(b_rot - math.pi) < 0.1:
                            ns['x'] = float(round(bed['x'] + lat_dist, 1))
                            ns['z'] = float(round(bed['z'], 1))
                        else:
                            ns['x'] = float(round(bed['x'], 1))
                            ns['z'] = float(round(bed['z'] + lat_dist, 1))
                        ns['rotationY'] = float(round(b_rot, 4))
                elif is_workspace_item and local_random.random() < 0.75:
                    # Cohesive workspace cluster mutation
                    desk = candidate_state[desk_idx]
                    d_w = desk.get('width', 140.0)
                    d_d = desk.get('depth', 70.0)
                    drot = desk.get('rotationY', 0.0)
                    
                    mutation_type = local_random.choice(['shift_cluster', 'shift_cluster', 'rotate_cluster'])
                    if mutation_type == 'shift_cluster':
                        shift_dx = local_random.uniform(-30.0, 30.0)
                        shift_dz = local_random.uniform(-30.0, 30.0)
                        
                        target_dx = max(80.0, min(room_width - 80.0, desk['x'] + shift_dx))
                        target_dz = max(80.0, min(room_length - 80.0, desk['z'] + shift_dz))
                        actual_dx = target_dx - desk['x']
                        actual_dz = target_dz - desk['z']
                        
                        desk['x'] = float(round(target_dx, 1))
                        desk['z'] = float(round(target_dz, 1))
                        
                        mc_idx = clusters["manager_chair_idx"]
                        if mc_idx is not None:
                            candidate_state[mc_idx]['x'] = float(round(candidate_state[mc_idx]['x'] + actual_dx, 1))
                            candidate_state[mc_idx]['z'] = float(round(candidate_state[mc_idx]['z'] + actual_dz, 1))
                            
                        for vc_idx in clusters["visitor_chair_indices"]:
                            candidate_state[vc_idx]['x'] = float(round(candidate_state[vc_idx]['x'] + actual_dx, 1))
                            candidate_state[vc_idx]['z'] = float(round(candidate_state[vc_idx]['z'] + actual_dz, 1))
                            
                    elif mutation_type == 'rotate_cluster':
                        new_rot = local_random.choice([0.0, math.pi / 2.0, math.pi, 3.0 * math.pi / 2.0])
                        desk['rotationY'] = float(round(new_rot, 4))
                        
                        mc_idx = clusters["manager_chair_idx"]
                        if mc_idx is not None:
                            mc = candidate_state[mc_idx]
                            mc_dist = d_d / 2.0 + mc.get('depth', 60.0) / 2.0 + 35.0
                            mc['x'] = float(round(desk['x'] - mc_dist * math.sin(new_rot), 1))
                            mc['z'] = float(round(desk['z'] + mc_dist * math.cos(new_rot), 1))
                            mc['rotationY'] = float(round(new_rot, 4))
                            
                        vc_indices = clusters["visitor_chair_indices"]
                        if vc_indices:
                            v_dist = d_d / 2.0 + 30.0 + 35.0
                            v_rot = (new_rot + math.pi) % (2.0 * math.pi)
                            v_spacing = min(60.0, max(42.0, d_w * 0.28))
                            for i, vc_idx in enumerate(vc_indices[:2]):
                                vc = candidate_state[vc_idx]
                                sign = -1.0 if i == 0 else 1.0
                                lat_x = sign * v_spacing * math.cos(new_rot)
                                lat_z = sign * v_spacing * math.sin(new_rot)
                                vc['x'] = float(round(desk['x'] + v_dist * math.sin(new_rot) + lat_x, 1))
                                vc['z'] = float(round(desk['z'] - v_dist * math.cos(new_rot) + lat_z, 1))
                                vc['rotationY'] = float(round(v_rot, 4))
                                
                elif is_storage_item:
                    # Storage stays flush against walls
                    st_w = target.get('width', 100.0)
                    st_d = target.get('depth', 50.0)
                    effective_d = st_d if st_w > st_d else st_w
                    padding = 5.0
                    
                    st_mutation = local_random.choice(['slide_wall', 'switch_wall', 'avoid_door'])
                    if st_mutation == 'slide_wall':
                        # Slide along current wall
                        curr_rot = target.get('rotationY', 0.0)
                        if abs(curr_rot - math.pi / 2.0) < 0.2 or abs(curr_rot - 3.0 * math.pi / 2.0) < 0.2:
                            # East or West wall -> slide along Z
                            shift_z = local_random.uniform(-40.0, 40.0)
                            target['z'] = float(round(max(st_w / 2.0 + 10.0, min(room_length - st_w / 2.0 - 10.0, target['z'] + shift_z)), 1))
                        else:
                            # North or South wall -> slide along X
                            shift_x = local_random.uniform(-40.0, 40.0)
                            target['x'] = float(round(max(st_w / 2.0 + 10.0, min(room_width - st_w / 2.0 - 10.0, target['x'] + shift_x)), 1))
                    elif st_mutation == 'switch_wall':
                        wall_choice = local_random.choice(['west', 'east', 'south', 'north'])
                        if wall_choice == 'west':
                            target['x'] = float(round(effective_d / 2.0 + padding, 1))
                            target['z'] = float(round(local_random.uniform(st_w / 2.0 + 20.0, room_length - st_w / 2.0 - 20.0), 1))
                            target['rotationY'] = float(round(math.pi / 2.0, 4))
                        elif wall_choice == 'east':
                            target['x'] = float(round(room_width - effective_d / 2.0 - padding, 1))
                            target['z'] = float(round(local_random.uniform(st_w / 2.0 + 20.0, room_length - st_w / 2.0 - 20.0), 1))
                            target['rotationY'] = float(round(3.0 * math.pi / 2.0, 4))
                        elif wall_choice == 'south':
                            target['z'] = float(round(room_length - effective_d / 2.0 - padding, 1))
                            target['x'] = float(round(local_random.uniform(st_w / 2.0 + 20.0, room_width - st_w / 2.0 - 20.0), 1))
                            target['rotationY'] = float(round(math.pi, 4))
                        else:
                            target['z'] = float(round(effective_d / 2.0 + padding, 1))
                            target['x'] = float(round(local_random.uniform(st_w / 2.0 + 20.0, room_width - st_w / 2.0 - 20.0), 1))
                            target['rotationY'] = 0.0
                    elif st_mutation == 'avoid_door':
                        doors = [op for op in openings if op.get('type') == 'door']
                        if doors:
                            d_item = doors[0]
                            d_x, d_z = d_item.get('x', 0.0), d_item.get('y', 0.0)
                            if target['z'] < room_length / 2.0:
                                target['z'] = float(round(room_length * 0.75, 1))
                            else:
                                target['z'] = float(round(room_length * 0.25, 1))
                else:
                    # General item mutation
                    mutation = local_random.choice([
                        'move_random', 'move_toward_wall', 'rotate_cardinal', 'snap_to_closest_wall', 'increase_clearance'
                    ])
                    if mutation == 'move_random':
                        dx = local_random.uniform(-40.0, 40.0)
                        dz = local_random.uniform(-40.0, 40.0)
                        target['x'] = float(round(max(w/2.0 + 5.0, min(room_width - w/2.0 - 5.0, target['x'] + dx)), 1))
                        target['z'] = float(round(max(d/2.0 + 5.0, min(room_length - d/2.0 - 5.0, target['z'] + dz)), 1))
                    elif mutation == 'increase_clearance':
                        other_items = [f for f in candidate_state if f['id'] != target['id']]
                        if other_items:
                            closest_item = min(other_items, key=lambda f: math.sqrt((target['x'] - f['x'])**2 + (target['z'] - f['z'])**2))
                            dx = target['x'] - closest_item['x']
                            dz = target['z'] - closest_item['z']
                            dist = math.sqrt(dx**2 + dz**2)
                            if dist > 0:
                                target['x'] = float(round(max(w/2.0 + 5.0, min(room_width - w/2.0 - 5.0, target['x'] + (dx / dist) * 60.0)), 1))
                                target['z'] = float(round(max(d/2.0 + 5.0, min(room_length - d/2.0 - 5.0, target['z'] + (dz / dist) * 60.0)), 1))
                    elif mutation == 'rotate_cardinal':
                        target['rotationY'] = float(round(local_random.choice([0.0, math.pi / 2.0, math.pi, 1.5 * math.pi]), 4))
                    elif mutation == 'snap_to_closest_wall':
                        dist_to_north = target['z']
                        dist_to_south = room_length - target['z']
                        dist_to_west = target['x']
                        dist_to_east = room_width - target['x']
                        min_dist = min(dist_to_north, dist_to_south, dist_to_west, dist_to_east)
                        padding = 5.0
                        if min_dist == dist_to_north:
                            target['rotationY'] = 0.0
                            target['z'] = float(round(d / 2.0 + padding, 1))
                        elif min_dist == dist_to_south:
                            target['rotationY'] = float(round(math.pi, 4))
                            target['z'] = float(round(room_length - d / 2.0 - padding, 1))
                        elif min_dist == dist_to_west:
                            target['rotationY'] = float(round(math.pi / 2.0, 4))
                            target['x'] = float(round(w / 2.0 + padding, 1))
                        else:
                            target['rotationY'] = float(round(1.5 * math.pi, 4))
                            target['x'] = float(round(room_width - w / 2.0 - padding, 1))
                
                # Re-sync bounding boxes
                for f in candidate_state:
                    f['rotation'] = f.get('rotationY', 0.0)
                    f['bounding_box'] = {
                        "center": [f['x'], f['z']],
                        "width": f.get('width', 100.0),
                        "depth": f.get('depth', 100.0),
                        "rotation": f.get('rotationY', 0.0)
                    }

                candidate_hard, candidate_total, candidate_scores = evaluate_cost_detailed(
                    room_width, room_length, room_type, candidate_state, openings
                )
                
                # Staged optimization decision
                if phase == 1:
                    delta = candidate_hard - current_hard
                    if delta < 0:
                        current_state = candidate_state
                        current_hard = candidate_hard
                        current_total = candidate_total
                        current_scores = candidate_scores
                        if candidate_hard < best_run_hard:
                            best_run_state = [f.copy() for f in candidate_state]
                            best_run_hard = candidate_hard
                            best_run_total = candidate_total
                            best_run_scores = candidate_scores
                    else:
                        p = math.exp(-delta / temp)
                        if local_random.random() < p:
                            current_state = candidate_state
                            current_hard = candidate_hard
                            current_total = candidate_total
                            current_scores = candidate_scores
                            
                    if current_hard == 0:
                        phase = 2
                        
                else:
                    if candidate_hard > 0:
                        continue
                        
                    delta = candidate_total - current_total
                    if delta < 0:
                        current_state = candidate_state
                        current_hard = candidate_hard
                        current_total = candidate_total
                        current_scores = candidate_scores
                        if candidate_total < best_run_total:
                            best_run_state = [f.copy() for f in candidate_state]
                            best_run_hard = candidate_hard
                            best_run_total = candidate_total
                            best_run_scores = candidate_scores
                    else:
                        p = math.exp(-delta / temp)
                        if local_random.random() < p:
                            current_state = candidate_state
                            current_hard = candidate_hard
                            current_total = candidate_total
                            current_scores = candidate_scores
                            
            temp *= cooling_rate
            
        if is_better_layout(best_run_scores, best_overall_scores):
            best_overall_state = [f.copy() for f in best_run_state]
            best_overall_scores = best_run_scores
            
        final_details = best_overall_scores.get('details', {})
        final_hard = final_details.get('collisions', 0) + final_details.get('out_of_bounds', 0) + final_details.get('blocked_doors', 0)
        if final_hard == 0 and best_overall_scores.get('overall_score', 0.0) >= 88.0:
            break
            
    final_scores = calculate_design_score(room_width, room_length, room_type, best_overall_state, openings)
    runtime_ms = int((time.time() - start_time) * 1000)
    
    report = {
        "initial": {
            "collision_violations": int(init_scores['details'].get('collisions', 0)),
            "wall_violations": int(init_scores['details'].get('out_of_bounds', 0)),
            "door_violations": int(init_scores['details'].get('blocked_doors', 0)),
            "walkway_score": float(init_scores['subscores'].get('accessibility', 0.0)),
            "ergonomic_score": float(init_scores['subscores'].get('ergonomics', 0.0)),
            "utilization_score": float(init_scores['subscores'].get('space_utilization', 0.0)),
            "overall_score": float(init_scores['overall_score'])
        },
        "final": {
            "collision_violations": int(final_scores['details'].get('collisions', 0)),
            "wall_violations": int(final_scores['details'].get('out_of_bounds', 0)),
            "door_violations": int(final_scores['details'].get('blocked_doors', 0)),
            "walkway_score": float(final_scores['subscores'].get('accessibility', 0.0)),
            "ergonomic_score": float(final_scores['subscores'].get('ergonomics', 0.0)),
            "utilization_score": float(final_scores['subscores'].get('space_utilization', 0.0)),
            "overall_score": float(final_scores['overall_score'])
        },
        "iterations": int(total_iterations_run),
        "runtime": int(runtime_ms),
        "number_of_candidates": int(total_candidates_evaluated),
        "optimization_seed": seed
    }
    
    return best_overall_state, report

