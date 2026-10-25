from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime

# Measurements DTOs
class RoomMeasurementData(BaseModel):
    length: float = Field(..., gt=0)
    width: float = Field(..., gt=0)
    height: float = Field(..., gt=0)
    floor_thickness: float = 30.0
    wall_thickness: float = 20.0
    ceiling_height: float = 300.0

class RoomMeasurementResponse(BaseModel):
    success: bool
    data: RoomMeasurementData

# Request DTOs
class RoomCreate(BaseModel):
    room_name: str = Field(..., min_length=1, max_length=100)
    room_type: str = Field(..., min_length=1, max_length=50)
    floor_number: int = 1
    notes: Optional[str] = None
    room_color: str = "#FFFFFF"
    properties: Optional[str] = None # JSON string

class RoomUpdate(BaseModel):
    room_name: Optional[str] = Field(None, min_length=1, max_length=100)
    room_type: Optional[str] = Field(None, min_length=1, max_length=50)
    floor_number: Optional[int] = None
    notes: Optional[str] = None
    room_color: Optional[str] = None
    properties: Optional[str] = None

# Response DTOs
class RoomListItem(BaseModel):
    id: str
    project_id: str
    room_name: str
    room_type: str
    floor_number: int
    notes: Optional[str] = None
    room_color: str
    properties: Optional[str] = None
    created_at: datetime
    updated_at: datetime

class RoomDetailsData(BaseModel):
    id: str
    project_id: str
    room_name: str
    room_type: str
    floor_number: int
    notes: Optional[str] = None
    room_color: str
    properties: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    measurements: Optional[RoomMeasurementData] = None

class RoomDetailsResponse(BaseModel):
    success: bool
    data: RoomDetailsData

class RoomListResponse(BaseModel):
    success: bool
    data: List[RoomListItem]

class RoomResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Any] = None

class RoomLayoutResponse(BaseModel):
    success: bool
    layout_data: Optional[str] = None
