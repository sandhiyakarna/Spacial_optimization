import os
import sys
import json
import shutil
import sqlite3
import uuid
import hashlib
from datetime import datetime, timezone

FINAL_DIR = r"C:\Users\Admin\Documents\FlowSpace_Final_Assets"
BACKEND_DIR = r"c:\Users\Admin\Documents\mad2\backend"
DB_PATH = os.path.join(BACKEND_DIR, "flowspace.db")
UPLOADS_MODELS_DIR = os.path.join(BACKEND_DIR, "uploads", "furniture", "models")
UPLOADS_THUMBS_DIR = os.path.join(BACKEND_DIR, "uploads", "furniture", "thumbnails")

# Category Mappings
CAT_MAPPINGS = {
    "living_room": ("Living Room", "Furniture"),
    "bedroom": ("Bedroom", "Furniture"),
    "dining": ("Dining", "Furniture"),
    "kitchen": ("Kitchen", "Furniture"),
    "office": ("Office", "Furniture"),
    "bathroom": ("Bathroom", "Furniture"),
    "lighting": ("Lighting", None),
    "decor": ("Decor", None),
    "plants": ("Plants", None),
    "outdoor": ("Outdoor", "Furniture")
}

# Setup import path for organizer module
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

from organizer import parse_glb_gltf, get_geometric_sig, MeshData

def get_file_hash(filepath):
    if not os.path.exists(filepath):
        return None
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            sha256.update(chunk)
    return sha256.hexdigest()

def load_db_assets(cursor):
    """
    Loads all existing assets in the DB and returns:
    - db_id_map: { id: { 'name': name, 'category': category, 'model_path': model_path } }
    - db_hash_map: { hash: id }
    - db_geom_map: { geom_sig: id }
    """
    db_id_map = {}
    db_hash_map = {}
    db_geom_map = {}

    cursor.execute("SELECT id, name, category, model_path FROM furniture_assets")
    rows = cursor.fetchall()
    
    for row in rows:
        fid, name, category, model_path = row
        db_id_map[fid] = {
            "name": name,
            "category": category,
            "model_path": model_path
        }
        
        if not model_path:
            continue
            
        # Resolve path
        abs_model_path = os.path.join(BACKEND_DIR, model_path.replace("/", os.sep))
        if os.path.exists(abs_model_path):
            h = get_file_hash(abs_model_path)
            if h:
                db_hash_map[h] = fid
                
            try:
                mesh = parse_glb_gltf(abs_model_path)
                if mesh.success:
                    sig = get_geometric_sig(mesh)
                    if sig:
                        db_geom_map[sig] = fid
            except Exception as e:
                print(f"[WARNING] Failed to parse existing GLB {abs_model_path}: {e}")
                
    return db_id_map, db_hash_map, db_geom_map

def get_unique_filepath(dest_dir, filename, src_hash, asset_id):
    """
    Ensures that we do not overwrite an existing file unless the content hash matches.
    """
    dest_path = os.path.join(dest_dir, filename)
    if not os.path.exists(dest_path):
        return dest_path, filename
        
    existing_hash = get_file_hash(dest_path)
    if existing_hash == src_hash:
        return dest_path, filename
        
    base, ext = os.path.splitext(filename)
    if not base.startswith(asset_id):
        new_filename = f"{asset_id}_{filename}"
    else:
        new_filename = f"{base}_{src_hash[:8]}{ext}"
        
    new_dest_path = os.path.join(dest_dir, new_filename)
    print(f"[INFO] Filename collision resolved: '{filename}' -> '{new_filename}'")
    return new_dest_path, new_filename

def get_unique_thumb_filepath(dest_dir, filename, src_hash, asset_id):
    dest_path = os.path.join(dest_dir, filename)
    if not os.path.exists(dest_path):
        return dest_path, filename
        
    existing_hash = get_file_hash(dest_path)
    if existing_hash == src_hash:
        return dest_path, filename
        
    base, ext = os.path.splitext(filename)
    if not base.startswith(asset_id):
        new_filename = f"{asset_id}_{filename}"
    else:
        new_filename = f"{base}_{src_hash[:8]}{ext}"
        
    new_dest_path = os.path.join(dest_dir, new_filename)
    print(f"[INFO] Thumbnail filename collision resolved: '{filename}' -> '{new_filename}'")
    return new_dest_path, new_filename

