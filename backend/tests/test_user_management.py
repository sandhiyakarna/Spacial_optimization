import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from features.auth.models import User, Role, Permission, UserSession, UserPreference
from features.auth.services import seed_roles_and_permissions, AuthService

from tests.db_config import get_test_engine
from typing import List

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace_pwd.db")
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

def create_test_user_with_role(email: str, name: str, role_name: str) -> str:
    db = TestingSessionLocal()
    role = db.query(Role).filter(Role.name == role_name).first()
    from core.security.jwt import hash_password
    user = User(
        full_name=name,
        email=email,
        password_hash=hash_password("Password123!"),
        role_id=role.id,
        is_active=True,
        is_verified=True
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    
    # default pref
    pref = UserPreference(user_id=user.id)
    db.add(pref)
    db.commit()
    
    user_id = user.id
    db.close()
    return user_id

def test_admin_and_customer_access():
    # Create an admin user and a customer user
    admin_id = create_test_user_with_role("admin@example.com", "System Admin", "Administrator")
    customer_id = create_test_user_with_role("customer@example.com", "Regular Customer", "Customer")
    
    # 1. Login both users to get their access tokens
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    assert admin_login.status_code == 200
    admin_token = admin_login.json()["data"]["access_token"]
    
    customer_login = client.post(
        "/api/v1/auth/login",
        json={"email": "customer@example.com", "password": "Password123!"}
    )
    assert customer_login.status_code == 200
    customer_token = customer_login.json()["data"]["access_token"]
    
    # 2. Test Customer access (should be 403 Forbidden)
    cust_get_users = client.get(
        "/api/v1/auth/admin/users",
        headers={"Authorization": f"Bearer {customer_token}"}
    )
    assert cust_get_users.status_code == 403
    
    # 3. Test Admin access (should be 200 OK)
    admin_get_users = client.get(
        "/api/v1/auth/admin/users",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert admin_get_users.status_code == 200
    users_data = admin_get_users.json()["data"]
    assert len(users_data) >= 2
    
    # Verify seeded roles and permissions listing
    roles_resp = client.get(
        "/api/v1/auth/admin/roles",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert roles_resp.status_code == 200
    roles = roles_resp.json()["data"]
    assert any(r["name"] == "Administrator" for r in roles)
    
    # Check permissions list
    perms_resp = client.get(
        "/api/v1/auth/admin/permissions",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert perms_resp.status_code == 200
    perms = perms_resp.json()["data"]
    assert any(p["name"] == "view_users" for p in perms)

def test_change_user_role():
    # Setup test token for Admin
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = admin_login.json()["data"]["access_token"]
    
    # Create customer user to modify role
    user_id = create_test_user_with_role("to_change@example.com", "Change Me", "Customer")
    
    # Change role to Architect
    change_resp = client.put(
        f"/api/v1/auth/admin/users/{user_id}/role",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"role_name": "Architect"}
    )
    assert change_resp.status_code == 200
    
    # Verify role was changed
    users_resp = client.get(
        "/api/v1/auth/admin/users",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    users = users_resp.json()["data"]
    modified_user = next(u for u in users if u["id"] == user_id)
    assert modified_user["role"] == "Architect"

def test_suspend_and_activate_user():
    # Setup test token for Admin
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = admin_login.json()["data"]["access_token"]
    
    # Create customer user
    user_id = create_test_user_with_role("suspend@example.com", "Suspend User", "Customer")
    
    # Login user to create active session
    user_login = client.post(
        "/api/v1/auth/login",
        json={"email": "suspend@example.com", "password": "Password123!"}
    )
    assert user_login.status_code == 200
    user_token = user_login.json()["data"]["access_token"]
    
    # Verify user session is active
    profile_resp = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {user_token}"}
    )
    assert profile_resp.status_code == 200
    
    # Suspend user
    suspend_resp = client.post(
        f"/api/v1/auth/admin/users/{user_id}/suspend",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert suspend_resp.status_code == 200
    
    # Verify user token is rejected now (inactive)
    profile_resp = client.get(
        "/api/v1/auth/profile",
        headers={"Authorization": f"Bearer {user_token}"}
    )
    assert profile_resp.status_code == 401
    
    # Activate user
    activate_resp = client.post(
        f"/api/v1/auth/admin/users/{user_id}/activate",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert activate_resp.status_code == 200
    
    # Login again to confirm they can access again
    user_login_2 = client.post(
        "/api/v1/auth/login",
        json={"email": "suspend@example.com", "password": "Password123!"}
    )
    assert user_login_2.status_code == 200

def test_session_management():
    # Setup test token for Admin
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = admin_login.json()["data"]["access_token"]
    
    user_id = create_test_user_with_role("session@example.com", "Session User", "Customer")
    
    # Create two sessions
    sess1 = client.post("/api/v1/auth/login", json={"email": "session@example.com", "password": "Password123!"})
    sess2 = client.post("/api/v1/auth/login", json={"email": "session@example.com", "password": "Password123!"})
    
    token1 = sess1.json()["data"]["access_token"]
    
    # List sessions
    sessions_resp = client.get(
        f"/api/v1/auth/admin/users/{user_id}/sessions",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert sessions_resp.status_code == 200
    sessions_data = sessions_resp.json()["data"]
    assert len(sessions_data) == 2
    assert sessions_data[0]["is_active"] is True
    assert sessions_data[1]["is_active"] is True
    
    # Revoke first session in list
    first_sess_id = sessions_data[0]["id"]
    revoke_resp = client.post(
        f"/api/v1/auth/admin/sessions/{first_sess_id}/revoke",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert revoke_resp.status_code == 200
    
    # Verify in DB that only the first session is inactive
    db = TestingSessionLocal()
    s1 = db.query(UserSession).filter(UserSession.id == sessions_data[0]["id"]).first()
    s2 = db.query(UserSession).filter(UserSession.id == sessions_data[1]["id"]).first()
    assert s1.is_active is False
    assert s2.is_active is True
    db.close()
    
    # Now revoke all sessions for this user
    revoke_all_resp = client.post(
        f"/api/v1/auth/admin/users/{user_id}/sessions/revoke-all",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert revoke_all_resp.status_code == 200
    
    # Verify both are inactive
    db = TestingSessionLocal()
    s1 = db.query(UserSession).filter(UserSession.id == sessions_data[0]["id"]).first()
    s2 = db.query(UserSession).filter(UserSession.id == sessions_data[1]["id"]).first()
    assert s1.is_active is False
    assert s2.is_active is False
    db.close()
    
    # Verify calling profile returns 401 since no active sessions remain
    assert client.get("/api/v1/auth/profile", headers={"Authorization": f"Bearer {token1}"}).status_code == 401

def test_delete_user():
    # Setup test token for Admin
    admin_login = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = admin_login.json()["data"]["access_token"]
    
    user_id = create_test_user_with_role("delete@example.com", "Delete User", "Customer")
    
    # Verify user exists
    users_resp_before = client.get(
        "/api/v1/auth/admin/users",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert any(u["id"] == user_id for u in users_resp_before.json()["data"])
    
    # Delete user
    delete_resp = client.delete(
        f"/api/v1/auth/admin/users/{user_id}",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert delete_resp.status_code == 200
    
    # Verify user is gone
    users_resp_after = client.get(
        "/api/v1/auth/admin/users",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert not any(u["id"] == user_id for u in users_resp_after.json()["data"])
