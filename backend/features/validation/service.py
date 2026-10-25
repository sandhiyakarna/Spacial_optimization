import json
import math
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any, Tuple
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from features.room.models import Room
from features.ai.models import ValidationRule, ValidationResult, ValidationChecklist, Analytics
from features.ai.geometry import (
    get_furniture_bbox, OccupancyGrid, compute_reachability, find_path_astar,
    get_furniture_obb, obb_overlap_sat, closest_point_on_obb, mark_obstacle_obb, OBB2D,
    obb_distance, get_door_swing_geometry, get_furniture_clearance_obb,
    check_furniture_metadata, point_segment_distance
)
from features.validation.schemas import ValidationIssue, ValidationRunResponseData

class ValidationService:
    @staticmethod
    def seed_default_rules(db: Session):
        """
        Seeds the standard validation rules if they don't already exist in the database.
        """
        default_rules = [
            ValidationRule(
                id="RULE_ROOM_COMPATIBILITY",
                rule_name="Room Furniture Compatibility",
                category="Furniture",
                minimum_value=0.0,
                maximum_value=0.0,
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_COLLISION",
                rule_name="Collision Detection",
                category="Furniture",
                minimum_value=0.0,
                maximum_value=0.0,
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_WALL",
                rule_name="Wall Collision",
                category="Safety",
                minimum_value=0.0,
                maximum_value=0.0,
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_DOOR",
                rule_name="Door Clearance",
                category="Accessibility",
                minimum_value=80.0, # standard door width clearance in cm
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_WINDOW",
                rule_name="Window Clearance",
                category="Accessibility",
                minimum_value=50.0, # min offset in cm
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_WALKWAY",
                rule_name="Walkway Width Validation",
                category="Circulation",
                minimum_value=75.0, # min walkway width in cm
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_ACCESSIBILITY",
                rule_name="Accessibility Validation",
                category="Accessibility",
                minimum_value=70.0, # min reachable area percentage
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_TV_DIST",
                rule_name="TV Viewing Distance",
                category="Ergonomics",
                minimum_value=150.0,
                maximum_value=300.0,
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_BED_CLR",
                rule_name="Bed Clearance",
                category="Ergonomics",
                minimum_value=60.0, # min clearance in cm
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_DINING_CLR",
                rule_name="Dining Chair Spacing",
                category="Ergonomics",
                minimum_value=50.0,
                severity="Info",
                enabled=True
            ),
            ValidationRule(
                id="RULE_DESK_ERGO",
                rule_name="Desk Ergonomics",
                category="Ergonomics",
                minimum_value=80.0, # min pull-out space behind chair
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_KITCHEN_TRI",
                rule_name="Kitchen Triangle Validation",
                category="Ergonomics",
                severity="Info",
                enabled=True
            ),
            ValidationRule(
                id="RULE_FIRE_ESCAPE",
                rule_name="Fire Escape Clearance",
                category="Safety",
                severity="Error",
                enabled=True
            ),
            ValidationRule(
                id="RULE_ROOM_CAP",
                rule_name="Room Capacity Validation",
                category="Furniture",
                maximum_value=60.0, # max furniture area percentage
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_LIGHTING",
                rule_name="Lighting Coverage",
                category="Lighting",
                minimum_value=0.0,
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_SPACING",
                rule_name="Furniture Spacing",
                category="Furniture",
                minimum_value=50.0, # min spacing in cm
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_BALANCE",
                rule_name="Room Balance",
                category="Aesthetics",
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_WARDROBE_CLR",
                rule_name="Wardrobe & Cabinet Clearance",
                category="Ergonomics",
                minimum_value=75.0, # 75cm front clearance for door and drawer operation
                severity="Warning",
                enabled=True
            ),
            ValidationRule(
                id="RULE_METADATA",
                rule_name="Dimension & Metadata Availability",
                category="Safety",
                severity="Warning",
                enabled=True
            )
        ]

        for rule in default_rules:
            existing = db.query(ValidationRule).filter(ValidationRule.id == rule.id).first()
            if not existing:
                db.add(rule)
        db.commit()

    @classmethod
    def validate_room(
        cls,
        db: Session,
        room_id: str,
        user_id: str,
        min_walkway_clearance: Optional[float] = None,
        require_both_sides_bed_access: Optional[bool] = None,
        override_room_type: Optional[str] = None,
        override_furniture: Optional[List[Dict[str, Any]]] = None,
        override_openings: Optional[List[Dict[str, Any]]] = None
    ) -> ValidationRunResponseData:
        """
        Runs the full spatial usability validation suite on the room layout.
        """
        # Ensure rules are seeded
        cls.seed_default_rules(db)

        # Fetch room
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
        
        # Verify ownership via project
        if room.project.user_id != user_id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

        if not room.measurements:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Room measurements are required")

        room_width = room.measurements.width   # X axis limit
        room_length = room.measurements.length # Z axis limit

        # Parse layout properties
        furniture: List[Dict[str, Any]] = []
        openings: List[Dict[str, Any]] = []
        props_dict = {}
        if room.properties:
            try:
                props_dict = json.loads(room.properties)
                furniture = props_dict.get('furniture', [])
                openings = props_dict.get('openings', [])
            except Exception:
                pass

        if override_furniture is not None:
            furniture = override_furniture
        if override_openings is not None:
            openings = override_openings

        if not openings:
            num_doors = int(props_dict.get('doors', 1) or 1)
            num_windows = int(props_dict.get('windows', 1) or 1)
            from features.ai.geometry import generate_room_geometry
            _, gen_openings = generate_room_geometry(room_width, room_length, num_doors, num_windows)
            openings = gen_openings

        # Effective room type and configurable clearance values
        effective_room_type = (override_room_type or room.room_type or "Living Room").strip()
        t_lower = effective_room_type.lower()

        # Load active rules from DB
        db_rules = {r.id: r for r in db.query(ValidationRule).filter(ValidationRule.enabled == True).all()}

        # Walkway width configuration
        if min_walkway_clearance is not None:
            walkway_width = float(min_walkway_clearance)
        else:
            if "bed" in t_lower:
                walkway_width = 70.0
            elif "hall" in t_lower or "corridor" in t_lower:
                walkway_width = 90.0
            elif "kitchen" in t_lower:
                walkway_width = 90.0
            elif "dining" in t_lower:
                walkway_width = 80.0
            elif "office" in t_lower:
                walkway_width = 75.0
            else:
                rule_w = db_rules.get("RULE_WALKWAY")
                walkway_width = rule_w.minimum_value if (rule_w and rule_w.minimum_value) else 75.0

        # Bed clearance requirement configuration
        if require_both_sides_bed_access is not None:
            require_both_sides = bool(require_both_sides_bed_access)
        else:
            require_both_sides = ("master" in t_lower or "double" in t_lower or "king" in t_lower or "queen" in t_lower)

        errors: List[ValidationIssue] = []
        warnings: List[ValidationIssue] = []
        suggestions: List[ValidationIssue] = []
        passed_rules: List[str] = []

        def add_issue(
            rule_id: str,
            message: str,
            rec: str,
            affected_ids: List[str] = [],
            severity_override: Optional[str] = None,
            measured_clearance: Optional[float] = None,
            required_clearance: Optional[float] = None,
            clearance_source: Optional[str] = None,
            issue_type: Optional[str] = None,
            is_fixable: bool = False,
            suggested_action: Optional[str] = None
        ):
            rule = db_rules.get(rule_id)
            if not rule:
                return
            
            sev = severity_override if severity_override is not None else rule.severity

            issue = ValidationIssue(
                id=str(uuid.uuid4()),
                rule_id=rule.id,
                rule_name=rule.rule_name,
                category=rule.category,
                severity=sev,
                message=message,
                recommendation=rec,
                affected_furniture_ids=affected_ids,
                measured_clearance=round(measured_clearance, 1) if measured_clearance is not None else None,
                required_clearance=round(required_clearance, 1) if required_clearance is not None else None,
                clearance_source=clearance_source,
                issue_type=issue_type,
                is_fixable=is_fixable,
                suggested_action=suggested_action
            )
            
            if sev == "Error":
                errors.append(issue)
            elif sev == "Warning":
                warnings.append(issue)
            else:
                suggestions.append(issue)

        # ----------------------------------------------------
        # 0. Metadata Completeness Check
        # ----------------------------------------------------
        for f in furniture:
            meta = check_furniture_metadata(f)
            if not meta['valid']:
                add_issue(
                    "RULE_METADATA",
                    f"Furniture '{f.get('name', 'Item')}' has incomplete dimensional metadata (missing: {', '.join(meta['missing'])}). Clearance calculations are limited.",
                    "Provide explicit width, depth, and height dimensions to ensure accurate clearance checking.",
                    affected_ids=[f.get('id')] if f.get('id') else [],
                    severity_override="Warning",
                    issue_type="missing_metadata",
                    is_fixable=False
                )

        # ----------------------------------------------------
        # 0.5. Room Type Furniture Compatibility Check
        # ----------------------------------------------------
        rule_compat_id = "RULE_ROOM_COMPATIBILITY"
        if rule_compat_id in db_rules:
            from features.ai.room_rules import get_room_rule
            room_rule = get_room_rule(effective_room_type)
            incompatible_found = False
            for f in furniture:
                f_name = f.get('name', '')
                f_cat = f.get('category', '')
                f_tags = f.get('tags', '')
                f_role = f.get('role', '')
                is_comp, reason = room_rule.is_asset_compatible(name=f_name, category=f_cat, tags=f_tags, role=f_role)
                if not is_comp:
                    incompatible_found = True
                    add_issue(
                        rule_compat_id,
                        f"Inappropriate furniture for {room_rule.display_name}: '{f_name}' ({f_cat}) violates room design requirements. {reason or ''}",
                        f"Replace '{f_name}' with a room-appropriate item from the catalog or remove it.",
                        affected_ids=[f.get('id')] if f.get('id') else [],
                        severity_override="Error",
                        issue_type="room_incompatible",
                        is_fixable=True,
                        suggested_action=f"Replace '{f_name}' with an appropriate {room_rule.display_name} asset."
                    )
            if not incompatible_found:
                passed_rules.append(rule_compat_id)

        # ----------------------------------------------------
        # 1. Collision Detection (Furniture Overlap using SAT)
        # ----------------------------------------------------
        rule_collision_id = "RULE_COLLISION"
        obbs = [(f, get_furniture_obb(f)) for f in furniture]
        if rule_collision_id in db_rules:
            collision_detected = False
            for i in range(len(obbs)):
                f1, o1 = obbs[i]
                for j in range(i + 1, len(obbs)):
                    f2, o2 = obbs[j]
                    has_overlap, depth, _ = obb_overlap_sat(o1, o2)
                    if has_overlap:
                        collision_detected = True
                        add_issue(
                            rule_collision_id,
                            f"Collision detected: '{f1.get('name')}' overlaps with '{f2.get('name')}'.",
                            f"Move '{f1.get('name')}' or '{f2.get('name')}' apart so they do not overlap.",
                            [f1.get('id'), f2.get('id')],
                            severity_override="Error",
                            measured_clearance=round(-depth, 1),
                            required_clearance=0.0,
                            clearance_source="Collision Detection Margin (0 cm)",
                            issue_type="collision",
                            is_fixable=True,
                            suggested_action=f"Reposition '{f1.get('name')}' or '{f2.get('name')}' to eliminate the {int(depth)} cm overlap."
                        )
            if not collision_detected:
                passed_rules.append(rule_collision_id)

        # ----------------------------------------------------
        # 2. Wall Collision (Boundary Check using OBB Corners)
        # ----------------------------------------------------
        rule_wall_id = "RULE_WALL"
        if rule_wall_id in db_rules:
            wall_collision = False
            for f, o1 in obbs:
                corners = o1.get_corners()
                max_intrusion = 0.0
                for cx, cz in corners:
                    intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                    if intrus > max_intrusion:
                        max_intrusion = intrus
                if max_intrusion > 0.0:
                    wall_collision = True
                    add_issue(
                        rule_wall_id,
                        f"Furniture '{f.get('name')}' intersects with room walls or is outside the room boundaries.",
                        f"Reposition '{f.get('name')}' to be completely inside the {int(room_width)}x{int(room_length)} cm room bounds.",
                        [f.get('id')],
                        severity_override="Error",
                        measured_clearance=round(-max_intrusion, 1),
                        required_clearance=0.0,
                        clearance_source="Room Perimeter Boundary (0 cm)",
                        issue_type="wall_collision",
                        is_fixable=True,
                        suggested_action=f"Move '{f.get('name')}' inside room bounds."
                    )
            if not wall_collision:
                passed_rules.append(rule_wall_id)

        # ----------------------------------------------------
        # 3. Door Clearance & Door-Swing Arc Validation
        # ----------------------------------------------------
        rule_door_id = "RULE_DOOR"
        if rule_door_id in db_rules:
            door_blocked = False
            doors = [op for op in openings if op.get('type') == 'door']
            door_val = db_rules[rule_door_id].minimum_value or 80.0
            
            for door in doors:
                door_geom = get_door_swing_geometry(door, room_width, room_length)
                dw = max(door.get('width', door_val), door_val)
                
                for f, o1 in obbs:
                    is_obstr, cl, reason = door_geom.check_obstruction(o1, dw)
                    
                    if is_obstr:
                        door_blocked = True
                        is_severe = (cl < 40.0) or ("arc" in reason) or ("threshold" in reason) or ("overlap" in reason)
                        add_issue(
                            rule_door_id,
                            f"Furniture '{f.get('name')}' blocks the door swing area ({int(dw)} cm zone).",
                            f"Move '{f.get('name')}' at least {int(dw)} cm away from the door center.",
                            [f.get('id')],
                            severity_override="Error" if is_severe else "Warning",
                            measured_clearance=cl,
                            required_clearance=dw,
                            clearance_source=f"Door Swing & Entry Clearance ({int(dw)} cm)",
                            issue_type="door_swing" if "arc" in reason else "door_blocked",
                            is_fixable=True,
                            suggested_action=f"Reposition '{f.get('name')}' at least {int(dw - cl + 10)} cm away from the door."
                        )
            if not door_blocked:
                passed_rules.append(rule_door_id)

        # ----------------------------------------------------
        # 4. Window Clearance (using Closest Point on OBB)
        # ----------------------------------------------------
        rule_window_id = "RULE_WINDOW"
        if rule_window_id in db_rules:
            window_issue = False
            windows = [op for op in openings if op.get('type') == 'window']
            min_win_offset = db_rules[rule_window_id].minimum_value or 50.0

            for win in windows:
                wx = win.get('x', 0.0)
                wz = win.get('y', 0.0)
                
                for f, o1 in obbs:
                    gx, gz = closest_point_on_obb(o1, (wx, wz))
                    dist = math.sqrt((gx - wx)**2 + (gz - wz)**2)

                    if dist < min_win_offset:
                        window_issue = True
                        add_issue(
                            rule_window_id,
                            f"Furniture '{f.get('name')}' blocks window access.",
                            f"Keep a clearance of at least {int(min_win_offset)} cm in front of the window.",
                            [f.get('id')],
                            severity_override="Warning",
                            measured_clearance=round(dist, 1),
                            required_clearance=min_win_offset,
                            clearance_source="Window Access Clearance (50 cm)",
                            issue_type="window_blocked",
                            is_fixable=True,
                            suggested_action=f"Move '{f.get('name')}' at least {int(min_win_offset)} cm from the window."
                        )
                    elif f.get('height', 0) > 100.0 and dist < 100.0:
                        window_issue = True
                        add_issue(
                            rule_window_id,
                            f"Tall furniture '{f.get('name')}' (height: {int(f.get('height'))} cm) blocks natural lighting from window.",
                            f"Relocate tall furniture '{f.get('name')}' away from windows to preserve natural lighting.",
                            [f.get('id')],
                            severity_override="Warning",
                            measured_clearance=round(dist, 1),
                            required_clearance=100.0,
                            clearance_source="Window Daylighting Envelope (100 cm)",
                            issue_type="window_blocked",
                            is_fixable=True,
                            suggested_action=f"Reposition tall item '{f.get('name')}' away from window."
                        )
            if not window_issue:
                passed_rules.append(rule_window_id)

        # ----------------------------------------------------
        # 5. Walking Passage Validation & Circulation Bottlenecks
        # ----------------------------------------------------
        grid = OccupancyGrid(room_width, room_length, cell_size=10.0)
        for f, o1 in obbs:
            mark_obstacle_obb(grid, o1)

        doors = [op for op in openings if op.get('type') == 'door']
        start_cell = grid.to_cell(doors[0].get('x', 0.0), doors[0].get('y', 0.0)) if doors else grid.to_cell(room_width / 2.0, room_length / 2.0)
        
        # Clear door start cell temporarily for pathfinding
        original_start_val = grid.grid[start_cell[0]][start_cell[1]]
        grid.grid[start_cell[0]][start_cell[1]] = 0
        reachable_cells = compute_reachability(grid, start_cell)

        # Walkway Width rule
        rule_walkway_id = "RULE_WALKWAY"
        if rule_walkway_id in db_rules:
            # Pairwise geometric passage clearance check
            for i in range(len(furniture)):
                f1, o1 = obbs[i]
                for j in range(i + 1, len(furniture)):
                    f2, o2 = obbs[j]
                    n1 = f1.get('name', '').lower()
                    n2 = f2.get('name', '').lower()
                    r1 = f1.get('role', '').lower()
                    r2 = f2.get('role', '').lower()
                    is_bed_stand = ('bed' in n1 and ('stand' in n2 or 'night' in n2)) or ('bed' in n2 and ('stand' in n1 or 'night' in n1)) or (r1 == 'primary_sleep' and r2 == 'bedside') or (r2 == 'primary_sleep' and r1 == 'bedside')
                    is_desk_chair = ('desk' in n1 and 'chair' in n2) or ('desk' in n2 and 'chair' in n1)
                    is_table_chair = ('table' in n1 and 'chair' in n2) or ('table' in n2 and 'chair' in n1)
                    if is_bed_stand or is_desk_chair or is_table_chair:
                        continue
                        
                    p_dist = obb_distance(o1, o2)
                    if p_dist < walkway_width:
                        is_blocked = p_dist < 45.0
                        sev = "Error" if is_blocked else "Warning"
                        passage_label = "severely blocked" if is_blocked else "narrow"
                        add_issue(
                            rule_walkway_id,
                            f"Walkway between '{f1.get('name')}' and '{f2.get('name')}' is {passage_label} ({int(p_dist)} cm; required: {int(walkway_width)} cm).",
                            f"Increase spacing between '{f1.get('name')}' and '{f2.get('name')}' to provide at least {int(walkway_width)} cm passage clearance.",
                            [f1.get('id'), f2.get('id')],
                            severity_override=sev,
                            measured_clearance=round(p_dist, 1),
                            required_clearance=walkway_width,
                            clearance_source=f"Configured Circulation Clearance ({int(walkway_width)} cm for {effective_room_type.title()})",
                            issue_type="narrow_passage",
                            is_fixable=True,
                            suggested_action=f"Shift '{f1.get('name')}' or '{f2.get('name')}' to widen the passage by at least {int(walkway_width - p_dist)} cm."
                        )

            # Circulation reachability & dilated grid
            dilated_grid = OccupancyGrid(room_width, room_length, cell_size=10.0)
            padding = walkway_width / 2.0
            for f, o1 in obbs:
                mark_obstacle_obb(dilated_grid, o1, padding=padding)

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

            doors_connected = True
            if len(doors) > 1:
                for i in range(len(doors)):
                    for j in range(i + 1, len(doors)):
                        cell_a = dilated_grid.to_cell(doors[i].get('x', 0.0), doors[i].get('y', 0.0))
                        cell_b = dilated_grid.to_cell(doors[j].get('x', 0.0), doors[j].get('y', 0.0))
                        dilated_grid.grid[cell_a[0]][cell_a[1]] = 0
                        dilated_grid.grid[cell_b[0]][cell_b[1]] = 0
                        path = find_path_astar(dilated_grid, cell_a, cell_b)
                        if not path:
                            doors_connected = False
                            break

            dilated_ratio = 0.0
            if dilated_start is not None:
                dilated_reachable = compute_reachability(dilated_grid, dilated_start)
                total_walkable = sum(1 for i in range(dilated_grid.width_cells) for j in range(dilated_grid.length_cells) if dilated_grid.grid[i][j] == 0)
                dilated_ratio = len(dilated_reachable) / total_walkable if total_walkable > 0 else 0.0

            if not doors_connected or (len(furniture) > 0 and dilated_ratio < 0.35):
                affected_walkway_ids = []
                for i in range(len(furniture)):
                    f1, o1 = obbs[i]
                    for j in range(i + 1, len(furniture)):
                        f2, o2 = obbs[j]
                        d_centers = math.sqrt((o1.cx - o2.cx)**2 + (o1.cz - o2.cz)**2)
                        size1 = (o1.width + o1.depth) / 4.0
                        size2 = (o2.width + o2.depth) / 4.0
                        if d_centers - size1 - size2 < walkway_width:
                            if f1.get('id') and f1.get('id') not in affected_walkway_ids:
                                affected_walkway_ids.append(f1.get('id'))
                            if f2.get('id') and f2.get('id') not in affected_walkway_ids:
                                affected_walkway_ids.append(f2.get('id'))

                add_issue(
                    rule_walkway_id,
                    f"Walkways are too narrow. Main circulation paths do not support {int(walkway_width)} cm clearances.",
                    f"Rearrange furniture items along perimeter walls or increase spacing to clear at least {int(walkway_width)} cm walking lanes.",
                    affected_walkway_ids,
                    severity_override="Error",
                    measured_clearance=round(dilated_ratio * walkway_width, 1),
                    required_clearance=walkway_width,
                    clearance_source=f"Overall Room Circulation Grid ({int(walkway_width)} cm)",
                    issue_type="narrow_passage",
                    is_fixable=True,
                    suggested_action="Spread furniture out towards walls to clear main walking corridor."
                )
            elif not any(e.rule_id == rule_walkway_id for e in errors + warnings):
                passed_rules.append(rule_walkway_id)

        # Accessibility turn space, reachable ratio, and furniture reachability
        rule_access_id = "RULE_ACCESSIBILITY"
        if rule_access_id in db_rules:
            access_issue = False
            total_walkable_cells = sum(1 for i in range(grid.width_cells) for j in range(grid.length_cells) if grid.grid[i][j] == 0)
            reachable_ratio = len(reachable_cells) / total_walkable_cells if total_walkable_cells > 0 else 0.0
            
            if reachable_ratio < 0.70:
                access_issue = True
                add_issue(
                    rule_access_id,
                    f"Reachable free space ratio is too low ({int(reachable_ratio*100)}%). Large areas are isolated.",
                    "Ensure walkways aren't completely blocked by floating furniture."
                )

            # Wheelchair turning circle: check if 150 cm circle is free
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

            if not has_turning_space and len(furniture) > 0:
                access_issue = True
                add_issue(
                    rule_access_id,
                    "No wheelchair turning space (150 cm diameter circle) is available.",
                    "Clear a central 150 cm circular area free of any furniture."
                )

            # Furniture reachability from room entrance
            unreachable_furniture = []
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
                    unreachable_furniture.append(f)
            
            if unreachable_furniture:
                access_issue = True
                f_names = ", ".join([f"'{f.get('name')}'" for f in unreachable_furniture])
                add_issue(
                    rule_access_id,
                    f"Blocked furniture access: {f_names} cannot be reached from the door.",
                    "Provide clear pathways to all furniture items.",
                    [f.get('id') for f in unreachable_furniture],
                    severity_override="Error",
                    measured_clearance=0.0,
                    required_clearance=walkway_width,
                    clearance_source="Entrance Reachability",
                    issue_type="blocked_route",
                    is_fixable=True,
                    suggested_action="Move obstructing furniture away from path to make item reachable."
                )

            if not access_issue:
                passed_rules.append(rule_access_id)

        # Restore original start value
        grid.grid[start_cell[0]][start_cell[1]] = original_start_val

        # ----------------------------------------------------
        # 6. TV Viewing Distance
        # ----------------------------------------------------
        rule_tv_id = "RULE_TV_DIST"
        if rule_tv_id in db_rules:
            tv_issue = False
            sofas = [f for f in furniture if 'sofa' in f.get('name', '').lower() or 'couch' in f.get('name', '').lower()]
            tvs = [f for f in furniture if 'tv' in f.get('name', '').lower() or 'television' in f.get('name', '').lower() or 'media' in f.get('name', '').lower()]
            
            rule_r = db_rules[rule_tv_id]
            min_v = rule_r.minimum_value or 150.0
            max_v = rule_r.maximum_value or 300.0

            for sofa in sofas:
                for tv in tvs:
                    dist = math.sqrt((sofa.get('x', 0.0) - tv.get('x', 0.0))**2 + (sofa.get('z', 0.0) - tv.get('z', 0.0))**2)
                    if dist < min_v:
                        tv_issue = True
                        add_issue(
                            rule_tv_id,
                            f"TV viewing distance is too close ({int(dist)} cm). Minimum is {int(min_v)} cm.",
                            f"Move the sofa '{sofa.get('name')}' or TV '{tv.get('name')}' further apart to at least {int(min_v)} cm.",
                            [sofa.get('id'), tv.get('id')]
                        )
                    elif dist > max_v:
                        tv_issue = True
                        add_issue(
                            rule_tv_id,
                            f"TV viewing distance is too far ({int(dist)} cm). Maximum comfortable viewing is {int(max_v)} cm.",
                            f"Bring the sofa '{sofa.get('name')}' or TV '{tv.get('name')}' closer together.",
                            [sofa.get('id'), tv.get('id')]
                        )
            if not tv_issue and sofas and tvs:
                passed_rules.append(rule_tv_id)

        # ----------------------------------------------------
        # 7. Bed Clearance Validation (Single vs Both Sides)
        # ----------------------------------------------------
        rule_bed_id = "RULE_BED_CLR"
        if rule_bed_id in db_rules:
            bed_issue = False
            beds = [f for f in furniture if 'bed' in f.get('name', '').lower() or f.get('category', '').lower() == 'bedroom']
            min_bed_clr = db_rules[rule_bed_id].minimum_value or 60.0

            for bed in beds:
                bed_obb = get_furniture_obb(bed)
                left_obb = get_furniture_clearance_obb(bed, 'left', depth=min_bed_clr)
                right_obb = get_furniture_clearance_obb(bed, 'right', depth=min_bed_clr)
                
                left_cl = min_bed_clr
                right_cl = min_bed_clr

                for other in furniture:
                    if other.get('id') == bed.get('id'):
                        continue
                    other_name = other.get('name', '').lower()
                    other_role = other.get('role', '').lower()
                    if 'stand' in other_name or 'night' in other_name or 'bedside' in other_role or other_role == 'bedside':
                        continue
                        
                    o2 = get_furniture_obb(other)
                    o_l, d_l, _ = obb_overlap_sat(left_obb, o2)
                    if o_l:
                        left_cl = min(left_cl, max(0.0, min_bed_clr - d_l))
                    o_r, d_r, _ = obb_overlap_sat(right_obb, o2)
                    if o_r:
                        right_cl = min(right_cl, max(0.0, min_bed_clr - d_r))

                # Wall boundaries
                for cx, cz in left_obb.get_corners():
                    if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                        intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                        left_cl = min(left_cl, max(0.0, min_bed_clr - intrus))
                for cx, cz in right_obb.get_corners():
                    if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                        intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                        right_cl = min(right_cl, max(0.0, min_bed_clr - intrus))

                if require_both_sides:
                    # Master bedroom requires both sides clear
                    if left_cl < min_bed_clr or right_cl < min_bed_clr:
                        bed_issue = True
                        measured = min(left_cl, right_cl)
                        is_severe = left_cl < 20.0 and right_cl < 20.0
                        add_issue(
                            rule_bed_id,
                            f"Bed '{bed.get('name')}' in {effective_room_type.title()} requires clearance on both sides (left: {int(left_cl)} cm, right: {int(right_cl)} cm; minimum: {int(min_bed_clr)} cm).",
                            f"Provide at least {int(min_bed_clr)} cm of space on both sides of the bed for comfortable egress.",
                            [bed.get('id')],
                            severity_override="Error" if is_severe else "Warning",
                            measured_clearance=round(measured, 1),
                            required_clearance=min_bed_clr,
                            clearance_source=f"Bed Egress (Both Sides Required for {effective_room_type.title()})",
                            issue_type="bed_access",
                            is_fixable=True,
                            suggested_action=f"Center bed '{bed.get('name')}' along the wall to equalize side clearances."
                        )
                else:
                    # Standard or single bed requires at least one side clear
                    if left_cl < min_bed_clr and right_cl < min_bed_clr:
                        bed_issue = True
                        measured = max(left_cl, right_cl)
                        add_issue(
                            rule_bed_id,
                            f"Bed '{bed.get('name')}' lacks standard side clearance (minimum {int(min_bed_clr)} cm on at least one side).",
                            f"Provide at least {int(min_bed_clr)} cm of space on at least one side of the bed for comfortable egress.",
                            [bed.get('id')],
                            severity_override="Warning",
                            measured_clearance=round(measured, 1),
                            required_clearance=min_bed_clr,
                            clearance_source="Bed Egress (Single Side Required)",
                            issue_type="bed_access",
                            is_fixable=True,
                            suggested_action=f"Shift bed '{bed.get('name')}' to provide at least {int(min_bed_clr)} cm on one side."
                        )

            if not bed_issue and beds:
                passed_rules.append(rule_bed_id)

        # ----------------------------------------------------
        # 8. Dining Spacing & Chair Pull-out Clearance
        # ----------------------------------------------------
        rule_dining_id = "RULE_DINING_CLR"
        if rule_dining_id in db_rules:
            dining_issue = False
            tables = [f for f in furniture if 'dining' in f.get('name', '').lower() or 'table' in f.get('name', '').lower() or f.get('category', '').lower() == 'dining']
            chairs = [f for f in furniture if 'chair' in f.get('name', '').lower()]
            min_dining = db_rules[rule_dining_id].minimum_value or 50.0

            for chair in chairs:
                if 'dining' in room.room_type.lower() or 'kitchen' in room.room_type.lower() or any('table' in f.get('name', '').lower() for f in furniture):
                    cx = chair.get('x', 0.0)
                    cz = chair.get('z', 0.0)
                    dist_wall = min(cx, room_width - cx, cz, room_length - cz)

                    rear_obb = get_furniture_clearance_obb(chair, 'rear', depth=min_dining)
                    min_dist_avail = dist_wall

                    # Check obstacle furniture behind chair
                    for other in furniture:
                        if other.get('id') == chair.get('id') or any(k in other.get('name', '').lower() for k in ['table', 'desk']):
                            continue
                        o2 = get_furniture_obb(other)
                        overlap, depth, _ = obb_overlap_sat(rear_obb, o2)
                        if overlap:
                            min_dist_avail = min(min_dist_avail, max(0.0, min_dining - depth))
                    
                    if min_dist_avail < min_dining:
                        dining_issue = True
                        add_issue(
                            rule_dining_id,
                            f"Dining chair '{chair.get('name')}' is too close to the wall ({int(dist_wall)} cm).",
                            f"Ensure at least {int(min_dining)} cm of clearance behind chairs for pull-out comfort.",
                            [chair.get('id')],
                            severity_override="Info" if min_dist_avail >= 35.0 else "Warning",
                            measured_clearance=round(min_dist_avail, 1),
                            required_clearance=min_dining,
                            clearance_source="Dining Chair Pull-out Ergonomics (50 cm)",
                            issue_type="dining_pullout",
                            is_fixable=True,
                            suggested_action=f"Pull dining table and '{chair.get('name')}' at least {int(min_dining - min_dist_avail + 10)} cm into the room."
                        )
            if not dining_issue and tables and chairs:
                passed_rules.append(rule_dining_id)

        # ----------------------------------------------------
        # 8b. Wardrobe & Cabinet Front Opening Clearance
        # ----------------------------------------------------
        rule_wardrobe_id = "RULE_WARDROBE_CLR"
        if rule_wardrobe_id in db_rules:
            wardrobe_issue = False
            storage_items = [f for f in furniture if any(k in f.get('name', '').lower() for k in ['wardrobe', 'cabinet', 'dresser', 'credenza'])]
            req_w_cl = db_rules[rule_wardrobe_id].minimum_value or 75.0

            for st in storage_items:
                st_obb = get_furniture_obb(st)
                front_obb = get_furniture_clearance_obb(st, 'front', depth=req_w_cl)
                min_front_avail = req_w_cl
                obstructing_name = None
                obstructing_id = None

                for other in furniture:
                    if other.get('id') == st.get('id'):
                        continue
                    o2 = get_furniture_obb(other)
                    overlap, depth, _ = obb_overlap_sat(front_obb, o2)
                    if overlap:
                        wardrobe_issue = True
                        avail_cl = max(0.0, req_w_cl - depth)
                        if avail_cl < min_front_avail:
                            min_front_avail = avail_cl
                            obstructing_name = other.get('name', 'Furniture')
                            obstructing_id = other.get('id')

                # Wall obstruction in front
                for cx, cz in front_obb.get_corners():
                    if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                        intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                        avail_cl = max(0.0, req_w_cl - intrus)
                        if avail_cl < min_front_avail:
                            min_front_avail = avail_cl
                            obstructing_name = "Room Wall"

                if min_front_avail < req_w_cl:
                    wardrobe_issue = True
                    sev = "Error" if min_front_avail < 30.0 else "Warning"
                    aff_ids = [st.get('id')]
                    if obstructing_id:
                        aff_ids.append(obstructing_id)
                    add_issue(
                        rule_wardrobe_id,
                        f"Wardrobe/cabinet '{st.get('name')}' front door/drawer opening clearance is obstructed by '{obstructing_name or 'another obstacle'}' ({int(min_front_avail)} cm available; required: {int(req_w_cl)} cm).",
                        f"Keep at least {int(req_w_cl)} cm of clear space in front of '{st.get('name')}' for doors and drawers to fully open.",
                        aff_ids,
                        severity_override=sev,
                        measured_clearance=round(min_front_avail, 1),
                        required_clearance=req_w_cl,
                        clearance_source=f"Wardrobe Door & Drawer Operation Zone ({int(req_w_cl)} cm)",
                        issue_type="wardrobe_blocked",
                        is_fixable=True,
                        suggested_action=f"Reposition '{st.get('name')}' or surrounding items to provide {int(req_w_cl)} cm open front space."
                    )
            if not wardrobe_issue and storage_items:
                passed_rules.append(rule_wardrobe_id)


        # ----------------------------------------------------
        # 9. Desk Ergonomics
        # ----------------------------------------------------
        rule_desk_id = "RULE_DESK_ERGO"
        if rule_desk_id in db_rules:
            desk_issue = False
            desks = [f for f in furniture if 'desk' in f.get('name', '').lower() or 'study' in f.get('name', '').lower()]
            chairs = [f for f in furniture if 'chair' in f.get('name', '').lower()]
            min_pullout = db_rules[rule_desk_id].minimum_value or 80.0

            for desk in desks:
                for chair in chairs:
                    dist = math.sqrt((desk.get('x', 0.0) - chair.get('x', 0.0))**2 + (desk.get('z', 0.0) - chair.get('z', 0.0))**2)
                    if 50.0 <= dist <= 120.0:
                        # Pull out space behind chair: distance to wall or boundaries
                        cx = chair.get('x', 0.0)
                        cz = chair.get('z', 0.0)
                        dist_wall = min(cx, room_width - cx, cz, room_length - cz)
                        if dist_wall < min_pullout:
                            desk_issue = True
                            add_issue(
                                rule_desk_id,
                                f"Desk chair '{chair.get('name')}' lacks required pull-out clearance behind it ({int(dist_wall)} cm).",
                                f"Keep at least {int(min_pullout)} cm of open space behind study/office chairs.",
                                [desk.get('id'), chair.get('id')]
                            )
            if not desk_issue and desks and chairs:
                passed_rules.append(rule_desk_id)

        # ----------------------------------------------------
        # 10. Kitchen Triangle Validation
        # ----------------------------------------------------
        rule_kitchen_id = "RULE_KITCHEN_TRI"
        if rule_kitchen_id in db_rules and 'kitchen' in room.room_type.lower():
            # Search for Stove, Fridge, Sink in name/category
            stove = next((f for f in furniture if any(k in f.get('name', '').lower() for k in ['stove', 'range', 'cooktop', 'oven'])), None)
            fridge = next((f for f in furniture if any(k in f.get('name', '').lower() for k in ['refrigerator', 'fridge', 'freezer'])), None)
            sink = next((f for f in furniture if 'sink' in f.get('name', '').lower()), None)

            if stove and fridge and sink:
                d1 = math.sqrt((stove['x'] - sink['x'])**2 + (stove['z'] - sink['z'])**2)
                d2 = math.sqrt((sink['x'] - fridge['x'])**2 + (sink['z'] - fridge['z'])**2)
                d3 = math.sqrt((fridge['x'] - stove['x'])**2 + (fridge['z'] - stove['z'])**2)
                total_dist = d1 + d2 + d3

                triangle_passed = True
                recs = []
                if not (120.0 <= d1 <= 270.0):
                    triangle_passed = False
                    recs.append(f"Stove-Sink distance ({int(d1)} cm) should be 120-270 cm.")
                if not (120.0 <= d2 <= 270.0):
                    triangle_passed = False
                    recs.append(f"Sink-Fridge distance ({int(d2)} cm) should be 120-270 cm.")
                if not (120.0 <= d3 <= 270.0):
                    triangle_passed = False
                    recs.append(f"Fridge-Stove distance ({int(d3)} cm) should be 120-270 cm.")
                if not (400.0 <= total_dist <= 790.0):
                    triangle_passed = False
                    recs.append(f"Sum of triangle legs ({int(total_dist)} cm) should be 400-790 cm.")

                if not triangle_passed:
                    add_issue(
                        rule_kitchen_id,
                        f"Kitchen work triangle principles are violated. Path segments: Stove-Sink: {int(d1)} cm, Sink-Fridge: {int(d2)} cm, Fridge-Stove: {int(d3)} cm.",
                        " ".join(recs),
                        [stove['id'], fridge['id'], sink['id']]
                    )
                else:
                    passed_rules.append(rule_kitchen_id)

        # ----------------------------------------------------
        # 11. Fire Escape Clearance
        # ----------------------------------------------------
        rule_fire_id = "RULE_FIRE_ESCAPE"
        if rule_fire_id in db_rules:
            fire_escape_blocked = False
            doors = [op for op in openings if op.get('type') == 'door']
            
            # Construct normal grid
            esc_grid = OccupancyGrid(room_width, room_length, cell_size=10.0)
            for f in furniture:
                bbox = get_furniture_bbox(f)
                esc_grid.mark_obstacle_rect(bbox['left'], bbox['right'], bbox['top'], bbox['bottom'])
                
            if doors:
                exit_door = doors[0]
                door_cell = esc_grid.to_cell(exit_door.get('x'), exit_door.get('y'))
                
                # Check if door cell itself is blocked (obstacle value = 1)
                if esc_grid.grid[door_cell[0]][door_cell[1]] == 1:
                    fire_escape_blocked = True
                    add_issue(
                        rule_fire_id,
                        "Emergency exit doorway is completely blocked by furniture.",
                        "Clear all obstacles immediately from the exit door swing and threshold."
                    )
                else:
                    # Check path from room interior to door cell
                    center_i, center_j = esc_grid.to_cell(room_width / 2.0, room_length / 2.0)
                    start_cell = (center_i, center_j)
                    if esc_grid.grid[center_i][center_j] == 1:
                        # Find nearest walkable cell
                        queue = [(center_i, center_j)]
                        visited = {(center_i, center_j)}
                        found = False
                        while queue and not found:
                            curr_i, curr_j = queue.pop(0)
                            for di, dj in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]:
                                ni, nj = curr_i + di, curr_j + dj
                                if esc_grid.is_valid_cell(ni, nj) and (ni, nj) not in visited:
                                    visited.add((ni, nj))
                                    if esc_grid.grid[ni][nj] == 0:
                                        start_cell = (ni, nj)
                                        found = True
                                        break
                                    queue.append((ni, nj))
                    
                    esc_grid.grid[door_cell[0]][door_cell[1]] = 0 # force clear door threshold for path check
                    path = find_path_astar(esc_grid, start_cell, door_cell)
                    if not path:
                        fire_escape_blocked = True
                        add_issue(
                            rule_fire_id,
                            "Emergency exit pathway is obstructed. There is no clear escape path to the exit.",
                            "Rearrange furniture to ensure a clear pathway from the center of the room to the exit door."
                        )
            if not fire_escape_blocked:
                passed_rules.append(rule_fire_id)

        # ----------------------------------------------------
        # 12. Room Capacity Validation
        # ----------------------------------------------------
        rule_cap_id = "RULE_ROOM_CAP"
        if rule_cap_id in db_rules:
            total_f_area = sum(f.get('width', 100.0) * f.get('depth', 100.0) for f in furniture)
            room_area = room_width * room_length
            ratio = (total_f_area / room_area) * 100.0 if room_area > 0 else 0.0

            max_cap = db_rules[rule_cap_id].maximum_value or 60.0
            if ratio > max_cap:
                add_issue(
                    rule_cap_id,
                    f"Room capacity exceeded. Furniture occupies {int(ratio)}% of the room area (maximum recommended is {int(max_cap)}%).",
                    "Remove optional or decorative furniture items to declutter and free up walkable space."
                )
            else:
                passed_rules.append(rule_cap_id)

        # ----------------------------------------------------
        # 13. Lighting Coverage
        # ----------------------------------------------------
        rule_lighting_id = "RULE_LIGHTING"
        if rule_lighting_id in db_rules:
            lighting_issue = False
            blocked_window_count = 0
            windows = [op for op in openings if op.get('type') == 'window']
            affected_ids = []
            for win in windows:
                win_x = win.get('x', 0.0)
                win_z = win.get('y', 0.0)
                for f, o1 in obbs:
                    if f.get('height', 100.0) > 100.0:
                        gx, gz = closest_point_on_obb(o1, (win_x, win_z))
                        dist = math.sqrt((gx - win_x)**2 + (gz - win_z)**2)
                        if dist < 60.0:
                            blocked_window_count += 1
                            affected_ids.append(f.get('id'))
                            break
            if not windows:
                lighting_issue = True
                add_issue(
                    rule_lighting_id,
                    "No windows detected in the room. Natural light coverage is poor.",
                    "Consider adding windows to the layout to introduce natural light."
                )
            elif blocked_window_count > 0:
                lighting_issue = True
                add_issue(
                    rule_lighting_id,
                    f"Natural light coverage is compromised because {blocked_window_count} window(s) are blocked by tall furniture.",
                    "Reposition tall furniture (height > 100cm) away from windows to allow natural light.",
                    affected_ids
                )
            if not lighting_issue:
                passed_rules.append(rule_lighting_id)

        # ----------------------------------------------------
        # 14. Furniture Spacing
        # ----------------------------------------------------
        rule_spacing_id = "RULE_SPACING"
        if rule_spacing_id in db_rules:
            spacing_issue = False
            too_close_pairs = []
            for i in range(len(furniture)):
                f1 = furniture[i]
                for j in range(i + 1, len(furniture)):
                    f2 = furniture[j]
                    
                    # Exempt intended functional groupings that have dedicated ergonomic rules
                    n1 = f1.get('name', '').lower()
                    n2 = f2.get('name', '').lower()
                    is_desk_chair = ('desk' in n1 and 'chair' in n2) or ('desk' in n2 and 'chair' in n1)
                    is_table_chair = ('table' in n1 and 'chair' in n2) or ('table' in n2 and 'chair' in n1)
                    is_bed_stand = ('bed' in n1 and ('stand' in n2 or 'night' in n2)) or ('bed' in n2 and ('stand' in n1 or 'night' in n1))
                    if is_desk_chair or is_table_chair or is_bed_stand:
                        continue
                        
                    dist = math.sqrt((f1.get('x', 0.0) - f2.get('x', 0.0))**2 + (f1.get('z', 0.0) - f2.get('z', 0.0))**2)
                    size1 = (f1.get('width', 100.0) + f1.get('depth', 100.0)) / 4.0
                    size2 = (f2.get('width', 100.0) + f2.get('depth', 100.0)) / 4.0
                    edge_dist = dist - size1 - size2
                    
                    if 0.0 <= edge_dist < 40.0:
                        spacing_issue = True
                        too_close_pairs.append((f1, f2))
                        add_issue(
                            rule_spacing_id,
                            f"Furniture items '{f1.get('name')}' and '{f2.get('name')}' are too close ({int(edge_dist)} cm apart).",
                            "Ensure at least 50 cm of clearance between furniture items for comfortable usage.",
                            [f1.get('id'), f2.get('id')]
                        )
            if not spacing_issue:
                passed_rules.append(rule_spacing_id)

        # ----------------------------------------------------
        # 15. Room Balance
        # ----------------------------------------------------
        rule_balance_id = "RULE_BALANCE"
        if rule_balance_id in db_rules:
            balance_issue = False
            if furniture:
                com_x = sum(f.get('x', 0.0) for f in furniture) / len(furniture)
                com_z = sum(f.get('z', 0.0) for f in furniture) / len(furniture)
                dev_x = com_x - room_width / 2.0
                dev_z = com_z - room_length / 2.0
                deviation = math.sqrt((dev_x / room_width)**2 + (dev_z / room_length)**2) if room_width > 0 and room_length > 0 else 0.0
                
                if deviation > 0.25:
                    balance_issue = True
                    add_issue(
                        rule_balance_id,
                        f"The layout is visually unbalanced. Furniture is clustered too far from the center (deviation: {int(deviation * 100)}%).",
                        "Distribute furniture items more evenly across the room to balance the layout.",
                        [f.get('id') for f in furniture]
                    )
            if not balance_issue:
                passed_rules.append(rule_balance_id)

        # Determine overall status
        if errors:
            status_val = "Fail"
        elif warnings:
            status_val = "Warning"
        else:
            status_val = "Pass"

        # Record validation results in database
        # Clear previous validation results for this room
        db.query(ValidationResult).filter(ValidationResult.room_id == room_id).delete()

        # Add new results
        for issue in errors + warnings + suggestions:
            res = ValidationResult(
                id=str(uuid.uuid4()),
                room_id=room_id,
                rule_id=issue.rule_id,
                status="Fail" if issue.severity == "Error" else "Warning",
                severity=issue.severity,
                message=issue.message,
                created_at=datetime.now(timezone.utc)
            )
            db.add(res)

        # Add passed rules too
        for pid in passed_rules:
            res = ValidationResult(
                id=str(uuid.uuid4()),
                room_id=room_id,
                rule_id=pid,
                status="Pass",
                severity="Info",
                message=f"Rule '{db_rules[pid].rule_name}' passed.",
                created_at=datetime.now(timezone.utc)
            )
            db.add(res)

        # Update checklist items in database
        checklist_items = [
            ("Wide Walkways", not any(i.rule_id == "RULE_WALKWAY" for i in errors)),
            ("No Furniture Collision", not any(i.rule_id in ["RULE_COLLISION", "RULE_WALL"] for i in errors+warnings)),
            ("Clear Door Pathways", not any(i.rule_id == "RULE_DOOR" for i in errors)),
            ("Accessible Windows", not any(i.rule_id == "RULE_WINDOW" for i in errors+warnings)),
            ("Adequate Lighting Coverage", not any(i.rule_id == "RULE_LIGHTING" for i in errors+warnings)),
            ("Accessibility Standards Met", not any(i.rule_id == "RULE_ACCESSIBILITY" for i in errors+warnings)),
            ("Optimal Furniture Spacing", not any(i.rule_id in ["RULE_SPACING", "RULE_TV_DIST", "RULE_BED_CLR", "RULE_DINING_CLR", "RULE_DESK_ERGO", "RULE_KITCHEN_TRI", "RULE_WARDROBE_CLR"] for i in errors+warnings)),
            ("Balanced Room Layout", not any(i.rule_id == "RULE_BALANCE" for i in errors+warnings))
        ]

        # Sync database checklists
        db.query(ValidationChecklist).filter(ValidationChecklist.room_id == room_id).delete()
        for item, comp in checklist_items:
            chk = ValidationChecklist(
                id=str(uuid.uuid4()),
                room_id=room_id,
                checklist_item=item,
                completed=comp,
                completed_at=datetime.now(timezone.utc) if comp else None
            )
            db.add(chk)

        # Update scoring dashboard Analytics
        # Re-calculate score and save
        from features.ai.scoring import calculate_design_score
        scores = calculate_design_score(room_width, room_length, room.room_type, furniture, openings)
        
        # Check if analytics entry already exists
        analy = db.query(Analytics).filter(Analytics.room_id == room_id).first()
        if not analy:
            analy = Analytics(id=str(uuid.uuid4()), room_id=room_id)
            db.add(analy)
            
        analy.accessibility_score = scores['subscores']['accessibility']
        analy.lighting_score = scores['subscores']['lighting']
        analy.ergonomic_score = scores['subscores']['ergonomics']
        analy.space_utilization_score = scores['subscores']['space_utilization']
        analy.furniture_balance_score = scores['subscores']['balance']
        analy.overall_score = scores['overall_score']
        analy.generated_at = datetime.now(timezone.utc)

        db.commit()

        # Build response data object
        return ValidationRunResponseData(
            room_id=room_id,
            overall_status=status_val,
            rules_passed=len(passed_rules),
            rules_failed=len(errors) + len(warnings) + len(suggestions),
            errors=errors,
            warnings=warnings,
            suggestions=suggestions
        )
