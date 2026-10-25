import os
import sys
import json
import csv
import shutil
import tempfile
import hashlib
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

# Add current folder to sys.path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from organizer import (
    parse_obj, parse_glb_gltf, get_file_hash, get_geometric_sig,
    detect_blender, run_blender_helper, SUPPORTED_EXTENSIONS, ARCHIVE_EXTENSIONS, MeshData
)

# Constants
PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
NEW_ASSET_SOURCE = r"C:\Users\Admin\Documents\flowspace_new_assets"
OUTPUT_DIR = r"C:\Users\Admin\Documents\FlowSpace_New_Processed_Assets"

CAT_MAP = {
    "Living Room": "living_room",
    "Bedroom": "bedroom",
    "Dining": "dining",
    "Kitchen": "kitchen",
    "Office": "office",
    "Bathroom": "bathroom",
    "Lighting": "lighting",
    "Decor": "decor",
    "Plants": "plants",
    "Outdoor": "outdoor",
    "Architectural": "architectural",
    "Other": "other",
    "Needs Review": "needs_review"
}

EXISTING_COUNTS = {
    "Living Room": 68,
    "Bedroom": 34,
    "Dining": 14,
    "Kitchen": 77,
    "Office": 24,
    "Bathroom": 22,
    "Lighting": 175,
    "Decor": 14,
    "Plants": 4,
    "Outdoor": 0,
    "Architectural": 27,
    "Other": 60,
    "Needs Review": 0
}

CATEGORY_TARGETS = {
    "Living Room": 25,
    "Bedroom": 20,
    "Dining": 15,
    "Kitchen": 15,
    "Office": 15,
    "Bathroom": 10,
    "Lighting": 15,
    "Decor": 20,
    "Plants": 10,
    "Outdoor": 10,
    "Architectural": 0,
    "Other": 0,
    "Needs Review": 0
}

def pre_populate_registries():
    """Builds seen_hashes and seen_geometries databases from existing folders and libraries."""
    seen_hashes = {}      # hash -> path
    seen_geometries = {}  # geom_sig -> path
    
    # 1. Scan original folders
    existing_dirs = [
        r"C:\Users\Admin\Documents\furniture2",
        r"C:\Users\Admin\Documents\furnituresforprojects"
    ]
    
    print("==================================================")
    print("PHASE 1: PRE-POPULATING DUPLICATE DATABASE")
    print("==================================================")
    
    for directory in existing_dirs:
        # check spelling
        if "furnituresforprojects" in directory:
            alt = directory.replace("furnituresforprojects", "furnitureforprojects")
            if os.path.exists(alt):
                directory = alt
        elif "furnitureforprojects" in directory:
            alt = directory.replace("furnitureforprojects", "furnituresforprojects")
            if os.path.exists(alt):
                directory = alt
                
        if not os.path.exists(directory):
            print(f"[WARN] Existing directory not found: {directory}")
            continue
            
        print(f"Scanning original directory: {directory}")
        for root, _, filenames in os.walk(directory):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                ext = os.path.splitext(filename)[1].lower()
                if ext in SUPPORTED_EXTENSIONS or ext in ARCHIVE_EXTENSIONS:
                    try:
                        f_hash = get_file_hash(filepath)
                        seen_hashes[f_hash] = filepath
                    except Exception as e:
                        print(f"  Failed to hash {filename}: {e}")
                        
                    # Geometry signature (if natively parsable)
                    if ext in ['.glb', '.gltf', '.obj']:
                        try:
                            if ext in ['.glb', '.gltf']:
                                mesh = parse_glb_gltf(filepath)
                            else:
                                mesh = parse_obj(filepath)
                            if mesh.success:
                                sig = get_geometric_sig(mesh)
                                if sig:
                                    seen_geometries[sig] = filepath
                        except Exception:
                            pass

    # 2. Scan previously processed FlowSpace libraries
    processed_library_dirs = [
        r"c:\Users\Admin\Documents\mad2\FlowSpace_Asset_Review\FlowSpace_Library",
        r"c:\Users\Admin\Documents\mad2\FlowSpace_Library_Output\FlowSpace_Library"
    ]
    
    for lib_dir in processed_library_dirs:
        if not os.path.exists(lib_dir):
            continue
        print(f"Scanning library: {lib_dir}")
        for root, _, filenames in os.walk(lib_dir):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                ext = os.path.splitext(filename)[1].lower()
                if ext in SUPPORTED_EXTENSIONS:
                    try:
                        f_hash = get_file_hash(filepath)
                        seen_hashes[f_hash] = filepath
                    except Exception:
                        continue
                        
                    if ext in ['.glb', '.gltf', '.obj']:
                        try:
                            if ext in ['.glb', '.gltf']:
                                mesh = parse_glb_gltf(filepath)
                            else:
                                mesh = parse_obj(filepath)
                            if mesh.success:
                                sig = get_geometric_sig(mesh)
                                if sig:
                                    seen_geometries[sig] = filepath
                        except Exception:
                            pass
                            
    print(f"[OK] Pre-population complete. Loaded {len(seen_hashes)} file hashes and {len(seen_geometries)} geometric signatures.")
    return seen_hashes, seen_geometries

