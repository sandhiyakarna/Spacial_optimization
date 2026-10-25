import os
import sys
import json
import csv
import shutil
import math
from PIL import Image, ImageDraw

# Configurations
PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
REVIEW_DIR = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Review")
NEEDS_REVIEW_DIR = os.path.join(REVIEW_DIR, "FlowSpace_Library", "needs_review")
OUTPUT_RENDERS_DIR = os.path.join(REVIEW_DIR, "needs_review_renders")
CONTACT_SHEETS_DIR = os.path.join(REVIEW_DIR, "contact_sheets")
MANIFEST_PATH = os.path.join(REVIEW_DIR, "manifests", "manifest.json")
ARTIFACTS_DIR = r"C:\Users\Admin\.gemini\antigravity-ide\brain\bae867d0-ffbb-4973-b76f-2cc39d01c0db"

# Manual overrides dictionary to correct heuristics after visual review
# Key: asset_id, Value: (category, subcategory, notes)
MANUAL_OVERRIDES = {
    # We will populate this dictionary after visually inspecting the contact sheets.
}

def load_master_manifest():
    """Loads the 603-item discovery manifest."""
    if not os.path.exists(MANIFEST_PATH):
        print(f"[ERROR] Master manifest not found at {MANIFEST_PATH}")
        sys.exit(1)
    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)

