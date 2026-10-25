import math
import json
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field

class DimensionsModel(BaseModel):
    width_cm: float
    depth_cm: float
    height_cm: float
    confidence: float = 1.0
    measurement_source: str = "visual_estimation" # "ar_measurement", "user_input", "detected_object", "visual_estimation"

class WallModel(BaseModel):
    id: str
    start: List[float] # [x, y]
    end: List[float]   # [x, y]
    length_cm: float
    thickness_cm: float = 20.0
    orientation: str   # "north", "south", "east", "west"

class DoorModel(BaseModel):
    id: str
    wall_id: str
    position_cm: float
    width_cm: float = 90.0
    swing: str = "inward" # "inward", "outward"
    clearance_area: float = 90.0

class WindowModel(BaseModel):
    id: str
    wall_id: str
    position_cm: float
    width_cm: float = 120.0
    height_cm: float = 120.0
    sill_height_cm: float = 90.0

class FurniturePosition(BaseModel):
    x_cm: float
    y_cm: float

class FurnitureDimensions(BaseModel):
    width_cm: float
    depth_cm: float
    height_cm: float

class FurnitureModel(BaseModel):
    id: str
    asset_id: str
    name: str
    category: str
    position: FurniturePosition
    dimensions: FurnitureDimensions
    rotation_deg: float
    confidence: float = 1.0

class RoomSpatialModel(BaseModel):
    room_id: str
    dimensions: DimensionsModel
    walls: List[WallModel] = []
    doors: List[DoorModel] = []
    windows: List[WindowModel] = []
    furniture: List[FurnitureModel] = []


def convert_db_properties_to_spatial_model(room_id: str, measurements: Any, properties_json: Optional[str]) -> RoomSpatialModel:
    """
    Parses properties JSON and DB measurements to reconstruct the unified RoomSpatialModel.
    """
    width_cm = measurements.length if measurements else 600.0
    depth_cm = measurements.width if measurements else 450.0
    height_cm = measurements.height if measurements else 300.0
    wall_thickness = measurements.wall_thickness if measurements else 20.0

    # Parse properties
    props = {}
    if properties_json:
        try:
            props = json.loads(properties_json) if isinstance(properties_json, str) else properties_json
        except Exception:
            pass

    # Extract metadata confidence if any
    metadata = props.get("ai_layout_metadata", {})
    performance = metadata.get("performance", {})
    confidence_val = 1.0 if performance else 0.5
    source = "user_input" if measurements else "visual_estimation"
    
    # Check if panorama metadata exists to raise confidence/source
    pano_meta = props.get("panorama_metadata", {})
    if pano_meta:
        confidence_val = pano_meta.get("confidence", 0.85)
        source = pano_meta.get("measurement_source", "visual_estimation")

    dimensions = DimensionsModel(
        width_cm=width_cm,
        depth_cm=depth_cm,
        height_cm=height_cm,
        confidence=confidence_val,
        measurement_source=source
    )

    walls: List[WallModel] = []
    db_walls = props.get("walls", [])
    for idx, w in enumerate(db_walls):
        w_id = w.get("id", f"wall_{idx + 1}")
        x1, y1 = w.get("x1", 0.0), w.get("y1", 0.0)
        x2, y2 = w.get("x2", 0.0), w.get("y2", 0.0)
        length = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
        
        # Determine orientation
        orient = "north"
        dx = abs(x2 - x1)
        dy = abs(y2 - y1)
        if dx > dy:
            orient = "north" if min(y1, y2) < depth_cm / 2.0 else "south"
        else:
            orient = "west" if min(x1, x2) < width_cm / 2.0 else "east"

        walls.append(WallModel(
            id=w_id,
            start=[x1, y1],
            end=[x2, y2],
            length_cm=round(length, 1),
            thickness_cm=w.get("thickness", wall_thickness),
            orientation=orient
        ))

    doors: List[DoorModel] = []
    windows: List[WindowModel] = []
    
    db_openings = props.get("openings", [])
    for idx, op in enumerate(db_openings):
        op_id = op.get("id", f"opening_{idx + 1}")
        op_type = op.get("type", "door")
        op_x, op_y = op.get("x", 0.0), op.get("y", 0.0)
        op_w = op.get("width", 90.0)
        
        # Find closest wall to associate
        closest_wall_id = "wall_1"
        min_dist = float("inf")
        position_along = 0.0
        
        for w in walls:
            # Vector math to project point on line segment
            ax, ay = w.start
            bx, by = w.end
            abx = bx - ax
            aby = by - ay
            l2 = abx**2 + aby**2
            if l2 == 0:
                continue
            
            # projection t
            t = ((op_x - ax) * abx + (op_y - ay) * aby) / l2
            t = max(0.0, min(1.0, t))
            proj_x = ax + t * abx
            proj_y = ay + t * aby
            dist = math.sqrt((op_x - proj_x)**2 + (op_y - proj_y)**2)
            
            if dist < min_dist:
                min_dist = dist
                closest_wall_id = w.id
                position_along = t * w.length_cm

        if op_type == "door":
            doors.append(DoorModel(
                id=op_id,
                wall_id=closest_wall_id,
                position_cm=round(position_along, 1),
                width_cm=op_w,
                swing=op.get("swing", "inward"),
                clearance_area=op.get("clearance_area", op_w)
            ))
        else:
            windows.append(WindowModel(
                id=op_id,
                wall_id=closest_wall_id,
                position_cm=round(position_along, 1),
                width_cm=op_w,
                height_cm=op.get("height", 120.0),
                sill_height_cm=op.get("sill_height", 90.0)
            ))

    furniture: List[FurnitureModel] = []
    db_furn = props.get("furniture", [])
    for f in db_furn:
        rot_deg = round((f.get("rotationY", 0.0) * 180.0 / math.pi) % 360.0, 1)
        furniture.append(FurnitureModel(
            id=f.get("id"),
            asset_id=f.get("assetId"),
            name=f.get("name", "Furniture"),
            category=f.get("category", "General"),
            position=FurniturePosition(x_cm=f.get("x", 0.0), y_cm=f.get("z", 0.0)),
            dimensions=FurnitureDimensions(
                width_cm=f.get("width", 100.0),
                depth_cm=f.get("depth", 100.0),
                height_cm=f.get("height", 75.0)
            ),
            rotation_deg=rot_deg,
            confidence=f.get("confidence", 1.0)
        ))

    return RoomSpatialModel(
        room_id=room_id,
        dimensions=dimensions,
        walls=walls,
        doors=doors,
        windows=windows,
        furniture=furniture
    )


