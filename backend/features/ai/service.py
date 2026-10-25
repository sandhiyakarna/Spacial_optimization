import json
import time
import uuid
from sqlalchemy.orm import Session
from typing import Dict, Any, List, Optional
from features.room.models import Room
from features.ai.repository import AIRepository
from features.ai.planner import generate_initial_layout
from features.ai.optimizer import optimize_layout_simulated_annealing
from features.ai.scoring import calculate_design_score
from features.ai.recommender import generate_recommendations
from features.ai.explainable import get_recommendation_explanation
from features.ai.exceptions import AIJobNotFoundException, RecommendationNotFoundException, AIProcessingException
from datetime import datetime, timezone

class AIService:
    @staticmethod
    def start_layout_generation(
        db: Session,
        room_id: str,
        user_id: str,
        style: str = "Modern",
        preferences: Optional[List[str]] = None,
        seed: Optional[int] = None,
        num_starts: Optional[int] = 2,
        command: Optional[str] = None,
        mode: str = "redesign",
        locked_furniture_ids: Optional[List[str]] = None,
        preserve_existing_mode: str = "replace_inappropriate",
        color_palette: Optional[str] = None,
        furniture_requirements: Optional[List[str]] = None,
        revision: Optional[int] = None
    ) -> str:
        # Create AI Job storing parameters in JSON string inside prompt column
        prompt_data = {
            "style": style,
            "preferences": preferences,
            "seed": seed,
            "num_starts": num_starts,
            "command": command,
            "mode": mode,
            "locked_furniture_ids": locked_furniture_ids or [],
            "preserve_existing_mode": preserve_existing_mode,
            "color_palette": color_palette,
            "furniture_requirements": furniture_requirements,
            "revision": revision
        }
        job = AIRepository.create_job(db, room_id, user_id, "AI Layout", json.dumps(prompt_data))
        return job.id

    @staticmethod
    def run_layout_generation_sync(request_db: Optional[Session], job_id: str):
        """
        Main execution pipeline for generating and scoring a room layout.
        Called asynchronously in background by FastAPI.
        """
        import os
        import logging
        from core.database.session import SessionLocal
        logger = logging.getLogger("flowspace")
        
        db = request_db if request_db is not None else SessionLocal()
        should_close_db = (request_db is None)
        start_time = time.time()
        job = None
        try:
            job = AIRepository.get_job(db, job_id)
            if not job:
                logger.error(f"[AI] Job {job_id} not found.")
                return
                
            AIRepository.update_job_status(db, job_id, "Running")

            # 1. Fetch Room measurements
            room = db.query(Room).filter(Room.id == job.room_id).first()
            if not room or not room.measurements:
                raise AIProcessingException("Room measurements are required.")
                
            # Auto-correct room type from name keyword mismatches if type is generic or mismatching
            room_name_lower = room.room_name.lower() if room.room_name else ""
            room_type_lower = room.room_type.lower() if room.room_type else ""
            if "kitchen" in room_name_lower and "kitchen" not in room_type_lower and "dining" not in room_type_lower:
                room.room_type = "Kitchen"
                db.commit()
            elif "bedroom" in room_name_lower and "bedroom" not in room_type_lower:
                room.room_type = "Bedroom"
                db.commit()
            elif "dining" in room_name_lower and "dining" not in room_type_lower:
                room.room_type = "Dining Room"
                db.commit()
            elif ("manager" in room_name_lower or "executive" in room_name_lower or "office" in room_name_lower or "study" in room_name_lower or "work" in room_name_lower) or ("manager" in room_type_lower or "executive" in room_type_lower):
                if "manager" in room_name_lower or "manager" in room_type_lower or "executive" in room_name_lower or "executive" in room_type_lower:
                    room.room_type = "Manager's Office"
                else:
                    room.room_type = "Office"
                db.commit()
            elif "bathroom" in room_name_lower and "bathroom" not in room_type_lower:
                room.room_type = "Bathroom"
                db.commit()
                
            room_width = room.measurements.width
            room_length = room.measurements.length
            
            logger.info(f"[AI DEBUG] Room: {room.id}")
            logger.info(f"[AI DEBUG] Dimensions: {room_width}x{room_length}x{room.measurements.height}")
            
            # Parse existing doors/windows from properties JSON if any
            openings = []
            props_dict = {}
            if room.properties:
                try:
                    props_dict = json.loads(room.properties)
                    openings = props_dict.get('openings', [])
                except Exception:
                    pass

            if not openings:
                num_doors = int(props_dict.get('doors', 1) or 1)
                num_windows = int(props_dict.get('windows', 1) or 1)
                from features.ai.geometry import generate_room_geometry
                _, gen_openings = generate_room_geometry(room_width, room_length, num_doors, num_windows)
                openings = gen_openings
                props_dict['openings'] = openings
            
            # Parse parameters from job.prompt if it is a JSON string
            seed = None
            num_starts = 5
            style = "Modern"
            preferences = []
            command = None
            mode = "redesign"
            locked_furniture_ids = []
            preserve_existing_mode = "replace_inappropriate"
            color_palette = None
            furniture_requirements = None
            revision = None
            if job.prompt:
                try:
                    params = json.loads(job.prompt)
                    seed = params.get("seed")
                    num_starts = params.get("num_starts", 5)
                    style = params.get("style", "Modern")
                    preferences = params.get("preferences") or []
                    command = params.get("command")
                    mode = params.get("mode", "redesign")
                    locked_furniture_ids = params.get("locked_furniture_ids") or []
                    preserve_existing_mode = params.get("preserve_existing_mode", "replace_inappropriate")
                    color_palette = params.get("color_palette")
                    furniture_requirements = params.get("furniture_requirements")
                    revision = params.get("revision")
                except Exception:
                    pass

            # Map regeneration modes to functional optimization strategies
            if mode == "optimize_space" and "more_spacious" not in preferences:
                preferences.append("more_spacious")
                preferences.append("better_circulation")
            elif mode == "improve_style" and "style_focused" not in preferences:
                preferences.append("style_focused")
            elif mode == "improve_layout" and "preserve_furniture" not in preferences:
                preferences.append("improve_layout")

            # Extract existing furniture and locked furniture items
            existing_furniture = props_dict.get('furniture', []) if room.properties else []
            locked_items = []
            locked_ids = set(str(lid) for lid in locked_furniture_ids)
            for f in existing_furniture:
                f_id = str(f.get('id', ''))
                if f.get('is_locked') or f.get('isLocked') or f_id in locked_ids:
                    f['is_locked'] = True
                    f['isLocked'] = True
                    locked_ids.add(f_id)
                    locked_items.append(f)

            # Convert optional command to structured preferences
            if command:
                low_cmd = command.lower()
                if "spacious" in low_cmd:
                    preferences.append("more_spacious")
                if "storage" in low_cmd:
                    preferences.append("more_storage")
                if "minimal" in low_cmd or "reduce" in low_cmd:
                    preferences.append("minimal_furniture")
                if "work" in low_cmd or "study" in low_cmd:
                    preferences.append("work_focused")
                if "circulation" in low_cmd or "flow" in low_cmd:
                    preferences.append("better_circulation")
                if "seating" in low_cmd or "seat" in low_cmd:
                    preferences.append("more_seating")

            # 2. Invoke LayoutAIProvider
            from features.furniture.models import FurnitureAsset
            assets = db.query(FurnitureAsset).all()
            if not assets:
                raise AIProcessingException("No furniture assets found in catalog.")
            
            # Filter assets strictly by room compatibility to keep prompt focused and prevent inappropriate substitutions
            from features.ai.planner import is_asset_compatible_with_room
            furniture_catalog = []
            for asset in assets:
                if is_asset_compatible_with_room(asset, room.room_type):
                    furniture_catalog.append({
                        "asset_id": asset.id,
                        "name": asset.name,
                        "category": asset.category,
                        "style": asset.style,
                        "width": asset.width,
                        "depth": asset.depth,
                        "height": asset.height
                    })
                    
            if not furniture_catalog:
                raise AIProcessingException(f"No compatible furniture assets available in catalog for room type '{room.room_type}'.")
                
            room_context = {
                "room_type": room.room_type,
                "width": room_width,
                "length": room_length,
                "height": room.measurements.height,
                "doors": [op for op in openings if op.get("type") == "door"],
                "windows": [op for op in openings if op.get("type") == "window"]
            }
            
            from features.ai.provider import LocalLLMLayoutProvider, GeminiLayoutProvider, HeuristicLayoutProvider
            
            # Determine provider selection
            preferred_provider = None
            if job.prompt:
                try:
                    params = json.loads(job.prompt)
                    preferred_provider = params.get("provider")
                except Exception:
                    pass
            if not preferred_provider:
                from app.config import settings
                preferred_provider = getattr(settings, "AI_PROVIDER", "ollama")
                
            logger.info(f"[AI DEBUG] Command: {command}")
            logger.info(f"[AI DEBUG] Provider: {preferred_provider}")
            logger.info(f"[AI DEBUG] Asset count: {len(assets)}")
                
            ai_plan = None
            ai_provider_status = "FALLBACK"
            ai_provider_name = "FALLBACK"
            
            ai_start = time.time()
            ai_response_time = 0.0
            
            if preferred_provider == "gemini":
                if os.environ.get("GEMINI_API_KEY"):
                    try:
                        logger.info("Invoking Gemini layout provider...")
                        gemini_provider = GeminiLayoutProvider()
                        ai_plan = gemini_provider.generate_layout_plan(
                            room_context,
                            furniture_catalog,
                            {"preferences": preferences, "style": style, "command": command}
                        )
                        ai_response_time = (time.time() - ai_start) * 1000
                        ai_provider_status = "SUCCESS"
                        ai_provider_name = "GEMINI"
                        logger.info("AI provider: GEMINI")
                        logger.info("AI provider status: SUCCESS")
                    except Exception as e:
                        logger.error(f"Gemini layout provider failed: {e}. Falling back to heuristics...")
                        ai_provider_status = "FALLBACK"
                        ai_provider_name = "FALLBACK"
                        logger.info("AI provider: FALLBACK")
                else:
                    logger.info("No Gemini API key found. Using offline heuristic layout provider...")
                    ai_provider_status = "FALLBACK"
                    ai_provider_name = "FALLBACK"
                    logger.info("AI provider: FALLBACK")
            else: # default/ollama
                try:
                    logger.info("Invoking Ollama layout provider...")
                    ollama_provider = LocalLLMLayoutProvider()
                    ai_plan = ollama_provider.generate_layout_plan(
                        room_context,
                        furniture_catalog,
                        {"preferences": preferences, "style": style, "command": command}
                    )
                    ai_response_time = (time.time() - ai_start) * 1000
                    ai_provider_status = "SUCCESS"
                    ai_provider_name = "OLLAMA"
                    logger.info("AI provider: OLLAMA")
                    logger.info("AI provider status: SUCCESS")
                except Exception as e:
                    logger.error(f"Ollama layout provider failed: {e}. Falling back to heuristics...")
                    ai_provider_status = "FALLBACK"
                    ai_provider_name = "FALLBACK"
                    logger.info("AI provider: FALLBACK")
                    
            if ai_plan is None:
                ai_start = time.time()
                heuristic_provider = HeuristicLayoutProvider()
                ai_plan = heuristic_provider.generate_layout_plan(
                    room_context,
                    furniture_catalog,
                    {"preferences": preferences, "style": style, "command": command}
                )
                ai_response_time = (time.time() - ai_start) * 1000
                ai_provider_status = "FALLBACK"
                ai_provider_name = "FALLBACK"
                logger.info("AI provider: FALLBACK")

            # 3. Convert intentions to coordinate candidates and validate
            candidate_gen_start = time.time()
            from features.ai.planner import (
                validate_ai_response_schema,
                validate_assets_exist,
                convert_intent_to_coordinates,
                validate_layout_geometry
            )
            
            try:
                validate_ai_response_schema(ai_plan)
                validate_assets_exist(db, ai_plan)
                
                initial_furniture = convert_intent_to_coordinates(
                    db, room_width, room_length, room.room_type, ai_plan, openings
                )
                candidate_gen_time = (time.time() - candidate_gen_start) * 1000
                
                # Retrieve alternative heuristic templates as candidate starts
                from features.ai.planner import generate_layout_candidates
                heuristic_candidates = generate_layout_candidates(
                    db, room_width, room_length, room.room_type, style, openings, preferences, seed,
                    locked_furniture=locked_items, mode=mode
                )
                
                # Merge locked items into AI initial furniture if present
                if locked_items:
                    from features.ai.geometry import get_furniture_obb, obb_overlap_sat
                    merged_ai = [dict(lf) for lf in locked_items]
                    lobbs = [get_furniture_obb(lf) for lf in locked_items]
                    for item in initial_furniture:
                        iobb = get_furniture_obb(item)
                        coll = any(obb_overlap_sat(iobb, lobb)[0] and obb_overlap_sat(iobb, lobb)[1] > 10.0 for lobb in lobbs)
                        if not coll:
                            merged_ai.append(item)
                    initial_furniture = merged_ai

                ai_strat = "wall_aligned"
                if isinstance(ai_plan, dict):
                    raw_strat = ai_plan.get("layout_strategy") or ai_plan.get("strategy")
                    if raw_strat in ["wall_aligned", "center_oriented", "window_oriented", "functional_zoned", "space_efficient"]:
                        ai_strat = raw_strat
                    elif room.room_type and "living" in room.room_type.lower():
                        ai_strat = "center_oriented"
                    elif room.room_type and "dining" in room.room_type.lower():
                        ai_strat = "center_oriented"
                    elif room.room_type and any(k in room.room_type.lower() for k in ["office", "manager", "executive"]):
                        ai_strat = "center_oriented"
                    else:
                        ai_strat = "wall_aligned"
                        
                candidates = [(ai_strat, initial_furniture, "AI proposed layout plan based on user preferences.")]
                for strat, placements, expl in heuristic_candidates:
                    candidates.append((strat, placements, expl))
            except Exception as ex:
                logger.error(f"AI proposed plan validation/conversion failed: {ex}. Falling back to default heuristics...")
                ai_provider_status = "FALLBACK"
                logger.info("AI provider: FALLBACK")
                
                candidate_gen_start = time.time()
                from features.ai.planner import generate_layout_candidates
                candidates = generate_layout_candidates(
                    db, room_width, room_length, room.room_type, style, openings, preferences, seed,
                    locked_furniture=locked_items, mode=mode
                )
                candidate_gen_time = (time.time() - candidate_gen_start) * 1000
                
                if not candidates:
                    from features.ai.planner import generate_initial_layout
                    fallback_furniture = generate_initial_layout(db, room_width, room_length, room.room_type, style)
                    candidates = [("default", fallback_furniture, "Default layout generated.")]

                # Only include existing furniture as a candidate if ALL items are room-compatible
                from features.ai.room_rules import is_asset_compatible_with_room
                if existing_furniture and mode in ["improve_layout", "preserve"]:
                    compatible_existing = [
                        f for f in existing_furniture if is_asset_compatible_with_room(f, room.room_type)
                    ]
                    if len(compatible_existing) == len(existing_furniture):
                        candidates.append(("improve_existing", existing_furniture, "Refined existing layout positions."))

            # 4. Optimize each candidate layout and select the best one
            from features.ai.optimizer import is_better_layout
            
            best_furniture = None
            best_scores = None
            best_strategy = None
            best_explanation = None
            best_opt_report = None
            
            optimization_time = 0.0
            validation_time = 0.0
            
            evaluated_candidates = []
            for strategy, initial_furniture, explanation in candidates:
                opt_start = time.time()
                opt_furniture, opt_report = optimize_layout_simulated_annealing(
                    room_width, room_length, room.room_type, initial_furniture, openings,
                    seed=seed, num_starts=num_starts, locked_ids=list(locked_ids)
                )
                optimization_time += (time.time() - opt_start) * 1000
                
                val_start = time.time()
                scores = calculate_design_score(room_width, room_length, room.room_type, opt_furniture, openings)
                validation_time += (time.time() - val_start) * 1000
                
                evaluated_candidates.append({
                    "strategy": strategy,
                    "furniture": opt_furniture,
                    "scores": scores,
                    "explanation": explanation,
                    "opt_report": opt_report
                })
                
                if best_scores is None or is_better_layout(scores, best_scores):
                    best_furniture = opt_furniture
                    best_scores = scores
                    if strategy == "ai_proposed":
                        if ai_provider_status == "FALLBACK":
                            if "spacious" in preferences or "minimal" in preferences or "more_spacious" in preferences or "minimal_furniture" in preferences:
                                best_strategy = "space_efficient"
                            else:
                                best_strategy = "center_oriented" if ("office" in room.room_type.lower() or "manager" in room.room_type.lower()) else "wall_aligned"
                        else:
                            best_strategy = strategy
                    else:
                        best_strategy = strategy
                        
                    if strategy == "ai_proposed" and ai_plan and ai_plan.get("reasoning"):
                        best_explanation = " | ".join(ai_plan.get("reasoning"))
                    else:
                        best_explanation = explanation
                    best_opt_report = opt_report

            # Build 3 distinct layout options: Balanced, Space-Efficient, and Style-Focused
            balanced_cand = next((c for c in evaluated_candidates if c["furniture"] == best_furniture), evaluated_candidates[0])
            
            space_cands = sorted(
                evaluated_candidates,
                key=lambda c: (
                    c["scores"]["subscores"].get("space_utilization", 0) +
                    c["scores"]["subscores"].get("accessibility", 0) +
                    (15 if c["strategy"] == "space_efficient" else 0)
                ),
                reverse=True
            )
            space_cand = next((c for c in space_cands if c != balanced_cand), space_cands[0])

            style_cands = sorted(
                evaluated_candidates,
                key=lambda c: (
                    c["scores"]["subscores"].get("aesthetics", 0) +
                    c["scores"]["subscores"].get("balance", 0) +
                    c["scores"]["subscores"].get("lighting", 0)
                ),
                reverse=True
            )
            style_cand = next((c for c in style_cands if c != balanced_cand and c != space_cand), style_cands[0])

            def _build_option(opt_id: str, title: str, cand: dict, default_expl: str):
                s = cand["scores"]
                sub = s.get("subscores", {})
                return {
                    "id": opt_id,
                    "title": title,
                    "strategy": cand["strategy"],
                    "furniture": cand["furniture"],
                    "design_scores": s,
                    "overall_score": int(s.get("overall_score", 70)),
                    "explanation": cand.get("explanation") or default_expl,
                    "highlights": [
                        f"Space Utilization: {int(sub.get('space_utilization', 75))}/100",
                        f"Ergonomics & Clearance: {int(sub.get('ergonomics', 75))}/100",
                        f"Aesthetics & Balance: {int(sub.get('aesthetics', 75))}/100",
                    ]
                }

            layout_options = [
                _build_option(
                    "balanced",
                    "Balanced Layout",
                    balanced_cand,
                    "Optimal balance between functional living zones, ergonomics, and aesthetic circulation."
                ),
                _build_option(
                    "space_efficient",
                    "Space-Efficient Layout",
                    space_cand,
                    "Maximizes usable open floor area and prioritizes unobstructed primary walkways."
                ),
                _build_option(
                    "style_focused",
                    "Style-Focused Layout",
                    style_cand,
                    f"Curated interior style emphasis ({style}) highlighting room focal points and balanced groupings."
                ),
            ]
            
            # Check for severe physical impossibility (e.g. furniture item is larger than the room itself)
            for item in best_furniture:
                item_w = item.get('width', 0)
                item_d = item.get('depth', 0)
                if (item_w > room_width and item_w > room_length) or (item_d > room_width and item_d > room_length):
                    raise AIProcessingException(f"Unable to generate a valid layout: item {item.get('name')} ({item_w}x{item_d}cm) exceeds room dimensions ({room_width}x{room_length}cm).")

            # Validate collisions/bounds safety - record warnings without discarding usable layout
            remaining_collisions = best_scores['details'].get('collisions', 0)
            remaining_oob = best_scores['details'].get('out_of_bounds', 0)
            remaining_blocked_doors = best_scores['details'].get('blocked_doors', 0)
            remaining_blocked_windows = best_scores['details'].get('blocked_windows', 0)
            
            validation_warnings = []
            if remaining_collisions > 0:
                validation_warnings.append(f"{remaining_collisions} furniture collision(s) detected.")
            if remaining_oob > 0:
                validation_warnings.append(f"{remaining_oob} furniture item(s) slightly outside room boundaries.")
            if remaining_blocked_doors > 0:
                validation_warnings.append(f"{remaining_blocked_doors} door clearance zone(s) obstructed.")
            if remaining_blocked_windows > 0:
                validation_warnings.append(f"{remaining_blocked_windows} window clearance zone(s) obstructed.")
                
            if validation_warnings:
                logger.warning(f"[AI WARNINGS] {'; '.join(validation_warnings)}")
            
            # Ensure walls match room dimensions (0, 0) to (room_width, room_length)
            from features.ai.geometry import generate_room_geometry
            generated_walls, _ = generate_room_geometry(room_width, room_length, 0, 0)
            walls = props_dict.get('walls', []) if room.properties else []
            # If walls are empty or outside [0, room_width] x [0, room_length], regenerate correct walls
            if not walls or any(w.get('x1', 0) > room_width + 10 or w.get('y1', 0) > room_length + 10 for w in walls):
                walls = generated_walls
                
            final_layout_id = str(uuid.uuid4())

            # Trace final layout
            logger.info("==================================================")
            logger.info("FINAL OPTIMIZED SPATIAL LAYOUT TRACE")
            logger.info("==================================================")
            logger.info(f"FINAL_LAYOUT_ID: {final_layout_id}")
            logger.info("ROOM:")
            logger.info(f"  width: {room_width} cm")
            logger.info(f"  length: {room_length} cm")
            logger.info(f"  height: {room.measurements.height} cm")
            logger.info("FURNITURE:")
            for item in best_furniture:
                logger.info(f"  Item: {item.get('name')}")
                logger.info(f"    id: {item.get('id')}")
                logger.info(f"    asset_id: {item.get('asset_id') or item.get('assetId')}")
                logger.info(f"    category: {item.get('category')}")
                logger.info(f"    x: {item.get('x')}")
                logger.info(f"    y: {item.get('y', 0.0)}")
                logger.info(f"    z: {item.get('z')}")
                logger.info(f"    width: {item.get('width')}")
                logger.info(f"    depth: {item.get('depth')}")
                logger.info(f"    height: {item.get('height')}")
                logger.info(f"    rotation: {item.get('rotationY', item.get('rotation', 0.0))}")
            logger.info("==================================================")
                
            from features.ai.planner import evaluate_design_quality
            design_eval = evaluate_design_quality(room_width, room_length, room.room_type, best_furniture, openings)
            
            layout_data = {
                **props_dict,
                "final_layout_id": final_layout_id,
                "walls": walls,
                "openings": openings,
                "furniture": best_furniture,
                "design_scores": best_scores,
                "design_evaluation": design_eval,
                "options": layout_options,
                "floorMaterialColor": props_dict.get('floorMaterialColor') if room.properties else None,
                "floorMaterialType": props_dict.get('floorMaterialType') if room.properties else None,
                "wallMaterialColor": props_dict.get('wallMaterialColor') if room.properties else None,
                "wallMaterialType": props_dict.get('wallMaterialType') if room.properties else None,
                "ai_layout_metadata": {
                    "final_layout_id": final_layout_id,
                    "strategy": best_strategy,
                    "preferences": preferences,
                    "command": command,
                    "explanation": best_explanation,
                    "optimization_report": best_opt_report,
                    "design_quality": design_eval,
                    "validation_warnings": validation_warnings,
                    "validation_details": {
                        "collision_count": remaining_collisions,
                        "out_of_bounds_count": remaining_oob,
                        "blocked_doors": remaining_blocked_doors,
                        "blocked_windows": remaining_blocked_windows,
                        "is_valid": len(validation_warnings) == 0,
                    },
                    "room_context": {
                        "room_type": room.room_type,
                        "width": room_width,
                        "length": room_length,
                        "openings": openings
                    },
                    "performance": {
                        "ai_provider": ai_provider_name,
                        "ai_provider_status": ai_provider_status,
                        "ai_response_time_ms": int(ai_response_time),
                        "candidate_generation_time_ms": int(candidate_gen_time),
                        "validation_time_ms": int(validation_time),
                        "optimization_time_ms": int(optimization_time),
                        "total_layout_generation_time_ms": int((time.time() - start_time) * 1000)
                    },
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }
            }
            # Preserve existing layout state for undo and version recovery
            if existing_furniture:
                try:
                    from features.ai.models import DesignHistory
                    last_hist = db.query(DesignHistory).filter(DesignHistory.room_id == room.id).order_by(DesignHistory.version_number.desc()).first()
                    next_ver = (last_hist.version_number + 1) if last_hist else 1
                    history_entry = DesignHistory(
                        room_id=room.id,
                        version_number=next_ver,
                        snapshot_json=json.dumps(props_dict),
                        summary=f"Automated snapshot before AI generation ({mode}) on {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')}"
                    )
                    db.add(history_entry)
                    db.commit()
                except Exception as hist_err:
                    logger.warning(f"Could not record design history snapshot: {hist_err}")

            layout_data["previous_furniture"] = existing_furniture
            room.properties = json.dumps(layout_data)
            
            # Save scores in database
            AIRepository.save_analytics(
                db, room.id,
                best_scores['subscores']['accessibility'],
                best_scores['subscores']['lighting'],
                best_scores['subscores']['ergonomics'],
                best_scores['subscores']['space_utilization'],
                best_scores['subscores']['balance'],
                best_scores['overall_score']
            )
            
            processing_time_ms = int((time.time() - start_time) * 1000)
            
            # Save AI Result
            res = AIRepository.save_result(
                db, job_id, room.id,
                json.dumps(layout_data),
                best_scores['overall_score'],
                explanation=best_explanation,
                processing_time_ms=processing_time_ms
            )
            
            # Add to AI History
            AIRepository.add_history(db, room.id, res.id)
            AIRepository.update_job_status(db, job_id, "Completed")
            db.commit()
            
        except Exception as e:
            logger.error(f"AI Layout generation job {job_id} failed: {e}", exc_info=True)
            db.rollback()
            AIRepository.update_job_status(db, job_id, "Failed")
            # Save result with error explanation
            try:
                if job:
                    room = db.query(Room).filter(Room.id == job.room_id).first()
                    if room:
                        AIRepository.save_result(
                            db, job_id, room.id,
                            layout_json="{}",
                            confidence_score=0.0,
                            explanation=str(e),
                            processing_time_ms=int((time.time() - start_time) * 1000)
                        )
                        db.commit()
            except Exception:
                pass
        finally:
            if should_close_db and db:
                db.close()

    @staticmethod
    def optimize_existing_layout(db: Session, room_id: str, seed: Optional[int] = None, num_starts: int = 5) -> Dict[str, Any]:
        """
        Directly optimizes the existing room layout and saves it.
        """
        start_time = time.time()
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room or not room.measurements:
            raise AIProcessingException("Room measurements are required.")
            
        room_width = room.measurements.width
        room_length = room.measurements.length
        
        # Parse current furniture & openings
        furniture = []
        openings = []
        walls = []
        floor_color = None
        floor_type = None
        wall_color = None
        wall_type = None
        
        if room.properties:
            try:
                props = json.loads(room.properties)
                furniture = props.get('furniture', [])
                openings = props.get('openings', [])
                walls = props.get('walls', [])
                floor_color = props.get('floorMaterialColor')
                floor_type = props.get('floorMaterialType')
                wall_color = props.get('wallMaterialColor')
                wall_type = props.get('wallMaterialType')
            except Exception:
                pass
                
        if not furniture:
            raise AIProcessingException("No furniture in room to optimize. Please add furniture or run initial planning.")
            
        # Run Simulated Annealing Layout Optimizer
        optimized_furniture, opt_report = optimize_layout_simulated_annealing(
            room_width, room_length, room.room_type, furniture, openings, seed=seed, num_starts=num_starts
        )
        
        # Recalculate design scores
        scores = calculate_design_score(room_width, room_length, room.room_type, optimized_furniture, openings)
        
        layout_data = {
            "walls": walls,
            "openings": openings,
            "furniture": optimized_furniture,
            "floorMaterialColor": floor_color, "floorMaterialType": floor_type,
            "wallMaterialColor": wall_color, "wallMaterialType": wall_type
        }
        room.properties = json.dumps(layout_data)
        
        AIRepository.save_analytics(
            db, room.id,
            scores['subscores']['accessibility'],
            scores['subscores']['lighting'],
            scores['subscores']['ergonomics'],
            scores['subscores']['space_utilization'],
            scores['subscores']['balance'],
            scores['overall_score']
        )
        
        processing_time_ms = int((time.time() - start_time) * 1000)
        
        db.commit()
        return {
            "success": True,
            "data": {
                "layout_data": json.dumps(layout_data),
                "overall_score": scores['overall_score'],
                "subscores": scores['subscores'],
                "processing_time_ms": processing_time_ms,
                "optimization_report": opt_report
            }
        }

    @staticmethod
    def get_room_recommendations(db: Session, room_id: str) -> List[Dict[str, Any]]:
        """
        Runs design analysis rules to identify issues and returns recommendation cards.
        Also logs generated cards in RecommendationHistory.
        """
        room = db.query(Room).filter(Room.id == room_id).first()
        if not room or not room.measurements:
            raise AIProcessingException("Room measurements are required.")
            
        room_width = room.measurements.width
        room_length = room.measurements.length
        
        furniture = []
        openings = []
        if room.properties:
            try:
                props = json.loads(room.properties)
                furniture = props.get('furniture', [])
                openings = props.get('openings', [])
            except Exception:
                pass
                
        # Generate fresh recommendations
        cards = generate_recommendations(room_width, room_length, room.room_type, furniture, openings)
        
        # Log to DB history (using description as JSON representation of card)
        for card in cards:
            AIRepository.log_recommendation(
                db, card["id"], room_id,
                card["recommendation_type"],
                card["title"],
                json.dumps(card)
            )
            
        return cards

    @staticmethod
    def explain_recommendation(db: Session, rec_id: str) -> Dict[str, Any]:
        """
        Returns explanations, expected benefits, and interior design principles.
        """
        rec = AIRepository.get_recommendation(db, rec_id)
        if not rec:
            raise RecommendationNotFoundException(rec_id)
            
        try:
            card = json.loads(rec.description)
            explanation = get_recommendation_explanation(card)
            return explanation
        except Exception:
            # Fallback
            return {
                "why_suggested": rec.description,
                "rule_triggered": "General Spacing Rule",
                "design_principle": "Ensure proper room circulation and balance.",
                "expected_improvement": "Improves overall room aesthetics.",
                "score_impact": "Overall Score +5%"
            }

    @staticmethod
    def apply_recommendation(db: Session, rec_id: str) -> Dict[str, Any]:
        """
        Applies recommendation actions directly to the room's layout properties.
        """
        rec = AIRepository.get_recommendation(db, rec_id)
        if not rec:
            raise RecommendationNotFoundException(rec_id)
            
        room = db.query(Room).filter(Room.id == rec.room_id).first()
        if not room:
            raise AIProcessingException("Room not found.")
            
        try:
            card = json.loads(rec.description)
            action = card.get("action", {})
            action_type = action.get("action_type")
            
            if not room.properties:
                layout = {"walls": [], "openings": [], "furniture": []}
            else:
                layout = json.loads(room.properties)
                
            applied = False
            
            if action_type == "move":
                f_id = action.get("furniture_id")
                dx = action.get("dx", 0.0)
                dz = action.get("dz", 0.0)
                for f in layout.get("furniture", []):
                    if f["id"] == f_id:
                        f["x"] += dx
                        f["z"] += dz
                        applied = True
                        break
                        
            elif action_type == "material":
                f_id = action.get("furniture_id")
                color = action.get("materialColor")
                m_type = action.get("materialType")
                for f in layout.get("furniture", []):
                    if f["id"] == f_id:
                        f["materialColor"] = color
                        f["materialType"] = m_type
                        applied = True
                        break
                        
            elif action_type == "add":
                # Find compatible asset from DB
                from features.furniture.models import FurnitureAsset
                asset = db.query(FurnitureAsset).filter(
                    FurnitureAsset.name.ilike(f"%{action.get('name')}%")
                ).first()
                if not asset:
                    asset = db.query(FurnitureAsset).first()
                    
                if asset:
                    layout.setdefault("furniture", []).append({
                        "id": str(uuid.uuid4()),
                        "assetId": asset.id,
                        "name": asset.name,
                        "width": asset.width,
                        "depth": asset.depth,
                        "height": asset.height,
                        "x": room.measurements.length / 2.0,
                        "y": 0.0,
                        "z": room.measurements.width / 2.0,
                        "rotationY": 0.0,
                        "scaleX": 1.0, "scaleY": 1.0, "scaleZ": 1.0
                    })
                    applied = True
            
            if applied:
                room.properties = json.dumps(layout)
                rec.accepted = True
                
                # Recalculate and update scores
                scores = calculate_design_score(
                    room.measurements.width, room.measurements.length,
                    room.room_type, layout.get("furniture", []), layout.get("openings", [])
                )
                AIRepository.save_analytics(
                    db, room.id,
                    scores['subscores']['accessibility'],
                    scores['subscores']['lighting'],
                    scores['subscores']['ergonomics'],
                    scores['subscores']['space_utilization'],
                    scores['subscores']['balance'],
                    scores['overall_score']
                )
                db.commit()
                
                return {
                    "success": True,
                    "message": "Recommendation applied successfully.",
                    "data": {"layout_data": room.properties}
                }
            else:
                raise AIProcessingException("Could not apply action elements of recommendation.")
                
        except Exception as e:
            db.rollback()
            raise AIProcessingException(f"Failed to apply recommendation: {str(e)}")
