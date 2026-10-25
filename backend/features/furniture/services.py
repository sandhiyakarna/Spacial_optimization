import os
import json
import struct
from typing import List, Optional, Set
from datetime import datetime, timezone
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session
from .models import Asset, FurnitureAsset, FurnitureCategory, FurnitureMaterial, FurnitureFavorite, FurnitureRecent
from features.material.models import Material
from .schemas import FurnitureAssetCreate, FurnitureAssetUpdate

def generate_minimal_glb() -> bytes:
    # 1. JSON Chunk containing minimal glTF structure
    json_data = {"asset": {"version": "2.0"}}
    json_bytes = json.dumps(json_data).encode("utf-8")
    
    # Pad JSON bytes to a multiple of 4 with space characters
    padding = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * padding
    
    chunk_length = len(json_bytes)
    chunk_type = b"JSON" # JSON chunk type marker (0x4E4F534A)
    
    # 2. Pack the GLB structure
    # Header: magic ("glTF" = 0x46546c67), version (2), total length (12 header + 8 chunk header + chunk length)
    header_magic = b"glTF"
    version = 2
    total_length = 12 + 8 + chunk_length
    
    header = struct.pack("<4sII", header_magic, version, total_length)
    chunk_header = struct.pack("<I4s", chunk_length, chunk_type)
    
    return header + chunk_header + json_bytes

def generate_minimal_png() -> bytes:
    # 1x1 transparent PNG bytes
    return b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82'

