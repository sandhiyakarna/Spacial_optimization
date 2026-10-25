from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime

class ReportGenerateRequest(BaseModel):
    project_id: str
    room_id: Optional[str] = None
    report_type: str # "Design Report", "Analytics Report", "Validation Report", "Recommendation Report"
    format: Optional[str] = "PDF" # PDF, PNG, JSON

class ReportGenerateResponseData(BaseModel):
    report_id: str

class ReportGenerateResponse(BaseModel):
    success: bool
    message: str
    data: ReportGenerateResponseData

class ReportStatusData(BaseModel):
    status: str # Pending, Running, Completed, Failed

class ReportStatusResponse(BaseModel):
    success: bool
    data: ReportStatusData

class ReportHistoryItem(BaseModel):
    id: str
    project_id: str
    room_id: Optional[str] = None
    report_type: str
    status: str
    file_size: int
    format: str
    created_at: datetime

    class Config:
        from_attributes = True

class ReportHistoryResponse(BaseModel):
    success: bool
    data: List[ReportHistoryItem]

class ProjectExportRequest(BaseModel):
    project_id: str
    format: str # JSON, PDF, PNG

class RoomExportRequest(BaseModel):
    room_id: str
    format: str # JSON, PDF, PNG

class ExportResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
