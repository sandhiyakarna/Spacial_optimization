import math
import uuid
import random
from typing import List, Dict, Any, Tuple, Optional
from sqlalchemy.orm import Session
from features.furniture.models import FurnitureAsset
from features.ai.geometry import OBB2D, closest_point_on_obb, obb_overlap_sat

def make_furniture_instance(
    asset: FurnitureAsset,
    x: float,
    y: float,
    z: float,
    rotation_y: float,
    category: str,
    functional_zone: str,
    role: str = "general"
) -> Dict[str, Any]:
    """
    Constructs a standardized furniture instance payload.
    """
    return {
        "id": str(uuid.uuid4()),
        "assetId": asset.id,
        "asset_id": asset.id,
        "name": asset.name,
        "width": asset.width,
        "depth": asset.depth,
        "height": asset.height,
        "x": float(round(x, 1)),
        "y": float(round(y, 1)),
        "z": float(round(z, 1)),
        "rotationY": float(round(rotation_y, 4)),
        "rotation": float(round(rotation_y, 4)),
        "scaleX": 1.0, "scaleY": 1.0, "scaleZ": 1.0,
        "category": category,
        "functional_zone": functional_zone,
        "role": role,
        "bounding_box": {
            "center": [float(round(x, 1)), float(round(z, 1))],
            "width": asset.width,
            "depth": asset.depth,
            "rotation": float(round(rotation_y, 4))
        }
    }

def clamp_to_bounds(
    x: float,
    z: float,
    width: float,
    depth: float,
    rotation: float,
    room_width: float,
    room_length: float
) -> Tuple[float, float]:
    """
    Clamps center coordinates to keep the rotated bounding box fully inside room boundaries.
    """
    cos_r = abs(math.cos(rotation))
    sin_r = abs(math.sin(rotation))
    half_w = (width * cos_r + depth * sin_r) / 2.0
    half_d = (width * sin_r + depth * cos_r) / 2.0
    
    min_x = min(half_w + 5.0, room_width / 2.0)
    max_x = max(room_width - half_w - 5.0, room_width / 2.0)
    clamped_x = max(min_x, min(max_x, x))
    
    min_z = min(half_d + 5.0, room_length / 2.0)
    max_z = max(room_length - half_d - 5.0, room_length / 2.0)
    clamped_z = max(min_z, min(max_z, z))
    
    return float(round(clamped_x, 1)), float(round(clamped_z, 1))

def is_near_openings(
    x: float,
    z: float,
    width: float,
    depth: float,
    rotation: float,
    openings: List[Dict[str, Any]]
) -> bool:
    """
    Checks if a proposed placement overlaps with door swings or blocks window clearance.
    """
    obb = OBB2D(x, z, width, depth, rotation)
    for op in openings:
        op_x = op.get('x', 0.0)
        op_z = op.get('y', 0.0)  # y represents the Z coordinate in openings JSON
        op_w = op.get('width', 80.0)
        op_type = op.get('type', 'door')
        
        gx, gz = closest_point_on_obb(obb, (op_x, op_z))
        dist = math.sqrt((gx - op_x)**2 + (gz - op_z)**2)
        
        if op_type == 'door':
            # Blocked door swing zone
            if dist < op_w + 10.0:
                return True
        elif op_type == 'window':
            # Blocked window zone (within 50 cm)
            if dist < 50.0:
                return True
    return False

ROOM_COMPATIBILITY_RULES = {
    "kitchen": {
        "allowed_categories": ["kitchen", "dining", "lighting", "decor", "plants"],
        "prohibited_keywords": ["office", "manager", "executive", "desk", "bed", "wardrobe", "sofa", "couch", "nightstand", "armchair", "tv console", "study desk", "task chair"],
        "essential_roles": ["food_storage", "cleaning", "preparation", "cooking", "storage"],
    },
    "dining": {
        "allowed_categories": ["dining", "kitchen", "lighting", "decor", "plants"],
        "prohibited_keywords": ["office", "manager", "executive", "desk", "bed", "wardrobe", "sofa", "couch", "nightstand", "sink", "refrigerator", "stove", "cooktop", "range", "kitchen counter", "tv console"],
        "essential_roles": ["dining_table", "dining_chair"],
    },
    "bedroom": {
        "allowed_categories": ["bedroom", "office", "lighting", "decor", "plants"],
        "prohibited_keywords": ["kitchen", "sink", "counter", "refrigerator", "fridge", "stove", "dining table", "coffee table"],
        "essential_roles": ["primary_sleep", "bedside", "wardrobe"],
    },
    "living": {
        "allowed_categories": ["living room", "lighting", "decor", "plants", "office"],
        "prohibited_keywords": ["bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge", "stove", "kitchen counter"],
        "essential_roles": ["sofa", "coffee_table", "tv_console"],
    },
    "office": {
        "allowed_categories": ["office", "lighting", "decor", "plants"],
        "prohibited_keywords": ["bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge", "stove", "kitchen counter", "sofa", "dining table"],
        "essential_roles": ["desk", "chair"],
    },
    "study": {
        "allowed_categories": ["office", "lighting", "decor", "plants"],
        "prohibited_keywords": ["bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge", "stove", "kitchen counter", "sofa", "dining table"],
        "essential_roles": ["desk", "chair", "bookshelf"],
    },
    "bathroom": {
        "allowed_categories": ["bathroom", "decor", "lighting"],
        "prohibited_keywords": ["bed", "desk", "sofa", "wardrobe", "dining table", "tv", "refrigerator", "couch"],
        "essential_roles": ["vanity"],
    }
}

from features.ai.room_rules import (
    ROOM_RULES, get_room_rule, is_asset_compatible_with_room, check_missing_essential_assets
)

def select_furniture_assets(db: Session, room_type: Optional[str] = None) -> Dict[str, List[FurnitureAsset]]:
    """
    Categorizes the database catalog assets by type and names with robust scored rankings,
    strictly respecting room-type compatibility.
    """
    raw_assets = db.query(FurnitureAsset).all()
    if not raw_assets:
        return {}

    # Hard room-type filtering: filter out any asset that violates room rules
    if room_type:
        assets = [a for a in raw_assets if is_asset_compatible_with_room(a, room_type)]
    else:
        assets = raw_assets
        
    def find_list(keywords: List[str], exclude: Optional[List[str]] = None, req_cat: Optional[List[str]] = None) -> List[FurnitureAsset]:
        exclude = [x.lower() for x in (exclude or [])]
        req_cat = [x.lower() for x in (req_cat or [])] if req_cat else None
        ranked = []
        for a in assets:
            name = a.name.lower()
            cat = a.category.lower()
            tags = (a.tags or "").lower()
            if any(ex in name or ex in cat or ex in tags for ex in exclude):
                continue
            if req_cat and not any(rc in cat for rc in req_cat):
                continue
            score = 0
            for kw in keywords:
                kw_low = kw.lower()
                if kw_low in name:
                    score += 15
                elif kw_low in tags:
                    score += 10
                elif kw_low in cat:
                    score += 5
            if score > 0:
                ranked.append((score, a))
        ranked.sort(key=lambda x: x[0], reverse=True)
        return [x[1] for x in ranked]

    desks = find_list(["desk", "workstation"], exclude=["chair", "dining", "coffee", "counter", "kitchen", "sink"])
    exec_desks = find_list(["executive", "manager", "desk"], exclude=["chair", "study", "dining", "counter", "kitchen"]) or desks
    chairs = find_list(["chair"], exclude=["desk", "table", "dining", "counter", "sink", "executive", "manager", "office"])
    manager_chairs = find_list(["manager", "executive", "ergonomic", "chair"], exclude=["visitor", "guest", "desk", "dining"]) or chairs
    visitor_chairs = find_list(["visitor", "guest", "chair"], exclude=["manager", "desk", "dining"]) or chairs
    bookshelves = find_list(["bookshelf", "shelf", "bookcase"], exclude=["desk", "chair", "kitchen", "sink", "counter"])
    cabinets = find_list(["storage", "cabinet", "credenza"], exclude=["kitchen", "desk", "chair", "sink", "vanity"])

    kitchen_counters = find_list(["counter", "modular"], exclude=["sink", "stove", "desk", "chair", "bed", "sofa", "office"], req_cat=["kitchen"])
    kitchen_sinks = find_list(["sink"], exclude=["bathroom", "desk", "chair", "bed", "sofa", "office"], req_cat=["kitchen"])
    refrigerators = find_list(["fridge", "refrigerator"], exclude=["desk", "chair", "bed", "sofa", "office"], req_cat=["kitchen"])
    kitchen_stoves = find_list(["stove", "cooktop", "range", "oven"], exclude=["desk", "chair", "bed", "sofa", "office"], req_cat=["kitchen"])
    kitchen_cabinets = find_list(["cabinet", "pantry", "storage"], exclude=["desk", "chair", "bed", "sofa", "office"], req_cat=["kitchen"])

    dining_tables = find_list(["dining", "table"], exclude=["coffee", "desk", "sink", "counter", "bed", "sofa"], req_cat=["dining", "kitchen"])
    dining_chairs = find_list(["dining", "chair"], exclude=["office", "desk", "executive", "manager", "visitor", "sofa", "mesh", "counter", "task", "gaming"], req_cat=["dining"])
    if not dining_chairs:
        dining_chairs = find_list(["chair"], exclude=["office", "desk", "executive", "manager", "visitor", "sofa", "mesh", "counter", "task", "gaming"], req_cat=["dining"])

    catalog = {
        "beds": find_list(["bed"], exclude=["night", "stand", "sofa", "desk", "chair", "table", "sink", "counter"]),
        "stands": find_list(["nightstand", "stand", "night", "bedside"], exclude=["tv", "desk", "chair", "sink", "counter"]),
        "wardrobes": find_list(["wardrobe", "closet", "armoire"], exclude=["desk", "chair", "sink", "counter"]),
        "sofas": find_list(["sofa", "couch"], exclude=["table", "tv", "desk", "chair", "sink", "counter"]),
        "coffee_tables": find_list(["coffee", "table"], exclude=["dining", "desk", "sofa", "sink", "counter"]),
        "tvs": find_list(["tv", "media", "console"], exclude=["sofa", "table", "chair", "sink", "counter"]),
        "desks": desks,
        "exec_desks": exec_desks,
        "chairs": chairs,
        "manager_chairs": manager_chairs,
        "visitor_chairs": visitor_chairs,
        "dining_tables": dining_tables,
        "dining_chairs": dining_chairs,
        "bookshelves": bookshelves,
        "lamps": find_list(["lamp", "light"], exclude=["table", "desk", "chair"]),
        "kitchen_counters": kitchen_counters,
        "cabinets": cabinets,
        "kitchen_cabinets": kitchen_cabinets,
        "kitchen_stoves": kitchen_stoves,
        "refrigerators": refrigerators,
        "sinks": kitchen_sinks,
        "bathroom_vanities": find_list(["vanity", "basin"], exclude=["desk", "chair", "bed", "sofa"], req_cat=["bathroom"]),
        "mirrors": find_list(["mirror"], exclude=["desk", "bed", "sofa"])
    }
    
    return catalog