def classify_heuristic(filename, metadata):
    """Classifies a model based on its filename, dimensions, and Blender metadata."""
    fn = filename.lower()
    # Filter out studio camera and light objects to avoid false positive matches (e.g. matching 'Light')
    obj_names = [n.lower() for n in metadata.get("obj_names", []) if n.lower() not in ['studiocamera', 'keylight', 'filllight']]
    mesh_names = [n.lower() for n in metadata.get("mesh_names", [])]
    mat_names = [n.lower() for n in metadata.get("mat_names", [])]
    
    width = metadata.get("width", 0.0)
    depth = metadata.get("depth", 0.0)
    height = metadata.get("height", 0.0)
    
    def matches(keywords):
        for kw in keywords:
            if kw in fn:
                return True
            for n in obj_names:
                if kw in n:
                    return True
            for n in mesh_names:
                if kw in n:
                    return True
            for n in mat_names:
                if kw in n:
                    return True
        return False

    # High-priority filename keyword checks to avoid material/sub-object name cross-contamination
    if "kitchen" in fn:
        return "Kitchen", "Kitchen Furniture", 0.9, "High-priority filename match for kitchen"
    if "bathroom" in fn:
        return "Bathroom", "Bathroom Furniture", 0.9, "High-priority filename match for bathroom"
    if "bookcase" in fn or "bookshelf" in fn:
        return "Office", "Bookcase", 0.9, "High-priority filename match for bookcase/bookshelf"
    if "book" in fn:
        return "Decor", "Accessory", 0.9, "High-priority filename match for book"
    if "television" in fn or "tv" in fn:
        return "Living Room", "Television", 0.9, "High-priority filename match for television/tv"
    if "bed" in fn:
        return "Bedroom", "Bed", 0.9, "High-priority filename match for bed"
    if "desk" in fn or "laptop" in fn or "computer" in fn or "keyboard" in fn or "mouse" in fn:
        if "chair" in fn:
            return "Office", "Office Chair", 0.9, "High-priority filename match for desk chair"
        return "Office", "Desk", 0.9, "High-priority filename match for desk/computer item"
    if "sessel" in fn or "armchair" in fn:
        return "Living Room", "Armchair", 0.9, "High-priority filename match for armchair/sessel"
    if "bench" in fn:
        return "Living Room", "Bench", 0.9, "High-priority filename match for bench"
    if "chair" in fn:
        return "Living Room", "Chair", 0.9, "High-priority filename match for chair"
    if "table" in fn:
        if "coffee" in fn:
            return "Living Room", "Table", 0.9, "High-priority filename match for coffee table"
        if "side" in fn:
            return "Living Room", "Table", 0.9, "High-priority filename match for side table"
        return "Dining", "Table", 0.9, "High-priority filename match for dining/general table"
    if "stool" in fn:
        if "bar" in fn:
            return "Kitchen", "Stool", 0.9, "High-priority filename match for bar stool"
        return "Living Room", "Stool", 0.9, "High-priority filename match for stool"
    if "rug" in fn:
        return "Decor", "Rug", 0.9, "High-priority filename match for rug"
    if "pillow" in fn:
        return "Decor", "Pillow", 0.9, "High-priority filename match for pillow"
    if "plant" in fn:
        return "Plants", "Indoor Plant", 0.9, "High-priority filename match for plant"
    if "wall" in fn or "window" in fn or "door" in fn or "stair" in fn or "floor" in fn:
        return "Architectural", "Structure", 0.9, "High-priority filename match for architectural element"
    if "washer" in fn or "dryer" in fn:
        return "Other", "Appliance", 0.9, "High-priority filename match for washer/dryer"


    # 1. Bedroom
    bedroom_keywords = ["bed", "mattress", "nightstand", "dresser", "wardrobe", "closet"]
    if matches(bedroom_keywords) or "bed" in fn:
        if "bed" in fn:
            return "Bedroom", "Bed", 0.9, "Heuristics matched bed keyword"
        return "Bedroom", "Storage", 0.7, "Heuristics matched bedroom keyword"

    # 2. Office
    office_keywords = ["desk", "office", "bookshelf", "bookshelves", "bookcase", "bookcases", "conference", "filing"]
    if matches(office_keywords) or "desk" in fn:
        if "chair" in fn:
            return "Office", "Office Chair", 0.85, "Heuristics matched desk chair keyword"
        return "Office", "Desk", 0.8, "Heuristics matched desk keyword"

    # 3. Living Room / Armchair / Sofa
    living_room_keywords = ["sofa", "couch", "sectional", "armchair", "lounge", "tv_stand", "coffee_table", "credenza", "sideboard", "chest", "sessel"]
    if matches(living_room_keywords) or "sofa" in fn or "sessel" in fn or "couch" in fn:
        if "sofa" in fn or "couch" in fn:
            return "Living Room", "Sofa", 0.9, "Heuristics matched sofa keyword"
        if "sessel" in fn or "armchair" in fn:
            return "Living Room", "Armchair", 0.9, "Heuristics matched armchair/sessel keyword"
        return "Living Room", "Table", 0.7, "Heuristics matched living room keyword"

    # 4. Dining
    dining_keywords = ["dining", "buffet", "dining_table", "dining_chair"]
    if matches(dining_keywords):
        return "Dining", "Dining Furniture", 0.8, "Heuristics matched dining keyword"

    # 5. Bathroom
    bathroom_keywords = ["bathroom", "tub", "bathtub", "shower", "toilet", "vanity", "sink", "faucet", "cabinetbathroom"]
    if matches(bathroom_keywords) or "sink" in fn:
        if "sink" in fn:
            return "Bathroom", "Sink", 0.8, "Heuristics matched sink keyword"
        if "toilet" in fn:
            return "Bathroom", "Toilet", 0.9, "Heuristics matched toilet keyword"
        if "tub" in fn or "bathtub" in fn:
            return "Bathroom", "Bathtub", 0.9, "Heuristics matched bathtub keyword"
        return "Bathroom", "Cabinet", 0.7, "Heuristics matched bathroom keyword"

    # 6. Kitchen
    kitchen_keywords = ["kitchen", "cabinet", "fridge", "refrigerator", "stove", "oven", "pantry", "microwave", "toaster", "blender", "coffee"]
    if matches(kitchen_keywords) or "fridge" in fn or "stove" in fn:
        if "fridge" in fn or "refrigerator" in fn:
            return "Kitchen", "Refrigerator", 0.9, "Heuristics matched fridge keyword"
        if "stove" in fn or "oven" in fn:
            return "Kitchen", "Stove", 0.9, "Heuristics matched stove keyword"
        if "cabinet" in fn:
            return "Kitchen", "Cabinet", 0.8, "Heuristics matched cabinet keyword"
        return "Kitchen", "Appliance", 0.7, "Heuristics matched kitchen keyword"

    # 7. Lighting
    lighting_keywords = ["lamp", "light", "chandelier", "sconce", "lantern", "lighting"]
    has_light = False
    for kw in lighting_keywords:
        if kw in fn:
            has_light = True
            break
        for n in obj_names + mesh_names:
            if kw in n:
                has_light = True
                break
        for n in mat_names:
            # Exclude 'metallight' material name false positive
            if kw in n and "metallight" not in n:
                has_light = True
                break
    if has_light or "lamp" in fn:
        return "Lighting", "Lamp", 0.9, "Heuristics matched lamp/light keyword"

    # 8. Plants
    plants_keywords = ["plant", "flower", "tree", "grass", "shrub", "bush", "potted"]
    if matches(plants_keywords) or "plant" in fn:
        return "Plants", "Indoor Plant", 0.9, "Heuristics matched plant keyword"

    # 9. Decor
    decor_keywords = ["mirror", "rug", "pillow", "cushion", "vase", "clock", "picture", "frame", "sculpture", "art", "decor", "book", "books", "bear", "coatrack", "coat_rack"]
    if matches(decor_keywords) or "rug" in fn or "pillow" in fn or "vase" in fn or "bear" in fn or "coatrack" in fn or "coat_rack" in fn:
        if "rug" in fn:
            return "Decor", "Rug", 0.9, "Heuristics matched rug keyword"
        if "pillow" in fn:
            return "Decor", "Pillow", 0.9, "Heuristics matched pillow keyword"
        if "vase" in fn:
            return "Decor", "Vase", 0.9, "Heuristics matched vase keyword"
        return "Decor", "Accessory", 0.7, "Heuristics matched decor keyword"

    # 10. Outdoor
    outdoor_keywords = ["outdoor", "garden", "patio", "bench", "lounge_chair_garden", "deck"]
    if matches(outdoor_keywords) or "bench" in fn:
        return "Outdoor", "Outdoor Furniture", 0.7, "Heuristics matched outdoor/bench keyword"

    # 11. Architectural
    architectural_keywords = ["wall", "door", "window", "stair", "column", "pillar", "ceiling", "floor", "beam", "roof", "doorway", "paneling"]
    if matches(architectural_keywords) or "wall" in fn or "door" in fn or "stair" in fn or "floor" in fn:
        if "stair" in fn:
            return "Architectural", "Stairs", 0.9, "Heuristics matched stairs keyword"
        if "door" in fn:
            return "Architectural", "Door", 0.9, "Heuristics matched door keyword"
        return "Architectural", "Structure", 0.8, "Heuristics matched architectural keyword"


    # 12. General Chair or Table
    if "chair" in fn:
        return "Living Room", "Chair", 0.6, "Default chair keyword mapping"
    if "table" in fn:
        return "Living Room", "Table", 0.6, "Default table keyword mapping"
    if "stool" in fn:
        return "Living Room", "Stool", 0.6, "Default stool keyword mapping"

    # Heuristics based on dimensions if name is ambiguous
    if width > 0 and depth > 0 and height > 0:
        if width > 1.2 and depth > 1.2 and height < 1.1:
            if depth > width * 1.1:
                return "Bedroom", "Bed", 0.5, "Dimension heuristic: Bed-like shape"
            else:
                return "Living Room", "Sofa", 0.5, "Dimension heuristic: Sofa-like shape"
        if 0.7 <= height <= 0.85 and 0.6 <= width <= 2.2 and 0.6 <= depth <= 2.2:
            return "Dining", "Table", 0.5, "Dimension heuristic: Table-like dimensions"

    return "Other", "Unknown", 0.4, "Fallback category (Other) due to no keyword matches"

