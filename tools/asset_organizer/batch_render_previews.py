import os
import sys
import math
import json
import zipfile
import tempfile
import shutil

try:
    import bpy
    import mathutils
except ImportError:
    print("This script must be run inside Blender's python environment.")
    sys.exit(1)

# Monkeypatch for Blender 5.2.0 Cycles/FBX importer bug (cast_shadow attribute error)
try:
    import addon_utils
    addon_utils.enable('cycles')
    import cycles.properties
    if hasattr(cycles.properties, 'CyclesLightSettings'):
        if not hasattr(cycles.properties.CyclesLightSettings, 'cast_shadow'):
            cycles.properties.CyclesLightSettings.cast_shadow = bpy.props.BoolProperty(name='Cast Shadow', default=True)
            print("[MONKEYPATCH] Successfully added cast_shadow to CyclesLightSettings.")
except Exception as e:
    print(f"[MONKEYPATCH] Warning: Failed to monkeypatch CyclesLightSettings: {str(e)}")

# Paths
PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
REVIEW_DIR = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Review")
NEEDS_REVIEW_DIR = os.path.join(REVIEW_DIR, "FlowSpace_Library", "needs_review")
OUTPUT_RENDERS_DIR = os.path.join(REVIEW_DIR, "needs_review_renders")
MANIFEST_PATH = os.path.join(REVIEW_DIR, "manifests", "manifest.json")

def clean_scene():
    """Removes all objects, meshes, cameras, lights, and materials context-freely."""
    for obj in list(bpy.context.scene.objects):
        try:
            bpy.data.objects.remove(obj, do_unlink=True)
        except Exception:
            pass
            
    for block in [bpy.data.meshes, bpy.data.materials, bpy.data.textures, bpy.data.images, bpy.data.cameras, bpy.data.lights]:
        for item in list(block):
            try:
                block.remove(item)
            except Exception:
                pass

def import_model(filepath):
    """Imports the 3D model based on file extension."""
    ext = os.path.splitext(filepath)[1].lower()
    
    # Always reset to factory default first to start with a clean slate
    try:
        bpy.ops.wm.read_factory_settings()
    except Exception as e:
        print(f"Warning: Failed to read factory settings: {str(e)}")
        
    if ext == '.blend':
        try:
            bpy.ops.wm.open_mainfile(filepath=filepath)
            # Create a fresh scene to bypass any custom format/render locks in the blend file
            old_scene = bpy.context.scene
            meshes = [obj for obj in old_scene.objects if obj.type == 'MESH']
            new_scene = bpy.data.scenes.new(name='TempScene')
            for obj in meshes:
                try:
                    new_scene.collection.objects.link(obj)
                except Exception:
                    pass
            bpy.context.window.scene = new_scene
            try:
                bpy.data.scenes.remove(old_scene)
            except Exception:
                pass
        except Exception as e:
            print(f"Failed to open blend file or create clean scene: {str(e)}")
            raise e
        return True
        
    clean_scene()
    
    if ext == '.obj':
        try:
            bpy.ops.wm.obj_import(filepath=filepath)
        except AttributeError:
            bpy.ops.import_scene.obj(filepath=filepath)
    elif ext == '.fbx':
        bpy.ops.import_scene.fbx(filepath=filepath)
    elif ext in ['.gltf', '.glb']:
        try:
            bpy.ops.import_scene.gltf(filepath=filepath)
        except AttributeError:
            bpy.ops.wm.gltf_import(filepath=filepath)
    else:
        raise ValueError(f"Unsupported file format: {ext}")
        
    return True

def get_combined_bbox():
    """Computes the combined bounding box of all mesh objects in the scene in world coordinates."""
    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    
    if not meshes:
        return None
        
    min_coords = [float('inf')] * 3
    max_coords = [float('-inf')] * 3
    
    for obj in meshes:
        for vertex in obj.bound_box:
            world_vertex = obj.matrix_world @ mathutils.Vector(vertex)
            for i in range(3):
                min_coords[i] = min(min_coords[i], world_vertex[i])
                max_coords[i] = max(max_coords[i], world_vertex[i])
                
    return min_coords, max_coords