def seed_furniture_assets(db: Session):
    # Ensure uploads production directories exist
    static_dir = os.path.join("uploads", "furniture")
    os.makedirs(os.path.join(static_dir, "models"), exist_ok=True)
    os.makedirs(os.path.join(static_dir, "thumbnails"), exist_ok=True)
    os.makedirs(os.path.join(static_dir, "previews"), exist_ok=True)
    
    # Seed default categories with parent-child relationships
    default_categories = [
        {"name": "Furniture", "description": "General furniture items", "parent_name": None},
        {"name": "Living Room", "description": "Furniture for living area layouts", "parent_name": "Furniture"},
        {"name": "Office", "description": "Ergonomic furniture for office workspaces", "parent_name": "Furniture"},
        {"name": "Kitchen", "description": "Kitchen counters, sinks, appliances, and pantry storage", "parent_name": "Furniture"},
        {"name": "Dining", "description": "Dining tables, chairs, and dining storage", "parent_name": "Furniture"},
        {"name": "Dining Room", "description": "Dining tables, chairs, and dining storage", "parent_name": "Furniture"},
        {"name": "Bedroom", "description": "Beds and bedroom storage layouts", "parent_name": "Furniture"},
        {"name": "Bathroom", "description": "Vanities, basins, mirrors, and bathroom storage", "parent_name": "Furniture"},
        {"name": "Lighting", "description": "Lighting fixtures and lamps", "parent_name": None},
        {"name": "Decor", "description": "Decorative mirrors, paintings, vases", "parent_name": None},
        {"name": "Plants", "description": "Biophilic design plants and trees", "parent_name": None},
    ]
    
    categories_map = {}
    for cat_data in default_categories:
        cat = db.query(FurnitureCategory).filter(FurnitureCategory.name == cat_data["name"]).first()
        if not cat:
            cat = FurnitureCategory(name=cat_data["name"], description=cat_data["description"])
            db.add(cat)
            db.commit()
            db.refresh(cat)
        categories_map[cat_data["name"]] = cat

    for cat_data in default_categories:
        if cat_data["parent_name"]:
            parent = categories_map.get(cat_data["parent_name"])
            child = categories_map.get(cat_data["name"])
            if parent and child and child.parent_id != parent.id:
                child.parent_id = parent.id
                db.commit()

    # Default furniture data list (including mock assets from frontend)
    default_assets = [
        {
            "id": "SOFA001",
            "name": "Modern Sofa",
            "category": "Living Room",
            "style": "Modern",
            "width": 210.0,
            "depth": 90.0,
            "height": 85.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "modern,fabric,3-seater,living-room",
        },
        {
            "id": "CHAIR001",
            "name": "Ergonomic Office Chair",
            "category": "Office",
            "style": "Modern",
            "width": 65.0,
            "depth": 65.0,
            "height": 102.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "ergonomic,chair,mesh,adjustable,office",
        },
        {
            "id": "TABLE001",
            "name": "Scandinavian Dining Table",
            "category": "Dining",
            "style": "Scandinavian",
            "width": 160.0,
            "depth": 90.0,
            "height": 75.0,
            "clearance": 70.0,
            "assembly_clearance": 90.0,
            "tags": "wooden,dining,table,scandinavian",
        },
        {
            "id": "DINING_CHAIR001",
            "name": "Scandinavian Dining Chair",
            "category": "Dining",
            "style": "Scandinavian",
            "width": 50.0,
            "depth": 50.0,
            "height": 85.0,
            "clearance": 50.0,
            "assembly_clearance": 60.0,
            "tags": "dining,chair,scandinavian,wood,fabric",
        },
        {
            "id": "BED001",
            "name": "Minimalist King Bed",
            "category": "Bedroom",
            "style": "Minimal",
            "width": 200.0,
            "depth": 220.0,
            "height": 45.0,
            "clearance": 50.0,
            "assembly_clearance": 100.0,
            "tags": "king-size,bed,minimalist,bedroom,wooden",
        },
        {
            "id": "STAND001",
            "name": "Minimalist Nightstand",
            "category": "Bedroom",
            "style": "Minimal",
            "width": 50.0,
            "depth": 40.0,
            "height": 55.0,
            "clearance": 10.0,
            "assembly_clearance": 10.0,
            "tags": "nightstand,table,minimalist,bedroom,wooden",
        },
        {
            "id": "WARDROBE001",
            "name": "Minimalist Wardrobe",
            "category": "Bedroom",
            "style": "Minimal",
            "width": 100.0,
            "depth": 60.0,
            "height": 180.0,
            "clearance": 80.0,
            "assembly_clearance": 100.0,
            "tags": "wardrobe,closet,cabinet,minimalist,bedroom,wooden",
        },
        {
            "id": "DESK001",
            "name": "Industrial Study Desk",
            "category": "Office",
            "style": "Industrial",
            "width": 120.0,
            "depth": 60.0,
            "height": 76.0,
            "clearance": 40.0,
            "assembly_clearance": 50.0,
            "tags": "desk,study,industrial,metal,wood,office",
        },
        {
            "id": "EXEC_DESK001",
            "name": "Executive Manager Desk",
            "category": "Office",
            "style": "Modern",
            "width": 180.0,
            "depth": 90.0,
            "height": 76.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "executive,desk,manager,office,wooden",
        },
        {
            "id": "EXEC_CHAIR001",
            "name": "Ergonomic Manager Chair",
            "category": "Office",
            "style": "Modern",
            "width": 70.0,
            "depth": 70.0,
            "height": 110.0,
            "clearance": 30.0,
            "assembly_clearance": 40.0,
            "tags": "executive,manager,chair,ergonomic,office,leather",
        },
        {
            "id": "VISITOR_CHAIR001",
            "name": "Executive Visitor Chair",
            "category": "Office",
            "style": "Modern",
            "width": 60.0,
            "depth": 60.0,
            "height": 85.0,
            "clearance": 20.0,
            "assembly_clearance": 30.0,
            "tags": "visitor,chair,guest,office",
        },
        {
            "id": "OFFICE_CABINET001",
            "name": "Executive Storage Cabinet",
            "category": "Office",
            "style": "Modern",
            "width": 100.0,
            "depth": 50.0,
            "height": 120.0,
            "clearance": 50.0,
            "assembly_clearance": 60.0,
            "tags": "cabinet,storage,credenza,office,wooden",
        },
        {
            "id": "BOOKSHELF001",
            "name": "Executive Bookshelf Unit",
            "category": "Office",
            "style": "Modern",
            "width": 100.0,
            "depth": 40.0,
            "height": 180.0,
            "clearance": 40.0,
            "assembly_clearance": 60.0,
            "tags": "bookshelf,bookcase,storage,office,wooden",
        },
        {
            "id": "LIGHT_001",
            "name": "Floor Lamp",
            "category": "Lighting",
            "subcategory": "Lamps",
            "style": "Modern",
            "width": 40.0,
            "depth": 40.0,
            "height": 160.0,
            "clearance": 10.0,
            "assembly_clearance": 10.0,
            "tags": "lamp,floor,light,lighting",
        },
        {
            "id": "LIGHT_002",
            "name": "Table Lamp",
            "category": "Lighting",
            "subcategory": "Lamps",
            "style": "Modern",
            "width": 30.0,
            "depth": 30.0,
            "height": 50.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "lamp,table,light,lighting",
        },
        {
            "id": "LIGHT_003",
            "name": "Ceiling Pendant Light",
            "category": "Lighting",
            "subcategory": "Ceiling",
            "style": "Modern",
            "width": 50.0,
            "depth": 50.0,
            "height": 80.0,
            "clearance": 20.0,
            "assembly_clearance": 20.0,
            "tags": "pendant,ceiling,light,lighting",
        },
        {
            "id": "DECOR_001",
            "name": "Abstract Wall Painting",
            "category": "Decor",
            "subcategory": "Wall Art",
            "style": "Modern",
            "width": 120.0,
            "depth": 5.0,
            "height": 90.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "painting,wall,art,decor",
        },
        {
            "id": "DECOR_002",
            "name": "Round Wall Mirror",
            "category": "Decor",
            "subcategory": "Mirrors",
            "style": "Modern",
            "width": 80.0,
            "depth": 5.0,
            "height": 80.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "mirror,wall,decor",
        },
        {
            "id": "KITCHEN_COUNTER001",
            "name": "Modular Kitchen Counter",
            "category": "Kitchen",
            "subcategory": "Counters",
            "style": "Modern",
            "width": 180.0,
            "depth": 60.0,
            "height": 90.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "kitchen,counter,modular,storage",
        },
        {
            "id": "CABINET001",
            "name": "Kitchen Storage Cabinet",
            "category": "Kitchen",
            "subcategory": "Storage",
            "style": "Modern",
            "width": 100.0,
            "depth": 50.0,
            "height": 190.0,
            "clearance": 70.0,
            "assembly_clearance": 80.0,
            "tags": "kitchen,cabinet,storage,pantry",
        },
        {
            "id": "FRIDGE001",
            "name": "Refrigerator Unit",
            "category": "Kitchen",
            "subcategory": "Appliances",
            "style": "Modern",
            "width": 80.0,
            "depth": 70.0,
            "height": 185.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "kitchen,fridge,refrigerator,appliance",
        },
        {
            "id": "SINK001",
            "name": "Kitchen Sink Station",
            "category": "Kitchen",
            "subcategory": "Counters",
            "style": "Modern",
            "width": 120.0,
            "depth": 60.0,
            "height": 90.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "kitchen,sink,counter,plumbing",
        },
        {
            "id": "KITCHEN_STOVE001",
            "name": "Kitchen Cooking Range & Stove",
            "category": "Kitchen",
            "subcategory": "Appliances",
            "style": "Modern",
            "width": 80.0,
            "depth": 60.0,
            "height": 90.0,
            "clearance": 60.0,
            "assembly_clearance": 80.0,
            "tags": "kitchen,stove,cooktop,oven,range,appliance",
        },
        {
            "id": "BATH_VANITY001",
            "name": "Bathroom Vanity Unit",
            "category": "Bathroom",
            "subcategory": "Vanity",
            "style": "Modern",
            "width": 100.0,
            "depth": 50.0,
            "height": 85.0,
            "clearance": 50.0,
            "assembly_clearance": 60.0,
            "tags": "bathroom,vanity,sink,mirror,cabinet",
        },
        {
            "id": "COFFEE001",
            "name": "Modern Coffee Table",
            "category": "Living Room",
            "style": "Modern",
            "width": 100.0,
            "depth": 60.0,
            "height": 45.0,
            "clearance": 45.0,
            "assembly_clearance": 60.0,
            "tags": "coffee-table,table,living-room,wood",
        },
        {
            "id": "TV001",
            "name": "Modern TV Console",
            "category": "Living Room",
            "style": "Modern",
            "width": 150.0,
            "depth": 40.0,
            "height": 60.0,
            "clearance": 50.0,
            "assembly_clearance": 60.0,
            "tags": "tv-unit,console,entertainment,media,living-room",
        },
        {
            "id": "DECOR_003",
            "name": "Ceramic Floor Vase",
            "category": "Decor",
            "subcategory": "Vase",
            "style": "Minimal",
            "width": 35.0,
            "depth": 35.0,
            "height": 70.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "vase,floor,ceramic,decor",
        },
        {
            "id": "PLANT_001",
            "name": "Monstera Plant",
            "category": "Plants",
            "subcategory": "Potted Plants",
            "style": "Biophilic",
            "width": 60.0,
            "depth": 60.0,
            "height": 100.0,
            "clearance": 10.0,
            "assembly_clearance": 10.0,
            "tags": "monstera,plant,biophilic,green",
        },
        {
            "id": "PLANT_002",
            "name": "Fiddle Leaf Fig Tree",
            "category": "Plants",
            "subcategory": "Trees",
            "style": "Biophilic",
            "width": 50.0,
            "depth": 50.0,
            "height": 150.0,
            "clearance": 10.0,
            "assembly_clearance": 10.0,
            "tags": "fig,tree,plant,biophilic,green",
        },
        {
            "id": "PLANT_003",
            "name": "Snake Plant in Pot",
            "category": "Plants",
            "subcategory": "Potted Plants",
            "style": "Biophilic",
            "width": 30.0,
            "depth": 30.0,
            "height": 80.0,
            "clearance": 5.0,
            "assembly_clearance": 5.0,
            "tags": "snake,plant,biophilic,green",
        }
    ]
    
    from generate_furniture_glbs import FURNITURE_SHAPES, generate_glb_binary
    png_bytes = generate_minimal_png()
    
    for item in default_assets:
        glb_path = f"uploads/furniture/models/{item['id']}.glb"
        thumb_path = f"uploads/furniture/thumbnails/{item['id']}.png"
        
        # Generate valid 3D GLB mesh if missing or minimal
        if not os.path.exists(glb_path) or os.path.getsize(glb_path) < 500:
            if item['id'] in FURNITURE_SHAPES:
                boxes, color = FURNITURE_SHAPES[item['id']]
                item_glb_bytes = generate_glb_binary(boxes, color)
            else:
                boxes = [(0.0, item['height'] / 2.0, 0.0, item['width'], item['height'], item['depth'])]
                item_glb_bytes = generate_glb_binary(boxes)
            with open(glb_path, "wb") as f:
                f.write(item_glb_bytes)
                
        if not os.path.exists(thumb_path):
            with open(thumb_path, "wb") as f:
                f.write(png_bytes)
            
        glb_url = f"/uploads/furniture/models/{item['id']}.glb"
        thumbnail_url = f"/uploads/furniture/thumbnails/{item['id']}.png"
        
        cat_obj = categories_map.get(item["category"])
        category_id = cat_obj.id if cat_obj else None

        # Check if asset already exists in DB
        existing_asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == item["id"]).first()
        if existing_asset:
            existing_asset.name = item["name"]
            existing_asset.category = item["category"]
            existing_asset.category_id = category_id
            existing_asset.subcategory = item.get("subcategory")
            existing_asset.tags = item["tags"]
            existing_asset.width = item["width"]
            existing_asset.depth = item["depth"]
            existing_asset.height = item["height"]
            existing_asset.glb_url = glb_url
            existing_asset.thumbnail_url = thumbnail_url
            existing_asset.model_path = glb_path
            existing_asset.thumbnail_path = thumb_path
            continue

        # Create central Asset records
        model_asset = db.query(Asset).filter(Asset.id == f"model_{item['id']}").first()
        if not model_asset:
            model_asset = Asset(
                id=f"model_{item['id']}",
                name=f"{item['name']} GLB Model",
                type="model",
                file_type="glb",
                model_path=glb_path
            )
            db.add(model_asset)
        
        thumb_asset = db.query(Asset).filter(Asset.id == f"thumb_{item['id']}").first()
        if not thumb_asset:
            thumb_asset = Asset(
                id=f"thumb_{item['id']}",
                name=f"{item['name']} Thumbnail",
                type="thumbnail",
                file_type="png",
                thumbnail_path=thumb_path
            )
            db.add(thumb_asset)
        db.commit()
        
        cat_obj = categories_map.get(item["category"])
        category_id = cat_obj.id if cat_obj else None

        db_asset = FurnitureAsset(
            id=item["id"],
            name=item["name"],
            category=item["category"],
            category_id=category_id,
            subcategory=item.get("subcategory"),
            style=item["style"],
            width=item["width"],
            depth=item["depth"],
            height=item["height"],
            clearance=item["clearance"],
            assembly_clearance=item["assembly_clearance"],
            tags=item["tags"],
            glb_url=glb_url,
            thumbnail_url=thumbnail_url,
            model_path=glb_path,
            thumbnail_path=thumb_path,
            model_asset_id=model_asset.id,
            thumbnail_asset_id=thumb_asset.id
        )
        db.add(db_asset)
        
    db.commit()