def extract_archive_local(archive_path, extract_to):
    """Extracts zip or rar archives using Python or Windows tar."""
    ext = os.path.splitext(archive_path)[1].lower()
    os.makedirs(extract_to, exist_ok=True)
    if ext == '.zip':
        import zipfile
        try:
            with zipfile.ZipFile(archive_path, 'r') as zip_ref:
                zip_ref.extractall(extract_to)
            return True
        except Exception as e:
            print(f"Zip extraction failed: {str(e)}")
            return False
    elif ext == '.rar':
        try:
            cmd = f'tar -xf "{archive_path}" -C "{extract_to}"'
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return res.returncode == 0
        except Exception as e:
            print(f"RAR extraction failed: {str(e)}")
            return False
    return False

def extract_all_archives_recursive(src_dir, target_dir):
    """Recursively extracts all archives found in src_dir (and inside nested directories) into target_dir."""
    to_check = []
    for root, _, filenames in os.walk(src_dir):
        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in ARCHIVE_EXTENSIONS:
                to_check.append(os.path.join(root, filename))
                
    extracted_paths = []
    while to_check:
        archive_path = to_check.pop(0)
        archive_name = os.path.basename(archive_path)
        # Create unique extract path
        rel_to_src = os.path.relpath(archive_path, src_dir)
        rel_dir = os.path.splitext(rel_to_src)[0]
        rel_dir = rel_dir.replace("..", "").replace(":", "").replace("\\", "_").replace("/", "_")
        extract_target = os.path.join(target_dir, rel_dir)
        
        print(f"  Extracting archive: {archive_name} -> {extract_target}")
        if extract_archive_local(archive_path, extract_target):
            extracted_paths.append((archive_path, extract_target))
            # Scan the newly extracted directory for nested archives
            for e_root, _, e_filenames in os.walk(extract_target):
                for e_filename in e_filenames:
                    e_ext = os.path.splitext(e_filename)[1].lower()
                    if e_ext in ARCHIVE_EXTENSIONS:
                        to_check.append(os.path.join(e_root, e_filename))
                        
    return extracted_paths

def gather_all_models(src_dir, temp_extract_dir, extracted_paths):
    models = []
    
    # 1. Walk original source dir, collect non-archive models
    for root, _, filenames in os.walk(src_dir):
        for filename in filenames:
            filepath = os.path.join(root, filename)
            ext = os.path.splitext(filename)[1].lower()
            if ext in SUPPORTED_EXTENSIONS:
                models.append({
                    "path": filepath,
                    "is_extracted": False,
                    "display_name": os.path.basename(filepath),
                    "source_archive": ""
                })
                
    # 2. Walk temp_extract_dir, collect all models
    if os.path.exists(temp_extract_dir):
        for root, _, filenames in os.walk(temp_extract_dir):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                ext = os.path.splitext(filename)[1].lower()
                if ext in SUPPORTED_EXTENSIONS:
                    # Find which archive this came from
                    source_archive = ""
                    for archive_path, extract_target in extracted_paths:
                        if filepath.startswith(extract_target):
                            source_archive = archive_path
                            break
                    
                    rel_path = os.path.relpath(filepath, temp_extract_dir)
                    models.append({
                        "path": filepath,
                        "is_extracted": True,
                        "display_name": rel_path.replace("\\", "/"),
                        "source_archive": source_archive
                    })
                    
    return models