def normalize_model():
    """Normalizes the model: makes meshes single-user, centers X/Y, aligns base to Z=0, scales to ~1.0m height if needed."""
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in meshes:
        obj.select_set(True)
        
    if meshes:
        try:
            bpy.ops.object.make_single_user(type='SELECTED_OBJECTS', object=True, obdata=True)
        except Exception as e:
            print(f"Warning: make_single_user failed: {str(e)}")

    bbox = get_combined_bbox()
    if not bbox:
        return
        
    min_c, max_c = bbox
    cx = (min_c[0] + max_c[0]) / 2.0
    cy = (min_c[1] + max_c[1]) / 2.0
    cz = min_c[2]
    
    for obj in meshes:
        obj.location.x -= cx
        obj.location.y -= cy
        obj.location.z -= cz
        
    bpy.context.view_layer.update()
    bbox = get_combined_bbox()
    if not bbox:
        return
    min_c, max_c = bbox
    
    dx = max_c[0] - min_c[0]
    dy = max_c[1] - min_c[1]
    dz = max_c[2] - min_c[2]
    max_dim = max(dx, dy, dz)
    
    if max_dim > 0 and (max_dim < 0.05 or max_dim > 20.0):
        scale_factor = 1.0 / max_dim
        for obj in meshes:
            obj.scale *= scale_factor
            obj.location *= scale_factor
            
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in meshes:
        obj.select_set(True)
    if meshes:
        bpy.context.view_layer.objects.active = meshes[0]
        try:
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        except Exception as e:
            print(f"Warning: transform_apply failed: {str(e)}")