def list_furniture_assets(
    db: Session,
    search: Optional[str] = None,
    category: Optional[str] = None,
    style: Optional[str] = None,
    favorites_only: bool = False,
    user_id: Optional[str] = None,
    page: int = 1,
    limit: int = 20
) -> List[FurnitureAsset]:
    query = db.query(FurnitureAsset)
    
    if favorites_only and user_id:
        query = query.join(FurnitureFavorite).filter(FurnitureFavorite.user_id == user_id)
        
    if category:
        query = query.join(FurnitureCategory, isouter=True).filter(
            or_(
                FurnitureAsset.category == category,
                FurnitureAsset.category_id == category,
                FurnitureCategory.name == category,
                FurnitureCategory.parent.has(name=category)
            )
        )
        
    if style:
        query = query.filter(FurnitureAsset.style == style)
        
    if search:
        search_filter = f"%{search}%"
        query = query.join(FurnitureCategory, isouter=True).filter(
            or_(
                FurnitureAsset.name.ilike(search_filter),
                FurnitureAsset.tags.ilike(search_filter),
                FurnitureAsset.style.ilike(search_filter),
                FurnitureCategory.name.ilike(search_filter)
            )
        )
        
    # Apply pagination
    query = query.offset((page - 1) * limit).limit(limit)
    assets = query.all()
    
    # Dynamically inject is_favorite
    if user_id:
        fav_ids = {f.furniture_id for f in db.query(FurnitureFavorite).filter(FurnitureFavorite.user_id == user_id).all()}
        for asset in assets:
            asset.is_favorite = asset.id in fav_ids
    else:
        for asset in assets:
            asset.is_favorite = False
            
    return assets

