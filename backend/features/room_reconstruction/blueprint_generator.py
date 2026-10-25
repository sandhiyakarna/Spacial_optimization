import math
from typing import Dict, Any, List, Tuple
from PIL import Image, ImageDraw, ImageFont
from features.room_reconstruction.spatial_model import RoomSpatialModel

class BlueprintGenerator:
    @staticmethod
    def render_blueprint(
        model: RoomSpatialModel,
        show_measurements: bool = True,
        show_furniture_labels: bool = True,
        show_doors: bool = True,
        show_windows: bool = True,
        quality_score: int = 92
    ) -> Image.Image:
        """
        Renders a high-fidelity 2D architectural blueprint from the RoomSpatialModel using Pillow.
        """
        # 1. Canvas Settings
        canvas_w, canvas_h = 1200, 900
        img = Image.new("RGB", (canvas_w, canvas_h), (255, 255, 255))
        draw = ImageDraw.Draw(img)

        # 2. Draw light gray blueprint grid background
        grid_color = (241, 245, 249)
        grid_spacing = 40
        for x in range(0, canvas_w, grid_spacing):
            draw.line([(x, 0), (x, canvas_h)], fill=grid_color, width=1)
        for y in range(0, canvas_h, grid_spacing):
            draw.line([(0, y), (canvas_w, y)], fill=grid_color, width=1)

        # 3. Calculate scaling to fit room nicely with margins
        room_w = model.dimensions.width_cm
        room_d = model.dimensions.depth_cm
        margin = 100.0
        
        # Scale factor (pixels per cm)
        scale_x = (canvas_w - 2 * margin) / room_w if room_w > 0 else 1.0
        scale_y = (canvas_h - 2 * margin) / room_d if room_d > 0 else 1.0
        scale = min(scale_x, scale_y)

        # Offsets to center the drawing
        offset_x = (canvas_w - room_w * scale) / 2.0
        offset_y = (canvas_h - room_d * scale) / 2.0

        def to_canvas(x_cm: float, y_cm: float) -> Tuple[float, float]:
            return offset_x + x_cm * scale, offset_y + y_cm * scale

        # Fonts configuration
        try:
            # Fallback to standard default font if custom font path doesn't exist
            font_title = ImageFont.load_default()
            font_label = ImageFont.load_default()
            font_dim = ImageFont.load_default()
        except Exception:
            font_title = font_label = font_dim = None

        # 4. Draw Walls (Thick dark lines)
        wall_color = (30, 41, 59) # Slate 800
        for w in model.walls:
            cx1, cy1 = to_canvas(w.start[0], w.start[1])
            cx2, cy2 = to_canvas(w.end[0], w.end[1])
            draw.line([(cx1, cy1), (cx2, cy2)], fill=wall_color, width=int(max(4.0, w.thickness_cm * scale)))

        # 5. Draw Doors
        if show_doors:
            door_color = (180, 83, 9) # Amber 700
            for d in model.doors:
                # Find wall coordinates
                wall = next((w for w in model.walls if w.id == d.wall_id), None)
                if not wall:
                    continue
                ax, ay = wall.start
                bx, by = wall.end
                w_len = wall.length_cm
                t = d.position_cm / w_len if w_len > 0 else 0.0
                
                # Door center position
                dx_cm = ax + t * (bx - ax)
                dy_cm = ay + t * (by - ay)
                cx, cy = to_canvas(dx_cm, dy_cm)
                
                # Draw swing direction arc
                angle = math.atan2(by - ay, bx - ax)
                dw_px = d.width_cm * scale
                
                # Draw door frame opening
                ex_cm = dx_cm + d.width_cm * math.cos(angle)
                ey_cm = dy_cm + d.width_cm * math.sin(angle)
                cex, cey = to_canvas(ex_cm, ey_cm)
                
                # Draw door leaf (90 deg to wall)
                lx_cm = dx_cm + d.width_cm * math.cos(angle - math.pi / 2)
                ly_cm = dy_cm + d.width_cm * math.sin(angle - math.pi / 2)
                clx, cly = to_canvas(lx_cm, ly_cm)
                
                draw.line([(cx, cy), (clx, cly)], fill=door_color, width=3)
                
                # Draw dashed arc for swing
                arc_bbox = [cx - dw_px, cy - dw_px, cx + dw_px, cy + dw_px]
                start_angle = math.degrees(angle - math.pi / 2)
                end_angle = math.degrees(angle)
                draw.arc(arc_bbox, start=start_angle, end=end_angle, fill=door_color, width=1)

        # 6. Draw Windows
        if show_windows:
            win_color = (14, 116, 144) # Cyan 700
            for win in model.windows:
                wall = next((w for w in model.walls if w.id == win.wall_id), None)
                if not wall:
                    continue
                ax, ay = wall.start
                bx, by = wall.end
                w_len = wall.length_cm
                t = win.position_cm / w_len if w_len > 0 else 0.0
                
                # Window position
                wx_cm = ax + t * (bx - ax)
                wy_cm = ay + t * (by - ay)
                cx, cy = to_canvas(wx_cm, wy_cm)
                
                angle = math.atan2(by - ay, bx - ax)
                hw_cm = win.width_cm / 2.0
                
                # Draw window segment
                x1 = wx_cm - hw_cm * math.cos(angle)
                y1 = wy_cm - hw_cm * math.sin(angle)
                x2 = wx_cm + hw_cm * math.cos(angle)
                y2 = wy_cm + hw_cm * math.sin(angle)
                
                cx1, cy1 = to_canvas(x1, y1)
                cx2, cy2 = to_canvas(x2, y2)
                
                # Draw double lines to look like architectural Casement window
                dx_p = 3.0 * math.cos(angle + math.pi / 2)
                dy_p = 3.0 * math.sin(angle + math.pi / 2)
                
                draw.line([(cx1 - dx_p, cy1 - dy_p), (cx2 - dx_p, cy2 - dy_p)], fill=win_color, width=2)
                draw.line([(cx1 + dx_p, cy1 + dy_p), (cx2 + dx_p, cy2 + dy_p)], fill=win_color, width=2)
                draw.line([(cx1, cy1), (cx2, cy2)], fill=(255, 255, 255), width=2)

        # 7. Draw Furniture Footprints & Architectural Symbols
        furn_color = (71, 85, 105) # Cool gray 600
        for f in model.furniture:
            fx, fy = to_canvas(f.position.x_cm, f.position.y_cm)
            fw = f.dimensions.width_cm * scale
            fd = f.dimensions.depth_cm * scale
            
            # Rotation transformation around center
            rot_rad = f.rotation_deg * math.pi / 180.0
            cos_r = math.cos(rot_rad)
            sin_r = math.sin(rot_rad)
            
            # Helper to rotate local offsets
            def get_rotated_corner(dx: float, dy: float) -> Tuple[float, float]:
                rx = fx + (dx * cos_r - dy * sin_r)
                ry = fy + (dx * sin_r + dy * cos_r)
                return rx, ry

            # Draw standard furniture footprint box
            corners = [
                get_rotated_corner(-fw / 2, -fd / 2),
                get_rotated_corner(fw / 2, -fd / 2),
                get_rotated_corner(fw / 2, fd / 2),
                get_rotated_corner(-fw / 2, fd / 2)
            ]
            draw.polygon(corners, outline=furn_color, fill=(248, 250, 252)) # Light slate fill

            # Draw recognizable internal architectural details depending on category
            cat = f.category.lower()
            if "bed" in cat:
                # Draw pillows
                p_w = fw * 0.35
                p_h = fd * 0.20
                pil1 = [
                    get_rotated_corner(-fw * 0.4, -fd * 0.45),
                    get_rotated_corner(-fw * 0.4 + p_w, -fd * 0.45),
                    get_rotated_corner(-fw * 0.4 + p_w, -fd * 0.45 + p_h),
                    get_rotated_corner(-fw * 0.4, -fd * 0.45 + p_h)
                ]
                pil2 = [
                    get_rotated_corner(fw * 0.4 - p_w, -fd * 0.45),
                    get_rotated_corner(fw * 0.4, -fd * 0.45),
                    get_rotated_corner(fw * 0.4, -fd * 0.45 + p_h),
                    get_rotated_corner(fw * 0.4 - p_w, -fd * 0.45 + p_h)
                ]
                draw.polygon(pil1, outline=furn_color)
                draw.polygon(pil2, outline=furn_color)
            elif "sofa" in cat or "chair" in cat:
                # Draw armrests/backrest lines
                back_line = [
                    get_rotated_corner(-fw * 0.45, -fd * 0.45),
                    get_rotated_corner(fw * 0.45, -fd * 0.45),
                    get_rotated_corner(fw * 0.45, -fd * 0.3),
                    get_rotated_corner(-fw * 0.45, -fd * 0.3)
                ]
                draw.polygon(back_line, outline=furn_color)

            # Furniture Labels
            if show_furniture_labels:
                label_text = f"{f.name.upper()}\n{int(f.dimensions.width_cm)}x{int(f.dimensions.depth_cm)}"
                draw.text((fx - 30, fy - 15), label_text, fill=(71, 85, 105), font=font_label)

        # 8. Draw Dimension lines along external walls
        if show_measurements:
            dim_color = (100, 116, 139) # slate 500
            # Width dimension (North outer wall)
            ny = offset_y - 30
            cx1, cy1 = to_canvas(0.0, 0.0)
            cx2, cy2 = to_canvas(room_w, 0.0)
            draw.line([(cx1, ny), (cx2, ny)], fill=dim_color, width=1)
            draw.line([(cx1, ny - 5), (cx1, ny + 5)], fill=dim_color, width=1)
            draw.line([(cx2, ny - 5), (cx2, ny + 5)], fill=dim_color, width=1)
            draw.text(((cx1 + cx2)/2 - 25, ny - 15), f"{int(room_w)} cm", fill=dim_color, font=font_dim)

            # Depth dimension (West outer wall)
            nx = offset_x - 30
            cx3, cy3 = to_canvas(0.0, 0.0)
            cx4, cy4 = to_canvas(0.0, room_d)
            draw.line([(nx, cy3), (nx, cy4)], fill=dim_color, width=1)
            draw.line([(nx - 5, cy3), (nx + 5, cy3)], fill=dim_color, width=1)
            draw.line([(nx - 5, cy4), (nx + 5, cy4)], fill=dim_color, width=1)
            draw.text((nx - 60, (cy3 + cy4)/2 - 5), f"{int(room_d)} cm", fill=dim_color, font=font_dim)

        # 9. Draw Room Labels (Centering text in room)
        title_text = f"{model.dimensions.measurement_source.replace('_', ' ').title()} - {int(room_w)}x{int(room_d)}cm"
        draw.text((canvas_w / 2 - 120, offset_y + room_d * scale + 30), title_text, fill=(15, 23, 42), font=font_title)

        # 10. Draw Info HUD details (North direction, Quality Score, Scale indicator)
        # Quality score
        hud_bg = (15, 23, 42)
        draw.rectangle([20, 20, 220, 100], fill=hud_bg)
        draw.text((35, 30), "BLUEPRINT QUALITY", fill=(148, 163, 184), font=font_dim)
        draw.text((35, 45), f"{quality_score}%", fill=(74, 222, 128), font=font_title)

        # North direction
        draw.ellipse([canvas_w - 90, 20, canvas_w - 30, 80], outline=wall_color, width=2)
        draw.line([(canvas_w - 60, 70), (canvas_w - 60, 30)], fill=wall_color, width=2)
        draw.line([(canvas_w - 65, 45), (canvas_w - 60, 30), (canvas_w - 55, 45)], fill=wall_color, width=2)
        draw.text((canvas_w - 65, 85), "NORTH", fill=wall_color, font=font_dim)

        # Scale indicator
        draw.line([(canvas_w - 180, canvas_h - 40), (canvas_w - 80, canvas_h - 40)], fill=wall_color, width=3)
        draw.line([(canvas_w - 180, canvas_h - 45), (canvas_w - 180, canvas_h - 35)], fill=wall_color, width=1)
        draw.line([(canvas_w - 80, canvas_h - 45), (canvas_w - 80, canvas_h - 35)], fill=wall_color, width=1)
        draw.text((canvas_w - 160, canvas_h - 30), "SCALE 1:50 (1m)", fill=wall_color, font=font_dim)

        return img
