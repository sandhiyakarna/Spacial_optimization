from pydantic import BaseModel, ConfigDict, Field
from typing import Optional, List
from datetime import datetime

class MaterialCategoryBase(BaseModel):
    name: str = Field(..., max_length=50)

class MaterialCategoryCreate(MaterialCategoryBase):
    pass

class MaterialCategoryOut(MaterialCategoryBase):
    id: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MaterialTextureBase(BaseModel):
    texture_type: str = Field(..., max_length=50, description="base_color, normal, roughness, metallic")
    file_path: str = Field(..., max_length=255)

class MaterialTextureCreate(MaterialTextureBase):
    pass

class MaterialTextureOut(MaterialTextureBase):
    id: str
    material_id: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MaterialBase(BaseModel):
    name: str = Field(..., max_length=100)
    category_id: str
    base_color: Optional[str] = Field(None, max_length=30)
    preview_image: Optional[str] = Field(None, max_length=255)
    opacity: float = Field(1.0, ge=0.0, le=1.0)
    reflectivity: float = Field(0.0, ge=0.0, le=1.0)
    default_scale: float = Field(1.0, gt=0.0)

class MaterialCreate(MaterialBase):
    textures: List[MaterialTextureCreate] = []

class MaterialUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    category_id: Optional[str] = None
    base_color: Optional[str] = Field(None, max_length=30)
    preview_image: Optional[str] = Field(None, max_length=255)
    opacity: Optional[float] = Field(None, ge=0.0, le=1.0)
    reflectivity: Optional[float] = Field(None, ge=0.0, le=1.0)
    default_scale: Optional[float] = Field(None, gt=0.0)
    textures: Optional[List[MaterialTextureCreate]] = None

class MaterialOut(MaterialBase):
    id: str
    created_at: datetime
    category: MaterialCategoryOut
    textures: List[MaterialTextureOut] = []

    model_config = ConfigDict(from_attributes=True)


# Wrapped Response schemas
class MaterialResponse(BaseModel):
    success: bool
    message: Optional[str] = None
    data: Optional[MaterialOut] = None

class MaterialListResponse(BaseModel):
    success: bool
    total: int
    page: int
    limit: int
    data: List[MaterialOut]

class CategoryListResponse(BaseModel):
    success: bool
    data: List[MaterialCategoryOut]
