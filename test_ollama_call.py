import httpx
import json
import time

def test():
    t0 = time.time()
    try:
        tags_resp = httpx.get("http://localhost:11434/api/tags", timeout=5.0)
        print("Ollama Tags:", tags_resp.status_code, [m['name'] for m in tags_resp.json().get('models', [])])
    except Exception as ex:
        print("Tags error:", ex)
        return

    catalog = [
        {"asset_id": "KITCHEN_COUNTER001", "name": "Modular Kitchen Counter", "width": 180.0, "depth": 60.0, "height": 90.0},
        {"asset_id": "SINK001", "name": "Kitchen Sink Station", "width": 120.0, "depth": 60.0, "height": 90.0},
        {"asset_id": "FRIDGE001", "name": "Refrigerator Unit", "width": 80.0, "depth": 70.0, "height": 185.0},
        {"asset_id": "KITCHEN_STOVE001", "name": "Kitchen Cooking Range & Stove", "width": 80.0, "depth": 60.0, "height": 90.0},
        {"asset_id": "CABINET001", "name": "Kitchen Storage Cabinet", "width": 100.0, "depth": 50.0, "height": 190.0}
    ]

    prompt = f"""You are a professional interior designer. Propose a layout plan for a Kitchen (500x500 cm).
Select items strictly from this catalog: {json.dumps(catalog)}

Return JSON with:
{{
  "room_type": "Kitchen",
  "layout_intent": "L-shaped ergonomic workflow",
  "furniture": [
    {{"asset_id": "KITCHEN_COUNTER001", "role": "kitchen_counter", "preferred_wall": "west", "preferred_zone": "preparation"}},
    {{"asset_id": "SINK001", "role": "sink", "preferred_wall": "west", "preferred_zone": "cleaning"}},
    {{"asset_id": "FRIDGE001", "role": "refrigerator", "preferred_wall": "north", "preferred_zone": "food_storage"}},
    {{"asset_id": "KITCHEN_STOVE001", "role": "stove", "preferred_wall": "north", "preferred_zone": "cooking"}}
  ],
  "functional_zones": {{"preparation": ["KITCHEN_COUNTER001"], "cleaning": ["SINK001"], "cooking": ["KITCHEN_STOVE001"], "food_storage": ["FRIDGE001"]}},
  "design_rationale": "Efficient work triangle",
  "constraints_considered": ["Preserve 90cm door clearance"],
  "unresolved_requirements": []
}}
"""
    print("Calling Ollama...")
    try:
        resp = httpx.post(
            "http://localhost:11434/api/generate",
            json={
                "model": "qwen3:8b",
                "prompt": prompt,
                "stream": False,
                "format": "json"
            },
            timeout=60.0
        )
        print("Status code:", resp.status_code, f"took {time.time()-t0:.2f}s")
        text = resp.json().get("response", "")
        print("Response length:", len(text))
        print("Response preview:", text[:400])
        parsed = json.loads(text)
        print("Parsed JSON successfully! Keys:", list(parsed.keys()))
    except Exception as ex:
        print("Call error:", ex)

if __name__ == "__main__":
    test()