def get_source_and_license(original_path, source_archive):
    path_to_check = source_archive if source_archive else original_path
    fn = os.path.basename(path_to_check).lower()
    
    if "kenney" in fn:
        return "Kenney Nature Kit", "CC0"
    elif "blends" in fn:
        return "Blends Pack", "Unknown"
    else:
        return "New Download Pack", "Unknown"

def classify_model_improved(mesh, filename, path):
    fn = filename.lower()
    path_lower = path.lower()
    
    obj_names = [n.lower() for n in getattr(mesh, "obj_names", [])]
    mesh_names = [n.lower() for n in getattr(mesh, "mesh_names", [])]
    mat_names = [n.lower() for n in getattr(mesh, "mat_names", [])]
    
    def matches_keyword(kw_list):
        for kw in kw_list:
            if kw in fn:
                return True
            for name in obj_names:
                if kw in name:
                    return True
            for name in mesh_names:
                if kw in name:
                    return True
            for name in mat_names:
                if kw in name:
                    return True
        return False

    # Plants keywords (high priority)
    plants_keywords = ["plant", "flower", "tree", "grass", "shrub", "bush", "vegetation", "pot_plant", "cactus", "fern", "foliage", "leaf", "palm"]
    if matches_keyword(plants_keywords):
        return "Plants", "Indoor Plant"

    # Outdoor keywords (high priority)
    outdoor_keywords = ["outdoor", "garden", "patio", "bench", "lounge_chair_garden", "deck", "umbrella", "firepit", "gazebo", "fountain"]
    if matches_keyword(outdoor_keywords):
        return "Outdoor", "Outdoor Furniture"

    # Dining keywords (high priority)
    dining_keywords = ["dining", "buffet", "dining_table", "dining_chair", "dinning"]
    if matches_keyword(dining_keywords) or (matches_keyword(["table"]) and matches_keyword(["chair"]) and "dining" in path_lower):
        return "Dining", "Dining Furniture"

    # Decor keywords (high priority)
    decor_keywords = ["mirror", "rug", "pillow", "cushion", "vase", "clock", "picture", "frame", "sculpture", "art", "decor", "book", "books", "candle", "tray", "bowl", "ornament"]
    if matches_keyword(decor_keywords):
        return "Decor", "Accessory"

    # Living Room keywords
    living_room_keywords = ["sofa", "couch", "sectional", "armchair", "lounge", "tv_stand", "coffee_table", "credenza", "sideboard", "chest", "sessel"]
    if matches_keyword(living_room_keywords):
        return "Living Room", "Armchair" if ("armchair" in fn or "sessel" in fn) else "Sofa" if ("sofa" in fn or "couch" in fn) else "Table" if "table" in fn else "Armchair"

    # Bedroom keywords
    bedroom_keywords = ["bed", "nightstand", "dresser", "wardrobe", "closet"]
    if matches_keyword(bedroom_keywords):
        return "Bedroom", "Bed" if "bed" in fn else "Storage"

    # Kitchen keywords
    kitchen_keywords = ["kitchen", "cabinet", "counter", "sink", "fridge", "refrigerator", "stove", "oven", "pantry", "faucet", "microwave", "toaster", "blender", "coffee"]
    if matches_keyword(kitchen_keywords):
        return "Kitchen", "Cabinet" if "cabinet" in fn else "Appliance"

    # Office keywords
    office_keywords = ["desk", "office_chair", "office", "bookshelf", "bookshelves", "bookself", "conference_table", "filing_cabinet", "computer", "laptop"]
    if matches_keyword(office_keywords):
        return "Office", "Desk" if "desk" in fn else "Office Chair"

    # Bathroom keywords
    bathroom_keywords = ["bathroom", "tub", "bathtub", "shower", "toilet", "vanity", "bathroom_mirror"]
    if matches_keyword(bathroom_keywords):
        return "Bathroom", "Bathroom Furniture"

    # Lighting keywords
    lighting_keywords = ["lamp", "light", "chandelier", "sconce", "lantern", "lighting", "illumination"]
    if matches_keyword(lighting_keywords):
        return "Lighting", "Light Source"

    # Architectural keywords
    architectural_keywords = ["wall", "door", "window", "stair", "column", "pillar", "ceiling", "floor", "beam", "roof", "fence", "gate"]
    if matches_keyword(architectural_keywords):
        return "Architectural", "Structure"

    # Heuristics based on dimensions if name is ambiguous
    width = getattr(mesh, "width", 0.0)
    depth = getattr(mesh, "depth", 0.0)
    height = getattr(mesh, "height", 0.0)
    poly_count = getattr(mesh, "polygon_count", 0)

    if width > 0 and depth > 0 and height > 0:
        if width > 1.2 and depth > 1.2 and height < 1.1:
            if depth > width * 1.1:
                return "Bedroom", "Bed"
            else:
                return "Living Room", "Sofa"
        if width > 1.4 and depth < 1.1 and height < 1.1:
            return "Living Room", "Sofa"
        if 0.7 <= height <= 0.85 and 0.6 <= width <= 2.2 and 0.6 <= depth <= 2.2:
            return "Dining", "Table"
        if width < 0.8 and depth < 0.8 and 0.7 < height < 1.2:
            return "Living Room", "Chair"

    if poly_count < 10 or width == 0:
        return "Needs Review", "Unknown"

    return "Other", "Other Furniture"

