import os
from fastapi import FastAPI, Depends, HTTPException, status, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from app.config import settings
from core.logging.logger import logger
from core.database.session import check_db_connection
from app.dependencies import get_db
from app.middleware.exception_middleware import GlobalExceptionMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from starlette.responses import Response

from contextlib import asynccontextmanager

class CacheControlledStaticFiles(StaticFiles):
    async def get_response(self, path: str, scope) -> Response:
        response = await super().get_response(path, scope)
        max_age = 31536000 if settings.ENVIRONMENT == "production" else 86400
        response.headers["Cache-Control"] = f"public, max-age={max_age}"
        return response

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting FlowSpace Backend...")
    
    # Ensure production uploads folders exist
    os.makedirs(os.path.join("uploads", "furniture", "models"), exist_ok=True)
    os.makedirs(os.path.join("uploads", "furniture", "thumbnails"), exist_ok=True)
    os.makedirs(os.path.join("uploads", "furniture", "previews"), exist_ok=True)
    os.makedirs(os.path.join("uploads", "materials", "textures"), exist_ok=True)
    os.makedirs(os.path.join("uploads", "materials", "previews"), exist_ok=True)

    # Security Validation for Production
    if settings.ENVIRONMENT == "production":
        if settings.SECRET_KEY == "supersecretjwtkeyplaceholderchangeinproduction" or len(settings.SECRET_KEY) < 32:
            logger.critical("SECURITY CRITICAL: Insecure SECRET_KEY configured in production environment!")
            
    # Verify database connection at startup
    db_connected = check_db_connection()
    if db_connected:
        from core.database.session import SessionLocal
        from features.auth.services import seed_roles_and_permissions
        from features.furniture.services import seed_furniture_assets
        from features.material.services import MaterialService
        from features.validation.service import ValidationService
        db = SessionLocal()
        try:
            seed_roles_and_permissions(db)
            seed_furniture_assets(db)
            MaterialService.seed_default_materials(db)
            ValidationService.seed_default_rules(db)
        finally:
            db.close()
    else:
        logger.warning("Database connection could not be established at startup. FlowSpace will run with limited features.")
    yield
    logger.info("Shutting down FlowSpace Backend...")

app = FastAPI(
    title="FlowSpace API",
    description="Backend API for FlowSpace Smart Floor Planning and Ergonomic Space Optimization",
    version="1.0.0",
    lifespan=lifespan
)

# Register Secure Headers Middleware (outermost)
app.add_middleware(SecurityHeadersMiddleware)

# Register GZip Response Compression Middleware
app.add_middleware(GZipMiddleware, minimum_size=500)

# Register Request Metrics Middleware
from app.middleware.metrics_middleware import RequestMetricsMiddleware
app.add_middleware(RequestMetricsMiddleware)

# Exception Handling Middleware (innermost to catch routing exceptions)
app.add_middleware(GlobalExceptionMiddleware)

# Configure CORS
cors_origins = [o for o in settings.ALLOWED_ORIGINS if o != "*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ensure static and uploads folders exist before mounting to avoid startup crash
os.makedirs("static", exist_ok=True)
app.mount("/static", CacheControlledStaticFiles(directory="static"), name="static")

os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", CacheControlledStaticFiles(directory="uploads"), name="uploads")

# API Version 1 Router
api_v1_router = APIRouter(prefix="/api/v1")

# Include Auth Router
from features.auth.api import router as auth_router
api_v1_router.include_router(auth_router)

# Include Project Router
from features.project.api import router as project_router
api_v1_router.include_router(project_router)

# Include Room Router
from features.room.api import router as room_router
api_v1_router.include_router(room_router)

# Include Furniture Router
from features.furniture.api import router as furniture_router
api_v1_router.include_router(furniture_router)

# Include Material Router
from features.material.api import router as material_router
api_v1_router.include_router(material_router)

# Include Validation Router
from features.validation.api import router as validation_router
api_v1_router.include_router(validation_router)

# Include AI Router
from features.ai.router import router as ai_router
api_v1_router.include_router(ai_router)

# Include Room Reconstruction Router
from features.room_reconstruction.router import router as room_reconstruction_router
api_v1_router.include_router(room_reconstruction_router)

# Include Analytics Router
from features.analytics.api import router as analytics_router
api_v1_router.include_router(analytics_router)

# Include Export Router
from features.export.api import router as export_router
api_v1_router.include_router(export_router)

# Include System Router
from features.system.api import router as system_router
api_v1_router.include_router(system_router)



# Health Check defined directly on app (root-level)
@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    db_connected = check_db_connection()
    return {
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
        "database_connected": db_connected
    }

# Liveness Probe
@app.get("/health/live", status_code=status.HTTP_200_OK)
def health_liveness():
    return {"status": "alive"}

# Readiness Probe (checks Database and Storage write status)
@app.get("/health/ready")
def health_readiness():
    db_connected = check_db_connection()
    
    # Check storage writable
    storage_writable = True
    try:
        test_file = os.path.join("uploads", ".write_test")
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)
    except Exception:
        storage_writable = False
        
    if not db_connected or not storage_writable:
        details = {
            "status": "unhealthy",
            "database_connected": db_connected,
            "storage_writable": storage_writable
        }
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=details
        )
        
    return {
        "status": "ready",
        "database_connected": db_connected,
        "storage_writable": storage_writable
    }

# Health Check also accessible on /api/v1/health
@api_v1_router.get("/health", status_code=status.HTTP_200_OK)
def api_v1_health_check():
    db_connected = check_db_connection()
    return {
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
        "database_connected": db_connected
    }

# Include v1 router in app
app.include_router(api_v1_router)

