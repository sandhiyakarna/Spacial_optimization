from datetime import datetime, timezone
from sqlalchemy.orm import Session
from sqlalchemy import or_, desc, asc
from fastapi import HTTPException, status
from features.project.models import Project, ProjectSetting, Room
from features.auth.models import User, AuditLog
from core.logging.logger import logger

class ProjectService:
    @staticmethod
    def create_project(db: Session, user_id: str, project_data) -> Project:
        # Check duplicate name for the same user
        existing = db.query(Project).filter(
            Project.user_id == user_id,
            Project.project_name == project_data.project_name,
            Project.status != "Deleted"
        ).first()
        
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Duplicate project names not allowed for the same user"
            )
            
        # Create Project
        new_project = Project(
            user_id=user_id,
            project_name=project_data.project_name,
            description=project_data.description,
            location=project_data.location,
            status="Draft"
        )
        db.add(new_project)
        db.commit()
        db.refresh(new_project)
        
        # Create ProjectSettings
        new_settings = ProjectSetting(project_id=new_project.id)
        db.add(new_settings)
        
        # Audit Log
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_CREATE",
            details=f"Project '{new_project.project_name}' created."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(new_project)
        return new_project

    @staticmethod
    def get_projects(
        db: Session,
        user_id: str,
        page: int = 1,
        limit: int = 20,
        status_filter: str = None,
        search_query: str = None,
        sort_by: str = "created_at",
        favorite_only: bool = False
    ) -> tuple[list[Project], int]:
        query = db.query(Project).filter(Project.user_id == user_id, Project.status != "Deleted")
        
        if status_filter:
            query = query.filter(Project.status == status_filter)
            
        if favorite_only:
            query = query.filter(Project.is_favorite == True)
            
        if search_query:
            query = query.filter(
                or_(
                    Project.project_name.ilike(f"%{search_query}%"),
                    Project.description.ilike(f"%{search_query}%"),
                    Project.location.ilike(f"%{search_query}%")
                )
            )
            
        # Sorting
        if sort_by == "project_name":
            query = query.order_by(asc(Project.project_name))
        elif sort_by == "project_name_desc":
            query = query.order_by(desc(Project.project_name))
        elif sort_by == "updated_at":
            query = query.order_by(desc(Project.updated_at))
        else: # default created_at desc
            query = query.order_by(desc(Project.created_at))
            
        total = query.count()
        
        # Pagination
        offset = (page - 1) * limit
        projects = query.offset(offset).limit(limit).all()
        
        return projects, total

    @staticmethod
    def get_project_details(db: Session, user_id: str, project_id: str) -> Project:
        project = db.query(Project).filter(
            Project.id == project_id,
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).first()
        
        if not project:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Project not found"
            )
        return project

    @staticmethod
    def update_project(db: Session, user_id: str, project_id: str, project_data) -> Project:
        project = ProjectService.get_project_details(db, user_id, project_id)
        
        # Check duplicate name if project_name changes
        if project_data.project_name and project_data.project_name != project.project_name:
            existing = db.query(Project).filter(
                Project.user_id == user_id,
                Project.project_name == project_data.project_name,
                Project.id != project_id,
                Project.status != "Deleted"
            ).first()
            if existing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Duplicate project names not allowed for the same user"
                )
            project.project_name = project_data.project_name
            
        if project_data.description is not None:
            project.description = project_data.description
            
        if project_data.location is not None:
            project.location = project_data.location
            
        if project_data.status is not None:
            project.status = project_data.status
            
        if project_data.is_favorite is not None:
            project.is_favorite = project_data.is_favorite
            
        project.updated_at = datetime.now(timezone.utc)
        
        # Audit Log
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_UPDATE",
            details=f"Project '{project.project_name}' updated."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(project)
        return project

    @staticmethod
    def archive_project(db: Session, user_id: str, project_id: str) -> Project:
        project = ProjectService.get_project_details(db, user_id, project_id)
        project.status = "Archived"
        project.updated_at = datetime.now(timezone.utc)
        
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_ARCHIVE",
            details=f"Project '{project.project_name}' archived."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(project)
        return project

    @staticmethod
    def restore_project(db: Session, user_id: str, project_id: str) -> Project:
        project = ProjectService.get_project_details(db, user_id, project_id)
        project.status = "Draft"
        project.updated_at = datetime.now(timezone.utc)
        
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_RESTORE",
            details=f"Project '{project.project_name}' restored."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(project)
        return project

    @staticmethod
    def soft_delete_project(db: Session, user_id: str, project_id: str) -> None:
        project = ProjectService.get_project_details(db, user_id, project_id)
        project.status = "Deleted"
        project.updated_at = datetime.now(timezone.utc)
        
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_DELETE",
            details=f"Project '{project.project_name}' soft deleted."
        )
        db.add(audit)
        db.commit()

    @staticmethod
    def duplicate_project(db: Session, user_id: str, project_id: str) -> Project:
        source_project = ProjectService.get_project_details(db, user_id, project_id)
        
        # Generate unique duplicate name
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        dup_name = f"{source_project.project_name} (Copy)"
        if len(dup_name) > 120:
            dup_name = f"{source_project.project_name[:100]} (Copy)"
            
        # Create Project
        dup_project = Project(
            user_id=user_id,
            project_name=dup_name,
            description=source_project.description,
            location=source_project.location,
            status="Draft"
        )
        db.add(dup_project)
        db.commit()
        db.refresh(dup_project)
        
        # Duplicate Settings
        if source_project.settings:
            dup_settings = ProjectSetting(
                project_id=dup_project.id,
                default_style=source_project.settings.default_style,
                default_template=source_project.settings.default_template,
                measurement_unit=source_project.settings.measurement_unit,
                grid_enabled=source_project.settings.grid_enabled,
                snap_enabled=source_project.settings.snap_enabled
            )
            db.add(dup_settings)
            
        # Duplicate Rooms
        for room in source_project.rooms:
            dup_room = Room(
                project_id=dup_project.id,
                room_name=room.room_name,
                room_type=room.room_type,
                floor_number=room.floor_number,
                notes=room.notes
            )
            db.add(dup_room)
            
        # Audit
        audit = AuditLog(
            user_id=user_id,
            action="PROJECT_DUPLICATE",
            details=f"Project '{source_project.project_name}' duplicated as '{dup_name}'."
        )
        db.add(audit)
        
        db.commit()
        db.refresh(dup_project)
        return dup_project

    @staticmethod
    def get_dashboard_summary(db: Session, user: User) -> dict:
        user_id = user.id
        
        # Recent Projects (top 5 sorted by updated_at)
        recent_projects = db.query(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).order_by(desc(Project.updated_at)).limit(5).all()
        
        # Favorite Projects
        favorite_projects = db.query(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted",
            Project.is_favorite == True
        ).order_by(desc(Project.updated_at)).limit(5).all()
        
        # Aggregations
        total_projects = db.query(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).count()
        
        total_rooms = db.query(Room).join(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).count()
        
        # Fetch dynamic recent activity from AuditLog
        activities = db.query(AuditLog).filter(
            AuditLog.user_id == user_id
        ).order_by(desc(AuditLog.created_at)).limit(5).all()
        
        recent_activity = [
            {
                "id": act.id,
                "description": f"{act.action}: {act.details}" if act.details else act.action,
                "timestamp": act.created_at.isoformat()
            } for act in activities
        ]
        
        # Fetch dynamic AI recommendations from RecommendationHistory
        from features.ai.models import RecommendationHistory, Analytics
        recommendations_list = db.query(RecommendationHistory).join(Room).join(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).order_by(desc(RecommendationHistory.created_at)).limit(5).all()
        
        ai_recommendations = [
            {
                "id": rec.id,
                "title": rec.title,
                "description": rec.description,
                "timestamp": rec.created_at.isoformat()
            } for rec in recommendations_list
        ]
        
        # Compile dynamic notifications based on user state
        notifications = []
        if favorite_projects:
            notifications.append({
                "id": "notif-fav",
                "title": "Favorite Added",
                "message": f"You have {len(favorite_projects)} favorite project(s) pinned to your dashboard.",
                "read": False
            })
        notifications.append({
            "id": "notif-welcome",
            "title": "Welcome to FlowSpace v2.0",
            "message": "Start by creating a new project or importing layout templates.",
            "read": True
        })
        
        # Calculate dynamic analytics summary
        room_analytics = db.query(Analytics).join(Room).join(Project).filter(
            Project.user_id == user_id,
            Project.status != "Deleted"
        ).all()
        
        avg_utilization = 0.0
        avg_ergonomic = 0.0
        if room_analytics:
            avg_utilization = sum(a.space_utilization_score for a in room_analytics) / len(room_analytics)
            avg_ergonomic = sum(a.ergonomic_score for a in room_analytics) / len(room_analytics)
        else:
            avg_utilization = 75.0
            avg_ergonomic = 85.0
            
        analytics_summary = {
            "average_room_utilization": f"{int(avg_utilization)}%",
            "ergonomic_compliance_rate": f"{int(avg_ergonomic)}%",
            "optimal_layouts_count": total_projects
        }
        
        return {
            "welcome_message": f"Welcome back, {user.full_name}!",
            "total_projects": total_projects,
            "total_rooms": total_rooms,
            "recent_projects": recent_projects,
            "favorite_projects": favorite_projects,
            "recent_activity": recent_activity,
            "ai_recommendations": ai_recommendations,
            "analytics_summary": analytics_summary,
            "notifications": notifications
        }
