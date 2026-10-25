import os
import json
import uuid
from typing import List
from fastapi import APIRouter, Depends, status, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy.orm import Session

from app.dependencies import get_db, get_current_user
from features.auth.models import User
from features.project.models import Project
from features.room.models import Room
from features.export.models import Report
from features.export.schemas import (
    ReportGenerateRequest, ReportGenerateResponse, ReportGenerateResponseData,
    ReportStatusResponse, ReportStatusData, ReportHistoryResponse, ReportHistoryItem,
    ProjectExportRequest, RoomExportRequest, ExportResponse
)
from features.export.services import ExportService
from core.database.session import SessionLocal

router = APIRouter(tags=["Reports & Exports"])

def run_report_generation_sync(db: Session, report_id: str):
    """Background task to generate reports in PDF, PNG, or JSON formats."""
    try:
        report = db.query(Report).filter(Report.id == report_id).first()
        if not report:
            return
        
        report.status = "Running"
        db.commit()

        project = db.query(Project).filter(Project.id == report.project_id).first()
        room = db.query(Room).filter(Room.id == report.room_id).first() if report.room_id else None

        if report.format == "PDF":
            filepath = ExportService.generate_report_pdf(db, report.id, report.report_type, project, room)
            report.file_path = filepath
            report.file_size = os.path.getsize(filepath)
            report.status = "Completed"
        elif report.format == "PNG":
            if room:
                os.makedirs("static/reports", exist_ok=True)
                filepath = os.path.join("static/reports", f"report_{report.id}.png")
                img = ExportService.generate_room_layout_image(room)
                img.save(filepath)
                report.file_path = filepath
                report.file_size = os.path.getsize(filepath)
                report.status = "Completed"
            else:
                report.status = "Failed"
        elif report.format == "JSON":
            os.makedirs("static/reports", exist_ok=True)
            filepath = os.path.join("static/reports", f"report_{report.id}.json")
            if room:
                data = {
                    "report_type": report.report_type,
                    "room_name": room.room_name,
                    "room_type": room.room_type,
                    "floor_number": room.floor_number,
                    "measurements": {
                        "length": room.measurements.length,
                        "width": room.measurements.width,
                        "height": room.measurements.height
                    } if room.measurements else {},
                    "layout": json.loads(room.properties) if room.properties else {}
                }
            else:
                data = ExportService.export_project_json(db, report.project_id, project.user_id)
            
            with open(filepath, "w") as f:
                json.dump(data, f, indent=4)

            report.file_path = filepath
            report.file_size = os.path.getsize(filepath)
            report.status = "Completed"
        else:
            report.status = "Failed"

        db.commit()
    except Exception:
        db.rollback()
        report = db.query(Report).filter(Report.id == report_id).first()
        if report:
            report.status = "Failed"
            db.commit()

# Report Generation APIs

