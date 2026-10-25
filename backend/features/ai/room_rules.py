"""
Modular room-specific interior design rules, compatibility checks, and functional constraints.
Defines hard constraints and ergonomic requirements for Kitchen, Bedroom, Living Room, Dining Room, Office/Study, and Bathroom.
"""

from typing import Dict, List, Optional, Set, Tuple, Any
from dataclasses import dataclass, field


@dataclass
class RoomRule:
    room_type: str
    display_name: str
    allowed_categories: List[str]
    prohibited_categories: List[str]
    prohibited_keywords: List[str]
    essential_roles: List[str]
    allowed_roles: List[str]
    min_area_m2: float = 4.0
    dining_allowed_min_area_m2: Optional[float] = None
    study_allowed_min_area_m2: Optional[float] = None
    description: str = ""

    def is_asset_compatible(
        self,
        name: str,
        category: str,
        tags: str = "",
        role: str = ""
    ) -> Tuple[bool, Optional[str]]:
        low_name = (name or "").lower()
        low_cat = (category or "").lower()
        low_tags = (tags or "").lower()
        low_role = (role or "").lower()

        # Check prohibited keywords in name, tags, or role
        for kw in self.prohibited_keywords:
            if kw in low_name or kw in low_tags or kw in low_role:
                return False, f"Item '{name}' contains prohibited keyword '{kw}' for room type '{self.display_name}'."

        # Check prohibited categories
        for pcat in self.prohibited_categories:
            if pcat in low_cat:
                return False, f"Item category '{category}' is prohibited in a {self.display_name}."

        # Check allowed categories (if specified)
        if self.allowed_categories:
            cat_matched = any(ac in low_cat for ac in self.allowed_categories)
            # Decor, lighting, plants are always globally allowed
            if not cat_matched and any(ac in low_cat for ac in ["lighting", "decor", "plants", "accessories"]):
                cat_matched = True
            if not cat_matched:
                return False, f"Item category '{category}' is not compatible with room type '{self.display_name}'."

        return True, None


ROOM_RULES: Dict[str, RoomRule] = {
    "kitchen": RoomRule(
        room_type="kitchen",
        display_name="Kitchen",
        allowed_categories=["kitchen", "dining", "lighting", "decor", "plants"],
        prohibited_categories=["office", "bedroom"],
        prohibited_keywords=[
            "office", "manager", "executive", "desk", "workstation",
            "bed", "wardrobe", "nightstand", "sofa", "couch", "armchair",
            "tv console", "tv", "media", "study desk", "task chair", "mesh chair",
            "gaming chair", "vanity"
        ],
        essential_roles=["kitchen_counter", "sink", "refrigerator"],
        allowed_roles=[
            "kitchen_counter", "sink", "stove", "refrigerator", "kitchen_cabinet",
            "dining_table", "dining_chair", "lighting", "decor", "plant"
        ],
        dining_allowed_min_area_m2=14.0,
        description="Practical, hygienic, and efficient food preparation, cooking, cleaning, and storage environment."
    ),
    "bedroom": RoomRule(
        room_type="bedroom",
        display_name="Bedroom",
        allowed_categories=["bedroom", "office", "lighting", "decor", "plants"],
        prohibited_categories=["kitchen", "bathroom"],
        prohibited_keywords=[
            "kitchen", "sink", "counter", "refrigerator", "fridge", "stove", "cooktop",
            "oven", "dining table", "coffee table", "pantry", "vanity"
        ],
        essential_roles=["primary_sleep"],
        allowed_roles=[
            "primary_sleep", "bedside", "wardrobe", "desk", "chair",
            "lighting", "decor", "plant"
        ],
        study_allowed_min_area_m2=14.0,
        description="Relaxing, restorative private sleeping quarters with clothes storage and circulation."
    ),
    "living": RoomRule(
        room_type="living",
        display_name="Living Room",
        allowed_categories=["living room", "lighting", "decor", "plants", "office"],
        prohibited_categories=["kitchen", "bathroom", "bedroom"],
        prohibited_keywords=[
            "bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge",
            "stove", "kitchen counter", "cooktop", "oven", "vanity"
        ],
        essential_roles=["sofa"],
        allowed_roles=[
            "sofa", "coffee_table", "tv_console", "bookshelf", "lounge_chair",
            "lighting", "decor", "plant"
        ],
        description="Inviting social, conversational, and entertainment gathering space."
    ),
    "dining": RoomRule(
        room_type="dining",
        display_name="Dining Room",
        allowed_categories=["dining", "kitchen", "lighting", "decor", "plants"],
        prohibited_categories=["office", "bedroom", "bathroom"],
        prohibited_keywords=[
            "office", "manager", "executive", "desk", "bed", "wardrobe",
            "sofa", "couch", "nightstand", "sink", "refrigerator", "stove",
            "cooktop", "range", "kitchen counter", "tv console", "vanity"
        ],
        essential_roles=["dining_table", "dining_chair"],
        allowed_roles=[
            "dining_table", "dining_chair", "sideboard", "lighting", "decor", "plant"
        ],
        description="Dedicated dining and social gathering area with generous chair clearances."
    ),
    "office": RoomRule(
        room_type="office",
        display_name="Office",
        allowed_categories=["office", "lighting", "decor", "plants"],
        prohibited_categories=["kitchen", "bedroom", "bathroom"],
        prohibited_keywords=[
            "bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge",
            "stove", "kitchen counter", "sofa", "dining table", "vanity"
        ],
        essential_roles=["desk", "chair"],
        allowed_roles=[
            "desk", "executive_desk", "manager_chair", "chair", "visitor_chair_1",
            "visitor_chair_2", "cabinet", "bookshelf", "lighting", "decor", "plant"
        ],
        description="Ergonomic individual work and productivity space."
    ),
    "study": RoomRule(
        room_type="study",
        display_name="Study Room",
        allowed_categories=["office", "lighting", "decor", "plants"],
        prohibited_categories=["kitchen", "bedroom", "bathroom"],
        prohibited_keywords=[
            "bed", "wardrobe", "nightstand", "sink", "refrigerator", "fridge",
            "stove", "kitchen counter", "sofa", "dining table", "vanity"
        ],
        essential_roles=["desk", "chair"],
        allowed_roles=[
            "desk", "chair", "bookshelf", "cabinet", "lighting", "decor", "plant"
        ],
        description="Focused quiet study and reading room with perimeter storage."
    ),
    "bathroom": RoomRule(
        room_type="bathroom",
        display_name="Bathroom",
        allowed_categories=["bathroom", "lighting", "decor"],
        prohibited_categories=["kitchen", "bedroom", "office", "living room"],
        prohibited_keywords=[
            "bed", "desk", "sofa", "wardrobe", "dining table", "tv", "refrigerator",
            "couch", "chair"
        ],
        essential_roles=["vanity"],
        allowed_roles=["vanity", "mirror", "lighting", "decor"],
        description="Private hygienic grooming and washing room."
    ),
}


