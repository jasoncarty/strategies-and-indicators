"""
Example test demonstrating the new testing framework
This shows how to use the new configuration-based testing system
"""

import pytest
import requests

def test_config_loading(test_config):
    """Test that configuration is loaded correctly"""
    assert test_config is not None
    assert test_config.environment == "testing"
    assert test_config.database.name == "test_breakout_analytics"
    assert test_config.analytics.port == 5002
    assert test_config.ml_service.port == 5004

def test_database_connection(test_db_connection):
    """Test database connection"""
    with test_db_connection.cursor() as cursor:
        cursor.execute("SELECT 1 as test_value")
        result = cursor.fetchone()
        assert result['test_value'] == 1

def test_analytics_service_health(test_analytics_client):
    """Test analytics service health endpoint"""
    response = test_analytics_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data

def test_ml_service_health(test_ml_client):
    """Test ML service health endpoint"""
    response = test_ml_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data

def test_service_urls(test_services):
    """Test that service URLs are correctly configured"""
    assert "analytics" in test_services
    assert "ml_service" in test_services

    analytics_url = test_services["analytics"]
    ml_url = test_services["ml_service"]

    assert analytics_url == "http://127.0.0.1:5002"
    assert ml_url == "http://127.0.0.1:5004"
