from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user
from features.room.schemas import (
    RoomCreate, RoomUpdate, RoomListItem, RoomDetailsResponse, RoomDetailsData,
    RoomListResponse, RoomResponse, RoomMeasurementData, RoomMeasurementResponse,
    RoomLayoutResponse
)
from features.room.services import RoomService
from features.auth.models import User

router = APIRouter(tags=["Rooms"])

def map_room_to_list_item(r) -> RoomListItem:
    return RoomListItem(
        id=r.id,
        project_id=r.project_id,
        room_name=r.room_name,
        room_type=r.room_type,
        floor_number=r.floor_number,
        notes=r.notes,
        room_color=r.room_color,
        properties=r.properties,
        created_at=r.created_at,
        updated_at=r.updated_at
    )

@router.post("/projects/{project_id}/rooms", response_model=RoomResponse, status_code=status.HTTP_201_CREATED)
def create_room(
    project_id: str,
    room_data: RoomCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = RoomService.create_room(db, current_user.id, project_id, room_data)
    return RoomResponse(
        success=True,
        message="Room added successfully.",
        data={"room_id": room.id}
    )

@router.get("/projects/{project_id}/rooms", response_model=RoomListResponse)
def get_rooms(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    rooms = RoomService.get_rooms(db, current_user.id, project_id)
    return RoomListResponse(
        success=True,
        data=[map_room_to_list_item(r) for r in rooms]
    )

@router.get("/rooms/{room_id}", response_model=RoomDetailsResponse)
def get_room_details(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    r = RoomService.get_room_details(db, current_user.id, room_id)
    return RoomDetailsResponse(
        success=True,
        data=RoomDetailsData(
            id=r.id,
            project_id=r.project_id,
            room_name=r.room_name,
            room_type=r.room_type,
            floor_number=r.floor_number,
            notes=r.notes,
            room_color=r.room_color,
            properties=r.properties,
            created_at=r.created_at,
            updated_at=r.updated_at,
            measurements=RoomMeasurementData(
                length=r.measurements.length,
                width=r.measurements.width,
                height=r.measurements.height,
                floor_thickness=r.measurements.floor_thickness,
                wall_thickness=r.measurements.wall_thickness,
                ceiling_height=r.measurements.ceiling_height
            ) if r.measurements else None
        )
    )

@router.put("/rooms/{room_id}", response_model=RoomResponse)
def update_room(
    room_id: str,
    room_data: RoomUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = RoomService.update_room(db, current_user.id, room_id, room_data)
    return RoomResponse(
        success=True,
        message="Room updated successfully.",
        data={"room_id": room.id}
    )

@router.delete("/rooms/{room_id}", response_model=RoomResponse)
def delete_room(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    RoomService.delete_room(db, current_user.id, room_id)
    return RoomResponse(
        success=True,
        message="Room deleted successfully."
    )

@router.post("/rooms/{room_id}/duplicate", response_model=RoomResponse)
def duplicate_room(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = RoomService.duplicate_room(db, current_user.id, room_id)
    return RoomResponse(
        success=True,
        message="Room duplicated successfully.",
        data={"room_id": room.id}
    )

@router.get("/rooms/{room_id}/measurements", response_model=RoomMeasurementResponse)
def get_measurements(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    m = RoomService.get_measurements(db, current_user.id, room_id)
    return RoomMeasurementResponse(
        success=True,
        data=RoomMeasurementData(
            length=m.length,
            width=m.width,
            height=m.height,
            floor_thickness=m.floor_thickness,
            wall_thickness=m.wall_thickness,
            ceiling_height=m.ceiling_height
        )
    )

@router.put("/rooms/{room_id}/measurements", response_model=RoomResponse)
def update_measurements(
    room_id: str,
    measure_data: RoomMeasurementData,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    m = RoomService.update_measurements(db, current_user.id, room_id, measure_data)
    return RoomResponse(
        success=True,
        message="Measurements updated successfully."
    )

@router.get("/rooms/{room_id}/layout", response_model=RoomLayoutResponse)
def get_room_layout(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from features.room.schemas import RoomLayoutResponse
    room = RoomService.get_room_details(db, current_user.id, room_id)
    return RoomLayoutResponse(
        success=True,
        layout_data=room.properties
    )

@router.put("/rooms/{room_id}/layout", response_model=RoomResponse)
def save_room_layout(
    room_id: str,
    layout_update: RoomLayoutResponse,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = RoomService.get_room_details(db, current_user.id, room_id)
    room.properties = layout_update.layout_data
    db.commit()

    # Save to Design History
    from features.ai.models import DesignHistory
    from sqlalchemy import func
    max_ver = db.query(func.max(DesignHistory.version_number)).filter(DesignHistory.room_id == room_id).scalar()
    next_ver = (max_ver or 0) + 1
    
    history_entry = DesignHistory(
        room_id=room_id,
        version_number=next_ver,
        snapshot_json=layout_update.layout_data,
        summary=f"Layout updated to Version {next_ver}"
    )
    db.add(history_entry)
    db.commit()

    # Re-calculate and save analytics
    from features.analytics.service import AnalyticsService
    try:
        AnalyticsService.ensure_room_scores(db, room)
    except Exception:
        pass  # If measurements don't exist yet, skip scoring calculation

    return RoomResponse(
        success=True,
        message="Room layout saved successfully."
    )

@router.get("/projects/{project_id}/full-floor")
def get_full_floor_layout(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    layout = RoomService.get_full_floor_layout(db, current_user.id, project_id)
    return {
        "success": True,
        "data": layout
    }


