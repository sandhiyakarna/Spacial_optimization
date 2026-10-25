import json
import struct
import os
import math

# Material presets definition: (baseColorFactor, roughnessFactor, metallicFactor)
MATERIAL_PRESETS = {
    "wood_walnut": ([0.28, 0.18, 0.12, 1.0], 0.45, 0.05),
    "wood_oak": ([0.72, 0.54, 0.35, 1.0], 0.50, 0.05),
    "wood_light": ([0.88, 0.78, 0.65, 1.0], 0.55, 0.05),
    "leather_black": ([0.12, 0.13, 0.15, 1.0], 0.55, 0.15),
    "leather_brown": ([0.38, 0.22, 0.14, 1.0], 0.50, 0.15),
    "mesh_charcoal": ([0.22, 0.24, 0.26, 1.0], 0.75, 0.05),
    "metal_chrome": ([0.88, 0.90, 0.92, 1.0], 0.20, 0.90),
    "metal_dark": ([0.18, 0.18, 0.20, 1.0], 0.35, 0.75),
    "metal_brass": ([0.84, 0.70, 0.32, 1.0], 0.28, 0.85),
    "fabric_cushion": ([0.32, 0.42, 0.54, 1.0], 0.85, 0.02),
    "fabric_cream": ([0.92, 0.90, 0.84, 1.0], 0.90, 0.02),
    "accent_navy": ([0.15, 0.24, 0.40, 1.0], 0.60, 0.05),
    "accent_terracotta": ([0.75, 0.35, 0.24, 1.0], 0.60, 0.05),
    "accent_teal": ([0.14, 0.48, 0.52, 1.0], 0.60, 0.05),
    "accent_gold": ([0.85, 0.72, 0.25, 1.0], 0.30, 0.80),
    "plant_leaf": ([0.18, 0.52, 0.24, 1.0], 0.60, 0.05),
    "plant_pot": ([0.88, 0.86, 0.82, 1.0], 0.35, 0.10),
    "soil_dark": ([0.15, 0.12, 0.10, 1.0], 0.95, 0.00),
    "glass_frosted": ([0.85, 0.92, 0.98, 1.0], 0.15, 0.10),
    "screen_black": ([0.05, 0.05, 0.06, 1.0], 0.15, 0.40),
}

def create_box_mesh(cx, cy, cz, w, h, d):
    hw, hh, hd = w / 2.0, h / 2.0, d / 2.0
    faces = [
        # +Z face (front)
        ([(cx-hw, cy-hh, cz+hd), (cx+hw, cy-hh, cz+hd), (cx+hw, cy+hh, cz+hd), (cx-hw, cy+hh, cz+hd)], (0, 0, 1)),
        # -Z face (back)
        ([(cx+hw, cy-hh, cz-hd), (cx-hw, cy-hh, cz-hd), (cx-hw, cy+hh, cz-hd), (cx+hw, cy+hh, cz-hd)], (0, 0, -1)),
        # +X face (right)
        ([(cx+hw, cy-hh, cz+hd), (cx+hw, cy-hh, cz-hd), (cx+hw, cy+hh, cz-hd), (cx+hw, cy+hh, cz+hd)], (1, 0, 0)),
        # -X face (left)
        ([(cx-hw, cy-hh, cz-hd), (cx-hw, cy-hh, cz+hd), (cx-hw, cy+hh, cz+hd), (cx-hw, cy+hh, cz-hd)], (-1, 0, 0)),
        # +Y face (top)
        ([(cx-hw, cy+hh, cz+hd), (cx+hw, cy+hh, cz+hd), (cx+hw, cy+hh, cz-hd), (cx-hw, cy+hh, cz-hd)], (0, 1, 0)),
        # -Y face (bottom)
        ([(cx-hw, cy-hh, cz-hd), (cx+hw, cy-hh, cz-hd), (cx+hw, cy-hh, cz+hd), (cx-hw, cy-hh, cz+hd)], (0, -1, 0)),
    ]

    positions = []
    normals = []
    uvs = []
    indices = []
    uv_coords = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]

    idx_offset = 0
    for quad, norm in faces:
        for i, pos in enumerate(quad):
            positions.extend(pos)
            normals.extend(norm)
            uvs.extend(uv_coords[i])
        indices.extend([idx_offset, idx_offset + 1, idx_offset + 2, idx_offset, idx_offset + 2, idx_offset + 3])
        idx_offset += 4

    return positions, normals, uvs, indices

