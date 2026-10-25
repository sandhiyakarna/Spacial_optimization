import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from core.database.session import Base

class Report(Base):
    __tablename__ = "reports"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    room_id = Column(String(36), ForeignKey("rooms.id", ondelete="CASCADE"), nullable=True)
    report_type = Column(String(50), nullable=False) # Design Report, Analytics Report, Validation Report, Recommendation Report
    status = Column(String(30), default="Pending", nullable=False) # Pending, Running, Completed, Failed
    file_path = Column(String(255), nullable=True)
    file_size = Column(Integer, default=0, nullable=False)
    format = Column(String(20), default="PDF", nullable=False) # PDF, PNG, JSON
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    project = relationship("Project")
    room = relationship("Room")