def create_failed_thumbnail(dest_thumb_path, label):
    img_size = 512
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (img_size, img_size), (22, 22, 28))
    draw = ImageDraw.Draw(img)
    draw.rectangle([100, 100, 412, 412], fill=(40, 40, 50), outline=(80, 80, 100), width=3)
    draw.text((180, 250), label, fill=(200, 200, 220))
    img.save(dest_thumb_path)

def process_single_asset_blender(blender_exe, model_path, asset_id, temp_working_dir):
    """Worker function to run Blender helper on a single asset."""
    temp_glb_path = os.path.join(temp_working_dir, f"{asset_id}_temp.glb")
    temp_thumb_path = os.path.join(temp_working_dir, f"{asset_id}_temp_thumb.png")
    
    blender_mesh = run_blender_helper(blender_exe, model_path, temp_glb_path, temp_thumb_path)
    return asset_id, blender_mesh, temp_glb_path, temp_thumb_path

def main():
    # Detect Blender
    blender_exe = detect_blender()
    blender_detected = blender_exe is not None
    blender_version = "N/A"
    if blender_detected:
        try:
            res = subprocess.run([blender_exe, "--version"], capture_output=True, text=True, check=True)
            for line in res.stdout.splitlines():
                if "blender" in line.lower():
                    blender_version = line.replace("Blender", "").strip()
                    break
        except Exception:
            pass
        print(f"[OK] Blender detected: {blender_exe} (Version: {blender_version})")
    else:
        print("[ERROR] Blender must be installed and verified. Exiting.")
        sys.exit(1)
        
    # Pre-populate seen databases
    seen_hashes, seen_geometries = pre_populate_registries()
    
    # Setup working temp directory
    temp_working_dir = tempfile.mkdtemp(prefix="fs_new_organizer_")
    temp_extract_dir = os.path.join(temp_working_dir, "extracted")
    os.makedirs(temp_extract_dir, exist_ok=True)
    
    # Setup output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for cat_folder in CAT_MAP.values():
        os.makedirs(os.path.join(OUTPUT_DIR, cat_folder), exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_DIR, "duplicates"), exist_ok=True)
    
    print("\n==================================================")
    print("PHASE 2: EXTRACTING NEW ASSET ARCHIVES")
    print("==================================================")
    extracted_paths = extract_all_archives_recursive(NEW_ASSET_SOURCE, temp_extract_dir)
    
    print("\n==================================================")
    print("PHASE 3: GATHERING CANDIDATE MODELS")
    print("==================================================")
    models_to_process = gather_all_models(NEW_ASSET_SOURCE, temp_extract_dir, extracted_paths)
    print(f"[OK] Gathered {len(models_to_process)} candidate model files to inspect.")
    
    # Process
    total_files = len(models_to_process)
    total_models = 0
    formats = set()
    valid_models = 0
    invalid_models = 0
    existing_glbs = 0
    convertible_models = 0
    duplicates_count = 0
    variants_count = 0
    
    asset_id_counter = 604
    
    # Step 1: Sequential duplicate checking (extremely fast, populates duplicate statuses)
    print("\n==================================================")
    print("PHASE 4.1: SEQUENTIAL DUPLICATE ANALYSIS")
    print("==================================================")
    
    models_metadata = []
    
    for idx, model_data in enumerate(models_to_process):
        model_path = model_data["path"]
        filename = os.path.basename(model_path)
        ext = os.path.splitext(filename)[1].lower()
        formats.add(ext.upper())
        total_models += 1
        
        # File hash and size
        f_hash = get_file_hash(model_path)
        
        # Check duplicate status
        dup_status = "unique"
        primary_match = None
        
        # Exact/binary duplicate check
        if f_hash in seen_hashes:
            dup_status = "duplicate"
            primary_match = seen_hashes[f_hash]
            duplicates_count += 1
        else:
            # Native parse to check geometric duplicate
            mesh = None
            if ext in ['.glb', '.gltf']:
                mesh = parse_glb_gltf(model_path)
            elif ext == '.obj':
                mesh = parse_obj(model_path)
            else:
                mesh = MeshData() # fallback
                
            geom_sig = get_geometric_sig(mesh) if mesh.success else None
            if geom_sig and geom_sig in seen_geometries:
                dup_status = "duplicate"
                primary_match = seen_geometries[geom_sig]
                duplicates_count += 1
            else:
                # Obvious variant check
                is_variant = False
                if mesh.success:
                    for sig, path in seen_geometries.items():
                        if sig.startswith(f"V{len(mesh.vertices)}_F{len(mesh.faces)}_"):
                            dup_status = "variant"
                            primary_match = path
                            is_variant = True
                            variants_count += 1
                            break
                if not is_variant:
                    # Update databases so subsequent new assets can detect this as duplicate
                    seen_hashes[f_hash] = model_path
                    if geom_sig:
                        seen_geometries[geom_sig] = model_path
                        
        models_metadata.append({
            "model_data": model_data,
            "filename": filename,
            "ext": ext,
            "f_hash": f_hash,
            "dup_status": dup_status,
            "primary_match": primary_match
        })
        
    print(f"[OK] Duplicate checks complete. Found {duplicates_count} duplicates/variants.")
    
    # Step 2: Parallel Blender running for unique/variant models
    print("\n==================================================")
    print("PHASE 4.2: PARALLEL BLENDER INSPECTION & RENDERING")
    print("==================================================")
    
    # Filter only assets that require Blender (unique/variant)
    unique_candidates = []
    for item in models_metadata:
        if item["dup_status"] in ["unique", "variant"]:
            asset_id = f"FS_ASSET_{asset_id_counter:03d}"
            asset_id_counter += 1
            item["asset_id"] = asset_id
            unique_candidates.append(item)
        else:
            asset_id = f"FS_ASSET_{asset_id_counter:03d}"
            asset_id_counter += 1
            item["asset_id"] = asset_id
            
    print(f"Running Blender processing on {len(unique_candidates)} unique/variant models in parallel...")
    
    blender_results = {}
    # Use ThreadPoolExecutor for concurrent Blender executions
    # Standard modern systems can handle 6 concurrent background Blender tasks comfortably
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = {
            executor.submit(
                process_single_asset_blender, 
                blender_exe, 
                item["model_data"]["path"], 
                item["asset_id"], 
                temp_working_dir
            ): item for item in unique_candidates
        }
        
        completed_count = 0
        for future in as_completed(futures):
            item = futures[future]
            completed_count += 1
            try:
                asset_id, blender_mesh, temp_glb, temp_thumb = future.result()
                blender_results[asset_id] = {
                    "mesh": blender_mesh,
                    "temp_glb": temp_glb,
                    "temp_thumb": temp_thumb
                }
                print(f"  [{completed_count}/{len(unique_candidates)}] Finished Blender processing for {item['filename']}")
            except Exception as e:
                print(f"  [ERROR] Blender worker thread failed for {item['filename']}: {e}")
                
    # Step 3: Sequential copy, finalize folders and record manifest
    print("\n==================================================")
    print("PHASE 4.3: COPYING & RECONCILING OUTPUTS")
    print("==================================================")
    
    manifest_records = []
    
    for item in models_metadata:
        model_data = item["model_data"]
        model_path = model_data["path"]
        filename = item["filename"]
        ext = item["ext"]
        dup_status = item["dup_status"]
        asset_id = item["asset_id"]
        
        inspect_status = "Success"
        mesh = MeshData()
        
        # Reconcile Blender results
        if dup_status in ["unique", "variant"]:
            res = blender_results.get(asset_id)
            if res:
                blender_mesh = res["mesh"]
                temp_glb_path = res["temp_glb"]
                temp_thumb_path = res["temp_thumb"]
                
                if blender_mesh.success:
                    if blender_mesh.width <= 0 or blender_mesh.height <= 0 or blender_mesh.depth <= 0:
                        inspect_status = "Failed: zero volume dimensions"
                        invalid_models += 1
                    elif blender_mesh.polygon_count <= 2:
                        inspect_status = "Failed: insufficient geometry polygons"
                        invalid_models += 1
                    else:
                        mesh = blender_mesh
                        valid_models += 1
                        if ext == '.glb':
                            existing_glbs += 1
                        else:
                            convertible_models += 1
                else:
                    inspect_status = f"Failed: {blender_mesh.error_message}"
                    invalid_models += 1
            else:
                inspect_status = "Failed: Blender task failed unexpectedly"
                invalid_models += 1
        else:
            # Duplicate - skip Blender run
            inspect_status = "Success"
            valid_models += 1
            if ext == '.glb':
                existing_glbs += 1
            else:
                convertible_models += 1
                
        # Categorize
        if inspect_status == "Success":
            category, subcategory = classify_model_improved(mesh, filename, model_path)
        else:
            category, subcategory = "Needs Review", "Unknown"
            
        target_folder = CAT_MAP.get(category, "needs_review")
        
        # Copy/move outputs
        final_glb_filename = f"{asset_id}_{os.path.splitext(filename)[0]}.glb"
        final_thumb_filename = f"{asset_id}_{os.path.splitext(filename)[0]}_thumb.png"
        
        if dup_status in ["duplicate", "variant"]:
            # Copy original to duplicates folder
            dest_path = os.path.join(OUTPUT_DIR, "duplicates", f"{asset_id}_{filename}")
            shutil.copy2(model_path, dest_path)
            final_glb_path = dest_path
            thumbnail_path = "None"
        elif inspect_status == "Success":
            # Valid unique model
            dest_glb_path = os.path.join(OUTPUT_DIR, target_folder, final_glb_filename)
            dest_thumb_path = os.path.join(OUTPUT_DIR, target_folder, final_thumb_filename)
            
            if os.path.exists(temp_glb_path):
                shutil.move(temp_glb_path, dest_glb_path)
            else:
                shutil.copy2(model_path, dest_glb_path)
                
            if os.path.exists(temp_thumb_path):
                shutil.move(temp_thumb_path, dest_thumb_path)
            else:
                create_failed_thumbnail(dest_thumb_path, "Preview Unavailable")
                
            final_glb_path = dest_glb_path
            thumbnail_path = dest_thumb_path
        else:
            # Invalid/Failed model -> needs_review/
            dest_path = os.path.join(OUTPUT_DIR, "needs_review", f"{asset_id}_{filename}")
            shutil.copy2(model_path, dest_path)
            
            dest_thumb_path = os.path.join(OUTPUT_DIR, "needs_review", final_thumb_filename)
            create_failed_thumbnail(dest_thumb_path, "Failed Verification")
            
            final_glb_path = dest_path
            thumbnail_path = dest_thumb_path
            
        # Get source and license
        src_name, lic_name = get_source_and_license(model_path, model_data["source_archive"])
        tex_status = "Yes" if getattr(mesh, "has_textures", False) else "No"
        dims_str = f"{getattr(mesh, 'width', 0.0):.3f} x {getattr(mesh, 'depth', 0.0):.3f} x {getattr(mesh, 'height', 0.0):.3f}"
        
        # Record manifest
        manifest_records.append({
            "asset_id": asset_id,
            "original_path": model_path,
            "original_filename": filename,
            "detected_name": os.path.splitext(filename)[0].replace("_", " ").replace("-", " ").title(),
            "category": category,
            "subcategory": subcategory,
            "format": ext.lstrip('.').upper(),
            "final_glb_path": final_glb_path,
            "thumbnail_path": thumbnail_path,
            "dimensions": dims_str,
            "polygon_count": getattr(mesh, "polygon_count", 0),
            "texture_status": tex_status,
            "duplicate_status": dup_status,
            "source": src_name,
            "license": lic_name,
            "quality_status": inspect_status
        })

    # Save metadata files inside OUTPUT_DIR
    json_manifest_path = os.path.join(OUTPUT_DIR, "new_assets_manifest.json")
    with open(json_manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest_records, f, indent=2)
    print(f"[OK] Generated {json_manifest_path}")
    
    csv_manifest_path = os.path.join(OUTPUT_DIR, "new_assets_manifest.csv")
    with open(csv_manifest_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            "asset_id", "original_path", "original_filename", "detected_name", 
            "category", "subcategory", "format", "final_glb_path", "thumbnail_path", 
            "dimensions", "polygon_count", "texture_status", "duplicate_status", 
            "source", "license", "quality_status"
        ])
        for r in manifest_records:
            writer.writerow([
                r["asset_id"], r["original_path"], r["original_filename"], r["detected_name"],
                r["category"], r["subcategory"], r["format"], r["final_glb_path"], r["thumbnail_path"],
                r["dimensions"], r["polygon_count"], r["texture_status"], r["duplicate_status"],
                r["source"], r["license"], r["quality_status"]
            ])
    print(f"[OK] Generated {csv_manifest_path}")
    
    # Calculate counts of NEW valid models
    new_counts = {cat: 0 for cat in EXISTING_COUNTS.keys()}
    for r in manifest_records:
        if r["quality_status"] == "Success" and r["duplicate_status"] == "unique":
            cat = r["category"]
            if cat in new_counts:
                new_counts[cat] += 1
                
    # Generate txt report content
    report_text = (
        "=========================================================================================\n"
        "                                FLOWSPACE NEW ASSETS REPORT                              \n"
        "=========================================================================================\n\n"
        "INVENTORY SUMMARY:\n"
        "-----------------------------------------------------------------------------------------\n"
        f"- Total files scanned:         {total_files}\n"
        f"- Total models parsed:         {total_models}\n"
        f"- Formats discovered:          {', '.join(sorted(formats))}\n"
        f"- Valid models:                {valid_models}\n"
        f"- Invalid models:              {invalid_models}\n"
        f"- Existing GLBs:               {existing_glbs}\n"
        f"- Convertible models:          {convertible_models}\n"
        f"- Duplicates detected:         {duplicates_count}\n"
        f"- Variants detected:           {variants_count}\n"
        "-----------------------------------------------------------------------------------------\n\n"
        "GAP REPORT UPDATE:\n"
        "-----------------------------------------------------------------------------------------\n"
    )
    
    report_text += f"{'Category':<20} | {'Existing':<10} | {'New Unique':<10} | {'Combined':<10} | {'Target':<6} | {'Remaining Gap':<15}\n"
    report_text += "-" * 81 + "\n"
    for cat in sorted(EXISTING_COUNTS.keys()):
        existing = EXISTING_COUNTS[cat]
        new_val = new_counts[cat]
        combined = existing + new_val
        target = CATEGORY_TARGETS.get(cat, 0)
        gap = max(0, target - combined)
        report_text += f"{cat:<20} | {existing:<10} | {new_val:<10} | {combined:<10} | {target:<6} | {gap:<15}\n"
        
    report_text += "=========================================================================================\n"
    
    txt_report_path = os.path.join(OUTPUT_DIR, "new_assets_report.txt")
    with open(txt_report_path, 'w', encoding='utf-8') as f:
        f.write(report_text)
    print(f"[OK] Generated {txt_report_path}")
    
    print("\n" + report_text)
    
    # Cleanup temp working dir
    try:
        shutil.rmtree(temp_working_dir)
    except Exception:
        pass

if __name__ == '__main__':
    main()
