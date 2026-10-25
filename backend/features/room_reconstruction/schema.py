from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional
from features.room_reconstruction.spatial_model import RoomSpatialModel

class PanoramaUploadResponse(BaseModel):
    success: bool
    scan_id: str
    message: str
    frame_count: int

class PanoramaProcessRequest(BaseModel):
    scan_id: str
    room_id: str
    room_type: str = "Living Room"
    known_width_cm: Optional[float] = None
    known_depth_cm: Optional[float] = None
    known_height_cm: Optional[float] = None

class PanoramaProcessResponse(BaseModel):
    success: bool
    status: str
    room_id: str
    scan_id: str
    spatial_model: RoomSpatialModel
    blueprint_quality_score: int
    message: str

class ScanStatusResponse(BaseModel):
    scan_id: str
    status: str
    frame_count: int
    coverage_pct: float
    average_lighting: str
    stability: str
    quality_score: int
    errors: List[str] = []

class BlueprintGenerateRequest(BaseModel):
    spatial_model: RoomSpatialModel
    show_measurements: bool = True
    show_furniture_labels: bool = True
    show_doors: bool = True
    show_windows: bool = True

class BlueprintGenerateResponse(BaseModel):
    success: bool
    scan_id: str
    quality_score: int
    blueprint_url: str
    message: str

class BlueprintJsonResponse(BaseModel):
    scan_id: str
    status: str
    room: Dict[str, float]
    walls: List[Dict[str, Any]]
    doors: List[Dict[str, Any]]
    windows: List[Dict[str, Any]]
    furniture: List[Dict[str, Any]]
    blueprint: Dict[str, Any]
