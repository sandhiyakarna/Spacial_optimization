import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Text, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from core.database.session import Base

class Room(Base):
    __tablename__ = "rooms"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    room_name = Column(String(100), nullable=False)
    room_type = Column(String(50), nullable=False) # Living Room, Bedroom, Kitchen, etc.
    floor_number = Column(Integer, default=1, nullable=False)
    notes = Column(Text, nullable=True)
    room_color = Column(String(30), default="#FFFFFF", nullable=False)
    properties = Column(Text, nullable=True) # JSON representation of extra properties
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)

    project = relationship("Project", back_populates="rooms")
    measurements = relationship("RoomMeasurement", back_populates="room", uselist=False, cascade="all, delete-orphan")

class RoomMeasurement(Base):
    __tablename__ = "room_measurements"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), unique=True, nullable=False)
    length = Column(Float, default=600.0, nullable=False) # length > 0
    width = Column(Float, default=450.0, nullable=False)  # width > 0
    height = Column(Float, default=300.0, nullable=False) # height > 0
    floor_thickness = Column(Float, default=30.0, nullable=False)
    wall_thickness = Column(Float, default=20.0, nullable=False)
    ceiling_height = Column(Float, default=300.0, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    room = relationship("Room", back_populates="measurements")
