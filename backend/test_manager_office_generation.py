import json
import time
import httpx

BASE_URL = "http://127.0.0.1:8000/api/v1"

def run_manager_office_tests():
    client = httpx.Client(timeout=60.0)
    
    # 1. Login / Register
    email = "manager_tester@flowspace.com"
    password = "Password123!"
    
    login_resp = client.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    if login_resp.status_code == 200:
        token = login_resp.json()["data"]["access_token"]
    else:
        reg_resp = client.post(f"{BASE_URL}/auth/register", json={"full_name": "Manager Tester", "email": email, "password": password})
        assert reg_resp.status_code == 201, f"Register failed: {reg_resp.text}"
        login_resp = client.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
        token = login_resp.json()["data"]["access_token"]

    headers = {"Authorization": f"Bearer {token}"}
    print("[+] Auth successful.")

    ts = int(time.time())

    # 2. Test Standard Manager's Office (500x400 cm)
    print("\n--- TEST 1: Standard Manager's Office (500x400cm) ---")
    proj_resp = client.post(f"{BASE_URL}/projects", json={
        "project_name": f"Manager Office Project {ts}",
        "description": "Testing AI Manager Office Generation",
        "location": "Executive Suite"
    }, headers=headers)
    assert proj_resp.status_code == 201, f"Project creation failed: {proj_resp.text}"
    proj_id = proj_resp.json()["data"]["project_id"]

    room_resp = client.post(f"{BASE_URL}/projects/{proj_id}/rooms", json={
        "room_name": "Manager's Room 101",
        "room_type": "Manager's Office",
        "floor_number": 1
    }, headers=headers)
    assert room_resp.status_code == 201, f"Room creation failed: {room_resp.text}"
    room_id = room_resp.json()["data"]["room_id"]

    # Measurements: 500cm width, 400cm length, 280cm height
    meas_resp = client.put(f"{BASE_URL}/rooms/{room_id}/measurements", json={
        "width": 500.0,
        "length": 400.0,
        "height": 280.0,
        "wall_thickness": 15.0
    }, headers=headers)
    assert meas_resp.status_code == 200, f"Measurements failed: {meas_resp.text}"

    # Openings: Door on south wall (x=250, y=400)
    openings = [
        {"id": "door_1", "type": "door", "x": 250.0, "y": 400.0, "width": 90.0, "angle": 0.0},
        {"id": "win_1", "type": "window", "x": 250.0, "y": 0.0, "width": 120.0, "angle": 0.0}
    ]
    client.put(f"{BASE_URL}/rooms/{room_id}/layout", json={
        "success": True,
        "layout_data": json.dumps({"walls": [], "openings": openings, "furniture": []})
    }, headers=headers)

    # Trigger AI Layout Generation for Manager's Office
    gen_resp = client.post(f"{BASE_URL}/ai/layout", json={
        "room_id": room_id,
        "style": "Modern Executive",
        "command": "Generates complete Manager's Office with desk, manager chair, visitor chairs, cabinet, and bookshelf"
    }, headers=headers)
    assert gen_resp.status_code == 201, f"AI generation trigger failed: {gen_resp.text}"
    job_id = gen_resp.json()["data"]["job_id"]
    print(f"[+] Started AI Layout Job: {job_id}")

    # Poll status
    status = "Pending"
    for _ in range(30):
        job_resp = client.get(f"{BASE_URL}/ai/jobs/{job_id}", headers=headers)
        status = job_resp.json()["data"]["status"]
        if status == "Completed":
            break
        elif status == "Failed":
            raise Exception("AI Job reported Failed")
        time.sleep(1.0)
    assert status == "Completed", f"Job failed to complete in time (status={status})"

    res_resp = client.get(f"{BASE_URL}/ai/results/{job_id}", headers=headers)
    res_data = res_resp.json()["data"]
    layout_data = json.loads(res_data["layout_data"])
    furniture = layout_data.get("furniture", [])

    print(f"[+] AI Generated {len(furniture)} items for Manager's Office:")
    categories = [f.get("category", "") for f in furniture]
    names = [f.get("name", "") for f in furniture]
    for f in furniture:
        print(f"    - {f.get('name')}: ({f.get('x'):.1f}, {f.get('z'):.1f}), rot={f.get('rotationY'):.2f}, dim={f.get('width')}x{f.get('depth')}x{f.get('height')}cm")

    # Assert mandatory items present
    has_desk = any("desk" in n.lower() or "desk" in c.lower() for n, c in zip(names, categories))
    has_chair = any("manager" in n.lower() or "exec" in n.lower() or "ergonomic" in n.lower() for n in names)
    has_visitor = any("visitor" in n.lower() or "guest" in n.lower() for n in names)
    has_cabinet = any("cabinet" in n.lower() or "storage" in n.lower() for n in names)
    has_bookshelf = any("bookshelf" in n.lower() or "shelf" in n.lower() for n in names)

    assert has_desk, "Executive desk missing!"
    assert has_chair, "Manager chair missing!"
    assert has_visitor, "Visitor chairs missing!"
    assert has_cabinet, "Storage cabinet missing!"
    assert has_bookshelf, "Bookshelf missing!"

    print("[+] All mandatory furniture items present in generated layout!")

    # Validate collisions
    val_resp = client.post(f"{BASE_URL}/validation/run", json={"room_id": room_id}, headers=headers)
    val_data = val_resp.json()["data"]
    collisions = [e for e in val_data.get("errors", []) if "collision" in e["message"].lower() or "overlap" in e["message"].lower()]
    print(f"[+] Validation result: {val_data.get('overall_status')}, Collisions count: {len(collisions)}")
    assert len(collisions) == 0, f"Collisions found in AI layout: {collisions}"

    # 3. Test Small Office (300x250 cm)
    print("\n--- TEST 2: Small Office (300x250cm) ---")
    s_room_resp = client.post(f"{BASE_URL}/projects/{proj_id}/rooms", json={
        "room_name": "Compact Office 102",
        "room_type": "Manager's Office",
        "floor_number": 1
    }, headers=headers)
    s_room_id = s_room_resp.json()["data"]["room_id"]

    client.put(f"{BASE_URL}/rooms/{s_room_id}/measurements", json={
        "width": 300.0,
        "length": 250.0,
        "height": 280.0
    }, headers=headers)

    s_gen_resp = client.post(f"{BASE_URL}/ai/layout", json={
        "room_id": s_room_id,
        "style": "Modern"
    }, headers=headers)
    s_job_id = s_gen_resp.json()["data"]["job_id"]

    for _ in range(30):
        s_job_resp = client.get(f"{BASE_URL}/ai/jobs/{s_job_id}", headers=headers)
        if s_job_resp.json()["data"]["status"] == "Completed":
            break
        time.sleep(1.0)

    s_res_resp = client.get(f"{BASE_URL}/ai/results/{s_job_id}", headers=headers)
    s_layout = json.loads(s_res_resp.json()["data"]["layout_data"])
    s_furniture = s_layout.get("furniture", [])
    print(f"[+] Small office generated {len(s_furniture)} items collision-free.")

    s_val = client.post(f"{BASE_URL}/validation/run", json={"room_id": s_room_id}, headers=headers).json()["data"]
    s_collisions = [e for e in s_val.get("errors", []) if "collision" in e["message"].lower()]
    assert len(s_collisions) == 0, f"Collisions in small office layout: {s_collisions}"

    # 4. Test Persistence
    print("\n--- TEST 3: Persistence and Reloading ---")
    reload_resp = client.get(f"{BASE_URL}/rooms/{room_id}/layout", headers=headers)
    reloaded_data = json.loads(reload_resp.json()["layout_data"])
    assert len(reloaded_data.get("furniture", [])) == len(furniture), "Persistence mismatch!"
    print("[+] Persistence verified! Generated layout successfully saved and reloaded.")

    print("\n==================================================")
    print(" ALL MANAGER'S OFFICE ACCEPTANCE TESTS PASSED!")
    print("==================================================")

if __name__ == "__main__":
    run_manager_office_tests()
