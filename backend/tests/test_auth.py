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
from features.auth.services import seed_roles_and_permissions

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
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_user_registration_and_login():
    reg_response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Test User",
            "email": "test@example.com",
            "password": "Password123!"
        }
    )
    assert reg_response.status_code == 201
    assert reg_response.json()["success"] is True
    
    dup_response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Another User",
            "email": "test@example.com",
            "password": "Password123!"
        }
    )
    assert dup_response.status_code == 400
    
    login_response = client.post(
        "/api/v1/auth/login",
        json={
            "email": "test@example.com",
            "password": "Password123!"
        }
    )
    assert login_response.status_code == 200
    login_data = login_response.json()
    assert login_data["success"] is True
    assert "access_token" in login_data["data"]
    assert "refresh_token" in login_data["data"]
    
    access_token = login_data["data"]["access_token"]
    refresh_token = login_data["data"]["refresh_token"]

    profile_response = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {access_token}"}
    )
    assert profile_response.status_code == 200
    profile_data = profile_response.json()["data"]
    assert profile_data["email"] == "test@example.com"
    assert profile_data["full_name"] == "Test User"
    assert profile_data["role"] == "Customer"

    fail_profile_response = client.get("/api/v1/auth/profile")
    assert fail_profile_response.status_code in (401, 403)
    
    refresh_response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token}
    )
    assert refresh_response.status_code == 200
    refresh_data = refresh_response.json()
    assert "access_token" in refresh_data["data"]
    new_access_token = refresh_data["data"]["access_token"]

    logout_response = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {new_access_token}"}
    )
    assert logout_response.status_code == 200
    
    logged_out_profile = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {new_access_token}"}
    )
    assert logged_out_profile.status_code == 401

def test_email_verification():
    # 1. Register user
    reg_response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Verify User",
            "email": "verify@example.com",
            "password": "Password123!"
        }
    )
    assert reg_response.status_code == 201
    
    # 2. Login
    login_response = client.post(
        "/api/v1/auth/login",
        json={
            "email": "verify@example.com",
            "password": "Password123!"
        }
    )
    assert login_response.status_code == 200
    token = login_response.json()["data"]["access_token"]
    
    # 3. Check profile (should be unverified)
    profile_response = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert profile_response.status_code == 200
    assert profile_response.json()["data"]["is_verified"] is False
    
    # 4. Request verification token
    req_response = client.post(
        "/api/v1/auth/request-verification",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert req_response.status_code == 200
    verify_token = req_response.json()["data"]["token"]
    assert verify_token is not None
    
    # 5. Verify email
    verify_response = client.post(
        "/api/v1/auth/verify-email",
        json={"token": verify_token}
    )
    assert verify_response.status_code == 200
    assert verify_response.json()["success"] is True
    
    # 6. Check profile again (should be verified)
    profile_response = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert profile_response.status_code == 200
    assert profile_response.json()["data"]["is_verified"] is True

def test_remember_me():
    from core.security.jwt import decode_access_token
    
    # Login with remember_me = False
    login_false = client.post(
        "/api/v1/auth/login",
        json={
            "email": "verify@example.com",
            "password": "Password123!",
            "remember_me": False
        }
    )
    assert login_false.status_code == 200
    rt_false = login_false.json()["data"]["refresh_token"]
    payload_false = decode_access_token(rt_false)
    exp_false = payload_false.get("exp")
    
    # Login with remember_me = True
    login_true = client.post(
        "/api/v1/auth/login",
        json={
            "email": "verify@example.com",
            "password": "Password123!",
            "remember_me": True
        }
    )
    assert login_true.status_code == 200
    rt_true = login_true.json()["data"]["refresh_token"]
    payload_true = decode_access_token(rt_true)
    exp_true = payload_true.get("exp")
    
    # True should expire later than False (by about 23 days difference since 30 days vs 7 days)
    diff = exp_true - exp_false
    assert diff > 1900000

def test_logout_all():
    # Login 1
    login1 = client.post(
        "/api/v1/auth/login",
        json={
            "email": "verify@example.com",
            "password": "Password123!"
        }
    )
    assert login1.status_code == 200
    token1 = login1.json()["data"]["access_token"]
    
    # Login 2
    login2 = client.post(
        "/api/v1/auth/login",
        json={
            "email": "verify@example.com",
            "password": "Password123!"
        }
    )
    assert login2.status_code == 200
    token2 = login2.json()["data"]["access_token"]
    
    # Verify both can access profile
    assert client.get("/api/v1/auth/profile", headers={"Authorization": f"Bearer {token1}"}).status_code == 200
    assert client.get("/api/v1/auth/profile", headers={"Authorization": f"Bearer {token2}"}).status_code == 200
    
    # Logout all using token1
    logout_all_resp = client.post(
        "/api/v1/auth/logout-all",
        headers={"Authorization": f"Bearer {token1}"}
    )
    assert logout_all_resp.status_code == 200
    
    # Verify both tokens are now invalid
    assert client.get("/api/v1/auth/profile", headers={"Authorization": f"Bearer {token1}"}).status_code == 401
    assert client.get("/api/v1/auth/profile", headers={"Authorization": f"Bearer {token2}"}).status_code == 401
