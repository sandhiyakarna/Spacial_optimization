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
from features.furniture.models import FurnitureAsset, FurnitureCategory, FurnitureMaterial, FurnitureFavorite, FurnitureRecent

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
        full_name="Furniture Tester",
        email="furniture@example.com",
        password="Password123!"
    ))

    # Create admin user
    admin_user = AuthService.register_user(db, UserRegister(
        full_name="Admin Tester",
        email="admin@example.com",
        password="Password123!"
    ))
    admin_role = AuthService.get_role_by_name(db, "Administrator")
    admin_user.role_id = admin_role.id
    db.commit()
    
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_furniture_endpoints():
    # 1. Login to get tokens
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "furniture@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    login_resp_admin = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    assert login_resp_admin.status_code == 200
    admin_token = login_resp_admin.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    # 2. Get list of all furniture (unfiltered)
    list_resp = client.get("/api/v1/furniture", headers=headers)
    assert list_resp.status_code == 200
    furniture_list = list_resp.json()
    assert len(furniture_list) >= 5 # 5 default assets seeded
    
    # Check the first item structure
    sofa = next((f for f in furniture_list if f["id"] == "SOFA001"), None)
    assert sofa is not None
    assert sofa["name"] == "Modern Sofa"
    assert sofa["category"] == "Living Room"
    assert sofa["style"] == "Modern"
    assert sofa["width"] == 210.0
    assert sofa["depth"] == 90.0
    assert sofa["height"] == 85.0
    assert sofa["clearance"] == 60.0
    assert sofa["assembly_clearance"] == 80.0
    assert "modern" in sofa["tags"]
    assert sofa["glb_url"].endswith(".glb")
    assert sofa["thumbnail_url"].endswith(".png")

    # 3. Test filtering by category
    office_resp = client.get("/api/v1/furniture?category=Office", headers=headers)
    assert office_resp.status_code == 200
    office_items = office_resp.json()
    assert len(office_items) >= 2 # Ergonomic Chair, Industrial Desk, etc.
    for item in office_items:
        assert item["category"] == "Office"

    # 4. Test filtering by style
    scand_resp = client.get("/api/v1/furniture?style=Scandinavian", headers=headers)
    assert scand_resp.status_code == 200
    scand_items = scand_resp.json()
    assert len(scand_items) >= 1
    assert any(item["id"] == "TABLE001" for item in scand_items)

    # 5. Test search filter
    search_resp = client.get("/api/v1/furniture?search=ergonomic", headers=headers)
    assert search_resp.status_code == 200
    search_items = search_resp.json()
    assert len(search_items) >= 1
    assert any(item["id"] == "CHAIR001" for item in search_items)

    # 6. Test getting specific asset
    detail_resp = client.get("/api/v1/furniture/SOFA001", headers=headers)
    assert detail_resp.status_code == 200
    assert detail_resp.json()["name"] == "Modern Sofa"

    # 7. Test getting non-existent asset returns 404
    missing_resp = client.get("/api/v1/furniture/NONEXISTENT", headers=headers)
    assert missing_resp.status_code == 404

    # 8. Test Categories API
    cat_list_resp = client.get("/api/v1/furniture/categories", headers=headers)
    assert cat_list_resp.status_code == 200
    cats = cat_list_resp.json()
    assert len(cats) >= 4  # Office, Living Room, Kitchen, Bedroom
    
    # Create new category (User: 403 Forbidden)
    new_cat_fail = client.post(
        "/api/v1/furniture/categories",
        json={"name": "Outdoor", "description": "Patio and garden furniture"},
        headers=headers
    )
    assert new_cat_fail.status_code == 403

    # Create new category (Admin: 201 Created)
    new_cat_resp = client.post(
        "/api/v1/furniture/categories",
        json={"name": "Outdoor", "description": "Patio and garden furniture"},
        headers=admin_headers
    )
    assert new_cat_resp.status_code == 201
    assert new_cat_resp.json()["name"] == "Outdoor"

    # 9. Test CRUD: Create a new asset (User: 403 Forbidden)
    create_fail = client.post(
        "/api/v1/furniture",
        json={
            "name": "Garden Chair",
            "category": "Outdoor",
            "style": "Rustic",
            "width": 60.0,
            "depth": 60.0,
            "height": 90.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "outdoor,wood,chair,garden"
        },
        headers=headers
    )
    assert create_fail.status_code == 403

    # Test dimensional validation (Admin: 400 Bad Request)
    create_invalid = client.post(
        "/api/v1/furniture",
        json={
            "name": "Invalid Chair",
            "category": "Outdoor",
            "style": "Rustic",
            "width": -10.0,
            "depth": 60.0,
            "height": 90.0
        },
        headers=admin_headers
    )
    assert create_invalid.status_code == 400

    # Create a new asset (Admin: 201 Created)
    create_resp = client.post(
        "/api/v1/furniture",
        json={
            "name": "Garden Chair",
            "category": "Outdoor",
            "style": "Rustic",
            "width": 60.0,
            "depth": 60.0,
            "height": 90.0,
            "clearance": 0.0,
            "assembly_clearance": 0.0,
            "tags": "outdoor,wood,chair,garden"
        },
        headers=admin_headers
    )
    assert create_resp.status_code == 201
    new_asset = create_resp.json()
    new_id = new_asset["id"]
    assert new_asset["name"] == "Garden Chair"
    assert new_asset["category"] == "Outdoor"
    assert new_asset["category_id"] is not None

    # 10. Test CRUD: Update the asset (User: 403 Forbidden)
    update_fail = client.put(
        f"/api/v1/furniture/{new_id}",
        json={"name": "Deluxe Garden Chair", "width": 65.0},
        headers=headers
    )
    assert update_fail.status_code == 403

    # Test dimensional validation (Admin: 400 Bad Request)
    update_invalid = client.put(
        f"/api/v1/furniture/{new_id}",
        json={"width": 0.0},
        headers=admin_headers
    )
    assert update_invalid.status_code == 400

    # Update the asset (Admin: 200 OK)
    update_resp = client.put(
        f"/api/v1/furniture/{new_id}",
        json={"name": "Deluxe Garden Chair", "width": 65.0},
        headers=admin_headers
    )
    assert update_resp.status_code == 200
    assert update_resp.json()["name"] == "Deluxe Garden Chair"
    assert update_resp.json()["width"] == 65.0

    # 11. Test Pagination
    page_resp = client.get("/api/v1/furniture?page=1&limit=2", headers=headers)
    assert page_resp.status_code == 200
    paginated_items = page_resp.json()
    assert len(paginated_items) == 2

    # 12. Test Favorites
    favs_resp = client.get("/api/v1/furniture/favorites", headers=headers)
    assert favs_resp.status_code == 200
    assert len(favs_resp.json()) == 0

    fav_post_resp = client.post(f"/api/v1/furniture/{new_id}/favorite", headers=headers)
    assert fav_post_resp.status_code == 200
    assert fav_post_resp.json()["success"] is True

    favs_resp2 = client.get("/api/v1/furniture/favorites", headers=headers)
    assert len(favs_resp2.json()) == 1
    assert favs_resp2.json()[0]["id"] == new_id

    detail_resp2 = client.get(f"/api/v1/furniture/{new_id}", headers=headers)
    assert detail_resp2.json()["is_favorite"] is True

    fav_del_resp = client.delete(f"/api/v1/furniture/{new_id}/favorite", headers=headers)
    assert fav_del_resp.status_code == 200
    assert fav_del_resp.json()["success"] is True

    favs_resp3 = client.get("/api/v1/furniture/favorites", headers=headers)
    assert len(favs_resp3.json()) == 0

    # 13. Test Recently Used tracking
    recent_resp = client.get("/api/v1/furniture/recent", headers=headers)
    assert recent_resp.status_code == 200
    recents = recent_resp.json()
    assert len(recents) >= 1
    assert recents[0]["id"] == new_id

    # 14. Test File Uploads (User: 403 Forbidden)
    import io
    glb_file = io.BytesIO(b"glTFdummy glb content")
    upload_glb_fail = client.post(
        f"/api/v1/furniture/{new_id}/upload-model",
        files={"file": ("test_model.glb", glb_file, "model/gltf-binary")},
        headers=headers
    )
    assert upload_glb_fail.status_code == 403

    # Upload GLB model (Admin: 200 OK)
    glb_file.seek(0)
    upload_glb_resp = client.post(
        f"/api/v1/furniture/{new_id}/upload-model",
        files={"file": ("test_model.glb", glb_file, "model/gltf-binary")},
        headers=admin_headers
    )
    assert upload_glb_resp.status_code == 200
    assert upload_glb_resp.json()["model_path"] is not None
    assert upload_glb_resp.json()["glb_url"].endswith("test_model.glb")

    # Upload Thumbnail (Admin: 200 OK)
    thumb_file = io.BytesIO(b"dummy png content")
    upload_thumb_resp = client.post(
        f"/api/v1/furniture/{new_id}/upload-thumbnail",
        files={"file": ("test_thumb.png", thumb_file, "image/png")},
        headers=admin_headers
    )
    assert upload_thumb_resp.status_code == 200
    assert upload_thumb_resp.json()["thumbnail_path"] is not None
    assert upload_thumb_resp.json()["thumbnail_url"].endswith("test_thumb.png")

    # 15. Test CRUD: Delete the asset (User: 403 Forbidden)
    delete_fail = client.delete(f"/api/v1/furniture/{new_id}", headers=headers)
    assert delete_fail.status_code == 403

    # Delete the asset (Admin: 200 OK)
    delete_resp = client.delete(f"/api/v1/furniture/{new_id}", headers=admin_headers)
    assert delete_resp.status_code == 200
    assert delete_resp.json()["success"] is True

    deleted_get_resp = client.get(f"/api/v1/furniture/{new_id}", headers=headers)
    assert deleted_get_resp.status_code == 404


