from fastapi import APIRouter, Depends, HTTPException, status, File, UploadFile
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user, RoleChecker
from features.auth.models import User
from typing import List, Optional, Set
import os
import shutil
from .schemas import (
    FurnitureAssetOut, FurnitureAssetCreate, FurnitureAssetUpdate,
    FurnitureCategoryOut, FurnitureCategoryCreate, FurnitureCategoryUpdate,
    FurnitureDuplicateCheckRequest, FurnitureDuplicateCheckResponse,
    FurnitureBulkImportRequest, FurnitureBulkImportResponse
)
from . import services

router = APIRouter(prefix="/furniture", tags=["Furniture"])

@router.get("", response_model=List[FurnitureAssetOut])
def list_furniture(
    search: Optional[str] = None,
    category: Optional[str] = None,
    style: Optional[str] = None,
    favorites_only: bool = False,
    page: int = 1,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    assets = services.list_furniture_assets(
        db, search=search, category=category, style=style,
        favorites_only=favorites_only, user_id=current_user.id,
        page=page, limit=limit
    )
    return assets

@router.get("/categories", response_model=List[FurnitureCategoryOut])
def list_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return services.list_categories(db)

@router.post("/categories", response_model=FurnitureCategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    req: FurnitureCategoryCreate,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    return services.create_category(db, req.name, req.description)

@router.post("", response_model=FurnitureAssetOut, status_code=status.HTTP_201_CREATED)
def create_furniture(
    req: FurnitureAssetCreate,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    if req.width <= 0 or req.depth <= 0 or req.height <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Dimensions (width, depth, height) must be positive values"
        )
    if req.clearance < 0 or req.assembly_clearance < 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Clearance values must be non-negative"
        )
    return services.create_furniture_asset(db, req)

@router.get("/favorites", response_model=List[FurnitureAssetOut])
def list_favorites(
    page: int = 1,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return services.list_favorite_furniture(db, current_user.id, page=page, limit=limit)

@router.get("/recent", response_model=List[FurnitureAssetOut])
def list_recent(
    limit: int = 10,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return services.list_recent_furniture(db, current_user.id, limit=limit)

@router.get("/{asset_id}", response_model=FurnitureAssetOut)
def get_furniture_by_id(
    asset_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    asset = services.get_furniture_asset(db, asset_id, user_id=current_user.id)
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    return asset

@router.put("/{asset_id}", response_model=FurnitureAssetOut)
def update_furniture(
    asset_id: str,
    req: FurnitureAssetUpdate,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    if req.width is not None and req.width <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Width must be a positive value")
    if req.depth is not None and req.depth <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Depth must be a positive value")
    if req.height is not None and req.height <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Height must be a positive value")
    if req.clearance is not None and req.clearance < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Clearance must be non-negative")
    if req.assembly_clearance is not None and req.assembly_clearance < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Assembly clearance must be non-negative")

    asset = services.update_furniture_asset(db, asset_id, req)
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    # Set favorite status for return schema
    asset.is_favorite = services.get_furniture_asset(db, asset_id, user_id=current_user.id).is_favorite
    return asset

@router.delete("/{asset_id}")
def delete_furniture(
    asset_id: str,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    success = services.delete_furniture_asset(db, asset_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    return {"success": True, "message": "Furniture asset deleted successfully"}

@router.post("/{asset_id}/favorite")
def favorite_furniture(
    asset_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    asset = services.get_furniture_asset(db, asset_id)
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    services.add_favorite(db, current_user.id, asset_id)
    return {"success": True, "message": "Furniture asset added to favorites"}

@router.delete("/{asset_id}/favorite")
def unfavorite_furniture(
    asset_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    asset = services.get_furniture_asset(db, asset_id)
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    services.remove_favorite(db, current_user.id, asset_id)
    return {"success": True, "message": "Furniture asset removed from favorites"}

import struct
from .models import Asset, FurnitureAsset

def validate_asset_file(file: UploadFile, allowed_extensions: List[str], max_size: int, file_type_label: str):
    # 1. Size check
    file.file.seek(0, 2)
    file_size = file.file.tell()
    file.file.seek(0)
    if file_size > max_size:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{file_type_label} file exceeds the {max_size // (1024 * 1024)}MB size limit"
        )
        
    # 2. Extension check
    _, ext = os.path.splitext(file.filename.lower())
    if ext not in allowed_extensions:
        if file_type_label == "Model":
            detail_msg = "Model file must have .glb extension"
        else:
            detail_msg = f"{file_type_label} file must be a valid image ({', '.join(allowed_extensions)})"
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=detail_msg
        )
        
    # 3. Magic bytes check
    if ext == ".glb":
        magic_bytes = file.file.read(4)
        file.file.seek(0)
        if magic_bytes != b'glTF':
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid GLB file format"
            )


@router.post("/{asset_id}/upload-model", response_model=FurnitureAssetOut)
def upload_model(
    asset_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    db_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not db_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    
    validate_asset_file(file, [".glb"], 50 * 1024 * 1024, "Model")
    
    # Save file to uploads/furniture/models/{asset_id}/
    static_dir = os.path.join("uploads", "furniture", "models", asset_id)
    os.makedirs(static_dir, exist_ok=True)
    
    file_path = os.path.join(static_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    rel_path = f"uploads/furniture/models/{asset_id}/{file.filename}"
    glb_url = f"/uploads/furniture/models/{asset_id}/{file.filename}"
    
    # Read GLB json metadata if possible
    json_metadata = None
    try:
        file.file.seek(12)
        chunk_header = file.file.read(8)
        if len(chunk_header) == 8:
            chunk_length, chunk_type = struct.unpack("<I4s", chunk_header)
            if chunk_type.strip() == b'JSON':
                json_data = file.file.read(chunk_length).decode('utf-8', errors='ignore')
                json.loads(json_data) # verify valid JSON
                json_metadata = json_data
    except Exception:
        pass
    file.file.seek(0)

    # Create/Update Asset record
    db_model_asset = db.query(Asset).filter(Asset.id == f"model_{asset_id}").first()
    if not db_model_asset:
        db_model_asset = Asset(id=f"model_{asset_id}", name=f"{db_asset.name} GLB Model", type="model", file_type="glb")
        db.add(db_model_asset)
    db_model_asset.model_path = rel_path
    db_model_asset.asset_metadata = json_metadata
    
    db_asset.model_asset_id = db_model_asset.id
    db_asset.model_path = rel_path
    db_asset.glb_url = glb_url
    db.commit()
    db.refresh(db_asset)
    
    # Set favorite status for return schema
    db_asset.is_favorite = services.get_furniture_asset(db, asset_id, user_id=current_user.id).is_favorite
    return db_asset


@router.post("/{asset_id}/upload-thumbnail", response_model=FurnitureAssetOut)
def upload_thumbnail(
    asset_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    db_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not db_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    
    allowed_exts = {".png", ".jpg", ".jpeg", ".webp"}
    _, ext = os.path.splitext(file.filename.lower())
    validate_asset_file(file, list(allowed_exts), 5 * 1024 * 1024, "Thumbnail")
    
    # Save file to uploads/furniture/thumbnails/{asset_id}/
    static_dir = os.path.join("uploads", "furniture", "thumbnails", asset_id)
    os.makedirs(static_dir, exist_ok=True)
    
    file_path = os.path.join(static_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    rel_path = f"uploads/furniture/thumbnails/{asset_id}/{file.filename}"
    thumb_url = f"/uploads/furniture/thumbnails/{asset_id}/{file.filename}"
    
    # Create/Update Asset record
    db_thumb_asset = db.query(Asset).filter(Asset.id == f"thumb_{asset_id}").first()
    if not db_thumb_asset:
        db_thumb_asset = Asset(id=f"thumb_{asset_id}", name=f"{db_asset.name} Thumbnail", type="thumbnail", file_type=ext[1:])
        db.add(db_thumb_asset)
    db_thumb_asset.thumbnail_path = rel_path
    
    db_asset.thumbnail_asset_id = db_thumb_asset.id
    db_asset.thumbnail_path = rel_path
    db_asset.thumbnail_url = thumb_url
    db.commit()
    db.refresh(db_asset)
    
    # Set favorite status for return schema
    db_asset.is_favorite = services.get_furniture_asset(db, asset_id, user_id=current_user.id).is_favorite
    return db_asset


@router.post("/{asset_id}/upload-preview", response_model=FurnitureAssetOut)
def upload_preview(
    asset_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    db_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not db_asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    
    allowed_exts = {".png", ".jpg", ".jpeg", ".webp"}
    _, ext = os.path.splitext(file.filename.lower())
    validate_asset_file(file, list(allowed_exts), 5 * 1024 * 1024, "Preview")
    
    # Save file to uploads/furniture/previews/{asset_id}/
    static_dir = os.path.join("uploads", "furniture", "previews", asset_id)
    os.makedirs(static_dir, exist_ok=True)
    
    file_path = os.path.join(static_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    rel_path = f"uploads/furniture/previews/{asset_id}/{file.filename}"
    
    # Create/Update Asset record
    db_preview_asset = db.query(Asset).filter(Asset.id == f"preview_{asset_id}").first()
    if not db_preview_asset:
        db_preview_asset = Asset(id=f"preview_{asset_id}", name=f"{db_asset.name} Preview", type="preview", file_type=ext[1:])
        db.add(db_preview_asset)
    db_preview_asset.preview_path = rel_path
    
    db_asset.preview_asset_id = db_preview_asset.id
    db_asset.preview_path = rel_path
    db.commit()
    db.refresh(db_asset)
    
    # Set favorite status for return schema
    db_asset.is_favorite = services.get_furniture_asset(db, asset_id, user_id=current_user.id).is_favorite
    return db_asset


# Keep original apply material endpoint
from pydantic import BaseModel
class ApplyMaterialRequest(BaseModel):
    material_id: str

@router.post("/{asset_id}/material")
def apply_material_to_furniture(
    asset_id: str,
    req: ApplyMaterialRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    asset = services.get_furniture_asset(db, asset_id)
    if not asset:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Furniture asset not found"
        )
    from features.material.services import MaterialService
    material = MaterialService.get_material(db, req.material_id)
    if not material:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Material not found"
        )
    return {
        "success": True,
        "message": "Material applied to furniture successfully.",
        "data": {
            "furniture_id": asset_id,
            "material_id": req.material_id,
            "material_name": material.name,
            "base_color": material.base_color,
            "reflectivity": material.reflectivity,
            "roughness": 1.0 - material.reflectivity,
            "opacity": material.opacity
        }
    }


@router.put("/categories/{category_id}", response_model=FurnitureCategoryOut)
def update_category_endpoint(
    category_id: str,
    req: FurnitureCategoryUpdate,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    cat = services.update_category(db, category_id, req.name, req.description)
    if not cat:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    return cat


@router.delete("/categories/{category_id}")
def delete_category_endpoint(
    category_id: str,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    success = services.delete_category(db, category_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    return {"success": True, "message": "Category deleted successfully"}


@router.post("/check-duplicate", response_model=FurnitureDuplicateCheckResponse)
def check_duplicate_endpoint(
    req: FurnitureDuplicateCheckRequest,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    match = services.check_duplicate_asset(
        db,
        name=req.name,
        category=req.category,
        style=req.style,
        width=req.width,
        depth=req.depth,
        height=req.height
    )
    if match:
        return FurnitureDuplicateCheckResponse(
            is_duplicate=True,
            duplicate_asset=FurnitureAssetOut.model_validate(match),
            reason=f"An asset with name '{match.name}' or identical dimensions already exists"
        )
    return FurnitureDuplicateCheckResponse(is_duplicate=False)


@router.post("/bulk-import", response_model=FurnitureBulkImportResponse)
def bulk_import_endpoint(
    req: FurnitureBulkImportRequest,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    return services.bulk_import_assets(db, req)


class BulkDeleteRequest(BaseModel):
    asset_ids: List[str]

class BulkUpdateCategoryRequest(BaseModel):
    asset_ids: List[str]
    category: str

@router.post("/bulk-delete")
def bulk_delete_endpoint(
    req: BulkDeleteRequest,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    count = services.bulk_delete_assets(db, req.asset_ids)
    return {"success": True, "message": f"Successfully deleted {count} furniture assets"}

@router.post("/bulk-update-category")
def bulk_update_category_endpoint(
    req: BulkUpdateCategoryRequest,
    current_user: User = Depends(RoleChecker(["Administrator"])),
    db: Session = Depends(get_db)
):
    if not req.category or not req.category.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Category name cannot be empty"
        )
    count = services.bulk_update_category(db, req.asset_ids, req.category.strip())
    return {"success": True, "message": f"Successfully updated category of {count} assets"}


