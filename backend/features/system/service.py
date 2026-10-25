import os
import sys
import shutil
import platform
import sqlite3
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.config import settings
from core.database.session import check_db_connection, engine
from features.auth.models import User, AuditLog
from features.project.models import Project
from features.room.models import Room
from features.furniture.models import FurnitureAsset
from features.material.models import Material

logger = logging.getLogger("flowspace")

class SystemService:
    @staticmethod
    def format_size(size_bytes: int) -> str:
        if size_bytes == 0:
            return "0 B"
        size_name = ("B", "KB", "MB", "GB", "TB")
        i = 0
        while size_bytes >= 1024 and i < len(size_name) - 1:
            size_bytes /= 1024.0
            i += 1
        return f"{size_bytes:.2f} {size_name[i]}"

    @staticmethod
    def get_directory_info(path: str) -> Dict[str, Any]:
        count = 0
        total_size = 0
        if os.path.exists(path):
            for root, _, files in os.walk(path):
                for f in files:
                    fp = os.path.join(root, f)
                    if os.path.exists(fp):
                        count += 1
                        total_size += os.path.getsize(fp)
        return {
            "count": count,
            "size_bytes": total_size,
            "size_formatted": SystemService.format_size(total_size)
        }

    @classmethod
    def get_storage_overview(cls) -> Dict[str, Any]:
        base_dir = os.path.abspath("uploads")
        # Ensure directory exists
        os.makedirs(base_dir, exist_ok=True)

        subdirs = [
            "furniture/models",
            "furniture/thumbnails",
            "furniture/previews",
            "materials/textures",
            "materials/previews"
        ]

        subdir_infos = []
        for s in subdirs:
            p = os.path.join(base_dir, s)
            info = cls.get_directory_info(p)
            subdir_infos.append({
                "name": s,
                "count": info["count"],
                "size_bytes": info["size_bytes"],
                "size_formatted": info["size_formatted"]
            })

        overall_info = cls.get_directory_info(base_dir)

        # Disk usage of the host/drive
        try:
            usage = shutil.disk_usage(base_dir)
            disk_usage = {
                "total": usage.total,
                "free": usage.free,
                "used": usage.used,
                "percent_used": round((usage.used / usage.total) * 100, 2)
            }
        except Exception:
            disk_usage = {
                "total": 0,
                "free": 0,
                "used": 0,
                "percent_used": 0.0
            }

        return {
            "total_files": overall_info["count"],
            "total_size_bytes": overall_info["size_bytes"],
            "total_size_formatted": overall_info["size_formatted"],
            "subdirectories": subdir_infos,
            "disk_usage": disk_usage
        }

    @classmethod
    def get_database_status(cls, db: Session) -> Dict[str, Any]:
        connected = check_db_connection()
        db_type = "Unknown"
        file_size_bytes = 0
        
        # Check database path/type from DATABASE_URL
        db_url = settings.DATABASE_URL
        if db_url.startswith("sqlite:///"):
            db_type = "SQLite"
            db_path = db_url.replace("sqlite:///", "")
            # relative paths resolve from current directory
            if db_path.startswith("./"):
                db_path = db_path[2:]
            
            db_path = os.path.abspath(db_path)
            if os.path.exists(db_path):
                file_size_bytes = os.path.getsize(db_path)
        elif "postgresql" in db_url or "postgres" in db_url:
            db_type = "PostgreSQL"
            if connected:
                try:
                    # Query PostgreSQL database size using SQL
                    result = db.execute(text("SELECT pg_database_size(current_database())")).scalar()
                    if result is not None:
                        file_size_bytes = int(result)
                except Exception as e:
                    logger.error(f"Error querying PostgreSQL database size: {e}")
        else:
            db_type = "Relational"

        table_counts = {
            "users": 0,
            "projects": 0,
            "rooms": 0,
            "furniture_assets": 0,
            "materials": 0,
            "audit_logs": 0
        }

        if connected:
            try:
                table_counts["users"] = db.query(User).count()
                table_counts["projects"] = db.query(Project).count()
                table_counts["rooms"] = db.query(Room).count()
                table_counts["furniture_assets"] = db.query(FurnitureAsset).count()
                table_counts["materials"] = db.query(Material).count()
                table_counts["audit_logs"] = db.query(AuditLog).count()
            except Exception as e:
                logger.error(f"Error querying table counts: {e}")

        return {
            "connected": connected,
            "type": db_type,
            "file_size_bytes": file_size_bytes,
            "file_size_formatted": cls.format_size(file_size_bytes),
            "table_counts": table_counts
        }

    @classmethod
    def get_backup_status(cls) -> Dict[str, Any]:
        backups_dir = os.path.abspath("backups")
        os.makedirs(backups_dir, exist_ok=True)

        backup_files = []
        last_backup = None

        valid_extensions = (".db", ".sql", ".gz")
        for f in os.listdir(backups_dir):
            fp = os.path.join(backups_dir, f)
            if os.path.isfile(fp) and f.startswith("flowspace_backup_") and f.endswith(valid_extensions):
                size = os.path.getsize(fp)
                mtime = os.path.getmtime(fp)
                created_at_dt = datetime.fromtimestamp(mtime)
                backup_files.append({
                    "filename": f,
                    "size_bytes": size,
                    "size_formatted": cls.format_size(size),
                    "created_at": created_at_dt.isoformat()
                })

        # Sort by filename or timestamp (latest first)
        if backup_files:
            backup_files.sort(key=lambda x: x["filename"], reverse=True)
            last_backup = backup_files[0]["created_at"]

        return {
            "backups_dir": backups_dir,
            "backup_files": backup_files,
            "last_backup": last_backup
        }

    @classmethod
    def create_backup(cls) -> str:
        backups_dir = os.path.abspath("backups")
        os.makedirs(backups_dir, exist_ok=True)

        db_url = settings.DATABASE_URL
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if db_url.startswith("sqlite:///"):
            db_path = db_url.replace("sqlite:///", "")
            if db_path.startswith("./"):
                db_path = db_path[2:]
            db_path = os.path.abspath(db_path)

            if not os.path.exists(db_path):
                raise FileNotFoundError(f"Database file not found at {db_path}")

            backup_filename = f"flowspace_backup_{timestamp}.db"
            backup_path = os.path.join(backups_dir, backup_filename)

            # Safe backup using SQLite backup API
            src_conn = sqlite3.connect(db_path)
            dst_conn = sqlite3.connect(backup_path)
            try:
                with dst_conn:
                    src_conn.backup(dst_conn)
            finally:
                dst_conn.close()
                src_conn.close()

            logger.info(f"SQLite Database backup created successfully: {backup_filename}")
            return backup_filename

        elif "postgresql" in db_url or "postgres" in db_url:
            from urllib.parse import urlparse
            import subprocess
            import gzip

            parsed = urlparse(db_url)
            username = parsed.username or "postgres"
            password = parsed.password or ""
            host = parsed.hostname or "localhost"
            port = parsed.port or 5432
            database = parsed.path.lstrip('/')

            backup_filename = f"flowspace_backup_{timestamp}.sql"
            backup_path = os.path.join(backups_dir, backup_filename)
            backup_filename_gz = f"{backup_filename}.gz"
            backup_path_gz = os.path.join(backups_dir, backup_filename_gz)

            # pg_dump command
            cmd = [
                "pg_dump",
                "-U", username,
                "-h", host,
                "-p", str(port),
                "-F", "p",  # plain text format SQL file
                "-f", backup_path,
                database
            ]

            env = os.environ.copy()
            if password:
                env["PGPASSWORD"] = password

            try:
                # Execute dump
                subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)

                # Compress the dumped SQL file using gzip
                with open(backup_path, "rb") as f_in:
                    with gzip.open(backup_path_gz, "wb") as f_out:
                        shutil.copyfileobj(f_in, f_out)

                # Remove uncompressed temp SQL file
                os.remove(backup_path)

                logger.info(f"PostgreSQL Database backup created and compressed successfully: {backup_filename_gz}")
                return backup_filename_gz
            except subprocess.CalledProcessError as e:
                logger.error(f"pg_dump backup failed: {e.stderr}")
                # Clean up backup files if failed midway
                if os.path.exists(backup_path):
                    os.remove(backup_path)
                if os.path.exists(backup_path_gz):
                    os.remove(backup_path_gz)
                raise RuntimeError(f"Database pg_dump failed: {e.stderr}")
            except Exception as e:
                logger.error(f"PostgreSQL backup failed: {e}")
                raise e
        else:
            raise ValueError(f"Unsupported database URL scheme for backup: {db_url}")

    @classmethod
    def get_cache_status(cls) -> Dict[str, Any]:
        cache_dir = os.path.abspath(os.path.join("uploads", "cache"))
        os.makedirs(cache_dir, exist_ok=True)
        info = cls.get_directory_info(cache_dir)
        return {
            "cache_dir": cache_dir,
            "size_bytes": info["size_bytes"],
            "size_formatted": info["size_formatted"],
            "files_count": info["count"]
        }

    @classmethod
    def purge_cache(cls) -> Dict[str, Any]:
        cache_dir = os.path.abspath(os.path.join("uploads", "cache"))
        os.makedirs(cache_dir, exist_ok=True)
        
        previous_status = cls.get_cache_status()
        
        # Purge all files in the cache directory
        for root, dirs, files in os.walk(cache_dir):
            for f in files:
                fp = os.path.join(root, f)
                try:
                    os.remove(fp)
                except Exception as e:
                    logger.error(f"Failed to delete cache file {fp}: {e}")
            for d in dirs:
                dp = os.path.join(root, d)
                try:
                    shutil.rmtree(dp)
                except Exception as e:
                    logger.error(f"Failed to delete cache directory {dp}: {e}")

        current_status = cls.get_cache_status()
        
        return {
            "previous_size": previous_status["size_formatted"],
            "current_size": current_status["size_formatted"]
        }

    @classmethod
    def get_environment_info(cls) -> Dict[str, Any]:
        # Gather curated settings safely
        curated_settings = {}
        for key in ["HOST", "PORT", "ENVIRONMENT", "LOG_LEVEL", "ALGORITHM", "ACCESS_TOKEN_EXPIRE_MINUTES"]:
            if hasattr(settings, key):
                curated_settings[key] = str(getattr(settings, key))

        # Check installed libraries versions
        import fastapi
        import sqlalchemy
        fastapi_version = fastapi.__version__
        sqlalchemy_version = sqlalchemy.__version__

        return {
            "environment": settings.ENVIRONMENT,
            "python_version": sys.version,
            "os": f"{platform.system()} {platform.release()}",
            "fastapi_version": fastapi_version,
            "sqlalchemy_version": sqlalchemy_version,
            "settings": curated_settings
        }

    @classmethod
    def get_health_status(cls, db: Session) -> List[Dict[str, Any]]:
        health = []
        
        # FastAPI
        health.append({
            "service": "FastAPI Service",
            "status": "HEALTHY",
            "message": "API gateway is running and responding."
        })

        # Database connection
        db_conn = check_db_connection()
        health.append({
            "service": "Database",
            "status": "CONNECTED" if db_conn else "DISCONNECTED",
            "message": "SQLite primary database connection check." if db_conn else "Database connection is down."
        })

        # Storage directory writeable check
        storage_healthy = True
        msg = "Upload storage directory is read/write accessible."
        try:
            test_file = os.path.join("uploads", ".write_test")
            with open(test_file, "w") as f:
                f.write("test")
            os.remove(test_file)
        except Exception as e:
            storage_healthy = False
            msg = f"Storage directory is not writable: {e}"

        health.append({
            "service": "Storage Service",
            "status": "HEALTHY" if storage_healthy else "DEGRADED",
            "message": msg
        })

        # Cache manager directory check
        cache_healthy = True
        cache_msg = "Local asset optimization cache folder is accessible."
        try:
            cache_dir = os.path.join("uploads", "cache")
            os.makedirs(cache_dir, exist_ok=True)
            test_file = os.path.join(cache_dir, ".write_test")
            with open(test_file, "w") as f:
                f.write("test")
            os.remove(test_file)
        except Exception as e:
            cache_healthy = False
            cache_msg = f"Cache folder is not writable: {e}"

        health.append({
            "service": "Cache Manager",
            "status": "HEALTHY" if cache_healthy else "DEGRADED",
            "message": cache_msg
        })

        return health

    @staticmethod
    def read_latest_logs(lines_count: int = 100) -> List[str]:
        log_file = os.path.abspath(os.path.join("logs", "flowspace.log"))
        if not os.path.exists(log_file):
            return ["Log file does not exist yet. Please generate some traffic or log messages first."]

        try:
            # Read last lines_count lines
            with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
                return [line.strip() for line in lines[-lines_count:]]
        except Exception as e:
            return [f"Failed to read log file: {e}"]

    @classmethod
    def get_metrics(cls) -> Dict[str, Any]:
        from core.monitoring.metrics import metrics_manager
        return metrics_manager.get_summary()
