from typing import Dict, Any

def get_recommendation_explanation(recommendation: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns explainable AI elements including supporting design principles,
    reasons, and design score impact.
    """
    rule = recommendation.get("rule_triggered", "General Rule")
    
    # Map rules to supporting interior design principles
    principles = {
        "Door Clearance Rule": (
            "Safety and circulation. Unobstructed doorways ensure emergency exits remain clear "
            "and allow comfortable door swing access (minimum 80-90 cm clearance)."
        ),
        "Window Clearance Rule": (
            "Preserving natural lighting and ventilation. Windows should remain clear of "
            "tall obstacles to allow daylight projection and airflow into the living space."
        ),
        "Walkway Width Rule": (
            "Accessibility and circulation paths. Walkways must maintain a minimum width of "
            "70-80 cm to allow comfortable movement of adults and accessibility access."
        ),
        "Bed Access Clearance Rule": (
            "Ergonomic bedside comfort. A minimum clearance of 60 cm on the sides of a bed "
            "is necessary to walk alongside the bed and make the sheets comfortably."
        ),
        "TV Viewing Distance Rule": (
            "Visual ergonomics and comfort. TV distance is calculated relative to screen size "
            "to prevent eye strain and support comfortable viewing angles (usually 1.5m to 3m)."
        ),
        "Desk Ergonomics Rule": (
            "Productivity and spatial ergonomics. Desks require 80 cm of clear space behind "
            "them to comfortably pull out the office chair and sit/stand without restriction."
        ),
        "Missing Furniture Rule": (
            "Functional room categorization. Each room type is optimized for specific "
            "activities which require core furniture assets to satisfy basic usability requirements."
        ),
        "Material Suggestion Rule": (
            "Visual coherence. Applying consistent colors, finishes, and wood/fabric types "
            "creates a unified interior style (e.g. Modern, Minimal, Scandinavian)."
        )
    }
    
    return {
        "why_suggested": recommendation.get("reason", "Improves overall room aesthetics and functionality."),
        "rule_triggered": rule,
        "design_principle": principles.get(rule, "Standard professional interior layout guideline."),
        "expected_improvement": recommendation.get("expected_improvement", "Improves room circulation and usability."),
        "score_impact": recommendation.get("score_impact", "Overall Score +5%")
    }
