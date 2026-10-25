import os
import shutil
import pytest
import logging
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from features.auth.models import User, Role
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.system.service import SystemService

from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace_system.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(scope="module", autouse=True)
def setup_test_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    seed_roles_and_permissions(db)
    
    # 1. Register admin user and elevate their role
    admin_user = AuthService.register_user(db, UserRegister(
        full_name="Admin Tester",
        email="admin_test@example.com",
        password="Password123!"
    ))
    admin_role = db.query(Role).filter(Role.name == "Administrator").first()
    admin_user.role_id = admin_role.id
    db.commit()

    # 2. Register a standard customer user
    AuthService.register_user(db, UserRegister(
        full_name="Normal User",
        email="user_test@example.com",
        password="Password123!"
    ))
    db.close()
    
    yield
    
    Base.metadata.drop_all(bind=engine)
    # Cleanup any backup files created during tests
    if os.path.exists("backups"):
        shutil.rmtree("backups")
    # Cleanup any cache files created during tests
    cache_dir = os.path.join("uploads", "cache")
    if os.path.exists(cache_dir):
        shutil.rmtree(cache_dir)
    # Cleanup test db file
    db_file = "./test_flowspace_system.db"
    if os.path.exists(db_file):
        try:
            os.remove(db_file)
        except Exception:
            pass

client = TestClient(app)

def test_system_management_flow():
    # --- AUTHENTICATION SETUPS ---
    # Login as admin
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin_test@example.com", "password": "Password123!"}
    )
    assert admin_login.status_code == 200
    admin_token = admin_login.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    # Login as normal user
    user_login = client.post(
        "/api/v1/auth/login",
        json={"email": "user_test@example.com", "password": "Password123!"}
    )
    assert user_login.status_code == 200
    user_token = user_login.json()["data"]["access_token"]
    user_headers = {"Authorization": f"Bearer {user_token}"}

    # --- SECURITY CONTROLS ---
    # Unauthenticated request to system status
    unauth_status = client.get("/api/v1/system/status")
    assert unauth_status.status_code == 401

    # Non-admin request to system status
    nonadmin_status = client.get("/api/v1/system/status", headers=user_headers)
    assert nonadmin_status.status_code == 403

    # --- SYSTEM STATUS DIAGNOSTICS ---
    # Admin request to system status
    status_resp = client.get("/api/v1/system/status", headers=admin_headers)
    assert status_resp.status_code == 200
    data = status_resp.json()

    # Validate schema fields
    assert "health" in data
    assert "storage" in data
    assert "database" in data
    assert "backup" in data
    assert "environment" in data
    assert "cache" in data

    # Validate health details
    health_list = data["health"]
    assert any(h["service"] == "FastAPI Service" for h in health_list)
    assert any(h["service"] == "Database" for h in health_list)

    # Validate storage overview
    storage = data["storage"]
    assert "total_files" in storage
    assert "total_size_formatted" in storage
    assert "disk_usage" in storage
    assert "percent_used" in storage["disk_usage"]

    # Validate database status
    database = data["database"]
    assert database["connected"] is True
    assert database["type"] == "SQLite"
    assert "table_counts" in database
    assert database["table_counts"]["users"] >= 2

    # Validate environment settings (no sensitive data leaks)
    env = data["environment"]
    assert "fastapi_version" in env
    assert "python_version" in env
    assert "settings" in env
    # SECRET_KEY and DATABASE_URL should not be exposed
    assert "SECRET_KEY" not in env["settings"]
    assert "DATABASE_URL" not in env["settings"]

    # --- CACHE PURGING ---
    # Put a test cache file in uploads/cache
    cache_dir = os.path.abspath(os.path.join("uploads", "cache"))
    os.makedirs(cache_dir, exist_ok=True)
    test_cache_file = os.path.join(cache_dir, "test_cache_asset.glb")
    with open(test_cache_file, "w") as f:
        f.write("dummy-glb-content")

    # Purge cache
    purge_resp = client.post("/api/v1/system/cache/purge", headers=admin_headers)
    assert purge_resp.status_code == 200
    purge_data = purge_resp.json()
    assert purge_data["success"] is True
    assert not os.path.exists(test_cache_file)

    # --- DATABASE BACKUP ---
    # Trigger database backup
    # Change DATABASE_URL settings for backup test to use the test db
    from app.config import settings as app_settings
    original_db_url = app_settings.DATABASE_URL
    app_settings.DATABASE_URL = TEST_SQLALCHEMY_DATABASE_URL
    
    try:
        backup_resp = client.post("/api/v1/system/backup", headers=admin_headers)
        assert backup_resp.status_code == 201
        backup_data = backup_resp.json()
        assert backup_data["success"] is True
        filename = backup_data["filename"]
        assert filename.startswith("flowspace_backup_")
        assert filename.endswith(".db")
        
        # Verify file is created in backups/
        backup_file_path = os.path.join("backups", filename)
        assert os.path.exists(backup_file_path)
    finally:
        app_settings.DATABASE_URL = original_db_url

    # Check status again to verify backup list is populated
    status_resp_2 = client.get("/api/v1/system/status", headers=admin_headers)
    assert status_resp_2.status_code == 200
    data_2 = status_resp_2.json()
    assert len(data_2["backup"]["backup_files"]) >= 1

    # --- APP LOGS ---
    # Write some logs to ensure logger file is written
    logger = logging.getLogger("flowspace")
    logger.info("TEST_SYSTEM_LOG_ENTRY_FOR_VERIFICATION")

    # Retrieve logs
    logs_resp = client.get("/api/v1/system/logs?lines=50", headers=admin_headers)
    assert logs_resp.status_code == 200
    logs_data = logs_resp.json()
    assert "logs" in logs_data
    assert "count" in logs_data
    # Assert our test entry is captured in logs list
    assert any("TEST_SYSTEM_LOG_ENTRY_FOR_VERIFICATION" in log for log in logs_data["logs"])

    # --- METRICS TELEMETRY ---
    # Unauthenticated request to metrics
    unauth_metrics = client.get("/api/v1/system/metrics")
    assert unauth_metrics.status_code == 401

    # Request metrics with admin credentials
    metrics_resp = client.get("/api/v1/system/metrics", headers=admin_headers)
    assert metrics_resp.status_code == 200
    metrics_data = metrics_resp.json()
    assert "uptime_seconds" in metrics_data
    assert "total_requests" in metrics_data
    assert "endpoints" in metrics_data
