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
        full_name="Project Tester",
        email="project@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_project_lifecycle():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "project@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Test Villa",
            "description": "Ergonomic vacation house",
            "location": "Goa"
        },
        headers=headers
    )
    assert create_resp.status_code == 201
    proj_id = create_resp.json()["data"]["project_id"]

    # 3. Duplicate name check
    dup_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Test Villa",
            "description": "Duplicate Name Project",
            "location": "Goa"
        },
        headers=headers
    )
    assert dup_resp.status_code == 400

    # 4. Get Project Details
    details_resp = client.get(f"/api/v1/projects/{proj_id}", headers=headers)
    assert details_resp.status_code == 200
    details = details_resp.json()["data"]
    assert details["project_name"] == "Test Villa"
    assert details["settings"]["measurement_unit"] == "Centimeters"

    # 5. Update Project
    update_resp = client.put(
        f"/api/v1/projects/{proj_id}",
        json={
            "project_name": "Updated Villa",
            "description": "Vacation house updated description",
            "is_favorite": True
        },
        headers=headers
    )
    assert update_resp.status_code == 200
    
    # Verify updated favorite status
    details_resp = client.get(f"/api/v1/projects/{proj_id}", headers=headers)
    assert details_resp.json()["data"]["is_favorite"] is True
    assert details_resp.json()["data"]["project_name"] == "Updated Villa"

    # 6. Duplicate Project
    dup_action_resp = client.post(f"/api/v1/projects/{proj_id}/duplicate", headers=headers)
    assert dup_action_resp.status_code == 200
    dup_id = dup_action_resp.json()["data"]["project_id"]

    # Verify duplicate name exists
    dup_details = client.get(f"/api/v1/projects/{dup_id}", headers=headers).json()["data"]
    assert dup_details["project_name"] == "Updated Villa (Copy)"

    # 7. Get Projects List
    list_resp = client.get("/api/v1/projects", headers=headers)
    assert list_resp.status_code == 200
    assert len(list_resp.json()["data"]) == 2

    # 8. Archive Project
    archive_resp = client.patch(f"/api/v1/projects/{proj_id}/archive", headers=headers)
    assert archive_resp.status_code == 200
    assert client.get(f"/api/v1/projects/{proj_id}", headers=headers).json()["data"]["status"] == "Archived"

    # 9. Dashboard summary check
    dash_resp = client.get("/api/v1/dashboard", headers=headers)
    assert dash_resp.status_code == 200
    summary = dash_resp.json()["data"]
    assert summary["total_projects"] == 2
    assert len(summary["recent_projects"]) == 2
    
    # 10. Delete Project
    delete_resp = client.delete(f"/api/v1/projects/{proj_id}", headers=headers)
    assert delete_resp.status_code == 200
    list_resp_deleted = client.get("/api/v1/projects", headers=headers)
    assert len(list_resp_deleted.json()["data"]) == 1
