import pytest
import json
import math
from sqlalchemy.orm import sessionmaker
from core.database.session import Base
from features.auth.models import User
from features.project.models import Project
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.service import AIService
from features.ai.repository import AIRepository
from features.ai.exceptions import AIProcessingException
from features.ai.planner import (
    validate_ai_response_schema,
    validate_assets_exist,
    convert_intent_to_coordinates,
    validate_layout_geometry
)
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
        full_name="Real AI Tester",
        email="real_ai@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

def get_test_user_and_project(db):
    user = db.query(User).filter_by(email="real_ai@example.com").first()
    project = db.query(Project).filter_by(user_id=user.id).first()
    if not project:
        project = Project(project_name="Real AI Test Project", user_id=user.id)
        db.add(project)
        db.commit()
        db.refresh(project)
    return user, project

def test_validate_ai_response_schema():
    # Valid schema
    valid_plan = {
        "room_type": "Bedroom",
        "layout_intent": "spacious",
        "furniture": [
            {"asset_id": "BED001", "role": "sleep", "preferred_wall": "north"}
        ],
        "reasoning": ["Place bed against north wall."]
    }
    validate_ai_response_schema(valid_plan)  # Should not raise

    # Invalid schemas
    invalid_plans = [
        # Missing required key
        {"room_type": "Bedroom", "layout_intent": "spacious", "furniture": []},
        # furniture field not a list
        {"room_type": "Bedroom", "layout_intent": "spacious", "furniture": "none", "reasoning": []},
        # item missing role
        {"room_type": "Bedroom", "layout_intent": "spacious", "furniture": [{"asset_id": "BED001"}], "reasoning": []}
    ]
    for plan in invalid_plans:
        with pytest.raises(AIProcessingException):
            validate_ai_response_schema(plan)

def test_validate_assets_exist():
    db = TestingSessionLocal()
    # BED001 exists
    valid_plan = {
        "furniture": [{"asset_id": "BED001", "role": "sleep"}]
    }
    validate_assets_exist(db, valid_plan)  # Should not raise

    # Non-existent asset ID
    invalid_plan = {
        "furniture": [{"asset_id": "INVALID_ID", "role": "sleep"}]
    }
    with pytest.raises(AIProcessingException):
        validate_assets_exist(db, invalid_plan)
    db.close()

def test_convert_intent_to_coordinates():
    db = TestingSessionLocal()
    plan = {
        "room_type": "Bedroom",
        "layout_intent": "spacious",
        "furniture": [
            {"asset_id": "BED001", "role": "sleep", "preferred_wall": "north"},
            {"asset_id": "STAND001", "role": "bedside", "preferred_wall": "north"},
            {"asset_id": "WARDROBE001", "role": "storage", "preferred_wall": "east"}
        ],
        "reasoning": ["Bed on north wall", "Wardrobe on east wall"]
    }
    openings = [{"type": "door", "x": 0.0, "y": 450.0, "width": 80.0}]
    
    placements = convert_intent_to_coordinates(db, 600.0, 450.0, "Bedroom", plan, openings)
    
    assert len(placements) == 3
    # Check bed placement
    bed = next(f for f in placements if "bed" in f["name"].lower())
    assert bed["x"] == 300.0
    assert bed["rotation"] == 0.0
    
    # Check nightstand placement
    stand = next(f for f in placements if "stand" in f["name"].lower())
    assert abs(stand["rotation"] - bed["rotation"]) < 0.1
    
    # Check wardrobe placement
    wardrobe = next(f for f in placements if "wardrobe" in f["name"].lower())
    assert abs(wardrobe["rotation"] - 3.0 * math.pi / 2.0) < 0.001  # East wall
    db.close()

def test_validate_layout_geometry():
    # Valid layout
    placements = [
        {"id": "BED1", "name": "Minimalist King Bed", "category": "Bedroom", "width": 200.0, "depth": 220.0, "height": 45.0, "x": 300.0, "y": 0.0, "z": 125.0, "rotation": 0.0},
        {"id": "STAND1", "name": "Minimalist Nightstand", "category": "Bedroom", "width": 50.0, "depth": 40.0, "height": 55.0, "x": 150.0, "y": 0.0, "z": 125.0, "rotation": 0.0}
    ]
    openings = [{"type": "door", "x": 0.0, "y": 450.0, "width": 80.0}]
    validate_layout_geometry(600.0, 450.0, "Bedroom", placements, openings)  # Should not raise

    # Out of bounds layout
    oob_placements = [
        {"id": "BED1", "name": "Minimalist King Bed", "category": "Bedroom", "width": 200.0, "depth": 220.0, "height": 45.0, "x": 700.0, "y": 0.0, "z": 125.0, "rotation": 0.0}
    ]
    with pytest.raises(AIProcessingException):
        validate_layout_geometry(600.0, 450.0, "Bedroom", oob_placements, openings)

    # Colliding layout
    colliding_placements = [
        {"id": "BED1", "name": "Minimalist King Bed", "category": "Bedroom", "width": 200.0, "depth": 220.0, "height": 45.0, "x": 300.0, "y": 0.0, "z": 125.0, "rotation": 0.0},
        {"id": "STAND1", "name": "Minimalist Nightstand", "category": "Bedroom", "width": 50.0, "depth": 40.0, "height": 55.0, "x": 300.0, "y": 0.0, "z": 125.0, "rotation": 0.0}
    ]
    with pytest.raises(AIProcessingException):
        validate_layout_geometry(600.0, 450.0, "Bedroom", colliding_placements, openings)

def test_provider_fallback_execution():
    import httpx
    def mock_post(*args, **kwargs):
        raise httpx.ConnectError("Simulated Ollama connection failure")

    original_post = httpx.post
    httpx.post = mock_post
    try:
        db = TestingSessionLocal()
        user, project = get_test_user_and_project(db)
        
        room = Room(project_id=project.id, room_name="AI Flow Bedroom", room_type="Bedroom")
        db.add(room)
        db.commit()
        
        meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
        db.add(meas)
        db.commit()
        
        job_id = AIService.start_layout_generation(
            db, room.id, user.id, "Modern", command="Create a spacious bedroom with a wardrobe"
        )
        
        # Run pipeline synchronously
        AIService.run_layout_generation_sync(db, job_id)
        
        job = AIRepository.get_job(db, job_id)
        assert job.status == "Completed"
        
        result = AIRepository.get_result_by_job(db, job_id)
        assert result is not None
        assert result.layout_json != "{}"
        
        layout = json.loads(result.layout_json)
        # Check that performance timings and explanation are present
        assert "ai_layout_metadata" in layout
        meta = layout["ai_layout_metadata"]
        assert "performance" in meta
        assert "explanation" in meta
        assert meta["performance"]["ai_provider_status"] == "FALLBACK"
    finally:
        httpx.post = original_post
        db.close()
