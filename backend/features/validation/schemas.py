from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime

class ValidationRunRequest(BaseModel):
    room_id: str
    min_walkway_clearance: Optional[float] = None # Configurable in cm (e.g. 75, 80, 90)
    require_both_sides_bed_access: Optional[bool] = None # Master bedroom config
    room_type: Optional[str] = None # Bedroom, Living Room, Dining Room, Office, etc.

class ValidationIssue(BaseModel):
    id: Optional[str] = None
    rule_id: Optional[str] = None
    rule_name: str
    category: str
    severity: str # Error, Warning, Info
    message: str
    recommendation: Optional[str] = None
    affected_furniture_ids: List[str] = []
    measured_clearance: Optional[float] = None # in cm
    required_clearance: Optional[float] = None # in cm
    clearance_source: Optional[str] = None # Config source description
    issue_type: Optional[str] = None # door_blocked, door_swing, narrow_passage, bed_access, dining_pullout, wardrobe_blocked, desk_access, collision, wall_collision
    is_fixable: bool = False
    suggested_action: Optional[str] = None

class ValidationRunResponseData(BaseModel):
    room_id: str
    overall_status: str # Pass, Warning, Fail
    rules_passed: int
    rules_failed: int
    errors: List[ValidationIssue]
    warnings: List[ValidationIssue]
    suggestions: List[ValidationIssue]

class ValidationRunResponse(BaseModel):
    success: bool
    message: str
    data: ValidationRunResponseData

class ValidationResultItem(BaseModel):
    id: str
    rule_id: Optional[str] = None
    rule_name: Optional[str] = None
    category: Optional[str] = None
    status: str # Pass, Warning, Fail
    severity: str # Error, Warning, Info
    message: str
    created_at: datetime

class ValidationResultsResponseData(BaseModel):
    room_id: str
    overall_status: str
    errors: List[ValidationIssue]
    warnings: List[ValidationIssue]
    passed_rules: List[str]

class ValidationResultsResponse(BaseModel):
    success: bool
    data: ValidationResultsResponseData

class ChecklistItemDTO(BaseModel):
    id: str
    checklist_item: str
    completed: bool
    completed_at: Optional[datetime] = None

class ValidationChecklistResponseData(BaseModel):
    room_id: str
    checklist_items: List[ChecklistItemDTO]
    completion_percentage: float
    remaining_issues: int

class ValidationChecklistResponse(BaseModel):
    success: bool
    data: ValidationChecklistResponseData

class ValidationSummaryResponseData(BaseModel):
    room_id: str
    pass_rate: float
    warning_count: int
    error_count: int
    overall_status: str
    overall_score: float = 100.0
    accessibility_score: float = 100.0
    lighting_score: float = 100.0
    ergonomic_score: float = 100.0
    space_utilization_score: float = 0.0
    furniture_balance_score: float = 100.0

class ValidationSummaryResponse(BaseModel):
    success: bool
    data: ValidationSummaryResponseData

# ==========================================
# ONE-CLICK FIX SCHEMAS
# ==========================================

class FixCandidateRequest(BaseModel):
    room_id: str
    rule_id: Optional[str] = None
    issue_type: Optional[str] = None
    furniture_id: str
    min_walkway_clearance: Optional[float] = None
    require_both_sides_bed_access: Optional[bool] = None

class ProposedFurnitureChange(BaseModel):
    furniture_id: str
    name: str
    original_x: float
    original_z: float
    original_rotation: float
    proposed_x: float
    proposed_z: float
    proposed_rotation: float
    displacement_cm: float
    action_type: Optional[str] = "move" # "move", "replace", "remove"
    replacement_asset_id: Optional[str] = None
    replacement_name: Optional[str] = None

class FixCandidateResponseData(BaseModel):
    room_id: str
    target_furniture_id: str
    can_fix: bool
    explanation: str
    issue_type: Optional[str] = None
    rule_id: Optional[str] = None
    changes: List[ProposedFurnitureChange] = []
    measured_before: Optional[float] = None
    measured_after: Optional[float] = None
    required_clearance: Optional[float] = None
    predicted_improvement: str
    alternative_suggestions: List[str] = []

class FixCandidateResponse(BaseModel):
    success: bool
    message: str
    data: FixCandidateResponseData

class ApplyFixRequest(BaseModel):
    room_id: str
    furniture_id: str
    proposed_x: float = 0.0
    proposed_z: float = 0.0
    proposed_rotation: float = 0.0
    action_type: Optional[str] = "move" # "move", "replace", "remove"
    replacement_asset_id: Optional[str] = None

class ApplyFixResponse(BaseModel):
    success: bool
    message: str
    data: ValidationRunResponseData

