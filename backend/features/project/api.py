from fastapi import APIRouter, Depends, status, Query
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user
from features.project.schemas import (
    ProjectCreate, ProjectUpdate, ProjectDetailsResponse, ProjectDetailsData,
    ProjectListResponse, ProjectListItem, ProjectResponse, DashboardSummaryResponse, DashboardSummaryData, ProjectSettingData
)
from features.project.services import ProjectService
from features.auth.models import User

router = APIRouter(tags=["Projects"])

def map_project_to_list_item(p) -> ProjectListItem:
    return ProjectListItem(
        id=p.id,
        project_name=p.project_name,
        description=p.description,
        location=p.location,
        status=p.status,
        is_favorite=p.is_favorite,
        rooms=len(p.rooms),
        created_at=p.created_at,
        updated_at=p.updated_at
    )

@router.post("/projects", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
def create_project(
    project_data: ProjectCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = ProjectService.create_project(db, current_user.id, project_data)
    return ProjectResponse(
        success=True,
        message="Project created successfully.",
        data={"project_id": project.id}
    )

@router.get("/projects", response_model=ProjectListResponse)
def get_projects(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: str = Query(None),
    search: str = Query(None),
    sort: str = Query("created_at"),
    favorite: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    projects, _ = ProjectService.get_projects(
        db, current_user.id, page, limit, status, search, sort, favorite
    )
    return ProjectListResponse(
        success=True,
        data=[map_project_to_list_item(p) for p in projects]
    )

from features.room.schemas import RoomListItem

@router.get("/projects/{project_id}", response_model=ProjectDetailsResponse)
def get_project_details(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    p = ProjectService.get_project_details(db, current_user.id, project_id)
    return ProjectDetailsResponse(
        success=True,
        data=ProjectDetailsData(
            id=p.id,
            project_name=p.project_name,
            description=p.description,
            location=p.location,
            status=p.status,
            is_favorite=p.is_favorite,
            created_at=p.created_at,
            updated_at=p.updated_at,
            settings=ProjectSettingData(
                default_style=p.settings.default_style if p.settings else None,
                measurement_unit=p.settings.measurement_unit if p.settings else "Centimeters",
                grid_enabled=p.settings.grid_enabled if p.settings else True,
                snap_enabled=p.settings.snap_enabled if p.settings else True
            ) if p.settings else None,
            rooms=[
                RoomListItem(
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
                ) for r in p.rooms
            ]
        )
    )

@router.put("/projects/{project_id}", response_model=ProjectResponse)
def update_project(
    project_id: str,
    project_data: ProjectUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = ProjectService.update_project(db, current_user.id, project_id, project_data)
    return ProjectResponse(
        success=True,
        message="Project updated successfully.",
        data={"project_id": project.id}
    )

@router.delete("/projects/{project_id}", response_model=ProjectResponse)
def delete_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    ProjectService.soft_delete_project(db, current_user.id, project_id)
    return ProjectResponse(
        success=True,
        message="Project archived successfully." # Return standard API spec archived message
    )

@router.post("/projects/{project_id}/duplicate", response_model=ProjectResponse)
def duplicate_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = ProjectService.duplicate_project(db, current_user.id, project_id)
    return ProjectResponse(
        success=True,
        message="Project duplicated successfully.",
        data={"project_id": project.id}
    )

@router.patch("/projects/{project_id}/archive", response_model=ProjectResponse)
def archive_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = ProjectService.archive_project(db, current_user.id, project_id)
    return ProjectResponse(
        success=True,
        message="Project archived successfully.",
        data={"project_id": project.id}
    )

@router.patch("/projects/{project_id}/restore", response_model=ProjectResponse)
def restore_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = ProjectService.restore_project(db, current_user.id, project_id)
    return ProjectResponse(
        success=True,
        message="Project restored successfully.",
        data={"project_id": project.id}
    )

@router.patch("/projects/{project_id}/toggle-favorite", response_model=ProjectResponse)
def toggle_favorite(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    p = ProjectService.get_project_details(db, current_user.id, project_id)
    p.is_favorite = not p.is_favorite
    db.commit()
    return ProjectResponse(
        success=True,
        message="Project favorite toggled successfully.",
        data={"is_favorite": p.is_favorite}
    )

@router.get("/dashboard", response_model=DashboardSummaryResponse)
def get_dashboard(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    summary = ProjectService.get_dashboard_summary(db, current_user)
    return DashboardSummaryResponse(
        success=True,
        data=DashboardSummaryData(
            welcome_message=summary["welcome_message"],
            total_projects=summary["total_projects"],
            total_rooms=summary["total_rooms"],
            recent_projects=[map_project_to_list_item(p) for p in summary["recent_projects"]],
            favorite_projects=[map_project_to_list_item(p) for p in summary["favorite_projects"]],
            recent_activity=summary["recent_activity"],
            ai_recommendations=summary["ai_recommendations"],
            analytics_summary=summary["analytics_summary"],
            notifications=summary["notifications"]
        )
    )
