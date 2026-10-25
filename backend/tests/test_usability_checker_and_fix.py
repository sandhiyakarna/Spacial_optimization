import pytest
import json
import uuid
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.dependencies import get_db
from core.database.session import Base
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from features.validation.service import ValidationService
from features.validation.fix_service import LayoutFixService
from features.ai.geometry import (
    get_door_swing_geometry, get_furniture_obb, obb_overlap_sat,
    check_furniture_metadata, get_furniture_clearance_obb
)
from tests.db_config import get_test_engine

engine, TEST_SQLALCHEMY_DATABASE_URL = get_test_engine("test_usability_suite.db")
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(scope="module", autouse=True)
def setup_test_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    seed_roles_and_permissions(db)
    seed_furniture_assets(db)
    ValidationService.seed_default_rules(db)
    
    AuthService.register_user(db, UserRegister(
        full_name="Usability Specialist",
        email="usability@flowspace.io",
        password="Password123!"
    ))
    db.close()
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def get_auth_token_and_room():
    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "usability@flowspace.io", "password": "Password123!"}
    )
    token = login_resp.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    create_proj_resp = client.post(
        "/api/v1/projects",
        json={"project_name": f"Usability Studio {uuid.uuid4().hex[:8]}", "description": "Validation & One-Click Fix Suite"},
        headers=headers
    )
    proj_id = create_proj_resp.json()["data"]["project_id"]

    create_room_resp = client.post(
        f"/api/v1/projects/{proj_id}/rooms",
        json={"room_name": "Master Suite", "room_type": "Master Bedroom", "floor_number": 1},
        headers=headers
    )
    room_id = create_room_resp.json()["data"]["room_id"]

    # Measurements 500 x 500 cm
    client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={"length": 500.0, "width": 500.0, "height": 280.0, "floor_thickness": 20.0, "wall_thickness": 15.0, "ceiling_height": 280.0},
        headers=headers
    )
    return headers, room_id


