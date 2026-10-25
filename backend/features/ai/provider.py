from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional, Type
import os
import json
import httpx
import logging

logger = logging.getLogger("flowspace")

class LayoutAIProvider(ABC):
    @abstractmethod
    def generate_layout_plan(
        self,
        room_context: Dict[str, Any],
        furniture_catalog: List[Dict[str, Any]],
        preferences: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generates a semantic layout plan containing furniture recommendations, 
        roles, preferred walls, and reasoning.
        """
        pass


class HeuristicLayoutProvider(LayoutAIProvider):
    def generate_layout_plan(
        self,
        room_context: Dict[str, Any],
        furniture_catalog: List[Dict[str, Any]],
        preferences: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Offline fallback generating structured layout intents based on interior-design rules.
        """
        room_type = room_context.get("room_type", "bedroom").lower()
        pref_list = preferences.get("preferences", [])
        is_minimal = "minimal" in [p.lower() for p in pref_list] or "minimal furniture" in [p.lower() for p in pref_list] or "minimal_furniture" in [p.lower() for p in pref_list]
        more_spacious = "spacious" in [p.lower() for p in pref_list] or "more spacious" in [p.lower() for p in pref_list] or "more_spacious" in [p.lower() for p in pref_list]
        
        furniture = []
        reasoning = []
        
        # Scored asset lookup with exclusion support
        def find_asset(keywords: List[str], exclude: Optional[List[str]] = None) -> Optional[str]:
            exclude = [x.lower() for x in (exclude or [])]
            best_match = None
            best_score = -100
            for asset in furniture_catalog:
                name = asset.get("name", "").lower()
                cat = asset.get("category", "").lower()
                if any(ex in name for ex in exclude):
                    continue
                score = 0
                for kw in keywords:
                    kw_low = kw.lower()
                    if kw_low in name:
                        score += 10
                    elif kw_low in cat:
                        score += 2
                if score > best_score and score > 0:
                    best_score = score
                    best_match = asset.get("asset_id") or asset.get("id")
            if best_match:
                return best_match
            return None

        room_w = room_context.get("width", 400.0)
        room_l = room_context.get("length", 500.0)
        room_area_m2 = (room_w * room_l) / 10000.0

        # 1. KITCHEN
        if "kitchen" in room_type:
            counter_id = find_asset(["counter", "island"], exclude=["office", "desk", "chair"])
            sink_id = find_asset(["sink", "basin"], exclude=["bathroom", "desk", "chair"])
            stove_id = find_asset(["stove", "cooktop", "range", "oven"], exclude=["desk", "chair"])
            fridge_id = find_asset(["fridge", "refrigerator"], exclude=["desk", "chair"])
            cabinet_id = find_asset(["kitchen cabinet", "cabinet", "pantry"], exclude=["desk", "chair"])

            if counter_id:
                furniture.append({
                    "asset_id": counter_id,
                    "role": "kitchen_counter",
                    "preferred_wall": "west",
                    "preferred_zone": "preparation"
                })
                reasoning.append("Modular kitchen prep counter positioned along perimeter wall.")
            if sink_id:
                furniture.append({
                    "asset_id": sink_id,
                    "role": "sink",
                    "preferred_wall": "west",
                    "preferred_zone": "cleaning"
                })
                reasoning.append("Kitchen sink station placed adjacent to food preparation counters.")
            if stove_id:
                furniture.append({
                    "asset_id": stove_id,
                    "role": "stove",
                    "preferred_wall": "north",
                    "preferred_zone": "cooking"
                })
                reasoning.append("Cooking stove arranged along cooking wall with adequate clearance.")
            if fridge_id:
                furniture.append({
                    "asset_id": fridge_id,
                    "role": "refrigerator",
                    "preferred_wall": "north",
                    "preferred_zone": "food_storage"
                })
                reasoning.append("Refrigerator positioned to complete ergonomic kitchen work triangle.")
            if cabinet_id and not is_minimal:
                furniture.append({
                    "asset_id": cabinet_id,
                    "role": "kitchen_cabinet",
                    "preferred_wall": "east",
                    "preferred_zone": "storage"
                })
                reasoning.append("Pantry storage cabinet placed along side wall.")

        # 2. DINING ROOM
        elif "dining" in room_type:
            table_id = find_asset(["dining table", "table"], exclude=["coffee", "desk"])
            chair_id = find_asset(["dining chair", "chair"], exclude=["office", "desk", "sofa"])
            sideboard_id = find_asset(["cabinet", "credenza", "sideboard"], exclude=["desk", "chair"])

            if table_id:
                furniture.append({
                    "asset_id": table_id,
                    "role": "dining_table",
                    "preferred_wall": "none",
                    "preferred_zone": "dining"
                })
                reasoning.append("Scandinavian dining table centered with wide surrounding circulation.")
            if chair_id:
                for idx in range(1, 3):
                    furniture.append({
                        "asset_id": chair_id,
                        "role": f"dining_chair_{idx}",
                        "preferred_wall": "none",
                        "preferred_zone": "dining"
                    })
                reasoning.append("Matching dining chairs arranged with proper pull-out clearance.")
            if sideboard_id and not is_minimal:
                furniture.append({
                    "asset_id": sideboard_id,
                    "role": "sideboard",
                    "preferred_wall": "east",
                    "preferred_zone": "storage"
                })
                reasoning.append("Sideboard buffet unit placed along perimeter wall.")

        # 3. BATHROOM
        elif "bathroom" in room_type or "restroom" in room_type:
            vanity_id = find_asset(["vanity", "basin"], exclude=["desk", "chair", "bed"])
            if vanity_id:
                furniture.append({
                    "asset_id": vanity_id,
                    "role": "vanity",
                    "preferred_wall": "north",
                    "preferred_zone": "washing"
                })
                reasoning.append("Bathroom vanity unit aligned along solid wall with clear grooming space.")

        # 4. BEDROOM
        elif "bedroom" in room_type:
            bed_id = find_asset(["bed"], exclude=["night", "stand"])
            wardrobe_id = find_asset(["wardrobe", "closet", "dresser", "cabinet"], exclude=["desk", "chair"])
            stand_id = find_asset(["nightstand", "stand", "night", "bedside"], exclude=["tv"])
            desk_id = find_asset(["study", "desk"], exclude=["chair"])
            chair_id = find_asset(["chair"], exclude=["desk", "table"])
            
            if bed_id:
                furniture.append({
                    "asset_id": bed_id,
                    "role": "primary_sleep",
                    "preferred_wall": "north",
                    "preferred_zone": "sleep"
                })
                reasoning.append("Primary bed positioned against the solid north wall to preserve circulation and side access.")
                
            if stand_id:
                furniture.append({
                    "asset_id": stand_id,
                    "role": "bedside",
                    "preferred_wall": "north",
                    "preferred_zone": "sleep"
                })
                reasoning.append("Bedside nightstand placed adjacent to the bed headboard for convenience.")
                if room_w >= 320.0 and not is_minimal:
                    furniture.append({
                        "asset_id": stand_id,
                        "role": "bedside",
                        "preferred_wall": "north",
                        "preferred_zone": "sleep"
                    })
                    reasoning.append("Secondary bedside nightstand added for symmetrical bed access.")
                
            if wardrobe_id:
                furniture.append({
                    "asset_id": wardrobe_id,
                    "role": "wardrobe",
                    "preferred_wall": "east",
                    "preferred_zone": "storage"
                })
                reasoning.append("Wardrobe placed flush along the perimeter wall with ample clearance for doors.")
                
            if desk_id and chair_id and room_area_m2 >= 14.0 and not is_minimal and not more_spacious:
                furniture.append({
                    "asset_id": desk_id,
                    "role": "desk",
                    "preferred_wall": "west",
                    "preferred_zone": "study"
                })
                furniture.append({
                    "asset_id": chair_id,
                    "role": "chair",
                    "preferred_wall": "west",
                    "preferred_zone": "study"
                })
                reasoning.append("Study desk and ergonomic chair positioned along the west wall with natural light access.")
                
        # 5. LIVING ROOM
        elif "living" in room_type:
            sofa_id = find_asset(["sofa", "couch"], exclude=["table", "tv"])
            coffee_id = find_asset(["coffee", "table"], exclude=["dining", "desk", "sofa"])
            tv_id = find_asset(["tv", "media", "console"], exclude=["sofa", "table"])
            bookshelf_id = find_asset(["bookshelf", "shelf"], exclude=["desk", "chair"])
            
            if sofa_id:
                furniture.append({
                    "asset_id": sofa_id,
                    "role": "sofa",
                    "preferred_wall": "south",
                    "preferred_zone": "seating"
                })
                reasoning.append("Sofa aligned along the south wall to anchor the living area.")
            if tv_id:
                furniture.append({
                    "asset_id": tv_id,
                    "role": "tv_console",
                    "preferred_wall": "north",
                    "preferred_zone": "display"
                })
                reasoning.append("TV console placed opposite the sofa on the north wall.")
            if coffee_id and not is_minimal and not more_spacious:
                furniture.append({
                    "asset_id": coffee_id,
                    "role": "coffee_table",
                    "preferred_wall": "none",
                    "preferred_zone": "social"
                })
                reasoning.append("Coffee table centered to complete the conversational cluster.")
            if bookshelf_id and not is_minimal:
                furniture.append({
                    "asset_id": bookshelf_id,
                    "role": "bookshelf",
                    "preferred_wall": "east",
                    "preferred_zone": "storage"
                })
                reasoning.append("Bookshelf unit aligned along side wall.")
                
        # 6. OFFICE / EXECUTIVE OFFICE / STUDY
        elif any(k in room_type for k in ["office", "manager", "executive", "study", "work"]):
            desk_id = find_asset(["executive", "manager", "desk", "study"], exclude=["chair"])
            manager_chair_id = find_asset(["manager", "executive", "ergonomic", "chair"], exclude=["visitor", "guest", "desk"])
            visitor_chair_id = find_asset(["visitor", "guest", "chair"], exclude=["manager", "desk"])
            cabinet_id = find_asset(["storage", "cabinet", "credenza"], exclude=["desk", "chair", "kitchen"])
            bookshelf_id = find_asset(["bookshelf", "shelf", "bookcase"], exclude=["desk", "chair"])
            
            if desk_id:
                furniture.append({
                    "asset_id": desk_id,
                    "role": "executive_desk",
                    "preferred_wall": "north",
                    "preferred_zone": "study"
                })
                reasoning.append("Executive desk placed in commanding position with clear door sightline.")

            if manager_chair_id:
                furniture.append({
                    "asset_id": manager_chair_id,
                    "role": "manager_chair",
                    "preferred_wall": "north",
                    "preferred_zone": "study"
                })
                reasoning.append("Ergonomic manager chair positioned directly behind executive desk with proper pullback space.")

            if visitor_chair_id:
                furniture.append({
                    "asset_id": visitor_chair_id,
                    "role": "visitor_chair_1",
                    "preferred_wall": "none",
                    "preferred_zone": "study"
                })
                furniture.append({
                    "asset_id": visitor_chair_id,
                    "role": "visitor_chair_2",
                    "preferred_wall": "none",
                    "preferred_zone": "study"
                })
                reasoning.append("Two visitor chairs placed in front of executive desk facing manager with comfortable clearance.")

            if cabinet_id and not is_minimal:
                furniture.append({
                    "asset_id": cabinet_id,
                    "role": "cabinet",
                    "preferred_wall": "east",
                    "preferred_zone": "storage"
                })
                reasoning.append("Storage cabinet placed flush against side wall for organized document storage.")

            if bookshelf_id and not is_minimal:
                furniture.append({
                    "asset_id": bookshelf_id,
                    "role": "bookshelf",
                    "preferred_wall": "west",
                    "preferred_zone": "storage"
                })
                reasoning.append("Bookshelf unit aligned along opposite side wall preserving circulation.")
                
        else: # Default fallback
            desk_id = find_asset(["desk", "table"], exclude=["bed"])
            chair_id = find_asset(["chair"], exclude=["desk", "bed"])
            if desk_id:
                furniture.append({"asset_id": desk_id, "role": "desk", "preferred_wall": "north", "preferred_zone": "work"})
            if chair_id:
                furniture.append({"asset_id": chair_id, "role": "chair", "preferred_wall": "north", "preferred_zone": "work"})

        return {
            "room_type": room_type,
            "layout_intent": "spacious_balanced" if more_spacious else "functional_zoned",
            "furniture": furniture,
            "reasoning": reasoning
        }


def _get_system_rules_prompt() -> str:
    return """
Rules for Room Layout by Room Type:
- For Kitchen:
  * Select Kitchen Counter (`role: "kitchen_counter"`, prep surface).
  * Select Kitchen Sink (`role: "sink"`, cleaning station).
  * Select Kitchen Stove / Cooktop (`role: "stove"`, cooking zone).
  * Select Refrigerator (`role: "refrigerator"`, food storage zone).
  * Select Kitchen Cabinet / Pantry (`role: "kitchen_cabinet"`, storage).
  * DO NOT select office chairs, desks, beds, or sofas for a kitchen!
  * Ensure food storage, prep, cleaning, and cooking zones form an ergonomic work triangle.
- For Dining Room:
  * Select Dining Table (`role: "dining_table"`).
  * Select Dining Chairs (`role: "dining_chair_1"`, `role: "dining_chair_2"`).
  * Select Sideboard / Credenza (`role: "sideboard"`).
  * DO NOT select office chairs, beds, or stoves!
- For Bathroom / Restroom:
  * Select Bathroom Vanity Unit (`role: "vanity"`).
  * DO NOT select desks, beds, or sofas!
- For Manager's Office / Executive Office:
  * Select 1 Executive Desk (`role: "executive_desk"`).
  * Select 1 Manager Chair (`role: "manager_chair"`, positioned directly behind the desk).
  * Select 2 Visitor Chairs (`role: "visitor_chair_1"` and `role: "visitor_chair_2"`, in front of desk).
  * Select 1 Storage Cabinet (`role: "cabinet"`, against a side wall).
  * Select 1 Bookshelf Unit (`role: "bookshelf"`, against a side wall).
  * DO NOT select beds or kitchen counters!
- For Bedroom:
  * Select 1 Bed (`role: "primary_sleep"` placed against solid wall).
  * Select 1-2 Nightstands (`role: "bedside"` placed next to bed).
  * Select 1 Wardrobe (`role: "wardrobe"` placed along perimeter wall).
  * If room area permits (>= 14 m²), select 1 Study Desk (`role: "desk"`) and 1 Chair (`role: "chair"`).
  * DO NOT select stoves or kitchen counters!
- For Living Room:
  * Select 1 Sofa (`role: "sofa"`).
  * Select 1 Coffee Table (`role: "coffee_table"`).
  * Select 1 TV Console (`role: "tv_console"`).
  * Select 1 Bookshelf (`role: "bookshelf"`).
"""


class GeminiLayoutProvider(LayoutAIProvider):
    def generate_layout_plan(
        self,
        room_context: Dict[str, Any],
        furniture_catalog: List[Dict[str, Any]],
        preferences: Dict[str, Any]
    ) -> Dict[str, Any]:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not configured.")
            
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
        prompt = self._build_prompt(room_context, furniture_catalog, preferences)
        
        headers = {"Content-Type": "application/json"}
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }],
            "generationConfig": {
                "responseMimeType": "application/json"
            }
        }
        
        try:
            response = httpx.post(url, headers=headers, json=payload, timeout=10.0)
            if response.status_code != 200:
                raise RuntimeError(f"Gemini API returned error: {response.text}")
                
            res_json = response.json()
            text_response = res_json["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(text_response)
        except Exception as e:
            logger.error(f"Gemini API call failed: {e}")
            raise e

    def _build_prompt(
        self,
        room_context: Dict[str, Any],
        furniture_catalog: List[Dict[str, Any]],
        preferences: Dict[str, Any]
    ) -> str:
        rules = _get_system_rules_prompt()
        return f"""
You are a senior professional interior designer. Propose a complete, ergonomic, functional layout plan strictly tailored to the room function and room type.

Room context:
{json.dumps(room_context)}

Furniture catalog (Select items strictly from this catalog):
{json.dumps(furniture_catalog)}

User Preferences / Command:
{json.dumps(preferences)}

{rules}

Output JSON schema:
{{
  "room_type": "string",
  "layout_intent": "string",
  "furniture": [
    {{
      "asset_id": "string",
      "role": "string",
      "preferred_wall": "north" | "south" | "west" | "east" | "none",
      "preferred_zone": "string"
    }}
  ],
  "reasoning": [
    "string explanation 1",
    "string explanation 2"
  ]
}}

Return ONLY the raw JSON object. Do not wrap in markdown code blocks.
"""


def discover_local_model(base_url: str, preferred_model: str) -> Tuple[bool, str, List[str]]:
    """
    Checks Ollama /api/tags to see if Ollama is running and which models are installed.
    Returns (is_available, selected_model_name, installed_model_names).
    """
    try:
        url = f"{base_url.rstrip('/')}/api/tags"
        resp = httpx.get(url, timeout=httpx.Timeout(4.0, connect=2.0))
        if resp.status_code == 200:
            models_data = resp.json().get("models", [])
            installed = [m.get("name") for m in models_data if m.get("name")]
            if preferred_model in installed:
                return True, preferred_model, installed
            # Check if any model contains the preferred name or qwen / llama
            pref_base = preferred_model.split(':')[0].lower()
            for m in installed:
                if pref_base in m.lower():
                    return True, m, installed
            for m in installed:
                if any(fam in m.lower() for fam in ["qwen", "llama", "mistral"]):
                    return True, m, installed
            if installed:
                return True, installed[0], installed
            return False, preferred_model, []
    except Exception as ex:
        logger.warning(f"Could not reach Ollama at {base_url}: {ex}")
    return False, preferred_model, []


class LocalLLMLayoutProvider(LayoutAIProvider):
    def generate_layout_plan(
        self,
        room_context: Dict[str, Any],
        furniture_catalog: List[Dict[str, Any]],
        preferences: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.config import settings
        from features.ai.exceptions import AIProcessingException
        import re
        import time

        base_url = settings.OLLAMA_BASE_URL.rstrip('/')
        url = f"{base_url}/api/generate"

        # 1. Determine model availability
        is_avail, selected_model, installed = discover_local_model(base_url, settings.OLLAMA_MODEL)
        if not is_avail:
            raise AIProcessingException(
                f"Local Ollama model service is not available at '{base_url}'. "
                f"Configured model '{settings.OLLAMA_MODEL}' was not found. "
                f"Installed models: {installed if installed else 'None (ensure Ollama is running)'}."
            )

        catalog_ids = {a.get("asset_id") or a.get("id") for a in furniture_catalog}
        rules = _get_system_rules_prompt()

        feedback = ""
        max_attempts = 2

        for attempt in range(max_attempts):
            prompt = f"""You are a senior professional interior designer. Propose a complete, ergonomic, functional layout plan strictly tailored to the room function and room type.

Room context:
{json.dumps(room_context, indent=2)}

Available Furniture Catalog (You MUST ONLY select items from this list using their exact asset_id):
{json.dumps(furniture_catalog, indent=2)}

User Preferences & Directives:
{json.dumps(preferences, indent=2)}

{rules}
{feedback}

Output JSON schema:
{{
  "room_type": "{room_context.get('room_type', 'Room')}",
  "layout_intent": "string (e.g. wall_aligned, functional_zoned, center_oriented, space_efficient)",
  "furniture": [
    {{
      "asset_id": "EXACT_ASSET_ID_FROM_CATALOG",
      "role": "string",
      "preferred_wall": "north" | "south" | "west" | "east" | "none",
      "preferred_zone": "string",
      "reasoning": "brief explanation"
    }}
  ],
  "functional_zones": {{
    "zone_name": ["asset_id_1"]
  }},
  "design_rationale": "Comprehensive design explanation",
  "constraints_considered": ["Constraint 1", "Constraint 2"],
  "unresolved_requirements": []
}}

Return ONLY valid JSON matching the schema above. Do NOT invent nonexistent asset_ids.
"""
            payload = {
                "model": selected_model,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {
                    "temperature": 0.2
                }
            }

            start_time = time.time()
            try:
                logger.info(f"Invoking Ollama model '{selected_model}' (attempt {attempt + 1}/{max_attempts})...")
                response = httpx.post(url, json=payload, timeout=httpx.Timeout(45.0, connect=3.0))
                latency = (time.time() - start_time) * 1000.0

                if response.status_code != 200:
                    logger.error(f"[AI DEBUG] Ollama HTTP status {response.status_code}: {response.text}")
                    raise RuntimeError(f"Ollama returned HTTP error {response.status_code}: {response.text}")

                res_json = response.json()
                resp_text = res_json.get("response", "").strip()
                logger.info(f"[AI DEBUG] Ollama connection: SUCCESS | Model: {selected_model} | Latency: {latency:.2f}ms")

                # Clean JSON fences if present
                json_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", resp_text, re.DOTALL)
                if json_match:
                    resp_text = json_match.group(1).strip()
                else:
                    brace_match = re.search(r"(\{.*\})", resp_text, re.DOTALL)
                    if brace_match:
                        resp_text = brace_match.group(1).strip()

                plan = json.loads(resp_text)

                # Validate structure
                if not isinstance(plan, dict):
                    raise ValueError("AI response must be a JSON object.")
                if "furniture" not in plan or not isinstance(plan["furniture"], list):
                    raise ValueError("AI response missing 'furniture' list.")

                # Check unknown asset IDs
                unknown_ids = []
                for item in plan["furniture"]:
                    aid = item.get("asset_id")
                    if aid not in catalog_ids:
                        unknown_ids.append(aid)

                if unknown_ids:
                    raise ValueError(f"AI response used nonexistent asset_ids: {unknown_ids}. Must use only catalog IDs.")

                # Ensure reasoning field exists for downstream consumers
                if "reasoning" not in plan or not isinstance(plan["reasoning"], list):
                    plan["reasoning"] = [plan.get("design_rationale", "AI planned layout.")]

                return plan

            except Exception as e:
                logger.warning(f"Ollama attempt {attempt + 1} failed: {e}")
                if attempt < max_attempts - 1:
                    feedback = f"\nCRITICAL CORRECTION REQUIRED: Your previous attempt failed validation with error: {e}. You MUST strictly use the exact asset_id values present in the catalog and output valid JSON only.\n"
                    time.sleep(1.0)
                else:
                    logger.error(f"Local LLM API call failed after {max_attempts} attempts: {e}")
                    raise e
