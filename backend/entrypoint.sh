#!/bin/sh
set -e

# Wait for database to be ready
echo "Waiting for database..."
python -c "
import time
import sys
from sqlalchemy import create_engine, text
from app.config import settings

# If not postgres, we don't need to wait
if not settings.DATABASE_URL.startswith('postgresql') and not settings.DATABASE_URL.startswith('postgres'):
    print('SQLite or other database detected. Skipping database wait.')
    sys.exit(0)

print(f'PostgreSQL database detected. Testing connection...')
for i in range(30):
    try:
        engine = create_engine(settings.DATABASE_URL)
        with engine.connect() as conn:
            conn.execute(text('SELECT 1'))
        print('Database connection successful!')
        sys.exit(0)
    except Exception as e:
        print(f'Waiting for database to be ready... (attempt {i+1}/30). Error: {e}')
        time.sleep(2)
print('Database connection timed out.')
sys.exit(1)
"

# Run migrations
echo "Running database migrations..."
alembic upgrade head

# Start application
echo "Starting FastAPI server..."
if [ "$ENVIRONMENT" = "production" ]; then
    echo "Running in production mode with Gunicorn..."
    exec gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 --access-logfile - --error-logfile -
else
    echo "Running in development mode..."
    exec python main.py
fi
