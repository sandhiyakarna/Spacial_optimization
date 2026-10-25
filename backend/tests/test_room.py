import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base

# Import all models to ensure registered on metadata
from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister

from tests.db_config import get_test_engine
from typing import List

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
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Room Tester",
        email="room@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_room_lifecycle():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "room@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Room Test Villa",
            "description": "Ergonomic vacation house",
            "location": "Goa"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Living Room",
            "room_type": "Living Room",
            "floor_number": 1,
            "notes": "Spacious main hall",
            "room_color": "#FF5733"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # 4. Get Rooms List
    list_resp = client.get(f"/api/v1/projects/{proj_id}/rooms", headers=headers)
    assert list_resp.status_code == 200
    assert len(list_resp.json()["data"]) == 1
    assert list_resp.json()["data"][0]["room_name"] == "Living Room"
    assert list_resp.json()["data"][0]["room_color"] == "#FF5733"

    # 5. Get Room Details
    details_resp = client.get(f"/api/v1/rooms/{room_id}", headers=headers)
    assert details_resp.status_code == 200
    details = details_resp.json()["data"]
    assert details["room_name"] == "Living Room"
    # Default measurements should exist
    assert details["measurements"]["length"] == 600.0

    # 6. Update Measurements (Validation check: length <= 0 should fail)
    fail_measure_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": -10.0,
            "width": 450,
            "height": 300
        },
        headers=headers
    )
    assert fail_measure_resp.status_code == 422 # Unprocessable Entity validation error

    # Valid measurements update
    measure_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": 700.5,
            "width": 500.0,
            "height": 320.0,
            "floor_thickness": 35.0,
            "wall_thickness": 25.0,
            "ceiling_height": 320.0
        },
        headers=headers
    )
    assert measure_resp.status_code == 200

    # Verify updated measurements
    get_measure = client.get(f"/api/v1/rooms/{room_id}/measurements", headers=headers)
    assert get_measure.status_code == 200
    assert get_measure.json()["data"]["length"] == 700.5
    assert get_measure.json()["data"]["width"] == 500.0

    # 7. Update Room Info
    update_resp = client.put(
        f"/api/v1/rooms/{room_id}",
        json={
            "room_name": "Grand Living Room",
            "room_color": "#00FF00"
        },
        headers=headers
    )
    assert update_resp.status_code == 200
    
    # Verify update
    details_resp = client.get(f"/api/v1/rooms/{room_id}", headers=headers)
    assert details_resp.json()["data"]["room_name"] == "Grand Living Room"
    assert details_resp.json()["data"]["room_color"] == "#00FF00"

    # 8. Duplicate Room
    dup_resp = client.post(f"/api/v1/rooms/{room_id}/duplicate", headers=headers)
    assert dup_resp.status_code == 200
    dup_id = dup_resp.json()["data"]["room_id"]

    # Verify duplicated room measurements are copied
    dup_details = client.get(f"/api/v1/rooms/{dup_id}", headers=headers).json()["data"]
    assert dup_details["room_name"] == "Grand Living Room (Copy)"
    assert dup_details["measurements"]["length"] == 700.5
    assert dup_details["measurements"]["width"] == 500.0

    # 9. Delete Room
    del_resp = client.delete(f"/api/v1/rooms/{room_id}", headers=headers)
    assert del_resp.status_code == 200
    
    # Verify deleted
    get_deleted = client.get(f"/api/v1/rooms/{room_id}", headers=headers)
    assert get_deleted.status_code == 404
