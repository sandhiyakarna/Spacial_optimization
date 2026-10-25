import pytest
from core.database.session import SessionLocal
import features.auth.models
import features.material.models
import features.furniture.models
import features.room.models
import features.project.models
import features.ai.models
from features.ai.planner import generate_layout_candidates, evaluate_design_quality, refine_layout_with_prompt
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score

@pytest.fixture
def db_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def test_manager_office_generation_and_zoning(db_session):
    room_w, room_l = 480.0, 360.0
    room_type = "Manager's Office"
    openings = [
        {"type": "door", "x": 60.0, "y": 360.0, "width": 90.0},
        {"type": "window", "x": 240.0, "y": 0.0, "width": 140.0}
    ]

    candidates = generate_layout_candidates(db_session, room_w, room_l, room_type, "Modern", openings)
    assert len(candidates) >= 3

    for strat, items, expl in candidates:
        assert len(items) >= 4
        # Verify functional pairings exist
        names = [it['name'].lower() for it in items]
        roles = [it.get('role', '').lower() for it in items]
        
        has_desk = any('desk' in n or 'desk' in r for n, r in zip(names, roles))
        has_manager_chair = any('manager' in n or 'exec' in n or 'manager_chair' in r for n, r in zip(names, roles))
        assert has_desk, f"Candidate {strat} missing executive desk"
        assert has_manager_chair, f"Candidate {strat} missing manager chair"

        # Optimize candidate
        opt_items, opt_rep = optimize_layout_simulated_annealing(room_w, room_l, room_type, items, openings, seed=42)
        scores = calculate_design_score(room_w, room_l, room_type, opt_items, openings)
        eval_res = evaluate_design_quality(room_w, room_l, room_type, opt_items, openings)

        # Assert hard constraints
        assert scores['details']['collisions'] == 0, f"Strategy {strat} has collisions: {scores['details']['collisions']}"
        assert scores['details']['out_of_bounds'] == 0, f"Strategy {strat} out of bounds"
        assert scores['details']['blocked_doors'] == 0, f"Strategy {strat} blocks door"
        assert scores['details']['walkways_clear'] is True, f"Strategy {strat} blocked walkways"
        assert scores['overall_score'] >= 85.0
        assert eval_res['is_valid'] is True
        assert eval_res['functional_zones']['manager_workspace']['status'] == 'Complete'
        assert eval_res['functional_zones']['circulation_corridor']['status'] == 'Clear'

def test_natural_language_refinement(db_session):
    room_w, room_l = 480.0, 360.0
    room_type = "Manager's Office"
    openings = [
        {"type": "door", "x": 60.0, "y": 360.0, "width": 90.0},
        {"type": "window", "x": 240.0, "y": 0.0, "width": 140.0}
    ]

    candidates = generate_layout_candidates(db_session, room_w, room_l, room_type, "Modern", openings)
    initial_furniture = candidates[0][1]

    refined_items, explanation = refine_layout_with_prompt(
        db_session, room_w, room_l, room_type, initial_furniture, openings, "Move the storage cabinet against the right wall."
    )
    assert "right" in explanation.lower() or "east" in explanation.lower() or "storage" in explanation.lower()
    
    # Check cabinet position is on the right side
    cab = next((f for f in refined_items if 'cabinet' in f['name'].lower()), None)
    assert cab is not None
    assert cab['x'] > room_w * 0.7
