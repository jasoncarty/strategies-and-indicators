#!/usr/bin/env python3
"""
Unit tests for ML Prediction Service
Tests the core functionality of the ML prediction service
"""

import unittest
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add the ML_Webserver directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / 'ML_Webserver'))

from ml_prediction_service import MLPredictionService


class TestMLPredictionService(unittest.TestCase):
    """Test cases for ML Prediction Service"""

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.models_dir = Path(self.temp_dir) / "ml_models"
        self.models_dir.mkdir()

        # Create mock model files
        self._create_mock_model_files()

        # Initialize service
        self.ml_service = MLPredictionService(models_dir=str(self.models_dir))

    def tearDown(self):
        """Clean up test fixtures"""
        shutil.rmtree(self.temp_dir)

    def _create_mock_model_files(self):
        """Create mock model files for testing"""
        import joblib
        import numpy as np
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.preprocessing import StandardScaler

        # Create mock feature names (28 features)
        feature_names = [
            'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
            'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
            'volume_ratio', 'price_change', 'volatility', 'force_index',
            'spread', 'session_hour', 'is_news_time', 'day_of_week', 'month',
            'rsi_regime', 'stoch_regime', 'volatility_regime',
            'hour', 'session', 'is_london_session', 'is_ny_session',
            'is_asian_session', 'is_session_overlap'
        ]

        # Create mock model
        model = RandomForestClassifier(n_estimators=10, random_state=42)
        X = np.random.rand(100, 28)
        y = np.random.randint(0, 2, 100)
        model.fit(X, y)

        # Create mock scaler
        scaler = StandardScaler()
        scaler.fit(X)

        # Save files
        model_file = self.models_dir / "buy_model_BTCUSD_PERIOD_M5.pkl"
        scaler_file = self.models_dir / "buy_scaler_BTCUSD_PERIOD_M5.pkl"
        features_file = self.models_dir / "buy_feature_names_BTCUSD_PERIOD_M5.pkl"

        joblib.dump(model, model_file)
        joblib.dump(scaler, scaler_file)
        joblib.dump(feature_names, features_file)

    def test_service_initialization(self):
        """Test that the service initializes correctly"""
        self.assertIsNotNone(self.ml_service)
        self.assertEqual(str(self.ml_service.models_dir), str(self.models_dir))

    def test_feature_preparation(self):
        """Test feature preparation functionality"""
        # Test data with 19 basic features
        features = {
            'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
            'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
            'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
            'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
            'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
            'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
            'month': 7
        }

        model_key = "buy_BTCUSD_PERIOD_M5"
        prepared_features = self.ml_service._prepare_features(features, model_key)

        self.assertIsNotNone(prepared_features)
        self.assertEqual(prepared_features.shape[1], 28)  # Should have 28 features

    def test_model_selection(self):
        """Test model selection logic"""
        # Test buy model selection
        buy_model = self.ml_service._select_model("BTCUSD", "M5", "buy")
        self.assertIsNotNone(buy_model)
        self.assertIn("buy", buy_model)

    def test_prediction_workflow(self):
        """Test complete prediction workflow"""
        features = {
            'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
            'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
            'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
            'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
            'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
            'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
            'month': 7
        }

        result = self.ml_service.get_prediction(
            strategy="TestStrategy",
            symbol="BTCUSD",
            timeframe="M5",
            features=features,
            direction="buy"
        )

        self.assertIn('status', result)
        self.assertIn('prediction', result)
        self.assertEqual(result['status'], 'success')

    def test_feature_consistency(self):
        """Test that feature names are consistent across models"""
        self.ml_service._ensure_consistent_feature_names()

        # All models should have 28 features
        for model_key, feature_names in self.ml_service.feature_names.items():
            if feature_names is not None:
                self.assertEqual(len(feature_names), 28)

    def test_error_handling(self):
        """Test error handling for invalid inputs"""
        # Test with missing features
        features = {'rsi': 50.0}  # Missing most features

        result = self.ml_service.get_prediction(
            strategy="TestStrategy",
            symbol="BTCUSD",
            timeframe="M5",
            features=features,
            direction="buy"
        )

        # Should handle missing features gracefully
        self.assertIn('status', result)

    def test_service_status(self):
        """Test service status endpoint"""
        status = self.ml_service.get_status()

        self.assertIn('status', status)
        self.assertIn('models_loaded', status)
        self.assertIn('available_models', status)
        self.assertEqual(status['status'], 'running')


if __name__ == '__main__':
    unittest.main()
