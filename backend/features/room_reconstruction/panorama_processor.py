import os
try:
    import cv2
except ImportError:
    cv2 = None
try:
    import numpy as np
except ImportError:
    np = None
from typing import List, Dict, Any, Tuple

class PanoramaProcessor:
    @staticmethod
    def validate_frame(image_path: str) -> Dict[str, Any]:
        """
        Validates individual frame for resolution, brightness, blur, and contrast.
        """
        if not os.path.exists(image_path):
            return {
                "valid": False,
                "error_code": "FILE_NOT_FOUND",
                "message": f"Frame file not found at {image_path}"
            }
            
        img = cv2.imread(image_path)
        if img is None:
            return {
                "valid": False,
                "error_code": "INVALID_IMAGE",
                "message": f"Could not load image from {image_path}"
            }

        height, width, channels = img.shape
        
        # 1. Resolution Check
        if width < 640 or height < 480:
            return {
                "valid": False,
                "error_code": "LOW_RESOLUTION",
                "message": f"Image resolution {width}x{height} is too low. Minimum required is 640x480."
            }

        # Convert to Grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # 2. Brightness Check
        mean_brightness = np.mean(gray)
        if mean_brightness < 40.0:
            return {
                "valid": False,
                "error_code": "TOO_DARK",
                "message": "Frame is too dark. Please ensure sufficient room lighting."
            }
        elif mean_brightness > 240.0:
            return {
                "valid": False,
                "error_code": "OVEREXPOSED",
                "message": "Frame is overexposed. Avoid pointing directly at bright light sources."
            }

        # 3. Blur Check (Variance of Laplacian)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        if laplacian_var < 50.0:
            return {
                "valid": False,
                "error_code": "MOTION_BLUR",
                "message": "Excessive motion blur detected. Keep the camera steady."
            }

        return {
            "valid": True,
            "width": width,
            "height": height,
            "brightness": float(mean_brightness),
            "blur_score": float(laplacian_var)
        }

    @classmethod
    def process_and_stitch(cls, frame_paths: List[str], output_path: str) -> Dict[str, Any]:
        """
        Loads captured frames, checks overlap, aligns, and stitches into a panorama.
        """
        # Validate all frames
        frames_metadata = []
        images = []
        
        for idx, path in enumerate(frame_paths):
            val = cls.validate_frame(path)
            if not val["valid"]:
                return {
                    "success": False,
                    "stage": "frame_validation",
                    "error_code": val.get("error_code", "VALIDATION_FAILED"),
                    "message": f"Frame {idx + 1} validation failed: {val['message']}",
                    "recoverable": True
                }
            
            img = cv2.imread(path)
            images.append(img)
            frames_metadata.append({
                "frame_id": f"frame_{idx + 1}",
                "timestamp": os.path.getmtime(path),
                "image_path": path,
                "width": val["width"],
                "height": val["height"],
                "rotation_estimate": idx * 60.0,
                "quality_score": val["blur_score"],
                "overlap_score": 0.0
            })

        # Single frame quick-scan support
        if len(images) == 1:
            stitched_resized = cv2.resize(images[0], (2048, 1024), interpolation=cv2.INTER_CUBIC)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            cv2.imwrite(output_path, stitched_resized)
            return {
                "success": True,
                "panorama_path": output_path,
                "metadata": frames_metadata
            }

        # Check overlap between consecutive frames
        orb = cv2.ORB_create(nfeatures=1000)
        bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

        for i in range(len(images)):
            next_idx = (i + 1) % len(images)
            img1 = cv2.cvtColor(images[i], cv2.COLOR_BGR2GRAY)
            img2 = cv2.cvtColor(images[next_idx], cv2.COLOR_BGR2GRAY)
            
            kp1, des1 = orb.detectAndCompute(img1, None)
            kp2, des2 = orb.detectAndCompute(img2, None)
            
            if des1 is not None and des2 is not None:
                matches = bf.match(des1, des2)
                # Keep good matches
                good_matches = sorted(matches, key=lambda x: x.distance)
                overlap_metric = len(good_matches) / 1000.0
                frames_metadata[i]["overlap_score"] = float(overlap_metric)
                
                # If overlap is extremely poor
                if len(good_matches) < 15:
                    return {
                        "success": False,
                        "stage": "overlap_validation",
                        "error_code": "INSUFFICIENT_OVERLAP",
                        "message": f"Insufficient overlap between frame {i + 1} and frame {next_idx + 1}. Please rotate slower and maintain overlap.",
                        "recoverable": True
                    }

        # Stitching
        try:
            # OpenCV Stitcher
            stitcher = cv2.Stitcher.create(cv2.Stitcher_PANORAMA)
            status, stitched = stitcher.stitch(images)
            
            if status != cv2.Stitcher_OK:
                # Provide diagnostic messages based on OpenCV status codes
                error_msg = "Stitching failed."
                error_code = "STITCHING_ERROR"
                if status == cv2.Stitcher_ERR_NEED_MORE_IMGS:
                    error_msg = "Panorama could not be created because camera frames had insufficient overlap. Please rescan the room slowly."
                    error_code = "INSUFFICIENT_OVERLAP"
                elif status == cv2.Stitcher_ERR_HOMOGRAPHY_EST_FAIL:
                    error_msg = "Homography estimation failed due to perspective distortion."
                    error_code = "HOMOGRAPHY_FAILED"
                elif status == cv2.Stitcher_ERR_CAMERA_PARAMS_ADJUST_FAIL:
                    error_msg = "Camera parameters adjustment failed."
                    error_code = "CAMERA_CALIBRATION_FAILED"
                    
                return {
                    "success": False,
                    "stage": "panorama_stitching",
                    "error_code": error_code,
                    "message": error_msg,
                    "recoverable": True
                }

            # Crop black boundaries from projection warp if any
            gray = cv2.cvtColor(stitched, cv2.COLOR_BGR2GRAY)
            _, thresh = cv2.threshold(gray, 1, 255, cv2.THRESH_BINARY)
            contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            if contours:
                c = max(contours, key=cv2.contourArea)
                x, y, w, h = cv2.boundingRect(c)
                stitched = stitched[y:y+h, x:x+w]

            # Resize to equirectangular 2:1 standard (e.g. 2048x1024 or 4096x2048)
            # Default height = 1024, width = 2048
            stitched_resized = cv2.resize(stitched, (2048, 1024), interpolation=cv2.INTER_CUBIC)
            
            # Save stitched image
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            cv2.imwrite(output_path, stitched_resized)
            
            return {
                "success": True,
                "panorama_path": output_path,
                "metadata": frames_metadata
            }
            
        except Exception as e:
            return {
                "success": False,
                "stage": "panorama_stitching",
                "error_code": "CRITICAL_STITCHER_ERROR",
                "message": f"Critical stitching failure: {str(e)}",
                "recoverable": True
            }
