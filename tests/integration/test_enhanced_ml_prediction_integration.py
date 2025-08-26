#!/usr/bin/env python3
"""
Integration tests for enhanced ML prediction service
Tests the complete workflow from feature input to trade decision output using REAL HTTP API calls
"""

import pytest
import sys
import time
import requests
import json
from pathlib import Path
import os

class TestEnhancedMLPredictionIntegration:
    """Integration tests for enhanced ML prediction service using REAL HTTP API calls"""

    @pytest.fixture
    def ml_service_url(self):
        """Get ML service URL from environment or use default"""
        # Use the port from docker.test.env (5009) or default to 5003
        port = os.getenv("ML_SERVICE_PORT", "5003")
        base_url = os.getenv("HOST_URL", "http://localhost")
        url = f"{base_url}:{port}"
        print(f"🔗 ML Service URL: {url}")
        return url

    @pytest.fixture
    def analytics_service_url(self):
        """Get analytics service URL from environment or use default"""
        # Use the port from docker.test.env if available
        port = os.getenv("ANALYTICS_PORT", "5001")
        base_url = os.getenv("HOST_URL", "http://localhost")
        url = f"{base_url}:{port}"
        print(f"🔗 Analytics service URL: {url}")
        return url

    @pytest.fixture
    def sample_features(self):
        """Sample features for testing - using realistic values"""
        return {
            "rsi": 65.5,
            "stoch_main": 75.2,
            "macd_main": 0.0012,
            "bb_upper": 1.0850,
            "bb_lower": 1.0820,
            "current_price": 1.0835,
            "atr": 0.0015,
            "account_balance": 10000,
            "risk_per_pip": 1.0
        }

    def test_ml_service_health_endpoint(self, ml_service_url):
        """Test that ML service health endpoint is accessible"""
        try:
            response = requests.get(f"{ml_service_url}/health", timeout=10)
            assert response.status_code == 200, f"ML service returned {response.status_code}"

            health_data = response.json()
            assert health_data["status"] == "healthy", f"ML service not healthy: {health_data}"

            print(f"✅ ML service health: {health_data}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_models_endpoint(self, ml_service_url):
        """Test that ML service models endpoint returns available models"""
        try:
            response = requests.get(f"{ml_service_url}/models", timeout=10)
            assert response.status_code == 200, f"ML service returned {response.status_code}"

            models_data = response.json()
            assert "models" in models_data, "No models data in response"
            assert len(models_data["models"]) > 0, "No models available"

            print(f"✅ Available models: {len(models_data['models'])}")
            print(f"   Sample models: {list(models_data['models'].keys())[:5]}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_predict_endpoint(self, ml_service_url, sample_features):
        """Test ML service predict endpoint with REAL HTTP call"""
        try:
            # Prepare request data
            request_data = {
                "strategy": "ML_Testing_EA",
                "symbol": "EURUSD+",
                "timeframe": "M15",
                "features": sample_features,
                "direction": "buy",
                "enhanced": True
            }

            # Make HTTP POST request to predict endpoint
            response = requests.post(
                f"{ml_service_url}/predict",
                json=request_data,
                timeout=30
            )

            assert response.status_code == 200, f"Predict endpoint returned {response.status_code}"

            result = response.json()
            assert result["status"] == "success", f"Prediction failed: {result.get('message', 'Unknown error')}"
            assert "prediction" in result
            assert "metadata" in result

            # Verify prediction data
            prediction = result["prediction"]
            assert prediction["direction"] == "buy"
            assert prediction["strategy"] == "ML_Testing_EA"
            assert prediction["symbol"] == "EURUSD+"
            assert prediction["timeframe"] == "M15"
            assert "confidence" in prediction
            assert "probability" in prediction
            assert "model_key" in prediction

            print(f"✅ Prediction successful: {result}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_trade_decision_endpoint(self, ml_service_url, sample_features):
        """Test ML service trade decision endpoint with REAL HTTP call"""
        try:
            # Prepare request data
            request_data = {
                "strategy": "ML_Testing_EA",
                "symbol": "GBPUSD+",
                "timeframe": "H1",
                "features": sample_features,
                "direction": "sell",
                "enhanced": True
            }

            # Make HTTP POST request to trade_decision endpoint
            response = requests.post(
                f"{ml_service_url}/trade_decision",
                json=request_data,
                timeout=30
            )

            assert response.status_code == 200, f"Trade decision endpoint returned {response.status_code}"

            result = response.json()
            assert result["status"] == "success", f"Trade decision failed: {result.get('message', 'Unknown error')}"
            assert "prediction" in result
            assert "metadata" in result

            # Verify prediction data
            prediction = result["prediction"]
            assert prediction["direction"] == "sell"
            assert prediction["strategy"] == "ML_Testing_EA"
            assert prediction["symbol"] == "GBPUSD+"
            assert prediction["timeframe"] == "H1"
            assert "confidence_threshold" in result
            assert "model_health" in result
            assert "should_trade" in result
            assert "trade_parameters" in result

            print(f"✅ Trade decision successful: {result}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_bulk_predict_endpoint(self, ml_service_url):
        """Test ML service bulk predict endpoint with REAL HTTP call"""
        try:
            # Prepare bulk request data
            request_data = {
                "requests": [
                    {
                        "strategy": "ML_Testing_EA",
                        "symbol": "EURUSD+",
                        "timeframe": "M15",
                        "features": {
                            "rsi": 65.5,
                            "current_price": 1.0835,
                            "atr": 0.0015
                        },
                        "direction": "buy"
                    },
                    {
                        "strategy": "ML_Testing_EA",
                        "symbol": "GBPUSD+",
                        "timeframe": "H1",
                        "features": {
                            "rsi": 35.2,
                            "current_price": 1.2650,
                            "atr": 0.0020
                        },
                        "direction": "sell"
                    }
                ]
            }

            # Make HTTP POST request to bulk_predict endpoint
            response = requests.post(
                f"{ml_service_url}/bulk_predict",
                json=request_data,
                timeout=60
            )

            assert response.status_code == 200, f"Bulk predict endpoint returned {response.status_code}"

            result = response.json()
            assert result["status"] == "success", f"Bulk prediction failed: {result.get('message', 'Unknown error')}"
            assert "results" in result
            assert "total_requests" in result
            assert result["total_requests"] == 2

            # Verify the response structure
            print(f"Bulk prediction response: {result}")

            print(f"✅ Bulk prediction successful: {result['total_requests']} requests processed")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_status_endpoint(self, ml_service_url):
        """Test ML service status endpoint"""
        try:
            response = requests.get(f"{ml_service_url}/status", timeout=10)
            assert response.status_code == 200, f"Status endpoint returned {response.status_code}"

            status_data = response.json()
            assert "status" in status_data
            assert "models_loaded" in status_data
            assert "uptime" in status_data

            print(f"✅ Service status: {status_data}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_performance_endpoint(self, ml_service_url):
        """Test ML service performance endpoint"""
        try:
            response = requests.get(f"{ml_service_url}/performance", timeout=10)
            assert response.status_code == 200, f"Performance endpoint returned {response.status_code}"

            performance_data = response.json()
            assert "status" in performance_data
            assert "metrics" in performance_data
            assert "total_predictions" in performance_data["metrics"]
            assert "avg_response_time_ms" in performance_data["metrics"]

            print(f"✅ Service performance: {performance_data}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_model_versions_endpoint(self, ml_service_url):
        """Test ML service model versions endpoint"""
        try:
            response = requests.get(f"{ml_service_url}/model_versions", timeout=10)
            assert response.status_code == 200, f"Model versions endpoint returned {response.status_code}"

            versions_data = response.json()
            assert "status" in versions_data
            assert "model_versions" in versions_data
            assert "total_models" in versions_data

            print(f"✅ Model versions: {versions_data['total_models']} models")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_ml_service_reload_models_endpoint(self, ml_service_url):
        """Test ML service reload models endpoint"""
        try:
            # First get current model count
            response = requests.get(f"{ml_service_url}/models", timeout=10)
            assert response.status_code == 200
            initial_models = response.json()["models"]
            initial_count = len(initial_models)

            # Reload models
            response = requests.post(f"{ml_service_url}/reload_models", timeout=30)
            assert response.status_code == 200, f"Reload models endpoint returned {response.status_code}"

            reload_data = response.json()
            assert reload_data["status"] == "success"
            assert "models_loaded" in reload_data

            # Verify models are still available
            response = requests.get(f"{ml_service_url}/models", timeout=10)
            assert response.status_code == 200
            final_models = response.json()["models"]
            final_count = len(final_models)

            assert final_count > 0, "No models after reload"
            print(f"✅ Models reloaded: {initial_count} -> {final_count}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")

    def test_analytics_service_integration(self, analytics_service_url):
        """Test that analytics service is accessible (for ML service integration)"""
        try:
            response = requests.get(f"{analytics_service_url}/health", timeout=10)
            assert response.status_code == 200, f"Analytics service returned {response.status_code}"

            health_data = response.json()
            assert health_data["status"] == "healthy", f"Analytics service not healthy: {health_data}"

            print(f"✅ Analytics service health: {health_data}")

        except requests.exceptions.RequestException as e:
            pytest.skip(f"Analytics service not accessible: {e}")

    def test_end_to_end_workflow(self, ml_service_url, sample_features):
        """Test complete end-to-end workflow with REAL HTTP calls"""
        try:
            # Test multiple symbols and timeframes
            test_configs = [
                ("EURUSD+", "M15", "buy"),
                ("GBPUSD+", "H1", "sell"),
                ("USDCAD+", "H1", "buy"),
            ]

            successful_tests = 0

            for symbol, timeframe, direction in test_configs:
                try:
                    print(f"\nTesting {symbol} {timeframe} {direction}...")

                    request_data = {
                        "strategy": "ML_Testing_EA",
                        "symbol": symbol,
                        "timeframe": timeframe,
                        "features": sample_features,
                        "direction": direction,
                        "enhanced": True
                    }

                    response = requests.post(
                        f"{ml_service_url}/predict",
                        json=request_data,
                        timeout=30
                    )

                    if response.status_code == 200:
                        result = response.json()
                        if result["status"] == "success":
                            print(f"✅ {symbol} {timeframe} {direction} - SUCCESS")
                            print(f"   Confidence: {result.get('prediction', {}).get('confidence', 'N/A')}")
                            print(f"   Should trade: {result.get('should_trade', 'N/A')}")
                            print(f"   Model health: {result.get('model_health', {}).get('status', 'N/A')}")
                            successful_tests += 1
                        else:
                            print(f"❌ {symbol} {timeframe} {direction} - FAILED: {result.get('message', 'Unknown error')}")
                    else:
                        print(f"❌ {symbol} {timeframe} {direction} - HTTP {response.status_code}")

                except Exception as e:
                    print(f"❌ {symbol} {timeframe} {direction} - EXCEPTION: {e}")

            print(f"\nEnd-to-end test results: {successful_tests}/{len(test_configs)} successful")
            assert successful_tests > 0, "No end-to-end tests passed"

        except requests.exceptions.RequestException as e:
            pytest.skip(f"ML service not accessible: {e}")


def run_enhanced_ml_prediction_integration_tests():
    """Run all enhanced ML prediction integration tests"""
    print("🧪 Running Enhanced ML Prediction Integration Tests (REAL HTTP API)...")

    try:
        # Run tests
        result = pytest.main([
            __file__,
            "-v",
            "--tb=short",
            "--capture=no"
        ])

        success = result == 0
        print(f"\n{'✅ All tests passed' if success else '❌ Some tests failed'}")
        return success

    except Exception as e:
        print(f"❌ Error running tests: {e}")
        return False


if __name__ == "__main__":
    run_enhanced_ml_prediction_integration_tests()