def generate_contact_sheets(results):
    """Compiles preview images into 6x6 contact sheet grids."""
    os.makedirs(CONTACT_SHEETS_DIR, exist_ok=True)
    
    # Filter only models with successful previews
    valid_renders = [r for r in results if r["quality_status"] == "Success" and os.path.exists(r["local_preview_path"])]
    print(f"[INFO] Generating contact sheets for {len(valid_renders)} rendered previews...")
    
    cell_w, cell_h = 256, 256
    cols, rows = 6, 6
    sheet_w = cell_w * cols
    sheet_h = cell_h * rows
    
    models_per_sheet = cols * rows
    num_sheets = math.ceil(len(valid_renders) / models_per_sheet)
    
    for s_idx in range(num_sheets):
        sheet_img = Image.new("RGB", (sheet_w, sheet_h), (22, 22, 28))
        draw = ImageDraw.Draw(sheet_img)
        
        start_idx = s_idx * models_per_sheet
        end_idx = min(start_idx + models_per_sheet, len(valid_renders))
        sheet_models = valid_renders[start_idx:end_idx]
        
        for idx, r in enumerate(sheet_models):
            c = idx % cols
            r_idx = idx // cols
            x = c * cell_w
            y = r_idx * cell_h
            
            # Load and paste preview
            try:
                p_img = Image.open(r["local_preview_path"])
                p_img = p_img.resize((cell_w, cell_h), Image.Resampling.LANCZOS)
                sheet_img.paste(p_img, (x, y))
            except Exception as e:
                print(f"[WARNING] Could not load preview for {r['asset_id']}: {str(e)}")
                draw.rectangle([x, y, x+cell_w, y+cell_h], fill=(40, 40, 50))
            
            # Draw overlay card
            draw.rectangle([x, y + cell_h - 60, x + cell_w, y + cell_h], fill=(0, 0, 0, 180))
            
            # Text layout
            draw.text((x + 5, y + cell_h - 55), f"{r['asset_id']}", fill=(0, 255, 128))
            draw.text((x + 5, y + cell_h - 38), f"Cat: {r['detected_category']}", fill=(255, 255, 255))
            
            # Truncated filename
            short_fn = r["filename"]
            if len(short_fn) > 22:
                short_fn = short_fn[:20] + "..."
            draw.text((x + 5, y + cell_h - 20), short_fn, fill=(180, 180, 180))
            
            # Grid borders
            draw.rectangle([x, y, x+cell_w, y+cell_h], outline=(50, 50, 60), width=1)
            
        # Save contact sheet
        sheet_filename = f"contact_sheet_{s_idx+1}.png"
        sheet_path = os.path.join(CONTACT_SHEETS_DIR, sheet_filename)
        sheet_img.save(sheet_path)
        print(f"[OK] Saved contact sheet: {sheet_path}")
        
        # Copy to artifacts directory
        artifact_path = os.path.join(ARTIFACTS_DIR, sheet_filename)
        try:
            shutil.copy2(sheet_path, artifact_path)
        except Exception as e:
            print(f"[WARNING] Failed to copy contact sheet to artifacts: {str(e)}")