def test_scenario_1_and_2_doorway_and_door_swing():
    """Scenario 1 & 2: Furniture blocking doorway and intersecting door-swing arc."""
    headers, room_id = get_auth_token_and_room()

    # South wall is at Z = 500 cm. Door at X = 250, Z = 500, width = 90 cm.
    # Inward swing arc occupies space in front of the door (e.g. Z between 410 and 500, X around 250).
    layout_data = {
        "walls": [],
        "openings": [
            {"id": "door_main", "type": "door", "x": 250.0, "y": 500.0, "width": 90.0, "angle": 0.0, "hinge": "left"}
        ],
        "furniture": [
            {
                "id": "sofa_door_blocker",
                "name": "Lounge Sofa",
                "width": 180.0,
                "depth": 85.0,
                "height": 75.0,
                "x": 250.0,
                "z": 460.0, # Intersects door swing
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    # Doorway/door-swing error must be caught with measured clearance
    door_issues = [e for e in res["errors"] if e["rule_id"] == "RULE_DOOR" or "door" in e["message"].lower()]
    assert len(door_issues) > 0
    issue = door_issues[0]
    assert issue["affected_furniture_ids"] == ["sofa_door_blocker"]
    assert issue["measured_clearance"] is not None
    assert issue["measured_clearance"] < 90.0
    assert issue["is_fixable"] is True

    # Test One-Click Fix Candidate
    fix_resp = client.post(
        "/api/v1/validation/fix-candidate",
        json={
            "room_id": room_id,
            "rule_id": "RULE_DOOR",
            "issue_type": "door_swing",
            "furniture_id": "sofa_door_blocker"
        },
        headers=headers
    )
    assert fix_resp.status_code == 200
    fix_data = fix_resp.json()["data"]
    assert fix_data["can_fix"] is True
    assert len(fix_data["changes"]) == 1
    assert fix_data["measured_after"] >= fix_data["required_clearance"]
    assert fix_data["changes"][0]["proposed_z"] < 400.0 # Shifted away from door!


def test_scenario_3_walking_passage_validation():
    """Scenario 3: Walking passage narrower than the configured requirement."""
    headers, room_id = get_auth_token_and_room()

    # Place two furniture items with narrow passage (e.g., 40 cm apart when 80 cm required)
    layout_data = {
        "walls": [],
        "openings": [
            {"id": "door_main", "type": "door", "x": 100.0, "y": 500.0, "width": 80.0, "angle": 0.0}
        ],
        "furniture": [
            {
                "id": "desk_1",
                "name": "Work Desk",
                "width": 120.0,
                "depth": 60.0,
                "height": 75.0,
                "x": 200.0,
                "z": 250.0,
                "rotationY": 0.0
            },
            {
                "id": "credenza_1",
                "name": "Storage Credenza",
                "width": 120.0,
                "depth": 50.0,
                "height": 80.0,
                "x": 200.0,
                "z": 345.0, # (345 - 25) - (250 + 30) = 320 - 280 = 40 cm passage!
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    # Configured walkway clearance = 80.0 cm
    run_resp = client.post(
        "/api/v1/validation/run",
        json={"room_id": room_id, "min_walkway_clearance": 80.0},
        headers=headers
    )
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    walkway_issues = [
        i for i in res["errors"] + res["warnings"]
        if i["rule_id"] == "RULE_WALKWAY" and "narrow" in i["message"].lower() or "blocked" in i["message"].lower()
    ]
    assert len(walkway_issues) > 0
    issue = walkway_issues[0]
    assert issue["measured_clearance"] is not None
    assert issue["measured_clearance"] < 80.0
    assert issue["required_clearance"] == 80.0


def test_scenario_4_dining_chair_pullout():
    """Scenario 4: Dining chair without sufficient pull-out space."""
    headers, room_id = get_auth_token_and_room()

    # Dining chair placed only 15 cm from north wall (Z = 0) facing south (local rear towards wall)
    layout_data = {
        "walls": [],
        "openings": [],
        "furniture": [
            {
                "id": "dining_table",
                "name": "Dining Table",
                "width": 140.0,
                "depth": 90.0,
                "height": 75.0,
                "x": 250.0,
                "z": 100.0,
                "rotationY": 0.0
            },
            {
                "id": "dining_chair_tight",
                "name": "Dining Chair",
                "width": 45.0,
                "depth": 45.0,
                "height": 85.0,
                "x": 250.0,
                "z": 30.0, # Too close to Z=0 wall (30 - 22.5 = 7.5 cm from wall!)
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id, "room_type": "Dining Room"}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    dining_issues = [i for i in res["errors"] + res["warnings"] + res["suggestions"] if i["rule_id"] == "RULE_DINING_CLR"]
    assert len(dining_issues) > 0
    assert dining_issues[0]["measured_clearance"] is not None
    assert dining_issues[0]["measured_clearance"] < 50.0


def test_scenario_5_wardrobe_blocked_by_other_furniture():
    """Scenario 5: Wardrobe door/drawer clearance blocked by another furniture item."""
    headers, room_id = get_auth_token_and_room()

    # Wardrobe against North wall (Z = 35), facing south (+Z). Bed placed 25 cm in front of it!
    layout_data = {
        "walls": [],
        "openings": [],
        "furniture": [
            {
                "id": "wardrobe_1",
                "name": "Master Wardrobe",
                "width": 180.0,
                "depth": 60.0,
                "height": 210.0,
                "x": 250.0,
                "z": 35.0, # Front edge is at Z = 35 + 30 = 65 cm
                "rotationY": 0.0
            },
            {
                "id": "bed_blocker",
                "name": "Queen Bed",
                "width": 160.0,
                "depth": 200.0,
                "height": 100.0,
                "x": 250.0,
                "z": 180.0, # Rear edge is at Z = 180 - 100 = 80 cm. Distance is only 15 cm!
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    wardrobe_issues = [i for i in res["errors"] + res["warnings"] if i["rule_id"] == "RULE_WARDROBE_CLR"]
    assert len(wardrobe_issues) > 0
    issue = wardrobe_issues[0]
    assert issue["measured_clearance"] is not None
    assert issue["measured_clearance"] < 75.0
    assert "wardrobe_1" in issue["affected_furniture_ids"]


def test_scenario_6_object_outside_room_boundary():
    """Scenario 6: Object placed outside room boundaries."""
    headers, room_id = get_auth_token_and_room()

    # Place wardrobe partly outside east wall (X > 500)
    layout_data = {
        "walls": [],
        "openings": [],
        "furniture": [
            {
                "id": "out_of_bounds_dresser",
                "name": "Wide Dresser",
                "width": 140.0,
                "depth": 50.0,
                "height": 90.0,
                "x": 490.0, # Center at 490, right edge at 490 + 70 = 560 cm (60 cm outside wall!)
                "z": 250.0,
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    wall_issues = [e for e in res["errors"] if e["rule_id"] == "RULE_WALL"]
    assert len(wall_issues) > 0
    assert "out_of_bounds_dresser" in wall_issues[0]["affected_furniture_ids"]
    assert wall_issues[0]["measured_clearance"] < 0.0 # Negative clearance indicates intrusion


def test_scenario_7_layout_with_multiple_simultaneous_issues():
    """Scenario 7: Multiple simultaneous issues (door swing, collision, out of bounds)."""
    headers, room_id = get_auth_token_and_room()

    layout_data = {
        "walls": [],
        "openings": [
            {"id": "d1", "type": "door", "x": 100.0, "y": 500.0, "width": 90.0, "angle": 0.0}
        ],
        "furniture": [
            {"id": "f_door", "name": "Door Blocker", "width": 100.0, "depth": 80.0, "height": 80.0, "x": 100.0, "z": 460.0, "rotationY": 0.0},
            {"id": "f_col1", "name": "Overlap A", "width": 100.0, "depth": 100.0, "height": 80.0, "x": 300.0, "z": 300.0, "rotationY": 0.0},
            {"id": "f_col2", "name": "Overlap B", "width": 100.0, "depth": 100.0, "height": 80.0, "x": 320.0, "z": 310.0, "rotationY": 0.0},
            {"id": "f_oob", "name": "Outside Shelf", "width": 80.0, "depth": 40.0, "height": 180.0, "x": 510.0, "z": 100.0, "rotationY": 0.0}
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    rule_ids = [e["rule_id"] for e in res["errors"]]
    assert "RULE_DOOR" in rule_ids
    assert "RULE_COLLISION" in rule_ids
    assert "RULE_WALL" in rule_ids


def test_scenario_8_no_valid_correction_exists():
    """Scenario 8: Overcrowded room where no valid correction exists."""
    headers, room_id = get_auth_token_and_room()

    # Small room 200 x 200 cm completely packed with large furniture items
    client.put(
        f"/api/v1/rooms/{room_id}/measurements",
        json={"length": 200.0, "width": 200.0, "height": 280.0, "floor_thickness": 20.0, "wall_thickness": 15.0, "ceiling_height": 280.0},
        headers=headers
    )

    # 4 large beds/sofas filling the entire 200x200 space leaving no free room
    furniture = [
        {"id": "huge_bed_1", "name": "Massive Bed 1", "width": 120.0, "depth": 100.0, "height": 80.0, "x": 60.0, "z": 50.0, "rotationY": 0.0},
        {"id": "huge_bed_2", "name": "Massive Bed 2", "width": 120.0, "depth": 100.0, "height": 80.0, "x": 140.0, "z": 50.0, "rotationY": 0.0},
        {"id": "huge_bed_3", "name": "Massive Bed 3", "width": 120.0, "depth": 100.0, "height": 80.0, "x": 60.0, "z": 150.0, "rotationY": 0.0},
        {"id": "problem_item", "name": "Overlapping Sofa", "width": 120.0, "depth": 100.0, "height": 80.0, "x": 100.0, "z": 100.0, "rotationY": 0.0}
    ]

    fix_data = LayoutFixService.find_fix_for_issue(
        room_width=200.0,
        room_length=200.0,
        room_type="Bedroom",
        furniture=furniture,
        openings=[],
        target_furniture_id="problem_item",
        issue_type="collision"
    )

    # Must honestly report that no correction can fit!
    assert fix_data.can_fix is False
    assert len(fix_data.alternative_suggestions) > 0
    assert "compact" in fix_data.alternative_suggestions[0].lower() or "remove" in fix_data.alternative_suggestions[0].lower()


def test_scenario_9_correction_rejects_new_violations():
    """Scenario 9: Candidate generation rejects proposals that introduce new collisions or block doors."""
    # Place item A blocking door, with item B right next to it.
    # The fix should not move item A into collision with item B.
    furniture = [
        {"id": "f_a", "name": "Moving Sofa", "width": 100.0, "depth": 80.0, "height": 80.0, "x": 100.0, "z": 450.0, "rotationY": 0.0},
        {"id": "f_b", "name": "Fixed Desk", "width": 120.0, "depth": 60.0, "height": 75.0, "x": 100.0, "z": 300.0, "rotationY": 0.0}
    ]
    openings = [
        {"id": "door_1", "type": "door", "x": 100.0, "y": 500.0, "width": 90.0, "angle": 0.0}
    ]

    fix_data = LayoutFixService.find_fix_for_issue(
        room_width=500.0,
        room_length=500.0,
        room_type="Living Room",
        furniture=furniture,
        openings=openings,
        target_furniture_id="f_a",
        issue_type="door_swing"
    )

    assert fix_data.can_fix is True
    # The proposed position for f_a must NOT overlap f_b!
    prop_change = fix_data.changes[0]
    cand_obb = get_furniture_obb({
        "x": prop_change.proposed_x,
        "z": prop_change.proposed_z,
        "width": 100.0,
        "depth": 80.0,
        "rotationY": prop_change.proposed_rotation
    })
    b_obb = get_furniture_obb(furniture[1])
    overlap, _, _ = obb_overlap_sat(cand_obb, b_obb)
    assert overlap is False


def test_scenario_10_apply_fix_and_revalidate():
    """Scenario 10: Apply fix endpoint and layout revalidation."""
    headers, room_id = get_auth_token_and_room()

    # Layout with 1 door blocker
    layout_data = {
        "walls": [],
        "openings": [
            {"id": "door_1", "type": "door", "x": 200.0, "y": 500.0, "width": 90.0, "angle": 0.0}
        ],
        "furniture": [
            {
                "id": "sofa_test",
                "name": "Cozy Couch",
                "width": 160.0,
                "depth": 80.0,
                "height": 80.0,
                "x": 200.0,
                "z": 455.0, # blocks door swing
                "rotationY": 0.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    # 1. Get Fix Candidate
    fix_cand_resp = client.post(
        "/api/v1/validation/fix-candidate",
        json={
            "room_id": room_id,
            "rule_id": "RULE_DOOR",
            "furniture_id": "sofa_test",
            "issue_type": "door_swing"
        },
        headers=headers
    )
    assert fix_cand_resp.status_code == 200
    candidate = fix_cand_resp.json()["data"]["changes"][0]

    # 2. Apply Fix
    apply_resp = client.post(
        "/api/v1/validation/apply-fix",
        json={
            "room_id": room_id,
            "furniture_id": "sofa_test",
            "proposed_x": candidate["proposed_x"],
            "proposed_z": candidate["proposed_z"],
            "proposed_rotation": candidate["proposed_rotation"]
        },
        headers=headers
    )
    assert apply_resp.status_code == 200
    revalidated = apply_resp.json()["data"]

    # In revalidated state, door blockage must be completely eliminated!
    door_errs = [e for e in revalidated["errors"] if e["rule_id"] == "RULE_DOOR"]
    assert len(door_errs) == 0


def test_scenario_11_missing_metadata_detection():
    """Scenario 11: Missing door or furniture clearance metadata."""
    headers, room_id = get_auth_token_and_room()

    # Furniture with zero dimensions
    layout_data = {
        "walls": [],
        "openings": [],
        "furniture": [
            {
                "id": "mystery_item",
                "name": "Mystery Box",
                "width": 0.0, # invalid/missing
                "depth": 0.0,
                "height": 0.0,
                "x": 200.0,
                "z": 200.0
            }
        ]
    }

    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(layout_data)},
        headers=headers
    )

    run_resp = client.post("/api/v1/validation/run", json={"room_id": room_id}, headers=headers)
    assert run_resp.status_code == 200
    res = run_resp.json()["data"]

    meta_issues = [i for i in res["warnings"] if i["rule_id"] == "RULE_METADATA" or "metadata" in i["message"].lower()]
    assert len(meta_issues) > 0
    assert "mystery_item" in meta_issues[0]["affected_furniture_ids"]
    assert meta_issues[0]["is_fixable"] is False


def test_scenario_12_save_and_reopen_corrected_layout():
    """Scenario 12: Saving and reopening the corrected layout."""
    headers, room_id = get_auth_token_and_room()

    # Save initial layout with sofa_test
    initial_layout = {
        "walls": [],
        "openings": [],
        "furniture": [
            {
                "id": "sofa_test",
                "name": "Sofa",
                "width": 180.0,
                "depth": 85.0,
                "height": 75.0,
                "x": 200.0,
                "z": 460.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(
        f"/api/v1/rooms/{room_id}/layout",
        json={"success": True, "layout_data": json.dumps(initial_layout)},
        headers=headers
    )

    # Apply fix to layout
    apply_resp = client.post(
        "/api/v1/validation/apply-fix",
        json={
            "room_id": room_id,
            "furniture_id": "sofa_test",
            "proposed_x": 200.0,
            "proposed_z": 250.0,
            "proposed_rotation": 0.0
        },
        headers=headers
    )
    assert apply_resp.status_code == 200

    # Reopen room layout from DB
    get_room_resp = client.get(f"/api/v1/rooms/{room_id}", headers=headers)
    assert get_room_resp.status_code == 200
    room_data = get_room_resp.json()["data"]
    props = json.loads(room_data["properties"])
    
    saved_furniture = next((f for f in props["furniture"] if f["id"] == "sofa_test"), None)
    assert saved_furniture is not None
    assert saved_furniture["z"] == 250.0
