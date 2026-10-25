import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Float, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from core.database.session import Base

class MaterialCategory(Base):
    __tablename__ = "material_categories"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(50), unique=True, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    materials = relationship("Material", back_populates="category", cascade="all, delete-orphan")


class Material(Base):
    __tablename__ = "materials"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(100), nullable=False)
    category_id = Column(String(36), ForeignKey("material_categories.id", ondelete="CASCADE"), nullable=False)
    base_color = Column(String(30), nullable=True)  # Hex code or color name (e.g. #FFFFFF)
    preview_image = Column(String(255), nullable=True)
    opacity = Column(Float, default=1.0, nullable=False)
    reflectivity = Column(Float, default=0.0, nullable=False)
    default_scale = Column(Float, default=1.0, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    category = relationship("MaterialCategory", back_populates="materials")
    textures = relationship("MaterialTexture", back_populates="material", cascade="all, delete-orphan")


class MaterialTexture(Base):
    __tablename__ = "material_textures"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    material_id = Column(String(36), ForeignKey("materials.id", ondelete="CASCADE"), nullable=False)
    texture_type = Column(String(50), nullable=False)  # base_color, normal, roughness, metallic
    file_path = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    material = relationship("Material", back_populates="textures")
