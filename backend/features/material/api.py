from fastapi import APIRouter, Depends, HTTPException, status, Query, File, UploadFile
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user
from features.auth.models import User
from typing import List, Optional
import os
import shutil
import uuid

from .schemas import (
    MaterialOut, MaterialCreate, MaterialUpdate, MaterialCategoryOut,
    MaterialCategoryCreate, MaterialResponse, MaterialListResponse, CategoryListResponse
)
from .services import MaterialService

router = APIRouter(prefix="/materials", tags=["Materials"])

@router.get("", response_model=MaterialListResponse)
def list_materials(
    search: Optional[str] = Query(None, description="Search materials by name"),
    category: Optional[str] = Query(None, description="Filter materials by category name"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    materials, total = MaterialService.list_materials(
        db, search=search, category_name=category, page=page, limit=limit
    )
    return MaterialListResponse(
        success=True,
        total=total,
        page=page,
        limit=limit,
        data=materials
    )

@router.get("/categories", response_model=CategoryListResponse)
def list_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    categories = MaterialService.list_categories(db)
    return CategoryListResponse(
        success=True,
        data=categories
    )

@router.get("/{material_id}", response_model=MaterialResponse)
def get_material(
    material_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    material = MaterialService.get_material(db, material_id)
    if not material:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Material not found"
        )
    return MaterialResponse(
        success=True,
        data=material
    )

@router.post("", response_model=MaterialResponse, status_code=status.HTTP_201_CREATED)
def create_material(
    material_data: MaterialCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        material = MaterialService.create_material(db, material_data)
        return MaterialResponse(
            success=True,
            message="Material created successfully.",
            data=material
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.put("/{material_id}", response_model=MaterialResponse)
def update_material(
    material_id: str,
    material_data: MaterialUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        material = MaterialService.update_material(db, material_id, material_data)
        if not material:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Material not found"
            )
        return MaterialResponse(
            success=True,
            message="Material updated successfully.",
            data=material
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.delete("/{material_id}", response_model=MaterialResponse)
def delete_material(
    material_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    success = MaterialService.delete_material(db, material_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Material not found"
        )
    return MaterialResponse(
        success=True,
        message="Material deleted successfully."
    )

@router.post("/categories", response_model=CategoryListResponse, status_code=status.HTTP_201_CREATED)
def create_category(
    category_data: MaterialCategoryCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    MaterialService.create_category(db, category_data)
    categories = MaterialService.list_categories(db)
    return CategoryListResponse(
        success=True,
        data=categories
    )


def validate_image_file(file: UploadFile, max_size: int = 5 * 1024 * 1024):
    allowed_extensions = {".png", ".jpg", ".jpeg", ".webp"}
    _, ext = os.path.splitext(file.filename.lower())
    if ext not in allowed_extensions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file extension {ext}. Allowed: {', '.join(allowed_extensions)}"
        )
    # Check file size (approximate)
    file.file.seek(0, 2)
    size = file.file.tell()
    file.file.seek(0)
    if size > max_size:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File exceeds maximum size of {max_size / (1024 * 1024):.1f}MB"
        )


@router.post("/{material_id}/upload-preview", response_model=MaterialResponse)
def upload_preview(
    material_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    material = MaterialService.get_material(db, material_id)
    if not material:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Material not found"
        )
    
    validate_image_file(file)
    
    static_dir = os.path.join("uploads", "materials", "previews", material_id)
    os.makedirs(static_dir, exist_ok=True)
    file_path = os.path.join(static_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    rel_path = f"/uploads/materials/previews/{material_id}/{file.filename}"
    
    if material.preview_image and material.preview_image.startswith("/uploads/"):
        old_path = material.preview_image.lstrip("/")
        if os.path.exists(old_path):
            try:
                os.remove(old_path)
            except Exception:
                pass
                
    material.preview_image = rel_path
    db.commit()
    db.refresh(material)
    return MaterialResponse(success=True, data=material)


@router.post("/{material_id}/upload-texture", response_model=MaterialResponse)
def upload_texture(
    material_id: str,
    texture_type: str = Query(..., description="base_color, normal, roughness, metallic"),
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    material = MaterialService.get_material(db, material_id)
    if not material:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Material not found"
        )
        
    validate_image_file(file)
    
    static_dir = os.path.join("uploads", "materials", "textures", material_id, texture_type)
    os.makedirs(static_dir, exist_ok=True)
    file_path = os.path.join(static_dir, file.filename)
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    rel_path = f"/uploads/materials/textures/{material_id}/{texture_type}/{file.filename}"
    
    from features.material.models import MaterialTexture
    existing_tex = db.query(MaterialTexture).filter(
        MaterialTexture.material_id == material_id,
        MaterialTexture.texture_type == texture_type
    ).first()
    
    if existing_tex:
        if existing_tex.file_path.startswith("/uploads/"):
            old_path = existing_tex.file_path.lstrip("/")
            if os.path.exists(old_path):
                try:
                    os.remove(old_path)
                except Exception:
                    pass
        existing_tex.file_path = rel_path
    else:
        new_tex = MaterialTexture(
            id=str(uuid.uuid4()),
            material_id=material_id,
            texture_type=texture_type,
            file_path=rel_path
        )
        db.add(new_tex)
        
    db.commit()
    db.refresh(material)
    return MaterialResponse(success=True, data=material)
