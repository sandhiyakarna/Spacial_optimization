import json
import math
from datetime import datetime, timezone
from typing import List, Dict, Any, Tuple
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func

from features.room.models import Room
from features.project.models import Project
from features.ai.models import Analytics, RoomScore, DesignHistory, RecommendationHistory
from features.ai.scoring import calculate_design_score
from features.ai.repository import AIRepository
from features.ai.geometry import OccupancyGrid, get_furniture_bbox, compute_reachability

class AnalyticsService:

    PRICE_MAP = {
        "bed": 600.0,
        "sofa": 800.0,
        "couch": 800.0,
        "chair": 150.0,
        "table": 300.0,
        "desk": 250.0,
        "nightstand": 120.0,
        "stand": 100.0,
        "wardrobe": 500.0,
        "dresser": 400.0,
        "cabinet": 300.0,
        "bookshelf": 200.0,
        "shelf": 150.0
    }

    PRICE_DATA = {
        "bed": {"std_w": 200.0, "std_d": 160.0},
        "sofa": {"std_w": 210.0, "std_d": 90.0},
        "couch": {"std_w": 210.0, "std_d": 90.0},
        "chair": {"std_w": 60.0, "std_d": 60.0},
        "table": {"std_w": 120.0, "std_d": 80.0},
        "desk": {"std_w": 140.0, "std_d": 70.0},
        "nightstand": {"std_w": 50.0, "std_d": 40.0},
        "stand": {"std_w": 50.0, "std_d": 40.0},
        "wardrobe": {"std_w": 150.0, "std_d": 60.0},
        "dresser": {"std_w": 120.0, "std_d": 50.0},
        "cabinet": {"std_w": 80.0, "std_d": 40.0},
        "bookshelf": {"std_w": 80.0, "std_d": 30.0},
        "shelf": {"std_w": 80.0, "std_d": 30.0}
    }

    @classmethod
    def get_estimated_cost(cls, furniture: List[Dict[str, Any]]) -> float:
        total = 0.0
        for f in furniture:
            name = f.get('name', '').lower()
            category = f.get('category', '').lower()
            style = f.get('style', '').lower()
            mat_type = f.get('materialType')
            mat_type_str = str(mat_type).lower() if mat_type else ''
            
            matched = False
            base_price = 150.0
            std_w, std_d = 80.0, 80.0
            
            for key, val in cls.PRICE_MAP.items():
                if key in name or key in category:
                    base_price = val
                    std_info = cls.PRICE_DATA.get(key, {})
                    std_w = std_info.get("std_w", 80.0)
                    std_d = std_info.get("std_d", 80.0)
                    matched = True
                    break
            
            # Multipliers
            # 1. Style Multiplier
            style_mult = 1.0
            if any(s in style for s in ["luxury", "classic", "vintage"]):
                style_mult = 1.5
            elif any(s in style for s in ["minimal", "industrial", "scandinavian", "modern"]):
                style_mult = 1.0
            elif any(s in style for s in ["budget", "simple", "basic"]):
                style_mult = 0.7
                
            # 2. Material Multiplier
            mat_mult = 1.0
            if "leather" in mat_type_str:
                mat_mult = 1.4
            elif any(m in mat_type_str for m in ["solid wood", "hardwood", "metal"]):
                mat_mult = 1.2
            elif any(m in mat_type_str for m in ["fabric", "plastic", "laminate"]):
                mat_mult = 0.9
                
            # 3. Size Multiplier (ratio of footprint area to standard footprint area)
            size_mult = 1.0
            if "width" in f and "depth" in f:
                f_area = f["width"] * f["depth"]
                std_area = std_w * std_d
                if std_area > 0:
                    raw_ratio = f_area / std_area
                    size_mult = max(0.7, min(1.5, raw_ratio))
            
            item_price = base_price * style_mult * mat_mult * size_mult
            total += round(item_price, 2)
            
        return float(round(total, 2))

    @classmethod
    def ensure_room_scores(cls, db: Session, room: Room) -> Dict[str, Any]:
        """Helper to compute and save scores if they do not exist or are outdated."""
        if not room.measurements:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Room measurements must be defined before retrieving analytics."
            )
        
        props = json.loads(room.properties) if room.properties else {}
        furniture = props.get('furniture', [])
        openings = props.get('openings', [])
        
        calc = calculate_design_score(
            room.measurements.width,
            room.measurements.length,
            room.room_type,
            furniture,
            openings
        )
        
        # Save scores to analytics database tables
        AIRepository.save_analytics(
            db,
            room.id,
            calc['subscores']['accessibility'],
            calc['subscores']['lighting'],
            calc['subscores']['ergonomics'],
            calc['subscores']['space_utilization'],
            calc['subscores']['balance'],
            calc['overall_score']
        )
        
        return calc

    @classmethod
    def get_analytics_dashboard(cls, db: Session, room_id: str) -> Dict[str, Any]:
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Room {room_id} not found")
        
        # Try finding stored analytics
        analytics = db.query(Analytics).filter(Analytics.room_id == room_id).first()
        if not analytics:
            calc = cls.ensure_room_scores(db, room)
            return {
                "accessibility_score": calc['subscores']['accessibility'],
                "lighting_score": calc['subscores']['lighting'],
                "comfort_score": calc['subscores']['ergonomics'],
                "balance_score": calc['subscores']['balance'],
                "space_utilization": calc['subscores']['space_utilization'],
                "overall_score": calc['overall_score']
            }
        
        return {
            "accessibility_score": analytics.accessibility_score,
            "lighting_score": analytics.lighting_score,
            "comfort_score": analytics.ergonomic_score,
            "balance_score": analytics.furniture_balance_score,
            "space_utilization": analytics.space_utilization_score,
            "overall_score": analytics.overall_score
        }

    @classmethod
    def get_detailed_scores(cls, db: Session, room_id: str) -> Dict[str, Any]:
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Room {room_id} not found")
            
        analytics = db.query(Analytics).filter(Analytics.room_id == room_id).first()
        if not analytics:
            cls.ensure_room_scores(db, room)
            analytics = db.query(Analytics).filter(Analytics.room_id == room_id).first()
            
        subscores = {}
        for s in analytics.scores:
            subscores[s.metric.lower().replace(" ", "_")] = s.score
            
        return {
            "accessibility_score": analytics.accessibility_score,
            "lighting_score": analytics.lighting_score,
            "ergonomic_score": analytics.ergonomic_score,
            "space_utilization_score": analytics.space_utilization_score,
            "furniture_balance_score": analytics.furniture_balance_score,
            "overall_score": analytics.overall_score,
            "subscores": subscores
        }

    @classmethod
    def get_scores_for_layout_json(cls, room: Room, layout_json: str) -> Dict[str, Any]:
        """Calculates scores for a specific layout configuration in string form."""
        if not room.measurements:
            return {
                "overall_score": 0.0,
                "subscores": {
                    "accessibility": 0.0, "lighting": 0.0, "ergonomics": 0.0,
                    "space_utilization": 0.0, "balance": 0.0, "aesthetics": 0.0,
                    "functionality": 0.0, "safety": 0.0
                }
            }
        props = json.loads(layout_json) if layout_json else {}
        return calculate_design_score(
            room.measurements.width,
            room.measurements.length,
            room.room_type,
            props.get('furniture', []),
            props.get('openings', [])
        )

    @classmethod
    def compare_layouts(cls, db: Session, layout_a: str, layout_b: str) -> Dict[str, Any]:
        # Resolve Layout A
        room_a = db.query(Room).filter(Room.id == layout_a).first()
        layout_a_json = None
        room_obj = None
        name_a = "Layout A"
        
        if room_a:
            layout_a_json = room_a.properties or "{}"
            room_obj = room_a
            name_a = f"{room_a.room_name} (Current)"
        else:
            dh_a = db.query(DesignHistory).filter(DesignHistory.id == layout_a).first()
            if dh_a:
                layout_a_json = dh_a.snapshot_json
                room_obj = dh_a.room
                name_a = f"Version {dh_a.version_number}"
                
        # Resolve Layout B
        room_b = db.query(Room).filter(Room.id == layout_b).first()
        layout_b_json = None
        name_b = "Layout B"
        
        if room_b:
            layout_b_json = room_b.properties or "{}"
            if not room_obj:
                room_obj = room_b
            name_b = f"{room_b.room_name} (Current)"
        else:
            dh_b = db.query(DesignHistory).filter(DesignHistory.id == layout_b).first()
            if dh_b:
                layout_b_json = dh_b.snapshot_json
                if not room_obj:
                    room_obj = dh_b.room
                name_b = f"Version {dh_b.version_number}"

        if not room_obj or not layout_a_json or not layout_b_json:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="One or both layouts could not be located in database."
            )
            
        scores_a = cls.get_scores_for_layout_json(room_obj, layout_a_json)
        scores_b = cls.get_scores_for_layout_json(room_obj, layout_b_json)
        
        overall_a = scores_a["overall_score"]
        overall_b = scores_b["overall_score"]
        
        diff = overall_b - overall_a
        improvement = diff > 0
        winner = layout_b if diff >= 0 else layout_a
        
        recs = []
        # Generate comparative suggestions
        recs.append(f"{name_b if diff >= 0 else name_a} has the higher overall Design Health score.")
        
        # Compare space utilization
        util_a = scores_a["subscores"]["space_utilization"]
        util_b = scores_b["subscores"]["space_utilization"]
        if abs(util_b - util_a) > 5:
            if util_b > util_a:
                recs.append(f"{name_b} achieves a better space utilization efficiency (+{util_b - util_a:.1f}%).")
            else:
                recs.append(f"{name_a} achieves a better space utilization efficiency (+{util_a - util_b:.1f}%).")

        # Compare accessibility
        acc_a = scores_a["subscores"]["accessibility"]
        acc_b = scores_b["subscores"]["accessibility"]
        if abs(acc_b - acc_a) > 5:
            if acc_b > acc_a:
                recs.append(f"{name_b} improves walkway circulation and furniture reachability (+{acc_b - acc_a:.1f}%).")
            else:
                recs.append(f"{name_a} improves walkway circulation and furniture reachability (+{acc_a - acc_b:.1f}%).")

        # Compare lighting
        lit_a = scores_a["subscores"]["lighting"]
        lit_b = scores_b["subscores"]["lighting"]
        if abs(lit_b - lit_a) > 5:
            if lit_b > lit_a:
                recs.append(f"{name_b} does a better job of preserving natural lighting and avoiding window blockages.")
            else:
                recs.append(f"{name_a} does a better job of preserving natural lighting and avoiding window blockages.")

        # Compare safety
        saf_a = scores_a["subscores"]["safety"]
        saf_b = scores_b["subscores"]["safety"]
        if saf_b > saf_a:
            recs.append(f"{name_b} has fewer furniture overlaps or door swing obstructions.")
        elif saf_a > saf_b:
            recs.append(f"{name_a} has fewer furniture overlaps or door swing obstructions.")

        return {
            "improvement": improvement,
            "score_difference": round(abs(diff), 2),
            "winner": winner,
            "recommendations": recs
        }

    @classmethod
    def get_history(cls, db: Session, room_id: str) -> List[Dict[str, Any]]:
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Room {room_id} not found")
            
        history_entries = db.query(DesignHistory).filter(DesignHistory.room_id == room_id).order_by(DesignHistory.version_number.asc()).all()
        result = []
        for entry in history_entries:
            scores = cls.get_scores_for_layout_json(room, entry.snapshot_json)
            result.append({
                "id": entry.id,
                "version_number": entry.version_number,
                "overall_score": scores["overall_score"],
                "accessibility_score": scores["subscores"]["accessibility"],
                "lighting_score": scores["subscores"]["lighting"],
                "ergonomic_score": scores["subscores"]["ergonomics"],
                "space_utilization_score": scores["subscores"]["space_utilization"],
                "furniture_balance_score": scores["subscores"]["balance"],
                "created_at": entry.created_at,
                "summary": entry.summary or f"Version {entry.version_number}"
            })
        return result

    @classmethod
    def get_statistics(cls, db: Session, room_id: str) -> Dict[str, Any]:
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room or not room.measurements:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Room {room_id} or measurements not found")
            
        props = json.loads(room.properties) if room.properties else {}
        furniture = props.get('furniture', [])
        openings = props.get('openings', [])
        
        # Calculations
        furniture_count = len(furniture)
        occupied_area = sum(f.get('width', 100.0) * f.get('depth', 100.0) for f in furniture)
        room_area = room.measurements.length * room.measurements.width
        free_area = max(0.0, room_area - occupied_area)
        
        # Calculate walkway coverage using reachability grid
        grid = OccupancyGrid(room.measurements.length, room.measurements.width)
        bboxes = [get_furniture_bbox(f) for f in furniture]
        for bbox in bboxes:
            grid.mark_obstacle_rect(bbox['left'], bbox['right'], bbox['top'], bbox['bottom'])
            
        doors = [op for op in openings if op.get('type') == 'door']
        if doors:
            start_cell = grid.to_cell(doors[0].get('x', 0.0), doors[0].get('y', 0.0))
        else:
            start_cell = grid.to_cell(room.measurements.length / 2.0, room.measurements.width / 2.0)
            
        # Clear start cell for reachability checks
        grid.grid[start_cell[0]][start_cell[1]] = 0
        reachable_cells = compute_reachability(grid, start_cell)
        total_walkable_cells = sum(1 for i in range(grid.width_cells) for j in range(grid.length_cells) if grid.grid[i][j] == 0)
        walkway_coverage = (len(reachable_cells) / total_walkable_cells) * 100.0 if total_walkable_cells > 0 else 100.0
        
        # Average clearance
        average_clearance = sum(f.get('clearance', 50.0) for f in furniture) / furniture_count if furniture_count > 0 else 0.0
        
        # Estimated cost
        estimated_cost = cls.get_estimated_cost(furniture)
        
        return {
            "furniture_count": furniture_count,
            "occupied_area": round(occupied_area, 2),
            "free_area": round(free_area, 2),
            "walkway_coverage": round(walkway_coverage, 2),
            "average_clearance": round(average_clearance, 2),
            "estimated_cost": estimated_cost
        }

    @classmethod
    def get_insights(cls, db: Session, room_id: str) -> List[str]:
        scores = cls.get_analytics_dashboard(db, room_id)
        
        insights = []
        # Accessibility insight
        acc = scores["accessibility_score"]
        if acc >= 80:
            insights.append("Your furniture arrangement provides excellent circulation with clear walkways.")
        elif acc >= 50:
            insights.append("Some pathways are narrow. Consider aligning chairs or smaller tables to open up pathways.")
        else:
            insights.append("Walkways are tight. Removing 1 or 2 furniture pieces will significantly improve room flow.")

        # Lighting insight
        lit = scores["lighting_score"]
        if lit >= 80:
            insights.append("Excellent preservation of natural light. Windows are clear of major obstructions.")
        else:
            insights.append("Natural lighting could be improved. Try moving taller cabinets or bookshelves away from window lanes.")

        # Ergonomics/Comfort
        com = scores["comfort_score"]
        if com >= 80:
            insights.append("The current layout achieves excellent ergonomic efficiency and placement comfort.")
        else:
            insights.append("Check clearance gaps around major furniture. Some items may feel cramped to access.")

        # Space Utilization
        util = scores["space_utilization"]
        if util > 80:
            insights.append("The space is highly utilized. Ensure there is enough open floor to avoid a cluttered feeling.")
        elif util < 40:
            insights.append("The space feels sparse. Adding accent rugs or wall decor can group and anchor your furniture.")
        else:
            insights.append("Well-balanced space utilization, matching room proportions beautifully.")

        # Balance
        bal = scores["balance_score"]
        if bal >= 75:
            insights.append("Furniture is balanced and distributed evenly across the room's axes.")
        else:
            insights.append("Visual weight is uneven. Try distributing heavy items (e.g. bed/sofa) to opposite walls.")
            
        return insights

    @classmethod
    def get_project_analytics(cls, db: Session, project_id: str) -> Dict[str, Any]:
        project = db.query(Project).filter(Project.id == project_id).first()
        if not project:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Project {project_id} not found")
            
        rooms = project.rooms
        total_rooms = len(rooms)
        
        if total_rooms == 0:
            return {
                "project_id": project_id,
                "average_overall_score": 0.0,
                "total_rooms": 0,
                "total_furniture_count": 0,
                "total_occupied_area": 0.0,
                "total_free_area": 0.0,
                "room_scores": []
            }
            
        total_furniture = 0
        total_occupied = 0.0
        total_free = 0.0
        scores_sum = 0.0
        room_scores = []
        
        for room in rooms:
            if not room.measurements:
                continue
                
            props = json.loads(room.properties) if room.properties else {}
            furniture = props.get('furniture', [])
            
            # Sum up counts & areas
            total_furniture += len(furniture)
            room_occupied = sum(f.get('width', 100.0) * f.get('depth', 100.0) for f in furniture)
            total_occupied += room_occupied
            room_area = room.measurements.length * room.measurements.width
            total_free += max(0.0, room_area - room_occupied)
            
            # Get score
            stored_analytics = db.query(Analytics).filter(Analytics.room_id == room.id).first()
            if stored_analytics:
                score = stored_analytics.overall_score
            else:
                try:
                    calc = cls.ensure_room_scores(db, room)
                    score = calc["overall_score"]
                except Exception:
                    score = 0.0
                    
            scores_sum += score
            room_scores.append({
                "room_id": room.id,
                "room_name": room.room_name,
                "room_type": room.room_type,
                "overall_score": round(score, 1)
            })
            
        avg_score = scores_sum / total_rooms if total_rooms > 0 else 0.0
        
        return {
            "project_id": project_id,
            "average_overall_score": round(avg_score, 1),
            "total_rooms": total_rooms,
            "total_furniture_count": total_furniture,
            "total_occupied_area": round(total_occupied, 2),
            "total_free_area": round(total_free, 2),
            "room_scores": room_scores
        }

    @classmethod
    def restore_history(cls, db: Session, room_id: str, version_number: int) -> Dict[str, Any]:
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Room {room_id} not found")
            
        history_entry = db.query(DesignHistory).filter(
            DesignHistory.room_id == room_id,
            DesignHistory.version_number == version_number
        ).first()
        
        if not history_entry:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Version {version_number} of layout history could not be found."
            )
            
        # Update room properties
        room.properties = history_entry.snapshot_json
        room.updated_at = datetime.now(timezone.utc)
        db.commit()
        
        # Save historical version as a new current version in design_history
        max_ver = db.query(func.max(DesignHistory.version_number)).filter(DesignHistory.room_id == room_id).scalar()
        next_ver = (max_ver or 0) + 1
        new_entry = DesignHistory(
            room_id=room_id,
            version_number=next_ver,
            snapshot_json=history_entry.snapshot_json,
            summary=f"Restored Version {version_number}"
        )
        db.add(new_entry)
        db.commit()
        db.refresh(new_entry)
        
        # Recompute and update stored analytics to match this restored version
        cls.ensure_room_scores(db, room)
        
        return {
            "success": True,
            "message": f"Successfully restored layout to Version {version_number}.",
            "data": {
                "room_id": room_id,
                "current_version": next_ver
            }
        }

    @classmethod
    def get_system_telemetry(cls, db: Session, period: str) -> Dict[str, Any]:
        import os
        from datetime import datetime, timedelta, timezone
        from sqlalchemy import func
        
        from features.auth.models import User, UserSession
        from features.project.models import Project
        from features.room.models import Room
        from features.furniture.models import FurnitureAsset
        from features.export.models import Report
        from features.ai.models import AIJob, Analytics

        now = datetime.now(timezone.utc)
        
        # Calculate time range
        if period == "7d":
            start_date = now - timedelta(days=7)
            days_count = 7
        elif period == "30d":
            start_date = now - timedelta(days=30)
            days_count = 30
        elif period == "90d":
            start_date = now - timedelta(days=90)
            days_count = 90
        else: # "all"
            start_date = datetime(2020, 1, 1, tzinfo=timezone.utc)
            days_count = 30 # For charts in "all time", limit to last 30 days of data

        if period == "all":
            preceding_start_date = datetime(2020, 1, 1, tzinfo=timezone.utc)
        else:
            delta = now - start_date
            preceding_start_date = start_date - delta

        # 1. Active Users
        total_users = db.query(func.count(User.id)).scalar() or 0
        
        # Active in period: last_login is within range
        active_users_count = db.query(func.count(User.id)).filter(User.last_login >= start_date).scalar() or 0
        
        preceding_active_users = db.query(func.count(User.id)).filter(
            User.last_login >= preceding_start_date,
            User.last_login < start_date
        ).scalar() or 0
        
        if preceding_active_users > 0:
            trend_percentage = round(((active_users_count - preceding_active_users) / preceding_active_users) * 100.0, 2)
        else:
            trend_percentage = 100.0 if active_users_count > 0 else 0.0

        # 2. Furniture Usage
        total_assets = db.query(func.count(FurnitureAsset.id)).scalar() or 0
        
        rooms = db.query(Room).all()
        usage_counts = {}
        categories_breakdown = {}
        
        for r in rooms:
            if r.properties:
                try:
                    props = json.loads(r.properties)
                    furniture_list = props.get("furniture", [])
                    for f in furniture_list:
                        name = f.get("name", "Unknown Item")
                        category = f.get("category", "Uncategorized")
                        
                        usage_counts[name] = usage_counts.get(name, 0) + 1
                        categories_breakdown[category] = categories_breakdown.get(category, 0) + 1
                except Exception:
                    continue

        sorted_usage = sorted(usage_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        most_used = []
        for name, count in sorted_usage:
            asset = db.query(FurnitureAsset).filter(FurnitureAsset.name == name).first()
            cat = asset.category if asset else "Furniture"
            most_used.append({
                "name": name,
                "category": cat,
                "count": count
            })

        # Ensure categories breakdown has at least some catalog entries if empty
        if not categories_breakdown:
            assets = db.query(FurnitureAsset).all()
            for asset in assets:
                categories_breakdown[asset.category] = categories_breakdown.get(asset.category, 0) + 1

        # 3. Project Statistics
        total_projects = db.query(func.count(Project.id)).scalar() or 0
        total_rooms = db.query(func.count(Room.id)).scalar() or 0
        avg_rooms = round(total_rooms / total_projects, 2) if total_projects > 0 else 0.0
        avg_design_score = round(db.query(func.avg(Analytics.overall_score)).scalar() or 0.0, 2)
        # Fallback to realistic avg design score if no analytics exist yet
        if avg_design_score == 0.0 and total_rooms > 0:
            avg_design_score = 75.0

        # 4. AI Usage
        jobs_query = db.query(AIJob)
        if period != "all":
            jobs_query = jobs_query.filter(AIJob.created_at >= start_date)
        jobs = jobs_query.all()
        
        total_jobs = len(jobs)
        completed_jobs = sum(1 for j in jobs if j.status == "Completed")
        failed_jobs = sum(1 for j in jobs if j.status == "Failed")
        pending_jobs = sum(1 for j in jobs if j.status == "Pending")
        
        success_rate = round((completed_jobs / (completed_jobs + failed_jobs) * 100.0), 2) if (completed_jobs + failed_jobs) > 0 else 100.0
        
        latencies = []
        for j in jobs:
            if j.completed_at and j.started_at:
                latencies.append((j.completed_at - j.started_at).total_seconds())
            else:
                results = j.results
                if results:
                    latencies.append(results[0].processing_time_ms / 1000.0)
                    
        avg_latency = round((sum(latencies) / len(latencies)), 2) if latencies else 0.0
        
        jobs_by_status = {
            "Completed": completed_jobs,
            "Failed": failed_jobs,
            "Pending": pending_jobs
        }
        
        jobs_by_type = {}
        for j in jobs:
            t = j.job_type or "AI Layout"
            jobs_by_type[t] = jobs_by_type.get(t, 0) + 1

        # 5. Storage Usage
        reports_used_bytes = float(db.query(func.sum(Report.file_size)).filter(Report.status == "Completed").scalar() or 0.0)
        
        def get_dir_size(path):
            total = 0
            if os.path.exists(path):
                for entry in os.scandir(path):
                    if entry.is_file():
                        total += entry.stat().st_size
                    elif entry.is_dir():
                        total += get_dir_size(entry.path)
            return total
            
        uploads_used_bytes = float(get_dir_size("uploads"))
        total_used_bytes = uploads_used_bytes + reports_used_bytes
        limit_bytes = 5.0 * 1024 * 1024 * 1024 # 5 GB Limit

        # 6. Export Statistics
        reports_query = db.query(Report)
        if period != "all":
            reports_query = reports_query.filter(Report.created_at >= start_date)
        reports = reports_query.all()
        
        total_exports = len(reports)
        exports_by_format = {}
        exports_by_type = {}
        for r in reports:
            fmt = r.format or "PDF"
            exports_by_format[fmt] = exports_by_format.get(fmt, 0) + 1
            
            rtype = r.report_type or "Design Report"
            exports_by_type[rtype] = exports_by_type.get(rtype, 0) + 1

        # 7. Charts Trend Data
        chart_days = 7 if period == "7d" else (30 if period == "30d" else (90 if period == "90d" else 30))
        dau_trend = []
        projects_trend = []
        ai_jobs_trend = []
        
        chart_start = now - timedelta(days=chart_days - 1)
        for i in range(chart_days):
            day_date = (chart_start + timedelta(days=i)).date()
            day_str = day_date.strftime("%Y-%m-%d")
            
            dau_count = db.query(func.count(func.distinct(UserSession.user_id))).filter(
                func.date(UserSession.created_at) == day_date
            ).scalar() or 0
            
            # If database has no sessions, default to counting active logins on this day
            if dau_count == 0:
                dau_count = db.query(func.count(User.id)).filter(
                    func.date(User.last_login) == day_date
                ).scalar() or 0
            
            proj_count = db.query(func.count(Project.id)).filter(
                func.date(Project.created_at) == day_date
            ).scalar() or 0
            
            ai_count = db.query(func.count(AIJob.id)).filter(
                func.date(AIJob.created_at) == day_date
            ).scalar() or 0
            
            dau_trend.append({"date": day_str, "count": dau_count})
            projects_trend.append({"date": day_str, "count": proj_count})
            ai_jobs_trend.append({"date": day_str, "count": ai_count})

        return {
            "active_users": {
                "total_users": total_users,
                "active_users_count": active_users_count,
                "trend_percentage": trend_percentage
            },
            "furniture_usage": {
                "total_assets": total_assets,
                "most_used": most_used,
                "categories_breakdown": categories_breakdown
            },
            "project_statistics": {
                "total_projects": total_projects,
                "total_rooms": total_rooms,
                "average_rooms_per_project": avg_rooms,
                "average_design_score": avg_design_score
            },
            "ai_usage": {
                "total_jobs": total_jobs,
                "success_rate": success_rate,
                "avg_latency_seconds": avg_latency,
                "jobs_by_status": jobs_by_status,
                "jobs_by_type": jobs_by_type
            },
            "storage_usage": {
                "total_used_bytes": total_used_bytes,
                "reports_used_bytes": reports_used_bytes,
                "uploads_used_bytes": uploads_used_bytes,
                "limit_bytes": limit_bytes
            },
            "export_statistics": {
                "total_exports": total_exports,
                "exports_by_format": exports_by_format,
                "exports_by_type": exports_by_type
            },
            "charts": {
                "dau_trend": dau_trend,
                "projects_trend": projects_trend,
                "ai_jobs_trend": ai_jobs_trend
            }
        }

