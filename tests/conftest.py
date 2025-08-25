"""
Pytest configuration and fixtures for the trading strategies project
Uses Docker services for clean, maintainable integration testing
"""

import os
import sys
import pytest
import requests
import time
from pathlib import Path
from typing import Dict, Any

def load_test_environment():
    """Load test environment variables from docker.test.env"""
    try:
        from dotenv import load_dotenv
        project_root = Path(__file__).parent.parent
        test_env_file = project_root / "docker.test.env"

        if test_env_file.exists():
            load_dotenv(test_env_file)
            print(f"✅ Loaded test environment from {test_env_file}")
            print(f"   Analytics Port: {os.getenv('ANALYTICS_PORT', '5001')}")
            print(f"   ML Service Port: {os.getenv('ML_SERVICE_PORT', '5003')}")
            print(f"   Database Port: {os.getenv('DB_PORT', '3306')}")
            print(f"   Environment: {os.getenv('ENVIRONMENT', 'testing')}")
        else:
            print(f"⚠️  {test_env_file} not found, using defaults")
    except ImportError:
        print("⚠️  python-dotenv not installed, skipping .env file loading")
    except Exception as e:
        print(f"⚠️  Error loading .env file: {e}")

# Load test environment variables at module import
load_test_environment()

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

@pytest.fixture(scope="session")
def test_services():
    """Get Docker test service URLs from environment variables"""
    analytics_url = os.getenv("ANALYTICS_EXTERNAL_URL", "http://localhost:5001")
    ml_service_url = os.getenv("ML_SERVICE_EXTERNAL_URL", "http://localhost:5003")

    services = {
        'analytics': analytics_url,
        'ml_service': ml_service_url
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
    print("ℹ️ Docker test services will continue running")

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
def test_analytics_client(test_services):
    """Get requests session for testing analytics endpoints"""
    import requests

    # Create a session with the base URL
    base_url = test_services['analytics']

    # Create a custom session that prepends the base URL
    class TestClient:
        def __init__(self, base_url):
            self.base_url = base_url
            self.session = requests.Session()

        def get(self, path):
            url = f"{self.base_url}{path}"
            return self.session.get(url)

        def post(self, path, **kwargs):
            url = f"{self.base_url}{path}"
            return self.session.post(url, **kwargs)

    client = TestClient(base_url)
    yield client
    client.session.close()

@pytest.fixture
def test_ml_client(test_services):
    """Get requests session for testing ML endpoints"""
    import requests

    # Create a session with the base URL
    base_url = test_services['ml_service']

    # Create a custom session that prepends the base URL
    class TestClient:
        def __init__(self, base_url):
            self.base_url = base_url
            self.session = requests.Session()

        def get(self, path):
            url = f"{self.base_url}{path}"
            return self.session.get(url)

        def post(self, path, **kwargs):
            url = f"{self.base_url}{path}"
            return self.session.post(url, **kwargs)

    client = TestClient(base_url)
    yield client
    client.session.close()

@pytest.fixture
def test_database_config():
    """Get test database configuration from environment variables"""
    # For tests running on host machine, use localhost instead of 'mysql'
    db_host = os.getenv('DB_HOST', 'localhost')
    if db_host == 'mysql':
        db_host = 'localhost'  # Use localhost for host machine tests

    return {
        'host': db_host,
        'port': int(os.getenv('DB_PORT', '3306')),
        'name': os.getenv('DB_NAME', 'test_breakout_analytics'),
        'user': os.getenv('DB_USER', 'test_user'),
        'password': os.getenv('DB_PASSWORD', 'test_password_2024')
    }