def get_furniture_asset(db: Session, asset_id: str, user_id: Optional[str] = None) -> Optional[FurnitureAsset]:
    asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not asset:
        return None
        
    if user_id:
        # Track usage
        log_furniture_usage(db, user_id, asset_id)
        
        # Set is_favorite
        fav = db.query(FurnitureFavorite).filter(
            FurnitureFavorite.user_id == user_id,
            FurnitureFavorite.furniture_id == asset_id
        ).first()
        asset.is_favorite = fav is not None
    else:
        asset.is_favorite = False
        
    return asset

def create_furniture_asset(db: Session, asset_in: FurnitureAssetCreate) -> FurnitureAsset:
    cat = db.query(FurnitureCategory).filter(FurnitureCategory.name == asset_in.category).first()
    if not cat:
        cat = FurnitureCategory(name=asset_in.category)
        db.add(cat)
        db.commit()
        db.refresh(cat)
        
    asset = FurnitureAsset(
        name=asset_in.name,
        category=asset_in.category,
        category_id=cat.id,
        subcategory=asset_in.subcategory,
        style=asset_in.style,
        width=asset_in.width,
        depth=asset_in.depth,
        height=asset_in.height,
        clearance=asset_in.clearance,
        assembly_clearance=asset_in.assembly_clearance,
        tags=asset_in.tags,
        glb_url=asset_in.glb_url or "",
        thumbnail_url=asset_in.thumbnail_url or "",
        preview_path=None
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return asset

def update_furniture_asset(db: Session, asset_id: str, asset_in: FurnitureAssetUpdate) -> Optional[FurnitureAsset]:
    asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not asset:
        return None
        
    update_data = asset_in.model_dump(exclude_unset=True)
    if "category" in update_data:
        cat_name = update_data["category"]
        cat = db.query(FurnitureCategory).filter(FurnitureCategory.name == cat_name).first()
        if not cat:
            cat = FurnitureCategory(name=cat_name)
            db.add(cat)
            db.commit()
            db.refresh(cat)
        asset.category_id = cat.id
        asset.category = cat_name
        
    for field, value in update_data.items():
        if field != "category":
            setattr(asset, field, value)
            
    db.commit()
    db.refresh(asset)
    return asset

def delete_furniture_asset(db: Session, asset_id: str) -> bool:
    import shutil
    asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
    if not asset:
        return False
        
    # Clean up associated physical files and Asset records
    # 1. Model Asset
    if asset.model_path and os.path.exists(asset.model_path):
        try:
            os.remove(asset.model_path)
            # Remove parent directory if empty
            parent_dir = os.path.dirname(asset.model_path)
            if os.path.exists(parent_dir) and not os.listdir(parent_dir):
                os.rmdir(parent_dir)
        except Exception as e:
            print(f"Error deleting GLB model file: {e}")
            
    if asset.model_asset:
        db.delete(asset.model_asset)
        
    # 2. Thumbnail Asset
    if asset.thumbnail_path and os.path.exists(asset.thumbnail_path):
        try:
            os.remove(asset.thumbnail_path)
            # Remove parent directory if empty
            parent_dir = os.path.dirname(asset.thumbnail_path)
            if os.path.exists(parent_dir) and not os.listdir(parent_dir):
                os.rmdir(parent_dir)
        except Exception as e:
            print(f"Error deleting thumbnail file: {e}")
            
    if asset.thumbnail_asset:
        db.delete(asset.thumbnail_asset)
        
    # 3. Preview Asset
    if asset.preview_path and os.path.exists(asset.preview_path):
        try:
            os.remove(asset.preview_path)
            # Remove parent directory if empty
            parent_dir = os.path.dirname(asset.preview_path)
            if os.path.exists(parent_dir) and not os.listdir(parent_dir):
                os.rmdir(parent_dir)
        except Exception as e:
            print(f"Error deleting preview file: {e}")
            
    if asset.preview_asset:
        db.delete(asset.preview_asset)
        
    db.delete(asset)
    db.commit()
    return True

def bulk_delete_assets(db: Session, asset_ids: List[str]) -> int:
    deleted_count = 0
    for asset_id in asset_ids:
        if delete_furniture_asset(db, asset_id):
            deleted_count += 1
    return deleted_count

def bulk_update_category(db: Session, asset_ids: List[str], category_name: str) -> int:
    cat = db.query(FurnitureCategory).filter(FurnitureCategory.name == category_name).first()
    if not cat:
        cat = FurnitureCategory(name=category_name)
        db.add(cat)
        db.commit()
        db.refresh(cat)
        
    updated_count = 0
    assets = db.query(FurnitureAsset).filter(FurnitureAsset.id.in_(asset_ids)).all()
    for asset in assets:
        asset.category_id = cat.id
        asset.category = cat.name
        updated_count += 1
        
    db.commit()
    return updated_count


# Categories
def list_categories(db: Session) -> List[FurnitureCategory]:
    return db.query(FurnitureCategory).all()

def create_category(db: Session, name: str, description: Optional[str] = None) -> FurnitureCategory:
    existing = db.query(FurnitureCategory).filter(FurnitureCategory.name == name).first()
    if existing:
        return existing
    cat = FurnitureCategory(name=name, description=description)
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return cat

# Favorites
def add_favorite(db: Session, user_id: str, furniture_id: str) -> bool:
    existing = db.query(FurnitureFavorite).filter(
        FurnitureFavorite.user_id == user_id,
        FurnitureFavorite.furniture_id == furniture_id
    ).first()
    if existing:
        return True
    fav = FurnitureFavorite(user_id=user_id, furniture_id=furniture_id)
    db.add(fav)
    db.commit()
    return True

def remove_favorite(db: Session, user_id: str, furniture_id: str) -> bool:
    fav = db.query(FurnitureFavorite).filter(
        FurnitureFavorite.user_id == user_id,
        FurnitureFavorite.furniture_id == furniture_id
    ).first()
    if fav:
        db.delete(fav)
        db.commit()
        return True
    return False

def list_favorite_furniture(db: Session, user_id: str, page: int = 1, limit: int = 20) -> List[FurnitureAsset]:
    favorites = db.query(FurnitureFavorite).filter(
        FurnitureFavorite.user_id == user_id
    ).offset((page - 1) * limit).limit(limit).all()
    
    assets = [fav.furniture for fav in favorites]
    for asset in assets:
        asset.is_favorite = True
    return assets

# Recents
def log_furniture_usage(db: Session, user_id: str, furniture_id: str):
    recent = db.query(FurnitureRecent).filter(
        FurnitureRecent.user_id == user_id,
        FurnitureRecent.furniture_id == furniture_id
    ).first()
    if recent:
        recent.last_used_at = datetime.now(timezone.utc)
    else:
        recent = FurnitureRecent(
            user_id=user_id,
            furniture_id=furniture_id,
            last_used_at=datetime.now(timezone.utc)
        )
        db.add(recent)
    db.commit()

def list_recent_furniture(db: Session, user_id: str, limit: int = 10) -> List[FurnitureAsset]:
    recents = db.query(FurnitureRecent).filter(
        FurnitureRecent.user_id == user_id
    ).order_by(FurnitureRecent.last_used_at.desc()).limit(limit).all()
    
    assets = [r.furniture for r in recents]
    fav_ids = {f.furniture_id for f in db.query(FurnitureFavorite).filter(FurnitureFavorite.user_id == user_id).all()}
    for asset in assets:
        asset.is_favorite = asset.id in fav_ids
    return assets


def update_category(db: Session, category_id: str, name: Optional[str] = None, description: Optional[str] = None) -> Optional[FurnitureCategory]:
    cat = db.query(FurnitureCategory).filter(FurnitureCategory.id == category_id).first()
    if not cat:
        return None
    if name is not None:
        cat.name = name
    if description is not None:
        cat.description = description
    db.commit()
    db.refresh(cat)
    return cat


def delete_category(db: Session, category_id: str) -> bool:
    cat = db.query(FurnitureCategory).filter(FurnitureCategory.id == category_id).first()
    if not cat:
        return False
    # Since category is nullable=False in FurnitureAsset, set it to "Uncategorized"
    assets = db.query(FurnitureAsset).filter(FurnitureAsset.category_id == category_id).all()
    for asset in assets:
        asset.category_id = None
        asset.category = "Uncategorized"
    db.delete(cat)
    db.commit()
    return True


def check_duplicate_asset(
    db: Session,
    name: str,
    category: str,
    style: str,
    width: float,
    depth: float,
    height: float,
    exclude_id: Optional[str] = None
) -> Optional[FurnitureAsset]:
    # 1. Exact name match (case-insensitive)
    query = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike(name))
    if exclude_id:
        query = query.filter(FurnitureAsset.id != exclude_id)
    match = query.first()
    if match:
        return match

    # 2. Dimensions similarity within 0.1cm tolerance inside same category and style
    query = db.query(FurnitureAsset).filter(
        FurnitureAsset.category.ilike(category),
        FurnitureAsset.style.ilike(style),
        FurnitureAsset.width.between(width - 0.1, width + 0.1),
        FurnitureAsset.depth.between(depth - 0.1, depth + 0.1),
        FurnitureAsset.height.between(height - 0.1, height + 0.1)
    )
    if exclude_id:
        query = query.filter(FurnitureAsset.id != exclude_id)
    return query.first()