def convert_spatial_model_to_db_properties(model: RoomSpatialModel, existing_props: Optional[str] = None) -> str:
    """
    Serializes a RoomSpatialModel back to the database-compatible properties JSON layout format.
    """
    import json
    
    props = {}
    if existing_props:
        try:
            props = json.loads(existing_props) if isinstance(existing_props, str) else existing_props
        except Exception:
            pass

    # Update walls
    db_walls = []
    for w in model.walls:
        db_walls.append({
            "id": w.id,
            "x1": w.start[0],
            "y1": w.start[1],
            "x2": w.end[0],
            "y2": w.end[1],
            "thickness": w.thickness_cm
        })
    props["walls"] = db_walls

    # Update openings (doors + windows)
    db_openings = []
    wall_map = {w.id: w for w in model.walls}

    for d in model.doors:
        x, y, angle = 0.0, 0.0, 0.0
        if d.wall_id in wall_map:
            w = wall_map[d.wall_id]
            # Interpolate position along wall line
            ax, ay = w.start
            bx, by = w.end
            w_len = w.length_cm
            t = d.position_cm / w_len if w_len > 0 else 0.0
            x = ax + t * (bx - ax)
            y = ay + t * (by - ay)
            angle = math.atan2(by - ay, bx - ax)

        db_openings.append({
            "id": d.id,
            "type": "door",
            "x": round(x, 1),
            "y": round(y, 1),
            "width": d.width_cm,
            "angle": round(angle, 4),
            "swing": d.swing,
            "clearance_area": d.clearance_area
        })

    for win in model.windows:
        x, y, angle = 0.0, 0.0, 0.0
        if win.wall_id in wall_map:
            w = wall_map[win.wall_id]
            # Interpolate position
            ax, ay = w.start
            bx, by = w.end
            w_len = w.length_cm
            t = win.position_cm / w_len if w_len > 0 else 0.0
            x = ax + t * (bx - ax)
            y = ay + t * (by - ay)
            angle = math.atan2(by - ay, bx - ax)

        db_openings.append({
            "id": win.id,
            "type": "window",
            "x": round(x, 1),
            "y": round(y, 1),
            "width": win.width_cm,
            "height": win.height_cm,
            "sill_height": win.sill_height_cm,
            "angle": round(angle, 4)
        })
    props["openings"] = db_openings

    # Update furniture
    db_furn = []
    for f in model.furniture:
        rot_rad = round((f.rotation_deg * math.pi / 180.0), 4)
        db_furn.append({
            "id": f.id,
            "assetId": f.asset_id,
            "name": f.name,
            "category": f.category,
            "x": f.position.x_cm,
            "y": 0.0,
            "z": f.position.y_cm,
            "width": f.dimensions.width_cm,
            "depth": f.dimensions.depth_cm,
            "height": f.dimensions.height_cm,
            "rotationX": 0.0,
            "rotationY": rot_rad,
            "rotationZ": 0.0,
            "scaleX": 1.0,
            "scaleY": 1.0,
            "scaleZ": 1.0,
            "opacity": 1.0,
            "isVisible": True,
            "isLocked": False,
            "confidence": f.confidence
        })
    props["furniture"] = db_furn

    # Save scale/panorama metadata
    props["panorama_metadata"] = {
        "confidence": model.dimensions.confidence,
        "measurement_source": model.dimensions.measurement_source
    }

    return json.dumps(props)