def create_cylinder_mesh(cx, cy, cz, radius, height, radial_segments=16):
    """Generates a vertical cylinder mesh."""
    hr = radius
    hh = height / 2.0
    positions = []
    normals = []
    uvs = []
    indices = []

    # Side quads
    for i in range(radial_segments):
        theta1 = (i / radial_segments) * 2 * math.pi
        theta2 = ((i + 1) / radial_segments) * 2 * math.pi
        
        c1, s1 = math.cos(theta1), math.sin(theta1)
        c2, s2 = math.cos(theta2), math.sin(theta2)

        x1, z1 = cx + hr * c1, cz + hr * s1
        x2, z2 = cx + hr * c2, cz + hr * s2

        base_idx = len(positions) // 3

        # 4 vertices for side quad
        p1 = (x1, cy - hh, z1)
        p2 = (x2, cy - hh, z2)
        p3 = (x2, cy + hh, z2)
        p4 = (x1, cy + hh, z1)

        positions.extend(p1 + p2 + p3 + p4)
        normals.extend([c1, 0, s1, c2, 0, s2, c2, 0, s2, c1, 0, s1])
        uvs.extend([i/radial_segments, 0.0, (i+1)/radial_segments, 0.0, (i+1)/radial_segments, 1.0, i/radial_segments, 1.0])
        indices.extend([base_idx, base_idx + 1, base_idx + 2, base_idx, base_idx + 2, base_idx + 3])

    # Top Cap
    top_center_idx = len(positions) // 3
    positions.extend([cx, cy + hh, cz])
    normals.extend([0, 1, 0])
    uvs.extend([0.5, 0.5])

    for i in range(radial_segments):
        theta1 = (i / radial_segments) * 2 * math.pi
        c1, s1 = math.cos(theta1), math.sin(theta1)
        positions.extend([cx + hr * c1, cy + hh, cz + hr * s1])
        normals.extend([0, 1, 0])
        uvs.extend([0.5 + 0.5 * c1, 0.5 + 0.5 * s1])

    for i in range(radial_segments):
        next_i = (i + 1) % radial_segments
        indices.extend([top_center_idx, top_center_idx + 1 + i, top_center_idx + 1 + next_i])

    # Bottom Cap
    bot_center_idx = len(positions) // 3
    positions.extend([cx, cy - hh, cz])
    normals.extend([0, -1, 0])
    uvs.extend([0.5, 0.5])

    for i in range(radial_segments):
        theta1 = (i / radial_segments) * 2 * math.pi
        c1, s1 = math.cos(theta1), math.sin(theta1)
        positions.extend([cx + hr * c1, cy - hh, cz + hr * s1])
        normals.extend([0, -1, 0])
        uvs.extend([0.5 + 0.5 * c1, 0.5 + 0.5 * s1])

    for i in range(radial_segments):
        next_i = (i + 1) % radial_segments
        indices.extend([bot_center_idx, bot_center_idx + 1 + next_i, bot_center_idx + 1 + i])

    return positions, normals, uvs, indices

def generate_glb_binary(boxes, color=(0.7, 0.6, 0.5, 1.0)):
    """Legacy helper for backward compatibility."""
    parts = [('box', cx, cy, cz, w, h, d) for (cx, cy, cz, w, h, d) in boxes]
    return build_multi_material_glb({"default": parts})

