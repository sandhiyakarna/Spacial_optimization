import pytest
import math
from sqlalchemy.orm import sessionmaker
from tests.db_config import get_test_engine
from core.database.session import Base
from features.furniture.models import FurnitureAsset
from features.furniture.services import seed_furniture_assets
from features.ai.geometry import (
    OBB2D, obb_overlap_sat, closest_point_on_obb, generate_room_geometry
)
from features.ai.planner import (
    generate_layout_candidates, clamp_to_bounds
)
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_spatial.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="module")
def db():
    Base.metadata.create_all(bind=engine)
    db_session = TestingSessionLocal()
    seed_furniture_assets(db_session)
    yield db_session
    db_session.close()
    Base.metadata.drop_all(bind=engine)

def test_unit_consistency_and_geometry_bounds():
    # 500cm x 300cm x 280cm room
    room_width = 500.0
    room_length = 300.0
    
    # Verify clamping inside wall boundaries with safety margin
    x, z = clamp_to_bounds(550.0, -10.0, 180.0, 80.0, 0.0, room_width, room_length)
    assert 90.0 <= x <= 500.0 - 90.0
    assert 40.0 <= z <= 300.0 - 40.0

def test_obb_sat_collision_detection():
    # Sofa 1 centered at (250, 150), width 180, depth 82
    sofa1 = OBB2D(cx=250.0, cz=150.0, width=180.0, depth=82.0, rotation=0.0)
    # Sofa 2 overlapping at (260, 160)
    sofa2_overlap = OBB2D(cx=260.0, cz=160.0, width=180.0, depth=82.0, rotation=0.0)
    # Sofa 3 non-overlapping at (400, 250)
    sofa3_safe = OBB2D(cx=400.0, cz=250.0, width=180.0, depth=82.0, rotation=0.0)

    has_overlap, depth, axis = obb_overlap_sat(sofa1, sofa2_overlap)
    assert has_overlap is True
    assert depth > 0.0

    has_overlap_safe, _, _ = obb_overlap_sat(sofa1, sofa3_safe)
    assert has_overlap_safe is False

def test_bedroom_600x450_layout(db):
    candidates = generate_layout_candidates(
        db, room_width=600.0, room_length=450.0, room_type="Bedroom"
    )
    assert len(candidates) > 0
    best_candidate_name, furniture_items, reasoning = candidates[0]
    
    # Calculate score
    scores = calculate_design_score(
        room_width=600.0, room_length=450.0, room_type="Bedroom",
        furniture=furniture_items, openings=[]
    )
    
    assert scores["details"]["collisions"] == 0
    assert scores["details"]["out_of_bounds"] == 0
    assert scores["overall_score"] > 50.0

def test_kitchen_500x300_layout(db):
    candidates = generate_layout_candidates(
        db, room_width=500.0, room_length=300.0, room_type="Kitchen",
        preferences=["spacious", "more_storage"]
    )
    assert len(candidates) > 0
    _, raw_items, _ = candidates[0]
    
    # Run simulated annealing optimizer to obtain final verified layout
    final_items, _ = optimize_layout_simulated_annealing(
        room_width=500.0, room_length=300.0, room_type="Kitchen",
        furniture=raw_items, openings=[]
    )
    
    scores = calculate_design_score(
        room_width=500.0, room_length=300.0, room_type="Kitchen",
        furniture=final_items, openings=[]
    )
    assert scores["details"]["collisions"] == 0
    assert scores["details"]["out_of_bounds"] == 0

def test_living_room_600x450_layout(db):
    candidates = generate_layout_candidates(
        db, room_width=600.0, room_length=450.0, room_type="Living Room"
    )
    assert len(candidates) > 0
    _, furniture_items, _ = candidates[0]
    
    categories = [f.get("category", "").lower() for f in furniture_items]
    roles = [f.get("role", "").lower() for f in furniture_items]
    
    scores = calculate_design_score(
        room_width=600.0, room_length=450.0, room_type="Living Room",
        furniture=furniture_items, openings=[]
    )
    assert scores["details"]["collisions"] == 0

def test_intentional_collision_score_decrease():
    furniture_safe = [
        {"id": "1", "name": "Sofa 1", "x": 150.0, "y": 0.0, "z": 150.0, "width": 180.0, "depth": 82.0, "height": 85.0, "rotationY": 0.0},
        {"id": "2", "name": "Sofa 2", "x": 400.0, "y": 0.0, "z": 300.0, "width": 180.0, "depth": 82.0, "height": 85.0, "rotationY": 0.0}
    ]
    furniture_colliding = [
        {"id": "1", "name": "Sofa 1", "x": 150.0, "y": 0.0, "z": 150.0, "width": 180.0, "depth": 82.0, "height": 85.0, "rotationY": 0.0},
        {"id": "2", "name": "Sofa 2", "x": 160.0, "y": 0.0, "z": 160.0, "width": 180.0, "depth": 82.0, "height": 85.0, "rotationY": 0.0}
    ]
    
    score_safe = calculate_design_score(600.0, 450.0, "Living Room", furniture_safe, [])
    score_colliding = calculate_design_score(600.0, 450.0, "Living Room", furniture_colliding, [])

    assert score_safe["details"]["collisions"] == 0
    assert score_colliding["details"]["collisions"] > 0
    assert score_safe["overall_score"] > score_colliding["overall_score"]
