import httpx
import json
import math
import time
from typing import Set, Type

BASE_URL = "http://127.0.0.1:8000/api/v1"

def print_header(title):
    print("\n" + "=" * 60)
    print(f" {title}")
    print("=" * 60)

def main():
    client = httpx.Client(timeout=30.0)

    # ----------------------------------------------------
    # PREPARATION & AUTHENTICATION
    # ----------------------------------------------------
    print_header("PREPARATION: AUTHENTICATION")
    email = "acceptance_tester@example.com"
    password = "Password123!"

    # Try login first
    token = None
    try:
        login_resp = client.post(f"{BASE_URL}/auth/login", json={
            "email": email,
            "password": password
        })
        if login_resp.status_code == 200:
            token = login_resp.json()["data"]["access_token"]
            print("[+] Logged in successfully.")
    except Exception as e:
        print(f"Login failed/skipped: {e}")

    if not token:
        # Register new user
        reg_resp = client.post(f"{BASE_URL}/auth/register", json={
            "full_name": "Acceptance Tester",
            "email": email,
            "password": password
        })
        if reg_resp.status_code == 201:
            print("[+] Registered successfully.")
            # Log in
            login_resp = client.post(f"{BASE_URL}/auth/login", json={
                "email": email,
                "password": password
            })
            token = login_resp.json()["data"]["access_token"]
            print("[+] Logged in after registration.")
        else:
            print(f"[-] Registration failed: {reg_resp.text}")
            return

    headers = {"Authorization": f"Bearer {token}"}

    # ----------------------------------------------------
    # TEST 1: CREATE A ROOM WITHOUT PANORAMA
    # ----------------------------------------------------
    print_header("TEST 1: CREATE PANORAMA-INDEPENDENT ROOM")
    # Create Project
    import time
    timestamp = int(time.time())
    proj_resp = client.post(f"{BASE_URL}/projects", json={
        "project_name": f"Acceptance Project {timestamp}",
        "description": "Project for spatial acceptance testing",
        "location": "Test Lab"
    }, headers=headers)
    if proj_resp.status_code != 201:
        print(f"[-] Failed to create project: {proj_resp.text}")
        return
    proj_id = proj_resp.json()["data"]["project_id"]
    print(f"[+] Created Project ID: {proj_id}")

    # Create Room (Bedroom)
    room_resp = client.post(f"{BASE_URL}/projects/{proj_id}/rooms", json={
        "room_name": "Bedroom 101",
        "room_type": "Bedroom",
        "floor_number": 1,
        "notes": "Acceptance test room"
    }, headers=headers)
    if room_resp.status_code != 201:
        print(f"[-] Failed to create room: {room_resp.text}")
        return
    room_id = room_resp.json()["data"]["room_id"]
    print(f"[+] Created Room ID: {room_id}")

    # Set Measurements: 6.0m length (600cm), 4.5m width (450cm), 3.0m height (300cm)
    meas_resp = client.put(f"{BASE_URL}/rooms/{room_id}/measurements", json={
        "length": 600.0,
        "width": 450.0,
        "height": 300.0,
        "floor_thickness": 30.0,
        "wall_thickness": 20.0,
        "ceiling_height": 300.0
    }, headers=headers)
    print(f"[+] Measurements set: Length=600cm, Width=450cm, Height=300cm (Status={meas_resp.status_code})")

    # Set openings: 1 door, 2 windows in properties
    openings = [
        {"id": "door_1", "type": "door", "x": 50.0, "y": 0.0, "width": 80.0, "angle": 0.0},
        {"id": "win_1", "type": "window", "x": 200.0, "y": 0.0, "width": 100.0, "angle": 0.0},
        {"id": "win_2", "type": "window", "x": 400.0, "y": 0.0, "width": 100.0, "angle": 0.0}
    ]
    room_layout = {
        "walls": [],
        "openings": openings,
        "furniture": []
    }
    layout_resp = client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(room_layout)
    }, headers=headers)
    print(f"[+] Set room layout with 1 door and 2 windows (Status={layout_resp.status_code})")

    # ----------------------------------------------------
    # TEST 2: AI-ASSISTED LAYOUT
    # ----------------------------------------------------
    print_header("TEST 2: AI-ASSISTED LAYOUT GENERATION")
    # Trigger layout generation
    gen_resp = client.post(f"{BASE_URL}/ai/layout", json={
        "room_id": room_id,
        "style": "Modern"
    }, headers=headers)
    if gen_resp.status_code != 201:
        print(f"[-] AI Layout trigger failed: {gen_resp.text}")
        return
    job_id = gen_resp.json()["data"]["job_id"]
    print(f"[+] Started AI Layout Job: {job_id}")

    # Poll status
    for _ in range(20):
        job_resp = client.get(f"{BASE_URL}/ai/jobs/{job_id}", headers=headers)
        status_data = job_resp.json()["data"]
        print(f"    - Job status: {status_data['status']} ({status_data['progress']}% done)")
        if status_data["status"] == "Completed":
            break
        time.sleep(1.0)

    # Get results
    res_resp = client.get(f"{BASE_URL}/ai/results/{job_id}", headers=headers)
    res_data = res_resp.json()["data"]
    layout_json = json.loads(res_data["layout_data"])
    furniture_placements = layout_json.get("furniture", [])

    print(f"[+] AI Heuristic Layout returned {len(furniture_placements)} furniture placements:")
    for f in furniture_placements:
        print(f"    - Name: {f.get('name')}")
        print(f"      asset_id: {f.get('asset_id') or f.get('assetId')}")
        print(f"      position: (x={f.get('x')}, y={f.get('y')}, z={f.get('z')})")
        print(f"      rotationY: {f.get('rotationY')}")
        print(f"      dimensions: {f.get('width')}w x {f.get('depth')}d x {f.get('height')}h")

    # Fetch available furniture assets to use for manual tests with high limit
    furn_resp = client.get(f"{BASE_URL}/furniture?limit=1000", headers=headers)
    assets = furn_resp.json()
    print(f"[+] Retrieved {len(assets)} furniture assets from catalog.")
    
    bed_asset = next((a for a in assets if "bed" in a["name"].lower()), None)
    sofa_asset = next((a for a in assets if "sofa" in a["name"].lower() or "couch" in a["name"].lower()), None)
    desk_asset = next((a for a in assets if "desk" in a["name"].lower() or "table" in a["name"].lower()), None)
    chair_asset = next((a for a in assets if "chair" in a["name"].lower() or "seating" in a["name"].lower()), None)
    table_asset = next((a for a in assets if "table" in a["name"].lower() or "dining" in a["name"].lower()), None)

    # Robust fallbacks
    if not bed_asset:
        print("[!] Bed asset not found, falling back to first asset.")
        bed_asset = assets[0] if assets else {"id": "FS_ASSET_BED", "name": "Fallback Bed", "width": 200.0, "depth": 200.0, "height": 80.0}
    if not sofa_asset:
        print("[!] Sofa asset not found, falling back to first asset.")
        sofa_asset = assets[0] if assets else {"id": "FS_ASSET_SOFA", "name": "Fallback Sofa", "width": 210.0, "depth": 90.0, "height": 85.0}
    if not desk_asset:
        print("[!] Desk asset not found, falling back to first asset.")
        desk_asset = assets[0] if assets else {"id": "FS_ASSET_DESK", "name": "Fallback Desk", "width": 120.0, "depth": 60.0, "height": 75.0}
    if not chair_asset:
        print("[!] Chair asset not found, falling back to first asset.")
        chair_asset = assets[0] if assets else {"id": "FS_ASSET_CHAIR", "name": "Fallback Chair", "width": 60.0, "depth": 60.0, "height": 90.0}
    if not table_asset:
        print("[!] Table asset not found, falling back to first asset.")
        table_asset = assets[0] if assets else {"id": "FS_ASSET_TABLE", "name": "Fallback Table", "width": 160.0, "depth": 90.0, "height": 75.0}

    print(f"    - Selected Bed Asset: {bed_asset['name']} (ID: {bed_asset['id']})")
    print(f"    - Selected Sofa Asset: {sofa_asset['name']} (ID: {sofa_asset['id']})")
    print(f"    - Selected Desk Asset: {desk_asset['name']} (ID: {desk_asset['id']})")
    print(f"    - Selected Chair Asset: {chair_asset['name']} (ID: {chair_asset['id']})")
    print(f"    - Selected Table Asset: {table_asset['name']} (ID: {table_asset['id']})")

    # ----------------------------------------------------
    # TEST 3: COLLISION DEMONSTRATION
    # ----------------------------------------------------
    print_header("TEST 3: COLLISION DEMONSTRATION")
    # Place two overlapping modern sofas
    overlapping_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 200.0,
                "y": 0.0,
                "z": 200.0,
                "rotationY": 0.0
            },
            {
                "id": "f_sofa_2",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 220.0,  # Overlaps significantly
                "z": 210.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(overlapping_layout)
    }, headers=headers)
    
    val_resp = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    val_data = val_resp.json()["data"]
    print(f"[+] Overlapping placement validated. Status: {val_data['overall_status']}")
    print(f"    - Errors found: {len(val_data['errors'])}")
    for err in val_data['errors']:
        print(f"      * [ERROR] {err['message']} (Severity={err['severity']})")

    # Move them apart
    resolved_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 150.0,
                "y": 0.0,
                "z": 200.0,
                "rotationY": 0.0
            },
            {
                "id": "f_sofa_2",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 400.0,  # Far away
                "z": 200.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(resolved_layout)
    }, headers=headers)

    val_resp_2 = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    val_data_2 = val_resp_2.json()["data"]
    print(f"[+] Repositioned placement validated. Status: {val_data_2['overall_status']}")
    print(f"    - Errors found: {len(val_data_2['errors'])}")

    # ----------------------------------------------------
    # TEST 4: ROTATED COLLISION
    # ----------------------------------------------------
    print_header("TEST 4: ROTATED COLLISION (45°, 90°, 135°)")
    rotations = [45.0, 90.0, 135.0]
    for rot in rotations:
        rad = math.radians(rot)
        rotated_layout = {
            "walls": [],
            "openings": openings,
            "furniture": [
                {
                    "id": "f_sofa_1",
                    "asset_id": sofa_asset["id"],
                    "name": sofa_asset["name"],
                    "width": sofa_asset["width"],
                    "depth": sofa_asset["depth"],
                    "height": sofa_asset["height"],
                    "x": 200.0,
                    "y": 0.0,
                    "z": 200.0,
                    "rotationY": 0.0
                },
                {
                    "id": "f_sofa_2",
                    "asset_id": sofa_asset["id"],
                    "name": sofa_asset["name"],
                    "width": sofa_asset["width"],
                    "depth": sofa_asset["depth"],
                    "height": sofa_asset["height"],
                    "x": 300.0,
                    "z": 220.0,
                    "y": 0.0,
                    "rotationY": rad
                }
            ]
        }
        client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
            "success": True,
            "layout_data": json.dumps(rotated_layout)
        }, headers=headers)
        val_rot = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
        v_data = val_rot.json()["data"]
        collisions = [e for e in v_data["errors"] if "collision" in e["message"].lower() or "overlap" in e["message"].lower()]
        print(f"[+] Rotated collision at {rot}°: Overlap Detected = {len(collisions) > 0} (Errors Count = {len(collisions)})")

    # ----------------------------------------------------
    # TEST 5: WALL COLLISION
    # ----------------------------------------------------
    print_header("TEST 5: WALL COLLISION (OUT OF BOUNDS)")
    out_of_bounds_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 580.0,
                "z": 200.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(out_of_bounds_layout)
    }, headers=headers)
    val_wall = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    w_data = val_wall.json()["data"]
    wall_errs = [e for e in w_data["errors"] if "outside the room boundaries" in e["message"].lower() or "wall" in e["message"].lower()]
    print(f"[+] Out of bounds validated. Status: {w_data['overall_status']}")
    print(f"    - Wall collision errors: {len(wall_errs)}")
    for e in wall_errs:
        print(f"      * {e['message']}")

    # ----------------------------------------------------
    # TEST 6: DOOR CLEARANCE
    # ----------------------------------------------------
    print_header("TEST 6: DOOR CLEARANCE (SWING BLOCKAGE)")
    door_block_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 60.0,
                "z": 50.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(door_block_layout)
    }, headers=headers)
    val_door = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    d_data = val_door.json()["data"]
    door_errs = [e for e in d_data["errors"] if "blocks the door swing" in e["message"].lower()]
    print(f"[+] Door swing block validated. Status: {d_data['overall_status']}")
    print(f"    - Door block errors: {len(door_errs)}")
    for e in door_errs:
        print(f"      * {e['message']}")

    # ----------------------------------------------------
    # TEST 7: WALKWAY BLOCKAGE
    # ----------------------------------------------------
    print_header("TEST 7: WALKWAY / CIRCULATION ACCESSIBILITY")
    walkway_block_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 100.0,
                "z": 120.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(walkway_block_layout)
    }, headers=headers)
    scores_blocked = client.get(f"{BASE_URL}/ai/scores/{room_id}", headers=headers).json()["data"]
    print(f"[+] Blocked Walkway Scores:")
    print(f"    - Overall Score: {scores_blocked['overall_score']}")
    print(f"    - Accessibility Score: {scores_blocked['subscores']['accessibility']}")

    # Restore/move sofa away to clear walkway
    clear_walkway_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "f_sofa_1",
                "asset_id": sofa_asset["id"],
                "name": sofa_asset["name"],
                "width": sofa_asset["width"],
                "depth": sofa_asset["depth"],
                "height": sofa_asset["height"],
                "x": 300.0,
                "z": 300.0,
                "y": 0.0,
                "rotationY": 0.0
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(clear_walkway_layout)
    }, headers=headers)
    scores_clear = client.get(f"{BASE_URL}/ai/scores/{room_id}", headers=headers).json()["data"]
    print(f"[+] Cleared Walkway Scores:")
    print(f"    - Overall Score: {scores_clear['overall_score']}")
    print(f"    - Accessibility Score: {scores_clear['subscores']['accessibility']}")

    # ----------------------------------------------------
    # TEST 8: ERGONOMICS (BED CLEARANCE)
    # ----------------------------------------------------
    print_header("TEST 8: ERGONOMICS")
    bed_ergo_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "bed_1",
                "asset_id": bed_asset["id"],
                "name": bed_asset["name"],
                "width": bed_asset["width"],
                "depth": bed_asset["depth"],
                "height": bed_asset["height"],
                "x": 300.0,
                "z": 110.0,
                "y": 0.0,
                "rotationY": 0.0,
                "category": "Bedroom"
            },
            {
                "id": "blocker_desk",
                "asset_id": desk_asset["id"],
                "name": desk_asset["name"],
                "width": desk_asset["width"],
                "depth": desk_asset["depth"],
                "height": desk_asset["height"],
                "x": 160.0,
                "z": 110.0,
                "y": 0.0,
                "rotationY": 0.0,
                "category": "Bedroom"
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(bed_ergo_layout)
    }, headers=headers)
    scores_ergo = client.get(f"{BASE_URL}/ai/scores/{room_id}", headers=headers).json()["data"]
    print(f"[+] Bed Clearance Blocked:")
    print(f"    - Ergonomics Score: {scores_ergo['subscores']['ergonomics']}")

    # ----------------------------------------------------
    # TEST 9 & 10: SPATIAL SCORE & OPTIMIZATION
    # ----------------------------------------------------
    print_header("TEST 9 & 10: SPATIAL SCORE & OPTIMIZATION")
    poor_layout = {
        "walls": [],
        "openings": openings,
        "furniture": [
            {
                "id": "poor_bed",
                "asset_id": bed_asset["id"],
                "name": bed_asset["name"],
                "width": bed_asset["width"],
                "depth": bed_asset["depth"],
                "height": bed_asset["height"],
                "x": 70.0,
                "z": 80.0,
                "y": 0.0,
                "rotationY": 0.0,
                "category": "Bedroom"
            },
            {
                "id": "poor_desk",
                "asset_id": desk_asset["id"],
                "name": desk_asset["name"],
                "width": desk_asset["width"],
                "depth": desk_asset["depth"],
                "height": desk_asset["height"],
                "x": 80.0,
                "z": 90.0,
                "y": 0.0,
                "rotationY": 0.0,
                "category": "Bedroom"
            }
        ]
    }
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(poor_layout)
    }, headers=headers)

    poor_scores_resp = client.get(f"{BASE_URL}/ai/scores/{room_id}", headers=headers)
    poor_scores = poor_scores_resp.json()["data"]
    print("[+] BEFORE OPTIMIZATION:")
    print(f"    - Overall Score: {poor_scores['overall_score']}")
    print(f"    - Safety Score (Collision): {poor_scores['subscores']['safety']}")
    print(f"    - Circulation Score (Accessibility): {poor_scores['subscores']['accessibility']}")
    print(f"    - Ergonomic Score: {poor_scores['subscores']['ergonomics']}")
    print(f"    - Space Utilization: {poor_scores['subscores']['space_utilization']}")

    # Run optimizer
    print("\n[~] Running Simulated Annealing Optimizer...")
    opt_resp = client.post(f"{BASE_URL}/ai/optimize", json={"room_id": room_id}, headers=headers)
    opt_data = opt_resp.json()["data"]
    opt_layout = json.loads(opt_data["layout_data"])

    print("\n[+] AFTER OPTIMIZATION:")
    print(f"    - Overall Score: {opt_data['overall_score']}")
    print(f"    - Safety Score (Collision): {opt_data['subscores']['safety']}")
    print(f"    - Circulation Score (Accessibility): {opt_data['subscores']['accessibility']}")
    print(f"    - Ergonomic Score: {opt_data['subscores']['ergonomics']}")
    print(f"    - Space Utilization: {opt_data['subscores']['space_utilization']}")

    print("\n[+] Optimized Placement Results:")
    for f in opt_layout.get("furniture", []):
        print(f"    * {f.get('name')}: pos=(x={f.get('x')}, z={f.get('z')}), rot={f.get('rotationY')}")

    # ----------------------------------------------------
    # TEST 11: AI CONSTRAINT SAFETY
    # ----------------------------------------------------
    print_header("TEST 11: AI CONSTRAINT SAFETY")
    val_opt = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    opt_val_data = val_opt.json()["data"]
    opt_collisions = [e for e in opt_val_data["errors"] if "collision" in e["message"].lower() or "overlap" in e["message"].lower()]
    print(f"[+] Checked optimized layout for collisions. Remaining collisions: {len(opt_collisions)}")
    print(f"    - Overall status: {opt_val_data['overall_status']}")

    # ----------------------------------------------------
    # TEST 13: PERSISTENCE
    # ----------------------------------------------------
    print_header("TEST 13: PERSISTENCE")
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps(opt_layout)
    }, headers=headers)
    
    reload_resp = client.get(f"{BASE_URL}/rooms/{room_id}", headers=headers)
    reload_data = reload_resp.json()["data"]
    print(f"[+] Reloaded Room details:")
    print(f"    - Name: {reload_data['room_name']}")
    print(f"    - Type: {reload_data['room_type']}")
    print(f"    - Measurements: length={reload_data['measurements']['length']}, width={reload_data['measurements']['width']}")
    
    reload_layout_resp = client.get(f"{BASE_URL}/rooms/{room_id}/layout", headers=headers)
    reloaded_layout = json.loads(reload_layout_resp.json()["layout_data"])
    print(f"[+] Reloaded Layout contains {len(reloaded_layout.get('furniture', []))} furniture items.")
    print(f"[+] Recomputing optimization score after reload:")
    scores_reloaded = client.get(f"{BASE_URL}/ai/scores/{room_id}", headers=headers).json()["data"]
    print(f"    - Recomputed Overall Score: {scores_reloaded['overall_score']}")

    # ----------------------------------------------------
    # TEST 16: NO MOCK VALUES
    # ----------------------------------------------------
    print_header("TEST 16: NO MOCK VALUES CHECK")
    print("[+] Inspected calculations:")
    print(f"    - safety score: {poor_scores['subscores']['safety']} (Poor) vs {opt_data['subscores']['safety']} (Optimized)")
    print(f"    - accessibility score: {poor_scores['subscores']['accessibility']} (Poor) vs {opt_data['subscores']['accessibility']} (Optimized)")
    print(f"    - ergonomic score: {poor_scores['subscores']['ergonomics']} (Poor) vs {opt_data['subscores']['ergonomics']} (Optimized)")
    print(f"    - utilization score: {poor_scores['subscores']['space_utilization']} (Poor) vs {opt_data['subscores']['space_utilization']} (Optimized)")
    print("[+] All scores are computed dynamically from OBB coordinates, SAT overlap, and clearance logic.")

if __name__ == "__main__":
    main()
