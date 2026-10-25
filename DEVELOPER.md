# Developer Guide & Contribution Handbook

Welcome to the FlowSpace Developer Guide. This document provides technical insights into the codebase structure, state management architecture, network integration, and engineering guidelines.

For a full list of design rules, requirements, and installation steps, please consult the **[Master Developer Handbook](file:///c:/Users/Admin/Documents/mad2/docs/PROJECT_HANDBOOK.md)**.

---

## 🏗️ Folder Conventions & Patterns

Both the backend and frontend modules use a **Feature-First** structure. Files are grouped by their business domain/feature rather than by technical layer (e.g. putting all controllers in one folder and all views in another).

### Backend Feature Layout
Each subdirectory inside `backend/features/` is self-contained:
* `models.py`: SQLAlchemy database models.
* `schemas.py`: Pydantic input validation and output serialization schemas.
* `service.py`: Business logic functions and controllers.
* `repository.py`: Database query abstraction handlers.
* `api.py` or `router.py`: FastAPI endpoint routers mapping HTTP methods to services.

### Frontend Feature Layout
Each feature subdirectory inside `frontend/lib/features/` is split into:
* `data/`: Network clients, API clients, local persistence interfaces.
* `domain/`: Business entities and pure model representations.
* `presentation/`: Flutter UI screens, custom widgets, and Riverpod controllers/notifiers.

---

## 🔁 Frontend State Management (Riverpod)

FlowSpace avoids using `setState` or long widget-scoped parameters to manage state. Instead, we use **Riverpod 2.x** with the code-generator pattern (where appropriate) or explicit Notifiers.

### 1. Authentication State
* **Provider**: `authProvider` manages user login states, access tokens, preferences, and session invalidation.
* **Navigation Guards**: GoRouter relies on `authProvider` to check authentication states. If a token is missing, GoRouter redirects the user to `/login`. If the token is valid, the user is navigated to `/home` (Dashboard).

### 2. Designer State & 3D Viewport
* **Provider**: `designerProvider` represents the single source of truth for the active room's spatial coordinates and furniture layout.
* **Synchronizer**: When a user selects, moves, rotates, or scales an object, `viewport_controller.dart` parses the Three.js message and dispatches it directly to `designerProvider`.
* **Transform Loop Prevention**: To avoid infinite loops (Three.js moves -> updates Riverpod -> updates Three.js -> repeats), the Webview controller ignores incoming state updates while the user is actively dragging the `TransformControls` gizmo.

---

## 🔌 Web-to-Flutter Communication Bridge

The 3D interactive viewport is an HTML page ([renderer_sandbox.html](file:///c:/Users/Admin/Documents/mad2/frontend/web/renderer_sandbox.html)) that runs inside a Flutter `HtmlElementView` (web) or webview controller (mobile/desktop).

### 1. Flutter to Webview (Sending Events)
To send instructions to the 3D viewport, Flutter invokes postMessage triggers on the web view window:
```dart
// Example: Selecting an object in the catalog tells Three.js to spawn it
void spawnFurniture(String assetId, String glbUrl) {
  _webViewContainer.postMessage({
    'type': 'SPAWN_OBJECT',
    'id': assetId,
    'url': glbUrl,
  });
}
```

### 2. Webview to Flutter (Receiving Events)
In JavaScript, actions (movements, selection events, collisions) are sent back to the parent frame:
```javascript
// Inside Three.js event listeners:
window.parent.postMessage({
    type: 'OBJECT_MOVED',
    id: activeSelectedId,
    x: mesh.position.x,
    y: mesh.position.y,
    z: mesh.position.z
}, '*');
```

---

## 🧪 Coding & Validation Conventions

To keep code robust and maintainable, please follow these guidelines:

### Type Safety & Linting
* Run static analysis on Dart files before committing:
  ```bash
  flutter analyze
  ```
  Ensure there are no errors, warnings, or formatting alerts.
* All backend APIs must use strict type hinting. Avoid returning raw Python dictionaries; wrap them in Pydantic schema schemas to ensure validation.

### Database Updates
* Database updates must be managed using Alembic. Never modify SQL schemas directly in production databases.
* Generate a new migration script using:
  ```bash
  alembic revision --autogenerate -m "describe your changes"
  ```
* Apply migrations using:
  ```bash
  alembic upgrade head
  ```

### Test Coverage
* Ensure all tests pass before proposing a PR.
* Write unit tests for business logic in:
  - Backend: `backend/tests/` (run with `pytest`)
  - Frontend: `frontend/test/` (run with `flutter test`)
