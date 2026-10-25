import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import Column, String, Float, Text, DateTime, ForeignKey, Boolean, UniqueConstraint
from sqlalchemy.orm import relationship
from core.database.session import Base
from features.material.models import Material
from features.auth.models import User

class Asset(Base):
    __tablename__ = "assets"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(100), nullable=False)
    type = Column(String(50), nullable=False)           # model, texture, thumbnail, preview
    file_type = Column(String(10), nullable=False)      # glb, jpg, png, webp
    model_path = Column(String(255), nullable=True)     # local path
    thumbnail_path = Column(String(255), nullable=True) # local path
    preview_path = Column(String(255), nullable=True)   # local path
    asset_metadata = Column(Text, nullable=True)              # JSON string for extra info
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)


class FurnitureCategory(Base):
    __tablename__ = "furniture_categories"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(50), unique=True, nullable=False)
    description = Column(Text, nullable=True)
    parent_id = Column(String(36), ForeignKey("furniture_categories.id", ondelete="CASCADE"), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    assets = relationship("FurnitureAsset", back_populates="category_rel", cascade="all, delete-orphan", foreign_keys="[FurnitureAsset.category_id]")
    parent = relationship("FurnitureCategory", remote_side=[id], backref="subcategories")


class FurnitureAsset(Base):
    __tablename__ = "furniture_assets"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(100), nullable=False)
    category = Column(String(50), nullable=False)       # Living Room, Bedroom, Office, etc. (for compatibility)
    category_id = Column(String(36), ForeignKey("furniture_categories.id", ondelete="SET NULL"), nullable=True)
    subcategory = Column(String(50), nullable=True)     # Added subcategory string
    style = Column(String(50), nullable=False)          # Modern, Scandinavian, Minimal, etc.
    width = Column(Float, nullable=False)               # Width in cm
    depth = Column(Float, nullable=False)               # Depth in cm
    height = Column(Float, nullable=False)              # Height in cm
    clearance = Column(Float, default=0.0, nullable=False)
    assembly_clearance = Column(Float, default=0.0, nullable=False)
    tags = Column(Text, nullable=True)                  # Comma-separated list of tags
    
    # Linked Asset Relationships
    model_asset_id = Column(String(36), ForeignKey("assets.id", ondelete="SET NULL"), nullable=True)
    thumbnail_asset_id = Column(String(36), ForeignKey("assets.id", ondelete="SET NULL"), nullable=True)
    preview_asset_id = Column(String(36), ForeignKey("assets.id", ondelete="SET NULL"), nullable=True)

    glb_url = Column(String(255), nullable=False)       # Static server URL to GLB file
    thumbnail_url = Column(String(255), nullable=False) # Static server URL to WebP/PNG thumbnail
    model_path = Column(String(255), nullable=True)     # Local file system path to GLB file
    thumbnail_path = Column(String(255), nullable=True) # Local file system path to thumbnail file
    preview_path = Column(String(255), nullable=True)   # Local file system path to preview file
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    # Relationships
    category_rel = relationship("FurnitureCategory", back_populates="assets", foreign_keys=[category_id])
    model_asset = relationship("Asset", foreign_keys=[model_asset_id])
    thumbnail_asset = relationship("Asset", foreign_keys=[thumbnail_asset_id])
    preview_asset = relationship("Asset", foreign_keys=[preview_asset_id])
    materials = relationship("FurnitureMaterial", back_populates="furniture", cascade="all, delete-orphan")
    favorites = relationship("FurnitureFavorite", back_populates="furniture", cascade="all, delete-orphan")
    recents = relationship("FurnitureRecent", back_populates="furniture", cascade="all, delete-orphan")

    @property
    def preview_url(self) -> Optional[str]:
        if self.preview_path:
            return "/" + self.preview_path.replace("\\", "/")
        return None


class FurnitureMaterial(Base):
    __tablename__ = "furniture_materials"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    furniture_id = Column(String(36), ForeignKey("furniture_assets.id", ondelete="CASCADE"), nullable=False)
    material_id = Column(String(36), ForeignKey("materials.id", ondelete="CASCADE"), nullable=False)
    is_default = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    # Relationships
    furniture = relationship("FurnitureAsset", back_populates="materials")
    material = relationship("Material")  # Referenced from material module


class FurnitureFavorite(Base):
    __tablename__ = "furniture_favorites"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    furniture_id = Column(String(36), ForeignKey("furniture_assets.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    # Relationships
    furniture = relationship("FurnitureAsset", back_populates="favorites")
    user = relationship("User")  # Referenced from auth module

    __table_args__ = (
        UniqueConstraint("user_id", "furniture_id", name="uq_user_furniture_favorite"),
    )


class FurnitureRecent(Base):
    __tablename__ = "furniture_recent"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    furniture_id = Column(String(36), ForeignKey("furniture_assets.id", ondelete="CASCADE"), nullable=False)
    last_used_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)

    # Relationships
    furniture = relationship("FurnitureAsset", back_populates="recents")
    user = relationship("User")  # Referenced from auth module

    __table_args__ = (
        UniqueConstraint("user_id", "furniture_id", name="uq_user_furniture_recent"),
    )

