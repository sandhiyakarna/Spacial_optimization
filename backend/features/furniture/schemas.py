from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime

class FurnitureCategoryCreate(BaseModel):
    name: str
    description: Optional[str] = None

class FurnitureCategoryOut(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    parent_id: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FurnitureAssetCreate(BaseModel):
    name: str
    category: str  # maps to category name, creates if not exists
    subcategory: Optional[str] = None
    style: str
    width: float
    depth: float
    height: float
    clearance: float = 0.0
    assembly_clearance: float = 0.0
    tags: Optional[str] = None
    glb_url: Optional[str] = ""
    thumbnail_url: Optional[str] = ""
    preview_url: Optional[str] = ""

class FurnitureAssetUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    style: Optional[str] = None
    width: Optional[float] = None
    depth: Optional[float] = None
    height: Optional[float] = None
    clearance: Optional[float] = None
    assembly_clearance: Optional[float] = None
    tags: Optional[str] = None
    glb_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    preview_url: Optional[str] = None


class AssetOut(BaseModel):
    id: str
    name: str
    type: str
    file_type: str
    model_path: Optional[str] = None
    thumbnail_path: Optional[str] = None
    preview_path: Optional[str] = None
    asset_metadata: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FurnitureAssetOut(BaseModel):
    id: str
    name: str
    category: str
    category_id: Optional[str] = None
    subcategory: Optional[str] = None
    style: str
    width: float
    depth: float
    height: float
    clearance: float
    assembly_clearance: float
    tags: Optional[str] = None
    glb_url: str
    thumbnail_url: str
    preview_url: Optional[str] = None
    model_path: Optional[str] = None
    thumbnail_path: Optional[str] = None
    preview_path: Optional[str] = None
    model_asset_id: Optional[str] = None
    thumbnail_asset_id: Optional[str] = None
    preview_asset_id: Optional[str] = None
    created_at: datetime
    is_favorite: Optional[bool] = None

    model_config = ConfigDict(from_attributes=True)


class FurnitureCategoryUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class FurnitureDuplicateCheckRequest(BaseModel):
    name: str
    category: str
    style: str
    width: float
    depth: float
    height: float


class FurnitureDuplicateCheckResponse(BaseModel):
    is_duplicate: bool
    duplicate_asset: Optional[FurnitureAssetOut] = None
    reason: Optional[str] = None


class FurnitureBulkImportItem(BaseModel):
    name: str
    category: str
    style: str
    width: float
    depth: float
    height: float
    clearance: float = 0.0
    assembly_clearance: float = 0.0
    tags: Optional[str] = None
    glb_url: Optional[str] = ""
    thumbnail_url: Optional[str] = ""


class FurnitureBulkImportRequest(BaseModel):
    assets: List[FurnitureBulkImportItem]
    dry_run: bool = True


class BulkImportReportItem(BaseModel):
    item_index: int
    name: str
    status: str  # "valid", "invalid", "duplicate"
    errors: List[str] = []
    duplicate_asset_id: Optional[str] = None


class FurnitureBulkImportResponse(BaseModel):
    success: bool
    total_processed: int
    valid_count: int
    invalid_count: int
    duplicate_count: int
    imported_count: int
    report: List[BulkImportReportItem]


