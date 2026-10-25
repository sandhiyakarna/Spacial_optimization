import math
from typing import List, Dict, Any, Tuple

class WallDetector:
    @staticmethod
    def snap_coordinate(val: float, grid_size: float = 10.0) -> float:
        """
        Snaps a coordinate to the nearest grid step (default 10cm) to keep layout clean.
        """
        return float(round(val / grid_size) * grid_size)

    @classmethod
    def snap_walls_to_orthogonal(cls, corners: List[Tuple[float, float]], wall_thickness: float = 20.0) -> List[Dict[str, Any]]:
        """
        Snaps corners to form straight horizontal/vertical walls.
        Corners is a CCW list of points.
        """
        snapped_corners = []
        for pt in corners:
            snapped_corners.append((cls.snap_coordinate(pt[0]), cls.snap_coordinate(pt[1])))

        walls = []
        n = len(snapped_corners)
        for i in range(n):
            p1 = snapped_corners[i]
            p2 = snapped_corners[(i + 1) % n]
            
            # Snap to orthogonal axes (force horizontal or vertical)
            dx = abs(p2[0] - p1[0])
            dy = abs(p2[1] - p1[1])
            
            x1, y1 = p1
            x2, y2 = p2
            
            if dx > dy:
                y2 = y1 # make strictly horizontal
            else:
                x2 = x1 # make strictly vertical

            walls.append({
                "id": f"wall_{i + 1}",
                "x1": float(round(x1, 1)),
                "y1": float(round(y1, 1)),
                "x2": float(round(x2, 1)),
                "y2": float(round(y2, 1)),
                "thickness": float(wall_thickness)
            })
        return walls

    @classmethod
    def detect_boundaries(cls, room_width: float, room_depth: float, wall_thickness: float = 20.0) -> List[Dict[str, Any]]:
        """
        Fallback generator that constructs default closed room boundaries.
        """
        corners = [
            (0.0, 0.0),
            (room_width, 0.0),
            (room_width, room_depth),
            (0.0, room_depth)
        ]
        return cls.snap_walls_to_orthogonal(corners, wall_thickness)