def test_admin_category_management():
    # Login admin
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = login_resp.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    
    # Login user
    login_resp_user = client.post(
        "/api/v1/auth/login",
        json={"email": "furniture@example.com", "password": "Password123!"}
    )
    user_token = login_resp_user.json()["data"]["access_token"]
    user_headers = {"Authorization": f"Bearer {user_token}"}
    
    # Create category
    cat_resp = client.post(
        "/api/v1/furniture/categories",
        json={"name": "TestCategory", "description": "For testing"},
        headers=admin_headers
    )
    assert cat_resp.status_code == 201
    cat_id = cat_resp.json()["id"]
    
    # User tries to update (403)
    user_upd = client.put(
        f"/api/v1/furniture/categories/{cat_id}",
        json={"name": "UserModified"},
        headers=user_headers
    )
    assert user_upd.status_code == 403
    
    # Admin updates
    admin_upd = client.put(
        f"/api/v1/furniture/categories/{cat_id}",
        json={"name": "AdminModified", "description": "Successfully updated description"},
        headers=admin_headers
    )
    assert admin_upd.status_code == 200
    assert admin_upd.json()["name"] == "AdminModified"
    assert admin_upd.json()["description"] == "Successfully updated description"
    
    # User tries to delete (403)
    user_del = client.delete(f"/api/v1/furniture/categories/{cat_id}", headers=user_headers)
    assert user_del.status_code == 403
    
    # Admin deletes
    admin_del = client.delete(f"/api/v1/furniture/categories/{cat_id}", headers=admin_headers)
    assert admin_del.status_code == 200
    assert admin_del.json()["success"] is True


