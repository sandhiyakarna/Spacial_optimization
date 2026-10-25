from typing import Dict, Any, Optional, Tuple

class DimensionEstimator:
    # Standard dimensions for reference calibration (in cm)
    STANDARD_DOOR_WIDTH = 90.0
    STANDARD_WINDOW_WIDTH = 120.0
    STANDARD_SOFA_WIDTH = 180.0
    STANDARD_SOFA_DEPTH = 85.0
    STANDARD_CEILING_HEIGHT = 280.0

    @classmethod
    def estimate_scale_factor(
        cls,
        ar_scale: Optional[float] = None,
        user_width: Optional[float] = None,
        user_depth: Optional[float] = None,
        detected_door_width_px: Optional[float] = None,
        estimated_room_width_px: Optional[float] = None
    ) -> Tuple[float, str, float]:
        """
        Determines the scale factor (pixels to cm) and confidence level based on hierarchy.
        Returns:
            - scale_factor: float (cm per pixel)
            - measurement_source: str
            - confidence: float (0.0 to 1.0)
        """
        # Hierarchy 1: AR/depth measurement
        if ar_scale is not None and ar_scale > 0:
            return ar_scale, "ar_measurement", 0.95
            
        # Hierarchy 2: User provided known dimension
        if user_width is not None and user_width > 0 and estimated_room_width_px is not None and estimated_room_width_px > 0:
            scale = user_width / estimated_room_width_px
            return scale, "user_input", 0.90
            
        # Hierarchy 3: Detected standard object (e.g. door width is 90cm)
        if detected_door_width_px is not None and detected_door_width_px > 0:
            scale = cls.STANDARD_DOOR_WIDTH / detected_door_width_px
            return scale, "detected_object", 0.70
            
        # Hierarchy 4: Visual estimation default
        # E.g. default scale maps estimated room pixels to standard 500cm width
        if estimated_room_width_px is not None and estimated_room_width_px > 0:
            scale = 500.0 / estimated_room_width_px
            return scale, "visual_estimation", 0.40
            
        # Hard fallback
        return 1.0, "visual_estimation", 0.30
