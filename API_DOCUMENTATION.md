# OpenAPI & REST API Specification

This document details the FlowSpace REST API specification. The backend exposes endpoints for user profiles, room configurations, interactive edits, layout scoring, and room reconstruction.

To learn how to authenticate your API client or set up database migrations, consult the **[Installation Guide](file:///c:/Users/Admin/Documents/mad2/docs/INSTALLATION.md)** and the **[Master Developer Handbook](file:///c:/Users/Admin/Documents/mad2/docs/PROJECT_HANDBOOK.md)**.

---

## 🔒 Authentication & Headers

Most API endpoints require authentication. To call protected endpoints, include your JWT access token in the `Authorization` header:

```http
Authorization: Bearer <your_jwt_access_token>
```

### Authentication Lifecycle Endpoints (`/api/v1/auth`)

* **`POST /register`**:
  * Registers a new user. Default role is `Customer`.
  * Inputs: `email`, `password`, `full_name`.
* **`POST /login`**:
  * Authenticates credentials and returns a JWT token pair (access and refresh tokens).
  * Inputs: `username` (email), `password`.
  * Response:
    ```json
    {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "d7aa8491c9...",
      "token_type": "bearer"
    }
    ```
* **`POST /refresh`**:
  * Generates a new access token if the refresh token is valid and active in the database session table.
* **`POST /logout`**:
  * Revokes the active session token in the session database.
* **`GET /profile` / `PUT /profile`**:
  * Reads or updates user preferences (theme, language, unit preferences).

---

## 📂 Project & Room CRUD (`/api/v1`)

* **`POST /projects`**:
  * Creates a new project workspace. Unique project names are enforced per user.
* **`GET /projects`**:
  * Retrieves a paginated list of projects. Supports filtering by status (`Draft`, `Completed`, `Archived`, `Deleted`), searching by name/description, and sorting.
* **`POST /projects/{id}/duplicate`**:
  * Clones a project and duplicates all its nested rooms and settings.
* **`POST /projects/{project_id}/rooms`**:
  * Appends a new room setup (length, width, height, type) to a project.
* **`PUT /rooms/{room_id}/measurements`**:
  * Updates room dimensions. The backend validates that values are positive floats.

---

## 🛋️ Furniture Catalog & Inventory (`/api/v1/furniture`)

* **`GET /furniture`**:
  * Retrieves a paginated list of catalog assets. Supports searching by keyword, filtering by category/subcategory, style, and filtering by favorites.
* **`GET /furniture/categories`**:
  * Retrieves categories dynamically seeded from the database.
* **`GET /furniture/favorites` / `POST /furniture/{id}/favorite` / `DELETE /furniture/{id}/favorite`**:
  * Manages the user's favorite furniture catalog items.
* **`GET /furniture/recent`**:
  * Retrieves the user's recently used furniture items to display in the design workspace.

---

## 🧮 Design Validation & Scoring (`/api/v1/validation`)

Calculates spatial clearances, wall alignments, and safety violations to score layouts in real-time.

* **`POST /validation/run`**:
  * Initiates validation checks for a specified room.
  * Inputs: `room_id`.
* **`GET /validation/summary/{room_id}`**:
  * Returns validation scores:
    ```json
    {
      "success": true,
      "data": {
        "room_id": "room-uuid",
        "pass_rate": 82.5,
        "warning_count": 2,
        "error_count": 0,
        "overall_status": "Warning",
        "overall_score": 85.0,
        "accessibility_score": 90.0,
        "lighting_score": 75.0,
        "ergonomic_score": 80.0,
        "space_utilization_score": 65.0,
        "furniture_balance_score": 95.0
      }
    }
    ```
* **`GET /validation/checklist/{room_id}`**:
  * Returns a checklist of design rules and safety guidelines with their completion status.

---

## 📸 3D Room Reconstruction (`/api/v1/reconstruction`)

Endpoints for 360-degree panorama stitching and spatial modeling.

* **`POST /reconstruction/upload-panorama`**:
  * Uploads a 360-degree panoramic image file to reconstruct a room layout.
* **`POST /reconstruction/stitch`**:
  * Stitches 6 captured camera sector frames into a 2:1 panoramic view.
* **`GET /reconstruction/model/{room_id}`**:
  * Retrieves the reconstructed 3D spatial room model (walls, openings, furniture layout estimates) generated from the panorama.

---

## 🩺 System Monitoring (`/api/v1/system`)

Endpoints for health monitoring and diagnostics.

* **`GET /health`**:
  * Public endpoint returning server status and database connectivity.
* **`GET /health/live`**:
  * Liveness probe for container orchestrators.
* **`GET /health/ready`**:
  * Readiness probe checking database connectivity and storage write permissions.
* **`GET /system/metrics`**:
  * Admin-only endpoint returning server performance metrics (request rates, HTTP status code counts, latencies).
