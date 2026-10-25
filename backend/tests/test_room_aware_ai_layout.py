import pytest
import math
from core.database.session import SessionLocal
from features.furniture.models import FurnitureAsset
from features.ai.planner import (
    select_furniture_assets,
    generate_layout_candidates,
    is_asset_compatible_with_room,
    convert_intent_to_coordinates,
    evaluate_design_quality
)
from features.ai.scoring import calculate_design_score, PROHIBITED_ITEMS_BY_ROOM
from features.ai.provider import HeuristicLayoutProvider, LocalLLMLayoutProvider, GeminiLayoutProvider

@pytest.fixture
def db():
    session = SessionLocal()
    yield session
    session.close()

def test_room_asset_compatibility_rules(db):
    """Test that is_asset_compatible_with_room strictly approves/rejects assets by room type."""
    office_chair = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%office chair%")).first()
    desk = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%desk%")).first()
    bed = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%bed%")).first()
    kitchen_counter = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%kitchen counter%")).first()
    kitchen_sink = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%sink%")).first()
    stove = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%stove%")).first()
    fridge = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%refrigerator%")).first()
    dining_chair = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%dining chair%")).first()
    vanity = db.query(FurnitureAsset).filter(FurnitureAsset.name.ilike("%vanity%")).first()

    # Kitchen
    assert is_asset_compatible_with_room(kitchen_counter, "Kitchen") is True
    assert is_asset_compatible_with_room(kitchen_sink, "Kitchen") is True
    assert is_asset_compatible_with_room(stove, "Kitchen") is True
    assert is_asset_compatible_with_room(fridge, "Kitchen") is True
    assert is_asset_compatible_with_room(office_chair, "Kitchen") is False
    assert is_asset_compatible_with_room(desk, "Kitchen") is False
    assert is_asset_compatible_with_room(bed, "Kitchen") is False

    # Dining Room
    assert is_asset_compatible_with_room(dining_chair, "Dining Room") is True
    assert is_asset_compatible_with_room(office_chair, "Dining Room") is False
    assert is_asset_compatible_with_room(bed, "Dining Room") is False
    assert is_asset_compatible_with_room(stove, "Dining Room") is False

    # Bathroom
    assert is_asset_compatible_with_room(vanity, "Bathroom") is True
    assert is_asset_compatible_with_room(desk, "Bathroom") is False
    assert is_asset_compatible_with_room(bed, "Bathroom") is False

    # Bedroom
    assert is_asset_compatible_with_room(bed, "Bedroom") is True
    assert is_asset_compatible_with_room(kitchen_counter, "Bedroom") is False
    assert is_asset_compatible_with_room(stove, "Bedroom") is False

    # Office
    assert is_asset_compatible_with_room(desk, "Office") is True
    assert is_asset_compatible_with_room(office_chair, "Office") is True
    assert is_asset_compatible_with_room(bed, "Office") is False
    assert is_asset_compatible_with_room(kitchen_sink, "Office") is False

def test_kitchen_layout_generation_and_scoring(db):
    """Test full kitchen layout generation, ensuring kitchen zones and no office furniture."""
    candidates = generate_layout_candidates(
        db, room_width=400.0, room_length=400.0, room_type="Kitchen", style="Modern", openings=[]
    )
    assert len(candidates) >= 1

    for strat, placements, explanation in candidates:
        names = [p['name'].lower() for p in placements]
        categories = [p.get('category', '').lower() for p in placements]
        roles = [p.get('role', '').lower() for p in placements]

        # Must have essential kitchen items
        assert any('counter' in n or 'counter' in r for n, r in zip(names, roles)), f"Missing counter in {strat}"
        assert any('sink' in n or 'cleaning' in r for n, r in zip(names, roles)), f"Missing sink in {strat}"
        assert any('refrigerator' in n or 'fridge' in n or 'food_storage' in r for n, r in zip(names, roles)), f"Missing fridge in {strat}"

        # Prohibited items must NEVER be in kitchen
        for n in names:
            assert 'office' not in n, f"Office furniture '{n}' found in kitchen!"
            assert 'desk' not in n, f"Desk '{n}' found in kitchen!"
            assert 'bed' not in n, f"Bed '{n}' found in kitchen!"

        # Score evaluation
        scores = calculate_design_score(400.0, 400.0, "Kitchen", placements, [])
        assert scores['overall_score'] >= 70.0
        assert scores['subscores']['functionality'] >= 70.0
        assert len(scores['critical_errors']) == 0

