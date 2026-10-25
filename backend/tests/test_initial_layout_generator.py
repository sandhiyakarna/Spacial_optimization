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
from features.ai.planner import generate_layout_candidates, generate_initial_layout
from features.ai.scoring import calculate_design_score
from features.ai.geometry import get_furniture_obb, obb_overlap_sat
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from features.ai.exceptions import AIProcessingException
from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_flowspace_pwd.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="module", autouse=True)
def setup_test_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    seed_roles_and_permissions(db)
    seed_furniture_assets(db)
    
    # Create test user
    AuthService.register_user(db, UserRegister(
        full_name="Layout Tester",
        email="layout@example.com",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

def get_test_user_and_project(db):
    user = db.query(User).filter_by(email="layout@example.com").first()
    project = db.query(Project).filter_by(user_id=user.id).first()
    if not project:
        project = Project(project_name="Test Project", user_id=user.id)
        db.add(project)
        db.commit()
        db.refresh(project)
    return user, project

def test_1_bedroom_layout():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Bed Suite", room_type="Bedroom")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    assert result is not None
    
    layout = json.loads(result.layout_json)
    assert len(layout["furniture"]) >= 1
    
    # Check that a bed exists
    has_bed = any("bed" in f["name"].lower() for f in layout["furniture"])
    assert has_bed
    
    # Check score
    assert result.confidence_score >= 50.0
    db.close()

def test_2_living_room_layout():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Living Salon", room_type="Living Room")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=500.0, width=400.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    has_sofa = any("sofa" in f["name"].lower() for f in layout["furniture"])
    assert has_sofa
    db.close()

def test_3_office_layout():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Work Studio", room_type="Office")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=400.0, width=300.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    has_desk = any("desk" in f["name"].lower() for f in layout["furniture"])
    has_chair = any("chair" in f["name"].lower() for f in layout["furniture"])
    assert has_desk
    assert has_chair
    db.close()

def test_4_dining_room_layout():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Dining Hall", room_type="Dining Room")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=500.0, width=400.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    has_table = any("table" in f["name"].lower() for f in layout["furniture"])
    assert has_table
    db.close()

def test_5_small_room_excessive_furniture():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    # 1.5m x 1.5m room (too small for standard furniture layouts without collisions)
    room = Room(project_id=project.id, room_name="Tiny Closet", room_type="Bedroom")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=150.0, width=150.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    # The generation is expected to fail or trigger safety validation failure since standard bed is 2m x 2.2m
    assert job.status == "Failed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    assert "Unable to generate a valid layout" in result.explanation
    db.close()

def test_6_door_clearance_avoidance():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Entry Bedroom", room_type="Bedroom")
    # Door directly in the middle of North wall (x=300, y=0, width=90)
    openings = [{"x": 300.0, "y": 0.0, "width": 90.0, "type": "door"}]
    room.properties = json.dumps({"openings": openings, "walls": []})
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    # Assert that no furniture overlaps the door swing zone (center=300, 0; distance must be > 90)
    for f in layout["furniture"]:
        dx = f["x"] - 300.0
        dz = f["z"] - 0.0
        dist = math.sqrt(dx**2 + dz**2)
        # Bounding box clearance check
        assert dist >= 90.0
    db.close()

def test_7_window_clearance():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Sunny Bedroom", room_type="Bedroom")
    # Window in the middle of East wall (x=600, y=225, width=120)
    openings = [{"x": 600.0, "y": 225.0, "width": 120.0, "type": "window"}]
    room.properties = json.dumps({"openings": openings, "walls": []})
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    job = AIRepository.get_job(db, job_id)
    assert job.status == "Completed"
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    # Verify no tall furniture blocks the window (distance > 50cm or tall items not near it)
    for f in layout["furniture"]:
        if f.get("height", 0.0) > 100.0:
            dx = f["x"] - 600.0
            dz = f["z"] - 225.0
            dist = math.sqrt(dx**2 + dz**2)
            assert dist >= 50.0
    db.close()

def test_8_panorama_unavailable():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    # Simulate a purely metric-based generation (no pre-existing walls in properties)
    room = Room(project_id=project.id, room_name="Metric Bedroom", room_type="Bedroom")
    room.properties = None
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

def test_9_user_preference_spacious():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Spacious Bedroom", room_type="Bedroom")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    # Generate with "more_spacious" preference
    job_id = AIService.start_layout_generation(
        db, room.id, user.id, "Modern", preferences=["more_spacious"]
    )
    AIService.run_layout_generation_sync(db, job_id)
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    # Should omit optional secondary items like desks or sofas, preserving primary sleep and storage essentials
    item_names = [f["name"].lower() for f in layout["furniture"]]
    assert not any("desk" in name or "sofa" in name for name in item_names)
    db.close()

def test_10_user_preference_storage():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Storage Bedroom", room_type="Bedroom")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(
        db, room.id, user.id, "Modern", preferences=["more_storage"]
    )
    AIService.run_layout_generation_sync(db, job_id)
    
    result = AIRepository.get_result_by_job(db, job_id)
    layout = json.loads(result.layout_json)
    
    # Storage (wardrobe) must be present
    has_wardrobe = any("wardrobe" in f["name"].lower() for f in layout["furniture"])
    assert has_wardrobe
    db.close()

def test_11_collision_rejection_and_correction():
    # Verify that the optimizer successfully resolves collision overlaps
    db = TestingSessionLocal()
    
    # 2 overlapping beds
    room_width = 600.0
    room_length = 450.0
    
    from features.ai.optimizer import optimize_layout_simulated_annealing
    
    bed_asset = db.query(FurnitureAsset).filter(FurnitureAsset.category == "Bedroom").first()
    
    from features.ai.planner import make_furniture_instance
    f1 = make_furniture_instance(bed_asset, 200.0, 0.0, 200.0, 0.0, "Bedroom", "sleep")
    f2 = make_furniture_instance(bed_asset, 220.0, 0.0, 210.0, 0.0, "Bedroom", "sleep")
    
    optimized, report = optimize_layout_simulated_annealing(
        room_width=room_width,
        room_length=room_length,
        room_type="Bedroom",
        furniture=[f1, f2],
        openings=[],
        seed=42,
        num_starts=2
    )
    
    assert report["final"]["collision_violations"] == 0
    db.close()

def test_12_save_and_reopen():
    db = TestingSessionLocal()
    user, project = get_test_user_and_project(db)
    
    room = Room(project_id=project.id, room_name="Persistent Bedroom", room_type="Bedroom")
    db.add(room)
    db.commit()
    
    meas = RoomMeasurement(room_id=room.id, length=600.0, width=450.0, height=300.0)
    db.add(meas)
    db.commit()
    
    job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern")
    AIService.run_layout_generation_sync(db, job_id)
    
    # Re-fetch room from DB to check property persistence
    db.refresh(room)
    layout = json.loads(room.properties)
    assert "furniture" in layout
    assert "ai_layout_metadata" in layout
    
    saved_strategy = layout["ai_layout_metadata"]["strategy"]
    assert saved_strategy in ["wall_aligned", "center_oriented", "window_oriented", "functional_zoned", "space_efficient"]
    db.close()
