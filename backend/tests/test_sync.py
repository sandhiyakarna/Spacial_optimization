import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base

# Import all models to ensure registered on metadata
from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting, Room
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister

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
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Sync Tester",
        email="sync@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_sync_room_population_in_project_details():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "sync@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Sync Test Mansion",
            "description": "Offline-first sync testing project",
            "location": "Mumbai"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room in that project
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Testing Hall",
            "room_type": "Living Room",
            "floor_number": 1,
            "notes": "Spacious hall for synchronization tests",
            "room_color": "#FF5733"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # 4. Get Project Details and verify rooms list is populated (not placeholder empty list)
    details_resp = client.get(f"/api/v1/projects/{proj_id}", headers=headers)
    assert details_resp.status_code == 200
    details = details_resp.json()["data"]
    assert details["project_name"] == "Sync Test Mansion"
    assert "rooms" in details
    assert len(details["rooms"]) == 1
    assert details["rooms"][0]["id"] == room_id
    assert details["rooms"][0]["room_name"] == "Testing Hall"
    assert details["rooms"][0]["room_type"] == "Living Room"
    assert details["rooms"][0]["room_color"] == "#FF5733"
