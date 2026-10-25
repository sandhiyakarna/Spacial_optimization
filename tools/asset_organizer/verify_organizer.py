import os
import sys
import shutil
import tempfile
import json
import subprocess

# Add project root to path
PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
ORGANIZER_DIR = os.path.join(PROJECT_ROOT, "tools", "asset_organizer")
sys.path.append(ORGANIZER_DIR)

def create_mock_obj(filepath, name, scale=1.0):
    """Creates a mock valid 3D OBJ file (a simple chair-like structure)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    
    # 3D vertices of a box with legs
    vertices = [
        # Seat
        [-0.5 * scale, 0.5 * scale, -0.5 * scale],
        [0.5 * scale, 0.5 * scale, -0.5 * scale],
        [0.5 * scale, 0.5 * scale, 0.5 * scale],
        [-0.5 * scale, 0.5 * scale, 0.5 * scale],
        # Backrest
        [-0.5 * scale, 1.2 * scale, -0.5 * scale],
        [0.5 * scale, 1.2 * scale, -0.5 * scale],
        # Legs bottom
        [-0.4 * scale, 0.0 * scale, -0.4 * scale],
        [0.4 * scale, 0.0 * scale, -0.4 * scale],
        [0.4 * scale, 0.0 * scale, 0.4 * scale],
        [-0.4 * scale, 0.0 * scale, 0.4 * scale]
    ]
    
    faces = [
        # Seat top face
        [1, 2, 3], [1, 3, 4],
        # Backrest face
        [5, 6, 2], [5, 2, 1],
        # Leg 1
        [1, 7, 2],
        # Leg 2
        [2, 8, 3],
        # Leg 3
        [3, 9, 4],
        # Leg 4
        [4, 10, 1]
    ]
    
    with open(filepath, 'w') as f:
        f.write(f"# Mock OBJ: {name}\n")
        f.write("mtllib mock_material.mtl\n")
        for v in vertices:
            f.write(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}\n")
        for face in faces:
            # OBJ indices are 1-based
            f.write(f"f {face[0]} {face[1]} {face[2]}\n")

def create_invalid_obj(filepath):
    """Creates a corrupted/invalid OBJ file."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w') as f:
        f.write("# Corrupted OBJ file\n")
        f.write("v 1.0\n") # missing coords
        f.write("f 1 2\n") # invalid face line

