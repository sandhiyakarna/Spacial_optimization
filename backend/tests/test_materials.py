import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.dependencies import get_db
from core.database.session import Base

# Import models to ensure they are registered on the test database
from features.auth.models import User, Role, Permission, UserPreference, UserSession, AuditLog
from features.project.models import Project, ProjectSetting
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.material.models import MaterialCategory, Material, MaterialTexture

from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from features.material.services import MaterialService

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
    MaterialService.seed_default_materials(db)
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Material Tester",
        email="material@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_material_endpoints():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "material@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Get list of all categories
    cat_resp = client.get("/api/v1/materials/categories", headers=headers)
    assert cat_resp.status_code == 200
    categories = cat_resp.json()["data"]
    category_names = [c["name"] for c in categories]
    for c_name in ["Wood", "Marble", "Granite", "Concrete", "Metal", "Glass", "Leather", "Fabric", "Ceramic", "Paint"]:
        assert c_name in category_names

    # Get Wood category id for creation later
    wood_cat_id = next(c["id"] for c in categories if c["name"] == "Wood")

    # 3. Get list of materials (unfiltered)
    list_resp = client.get("/api/v1/materials", headers=headers)
    assert list_resp.status_code == 200
    res_data = list_resp.json()
    assert res_data["success"] is True
    assert res_data["total"] >= 10
    materials = res_data["data"]
    
    # Check structure
    oak = next((m for m in materials if m["name"] == "Oak Wood"), None)
    assert oak is not None
    assert oak["base_color"] == "#D27D2D"
    assert oak["category"]["name"] == "Wood"
    assert oak["opacity"] == 1.0
    assert len(oak["textures"]) >= 2

    # 4. Search filter
    search_resp = client.get("/api/v1/materials?search=Oak", headers=headers)
    assert search_resp.status_code == 200
    search_data = search_resp.json()["data"]
    assert len(search_data) == 1
    assert search_data[0]["name"] == "Oak Wood"

    # 5. Category filter
    filter_resp = client.get("/api/v1/materials?category=Wood", headers=headers)
    assert filter_resp.status_code == 200
    filter_data = filter_resp.json()["data"]
    assert len(filter_data) >= 2
    for m in filter_data:
        assert m["category"]["name"] == "Wood"

    # 6. Create custom material
    create_payload = {
        "name": "Custom Mahogany",
        "category_id": wood_cat_id,
        "base_color": "#C04000",
        "preview_image": "/static/materials/mahogany.png",
        "opacity": 1.0,
        "reflectivity": 0.3,
        "default_scale": 1.0,
        "textures": [
            {"texture_type": "base_color", "file_path": "/static/textures/mahogany_base.png"},
            {"texture_type": "normal", "file_path": "/static/textures/mahogany_normal.png"}
        ]
    }
    create_resp = client.post("/api/v1/materials", json=create_payload, headers=headers)
    assert create_resp.status_code == 201
    custom_mat = create_resp.json()["data"]
    custom_mat_id = custom_mat["id"]
    assert custom_mat["name"] == "Custom Mahogany"
    assert len(custom_mat["textures"]) == 2

    # 7. Get details of created material
    detail_resp = client.get(f"/api/v1/materials/{custom_mat_id}", headers=headers)
    assert detail_resp.status_code == 200
    assert detail_resp.json()["data"]["name"] == "Custom Mahogany"

    # 8. Update material
    update_payload = {
        "name": "Updated Mahogany",
        "base_color": "#A03000",
        "reflectivity": 0.4
    }
    update_resp = client.put(f"/api/v1/materials/{custom_mat_id}", json=update_payload, headers=headers)
    assert update_resp.status_code == 200
    updated_mat = update_resp.json()["data"]
    assert updated_mat["name"] == "Updated Mahogany"
    assert updated_mat["base_color"] == "#A03000"
    assert updated_mat["reflectivity"] == 0.4

    # 9. Apply Material to Furniture Asset
    apply_resp = client.post(
        f"/api/v1/furniture/SOFA001/material",
        json={"material_id": custom_mat_id},
        headers=headers
    )
    assert apply_resp.status_code == 200
    apply_data = apply_resp.json()
    assert apply_data["success"] is True
    assert apply_data["data"]["furniture_id"] == "SOFA001"
    assert apply_data["data"]["material_id"] == custom_mat_id
    assert apply_data["data"]["material_name"] == "Updated Mahogany"

    # 10. Delete material
    del_resp = client.delete(f"/api/v1/materials/{custom_mat_id}", headers=headers)
    assert del_resp.status_code == 200
    assert del_resp.json()["success"] is True

    # 11. Verify deleted material returns 404
    missing_resp = client.get(f"/api/v1/materials/{custom_mat_id}", headers=headers)
    assert missing_resp.status_code == 404