def test_upload_validation():
    # Login admin
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = login_resp.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    
    # Create dummy furniture item
    create_resp = client.post(
        "/api/v1/furniture",
        json={
            "name": "Validation Dummy Sofa",
            "category": "Living Room",
            "style": "Modern",
            "width": 100.0,
            "depth": 100.0,
            "height": 100.0
        },
        headers=admin_headers
    )
    assert create_resp.status_code == 201
    asset_id = create_resp.json()["id"]
    
    # 1. GLB size limit check (exceeds 50MB)
    import io
    huge_data = b"x" * (51 * 1024 * 1024)
    huge_file = io.BytesIO(huge_data)
    up_resp = client.post(
        f"/api/v1/furniture/{asset_id}/upload-model",
        files={"file": ("too_large.glb", huge_file, "model/gltf-binary")},
        headers=admin_headers
    )
    assert up_resp.status_code == 400
    assert "exceeds the 50MB" in up_resp.json()["detail"]
    
    # 2. GLB extension check
    bad_ext_file = io.BytesIO(b"glTFdummycontent")
    up_resp = client.post(
        f"/api/v1/furniture/{asset_id}/upload-model",
        files={"file": ("invalid_ext.txt", bad_ext_file, "text/plain")},
        headers=admin_headers
    )
    assert up_resp.status_code == 400
    assert "must have .glb extension" in up_resp.json()["detail"]
    
    # 3. GLB magic bytes check
    bad_magic_file = io.BytesIO(b"NOTglTFdummycontent")
    up_resp = client.post(
        f"/api/v1/furniture/{asset_id}/upload-model",
        files={"file": ("invalid_magic.glb", bad_magic_file, "model/gltf-binary")},
        headers=admin_headers
    )
    assert up_resp.status_code == 400
    assert "Invalid GLB file format" in up_resp.json()["detail"]
    
    # 4. Thumbnail size limit check (exceeds 5MB)
    huge_thumb_data = b"y" * (6 * 1024 * 1024)
    huge_thumb_file = io.BytesIO(huge_thumb_data)
    up_resp = client.post(
        f"/api/v1/furniture/{asset_id}/upload-thumbnail",
        files={"file": ("too_large.png", huge_thumb_file, "image/png")},
        headers=admin_headers
    )
    assert up_resp.status_code == 400
    assert "exceeds the 5MB" in up_resp.json()["detail"]
    
    # 5. Thumbnail extension check
    bad_thumb_ext = io.BytesIO(b"pngcontent")
    up_resp = client.post(
        f"/api/v1/furniture/{asset_id}/upload-thumbnail",
        files={"file": ("invalid_ext.txt", bad_thumb_ext, "text/plain")},
        headers=admin_headers
    )
    assert up_resp.status_code == 400
    assert "must be a valid image" in up_resp.json()["detail"]
    
    # Cleanup
    client.delete(f"/api/v1/furniture/{asset_id}", headers=admin_headers)