def run_verification():
    print("==================================================")
    print("          ORGANIZER VERIFICATION RUN")
    print("==================================================")
    
    # 1. Setup temp test input and output directories
    temp_dir = tempfile.mkdtemp(prefix="fs_test_")
    test_src = os.path.join(temp_dir, "messy_src")
    test_out = os.path.join(temp_dir, "organized_out")
    
    os.makedirs(test_src, exist_ok=True)
    
    print(f"Creating mock assets in: {test_src}")
    
    # Create valid chair model
    create_mock_obj(os.path.join(test_src, "chair_valid.obj"), "ChairValid")
    
    # Create duplicate file (identical copy)
    shutil.copy2(
        os.path.join(test_src, "chair_valid.obj"),
        os.path.join(test_src, "chair_duplicate.obj")
    )
    
    # Create geometric duplicate (different name/hash, same vertices)
    create_mock_obj(os.path.join(test_src, "another_chair.obj"), "AnotherChair")
    
    # Create abnormal scale variant (requires scale normalization)
    create_mock_obj(os.path.join(test_src, "giant_chair.obj"), "GiantChair", scale=50.0)
    
    # Create invalid file
    create_invalid_obj(os.path.join(test_src, "corrupted_model.obj"))
    
    # Copy existing valid GLB from project to test source
    project_glb = os.path.join(PROJECT_ROOT, "frontend", "test_assets", "valid_test.glb")
    test_glb = os.path.join(test_src, "test_asset.glb")
    if os.path.exists(project_glb):
        shutil.copy2(project_glb, test_glb)
        print("[OK] Copied valid_test.glb from project assets.")
    else:
        print("[WARN] Project valid_test.glb not found. Skipping GLB copy.")
        
    print("-" * 50)
    print("Executing organizer.py in fallback mode...")
    
    # 2. Run the organizer
    organizer_script = os.path.join(ORGANIZER_DIR, "organizer.py")
    cmd = [
        sys.executable,
        organizer_script,
        test_src,
        test_out,
        "--force"
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    print("Organizer Output:")
    print(result.stdout)
    if result.stderr:
        print("Organizer Errors:")
        print(result.stderr)
        
    print("-" * 50)
    print("Verifying Outputs...")
    
    # 3. Verify files and outputs
    library_path = os.path.join(test_out, "FlowSpace_Library")
    if not os.path.exists(library_path):
        print("[FAIL] ERROR: FlowSpace_Library directory was not created!")
        return False
        
    # Check outputs metadata
    manifest_file = os.path.join(test_out, "manifest.json")
    duplicates_file = os.path.join(test_out, "duplicates.json")
    invalid_file = os.path.join(test_out, "invalid_models.json")
    review_file = os.path.join(test_out, "review.json")
    summary_file = os.path.join(test_out, "summary.txt")
    
    expected_files = [manifest_file, duplicates_file, invalid_file, review_file, summary_file]
    for ef in expected_files:
        if not os.path.exists(ef):
            print(f"[FAIL] ERROR: Metadata file '{os.path.basename(ef)}' is missing!")
            return False
            
    print("[OK] All metadata JSON files and summary.txt were created.")
    
    # Parse JSONs
    with open(manifest_file, 'r') as f:
        manifest = json.load(f)
    with open(duplicates_file, 'r') as f:
        duplicates = json.load(f)
    with open(invalid_file, 'r') as f:
        invalid = json.load(f)
    with open(review_file, 'r') as f:
        review = json.load(f)
        
    print(f"Manifest count: {len(manifest)}")
    print(f"Duplicates count: {len(duplicates)}")
    print(f"Invalid count: {len(invalid)}")
    print(f"Review count: {len(review)}")
    
    # Verify duplicates detection
    if "chair_valid.obj" not in duplicates and "chair_duplicate.obj" not in duplicates:
        # Note: Depending on which is selected as primary
        has_dup = False
        for k, v in duplicates.items():
            if "chair_duplicate.obj" in v or "chair_valid.obj" in v or "another_chair.obj" in v:
                has_dup = True
        if not has_dup:
            print("[FAIL] ERROR: Duplicates were not detected!")
            return False
    print("[OK] Duplicates/variants were detected correctly.")
    
    # Verify invalid model detection
    if not any(item["filename"] == "corrupted_model.obj" for item in invalid):
        print("[FAIL] ERROR: corrupted_model.obj was not caught as invalid!")
        return False
    print("[OK] corrupted_model.obj was correctly filtered as invalid.")
    
    # Verify normalization output
    # The giant chair should be scaled down to 1.0m height
    giant_meta = next((item for item in manifest if "giant_chair" in item["filename"].lower()), None)
    if giant_meta:
        if giant_meta["height"] > 2.0: # should be ~1.0m due to scale normalization
            print(f"[FAIL] ERROR: Giant chair was not scaled down! Height is {giant_meta['height']}m")
            return False
        else:
            print(f"[OK] Giant chair scaled down to: height={giant_meta['height']}m")
            
    # Verify thumbnails are generated
    needs_review_dir = os.path.join(library_path, "needs_review")
    thumbnails = [f for f in os.listdir(needs_review_dir) if f.endswith("_thumb.png")]
    if not thumbnails:
        print("[FAIL] ERROR: No thumbnails were created in needs_review!")
        return False
    print(f"[OK] Rendered thumbnails: {thumbnails}")
    
    # Clean up temp
    try:
        shutil.rmtree(temp_dir)
        print("[OK] Temporary test directory cleaned up.")
    except Exception:
        pass
        
    print("==================================================")
    print("       VERIFICATION COMPLETED SUCCESSFULLY!")
    print("==================================================")
    return True

if __name__ == '__main__':
    run_verification()