def test_kitchen_unacceptable_office_chair_penalty(db):
    """Test that a kitchen with office chairs and table receives critical deductions and score <= 35%."""
    bad_kitchen_furniture = [
        {
            "id": "bad-1",
            "name": "Solid Wood Dining Table",
            "category": "Dining",
            "role": "table",
            "width": 160.0,
            "depth": 90.0,
            "height": 75.0,
            "x": 200.0,
            "y": 0.0,
            "z": 200.0,
            "rotationY": 0.0
        },
        {
            "id": "bad-2",
            "name": "Ergonomic Office Chair",
            "category": "Office",
            "role": "chair",
            "width": 65.0,
            "depth": 65.0,
            "height": 100.0,
            "x": 200.0,
            "y": 0.0,
            "z": 130.0,
            "rotationY": 0.0
        }
    ]

    scores = calculate_design_score(400.0, 400.0, "Kitchen", bad_kitchen_furniture, [])
    assert scores['overall_score'] <= 35.0, f"Expected capped score <= 35%, got {scores['overall_score']}"
    assert scores['rating_status'] == "Unacceptable / Critical Issues"
    assert len(scores['critical_errors']) > 0
    # Must explicitly mention prohibited furniture and missing kitchen zones
    err_text = " ".join(scores['critical_errors']).lower()
    assert "inappropriate furniture" in err_text or "office chair" in err_text
    assert "counter" in err_text or "sink" in err_text

def test_dining_room_layout_generation(db):
    """Test dining room layout candidate generation."""
    candidates = generate_layout_candidates(
        db, room_width=450.0, room_length=450.0, room_type="Dining Room", style="Modern", openings=[]
    )
    assert len(candidates) >= 1
    placements = candidates[0][1]
    names = [p['name'].lower() for p in placements]

    assert any('dining table' in n or 'table' in n for n in names)
    assert any('dining chair' in n for n in names)
    assert not any('office' in n for n in names)
    assert not any('bed' in n for n in names)

    scores = calculate_design_score(450.0, 450.0, "Dining Room", placements, [])
    assert scores['overall_score'] >= 70.0
    assert len(scores['critical_errors']) == 0

def test_bedroom_layout_generation(db):
    """Test bedroom layout candidate generation."""
    candidates = generate_layout_candidates(
        db, room_width=400.0, room_length=500.0, room_type="Bedroom", style="Modern", openings=[]
    )
    assert len(candidates) >= 1
    placements = candidates[0][1]
    names = [p['name'].lower() for p in placements]

    assert any('bed' in n for n in names)
    assert not any('sink' in n for n in names)
    assert not any('stove' in n for n in names)

    scores = calculate_design_score(400.0, 500.0, "Bedroom", placements, [])
    assert scores['overall_score'] >= 70.0

def test_bathroom_layout_generation(db):
    """Test bathroom layout candidate generation."""
    candidates = generate_layout_candidates(
        db, room_width=300.0, room_length=300.0, room_type="Bathroom", style="Modern", openings=[]
    )
    assert len(candidates) >= 1
    placements = candidates[0][1]
    names = [p['name'].lower() for p in placements]

    assert any('vanity' in n or 'basin' in n for n in names)
    assert not any('bed' in n for n in names)
    assert not any('desk' in n for n in names)

    scores = calculate_design_score(300.0, 300.0, "Bathroom", placements, [])
    assert scores['overall_score'] >= 70.0

def test_office_and_study_layout_generation(db):
    """Test executive manager office and study room layouts."""
    # Manager's Office
    mgr_candidates = generate_layout_candidates(
        db, room_width=450.0, room_length=500.0, room_type="Manager's Office", style="Modern", openings=[]
    )
    assert len(mgr_candidates) >= 1
    mgr_placements = mgr_candidates[0][1]
    mgr_names = [p['name'].lower() for p in mgr_placements]
    assert any('desk' in n for n in mgr_names)
    assert any('chair' in n for n in mgr_names)
    assert not any('bed' in n for n in mgr_names)

    # Study Room
    study_candidates = generate_layout_candidates(
        db, room_width=350.0, room_length=350.0, room_type="Study Room", style="Modern", openings=[]
    )
    assert len(study_candidates) >= 1
    study_placements = study_candidates[0][1]
    study_names = [p['name'].lower() for p in study_placements]
    assert any('desk' in n for n in study_names)
    assert any('chair' in n for n in study_names)
    assert not any('bed' in n for n in study_names)

def test_heuristic_provider_all_room_types(db):
    """Test HeuristicLayoutProvider for all supported room types."""
    provider = HeuristicLayoutProvider()
    assets = db.query(FurnitureAsset).all()
    catalog = [{
        "asset_id": a.id,
        "name": a.name,
        "category": a.category,
        "width": a.width,
        "depth": a.depth,
        "height": a.height
    } for a in assets]

    for r_type in ["Kitchen", "Dining Room", "Bathroom", "Bedroom", "Living Room", "Office", "Study Room"]:
        plan = provider.generate_layout_plan(
            {"room_type": r_type, "width": 400.0, "length": 400.0, "height": 280.0},
            catalog,
            {"preferences": []}
        )
        assert plan["room_type"].lower() in r_type.lower()
        assert len(plan["furniture"]) >= 1
        assert len(plan["reasoning"]) >= 1

        # Check conversion to coordinates
        placements = convert_intent_to_coordinates(db, 400.0, 400.0, r_type, plan, [])
        assert len(placements) >= 1
        scores = calculate_design_score(400.0, 400.0, r_type, placements, [])
        assert scores['overall_score'] >= 65.0
