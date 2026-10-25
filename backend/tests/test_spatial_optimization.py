import math
import pytest
from features.ai.geometry import (
    OBB2D, get_furniture_obb, obb_overlap_sat, generate_room_geometry,
    closest_point_on_obb, OccupancyGrid, mark_obstacle_obb
)
from features.ai.scoring import calculate_design_score


def test_obb_creation_and_corners():
    # Construct a 200 x 100 cm OBB at center (100, 100) with 0 rotation
    obb = OBB2D(100.0, 100.0, 200.0, 100.0, 0.0)
    assert obb.ext_x == 100.0
    assert obb.ext_z == 50.0
    
    corners = obb.get_corners()
    assert len(corners) == 4
    # With 0 rotation, corners should be AABB-like
    # Left-Top, Right-Top, Right-Bottom, Left-Bottom
    assert (0.0, 50.0) in corners
    assert (200.0, 50.0) in corners
    assert (200.0, 150.0) in corners
    assert (0.0, 150.0) in corners


def test_obb_overlap_sat_no_overlap():
    # Two disjoint boxes
    obb1 = OBB2D(50.0, 50.0, 40.0, 40.0, 0.0)
    obb2 = OBB2D(150.0, 50.0, 40.0, 40.0, 0.0)
    
    has_overlap, _, _ = obb_overlap_sat(obb1, obb2)
    assert not has_overlap


def test_obb_overlap_sat_with_overlap():
    # Overlapping boxes
    obb1 = OBB2D(100.0, 100.0, 100.0, 100.0, 0.0)
    obb2 = OBB2D(140.0, 100.0, 100.0, 100.0, 0.0)
    
    has_overlap, pen_depth, _ = obb_overlap_sat(obb1, obb2)
    assert has_overlap
    assert pen_depth > 0.0


def test_obb_overlap_sat_rotated():
    # Non-overlapping AABBs that overlap when one is rotated
    # Box 1: Center (100, 100), Size 100 x 100, rotated 45 degrees (corners extend to about 70.7 cm from center)
    # Box 2: Center (170, 100), Size 40 x 40, unrotated
    obb1 = OBB2D(100.0, 100.0, 100.0, 100.0, math.pi / 4.0)
    obb2 = OBB2D(165.0, 100.0, 40.0, 40.0, 0.0)
    
    has_overlap, _, _ = obb_overlap_sat(obb1, obb2)
    assert has_overlap


def test_generate_room_geometry():
    # 5.0m x 4.0m room
    walls, openings = generate_room_geometry(500.0, 400.0, num_doors=1, num_windows=2)
    
    # Four walls should be generated
    assert len(walls) == 4
    for wall in walls:
        assert "x1" in wall and "y1" in wall
        assert "thickness" in wall
        
    # At least 1 door and 2 windows should be generated
    doors = [op for op in openings if op["type"] == "door"]
    windows = [op for op in openings if op["type"] == "window"]
    assert len(doors) == 1
    assert len(windows) == 2


def test_closest_point_on_obb():
    obb = OBB2D(100.0, 100.0, 100.0, 100.0, 0.0)
    
    # Point outside to the right
    p1 = (180.0, 100.0)
    gx, gz = closest_point_on_obb(obb, p1)
    assert gx == 150.0
    assert gz == 100.0
    
    # Point inside
    p2 = (110.0, 110.0)
    gx, gz = closest_point_on_obb(obb, p2)
    assert gx == 110.0
    assert gz == 110.0


def test_mark_obstacle_obb_grid():
    grid = OccupancyGrid(200.0, 200.0, cell_size=10.0)
    # Put a 40x40 cm obstacle at (50, 50)
    obb = OBB2D(50.0, 50.0, 40.0, 40.0, 0.0)
    mark_obstacle_obb(grid, obb)
    
    # Center cell should be marked
    center_cell = grid.to_cell(50.0, 50.0)
    assert grid.grid[center_cell[0]][center_cell[1]] == 1
    
    # Disjoint cell should be empty
    far_cell = grid.to_cell(150.0, 150.0)
    assert grid.grid[far_cell[0]][far_cell[1]] == 0


def test_calculate_design_score_collisions():
    # Construct a layout with two overlapping beds
    furniture = [
        {
            "id": "bed_1",
            "name": "Queen Bed",
            "category": "bedroom",
            "x": 100.0,
            "z": 100.0,
            "width": 150.0,
            "depth": 200.0,
            "rotationY": 0.0,
            "height": 80.0
        },
        {
            "id": "bed_2",
            "name": "King Bed",
            "category": "bedroom",
            "x": 120.0,
            "z": 110.0,
            "width": 180.0,
            "depth": 200.0,
            "rotationY": 0.0,
            "height": 80.0
        }
    ]
    
    score = calculate_design_score(
        room_width=400.0,
        room_length=400.0,
        room_type="bedroom",
        furniture=furniture,
        openings=[]
    )
    
    # Safety score should be low because of the collision penalty
    assert score["subscores"]["safety"] < 100.0
