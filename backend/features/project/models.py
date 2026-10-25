import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, Text, Integer
from sqlalchemy.orm import relationship
from core.database.session import Base

class Project(Base):
    __tablename__ = "projects"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    project_name = Column(String(120), nullable=False)
    description = Column(Text, nullable=True)
    location = Column(String(150), nullable=True)
    cover_image = Column(Text, nullable=True)
    status = Column(String(30), default="Draft", nullable=False) # Draft, Completed, Archived, Deleted
    is_favorite = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)

    user = relationship("User")
    settings = relationship("ProjectSetting", back_populates="project", uselist=False, cascade="all, delete-orphan")
    rooms = relationship("Room", back_populates="project", cascade="all, delete-orphan")

class ProjectSetting(Base):
    __tablename__ = "project_settings"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), unique=True, nullable=False)
    default_style = Column(String(50), nullable=True)
    default_template = Column(String(36), nullable=True)
    measurement_unit = Column(String(20), default="Centimeters", nullable=False)
    grid_enabled = Column(Boolean, default=True, nullable=False)
    snap_enabled = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    project = relationship("Project", back_populates="settings")

from features.room.models import Room