def setup_studio():
    """Sets up a standardized camera, studio lighting, and render settings context-freely."""
    for obj in list(bpy.context.scene.objects):
        if obj.type in ['CAMERA', 'LIGHT']:
            try:
                bpy.data.objects.remove(obj, do_unlink=True)
            except Exception:
                pass

    cam_data = bpy.data.cameras.new(name="StudioCamera")
    cam_obj = bpy.data.objects.new("StudioCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 1.8
    
    yaw = math.radians(45)
    pitch = math.radians(30)
    D = 5.0
    cam_obj.location = (
        D * math.cos(pitch) * math.sin(yaw),
        -D * math.cos(pitch) * math.cos(yaw),
        D * math.sin(pitch) + 0.3
    )
    cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
    
    light_data = bpy.data.lights.new(name="KeyLight", type='SUN')
    light_data.energy = 4.0
    light_obj = bpy.data.objects.new("KeyLight", light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.location = (4.0, -4.0, 8.0)
    light_obj.rotation_euler = (math.radians(35), math.radians(25), math.radians(45))
    
    fill_data = bpy.data.lights.new(name="FillLight", type='SUN')
    fill_data.energy = 1.5
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.location = (-4.0, -4.0, 4.0)
    fill_obj.rotation_euler = (math.radians(55), math.radians(-25), math.radians(-45))

    bpy.context.scene.render.film_transparent = False
    world = bpy.context.scene.world
    if world:
        world.use_nodes = True
        bg_node = world.node_tree.nodes.get("Background")
        if bg_node:
            bg_node.inputs['Color'].default_value = (0.08, 0.08, 0.1, 1.0)
            
    bpy.context.scene.render.resolution_x = 512
    bpy.context.scene.render.resolution_y = 512
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = 'PNG'
    bpy.context.scene.render.engine = 'BLENDER_EEVEE'

def main():
    print("=" * 60)
    print("      BLENDER BATCH PREVIEW RENDERER")
    print("=" * 60)
    
    os.makedirs(OUTPUT_RENDERS_DIR, exist_ok=True)
    
    # Load manifest
    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        manifest = json.load(f)
    manifest_by_id = {m["asset_id"]: m for m in manifest}
    
    # Scan needs_review
    files = sorted([f for f in os.listdir(NEEDS_REVIEW_DIR) if not f.endswith("_thumb.png")])
    total = len(files)
    print(f"Loaded {total} assets to process.")
    
    for idx, f in enumerate(files):
        # Extract asset ID
        parts = f.split("_")
        if len(parts) >= 3 and parts[0] == "FS" and parts[1] == "ASSET":
            asset_id = parts[0] + "_" + parts[1] + "_" + parts[2]
            filename = f[len(asset_id)+1:]
        else:
            continue
            
        print(f"[{idx+1}/{total}] Batch processing {asset_id}: {filename}...")
        
        # Check if already processed and successful
        preview_png = os.path.join(OUTPUT_RENDERS_DIR, f"{asset_id}_preview.png")
        meta_json = os.path.join(OUTPUT_RENDERS_DIR, f"{asset_id}_meta.json")
        
        # We skip only if both metadata and preview exist, and metadata is success
        if os.path.exists(preview_png) and os.path.exists(meta_json):
            try:
                with open(meta_json, 'r') as file:
                    data = json.load(file)
                if data.get("success"):
                    print("  Already processed successfully. Skipping.")
                    continue
            except Exception:
                pass
                
        model_path = os.path.join(NEEDS_REVIEW_DIR, f)
        original_path = manifest_by_id.get(asset_id, {}).get("original_path", model_path)
        
        # Handle zip extract counterpart if fbx
        temp_model_path = None
        if original_path.lower().endswith(".zip") and f.lower().endswith(".fbx"):
            try:
                base_model_name = os.path.splitext(filename)[0]
                with zipfile.ZipFile(original_path, 'r') as z:
                    zip_names = z.namelist()
                    target_internal_path = None
                    for name in zip_names:
                        name_lower = name.lower()
                        if f"/{base_model_name.lower()}." in name_lower or name_lower.endswith(f"/{base_model_name.lower()}"):
                            if name_lower.endswith(".glb") or name_lower.endswith(".obj"):
                                target_internal_path = name
                                break
                    if not target_internal_path:
                        for name in zip_names:
                            name_lower = name.lower()
                            if base_model_name.lower() in name_lower and (name_lower.endswith(".glb") or name_lower.endswith(".obj")):
                                target_internal_path = name
                                break
                                
                    if target_internal_path:
                        temp_dir = tempfile.mkdtemp(prefix="fs_zip_batch_")
                        ext = os.path.splitext(target_internal_path)[1]
                        extracted_path = os.path.join(temp_dir, f"{base_model_name}{ext}")
                        with z.open(target_internal_path) as z_file, open(extracted_path, 'wb') as out_file:
                            shutil.copyfileobj(z_file, out_file)
                        model_path = extracted_path
                        temp_model_path = temp_dir
                        print(f"  [ZIP] Extracted GLB/OBJ counterpart: {target_internal_path}")
            except Exception as e:
                print(f"  [ZIP] Warning: Failed extraction: {str(e)}")

        success = False
        error_msg = ""
        width, depth, height = 0.0, 0.0, 0.0
        poly_count = 0
        has_textures = False
        obj_names, mesh_names, mat_names = [], [], []

        try:
            # Import model (now safely resets settings and extracts blend scenes)
            import_model(model_path)
            
            # Normalize scale and coordinates
            normalize_model()
            
            # Get dimensions and stats
            bbox = get_combined_bbox()
            if bbox:
                min_c, max_c = bbox
                width = float(max_c[0] - min_c[0])
                depth = float(max_c[1] - min_c[1])
                height = float(max_c[2] - min_c[2])
                
            for mesh in bpy.data.meshes:
                poly_count += len(mesh.polygons)
                
            for mat in bpy.data.materials:
                if mat.use_nodes:
                    for node in mat.node_tree.nodes:
                        if node.type == 'TEX_IMAGE' and node.image:
                            has_textures = True
                            break
                            
            # Render thumbnail
            setup_studio()
            bpy.context.scene.render.filepath = preview_png
            bpy.ops.render.render(write_still=True)
            
            # Collect object, mesh, and material names
            obj_names = [obj.name for obj in bpy.context.scene.objects]
            mesh_names = [mesh.name for mesh in bpy.data.meshes]
            mat_names = [mat.name for mat in bpy.data.materials]
            
            success = True
            print("  Successfully rendered and processed.")
            
        except Exception as e:
            print(f"  Failed: {str(e)}")
            error_msg = str(e)
            # Make sure preview file is removed if it was partially rendered
            if os.path.exists(preview_png):
                try:
                    os.remove(preview_png)
                except Exception:
                    pass
        finally:
            if temp_model_path:
                try:
                    shutil.rmtree(temp_model_path)
                except Exception:
                    pass
            # Always clean scene for the next model
            try:
                clean_scene()
            except Exception:
                pass

        # Write metadata JSON
        meta = {
            "width": round(width, 3),
            "depth": round(depth, 3),
            "height": round(height, 3),
            "polygon_count": poly_count,
            "has_textures": has_textures,
            "obj_names": obj_names,
            "mesh_names": mesh_names,
            "mat_names": mat_names,
            "success": success
        }
        if not success:
            meta["error"] = error_msg
            
        with open(meta_json, 'w') as f_meta:
            json.dump(meta, f_meta)

    print("=" * 60)
    print("      BATCH PROCESSING COMPLETED")
    print("=" * 60)

if __name__ == '__main__':
    main()
