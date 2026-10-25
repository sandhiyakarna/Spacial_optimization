import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base

from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.export.models import Report

from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.validation.service import ValidationService

from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace.db")
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
    ValidationService.seed_default_rules(db)
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Exporter Tester",
        email="export@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_export_backup_restore_reports():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "export@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Export Villa",
            "description": "Ergonomic vacation mansion",
            "location": "Maldives"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Living Hall",
            "room_type": "Living Room",
            "floor_number": 1,
            "notes": "Large room with sea view",
            "room_color": "#00FF00"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # 4. Save Measurements
    meas_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": 800.0,
            "width": 600.0,
            "height": 350.0,
            "floor_thickness": 30.0,
            "wall_thickness": 20.0,
            "ceiling_height": 350.0
        },
        headers=headers
    )
    assert meas_resp.status_code == 200

    # 5. Save Layout Data
    fake_layout = '{"walls":[],"doors":[],"windows":[],"furniture":[{"id":"SOFA001","name":"Modern Sofa","category":"Living Room","x":400.0,"z":300.0,"width":200.0,"depth":90.0,"height":80.0}]}'
    save_layout_resp = client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": fake_layout},
        headers=headers
    )
    assert save_layout_resp.status_code == 200

    # 6. Generate PDF Report
    gen_report_resp = client.post(
        "/api/v1/reports/generate",
        json={
            "project_id": proj_id,
            "room_id": room_id,
            "report_type": "Design Report",
            "format": "PDF"
        },
        headers=headers
    )
    assert gen_report_resp.status_code == 201
    report_id = gen_report_resp.json()["data"]["report_id"]

    # 7. Check Report Status and download
    # Since background tasks run sequentially/synchronously in TestClient, it is already Completed
    status_resp = client.get(f"/api/v1/reports/{report_id}/status", headers=headers)
    assert status_resp.status_code == 200
    assert status_resp.json()["data"]["status"] == "Completed"

    # Download PDF
    download_resp = client.get(f"/api/v1/reports/{report_id}/download", headers=headers)
    assert download_resp.status_code == 200
    assert download_resp.headers["content-type"] == "application/pdf"

    # 8. Generate PNG Report
    gen_png_resp = client.post(
        "/api/v1/reports/generate",
        json={
            "project_id": proj_id,
            "room_id": room_id,
            "report_type": "Design Report",
            "format": "PNG"
        },
        headers=headers
    )
    assert gen_png_resp.status_code == 201
    png_report_id = gen_png_resp.json()["data"]["report_id"]
    
    # Download PNG
    download_png_resp = client.get(f"/api/v1/reports/{png_report_id}/download", headers=headers)
    assert download_png_resp.status_code == 200
    assert download_png_resp.headers["content-type"] == "image/png"

    # 9. Get Report History
    history_resp = client.get(f"/api/v1/reports/history/{proj_id}", headers=headers)
    assert history_resp.status_code == 200
    assert len(history_resp.json()["data"]) >= 2

    # 10. Direct Export Room (JSON)
    export_room_resp = client.post(
        "/api/v1/export/room",
        json={"room_id": room_id, "format": "JSON"},
        headers=headers
    )
    assert export_room_resp.status_code == 200
    assert "room_name" in export_room_resp.json()["data"]

    # 11. Direct Export Scene Image
    export_image_resp = client.post(
        "/api/v1/export/image",
        json={"room_id": room_id, "format": "PNG"},
        headers=headers
    )
    assert export_image_resp.status_code == 200
    assert export_image_resp.headers["content-type"] == "image/png"

    # 12. Direct Export Analytics
    export_an_resp = client.post(
        "/api/v1/export/analytics",
        json={"room_id": room_id, "format": "JSON"},
        headers=headers
    )
    assert export_an_resp.status_code == 200
    assert "overall_score" in export_an_resp.json()["data"]

    # 13. Backup Project
    backup_resp = client.post(f"/api/v1/projects/{proj_id}/backup", headers=headers)
    assert backup_resp.status_code == 200
    backup_data = backup_resp.json()
    assert backup_data["project_name"] == "Export Villa"
    assert len(backup_data["rooms"]) == 1

    # 14. Restore Project
    restore_resp = client.post(
        "/api/v1/projects/restore",
        json=backup_data,
        headers=headers
    )
    assert restore_resp.status_code == 200
    new_proj_id = restore_resp.json()["data"]["project_id"]
    assert new_proj_id != proj_id
    
    # Confirm it was imported with the Restored name
    new_proj_details = client.get(f"/api/v1/projects/{new_proj_id}", headers=headers)
    assert new_proj_details.status_code == 200
    assert new_proj_details.json()["data"]["project_name"] == "Export Villa (Restored)"
