#!/usr/bin/env python3
"""
Simple configuration test that doesn't require database access
"""
import pytest
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

def test_config_loading():
    """Test that configuration can be loaded"""
    try:
        from config import Config
        config = Config('testing')

        # Basic assertions
        assert config is not None
        assert config.environment == "testing"
        assert config.database.name == "test_breakout_analytics"
        assert config.get_test_analytics_port() == 5002
        assert config.get_test_ml_port() == 5004

        print("✅ Configuration loaded successfully")
        print(f"   Environment: {config.environment}")
        print(f"   Database: {config.database.name}")
        print(f"   Analytics Port: {config.get_test_analytics_port()}")
        print(f"   ML Service Port: {config.get_test_ml_port()}")

    except Exception as e:
        pytest.fail(f"Failed to load configuration: {e}")

def test_config_structure():
    """Test that configuration has expected structure"""
    from config import Config
    config = Config('testing')

    # Check required attributes exist
    assert hasattr(config, 'database')
    assert hasattr(config, 'analytics')
    assert hasattr(config, 'ml_service')
    assert hasattr(config, 'environment')

    # Check database config
    assert hasattr(config.database, 'host')
    assert hasattr(config.database, 'port')
    assert hasattr(config.database, 'name')
    assert hasattr(config.database, 'user')
    assert hasattr(config.database, 'password')

    # Check service configs
    assert hasattr(config.analytics, 'host')
    assert hasattr(config.analytics, 'port')
    assert hasattr(config.ml_service, 'host')
    assert hasattr(config.ml_service, 'port')

    print("✅ Configuration structure is correct")
