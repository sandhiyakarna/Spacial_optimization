import os
import sys
import json
import math
import struct
import hashlib
import shutil
import tempfile
import argparse
import subprocess
import csv
from PIL import Image, ImageDraw

# Supported formats
SUPPORTED_EXTENSIONS = {'.obj', '.glb', '.gltf', '.blend', '.fbx'}
ARCHIVE_EXTENSIONS = {'.zip', '.rar'}

class MeshData:
    def __init__(self):
        self.vertices = []  # List of [x, y, z]
        self.faces = []     # List of [v1, v2, v3]
        self.width = 0.0
        self.depth = 0.0
        self.height = 0.0
        self.polygon_count = 0
        self.mesh_count = 1
        self.has_textures = False
        self.success = False
        self.error_message = ""
        self.obj_names = []
        self.mesh_names = []
        self.mat_names = []

def parse_obj(filepath):
    """Parses an OBJ file and returns MeshData."""
    mesh = MeshData()
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split()
                if not parts:
                    continue
                
                if parts[0] == 'v':
                    if len(parts) >= 4:
                        mesh.vertices.append([float(parts[1]), float(parts[2]), float(parts[3])])
                elif parts[0] == 'f':
                    face_verts = []
                    for part in parts[1:]:
                        v_idx = int(part.split('/')[0])
                        if v_idx < 0:
                            v_idx = len(mesh.vertices) + v_idx
                        else:
                            v_idx = v_idx - 1
                        face_verts.append(v_idx)
                    if len(face_verts) >= 3:
                        for i in range(1, len(face_verts) - 1):
                            mesh.faces.append([face_verts[0], face_verts[i], face_verts[i+1]])
                elif parts[0] in ('usemtl', 'mtllib'):
                    mesh.has_textures = True
                    
        if not mesh.vertices:
            mesh.error_message = "No vertices found in OBJ file"
            return mesh
            
        mesh.polygon_count = len(mesh.faces)
        
        # Calculate bounds
        xs = [v[0] for v in mesh.vertices]
        ys = [v[1] for v in mesh.vertices]
        zs = [v[2] for v in mesh.vertices]
        mesh.width = max(xs) - min(xs)
        mesh.depth = max(zs) - min(zs)
        mesh.height = max(ys) - min(ys)
        
        # Check if textures exist in directory
        parent_dir = os.path.dirname(filepath)
        if os.path.exists(parent_dir):
            for file in os.listdir(parent_dir):
                if file.lower().endswith(('.png', '.jpg', '.jpeg', '.tga', '.dds')):
                    mesh.has_textures = True
                    break
                    
        mesh.success = True
    except Exception as e:
        mesh.error_message = f"OBJ Parsing failed: {str(e)}"
        
    return mesh