def main():
    import hashlib # Make sure hashlib is imported locally if needed
    print("==================================================")
    print("STARTING DATABASE INTEGRATION PIPELINE (SQLITE)")
    print("==================================================")

    # 1. Ensure uploads directories exist
    os.makedirs(UPLOADS_MODELS_DIR, exist_ok=True)
    os.makedirs(UPLOADS_THUMBS_DIR, exist_ok=True)

    # 2. Load manifest
    manifest_path = os.path.join(FINAL_DIR, "metadata", "final_asset_manifest.json")
    if not os.path.exists(manifest_path):
        print(f"[ERROR] Final manifest not found: {manifest_path}")
        sys.exit(1)
        
    with open(manifest_path, 'r', encoding='utf-8') as f:
        final_assets = json.load(f)
    print(f"Loaded {len(final_assets)} curated assets from manifest.")

    # 3. Connect to database
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        # Create parent "Furniture" category if it does not exist
        cursor.execute("SELECT id FROM furniture_categories WHERE name = 'Furniture'")
        parent_furniture_row = cursor.fetchone()
        
        if not parent_furniture_row:
            parent_id = str(uuid.uuid4())
            now_str = datetime.now(timezone.utc).isoformat()
            cursor.execute(
                "INSERT INTO furniture_categories (id, name, description, parent_id, created_at) VALUES (?, ?, ?, ?, ?)",
                (parent_id, "Furniture", "General furniture items", None, now_str)
            )
            print("[OK] Created parent category 'Furniture'")
        else:
            parent_id = parent_furniture_row[0]

        # Setup all categories
        categories_map = {}
        for cat_key, (db_name, parent_name) in CAT_MAPPINGS.items():
            cursor.execute("SELECT id, parent_id FROM furniture_categories WHERE name = ?", (db_name,))
            cat_row = cursor.fetchone()
            
            p_id = parent_id if parent_name == "Furniture" else None
            now_str = datetime.now(timezone.utc).isoformat()
            
            if not cat_row:
                cat_uuid = str(uuid.uuid4())
                cursor.execute(
                    "INSERT INTO furniture_categories (id, name, description, parent_id, created_at) VALUES (?, ?, ?, ?, ?)",
                    (cat_uuid, db_name, f"Seeded {db_name} category", p_id, now_str)
                )
                print(f"[OK] Created category '{db_name}' with parent '{parent_name}'")
            else:
                cat_uuid = cat_row[0]
                if cat_row[1] != p_id:
                    cursor.execute("UPDATE furniture_categories SET parent_id = ? WHERE id = ?", (p_id, cat_uuid))
                    print(f"[OK] Updated category '{db_name}' parent to '{parent_name}'")
            categories_map[cat_key] = (cat_uuid, db_name)

        # Pre-populate DB registries
        print("Loading database asset registries for duplicate checks...")
        db_id_map, db_hash_map, db_geom_map = load_db_assets(cursor)
        print(f"Loaded {len(db_id_map)} assets, {len(db_hash_map)} hashes, and {len(db_geom_map)} geom signatures from DB.")

        # 4. Integrate Assets
        records_created = 0
        records_updated = 0
        duplicates_prevented = 0

        for item in final_assets:
            asset_id = item["asset_id"]
            cat_key = item["category"]
            db_cat_info = categories_map.get(cat_key)
            category_id = db_cat_info[0] if db_cat_info else None
            category_name = db_cat_info[1] if db_cat_info else item["category"].capitalize()

            # Get filenames from paths in manifest
            model_filename = os.path.basename(item["model_path"])
            thumb_filename = os.path.basename(item["thumbnail_path"])

            # Source paths
            src_glb = os.path.join(FINAL_DIR, "models", cat_key, model_filename)
            src_thumb = os.path.join(FINAL_DIR, "thumbnails", thumb_filename)

            if not os.path.exists(src_glb):
                print(f"[ERROR] Source model not found: {src_glb}")
                sys.exit(1)

            # Compute source hashes and signatures
            src_hash = get_file_hash(src_glb)
            
            src_geom_sig = None
            try:
                mesh = parse_glb_gltf(src_glb)
                if mesh.success:
                    src_geom_sig = get_geometric_sig(mesh)
            except Exception as e:
                print(f"[WARNING] Failed to parse source GLB {src_glb}: {e}")

            src_thumb_hash = get_file_hash(src_thumb) if os.path.exists(src_thumb) else None

            # Duplicate priority checks
            # 1. Exact ID match
            is_exact_id = asset_id in db_id_map

            # 2. Exact model hash match
            is_exact_hash = src_hash in db_hash_map
            matching_hash_id = db_hash_map.get(src_hash)

            # 3. Exact normalized content (geometric signature) match
            is_exact_geom = src_geom_sig is not None and src_geom_sig in db_geom_map
            matching_geom_id = db_geom_map.get(src_geom_sig)

            # Skip duplicate if not exact ID match but matches hash or geometry
            if not is_exact_id:
                if is_exact_hash:
                    print(f"[INFO] Skipping duplicate asset by hash: '{item['name']}' (Matches existing ID: {matching_hash_id})")
                    duplicates_prevented += 1
                    continue
                if is_exact_geom:
                    print(f"[INFO] Skipping duplicate asset by geometry: '{item['name']}' (Matches existing ID: {matching_geom_id})")
                    duplicates_prevented += 1
                    continue

            # Safe copy with file conflict resolver
            dest_glb, final_model_filename = get_unique_filepath(UPLOADS_MODELS_DIR, model_filename, src_hash, asset_id)
            if src_thumb_hash:
                dest_thumb, final_thumb_filename = get_unique_thumb_filepath(UPLOADS_THUMBS_DIR, thumb_filename, src_thumb_hash, asset_id)
            else:
                dest_thumb, final_thumb_filename = os.path.join(UPLOADS_THUMBS_DIR, thumb_filename), thumb_filename

            # Copy files if they exist
            if os.path.exists(src_glb):
                shutil.copy2(src_glb, dest_glb)
            if os.path.exists(src_thumb):
                shutil.copy2(src_thumb, dest_thumb)

            # Local relative paths and URLs
            rel_glb_path = f"uploads/furniture/models/{final_model_filename}"
            rel_thumb_path = f"uploads/furniture/thumbnails/{final_thumb_filename}"
            glb_url = f"/uploads/furniture/models/{final_model_filename}"
            thumb_url = f"/uploads/furniture/thumbnails/{final_thumb_filename}"

            # Convert dimensions to cm
            width_cm = float(item["width"]) * 100.0
            depth_cm = float(item["depth"]) * 100.0
            height_cm = float(item["height"]) * 100.0

            # Create or update Asset records
            model_asset_id = f"model_{asset_id}"
            cursor.execute("SELECT id FROM assets WHERE id = ?", (model_asset_id,))
            if not cursor.fetchone():
                now_str = datetime.now(timezone.utc).isoformat()
                cursor.execute(
                    "INSERT INTO assets (id, name, type, file_type, model_path, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                    (model_asset_id, f"{item['name']} GLB Model", "model", "glb", rel_glb_path, now_str)
                )
            else:
                cursor.execute("UPDATE assets SET model_path = ? WHERE id = ?", (rel_glb_path, model_asset_id))

            thumb_asset_id = f"thumb_{asset_id}"
            cursor.execute("SELECT id FROM assets WHERE id = ?", (thumb_asset_id,))
            ext = os.path.splitext(final_thumb_filename)[1][1:] # e.g. "png"
            if not cursor.fetchone():
                now_str = datetime.now(timezone.utc).isoformat()
                cursor.execute(
                    "INSERT INTO assets (id, name, type, file_type, thumbnail_path, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                    (thumb_asset_id, f"{item['name']} Thumbnail", "thumbnail", ext, rel_thumb_path, now_str)
                )
            else:
                cursor.execute("UPDATE assets SET thumbnail_path = ? WHERE id = ?", (rel_thumb_path, thumb_asset_id))

            # Create or update FurnitureAsset record
            cursor.execute("SELECT id FROM furniture_assets WHERE id = ?", (asset_id,))
            now_str = datetime.now(timezone.utc).isoformat()
            if not cursor.fetchone():
                cursor.execute(
                    """INSERT INTO furniture_assets 
                    (id, name, category, category_id, subcategory, style, width, depth, height, clearance, assembly_clearance, tags, glb_url, thumbnail_url, model_path, thumbnail_path, model_asset_id, thumbnail_asset_id, created_at) 
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        asset_id, item["name"], category_name, category_id, item.get("subcategory"),
                        item.get("style", "Modern"), width_cm, depth_cm, height_cm, 10.0, 10.0,
                        item.get("tags", ""), glb_url, thumb_url, rel_glb_path, rel_thumb_path,
                        model_asset_id, thumb_asset_id, now_str
                    )
                )
                records_created += 1
            else:
                cursor.execute(
                    """UPDATE furniture_assets SET 
                    name = ?, category = ?, category_id = ?, subcategory = ?, style = ?, width = ?, depth = ?, height = ?, tags = ?, glb_url = ?, thumbnail_url = ?, model_path = ?, thumbnail_path = ?, model_asset_id = ?, thumbnail_asset_id = ?
                    WHERE id = ?""",
                    (
                        item["name"], category_name, category_id, item.get("subcategory"),
                        item.get("style", "Modern"), width_cm, depth_cm, height_cm,
                        item.get("tags", ""), glb_url, thumb_url, rel_glb_path, rel_thumb_path,
                        model_asset_id, thumb_asset_id, asset_id
                    )
                )
                records_updated += 1

        conn.commit()
        print(f"[OK] Database integration finished. Created: {records_created}, Updated: {records_updated}, Duplicates Prevented: {duplicates_prevented}")

        # Save summary report details
        report_meta = {
            "records_created": records_created,
            "records_updated": records_updated,
            "duplicates_prevented": duplicates_prevented
        }
        os.makedirs(os.path.join(FINAL_DIR, "reports"), exist_ok=True)
        with open(os.path.join(FINAL_DIR, "reports", "database_integration_report.json"), 'w') as f:
            json.dump(report_meta, f, indent=2)

    except Exception as e:
        print(f"[ERROR] Database integration failed: {e}")
        conn.rollback()
        sys.exit(1)
    finally:
        conn.close()

if __name__ == "__main__":
    main()

