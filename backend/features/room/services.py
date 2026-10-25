import json
from datetime import datetime, timezone
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from features.room.models import Room, RoomMeasurement
from features.project.models import Project
from features.auth.models import AuditLog

class RoomService:
    @staticmethod
    def get_project(db: Session, user_id: str, project_id: str) -> Project:
        project = db.query(Project).filter(
            Project.id == project_id,
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).first()
        if not project:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found"
            )
        return project

    @classmethod
    def create_room(cls, db: Session, user_id: str, project_id: str, room_data) -> Room:
        # Verify project ownership
        project = cls.get_project(db, user_id, project_id)
        
        # Create Room
        new_room = Room(
            project_id=project_id,
            room_name=room_data.room_name,
            room_type=room_data.room_type,
            floor_number=room_data.floor_number,
            notes=room_data.notes,
            room_color=room_data.room_color,
            properties=room_data.properties
        )
        db.add(new_room)
        db.commit()
        db.refresh(new_room)
        
        # Create Default RoomMeasurement
        default_measure = RoomMeasurement(room_id=new_room.id)
        db.add(default_measure)
        
        # Audit Log
        audit = AuditLog(
            user_id=user_id,
            action="ROOM_CREATE",
            details=f"Room '{new_room.room_name}' added to project '{project.project_name}'."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(new_room)
        return new_room

    @classmethod
    def get_rooms(cls, db: Session, user_id: str, project_id: str) -> list[Room]:
        # Verify project ownership
        cls.get_project(db, user_id, project_id)
        return db.query(Room).filter(Room.project_id == project_id).all()

    @staticmethod
    def get_room_details(db: Session, user_id: str, room_id: str) -> Room:
        room = db.query(Room).join(Project).filter(
            Room.id == room_id,
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).first()
        
        if not room:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Room not found"
            )
        return room

    @classmethod
    def update_room(cls, db: Session, user_id: str, room_id: str, room_data) -> Room:
        room = cls.get_room_details(db, user_id, room_id)
        
        if room_data.room_name is not None:
            room.room_name = room_data.room_name
        if room_data.room_type is not None:
            room.room_type = room_data.room_type
        if room_data.floor_number is not None:
            room.floor_number = room_data.floor_number
        if room_data.notes is not None:
            room.notes = room_data.notes
        if room_data.room_color is not None:
            room.room_color = room_data.room_color
        if room_data.properties is not None:
            try:
                import json
                from features.ai.geometry import generate_room_geometry
                props = json.loads(room_data.properties)
                
                walls = props.get("walls", [])
                openings = props.get("openings", [])
                
                if (not walls or not openings) and room.measurements:
                    num_doors = int(props.get("doors") or 0)
                    num_windows = int(props.get("windows") or 0)
                    room_w = room.measurements.length
                    room_l = room.measurements.width
                    
                    gen_walls, gen_openings = generate_room_geometry(
                        room_w, room_l, num_doors, num_windows, room.measurements.wall_thickness
                    )
                    
                    if not walls:
                        props["walls"] = gen_walls
                    if not openings:
                        props["openings"] = gen_openings
                        
                    room_data.properties = json.dumps(props)
            except Exception:
                pass
            room.properties = room_data.properties
            
        room.updated_at = datetime.now(timezone.utc)
        
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="ROOM_UPDATE",
            details=f"Room '{room.room_name}' updated."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(room)
        return room

    @classmethod
    def delete_room(cls, db: Session, user_id: str, room_id: str) -> None:
        room = cls.get_room_details(db, user_id, room_id)
        
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="ROOM_DELETE",
            details=f"Room '{room.room_name}' deleted."
        )
        db.add(audit)
        
        db.delete(room)
        db.commit()

    @classmethod
    def duplicate_room(cls, db: Session, user_id: str, room_id: str) -> Room:
        source_room = cls.get_room_details(db, user_id, room_id)
        
        dup_name = f"{source_room.room_name} (Copy)"
        if len(dup_name) > 100:
            dup_name = f"{source_room.room_name[:80]} (Copy)"
            
        # Create Room
        dup_room = Room(
            project_id=source_room.project_id,
            room_name=dup_name,
            room_type=source_room.room_type,
            floor_number=source_room.floor_number,
            notes=source_room.notes,
            room_color=source_room.room_color,
            properties=source_room.properties
        )
        db.add(dup_room)
        db.commit()
        db.refresh(dup_room)
        
        # Duplicate measurements
        if source_room.measurements:
            dup_measure = RoomMeasurement(
                room_id=dup_room.id,
                length=source_room.measurements.length,
                width=source_room.measurements.width,
                height=source_room.measurements.height,
                floor_thickness=source_room.measurements.floor_thickness,
                wall_thickness=source_room.measurements.wall_thickness,
                ceiling_height=source_room.measurements.ceiling_height
            )
            db.add(dup_measure)
            
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="ROOM_DUPLICATE",
            details=f"Room '{source_room.room_name}' duplicated as '{dup_name}'."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(dup_room)
        return dup_room

    @classmethod
    def get_measurements(cls, db: Session, user_id: str, room_id: str) -> RoomMeasurement:
        room = cls.get_room_details(db, user_id, room_id)
        if not room.measurements:
            # Create default if not present
            measure = RoomMeasurement(room_id=room_id)
            db.add(measure)
            db.commit()
            db.refresh(measure)
            return measure
        return room.measurements

    @classmethod
    def update_measurements(cls, db: Session, user_id: str, room_id: str, measure_data) -> RoomMeasurement:
        measure = cls.get_measurements(db, user_id, room_id)
        
        measure.length = measure_data.length
        measure.width = measure_data.width
        measure.height = measure_data.height
        if measure_data.floor_thickness is not None:
            measure.floor_thickness = measure_data.floor_thickness
        if measure_data.wall_thickness is not None:
            measure.wall_thickness = measure_data.wall_thickness
        if measure_data.ceiling_height is not None:
            measure.ceiling_height = measure_data.ceiling_height
            
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="ROOM_MEASUREMENTS_UPDATE",
            details=f"Room measurements updated (length: {measure.length}, width: {measure.width}, height: {measure.height})."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(measure)
        return measure

    @classmethod
    def get_full_floor_layout(cls, db: Session, user_id: str, project_id: str) -> dict:
        rooms = cls.get_rooms(db, user_id, project_id)
        if not rooms:
            return {
                "project_id": project_id,
                "total_rooms": 0,
                "total_area": 0.0,
                "total_furniture": 0,
                "overall_score": 100,
                "status": "SAFE",
                "rooms": [],
                "walls": [],
                "openings": [],
                "furniture": []
            }

        combined_walls = []
        combined_openings = []
        combined_furniture = []
        room_summaries = []
        
        total_area_sqm = 0.0
        total_furniture_count = 0
        total_score_sum = 0.0
        has_collisions = False
        
        # Grid placement layout parameters for multi-room synthesis
        current_offset_x = 0.0
        current_offset_z = 0.0
        max_row_height = 0.0
        columns = 2
        col_index = 0
        gap = 60.0 # 60cm gap between separate room blocks

        for room in rooms:
            room_w = room.measurements.width if (room.measurements and room.measurements.width) else 450.0
            room_l = room.measurements.length if (room.measurements and room.measurements.length) else 390.0
            room_h = room.measurements.height if (room.measurements and room.measurements.height) else 280.0
            
            area = (room_w * room_l) / 10000.0
            total_area_sqm += area

            props = {}
            if room.properties:
                try:
                    props = json.loads(room.properties)
                except Exception:
                    pass

            walls = props.get("walls", [])
            openings = props.get("openings", [])
            furniture = props.get("furniture", [])

            if not walls:
                from features.ai.geometry import generate_room_geometry
                walls, openings = generate_room_geometry(room_w, room_l, 1, 1)

            # Offset room geometry onto house floor plan
            off_x = current_offset_x
            off_z = current_offset_z

            for w in walls:
                x1 = w.get("x1")
                y1 = w.get("y1")
                x2 = w.get("x2")
                y2 = w.get("y2")
                if x1 is None and "start" in w:
                    start = w["start"]
                    end = w.get("end", {})
                    if isinstance(start, dict):
                        x1 = start.get("x", 0.0)
                        y1 = start.get("y", 0.0)
                    elif isinstance(start, (list, tuple)) and len(start) >= 2:
                        x1 = start[0]
                        y1 = start[1]
                    if isinstance(end, dict):
                        x2 = end.get("x", 0.0)
                        y2 = end.get("y", 0.0)
                    elif isinstance(end, (list, tuple)) and len(end) >= 2:
                        x2 = end[0]
                        y2 = end[1]
                
                x1 = float(x1 or 0.0)
                y1 = float(y1 or 0.0)
                x2 = float(x2 or 0.0)
                y2 = float(y2 or 0.0)

                combined_walls.append({
                    "x1": x1 + off_x,
                    "y1": y1 + off_z,
                    "x2": x2 + off_x,
                    "y2": y2 + off_z,
                    "thickness": w.get("thickness", 15.0)
                })

            for op in openings:
                combined_openings.append({
                    "id": f"{room.id}_{op.get('id', 'op')}",
                    "type": op.get("type", "door"),
                    "x": op.get("x", 0.0) + off_x,
                    "y": op.get("y", 0.0) + off_z,
                    "width": op.get("width", 90.0),
                    "angle": op.get("angle", 0.0)
                })

            for f in furniture:
                total_furniture_count += 1
                f_copy = dict(f)
                f_copy["x"] = f.get("x", 0.0) + off_x
                f_copy["z"] = f.get("z", 0.0) + off_z
                f_copy["room_id"] = room.id
                combined_furniture.append(f_copy)

            # Analytics score
            from features.ai.models import Analytics
            analytic = db.query(Analytics).filter(Analytics.room_id == room.id).first()
            room_score = analytic.overall_score if analytic else 85
            total_score_sum += room_score

            room_summaries.append({
                "id": room.id,
                "name": room.room_name,
                "type": room.room_type,
                "width": room_w,
                "length": room_l,
                "height": room_h,
                "offset_x": off_x,
                "offset_z": off_z,
                "area_sqm": round(area, 1),
                "furniture_count": len(furniture),
                "score": room_score,
                "status": "SAFE"
            })

            # Update grid layout position
            col_index += 1
            max_row_height = max(max_row_height, room_l)
            if col_index >= columns:
                current_offset_x = 0.0
                current_offset_z += max_row_height + gap
                max_row_height = 0.0
                col_index = 0
            else:
                current_offset_x += room_w + gap

        avg_score = int(total_score_sum / len(rooms)) if rooms else 100
        overall_status = "COLLISION" if has_collisions else "SAFE"

        return {
            "project_id": project_id,
            "total_rooms": len(rooms),
            "total_area": round(total_area_sqm, 1),
            "total_furniture": total_furniture_count,
            "overall_score": avg_score,
            "status": overall_status,
            "rooms": room_summaries,
            "walls": combined_walls,
            "openings": combined_openings,
            "furniture": combined_furniture
        }

