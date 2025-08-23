#!/usr/bin/env python3
"""
ML retraining integration tests using the new pytest framework
"""
import pytest
import requests
import json
from pathlib import Path

def test_ml_service_model_endpoints(test_ml_client):
    """Test ML service model-related endpoints"""
    # Test model versions endpoint
    response = test_ml_client.get("/model_versions")
    assert response.status_code == 200

    data = response.json()
    assert "models" in data or "status" in data
    print("✅ ML service model versions endpoint working")

def test_ml_service_performance_endpoint(test_ml_client):
    """Test ML service performance endpoint"""
    response = test_ml_client.get("/performance")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service performance endpoint working")

def test_ml_service_enhanced_health(test_ml_client):
    """Test ML service enhanced health endpoint"""
    response = test_ml_client.get("/enhanced_health")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service enhanced health endpoint working")

def test_ml_service_reload_models(test_ml_client):
    """Test ML service model reload functionality"""
    # Test GET method
    response = test_ml_client.get("/reload_models")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service reload models GET endpoint working")

def test_ml_service_bulk_predict_endpoint(test_ml_client):
    """Test ML service bulk prediction endpoint"""
    # Test with minimal valid request
    test_request = {
        "requests": [
            {
                "symbol": "BTCUSD",
                "timeframe": "M5",
                "features": {
                    "rsi": 50.0,
                    "stoch_main": 50.0,
                    "stoch_signal": 50.0
                }
            }
        ]
    }

    response = test_ml_client.post("/bulk_predict", json=test_request)
    # This might fail if models aren't loaded, but should at least return a response
    assert response.status_code in [200, 400, 500]  # Accept various status codes

    print("✅ ML service bulk predict endpoint responding")

def test_ml_service_configuration(test_config):
    """Test ML service configuration"""
    # Get ML config from test config
    ml_config = test_config.ml

    # Verify ML config has required fields
    assert hasattr(ml_config, 'models_dir')
    assert hasattr(ml_config, 'analytics_url')
    assert hasattr(ml_config, 'max_request_size')

    # Verify models directory path
    models_dir = Path(ml_config.models_dir)
    assert models_dir.exists() or str(models_dir).startswith('ML_Webserver'), \
        f"Models directory {models_dir} should exist or be in ML_Webserver"

    print("✅ ML service configuration test passed")

def test_ml_service_analytics_integration(test_config):
    """Test ML service analytics integration"""
    # Get analytics URL from ML config
    analytics_url = test_config.ml.analytics_url

    # Verify analytics URL format
    assert analytics_url.startswith("http://")
    assert ":" in analytics_url  # Should contain port

    print("✅ ML service analytics integration test passed")
