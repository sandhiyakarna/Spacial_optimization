# FlowSpace: Implementation Walkthrough

This document records the implemented core foundation, the Authentication & User Management module, the Dashboard & Project Management module, the Room Management module, the Design Validation System, the Dynamic Furniture Catalog, and the GPU Viewport Interactive Editing module. All modules conform fully to the technical specs in `docs/`.

---

## 1. Authentication & User Management Module (MOD-001)

The complete Authentication and User Profile system has been implemented across both the backend and frontend.

### 1.1 Database Schema (SQLite/PostgreSQL compatible)
The database structure has been updated and migrated via Alembic:
* **`roles`**: System roles (`Administrator`, `Interior Designer`, `Architect`, `Customer`, `Guest`). Automatically seeded on backend start.
* **`permissions`**: Granular permissions (e.g. read/write).
* **`role_permissions`**: Joins roles and permissions.
* **`users`**: User records containing `full_name`, `email`, `password_hash`, and a foreign key to their `role_id`.
* **`user_preferences`**: Layout styling (`theme`, `language`, `measurement_unit`, `default_room_unit`, `notifications_enabled`). Created automatically upon registration.
* **`user_sessions`**: Session database tracker mapping `access_token` and `refresh_token` to handle logout invalidations.
* **`audit_logs`**: Logs login, registrations, passwords changes, and deletion audit entries.

### 1.2 Backend API Features (FastAPI)
1. **Password Hashing**: Secure encryption using bcrypt hashing.
2. **Access & Refresh Tokens**: Generates JWT access tokens (120 min duration) and refresh tokens (7 days).
3. **Protected Routers**: `get_current_user` dependency parses and checks the session table, rejecting requests with revoked sessions.
4. **Role-Based Access Control**: `RoleChecker` dependency restricts endpoints to authorized roles.
5. **Endpoints Implemented (`/api/v1/auth/*`)**:
   * `POST /register`: Creates users and maps them to the default `Customer` role.
   * `POST /login`: Validates credentials, issues JWT/refresh tokens, and records last_login and audit trail.
   * `POST /refresh`: Issues a new access token if the refresh token session is active.
   * `POST /logout`: Revokes active sessions.
   * `GET /profile` / `PUT /profile`: Retreives or updates details (e.g. full name, theme, language).
   * `PUT /change-password`: Modifies user password.
   * `POST /forgot-password` / `POST /reset-password`: Handles token resets safely.
   * `DELETE /account`: Soft-deletes user accounts.

### 1.3 Frontend Client Features (Flutter)
1. **Form Validation**: Validates text inputs (e.g. valid email patterns, password min length of 8).
2. **Secure Token Storage**: Handles JWT tokens locally across platforms.
3. **Route Guards**: Evaluates token presence in `GoRouter` redirects. Redirects unauthenticated users to `/login` and authenticated users to `/home`.
4. **Riverpod Authentication Notifier**: Modern `NotifierProvider` manages login, registration, password actions, and loading states reactively.
5. **Auth Screens Implemented**:
   * `LoginScreen`: Custom welcome cards and options to register or recover passwords.
   * `RegisterScreen`: Registration forms for full name, email, and password.
   * `ForgotPasswordScreen`: Initiates reset recovery emails.
   * `ResetPasswordScreen`: Submits token and new password updates.
   * `ProfileScreen`: Unified profile panel to update names, change passwords, logout, or soft-delete accounts.

---

## 2. Dashboard & Project Management Module (MOD-002 & MOD-003)

The complete project creation, duplication, and monitoring system has been implemented.

### 2.1 Database Schema (SQLite/PostgreSQL compatible)
The database structure has been updated and migrated via Alembic:
* **`projects`**: Project records containing `project_name`, `description`, `location`, `cover_image`, `status`, and `is_favorite`.
* **`project_settings`**: Configurations for each project (`default_style`, `default_template`, `measurement_unit`, `grid_enabled`, `snap_enabled`).

### 2.2 Backend API Features (FastAPI)
1. **Project CRUD Endpoints (`/api/v1/projects/*`)**:
   * `POST /projects`: Creates a project with default configuration and ensures duplicate project names for the same user are rejected.
   * `GET /projects`: Fetches page list, supporting status filters, search queries, favorite toggles, and sorting options.
   * `GET /projects/{project_id}`: Fetches individual project config.
   * `PUT /projects/{project_id}`: Edits project names, descriptions, locations, status states, and favorite toggles.
   * `DELETE /projects/{project_id}`: Performs soft deletion (sets status to 'Deleted').
   * `POST /projects/{project_id}/duplicate`: Duplicates a project, making full copies of the project row, configuration settings, and associated room list.
   * `PATCH /projects/{project_id}/archive`: Sets project status to 'Archived'.
   * `PATCH /projects/{project_id}/restore`: Sets project status to 'Draft'.
   * `PATCH /projects/{project_id}/toggle-favorite`: Toggles the favorite flag.
