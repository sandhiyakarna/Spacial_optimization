from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
from app.dependencies import get_db, RoleChecker
from features.system.schemas import (
    SystemOverviewResponse, LogsResponse, BackupCreateResponse, CachePurgeResponse,
    SystemMetricsResponse
)
from features.system.service import SystemService

router = APIRouter(
    prefix="/system", 
    tags=["System Management"], 
    dependencies=[Depends(RoleChecker(["Administrator"]))]
)

@router.get("/status", response_model=SystemOverviewResponse)
def get_system_status(db: Session = Depends(get_db)):
    health = SystemService.get_health_status(db)
    storage = SystemService.get_storage_overview()
    database = SystemService.get_database_status(db)
    backup = SystemService.get_backup_status()
    environment = SystemService.get_environment_info()
    cache = SystemService.get_cache_status()
    
    return {
        "health": health,
        "storage": storage,
        "database": database,
        "backup": backup,
        "environment": environment,
        "cache": cache
    }

@router.post("/backup", response_model=BackupCreateResponse, status_code=status.HTTP_201_CREATED)
def create_database_backup():
    try:
        backup_file = SystemService.create_backup()
        return {
            "success": True,
            "message": "Database backup created successfully.",
            "filename": backup_file
        }
    except Exception as e:
        return {
            "success": False,
            "message": f"Failed to create database backup: {str(e)}",
            "filename": ""
        }

@router.post("/cache/purge", response_model=CachePurgeResponse)
def purge_system_cache():
    res = SystemService.purge_cache()
    return {
        "success": True,
        "message": "Asset cache purged successfully.",
        "previous_size": res["previous_size"],
        "current_size": res["current_size"]
    }

@router.get("/logs", response_model=LogsResponse)
def get_latest_logs(lines: int = Query(default=100, ge=1, le=1000)):
    logs = SystemService.read_latest_logs(lines)
    return {
        "logs": logs,
        "count": len(logs)
    }

@router.get("/metrics", response_model=SystemMetricsResponse)
def get_system_metrics():
    return SystemService.get_metrics()
