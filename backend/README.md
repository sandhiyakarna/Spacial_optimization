# FlowSpace Backend

The backend for FlowSpace is built with **FastAPI**, **SQLAlchemy** ORM, and **Alembic** migrations. It exposes REST APIs for space planning, optimization, and analytics scoring.

## Architecture

We use a **Feature-First** structure where features are organized by business domain:
* `app/`: Application-wide setup, settings loading (`config.py`), dependencies (`dependencies.py`), and FastAPI instantiation.
* `core/`: Core cross-cutting concerns:
  * `database/`: Session database manager.
  * `security/`: JWT generation and bcrypt passwords.
  * `logging/`: Structured console log handlers.
* `features/`: The feature modules containing api routers, schemas, services, and models.

## How to Run

1. Setup virtual environment and activate:
   ```bash
   python -m venv .venv
   # Windows (PS):
   .venv\Scripts\Activate.ps1
   # macOS/Linux:
   source .venv/bin/activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Configure environment variables in `.env`.

4. Start development server:
   ```bash
   python main.py
   ```

5. Run test suite:
   ```bash
   $env:PYTHONPATH="."
   pytest tests
   ```
