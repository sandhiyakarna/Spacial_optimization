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
        full_name="Layout Tester",
        email="layout@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_layout_saving_and_loading():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "layout@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Layout Test Villa",
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
            "room_name": "Studio",
            "room_type": "Office",
            "floor_number": 1,
            "notes": "Work office space",
            "room_color": "#000000"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # 4. Save Layout
    fake_layout_data = '{"walls":[{"x1":0,"y1":0,"x2":100,"y2":0},{"x1":100,"y1":0,"x2":100,"y2":100}],"doors":[],"windows":[]}'
    save_resp = client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": fake_layout_data},
        headers=headers
    )
    assert save_resp.status_code == 200

    # 5. Load Layout and Verify
    load_resp = client.get(f"/api/v1/rooms/{room_id}/layout", headers=headers)
    assert load_resp.status_code == 200
    assert load_resp.json()["layout_data"] == fake_layout_data