@router.post("/reports/generate", response_model=ReportGenerateResponse, status_code=status.HTTP_201_CREATED)
def generate_report(
    req: ReportGenerateRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = db.query(Project).filter(Project.id == req.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    if req.room_id:
        room = db.query(Room).filter(Room.id == req.room_id, Room.project_id == req.project_id).first()
        if not room:
            raise HTTPException(status_code=404, detail="Room not found")

    new_report = Report(
        id=str(uuid.uuid4()),
        project_id=req.project_id,
        room_id=req.room_id,
        report_type=req.report_type,
        format=req.format or "PDF",
        status="Pending"
    )
    db.add(new_report)
    db.commit()

    # Trigger async generation
    background_tasks.add_task(run_report_generation_sync, db, new_report.id)

    return ReportGenerateResponse(
        success=True,
        message="Report generation started.",
        data=ReportGenerateResponseData(report_id=new_report.id)
    )

@router.get("/reports/{report_id}/status", response_model=ReportStatusResponse)
def get_report_status(
    report_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    report = db.query(Report).filter(Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Confirm project ownership
    project = db.query(Project).filter(Project.id == report.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=403, detail="Access denied")

    return ReportStatusResponse(
        success=True,
        data=ReportStatusData(status=report.status)
    )

@router.get("/reports/{report_id}/download")
def download_report(
    report_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    report = db.query(Report).filter(Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    
    project = db.query(Project).filter(Project.id == report.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=403, detail="Access denied")

    if report.status != "Completed":
        raise HTTPException(status_code=400, detail=f"Report is not ready. Current status: {report.status}")

    if not report.file_path or not os.path.exists(report.file_path):
        raise HTTPException(status_code=404, detail="Report file not found on server")

    media_type = "application/pdf" if report.format == "PDF" else ("image/png" if report.format == "PNG" else "application/json")
    return FileResponse(
        path=report.file_path,
        filename=os.path.basename(report.file_path),
        media_type=media_type
    )

@router.get("/reports/history/{project_id}", response_model=ReportHistoryResponse)
def get_report_history(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = db.query(Project).filter(Project.id == project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    reports = db.query(Report).filter(Report.project_id == project_id).order_by(Report.created_at.desc()).all()
    
    history_items = []
    for r in reports:
        history_items.append(ReportHistoryItem(
            id=r.id,
            project_id=r.project_id,
            room_id=r.room_id,
            report_type=r.report_type,
            status=r.status,
            file_size=r.file_size,
            format=r.format,
            created_at=r.created_at
        ))

    return ReportHistoryResponse(
        success=True,
        data=history_items
    )

# Export APIs

@router.post("/export/project")
def export_project(
    req: ProjectExportRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    project = db.query(Project).filter(Project.id == req.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    if req.format == "JSON":
        data = ExportService.export_project_json(db, req.project_id, current_user.id)
        return {"success": True, "message": "Project exported successfully.", "data": data}
    elif req.format in ["PDF", "PNG"]:
        # Inline generation
        report_id = str(uuid.uuid4())
        new_report = Report(
            id=report_id,
            project_id=req.project_id,
            report_type="Project Summary",
            format=req.format,
            status="Pending"
        )
        db.add(new_report)
        db.commit()
        
        run_report_generation_sync(db, report_id)
        
        db.refresh(new_report)
        if new_report.status == "Completed" and os.path.exists(new_report.file_path):
            media_type = "application/pdf" if req.format == "PDF" else "image/png"
            return FileResponse(new_report.file_path, filename=f"project_{req.project_id}.{req.format.lower()}", media_type=media_type)
        else:
            raise HTTPException(status_code=500, detail="Export failed")
    else:
        raise HTTPException(status_code=400, detail="Unsupported format")

@router.post("/export/room")
def export_room(
    req: RoomExportRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = db.query(Room).filter(Room.id == req.room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    project = db.query(Project).filter(Project.id == room.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=403, detail="Access denied")

    if req.format == "JSON":
        data = {
            "room_name": room.room_name,
            "room_type": room.room_type,
            "floor_number": room.floor_number,
            "notes": room.notes,
            "room_color": room.room_color,
            "measurements": {
                "length": room.measurements.length,
                "width": room.measurements.width,
                "height": room.measurements.height,
                "floor_thickness": room.measurements.floor_thickness,
                "wall_thickness": room.measurements.wall_thickness,
                "ceiling_height": room.measurements.ceiling_height
            } if room.measurements else {},
            "layout": json.loads(room.properties) if room.properties else {}
        }
        return {"success": True, "message": "Room exported successfully.", "data": data}
    elif req.format in ["PDF", "PNG"]:
        report_id = str(uuid.uuid4())
        new_report = Report(
            id=report_id,
            project_id=room.project_id,
            room_id=room.id,
            report_type="Design Report",
            format=req.format,
            status="Pending"
        )
        db.add(new_report)
        db.commit()
        
        run_report_generation_sync(db, report_id)
        
        db.refresh(new_report)
        if new_report.status == "Completed" and os.path.exists(new_report.file_path):
            media_type = "application/pdf" if req.format == "PDF" else "image/png"
            return FileResponse(new_report.file_path, filename=f"room_{req.room_id}.{req.format.lower()}", media_type=media_type)
        else:
            raise HTTPException(status_code=500, detail="Export failed")
    else:
        raise HTTPException(status_code=400, detail="Unsupported format")

@router.post("/export/image")
def export_scene_image(
    req: RoomExportRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Returns high-resolution 2D floor plan rendering of the room."""
    room = db.query(Room).filter(Room.id == req.room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    project = db.query(Project).filter(Project.id == room.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=403, detail="Access denied")

    os.makedirs("static/reports", exist_ok=True)
    filepath = os.path.join("static/reports", f"temp_scene_{room.id}.png")
    
    img = ExportService.generate_room_layout_image(room)
    img.save(filepath)
    
    return FileResponse(filepath, filename=f"room_scene_{room.id}.png", media_type="image/png")

@router.post("/export/analytics")
def export_analytics(
    req: RoomExportRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    room = db.query(Room).filter(Room.id == req.room_id).first()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    project = db.query(Project).filter(Project.id == room.project_id, Project.user_id == current_user.id).first()
    if not project:
        raise HTTPException(status_code=403, detail="Access denied")

    from features.analytics.service import AnalyticsService
    an_data = AnalyticsService.get_analytics_dashboard(db, room.id)
    insights = AnalyticsService.get_insights(db, room.id)

    return {
        "success": True,
        "data": {
            "room_id": room.id,
            "overall_score": an_data.get("overall_score", 0.0),
            "subscores": {
                "accessibility": an_data.get("accessibility_score", 0.0),
                "ergonomics": an_data.get("comfort_score", 0.0),
                "lighting": an_data.get("lighting_score", 0.0),
                "balance": an_data.get("balance_score", 0.0),
                "space_utilization": an_data.get("space_utilization", 0.0)
            },
            "insights": insights
        }
    }

# Import & Backup/Restore APIs

@router.post("/projects/import")
def import_project(
    data: dict,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    new_project = ExportService.import_project_json(db, data, current_user.id)
    return {
        "success": True,
        "message": "Project imported successfully.",
        "data": {
            "project_id": new_project.id,
            "project_name": new_project.project_name
        }
    }

@router.post("/projects/{project_id}/backup")
def backup_project(
    project_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    data = ExportService.export_project_json(db, project_id, current_user.id)
    # Save a temporary backup file
    os.makedirs("static/reports", exist_ok=True)
    filepath = os.path.join("static/reports", f"backup_{project_id}.json")
    with open(filepath, "w") as f:
        json.dump(data, f, indent=4)
        
    return FileResponse(filepath, filename=f"backup_{project_id}.json", media_type="application/json")

@router.post("/projects/restore")
def restore_project(
    data: dict,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    new_project = ExportService.import_project_json(db, data, current_user.id)
    return {
        "success": True,
        "message": "Project restored successfully.",
        "data": {
            "project_id": new_project.id,
            "project_name": new_project.project_name
        }
    }