def find_best_wall(
    room_width: float,
    room_length: float,
    openings: List[Dict[str, Any]]
) -> Tuple[str, float]:
    """
    Ranks walls (North, South, West, East) by checking which has the fewest openings.
    Returns (wall_name, rotation_y).
    """
    walls = [
        ('North', 0.0),
        ('South', math.pi),
        ('West', math.pi / 2.0),
        ('East', 3.0 * math.pi / 2.0)
    ]
    
    wall_scores = {'North': 0.0, 'South': 0.0, 'West': 0.0, 'East': 0.0}
    for op in openings:
        op_x = op.get('x', 0.0)
        op_z = op.get('y', 0.0)
        if op_z <= 35.0:
            wall_scores['North'] += 15.0
        elif op_z >= room_length - 35.0:
            wall_scores['South'] += 15.0
        elif op_x <= 35.0:
            wall_scores['West'] += 15.0
        elif op_x >= room_width - 35.0:
            wall_scores['East'] += 15.0
            
    sorted_walls = sorted(walls, key=lambda w: wall_scores[w[0]])
    return sorted_walls[0]

def get_windows(openings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [op for op in openings if op.get('type') == 'window']

def get_doors(openings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [op for op in openings if op.get('type') == 'door']

def generate_layout_candidates(
    db: Session,
    room_width: float,
    room_length: float,
    room_type: str,
    style: str = "Modern",
    openings: List[Dict[str, Any]] = [],
    preferences: List[str] = [],
    seed: Optional[int] = None,
    locked_furniture: Optional[List[Dict[str, Any]]] = None,
    mode: str = "redesign"
) -> List[Tuple[str, List[Dict[str, Any]], str]]:
    """
    Generates multiple distinct candidate layouts based on room context, room function,
    geometry, and user preferences, strictly preserving locked furniture across all candidates.
    """
    from features.ai.exceptions import AIProcessingException
    
    catalog = select_furniture_assets(db, room_type)
    if not catalog:
        return []
        
    candidates = []
    low_room_type = (room_type or "").lower()
    
    # Standardize preferences
    if preferences is None:
        preferences = []
    is_minimal = "minimal" in [p.lower() for p in preferences] or "minimal furniture" in [p.lower() for p in preferences] or "minimal_furniture" in preferences
    more_spacious = "spacious" in [p.lower() for p in preferences] or "more spacious" in [p.lower() for p in preferences] or "more_spacious" in preferences
    more_storage = "storage" in [p.lower() for p in preferences] or "more storage" in [p.lower() for p in preferences] or "more_storage" in preferences
    better_circ = "circulation" in [p.lower() for p in preferences] or "better circulation" in [p.lower() for p in preferences] or "better_circulation" in preferences
    more_seating = "seating" in [p.lower() for p in preferences] or "more seating" in [p.lower() for p in preferences] or "more_seating" in preferences

    doors = get_doors(openings)
    windows = get_windows(openings)
    room_area_m2 = (room_width * room_length) / 10000.0

    # ---------------------------------------------------------
    # 1. KITCHEN FUNCTIONAL LAYOUT GENERATION
    # ---------------------------------------------------------
    if 'kitchen' in low_room_type:
        counter = catalog["kitchen_counters"][0] if catalog.get("kitchen_counters") else None
        sink = catalog["sinks"][0] if catalog.get("sinks") else None
        fridge = catalog["refrigerators"][0] if catalog.get("refrigerators") else None
        stove = catalog["kitchen_stoves"][0] if catalog.get("kitchen_stoves") else None
        cabinet = catalog["kitchen_cabinets"][0] if catalog.get("kitchen_cabinets") else None
        dtable = catalog["dining_tables"][0] if catalog.get("dining_tables") else None
        dchair = catalog["dining_chairs"][0] if catalog.get("dining_chairs") else None

        # Verify essential kitchen assets
        missing_assets = []
        if not counter: missing_assets.append("Modular Kitchen Counter")
        if not sink: missing_assets.append("Kitchen Sink Station")
        if not fridge: missing_assets.append("Refrigerator Unit")
        if missing_assets:
            raise AIProcessingException(f"Missing essential kitchen furniture in catalog: {', '.join(missing_assets)}.")

        # Candidate 1: L-Shaped Kitchen Layout (Ergonomic Corner Workflow)
        placements_l = []
        # Main prep & washing leg along solid West wall
        cx, cz = clamp_to_bounds(counter.depth / 2.0 + 5.0, counter.width / 2.0 + 20.0, counter.width, counter.depth, math.pi / 2.0, room_width, room_length)
        placements_l.append(make_furniture_instance(counter, cx, 0.0, cz, math.pi / 2.0, "Kitchen", "preparation", "kitchen_counter"))

        sx, sz = clamp_to_bounds(sink.depth / 2.0 + 5.0, counter.width + sink.width / 2.0 + 25.0, sink.width, sink.depth, math.pi / 2.0, room_width, room_length)
        placements_l.append(make_furniture_instance(sink, sx, 0.0, sz, math.pi / 2.0, "Kitchen", "cleaning", "sink"))

        # Cooking and food storage perpendicular leg along North wall
        if stove:
            stx, stz = clamp_to_bounds(counter.depth + stove.width / 2.0 + 20.0, stove.depth / 2.0 + 5.0, stove.width, stove.depth, 0.0, room_width, room_length)
            placements_l.append(make_furniture_instance(stove, stx, 0.0, stz, 0.0, "Kitchen", "cooking", "stove"))

        fx_offset = (counter.depth + (stove.width if stove else 0.0) + fridge.width / 2.0 + 35.0)
        fx, fz = clamp_to_bounds(fx_offset, fridge.depth / 2.0 + 5.0, fridge.width, fridge.depth, 0.0, room_width, room_length)
        placements_l.append(make_furniture_instance(fridge, fx, 0.0, fz, 0.0, "Kitchen", "food_storage", "refrigerator"))

        if cabinet and not is_minimal:
            cab_x, cab_z = clamp_to_bounds(room_width - cabinet.depth / 2.0 - 5.0, room_length * 0.40, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_l.append(make_furniture_instance(cabinet, cab_x, 0.0, cab_z, 3.0 * math.pi / 2.0, "Kitchen", "storage", "kitchen_cabinet"))

        candidates.append((
            "l_shaped",
            placements_l,
            "L-shaped kitchen layout providing continuous prep and sink workspace with integrated refrigeration and cooking zones."
        ))

        # Candidate 2: Galley / Parallel Kitchen Layout (High Efficiency Corridor)
        placements_galley = []
        # Side 1 (West wall): Prep counter + Sink station
        cx, cz = clamp_to_bounds(counter.depth / 2.0 + 5.0, counter.width / 2.0 + 20.0, counter.width, counter.depth, math.pi / 2.0, room_width, room_length)
        placements_galley.append(make_furniture_instance(counter, cx, 0.0, cz, math.pi / 2.0, "Kitchen", "preparation", "kitchen_counter"))

        sx, sz = clamp_to_bounds(sink.depth / 2.0 + 5.0, counter.width + sink.width / 2.0 + 35.0, sink.width, sink.depth, math.pi / 2.0, room_width, room_length)
        placements_galley.append(make_furniture_instance(sink, sx, 0.0, sz, math.pi / 2.0, "Kitchen", "cleaning", "sink"))

        # Side 2 (East wall): Refrigerator + Stove + Pantry Storage
        fx, fz = clamp_to_bounds(room_width - fridge.depth / 2.0 - 5.0, fridge.width / 2.0 + 20.0, fridge.width, fridge.depth, 3.0 * math.pi / 2.0, room_width, room_length)
        placements_galley.append(make_furniture_instance(fridge, fx, 0.0, fz, 3.0 * math.pi / 2.0, "Kitchen", "food_storage", "refrigerator"))

        if stove:
            stx, stz = clamp_to_bounds(room_width - stove.depth / 2.0 - 5.0, fridge.width + stove.width / 2.0 + 35.0, stove.width, stove.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            placements_galley.append(make_furniture_instance(stove, stx, 0.0, stz, 3.0 * math.pi / 2.0, "Kitchen", "cooking", "stove"))

        if cabinet and not is_minimal:
            cab_x, cab_z = clamp_to_bounds(room_width - cabinet.depth / 2.0 - 5.0, fridge.width + (stove.width if stove else 0.0) + cabinet.width / 2.0 + 50.0, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_galley.append(make_furniture_instance(cabinet, cab_x, 0.0, cab_z, 3.0 * math.pi / 2.0, "Kitchen", "storage", "kitchen_cabinet"))

        candidates.append((
            "galley",
            placements_galley,
            "Parallel galley kitchen configuration with prep & washing along one side and cooking & refrigeration opposite."
        ))

        # Candidate 3: Single-Wall Compact Kitchen Layout (I-Shaped)
        placements_single = []
        if room_width >= 460.0:
            fx, fz = clamp_to_bounds(fridge.width / 2.0 + 15.0, fridge.depth / 2.0 + 5.0, fridge.width, fridge.depth, 0.0, room_width, room_length)
            placements_single.append(make_furniture_instance(fridge, fx, 0.0, fz, 0.0, "Kitchen", "food_storage", "refrigerator"))

            cx, cz = clamp_to_bounds(fx + fridge.width / 2.0 + counter.width / 2.0 + 15.0, counter.depth / 2.0 + 5.0, counter.width, counter.depth, 0.0, room_width, room_length)
            placements_single.append(make_furniture_instance(counter, cx, 0.0, cz, 0.0, "Kitchen", "preparation", "kitchen_counter"))

            if stove:
                stx, stz = clamp_to_bounds(cx + counter.width / 2.0 + stove.width / 2.0 + 15.0, stove.depth / 2.0 + 5.0, stove.width, stove.depth, 0.0, room_width, room_length)
                placements_single.append(make_furniture_instance(stove, stx, 0.0, stz, 0.0, "Kitchen", "cooking", "stove"))
                next_x = stx + stove.width / 2.0 + sink.width / 2.0 + 15.0
            else:
                next_x = cx + counter.width / 2.0 + sink.width / 2.0 + 15.0

            sx, sz = clamp_to_bounds(next_x, sink.depth / 2.0 + 5.0, sink.width, sink.depth, 0.0, room_width, room_length)
            placements_single.append(make_furniture_instance(sink, sx, 0.0, sz, 0.0, "Kitchen", "cleaning", "sink"))
        else:
            # Compact arrangement with prep and sink along North wall, fridge on West wall
            cx, cz = clamp_to_bounds(counter.width / 2.0 + 15.0, counter.depth / 2.0 + 5.0, counter.width, counter.depth, 0.0, room_width, room_length)
            placements_single.append(make_furniture_instance(counter, cx, 0.0, cz, 0.0, "Kitchen", "preparation", "kitchen_counter"))

            sx, sz = clamp_to_bounds(cx + counter.width / 2.0 + sink.width / 2.0 + 15.0, sink.depth / 2.0 + 5.0, sink.width, sink.depth, 0.0, room_width, room_length)
            placements_single.append(make_furniture_instance(sink, sx, 0.0, sz, 0.0, "Kitchen", "cleaning", "sink"))

            fx, fz = clamp_to_bounds(fridge.depth / 2.0 + 5.0, room_length * 0.70, fridge.width, fridge.depth, math.pi / 2.0, room_width, room_length)
            placements_single.append(make_furniture_instance(fridge, fx, 0.0, fz, math.pi / 2.0, "Kitchen", "food_storage", "refrigerator"))

            if stove:
                stx, stz = clamp_to_bounds(room_width - stove.depth / 2.0 - 5.0, room_length * 0.35, stove.width, stove.depth, 3.0 * math.pi / 2.0, room_width, room_length)
                placements_single.append(make_furniture_instance(stove, stx, 0.0, stz, 3.0 * math.pi / 2.0, "Kitchen", "cooking", "stove"))

        if cabinet and not is_minimal:
            cab_x, cab_z = clamp_to_bounds(room_width - cabinet.depth / 2.0 - 5.0, room_length * 0.75, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_single.append(make_furniture_instance(cabinet, cab_x, 0.0, cab_z, 3.0 * math.pi / 2.0, "Kitchen", "storage", "kitchen_cabinet"))

        candidates.append((
            "single_wall",
            placements_single,
            "Single-wall linear kitchen arrangement maximizing open floor space and continuous walkway circulation."
        ))

        # Candidate 4: Eat-in Kitchen Layout (Spacious kitchens >= 14 m²)
        if room_area_m2 >= 14.0 and dtable and dchair and not is_minimal and not more_spacious:
            placements_eatin = [p.copy() for p in placements_l]
            tx, tz = clamp_to_bounds(room_width * 0.65, room_length * 0.65, dtable.width, dtable.depth, 0.0, room_width, room_length)
            if not is_near_openings(tx, tz, dtable.width, dtable.depth, 0.0, openings):
                # Check chair clearances around table
                c1x, c1z = clamp_to_bounds(tx, tz - dtable.depth / 2.0 - dchair.depth / 2.0 - 15.0, dchair.width, dchair.depth, 0.0, room_width, room_length)
                c2x, c2z = clamp_to_bounds(tx, tz + dtable.depth / 2.0 + dchair.depth / 2.0 + 15.0, dchair.width, dchair.depth, math.pi, room_width, room_length)
                c1_ok = not is_near_openings(c1x, c1z, dchair.width, dchair.depth, 0.0, openings)
                c2_ok = not is_near_openings(c2x, c2z, dchair.width, dchair.depth, math.pi, openings)
                if c1_ok and c2_ok:
                    placements_eatin.append(make_furniture_instance(dtable, tx, 0.0, tz, 0.0, "Dining", "dining", "dining_table"))
                    placements_eatin.append(make_furniture_instance(dchair, c1x, 0.0, c1z, 0.0, "Dining", "dining", "dining_chair_1"))
                    placements_eatin.append(make_furniture_instance(dchair, c2x, 0.0, c2z, math.pi, "Dining", "dining", "dining_chair_2"))
                    candidates.append((
                        "functional_zoned",
                        placements_eatin,
                        "Eat-in kitchen featuring perimeter cooking/cleaning counters and a dedicated dining table cluster."
                    ))

    # ---------------------------------------------------------
    # 2. DINING ROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    elif 'dining' in low_room_type:
        dtable = catalog["dining_tables"][0] if catalog.get("dining_tables") else None
        dchair = catalog["dining_chairs"][0] if catalog.get("dining_chairs") else None
        cabinet = catalog["cabinets"][0] if catalog.get("cabinets") else None

        if not dtable or not dchair:
            raise AIProcessingException("Dining Room requires dining table and dining chair assets in catalog.")

        # Candidate 1: Center-Oriented Formal Dining
        placements_formal = []
        tx, tz = clamp_to_bounds(room_width / 2.0, room_length / 2.0, dtable.width, dtable.depth, 0.0, room_width, room_length)
        placements_formal.append(make_furniture_instance(dtable, tx, 0.0, tz, 0.0, "Dining", "dining", "dining_table"))

        # 4 Chairs surrounding dining table
        c1x, c1z = clamp_to_bounds(tx, tz - dtable.depth / 2.0 - dchair.depth / 2.0 - 20.0, dchair.width, dchair.depth, 0.0, room_width, room_length)
        c2x, c2z = clamp_to_bounds(tx, tz + dtable.depth / 2.0 + dchair.depth / 2.0 + 20.0, dchair.width, dchair.depth, math.pi, room_width, room_length)
        placements_formal.append(make_furniture_instance(dchair, c1x, 0.0, c1z, 0.0, "Dining", "dining", "dining_chair_1"))
        placements_formal.append(make_furniture_instance(dchair, c2x, 0.0, c2z, math.pi, "Dining", "dining", "dining_chair_2"))

        if room_width >= 320.0:
            c3x, c3z = clamp_to_bounds(tx - dtable.width / 2.0 - dchair.depth / 2.0 - 20.0, tz, dchair.width, dchair.depth, math.pi / 2.0, room_width, room_length)
            c4x, c4z = clamp_to_bounds(tx + dtable.width / 2.0 + dchair.depth / 2.0 + 20.0, tz, dchair.width, dchair.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            placements_formal.append(make_furniture_instance(dchair, c3x, 0.0, c3z, math.pi / 2.0, "Dining", "dining", "dining_chair_3"))
            placements_formal.append(make_furniture_instance(dchair, c4x, 0.0, c4z, 3.0 * math.pi / 2.0, "Dining", "dining", "dining_chair_4"))

        if cabinet and not is_minimal:
            cab_x, cab_z = clamp_to_bounds(room_width - cabinet.depth / 2.0 - 5.0, room_length / 2.0, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_formal.append(make_furniture_instance(cabinet, cab_x, 0.0, cab_z, 3.0 * math.pi / 2.0, "Dining", "storage", "sideboard"))

        candidates.append((
            "center_oriented",
            placements_formal,
            "Formal dining arrangement featuring centered Scandinavian dining table, ergonomic chairs, and perimeter sideboard."
        ))

        # Candidate 2: Wall-Adjacent Space-Efficient Dining
        placements_side = []
        tx, tz = clamp_to_bounds(room_width * 0.42, room_length / 2.0, dtable.width, dtable.depth, 0.0, room_width, room_length)
        placements_side.append(make_furniture_instance(dtable, tx, 0.0, tz, 0.0, "Dining", "dining", "dining_table"))
        c1x, c1z = clamp_to_bounds(tx, tz - dtable.depth / 2.0 - dchair.depth / 2.0 - 20.0, dchair.width, dchair.depth, 0.0, room_width, room_length)
        c2x, c2z = clamp_to_bounds(tx, tz + dtable.depth / 2.0 + dchair.depth / 2.0 + 20.0, dchair.width, dchair.depth, math.pi, room_width, room_length)
        placements_side.append(make_furniture_instance(dchair, c1x, 0.0, c1z, 0.0, "Dining", "dining", "dining_chair_1"))
        placements_side.append(make_furniture_instance(dchair, c2x, 0.0, c2z, math.pi, "Dining", "dining", "dining_chair_2"))

        candidates.append((
            "space_efficient",
            placements_side,
            "Space-efficient dining layout preserving wide circulation paths."
        ))

    # ---------------------------------------------------------
    # 3. BEDROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    elif 'bedroom' in low_room_type:
        bed = catalog["beds"][0] if catalog.get("beds") else None
        stand = catalog["stands"][0] if catalog.get("stands") else None
        wardrobe = catalog["wardrobes"][0] if catalog.get("wardrobes") else None
        desk = catalog["desks"][0] if catalog.get("desks") else None
        chair = catalog["chairs"][0] if catalog.get("chairs") else None
        
        if not bed:
            raise AIProcessingException("Bedroom requires bed asset in catalog.")

        best_wall_name, bed_rot = find_best_wall(room_width, room_length, openings)
        
        # 1. Wall Aligned / Symmetrical Master Candidate
        placements_wall = []
        if best_wall_name == 'North':
            bx, bz = room_width / 2.0, bed.depth / 2.0 + 15.0
        elif best_wall_name == 'South':
            bx, bz = room_width / 2.0, room_length - bed.depth / 2.0 - 15.0
        elif best_wall_name == 'West':
            bx, bz = bed.depth / 2.0 + 15.0, room_length / 2.0
        else:
            bx, bz = room_width - bed.depth / 2.0 - 15.0, room_length / 2.0
            
        bx, bz = clamp_to_bounds(bx, bz, bed.width, bed.depth, bed_rot, room_width, room_length)
        placements_wall.append(make_furniture_instance(bed, bx, 0.0, bz, bed_rot, "Bedroom", "sleep", "primary_sleep"))
        
        # Flanking bedside tables
        if stand:
            if best_wall_name in ['North', 'South']:
                sx1, sz1 = bx - bed.width / 2.0 - stand.width / 2.0 - 10.0, bz
                sx2, sz2 = bx + bed.width / 2.0 + stand.width / 2.0 + 10.0, bz
            else:
                sx1, sz1 = bx, bz - bed.width / 2.0 - stand.width / 2.0 - 10.0
                sx2, sz2 = bx, bz + bed.width / 2.0 + stand.width / 2.0 + 10.0
                
            sx1, sz1 = clamp_to_bounds(sx1, sz1, stand.width, stand.depth, bed_rot, room_width, room_length)
            sx2, sz2 = clamp_to_bounds(sx2, sz2, stand.width, stand.depth, bed_rot, room_width, room_length)
            placements_wall.append(make_furniture_instance(stand, sx1, 0.0, sz1, bed_rot, "Bedroom", "sleep", "bedside"))
            if room_width >= 320.0 or best_wall_name not in ['North', 'South']:
                placements_wall.append(make_furniture_instance(stand, sx2, 0.0, sz2, bed_rot, "Bedroom", "sleep", "bedside"))
            
        # Wardrobe along a solid side wall
        if wardrobe:
            w_rot = (bed_rot + math.pi / 2.0) % (2.0 * math.pi)
            if best_wall_name in ['North', 'South']:
                wx = room_width - wardrobe.depth / 2.0 - 15.0
                wz = room_length * 0.65 if best_wall_name == 'North' else room_length * 0.35
                w_rot = 3.0 * math.pi / 2.0
            else:
                wx = room_width * 0.65 if best_wall_name == 'West' else room_width * 0.35
                wz = room_length - wardrobe.depth / 2.0 - 15.0
                w_rot = math.pi
                
            wx, wz = clamp_to_bounds(wx, wz, wardrobe.width, wardrobe.depth, w_rot, room_width, room_length)
            if not is_near_openings(wx, wz, wardrobe.width, wardrobe.depth, w_rot, openings):
                placements_wall.append(make_furniture_instance(wardrobe, wx, 0.0, wz, w_rot, "Bedroom", "storage", "wardrobe"))
            
        candidates.append((
            "wall_aligned",
            placements_wall,
            f"Minimalist King Bed placed against the solid {best_wall_name} wall with bedside tables, wardrobe, and dedicated circulation."
        ))
        
        # 2. Functional Zoned Candidate
        placements_zoned = []
        if best_wall_name in ['North', 'South']:
            bx, bz = room_width * 0.40, bed.depth / 2.0 + 15.0 if best_wall_name == 'North' else room_length - bed.depth / 2.0 - 15.0
            bed_rot_z = 0.0 if best_wall_name == 'North' else math.pi
        else:
            bx, bz = bed.depth / 2.0 + 15.0 if best_wall_name == 'West' else room_width - bed.depth / 2.0 - 15.0, room_length * 0.40
            bed_rot_z = math.pi / 2.0 if best_wall_name == 'West' else 3.0 * math.pi / 2.0

        bx, bz = clamp_to_bounds(bx, bz, bed.width, bed.depth, bed_rot_z, room_width, room_length)
        placements_zoned.append(make_furniture_instance(bed, bx, 0.0, bz, bed_rot_z, "Bedroom", "sleep", "primary_sleep"))
        
        if stand:
            if bed_rot_z in [0.0, math.pi]:
                sx = bx + bed.width / 2.0 + stand.width / 2.0 + 10.0
                sz = bz
            else:
                sx = bx
                sz = bz + bed.width / 2.0 + stand.width / 2.0 + 10.0
            sx, sz = clamp_to_bounds(sx, sz, stand.width, stand.depth, bed_rot_z, room_width, room_length)
            placements_zoned.append(make_furniture_instance(stand, sx, 0.0, sz, bed_rot_z, "Bedroom", "sleep", "bedside"))

        if wardrobe:
            w_rot_z = 3.0 * math.pi / 2.0 if best_wall_name != 'East' else math.pi / 2.0
            wx = room_width - wardrobe.depth / 2.0 - 15.0 if best_wall_name != 'East' else wardrobe.depth / 2.0 + 15.0
            wz = room_length * 0.75
            wx, wz = clamp_to_bounds(wx, wz, wardrobe.width, wardrobe.depth, w_rot_z, room_width, room_length)
            if not is_near_openings(wx, wz, wardrobe.width, wardrobe.depth, w_rot_z, openings):
                placements_zoned.append(make_furniture_instance(wardrobe, wx, 0.0, wz, w_rot_z, "Bedroom", "storage", "wardrobe"))

        if desk and chair and room_area_m2 >= 12.0 and not is_minimal and not more_spacious:
            dx = desk.width / 2.0 + 20.0
            dz = room_length * 0.75
            dx, dz = clamp_to_bounds(dx, dz, desk.width, desk.depth, math.pi / 2.0, room_width, room_length)
            if not is_near_openings(dx, dz, desk.width, desk.depth, math.pi / 2.0, openings):
                placements_zoned.append(make_furniture_instance(desk, dx, 0.0, dz, math.pi / 2.0, "Office", "study", "desk"))
                cx, cz = clamp_to_bounds(dx + 50.0, dz, chair.width, chair.depth, math.pi / 2.0, room_width, room_length)
                placements_zoned.append(make_furniture_instance(chair, cx, 0.0, cz, math.pi / 2.0, "Office", "study", "chair"))

        candidates.append((
            "functional_zoned",
            placements_zoned,
            "Room partitioned into ergonomic sleep, wardrobe storage, and study zones."
        ))

    # ---------------------------------------------------------
    # 4. BATHROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    elif 'bathroom' in low_room_type or 'restroom' in low_room_type:
        vanity = catalog["bathroom_vanities"][0] if catalog.get("bathroom_vanities") else None
        cabinet = catalog["cabinets"][0] if catalog.get("cabinets") else None
        
        if not vanity:
            # Create standard vanity instance from catalog cabinet/counter if specific vanity missing
            raise AIProcessingException("Bathroom requires a bathroom vanity or basin asset in catalog.")

        placements_bath = []
        best_wall_name, v_rot = find_best_wall(room_width, room_length, openings)
        
        if best_wall_name == 'North':
            vx, vz = room_width / 2.0, vanity.depth / 2.0 + 5.0
        elif best_wall_name == 'South':
            vx, vz = room_width / 2.0, room_length - vanity.depth / 2.0 - 5.0
        elif best_wall_name == 'West':
            vx, vz = vanity.depth / 2.0 + 5.0, room_length / 2.0
        else:
            vx, vz = room_width - vanity.depth / 2.0 - 5.0, room_length / 2.0
            
        vx, vz = clamp_to_bounds(vx, vz, vanity.width, vanity.depth, v_rot, room_width, room_length)
        placements_bath.append(make_furniture_instance(vanity, vx, 0.0, vz, v_rot, "Bathroom", "washing", "vanity"))

        candidates.append((
            "wall_aligned",
            placements_bath,
            "Bathroom vanity positioned along primary solid wall with ample grooming clearance."
        ))

    # ---------------------------------------------------------
    # 5. OFFICE / MANAGER'S ROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    elif any(k in low_room_type for k in ['manager', 'executive', 'office']):
        desk = catalog["exec_desks"][0] if catalog.get("exec_desks") else catalog["desks"][0]
        chair = catalog["manager_chairs"][0] if catalog.get("manager_chairs") else catalog["chairs"][0]
        visitor_asset = catalog["visitor_chairs"][0] if catalog.get("visitor_chairs") else catalog["chairs"][0]
        cabinet = catalog["cabinets"][0] if catalog.get("cabinets") else None
        bookshelf = catalog["bookshelves"][0] if catalog.get("bookshelves") else None
        
        door_z = doors[0].get('y', 0.0) if doors else room_length
        door_x = doors[0].get('x', 0.0) if doors else room_width / 2.0
        
        if doors and door_z <= 35.0:
            d_rot = 0.0
        elif doors and door_z >= room_length - 35.0:
            d_rot = math.pi
        elif doors and door_x <= 35.0:
            d_rot = math.pi / 2.0
        elif doors and door_x >= room_width - 35.0:
            d_rot = 3.0 * math.pi / 2.0
        else:
            d_rot = math.pi
            
        # 1. Executive Command Strategy
        placements_command = []
        if d_rot == math.pi:
            dx = room_width / 2.0
            dz = max(desk.depth / 2.0 + chair.depth + 45.0, min(room_length - desk.depth / 2.0 - visitor_asset.depth - 110.0, room_length * 0.42))
        elif d_rot == 0.0:
            dx = room_width / 2.0
            dz = min(room_length - desk.depth / 2.0 - chair.depth - 45.0, max(desk.depth / 2.0 + visitor_asset.depth + 110.0, room_length * 0.58))
        elif d_rot == math.pi / 2.0:
            dx = min(room_width - desk.depth / 2.0 - chair.depth - 45.0, max(desk.depth / 2.0 + visitor_asset.depth + 110.0, room_width * 0.58))
            dz = room_length / 2.0
        else:
            dx = max(desk.depth / 2.0 + chair.depth + 45.0, min(room_width - desk.depth / 2.0 - visitor_asset.depth - 110.0, room_width * 0.42))
            dz = room_length / 2.0
            
        dx, dz = clamp_to_bounds(dx, dz, desk.width, desk.depth, d_rot, room_width, room_length)
        placements_command.append(make_furniture_instance(desk, dx, 0.0, dz, d_rot, "Office", "study", "desk"))
        
        mc_dist = desk.depth / 2.0 + chair.depth / 2.0 + 35.0
        cx = dx - mc_dist * math.sin(d_rot)
        cz = dz + mc_dist * math.cos(d_rot)
        cx, cz = clamp_to_bounds(cx, cz, chair.width, chair.depth, d_rot, room_width, room_length)
        placements_command.append(make_furniture_instance(chair, cx, 0.0, cz, d_rot, "Office", "study", "manager_chair"))
        
        vc_dist = desk.depth / 2.0 + visitor_asset.depth / 2.0 + 35.0
        vc_rot = (d_rot + math.pi) % (2.0 * math.pi)
        v_spacing = min(60.0, max(42.0, desk.width * 0.28))
        for idx, sign in enumerate([-1.0, 1.0]):
            lat_x = sign * v_spacing * math.cos(d_rot)
            lat_z = sign * v_spacing * math.sin(d_rot)
            vx = dx + vc_dist * math.sin(d_rot) + lat_x
            vz = dz - vc_dist * math.cos(d_rot) + lat_z
            vx, vz = clamp_to_bounds(vx, vz, visitor_asset.width, visitor_asset.depth, vc_rot, room_width, room_length)
            placements_command.append(make_furniture_instance(visitor_asset, vx, 0.0, vz, vc_rot, "Office", "study", f"visitor_chair_{idx+1}"))

        if cabinet:
            cab_z = min(room_length - cabinet.width / 2.0 - 25.0, max(cabinet.width / 2.0 + 25.0, room_length * 0.70))
            wx = room_width - cabinet.depth / 2.0 - 5.0
            wx, wz = clamp_to_bounds(wx, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(wx, wz, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_command.append(make_furniture_instance(cabinet, wx, 0.0, wz, 3.0 * math.pi / 2.0, "Office", "storage", "cabinet"))

        if bookshelf:
            shelf_z = min(room_length - bookshelf.width / 2.0 - 25.0, max(bookshelf.width / 2.0 + 25.0, room_length * 0.30))
            bx = bookshelf.depth / 2.0 + 5.0
            bx, bz = clamp_to_bounds(bx, shelf_z, bookshelf.width, bookshelf.depth, math.pi / 2.0, room_width, room_length)
            if not is_near_openings(bx, bz, bookshelf.width, bookshelf.depth, math.pi / 2.0, openings):
                placements_command.append(make_furniture_instance(bookshelf, bx, 0.0, bz, math.pi / 2.0, "Office", "storage", "bookshelf"))
        
        candidates.append((
            "center_oriented",
            placements_command,
            "Executive Manager's Office with commanding desk facing entrance, ergonomic manager chair, 2 visitor chairs, side cabinet, and bookshelf with wide circulation."
        ))

        # 2. Wall Aligned Office Strategy
        placements_wall = []
        w_dx = room_width * 0.40
        w_dz = max(desk.depth / 2.0 + chair.depth + 45.0, min(room_length - desk.depth / 2.0 - visitor_asset.depth - 110.0, room_length * 0.38))
        w_dx, w_dz = clamp_to_bounds(w_dx, w_dz, desk.width, desk.depth, math.pi, room_width, room_length)
        placements_wall.append(make_furniture_instance(desk, w_dx, 0.0, w_dz, math.pi, "Office", "study", "desk"))
        
        w_cx, w_cz = clamp_to_bounds(w_dx, w_dz - desk.depth / 2.0 - chair.depth / 2.0 - 30.0, chair.width, chair.depth, math.pi, room_width, room_length)
        placements_wall.append(make_furniture_instance(chair, w_cx, 0.0, w_cz, math.pi, "Office", "study", "manager_chair"))

        w_vx, w_vz = clamp_to_bounds(w_dx, w_dz + desk.depth / 2.0 + visitor_asset.depth / 2.0 + 35.0, visitor_asset.width, visitor_asset.depth, 0.0, room_width, room_length)
        placements_wall.append(make_furniture_instance(visitor_asset, w_vx, 0.0, w_vz, 0.0, "Office", "study", "visitor_chair_1"))

        if cabinet:
            cab_x = room_width - cabinet.depth / 2.0 - 5.0
            cab_z = min(room_length - cabinet.width / 2.0 - 25.0, max(cabinet.width / 2.0 + 25.0, room_length * 0.50))
            cab_x, cab_z = clamp_to_bounds(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            if not is_near_openings(cab_x, cab_z, cabinet.width, cabinet.depth, 3.0 * math.pi / 2.0, openings):
                placements_wall.append(make_furniture_instance(cabinet, cab_x, 0.0, cab_z, 3.0 * math.pi / 2.0, "Office", "storage", "cabinet"))

        candidates.append((
            "wall_aligned",
            placements_wall,
            "Wall-aligned executive office optimizing open floor circulation and focused work orientation."
        ))

        # 3. Functional Zoned Office Strategy
        placements_zoned = []
        z_dx = room_width * 0.52
        z_dz = max(desk.depth / 2.0 + chair.depth + 45.0, min(room_length - desk.depth / 2.0 - visitor_asset.depth - 110.0, room_length * 0.45))
        z_dx, z_dz = clamp_to_bounds(z_dx, z_dz, desk.width, desk.depth, math.pi, room_width, room_length)
        placements_zoned.append(make_furniture_instance(desk, z_dx, 0.0, z_dz, math.pi, "Office", "study", "desk"))

        z_cx, z_cz = clamp_to_bounds(z_dx, z_dz - desk.depth / 2.0 - chair.depth / 2.0 - 30.0, chair.width, chair.depth, math.pi, room_width, room_length)
        placements_zoned.append(make_furniture_instance(chair, z_cx, 0.0, z_cz, math.pi, "Office", "study", "manager_chair"))

        z_vx1, z_vz1 = clamp_to_bounds(z_dx - 45.0, z_dz + desk.depth / 2.0 + visitor_asset.depth / 2.0 + 35.0, visitor_asset.width, visitor_asset.depth, 0.0, room_width, room_length)
        z_vx2, z_vz2 = clamp_to_bounds(z_dx + 45.0, z_dz + desk.depth / 2.0 + visitor_asset.depth / 2.0 + 35.0, visitor_asset.width, visitor_asset.depth, 0.0, room_width, room_length)
        placements_zoned.append(make_furniture_instance(visitor_asset, z_vx1, 0.0, z_vz1, 0.0, "Office", "study", "visitor_chair_1"))
        placements_zoned.append(make_furniture_instance(visitor_asset, z_vx2, 0.0, z_vz2, 0.0, "Office", "study", "visitor_chair_2"))

        if bookshelf:
            bx = bookshelf.depth / 2.0 + 5.0
            bz = min(room_length - bookshelf.width / 2.0 - 25.0, max(bookshelf.width / 2.0 + 25.0, room_length * 0.35))
            bx, bz = clamp_to_bounds(bx, bz, bookshelf.width, bookshelf.depth, math.pi / 2.0, room_width, room_length)
            if not is_near_openings(bx, bz, bookshelf.width, bookshelf.depth, math.pi / 2.0, openings):
                placements_zoned.append(make_furniture_instance(bookshelf, bx, 0.0, bz, math.pi / 2.0, "Office", "storage", "bookshelf"))

        candidates.append((
            "functional_zoned",
            placements_zoned,
            "Zoned executive layout featuring primary workstation and meeting/consultation seating area."
        ))

    # ---------------------------------------------------------
    # 6. STUDY ROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    elif any(k in low_room_type for k in ['study', 'work']):
        desk = catalog["desks"][0] if catalog.get("desks") else None
        chair = catalog["chairs"][0] if catalog.get("chairs") else None
        bookshelf = catalog["bookshelves"][0] if catalog.get("bookshelves") else None

        if not desk or not chair:
            raise AIProcessingException("Study Room requires study desk and chair in catalog.")

        placements_study = []
        dx, dz = clamp_to_bounds(room_width * 0.45, desk.depth / 2.0 + 25.0, desk.width, desk.depth, 0.0, room_width, room_length)
        placements_study.append(make_furniture_instance(desk, dx, 0.0, dz, 0.0, "Office", "study", "desk"))

        cx, cz = clamp_to_bounds(dx, dz + desk.depth / 2.0 + chair.depth / 2.0 + 25.0, chair.width, chair.depth, math.pi, room_width, room_length)
        placements_study.append(make_furniture_instance(chair, cx, 0.0, cz, math.pi, "Office", "study", "chair"))

        if bookshelf:
            bx, bz = clamp_to_bounds(room_width - bookshelf.depth / 2.0 - 5.0, room_length * 0.50, bookshelf.width, bookshelf.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            placements_study.append(make_furniture_instance(bookshelf, bx, 0.0, bz, 3.0 * math.pi / 2.0, "Office", "storage", "bookshelf"))

        candidates.append((
            "wall_aligned",
            placements_study,
            "Dedicated study workspace with ergonomic task desk, chair clearance, and perimeter bookcase."
        ))

    # ---------------------------------------------------------
    # 7. LIVING ROOM LAYOUT GENERATION
    # ---------------------------------------------------------
    else:
        sofa = catalog["sofas"][0] if catalog.get("sofas") else None
        coffee = catalog["coffee_tables"][0] if catalog.get("coffee_tables") else None
        tv = catalog["tvs"][0] if catalog.get("tvs") else None
        bookshelf = catalog["bookshelves"][0] if catalog.get("bookshelves") else None
        
        if not sofa:
            raise AIProcessingException("Living Room requires sofa asset in catalog.")

        placements_wall = []
        sx, sz = clamp_to_bounds(room_width / 2.0, room_length - sofa.depth / 2.0 - 20.0, sofa.width, sofa.depth, math.pi, room_width, room_length)
        placements_wall.append(make_furniture_instance(sofa, sx, 0.0, sz, math.pi, "Living Room", "seating", "sofa"))

        if tv:
            tx, tz = clamp_to_bounds(room_width / 2.0, tv.depth / 2.0 + 20.0, tv.width, tv.depth, 0.0, room_width, room_length)
            placements_wall.append(make_furniture_instance(tv, tx, 0.0, tz, 0.0, "Living Room", "display", "tv_console"))

        if coffee and not is_minimal and not more_spacious:
            cx, cz = clamp_to_bounds(room_width / 2.0, sz - sofa.depth / 2.0 - coffee.depth / 2.0 - 55.0, coffee.width, coffee.depth, 0.0, room_width, room_length)
            placements_wall.append(make_furniture_instance(coffee, cx, 0.0, cz, 0.0, "Living Room", "social", "coffee_table"))

        if bookshelf and not is_minimal:
            bx, bz = clamp_to_bounds(room_width - bookshelf.depth / 2.0 - 5.0, room_length * 0.40, bookshelf.width, bookshelf.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            placements_wall.append(make_furniture_instance(bookshelf, bx, 0.0, bz, 3.0 * math.pi / 2.0, "Living Room", "storage", "bookshelf"))

        candidates.append(("wall_aligned", placements_wall, "Sofa and TV console aligned against opposite walls with central coffee table."))

    # Apply global preference rules
    for strategy, placements, explanation in candidates:
        if is_minimal or more_spacious:
            filtered = []
            for p in placements:
                role = p.get("role", "")
                if 'bedroom' in low_room_type:
                    if (is_minimal or more_spacious) and role in ["desk", "chair"]:
                        continue
                    filtered.append(p)
                elif 'kitchen' in low_room_type:
                    # In kitchen, counter, sink, and fridge are essential
                    if (is_minimal or more_spacious) and role in ["dining_table", "dining_chair"]:
                        continue
                    filtered.append(p)
                else:
                    primary_roles = ["primary_sleep", "sofa", "desk", "table", "manager_chair", "visitor_chair_1", "visitor_chair_2", "wardrobe", "bedside", "kitchen_counter", "sink", "refrigerator", "stove", "vanity"]
                    if role in primary_roles or "visitor" in role:
                        filtered.append(p)
            placements.clear()
            placements.extend(filtered)
            
    # Preserve locked furniture across all candidates
    if locked_furniture:
        from features.ai.geometry import get_furniture_obb, obb_overlap_sat
        processed_candidates = []
        for strategy, placements, explanation in candidates:
            merged = []
            # First, add all locked furniture
            for lf in locked_furniture:
                locked_copy = dict(lf)
                locked_copy["is_locked"] = True
                locked_copy["isLocked"] = True
                merged.append(locked_copy)
                
            locked_obbs = [get_furniture_obb(lf) for lf in locked_furniture]
            # Next, add placements that don't collide with locked furniture
            for p in placements:
                p_obb = get_furniture_obb(p)
                collides_with_locked = False
                for lobb in locked_obbs:
                    overlap, depth, _ = obb_overlap_sat(p_obb, lobb)
                    if overlap and depth > 10.0:
                        collides_with_locked = True
                        break
                if not collides_with_locked:
                    merged.append(p)
            processed_candidates.append((strategy, merged, explanation + " (Preserved locked furniture)."))
        candidates = processed_candidates

    return candidates

def generate_initial_layout(
    db: Session,
    room_width: float,
    room_length: float,
    room_type: str,
    style: str = "Modern"
) -> List[Dict[str, Any]]:
    candidates = generate_layout_candidates(db, room_width, room_length, room_type, style)
    if candidates:
        return candidates[0][1]
    return []

def validate_ai_response_schema(plan: Dict[str, Any]) -> None:
    from features.ai.exceptions import AIProcessingException
    if not isinstance(plan, dict):
        raise AIProcessingException("AI response must be a JSON object.")
    for key in ["room_type", "layout_intent", "furniture", "reasoning"]:
        if key not in plan:
            raise AIProcessingException(f"AI response missing required key: {key}")
    if not isinstance(plan["furniture"], list):
        raise AIProcessingException("AI response furniture field must be a list.")
    if not isinstance(plan["reasoning"], list):
        raise AIProcessingException("AI response reasoning field must be a list.")
    for idx, item in enumerate(plan["furniture"]):
        if not isinstance(item, dict):
            raise AIProcessingException(f"AI response furniture item at index {idx} must be an object.")
        if "asset_id" not in item:
            raise AIProcessingException(f"AI response furniture item at index {idx} missing 'asset_id'.")
        if "role" not in item:
            raise AIProcessingException(f"AI response furniture item at index {idx} missing 'role'.")

def validate_assets_exist(db: Session, plan: Dict[str, Any]) -> None:
    from features.ai.exceptions import AIProcessingException
    from features.furniture.models import FurnitureAsset
    for item in plan["furniture"]:
        asset_id = item["asset_id"]
        asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
        if not asset:
            raise AIProcessingException(f"Asset ID '{asset_id}' from AI plan does not exist in the database.")

def convert_intent_to_coordinates(
    db: Session,
    room_width: float,
    room_length: float,
    room_type: str,
    plan: Dict[str, Any],
    openings: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    from features.furniture.models import FurnitureAsset
    placements = []
    
    bed_instances = []
    sofa_instances = []
    desk_instances = []
    
    placed_stands = 0
    placed_chairs = 0
    
    doors = get_doors(openings)
    windows = get_windows(openings)
    
    for item in plan["furniture"]:
        asset_id = item["asset_id"]
        role = item.get("role", "general").lower()
        preferred_wall = item.get("preferred_wall", "none").lower()
        preferred_zone = item.get("preferred_zone", "general").lower()
        
        asset = db.query(FurnitureAsset).filter(FurnitureAsset.id == asset_id).first()
        if not asset or not is_asset_compatible_with_room(asset, room_type):
            continue
            
        best_wall, wall_rot = find_best_wall(room_width, room_length, openings)
        wall_name = preferred_wall.capitalize() if preferred_wall in ["north", "south", "west", "east"] else best_wall
        
        rot_map = {
            "North": 0.0,
            "South": math.pi,
            "West": math.pi / 2.0,
            "East": 3.0 * math.pi / 2.0
        }
        rot_y = rot_map.get(wall_name, 0.0)
        
        x = room_width / 2.0
        z = room_length / 2.0
        
        # Bed
        if "sleep" in role or "bed" in asset.name.lower():
            if wall_name == "North":
                x, z = room_width / 2.0, asset.depth / 2.0 + 15.0
            elif wall_name == "South":
                x, z = room_width / 2.0, room_length - asset.depth / 2.0 - 15.0
            elif wall_name == "West":
                x, z = asset.depth / 2.0 + 15.0, room_length / 2.0
            else:
                x, z = room_width - asset.depth / 2.0 - 15.0, room_length / 2.0
                
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Bedroom", "sleep", "primary_sleep")
            placements.append(instance)
            bed_instances.append(instance)
            
        # Stand
        elif "bedside" in role or "stand" in asset.name.lower():
            if bed_instances:
                bed = bed_instances[0]
                bx, bz, brot = bed["x"], bed["z"], bed["rotation"]
                offset_sign = -1.0 if placed_stands % 2 == 0 else 1.0
                offset_dist = (bed["width"] / 2.0 + asset.width / 2.0 + 10.0) * offset_sign
                
                if abs(brot) < 0.1 or abs(brot - math.pi) < 0.1:
                    x, z = bx + offset_dist, bz
                else:
                    x, z = bx, bz + offset_dist
                rot_y = brot
            else:
                x, z = room_width / 3.0, asset.depth / 2.0 + 15.0
                x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
                
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Bedroom", "sleep", "bedside")
            placements.append(instance)
            placed_stands += 1
            
        # Sofa
        elif "sofa" in role or "seating" in role or "sofa" in asset.name.lower():
            if wall_name == "North":
                x, z = room_width / 2.0, asset.depth / 2.0 + 20.0
            elif wall_name == "South":
                x, z = room_width / 2.0, room_length - asset.depth / 2.0 - 20.0
            elif wall_name == "West":
                x, z = asset.depth / 2.0 + 20.0, room_length / 2.0
            else:
                x, z = room_width - asset.depth / 2.0 - 20.0, room_length / 2.0
                
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Living Room", "seating", "sofa")
            placements.append(instance)
            sofa_instances.append(instance)
            
        # TV
        elif "tv" in role or "media" in asset.name.lower() or "console" in asset.name.lower():
            if sofa_instances:
                sofa = sofa_instances[0]
                sx, sz, srot = sofa["x"], sofa["z"], sofa["rotation"]
                if abs(srot) < 0.1:
                    x, z = sx, room_length - asset.depth / 2.0 - 20.0
                    rot_y = math.pi
                elif abs(srot - math.pi) < 0.1:
                    x, z = sx, asset.depth / 2.0 + 20.0
                    rot_y = 0.0
                elif abs(srot - math.pi / 2.0) < 0.1:
                    x, z = room_width - asset.depth / 2.0 - 20.0, sz
                    rot_y = 3.0 * math.pi / 2.0
                else:
                    x, z = asset.depth / 2.0 + 20.0, sz
                    rot_y = math.pi / 2.0
            else:
                x, z = room_width / 2.0, asset.depth / 2.0 + 20.0
                x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
                
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Living Room", "display", "tv_console")
            placements.append(instance)
            
        # Dining Table
        elif "dining_table" in role or "dining table" in asset.name.lower() or ("table" in asset.name.lower() and "dining" in room_type.lower() and "coffee" not in asset.name.lower()):
            tx, tz = clamp_to_bounds(room_width / 2.0, room_length / 2.0, asset.width, asset.depth, 0.0, room_width, room_length)
            instance = make_furniture_instance(asset, tx, 0.0, tz, 0.0, "Dining", "dining", "dining_table")
            placements.append(instance)

        # Dining Chair
        elif "dining_chair" in role or "dining chair" in asset.name.lower() or ("chair" in asset.name.lower() and "dining" in room_type.lower() and "office" not in asset.name.lower()):
            placed_chairs += 1
            if placed_chairs == 1:
                cx, cz, crot = room_width / 2.0, room_length / 2.0 - 110.0, 0.0
            elif placed_chairs == 2:
                cx, cz, crot = room_width / 2.0, room_length / 2.0 + 110.0, math.pi
            elif placed_chairs == 3:
                cx, cz, crot = room_width / 2.0 - 145.0, room_length / 2.0, math.pi / 2.0
            else:
                cx, cz, crot = room_width / 2.0 + 145.0, room_length / 2.0, 3.0 * math.pi / 2.0
            cx, cz = clamp_to_bounds(cx, cz, asset.width, asset.depth, crot, room_width, room_length)
            instance = make_furniture_instance(asset, cx, 0.0, cz, crot, "Dining", "dining", f"dining_chair_{placed_chairs}")
            placements.append(instance)

        # Kitchen Counter / Island
        elif "kitchen_counter" in role or "counter" in role or "counter" in asset.name.lower():
            x, z = asset.depth / 2.0 + 5.0, asset.width / 2.0 + 20.0
            rot_y = math.pi / 2.0
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Kitchen", "preparation", "kitchen_counter")
            placements.append(instance)

        # Kitchen Sink
        elif "sink" in role or "sink" in asset.name.lower() or "wash" in role:
            x, z = asset.depth / 2.0 + 5.0, 280.0
            rot_y = math.pi / 2.0
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Kitchen", "cleaning", "sink")
            placements.append(instance)

        # Kitchen Stove / Cooktop
        elif "stove" in role or "cook" in role or "stove" in asset.name.lower() or "oven" in asset.name.lower() or "range" in asset.name.lower():
            x, z = 65.0 + asset.width / 2.0 + 20.0, asset.depth / 2.0 + 5.0
            rot_y = 0.0
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Kitchen", "cooking", "stove")
            placements.append(instance)

        # Refrigerator
        elif "fridge" in role or "refrigerator" in role or "fridge" in asset.name.lower() or "refrigerator" in asset.name.lower():
            x, z = 65.0 + 80.0 + asset.width / 2.0 + 35.0, asset.depth / 2.0 + 5.0
            rot_y = 0.0
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Kitchen", "food_storage", "refrigerator")
            placements.append(instance)

        # Kitchen Cabinet / Pantry
        elif "kitchen_cabinet" in role or ("cabinet" in asset.name.lower() and "kitchen" in room_type.lower()):
            cx, cz = clamp_to_bounds(room_width - asset.depth / 2.0 - 5.0, room_length * 0.70, asset.width, asset.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            instance = make_furniture_instance(asset, cx, 0.0, cz, 3.0 * math.pi / 2.0, "Kitchen", "storage", "kitchen_cabinet")
            placements.append(instance)

        # Bathroom Vanity / Basin
        elif "vanity" in role or "basin" in role or "vanity" in asset.name.lower() or "basin" in asset.name.lower():
            if best_wall == "North":
                vx, vz = room_width / 2.0, asset.depth / 2.0 + 5.0
            elif best_wall == "South":
                vx, vz = room_width / 2.0, room_length - asset.depth / 2.0 - 5.0
            elif best_wall == "West":
                vx, vz = asset.depth / 2.0 + 5.0, room_length / 2.0
            else:
                vx, vz = room_width - asset.depth / 2.0 - 5.0, room_length / 2.0
            vx, vz = clamp_to_bounds(vx, vz, asset.width, asset.depth, wall_rot, room_width, room_length)
            instance = make_furniture_instance(asset, vx, 0.0, vz, wall_rot, "Bathroom", "washing", "vanity")
            placements.append(instance)

        # Desk
        elif "desk" in role or "desk" in asset.name.lower():
            is_office = any(k in room_type.lower() for k in ["office", "manager", "executive", "study", "work"])
            if is_office:
                rot_y = math.pi
                dx = room_width / 2.0
                dz = room_length * 0.40
                x, z = dx, dz
            else:
                x = asset.depth / 2.0 + 15.0
                z = room_length * 0.80
                rot_y = math.pi / 2.0
                        
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Office", "study", "desk")
            placements.append(instance)
            desk_instances.append(instance)
            
        # Chair (Manager Chair vs Visitor Chair vs Study Chair)
        elif "chair" in role or "chair" in asset.name.lower() or "visitor" in role:
            if "visitor" in role or "guest" in role or placed_chairs >= 1:
                if desk_instances:
                    desk = desk_instances[0]
                    dx, dz, drot = desk["x"], desk["z"], desk["rotation"]
                    v_dist = desk["depth"] / 2.0 + asset.depth / 2.0 + 35.0
                    v_spacing = min(60.0, max(42.0, desk["width"] * 0.28))
                    sign = -1.0 if placed_chairs % 2 == 1 else 1.0
                    lat_x = sign * v_spacing * math.cos(drot)
                    lat_z = sign * v_spacing * math.sin(drot)
                    x = dx + v_dist * math.sin(drot) + lat_x
                    z = dz - v_dist * math.cos(drot) + lat_z
                    rot_y = (drot + math.pi) % (2.0 * math.pi)
                else:
                    x, z = room_width / 2.0 + (50.0 if placed_chairs % 2 == 1 else -50.0), room_length * 0.65
                    rot_y = 0.0
                x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
                instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Office", "study", f"visitor_chair_{placed_chairs+1}")
                placements.append(instance)
                placed_chairs += 1
            else:
                # Manager / Task Chair (behind desk)
                if desk_instances:
                    desk = desk_instances[0]
                    dx, dz, drot = desk["x"], desk["z"], desk["rotation"]
                    mc_dist = desk["depth"] / 2.0 + asset.depth / 2.0 + 35.0
                    if abs(drot) < 0.1:
                        x, z = dx, dz + mc_dist
                    elif abs(drot - math.pi) < 0.1:
                        x, z = dx, dz - mc_dist
                    elif abs(drot - math.pi / 2.0) < 0.1:
                        x, z = dx + mc_dist, dz
                    else:
                        x, z = dx - mc_dist, dz
                    rot_y = drot
                else:
                    x, z = room_width / 2.0, room_length * 0.35
                    rot_y = 0.0
                x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
                instance = make_furniture_instance(asset, x, 0.0, z, rot_y, "Office", "study", "manager_chair")
                placements.append(instance)
                placed_chairs += 1

        # Bookshelf
        elif "bookshelf" in role or "book" in asset.name.lower() or "shelf" in asset.name.lower():
            shelf_z = room_length * 0.75
            bx = asset.depth / 2.0 + 5.0 if asset.width > asset.depth else asset.width / 2.0 + 5.0
            bx, bz = clamp_to_bounds(bx, shelf_z, asset.width, asset.depth, math.pi / 2.0, room_width, room_length)
            instance = make_furniture_instance(asset, bx, 0.0, bz, math.pi / 2.0, "Office", "storage", "bookshelf")
            placements.append(instance)

        # Cabinet / Sideboard
        elif "cabinet" in role or "sideboard" in role or "cabinet" in asset.name.lower() or "credenza" in asset.name.lower():
            cab_z = room_length * 0.75
            cx = room_width - asset.depth / 2.0 - 5.0
            cx, cz = clamp_to_bounds(cx, cab_z, asset.width, asset.depth, 3.0 * math.pi / 2.0, room_width, room_length)
            instance = make_furniture_instance(asset, cx, 0.0, cz, 3.0 * math.pi / 2.0, asset.category, "storage", "cabinet")
            placements.append(instance)

        # Wardrobe / Closet
        elif "wardrobe" in role or "closet" in role or "wardrobe" in asset.name.lower() or "closet" in asset.name.lower() or "armoire" in asset.name.lower() or "dresser" in asset.name.lower():
            if bed_instances:
                brot = bed_instances[0]["rotation"]
                if abs(brot) < 0.1: # Bed on North wall
                    w_rot = 3.0 * math.pi / 2.0
                    wx = room_width - asset.depth / 2.0 - 10.0
                    wz = room_length * 0.65
                elif abs(brot - math.pi) < 0.1: # Bed on South wall
                    w_rot = 3.0 * math.pi / 2.0
                    wx = room_width - asset.depth / 2.0 - 10.0
                    wz = room_length * 0.35
                elif abs(brot - math.pi / 2.0) < 0.1: # Bed on West wall
                    w_rot = 3.0 * math.pi / 2.0
                    wx = room_width - asset.depth / 2.0 - 10.0
                    wz = room_length * 0.35
                else: # Bed on East wall
                    w_rot = math.pi / 2.0
                    wx = asset.depth / 2.0 + 10.0
                    wz = room_length * 0.65
            else:
                w_rot = 3.0 * math.pi / 2.0
                wx = room_width - asset.depth / 2.0 - 10.0
                wz = room_length * 0.50
                
            wx, wz = clamp_to_bounds(wx, wz, asset.width, asset.depth, w_rot, room_width, room_length)
            if is_near_openings(wx, wz, asset.width, asset.depth, w_rot, openings):
                # Try opposite wall if near door or window
                alt_rot = math.pi / 2.0 if w_rot == 3.0 * math.pi / 2.0 else 3.0 * math.pi / 2.0
                alt_wx = asset.depth / 2.0 + 10.0 if alt_rot == math.pi / 2.0 else room_width - asset.depth / 2.0 - 10.0
                alt_wx, alt_wz = clamp_to_bounds(alt_wx, wz, asset.width, asset.depth, alt_rot, room_width, room_length)
                if not is_near_openings(alt_wx, alt_wz, asset.width, asset.depth, alt_rot, openings):
                    wx, wz, w_rot = alt_wx, alt_wz, alt_rot
                    
            instance = make_furniture_instance(asset, wx, 0.0, wz, w_rot, "Bedroom", "storage", "wardrobe")
            placements.append(instance)

        else:
            x, z = room_width * 0.8, room_length * 0.5
            x, z = clamp_to_bounds(x, z, asset.width, asset.depth, rot_y, room_width, room_length)
            instance = make_furniture_instance(asset, x, 0.0, z, rot_y, asset.category, preferred_zone, role)
            placements.append(instance)
            
    return placements

def validate_layout_geometry(
    room_width: float,
    room_length: float,
    room_type: str,
    placements: List[Dict[str, Any]],
    openings: List[Dict[str, Any]]
) -> None:
    from features.ai.exceptions import AIProcessingException
    from features.ai.geometry import get_furniture_obb, obb_overlap_sat, closest_point_on_obb
    
    # 1. Room boundary check
    for p in placements:
        obb = get_furniture_obb(p)
        corners = obb.get_corners()
        for cx, cz in corners:
            if cx < -1.0 or cx > room_width + 1.0 or cz < -1.0 or cz > room_length + 1.0:
                raise AIProcessingException(f"Furniture placement for '{p.get('name')}' is out of bounds.")
                
    # 2. Collision check
    obbs = [get_furniture_obb(p) for p in placements]
    for i in range(len(obbs)):
        o1 = obbs[i]
        for j in range(i + 1, len(obbs)):
            o2 = obbs[j]
            overlap, _, _ = obb_overlap_sat(o1, o2)
            if overlap:
                raise AIProcessingException(f"Collision detected between '{placements[i].get('name')}' and '{placements[j].get('name')}' in layout.")
                
    # 3. Door/Window swing check
    for op in openings:
        op_x = op.get('x', 0.0)
        op_z = op.get('y', 0.0)
        op_w = op.get('width', 80.0)
        op_type = op.get('type', 'door')
        
        for idx, p in enumerate(placements):
            obb = obbs[idx]
            gx, gz = closest_point_on_obb(obb, (op_x, op_z))
            dist = math.sqrt((gx - op_x)**2 + (gz - op_z)**2)
            if op_type == 'door' and dist < op_w:
                raise AIProcessingException(f"Furniture '{p.get('name')}' obstructs door clearance zone.")

def evaluate_design_quality(
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Evaluates layout against professional interior design criteria and functional completeness.
    """
    from features.ai.scoring import calculate_design_score
    scores = calculate_design_score(room_width, room_length, room_type, furniture, openings)
    
    zones = {}
    low_type = room_type.lower()
    names = [f.get('name', '').lower() for f in furniture]
    roles = [f.get('role', '').lower() for f in furniture]
    
    if 'kitchen' in low_type:
        has_prep = any('counter' in n or 'counter' in r or 'preparation' in r for n, r in zip(names, roles))
        has_clean = any('sink' in n or 'cleaning' in r for n, r in zip(names, roles))
        has_storage = any('fridge' in n or 'refrigerator' in n or 'food_storage' in r for n, r in zip(names, roles))
        has_cooking = any('stove' in n or 'cook' in n or 'cooking' in r for n, r in zip(names, roles))
        has_cabinet = any('cabinet' in n or 'pantry' in n or 'storage' in r for n, r in zip(names, roles))
        
        zones["preparation_zone"] = {"status": "Complete" if has_prep else "Missing", "score": 100 if has_prep else 0}
        zones["cleaning_zone"] = {"status": "Complete" if has_clean else "Missing", "score": 100 if has_clean else 0}
        zones["food_storage_zone"] = {"status": "Complete" if has_storage else "Missing", "score": 100 if has_storage else 0}
        zones["cooking_zone"] = {"status": "Complete" if has_cooking else "Optional", "score": 100 if has_cooking else 80}
        zones["cabinetry_storage"] = {"status": "Complete" if has_cabinet else "Optional", "score": 100 if has_cabinet else 70}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}

    elif 'dining' in low_type:
        has_table = any('table' in n or 'dining' in r for n, r in zip(names, roles))
        chair_count = sum(1 for n, r in zip(names, roles) if 'chair' in n or 'dining_chair' in r)
        has_sideboard = any('cabinet' in n or 'sideboard' in n or 'storage' in r for n, r in zip(names, roles))
        
        zones["dining_core"] = {"status": "Complete" if (has_table and chair_count >= 2) else "Incomplete", "score": 100 if (has_table and chair_count >= 2) else 30}
        zones["buffet_storage"] = {"status": "Complete" if has_sideboard else "Optional", "score": 100 if has_sideboard else 80}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}

    elif 'bathroom' in low_type or 'restroom' in low_type:
        has_vanity = any('vanity' in n or 'basin' in n or 'washing' in r for n, r in zip(names, roles))
        zones["grooming_zone"] = {"status": "Complete" if has_vanity else "Missing", "score": 100 if has_vanity else 0}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}

    elif any(k in low_type for k in ['office', 'manager', 'executive', 'study', 'work']):
        has_primary_work = any('desk' in n or 'desk' in r for n, r in zip(names, roles))
        has_exec_seating = any('manager' in n or 'exec' in n or 'chair' in n for n in names)
        has_visitor_seating = any('visitor' in n or 'guest' in n or 'visitor' in r for n, r in zip(names, roles))
        has_storage = any('cabinet' in n or 'shelf' in n or 'book' in n or 'storage' in r for n, r in zip(names, roles))
        
        zones["manager_workspace"] = {"status": "Complete" if (has_primary_work and has_exec_seating) else "Incomplete", "score": 100 if (has_primary_work and has_exec_seating) else 40}
        zones["visitor_meeting"] = {"status": "Complete" if has_visitor_seating else "Missing", "score": 100 if has_visitor_seating else 0}
        zones["document_storage"] = {"status": "Complete" if has_storage else "Missing", "score": 100 if has_storage else 30}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}
        
    elif 'bedroom' in low_type:
        has_bed = any('bed' in n or 'primary_sleep' in r for n, r in zip(names, roles))
        stand_count = sum(1 for n, r in zip(names, roles) if 'stand' in n or 'night' in n or 'bedside' in r)
        has_wardrobe = any('wardrobe' in n or 'closet' in n or 'armoire' in n or 'wardrobe' in r for n, r in zip(names, roles))
        has_desk = any('desk' in n or 'study' in n for n in names)
        
        zones["sleep_sanctuary"] = {"status": "Complete" if has_bed else "Missing", "score": 100 if has_bed else 0}
        zones["bedside_utility"] = {"status": "Complete" if stand_count >= 2 else ("Partial" if stand_count == 1 else "Missing"), "score": 100 if stand_count >= 2 else (80 if stand_count == 1 else 30)}
        zones["wardrobe_storage"] = {"status": "Complete" if has_wardrobe else "Missing", "score": 100 if has_wardrobe else 0}
        if (room_width * room_length) / 10000.0 >= 13.0:
            zones["study_work"] = {"status": "Complete" if has_desk else "Optional", "score": 100 if has_desk else 80}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}
        
    elif 'living' in low_type:
        has_sofa = any('sofa' in n or 'couch' in n for n in names)
        has_coffee = any('coffee' in n or 'table' in n for n in names)
        has_tv = any('tv' in n or 'media' in n for n in names)
        zones["conversation_core"] = {"status": "Complete" if (has_sofa and has_coffee) else "Partial", "score": 100 if (has_sofa and has_coffee) else 50}
        zones["media_entertainment"] = {"status": "Complete" if has_tv else "Optional", "score": 100 if has_tv else 60}
        zones["circulation_corridor"] = {"status": "Clear" if scores['details'].get('walkways_clear', True) else "Obstructed", "score": 100 if scores['details'].get('walkways_clear', True) else 30}

    walkway_coverage = scores['details'].get('walkway_coverage', 100.0)
    accessibility_rating = "Excellent" if scores['subscores']['accessibility'] >= 85 else ("Good" if scores['subscores']['accessibility'] >= 70 else "Needs Improvement")
    
    recommendations = []
    if scores['details'].get('collisions', 0) > 0:
        recommendations.append("Resolve overlapping furniture items to eliminate collisions.")
    if scores['details'].get('blocked_doors', 0) > 0:
        recommendations.append("Increase clearance around the door swing area.")
    if not scores['details'].get('walkways_clear', True):
        recommendations.append("Widen main circulation pathways by aligning storage flush against walls.")
    if not recommendations:
        recommendations.append("Layout satisfies all ergonomic, circulation, and functional interior design guidelines.")

    return {
        "overall_score": scores['overall_score'],
        "subscores": scores['subscores'],
        "functional_zones": zones,
        "circulation_rating": accessibility_rating,
        "walkway_clearance_percent": walkway_coverage,
        "recommendations": recommendations,
        "is_valid": (scores['details'].get('collisions', 0) == 0 and scores['details'].get('out_of_bounds', 0) == 0 and scores['details'].get('blocked_doors', 0) == 0 and scores['details'].get('walkways_clear', True))
    }

def refine_layout_with_prompt(
    db: Session,
    room_width: float,
    room_length: float,
    room_type: str,
    furniture: List[Dict[str, Any]],
    openings: List[Dict[str, Any]],
    command: str
) -> Tuple[List[Dict[str, Any]], str]:
    """
    Interprets natural language refinement requests and applies targeted spatial adjustments.
    """
    low_cmd = command.lower()
    refined = [f.copy() for f in furniture]
    explanation = "Layout refined based on user instructions."

    # 1. Open space / spaciousness
    if "open space" in low_cmd or "center" in low_cmd or "spacious" in low_cmd:
        for f in refined:
            f_name = f.get('name', '').lower()
            if any(k in f_name for k in ['cabinet', 'storage', 'bookshelf', 'shelf', 'wardrobe']):
                dist_w = f['x']
                dist_e = room_width - f['x']
                min_d = min(dist_w, dist_e)
                padding = 5.0
                if min_d == dist_w:
                    f['x'] = f.get('depth', 50.0) / 2.0 + padding if f.get('width', 100.0) > f.get('depth', 50.0) else f.get('width', 100.0) / 2.0 + padding
                    f['rotationY'] = math.pi / 2.0
                else:
                    f['x'] = room_width - (f.get('depth', 50.0) / 2.0 + padding if f.get('width', 100.0) > f.get('depth', 50.0) else f.get('width', 100.0) / 2.0 + padding)
                    f['rotationY'] = 3.0 * math.pi / 2.0
        explanation = "Re-aligned storage units flush to perimeter walls to open central circulation."

    # 2. Move cabinet to specific wall
    if "cabinet" in low_cmd or "storage" in low_cmd:
        target_cabinet = next((f for f in refined if 'cabinet' in f.get('name', '').lower() or 'storage' in f.get('name', '').lower()), None)
        if target_cabinet:
            if "right" in low_cmd or "east" in low_cmd:
                target_cabinet['x'] = room_width - (target_cabinet.get('depth', 50.0) / 2.0 + 5.0)
                target_cabinet['rotationY'] = 3.0 * math.pi / 2.0
                explanation = "Moved storage cabinet flush against the right (East) wall."
            elif "left" in low_cmd or "west" in low_cmd:
                target_cabinet['x'] = target_cabinet.get('depth', 50.0) / 2.0 + 5.0
                target_cabinet['rotationY'] = math.pi / 2.0
                explanation = "Moved storage cabinet flush against the left (West) wall."

    # 3. Arrange visitor chairs in front of desk
    if "visitor" in low_cmd and ("desk" in low_cmd or "front" in low_cmd or "arrange" in low_cmd):
        desk = next((f for f in refined if 'desk' in f.get('name', '').lower()), None)
        visitor_chairs = [f for f in refined if 'visitor' in f.get('name', '').lower() or 'visitor' in f.get('role', '').lower() or 'guest' in f.get('name', '').lower()]
        if desk and visitor_chairs:
            dx, dz, drot = desk['x'], desk['z'], desk.get('rotationY', 0.0)
            v_dist = desk.get('depth', 80.0) / 2.0 + visitor_chairs[0].get('depth', 60.0) / 2.0 + 35.0
            v_rot = (drot + math.pi) % (2.0 * math.pi)
            v_spacing = min(60.0, max(42.0, desk.get('width', 140.0) * 0.28))
            for idx, vc in enumerate(visitor_chairs[:2]):
                sign = -1.0 if idx == 0 else 1.0
                lat_x = sign * v_spacing * math.cos(drot)
                lat_z = sign * v_spacing * math.sin(drot)
                vc['x'] = dx + v_dist * math.sin(drot) + lat_x
                vc['z'] = dz - v_dist * math.cos(drot) + lat_z
                vc['rotationY'] = v_rot
            explanation = "Aligned visitor chairs in front of executive desk facing manager."

    # Resync bounding boxes
    for f in refined:
        f['rotation'] = f.get('rotationY', 0.0)
        f['bounding_box'] = {
            "center": [f['x'], f['z']],
            "width": f.get('width', 100.0),
            "depth": f.get('depth', 100.0),
            "rotation": f.get('rotationY', 0.0)
        }

    return refined, explanation


