from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import settings
from core.logging.logger import logger

# Check if PostgreSQL is used
is_postgres = settings.DATABASE_URL.startswith("postgresql") or settings.DATABASE_URL.startswith("postgres")

if is_postgres:
    # Use connection pooling parameters for PostgreSQL
    engine = create_engine(
        settings.DATABASE_URL,
        pool_size=10,
        max_overflow=20,
        pool_recycle=1800,
        pool_pre_ping=True
    )
else:
    # SQLite configuration
    connect_args = {"check_same_thread": False} if settings.DATABASE_URL.startswith("sqlite") else {}
    engine = create_engine(
        settings.DATABASE_URL,
        connect_args=connect_args,
        pool_pre_ping=True
    )

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

Base = declarative_base()

def check_db_connection() -> bool:
    try:
        # Connect and execute a simple query to verify the database is active
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
            logger.info("Successfully connected to the database.")
            return True
    except Exception as e:
        logger.error(f"Failed to connect to the database: {e}")
        return False

