#!/usr/bin/env python3
"""
Unit tests for enhanced ML prediction service
Tests the new trade decision functionality and health-based confidence thresholds
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import numpy as np

# Add ML_Webserver to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "ML_Webserver"))

from ml_prediction_service import MLPredictionService


class TestEnhancedPrediction:
    """Test enhanced prediction functionality"""

    @pytest.fixture
    def mock_service(self):
        """Create a mock ML prediction service"""
        service = MLPredictionService(models_dir="test_models")

        # Mock the models and scalers
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
            "buy_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main"],
            "sell_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main"],
            "combined_EURUSD+_PERIOD_M5": ["rsi", "stoch_main", "macd_main"]
        }

        service.model_metadata = {
            "buy_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"},
            "sell_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"},
            "combined_EURUSD+_PERIOD_M5": {"model_type": "gradient_boosting", "file_path": "test.pkl"}
        }

        # Create a simple mock risk manager that returns fixed values
        class MockRiskManager:
            def __init__(self):
                # Mock portfolio object with required attributes
                self.portfolio = Mock()
                self.portfolio.total_balance = 10000.0
                self.portfolio.total_equity = 10000.0
                self.portfolio.total_positions = 0
                self.portfolio.long_positions = 0
                self.portfolio.short_positions = 0
                self.portfolio.total_profit_loss = 0.0
                self.portfolio.current_drawdown_percent = 0.01
                self.portfolio.daily_loss_percent = 0.0
                self.portfolio.total_risk_percent = 0.02
                self.portfolio.positions_per_symbol = {}
                self.portfolio.total_margin = 0.0
                self.portfolio.margin_level = 0.0
                self.portfolio.sharpe_ratio = 0.0
                self.portfolio.calmar_ratio = 0.0
                self.portfolio.sortino_ratio = 0.0

                # Mock config object
                self.config = Mock()
                self.config.max_total_positions = 100
                self.config.max_drawdown_percent = 0.20
                self.config.max_daily_loss_percent = 0.10
                self.config.max_total_risk_percent = 0.50
                self.config.max_positions_per_symbol = 10
                self.config.risk_per_trade_percent = 0.02
                self.config.max_risk_per_trade_percent = 0.05
                self.config.risk_free_rate = 0.02

            def calculate_optimal_lot_size(self, symbol, entry_price, stop_loss, account_balance, risk_override=0.0):
                return 0.1, {'risk_amount': 10.0, 'stop_distance': 0.0015}

            def can_open_new_trade(self, symbol, lot_size, stop_loss_distance, direction):
                return True, {'status': 'approved'}

            def get_risk_status(self):
                return {
                    'status': 'healthy',
                    'portfolio': {
                        'total_risk_percent': 0.02,
                        'current_drawdown_percent': 0.01
                    }
                }

        service.risk_manager = MockRiskManager()

        return service

    @pytest.fixture
    def sample_features(self):
        """Sample features for testing"""
        return {
            "rsi": 65.5,
            "stoch_main": 75.2,
            "macd_main": 0.0012,
            "current_price": 1.0835,
            "atr": 0.0015,
            "account_balance": 10000,
            "risk_per_pip": 1.0
        }

    def test_get_model_health_and_threshold_critical(self, mock_service):
        """Test confidence threshold for critical models"""
        with patch('requests.get') as mock_get:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {
                "models": [
                    {
                        "model_key": "buy_EURUSD+_PERIOD_M5",
                        "status": "critical",
                        "health_score": 30
                    }
                ]
            }
            mock_get.return_value = mock_response

            health_data, threshold = mock_service._get_model_health_and_threshold("buy_EURUSD+_PERIOD_M5")

            assert health_data["status"] == "critical"
            assert threshold == 0.5

    def test_get_model_health_and_threshold_warning(self, mock_service):
        """Test confidence threshold for warning models"""
        with patch('requests.get') as mock_get:
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

            health_data, threshold = mock_service._get_model_health_and_threshold("buy_EURUSD+_PERIOD_M5")

            assert health_data["status"] == "warning"
            assert threshold == 0.4

    def test_get_model_health_and_threshold_healthy(self, mock_service):
        """Test confidence threshold for healthy models"""
        with patch('requests.get') as mock_get:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {
                "models": [
                    {
                        "model_key": "buy_EURUSD+_PERIOD_M5",
                        "status": "healthy",
                        "health_score": 85
                    }
                ]
            }
            mock_get.return_value = mock_response

            health_data, threshold = mock_service._get_model_health_and_threshold("buy_EURUSD+_PERIOD_M5")

            assert health_data["status"] == "healthy"
            assert threshold == 0.3

    def test_get_model_health_and_threshold_fallback(self, mock_service):
        """Test fallback when analytics service is unavailable"""
        with patch('requests.get') as mock_get:
            mock_get.side_effect = Exception("Connection failed")

            health_data, threshold = mock_service._get_model_health_and_threshold("buy_EURUSD+_PERIOD_M5")

            assert health_data["status"] == "unknown"
            assert threshold == 0.5

    def test_calculate_trade_parameters_buy(self, mock_service):
        """Test trade parameter calculation for BUY trades"""
        features = {
            "current_price": 1.0835,
            "atr": 0.0015,
            "account_balance": 10000,
            "risk_per_pip": 1.0
        }

        params = mock_service._calculate_trade_parameters("EURUSD+", "BUY", features)

        assert params["entry_price"] == 1.0835
        assert params["stop_loss"] < params["entry_price"]  # Below entry for BUY
        assert params["take_profit"] > params["entry_price"]  # Above entry for BUY
        assert 0.01 <= params["lot_size"] <= 10.0

    def test_calculate_trade_parameters_sell(self, mock_service):
        """Test trade parameter calculation for SELL trades"""
        features = {
            "current_price": 1.0835,
            "atr": 0.0015,
            "account_balance": 10000,
            "risk_per_pip": 1.0
        }

        params = mock_service._calculate_trade_parameters("EURUSD+", "SELL", features)

        assert params["entry_price"] == 1.0835
        assert params["stop_loss"] > params["entry_price"]  # Above entry for SELL
        assert params["take_profit"] < params["entry_price"]  # Below entry for SELL
        assert 0.01 <= params["lot_size"] <= 10.0

    def test_calculate_trade_parameters_no_price(self, mock_service):
        """Test trade parameter calculation with no current price"""
        features = {
            "atr": 0.0015,
            "account_balance": 10000,
            "risk_per_pip": 1.0
        }

        params = mock_service._calculate_trade_parameters("EURUSD+", "BUY", features)

        assert params["entry_price"] == 0.0
        assert params["stop_loss"] == 0.0
        assert params["take_profit"] == 0.0
        assert params["lot_size"] == 0.1

    def test_legacy_prediction_response(self, mock_service):
        """Test that legacy prediction response format is maintained"""
        # Mock the model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = np.array([[0.3, 0.7]])
        mock_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        mock_service._prepare_features = Mock(return_value=np.array([[0.5, 0.6, 0.7]]))

        result = mock_service.get_prediction(
            strategy="test",
            symbol="EURUSD+",
            timeframe="M5",
            features={"rsi": 65.5},
            direction="buy",
            enhanced=False
        )

        # Should not contain enhanced fields
        assert "should_trade" not in result
        assert "confidence_threshold" not in result
        assert "model_health" not in result
        assert "trade_parameters" not in result

        # Should contain legacy fields
        assert "prediction" in result
        assert "metadata" in result
        assert result["status"] == "success"

    def test_enhanced_prediction_response(self, mock_service):
        """Test that enhanced prediction response includes all new fields"""
        # Mock the model prediction
        mock_model = Mock()
        mock_model.predict_proba.return_value = np.array([[0.3, 0.7]])
        mock_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        mock_service._prepare_features = Mock(return_value=np.array([[0.5, 0.6, 0.7]]))

        # Mock health check
        with patch.object(mock_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "healthy", "health_score": 85}, 0.3)

            result = mock_service.get_prediction(
                strategy="test",
                symbol="EURUSD+",
                timeframe="M5",
                features={"rsi": 65.5, "current_price": 1.0835, "atr": 0.0015},
                direction="buy",
                enhanced=True
            )

            # Should contain enhanced fields
            assert "should_trade" in result
            assert "confidence_threshold" in result
            assert "model_health" in result
            assert "trade_parameters" in result

            # Should contain legacy fields
            assert "prediction" in result
            assert "metadata" in result
            assert result["status"] == "success"

    def test_should_trade_decision_high_confidence(self, mock_service):
        """Test that high confidence predictions result in should_trade=True"""
        # Mock the model prediction with high confidence
        mock_model = Mock()
        mock_model.predict_proba.return_value = np.array([[0.1, 0.9]])  # High confidence
        mock_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        mock_service._prepare_features = Mock(return_value=np.array([[0.5, 0.6, 0.7]]))

        # Mock health check for healthy model (threshold 0.3)
        with patch.object(mock_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "healthy", "health_score": 85}, 0.3)

            result = mock_service.get_prediction(
                strategy="test",
                symbol="EURUSD+",
                timeframe="M5",
                features={"rsi": 65.5, "current_price": 1.0835, "atr": 0.0015},
                direction="buy",
                enhanced=True
            )

            # High confidence (0.8) should exceed healthy threshold (0.3)
            assert result["should_trade"] == True

    def test_should_trade_decision_low_confidence(self, mock_service):
        """Test that low confidence predictions result in should_trade=False"""
        # Mock the model prediction with low confidence
        mock_model = Mock()
        mock_model.predict_proba.return_value = np.array([[0.45, 0.55]])  # Low confidence
        mock_service.models["buy_EURUSD+_PERIOD_M5"] = mock_model

        # Mock feature preparation
        mock_service._prepare_features = Mock(return_value=np.array([[0.5, 0.6, 0.7]]))

        # Mock health check for critical model (threshold 0.7)
        with patch.object(mock_service, '_get_model_health_and_threshold') as mock_health:
            mock_health.return_value = ({"status": "critical", "health_score": 30}, 0.7)

            result = mock_service.get_prediction(
                strategy="test",
                symbol="EURUSD+",
                timeframe="M5",
                features={"rsi": 65.5, "current_price": 1.0835, "atr": 0.0015},
                direction="buy",
                enhanced=True
            )

            # Low confidence (0.1) should not exceed critical threshold (0.7)
            assert result["should_trade"] == False


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
