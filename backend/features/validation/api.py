import json
from fastapi import APIRouter, Depends, status, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.dependencies import get_db, get_current_user
from features.auth.models import User
from features.room.models import Room
from features.ai.models import ValidationResult, ValidationChecklist, ValidationRule, Analytics
from features.validation.schemas import (
    ValidationRunRequest, ValidationRunResponse, ValidationRunResponseData,
    ValidationResultsResponse, ValidationResultsResponseData, ValidationIssue,
    ValidationChecklistResponse, ValidationChecklistResponseData, ChecklistItemDTO,
    ValidationSummaryResponse, ValidationSummaryResponseData,
    FixCandidateRequest, FixCandidateResponse, FixCandidateResponseData,
    ApplyFixRequest, ApplyFixResponse
)
from features.validation.service import ValidationService
from features.validation.fix_service import LayoutFixService

router = APIRouter(prefix="/validation", tags=["Validation"])

@router.post("/run", response_model=ValidationRunResponse, status_code=status.HTTP_200_OK)
def run_validation(
    req: ValidationRunRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Triggers re-validation for the given room layout and returns the results.
    """
    res_data = ValidationService.validate_room(
        db,
        req.room_id,
        current_user.id,
        min_walkway_clearance=req.min_walkway_clearance,
        require_both_sides_bed_access=req.require_both_sides_bed_access,
        override_room_type=req.room_type
    )
    return ValidationRunResponse(
        success=True,
        message="Validation complete.",
        data=res_data
    )

@router.post("/fix-candidate", response_model=FixCandidateResponse, status_code=status.HTTP_200_OK)
def get_fix_candidate(
    req: FixCandidateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Evaluates intelligent layout corrections for a specific issue and target furniture item.
    Returns proposed transformations, predicted improvement, or reasons if unfixable.
    """
    room = db.query(Room).filter(Room.id == req.room_id).first()
    if not room:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.project.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    if not room.measurements:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Room measurements are required")

    furniture = []
    openings = []
    if room.properties:
        try:
            props = json.loads(room.properties)
            furniture = props.get('furniture', [])
            openings = props.get('openings', [])
        except Exception:
            pass

    fix_data = LayoutFixService.find_fix_for_issue(
        room_width=room.measurements.width,
        room_length=room.measurements.length,
        room_type=room.room_type or "Living Room",
        furniture=furniture,
        openings=openings,
        target_furniture_id=req.furniture_id,
        issue_type=req.issue_type,
        rule_id=req.rule_id,
        min_walkway_clearance=req.min_walkway_clearance or 75.0,
        require_both_sides_bed_access=req.require_both_sides_bed_access or False
    )
    fix_data.room_id = req.room_id
    return FixCandidateResponse(
        success=True,
        message="Fix candidate evaluated successfully." if fix_data.can_fix else "No feasible candidate found.",
        data=fix_data
    )

@router.post("/apply-fix", response_model=ApplyFixResponse, status_code=status.HTTP_200_OK)
def apply_fix(
    req: ApplyFixRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Applies a proposed one-click layout correction and returns the newly validated state.
    """
    room = db.query(Room).filter(Room.id == req.room_id).first()
    if not room:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.project.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    props = {}
    if room.properties:
        try:
            props = json.loads(room.properties)
        except Exception:
            pass
    furniture = props.get('furniture', [])

    found = False
    for f in list(furniture):
        if str(f.get('id')) == str(req.furniture_id):
            if req.action_type == "remove":
                furniture.remove(f)
                found = True
                break
            elif req.action_type == "replace" and req.replacement_asset_id:
                from features.furniture.models import FurnitureAsset
                replacement = db.query(FurnitureAsset).filter(FurnitureAsset.id == req.replacement_asset_id).first()
                if replacement:
                    f['asset_id'] = replacement.id
                    f['assetId'] = replacement.id
                    f['name'] = replacement.name
                    f['category'] = replacement.category
                    f['width'] = replacement.width
                    f['depth'] = replacement.depth
                    f['height'] = replacement.height
                    f['x'] = req.proposed_x
                    f['z'] = req.proposed_z
                    f['rotationY'] = req.proposed_rotation
                    found = True
                    break
            else:
                f['x'] = req.proposed_x
                f['z'] = req.proposed_z
                f['rotationY'] = req.proposed_rotation
                found = True
                break
    if not found:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Furniture not found in layout")

    props['furniture'] = furniture
    room.properties = json.dumps(props)
    db.commit()

    # Re-run validation on the updated layout
    res_data = ValidationService.validate_room(db, req.room_id, current_user.id)
    return ApplyFixResponse(
        success=True,
        message="Layout correction applied and revalidated successfully.",
        data=res_data
    )

@router.get("/{room_id}", response_model=ValidationResultsResponse)
def get_validation_results(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Retrieves the cached validation results (errors, warnings, suggestions) for a room.
    """
    # Verify room ownership
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.project.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    # Fetch results from DB
    results = db.query(ValidationResult).filter(ValidationResult.room_id == room_id).all()

    errors: List[ValidationIssue] = []
    warnings: List[ValidationIssue] = []
    passed_rules: List[str] = []

    for r in results:
        # Load rule details
        rule = db.query(ValidationRule).filter(ValidationRule.id == r.rule_id).first()
        rule_name = rule.rule_name if rule else "Unknown Rule"
        category = rule.category if rule else "General"
        
        issue = ValidationIssue(
            rule_id=r.rule_id,
            rule_name=rule_name,
            category=category,
            severity=r.severity,
            message=r.message,
            recommendation=f"Please adjust coordinates to resolve this {r.severity.lower()} constraint violation."
        )

        if r.status == "Fail" or r.severity == "Error":
            errors.append(issue)
        elif r.status == "Warning" or r.severity == "Warning":
            warnings.append(issue)
        elif r.status == "Pass":
            passed_rules.append(r.rule_id or "Rule")

    overall_status = "Pass"
    if errors:
        overall_status = "Fail"
    elif warnings:
        overall_status = "Warning"

    return ValidationResultsResponse(
        success=True,
        data=ValidationResultsResponseData(
            room_id=room_id,
            overall_status=overall_status,
            errors=errors,
            warnings=warnings,
            passed_rules=passed_rules
        )
    )

@router.get("/checklist/{room_id}", response_model=ValidationChecklistResponse)
def get_validation_checklist(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Retrieves the smart design checklist status for the room.
    """
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.project.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    checklist = db.query(ValidationChecklist).filter(ValidationChecklist.room_id == room_id).all()

    # If checklist is empty, run validation once to seed it
    if not checklist:
        ValidationService.validate_room(db, room_id, current_user.id)
        checklist = db.query(ValidationChecklist).filter(ValidationChecklist.room_id == room_id).all()

    completed_count = sum(1 for c in checklist if c.completed)
    total_count = len(checklist)
    completion_percentage = (completed_count / total_count) * 100.0 if total_count > 0 else 100.0

    # Remaining issues (errors + warnings from checklist)
    remaining = total_count - completed_count

    items = [
        ChecklistItemDTO(
            id=c.id,
            checklist_item=c.checklist_item,
            completed=c.completed,
            completed_at=c.completed_at
        ) for c in checklist
    ]

    return ValidationChecklistResponse(
        success=True,
        data=ValidationChecklistResponseData(
            room_id=room_id,
            checklist_items=items,
            completion_percentage=round(completion_percentage, 1),
            remaining_issues=remaining
        )
    )

@router.get("/summary/{room_id}", response_model=ValidationSummaryResponse)
def get_validation_summary(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns a high-level summary of validation for a room.
    """
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Room not found")
    if room.project.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    results = db.query(ValidationResult).filter(ValidationResult.room_id == room_id).all()

    # Seed if empty
    if not results:
        ValidationService.validate_room(db, room_id, current_user.id)
        results = db.query(ValidationResult).filter(ValidationResult.room_id == room_id).all()

    total_rules = len(results)
    passed_rules = sum(1 for r in results if r.status == "Pass")
    errors = sum(1 for r in results if r.status != "Pass" and r.severity == "Error")
    warnings = sum(1 for r in results if r.status != "Pass" and r.severity == "Warning")

    pass_rate = (passed_rules / total_rules) * 100.0 if total_rules > 0 else 100.0
    overall_status = "Pass"
    if errors > 0:
        overall_status = "Fail"
    elif warnings > 0:
        overall_status = "Warning"

    # Query the Analytics table to fetch calculated scores
    analytics = db.query(Analytics).filter(Analytics.room_id == room_id).first()
    if not analytics:
        # Re-trigger to generate analytics if somehow missing
        ValidationService.validate_room(db, room_id, current_user.id)
        analytics = db.query(Analytics).filter(Analytics.room_id == room_id).first()

    return ValidationSummaryResponse(
        success=True,
        data=ValidationSummaryResponseData(
            room_id=room_id,
            pass_rate=round(pass_rate, 1),
            warning_count=warnings,
            error_count=errors,
            overall_status=overall_status,
            overall_score=round(analytics.overall_score, 1) if analytics else 100.0,
            accessibility_score=round(analytics.accessibility_score, 1) if analytics else 100.0,
            lighting_score=round(analytics.lighting_score, 1) if analytics else 100.0,
            ergonomic_score=round(analytics.ergonomic_score, 1) if analytics else 100.0,
            space_utilization_score=round(analytics.space_utilization_score, 1) if analytics else 0.0,
            furniture_balance_score=round(analytics.furniture_balance_score, 1) if analytics else 100.0
        )
    )
