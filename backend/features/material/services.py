import uuid
import os
import shutil
from datetime import datetime, timezone
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional, Tuple
from .models import MaterialCategory, Material, MaterialTexture
from .schemas import MaterialCreate, MaterialUpdate, MaterialCategoryCreate

class MaterialService:
    @staticmethod
    def get_category_by_name(db: Session, name: str) -> Optional[MaterialCategory]:
        return db.query(MaterialCategory).filter(MaterialCategory.name == name).first()

    @staticmethod
    def create_category(db: Session, category_data: MaterialCategoryCreate) -> MaterialCategory:
        existing = db.query(MaterialCategory).filter(MaterialCategory.name == category_data.name).first()
        if existing:
            return existing
        db_cat = MaterialCategory(
            id=str(uuid.uuid4()),
            name=category_data.name
        )
        db.add(db_cat)
        db.commit()
        db.refresh(db_cat)
        return db_cat

    @staticmethod
    def list_categories(db: Session) -> List[MaterialCategory]:
        return db.query(MaterialCategory).order_by(MaterialCategory.name).all()

    @staticmethod
    def get_material(db: Session, material_id: str) -> Optional[Material]:
        return db.query(Material).filter(Material.id == material_id).first()

    @staticmethod
    def list_materials(
        db: Session,
        search: Optional[str] = None,
        category_name: Optional[str] = None,
        page: int = 1,
        limit: int = 20
    ) -> Tuple[List[Material], int]:
        query = db.query(Material)

        if search:
            query = query.filter(Material.name.ilike(f"%{search}%"))

        if category_name:
            query = query.join(MaterialCategory).filter(MaterialCategory.name == category_name)

        total = query.count()
        offset = (page - 1) * limit
        materials = query.order_by(Material.name).offset(offset).limit(limit).all()
        return materials, total

    @staticmethod
    def create_material(db: Session, material_data: MaterialCreate) -> Material:
        # Validate category
        category = db.query(MaterialCategory).filter(MaterialCategory.id == material_data.category_id).first()
        if not category:
            raise ValueError(f"Category with id {material_data.category_id} not found")

        material_id = str(uuid.uuid4())
        db_material = Material(
            id=material_id,
            name=material_data.name,
            category_id=material_data.category_id,
            base_color=material_data.base_color,
            preview_image=material_data.preview_image,
            opacity=material_data.opacity,
            reflectivity=material_data.reflectivity,
            default_scale=material_data.default_scale
        )
        db.add(db_material)

        for tex in material_data.textures:
            db_tex = MaterialTexture(
                id=str(uuid.uuid4()),
                material_id=material_id,
                texture_type=tex.texture_type,
                file_path=tex.file_path
            )
            db.add(db_tex)

        db.commit()
        db.refresh(db_material)
        return db_material

    @staticmethod
    def update_material(db: Session, material_id: str, material_data: MaterialUpdate) -> Optional[Material]:
        db_material = db.query(Material).filter(Material.id == material_id).first()
        if not db_material:
            return None

        update_dict = material_data.model_dump(exclude_unset=True)
        
        # Check category validation if updating it
        if "category_id" in update_dict and update_dict["category_id"]:
            category = db.query(MaterialCategory).filter(MaterialCategory.id == update_dict["category_id"]).first()
            if not category:
                raise ValueError(f"Category with id {update_dict['category_id']} not found")

        # Update core fields
        for key, value in update_dict.items():
            if key != "textures":
                setattr(db_material, key, value)

        # Update textures if supplied
        if "textures" in update_dict and update_dict["textures"] is not None:
            # Delete old textures
            db.query(MaterialTexture).filter(MaterialTexture.material_id == material_id).delete()
            # Add new textures
            for tex in update_dict["textures"]:
                db_tex = MaterialTexture(
                    id=str(uuid.uuid4()),
                    material_id=material_id,
                    texture_type=tex["texture_type"],
                    file_path=tex["file_path"]
                )
                db.add(db_tex)

        db.commit()
        db.refresh(db_material)
        return db_material

    @staticmethod
    def delete_material(db: Session, material_id: str) -> bool:
        db_material = db.query(Material).filter(Material.id == material_id).first()
        if not db_material:
            return False
            
        # Collect paths to clean up
        paths_to_delete = []
        if db_material.preview_image and db_material.preview_image.startswith("/uploads/"):
            paths_to_delete.append(db_material.preview_image.lstrip("/"))
        for tex in db_material.textures:
            if tex.file_path and tex.file_path.startswith("/uploads/"):
                paths_to_delete.append(tex.file_path.lstrip("/"))
                
        preview_dir = os.path.join("uploads", "materials", "previews", material_id)
        texture_dir = os.path.join("uploads", "materials", "textures", material_id)
        
        db.delete(db_material)
        db.commit()
        
        # Delete files and folders
        for p in paths_to_delete:
            if os.path.exists(p):
                try:
                    os.remove(p)
                except Exception:
                    pass
        if os.path.exists(preview_dir):
            try:
                shutil.rmtree(preview_dir)
            except Exception:
                pass
        if os.path.exists(texture_dir):
            try:
                shutil.rmtree(texture_dir)
            except Exception:
                pass
                
        return True

    @staticmethod
    def seed_default_materials(db: Session):
        # Quick check: if materials already exist, skip seeding to optimize startup time
        from features.material.models import Material
        if db.query(Material).first() is not None:
            return
            
        # 1. Seed Categories
        categories = ["Wood", "Marble", "Granite", "Concrete", "Metal", "Glass", "Leather", "Fabric", "Ceramic", "Paint"]
        cat_map = {}
        for cat_name in categories:
            cat = db.query(MaterialCategory).filter(MaterialCategory.name == cat_name).first()
            if not cat:
                cat = MaterialCategory(id=str(uuid.uuid4()), name=cat_name)
                db.add(cat)
                db.commit()
                db.refresh(cat)
            cat_map[cat_name] = cat.id

        # 2. Seed Default Materials (at least one for each category)
        default_materials_data = [
            {
                "name": "Oak Wood",
                "category": "Wood",
                "base_color": "#D27D2D",
                "preview_image": "/static/materials/oak_wood_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.1,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/wood_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/wood_normal.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/wood_roughness.png"}
                ]
            },
            {
                "name": "Walnut Wood",
                "category": "Wood",
                "base_color": "#5C4033",
                "preview_image": "/static/materials/walnut_wood_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.2,
                "default_scale": 1.2,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/walnut_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/walnut_normal.png"}
                ]
            },
            {
                "name": "Carrara Marble",
                "category": "Marble",
                "base_color": "#F2F3F4",
                "preview_image": "/static/materials/carrara_marble_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.8,
                "default_scale": 2.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/marble_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/marble_normal.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/marble_roughness.png"}
                ]
            },
            {
                "name": "Black Granite",
                "category": "Granite",
                "base_color": "#1A1A1A",
                "preview_image": "/static/materials/black_granite_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.7,
                "default_scale": 1.5,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/granite_base.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/granite_roughness.png"}
                ]
            },
            {
                "name": "Polished Concrete",
                "category": "Concrete",
                "base_color": "#808080",
                "preview_image": "/static/materials/concrete_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.3,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/concrete_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/concrete_normal.png"}
                ]
            },
            {
                "name": "Brushed Steel",
                "category": "Metal",
                "base_color": "#C0C0C0",
                "preview_image": "/static/materials/steel_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.9,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/steel_base.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/steel_roughness.png"},
                    {"texture_type": "metallic", "file_path": "/static/textures/steel_metallic.png"}
                ]
            },
            {
                "name": "Polished Brass",
                "category": "Metal",
                "base_color": "#B5A642",
                "preview_image": "/static/materials/brass_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.95,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/brass_base.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/brass_roughness.png"},
                    {"texture_type": "metallic", "file_path": "/static/textures/brass_metallic.png"}
                ]
            },
            {
                "name": "Clear Glass",
                "category": "Glass",
                "base_color": "#FFFFFF",
                "preview_image": "/static/materials/clear_glass_preview.png",
                "opacity": 0.1,
                "reflectivity": 0.9,
                "default_scale": 1.0,
                "textures": []
            },
            {
                "name": "Frosted Glass",
                "category": "Glass",
                "base_color": "#E0EEEE",
                "preview_image": "/static/materials/frosted_glass_preview.png",
                "opacity": 0.4,
                "reflectivity": 0.5,
                "default_scale": 1.0,
                "textures": []
            },
            {
                "name": "Brown Leather",
                "category": "Leather",
                "base_color": "#964B00",
                "preview_image": "/static/materials/brown_leather_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.15,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/leather_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/leather_normal.png"},
                    {"texture_type": "roughness", "file_path": "/static/textures/leather_roughness.png"}
                ]
            },
            {
                "name": "Black Leather",
                "category": "Leather",
                "base_color": "#252525",
                "preview_image": "/static/materials/black_leather_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.1,
                "default_scale": 1.0,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/leather_black_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/leather_black_normal.png"}
                ]
            },
            {
                "name": "Linen Fabric",
                "category": "Fabric",
                "base_color": "#FAF0E6",
                "preview_image": "/static/materials/linen_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.0,
                "default_scale": 0.5,
                "textures": [
                    {"texture_type": "base_color", "file_path": "/static/textures/linen_base.png"},
                    {"texture_type": "normal", "file_path": "/static/textures/linen_normal.png"}
                ]
            },
            {
                "name": "White Ceramic",
                "category": "Ceramic",
                "base_color": "#FFFFFF",
                "preview_image": "/static/materials/ceramic_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.8,
                "default_scale": 1.0,
                "textures": []
            },
            {
                "name": "Matte White Paint",
                "category": "Paint",
                "base_color": "#F8F8FF",
                "preview_image": "/static/materials/white_paint_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.05,
                "default_scale": 1.0,
                "textures": []
            },
            {
                "name": "Teal Paint",
                "category": "Paint",
                "base_color": "#008080",
                "preview_image": "/static/materials/teal_paint_preview.png",
                "opacity": 1.0,
                "reflectivity": 0.05,
                "default_scale": 1.0,
                "textures": []
            }
        ]

        for mat_data in default_materials_data:
            existing_mat = db.query(Material).filter(Material.name == mat_data["name"]).first()
            if not existing_mat:
                cat_id = cat_map[mat_data["category"]]
                mat = Material(
                    id=str(uuid.uuid4()),
                    name=mat_data["name"],
                    category_id=cat_id,
                    base_color=mat_data["base_color"],
                    preview_image=mat_data["preview_image"],
                    opacity=mat_data["opacity"],
                    reflectivity=mat_data["reflectivity"],
                    default_scale=mat_data["default_scale"]
                )
                db.add(mat)
                db.commit()
                db.refresh(mat)

                for tex in mat_data["textures"]:
                    db_tex = MaterialTexture(
                        id=str(uuid.uuid4()),
                        material_id=mat.id,
                        texture_type=tex["texture_type"],
                        file_path=tex["file_path"]
                    )
                    db.add(db_tex)
                db.commit()