from .schemas import FurnitureBulkImportRequest, FurnitureBulkImportResponse, BulkImportReportItem
import uuid

def bulk_import_assets(db: Session, req: FurnitureBulkImportRequest) -> FurnitureBulkImportResponse:
    report = []
    valid_count = 0
    invalid_count = 0
    duplicate_count = 0
    imported_count = 0
    
    # Cache categories
    categories_map = {c.name.lower(): c for c in db.query(FurnitureCategory).all()}
    
    for idx, item in enumerate(req.assets):
        errors = []
        status = "valid"
        duplicate_asset_id = None
        
        # Validation checks
        if not item.name or not item.name.strip():
            errors.append("Name cannot be empty")
        elif len(item.name) > 100:
            errors.append("Name must be 100 characters or less")
            
        if not item.category or not item.category.strip():
            errors.append("Category cannot be empty")
        elif len(item.category) > 50:
            errors.append("Category must be 50 characters or less")
            
        if not item.style or not item.style.strip():
            errors.append("Style cannot be empty")
        elif len(item.style) > 50:
            errors.append("Style must be 50 characters or less")
            
        if item.width <= 0:
            errors.append("Width must be a positive number")
        if item.depth <= 0:
            errors.append("Depth must be a positive number")
        if item.height <= 0:
            errors.append("Height must be a positive number")
            
        if item.clearance < 0:
            errors.append("Clearance must be non-negative")
        if item.assembly_clearance < 0:
            errors.append("Assembly clearance must be non-negative")
            
        if errors:
            status = "invalid"
            invalid_count += 1
        else:
            # Check duplicate
            dup = check_duplicate_asset(
                db,
                name=item.name,
                category=item.category,
                style=item.style,
                width=item.width,
                depth=item.depth,
                height=item.height
            )
            if dup:
                status = "duplicate"
                duplicate_asset_id = dup.id
                duplicate_count += 1
            else:
                valid_count += 1
                
        # Import if valid, not duplicate, and not dry run
        if status == "valid" and not req.dry_run:
            cat_key = item.category.strip().lower()
            cat = categories_map.get(cat_key)
            if not cat:
                cat = FurnitureCategory(name=item.category.strip())
                db.add(cat)
                db.commit()
                db.refresh(cat)
                categories_map[cat_key] = cat
                
            new_id = f"IMP{str(uuid.uuid4())[:8].upper()}"
            db_asset = FurnitureAsset(
                id=new_id,
                name=item.name.strip(),
                category=item.category.strip(),
                category_id=cat.id,
                style=item.style.strip(),
                width=item.width,
                depth=item.depth,
                height=item.height,
                clearance=item.clearance,
                assembly_clearance=item.assembly_clearance,
                tags=item.tags,
                glb_url=item.glb_url or "",
                thumbnail_url=item.thumbnail_url or ""
            )
            db.add(db_asset)
            imported_count += 1
            
        report.append(BulkImportReportItem(
            item_index=idx,
            name=item.name,
            status=status,
            errors=errors,
            duplicate_asset_id=duplicate_asset_id
        ))
        
    if not req.dry_run and imported_count > 0:
        db.commit()
        
    return FurnitureBulkImportResponse(
        success=True,
        total_processed=len(req.assets),
        valid_count=valid_count,
        invalid_count=invalid_count,
        duplicate_count=duplicate_count,
        imported_count=imported_count,
        report=report
    )

