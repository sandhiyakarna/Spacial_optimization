from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class LayoutGenerationRequest(BaseModel):
    room_id: str
    style: str = "Modern"
    preferences: Optional[List[str]] = []
    seed: Optional[int] = None
    num_starts: Optional[int] = 2
    command: Optional[str] = None
    mode: Optional[str] = "redesign" # "redesign", "improve_layout", "optimize_space", "improve_style"
    locked_furniture_ids: Optional[List[str]] = []
    preserve_existing_mode: Optional[str] = "replace_inappropriate"
    color_palette: Optional[str] = None
    furniture_requirements: Optional[List[str]] = None
    revision: Optional[int] = None

class LayoutGenerationResponse(BaseModel):
    success: bool
    message: str
    data: Dict[str, str] # {"job_id": "uuid"}

class AIJobResponseData(BaseModel):
    status: str
    progress: int

class AIJobResponse(BaseModel):
    success: bool
    data: AIJobResponseData

class AIResultResponseData(BaseModel):
    layout_data: str # Stringified JSON
    overall_score: float
    subscores: Dict[str, float]
    processing_time_ms: int
    optimization_report: Optional[Dict[str, Any]] = None
    explanation: Optional[str] = None

class AIResultResponse(BaseModel):
    success: bool
    data: AIResultResponseData

class OptimizeRequest(BaseModel):
    room_id: str
    seed: Optional[int] = None
    num_starts: Optional[int] = 5

class RecommendationCard(BaseModel):
    id: str
    recommendation_type: str
    title: str
    description: str
    reason: str
    rule_triggered: str
    expected_improvement: str
    score_impact: str
    action: Dict[str, Any]

class RecommendationResponse(BaseModel):
    success: bool
    data: List[RecommendationCard]

class ExplainResponseData(BaseModel):
    why_suggested: str
    rule_triggered: str
    design_principle: str
    expected_improvement: str
    score_impact: str

class ExplainResponse(BaseModel):
    success: bool
    data: ExplainResponseData

class AIHistoryItem(BaseModel):
    id: str
    room_id: str
    ai_result_id: str
    applied: bool
    applied_at: Optional[datetime] = None
    created_at: datetime

class AIHistoryResponse(BaseModel):
    success: bool
    data: List[AIHistoryItem]
