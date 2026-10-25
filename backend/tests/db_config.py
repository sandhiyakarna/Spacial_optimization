import os
from sqlalchemy import create_engine

def get_test_engine(db_name: str):
    default_url = f"sqlite:///./{db_name}"
    url = os.getenv("TEST_DATABASE_URL", default_url)
    
    # Handle postgres scheme compatibility
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
        
    is_sqlite = url.startswith("sqlite")
    
    connect_args = {"check_same_thread": False} if is_sqlite else {}
    
    engine = create_engine(url, connect_args=connect_args)
    return engine, url