2. **Dashboard Endpoint (`/api/v1/dashboard`)**:
   * Aggregates recent/favorite projects, metrics totals (total projects, total rooms), AI recommendation lists, notifications, and activity logs.

### 2.3 Frontend Client Features (Flutter)
1. **Dashboard Screen** (`dashboard_screen.dart`): Displays welcome headers, quick action buttons, responsive columns for recent/favorite projects, AI recommendations, notifications, and user metadata details.
2. **Project List Screen** (`project_list_screen.dart`): Listing view with custom search inputs, status drop-down filters, sorting triggers, and cards managing duplicates and edits.
3. **Project Dialogs** (`project_dialogs.dart`): Modals facilitating project creations, detail updates, and confirmation prompts.
4. **State Management**: `projectProvider` and `dashboardProvider` manage reactive updates.

---

## 3. Room Management Module (MOD-004)

A comprehensive spatial geometry cataloging system allowing designers to configure individual room specifications, wall/ceiling layouts, and custom attributes.

### 3.1 Database Schema (SQLite/PostgreSQL compatible)
The room tables have been migrated via Alembic:
* **`rooms`**: Represents a room entity containing `room_name`, `room_type`, `floor_number`, `room_color`, `properties` (JSON parameters), and a relation back to `projects.id`.
* **`room_measurements`**: Integrates room geometry dimensions: `length`, `width`, `height`, `floor_thickness`, `wall_thickness`, and `ceiling_height` in centimeters.

### 3.2 Backend API Features (FastAPI)
1. **Room CRUD Endpoints (`/api/v1/*`)**:
   * `POST /projects/{project_id}/rooms`: Adds a new room to a project.
   * `GET /projects/{project_id}/rooms`: Fetches all rooms configured inside a project.
   * `GET /rooms/{room_id}`: Returns complete room properties and measurements.
   * `PUT /rooms/{room_id}`: Modifies room naming, style properties, and custom attributes.
   * `DELETE /rooms/{room_id}`: Deletes a room along with all linked configurations.
   * `POST /rooms/{room_id}/duplicate`: Duplicates a room, copying all structural metrics.
2. **Measurements API**:
   * `GET /rooms/{room_id}/measurements`: Retrieves dimensional measurements.
   * `PUT /rooms/{room_id}/measurements`: Updates lengths, widths, and thicknesses (validating bounds: length, width, and height must exceed zero).

### 3.3 Frontend Client Features (Flutter)
1. **Rooms List View** (`room_list_screen.dart`): Displays project room catalogs with quick statistics (type, floor, notes, color swatch).
2. **Room Details Screen** (`room_details_screen.dart`): Dynamic layout displaying and saving space geometry attributes (length, width, height, ceiling height, wall/floor thicknesses, custom properties).
3. **Room Dialogs** (`room_dialogs.dart`): Form-validated dialogs for adding or editing space metadata.
4. **State Management**: `roomListProvider` and `roomDetailsProvider` coordinate state updates.

---

## 4. Design Validation System (MOD-005)

A comprehensive architectural and safety validation suite that runs on the room layout, calculates design scores, and reports alerts and remedies.

### 4.1 Backend Implementation
* **Validation Schema**: Enhanced `ValidationSummaryResponseData` schema to include `overall_score` and subscores (`accessibility_score`, `lighting_score`, `ergonomic_score`, `space_utilization_score`, `furniture_balance_score`).
* **Validation Endpoints**: Updated `/summary/{room_id}` in `api.py` to fetch layout scores from the `Analytics` table and calculate them dynamically if missing.

