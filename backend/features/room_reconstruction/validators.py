import math
from typing import List, Dict, Any, Tuple
from features.room_reconstruction.spatial_model import RoomSpatialModel
from features.ai.geometry import OBB2D, obb_overlap_sat

def validate_walls_closed(model: RoomSpatialModel) -> Tuple[bool, str]:
    """
    Verifies that the walls form a closed polygon/geometry.
    """
    if not model.walls:
        return False, "No walls defined in spatial model."
    
    # Standard check: count starts and ends matching
    # Build adjacency list of endpoints within a tolerance of 5cm
    tolerance = 5.0
    endpoints = []
    for w in model.walls:
        endpoints.append(tuple(w.start))
        endpoints.append(tuple(w.end))

    # Match endpoints
    for pt in endpoints:
        matches = 0
        for w in model.walls:
            d_start = math.sqrt((pt[0] - w.start[0])**2 + (pt[1] - w.start[1])**2)
            d_end = math.sqrt((pt[0] - w.end[0])**2 + (pt[1] - w.end[1])**2)
            if d_start < tolerance:
                matches += 1
            if d_end < tolerance:
                matches += 1
        
        if matches < 2:
            return False, f"Room boundary is open near corner {pt}. Every wall intersection must have at least 2 meeting walls."
            
    return True, "Walls form a closed geometry."


def validate_openings_on_walls(model: RoomSpatialModel) -> Tuple[bool, str]:
    """
    Checks that every door/window lies on a valid wall in the model.
    """
    wall_ids = {w.id for w in model.walls}
    
    for d in model.doors:
        if d.wall_id not in wall_ids:
            return False, f"Door '{d.id}' is associated with non-existent wall '{d.wall_id}'."
        if d.position_cm < 0:
            return False, f"Door '{d.id}' has invalid negative position {d.position_cm}."
            
    for win in model.windows:
        if win.wall_id not in wall_ids:
            return False, f"Window '{win.id}' is associated with non-existent wall '{win.wall_id}'."
        if win.position_cm < 0:
            return False, f"Window '{win.id}' has invalid negative position {win.position_cm}."
            
    return True, "All doors and windows lie on walls."


def validate_furniture_in_bounds(model: RoomSpatialModel) -> Tuple[bool, str]:
    """
    Ensures that all furniture coordinates are positive and lie inside the room dimensions.
    """
    w_limit = model.dimensions.width_cm
    d_limit = model.dimensions.depth_cm

    for f in model.furniture:
        # Check coordinates positive
        if f.position.x_cm < 0 or f.position.y_cm < 0:
            return False, f"Furniture '{f.name}' has invalid negative coordinates ({f.position.x_cm}, {f.position.y_cm})."
        
        # Simple bounding box containment check
        rot_rad = f.rotation_deg * math.pi / 180.0
        cos_r = abs(math.cos(rot_rad))
        sin_r = abs(math.sin(rot_rad))
        proj_w = f.dimensions.width_cm * cos_r + f.dimensions.depth_cm * sin_r
        proj_d = f.dimensions.width_cm * sin_r + f.dimensions.depth_cm * cos_r
        
        left = f.position.x_cm - proj_w / 2.0
        right = f.position.x_cm + proj_w / 2.0
        top = f.position.y_cm - proj_d / 2.0
        bottom = f.position.y_cm + proj_d / 2.0

        if left < -10.0 or right > w_limit + 10.0 or top < -10.0 or bottom > d_limit + 10.0:
            return False, f"Furniture '{f.name}' lies outside room boundaries ({w_limit} x {d_limit})."
            
    return True, "All furniture lies within room bounds."


def validate_no_collisions(model: RoomSpatialModel) -> Tuple[bool, str]:
    """
    Uses the SAT OBB collision engine to check if any furniture objects overlap,
    or collide with doors and windows.
    """
    # 1. Convert model furniture to OBB2D list
    obbs = []
    for f in model.furniture:
        rot_rad = f.rotation_deg * math.pi / 180.0
        obb = OBB2D(
            cx=f.position.x_cm,
            cz=f.position.y_cm,
            width=f.dimensions.width_cm,
            depth=f.dimensions.depth_cm,
            rotation=rot_rad
        )
        obbs.append((f, obb))

    # 2. Check furniture-furniture collisions
    for i in range(len(obbs)):
        f1, obb1 = obbs[i]
        for j in range(i + 1, len(obbs)):
            f2, obb2 = obbs[j]
            overlap, _, _ = obb_overlap_sat(obb1, obb2)
            if overlap:
                return False, f"Collision detected between '{f1.name}' and '{f2.name}'."

    # 3. Check collision with doors (using door swing clearance area)
    # Map wall orientation to compute door projection in 2D space
    wall_map = {w.id: w for w in model.walls}
    for d in model.doors:
        if d.wall_id not in wall_map:
            continue
        w = wall_map[d.wall_id]
        ax, ay = w.start
        bx, by = w.end
        w_len = w.length_cm
        t = d.position_cm / w_len if w_len > 0 else 0.0
        door_x = ax + t * (bx - ax)
        door_y = ay + t * (by - ay)
        
        # Build OBB for door swing area
        door_obb = OBB2D(
            cx=door_x,
            cz=door_y,
            width=d.width_cm,
            depth=d.width_cm,
            rotation=math.atan2(by - ay, bx - ax)
        )
        
        for f, f_obb in obbs:
            overlap, _, _ = obb_overlap_sat(door_obb, f_obb)
            if overlap:
                return False, f"Furniture '{f.name}' overlaps with door '{d.id}' swing clearance area."

    return True, "No spatial collisions detected."


def validate_spatial_model(model: RoomSpatialModel) -> Dict[str, Any]:
    """
    Full validation report of the RoomSpatialModel.
    """
    validations = [
        validate_walls_closed,
        validate_openings_on_walls,
        validate_furniture_in_bounds,
        validate_no_collisions
    ]
    
    errors = []
    for validate_fn in validations:
        success, message = validate_fn(model)
        if not success:
            errors.append(message)
            
    return {
        "valid": len(errors) == 0,
        "errors": errors
    }
