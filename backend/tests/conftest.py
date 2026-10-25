import pytest
from app.dependencies import get_db
from app.main import app

def pytest_runtest_setup(item):
    # Dynamically bind get_db override to the currently executing module's override_get_db
    if hasattr(item.module, "override_get_db"):
        app.dependency_overrides[get_db] = item.module.override_get_db

def pytest_runtest_teardown(item, nextitem):
    # Safely clear the dependency overrides after each test
    if get_db in app.dependency_overrides:
        del app.dependency_overrides[get_db]
