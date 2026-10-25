import os
import json
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Type
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.models import (
    Analytics, ValidationResult, ValidationChecklist, DesignHistory, RecommendationHistory
)
from features.export.models import Report

# PIL and ReportLab imports
from PIL import Image, ImageDraw, ImageFont
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch

class ExportService:

    @classmethod
    def generate_room_layout_image(cls, room: Room) -> Image.Image:
        """Draws a 2D floor plan image of the room and its furniture using PIL."""
        # 1. Determine Room Dimensions
        length = 600.0  # Default measurements in cm
        width = 450.0
        if room.measurements:
            length = room.measurements.length
            width = room.measurements.width

        # 2. Image setup
        img_w, img_h = 800, 600
        padding = 50
        image = Image.new("RGB", (img_w, img_h), "#F3F4F6") # Light grey background
        draw = ImageDraw.Draw(image)

        # 3. Calculate scaling factor to fit the room on canvas
        scale_x = (img_w - 2 * padding) / length
        scale_y = (img_h - 2 * padding) / width
        scale = min(scale_x, scale_y)

        # Center the room
        room_pixel_w = length * scale
        room_pixel_h = width * scale
        offset_x = (img_w - room_pixel_w) / 2
        offset_y = (img_h - room_pixel_h) / 2

        # 4. Draw room boundary
        room_rect = [offset_x, offset_y, offset_x + room_pixel_w, offset_y + room_pixel_h]
        # Fill room interior with white
        draw.rectangle(room_rect, fill="#FFFFFF", outline="#1F2937", width=4)

        # 5. Parse and draw furniture placements
        props = json.loads(room.properties) if room.properties else {}
        furniture_list = props.get("furniture", [])

        # Setup standard styling color palette for categories
        cat_colors = {
            "living room": ("#3B82F6", "#EFF6FF"), # Blue
            "bedroom": ("#10B981", "#ECFDF5"),    # Green
            "office": ("#8B5CF6", "#F5F3FF"),     # Purple
            "kitchen": ("#F59E0B", "#FEF3C7"),    # Yellow/Amber
            "dining": ("#EF4444", "#FEF2F2"),     # Red
        }

        # Try to load a font, fallback to default
        try:
            font = ImageFont.load_default()
        except Exception:
            font = None

        for item in furniture_list:
            # Position is relative to room center
            # standard coordinate: x is width, z is length (or vice versa)
            x_cm = item.get("x", length / 2.0)
            z_cm = item.get("z", width / 2.0)
            item_w = item.get("width", 80.0)
            item_d = item.get("depth", 80.0)
            name = item.get("name", "Furniture")
            category = item.get("category", "").lower()

            # Map coordinates to pixels
            pixel_cx = offset_x + x_cm * scale
            pixel_cy = offset_y + z_cm * scale
            pixel_w = item_w * scale
            pixel_h = item_d * scale

            # Bounding box
            left = pixel_cx - pixel_w / 2
            right = pixel_cx + pixel_w / 2
            top = pixel_cy - pixel_h / 2
            bottom = pixel_cy + pixel_h / 2

            # Keep inside room bounds safely
            left = max(offset_x, min(offset_x + room_pixel_w, left))
            right = max(offset_x, min(offset_x + room_pixel_w, right))
            top = max(offset_y, min(offset_y + room_pixel_h, top))
            bottom = max(offset_y, min(offset_y + room_pixel_h, bottom))

            # Fetch styling
            stroke, fill = cat_colors.get(category, ("#6B7280", "#F3F4F6")) # Fallback grey
            
            # Draw furniture rectangle
            draw.rectangle([left, top, right, bottom], fill=fill, outline=stroke, width=2)
            
            # Label furniture
            label = name[:12]
            if font:
                # Draw small label inside
                draw.text((left + 4, top + 4), label, fill="#374151", font=font)

        # 6. Draw Openings (doors/windows)
        openings = props.get("openings", [])
        for op in openings:
            op_type = op.get("type", "window").lower()
            op_x = op.get("x", 0.0)
            op_z = op.get("z", 0.0)
            op_w = op.get("width", 90.0)
            # Wall placement mapping
            px = offset_x + op_x * scale
            py = offset_y + op_z * scale
            pw = op_w * scale
            
            # Windows are blue lines, doors are brown curves/arcs
            if op_type == "window":
                draw.line([px - pw/2, py, px + pw/2, py], fill="#06B6D4", width=6)
            else:
                draw.line([px - pw/2, py, px + pw/2, py], fill="#B45309", width=4)

        return image

    @classmethod
    def export_project_json(cls, db: Session, project_id: str, user_id: str) -> Dict[str, Any]:
        """Serializes the entire project data to a dictionary."""
        project = db.query(Project).filter(Project.id == project_id, Project.user_id == user_id).first()
        if not project:
            raise HTTPException(status_code=404, detail="Project not found")

        # Project settings
        settings_data = {}
        if project.settings:
            settings_data = {
                "default_style": project.settings.default_style,
                "default_template": project.settings.default_template,
                "measurement_unit": project.settings.measurement_unit,
                "grid_enabled": project.settings.grid_enabled,
                "snap_enabled": project.settings.snap_enabled
            }

        # Rooms
        rooms_list = []
        for room in project.rooms:
            meas_data = {}
            if room.measurements:
                meas_data = {
                    "length": room.measurements.length,
                    "width": room.measurements.width,
                    "height": room.measurements.height,
                    "floor_thickness": room.measurements.floor_thickness,
                    "wall_thickness": room.measurements.wall_thickness,
                    "ceiling_height": room.measurements.ceiling_height
                }

            rooms_list.append({
                "room_name": room.room_name,
                "room_type": room.room_type,
                "floor_number": room.floor_number,
                "notes": room.notes,
                "room_color": room.room_color,
                "properties": room.properties, # Contains layout json
                "measurements": meas_data
            })

        return {
            "version": "1.0",
            "project_name": project.project_name,
            "description": project.description,
            "location": project.location,
            "status": project.status,
            "is_favorite": project.is_favorite,
            "settings": settings_data,
            "rooms": rooms_list
        }

    @classmethod
    def import_project_json(cls, db: Session, data: Dict[str, Any], user_id: str) -> Project:
        """Imports and recreates a project from serialized JSON data."""
        # 1. Create Project
        proj_name = data.get("project_name", "Imported Project")
        # Ensure project name doesn't conflict for the same user
        existing = db.query(Project).filter(Project.project_name == proj_name, Project.user_id == user_id).first()
        if existing:
            proj_name = f"{proj_name} (Restored)"

        new_project = Project(
            id=str(uuid.uuid4()),
            user_id=user_id,
            project_name=proj_name,
            description=data.get("description"),
            location=data.get("location"),
            status=data.get("status", "Draft"),
            is_favorite=data.get("is_favorite", False)
        )
        db.add(new_project)
        db.flush()

        # 2. Add Settings
        set_data = data.get("settings", {})
        new_settings = ProjectSetting(
            id=str(uuid.uuid4()),
            project_id=new_project.id,
            default_style=set_data.get("default_style"),
            default_template=set_data.get("default_template"),
            measurement_unit=set_data.get("measurement_unit", "Centimeters"),
            grid_enabled=set_data.get("grid_enabled", True),
            snap_enabled=set_data.get("snap_enabled", True)
        )
        db.add(new_settings)

        # 3. Add Rooms & RoomMeasurements
        for r_data in data.get("rooms", []):
            new_room = Room(
                id=str(uuid.uuid4()),
                project_id=new_project.id,
                room_name=r_data.get("room_name", "Unnamed Room"),
                room_type=r_data.get("room_type", "Living Room"),
                floor_number=r_data.get("floor_number", 1),
                notes=r_data.get("notes"),
                room_color=r_data.get("room_color", "#FFFFFF"),
                properties=r_data.get("properties")
            )
            db.add(new_room)
            db.flush()

            m_data = r_data.get("measurements")
            if m_data:
                new_meas = RoomMeasurement(
                    id=str(uuid.uuid4()),
                    room_id=new_room.id,
                    length=m_data.get("length", 600.0),
                    width=m_data.get("width", 450.0),
                    height=m_data.get("height", 300.0),
                    floor_thickness=m_data.get("floor_thickness", 30.0),
                    wall_thickness=m_data.get("wall_thickness", 20.0),
                    ceiling_height=m_data.get("ceiling_height", 300.0)
                )
                db.add(new_meas)

        db.commit()
        return new_project

    @classmethod
    def generate_report_pdf(cls, db: Session, report_id: str, report_type: str, project: Project, room: Optional[Room], format_style: str = "Standard") -> str:
        """Generates a professional PDF report on disk and returns its file path."""
        os.makedirs("static/reports", exist_ok=True)
        filename = f"report_{report_id}.pdf"
        filepath = os.path.join("static/reports", filename)

        # Styles
        styles = getSampleStyleSheet()
        
        # Modify existing Normal/Title styles safely
        title_style = ParagraphStyle(
            'ReportTitle',
            parent=styles['Heading1'],
            fontSize=24,
            leading=28,
            textColor=colors.HexColor("#1E3A8A"), # Corporate Blue
            spaceAfter=15
        )
        
        subtitle_style = ParagraphStyle(
            'ReportSubtitle',
            parent=styles['Normal'],
            fontSize=12,
            leading=16,
            textColor=colors.HexColor("#4B5563"),
            spaceAfter=30
        )
        
        heading_style = ParagraphStyle(
            'SectionHeading',
            parent=styles['Heading2'],
            fontSize=16,
            leading=20,
            textColor=colors.HexColor("#0F766E"), # Teal
            spaceBefore=15,
            spaceAfter=10
        )

        body_style = ParagraphStyle(
            'ReportBody',
            parent=styles['Normal'],
            fontSize=10,
            leading=14,
            textColor=colors.HexColor("#1F2937")
        )

        doc = SimpleDocTemplate(filepath, pagesize=letter, leftMargin=0.75*inch, rightMargin=0.75*inch, topMargin=0.75*inch, bottomMargin=0.75*inch)
        story = []

        # 1. Title / Header
        story.append(Paragraph(f"FlowSpace: {report_type}", title_style))
        story.append(Paragraph(f"Project: {project.project_name} | Location: {project.location or 'N/A'} | Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}", subtitle_style))
        story.append(Spacer(1, 10))

        # 2. Add content based on Report Type
        if report_type == "Design Report":
            story.append(Paragraph("Project Details", heading_style))
            proj_info = [
                ["Project Name:", project.project_name],
                ["Description:", project.description or "None"],
                ["Location:", project.location or "N/A"],
                ["Status:", project.status],
                ["Created At:", project.created_at.strftime('%Y-%m-%d %H:%M:%S')]
            ]
            t_proj = Table(proj_info, colWidths=[1.5*inch, 5*inch])
            t_proj.setStyle(TableStyle([
                ('TEXTCOLOR', (0,0), (-1,-1), colors.HexColor("#374151")),
                ('BOTTOMPADDING', (0,0), (-1,-1), 4),
                ('ALIGN', (0,0), (-1,-1), 'LEFT'),
            ]))
            story.append(t_proj)
            story.append(Spacer(1, 15))

            if room:
                story.append(Paragraph("Room Details & Measurements", heading_style))
                room_info = [
                    ["Room Name:", room.room_name],
                    ["Room Type:", room.room_type],
                    ["Floor Number:", str(room.floor_number)],
                    ["Dimensions:", f"{room.measurements.length} x {room.measurements.width} cm" if room.measurements else "Not configured"]
                ]
                t_room = Table(room_info, colWidths=[1.5*inch, 5*inch])
                t_room.setStyle(TableStyle([
                    ('TEXTCOLOR', (0,0), (-1,-1), colors.HexColor("#374151")),
                    ('BOTTOMPADDING', (0,0), (-1,-1), 4),
                ]))
                story.append(t_room)
                story.append(Spacer(1, 20))

                # Insert 2D Floor Plan Image
                story.append(Paragraph("2D Floor Plan layout", heading_style))
                layout_img = cls.generate_room_layout_image(room)
                img_path = f"static/reports/temp_layout_{report_id}.png"
                layout_img.save(img_path)
                story.append(RLImage(img_path, width=5.5*inch, height=4.125*inch))
                story.append(Spacer(1, 20))

                # Furniture List Table
                story.append(Paragraph("Furniture Inventory (BOM)", heading_style))
                props = json.loads(room.properties) if room.properties else {}
                furniture = props.get("furniture", [])
                
                table_data = [["Name", "Category", "Width (cm)", "Depth (cm)", "Height (cm)"]]
                for f in furniture:
                    table_data.append([
                        f.get("name", "Furniture"),
                        f.get("category", "N/A"),
                        str(f.get("width", 0.0)),
                        str(f.get("depth", 0.0)),
                        str(f.get("height", 0.0))
                    ])
                
                t_furn = Table(table_data, colWidths=[2.5*inch, 1.5*inch, 1*inch, 1*inch, 1*inch])
                t_furn.setStyle(TableStyle([
                    ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#0F766E")),
                    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                    ('ALIGN', (0,0), (-1,-1), 'CENTER'),
                    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
                    ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                ]))
                story.append(t_furn)

        elif report_type == "Analytics Report":
            if room:
                # Find Analytics
                from features.analytics.service import AnalyticsService
                an_data = AnalyticsService.get_analytics_dashboard(db, room.id)

                story.append(Paragraph("Ergonomic & Layout Analytics Summary", heading_style))
                scores_data = [
                    ["Metric", "Score / 100"],
                    ["Overall Score:", f"{an_data.get('overall_score', 0.0):.1f}"],
                    ["Accessibility Score:", f"{an_data.get('accessibility_score', 0.0):.1f}"],
                    ["Comfort & Ergonomics:", f"{an_data.get('comfort_score', 0.0):.1f}"],
                    ["Space Utilization:", f"{an_data.get('space_utilization', 0.0):.1f}"],
                    ["Lighting Adequacy:", f"{an_data.get('lighting_score', 0.0):.1f}"],
                    ["Furniture Balance:", f"{an_data.get('balance_score', 0.0):.1f}"]
                ]
                t_scores = Table(scores_data, colWidths=[3*inch, 2.5*inch])
                t_scores.setStyle(TableStyle([
                    ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#1E3A8A")),
                    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                    ('ALIGN', (0,0), (-1,-1), 'LEFT'),
                    ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                    ('FONTNAME', (0,1), (0,-1), 'Helvetica-Bold'),
                    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
                ]))
                story.append(t_scores)
                story.append(Spacer(1, 20))

                # Insights
                insights = AnalyticsService.get_insights(db, room.id)
                story.append(Paragraph("Design Insights & Feedback", heading_style))
                for ins in insights:
                    story.append(Paragraph(f"• <b>{ins.get('type', 'Info')}</b>: {ins.get('text', '')}", body_style))
                    story.append(Spacer(1, 4))
                story.append(Spacer(1, 15))

                # Estimated cost
                cost = an_data.get('estimated_cost', 0.0)
                story.append(Paragraph(f"<b>Estimated Project Cost:</b> ${cost:,.2f}", body_style))

        elif report_type == "Validation Report":
            if room:
                results = db.query(ValidationResult).filter(ValidationResult.room_id == room.id).all()
                checklist = db.query(ValidationChecklist).filter(ValidationChecklist.room_id == room.id).all()

                story.append(Paragraph("Validation Rule Compliance Check", heading_style))
                story.append(Paragraph(f"Total Rules Evaluated: {len(results)}", body_style))
                story.append(Spacer(1, 10))

                # Validation checklist table
                checklist_data = [["Checklist Item", "Status"]]
                for item in checklist:
                    checklist_data.append([
                        item.checklist_item,
                        "✓ Pass" if item.completed else "✗ Failed"
                    ])
                t_check = Table(checklist_data, colWidths=[4.5*inch, 2*inch])
                t_check.setStyle(TableStyle([
                    ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#0F766E")),
                    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                    ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                    ('BOTTOMPADDING', (0,0), (-1,-1), 6),
                ]))
                story.append(t_check)
                story.append(Spacer(1, 20))

                # Detailed Violations/Results
                story.append(Paragraph("Specific Rule Violations / Warnings", heading_style))
                if not results:
                    story.append(Paragraph("No validation errors or warnings detected.", body_style))
                else:
                    res_data = [["Rule ID / Severity", "Status", "Description/Message"]]
                    for r in results:
                        res_data.append([
                            f"Rule ({r.severity})",
                            r.status,
                            r.message
                        ])
                    t_res = Table(res_data, colWidths=[2*inch, 1.2*inch, 3.3*inch])
                    t_res.setStyle(TableStyle([
                        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#B91C1C") if any(r.severity == 'Error' for r in results) else colors.HexColor("#F59E0B")),
                        ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                        ('BOTTOMPADDING', (0,0), (-1,-1), 6),
                    ]))
                    story.append(t_res)

        elif report_type == "Recommendation Report":
            if room:
                from features.ai.service import AIService
                cards = AIService.get_room_recommendations(db, room.id)

                story.append(Paragraph("AI Layout & Ergonomic Optimization Suggestions", heading_style))
                if not cards:
                    story.append(Paragraph("No recommendations generated for this layout. Check layout metrics or validation rule updates.", body_style))
                else:
                    for card in cards:
                        story.append(Paragraph(f"<b>Recommendation:</b> {card['title']}", body_style))
                        story.append(Paragraph(f"<i>Category:</i> {card['recommendation_type']} | <i>Impact:</i> +{card['score_impact']} points", body_style))
                        story.append(Paragraph(f"<i>Triggered by:</i> {card['rule_triggered']}", body_style))
                        story.append(Paragraph(f"<i>Why suggested:</i> {card['reason']}", body_style))
                        story.append(Paragraph(f"<i>Proposed Action:</i> {card['action']}", body_style))
                        story.append(Spacer(1, 10))

        else: # Default Project Summary
            story.append(Paragraph("Project Room Catalog Summary", heading_style))
            rooms = project.rooms
            table_data = [["Room Name", "Room Type", "Floor Number", "Notes"]]
            for r in rooms:
                table_data.append([
                    r.room_name,
                    r.room_type,
                    str(r.floor_number),
                    r.notes or "None"
                ])
            t_rooms = Table(table_data, colWidths=[2*inch, 1.5*inch, 1.2*inch, 1.8*inch])
            t_rooms.setStyle(TableStyle([
                ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#1E3A8A")),
                ('TEXTCOLOR', (0,0), (-1,0), colors.white),
                ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
                ('BOTTOMPADDING', (0,0), (-1,-1), 6),
            ]))
            story.append(t_rooms)

        # Build document
        doc.build(story)

        # Cleanup temp layout image if created
        temp_img_path = f"static/reports/temp_layout_{report_id}.png"
        if os.path.exists(temp_img_path):
            try:
                os.remove(temp_img_path)
            except Exception:
                pass

        return filepath
