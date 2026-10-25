from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime

# Request DTOs
class ProjectCreate(BaseModel):
    project_name: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = None
    location: Optional[str] = None

class ProjectUpdate(BaseModel):
    project_name: Optional[str] = Field(None, min_length=1, max_length=120)
    description: Optional[str] = None
    location: Optional[str] = None
    status: Optional[str] = None
    is_favorite: Optional[bool] = None

# Response DTOs
class ProjectSettingData(BaseModel):
    default_style: Optional[str] = None
    measurement_unit: str = "Centimeters"
    grid_enabled: bool = True
    snap_enabled: bool = True

class ProjectListItem(BaseModel):
    id: str
    project_name: str
    description: Optional[str] = None
    location: Optional[str] = None
    status: str
    is_favorite: bool
    rooms: int
    created_at: datetime
    updated_at: datetime

class ProjectDetailsData(BaseModel):
    id: str
    project_name: str
    description: Optional[str] = None
    location: Optional[str] = None
    status: str
    is_favorite: bool
    created_at: datetime
    updated_at: datetime
    settings: Optional[ProjectSettingData] = None
    rooms: List[Any] = []

class ProjectDetailsResponse(BaseModel):
    success: bool
    data: ProjectDetailsData

class ProjectListResponse(BaseModel):
    success: bool
    data: List[ProjectListItem]

class ProjectResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Any] = None

# Dashboard Schemas
class DashboardSummaryData(BaseModel):
    welcome_message: str
    total_projects: int
    total_rooms: int
    recent_projects: List[ProjectListItem]
    favorite_projects: List[ProjectListItem]
    recent_activity: List[dict]
    ai_recommendations: List[dict]
    analytics_summary: dict
    notifications: List[dict]

class DashboardSummaryResponse(BaseModel):
    success: bool
    data: DashboardSummaryData
