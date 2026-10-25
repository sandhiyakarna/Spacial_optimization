import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Text, ForeignKey, DateTime, Boolean
from sqlalchemy.orm import relationship
from core.database.session import Base

class AIJob(Base):
    __tablename__ = "ai_jobs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    prompt = Column(Text, nullable=True)
    job_type = Column(String(50), nullable=False) # AI Layout, Optimization, Furniture Recommendation, Design Scoring, etc.
    status = Column(String(30), default="Pending", nullable=False) # Pending, Running, Completed, Failed, Cancelled
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")
    user = relationship("User")
    results = relationship("AIResult", back_populates="job", cascade="all, delete-orphan")

class AIResult(Base):
    __tablename__ = "ai_results"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    job_id = Column(String(36), ForeignKey("ai_jobs.id", ondelete="CASCADE"), nullable=False)
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    layout_json = Column(Text, nullable=False) # JSON layout representation
    confidence_score = Column(Float, default=100.0, nullable=False)
    explanation = Column(Text, nullable=True)
    processing_time_ms = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    job = relationship("AIJob", back_populates="results")
    room = relationship("Room")

class AIHistory(Base):
    __tablename__ = "ai_history"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    ai_result_id = Column(String(36), ForeignKey("ai_results.id", ondelete="CASCADE"), nullable=False)
    applied = Column(Boolean, default=False, nullable=False)
    applied_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")
    ai_result = relationship("AIResult")

class ValidationRule(Base):
    __tablename__ = "validation_rules"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    rule_name = Column(String(100), nullable=False)
    category = Column(String(50), nullable=False) # Accessibility, Spacing, Ergonomics, etc.
    minimum_value = Column(Float, nullable=True)
    maximum_value = Column(Float, nullable=True)
    severity = Column(String(20), nullable=False) # Info, Warning, Error
    enabled = Column(Boolean, default=True, nullable=False)

class ValidationResult(Base):
    __tablename__ = "validation_results"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    rule_id = Column(String(36), ForeignKey("validation_rules.id", ondelete="SET NULL"), nullable=True)
    status = Column(String(20), nullable=False) # Pass, Warning, Fail
    severity = Column(String(20), nullable=False) # Info, Warning, Error
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")
    rule = relationship("ValidationRule")

class ValidationChecklist(Base):
    __tablename__ = "validation_checklists"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    checklist_item = Column(String(120), nullable=False)
    completed = Column(Boolean, default=False, nullable=False)
    completed_at = Column(DateTime, nullable=True)

    room = relationship("Room")

class Analytics(Base):
    __tablename__ = "analytics"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    accessibility_score = Column(Float, default=100.0, nullable=False)
    lighting_score = Column(Float, default=100.0, nullable=False)
    ergonomic_score = Column(Float, default=100.0, nullable=False)
    space_utilization_score = Column(Float, default=0.0, nullable=False)
    furniture_balance_score = Column(Float, default=100.0, nullable=False)
    overall_score = Column(Float, default=100.0, nullable=False)
    generated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")
    scores = relationship("RoomScore", back_populates="analytics", cascade="all, delete-orphan")

class RoomScore(Base):
    __tablename__ = "room_scores"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    analytics_id = Column(String(36), ForeignKey("analytics.id", ondelete="CASCADE"), nullable=False)
    metric = Column(String(60), nullable=False) # Accessibility, Lighting, Comfort, etc.
    score = Column(Float, nullable=False)
    weight = Column(Float, nullable=False)

    analytics = relationship("Analytics", back_populates="scores")

class DesignHistory(Base):
    __tablename__ = "design_history"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    version_number = Column(Integer, nullable=False)
    snapshot_json = Column(Text, nullable=False)
    summary = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")

class RecommendationHistory(Base):
    __tablename__ = "recommendation_history"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False)
    recommendation_type = Column(String(50), nullable=False) # AI, Validation, Lighting, Optimization, Analytics
    title = Column(String(150), nullable=False)
    description = Column(Text, nullable=False)
    accepted = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room")