def build_multi_material_glb(parts_by_material):
    """
    parts_by_material: dict mapping material_key to list of box/cylinder definitions:
      - ('box', cx, cy, cz, w, h, d)
      - ('cyl', cx, cy, cz, radius, height)
    """
    all_bin_chunks = []
    gltf_materials = []
    gltf_primitives = []
    gltf_accessors = []
    gltf_buffer_views = []

    current_bin_offset = 0

    material_index_map = {}
    for mat_key in parts_by_material.keys():
        if mat_key not in material_index_map:
            mat_idx = len(gltf_materials)
            material_index_map[mat_key] = mat_idx
            base_col, rough, metal = MATERIAL_PRESETS.get(mat_key, ([0.6, 0.6, 0.6, 1.0], 0.5, 0.1))
            gltf_materials.append({
                "name": mat_key,
                "pbrMetallicRoughness": {
                    "baseColorFactor": base_col,
                    "roughnessFactor": rough,
                    "metallicFactor": metal
                }
            })

    accessor_idx_counter = 0

    for mat_key, parts in parts_by_material.items():
        mat_idx = material_index_map[mat_key]
        pos_list = []
        norm_list = []
        uv_list = []
        ind_list = []

        vertex_offset = 0
        for p in parts:
            p_type = p[0]
            if p_type == 'box':
                _, cx, cy, cz, w, h, d = p
                pos, norm, uv, ind = create_box_mesh(cx, cy, cz, w, h, d)
            elif p_type == 'cyl':
                _, cx, cy, cz, r, h = p
                pos, norm, uv, ind = create_cylinder_mesh(cx, cy, cz, r, h)
            else:
                continue

            pos_list.extend(pos)
            norm_list.extend(norm)
            uv_list.extend(uv)
            for i in ind:
                ind_list.append(i + vertex_offset)
            vertex_offset += len(pos) // 3

        if not pos_list or not ind_list:
            continue

        n_verts = len(pos_list) // 3
        n_inds = len(ind_list)

        min_x, max_x = min(pos_list[0::3]), max(pos_list[0::3])
        min_y, max_y = min(pos_list[1::3]), max(pos_list[1::3])
        min_z, max_z = min(pos_list[2::3]), max(pos_list[2::3])

        pos_b = struct.pack(f"<{len(pos_list)}f", *pos_list)
        norm_b = struct.pack(f"<{len(norm_list)}f", *norm_list)
        uv_b = struct.pack(f"<{len(uv_list)}f", *uv_list)
        ind_b = struct.pack(f"<{len(ind_list)}H", *ind_list)

        def pad4(b):
            rem = len(b) % 4
            return b if rem == 0 else b + (b"\x00" * (4 - rem))

        pos_b = pad4(pos_b)
        norm_b = pad4(norm_b)
        uv_b = pad4(uv_b)
        ind_b = pad4(ind_b)

        # Buffer Views for this primitive
        bv_pos = len(gltf_buffer_views)
        gltf_buffer_views.append({"buffer": 0, "byteOffset": current_bin_offset, "byteLength": len(pos_b), "target": 34962})
        current_bin_offset += len(pos_b)
        all_bin_chunks.append(pos_b)

        bv_norm = len(gltf_buffer_views)
        gltf_buffer_views.append({"buffer": 0, "byteOffset": current_bin_offset, "byteLength": len(norm_b), "target": 34962})
        current_bin_offset += len(norm_b)
        all_bin_chunks.append(norm_b)

        bv_uv = len(gltf_buffer_views)
        gltf_buffer_views.append({"buffer": 0, "byteOffset": current_bin_offset, "byteLength": len(uv_b), "target": 34962})
        current_bin_offset += len(uv_b)
        all_bin_chunks.append(uv_b)

        bv_ind = len(gltf_buffer_views)
        gltf_buffer_views.append({"buffer": 0, "byteOffset": current_bin_offset, "byteLength": len(ind_b), "target": 34963})
        current_bin_offset += len(ind_b)
        all_bin_chunks.append(ind_b)

        # Accessors
        acc_pos = accessor_idx_counter
        gltf_accessors.append({
            "bufferView": bv_pos, "byteOffset": 0, "componentType": 5126,
            "count": n_verts, "type": "VEC3",
            "min": [min_x, min_y, min_z], "max": [max_x, max_y, max_z]
        })
        acc_norm = accessor_idx_counter + 1
        gltf_accessors.append({
            "bufferView": bv_norm, "byteOffset": 0, "componentType": 5126,
            "count": n_verts, "type": "VEC3"
        })
        acc_uv = accessor_idx_counter + 2
        gltf_accessors.append({
            "bufferView": bv_uv, "byteOffset": 0, "componentType": 5126,
            "count": n_verts, "type": "VEC2"
        })
        acc_ind = accessor_idx_counter + 3
        gltf_accessors.append({
            "bufferView": bv_ind, "byteOffset": 0, "componentType": 5123,
            "count": n_inds, "type": "SCALAR"
        })
        accessor_idx_counter += 4

        gltf_primitives.append({
            "attributes": {
                "POSITION": acc_pos,
                "NORMAL": acc_norm,
                "TEXCOORD_0": acc_uv
            },
            "indices": acc_ind,
            "material": mat_idx
        })

    bin_data = b"".join(all_bin_chunks)

    gltf_dict = {
        "asset": {"version": "2.0", "generator": "FlowSpace GLB Engine v2.0"},
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "FurnitureRoot"}],
        "meshes": [{"name": "FurnitureMesh", "primitives": gltf_primitives}],
        "materials": gltf_materials,
        "accessors": gltf_accessors,
        "bufferViews": gltf_buffer_views,
        "buffers": [{"byteLength": len(bin_data)}]
    }

    json_text = json.dumps(gltf_dict, indent=None).encode("utf-8")
    rem_json = len(json_text) % 4
    if rem_json != 0:
        json_text += b" " * (4 - rem_json)

    json_chunk_header = struct.pack("<I4s", len(json_text), b"JSON")
    bin_chunk_header = struct.pack("<I4s", len(bin_data), b"BIN\x00")

    total_file_len = 12 + 8 + len(json_text) + 8 + len(bin_data)
    glb_header = struct.pack("<4sII", b"glTF", 2, total_file_len)

    return glb_header + json_chunk_header + json_text + bin_chunk_header + bin_data


