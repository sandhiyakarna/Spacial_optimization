import math
from typing import List, Dict, Any, Tuple

class OpeningDetector:
    @staticmethod
    def project_point_on_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> Tuple[float, float, float]:
        """
        Projects point P on segment AB.
        Returns projected (x, y) coordinates and progress t (0.0 to 1.0) along the segment.
        """
        abx = bx - ax
        aby = by - ay
        l2 = abx**2 + aby**2
        if l2 == 0:
            return ax, ay, 0.0
            
        t = ((px - ax) * abx + (py - ay) * aby) / l2
        t = max(0.0, min(1.0, t))
        proj_x = ax + t * abx
        proj_y = ay + t * aby
        return proj_x, proj_y, t

    @classmethod
    def detect_and_align_openings(
        cls,
        detected_openings: List[Dict[str, Any]],
        walls: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """
        Aligns each raw detected opening (door/window) to the closest wall segment.
        """
        aligned_openings = []
        for idx, op in enumerate(detected_openings):
            op_x = op.get("x", 0.0)
            op_y = op.get("y", 0.0)
            op_w = op.get("width", 90.0)
            op_type = op.get("type", "door")

            closest_wall_idx = 0
            min_dist = float("inf")
            best_x, best_y, best_angle = op_x, op_y, 0.0

            for w_idx, w in enumerate(walls):
                ax, ay = w["x1"], w["y1"]
                bx, by = w["x2"], w["y2"]
                
                proj_x, proj_y, _ = cls.project_point_on_segment(op_x, op_y, ax, ay, bx, by)
                dist = math.sqrt((op_x - proj_x)**2 + (op_y - proj_y)**2)
                
                if dist < min_dist:
                    min_dist = dist
                    closest_wall_idx = w_idx
                    best_x = proj_x
                    best_y = proj_y
                    best_angle = math.atan2(by - ay, bx - ax)

            aligned_openings.append({
                "id": op.get("id", f"opening_{op_type}_{idx + 1}"),
                "type": op_type,
                "x": float(round(best_x, 1)),
                "y": float(round(best_y, 1)),
                "width": float(round(op_w, 1)),
                "angle": float(round(best_angle, 4)),
                "swing": op.get("swing", "inward"),
                "clearance_area": op.get("clearance_area", op_w)
            })
            
        return aligned_openings