def get_room_rule(room_type: Optional[str]) -> RoomRule:
    """
    Retrieves the matched RoomRule for any room_type string.
    Defaults to Living Room if unrecognized.
    """
    low = (room_type or "").lower().strip()
    if "kitchen" in low:
        return ROOM_RULES["kitchen"]
    elif "bedroom" in low:
        return ROOM_RULES["bedroom"]
    elif "dining" in low:
        return ROOM_RULES["dining"]
    elif any(k in low for k in ["office", "manager", "executive"]):
        return ROOM_RULES["office"]
    elif any(k in low for k in ["study", "work"]):
        return ROOM_RULES["study"]
    elif any(k in low for k in ["bathroom", "restroom", "toilet", "washroom"]):
        return ROOM_RULES["bathroom"]
    elif "living" in low:
        return ROOM_RULES["living"]
    return ROOM_RULES["living"]


def is_asset_compatible_with_room(
    asset_or_name: Any,
    room_type_or_cat: Optional[str] = None,
    asset_tags: Optional[str] = None,
    room_type: Optional[str] = None
) -> bool:
    """
    Full backward-compatible compatibility checker that delegates to RoomRule.
    """
    if hasattr(asset_or_name, "name"):
        name = asset_or_name.name or ""
        cat = getattr(asset_or_name, "category", "") or ""
        tags = getattr(asset_or_name, "tags", "") or ""
        target_room = room_type_or_cat or ""
    elif isinstance(asset_or_name, dict):
        name = asset_or_name.get("name") or ""
        cat = asset_or_name.get("category") or ""
        tags = asset_or_name.get("tags") or ""
        target_room = room_type_or_cat or ""
    else:
        name = str(asset_or_name or "")
        cat = room_type_or_cat or ""
        tags = asset_tags or ""
        target_room = room_type or ""

    rule = get_room_rule(target_room)
    ok, _ = rule.is_asset_compatible(name=name, category=cat, tags=tags)
    return ok


def check_missing_essential_assets(catalog_assets: List[Any], room_type: str) -> List[str]:
    """
    Inspects whether the given catalog contains the essential assets required for this room type.
    Returns list of missing essential role descriptions.
    """
    rule = get_room_rule(room_type)
    present_roles = set()
    for a in catalog_assets:
        name = (getattr(a, "name", "") or a.get("name", "") if isinstance(a, dict) else "").lower()
        cat = (getattr(a, "category", "") or a.get("category", "") if isinstance(a, dict) else "").lower()
        if "counter" in name:
            present_roles.add("kitchen_counter")
        if "sink" in name:
            present_roles.add("sink")
        if "fridge" in name or "refrigerator" in name:
            present_roles.add("refrigerator")
        if "bed" in name and "night" not in name:
            present_roles.add("primary_sleep")
        if "sofa" in name or "couch" in name:
            present_roles.add("sofa")
        if "dining" in name and "table" in name:
            present_roles.add("dining_table")
        if "desk" in name:
            present_roles.add("desk")
        if "vanity" in name:
            present_roles.add("vanity")

    missing = []
    for role in rule.essential_roles:
        if role not in present_roles:
            role_label = role.replace("_", " ").title()
            missing.append(role_label)
    return missing