def test_material_validation_and_errors():
    # Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "material@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Try to create material with non-existent category_id
    create_payload = {
        "name": "Invalid Category Material",
        "category_id": "non-existent-category-id",
        "base_color": "#FFFFFF",
        "opacity": 1.0,
        "reflectivity": 0.0,
        "default_scale": 1.0
    }
    create_resp = client.post("/api/v1/materials", json=create_payload, headers=headers)
    assert create_resp.status_code == 400
    assert "not found" in create_resp.json()["detail"]

    # 2. Try to get details of a non-existent material
    get_resp = client.get("/api/v1/materials/non-existent-material-id", headers=headers)
    assert get_resp.status_code == 404

    # 3. Try to update a non-existent material
    update_payload = {
        "name": "Non-existent Update"
    }
    update_resp = client.put("/api/v1/materials/non-existent-material-id", json=update_payload, headers=headers)
    assert update_resp.status_code == 404

    # 4. Try to delete a non-existent material
    del_resp = client.delete("/api/v1/materials/non-existent-material-id", headers=headers)
    assert del_resp.status_code == 404


def test_material_file_uploads():
    import io
    import os
    
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "material@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Get list of categories
    cat_resp = client.get("/api/v1/materials/categories", headers=headers)
    wood_cat_id = cat_resp.json()["data"][0]["id"]

    # 3. Create a test material
    create_payload = {
        "name": "Upload Test Material",
        "category_id": wood_cat_id,
        "base_color": "#A0B0C0",
        "opacity": 0.9,
        "reflectivity": 0.5,
        "default_scale": 1.0,
        "textures": []
    }
    create_resp = client.post("/api/v1/materials", json=create_payload, headers=headers)
    assert create_resp.status_code == 201
    material_id = create_resp.json()["data"]["id"]

    # 4. Upload Preview Image
    preview_file_data = b"fake_png_data_for_preview"
    preview_file = io.BytesIO(preview_file_data)
    
    upload_prev_resp = client.post(
        f"/api/v1/materials/{material_id}/upload-preview",
        files={"file": ("test_preview.png", preview_file, "image/png")},
        headers=headers
    )
    assert upload_prev_resp.status_code == 200
    data = upload_prev_resp.json()["data"]
    assert data["preview_image"].startswith("/uploads/materials/previews/")
    
    physical_preview_path = data["preview_image"].lstrip("/")
    assert os.path.exists(physical_preview_path)

    # 5. Upload Texture Map (Roughness)
    texture_file_data = b"fake_jpg_data_for_roughness"
    texture_file = io.BytesIO(texture_file_data)
    
    upload_tex_resp = client.post(
        f"/api/v1/materials/{material_id}/upload-texture?texture_type=roughness",
        files={"file": ("test_roughness.jpg", texture_file, "image/jpeg")},
        headers=headers
    )
    assert upload_tex_resp.status_code == 200
    data = upload_tex_resp.json()["data"]
    assert len(data["textures"]) == 1
    assert data["textures"][0]["texture_type"] == "roughness"
    assert data["textures"][0]["file_path"].startswith("/uploads/materials/textures/")
    
    physical_texture_path = data["textures"][0]["file_path"].lstrip("/")
    assert os.path.exists(physical_texture_path)

    # 6. Test Invalid File Extension (TXT)
    invalid_file = io.BytesIO(b"some text")
    upload_invalid_resp = client.post(
        f"/api/v1/materials/{material_id}/upload-preview",
        files={"file": ("test.txt", invalid_file, "text/plain")},
        headers=headers
    )
    assert upload_invalid_resp.status_code == 400
    assert "Invalid file extension" in upload_invalid_resp.json()["detail"]

    # 7. Delete Material & Verify File Cleanup
    del_resp = client.delete(f"/api/v1/materials/{material_id}", headers=headers)
    assert del_resp.status_code == 200
    
    assert not os.path.exists(physical_preview_path)
    assert not os.path.exists(physical_texture_path)
    assert not os.path.exists(os.path.dirname(physical_preview_path))
    assert not os.path.exists(os.path.dirname(os.path.dirname(physical_texture_path)))


