import os
import sys
import math
import json

# Check if running inside Blender
try:
    import bpy
    import mathutils
except ImportError:
    print("This script must be run inside Blender's python environment.")
    sys.exit(1)

def clean_scene():
    """Removes all objects, meshes, cameras, lights, and materials."""
    # Deselect all
    bpy.ops.object.select_all(action='DESELECT')
    # Select all objects
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.ops.object.delete()
    
    # Clean data blocks
    for block in [bpy.data.meshes, bpy.data.materials, bpy.data.textures, bpy.data.images, bpy.data.cameras, bpy.data.lights]:
        for item in block:
            block.remove(item)

def import_model(filepath):
    """Imports the 3D model based on file extension."""
    ext = os.path.splitext(filepath)[1].lower()
    
    if ext == '.blend':
        # Open blend file directly
        bpy.ops.wm.open_mainfile(filepath=filepath)
        return True
        
    # Otherwise, clean scene first
    clean_scene()
    
    if ext == '.obj':
        try:
            bpy.ops.wm.obj_import(filepath=filepath)
        except AttributeError:
            bpy.ops.import_scene.obj(filepath=filepath)
    elif ext == '.fbx':
        bpy.ops.import_scene.fbx(filepath=filepath)
    elif ext in ['.gltf', '.glb']:
        bpy.ops.import_scene.gltf(filepath=filepath)
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
    """Normalizes the model: centers X/Y, aligns base to Z=0, scales to ~1.0m height if needed."""
    bbox = get_combined_bbox()
    if not bbox:
        return
        
    min_c, max_c = bbox
    cx = (min_c[0] + max_c[0]) / 2.0
    cy = (min_c[1] + max_c[1]) / 2.0
    cz = min_c[2] # Floor alignment
    
    # Shift model to center
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    for obj in meshes:
        # Move objects to ground center
        obj.location.x -= cx
        obj.location.y -= cy
        obj.location.z -= cz
        
    # Recalculate bounding box after translation
    bpy.context.view_layer.update()
    bbox = get_combined_bbox()
    if not bbox:
        return
    min_c, max_c = bbox
    
    # Check dimensions
    dx = max_c[0] - min_c[0]
    dy = max_c[1] - min_c[1]
    dz = max_c[2] - min_c[2]
    max_dim = max(dx, dy, dz)
    
    # Scale normalization: if model is extremely large or small, scale it to ~1m height
    if max_dim > 0 and (max_dim < 0.05 or max_dim > 20.0):
        scale_factor = 1.0 / max_dim
        for obj in meshes:
            obj.scale *= scale_factor
            obj.location *= scale_factor
            
    # Apply transforms
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def setup_studio():
    """Sets up a standardized camera, studio lighting, and render settings."""
    # Add a camera
    cam_data = bpy.data.cameras.new(name="StudioCamera")
    cam_obj = bpy.data.objects.new("StudioCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Configure camera for isometric-like view
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 1.8 # Standard framing for normalized models
    
    # Position camera: Yaw 45 deg, Pitch 30 deg, distance 5m
    yaw = math.radians(45)
    pitch = math.radians(30)
    D = 5.0
    cam_obj.location = (
        D * math.cos(pitch) * math.sin(yaw),
        -D * math.cos(pitch) * math.cos(yaw),
        D * math.sin(pitch) + 0.3
    )
    cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
    
    # Add key light
    light_data = bpy.data.lights.new(name="KeyLight", type='SUN')
    light_data.energy = 4.0
    light_obj = bpy.data.objects.new("KeyLight", light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.location = (4.0, -4.0, 8.0)
    light_obj.rotation_euler = (math.radians(35), math.radians(25), math.radians(45))
    
    # Add fill light
    fill_data = bpy.data.lights.new(name="FillLight", type='SUN')
    fill_data.energy = 1.5
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.location = (-4.0, -4.0, 4.0)
    fill_obj.rotation_euler = (math.radians(55), math.radians(-25), math.radians(-45))

    # Set background color to premium dark slate gray
    bpy.context.scene.render.film_transparent = False
    world = bpy.context.scene.world
    if world:
        world.use_nodes = True
        bg_node = world.node_tree.nodes.get("Background")
        if bg_node:
            bg_node.inputs['Color'].default_value = (0.08, 0.08, 0.1, 1.0)
            
    # Set render resolution and engine
    bpy.context.scene.render.resolution_x = 512
    bpy.context.scene.render.resolution_y = 512
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = 'PNG'
    bpy.context.scene.render.engine = 'BLENDER_EEVEE'

def main():
    # Parse arguments after '--'
    argv = sys.argv
    try:
        idx = argv.index("--")
        args = argv[idx + 1:]
    except ValueError:
        print("Usage: blender --background --python blender_helper.py -- <import_file> <export_glb> <thumbnail_png> <metadata_json>")
        sys.exit(1)
        
    if len(args) < 4:
        print("Insufficient arguments provided.")
        sys.exit(1)
        
    import_file = args[0]
    export_glb = args[1]
    thumbnail_png = args[2]
    metadata_json = args[3]
    
    print(f"Blender Helper processing: {import_file}")
    
    try:
        # Import model
        import_model(import_file)
        
        # Normalize scale and coordinates
        normalize_model()
        
        # Export normalized GLB
        if export_glb and export_glb.lower() != 'none':
            os.makedirs(os.path.dirname(export_glb), exist_ok=True)
            bpy.ops.export_scene.gltf(filepath=export_glb, export_format='GLB')
            print(f"Exported GLB to: {export_glb}")
            
        # Get dimensions and stats
        bbox = get_combined_bbox()
        width, depth, height = 0.0, 0.0, 0.0
        if bbox:
            min_c, max_c = bbox
            width = float(max_c[0] - min_c[0])
            depth = float(max_c[1] - min_c[1])
            height = float(max_c[2] - min_c[2])
            
        poly_count = 0
        has_textures = False
        for mesh in bpy.data.meshes:
            poly_count += len(mesh.polygons)
            
        for mat in bpy.data.materials:
            if mat.use_nodes:
                for node in mat.node_tree.nodes:
                    if node.type == 'TEX_IMAGE' and node.image:
                        has_textures = True
                        break
                        
        # Render thumbnail
        if thumbnail_png and thumbnail_png.lower() != 'none':
            setup_studio()
            os.makedirs(os.path.dirname(thumbnail_png), exist_ok=True)
            bpy.context.scene.render.filepath = thumbnail_png
            bpy.ops.render.render(write_still=True)
            print(f"Rendered thumbnail to: {thumbnail_png}")
            
        # Collect object, mesh, and material names for classification
        obj_names = [obj.name for obj in bpy.context.scene.objects]
        mesh_names = [mesh.name for mesh in bpy.data.meshes]
        mat_names = [mat.name for mat in bpy.data.materials]

        # Save metadata to temporary JSON file
        meta = {
            "width": round(width, 3),
            "depth": round(depth, 3),
            "height": round(height, 3),
            "polygon_count": poly_count,
            "has_textures": has_textures,
            "obj_names": obj_names,
            "mesh_names": mesh_names,
            "mat_names": mat_names,
            "success": True
        }
        with open(metadata_json, 'w') as f:
            json.dump(meta, f)
            
    except Exception as e:
        print(f"Blender processing failed: {str(e)}")
        meta = {
            "success": False,
            "error": str(e)
        }
        with open(metadata_json, 'w') as f:
            json.dump(meta, f)
        sys.exit(1)

if __name__ == '__main__':
    main()