def process_review():
    """Main function that runs the pipeline."""
    print("=" * 60)
    print("      FLOWSPACE DETAILED ASSET REVIEW PIPELINE")
    print("=" * 60)
    
    # 1. Load manifest and locate needs_review files
    master_manifest = load_master_manifest()
    manifest_by_id = {m["asset_id"]: m for m in master_manifest}
    
    needs_review_files = sorted([f for f in os.listdir(NEEDS_REVIEW_DIR) if not f.endswith("_thumb.png")])
    print(f"Found {len(needs_review_files)} model files in needs_review folder.")
    
    results = []
    
    for idx, f in enumerate(needs_review_files):
        # Extract asset ID
        parts = f.split("_")
        if len(parts) >= 3 and parts[0] == "FS" and parts[1] == "ASSET":
            asset_id = parts[0] + "_" + parts[1] + "_" + parts[2]
            filename = f[len(asset_id)+1:]
        else:
            continue
            
        model_path = os.path.join(NEEDS_REVIEW_DIR, f)
        original_path = manifest_by_id.get(asset_id, {}).get("original_path", model_path)
        
        # Setup render paths
        preview_png = os.path.join(OUTPUT_RENDERS_DIR, f"{asset_id}_preview.png")
        meta_json = os.path.join(OUTPUT_RENDERS_DIR, f"{asset_id}_meta.json")
        
        detected_category = "Other"
        detected_subcategory = "Unknown"
        confidence = 0.4
        quality_status = "Success"
        notes = ""
        
        # Read pre-rendered metadata if exists
        meta_data = {}
        if os.path.exists(meta_json):
            try:
                with open(meta_json, 'r') as f_meta:
                    meta_data = json.load(f_meta)
            except Exception as e:
                meta_data = {"success": False, "error": f"Failed to read metadata: {str(e)}"}
        else:
            meta_data = {"success": False, "error": "Metadata file not found"}

        # Check Blender run success
        if meta_data.get("success"):
            # Check geometry health
            w, d, h = meta_data.get("width", 0.0), meta_data.get("depth", 0.0), meta_data.get("height", 0.0)
            poly_count = meta_data.get("polygon_count", 0)
            
            if w <= 0 or d <= 0 or h <= 0:
                quality_status = "Invalid: Zero dimensions"
                detected_category = "Invalid"
                notes = f"Zero volume bounds: {w:.3f} x {d:.3f} x {h:.3f}"
            elif poly_count <= 2:
                quality_status = "Invalid: Insufficient geometry"
                detected_category = "Invalid"
                notes = f"Insufficient polygon count: {poly_count}"
            else:
                # Apply heuristics
                detected_category, detected_subcategory, confidence, notes = classify_heuristic(filename, meta_data)
                
                # Check texture status for note
                if meta_data.get("has_textures"):
                    notes += " | Textures detected"
        else:
            # Blender failed
            quality_status = "Invalid: Render failed"
            detected_category = "Invalid"
            notes = meta_data.get("error", "Blender execution failed")
            
        # Apply manual overrides if present
        if asset_id in MANUAL_OVERRIDES:
            over_cat, over_sub, over_notes = MANUAL_OVERRIDES[asset_id]
            detected_category = over_cat
            detected_subcategory = over_sub
            confidence = 1.0
            notes = f"[Manual Override] {over_notes}"
            if over_cat == "Invalid":
                quality_status = "Invalid"
            else:
                quality_status = "Success"

        # Record record
        results.append({
            "asset_id": asset_id,
            "filename": filename,
            "original_path": original_path,
            "preview_path": f"FlowSpace_Asset_Review/needs_review_renders/{asset_id}_preview.png",
            "local_preview_path": preview_png,
            "detected_category": detected_category,
            "detected_subcategory": detected_subcategory,
            "confidence": confidence,
            "quality_status": quality_status,
            "notes": notes
        })

    # 2. Write CSV & JSON reports
    json_out_path = os.path.join(REVIEW_DIR, "review_classification.json")
    csv_out_path = os.path.join(REVIEW_DIR, "review_classification.csv")
    txt_out_path = os.path.join(REVIEW_DIR, "review_summary.txt")
    
    # Save JSON
    with open(json_out_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2)
    print(f"[OK] Saved classification database to {json_out_path}")
    
    # Save CSV
    with open(csv_out_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["asset_id", "original_path", "preview_path", "detected_category", "detected_subcategory", "confidence", "quality_status", "notes"])
        for r in results:
            writer.writerow([r["asset_id"], r["original_path"], r["preview_path"], r["detected_category"], r["detected_subcategory"], r["confidence"], r["quality_status"], r["notes"]])
    print(f"[OK] Saved CSV spreadsheet to {csv_out_path}")

    # Generate Contact Sheets
    generate_contact_sheets(results)
    
    # 3. Calculate revised category stats
    gap_report_path = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Gap_Report.json")
    with open(gap_report_path, 'r', encoding='utf-8') as f:
        gap = json.load(f)
        
    category_counts = {}
    for cat_data in gap["categories"]:
        name = cat_data["category"]
        if name != "Needs Review":
            category_counts[name] = cat_data["existing_usable"]
            
    new_additions = {}
    invalid_reviewed = 0
    total_reviewed_success = 0
    
    for r in results:
        if r["quality_status"] == "Success":
            cat = r["detected_category"]
            if cat in category_counts:
                category_counts[cat] += 1
                new_additions[cat] = new_additions.get(cat, 0) + 1
                total_reviewed_success += 1
            else:
                category_counts[cat] = category_counts.get(cat, 0) + 1
                new_additions[cat] = new_additions.get(cat, 0) + 1
                total_reviewed_success += 1
        else:
            invalid_reviewed += 1

    # Write summary text
    with open(txt_out_path, 'w', encoding='utf-8') as f:
        f.write("============================================================\n")
        f.write("                 FLOWSPACE REVIEW SUMMARY\n")
        f.write("============================================================\n")
        f.write(f"Total Assets Reviewed:          {len(results)}\n")
        f.write(f"  - Valid & Classified:         {total_reviewed_success}\n")
        f.write(f"  - Invalid / Failed:           {invalid_reviewed}\n")
        f.write("------------------------------------------------------------\n")
        f.write("Revised Category Counts (incorporating reviewed assets):\n")
        for cat, count in sorted(category_counts.items()):
            added = new_additions.get(cat, 0)
            f.write(f"  {cat:<20} : {count:<4} (added +{added} from review)\n")
        f.write("------------------------------------------------------------\n")
        
        f.write("\nEvaluation of Target Categories:\n")
        target_eval = {
            "Decor": (category_counts.get("Decor", 0), 20),
            "Plants": (category_counts.get("Plants", 0), 10),
            "Outdoor": (category_counts.get("Outdoor", 0), 10),
            "Dining": (category_counts.get("Dining", 0), 15),
            "Office": (category_counts.get("Office", 0), 15)
        }
        for name, (cnt, target) in target_eval.items():
            gap_size = max(0, target - cnt)
            status = "Genuinely Underrepresented" if gap_size > 0 else "Sufficiently Covered"
            f.write(f"  {name:<10}: Current={cnt:<2} Target={target:<2} Gap={gap_size:<2} -> {status}\n")
        f.write("============================================================\n")
        
    print(f"[OK] Saved text summary to {txt_out_path}")
    
    try:
        shutil.copy2(json_out_path, os.path.join(ARTIFACTS_DIR, "review_classification.json"))
        shutil.copy2(csv_out_path, os.path.join(ARTIFACTS_DIR, "review_classification.csv"))
        shutil.copy2(txt_out_path, os.path.join(ARTIFACTS_DIR, "review_summary.txt"))
        print("[OK] Copied final reports to artifacts directory.")
    except Exception as e:
        print(f"[WARNING] Failed to copy reports to artifacts: {str(e)}")

if __name__ == "__main__":
    process_review()
