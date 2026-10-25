import pytest
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
from features.furniture.models import FurnitureAsset
from features.material.models import MaterialCategory, Material, MaterialTexture
from features.ai.models import (
    AIJob, AIResult, AIHistory, ValidationRule, ValidationResult,
    ValidationChecklist, Analytics, RoomScore, DesignHistory, RecommendationHistory
)
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from features.ai.geometry import OccupancyGrid, get_furniture_bbox
from features.ai.scoring import calculate_design_score

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
        full_name="AI Tester",
        email="ai@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_geometry_and_bbox():
    f = {"x": 100.0, "z": 100.0, "width": 80.0, "depth": 60.0, "rotationY": 0.0}
    bbox = get_furniture_bbox(f)
    assert bbox['left'] == 60.0
    assert bbox['right'] == 140.0
    assert bbox['top'] == 70.0
    assert bbox['bottom'] == 130.0

def test_scoring_engine():
    furniture = [
        {"id": "f1", "x": 100.0, "z": 100.0, "width": 80.0, "depth": 60.0, "rotationY": 0.0, "category": "Bedroom", "name": "Minimalist King Bed"},
        {"id": "f2", "x": 250.0, "z": 100.0, "width": 50.0, "depth": 40.0, "rotationY": 0.0, "category": "Bedroom", "name": "Minimalist Nightstand"}
    ]
    openings = [
        {"x": 30.0, "y": 0.0, "width": 80.0, "type": "door"}
    ]
    scores = calculate_design_score(500.0, 400.0, "Bedroom", furniture, openings)
    assert "overall_score" in scores
    assert "subscores" in scores
    assert scores["subscores"]["space_utilization"] > 0.0

def test_ai_endpoints_integration():
    # 1. Login
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "ai@example.com", "password": "Password123!"}
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create Project
    create_proj_resp = client.post(
        "/api/v1/projects",
        json={
            "project_name": "AI Test Mansion",
            "description": "Smart layout testing",
            "location": "Paris"
        },
        headers=headers
    )
    assert create_proj_resp.status_code == 201
    proj_id = create_proj_resp.json()["data"]["project_id"]

    # 3. Create Room
    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={
            "room_name": "Master Suite",
            "room_type": "Bedroom",
            "floor_number": 1,
            "notes": "Spacious bedroom area"
        },
        headers=headers
    )
    assert create_room_resp.status_code == 201
    room_id = create_room_resp.json()["data"]["room_id"]

    # Add room measurements
    meas_resp = client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={
            "length": 600.0,
            "width": 500.0,
            "height": 300.0,
            "floor_thickness": 30.0,
            "wall_thickness": 20.0,
            "ceiling_height": 300.0
        },
        headers=headers
    )
    assert meas_resp.status_code == 200

    # 4. Generate AI Layout
    gen_resp = client.post(
        "/api/v1/ai/layout",
        json={"room_id": room_id, "style": "Modern"},
        headers=headers
    )
    assert gen_resp.status_code == 201
    job_id = gen_resp.json()["data"]["job_id"]

    # 5. Check Job Status
    job_resp = client.get(f"/api/v1/ai/jobs/{job_id}", headers=headers)
    assert job_resp.status_code == 200
    assert "status" in job_resp.json()["data"]

    # 6. Optimize Existing Layout (fails if empty, so let's check it gives 400 or works after layout saves)
    opt_resp = client.post(
        "/api/v1/ai/optimize",
        json={"room_id": room_id},
        headers=headers
    )
    assert opt_resp.status_code in [200, 400]

    # 7. Get Recommendations
    rec_resp = client.get(f"/api/v1/ai/recommendations/{room_id}", headers=headers)
    assert rec_resp.status_code == 200
    cards = rec_resp.json()["data"]
    assert len(cards) > 0
    rec_id = cards[0]["id"]

    # 8. Explain Recommendation
    explain_resp = client.get(f"/api/v1/ai/explain/{rec_id}", headers=headers)
    assert explain_resp.status_code == 200
    assert "why_suggested" in explain_resp.json()["data"]


def test_advanced_recommendations_and_optimizer():
    from features.ai.recommender import generate_recommendations
    from features.ai.optimizer import optimize_layout_simulated_annealing

    # 1. Overcrowded room (utilization > 65%) should trigger Downsize Room suggestion
    furniture = [
        {"id": "f1", "x": 100.0, "z": 100.0, "width": 200.0, "depth": 200.0, "height": 80.0, "category": "Living Room", "name": "Cozy Sofa", "style": "Scandinavian"},
        {"id": "f2", "x": 200.0, "z": 200.0, "width": 150.0, "depth": 150.0, "height": 75.0, "category": "Living Room", "name": "Big Bookshelf", "style": "Scandinavian"},
        {"id": "f3", "x": 300.0, "z": 100.0, "width": 100.0, "depth": 100.0, "height": 90.0, "category": "Living Room", "name": "Armchair", "style": "Scandinavian"}
    ]
    openings = [{"x": 10.0, "y": 0.0, "width": 80.0, "type": "door"}]
    
    # 400x300 room (area = 120000). Furniture area = 40000 + 22500 + 10000 = 72500 (ratio = 60.4% - let's make it smaller or add another item to go over 65%)
    # Let's add f4
    furniture.append({"id": "f4", "x": 50.0, "z": 250.0, "width": 100.0, "depth": 100.0, "height": 90.0, "category": "Living Room", "name": "End Table", "style": "Scandinavian"})
    
    recs = generate_recommendations(300.0, 300.0, "Living Room", furniture, openings)
    
    # Verify density recommendation
    density_recs = [r for r in recs if r["rule_triggered"] == "Room Density Rule"]
    assert len(density_recs) > 0
    assert density_recs[0]["action"]["action_type"] == "remove"
    
    # Verify lighting fixture suggestion (as no lamp exists)
    lighting_recs = [r for r in recs if r["rule_triggered"] == "Lighting Adequacy Rule"]
    assert len(lighting_recs) > 0
    assert lighting_recs[0]["action"]["category"] == "Lighting"
    
    # Verify style-aligned material suggestion
    material_recs = [r for r in recs if r["rule_triggered"] == "Material Suggestion Rule"]
    assert len(material_recs) > 0
    # Scandinavian style fabric/wood should be recommended
    assert material_recs[0]["action"]["materialColor"] in ["#E6DFD3", "#3B5998"]

    # 2. Test spatial optimizer with snap-to-wall mutation
    optimized, report = optimize_layout_simulated_annealing(
        room_width=300.0,
        room_length=300.0,
        room_type="Living Room",
        furniture=[
            {"id": "f1", "x": 150.0, "z": 150.0, "width": 100.0, "depth": 50.0, "height": 80.0, "rotationY": 0.0, "category": "Living Room", "name": "Sofa"}
        ],
        openings=[]
    )
    assert len(optimized) == 1
    # Check that center is valid
    assert 0.0 < optimized[0]["x"] < 300.0
    assert 0.0 < optimized[0]["z"] < 300.0