### 4.2 Frontend Implementation
* **Validation Provider**: Updated `ValidationSummary` class to parse the new Design Score fields from the backend response.
* **Validation UI (Drawer & Sidebar)**:
  * **Design Score Card**: Displays a high-level Design Score gauge (e.g. `85/100`) and a collapsible subscore breakdown (Space Utilization, Accessibility, Comfort, Lighting, Balance).
  * **Warning Panel**: Grouped validation issues under styled headers: **Errors** (Critical violations), **Warnings** (Alerts), and **Suggestions** (Improvements).
  * **Suggested Fixes**: Styled recommendations as clean callout boxes labeled "Suggested Fix".
  * **One-Click Navigation**: Added selection change listeners in `_DesignerScreenState` (`designer_screen.dart`) to trigger `_focusSelection2D()` automatically on selection, centering and zooming the canvas on the problematic item when the user clicks "Locate".
  * **Problematic Object Highlighting**: Retained the red dashed border highlighting and exclamation warning bubble on invalid/colliding objects on the 2D canvas.

---

## 5. Dynamic Furniture Catalog Module (MOD-006)

A comprehensive spatial asset management system allowing designers to browse and search the backend furniture catalog, organize elements by categories/filters, manage favorites, track recently used items, and navigate via paginated lists.

### 5.1 Backend Integration
* Connected the catalog to the SQLite/PostgreSQL dynamic endpoints.
* Integrated with endpoints:
  * `GET /furniture`: Paginated assets with search, category, style, and favorite filters.
  * `GET /furniture/categories`: Dynamically loads category lists.
  * `GET /furniture/favorites`: Loads the list of user's favorited items.
  * `GET /furniture/recent`: Tracks and displays recently used assets.
  * `POST /furniture/{id}/favorite` / `DELETE /furniture/{id}/favorite`: Toggles favorite statuses.

### 5.2 Frontend Architecture
* **[furniture_asset.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/models/furniture_asset.dart)**: Added `isFavorite` support and implemented a dedicated `FurnitureCategory` class.
* **[furniture_api_client.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/data/furniture_api_client.dart)**: Implemented network calls matching the backend's paginated, categories, favorites, and recents endpoints.
* **[furniture_provider.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/providers/furniture_provider.dart)**: Updated state notifier (`FurnitureListState` and `FurnitureNotifier`) to manage pagination indices, modes (`all`, `favorites`, `recent`), dynamic categories, and optimistic favorite toggling.
* **[furniture_filter_panel.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/presentation/widgets/furniture_filter_panel.dart)**: Replaced static category arrays with dynamic chips loaded from backend metadata.
* **[furniture_grid_item.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/presentation/widgets/furniture_grid_item.dart)**: Converted to `ConsumerWidget` and added a premium heart overlay toggling favorite status reactively.
* **[furniture_library_screen.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/furniture/presentation/furniture_library_screen.dart)**: Designed a modern SegmentedButton tab switcher, custom pagination controls, loading progress bars, and descriptive empty states for each catalog category.

---

## 6. Verification Summary (Core Modules)

### 6.1 Backend Tests
Passed pytest tests verifying authentication, project lifecycles, room CRUDs, measurements validation bounds, and duplicating settings:
```bash
pytest tests
```

### 6.2 Frontend Tests
Passed widget tests verifying route guarding, dashboard rendering, and room catalog listings:
```bash
flutter test
```

---

## 7. Interactive Object Editing in GPU Viewport (Milestone 13.5)

Professional interactive object editing has been enabled directly inside the GPU Viewport sandbox, fully integrated with Flutter/Riverpod state management.

