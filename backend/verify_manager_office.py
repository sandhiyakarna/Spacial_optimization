import sys
from core.database.session import SessionLocal
import features.auth.models
import features.material.models
import features.furniture.models
import features.room.models
import features.project.models
import features.ai.models
from features.furniture.models import FurnitureAsset
from features.ai.planner import generate_layout_candidates, evaluate_design_quality, refine_layout_with_prompt
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score

def test_office():
    db = SessionLocal()
    room_w, room_l = 480.0, 360.0
    room_type = "Manager's Office"
    openings = [
        {"type": "door", "x": 60.0, "y": 360.0, "width": 90.0},
        {"type": "window", "x": 240.0, "y": 0.0, "width": 140.0}
    ]

    candidates = generate_layout_candidates(db, room_w, room_l, room_type, "Modern", openings)
    print(f"Generated {len(candidates)} candidates for {room_type} ({room_w}x{room_l} cm):")
    
    for strat, items, expl in candidates:
        print(f"\n--- Strategy: {strat} ({len(items)} items) ---")
        for it in items:
            print(f"  - {it['name']} ({it.get('role', 'general')}): pos=({it['x']}, {it['z']}), rot={it['rotationY']}")
        
        opt_items, opt_rep = optimize_layout_simulated_annealing(room_w, room_l, room_type, items, openings, seed=42)
        scores = calculate_design_score(room_w, room_l, room_type, opt_items, openings)
        eval_res = evaluate_design_quality(room_w, room_l, room_type, opt_items, openings)
        
        print(f"  Score: {scores['overall_score']:.1f} / 100")
        print(f"  Collisions: {scores['details']['collisions']}, OutOfBounds: {scores['details']['out_of_bounds']}")
        print(f"  BlockedDoors: {scores['details']['blocked_doors']}, WalkwaysClear: {scores['details']['walkways_clear']}")
        print(f"  Accessibility: {scores['subscores']['accessibility']:.1f}, Ergonomics: {scores['subscores']['ergonomics']:.1f}")
        print(f"  Design Valid: {eval_res['is_valid']}")
        print(f"  Zones: {[(k, v['status']) for k, v in eval_res['functional_zones'].items()]}")

    # Test NL Refinement
    print("\n--- Testing NL Refinement ---")
    best_candidate = candidates[0][1]
    refined_items, ref_expl = refine_layout_with_prompt(
        db, room_w, room_l, room_type, best_candidate, openings, "Move the storage cabinet against the right wall."
    )
    print(f"Refinement explanation: {ref_expl}")
    for it in refined_items:
        if 'cabinet' in it['name'].lower():
            print(f"  - Cabinet pos: ({it['x']}, {it['z']}), rot={it['rotationY']}")

if __name__ == "__main__":
    test_office()
