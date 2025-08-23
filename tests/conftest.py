"""
Pytest configuration and fixtures for the trading strategies project
Uses the new configuration system for clean, maintainable testing
"""

import os
import sys
import pytest
import pymysql
import subprocess
import time
import requests
from pathlib import Path
from typing import Dict, Any

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from config import get_config

@pytest.fixture(scope="session")
def test_config():
    """Load test configuration once for all tests"""
    try:
        from config import Config
        config = Config('testing')
        print(f"✅ Loaded test configuration: {config.environment}")
        return config
    except Exception as e:
        print(f"⚠️ Could not load test config: {e}")
        # Fallback to environment variables
        return None

@pytest.fixture(scope="session")
def test_database(test_config):
    """Create and manage test database"""
    if not test_config:
        pytest.skip("Test configuration not available")

    db_config = test_config.database
    print(f"🔧 Setting up test database: {db_config.name}")

    # Connect to MySQL server (without specifying database)
    # For Docker MySQL, we need to ensure the container is running
    print(f"🔌 Connecting to MySQL at {db_config.host}:{db_config.port}")

    try:
        connection = pymysql.connect(
            host=db_config.host,
            port=db_config.port,
            user=db_config.user,
            password=db_config.password,
            charset='utf8mb4'
        )
    except pymysql.err.OperationalError as e:
        if "Access denied" in str(e):
            print(f"❌ Access denied to MySQL. Please ensure Docker MySQL is running and test database is set up.")
            print(f"   Run: ./scripts/setup_test_env.sh")
            pytest.skip(f"MySQL access denied: {e}")
        else:
            raise

    try:
        # Drop existing test database if it exists
        with connection.cursor() as cursor:
            cursor.execute(f"DROP DATABASE IF EXISTS `{db_config.name}`")
            print(f"🗑️ Dropped existing test database: {db_config.name}")

        # Create fresh test database
        with connection.cursor() as cursor:
            cursor.execute(f"CREATE DATABASE `{db_config.name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            print(f"✅ Created fresh test database: {db_config.name}")

        # Run migrations
        print("📦 Running migrations on test database...")
        migrations_dir = Path(__file__).parent.parent / 'analytics' / 'database'
        run_migrations_script = migrations_dir / 'run_migrations.py'

        if run_migrations_script.exists():
            result = subprocess.run([
                sys.executable, str(run_migrations_script)
            ], capture_output=True, text=True, cwd=str(migrations_dir.parent),
               env={**os.environ.copy(), 'ENVIRONMENT': 'testing'})

            if result.returncode == 0:
                print("✅ Migrations completed successfully")
            else:
                print(f"⚠️ Migration output: {result.stdout}")
                print(f"⚠️ Migration errors: {result.stderr}")
        else:
            print("⚠️ Migration script not found")

        yield db_config

    finally:
        # Cleanup: drop test database
        try:
            with connection.cursor() as cursor:
                cursor.execute(f"DROP DATABASE IF EXISTS `{db_config.name}`")
                print(f"🗑️ Cleaned up test database: {db_config.name}")
        except Exception as e:
            print(f"⚠️ Could not cleanup test database: {e}")
        finally:
            connection.close()

@pytest.fixture(scope="session")
def test_services(test_config):
    """Use Docker test services instead of starting host services"""
    if not test_config:
        pytest.skip("Test configuration not available")

    # Use the Docker services that are already running
    analytics_port = test_config.get_test_analytics_port()
    ml_port = test_config.get_test_ml_port()

    services = {
        'analytics': f"http://127.0.0.1:{analytics_port}",
        'ml_service': f"http://127.0.0.1:{ml_port}"
    }

    print(f"🎯 Using Docker test services:")
    print(f"   Analytics: {services['analytics']}")
    print(f"   ML Service: {services['ml_service']}")

    # Verify services are accessible
    analytics_ready = wait_for_service(f"{services['analytics']}/health")
    ml_ready = wait_for_service(f"{services['ml_service']}/health")

    if not analytics_ready or not ml_ready:
        raise Exception("Docker test services are not accessible")

    print("✅ Docker test services are ready")
    yield services

    # No cleanup needed - Docker services are managed externally
    print("ℹ️ Docker test services will continue running (use ./scripts/cleanup_test_env.sh to stop)")

def wait_for_service(url: str, timeout: int = 30) -> bool:
    """Wait for a service to be ready"""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"✅ Service ready: {url}")
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(2)
    print(f"❌ Service not ready after {timeout}s: {url}")
    return False

@pytest.fixture
def test_db_connection(test_database):
    """Get database connection for individual tests"""
    connection = pymysql.connect(
        host=test_database.host,
        port=test_database.port,
        user=test_database.user,
        password=test_database.password,
        database=test_database.name,
        charset='utf8mb4'
    )

    yield connection

    connection.close()

@pytest.fixture
def test_analytics_client(test_services):
    """Get requests session for testing analytics endpoints"""
    import requests

    session = requests.Session()
    session.base_url = test_services['analytics']

    yield session

    session.close()

@pytest.fixture
def test_ml_client(test_services):
    """Get requests session for testing ML endpoints"""
    import requests

    session = requests.Session()
    session.base_url = test_services['ml_service']

    yield session

    session.close()