### 7.1 Web Viewport Implementation
* **File Location**: [renderer_sandbox.html](file:///c:/Users/Admin/Documents/mad2/frontend/web/renderer_sandbox.html)
* **Interactive Selection**:
  * Single click raycasting selects furniture.
  * Empty space clicks trigger deselection.
  * Emissive highlight and gray bounding box helper (`THREE.BoxHelper`) on hover.
  * Blue bounding box helper (`THREE.BoxHelper`) on active selection.
  * Multi-selection architecture preparation (using `selectedIds` state representation).
* **Gizmos & Controls**:
  * Active gizmo support for Translation, Rotation, and Scaling modes.
  * Axis constraints and space toggles (World vs Local) supported programmatically and via keyboard shortcuts.
  * Snap-to-floor constraint dynamically positions furniture bottom bound at `y = 0` (resting on floor).
  * Collision preparation check against walls and other furniture meshes, displaying a red bounding box highlight (`0xef4444`) on overlap.
  * Refocus camera controls (`OrbitControls.target`) to center on the selected object's coordinates.
* **Shortcut Keys**:
  * `T`: Translate Mode
  * `R`: Rotate Mode
  * `S`: Scale Mode
  * `Q`: Select Mode
  * `W` / `L`: World / Local Coordinate Space
  * `X` / `Y` / `Z`: Lock/Unlock axis constraint
  * `F`: Center camera focus on selected object
* **Interaction Mockup Visual**:
  ![FlowSpace 3D Viewport Mockup](file:///C:/Users/Admin/.gemini/antigravity-ide/brain/3c73487e-134d-476e-a36e-c576de036752/designer_viewport_mockup_1786296483046.png)

### 7.2 Flutter Bridge Integration
* **File Location**: [viewport_controller.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/features/designer/bridge/viewport_controller.dart)
* **Message Handlers**:
  * Implemented event listeners for `OBJECT_SELECTED`, `OBJECT_DESELECTED`, `OBJECT_MOVED`, `OBJECT_ROTATED`, and `OBJECT_SCALED`.
  * Added robust coordinate extraction that parses both flat payload properties (`x`, `y`, `z`) and nested objects (`position: {x, y, z}`).
  * Updates Riverpod provider (`designerProvider`) state reactively, preserving it as the single source of truth.
* **Loop Prevention**:
  * Safely ignores incoming updates during active user dragging/interaction via `transformControls.dragging` checks.

### 7.3 Automated Verification Results
All automated tests compiled and passed cleanly:
```bash
flutter test
# Output: All tests passed! (77 passed)
```
New unit tests were added in [gpu_viewport_bridge_test.dart](file:///c:/Users/Admin/Documents/mad2/frontend/test/gpu_viewport_bridge_test.dart):
1. `Receiving OBJECT_SELECTED and OBJECT_DESELECTED updates designer selection state`
2. `Receiving OBJECT_MOVED, OBJECT_ROTATED, and OBJECT_SCALED updates furniture transform`

---

## 8. Dockerization Infrastructure

A complete, production-ready containerization and orchestration structure has been successfully implemented for FlowSpace v2.0.

### 8.1 Backend Docker Container
- Created an optimized [Dockerfile](file:///c:/Users/Admin/Documents/mad2/backend/Dockerfile) based on `python:3.11-slim` that installs `curl`, `libpq-dev`, and `gcc` for database connections and health checking.
- Integrated a robust [entrypoint.sh](file:///c:/Users/Admin/Documents/mad2/backend/entrypoint.sh) startup script that handles database availability checking (waiting up to 60s for PostgreSQL) and automatic database migrations (`alembic upgrade head`) before booting up uvicorn.
- Configured [.dockerignore](file:///c:/Users/Admin/Documents/mad2/backend/.dockerignore) to exclude local virtual environments and caches.

### 8.2 Frontend Docker Container (Flutter Web serving)
- Implemented a multi-stage [Dockerfile](file:///c:/Users/Admin/Documents/mad2/frontend/Dockerfile):
  - **Stage 1 (Build)**: Downloads/caches the Flutter stable SDK and builds the Flutter Web release bundle.
  - **Stage 2 (Run)**: Deploys the built HTML/JS assets to a minimal `nginx:alpine` container.
- Designed a custom reverse proxy [nginx.conf](file:///c:/Users/Admin/Documents/mad2/frontend/nginx.conf) that serves static Flutter Web assets on port 80 and reverse proxies `/api/*`, `/uploads/*`, and `/static/*` traffic back to the backend service, eliminating CORS issues.
- Created a safe, platform-independent URL helper [url_helper.dart](file:///c:/Users/Admin/Documents/mad2/frontend/lib/core/utils/url_helper.dart) and modified all hardcoded URL formats across the frontend source files to dynamically point to the Nginx origin in release/production modes, and fallback to `localhost:8000` in local Flutter debug/development modes.

### 8.3 Orchestration & Composition
- **Production Stack** ([docker-compose.yml](file:///c:/Users/Admin/Documents/mad2/docker-compose.yml)):
  - `db`: PostgreSQL 16 image with database persistence, a health check (`pg_isready`).
  - `backend`: Built from source, depends on `db` (healthy), mounts a persistent `uploads_data` volume for permanent user assets. Includes API healthcheck.
  - `frontend`: Built using multi-stage build, depends on `backend` (healthy), maps port 8080.
- **Development Stack** ([docker-compose.dev.yml](file:///c:/Users/Admin/Documents/mad2/docker-compose.dev.yml)):
  - Backend mounts the local `backend/` directory directly to `/app` enabling live code reloading.
  - Frontend mounts the local `frontend/build/web` directory directly to Nginx's HTML root directory, allowing developers to run `flutter build web` locally on the host and have the container immediately reflect changes.
  - Local `uploads` directory is mounted to preserve assets directly on the host machine.

### 8.4 Verification Results
- All 33 backend tests passed successfully:
  ```bash
  .venv\Scripts\python -m pytest
  ```
- Flutter static analysis compiles cleanly:
  ```bash
  flutter analyze
  ```

---

## 9. Production Readiness & Deployment Preparation (Milestone 18)

We have successfully prepared the entire application stack for production deployment.

### 9.1 Nginx HTTPS & Security Headers
- Created [nginx.prod.conf](file:///c:/Users/Admin/Documents/mad2/frontend/nginx.prod.conf) for production environments:
  - Listens on port 443 with SSL and HTTP/2.
  - Automatically redirects all port 80 HTTP requests to HTTPS via 301.
  - Implements production security headers (`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy`, and a tight `Content-Security-Policy`).
- Updated the frontend [Dockerfile](file:///c:/Users/Admin/Documents/mad2/frontend/Dockerfile) to:
  - Install `openssl` in the run stage.
  - Generate a default 365-day self-signed SSL key/certificate at `/etc/nginx/ssl/nginx.key` and `/etc/nginx/ssl/nginx.crt` during build, enabling the server to start up correctly out-of-the-box and support volume overrides.
- Configured [docker-compose.yml](file:///c:/Users/Admin/Documents/mad2/docker-compose.yml) to map ports `80:80` and `443:443` for the frontend.

### 9.2 FastAPI Production Execution
- Installed `gunicorn` in [requirements.txt](file:///c:/Users/Admin/Documents/mad2/backend/requirements.txt) to act as the production WSGI/ASGI manager.
- Updated [entrypoint.sh](file:///c:/Users/Admin/Documents/mad2/backend/entrypoint.sh) to:
  - Check if `ENVIRONMENT=production`. If so, start the server using Gunicorn process manager with 4 Uvicorn workers: `gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 --access-logfile - --error-logfile -`
  - Otherwise, fallback to the development server `python main.py` with auto-reload.

### 9.3 Dynamic Logging
- Updated [logger.py](file:///c:/Users/Admin/Documents/mad2/backend/core/logging/logger.py) to read the `LOG_LEVEL` environment variable dynamically at startup.

### 9.4 Telemetry Metrics Middleware
- Implemented `RequestMetricsMiddleware` in [metrics_middleware.py](file:///c:/Users/Admin/Documents/mad2/backend/app/middleware/metrics_middleware.py) to track request counts, 5xx errors, latencies, and route distributions.
- Created a thread-safe telemetry storage manager [metrics.py](file:///c:/Users/Admin/Documents/mad2/backend/core/monitoring/metrics.py).
- Registered the middleware in [main.py](file:///c:/Users/Admin/Documents/mad2/backend/app/main.py) and added the admin-only `GET /api/v1/system/metrics` endpoint in [api.py](file:///c:/Users/Admin/Documents/mad2/backend/features/system/api.py).

### 9.5 Health Probes & Robust Error Handling
- Implemented `/health/live` (liveness) and `/health/ready` (readiness) endpoints in [main.py](file:///c:/Users/Admin/Documents/mad2/backend/app/main.py).
  - Readiness check performs a database connection ping and verifies write permissions on the `uploads/` directory. Returns `503 Service Unavailable` if either dependency is offline.
- Updated `docker-compose.yml` and `docker-compose.dev.yml` to target `/health/ready`.
- Modified [exception_middleware.py](file:///c:/Users/Admin/Documents/mad2/backend/app/middleware/exception_middleware.py) to catch `OperationalError` and `InterfaceError` database connection errors and return a `503 Service Unavailable` response.

### 9.6 Backup Infrastructure
- Updated the database service in [service.py](file:///c:/Users/Admin/Documents/mad2/backend/features/system/service.py) to support native PostgreSQL backups via `pg_dump` when a PostgreSQL database URL is detected, compressing the dump using gzip.
- Created standalone, robust, self-rotating database backup utility scripts:
  - Linux Shell: [backup_db.sh](file:///c:/Users/Admin/Documents/mad2/scripts/backup_db.sh)
  - Windows PowerShell: [backup_db.ps1](file:///c:/Users/Admin/Documents/mad2/scripts/backup_db.ps1)

### 9.7 Verification Results
- All 37 backend tests passed successfully:
  ```powershell
  $env:PYTHONPATH="." ; .\.venv\Scripts\pytest
  ```

