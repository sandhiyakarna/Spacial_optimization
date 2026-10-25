import math
from typing import List, Dict, Any, Optional
from sqlalchemy.orm import Session
from features.furniture.models import FurnitureAsset

class FurnitureDetector:
    @staticmethod
    def match_existing_asset(db: Session, category: str, width: float, depth: float, height: float) -> Optional[FurnitureAsset]:
        """
        Queries the database for a FurnitureAsset that matches the detected category and dimensions.
        Selects the asset with the closest volume or dimensions.
        """
        assets = db.query(FurnitureAsset).all()
        if not assets:
            return None

        # Filter by category matching
        cat_lower = category.lower()
        matched_cat_assets = []
        for asset in assets:
            a_cat = asset.category.lower()
            a_name = asset.name.lower()
            if cat_lower in a_cat or a_cat in cat_lower or cat_lower in a_name:
                matched_cat_assets.append(asset)

        # Fallback to all assets if no category matches
        candidates = matched_cat_assets if matched_cat_assets else assets

        # Find closest by dimension diff: delta = abs(w - aw) + abs(d - ad) + abs(h - ah)
        best_match = None
        min_diff = float("inf")
        for asset in candidates:
            diff = abs(asset.width - width) + abs(asset.depth - depth) + abs(asset.height - height)
            if diff < min_diff:
                min_diff = diff
                best_match = asset

        return best_match

    @classmethod
    def detect_and_resolve_furniture(
        cls,
        db: Session,
        detected_items: List[Dict[str, Any]],
        room_width: float,
        room_depth: float
    ) -> List[Dict[str, Any]]:
        """
        Processes detected items, resolves them against database assets,
        and translates coordinates to room-relative centimeters.
        """
        resolved_furniture = []
        for idx, item in enumerate(detected_items):
            cat = item.get("category", "sofa")
            w = item.get("width_cm", 180.0)
            d = item.get("depth_cm", 80.0)
            h = item.get("height_cm", 85.0)
            x = item.get("x", room_width / 2.0)
            z = item.get("z", room_depth / 2.0)
            rot = item.get("rotation_deg", 0.0)
            conf = item.get("confidence", 0.90)

            # Snap coordinates to keep them neat
            x = float(round(x / 5.0) * 5.0)
            z = float(round(z / 5.0) * 5.0)

            # Query database
            db_asset = cls.match_existing_asset(db, cat, w, d, h)
            
            asset_id = db_asset.id if db_asset else f"MOCK_ASSET_{cat.upper()}"
            name = db_asset.name if db_asset else f"Detected {cat.capitalize()}"
            resolved_w = db_asset.width if db_asset else w
            resolved_d = db_asset.depth if db_asset else d
            resolved_h = db_asset.height if db_asset else h

            resolved_furniture.append({
                "id": item.get("id", f"placed_furniture_{idx + 1}"),
                "assetId": asset_id,
                "name": name,
                "category": cat,
                "x": float(x),
                "y": 0.0,
                "z": float(z),
                "width": float(resolved_w),
                "depth": float(resolved_d),
                "height": float(resolved_h),
                "rotationX": 0.0,
                "rotationY": float(round(rot * math.pi / 180.0, 4)),
                "rotationZ": 0.0,
                "opacity": 1.0,
                "isVisible": True,
                "isLocked": False,
                "confidence": float(conf)
            })

        return resolved_furniture
