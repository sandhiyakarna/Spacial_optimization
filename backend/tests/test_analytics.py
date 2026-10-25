import pytest
import json
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from features.auth.models import User, Role, Permission
from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.models import (
    AIJob, AIResult, AIHistory, ValidationRule, ValidationResult,
    ValidationChecklist, Analytics, RoomScore, DesignHistory, RecommendationHistory
)
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets

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
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Analytics Tester",
        email="analytics_test@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_analytics_features():
    # 1. Login
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "analytics_test@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Analytics Suite Project",
            "description": "Project for testing design health insights",
            "location": "New York"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Living Room Alpha",
            "room_type": "Living Room",
            "floor_number": 1,
            "notes": "Testing room"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # Add measurements (required for analytics)
    meas_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": 500.0,
            "width": 400.0,
            "height": 300.0,
            "floor_thickness": 30.0,
            "wall_thickness": 20.0,
            "ceiling_height": 300.0
        },
        headers=headers
    )
    assert meas_resp.status_code == 200

    # Save room layout with some furniture to generate history/analytics
    layout_data = {
        "furniture": [
            {"id": "item-1", "name": "Cozy Sofa", "category": "Living Room", "x": 100.0, "z": 100.0, "width": 180.0, "depth": 90.0, "height": 80.0, "rotationY": 0.0, "clearance": 50.0},
            {"id": "item-2", "name": "Coffee Table", "category": "Living Room", "x": 100.0, "z": 220.0, "width": 100.0, "depth": 60.0, "height": 40.0, "rotationY": 0.0, "clearance": 30.0}
        ],
        "openings": [
            {"x": 10.0, "y": 0.0, "width": 80.0, "type": "door"}
        ]
    }
    layout_resp = client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )
    assert layout_resp.status_code == 200

    # 4. Get Dashboard Analytics
    dash_resp = client.get(f"/api/v1/analytics/{room_id}", headers=headers)
    assert dash_resp.status_code == 200
    dash_data = dash_resp.json()["data"]
    assert "overall_score" in dash_data
    assert "space_utilization" in dash_data
    assert "accessibility_score" in dash_data

    # 5. Get Detailed Scores
    scores_resp = client.get(f"/api/v1/analytics/{room_id}/scores", headers=headers)
    assert scores_resp.status_code == 200
    scores_data = scores_resp.json()["data"]
    assert "subscores" in scores_data

    # 6. Get Room Statistics
    stats_resp = client.get(f"/api/v1/analytics/statistics/{room_id}", headers=headers)
    assert stats_resp.status_code == 200
    stats_data = stats_resp.json()["data"]
    assert stats_data["furniture_count"] == 2
    assert stats_data["occupied_area"] == (180.0 * 90.0) + (100.0 * 60.0)
    assert stats_data["estimated_cost"] == 895.71 # sofa + table with size multipliers
    assert "walkway_coverage" in stats_data
    assert "free_area" in stats_data

    # 7. Get Design Insights
    insights_resp = client.get(f"/api/v1/analytics/insights/{room_id}", headers=headers)
    assert insights_resp.status_code == 200
    insights_list = insights_resp.json()["data"]
    assert len(insights_list) > 0

    # 8. Save another room layout (Version 2)
    layout_data_v2 = {
        "furniture": [
            {"id": "item-1", "name": "Cozy Sofa", "category": "Living Room", "x": 150.0, "z": 150.0, "width": 180.0, "depth": 90.0, "height": 80.0, "rotationY": 0.0, "clearance": 50.0}
        ],
        "openings": [
            {"x": 10.0, "y": 0.0, "width": 80.0, "type": "door"}
        ]
    }
    layout_resp_v2 = client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data_v2)},
        headers=headers
    )
    assert layout_resp_v2.status_code == 200

    # 9. Get History Timeline
    hist_resp = client.get(f"/api/v1/analytics/history/{room_id}", headers=headers)
    assert hist_resp.status_code == 200
    hist_list = hist_resp.json()["data"]
    assert len(hist_list) >= 2
    assert hist_list[0]["version_number"] == 1
    assert "id" in hist_list[0]
    assert hist_list[1]["version_number"] == 2

    # 10. Compare Layouts
    comp_resp = client.post(
        "/api/v1/analytics/compare",
        json={"layout_a": room_id, "layout_b": room_id},
        headers=headers
    )
    assert comp_resp.status_code == 200
    comp_data = comp_resp.json()["data"]
    assert "winner" in comp_data
    assert "score_difference" in comp_data
    assert len(comp_data["recommendations"]) > 0

    # 11. Project Analytics
    proj_resp = client.get(f"/api/v1/analytics/project/{proj_id}", headers=headers)
    assert proj_resp.status_code == 200
    proj_data = proj_resp.json()["data"]
    assert proj_data["total_rooms"] == 1
    assert len(proj_data["room_scores"]) == 1
    assert proj_data["total_furniture_count"] == 1 # based on version 2 which has 1 item

    # 12. History Restore
    restore_resp = client.post(
        "/api/v1/analytics/history/restore",
        json={"room_id": room_id, "version_number": 1},
        headers=headers
    )
    assert restore_resp.status_code == 200
    
    # Confirm it is restored to version 1 furniture count (which was 2 items)
    stats_resp_restored = client.get(f"/api/v1/analytics/statistics/{room_id}", headers=headers)
    assert stats_resp_restored.json()["data"]["furniture_count"] == 2

    # 13. Admin Telemetry - Unauthorized (Customer Role)
    telemetry_unauth = client.get("/api/v1/analytics/admin/system?period=7d", headers=headers)
    assert telemetry_unauth.status_code == 403

    # 14. Admin Telemetry - Authorized (Elevating to Administrator)
    db = TestingSessionLocal()
    user = db.query(User).filter(User.email == "analytics_test@example.com").first()
    admin_role = db.query(Role).filter(Role.name == "Administrator").first()
    user.role_id = admin_role.id
    db.commit()
    db.close()

    telemetry_auth = client.get("/api/v1/analytics/admin/system?period=7d", headers=headers)
    assert telemetry_auth.status_code == 200
    tel_data = telemetry_auth.json()["data"]
    
    assert "active_users" in tel_data
    assert tel_data["active_users"]["total_users"] >= 1
    assert "furniture_usage" in tel_data
    assert tel_data["furniture_usage"]["total_assets"] >= 0
    assert "project_statistics" in tel_data
    assert "ai_usage" in tel_data
    assert "storage_usage" in tel_data
    assert tel_data["storage_usage"]["limit_bytes"] == 5.0 * 1024 * 1024 * 1024
    assert "export_statistics" in tel_data
    assert "charts" in tel_data
    assert len(tel_data["charts"]["dau_trend"]) == 7

