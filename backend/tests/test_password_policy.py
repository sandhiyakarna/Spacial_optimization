import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from datetime import timedelta

from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from core.security.jwt import create_access_token
from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting, Room
from features.auth.services import seed_roles_and_permissions

from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
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

def test_registration_password_complexity():
    # 1. Too short
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd1@example.com",
        "password": "Sh1!"
    })
    assert res.status_code == 422

    # 2. No uppercase
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd2@example.com",
        "password": "lowercase123!"
    })
    assert res.status_code == 422

    # 3. No lowercase
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd3@example.com",
        "password": "UPPERCASE123!"
    })
    assert res.status_code == 422

    # 4. No numbers
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd4@example.com",
        "password": "NoNumbersHere!"
    })
    assert res.status_code == 422

    # 5. No special characters
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd5@example.com",
        "password": "NoSpecialChar123"
    })
    assert res.status_code == 422

    # 6. Valid password
    res = client.post("/api/v1/auth/register", json={
        "full_name": "Test User",
        "email": "pwd_success@example.com",
        "password": "StrongPassword123!"
    })
    assert res.status_code == 201


def test_change_password_policy():
    # Login first
    login_res = client.post("/api/v1/auth/login", json={
        "email": "pwd_success@example.com",
        "password": "StrongPassword123!"
    })
    assert login_res.status_code == 200
    token = login_res.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Change password to a weak one
    res = client.put("/api/v1/auth/change-password", headers=headers, json={
        "current_password": "StrongPassword123!",
        "new_password": "weak"
    })
    assert res.status_code == 422

    # 2. Change password to same password
    res = client.put("/api/v1/auth/change-password", headers=headers, json={
        "current_password": "StrongPassword123!",
        "new_password": "StrongPassword123!"
    })
    assert res.status_code == 400

    # 3. Change password with wrong current password
    res = client.put("/api/v1/auth/change-password", headers=headers, json={
        "current_password": "WrongPassword123!",
        "new_password": "NewStrongPassword123!"
    })
    assert res.status_code == 400

    # 4. Change password successfully
    res = client.put("/api/v1/auth/change-password", headers=headers, json={
        "current_password": "StrongPassword123!",
        "new_password": "NewStrongPassword123!"
    })
    assert res.status_code == 200


def test_reset_password_policy_and_token():
    db = TestingSessionLocal()
    user = db.query(User).filter(User.email == "pwd_success@example.com").first()
    user_id = user.id
    db.close()

    # Create tokens manually
    valid_reset_token = create_access_token(
        data={"sub": user_id, "type": "reset"},
        expires_delta=timedelta(minutes=15)
    )
    wrong_type_token = create_access_token(
        data={"sub": user_id, "type": "access"},
        expires_delta=timedelta(minutes=15)
    )

    # 1. Reset with wrong token type (e.g. access token)
    res = client.post("/api/v1/auth/reset-password", json={
        "token": wrong_type_token,
        "new_password": "AnotherStrongPassword123!"
    })
    assert res.status_code == 400
    assert "Invalid or expired reset token" in res.json()["detail"]

    # 2. Reset with weak password
    res = client.post("/api/v1/auth/reset-password", json={
        "token": valid_reset_token,
        "new_password": "weak"
    })
    assert res.status_code == 422

    # 3. Reset successfully
    res = client.post("/api/v1/auth/reset-password", json={
        "token": valid_reset_token,
        "new_password": "FinalStrongPassword123!"
    })
    assert res.status_code == 200

    # 4. Try logging in with the reset password
    login_res = client.post("/api/v1/auth/login", json={
        "email": "pwd_success@example.com",
        "password": "FinalStrongPassword123!"
    })
    assert login_res.status_code == 200
