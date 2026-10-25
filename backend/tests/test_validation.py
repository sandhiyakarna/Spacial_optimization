import pytest
import json
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.models import ValidationRule, ValidationResult, ValidationChecklist
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
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
    seed_furniture_assets(db)
    ValidationService.seed_default_rules(db)
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Validation Tester",
        email="val@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_validation_workflow():
    # 1. Login
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "val@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Val Castle",
            "description": "Validation testing layout",
            "location": "Valhalla"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Living Lab",
            "room_type": "Living Room",
            "floor_number": 1,
            "notes": "Testing safety constraints"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # Update measurements
    meas_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": 600.0,
            "width": 500.0,
            "height": 300.0,
            "floor_thickness": 30.0,
            "wall_thickness": 20.0,
            "ceiling_height": 300.0
        },
        headers=headers
    )
    assert meas_resp.status_code == 200

    # 4. Save layout with overlaps (f1 and f2) and door swing block (f1 near door)
    # Door is at x=50, y=0. Swing zone radius 80cm
    # Window is at x=200, y=0. Clearance zone 50cm
    layout_data = {
        "walls": [],
        "openings": [
            {"id": "d1", "type": "door", "x": 50.0, "y": 0.0, "width": 80.0, "angle": 0.0},
            {"id": "w1", "type": "window", "x": 200.0, "y": 0.0, "width": 100.0, "angle": 0.0}
        ],
        "furniture": [
            {
                "id": "f1",
                "assetId": "SOFA001",
                "name": "Overlapping Sofa 1",
                "width": 200.0,
                "depth": 90.0,
                "height": 80.0,
                "x": 60.0, # Center X
                "z": 50.0, # Center Z
                "rotationY": 0.0
            },
            {
                "id": "f2",
                "assetId": "SOFA001",
                "name": "Overlapping Sofa 2",
                "width": 200.0,
                "depth": 90.0,
                "height": 80.0,
                "x": 70.0, # Overlaps Sofa 1 heavily
                "z": 60.0,
                "rotationY": 0.0
            },
            {
                "id": "f3",
                "assetId": "DESK001",
                "name": "Tall Window Blocker",
                "width": 120.0,
                "depth": 60.0,
                "height": 110.0, # Height > 100 cm
                "x": 200.0, # Blocks window w1
                "z": 30.0,
                "rotationY": 0.0
            }
        ]
    }
    
    save_resp = client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )
    assert save_resp.status_code == 200

    # 5. Run validation API
    run_resp = client.post(
        "/api/v1/validation/run",
        json={"room_id": room_id},
        headers=headers
    )
    assert run_resp.status_code == 200
    res_data = run_resp.json()["data"]
    assert res_data["overall_status"] == "Fail"
    assert len(res_data["errors"]) > 0

    # Verify specific issues are caught
    errors_text = [e["message"] for e in res_data["errors"]]
    warnings_text = [w["message"] for w in res_data["warnings"]]
    
    # Overlap / Collision check
    assert any("collision" in err.lower() or "overlap" in err.lower() for err in errors_text)
    # Door block check
    assert any("blocks the door swing" in err.lower() for err in errors_text)
    # Window block check
    assert any("blocks window access" in wrn.lower() or "blocks natural lighting" in wrn.lower() for wrn in warnings_text)

    # 6. Test results endpoint
    results_resp = client.get(f"/api/v1/validation/{room_id}", headers=headers)
    assert results_resp.status_code == 200
    assert len(results_resp.json()["data"]["errors"]) > 0

    # 7. Test checklist endpoint
    checklist_resp = client.get(f"/api/v1/validation/checklist/{room_id}", headers=headers)
    assert checklist_resp.status_code == 200
    chk_data = checklist_resp.json()["data"]
    assert chk_data["completion_percentage"] < 100.0
    assert chk_data["remaining_issues"] > 0

    # 8. Test summary endpoint
    summary_resp = client.get(f"/api/v1/validation/summary/{room_id}", headers=headers)
    assert summary_resp.status_code == 200
    sum_data = summary_resp.json()["data"]
    assert sum_data["overall_status"] == "Fail"
    assert sum_data["error_count"] > 0
