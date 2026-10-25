import pytest
import math
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score

def test_collision_resolution():
    # Two overlapping beds
    initial_furniture = [
        {"id": "bed1", "name": "King Bed", "category": "bedroom", "x": 200.0, "z": 200.0, "width": 200.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
        {"id": "bed2", "name": "Queen Bed", "category": "bedroom", "x": 220.0, "z": 210.0, "width": 160.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0}
    ]
    openings = []
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=600.0,
        room_length=450.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=101,
        num_starts=3
    )
    
    # Verify that the final layout has 0 collisions
    assert report["final"]["collision_violations"] == 0
    assert report["final"]["overall_score"] > report["initial"]["overall_score"]

def test_wall_resolution():
    # Bed partially outside the room bounds
    initial_furniture = [
        {"id": "bed", "name": "Bed", "category": "bedroom", "x": -10.0, "z": 100.0, "width": 150.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0}
    ]
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=500.0,
        room_length=400.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=[],
        seed=42,
        num_starts=2
    )
    
    assert report["final"]["wall_violations"] == 0
    for item in optimized:
        # Should be fully within bounds
        half_w = item["width"] / 2.0
        half_d = item["depth"] / 2.0
        assert item["x"] - half_w >= 0
        assert item["x"] + half_w <= 500.0
        assert item["z"] - half_d >= 0
        assert item["z"] + half_d <= 400.0

def test_door_resolution():
    # Wardrobe directly blocking the door swing zone
    openings = [
        {"id": "door1", "type": "door", "x": 100.0, "y": 0.0, "width": 90.0, "angle": 0.0} # y represents Z in openings
    ]
    initial_furniture = [
        {"id": "wardrobe", "name": "Wardrobe", "category": "storage", "x": 100.0, "z": 45.0, "width": 100.0, "depth": 60.0, "height": 200.0, "rotationY": 0.0}
    ]
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=500.0,
        room_length=400.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=42,
        num_starts=3
    )
    
    assert report["final"]["door_violations"] == 0

def test_walkway_and_ergonomic_improvement():
    # Intentionally poor bedroom layout
    initial_furniture = [
        {"id": "bed", "name": "Double Bed", "category": "bedroom", "x": 100.0, "z": 100.0, "width": 160.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
        {"id": "wardrobe", "name": "Wardrobe", "category": "storage", "x": 90.0, "z": 110.0, "width": 120.0, "depth": 60.0, "height": 200.0, "rotationY": 0.0}
    ]
    openings = [
        {"id": "door", "type": "door", "x": 30.0, "y": 0.0, "width": 90.0, "angle": 0.0}
    ]
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=600.0,
        room_length=450.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=42,
        num_starts=3
    )
    
    assert report["final"]["collision_violations"] == 0
    assert report["final"]["overall_score"] > report["initial"]["overall_score"]
    assert report["final"]["overall_score"] >= 45.0 # Significant improvement

def test_deterministic_seed():
    initial_furniture = [
        {"id": "bed", "name": "Bed", "category": "bedroom", "x": 120.0, "z": 120.0, "width": 150.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
        {"id": "wardrobe", "name": "Wardrobe", "category": "storage", "x": 280.0, "z": 280.0, "width": 100.0, "depth": 60.0, "height": 200.0, "rotationY": 0.0}
    ]
    openings = [{"id": "door", "type": "door", "x": 50.0, "y": 0.0, "width": 90.0, "angle": 0.0}]
    
    optimized1, report1 = optimize_layout_simulated_annealing(
        room_width=500.0,
        room_length=400.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=12345,
        num_starts=2
    )
    
    optimized2, report2 = optimize_layout_simulated_annealing(
        room_width=500.0,
        room_length=400.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=12345,
        num_starts=2
    )
    
    # Assert exact coordinate and rotation match
    for f1, f2 in zip(optimized1, optimized2):
        assert f1["id"] == f2["id"]
        assert f1["x"] == f2["x"]
        assert f1["z"] == f2["z"]
        assert f1["rotationY"] == f2["rotationY"]

def test_multi_start_optimization():
    # A complex scene where different starts explore different rooms
    initial_furniture = [
        {"id": "bed", "name": "King Bed", "category": "bedroom", "x": 200.0, "z": 200.0, "width": 200.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
        {"id": "wardrobe", "name": "Large Wardrobe", "category": "storage", "x": 210.0, "z": 190.0, "width": 180.0, "depth": 60.0, "height": 220.0, "rotationY": 0.0},
        {"id": "desk", "name": "Study Desk", "category": "office", "x": 195.0, "z": 205.0, "width": 120.0, "depth": 70.0, "height": 75.0, "rotationY": 0.0}
    ]
    openings = [{"id": "door", "type": "door", "x": 50.0, "y": 0.0, "width": 90.0, "angle": 0.0}]
    
    # Run with 1 start vs 5 starts
    _, report1 = optimize_layout_simulated_annealing(
        room_width=600.0,
        room_length=450.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=999,
        num_starts=1
    )
    
    _, report5 = optimize_layout_simulated_annealing(
        room_width=600.0,
        room_length=450.0,
        room_type="Bedroom",
        furniture=initial_furniture,
        openings=openings,
        seed=999,
        num_starts=5
    )
    
    # 5 starts should find a layout at least as good as 1 start, likely better
    assert report5["final"]["overall_score"] >= report1["final"]["overall_score"]

def test_manual_editing_regression():
    # 1. Clean optimized layout
    room_width = 500.0
    room_length = 400.0
    furniture = [
        {"id": "bed", "name": "Queen Bed", "category": "bedroom", "x": 150.0, "z": 150.0, "width": 160.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
        {"id": "wardrobe", "name": "Wardrobe", "category": "storage", "x": 350.0, "z": 150.0, "width": 100.0, "depth": 60.0, "height": 200.0, "rotationY": 0.0}
    ]
    
    # Verify no collisions initially
    score = calculate_design_score(room_width, room_length, "Bedroom", furniture, [])
    assert score["details"]["collisions"] == 0
    
    # 2. Simulate manual edit: move wardrobe into collision with bed
    furniture[1]["x"] = 180.0
    furniture[1]["z"] = 150.0
    
    # Verify collision detected
    collision_score = calculate_design_score(room_width, room_length, "Bedroom", furniture, [])
    assert collision_score["details"]["collisions"] > 0
    
    # 3. Simulate manual edit: move it back
    furniture[1]["x"] = 350.0
    furniture[1]["z"] = 150.0
    
    # Verify safe again
    safe_score = calculate_design_score(room_width, room_length, "Bedroom", furniture, [])
    assert safe_score["details"]["collisions"] == 0
    
    # 4. Move it back to collision state and run optimization again to resolve it
    furniture[1]["x"] = 180.0
    furniture[1]["z"] = 150.0
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=room_width,
        room_length=room_length,
        room_type="Bedroom",
        furniture=furniture,
        openings=[],
        seed=42,
        num_starts=3
    )
    
    # Verify optimizer resolved the manual edit collision successfully
    assert report["final"]["collision_violations"] == 0