def parse_glb_gltf(filepath):
    """Parses GLB/GLTF structural and geometry data natively in Python."""
    mesh = MeshData()
    ext = os.path.splitext(filepath)[1].lower()
    
    try:
        gltf_json = None
        bin_data = b''
        
        if ext == '.glb':
            with open(filepath, 'rb') as f:
                header = f.read(12)
                if len(header) < 12:
                    mesh.error_message = "Invalid GLB header"
                    return mesh
                magic, version, length = struct.unpack('<4sII', header)
                if magic != b'glTF':
                    mesh.error_message = "Not a valid GLB file"
                    return mesh
                
                # Read JSON chunk
                chunk_hdr = f.read(8)
                if len(chunk_hdr) < 8:
                    mesh.error_message = "Invalid JSON chunk header"
                    return mesh
                chunk_len, chunk_type = struct.unpack('<II', chunk_hdr)
                if chunk_type != 0x4E4F534A:
                    mesh.error_message = "First chunk in GLB is not JSON"
                    return mesh
                json_bytes = f.read(chunk_len)
                gltf_json = json.loads(json_bytes.decode('utf-8'))
                
                # Optimize: calculate total vertices first
                total_vertices = 0
                for m in gltf_json.get('meshes', []):
                    for prim in m.get('primitives', []):
                        attrs = prim.get('attributes', {})
                        if 'POSITION' in attrs:
                            pos_idx = attrs['POSITION']
                            if pos_idx < len(gltf_json.get('accessors', [])):
                                total_vertices += gltf_json['accessors'][pos_idx]['count']
                
                # Read BIN chunk if present and total_vertices is small
                if total_vertices <= 50000:
                    bin_hdr = f.read(8)
                    if len(bin_hdr) == 8:
                        chunk_len, chunk_type = struct.unpack('<II', bin_hdr)
                        if chunk_type == 0x004E4942:
                            bin_data = f.read(chunk_len)
                else:
                    # Skip binary decoding for huge assets to avoid OOM / freeze
                    bin_data = b''
        else: # .gltf
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                gltf_json = json.load(f)
            buffers = gltf_json.get('buffers', [])
            if buffers:
                uri = buffers[0].get('uri', '')
                if uri.startswith('data:'):
                    import base64
                    header, base64_data = uri.split(',', 1)
                    bin_data = base64.b64decode(base64_data)
                elif uri:
                    bin_path = os.path.join(os.path.dirname(filepath), uri)
                    if os.path.exists(bin_path):
                        # Optimize: only load bin_data if file is small
                        file_sz = os.path.getsize(bin_path)
                        if file_sz < 50000000: # < 50MB
                            with open(bin_path, 'rb') as f_bin:
                                bin_data = f_bin.read()
                                
        if not gltf_json:
            mesh.error_message = "Failed to parse glTF JSON"
            return mesh
            
        mesh.has_textures = len(gltf_json.get('images', [])) > 0 or len(gltf_json.get('textures', [])) > 0
        mesh.mesh_count = len(gltf_json.get('meshes', []))
        
        total_vertices = 0
        total_triangles = 0
        min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
        max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')
        has_bounds = False
        
        for m in gltf_json.get('meshes', []):
            for prim in m.get('primitives', []):
                attrs = prim.get('attributes', {})
                if 'POSITION' not in attrs:
                    continue
                pos_idx = attrs['POSITION']
                if pos_idx >= len(gltf_json['accessors']):
                    continue
                accessor = gltf_json['accessors'][pos_idx]
                total_vertices += accessor['count']
                
                if 'min' in accessor and 'max' in accessor:
                    min_x = min(min_x, accessor['min'][0])
                    min_y = min(min_y, accessor['min'][1])
                    min_z = min(min_z, accessor['min'][2])
                    max_x = max(max_x, accessor['max'][0])
                    max_y = max(max_y, accessor['max'][1])
                    max_z = max(max_z, accessor['max'][2])
                    has_bounds = True
                    
                if 'indices' in prim:
                    ind_idx = prim['indices']
                    if ind_idx < len(gltf_json['accessors']):
                        ind_accessor = gltf_json['accessors'][ind_idx]
                        total_triangles += ind_accessor['count'] // 3
                else:
                    total_triangles += accessor['count'] // 3
                    
        if total_vertices == 0:
            mesh.error_message = "No vertices found in glTF structure"
            return mesh
            
        mesh.polygon_count = total_triangles
        
        if total_vertices > 50000 or not bin_data:
            if has_bounds:
                mesh.width = max_x - min_x
                mesh.height = max_y - min_y
                mesh.depth = max_z - min_z
            # Bounding box fallback corners
            mesh.vertices = [
                [min_x, min_y, min_z], [max_x, min_y, min_z],
                [max_x, min_y, max_z], [min_x, min_y, max_z],
                [min_x, max_y, min_z], [max_x, max_y, min_z],
                [max_x, max_y, max_z], [min_x, max_y, max_z]
            ]
            mesh.faces = [
                [0, 1, 2], [0, 2, 3], [4, 5, 6], [4, 6, 7],
                [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
                [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]
            ]
            mesh.success = True
            return mesh
            
        # Helper to unpack accessor data
        def get_accessor_data(accessor_idx):
            accessor = gltf_json['accessors'][accessor_idx]
            b_view_idx = accessor.get('bufferView')
            if b_view_idx is None:
                return []
            b_view = gltf_json['bufferViews'][b_view_idx]
            
            offset = accessor.get('byteOffset', 0) + b_view.get('byteOffset', 0)
            comp_type = accessor['componentType']
            type_str = accessor['type']
            count = accessor['count']
            
            type_sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
            type_formats = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
            
            num_components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[type_str]
            elem_size = type_sizes[comp_type] * num_components
            stride = b_view.get('byteStride', elem_size)
            
            # Fast slice unpack if stride is equal to element size
            if stride == elem_size and len(bin_data) >= offset + count * elem_size:
                try:
                    pack_format = f"<{count * num_components}{type_formats[comp_type]}"
                    flat_data = struct.unpack(pack_format, bin_data[offset : offset + count * elem_size])
                    if num_components == 1:
                        return list(flat_data)
                    else:
                        return [list(flat_data[i : i + num_components]) for i in range(0, len(flat_data), num_components)]
                except Exception:
                    pass
                    
            data = []
            for i in range(count):
                elem_offset = offset + i * stride
                chunk = bin_data[elem_offset : elem_offset + elem_size]
                if len(chunk) < elem_size:
                    chunk = chunk.ljust(elem_size, b'\x00')
                values = struct.unpack(f'<{num_components}{type_formats[comp_type]}', chunk)
                data.append(values[0] if num_components == 1 else list(values))
            return data

        for m in gltf_json.get('meshes', []):
            for prim in m.get('primitives', []):
                attrs = prim.get('attributes', {})
                if 'POSITION' not in attrs:
                    continue
                pos_idx = attrs['POSITION']
                vertices = get_accessor_data(pos_idx)
                v_offset = len(mesh.vertices)
                mesh.vertices.extend(vertices)
                
                if 'indices' in prim:
                    indices = get_accessor_data(prim['indices'])
                    for i in range(0, len(indices), 3):
                        if i + 2 < len(indices):
                            mesh.faces.append([indices[i] + v_offset, indices[i+1] + v_offset, indices[i+2] + v_offset])
                else:
                    for i in range(0, len(vertices), 3):
                        if i + 2 < len(vertices):
                            mesh.faces.append([i + v_offset, i + 1 + v_offset, i + 2 + v_offset])
                            
        if not mesh.vertices:
            mesh.error_message = "No coordinate vertex data parsed"
            return mesh
            
        mesh.polygon_count = len(mesh.faces)
        
        # Calculate bounds
        xs = [v[0] for v in mesh.vertices]
        ys = [v[1] for v in mesh.vertices]
        zs = [v[2] for v in mesh.vertices]
        mesh.width = max(xs) - min(xs)
        mesh.height = max(ys) - min(ys)
        mesh.depth = max(zs) - min(zs)
        
        mesh.success = True
    except Exception as e:
        mesh.error_message = f"GLB/GLTF parsing failed: {str(e)}"
        
    return mesh

def normalize_mesh(mesh: MeshData, is_glb_or_gltf):
    """Normalizes coordinate space (centers X/Z, grounds bottom of model to 0, scales max size to 1.0m if needed)."""
    if not mesh.success or not mesh.vertices:
        return
        
    xs = [v[0] for v in mesh.vertices]
    ys = [v[1] for v in mesh.vertices]
    zs = [v[2] for v in mesh.vertices]
    
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    min_z, max_z = min(zs), max(zs)
    
    cx = (min_x + max_x) / 2.0
    cz = (min_z + max_z) / 2.0
    
    # Ground Y for GLTF (where Y is Up), or Ground Z for OBJ (where Z/Y can vary, we assume standard Z is Up)
    if is_glb_or_gltf:
        ground_y = min_y
        for v in mesh.vertices:
            v[0] -= cx
            v[1] -= ground_y
            v[2] -= cz
    else:
        # For OBJ, we assume Z is depth/up or Y is up. Standard: center X/Y, ground Z
        ground_z = min_z
        cy = (min_y + max_y) / 2.0
        for v in mesh.vertices:
            v[0] -= cx
            v[1] -= cy
            v[2] -= ground_z

    # Recompute dimensions
    xs = [v[0] for v in mesh.vertices]
    ys = [v[1] for v in mesh.vertices]
    zs = [v[2] for v in mesh.vertices]
    dx = max(xs) - min(xs)
    dy = max(ys) - min(ys)
    dz = max(zs) - min(zs)
    max_dim = max(dx, dy, dz)
    
    if max_dim > 0 and (max_dim < 0.05 or max_dim > 20.0):
        scale = 1.0 / max_dim
        for v in mesh.vertices:
            v[0] *= scale
            v[1] *= scale
            v[2] *= scale
        mesh.width *= scale
        mesh.height *= scale
        mesh.depth *= scale

def render_software_thumbnail(mesh: MeshData, output_path, is_glb_or_gltf):
    """Renders a wireframe + shaded orthographic isometric view of the 3D model."""
    img_size = 512
    img = Image.new("RGB", (img_size, img_size), (22, 22, 28))
    draw = ImageDraw.Draw(img)
    
    if not mesh.success or not mesh.vertices:
        draw.rectangle([100, 100, 412, 412], fill=(40, 40, 50), outline=(80, 80, 100), width=3)
        draw.text((180, 250), "Preview Unavailable", fill=(200, 200, 220))
        img.save(output_path)
        return False

    try:
        # Rotations: 45 yaw, 30 pitch
        yaw = math.radians(45)
        pitch = math.radians(30)
        
        cos_y, sin_y = math.cos(yaw), math.sin(yaw)
        cos_p, sin_p = math.cos(pitch), math.sin(pitch)
        
        rotated_verts = []
        for v in mesh.vertices:
            x, y, z = v[0], v[1], v[2]
            if is_glb_or_gltf:
                # Y is Up
                rx = x * cos_y - z * sin_y
                ry = y
                rz = x * sin_y + z * cos_y
                
                ry_final = ry * cos_p - rz * sin_p
                rz_final = ry * sin_p + rz * cos_p
                rx_final = rx
            else:
                # Z is Up
                rx = x * cos_y - y * sin_y
                ry = x * sin_y + y * cos_y
                rz = z
                
                rz_final = rz * cos_p - ry * sin_p
                ry_final = rz * sin_p + ry * cos_p
                rx_final = rx
            rotated_verts.append([rx_final, ry_final, rz_final])
            
        proj_xs = [v[0] for v in rotated_verts]
        proj_ys = [v[1] for v in rotated_verts]
        
        min_px, max_px = min(proj_xs), max(proj_xs)
        min_py, max_py = min(proj_ys), max(proj_ys)
        
        span_x = max_px - min_px
        span_y = max_py - min_py
        max_span = max(span_x, span_y)
        if max_span == 0:
            max_span = 1.0
            
        margin = 0.20
        scale = (img_size * (1.0 - 2 * margin)) / max_span
        
        c_proj_x = (min_px + max_px) / 2.0
        c_proj_y = (min_py + max_py) / 2.0
        
        screen_verts = []
        for v in rotated_verts:
            sx = int(img_size / 2.0 + (v[0] - c_proj_x) * scale)
            sy = int(img_size / 2.0 - (v[1] - c_proj_y) * scale)
            screen_verts.append((sx, sy))
            
        # Depth sorting
        face_depths = []
        for idx, face in enumerate(mesh.faces):
            z_avg = (rotated_verts[face[0]][2] + rotated_verts[face[1]][2] + rotated_verts[face[2]][2]) / 3.0
            face_depths.append((z_avg, idx))
        face_depths.sort(key=lambda item: item[0])
        
        light_dir = [0.5, 0.7, 0.5]
        l_len = math.sqrt(sum(c*c for c in light_dir))
        light_dir = [c / l_len for c in light_dir]
        
        for _, face_idx in face_depths:
            face = mesh.faces[face_idx]
            v0 = mesh.vertices[face[0]]
            v1 = mesh.vertices[face[1]]
            v2 = mesh.vertices[face[2]]
            
            # Normal calculation
            ux, uy, uz = v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]
            wx, wy, wz = v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]
            
            nx = uy * wz - uz * wy
            ny = uz * wx - ux * wz
            nz = ux * wy - uy * wx
            
            n_len = math.sqrt(nx*nx + ny*ny + nz*nz)
            if n_len > 0:
                nx, ny, nz = nx/n_len, ny/n_len, nz/n_len
            else:
                nx, ny, nz = 0.0, 0.0, 1.0
                
            dot = nx * light_dir[0] + ny * light_dir[1] + nz * light_dir[2]
            intensity = 0.40 + 0.60 * max(0.0, dot)
            
            # Bronze shade style
            r = int(210 * intensity)
            g = int(175 * intensity)
            b = int(130 * intensity)
            
            or_val = max(0, r - 30)
            og_val = max(0, g - 30)
            ob_val = max(0, b - 30)
            
            pts = [screen_verts[face[0]], screen_verts[face[1]], screen_verts[face[2]]]
            draw.polygon(pts, fill=(r, g, b), outline=(or_val, og_val, ob_val))
            
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        img.save(output_path)
        return True
    except Exception as e:
        print(f"Rasterizer failed: {str(e)}")
        draw.rectangle([100, 100, 412, 412], fill=(40, 40, 50), outline=(80, 80, 100), width=3)
        draw.text((180, 250), "Rasterization Error", fill=(200, 100, 100))
        img.save(output_path)
        return False

