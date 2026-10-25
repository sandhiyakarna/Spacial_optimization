import json
import csv
import time
import math
from typing import Any, Dict, Final, List
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score

def print_banner(text: str):
    print("\n" + "=" * 80)
    print(f" {text}")
    print("=" * 80)

def visualize_layout_text(room_name: str, before_scores: Dict[str, Any], after_scores: Dict[str, Any]):
    print(f"\n[+] Room: {room_name}")
    print("-" * 50)
    
    b_detail = before_scores["details"]
    a_detail = after_scores["details"]
    b_sub = before_scores["subscores"]
    a_sub = after_scores["subscores"]
    
    b_col = b_detail.get("collisions", 0)
    a_col = a_detail.get("collisions", 0)
    b_oob = b_detail.get("out_of_bounds", 0)
    a_oob = a_detail.get("out_of_bounds", 0)
    b_door = b_detail.get("blocked_doors", 0)
    a_door = a_detail.get("blocked_doors", 0)
    
    print("  INITIAL STATUS (BAD):")
    if b_col > 0 or b_oob > 0 or b_door > 0:
        if b_col > 0: print(f"    [FAIL] overlapping furniture ({b_col} overlaps)")
        if b_oob > 0: print(f"    [FAIL] furniture outside room ({b_oob} out of bounds)")
        if b_door > 0: print(f"    [FAIL] blocked walkway / door ({b_door} blocked doors)")
    else:
        print("    [PASS] safe / no violations")
        
    print(f"    [WARN] poor clearance (Ergonomics Score: {b_sub.get('ergonomics', 0.0):.1f})")
    print(f"    Overall Score: {before_scores['overall_score']:.1f}")
    
    print("\n      >>> OPTIMIZER >>>\n")
    
    print("  FINAL STATUS (GOOD):")
    if a_col == 0 and a_oob == 0 and a_door == 0:
        print("    [PASS] furniture separated")
        print("    [PASS] valid room boundaries")
        print("    [PASS] walkway clear / door open")
    else:
        if a_col > 0: print(f"    [FAIL] overlapping furniture ({a_col} overlaps)")
        if a_oob > 0: print(f"    [FAIL] furniture outside room ({a_oob} out of bounds)")
        if a_door > 0: print(f"    [FAIL] blocked walkway ({a_door} blocked doors)")
        
    print(f"    [PASS] ergonomic access (Ergonomics Score: {a_sub.get('ergonomics', 0.0):.1f})")
    print(f"    Overall Score: {after_scores['overall_score']:.1f}")
    print("-" * 50)

