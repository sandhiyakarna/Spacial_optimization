from sqlalchemy.orm import Session
from typing import Optional, List
from features.ai.models import AIJob, AIResult, AIHistory, RecommendationHistory, Analytics, RoomScore
from datetime import datetime, timezone

class AIRepository:
    @staticmethod
    def create_job(db: Session, room_id: str, user_id: str, job_type: str, prompt: Optional[str] = None) -> AIJob:
        job = AIJob(
            room_id=room_id,
            user_id=user_id,
            job_type=job_type,
            prompt=prompt,
            status="Pending"
        )
        db.add(job)
        db.commit()
        db.refresh(job)
        return job

    @staticmethod
    def get_job(db: Session, job_id: str) -> Optional[AIJob]:
        return db.query(AIJob).filter(AIJob.id == job_id).first()

    @staticmethod
    def update_job_status(db: Session, job_id: str, status: str, progress: int = 0) -> Optional[AIJob]:
        job = db.query(AIJob).filter(AIJob.id == job_id).first()
        if job:
            job.status = status
            if status == "Running" and not job.started_at:
                job.started_at = datetime.now(timezone.utc)
            elif status in ["Completed", "Failed"]:
                job.completed_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(job)
        return job

    @staticmethod
    def save_result(
        db: Session,
        job_id: str,
        room_id: str,
        layout_json: str,
        confidence_score: float,
        explanation: Optional[str] = None,
        processing_time_ms: int = 0
    ) -> AIResult:
        result = AIResult(
            job_id=job_id,
            room_id=room_id,
            layout_json=layout_json,
            confidence_score=confidence_score,
            explanation=explanation,
            processing_time_ms=processing_time_ms
        )
        db.add(result)
        db.commit()
        db.refresh(result)
        return result

    @staticmethod
    def get_result_by_job(db: Session, job_id: str) -> Optional[AIResult]:
        return db.query(AIResult).filter(AIResult.job_id == job_id).first()

    @staticmethod
    def add_history(db: Session, room_id: str, result_id: str) -> AIHistory:
        history = AIHistory(
            room_id=room_id,
            ai_result_id=result_id,
            applied=False
        )
        db.add(history)
        db.commit()
        db.refresh(history)
        return history

    @staticmethod
    def get_history(db: Session, room_id: str) -> List[AIHistory]:
        return db.query(AIHistory).filter(AIHistory.room_id == room_id).order_by(AIHistory.created_at.desc()).all()

    @staticmethod
    def log_recommendation(
        db: Session,
        id: str,
        room_id: str,
        rec_type: str,
        title: str,
        description: str
    ) -> RecommendationHistory:
        # Delete if already exists
        db.query(RecommendationHistory).filter(RecommendationHistory.id == id).delete()
        
        rec = RecommendationHistory(
            id=id,
            room_id=room_id,
            recommendation_type=rec_type,
            title=title,
            description=description,
            accepted=False
        )
        db.add(rec)
        db.commit()
        db.refresh(rec)
        return rec

    @staticmethod
    def get_recommendation(db: Session, rec_id: str) -> Optional[RecommendationHistory]:
        return db.query(RecommendationHistory).filter(RecommendationHistory.id == rec_id).first()

    @staticmethod
    def list_recommendations(db: Session, room_id: str) -> List[RecommendationHistory]:
        return db.query(RecommendationHistory).filter(RecommendationHistory.room_id == room_id).order_by(RecommendationHistory.created_at.desc()).all()

    @staticmethod
    def save_analytics(
        db: Session,
        room_id: str,
        accessibility: float,
        lighting: float,
        ergonomics: float,
        space_util: float,
        balance: float,
        overall: float
    ) -> Analytics:
        # Delete old room analytics
        db.query(Analytics).filter(Analytics.room_id == room_id).delete()
        
        analytics = Analytics(
            room_id=room_id,
            accessibility_score=accessibility,
            lighting_score=lighting,
            ergonomic_score=ergonomics,
            space_utilization_score=space_util,
            furniture_balance_score=balance,
            overall_score=overall
        )
        db.add(analytics)
        db.commit()
        db.refresh(analytics)
        
        # Save metrics
        metrics = [
            ("Accessibility", accessibility, 0.20),
            ("Space Utilization", space_util, 0.15),
            ("Ergonomics", ergonomics, 0.15),
            ("Balance", balance, 0.10),
            ("Lighting", lighting, 0.10),
            ("Overall", overall, 1.0)
        ]
        
        for name, score, weight in metrics:
            rs = RoomScore(
                analytics_id=analytics.id,
                metric=name,
                score=score,
                weight=weight
            )
            db.add(rs)
            
        db.commit()
        db.refresh(analytics)
        return analytics
