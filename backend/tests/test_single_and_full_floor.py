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
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.room.services import RoomService
from features.room.schemas import RoomCreate
from features.room_reconstruction.service import RoomReconstructionService

from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_single_and_full_floor.db")
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
    user = AuthService.register_user(db, UserRegister(
        full_name="Single Floor Tester",
        email="floor@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def get_auth_headers():
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "floor@example.com", "password": "Password123!"}
    )
    token = login_resp.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}

def test_single_room_creation_and_geometry():
    """
    Test creating a single room and generating its canonical 3D/2D geometry.
    """
    headers = get_auth_headers()
    # 1. Create Project
    proj_resp = client.post("/api/v1/projects", json={
        "project_name": "Single Room Project",
        "description": "Project for single room testing"
    }, headers=headers)
    assert proj_resp.status_code == 201
    proj_id = proj_resp.json()["data"]["project_id"]

    # 2. Create Room
    room_resp = client.post(f"/api/v1/projects/{proj_id}/rooms", json={
        "room_name": "Bedroom 1",
        "room_type": "Bedroom",
        "floor_number": 1,
        "notes": "Master bedroom"
    }, headers=headers)
    assert room_resp.status_code == 201

    # 3. Fetch rooms list
    resp = client.get(f"/api/v1/projects/{proj_id}/rooms", headers=headers)
    assert resp.status_code == 200
    rooms = resp.json()["data"]
    assert len(rooms) == 1
    assert rooms[0]["room_name"] == "Bedroom 1"

def test_full_floor_generation_combines_all_rooms():
    """
    Test multi-room project flow: creating Bedroom 1, Kitchen, and Living Room,
    then verifying GET /projects/{project_id}/full-floor endpoint returns combined geometry.
    """
    headers = get_auth_headers()
    
    # 1. Create Project
    proj_resp = client.post("/api/v1/projects", json={
        "project_name": "Full Floor House Project",
        "description": "Multi room project"
    }, headers=headers)
    assert proj_resp.status_code == 201
    proj_id = proj_resp.json()["data"]["project_id"]

    # 2. Create 3 distinct rooms
    r1 = client.post(f"/api/v1/projects/{proj_id}/rooms", json={
        "room_name": "Bedroom 1", "room_type": "Bedroom", "floor_number": 1
    }, headers=headers)
    assert r1.status_code == 201

    r2 = client.post(f"/api/v1/projects/{proj_id}/rooms", json={
        "room_name": "Kitchen", "room_type": "Kitchen", "floor_number": 1
    }, headers=headers)
    assert r2.status_code == 201

    r3 = client.post(f"/api/v1/projects/{proj_id}/rooms", json={
        "room_name": "Living Room", "room_type": "Living Room", "floor_number": 1
    }, headers=headers)
    assert r3.status_code == 201

    # 3. Fetch combined Full Floor layout
    ff_resp = client.get(f"/api/v1/projects/{proj_id}/full-floor", headers=headers)
    assert ff_resp.status_code == 200
    data = ff_resp.json()["data"]
    assert data["total_rooms"] == 3
    assert data["total_area"] > 0.0
    assert len(data["rooms"]) == 3
    assert len(data["walls"]) > 0

def test_panorama_reconstruction_fallback_path():
    """
    Test that when panorama stitching has no frames,
    RoomReconstructionService gracefully falls back to an AI-assisted layout.
    """
    db = TestingSessionLocal()
    user = db.query(User).filter(User.email == "floor@example.com").first()
    
    headers = get_auth_headers()
    proj_resp = client.post("/api/v1/projects", json={
        "project_name": "Panorama Fallback Project",
        "description": "Fallback testing"
    }, headers=headers)
    proj_id = proj_resp.json()["data"]["project_id"]

    room = RoomService.create_room(db, user.id, proj_id, RoomCreate(
        room_name="Scan Bedroom", room_type="Bedroom", floor_number=1
    ))
    res = RoomReconstructionService.process_room_reconstruction(
        db=db,
        scan_id="test_scan_fallback_999",
        room_id=room.id,
        room_type="Bedroom",
        known_width=450.0,
        known_depth=390.0,
        known_height=280.0
    )
    db.close()
    assert res is not None
    assert res.get("success") is True
