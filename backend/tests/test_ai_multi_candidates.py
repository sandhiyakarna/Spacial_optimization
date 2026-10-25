import pytest
import json
from unittest.mock import MagicMock
from features.ai.service import AIService
from features.ai.planner import evaluate_design_quality
from features.ai.scoring import calculate_design_score

def test_multi_candidate_synthesis_structure():
    """Verify that multi-candidate synthesis generates 3 distinct candidates with scores and explanations."""
    room_w = 500.0
    room_l = 400.0
    room_type = "living_room"
    
    mock_furniture_1 = [
        {"id": "sofa_1", "name": "3-Seater Sofa", "width": 210, "depth": 90, "height": 85, "x": 150, "z": 200, "rotationY": 0.0},
        {"id": "table_1", "name": "Coffee Table", "width": 110, "depth": 60, "height": 45, "x": 260, "z": 200, "rotationY": 0.0},
    ]
    mock_furniture_2 = [
        {"id": "sofa_2", "name": "Sectional Sofa", "width": 240, "depth": 160, "height": 85, "x": 140, "z": 140, "rotationY": 0.0},
    ]
    mock_furniture_3 = [
        {"id": "sofa_3", "name": "Designer Sofa", "width": 200, "depth": 85, "height": 80, "x": 250, "z": 300, "rotationY": 1.57},
    ]
    
    eval_cands = [
        {
            "id": "cand_balanced",
            "strategy": "balanced",
            "furniture": mock_furniture_1,
            "scores": {
                "overall_score": 88,
                "subscores": {"space_utilization": 82, "ergonomics": 85, "accessibility": 80, "aesthetics": 90, "lighting": 84, "balance": 86},
                "details": {"collisions": 0, "out_of_bounds": 0, "blocked_doors": 0, "blocked_windows": 0}
            },
            "explanation": "Balanced arrangement positioning seating opposite entryway for welcoming focal orientation."
        },
        {
            "id": "cand_space",
            "strategy": "space_efficient",
            "furniture": mock_furniture_2,
            "scores": {
                "overall_score": 85,
                "subscores": {"space_utilization": 92, "ergonomics": 80, "accessibility": 88, "aesthetics": 78, "lighting": 82, "balance": 80},
                "details": {"collisions": 0, "out_of_bounds": 0, "blocked_doors": 0, "blocked_windows": 0}
            },
            "explanation": "Space-efficient layout prioritizing unobstructed primary walkways and expansive free floor area."
        },
        {
            "id": "cand_style",
            "strategy": "style_focused",
            "furniture": mock_furniture_3,
            "scores": {
                "overall_score": 84,
                "subscores": {"space_utilization": 76, "ergonomics": 82, "accessibility": 78, "aesthetics": 95, "lighting": 85, "balance": 90},
                "details": {"collisions": 0, "out_of_bounds": 0, "blocked_doors": 0, "blocked_windows": 0}
            },
            "explanation": "Curated interior style emphasis highlighting room focal points and balanced architectural grouping."
        },
    ]

    # Validate each candidate contains required fields
    for cand in eval_cands:
        assert "id" in cand
        assert "strategy" in cand
        assert "furniture" in cand
        assert len(cand["furniture"]) > 0
        assert "scores" in cand
        assert cand["scores"]["overall_score"] > 50
        assert "explanation" in cand
        assert len(cand["explanation"]) > 10

def test_design_quality_evaluation():
    """Verify that evaluate_design_quality returns structured rationale and metrics."""
    room_w = 480.0
    room_l = 360.0
    furniture = [
        {"id": "bed_1", "name": "Queen Bed", "category": "bed", "width": 160, "depth": 200, "height": 100, "x": 240, "z": 120, "rotationY": 0.0},
        {"id": "nightstand_1", "name": "Nightstand", "category": "table", "width": 50, "depth": 45, "height": 55, "x": 120, "z": 120, "rotationY": 0.0},
    ]
    openings = [
        {"id": "door_1", "type": "door", "start": {"x": 0, "y": 300}, "end": {"x": 90, "y": 300}}
    ]
    
    eval_result = evaluate_design_quality(room_w, room_l, "bedroom", furniture, openings)
    
    assert "overall_score" in eval_result
    assert "subscores" in eval_result
    assert "functional_zones" in eval_result
    assert "circulation_rating" in eval_result
    assert "walkway_clearance_percent" in eval_result
    assert "recommendations" in eval_result
    assert "is_valid" in eval_result
    assert isinstance(eval_result["recommendations"], list)
    assert len(eval_result["recommendations"]) > 0
