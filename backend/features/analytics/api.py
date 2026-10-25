from fastapi import APIRouter, Depends, status, HTTPException
from sqlalchemy.orm import Session
from app.dependencies import get_db, RoleChecker
from features.auth.models import User
from features.room.models import Room
from features.project.models import Project
from features.ai.models import DesignHistory
from features.analytics.schemas import (
    AnalyticsDashboardResponse, AnalyticsDashboardData,
    AnalyticsDetailedScoresResponse, AnalyticsDetailedScoresData,
    CompareLayoutsRequest, CompareLayoutsResponse, CompareLayoutsResponseData,
    DesignHistoryResponse, DesignHistoryItem,
    RoomStatisticsResponse, RoomStatisticsData,
    DesignInsightsResponse,
    ProjectAnalyticsResponse, ProjectAnalyticsData,
    HistoryRestoreRequest, HistoryRestoreResponse,
    SystemTelemetryResponse, SystemTelemetryData
)
from features.analytics.service import AnalyticsService

router = APIRouter(prefix="/analytics", tags=["Analytics"])

# Helper to verify room ownership
def verify_room_owner(db: Session, room_id: str, user_id: str) -> Room:
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Room not found"
        )
    if room.project.user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )
    return room

# Helper to verify project ownership
def verify_project_owner(db: Session, project_id: str, user_id: str) -> Project:
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )
    if project.user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )
    return project

@router.get("/{room_id}", response_model=AnalyticsDashboardResponse)
def get_analytics_dashboard(
    room_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, room_id, current_user.id)
    data = AnalyticsService.get_analytics_dashboard(db, room_id)
    return AnalyticsDashboardResponse(
        success=True,
        data=AnalyticsDashboardData(**data)
    )

@router.get("/{room_id}/scores", response_model=AnalyticsDetailedScoresResponse)
def get_detailed_scores(
    room_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, room_id, current_user.id)
    data = AnalyticsService.get_detailed_scores(db, room_id)
    return AnalyticsDetailedScoresResponse(
        success=True,
        data=AnalyticsDetailedScoresData(**data)
    )

@router.post("/compare", response_model=CompareLayoutsResponse)
def compare_layouts(
    request: CompareLayoutsRequest,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    # Verify ownership of layout A
    room_a = db.query(Room).filter(Room.id == request.layout_a).first()
    if room_a:
        if room_a.project.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    else:
        dh_a = db.query(DesignHistory).filter(DesignHistory.id == request.layout_a).first()
        if not dh_a or dh_a.room.project.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    # Verify ownership of layout B
    room_b = db.query(Room).filter(Room.id == request.layout_b).first()
    if room_b:
        if room_b.project.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    else:
        dh_b = db.query(DesignHistory).filter(DesignHistory.id == request.layout_b).first()
        if not dh_b or dh_b.room.project.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    data = AnalyticsService.compare_layouts(db, request.layout_a, request.layout_b)
    return CompareLayoutsResponse(
        success=True,
        data=CompareLayoutsResponseData(**data)
    )

@router.get("/history/{room_id}", response_model=DesignHistoryResponse)
def get_history(
    room_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, room_id, current_user.id)
    data = AnalyticsService.get_history(db, room_id)
    return DesignHistoryResponse(
        success=True,
        data=[DesignHistoryItem(**item) for item in data]
    )

@router.get("/statistics/{room_id}", response_model=RoomStatisticsResponse)
def get_statistics(
    room_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, room_id, current_user.id)
    data = AnalyticsService.get_statistics(db, room_id)
    return RoomStatisticsResponse(
        success=True,
        data=RoomStatisticsData(**data)
    )

@router.get("/insights/{room_id}", response_model=DesignInsightsResponse)
def get_insights(
    room_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, room_id, current_user.id)
    data = AnalyticsService.get_insights(db, room_id)
    return DesignInsightsResponse(
        success=True,
        data=data
    )

@router.get("/project/{project_id}", response_model=ProjectAnalyticsResponse)
def get_project_analytics(
    project_id: str,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_project_owner(db, project_id, current_user.id)
    data = AnalyticsService.get_project_analytics(db, project_id)
    return ProjectAnalyticsResponse(
        success=True,
        data=ProjectAnalyticsData(**data)
    )

@router.post("/history/restore", response_model=HistoryRestoreResponse)
def restore_history(
    request: HistoryRestoreRequest,
    current_user: User = Depends(RoleChecker(["Administrator", "Interior Designer", "Architect", "Customer"])),
    db: Session = Depends(get_db)
):
    verify_room_owner(db, request.room_id, current_user.id)
    res = AnalyticsService.restore_history(db, request.room_id, request.version_number)
    return HistoryRestoreResponse(
        success=True,
        message=res["message"],
        data=res["data"]
    )

@router.get("/admin/system", response_model=SystemTelemetryResponse)
def get_system_telemetry(
    period: str = "7d",
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    data = AnalyticsService.get_system_telemetry(db, period)
    return SystemTelemetryResponse(
        success=True,
        data=SystemTelemetryData(**data)
    )