def test_duplicate_checking():
    # Login admin
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = login_resp.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    
    # 1. Exact name match duplicate
    check_resp = client.post(
        "/api/v1/furniture/check-duplicate",
        json={
            "name": "Modern Sofa",
            "category": "Living Room",
            "style": "Modern",
            "width": 210.0,
            "depth": 90.0,
            "height": 85.0
        },
        headers=admin_headers
    )
    assert check_resp.status_code == 200
    assert check_resp.json()["is_duplicate"] is True
    assert check_resp.json()["duplicate_asset"]["id"] == "SOFA001"
    
    # 2. Dimensions similarity duplicate
    check_resp = client.post(
        "/api/v1/furniture/check-duplicate",
        json={
            "name": "Another Sofa Name",
            "category": "Living Room",
            "style": "Modern",
            "width": 210.0,
            "depth": 90.0,
            "height": 85.0
        },
        headers=admin_headers
    )
    assert check_resp.status_code == 200
    assert check_resp.json()["is_duplicate"] is True
    assert check_resp.json()["duplicate_asset"]["id"] == "SOFA001"
    
    # 3. Unique asset (no duplicate)
    check_resp = client.post(
        "/api/v1/furniture/check-duplicate",
        json={
            "name": "Completely Unique Sofa 2026",
            "category": "Living Room",
            "style": "Modern",
            "width": 10.0,
            "depth": 10.0,
            "height": 10.0
        },
        headers=admin_headers
    )
    assert check_resp.status_code == 200
    assert check_resp.json()["is_duplicate"] is False