def extract_archive(archive_path, extract_to):
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
            # Use built-in tar command on Windows
            cmd = f'tar -xf "{archive_path}" -C "{extract_to}"'
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            return res.returncode == 0
        except Exception as e:
            print(f"RAR extraction failed: {str(e)}")
            return False
    return False

def get_file_hash(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()

def get_geometric_sig(mesh: MeshData):
    if not mesh.success:
        return None
    # Round bounds and polycount
    w = round(mesh.width, 2)
    d = round(mesh.depth, 2)
    h = round(mesh.height, 2)
    return f"V{len(mesh.vertices)}_F{len(mesh.faces)}_W{w}_D{d}_H{h}"

def detect_blender(cli_path=None):
    """Automatically detects the Blender executable path on Windows or PATH."""
    if cli_path and os.path.exists(cli_path):
        return cli_path

    # Check environment variable
    env_path = os.environ.get("BLENDER_PATH")
    if env_path and os.path.exists(env_path):
        return env_path

    # Check .env file in the script's directory
    env_file = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                if line.strip().startswith("BLENDER_PATH="):
                    path = line.split("=", 1)[1].strip().strip('"\'')
                    if os.path.exists(path):
                        return path

    # Check system PATH
    path_check = shutil.which("blender")
    if path_check:
        return path_check

    # Check standard Windows directories
    standard_dirs = [
        r"C:\Program Files\Blender Foundation",
        r"C:\Program Files (x86)\Blender Foundation"
    ]
    for base_dir in standard_dirs:
        if os.path.exists(base_dir):
            for root, dirs, files in os.walk(base_dir):
                if "blender.exe" in files:
                    return os.path.join(root, "blender.exe")
    return None

def run_blender_helper(blender_path, model_path, output_glb_path, preview_dest_path):
    """Runs blender_helper.py inside Blender in background mode to process the model."""
    temp_dir = tempfile.mkdtemp(prefix="fs_blender_meta_")
    meta_json = os.path.join(temp_dir, "metadata.json")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    helper_path = os.path.join(script_dir, "blender_helper.py")

    cmd = [
        blender_path,
        "--background",
        "--python",
        helper_path,
        "--",
        model_path,
        output_glb_path if output_glb_path else "None",
        preview_dest_path if preview_dest_path else "None",
        meta_json
    ]

    mesh = MeshData()
    try:
        # Run Blender
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if os.path.exists(meta_json):
            with open(meta_json, 'r') as f:
                data = json.load(f)
            if data.get("success"):
                mesh.success = True
                mesh.width = data.get("width", 0.0)
                mesh.depth = data.get("depth", 0.0)
                mesh.height = data.get("height", 0.0)
                mesh.polygon_count = data.get("polygon_count", 0)
                mesh.has_textures = data.get("has_textures", False)
                mesh.obj_names = data.get("obj_names", [])
                mesh.mesh_names = data.get("mesh_names", [])
                mesh.mat_names = data.get("mat_names", [])
            else:
                mesh.error_message = data.get("error", "Unknown Blender helper error")
        else:
            mesh.error_message = f"Blender helper did not write metadata file. stdout: {res.stdout[:500]}..."
    except Exception as e:
        mesh.error_message = f"Failed to execute Blender: {str(e)}"
    finally:
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass
    return mesh

def classify_model(mesh: MeshData, filename: str, path: str) -> str:
    """Classifies a model based on its metadata and file naming clues."""
    fn = filename.lower()
    path_lower = path.lower()
    
    # Extract names from metadata
    obj_names = [n.lower() for n in mesh.obj_names]
    mesh_names = [n.lower() for n in mesh.mesh_names]
    mat_names = [n.lower() for n in mesh.mat_names]
    
    # Check dimensions
    width = mesh.width
    depth = mesh.depth
    height = mesh.height
    poly_count = mesh.polygon_count
    
    # Helper to check if keyword matches
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

    # Check for materials/textures which represent flat planes or spheres, usually "Other" or "Architectural"
    material_keywords = ["asphalt", "cobblestone", "gravel", "cotton", "crepe", "satin", "teddy", "checkered", "fabric", 
                         "fleece", "fur", "knitted", "plank_wall", "road_damaged", "road_clean", "rock_tile", "velour", 
                         "velvet", "waffle", "planks", "wool", "boucle", "material", "texture", "pattern_4k"]
    if matches_keyword(material_keywords):
        if "wall" in fn or "floor" in fn or "plank" in fn:
            return "Architectural"
        return "Other"

    # Living Room keywords
    living_room_keywords = ["sofa", "couch", "sectional", "armchair", "lounge", "tv_stand", "coffee_table", "credenza", "sideboard", "chest"]
    if matches_keyword(living_room_keywords):
        return "Living Room"
        
    # Bedroom keywords
    bedroom_keywords = ["bed", "mattress", "nightstand", "dresser", "wardrobe", "closet"]
    if matches_keyword(bedroom_keywords):
        return "Bedroom"

    # Dining keywords
    dining_keywords = ["dining", "buffet", "dining_table", "dining_chair"]
    if (matches_keyword(["table"]) and matches_keyword(["chair"])) or matches_keyword(["dinning", "dining"]):
        return "Dining"
        
    # Kitchen keywords
    kitchen_keywords = ["kitchen", "cabinet", "counter", "sink", "fridge", "refrigerator", "stove", "oven", "pantry", "faucet"]
    if matches_keyword(kitchen_keywords):
        return "Kitchen"

    # Office keywords
    office_keywords = ["desk", "office_chair", "office", "bookshelf", "bookshelves", "bookself", "conference_table", "filing_cabinet"]
    if matches_keyword(office_keywords):
        return "Office"

    # Bathroom keywords
    bathroom_keywords = ["bathroom", "tub", "bathtub", "shower", "toilet", "vanity", "bathroom_mirror"]
    if matches_keyword(bathroom_keywords):
        return "Bathroom"

    # Lighting keywords
    lighting_keywords = ["lamp", "light", "chandelier", "sconce", "lantern", "lighting", "illumination"]
    if matches_keyword(lighting_keywords):
        return "Lighting"

    # Plants keywords
    plants_keywords = ["plant", "flower", "tree", "grass", "shrub", "bush", "vegetation", "pot_plant"]
    if matches_keyword(plants_keywords):
        return "Plants"

    # Outdoor keywords
    outdoor_keywords = ["outdoor", "garden", "patio", "bench", "lounge_chair_garden", "deck"]
    if matches_keyword(outdoor_keywords):
        return "Outdoor"

    # Architectural keywords
    architectural_keywords = ["wall", "door", "window", "stair", "column", "pillar", "ceiling", "floor", "beam", "roof"]
    if matches_keyword(architectural_keywords):
        return "Architectural"

    # Decor keywords
    decor_keywords = ["mirror", "rug", "pillow", "cushion", "vase", "clock", "picture", "frame", "sculpture", "art", "decor", "book", "books"]
    if matches_keyword(decor_keywords):
        return "Decor"

    # Heuristics based on dimensions if name is ambiguous
    if width > 0 and depth > 0 and height > 0:
        # Bed or Sofa
        if width > 1.2 and depth > 1.2 and height < 1.1:
            if depth > width * 1.1:
                return "Bedroom"
            else:
                return "Living Room"
        # Sofa-like
        if width > 1.4 and depth < 1.1 and height < 1.1:
            return "Living Room"
        # Table-like (height around 0.7-0.85m)
        if 0.7 <= height <= 0.85 and 0.6 <= width <= 2.2 and 0.6 <= depth <= 2.2:
            return "Dining"
        # Chair-like (small width/depth, height around 0.8-1.2m)
        if width < 0.8 and depth < 0.8 and 0.7 < height < 1.2:
            return "Living Room"
            
    if poly_count < 10 or width == 0:
        return "Needs Review"
        
    return "Other"

def main():
    parser = argparse.ArgumentParser(description="FlowSpace 3D Asset Organizer")
    parser.add_argument("src_dir", nargs="?", help="Source directory containing raw 3D assets")
    parser.add_argument("out_dir", nargs="?", help="Output directory for the organized library")
    parser.add_argument("--sources", nargs="+", help="Alternative source directories to scan")
    parser.add_argument("--output", help="Alternative output directory path")
    parser.add_argument("--api-key", help="Gemini API Key")
    parser.add_argument("--blender-path", help="Path to blender.exe")
    parser.add_argument("--force", action="store_true", help="Force overwrite output directory")
    args = parser.parse_args()

    # Resolve sources
    sources = []
    if args.src_dir:
        sources = [args.src_dir]
    elif args.sources:
        sources = args.sources
    else:
        sources = [
            r"c:\Users\Admin\Documents\furniture2",
            r"c:\Users\Admin\Documents\furnitureforprojects"
        ]

    resolved_sources = []
    for src in sources:
        resolved = os.path.abspath(src)
        if not os.path.exists(resolved):
            # Check for common misspellings (e.g. furnitureforprojects -> furnituresforprojects)
            if "furnitureforprojects" in resolved:
                alt = resolved.replace("furnitureforprojects", "furnituresforprojects")
                if os.path.exists(alt):
                    resolved = alt
            elif "furnituresforprojects" in resolved:
                alt = resolved.replace("furnituresforprojects", "furnitureforprojects")
                if os.path.exists(alt):
                    resolved = alt
        resolved_sources.append(resolved)

    # Resolve output
    output_dir = None
    if args.out_dir:
        output_dir = args.out_dir
    elif args.output:
        output_dir = args.output
    else:
        output_dir = r"c:\Users\Admin\Documents\mad2\FlowSpace_Asset_Review"
    output_dir = os.path.abspath(output_dir)

    print("=" * 60)
    print("      FLOWSPACE 3D ASSET ORGANIZER")
    print("=" * 60)
    print(f"Sources: {resolved_sources}")
    print(f"Output:  {output_dir}")
    print("-" * 60)

    # Verify sources exist
    valid_sources = []
    for src in resolved_sources:
        if os.path.exists(src):
            valid_sources.append(src)
        else:
            print(f"[ERROR] Source folder does not exist: {src}")

    if not valid_sources:
        print("[ERROR] No valid source directories found. Exiting.")
        sys.exit(1)

    # Automatically detect Blender
    blender_exe = detect_blender(args.blender_path)
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
        print("[INFO] Blender not detected. Using software fallback pipeline.")

    # Output directory structure as expected by verify_organizer.py
    library_dir = os.path.join(output_dir, "FlowSpace_Library")
    categories = [
        "living_room", "bedroom", "dining", "kitchen", "bathroom",
        "office", "lighting", "decor", "plants", "outdoor",
        "architectural", "other", "needs_review", "duplicates"
    ]

    # Clean output if force option is set
    if args.force and os.path.exists(output_dir):
        # We preserve output_dir but recreate libraries if needed
        try:
            shutil.rmtree(library_dir, ignore_errors=True)
        except Exception:
            pass

    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(library_dir, exist_ok=True)
    for cat in categories:
        os.makedirs(os.path.join(library_dir, cat), exist_ok=True)

    # Stats trackers
    folder_stats = {}
    for src in valid_sources:
        folder_name = os.path.basename(src)
        folder_stats[folder_name] = {"files": 0, "models": 0}

    combined_stats = {
        "total_models": 0,
        "exact_duplicates": 0,
        "geometric_duplicates": 0,
        "valid_models": 0,
        "invalid_models": 0,
        "rendered": 0,
        "needs_review": 0
    }

    discovered_formats = set()
    inventory_records = []
    
    # Assert-verification records
    manifest_records = []
    duplicates_records = {} # primary_filename -> [duplicate_filenames]
    invalid_records = []
    review_records = []

    # De-duplication structures
    seen_hashes = {}      # file_hash -> asset_id
    seen_geometries = {}  # geom_sig -> asset_id
    asset_id_to_filename = {} # asset_id -> filename
    asset_id_counter = 1
    # Classification and Gap Report statistics
    category_targets = {
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
    
    category_counts = {}
    for cat in category_targets.keys():
        category_counts[cat] = {"usable": 0, "duplicates": 0, "needs_review": 0}

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

    unique_asset_categories = {}

    total_discovered = 0
    total_unique = 0
    total_valid = 0
    total_valid_glb = 0
    total_convertible_to_glb = 0
    total_duplicates = 0
    total_invalid = 0
    total_needing_review = 0

    temp_working_dir = tempfile.mkdtemp(prefix="fs_organizer_working_")

    # Phase 1: recursive scan
    for src in valid_sources:
        folder_name = os.path.basename(src)
        print(f"Scanning folder: {folder_name}...")

        # Gather all files in original folder recursively for count
        orig_files_count = 0
        all_candidate_files = []

        for root, _, filenames in os.walk(src):
            for filename in filenames:
                orig_files_count += 1
                full_path = os.path.join(root, filename)
                ext = os.path.splitext(filename)[1].lower()
                if ext in SUPPORTED_EXTENSIONS or ext in ARCHIVE_EXTENSIONS:
                    all_candidate_files.append((full_path, False, "")) # (path, is_extracted, inner_path)

        folder_stats[folder_name]["files"] = orig_files_count

        # Handle archives and extraction
        extracted_files = []
        for file_path, is_ext, inner_p in all_candidate_files:
            ext = os.path.splitext(file_path)[1].lower()
            if ext in ARCHIVE_EXTENSIONS:
                archive_name = os.path.basename(file_path)
                extract_target = os.path.join(temp_working_dir, folder_name, archive_name)
                print(f"  Extracting archive {archive_name}...")
                if extract_archive(file_path, extract_target):
                    # Scan extracted contents
                    for e_root, _, e_filenames in os.walk(extract_target):
                        for e_filename in e_filenames:
                            e_ext = os.path.splitext(e_filename)[1].lower()
                            if e_ext in SUPPORTED_EXTENSIONS:
                                e_path = os.path.join(e_root, e_filename)
                                rel_path = os.path.relpath(e_path, extract_target)
                                extracted_files.append((e_path, True, f"{archive_name}/{rel_path}", file_path))

        # Combine direct files and extracted models
        models_to_process = []
        for path, is_ext, inner in all_candidate_files:
            ext = os.path.splitext(path)[1].lower()
            if ext in SUPPORTED_EXTENSIONS:
                models_to_process.append((path, False, os.path.basename(path), path))

        for path, is_ext, inner, archive_path in extracted_files:
            models_to_process.append((path, True, inner, archive_path))

        folder_stats[folder_name]["models"] = len(models_to_process)
        combined_stats["total_models"] += len(models_to_process)

        # Process each model
        for model_path, is_extracted, display_path, origin_source_path in models_to_process:
            filename = os.path.basename(model_path)
            fmt = os.path.splitext(filename)[1].lower()
            discovered_formats.add(fmt.upper())

            # File size
            f_size = os.path.getsize(model_path)

            # Compute hash
            f_hash = get_file_hash(model_path)

            # Parse model natively (for fallback validation or hash checks)
            mesh = None
            if fmt in ['.glb', '.gltf']:
                mesh = parse_glb_gltf(model_path)
            elif fmt == '.obj':
                mesh = parse_obj(model_path)
            else:
                mesh = MeshData()
                mesh.error_message = f"Format {fmt} requires Blender for inspection."

            # Determine duplicate status
            dup_status = "unique"
            primary_id = None

            if f_hash in seen_hashes:
                dup_status = "duplicate"
                primary_id = seen_hashes[f_hash]
                combined_stats["exact_duplicates"] += 1
            else:
                geom_sig = get_geometric_sig(mesh) if mesh.success else None
                if geom_sig and geom_sig in seen_geometries:
                    dup_status = "duplicate"
                    primary_id = seen_geometries[geom_sig]
                    combined_stats["geometric_duplicates"] += 1
                else:
                    is_variant = False
                    if mesh.success:
                        for sig, pid in seen_geometries.items():
                            if sig.startswith(f"V{len(mesh.vertices)}_F{mesh.polygon_count}_"):
                                dup_status = "variant"
                                primary_id = pid
                                is_variant = True
                                combined_stats["geometric_duplicates"] += 1
                                break
                    if not is_variant:
                        dup_status = "unique"

            # Allocate Asset ID
            if dup_status == "unique":
                asset_id = f"FS_ASSET_{asset_id_counter:03d}"
                asset_id_counter += 1
                seen_hashes[f_hash] = asset_id
                geom_sig = get_geometric_sig(mesh) if mesh.success else None
                if geom_sig:
                    seen_geometries[geom_sig] = asset_id
                asset_id_to_filename[asset_id] = filename
            else:
                asset_id = f"FS_ASSET_{asset_id_counter:03d}"
                asset_id_counter += 1
                
                # Record duplicate mapping
                if primary_id and primary_id in asset_id_to_filename:
                    prim_filename = asset_id_to_filename[primary_id]
                    if prim_filename not in duplicates_records:
                        duplicates_records[prim_filename] = []
                    duplicates_records[prim_filename].append(filename)

            # Temporary files to hold outputs from Blender before classification
            temp_glb_path = os.path.join(temp_working_dir, f"{asset_id}_temp.glb")
            temp_thumb_path = os.path.join(temp_working_dir, f"{asset_id}_temp_thumb.png")

            # Process / Render using Blender or Fallback
            rendered = False
            inspect_status = "Success"
            
            if blender_detected:
                blender_mesh = run_blender_helper(blender_exe, model_path, temp_glb_path, temp_thumb_path)
                if blender_mesh.success:
                    if blender_mesh.width <= 0 or blender_mesh.height <= 0 or blender_mesh.depth <= 0:
                        inspect_status = "Failed: zero volume dimensions"
                    elif blender_mesh.polygon_count <= 2:
                        inspect_status = "Failed: insufficient geometry polygons"
                    else:
                        mesh = blender_mesh
                        rendered = True
                        combined_stats["rendered"] += 1
                else:
                    inspect_status = f"Failed: {blender_mesh.error_message}"
            
            # If Blender was not run or failed, check Python native parsing
            if not rendered:
                if not mesh.success:
                    inspect_status = f"Failed: {mesh.error_message}"
                elif mesh.width <= 0 or mesh.height <= 0 or mesh.depth <= 0:
                    inspect_status = "Failed: zero volume dimensions"
                elif mesh.polygon_count <= 2:
                    inspect_status = "Failed: insufficient geometry polygons"

                if inspect_status == "Success":
                    normalize_mesh(mesh, fmt in ['.glb', '.gltf'])
                    if render_software_thumbnail(mesh, temp_thumb_path, fmt in ['.glb', '.gltf']):
                        rendered = True
                        combined_stats["rendered"] += 1

            # Determine category and copy/move outputs
            semantic_category = "Needs Review"
            target_category = "needs_review"
            
            if inspect_status == "Success":
                # Determine classification
                if dup_status in ["duplicate", "variant"]:
                    # Find category of primary model
                    if primary_id and primary_id in unique_asset_categories:
                        semantic_category = unique_asset_categories[primary_id]
                    else:
                        semantic_category = classify_model(mesh, filename, model_path)
                    target_category = "duplicates"
                    category_counts[semantic_category]["duplicates"] += 1
                else:
                    semantic_category = classify_model(mesh, filename, model_path)
                    target_category = CAT_MAP.get(semantic_category, "needs_review")
                    unique_asset_categories[asset_id] = semantic_category
                    if semantic_category == "Needs Review":
                        category_counts["Needs Review"]["needs_review"] += 1
                    else:
                        category_counts[semantic_category]["usable"] += 1
            else:
                semantic_category = "Needs Review"
                target_category = "needs_review"
                category_counts["Needs Review"]["needs_review"] += 1

            category = target_category
            target_folder = os.path.join(library_dir, category)
            os.makedirs(target_folder, exist_ok=True)

            if rendered and inspect_status == "Success":
                dest_filename = f"{asset_id}_{os.path.splitext(filename)[0]}.glb"
                dest_path = os.path.join(target_folder, dest_filename)
                if os.path.exists(temp_glb_path):
                    shutil.move(temp_glb_path, dest_path)
            else:
                dest_filename = f"{asset_id}_{filename}"
                dest_path = os.path.join(target_folder, dest_filename)
                shutil.copy2(model_path, dest_path)

            preview_filename = f"{asset_id}_{os.path.splitext(filename)[0]}_thumb.png"
            preview_dest = os.path.join(target_folder, preview_filename)
            if os.path.exists(temp_thumb_path):
                shutil.move(temp_thumb_path, preview_dest)
            else:
                # Render standard failed thumbnail
                img_size = 512
                img = Image.new("RGB", (img_size, img_size), (22, 22, 28))
                draw = ImageDraw.Draw(img)
                draw.rectangle([100, 100, 412, 412], fill=(40, 40, 50), outline=(80, 80, 100), width=3)
                draw.text((180, 250), "Preview Unavailable", fill=(200, 200, 220))
                img.save(preview_dest)

            # Record stats
            total_discovered += 1
            if inspect_status == "Success":
                total_valid += 1
                if fmt == '.glb':
                    total_valid_glb += 1
                else:
                    total_convertible_to_glb += 1
                if dup_status == "unique":
                    total_unique += 1
                else:
                    total_duplicates += 1
            else:
                total_invalid += 1

            if inspect_status == "Success":
                combined_stats["valid_models"] += 1
                manifest_records.append({
                    "asset_id": asset_id,
                    "filename": filename,
                    "dest_filename": dest_filename,
                    "original_path": origin_source_path,
                    "preview_path": f"FlowSpace_Library/{category}/{preview_filename}",
                    "format": fmt.lstrip('.').upper(),
                    "width": round(mesh.width, 3),
                    "depth": round(mesh.depth, 3),
                    "height": round(mesh.height, 3),
                    "polygon_count": mesh.polygon_count,
                    "has_textures": mesh.has_textures,
                    "duplicate_status": dup_status,
                    "category": category,
                    "semantic_category": semantic_category
                })
                if category == "needs_review":
                    review_records.append({
                        "filename": filename,
                        "reason": "Missing API Key for auto-classification" if not args.api_key else "Needs review verification"
                    })
            else:
                combined_stats["invalid_models"] += 1
                combined_stats["needs_review"] += 1
                invalid_records.append({
                    "filename": filename,
                    "original_path": origin_source_path,
                    "error": inspect_status
                })

            # Populate inventory values (Phase 1)
            has_geom = mesh.success and len(mesh.vertices) > 0
            mesh_cnt = mesh.mesh_count if mesh.success else 0
            vert_cnt = len(mesh.vertices) if mesh.success else 0
            poly_cnt = mesh.polygon_count if mesh.success else 0
            dims_str = f"{mesh.width:.3f} x {mesh.depth:.3f} x {mesh.height:.3f}" if mesh.success else "0.000 x 0.000 x 0.000"
            has_tex = mesh.has_textures if mesh.success else False

            inventory_records.append({
                "source_folder": folder_name,
                "original_path": origin_source_path,
                "filename": filename,
                "format": fmt,
                "file_size": f_size,
                "whether_it_contains_geometry": has_geom,
                "mesh_count": mesh_cnt,
                "approximate_vertex_count": vert_cnt,
                "dimensions": dims_str,
                "texture_presence": has_tex,
                "inspection_status": inspect_status
            })

    # Write output JSON files directly inside output_dir
    with open(os.path.join(output_dir, "manifest.json"), 'w', encoding='utf-8') as f:
        json.dump(manifest_records, f, indent=2)

    with open(os.path.join(output_dir, "duplicates.json"), 'w', encoding='utf-8') as f:
        json.dump(duplicates_records, f, indent=2)

    with open(os.path.join(output_dir, "invalid_models.json"), 'w', encoding='utf-8') as f:
        json.dump(invalid_records, f, indent=2)

    with open(os.path.join(output_dir, "review.json"), 'w', encoding='utf-8') as f:
        json.dump(review_records, f, indent=2)

    # Render final report string
    report_text = (
        "============================================================\n"
        "                  FLOWSPACE INVENTORY REPORT\n"
        "============================================================\n"
    )
    for src in valid_sources:
        folder_name = os.path.basename(src)
        stats = folder_stats[folder_name]
        report_text += (
            f"{folder_name}:\n"
            f"  - files: {stats['files']}\n"
            f"  - models: {stats['models']}\n"
        )
    report_text += (
        "------------------------------------------------------------\n"
        "Combined:\n"
        f"  - total models: {combined_stats['total_models']}\n"
        f"  - exact duplicates: {combined_stats['exact_duplicates']}\n"
        f"  - geometric duplicates/variants: {combined_stats['geometric_duplicates']}\n"
        f"  - valid models: {combined_stats['valid_models']}\n"
        f"  - invalid models: {combined_stats['invalid_models']}\n"
        f"  - models successfully rendered: {combined_stats['rendered']}\n"
        f"  - models needing review: {combined_stats['needs_review']}\n"
        "------------------------------------------------------------\n"
        f"Blender detected: {'YES' if blender_detected else 'NO'}\n"
        f"Blender version: {blender_version}\n"
        f"Supported formats discovered: {', '.join(sorted(discovered_formats))}\n"
        "============================================================\n"
    )

    with open(os.path.join(output_dir, "summary.txt"), 'w', encoding='utf-8') as f:
        f.write(report_text)

    print(report_text)

    # Calculate Gap Report Metrics
    PROJECT_ROOT = r"c:\Users\Admin\Documents\mad2"
    total_needing_review = total_invalid + category_counts["Needs Review"]["needs_review"]

    gap_data = []
    gap_categories = [
        "Living Room", "Bedroom", "Dining", "Kitchen", "Office", 
        "Bathroom", "Lighting", "Decor", "Plants", "Outdoor", 
        "Architectural", "Other", "Needs Review"
    ]
    
    for cat in gap_categories:
        counts = category_counts.get(cat, {"usable": 0, "duplicates": 0, "needs_review": 0})
        target = category_targets.get(cat, 0)
        usable = counts["usable"]
        dups = counts["duplicates"]
        nr = counts["needs_review"]
        
        if cat == "Needs Review":
            nr = counts["needs_review"] + total_invalid
            usable = 0
            
        additional = max(0, target - usable)
        
        gap_data.append({
            "category": cat,
            "existing_usable": usable,
            "duplicates": dups,
            "needs_review": nr,
            "target": target,
            "additional_assets_required": additional
        })

    summary_stats = {
        "total_discovered": total_discovered,
        "total_unique": total_unique,
        "total_valid": total_valid,
        "total_valid_glb": total_valid_glb,
        "total_convertible_to_glb": total_convertible_to_glb,
        "total_duplicates": total_duplicates,
        "total_invalid": total_invalid,
        "total_needing_review": total_needing_review
    }

    gap_report_json = {
        "categories": gap_data,
        "summary": summary_stats
    }
    
    # Save Gap Reports to project root
    # JSON
    json_path = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Gap_Report.json")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(gap_report_json, f, indent=2)
    print(f"[OK] Generated {json_path}")
    
    # CSV
    csv_path = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Gap_Report.csv")
    with open(csv_path, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["Category", "Existing usable", "Duplicates", "Needs review", "Target", "Additional assets required"])
        for row in gap_data:
            writer.writerow([
                row["category"],
                row["existing_usable"],
                row["duplicates"],
                row["needs_review"],
                row["target"],
                row["additional_assets_required"]
            ])
    print(f"[OK] Generated {csv_path}")

    # TXT
    txt_path = os.path.join(PROJECT_ROOT, "FlowSpace_Asset_Gap_Report.txt")
    with open(txt_path, 'w', encoding='utf-8') as f:
        f.write("=========================================================================================\n")
        f.write("                                FLOWSPACE ASSET GAP REPORT                               \n")
        f.write("=========================================================================================\n\n")
        
        f.write(f"{'Category':<20} | {'Existing Usable':<15} | {'Duplicates':<10} | {'Needs Review':<12} | {'Target':<6} | {'Additional Required':<20}\n")
        f.write("-" * 97 + "\n")
        for row in gap_data:
            f.write(f"{row['category']:<20} | {row['existing_usable']:<15} | {row['duplicates']:<10} | {row['needs_review']:<12} | {row['target']:<6} | {row['additional_assets_required']:<20}\n")
        
        f.write("\n" + "=" * 75 + "\n")
        f.write("METRIC SUMMARY\n")
        f.write("=" * 75 + "\n")
        f.write(f"- Total discovered:           {summary_stats['total_discovered']}\n")
        f.write(f"- Total unique:               {summary_stats['total_unique']}\n")
        f.write(f"- Total valid:                {summary_stats['total_valid']}\n")
        f.write(f"- Total valid GLB:            {summary_stats['total_valid_glb']}\n")
        f.write(f"- Total convertible to GLB:   {summary_stats['total_convertible_to_glb']}\n")
        f.write(f"- Total duplicates:           {summary_stats['total_duplicates']}\n")
        f.write(f"- Total invalid:              {summary_stats['total_invalid']}\n")
        f.write(f"- Total needing review:       {summary_stats['total_needing_review']}\n")
        f.write("=========================================================================================\n")
    print(f"[OK] Generated {txt_path}")

    # Cleanup temp extraction directory
    try:
        shutil.rmtree(temp_working_dir)
    except Exception:
        pass

if __name__ == '__main__':
    main()