# =========================================================================
# RICH HIGH-FIDELITY CATALOG MODELS DEFINITIONS
# =========================================================================
DETAILED_FURNITURE = {
    # 1. Executive Manager Desk (180 x 90 x 76 cm)
    "EXEC_DESK001": {
        "wood_walnut": [
            # Main Desk Top Slab with beveled edge
            ('box', 0.0, 73.0, 0.0, 180.0, 6.0, 90.0),
            # Left Pedestal Body (3 drawers)
            ('box', -66.0, 36.0, 0.0, 38.0, 68.0, 80.0),
            # Right Pedestal Body (3 drawers)
            ('box', 66.0, 36.0, 0.0, 38.0, 68.0, 80.0),
            # Modesty panel between pedestals
            ('box', 0.0, 48.0, -32.0, 94.0, 44.0, 3.0),
            # Base Plinth Left & Right
            ('box', -66.0, 1.5, 0.0, 39.0, 3.0, 81.0),
            ('box', 66.0, 1.5, 0.0, 39.0, 3.0, 81.0),
        ],
        "leather_black": [
            # Executive Inset Leather Writing Blotter
            ('box', 0.0, 76.2, 5.0, 90.0, 0.5, 52.0),
        ],
        "metal_brass": [
            # 3 Left Drawer Handles
            ('box', -66.0, 60.0, 41.0, 14.0, 2.0, 2.5),
            ('box', -66.0, 42.0, 41.0, 14.0, 2.0, 2.5),
            ('box', -66.0, 24.0, 41.0, 14.0, 2.0, 2.5),
            # 3 Right Drawer Handles
            ('box', 66.0, 60.0, 41.0, 14.0, 2.0, 2.5),
            ('box', 66.0, 42.0, 41.0, 14.0, 2.0, 2.5),
            ('box', 66.0, 24.0, 41.0, 14.0, 2.0, 2.5),
            # Cable Grommet Ring on Top
            ('cyl', 65.0, 76.2, -30.0, 3.5, 0.6),
        ]
    },

    # 2. Ergonomic Manager Chair (70 x 70 x 110 cm)
    "EXEC_CHAIR001": {
        "leather_black": [
            # Contoured Seat Cushion
            ('box', 0.0, 46.0, 2.0, 56.0, 10.0, 54.0),
            # Ergonomic High Lumbar Backrest
            ('box', 0.0, 82.0, -22.0, 52.0, 66.0, 8.0),
            # Upholstered Headrest
            ('box', 0.0, 118.0, -22.0, 36.0, 16.0, 9.0),
            # Left Padded Armrest Top
            ('box', -26.0, 68.0, 0.0, 8.0, 3.0, 32.0),
            # Right Padded Armrest Top
            ('box', 26.0, 68.0, 0.0, 8.0, 3.0, 32.0),
        ],
        "metal_chrome": [
            # Pneumatic Lift Column
            ('cyl', 0.0, 22.0, 0.0, 3.2, 34.0),
            # 5-Star Swivel Base (5 tubular prongs)
            ('box', 0.0, 6.0, 0.0, 62.0, 3.5, 8.0),
            ('box', 0.0, 6.0, 0.0, 8.0, 3.5, 62.0),
            # Armrest Upright Posts (Left & Right)
            ('box', -26.0, 54.0, -5.0, 3.0, 26.0, 4.0),
            ('box', 26.0, 54.0, -5.0, 3.0, 26.0, 4.0),
            # Backrest Metal Spine
            ('box', 0.0, 68.0, -26.5, 6.0, 50.0, 3.0),
        ],
        "metal_dark": [
            # 5 Floor Castor Wheels
            ('cyl', -28.0, 3.0, 0.0, 3.0, 3.0),
            ('cyl', 28.0, 3.0, 0.0, 3.0, 3.0),
            ('cyl', 0.0, 3.0, -28.0, 3.0, 3.0),
            ('cyl', 0.0, 3.0, 28.0, 3.0, 3.0),
        ]
    },

    # 3. Standard Ergonomic Office Task Chair (65 x 65 x 102 cm)
    "CHAIR001": {
        "mesh_charcoal": [
            # Ergonomic Breathable Curved Mesh Back
            ('box', 0.0, 78.0, -18.0, 48.0, 54.0, 5.0),
        ],
        "fabric_cushion": [
            # Waterfall Foam Seat Cushion
            ('box', 0.0, 44.0, 2.0, 50.0, 8.0, 48.0),
            # Armrest Pads
            ('box', -23.0, 64.0, 0.0, 6.0, 2.5, 26.0),
            ('box', 23.0, 64.0, 0.0, 6.0, 2.5, 26.0),
        ],
        "metal_dark": [
            # Chair Base Central Column & Mechanism
            ('cyl', 0.0, 22.0, 0.0, 3.0, 32.0),
            ('box', 0.0, 39.0, 0.0, 24.0, 4.0, 24.0),
            # Star Base Legs
            ('box', 0.0, 5.0, 0.0, 56.0, 3.0, 6.0),
            ('box', 0.0, 5.0, 0.0, 6.0, 3.0, 56.0),
            # Arm Supports
            ('box', -23.0, 52.0, -3.0, 2.5, 22.0, 3.0),
            ('box', 23.0, 52.0, -3.0, 2.5, 22.0, 3.0),
            # 4 Wheels
            ('cyl', -25.0, 2.5, 0.0, 2.5, 2.5),
            ('cyl', 25.0, 2.5, 0.0, 2.5, 2.5),
            ('cyl', 0.0, 2.5, -25.0, 2.5, 2.5),
            ('cyl', 0.0, 2.5, 25.0, 2.5, 2.5),
        ]
    },

    # 4. Executive Visitor / Guest Chair (60 x 60 x 85 cm)
    "VISITOR_CHAIR001": {
        "fabric_cushion": [
            # Upholstered Seat Cushion
            ('box', 0.0, 43.0, 2.0, 48.0, 7.0, 46.0),
            # Mid-back Lumbar Cushion
            ('box', 0.0, 70.0, -18.0, 46.0, 44.0, 6.0),
        ],
        "metal_chrome": [
            # Sleek Cantilever S-frame / 4 tubular legs
            ('box', -22.0, 20.0, -16.0, 3.0, 40.0, 3.0),
            ('box', 22.0, 20.0, -16.0, 3.0, 40.0, 3.0),
            ('box', -22.0, 20.0, 16.0, 3.0, 40.0, 3.0),
            ('box', 22.0, 20.0, 16.0, 3.0, 40.0, 3.0),
            # Bottom Connecting Sled Glides
            ('box', -22.0, 1.5, 0.0, 3.0, 3.0, 36.0),
            ('box', 22.0, 1.5, 0.0, 3.0, 3.0, 36.0),
            # Armrest loop tubes
            ('box', -23.0, 60.0, 0.0, 3.0, 3.0, 32.0),
            ('box', 23.0, 60.0, 0.0, 3.0, 3.0, 32.0),
        ]
    },

    # 5. Executive Bookshelf Unit (100 x 40 x 180 cm)
    "BOOKSHELF001": {
        "wood_walnut": [
            # Left & Right Outer Side Gables
            ('box', -47.5, 90.0, 0.0, 5.0, 180.0, 40.0),
            ('box', 47.5, 90.0, 0.0, 5.0, 180.0, 40.0),
            # Top Crown Molding Slab
            ('box', 0.0, 178.0, 0.0, 100.0, 4.0, 41.0),
            # Bottom Plinth Base Slab
            ('box', 0.0, 4.0, 0.0, 100.0, 8.0, 41.0),
            # Back Wall Panel
            ('box', 0.0, 90.0, -18.5, 90.0, 170.0, 2.0),
            # 4 Internal Horizontal Shelves
            ('box', 0.0, 42.0, 0.0, 90.0, 3.5, 37.0),
            ('box', 0.0, 82.0, 0.0, 90.0, 3.5, 37.0),
            ('box', 0.0, 122.0, 0.0, 90.0, 3.5, 37.0),
            ('box', 0.0, 162.0, 0.0, 90.0, 3.5, 37.0),
        ],
        "accent_navy": [
            # Stylized Book Series on Middle Shelf
            ('box', -30.0, 94.0, 0.0, 14.0, 20.0, 22.0),
            ('box', 15.0, 54.0, 0.0, 18.0, 20.0, 22.0),
        ],
        "accent_terracotta": [
            # Terracotta Architectural Book Set
            ('box', -14.0, 94.0, 0.0, 12.0, 21.0, 22.0),
            ('box', -32.0, 134.0, 0.0, 16.0, 20.0, 22.0),
        ],
        "accent_teal": [
            # Teal Volumes
            ('box', 30.0, 94.0, 0.0, 14.0, 20.0, 22.0),
            ('box', -12.0, 54.0, 0.0, 16.0, 19.0, 22.0),
        ],
        "accent_gold": [
            # Decorative Sculpture Accent on Top Shelf
            ('box', 26.0, 133.0, 0.0, 10.0, 18.0, 10.0),
            ('cyl', -2.0, 131.0, 0.0, 5.0, 14.0),
        ]
    },

    # 6. Executive Storage Cabinet / Credenza (100 x 50 x 120 cm)
    "OFFICE_CABINET001": {
        "wood_walnut": [
            # Top Beveled Surface Slab
            ('box', 0.0, 118.0, 0.0, 102.0, 4.0, 52.0),
            # Main Outer Body (Carcase)
            ('box', 0.0, 59.0, 0.0, 100.0, 114.0, 48.0),
            # Recessed Base Plinth
            ('box', 0.0, 4.0, 0.0, 96.0, 8.0, 44.0),
            # Left Door Panel with recessed detail
            ('box', -24.0, 60.0, 25.5, 46.0, 104.0, 2.5),
            # Right Door Panel with recessed detail
            ('box', 24.0, 60.0, 25.5, 46.0, 104.0, 2.5),
        ],
        "metal_brass": [
            # Long Modern Vertical Bar Handles (Left & Right)
            ('box', -4.0, 64.0, 28.5, 2.0, 30.0, 3.0),
            ('box', 4.0, 64.0, 28.5, 2.0, 30.0, 3.0),
            # Subtle Metallic Plinth Trim Line
            ('box', 0.0, 8.5, 23.0, 96.0, 1.0, 2.0),
        ]
    },

    # 7. Industrial Study Desk (120 x 60 x 76 cm)
    "DESK001": {
        "wood_oak": [
            # Thick Solid Oak Tabletop
            ('box', 0.0, 73.0, 0.0, 120.0, 6.0, 60.0),
            # Right Drawer Unit (2 drawers)
            ('box', 38.0, 42.0, 0.0, 36.0, 56.0, 54.0),
        ],
        "metal_dark": [
            # Left Loop Leg Frame (black steel)
            ('box', -54.0, 35.0, -25.0, 5.0, 70.0, 5.0),
            ('box', -54.0, 35.0, 25.0, 5.0, 70.0, 5.0),
            ('box', -54.0, 2.5, 0.0, 5.0, 5.0, 55.0),
            ('box', -54.0, 68.0, 0.0, 5.0, 5.0, 55.0),
            # Right Support Post
            ('box', 54.0, 35.0, 0.0, 4.0, 70.0, 50.0),
            # Cross Stretcher Bar
            ('box', 0.0, 20.0, -24.0, 104.0, 3.0, 3.0),
        ],
        "metal_chrome": [
            # 2 Cutout Drawer Pull Handles
            ('box', 38.0, 56.0, 28.0, 12.0, 2.0, 2.0),
            ('box', 38.0, 30.0, 28.0, 12.0, 2.0, 2.0),
        ]
    },

    # 8. Modern 3-Seater Sofa (210 x 90 x 85 cm)
    "SOFA001": {
        "fabric_cushion": [
            # Deep Base Seat Platform
            ('box', 0.0, 24.0, 2.0, 210.0, 24.0, 86.0),
            # Left Seat Cushion
            ('box', -52.0, 42.0, 6.0, 98.0, 14.0, 76.0),
            # Right Seat Cushion
            ('box', 52.0, 42.0, 6.0, 98.0, 14.0, 76.0),
            # Left Backrest Pillow
            ('box', -52.0, 68.0, -28.0, 98.0, 38.0, 20.0),
            # Right Backrest Pillow
            ('box', 52.0, 68.0, -28.0, 98.0, 38.0, 20.0),
            # Left Armrest Bolster
            ('box', -100.0, 52.0, 4.0, 18.0, 34.0, 88.0),
            # Right Armrest Bolster
            ('box', 100.0, 52.0, 4.0, 18.0, 34.0, 88.0),
        ],
        "wood_walnut": [
            # 4 Tapered Scandinavian Wooden Legs
            ('cyl', -95.0, 6.0, -36.0, 3.0, 12.0),
            ('cyl', 95.0, 6.0, -36.0, 3.0, 12.0),
            ('cyl', -95.0, 6.0, 36.0, 3.0, 12.0),
            ('cyl', 95.0, 6.0, 36.0, 3.0, 12.0),
        ]
    },

    # 9. Scandinavian Dining Table (160 x 90 x 75 cm)
    "TABLE001": {
        "wood_oak": [
            # Solid Oak Tabletop with beveled edge
            ('box', 0.0, 72.0, 0.0, 160.0, 5.5, 90.0),
            # Under-top Apron Frame
            ('box', 0.0, 66.0, -38.0, 146.0, 6.0, 4.0),
            ('box', 0.0, 66.0, 38.0, 146.0, 6.0, 4.0),
            ('box', -72.0, 66.0, 0.0, 4.0, 6.0, 76.0),
            ('box', 72.0, 66.0, 0.0, 4.0, 6.0, 76.0),
            # 4 Tapered Sturdy Legs
            ('box', -72.0, 34.0, -37.0, 7.0, 68.0, 7.0),
            ('box', 72.0, 34.0, -37.0, 7.0, 68.0, 7.0),
            ('box', -72.0, 34.0, 37.0, 7.0, 68.0, 7.0),
            ('box', 72.0, 34.0, 37.0, 7.0, 68.0, 7.0),
        ]
    },

    # 10. Modern Coffee Table (100 x 60 x 45 cm)
    "COFFEE001": {
        "wood_oak": [
            # Beveled Table Top
            ('box', 0.0, 42.0, 0.0, 100.0, 4.5, 60.0),
            # Lower Magazine / Storage Shelf
            ('box', 0.0, 16.0, 0.0, 88.0, 2.5, 48.0),
        ],
        "metal_dark": [
            # 4 Angled Steel Hairpin / Tubular Legs
            ('cyl', -44.0, 20.0, -24.0, 1.8, 40.0),
            ('cyl', 44.0, 20.0, -24.0, 1.8, 40.0),
            ('cyl', -44.0, 20.0, 24.0, 1.8, 40.0),
            ('cyl', 44.0, 20.0, 24.0, 1.8, 40.0),
        ]
    },

    # 11. Minimalist King Bed (200 x 220 x 45 cm)
    "BED001": {
        "wood_oak": [
            # Solid Wood Perimeter Platform Bed Frame
            ('box', 0.0, 12.0, 0.0, 200.0, 24.0, 220.0),
            # Headboard Wall Panel
            ('box', 0.0, 58.0, -106.0, 200.0, 92.0, 8.0),
        ],
        "fabric_cream": [
            # Plush Tufted Mattress
            ('box', 0.0, 32.0, 6.0, 186.0, 24.0, 200.0),
            # Left Fluffy Sleeping Pillow
            ('box', -48.0, 47.0, -78.0, 64.0, 10.0, 36.0),
            # Right Fluffy Sleeping Pillow
            ('box', 48.0, 47.0, -78.0, 64.0, 10.0, 36.0),
        ],
        "accent_navy": [
            # Decorative End-of-Bed Throw Blanket
            ('box', 0.0, 45.0, 75.0, 188.0, 3.0, 50.0),
        ]
    },

    # 12. Minimalist Nightstand (50 x 40 x 55 cm)
    "STAND001": {
        "wood_oak": [
            # Main Box Body (Drawer & open cubby)
            ('box', 0.0, 34.0, 0.0, 50.0, 36.0, 40.0),
            # Drawer Front Panel
            ('box', 0.0, 42.0, 20.5, 46.0, 16.0, 2.0),
        ],
        "metal_dark": [
            # 4 Splayed Legs
            ('cyl', -20.0, 8.0, -15.0, 1.6, 16.0),
            ('cyl', 20.0, 8.0, -15.0, 1.6, 16.0),
            ('cyl', -20.0, 8.0, 15.0, 1.6, 16.0),
            ('cyl', 20.0, 8.0, 15.0, 1.6, 16.0),
        ],
        "metal_brass": [
            # Round Brass Knob
            ('cyl', 0.0, 42.0, 22.0, 1.2, 2.0),
        ]
    },

    # 13. Minimalist Wardrobe (100 x 60 x 180 cm)
    "WARDROBE001": {
        "wood_oak": [
            # Wardrobe Main Carcase
            ('box', 0.0, 90.0, 0.0, 100.0, 180.0, 60.0),
            # Left Full-Height Door
            ('box', -24.5, 90.0, 30.5, 47.0, 172.0, 2.0),
            # Right Full-Height Door
            ('box', 24.5, 90.0, 30.5, 47.0, 172.0, 2.0),
        ],
        "metal_brass": [
            # Elegant Long Vertical Handles
            ('box', -4.0, 90.0, 33.0, 1.5, 36.0, 2.0),
            ('box', 4.0, 90.0, 33.0, 1.5, 36.0, 2.0),
        ]
    },

    # 14. Modern Floor Lamp (40 x 40 x 160 cm)
    "LIGHT_001": {
        "metal_brass": [
            # Heavy Weighted Disc Base
            ('cyl', 0.0, 2.0, 0.0, 16.0, 4.0),
            # Tall Slender Brass Pole Column
            ('cyl', 0.0, 78.0, 0.0, 1.6, 152.0),
            # Shade Support Finial
            ('cyl', 0.0, 152.0, 0.0, 2.2, 8.0),
        ],
        "fabric_cream": [
            # Drum Fabric Lampshade
            ('cyl', 0.0, 136.0, 0.0, 18.0, 28.0),
        ]
    },

    # 15. Modern Indoor Plant in Planter (35 x 35 x 85 cm)
    "PLANT_001": {
        "plant_pot": [
            # Ceramic Geometric Pot
            ('cyl', 0.0, 20.0, 0.0, 16.0, 40.0),
            ('box', 0.0, 4.0, 0.0, 22.0, 8.0, 22.0),
        ],
        "soil_dark": [
            # Top Soil Disk
            ('cyl', 0.0, 39.0, 0.0, 15.0, 2.0),
        ],
        "plant_leaf": [
            # Central Stems & Layered Broad Leaves
            ('box', 0.0, 56.0, 0.0, 28.0, 34.0, 28.0),
            ('box', 0.0, 72.0, 0.0, 22.0, 26.0, 22.0),
            ('box', -10.0, 62.0, 8.0, 18.0, 24.0, 18.0),
            ('box', 10.0, 62.0, -8.0, 18.0, 24.0, 18.0),
        ]
    },

    # 16. TV Console & Flat Panel (150 x 40 x 120 cm)
    "TV001": {
        "wood_walnut": [
            # TV Console Credenza Body
            ('box', 0.0, 25.0, 0.0, 150.0, 50.0, 40.0),
            # Left Door & Center Open Shelf Frame
            ('box', -48.0, 25.0, 20.5, 48.0, 46.0, 2.0),
            ('box', 48.0, 25.0, 20.5, 48.0, 46.0, 2.0),
        ],
        "screen_black": [
            # TV Screen Bezel & Panel
            ('box', 0.0, 86.0, 0.0, 126.0, 68.0, 4.0),
        ],
        "metal_dark": [
            # TV Central Stand Neck & Pedestal
            ('box', 0.0, 51.0, 0.0, 38.0, 4.0, 24.0),
            ('box', 0.0, 58.0, 0.0, 10.0, 12.0, 6.0),
        ]
    },

    # 17. Storage Cabinet (100 x 50 x 190 cm)
    "CABINET001": {
        "wood_walnut": [
            # Tall Cabinet Body
            ('box', 0.0, 95.0, 0.0, 100.0, 190.0, 50.0),
            # Upper Left Door
            ('box', -24.0, 138.0, 25.5, 46.0, 94.0, 2.0),
            # Upper Right Door
            ('box', 24.0, 138.0, 25.5, 46.0, 94.0, 2.0),
            # Lower Left Door
            ('box', -24.0, 46.0, 25.5, 46.0, 80.0, 2.0),
            # Lower Right Door
            ('box', 24.0, 46.0, 25.5, 46.0, 80.0, 2.0),
        ],
        "metal_brass": [
            # 4 Bar Handles
            ('box', -4.0, 138.0, 27.5, 2.0, 25.0, 2.0),
            ('box', 4.0, 138.0, 27.5, 2.0, 25.0, 2.0),
            ('box', -4.0, 46.0, 27.5, 2.0, 25.0, 2.0),
            ('box', 4.0, 46.0, 27.5, 2.0, 25.0, 2.0),
        ]
    },

    # 18. Kitchen Counter (180 x 60 x 90 cm)
    "KITCHEN_COUNTER001": {
        "wood_oak": [
            # Counter Cabinet Base Body
            ('box', 0.0, 43.0, 0.0, 180.0, 86.0, 60.0),
        ],
        "plant_pot": [
            # Clean White Marble Countertop Slab
            ('box', 0.0, 88.0, 0.0, 182.0, 4.0, 62.0),
        ],
        "metal_chrome": [
            # Handles for 3 Counter Drawers & 2 Doors
            ('box', -50.0, 65.0, 31.0, 15.0, 2.0, 2.0),
            ('box', 0.0, 65.0, 31.0, 15.0, 2.0, 2.0),
            ('box', 50.0, 65.0, 31.0, 15.0, 2.0, 2.0),
        ]
    },

    # 19. Kitchen Refrigerator (80 x 70 x 185 cm)
    "FRIDGE001": {
        "metal_chrome": [
            # Stainless Steel Refrigerator Body
            ('box', 0.0, 92.5, 0.0, 80.0, 185.0, 70.0),
        ],
        "metal_dark": [
            # Recessed Split Line & Long Handle Bars
            ('box', 0.0, 110.0, 35.5, 80.0, 1.5, 2.0),
            ('box', 34.0, 140.0, 37.0, 2.5, 50.0, 3.0),
            ('box', 34.0, 60.0, 37.0, 2.5, 60.0, 3.0),
        ]
    },

    # 20. Kitchen Sink Counter (120 x 60 x 90 cm)
    "SINK001": {
        "wood_oak": [
            ('box', 0.0, 43.0, 0.0, 120.0, 86.0, 60.0),
        ],
        "metal_chrome": [
            # Countertop & Stainless Sink Basin
            ('box', 0.0, 88.0, 0.0, 122.0, 4.0, 62.0),
            # Gooseneck Faucet
            ('cyl', 0.0, 98.0, -16.0, 1.8, 16.0),
            ('box', 0.0, 105.0, -10.0, 2.0, 2.0, 14.0),
        ]
    },

    # 21. Scandinavian Dining Chair (50 x 50 x 85 cm)
    "DINING_CHAIR001": {
        "wood_oak": [
            # 4 Tapered Wooden Legs
            ('cyl', -18.0, 22.0, -18.0, 1.8, 44.0),
            ('cyl', 18.0, 22.0, -18.0, 1.8, 44.0),
            ('cyl', -18.0, 22.0, 18.0, 1.8, 44.0),
            ('cyl', 18.0, 22.0, 18.0, 1.8, 44.0),
            # Spindle Backrest Support
            ('box', 0.0, 68.0, -19.0, 44.0, 38.0, 3.5),
        ],
        "fabric_cushion": [
            # Padded Seat Cushion
            ('box', 0.0, 45.0, 0.0, 48.0, 6.0, 48.0),
        ]
    },

    # 22. Kitchen Cooking Range & Stove (80 x 60 x 90 cm)
    "KITCHEN_STOVE001": {
        "metal_dark": [
            # Heavy Stove Base Range Body
            ('box', 0.0, 42.0, 0.0, 80.0, 84.0, 60.0),
            # Glass Oven Door Inset
            ('box', 0.0, 40.0, 30.5, 68.0, 48.0, 1.5),
            # 4 Cooktop Gas Burner Rings on top
            ('cyl', -22.0, 85.5, -14.0, 8.0, 1.0),
            ('cyl', 22.0, 85.5, -14.0, 8.0, 1.0),
            ('cyl', -22.0, 85.5, 14.0, 8.0, 1.0),
            ('cyl', 22.0, 85.5, 14.0, 8.0, 1.0),
        ],
        "metal_chrome": [
            # Stainless Steel Cooktop Surface
            ('box', 0.0, 85.0, 0.0, 82.0, 2.0, 62.0),
            # Oven Handle Bar
            ('box', 0.0, 66.0, 33.0, 56.0, 2.0, 2.5),
            # Control Knobs
            ('cyl', -28.0, 81.0, 31.0, 2.0, 2.0),
            ('cyl', -14.0, 81.0, 31.0, 2.0, 2.0),
            ('cyl', 14.0, 81.0, 31.0, 2.0, 2.0),
            ('cyl', 28.0, 81.0, 31.0, 2.0, 2.0),
        ]
    },

    # 23. Bathroom Vanity Unit (100 x 50 x 85 cm)
    "BATH_VANITY001": {
        "wood_oak": [
            # Vanity Cabinet Base Body
            ('box', 0.0, 40.0, 0.0, 100.0, 80.0, 50.0),
            # 2 Cabinet Doors
            ('box', -24.0, 40.0, 25.5, 46.0, 74.0, 2.0),
            ('box', 24.0, 40.0, 25.5, 46.0, 74.0, 2.0),
        ],
        "plant_pot": [
            # Ceramic White Basin Top
            ('box', 0.0, 82.0, 0.0, 102.0, 4.0, 52.0),
        ],
        "metal_chrome": [
            # Chrome Faucet
            ('cyl', 0.0, 92.0, -12.0, 1.5, 16.0),
            ('box', 0.0, 99.0, -6.0, 1.8, 1.8, 12.0),
            # Handles
            ('box', -4.0, 40.0, 27.5, 1.5, 20.0, 1.5),
            ('box', 4.0, 40.0, 27.5, 1.5, 20.0, 1.5),
        ]
    }
}