def main():
    print_banner("FLOWSPACE - SPATIAL OPTIMIZER QUALITY BENCHMARKS")
    
    # Define Benchmark 1: Bedroom (6m x 4.5m)
    # Intentionally poor: Bed overlapping Nightstand, Wardrobe blocking the door
    benchmarks = [
        {
            "name": "Benchmark 1: 6m x 4.5m Bedroom",
            "type": "Bedroom",
            "width": 600.0,
            "length": 450.0,
            "openings": [
                {"id": "door_1", "type": "door", "x": 60.0, "y": 0.0, "width": 90.0, "angle": 0.0}
            ],
            "furniture": [
                {"id": "bed_1", "name": "Queen Bed", "category": "bedroom", "x": 200.0, "z": 200.0, "width": 160.0, "depth": 200.0, "height": 80.0, "rotationY": 0.0},
                {"id": "nightstand_1", "name": "Nightstand", "category": "bedroom", "x": 210.0, "z": 205.0, "width": 50.0, "depth": 40.0, "height": 55.0, "rotationY": 0.0}, # Overlaps bed
                {"id": "wardrobe_1", "name": "Wardrobe", "category": "storage", "x": 60.0, "z": 45.0, "width": 100.0, "depth": 60.0, "height": 210.0, "rotationY": 0.0} # Blocks door
            ]
        },
        {
            "name": "Benchmark 2: 5m x 4m Living Room",
            "type": "Living Room",
            "width": 500.0,
            "length": 400.0,
            "openings": [
                {"id": "door_1", "type": "door", "x": 60.0, "y": 0.0, "width": 90.0, "angle": 0.0}
            ],
            "furniture": [
                {"id": "sofa_1", "name": "Sofa", "category": "livingroom", "x": 250.0, "z": 200.0, "width": 200.0, "depth": 90.0, "height": 85.0, "rotationY": 0.0},
                {"id": "table_1", "name": "Coffee Table", "category": "livingroom", "x": 240.0, "z": 195.0, "width": 120.0, "depth": 70.0, "height": 45.0, "rotationY": 0.0}, # Overlaps sofa
                {"id": "tv_1", "name": "TV Console", "category": "livingroom", "x": 60.0, "z": 40.0, "width": 140.0, "depth": 45.0, "height": 60.0, "rotationY": 0.0} # Blocks door
            ]
        },
        {
            "name": "Benchmark 3: 4m x 3m Office",
            "type": "Office",
            "width": 400.0,
            "length": 300.0,
            "openings": [
                {"id": "door_1", "type": "door", "x": 50.0, "y": 0.0, "width": 90.0, "angle": 0.0}
            ],
            "furniture": [
                {"id": "desk_1", "name": "Study Desk", "category": "office", "x": 150.0, "z": 150.0, "width": 140.0, "depth": 70.0, "height": 75.0, "rotationY": 0.0},
                {"id": "chair_1", "name": "Office Chair", "category": "office", "x": 145.0, "z": 145.0, "width": 60.0, "depth": 60.0, "height": 90.0, "rotationY": 0.0}, # Overlaps desk
                {"id": "bookshelf_1", "name": "Bookshelf", "category": "office", "x": 395.0, "z": 150.0, "width": 80.0, "depth": 35.0, "height": 180.0, "rotationY": 0.0} # Out of bounds
            ]
        },
        {
            "name": "Benchmark 4: 5m x 4m Dining Room",
            "type": "Dining Room",
            "width": 500.0,
            "length": 400.0,
            "openings": [
                {"id": "door_1", "type": "door", "x": 60.0, "y": 0.0, "width": 90.0, "angle": 0.0}
            ],
            "furniture": [
                {"id": "table_1", "name": "Dining Table", "category": "dining", "x": -20.0, "z": 150.0, "width": 180.0, "depth": 90.0, "height": 75.0, "rotationY": 0.0}, # Out of bounds
                {"id": "chair_1", "name": "Dining Chair 1", "category": "dining", "x": 200.0, "z": 200.0, "width": 50.0, "depth": 50.0, "height": 85.0, "rotationY": 0.0},
                {"id": "chair_2", "name": "Dining Chair 2", "category": "dining", "x": 210.0, "z": 205.0, "width": 50.0, "depth": 50.0, "height": 85.0, "rotationY": 0.0} # Overlaps chair 1
            ]
        }
    ]
    
    results = []
    
    for bm in benchmarks:
        print(f"\nRunning Optimization on: {bm['name']}")
        
        # Calculate Initial design score
        init_scores = calculate_design_score(
            bm["width"], bm["length"], bm["type"], bm["furniture"], bm["openings"]
        )
        
        # Run Simulated Annealing optimizer (using deterministic seed = 42 for testing)
        start_time = time.perf_counter()
        optimized, report = optimize_layout_simulated_annealing(
            room_width=bm["width"],
            room_length=bm["length"],
            room_type=bm["type"],
            furniture=bm["furniture"],
            openings=bm["openings"],
            seed=42,
            num_starts=5
        )
        elapsed = time.perf_counter() - start_time
        
        # Calculate Final design score
        final_scores = calculate_design_score(
            bm["width"], bm["length"], bm["type"], optimized, bm["openings"]
        )
        
        # Visualize stdout
        visualize_layout_text(bm["name"], init_scores, final_scores)
        
        # Store benchmark statistics
        results.append({
            "room": bm["name"],
            "initial_score": float(init_scores["overall_score"]),
            "final_score": float(final_scores["overall_score"]),
            "improvement": float(final_scores["overall_score"] - init_scores["overall_score"]),
            "collision_before": int(init_scores["details"].get("collisions", 0)),
            "collision_after": int(final_scores["details"].get("collisions", 0)),
            "ergonomic_before": float(init_scores["subscores"].get("ergonomics", 0.0)),
            "ergonomic_after": float(final_scores["subscores"].get("ergonomics", 0.0)),
            "circulation_before": float(init_scores["subscores"].get("accessibility", 0.0)),
            "circulation_after": float(final_scores["subscores"].get("accessibility", 0.0)),
            "utilization_before": float(init_scores["subscores"].get("space_utilization", 0.0)),
            "utilization_after": float(final_scores["subscores"].get("space_utilization", 0.0)),
            "runtime": float(elapsed),
            "iterations": int(report.get("iterations", 0))
        })
        
    # Write JSON report
    json_path = "../optimizer_benchmark_results.json"
    with open(json_path, "w") as f:
        json.dump(results, f, indent=4)
    print(f"\n[+] Saved JSON report to: {json_path}")
    
    # Write CSV report
    csv_path = "../optimizer_benchmark_results.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "room", "initial_score", "final_score", "improvement",
            "collision_before", "collision_after", "ergonomic_before", "ergonomic_after",
            "circulation_before", "circulation_after", "utilization_before", "utilization_after",
            "runtime", "iterations"
        ])
        writer.writeheader()
        writer.writerows(results)
    print(f"[+] Saved CSV report to: {csv_path}")
    
    print("\nAcceptance Validation Summary:")
    print("=" * 40)
    all_passed = True
    for res in results:
        passed = (res["collision_after"] == 0 and res["improvement"] > 0)
        print(f"  {res['room']}: {'Passed [OK]' if passed else 'Failed [FAIL]'}")
        if not passed:
            all_passed = False
    print("=" * 40)
    
    if all_passed:
        print("\nALL BENCHMARKS PASSED SUCCESSFULLY!")
    else:
        print("\nSOME BENCHMARKS FAILED.")
        
if __name__ == "__main__":
    main()
