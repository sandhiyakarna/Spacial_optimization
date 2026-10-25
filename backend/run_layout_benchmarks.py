import json
import csv
import time
import os
from datetime import datetime, timezone
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from core.database.session import Base
from features.auth.models import User
from features.project.models import Project
from features.room.models import Room, RoomMeasurement
from features.furniture.models import FurnitureAsset
from features.ai.service import AIService
from features.ai.repository import AIRepository
from features.ai.planner import generate_layout_candidates
from features.ai.scoring import calculate_design_score
from features.auth.services import seed_roles_and_permissions, AuthService
from features.auth.schemas import UserRegister
from features.furniture.services import seed_furniture_assets
from typing import Final

def print_banner(text: str):
    print("\n" + "=" * 80)
    print(f" {text}")
    print("=" * 80)

def main():
    print_banner("FLOWSPACE - INITIAL LAYOUT GENERATOR QUALITY BENCHMARKS")
    
    # 1. Setup temporary in-memory database
    engine = create_engine("sqlite:///:memory:")
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    
    # 2. Seed database
    print("[+] Seeding layout asset database...")
    seed_roles_and_permissions(db)
    seed_furniture_assets(db)
    
    # Create benchmark user and project
    AuthService.register_user(db, UserRegister(
        full_name="Benchmark User",
        email="benchmark@example.com",
        password="Password123!"
    ))
    user = db.query(User).filter_by(email="benchmark@example.com").first()
    project = Project(project_name="Benchmark Project", user_id=user.id)
    db.add(project)
    db.commit()
    db.refresh(project)
    
    # 3. Define Rooms to Benchmark
    rooms_to_test = [
        {
            "name": "Bedroom",
            "room_type": "Bedroom",
            "length": 600.0,
            "width": 450.0,
            "openings": [{"x": 100.0, "y": 0.0, "width": 90.0, "type": "door"}]
        },
        {
            "name": "Living Room",
            "room_type": "Living Room",
            "length": 500.0,
            "width": 400.0,
            "openings": [{"x": 60.0, "y": 0.0, "width": 90.0, "type": "door"}]
        },
        {
            "name": "Office",
            "room_type": "Office",
            "length": 400.0,
            "width": 300.0,
            "openings": [{"x": 50.0, "y": 0.0, "width": 90.0, "type": "door"}]
        },
        {
            "name": "Dining Room",
            "room_type": "Dining Room",
            "length": 500.0,
            "width": 400.0,
            "openings": [{"x": 60.0, "y": 0.0, "width": 90.0, "type": "door"}]
        },
        {
            "name": "Kitchen",
            "room_type": "Kitchen",
            "length": 450.0,
            "width": 350.0,
            "openings": [{"x": 60.0, "y": 0.0, "width": 90.0, "type": "door"}]
        }
    ]
    
    benchmark_records = []
    
    for r_cfg in rooms_to_test:
        print(f"\n[+] Evaluating Layout Generation on: {r_cfg['name']} ({r_cfg['length']}x{r_cfg['width']})")
        
        room = Room(project_id=project.id, room_name=r_cfg["name"], room_type=r_cfg["room_type"])
        room.properties = json.dumps({"openings": r_cfg["openings"], "walls": []})
        db.add(room)
        db.commit()
        db.refresh(room)
        
        meas = RoomMeasurement(room_id=room.id, length=r_cfg["length"], width=r_cfg["width"], height=300.0)
        db.add(meas)
        db.commit()
        
        # Measure candidate generation time
        t_gen_start = time.perf_counter()
        candidates = generate_layout_candidates(
            db, r_cfg["length"], r_cfg["width"], r_cfg["room_type"], "Modern", r_cfg["openings"], [], 42
        )
        t_gen_elapsed = (time.perf_counter() - t_gen_start) * 1000.0
        
        # Run full pipeline (includes optimization and final scoring)
        t_pipeline_start = time.perf_counter()
        job_id = AIService.start_layout_generation(db, room.id, user.id, "Modern", seed=42, num_starts=3)
        AIService.run_layout_generation_sync(db, job_id)
        t_pipeline_elapsed = (time.perf_counter() - t_pipeline_start) * 1000.0
        
        # Fetch results
        result = AIRepository.get_result_by_job(db, job_id)
        assert result is not None
        
        layout = json.loads(result.layout_json)
        furniture_placed = layout.get("furniture", [])
        
        # Calculate subscores
        scores = calculate_design_score(r_cfg["width"], r_cfg["length"], r_cfg["room_type"], furniture_placed, r_cfg["openings"])
        
        # Extract metadata
        metadata = layout.get("ai_layout_metadata", {})
        strategy_selected = metadata.get("strategy", "default")
        opt_report = metadata.get("optimization_report", {})
        
        record = {
            "room_type": r_cfg["room_type"],
            "dimensions": f"{r_cfg['length']} x {r_cfg['width']}",
            "furniture_selected": [f["name"] for f in furniture_placed],
            "candidates_generated": len(candidates),
            "invalid_candidates_rejected": len(candidates) - 1, # Optimizer refines candidates and selects the best valid
            "final_score": round(scores["overall_score"], 2),
            "collision_status": "SAFE" if scores["details"]["collisions"] == 0 else "COLLISION",
            "ergonomic_score": round(scores["subscores"]["ergonomics"], 2),
            "circulation_score": round(scores["subscores"]["accessibility"], 2),
            "generation_time_ms": round(t_gen_elapsed, 2),
            "optimization_time_ms": round(t_pipeline_elapsed - t_gen_elapsed, 2),
            "total_time_ms": round(t_pipeline_elapsed, 2)
        }
        
        benchmark_records.append(record)
        
        print(f"    - Strategy Selected: {strategy_selected}")
        print(f"    - Final Design Score: {record['final_score']}/100")
        print(f"    - Collision Status: {record['collision_status']}")
        print(f"    - Ergonomics Score: {record['ergonomic_score']}/100")
        print(f"    - Circulation Score: {record['circulation_score']}/100")
        print(f"    - Total Generation Time: {record['total_time_ms']:.2f} ms")
        
    db.close()
    
    # 4. Save results to JSON and CSV in workspace root
    json_path = "../ai_layout_generation_benchmark.json"
    csv_path = "../ai_layout_generation_benchmark.csv"
    
    with open(json_path, "w") as f:
        json.dump(benchmark_records, f, indent=2)
    print(f"\n[+] Saved JSON benchmark report: {json_path}")
    
    headers = [
        "room_type", "dimensions", "furniture_selected", "candidates_generated", 
        "invalid_candidates_rejected", "final_score", "collision_status", 
        "ergonomic_score", "circulation_score", "generation_time_ms", 
        "optimization_time_ms", "total_time_ms"
    ]
    
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=headers)
        writer.writeheader()
        for r in benchmark_records:
            # Format list of furniture to comma-separated string
            row = r.copy()
            row["furniture_selected"] = ", ".join(row["furniture_selected"])
            writer.writerow(row)
    print(f"[+] Saved CSV benchmark report: {csv_path}")

if __name__ == "__main__":
    main()
