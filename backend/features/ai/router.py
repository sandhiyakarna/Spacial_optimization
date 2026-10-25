from fastapi import APIRouter, Depends, BackgroundTasks, status
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user
from features.auth.models import User
from features.ai.schema import (
    LayoutGenerationRequest, LayoutGenerationResponse, AIJobResponse, AIJobResponseData,
    AIResultResponse, AIResultResponseData, OptimizeRequest, RecommendationResponse,
    RecommendationCard, ExplainResponse, ExplainResponseData, AIHistoryResponse, AIHistoryItem
)
from features.ai.service import AIService
from features.ai.repository import AIRepository
from features.ai.exceptions import AIJobNotFoundException
import json

router = APIRouter(prefix="/ai", tags=["AI Engineering"])

@router.post("/layout", response_model=LayoutGenerationResponse, status_code=status.HTTP_201_CREATED)
def generate_layout(
    request: LayoutGenerationRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    import logging
    logger = logging.getLogger("flowspace")
    logger.info("[AI DEBUG] Request received")
    logger.info(f"[AI DEBUG] Room: {request.room_id}")
    logger.info(f"[AI DEBUG] Command: {request.command}")

    job_id = AIService.start_layout_generation(
        db,
        request.room_id,
        current_user.id,
        request.style,
        request.preferences,
        request.seed,
        request.num_starts,
        request.command,
        mode=request.mode or "redesign",
        locked_furniture_ids=request.locked_furniture_ids or [],
        preserve_existing_mode=request.preserve_existing_mode or "replace_inappropriate",
        color_palette=request.color_palette,
        furniture_requirements=request.furniture_requirements,
        revision=request.revision
    )
    # Trigger layout generation in background task
    background_tasks.add_task(AIService.run_layout_generation_sync, db, job_id)
    
    return LayoutGenerationResponse(
        success=True,
        message="AI layout generation started.",
        data={"job_id": job_id}
    )

@router.get("/jobs/{job_id}", response_model=AIJobResponse)
def get_job_status(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job = AIRepository.get_job(db, job_id)
    if not job:
        raise AIJobNotFoundException(job_id)
        
    progress = 100 if job.status == "Completed" else (0 if job.status == "Pending" else 50)
    return AIJobResponse(
        success=True,
        data=AIJobResponseData(status=job.status, progress=progress)
    )

@router.get("/results/{job_id}", response_model=AIResultResponse)
def get_job_result(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    job = AIRepository.get_job(db, job_id)
    if not job:
        raise AIJobNotFoundException(job_id)
        
    result = AIRepository.get_result_by_job(db, job_id)
    if not result:
        # Fallback empty result
        return AIResultResponse(
            success=True,
            data=AIResultResponseData(
                layout_data="{}",
                overall_score=0.0,
                subscores={},
                processing_time_ms=0
            )
        )
        
    # Get scores
    scores = {}
    analytics = db.query(AIRepository.get_result_by_job(db, job_id).__class__).filter_by(room_id=result.room_id).first() # Dummy check
    
    # We can calculate design scores directly for safety
    try:
        room = job.room
        props = json.loads(result.layout_json)
        from features.ai.scoring import calculate_design_score
        calc = calculate_design_score(
            room.measurements.width, room.measurements.length,
            room.room_type, props.get('furniture', []), props.get('openings', [])
        )
        overall_score = calc['overall_score']
        subscores = calc['subscores']
    except Exception:
        overall_score = result.confidence_score
        subscores = {
            "accessibility": result.confidence_score,
            "space_utilization": result.confidence_score,
            "ergonomics": result.confidence_score,
            "safety": result.confidence_score,
            "balance": result.confidence_score,
            "aesthetics": result.confidence_score,
            "functionality": result.confidence_score,
            "lighting": result.confidence_score
        }

    return AIResultResponse(
        success=True,
        data=AIResultResponseData(
            layout_data=result.layout_json,
            overall_score=overall_score,
            subscores=subscores,
            processing_time_ms=result.processing_time_ms,
            explanation=result.explanation
        )
    )

@router.post("/optimize", response_model=AIResultResponse)
def optimize_layout(
    request: OptimizeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    res = AIService.optimize_existing_layout(db, request.room_id, request.seed, request.num_starts)
    return AIResultResponse(
        success=True,
        data=AIResultResponseData(
            layout_data=res["data"]["layout_data"],
            overall_score=res["data"]["overall_score"],
            subscores=res["data"]["subscores"],
            processing_time_ms=res["data"]["processing_time_ms"],
            optimization_report=res["data"].get("optimization_report")
        )
    )

@router.get("/recommendations/{room_id}", response_model=RecommendationResponse)
def get_recommendations(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    cards = AIService.get_room_recommendations(db, room_id)
    response_cards = []
    for c in cards:
        response_cards.append(RecommendationCard(
            id=c["id"],
            recommendation_type=c["recommendation_type"],
            title=c["title"],
            description=c["description"],
            reason=c["reason"],
            rule_triggered=c["rule_triggered"],
            expected_improvement=c["expected_improvement"],
            score_impact=c["score_impact"],
            action=c["action"]
        ))
    return RecommendationResponse(success=True, data=response_cards)

@router.get("/explain/{recommendation_id}", response_model=ExplainResponse)
def explain_decision(
    recommendation_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    res = AIService.explain_recommendation(db, recommendation_id)
    return ExplainResponse(
        success=True,
        data=ExplainResponseData(
            why_suggested=res["why_suggested"],
            rule_triggered=res["rule_triggered"],
            design_principle=res["design_principle"],
            expected_improvement=res["expected_improvement"],
            score_impact=res["score_impact"]
        )
    )

@router.get("/history/{room_id}", response_model=AIHistoryResponse)
def get_history(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    histories = AIRepository.get_history(db, room_id)
    data = []
    for h in histories:
        data.append(AIHistoryItem(
            id=h.id,
            room_id=h.room_id,
            ai_result_id=h.ai_result_id,
            applied=h.applied,
            applied_at=h.applied_at,
            created_at=h.created_at
        ))
    return AIHistoryResponse(success=True, data=data)

@router.post("/apply/{recommendation_id}")
def apply_rec(
    recommendation_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    res = AIService.apply_recommendation(db, recommendation_id)
    return res

@router.get("/scores/{room_id}")
def get_room_scores(
    room_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from features.room.models import Room
    room = db.query(Room).filter(Room.id == room_id).first()
    if not room or not room.measurements:
        return {
            "success": True,
            "data": {
                "overall_score": 0.0,
                "subscores": {
                    "accessibility": 0.0,
                    "space_utilization": 0.0,
                    "ergonomics": 0.0,
                    "aesthetics": 0.0,
                    "balance": 0.0,
                    "functionality": 0.0,
                    "safety": 0.0,
                    "lighting": 0.0
                }
            }
        }
    
    props = json.loads(room.properties) if room.properties else {}
    from features.ai.scoring import calculate_design_score
    calc = calculate_design_score(
        room.measurements.width, room.measurements.length,
        room.room_type, props.get('furniture', []), props.get('openings', [])
    )
    
    AIRepository.save_analytics(
        db, room_id,
        calc['subscores']['accessibility'],
        calc['subscores']['lighting'],
        calc['subscores']['ergonomics'],
        calc['subscores']['space_utilization'],
        calc['subscores']['balance'],
        calc['overall_score']
    )
    
    return {
        "success": True,
        "data": {
            "overall_score": calc['overall_score'],
            "subscores": calc['subscores']
        }
    }
