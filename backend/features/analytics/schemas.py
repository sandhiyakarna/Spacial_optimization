from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class CompareLayoutsRequest(BaseModel):
    layout_a: str
    layout_b: str

class CompareLayoutsResponseData(BaseModel):
    improvement: bool
    score_difference: float
    winner: str
    recommendations: List[str]

class CompareLayoutsResponse(BaseModel):
    success: bool
    data: CompareLayoutsResponseData

class AnalyticsDashboardData(BaseModel):
    accessibility_score: float
    lighting_score: float
    comfort_score: float
    balance_score: float
    space_utilization: float
    overall_score: float

class AnalyticsDashboardResponse(BaseModel):
    success: bool
    data: AnalyticsDashboardData

class AnalyticsDetailedScoresData(BaseModel):
    accessibility_score: float
    lighting_score: float
    ergonomic_score: float
    space_utilization_score: float
    furniture_balance_score: float
    overall_score: float
    subscores: Dict[str, float]

class AnalyticsDetailedScoresResponse(BaseModel):
    success: bool
    data: AnalyticsDetailedScoresData

class HistoryRestoreRequest(BaseModel):
    room_id: str
    version_number: int

class HistoryRestoreResponse(BaseModel):
    success: bool
    message: str
    data: Dict[str, Any]

class DesignHistoryItem(BaseModel):
    id: str
    version_number: int
    overall_score: float
    accessibility_score: float
    lighting_score: float
    ergonomic_score: float
    space_utilization_score: float
    furniture_balance_score: float
    created_at: datetime
    summary: str

class DesignHistoryResponse(BaseModel):
    success: bool
    data: List[DesignHistoryItem]

class RoomStatisticsData(BaseModel):
    furniture_count: int
    occupied_area: float
    free_area: float
    walkway_coverage: float
    average_clearance: float
    estimated_cost: float

class RoomStatisticsResponse(BaseModel):
    success: bool
    data: RoomStatisticsData

class DesignInsightsResponse(BaseModel):
    success: bool
    data: List[str]

class ProjectRoomScore(BaseModel):
    room_id: str
    room_name: str
    room_type: str
    overall_score: float

class ProjectAnalyticsData(BaseModel):
    project_id: str
    average_overall_score: float
    total_rooms: int
    total_furniture_count: int
    total_occupied_area: float
    total_free_area: float
    room_scores: List[ProjectRoomScore]

class ProjectAnalyticsResponse(BaseModel):
    success: bool
    data: ProjectAnalyticsData

# System Telemetry & Admin Analytics
class ActiveUsersTelemetry(BaseModel):
    total_users: int
    active_users_count: int
    trend_percentage: float

class MostUsedFurnitureItem(BaseModel):
    name: str
    category: str
    count: int

class FurnitureUsageTelemetry(BaseModel):
    total_assets: int
    most_used: List[MostUsedFurnitureItem]
    categories_breakdown: Dict[str, int]

class ProjectStatisticsTelemetry(BaseModel):
    total_projects: int
    total_rooms: int
    average_rooms_per_project: float
    average_design_score: float

class AIUsageTelemetry(BaseModel):
    total_jobs: int
    success_rate: float
    avg_latency_seconds: float
    jobs_by_status: Dict[str, int]
    jobs_by_type: Dict[str, int]

class StorageUsageTelemetry(BaseModel):
    total_used_bytes: float
    reports_used_bytes: float
    uploads_used_bytes: float
    limit_bytes: float

class ExportStatisticsTelemetry(BaseModel):
    total_exports: int
    exports_by_format: Dict[str, int]
    exports_by_type: Dict[str, int]

class TrendDataPoint(BaseModel):
    date: str
    count: int

class ChartsTelemetry(BaseModel):
    dau_trend: List[TrendDataPoint]
    projects_trend: List[TrendDataPoint]
    ai_jobs_trend: List[TrendDataPoint]

class SystemTelemetryData(BaseModel):
    active_users: ActiveUsersTelemetry
    furniture_usage: FurnitureUsageTelemetry
    project_statistics: ProjectStatisticsTelemetry
    ai_usage: AIUsageTelemetry
    storage_usage: StorageUsageTelemetry
    export_statistics: ExportStatisticsTelemetry
    charts: ChartsTelemetry

class SystemTelemetryResponse(BaseModel):
    success: bool
    data: SystemTelemetryData

