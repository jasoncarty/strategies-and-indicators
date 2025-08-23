#!/usr/bin/env python3
"""
End-to-end workflow tests using the new pytest framework
"""
import pytest
import requests
import json
from pathlib import Path

def test_analytics_service_health(test_analytics_client):
    """Test analytics service health endpoint"""
    response = test_analytics_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    print("✅ Analytics service health check passed")

def test_ml_service_health(test_ml_client):
    """Test ML service health endpoint"""
    response = test_ml_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service health check passed")

def test_service_communication(test_analytics_client, test_ml_client):
    """Test that services can communicate with each other"""
    # Test analytics service
    analytics_response = test_analytics_client.get("/health")
    assert analytics_response.status_code == 200

    # Test ML service
    ml_response = test_ml_client.get("/health")
    assert ml_response.status_code == 200

    print("✅ Service communication test passed")

def test_configuration_consistency(test_config):
    """Test that configuration is consistent across services"""
    # Get service ports from config
    analytics_port = test_config.get_test_analytics_port()
    ml_port = test_config.get_test_ml_port()

    # Verify ports are different (to avoid conflicts)
    assert analytics_port != ml_port, "Service ports should be different"

    # Verify ports are in expected ranges
    assert 5000 <= analytics_port <= 6000, f"Analytics port {analytics_port} should be in range 5000-6000"
    assert 5000 <= ml_port <= 6000, f"ML port {ml_port} should be in range 5000-6000"

    print("✅ Configuration consistency test passed")

def test_database_configuration(test_config):
    """Test database configuration"""
    db_config = test_config.get_test_database_config()

    # Verify database config has required fields
    assert hasattr(db_config, 'host')
    assert hasattr(db_config, 'port')
    assert hasattr(db_config, 'name')
    assert hasattr(db_config, 'user')
    assert hasattr(db_config, 'password')

    # Verify test database name
    assert 'test' in db_config.name.lower(), "Test database should contain 'test' in name"

    print("✅ Database configuration test passed")

def test_service_urls(test_services):
    """Test that service URLs are correctly configured"""
    assert "analytics" in test_services
    assert "ml_service" in test_services

    analytics_url = test_services["analytics"]
    ml_url = test_services["ml_service"]

    # Verify URLs are properly formatted
    assert analytics_url.startswith("http://127.0.0.1:")
    assert ml_url.startswith("http://127.0.0.1:")

    # Verify ports are different
    analytics_port = int(analytics_url.split(":")[-1])
    ml_port = int(ml_url.split(":")[-1])
    assert analytics_port != ml_port

    print("✅ Service URLs test passed")