def test_bulk_import():
    # Login admin
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = login_resp.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    
    # Prep import data
    import_payload = {
        "assets": [
            {
                "name": "Bulk Valid Sofa",
                "category": "Living Room",
                "style": "Modern",
                "width": 100.0,
                "depth": 100.0,
                "height": 100.0,
                "clearance": 10.0,
                "assembly_clearance": 20.0,
                "tags": "bulk,valid"
            },
            {
                "name": "Modern Sofa",  # Duplicate match
                "category": "Living Room",
                "style": "Modern",
                "width": 210.0,
                "depth": 90.0,
                "height": 85.0
            },
            {
                "name": "Bulk Invalid Sofa",  # Invalid dimension
                "category": "Living Room",
                "style": "Modern",
                "width": -10.0,
                "depth": 100.0,
                "height": 100.0
            }
        ],
        "dry_run": True
    }
    
    # 1. Dry run preparation report
    prep_resp = client.post(
        "/api/v1/furniture/bulk-import",
        json=import_payload,
        headers=admin_headers
    )
    assert prep_resp.status_code == 200
    res = prep_resp.json()
    print("BULK IMPORT RESULT DEBUG:", res)
    assert res["success"] is True
    assert res["total_processed"] == 3
    assert res["valid_count"] == 1
    assert res["duplicate_count"] == 1
    assert res["invalid_count"] == 1
    assert res["imported_count"] == 0
    
    # 2. Commit dry_run=False
    import_payload["dry_run"] = False
    commit_resp = client.post(
        "/api/v1/furniture/bulk-import",
        json=import_payload,
        headers=admin_headers
    )
    assert commit_resp.status_code == 200
    res_commit = commit_resp.json()
    assert res_commit["imported_count"] == 1
    
    # Search for imported item
    search_resp = client.get("/api/v1/furniture?search=Bulk Valid Sofa", headers=admin_headers)
    assert search_resp.status_code == 200
    items = search_resp.json()
    assert len(items) == 1
    assert items[0]["name"] == "Bulk Valid Sofa"
    
    # Clean up imported item
    client.delete(f"/api/v1/furniture/{items[0]['id']}", headers=admin_headers)


def test_bulk_actions_and_file_cleanup():
    # Login admin
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@example.com", "password": "Password123!"}
    )
    admin_token = login_resp.json()["data"]["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}
    
    # 1. Create a dummy asset
    create_resp1 = client.post(
        "/api/v1/furniture",
        json={
            "name": "Bulk Action Sofa 1",
            "category": "Living Room",
            "style": "Modern",
            "width": 100.0,
            "depth": 100.0,
            "height": 100.0
        },
        headers=admin_headers
    )
    asset_id1 = create_resp1.json()["id"]

    create_resp2 = client.post(
        "/api/v1/furniture",
        json={
            "name": "Bulk Action Sofa 2",
            "category": "Living Room",
            "style": "Modern",
            "width": 100.0,
            "depth": 100.0,
            "height": 100.0
        },
        headers=admin_headers
    )
    asset_id2 = create_resp2.json()["id"]
    
    # 2. Test Bulk Update Category
    bulk_cat_resp = client.post(
        "/api/v1/furniture/bulk-update-category",
        json={
            "asset_ids": [asset_id1, asset_id2],
            "category": "BulkCategoryTest"
        },
        headers=admin_headers
    )
    assert bulk_cat_resp.status_code == 200
    assert "Successfully updated category of 2 assets" in bulk_cat_resp.json()["message"]
    
    # Verify the category has changed
    get1 = client.get(f"/api/v1/furniture/{asset_id1}", headers=admin_headers)
    assert get1.json()["category"] == "BulkCategoryTest"
    get2 = client.get(f"/api/v1/furniture/{asset_id2}", headers=admin_headers)
    assert get2.json()["category"] == "BulkCategoryTest"
    
    # 3. Test GLB/Thumbnail file upload cleanup on deletion
    # Let's upload a dummy GLB and thumbnail
    import io
    glb_data = b"glTFdummy glb content"
    glb_file = io.BytesIO(glb_data)
    upload_glb_resp = client.post(
        f"/api/v1/furniture/{asset_id1}/upload-model",
        files={"file": ("test_bulk_model.glb", glb_file, "model/gltf-binary")},
        headers=admin_headers
    )
    assert upload_glb_resp.status_code == 200
    model_path = upload_glb_resp.json()["model_path"]
    import os
    assert os.path.exists(model_path)
    
    # Delete the asset
    del_resp = client.delete(f"/api/v1/furniture/{asset_id1}", headers=admin_headers)
    assert del_resp.status_code == 200
    
    # Check that file on disk is removed
    assert not os.path.exists(model_path)
    
    # 4. Test Bulk Delete on the remaining asset
    bulk_del_resp = client.post(
        "/api/v1/furniture/bulk-delete",
        json={
            "asset_ids": [asset_id2]
        },
        headers=admin_headers
    )
    assert bulk_del_resp.status_code == 200
    assert "Successfully deleted 1 furniture assets" in bulk_del_resp.json()["message"]
    
    # Verify asset is deleted
    get2_missing = client.get(f"/api/v1/furniture/{asset_id2}", headers=admin_headers)
    assert get2_missing.status_code == 404


