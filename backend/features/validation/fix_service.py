import math
from typing import List, Dict, Any, Optional, Tuple
from features.ai.geometry import (
    OBB2D, get_furniture_obb, obb_overlap_sat, obb_distance,
    get_door_swing_geometry, get_furniture_clearance_obb,
    closest_point_on_obb, point_segment_distance
)
from features.validation.schemas import (
    FixCandidateResponseData, ProposedFurnitureChange, ValidationIssue
)

class LayoutFixService:
    """
    Intelligent One-Click Fix computational geometry solver.
    Identifies responsible furniture for usability violations, generates candidates
    using nearby positions, rotations, and wall snapping, filters invalid states,
    and ranks candidates to find the minimal disruption layout correction.
    """

    @classmethod
    def find_fix_for_issue(
        cls,
        room_width: float,
        room_length: float,
        room_type: str,
        furniture: List[Dict[str, Any]],
        openings: List[Dict[str, Any]],
        target_furniture_id: str,
        issue_type: Optional[str] = None,
        rule_id: Optional[str] = None,
        min_walkway_clearance: float = 75.0,
        require_both_sides_bed_access: bool = False
    ) -> FixCandidateResponseData:
        target_idx = next((i for i, f in enumerate(furniture) if str(f.get('id')) == str(target_furniture_id)), None)
        if target_idx is None:
            return FixCandidateResponseData(
                room_id="",
                target_furniture_id=target_furniture_id,
                can_fix=False,
                explanation=f"Furniture item with ID '{target_furniture_id}' was not found in the layout.",
                issue_type=issue_type,
                rule_id=rule_id,
                changes=[],
                predicted_improvement="Cannot fix: target furniture not found.",
                alternative_suggestions=["Select another issue or ensure furniture item is loaded."]
            )

        target_f = furniture[target_idx]
        f_name = target_f.get('name', 'Furniture')
        orig_x = float(target_f.get('x', 0.0))
        orig_z = float(target_f.get('z', 0.0))
        orig_rot = float(target_f.get('rotationY', target_f.get('rotation', 0.0)))
        w = float(target_f.get('width', 100.0))
        d = float(target_f.get('depth', 100.0))

        # Check for room compatibility violation fix
        if issue_type == "room_incompatible" or rule_id == "RULE_ROOM_COMPATIBILITY":
            from features.ai.room_rules import get_room_rule
            rule = get_room_rule(room_type)
            from core.database.session import SessionLocal
            from features.furniture.models import FurnitureAsset
            db = SessionLocal()
            try:
                replacement_asset = None
                low_name = f_name.lower()
                if "chair" in low_name:
                    replacement_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == "DINING_CHAIR001").first()
                    if not replacement_asset:
                        replacement_asset = db.query(FurnitureAsset).filter(FurnitureAsset.category == "Dining").first()
                elif "table" in low_name or "desk" in low_name:
                    if "kitchen" in room_type.lower() or "dining" in room_type.lower():
                        replacement_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == "TABLE001").first()
                    elif "office" in room_type.lower() or "study" in room_type.lower():
                        replacement_asset = db.query(FurnitureAsset).filter(FurnitureAsset.category == "Office").first()
                
                if replacement_asset:
                    change = ProposedFurnitureChange(
                        furniture_id=str(target_furniture_id),
                        name=f_name,
                        original_x=orig_x,
                        original_z=orig_z,
                        original_rotation=orig_rot,
                        proposed_x=orig_x,
                        proposed_z=orig_z,
                        proposed_rotation=orig_rot,
                        displacement_cm=0.0,
                        action_type="replace",
                        replacement_asset_id=replacement_asset.id,
                        replacement_name=replacement_asset.name
                    )
                    return FixCandidateResponseData(
                        room_id="",
                        target_furniture_id=str(target_furniture_id),
                        can_fix=True,
                        explanation=f"Replace '{f_name}' with room-appropriate '{replacement_asset.name}' ({replacement_asset.category}) at current location.",
                        issue_type=issue_type,
                        rule_id=rule_id,
                        changes=[change],
                        measured_before=0.0,
                        measured_after=100.0,
                        required_clearance=100.0,
                        predicted_improvement=f"Resolves room furniture incompatibility by substituting with {replacement_asset.name}.",
                        alternative_suggestions=[
                            f"Substitute with '{replacement_asset.name}' from the {replacement_asset.category} catalog.",
                            f"Delete '{f_name}' from the {rule.display_name} if seating is not needed."
                        ]
                    )
                else:
                    change = ProposedFurnitureChange(
                        furniture_id=str(target_furniture_id),
                        name=f_name,
                        original_x=orig_x,
                        original_z=orig_z,
                        original_rotation=orig_rot,
                        proposed_x=orig_x,
                        proposed_z=orig_z,
                        proposed_rotation=orig_rot,
                        displacement_cm=0.0,
                        action_type="remove"
                    )
                    return FixCandidateResponseData(
                        room_id="",
                        target_furniture_id=str(target_furniture_id),
                        can_fix=True,
                        explanation=f"Remove '{f_name}' from {rule.display_name} to restore room design appropriateness.",
                        issue_type=issue_type,
                        rule_id=rule_id,
                        changes=[change],
                        measured_before=0.0,
                        measured_after=100.0,
                        required_clearance=100.0,
                        predicted_improvement="Eliminates inappropriate furniture violation.",
                        alternative_suggestions=[f"Remove '{f_name}' from {rule.display_name}."]
                    )
            finally:
                db.close()

        other_furniture = [f for i, f in enumerate(furniture) if i != target_idx]
        other_obbs = [(f, get_furniture_obb(f)) for f in other_furniture]
        doors = [op for op in openings if op.get('type') == 'door']
        door_geoms = [get_door_swing_geometry(door, room_width, room_length) for door in doors]

        # 1. Measure clearance before fix
        before_clearance, before_required = cls._measure_clearance(
            target_f, issue_type, rule_id, other_furniture, doors, door_geoms,
            room_width, room_length, min_walkway_clearance, require_both_sides_bed_access
        )

        # 2. Generate Candidate Pool
        candidates: List[Dict[str, Any]] = []

        # Directional displacement vectors
        candidate_shifts = [
            (0.0, 0.0), # in case pure rotation fixes it
            # Orthogonal steps
            (20.0, 0.0), (-20.0, 0.0), (0.0, 20.0), (0.0, -20.0),
            (35.0, 0.0), (-35.0, 0.0), (0.0, 35.0), (0.0, -35.0),
            (50.0, 0.0), (-50.0, 0.0), (0.0, 50.0), (0.0, -50.0),
            (70.0, 0.0), (-70.0, 0.0), (0.0, 70.0), (0.0, -70.0),
            (90.0, 0.0), (-90.0, 0.0), (0.0, 90.0), (0.0, -90.0),
            (120.0, 0.0), (-120.0, 0.0), (0.0, 120.0), (0.0, -120.0),
            (160.0, 0.0), (-160.0, 0.0), (0.0, 160.0), (0.0, -160.0),
            # Diagonals
            (30.0, 30.0), (-30.0, 30.0), (30.0, -30.0), (-30.0, -30.0),
            (60.0, 60.0), (-60.0, 60.0), (60.0, -60.0), (-60.0, -60.0),
            (90.0, 90.0), (-90.0, 90.0), (90.0, -90.0), (-90.0, -90.0),
        ]

        # If obstructed by a specific door, add directional shifts away from door
        for dg in door_geoms:
            vec_x = orig_x - dg.cx
            vec_z = orig_z - dg.cz
            v_len = math.sqrt(vec_x ** 2 + vec_z ** 2)
            if v_len > 0.001:
                u_x = vec_x / v_len
                u_z = vec_z / v_len
                for push_dist in [30.0, 50.0, 75.0, 100.0, 130.0, 170.0]:
                    candidate_shifts.append((u_x * push_dist, u_z * push_dist))

        # Wall-aligned shifts: test sliding flush against perimeter walls
        half_w = w / 2.0
        half_d = d / 2.0
        wall_snap_positions = [
            # North wall (Z = half_d)
            (orig_x, half_d + 5.0),
            # South wall (Z = room_length - half_d - 5)
            (orig_x, room_length - half_d - 5.0),
            # West wall (X = half_w + 5)
            (half_w + 5.0, orig_z),
            # East wall (X = room_width - half_w - 5)
            (room_width - half_w - 5.0, orig_z)
        ]
        for wx, wz in wall_snap_positions:
            candidate_shifts.append((wx - orig_x, wz - orig_z))

        # Test rotation angles: original, +90°, +180°, +270°, 0°
        rotations_to_test = [orig_rot]
        for extra in [math.pi / 2.0, math.pi, 3 * math.pi / 2.0, 0.0]:
            normalized_rot = (orig_rot + extra) % (2 * math.pi)
            if not any(abs(normalized_rot - r) < 0.01 for r in rotations_to_test):
                rotations_to_test.append(normalized_rot)

        # 3. Evaluate each candidate
        valid_candidates = []

        for dx, dz in candidate_shifts:
            cand_x = round(orig_x + dx, 1)
            cand_z = round(orig_z + dz, 1)

            for cand_rot in rotations_to_test:
                cand_f = dict(target_f)
                cand_f['x'] = cand_x
                cand_f['z'] = cand_z
                cand_f['rotationY'] = cand_rot
                cand_obb = get_furniture_obb(cand_f)

                # A. Room Boundary Check (all corners inside room with 2cm tolerance)
                corners = cand_obb.get_corners()
                if any(cx < 2.0 or cx > room_width - 2.0 or cz < 2.0 or cz > room_length - 2.0 for cx, cz in corners):
                    continue

                # B. Collision Check against all other furniture
                has_collision = False
                for other_f, other_o in other_obbs:
                    overlap, depth, _ = obb_overlap_sat(cand_obb, other_o)
                    if overlap:
                        has_collision = True
                        break
                if has_collision:
                    continue

                # C. Door Swing & Threshold Check (must not block any door)
                blocks_door = False
                for dg in door_geoms:
                    is_obstr, cl, _ = dg.check_obstruction(cand_obb, dg.width)
                    if is_obstr and cl < dg.width * 0.9:
                        blocks_door = True
                        break
                if blocks_door:
                    continue

                # D. Usability Clearance Evaluation for the candidate
                cand_clearance, cand_required = cls._measure_clearance(
                    cand_f, issue_type, rule_id, other_furniture, doors, door_geoms,
                    room_width, room_length, min_walkway_clearance, require_both_sides_bed_access
                )

                # Candidate must strictly satisfy the required clearance
                if cand_clearance < cand_required:
                    continue

                # E. Calculate Cost / Score
                displacement = math.sqrt(dx * dx + dz * dz)
                # Angle difference
                diff_angle = abs(cand_rot - orig_rot)
                while diff_angle > math.pi:
                    diff_angle -= 2 * math.pi
                diff_angle = abs(diff_angle)

                # Wall affinity: storage furniture (wardrobes, cabinets, desks) prefers being against a wall
                f_name_lower = f_name.lower()
                is_storage = any(k in f_name_lower for k in ['wardrobe', 'cabinet', 'bookshelf', 'dresser', 'credenza', 'desk', 'bed'])
                wall_bonus = 0.0
                if is_storage:
                    dist_to_wall = min(
                        cand_x - cand_obb.ext_x,
                        room_width - (cand_x + cand_obb.ext_x),
                        cand_z - cand_obb.ext_z,
                        room_length - (cand_z + cand_obb.ext_z)
                    )
                    if dist_to_wall <= 15.0:
                        wall_bonus = 40.0

                # Score: prefer minimal displacement, minimal rotation change, higher clearance
                score = (
                    cand_clearance * 2.0 +
                    wall_bonus -
                    displacement * 1.5 -
                    diff_angle * 15.0
                )

                valid_candidates.append({
                    'candidate_f': cand_f,
                    'cand_x': cand_x,
                    'cand_z': cand_z,
                    'cand_rot': cand_rot,
                    'displacement': round(displacement, 1),
                    'rot_diff_deg': round(math.degrees(diff_angle), 0),
                    'clearance': cand_clearance,
                    'required': cand_required,
                    'score': score
                })

        # 4. Check if valid solution found
        if valid_candidates:
            # Sort by score descending
            valid_candidates.sort(key=lambda c: c['score'], reverse=True)
            best = valid_candidates[0]

            rot_msg = f" and rotated {int(best['rot_diff_deg'])}°" if best['rot_diff_deg'] > 5 else ""
            explanation = (
                f"Repositioned '{f_name}' by {int(best['displacement'])} cm{rot_msg} to satisfy the "
                f"{int(best['required'])} cm clearance requirement without introducing any collisions."
            )

            predicted_improvement = (
                f"Clearance increases from {int(before_clearance)} cm to {int(best['clearance'])} cm "
                f"(required {int(best['required'])} cm clearance achieved)."
            )

            changes = [
                ProposedFurnitureChange(
                    furniture_id=target_furniture_id,
                    name=f_name,
                    original_x=orig_x,
                    original_z=orig_z,
                    original_rotation=orig_rot,
                    proposed_x=best['cand_x'],
                    proposed_z=best['cand_z'],
                    proposed_rotation=best['cand_rot'],
                    displacement_cm=best['displacement']
                )
            ]

            return FixCandidateResponseData(
                room_id="",
                target_furniture_id=target_furniture_id,
                can_fix=True,
                explanation=explanation,
                issue_type=issue_type,
                rule_id=rule_id,
                changes=changes,
                measured_before=round(before_clearance, 1),
                measured_after=round(best['clearance'], 1),
                required_clearance=round(best['required'], 1),
                predicted_improvement=predicted_improvement,
                alternative_suggestions=[]
            )

        # 5. When no valid candidate exists
        alternatives = [
            f"Select a more compact furniture model (current footprint: {int(w)}x{int(d)} cm).",
            "Remove or relocate an optional item to free up clearance along this corridor.",
            "Adjust the configured walkway clearance setting in room options if a narrower path is acceptable."
        ]
        if 'bed' in f_name.lower():
            alternatives.insert(0, "Configure the room as a Single/Guest room to permit placing the bed against one wall.")

        fail_explanation = (
            f"Cannot resolve usability constraint for '{f_name}' without colliding with other furniture "
            f"or extending outside the {int(room_width)}x{int(room_length)} cm room boundaries. "
            f"The room area is physically too tight for this layout configuration."
        )

        return FixCandidateResponseData(
            room_id="",
            target_furniture_id=target_furniture_id,
            can_fix=False,
            explanation=fail_explanation,
            issue_type=issue_type,
            rule_id=rule_id,
            changes=[],
            measured_before=round(before_clearance, 1),
            measured_after=round(before_clearance, 1),
            required_clearance=round(before_required, 1),
            predicted_improvement="No automatic correction available without violating safety boundaries.",
            alternative_suggestions=alternatives
        )

    @classmethod
    def _measure_clearance(
        cls,
        f: Dict[str, Any],
        issue_type: Optional[str],
        rule_id: Optional[str],
        other_furniture: List[Dict[str, Any]],
        doors: List[Dict[str, Any]],
        door_geoms: List[Any],
        room_width: float,
        room_length: float,
        min_walkway_clearance: float,
        require_both_sides_bed_access: bool
    ) -> Tuple[float, float]:
        """
        Calculates the specific measured clearance and required clearance for the target furniture item.
        """
        obb = get_furniture_obb(f)
        f_name = f.get('name', '').lower()

        # A. Door Obstruction
        if issue_type in ['door_blocked', 'door_swing'] or rule_id == 'RULE_DOOR':
            min_cl = float('inf')
            req_cl = 80.0
            for dg in door_geoms:
                req_cl = max(req_cl, dg.width)
                is_obstr, cl, _ = dg.check_obstruction(obb, req_cl)
                if cl < min_cl:
                    min_cl = cl
            return (min_cl if min_cl != float('inf') else req_cl, req_cl)

        # B. Wardrobe / Cabinet Front Opening
        if issue_type == 'wardrobe_blocked' or any(k in f_name for k in ['wardrobe', 'cabinet', 'dresser']):
            req_cl = 75.0
            front_obb = get_furniture_clearance_obb(f, 'front', depth=req_cl)
            min_dist = req_cl
            for other in other_furniture:
                o2 = get_furniture_obb(other)
                overlap, depth, _ = obb_overlap_sat(front_obb, o2)
                if overlap:
                    min_dist = min(min_dist, max(0.0, req_cl - depth))
                else:
                    d = obb_distance(obb, o2)
                    if d < min_dist:
                        min_dist = d
            # Also check distance to wall in front
            front_corners = front_obb.get_corners()
            for cx, cz in front_corners:
                if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                    intrusion = max(-cx, cx - room_width, -cz, cz - room_length)
                    min_dist = min(min_dist, max(0.0, req_cl - intrusion))
            return (min_dist, req_cl)

        # C. Bed Side Clearance
        if issue_type == 'bed_access' or 'bed' in f_name:
            req_cl = 60.0
            left_obb = get_furniture_clearance_obb(f, 'left', depth=req_cl)
            right_obb = get_furniture_clearance_obb(f, 'right', depth=req_cl)

            left_cl = req_cl
            right_cl = req_cl

            for other in other_furniture:
                o2 = get_furniture_obb(other)
                # Ignore nightstands
                if any(k in other.get('name', '').lower() for k in ['stand', 'night', 'bedside']):
                    continue
                o_left, d_left, _ = obb_overlap_sat(left_obb, o2)
                if o_left:
                    left_cl = min(left_cl, max(0.0, req_cl - d_left))
                o_right, d_right, _ = obb_overlap_sat(right_obb, o2)
                if o_right:
                    right_cl = min(right_cl, max(0.0, req_cl - d_right))

            # Wall checks
            for cx, cz in left_obb.get_corners():
                if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                    intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                    left_cl = min(left_cl, max(0.0, req_cl - intrus))
            for cx, cz in right_obb.get_corners():
                if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                    intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                    right_cl = min(right_cl, max(0.0, req_cl - intrus))

            if require_both_sides_bed_access:
                return (min(left_cl, right_cl), req_cl)
            else:
                return (max(left_cl, right_cl), req_cl)

        # D. Dining Chair Pull-out Space
        if issue_type == 'dining_pullout' or 'chair' in f_name:
            req_cl = 60.0
            rear_obb = get_furniture_clearance_obb(f, 'rear', depth=req_cl)
            min_cl = req_cl
            for other in other_furniture:
                # Ignore table it's paired with
                if any(k in other.get('name', '').lower() for k in ['table', 'desk']):
                    continue
                o2 = get_furniture_obb(other)
                overlap, depth, _ = obb_overlap_sat(rear_obb, o2)
                if overlap:
                    min_cl = min(min_cl, max(0.0, req_cl - depth))
            for cx, cz in rear_obb.get_corners():
                if cx < 0 or cx > room_width or cz < 0 or cz > room_length:
                    intrus = max(-cx, cx - room_width, -cz, cz - room_length)
                    min_cl = min(min_cl, max(0.0, req_cl - intrus))
            return (min_cl, req_cl)

        # E. Walkway & Passage Clearance
        min_p_dist = float('inf')
        for other in other_furniture:
            o2 = get_furniture_obb(other)
            d = obb_distance(obb, o2)
            if d < min_p_dist:
                min_p_dist = d

        # Distance to perimeter walls
        corners = obb.get_corners()
        wall_dist = min(
            min(cx for cx, _ in corners),
            min(room_width - cx for cx, _ in corners),
            min(cz for _, cz in corners),
            min(room_length - cz for _, cz in corners)
        )
        if 15.0 < wall_dist < min_p_dist:
            min_p_dist = wall_dist

        effective = min(min_p_dist, min_walkway_clearance) if min_p_dist != float('inf') else min_walkway_clearance
        return (round(max(0.0, effective), 1), min_walkway_clearance)
