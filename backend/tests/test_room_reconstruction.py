import pytest
import os
import json
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
from features.furniture.models import FurnitureAsset, FurnitureMaterial
from features.material.models import MaterialCategory, Material, MaterialTexture
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister

from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace_reconstruction.db")
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
        full_name="Reconstruct Tester",
        email="reconstruct@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_room_reconstruction_pipeline():
    # 1. Login to get token
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "reconstruct@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "Reconstruction Villa",
            "description": "Spatial planning test",
            "location": "Miami"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Panoramic Master Bedroom",
            "room_type": "Bedroom",
            "floor_number": 1,
            "notes": "Spacious bedroom area"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # 4. Upload mock frames
    # Let's create a temporary dummy image with high-contrast lines to upload
    dummy_img_path = "test_dummy_frame.jpg"
    import PIL.Image
    from PIL import ImageDraw
    img = PIL.Image.new("RGB", (800, 600), color=(100, 100, 100))
    draw = ImageDraw.Draw(img)
    for i in range(0, 800, 20):
        draw.line([(i, 0), (800 - i, 600)], fill=(0, 0, 0), width=3)
        draw.line([(0, i), (800, 600 - i)], fill=(255, 255, 255), width=3)
    img.save(dummy_img_path)

    scan_id = None
    with open(dummy_img_path, "rb") as f:
        upload_resp = client.post(
            "/api/v1/room/panorama/upload",
            data={"scan_id": ""},
            files={"file": (dummy_img_path, f, "image/jpeg")},
            headers=headers
        )
        assert upload_resp.status_code == 201
        res_data = upload_resp.json()
        assert res_data["success"] is True
        scan_id = res_data["scan_id"]
        assert scan_id is not None
        assert res_data["frame_count"] == 1

    # Cleanup local dummy file
    if os.path.exists(dummy_img_path):
        os.remove(dummy_img_path)

    # 5. Process reconstruction (using the upload scan_id)
    # We will trigger the mock reconstruction process on the backend
    process_resp = client.post(
        "/api/v1/room/panorama/process",
        json={
            "scan_id": scan_id,
            "room_id": room_id,
            "room_type": "Bedroom",
            "known_width_cm": 600.0,
            "known_depth_cm": 450.0,
            "known_height_cm": 300.0
        },
        headers=headers
    )
    if process_resp.status_code != 200:
        print("ERROR DETAIL:", process_resp.json())
    assert process_resp.status_code == 200
    p_data = process_resp.json()
    assert p_data["success"] is True
    assert p_data["status"] == "completed"
    assert p_data["blueprint_quality_score"] in [80, 96] # Validation-aware score

    # 6. Retrieve Scan Status
    status_resp = client.get(f"/api/v1/room/panorama/{scan_id}", headers=headers)
    assert status_resp.status_code == 200
    st_data = status_resp.json()
    assert st_data["status"] == "completed"
    assert st_data["quality_score"] == 92

    # 7. Get Reconstructed Spatial Model JSON
    spatial_resp = client.get(f"/api/v1/room/spatial-model/{scan_id}", headers=headers)
    assert spatial_resp.status_code == 200
    sp_data = spatial_resp.json()
    assert sp_data["scan_id"] == scan_id
    assert sp_data["room"]["width_cm"] == 600.0
    assert len(sp_data["walls"]) == 4
    assert len(sp_data["doors"]) == 1
    assert len(sp_data["furniture"]) >= 2

    # 8. Get Blueprint Image File
    blueprint_resp = client.get(f"/api/v1/room/blueprint/{scan_id}", headers=headers)
    assert blueprint_resp.status_code == 200
    assert blueprint_resp.headers["content-type"] == "image/png"

    # 9. Generate custom blueprint
    gen_custom_resp = client.post(
        "/api/v1/room/blueprint/generate",
        json={
            "spatial_model": {
                "room_id": room_id,
                "dimensions": {
                    "width_cm": 500.0,
                    "depth_cm": 400.0,
                    "height_cm": 280.0
                },
                "walls": [
                    {"id": "wall_1", "start": [0, 0], "end": [500, 0], "length_cm": 500, "orientation": "north"},
                    {"id": "wall_2", "start": [500, 0], "end": [500, 400], "length_cm": 400, "orientation": "east"},
                    {"id": "wall_3", "start": [500, 400], "end": [0, 400], "length_cm": 500, "orientation": "south"},
                    {"id": "wall_4", "start": [0, 400], "end": [0, 0], "length_cm": 400, "orientation": "west"}
                ],
                "doors": [
                    {"id": "door_1", "wall_id": "wall_1", "position_cm": 250, "width_cm": 90, "swing": "inward"}
                ],
                "windows": [],
                "furniture": [
                    {"id": "f_1", "asset_id": "test_sofa", "name": "Sofa", "category": "Sofa", "position": {"x_cm": 250, "y_cm": 300}, "dimensions": {"width_cm": 180, "depth_cm": 85, "height_cm": 85}, "rotation_deg": 180.0}
                ]
            }
        },
        headers=headers
    )
    assert gen_custom_resp.status_code == 200
    custom_data = gen_custom_resp.json()
    assert custom_data["success"] is True
    assert custom_data["blueprint_url"].startswith("/api/v1/room/blueprint/")
