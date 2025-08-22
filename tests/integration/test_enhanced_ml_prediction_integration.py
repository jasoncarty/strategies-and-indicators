#!/usr/bin/env python3
"""
Integration tests for enhanced ML prediction service
Tests the complete workflow from feature input to trade decision output
"""

import pytest
import sys
import time
import requests
import json
from pathlib import Path
from unittest.mock import Mock, patch

# Add ML_Webserver to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "ML_Webserver"))

from ml_prediction_service import MLPredictionService


class TestEnhancedMLPredictionIntegration:
    """Integration tests for enhanced ML prediction service"""

    @pytest.fixture
    def ml_service(self):
        """Create ML prediction service instance"""
        service = MLPredictionService(models_dir="test_models")

        # Mock models and scalers for testing
        service.models = {
            "buy_EURUSD+_PERIOD_M5": Mock(),
            "sell_EURUSD+_PERIOD_M5": Mock(),
            "combined_EURUSD+_PERIOD_M5": Mock()
        }

        service.scalers = {
            "buy_EURUSD+_PERIOD_M5": Mock(),
            "sell_EURUSD+_PERIOD_M5": Mock(),
            "combined_EURUSD+_PERIOD_M5": Mock()
        }

        service.feature_names = {
            "buy_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main", "bb_upper", "bb_lower"],
            "sell_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main", "bb_upper", "bb_lower"],
            "combined_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main", "bb_upper", "bb_lower"]
        }

        service.model_metadata = {
            "buy_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"},
            "sell_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"},
            "combined_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"}
        }

        return service

    @pytest.fixture
    def sample_features(self):
        """Sample features for testing"""
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

    def test_enhanced_prediction_workflow(self, ml_service, sample_features):
        """Test complete enhanced prediction workflow"""
        # Mock model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.2, 0.8]]  # High confidence
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Mock health check
        with patch.object(ml_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "healthy", "health_score": 85}, 0.3)

            # Test enhanced prediction
            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=sample_features,
                direction="buy",
                enhanced=True
            )

            # Verify enhanced response structure
            assert result["status"] == "success"
            assert "should_trade" in result
            assert "confidence_threshold" in result
            assert "model_health" in result
            assert "trade_parameters" in result
            assert "prediction" in result

            # Verify trade decision
            assert result["should_trade"] is True  # High confidence should exceed healthy threshold
            assert result["confidence_threshold"] == 0.3
            assert result["model_health"]["status"] == "healthy"

            # Verify trade parameters
            trade_params = result["trade_parameters"]
            assert trade_params["entry_price"] == 1.0835
            assert trade_params["stop_loss"] > 0
            assert trade_params["take_profit"] > 0
            assert trade_params["lot_size"] > 0

    def test_legacy_prediction_workflow(self, ml_service, sample_features):
        """Test legacy prediction workflow for backward compatibility"""
        # Mock model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.3, 0.7]]
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Test legacy prediction
        result = ml_service.get_prediction(
            strategy="ML_Testing_EA",
            symbol="EURUSD+",
            timeframe="M5",
            features=sample_features,
            direction="buy",
            enhanced=False
        )

        # Verify legacy response structure (no enhanced fields)
        assert result["status"] == "success"
        assert "should_trade" not in result
        assert "confidence_threshold" not in result
        assert "model_health" not in result
        assert "trade_parameters" not in result

        # Verify legacy fields are present
        assert "prediction" in result
        assert "metadata" in result

        # Verify prediction data
        prediction = result["prediction"]
        assert prediction["direction"] == "buy"
        assert prediction["strategy"] == "ML_Testing_EA"
        assert prediction["symbol"] == "EURUSD+"
        assert prediction["timeframe"] == "M5"

    def test_health_based_thresholds(self, ml_service, sample_features):
        """Test different confidence thresholds based on model health"""
        # Mock model prediction with medium confidence
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.4, 0.6]]  # Medium confidence (0.2)
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Test critical model (threshold 0.7)
        with patch.object(ml_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "critical", "health_score": 30}, 0.7)

            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=sample_features,
                direction="buy",
                enhanced=True
            )

            # Medium confidence (0.2) should not exceed critical threshold (0.7)
            assert result["should_trade"] is False
            assert result["confidence_threshold"] == 0.7

        # Test healthy model (threshold 0.3)
        with patch.object(ml_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "healthy", "health_score": 85}, 0.3)

            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=sample_features,
                direction="buy",
                enhanced=True
            )

            # Medium confidence (0.2) should not exceed healthy threshold (0.3)
            assert result["should_trade"] is False
            assert result["confidence_threshold"] == 0.3

    def test_trade_parameter_calculation(self, ml_service, sample_features):
        """Test trade parameter calculation for different scenarios"""
        # Test the _calculate_trade_parameters method directly to isolate the issue

        # Test BUY direction
        trade_params_buy = ml_service._calculate_trade_parameters("EURUSD+", "buy", sample_features)
        assert trade_params_buy["entry_price"] == 1.0835
        assert trade_params_buy["stop_loss"] < trade_params_buy["entry_price"]  # Below for BUY
        assert trade_params_buy["take_profit"] > trade_params_buy["entry_price"]  # Above for BUY
        assert trade_params_buy["lot_size"] > 0

        # Test SELL direction
        trade_params_sell = ml_service._calculate_trade_parameters("EURUSD+", "sell", sample_features)
        assert trade_params_sell["entry_price"] == 1.0835
        assert trade_params_sell["stop_loss"] > trade_params_sell["entry_price"]  # Above for SELL
        assert trade_params_sell["take_profit"] < trade_params_sell["entry_price"]  # Below for SELL
        assert trade_params_sell["lot_size"] > 0

        # Test edge cases
        minimal_features = {"current_price": 1.0835, "atr": 0.0015, "account_balance": 10000, "risk_per_pip": 1.0}
        trade_params_minimal = ml_service._calculate_trade_parameters("EURUSD+", "buy", minimal_features)
        assert trade_params_minimal["entry_price"] == 1.0835

        # Test with missing current_price (should use defaults)
        incomplete_features = {"atr": 0.0015, "account_balance": 10000, "risk_per_pip": 1.0}
        trade_params_incomplete = ml_service._calculate_trade_parameters("EURUSD+", "buy", incomplete_features)
        assert trade_params_incomplete["entry_price"] == 0.0  # Should use default

    def test_feature_handling_and_engineering(self, ml_service):
        """Test feature handling and engineering integration"""
        # Test with minimal features
        minimal_features = {
            "rsi": 65.5,
            "current_price": 1.0835,
            "atr": 0.0015
        }

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Mock model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.3, 0.7]]
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock health check
        with patch.object(ml_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "healthy", "health_score": 85}, 0.3)

            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=minimal_features,
                direction="buy",
                enhanced=True
            )

            # Should still work with minimal features
            assert result["status"] == "success"
            assert "trade_parameters" in result

    def test_error_handling_and_fallbacks(self, ml_service, sample_features):
        """Test error handling and fallback mechanisms"""
        # Mock feature preparation failure
        ml_service._prepare_features = Mock(return_value=None)

        result = ml_service.get_prediction(
            strategy="ML_Testing_EA",
            symbol="EURUSD+",
            timeframe="M5",
            features=sample_features,
            direction="buy",
            enhanced=True
        )

        # Should handle feature preparation failure gracefully
        assert result["status"] == "error"
        assert "Feature preparation failed" in result["message"]

        # Mock model not found
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])
        ml_service._select_model = Mock(return_value=None)

        result = ml_service.get_prediction(
            strategy="ML_Testing_EA",
            symbol="EURUSD+",
            timeframe="M5",
            features=sample_features,
            direction="buy",
            enhanced=True
        )

        # Should handle missing model gracefully
        assert result["status"] == "error"
        assert "No suitable model found" in result["message"]

    def test_analytics_service_integration(self, ml_service, sample_features):
        """Test integration with analytics service for model health"""
        # Mock model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.3, 0.7]]
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Test analytics service connection
        with patch('requests.get') as mock_get:
            # Mock successful analytics response
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {
                "models": [
                    {
                        "model_key": "buy_EURUSD+_PERIOD_M5",
                        "status": "warning",
                        "health_score": 55
                    }
                ]
            }
            mock_get.return_value = mock_response

            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=sample_features,
                direction="buy",
                enhanced=True
            )

            # Should use analytics service data
            assert result["model_health"]["status"] == "warning"
            assert result["confidence_threshold"] == 0.6  # Warning threshold

            # Test analytics service failure
            mock_get.side_effect = Exception("Connection failed")

            result = ml_service.get_prediction(
                strategy="ML_Testing_EA",
                symbol="EURUSD+",
                timeframe="M5",
                features=sample_features,
                direction="buy",
                enhanced=True
            )

            # Should fallback to default values
            assert result["model_health"]["status"] == "unknown"
            assert result["confidence_threshold"] == 0.5  # Default threshold

    def test_model_selection_logic(self, ml_service, sample_features):
        """Test model selection logic for different scenarios"""
        # Clear any existing models to ensure clean state
        ml_service.models.clear()

        # Mock feature preparation
        ml_service._prepare_features = Mock(return_value=[[0.5, 0.6, 0.7, 0.8, 0.9]])

        # Mock model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = [[0.3, 0.7]]

        # Test exact direction match
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        result = ml_service._select_model("EURUSD+", "M5", "buy")
        assert result == "buy_EURUSD+_PERIOD_M5"

        # Test combined model fallback
        del ml_service.models["buy_EURUSD+_PERIOD_M5"]  # Remove the buy model
        ml_service.models["combined_EURUSD+_PERIOD_M5"] = mock_model

        result = ml_service._select_model("EURUSD+", "M5", "buy")
        assert result == "combined_EURUSD+_PERIOD_M5"

        # Test buy model fallback
        del ml_service.models["combined_EURUSD+_PERIOD_M5"]  # Remove the combined model
        ml_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        result = ml_service._select_model("EURUSD+", "M5", "sell")
        assert result == "buy_EURUSD+_PERIOD_M5"

        # Test no model found
        del ml_service.models["buy_EURUSD+_PERIOD_M5"]  # Remove the model completely

        result = ml_service._select_model("EURUSD+", "M5", "buy")
        assert result is None


def run_enhanced_ml_prediction_integration_tests():
    """Run all enhanced ML prediction integration tests"""
    print("🧪 Running Enhanced ML Prediction Integration Tests...")

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
