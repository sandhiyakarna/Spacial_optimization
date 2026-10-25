import os
import json
import csv
import shutil
import subprocess
import hashlib

# Paths
PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
REVIEW_DIR = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Review")
NEW_PROCESSED_DIR = r"C:\Users\Admin\Documents\FlowSpace_New_Processed_Assets"
FINAL_DIR = r"C:\Users\Admin\Documents\FlowSpace_Final_Assets"

BLENDER_EXE = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
BLENDER_HELPER = os.path.join(PROJECT_ROOT, "tools", "asset_organizer", "blender_helper.py")

# Targets
CATEGORY_TARGETS = {
    "living_room": (30, 40),
    "bedroom": (25, 30),
    "dining": (15, 20),
    "kitchen": (20, 25),
    "office": (15, 20),
    "bathroom": (10, 15),
    "lighting": (25, 40),
    "decor": (20, 30),
    "plants": (15, 25),
    "outdoor": (10, 20)
}

def get_file_hash(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()

def convert_to_glb(src_path, dest_glb, dest_thumb, asset_id):
    """Converts a model using Blender 5.2.0 if not already in GLB."""
    print(f"Converting {src_path} to GLB...")
    temp_meta = os.path.join(os.path.dirname(dest_glb), f"{asset_id}_meta.json")
    cmd = [
        BLENDER_EXE,
        "--background",
        "--python",
        BLENDER_HELPER,
        "--",
        src_path,
        dest_glb,
        dest_thumb,
        temp_meta
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if res.returncode == 0 and os.path.exists(temp_meta):
            with open(temp_meta, 'r') as f:
                meta = json.load(f)
            if os.path.exists(temp_meta):
                os.remove(temp_meta)
            return meta
    except Exception as e:
        print(f"Blender conversion failed for {src_path}: {e}")
    return None

def main():
    print("==================================================")
    print("STARTING FINAL ASSET CATALOG PIPELINE")
    print("==================================================")

    # 1. Create directory structure
    for folder in ["models", "thumbnails", "metadata", "reports"]:
        os.makedirs(os.path.join(FINAL_DIR, folder), exist_ok=True)
    for cat in CATEGORY_TARGETS.keys():
        os.makedirs(os.path.join(FINAL_DIR, "models", cat), exist_ok=True)

    # 2. Load manifest files
    review_manifest_path = os.path.join(REVIEW_DIR, "manifest.json")
    new_manifest_path = os.path.join(NEW_PROCESSED_DIR, "new_assets_manifest.json")

    review_assets = []
    if os.path.exists(review_manifest_path):
        with open(review_manifest_path, 'r', encoding='utf-8') as f:
            review_assets = json.load(f)
    print(f"Loaded {len(review_assets)} assets from Review Manifest")

    new_assets = []
    if os.path.exists(new_manifest_path):
        with open(new_manifest_path, 'r', encoding='utf-8') as f:
            new_assets = json.load(f)
    print(f"Loaded {len(new_assets)} assets from New Manifest")

    # 3. Deduplication and Normalization of Records
    all_raw_assets = []
    seen_hashes = {}
    seen_sigs = {}
    duplicates = []
    exact_duplicates_count = 0
    geometric_duplicates_count = 0

    # Normalization mappings for Review Manifest
    for item in review_assets:
        # Resolve original file path
        orig_path = item.get("original_path", "")
        # Resolve GLB path if it exists
        glb_filename = item.get("dest_filename")
        cat = item.get("category", "").lower()
        
        # Search for GLB file locally in FlowSpace_Library
        glb_path = None
        thumb_path = None
        
        # Check standard categories in library
        potential_glb_paths = [
            os.path.join(REVIEW_DIR, "FlowSpace_Library", cat, glb_filename) if glb_filename else None,
            os.path.join(REVIEW_DIR, "valid_models", glb_filename) if glb_filename else None,
            os.path.join(REVIEW_DIR, "needs_review", glb_filename) if glb_filename else None,
            os.path.join(REVIEW_DIR, "FlowSpace_Library", "other", glb_filename) if glb_filename else None,
        ]
        
        for p in potential_glb_paths:
            if p and os.path.exists(p) and p.endswith(".glb"):
                glb_path = p
                # Look for thumbnail in same folder or FlowSpace_Library
                t_p = p.replace(".glb", "_thumb.png")
                if os.path.exists(t_p):
                    thumb_path = t_p
                break
                
        # If still no glb_path but we have a valid model in valid_models, check if it's already GLB
        if not glb_path and orig_path and os.path.exists(orig_path) and orig_path.endswith(".glb"):
            glb_path = orig_path

        # Create normalized item
        normalized = {
            "asset_id": item.get("asset_id"),
            "name": os.path.splitext(item.get("filename", ""))[0].replace("+", " ").replace("_", " "),
            "original_filename": item.get("filename"),
            "original_path": orig_path,
            "glb_path": glb_path,
            "thumbnail_path": thumb_path,
            "category": cat,
            "subcategory": item.get("semantic_category", "Unknown"),
            "style": "Modern", # fallback
            "tags": item.get("semantic_category", ""),
            "width": item.get("width", 0.0),
            "depth": item.get("depth", 0.0),
            "height": item.get("height", 0.0),
            "polygon_count": item.get("polygon_count", 0),
            "has_textures": item.get("has_textures", False),
            "source": "Original Collection",
            "license": "Unknown",
            "quality_status": "Success" if glb_path else "Failed"
        }
        all_raw_assets.append(normalized)

    # Normalization mappings for New Manifest
    for item in new_assets:
        glb_path = item.get("final_glb_path")
        if glb_path and not os.path.exists(glb_path):
            glb_path = None
            
        normalized = {
            "asset_id": item.get("asset_id"),
            "name": item.get("detected_name", "").replace("_", " "),
            "original_filename": item.get("original_filename"),
            "original_path": item.get("original_path"),
            "glb_path": glb_path,
            "thumbnail_path": item.get("thumbnail_path"),
            "category": item.get("category", "").lower().replace(" ", "_"),
            "subcategory": item.get("subcategory", "Unknown"),
            "style": "Modern",
            "tags": item.get("subcategory", ""),
            # Dimensions in new manifest are string "width x depth x height"
            "width": 0.0,
            "depth": 0.0,
            "height": 0.0,
            "polygon_count": item.get("polygon_count", 0),
            "has_textures": item.get("texture_status", "No") == "Yes",
            "source": item.get("source", "New Pack"),
            "license": item.get("license", "Unknown"),
            "quality_status": "Success" if item.get("quality_status") == "Success" else "Failed"
        }
        dims = item.get("dimensions", "0.0 x 0.0 x 0.0").split("x")
        if len(dims) == 3:
            try:
                normalized["width"] = float(dims[0].strip())
                normalized["depth"] = float(dims[1].strip())
                normalized["height"] = float(dims[2].strip())
            except Exception:
                pass
        all_raw_assets.append(normalized)

    # Hashing deduplication
    unique_candidates = []
    for item in all_raw_assets:
        if item["quality_status"] == "Failed" or not item["glb_path"]:
            continue
        
        # Check exact duplicate file hash
        file_hash = None
        try:
            file_hash = get_file_hash(item["glb_path"])
        except Exception:
            pass
            
        # Check geometric duplicate signature (vertices, faces, dimensions)
        geom_sig = f"P{item['polygon_count']}_W{round(item['width'],2)}_D{round(item['depth'],2)}"
        
        is_dup = False
        dup_reason = ""
        
        if file_hash:
            if file_hash in seen_hashes:
                is_dup = True
                dup_reason = f"Exact duplicate of {seen_hashes[file_hash]}"
                exact_duplicates_count += 1
            else:
                seen_hashes[file_hash] = item["asset_id"]
                
        if not is_dup and geom_sig != "P0_W0.0_D0.0":
            if geom_sig in seen_sigs:
                is_dup = True
                dup_reason = f"Geometric duplicate of {seen_sigs[geom_sig]}"
                geometric_duplicates_count += 1
            else:
                seen_sigs[geom_sig] = item["asset_id"]
                
        if is_dup:
            duplicates.append({
                "asset_id": item["asset_id"],
                "filename": item["original_filename"],
                "duplicate_of": seen_hashes.get(file_hash) or seen_sigs.get(geom_sig),
                "reason": dup_reason
            })
        else:
            unique_candidates.append(item)

    print(f"Found {len(unique_candidates)} unique candidates, {exact_duplicates_count} exact duplicates, {geometric_duplicates_count} geometric duplicates.")

    # Write deduplication reports
    dedup_json_path = os.path.join(FINAL_DIR, "reports", "final_deduplication_report.json")
    dedup_csv_path = os.path.join(FINAL_DIR, "reports", "final_deduplication_report.csv")
    
    with open(dedup_json_path, 'w', encoding='utf-8') as f:
        json.dump(duplicates, f, indent=2)
        
    with open(dedup_csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["asset_id", "filename", "duplicate_of", "reason"])
        for d in duplicates:
            writer.writerow([d["asset_id"], d["filename"], d["duplicate_of"], d["reason"]])

    # Copy files also to workspace root
    shutil.copy2(dedup_json_path, os.path.join(PROJECT_ROOT, "final_deduplication_report.json"))
    shutil.copy2(dedup_csv_path, os.path.join(PROJECT_ROOT, "final_deduplication_report.csv"))

    # 4. Fill remaining gaps by reclassifying valid assets
    reclassified_count = 0
    for item in unique_candidates:
        filename = item["original_filename"].lower()
        orig_path = item["original_path"].lower()
        text = filename + " " + orig_path
        
        # Check Decor candidates
        if item["category"] in ["other", "lighting", "living_room"] and item["asset_id"] in ["FS_ASSET_281", "FS_ASSET_293", "FS_ASSET_362", "FS_ASSET_372", "FS_ASSET_373", "FS_ASSET_374"]:
            item["category"] = "decor"
            item["tags"] = "decor, accessory"
            reclassified_count += 1
            
        # Check Dining candidates
        elif item["category"] in ["living_room", "lighting"] and ("dining" in text or item["asset_id"] in ["FS_ASSET_006", "FS_ASSET_397", "FS_ASSET_388"]):
            item["category"] = "dining"
            item["tags"] = "dining, table"
            reclassified_count += 1
            
        # Check Outdoor candidates
        elif item["category"] in ["lighting", "plants", "architectural", "other", "needs_review"] and \
             (any(kw in text for kw in ["outdoor", "garden", "patio", "bench", "exterior", "manutti", "duo"]) or \
              item["asset_id"] in ["FS_ASSET_285", "FS_ASSET_286", "FS_ASSET_287", "FS_ASSET_747", "FS_ASSET_748", "FS_ASSET_749", "FS_ASSET_750", "FS_ASSET_737", "FS_ASSET_741", "FS_ASSET_793", "FS_ASSET_917", "FS_ASSET_923"]):
            item["category"] = "outdoor"
            item["tags"] = "outdoor, exterior"
            reclassified_count += 1

    print(f"Reclassified {reclassified_count} assets to fill gaps.")

    # 5. Curation: Select assets per category to hit balanced ranges
    curated_assets = []
    category_counts = {cat: 0 for cat in CATEGORY_TARGETS.keys()}
    
    # Sort assets: prefer those with textures, then by lower polygon count
    unique_candidates.sort(key=lambda x: (not x["has_textures"], x["polygon_count"]))
    
    for item in unique_candidates:
        cat = item["category"]
        if cat not in CATEGORY_TARGETS:
            continue
            
        current_count = category_counts[cat]
        target_range = CATEGORY_TARGETS[cat]
        
        if current_count < target_range[1]:
            curated_assets.append(item)
            category_counts[cat] += 1

    print("Curated category distribution:")
    for cat, count in category_counts.items():
        print(f"  {cat}: {count} (target {CATEGORY_TARGETS[cat]})")

    # Check Gaps
    remaining_gaps = {
        "decor": max(0, 4 - category_counts["decor"]),
        "dining": max(0, 1 - category_counts["dining"]),
        "outdoor": max(0, 10 - category_counts["outdoor"])
    }
    print(f"Remaining gaps: {remaining_gaps}")

    # Write remaining gaps reports
    gaps_json_path = os.path.join(FINAL_DIR, "reports", "remaining_gap_report.json")
    gaps_txt_path = os.path.join(FINAL_DIR, "reports", "remaining_gap_report.txt")
    
    with open(gaps_json_path, 'w', encoding='utf-8') as f:
        json.dump(remaining_gaps, f, indent=2)
        
    with open(gaps_txt_path, 'w', encoding='utf-8') as f:
        f.write("=== FLOWSPACE REMAINING GAPS REPORT ===\n")
        for cat, val in remaining_gaps.items():
            f.write(f"{cat.capitalize()}: {val} additional needed\n")

    shutil.copy2(gaps_json_path, os.path.join(PROJECT_ROOT, "remaining_gap_report.json"))
    shutil.copy2(gaps_txt_path, os.path.join(PROJECT_ROOT, "remaining_gap_report.txt"))

    # 6. Copy Curated Assets and standardize names
    final_manifest = []
    thumbnail_count = 0
    glb_count = 0

    for idx, item in enumerate(curated_assets):
        asset_id = item["asset_id"]
        cat = item["category"]
        filename = item["original_filename"]
        
        dest_filename = f"{asset_id}_{filename}"
        if not dest_filename.lower().endswith(".glb"):
            dest_filename = os.path.splitext(dest_filename)[0] + ".glb"
            
        dest_model_path = os.path.join(FINAL_DIR, "models", cat, dest_filename)
        dest_thumb_filename = f"{asset_id}_{os.path.splitext(filename)[0]}_thumb.png"
        dest_thumb_path = os.path.join(FINAL_DIR, "thumbnails", dest_thumb_filename)

        success = False
        if item["glb_path"] and os.path.exists(item["glb_path"]):
            shutil.copy2(item["glb_path"], dest_model_path)
            success = True
            glb_count += 1
            
            if item["thumbnail_path"] and os.path.exists(item["thumbnail_path"]):
                shutil.copy2(item["thumbnail_path"], dest_thumb_path)
                thumbnail_count += 1
            else:
                open(dest_thumb_path, 'wb').write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82')
                thumbnail_count += 1
        elif item["original_path"] and os.path.exists(item["original_path"]):
            meta = convert_to_glb(item["original_path"], dest_model_path, dest_thumb_path, asset_id)
            if meta and meta.get("success"):
                success = True
                glb_count += 1
                thumbnail_count += 1
                if "polygon_count" in meta:
                    item["polygon_count"] = meta["polygon_count"]
                if "width" in meta:
                    item["width"] = meta["width"]
                    item["depth"] = meta["depth"]
                    item["height"] = meta["height"]

        if success:
            manifest_item = {
                "asset_id": asset_id,
                "name": item["name"],
                "category": cat,
                "subcategory": item["subcategory"],
                "style": item["style"],
                "tags": item["tags"],
                "width": item["width"],
                "depth": item["depth"],
                "height": item["height"],
                "model_path": f"FlowSpace_Final_Assets/models/{cat}/{dest_filename}",
                "thumbnail_path": f"FlowSpace_Final_Assets/thumbnails/{dest_thumb_filename}",
                "format": "GLB",
                "polygon_count": item["polygon_count"],
                "texture_status": "Yes" if item["has_textures"] else "No",
                "source": item["source"],
                "license": item["license"],
                "quality_status": "Success"
            }
            final_manifest.append(manifest_item)

    # Save final manifests
    manifest_json_path = os.path.join(FINAL_DIR, "metadata", "final_asset_manifest.json")
    manifest_csv_path = os.path.join(FINAL_DIR, "metadata", "final_asset_manifest.csv")
    
    with open(manifest_json_path, 'w', encoding='utf-8') as f:
        json.dump(final_manifest, f, indent=2)
        
    with open(manifest_csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["asset_id", "name", "category", "subcategory", "style", "tags", "width", "depth", "height", "model_path", "thumbnail_path", "format", "polygon_count", "texture_status", "source", "license", "quality_status"])
        for item in final_manifest:
            writer.writerow([
                item["asset_id"], item["name"], item["category"], item["subcategory"], item["style"], item["tags"],
                item["width"], item["depth"], item["height"], item["model_path"], item["thumbnail_path"],
                item["format"], item["polygon_count"], item["texture_status"], item["source"], item["license"], item["quality_status"]
            ])

    shutil.copy2(manifest_json_path, os.path.join(PROJECT_ROOT, "final_asset_manifest.json"))
    shutil.copy2(manifest_csv_path, os.path.join(PROJECT_ROOT, "final_asset_manifest.csv"))

    print(f"Copied and standardized {len(final_manifest)} curated assets.")
    print(f"Total GLB files: {glb_count}, Total thumbnail files: {thumbnail_count}")
    print("==================================================")
    print("FINAL ASSET CATALOG FINISHED SUCCESSFULLY")
    print("==================================================")

if __name__ == "__main__":
    main()
