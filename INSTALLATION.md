# Installation & Setup Guide

This guide details the complete local installation process for the FlowSpace project.

For a comprehensive overview of requirements, architecture, and other advanced modules, consult the **[Master Developer Handbook](file:///c:/Users/Admin/Documents/mad2/docs/PROJECT_HANDBOOK.md)**.

---

## 📋 System Prerequisites
Before starting, ensure your local workstation has the following installed:
* **Python**: 3.11.x or 3.12.x
* **Flutter**: 3.22.x (Stable channel)
* **Dart**: Included with Flutter SDK
* **Node.js**: (Optional) 18.x+ (if working on JS sandbox files locally)
* **Docker & Docker Compose**: (Optional, for containerized execution)
* **Blender**: (Optional, 4.2+ for local 3D Asset Organizer mesh normalization)

---

## 🗄️ Backend Setup (FastAPI & Database)

### 1. Create and Activate Virtual Environment
Open a terminal in the `backend/` directory:
```bash
cd backend
python -m venv .venv
```

Activate the environment based on your operating system:
* **Windows (PowerShell)**:
  ```powershell
  .venv\Scripts\Activate.ps1
  ```
* **macOS / Linux**:
  ```bash
  source .venv/bin/activate
  ```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Setup Configuration
Copy the sample environment file and configure variables:
```bash
cp .env.example .env
```
Ensure `DATABASE_URL` is set:
* For SQLite local dev: `sqlite:///flowspace.db`
* For production PostgreSQL: `postgresql://user:pass@localhost:5432/dbname`

### 4. Run Migrations & Seed Data
Initialize your local database schemas using Alembic migrations:
```bash
alembic upgrade head
```
*Note: Roles, default materials, catalog furniture assets, and design rules are automatically seeded into the database on the initial server startup.*

### 5. Launch FastAPI Dev Server
```bash
python main.py
```
The API is now running locally at **`http://localhost:8000`**. You can inspect the interactive OpenAPI specifications at `http://localhost:8000/docs`.

---

## 📱 Frontend Setup (Flutter)

### 1. Fetch Dart Packages
Open a terminal in the `frontend/` directory:
```bash
cd frontend
flutter pub get
```

### 2. Prepare Web Assets
To run the Flutter web designer, build the web assets once to make sure the Three.js sandbox files are cached correctly in the browser:
```bash
flutter build web
```

### 3. Launch Development Client
Run the client on Google Chrome (or your native platform):
```bash
flutter run -d chrome
```

---

## 🐳 Docker Compose Alternative (Single Command Setup)
If you prefer running containerized setups, you can boot the entire stack (PostgreSQL, Backend API, Nginx Reverse Proxy serving Flutter Web) with one command.

### Local Development Stack (Hot-Reloading Enabled)
```bash
# From the root workspace directory:
docker-compose -f docker-compose.dev.yml up --build
```
Open **`http://localhost:8080`** in your browser. All code edits to `backend/` will hot-reload automatically.

### Production Stack (Gunicorn & HTTPS Enabled)
```bash
# From the root workspace directory:
docker-compose up --build -d
```
Open **`https://localhost`** in your browser. (Accept the self-signed certificate warning for local testing).

---

## 🧪 Verification
Confirm that your local environment is correctly configured by running the test suites.

### Run Backend Unit Tests:
```powershell
# From the backend directory
$env:PYTHONPATH="."
pytest tests
```

### Run Frontend Widget Tests:
```bash
# From the frontend directory
flutter test
```