def generate_all_glbs(models_dir="uploads/furniture/models"):
    os.makedirs(models_dir, exist_ok=True)
    generated_count = 0
    for asset_id, parts_by_mat in DETAILED_FURNITURE.items():
        glb_data = build_multi_material_glb(parts_by_mat)
        filepath = os.path.join(models_dir, f"{asset_id}.glb")
        with open(filepath, "wb") as f:
            f.write(glb_data)
        generated_count += 1
        print(f"[OK] Generated High-Detail GLB: {filepath} ({len(glb_data)} bytes, {len(parts_by_mat)} materials)")

    # Also copy to static/furniture/models if needed
    static_models_dir = os.path.join("static", "furniture", "models")
    if os.path.exists("static"):
        os.makedirs(static_models_dir, exist_ok=True)
        for asset_id, parts_by_mat in DETAILED_FURNITURE.items():
            glb_data = build_multi_material_glb(parts_by_mat)
            filepath = os.path.join(static_models_dir, f"{asset_id}.glb")
            with open(filepath, "wb") as f:
                f.write(glb_data)

FURNITURE_SHAPES = {}
for _aid, _pbm in DETAILED_FURNITURE.items():
    _all_boxes = []
    for _mat, _parts in _pbm.items():
        for _p in _parts:
            if _p[0] == 'box':
                _all_boxes.append((_p[1], _p[2], _p[3], _p[4], _p[5], _p[6]))
            elif _p[0] == 'cyl':
                _all_boxes.append((_p[1], _p[2], _p[3], _p[4]*2, _p[5], _p[4]*2))
    FURNITURE_SHAPES[_aid] = (_all_boxes, (0.6, 0.5, 0.4, 1.0))

if __name__ == "__main__":
    generate_all_glbs()
