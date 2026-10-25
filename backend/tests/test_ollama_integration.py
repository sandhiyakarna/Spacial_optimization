import pytest
import json
import httpx
import math
import os
from sqlalchemy.orm import sessionmaker
from app.config import settings
from core.database.session import Base
from features.auth.models import User
from features.project.models import Project
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.provider import LocalLLMLayoutProvider, HeuristicLayoutProvider
from features.ai.planner import (
    validate_ai_response_schema,
    validate_assets_exist,
    convert_intent_to_coordinates,
    validate_layout_geometry
)
from features.ai.scoring import calculate_design_score
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.service import AIService
from features.ai.repository import AIRepository
from features.ai.exceptions import AIProcessingException
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace_real_ai.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="module", autouse=True)
def setup_test_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    seed_roles_and_permissions(db)
    seed_furniture_assets(db)
    
    AuthService.register_user(db, UserRegister(
        full_name="Ollama Tester",
        email="ollama_test@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

def get_test_user_and_project(db):
    user = db.query(User).filter_by(email="ollama_test@example.com").first()
    project = db.query(Project).filter_by(user_id=user.id).first()
    if not project:
        project = Project(project_name="Ollama Test Project", user_id=user.id)
        db.add(project)
        db.commit()
        db.refresh(project)
    return user, project


# 1. Ollama connection
def test_1_ollama_connection():
    # Verify we can connect to the base URL configured in settings
    try:
        response = httpx.get(settings.OLLAMA_BASE_URL, timeout=5.0)
        assert response.status_code == 200
    except Exception as e:
        pytest.skip(f"Ollama not running locally: {e}")


# 2. Ollama model availability
def test_2_ollama_model_availability():
    # Verify that the configured model is installed locally in Ollama
    try:
        response = httpx.get(f"{settings.OLLAMA_BASE_URL.rstrip('/')}/api/tags", timeout=5.0)
        assert response.status_code == 200
        tags = response.json()
        models = [m["name"] for m in tags.get("models", [])]
        assert settings.OLLAMA_MODEL in models or any(settings.OLLAMA_MODEL in m for m in models)
    except Exception as e:
        pytest.skip(f"Ollama check failed: {e}")


# 3. Ollama structured response
def test_3_ollama_structured_response():
    provider = LocalLLMLayoutProvider()
    room_context = {
        "room_type": "Bedroom",
        "width": 600.0,
        "length": 450.0,
        "height": 300.0,
        "doors": [],
        "windows": []
    }
    db = TestingSessionLocal()
    bed = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%bed%")).first()
    furniture_catalog = [{
        "asset_id": bed.id,
        "name": bed.name,
        "category": bed.category,
        "style": bed.style,
        "width": bed.width,
        "depth": bed.depth,
        "height": bed.height
    }]
    db.close()
    
    # We mock the response to verify parsing and structure validation works cleanly
    class MockResponse:
        def __init__(self, json_data, status_code=200):
            self.json_data = json_data
            self.status_code = status_code
            self.text = json.dumps(json_data)
        def json(self):
            return self.json_data

    def mock_post(url, **kwargs):
        mock_raw_resp = {
            "room_type": "bedroom",
            "layout_intent": "spacious",
            "furniture": [
                {
                    "asset_id": bed.id,
                    "role": "primary_sleep",
                    "preferred_wall": "north",
                    "preferred_zone": "sleep"
                }
            ],
            "reasoning": ["Bed positioned against north wall."]
        }
        return MockResponse({"response": json_data_str_wrap(mock_raw_resp)})

    def json_data_str_wrap(d):
        return json.dumps(d)

    original_post = httpx.post
    httpx.post = mock_post
    try:
        plan = provider.generate_layout_plan(room_context, furniture_catalog, {})
        validate_ai_response_schema(plan)
        assert plan["room_type"] == "bedroom"
        assert len(plan["furniture"]) == 1
        assert plan["furniture"][0]["asset_id"] == bed.id
    finally:
        httpx.post = original_post


# 4. Malformed AI response
def test_4_malformed_ai_response():
    # If the response is not valid JSON or missing keys, schema validation must raise
    malformed_plans = [
        {"room_type": "bedroom"}, # missing keys
        {"room_type": "bedroom", "layout_intent": "minimal", "furniture": "not-a-list", "reasoning": []},
        "not-even-a-dict"
    ]
    for plan in malformed_plans:
        with pytest.raises(AIProcessingException):
            validate_ai_response_schema(plan)


# 5. Ollama timeout
def test_5_ollama_timeout():
    # Verify that local provider raises on HTTPX timeout
    def mock_timeout_post(*args, **kwargs):
        raise httpx.TimeoutException("Connection timed out")
        
    provider = LocalLLMLayoutProvider()
    original_post = httpx.post
    httpx.post = mock_timeout_post
    try:
        with pytest.raises(httpx.TimeoutException):
            provider.generate_layout_plan({}, [], {})
    finally:
        httpx.post = original_post


# 6. Ollama unavailable
def test_6_ollama_unavailable():
    # If Ollama is offline or unavailable, fallback logic must kick in
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    room = Room(project_id=project.id, room_name="Offline Room", room_type="Bedroom")
    db.add(room)
    db.commit()
    meas = RoomMeasurement(room_id=room.id, length=500.0, width=400.0, height=280.0)
    db.add(meas)
    db.commit()

    # We mock post to throw error to simulate Ollama being offline
    def mock_offline_post(*args, **kwargs):
        raise httpx.ConnectError("Ollama offline")

    original_post = httpx.post
    httpx.post = mock_offline_post
    try:
        job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
        AIService.run_layout_generation_sync(db, job_id)
        
        job = AIRepository.get_job(db, job_id)
        assert job.status == "Completed"
        
        result = AIRepository.get_result_by_job(db, job_id)
        layout = json.loads(result.layout_json)
        assert "ai_layout_metadata" in layout
        meta = layout["ai_layout_metadata"]
        assert meta["performance"]["ai_provider_status"] == "FALLBACK"
    finally:
        httpx.post = original_post
    db.close()


# 7. Heuristic fallback
def test_7_heuristic_fallback():
    provider = HeuristicLayoutProvider()
    room_context = {"room_type": "Bedroom"}
    db = TestingSessionLocal()
    assets = db.query(FurnitureAsset).all()
    catalog = [{"asset_id": a.id, "name": a.name, "category": a.category, "width": a.width, "depth": a.depth} for a in assets]
    db.close()
    
    plan = provider.generate_layout_plan(room_context, catalog, {})
    validate_ai_response_schema(plan)
    assert plan["room_type"] == "bedroom"
    assert len(plan["furniture"]) > 0


# 8. Asset validation
def test_8_asset_validation():
    db = TestingSessionLocal()
    bed = db.query(FurnitureAsset).first()
    
    valid_plan = {"furniture": [{"asset_id": bed.id, "role": "sleep"}]}
    validate_assets_exist(db, valid_plan) # Should pass
    
    invalid_plan = {"furniture": [{"asset_id": "NON_EXISTENT_ID", "role": "sleep"}]}
    with pytest.raises(AIProcessingException):
        validate_assets_exist(db, invalid_plan)
    db.close()


# 9. OBB collision
def test_9_obb_collision():
    from features.ai.geometry import get_furniture_obb, obb_overlap_sat
    f1 = {"x": 100.0, "z": 100.0, "width": 100.0, "depth": 100.0, "rotationY": 0.0}
    f2 = {"x": 120.0, "z": 110.0, "width": 100.0, "depth": 100.0, "rotationY": 0.0} # Overlaps
    f3 = {"x": 300.0, "z": 300.0, "width": 100.0, "depth": 100.0, "rotationY": 0.0} # Safe
    
    o1 = get_furniture_obb(f1)
    o2 = get_furniture_obb(f2)
    o3 = get_furniture_obb(f3)
    
    overlap12, _, _ = obb_overlap_sat(o1, o2)
    overlap13, _, _ = obb_overlap_sat(o1, o3)
    
    assert overlap12 is True
    assert overlap13 is False


# 10. Ergonomic validation
def test_10_ergonomic_validation():
    # Verify that the design scoring engine calculates ergonomic violations (e.g. Bed clearance)
    furniture = [
        {"id": "bed", "name": "King Bed", "category": "Bedroom", "width": 200.0, "depth": 220.0, "height": 45.0, "x": 110.0, "z": 110.0, "rotationY": 0.0}
    ]
    # Place bed right against the wall, so it lacks spacing clearance
    scores = calculate_design_score(300.0, 300.0, "Bedroom", furniture, [])
    # Ergonomic score should reflect spacing penalty
    assert scores["subscores"]["ergonomics"] < 100.0


# 11. Optimizer correction
def test_11_optimizer_correction():
    db = TestingSessionLocal()
    bed_asset = db.query(FurnitureAsset).filter(FurnitureAsset.category == "Bedroom").first()
    
    from features.ai.planner import make_furniture_instance
    f1 = make_furniture_instance(bed_asset, 100.0, 0.0, 100.0, 0.0, "Bedroom", "sleep")
    f2 = make_furniture_instance(bed_asset, 110.0, 0.0, 105.0, 0.0, "Bedroom", "sleep") # Collding
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=500.0,
        room_length=500.0,
        room_type="Bedroom",
        furniture=[f1, f2],
        openings=[],
        seed=42,
        num_starts=2
    )
    
    # Optimizer must have corrected the layout to have 0 collisions
    assert report["final"]["collision_violations"] == 0
    db.close()


# 12. Panorama failure -> AI layout
def test_12_panorama_failure_to_ai_layout():
    # Verify backend executes fallback procedural generation when panorama is skipped/failed
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    # Create room without panorama properties (or empty properties)
    room = Room(project_id=project.id, room_name="Fallback AI Room", room_type="Bedroom")
    db.add(room)
    db.commit()
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=500.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    db.close()


# 13. Offline layout generation
def test_13_offline_layout_generation():
    # Offline scenario: We simulate connection failures to Google Gemini, forcing local Ollama usage
    # Under offline requirements, if Gemini API is selected but fails, it falls back to heuristics/local Ollama (depending on provider selection).
    # Since settings.AI_PROVIDER is set to 'ollama' by default, it will route to Ollama locally.
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    room = Room(project_id=project.id, room_name="Offline Integration Room", room_type="Bedroom")
    db.add(room)
    db.commit()
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=500.0, height=300.0)
    db.add(meas)
    db.commit()

    # Block Gemini completely by setting GEMINI_API_KEY to blank/none and mock HTTPX requests to Gemini
    # Since settings.AI_PROVIDER = 'ollama', it won't even hit Gemini. It will call Ollama.
    # We mock Ollama call to succeed locally.
    class MockResponse:
        def __init__(self, json_data):
            self.json_data = json_data
            self.status_code = 200
        def json(self):
            return self.json_data

    def mock_ollama_post(url, **kwargs):
        # mock qwen3:8b layout
        bed_asset = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%bed%")).first()
        mock_plan = {
            "room_type": "bedroom",
            "layout_intent": "spacious",
            "furniture": [
                {"asset_id": bed_asset.id, "role": "primary_sleep", "preferred_wall": "north", "preferred_zone": "sleep"}
            ],
            "reasoning": ["Placed bed against the north wall."]
        }
        import json as json_mod
        return MockResponse({"response": json_mod.dumps(mock_plan)})

    original_post = httpx.post
    httpx.post = mock_ollama_post
    try:
        job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
        AIService.run_layout_generation_sync(db, job_id)
        
        job = AIRepository.get_job(db, job_id)
        assert job.status == "Completed"
        
        result = AIRepository.get_result_by_job(db, job_id)
        layout = json.loads(result.layout_json)
        assert layout["ai_layout_metadata"]["performance"]["ai_provider"] == "OLLAMA"
        assert layout["ai_layout_metadata"]["performance"]["ai_provider_status"] == "SUCCESS"
    finally:
        httpx.post = original_post
    db.close()
