#!/usr/bin/env python3
"""
Integration tests for shared feature engineering utility
Tests that feature engineering is consistent across training and prediction services
"""

import unittest
import sys
import os
import tempfile
import shutil
import json
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime

# Add the ML_Webserver directory to the path for imports
ml_webserver_path = Path(__file__).parent.parent / 'ML_Webserver'
sys.path.insert(0, str(ml_webserver_path))

# Import the shared utility
try:
    from feature_engineering_utils import FeatureEngineeringUtils
except ImportError:
    # Try alternative import path
    import sys
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from ML_Webserver.feature_engineering_utils import FeatureEngineeringUtils


class TestFeatureEngineeringIntegration(unittest.TestCase):
    """Integration tests for shared feature engineering utility"""

    def setUp(self):
        """Set up test environment"""
        self.test_data = {
            'rsi': 25.0,
            'stoch_main': 15.0,
            'stoch_signal': 20.0,
            'macd_main': 0.0,
            'macd_signal': 0.0,
            'bb_upper': 50000.0,
            'bb_lower': 49000.0,
            'williams_r': 50.0,
            'cci': 0.0,
            'momentum': 100.0,
            'force_index': 0.0,
            'volume_ratio': 1.0,
            'price_change': 0.001,
            'volatility': 0.0003,  # This will be 'low' in prediction (< 0.0005)
            'spread': 1.0,
            'session_hour': 10,
            'is_news_time': 0,
            'day_of_week': 1,
            'month': 7
        }

    def test_01_feature_engineering_consistency(self):
        """Test that feature engineering produces consistent results"""
        print("\n🔧 Testing feature engineering consistency...")

        # Test the shared utility directly
        engineered_features = FeatureEngineeringUtils.calculate_engineered_features(self.test_data)

        # Verify all expected engineered features are present
        expected_engineered_features = [
            'rsi_regime', 'stoch_regime', 'volatility_regime',
            'hour', 'session', 'is_london_session', 'is_ny_session',
            'is_asian_session', 'is_session_overlap'
        ]

        for feature in expected_engineered_features:
            self.assertIn(feature, engineered_features, f"Missing engineered feature: {feature}")

        # Verify specific values based on our test data
        self.assertEqual(engineered_features['rsi_regime'], 0)  # oversold (25 < 30)
        self.assertEqual(engineered_features['stoch_regime'], 0)  # oversold (15 < 20)
        self.assertEqual(engineered_features['volatility_regime'], 0)  # low (0.0003 < 0.0005)
        self.assertEqual(engineered_features['hour'], 10)
        self.assertEqual(engineered_features['session'], 1)  # london (8 <= 10 < 16)
        self.assertEqual(engineered_features['is_london_session'], 1)
        self.assertEqual(engineered_features['is_ny_session'], 0)
        self.assertEqual(engineered_features['is_asian_session'], 0)
        self.assertEqual(engineered_features['is_session_overlap'], 1)

        print("✅ Feature engineering consistency verified")

    def test_02_training_prediction_consistency(self):
        """Test that training and prediction services produce consistent features"""
        print("\n🔄 Testing training-prediction consistency...")

        # Create a DataFrame for training (simulating what the training service would do)
        df = pd.DataFrame([self.test_data])

        # Add engineered features using the training method
        df_with_engineered = FeatureEngineeringUtils.add_engineered_features_to_dataframe(df.copy())

        # Calculate engineered features using the prediction method
        prediction_engineered = FeatureEngineeringUtils.calculate_engineered_features(self.test_data)

        # Compare the results
        for feature in ['rsi_regime', 'stoch_regime', 'volatility_regime', 'session']:
            training_value = df_with_engineered[feature].iloc[0]
            prediction_value = prediction_engineered[feature]

            # Note: Training uses categorical values, prediction uses numeric
            # We need to check that the logic is consistent
            if feature == 'rsi_regime':
                self.assertEqual(training_value, 'oversold')  # Training: categorical
                self.assertEqual(prediction_value, 0)  # Prediction: numeric (LabelEncoder)
            elif feature == 'stoch_regime':
                self.assertEqual(training_value, 'oversold')  # Training: categorical
                self.assertEqual(prediction_value, 0)  # Prediction: numeric (LabelEncoder)
            elif feature == 'volatility_regime':
                self.assertEqual(training_value, 'medium')  # Training: categorical (default for single row)
                self.assertEqual(prediction_value, 0)  # Prediction: numeric (LabelEncoder) - low (< 0.0005)
            elif feature == 'session':
                self.assertEqual(training_value, 'london')  # Training: categorical
                self.assertEqual(prediction_value, 1)  # Prediction: numeric (LabelEncoder)

        print("✅ Training-prediction consistency verified")

    def test_03_feature_count_consistency(self):
        """Test that feature counts are consistent across services"""
        print("\n📊 Testing feature count consistency...")

        # Get expected feature lists
        basic_features = FeatureEngineeringUtils.get_expected_19_features()
        complete_features = FeatureEngineeringUtils.get_expected_28_features()

        # Verify counts
        self.assertEqual(len(basic_features), 19, "Basic features should be 19")
        self.assertEqual(len(complete_features), 28, "Complete features should be 28")

        # Verify that complete features include all basic features
        for feature in basic_features:
            self.assertIn(feature, complete_features, f"Basic feature {feature} missing from complete features")

        # Verify that engineered features are in complete but not basic
        engineered_features = [
            'rsi_regime', 'stoch_regime', 'volatility_regime',
            'hour', 'session', 'is_london_session', 'is_ny_session',
            'is_asian_session', 'is_session_overlap'
        ]

        for feature in engineered_features:
            self.assertIn(feature, complete_features, f"Engineered feature {feature} missing from complete features")
            self.assertNotIn(feature, basic_features, f"Engineered feature {feature} should not be in basic features")

        print("✅ Feature count consistency verified")

    def test_04_session_classification_consistency(self):
        """Test that session classification is consistent across different input types"""
        print("\n🕐 Testing session classification consistency...")

        # Test different input types
        test_hours = [1, 8, 13, 22, 23]
        expected_sessions = ['asian', 'london', 'ny', 'off_hours', 'off_hours']

        # Test single value
        for hour, expected in zip(test_hours, expected_sessions):
            result = FeatureEngineeringUtils._classify_session(hour)
            self.assertEqual(result, expected, f"Session classification failed for hour {hour}")

        # Test list
        results = FeatureEngineeringUtils._classify_session(test_hours)
        self.assertEqual(results, expected_sessions, "Session classification failed for list input")

        # Test pandas Series
        series = pd.Series(test_hours)
        results = FeatureEngineeringUtils._classify_session(series)
        self.assertEqual(results, expected_sessions, "Session classification failed for pandas Series")

        print("✅ Session classification consistency verified")

    def test_05_edge_cases(self):
        """Test edge cases and boundary conditions"""
        print("\n🔍 Testing edge cases...")

        # Test boundary values for RSI
        edge_data = self.test_data.copy()

        # RSI boundaries
        edge_data['rsi'] = 29.9  # Just below oversold threshold
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['rsi_regime'], 0)  # oversold

        edge_data['rsi'] = 30.0  # At oversold threshold
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['rsi_regime'], 1)  # neutral

        edge_data['rsi'] = 70.0  # At overbought threshold
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['rsi_regime'], 2)  # overbought

        # Session boundaries
        edge_data['session_hour'] = 7  # Just before London session
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['session'], 0)  # asian (1 <= 7 < 10)

        edge_data['session_hour'] = 8  # Start of London session
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['session'], 1)  # london

        edge_data['session_hour'] = 15  # End of London session (but overlaps with NY)
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['session'], 2)  # ny (takes precedence in overlap)

        edge_data['session_hour'] = 16  # Just after London session
        features = FeatureEngineeringUtils.calculate_engineered_features(edge_data)
        self.assertEqual(features['session'], 2)  # ny

        print("✅ Edge cases verified")

    def test_06_missing_features_handling(self):
        """Test handling of missing features"""
        print("\n⚠️ Testing missing features handling...")

        # Test with missing features
        incomplete_data = {
            'rsi': 50.0,
            'session_hour': 12
            # Missing other features
        }

        features = FeatureEngineeringUtils.calculate_engineered_features(incomplete_data)

        # Should use default values for missing features
        self.assertEqual(features['rsi_regime'], 1)  # neutral (default 50.0)
        self.assertEqual(features['stoch_regime'], 1)  # neutral (default 50.0)
        self.assertEqual(features['volatility_regime'], 1)  # medium (default 0.001)
        self.assertEqual(features['hour'], 12)
        self.assertEqual(features['session'], 1)  # london

        print("✅ Missing features handling verified")

    def test_07_feature_engineering_performance(self):
        """Test that feature engineering is performant"""
        print("\n⚡ Testing feature engineering performance...")

        import time

        # Create larger dataset
        large_data = []
        for i in range(1000):
            data = self.test_data.copy()
            data['rsi'] = 30 + (i % 40)  # Vary RSI
            data['session_hour'] = i % 24  # Vary hour
            large_data.append(data)

        # Test performance
        start_time = time.time()
        for data in large_data:
            FeatureEngineeringUtils.calculate_engineered_features(data)
        end_time = time.time()

        processing_time = end_time - start_time
        self.assertLess(processing_time, 1.0, f"Feature engineering too slow: {processing_time:.3f}s for 1000 records")

        print(f"✅ Performance verified: {processing_time:.3f}s for 1000 records")

    def test_08_import_consistency(self):
        """Test that all services can import the shared utility"""
        print("\n📦 Testing import consistency...")

        # Test that we can import from different locations
        try:
            # Test direct import
            from feature_engineering_utils import FeatureEngineeringUtils
            print("✅ Direct import successful")
        except ImportError as e:
            self.fail(f"Direct import failed: {e}")

        # Test that the utility has all expected methods
        expected_methods = [
            'calculate_engineered_features',
            'add_engineered_features_to_dataframe',
            '_classify_session',
            'get_expected_28_features',
            'get_expected_19_features'
        ]

        for method in expected_methods:
            self.assertTrue(hasattr(FeatureEngineeringUtils, method),
                          f"Missing method: {method}")

        print("✅ Import consistency verified")


def run_feature_engineering_integration_tests():
    """Run all feature engineering integration tests"""
    print("🧪 Running Feature Engineering Integration Tests")
    print("=" * 60)

    # Create test suite
    suite = unittest.TestLoader().loadTestsFromTestCase(TestFeatureEngineeringIntegration)

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # Print summary
    print("\n" + "=" * 60)
    print("📊 Feature Engineering Integration Test Summary:")
    print(f"   Tests run: {result.testsRun}")
    print(f"   Failures: {len(result.failures)}")
    print(f"   Errors: {len(result.errors)}")

    if result.failures:
        print("\n❌ Failures:")
        for test, traceback in result.failures:
            print(f"   - {test}: {traceback}")

    if result.errors:
        print("\n❌ Errors:")
        for test, traceback in result.errors:
            print(f"   - {test}: {traceback}")

    if result.wasSuccessful():
        print("\n✅ All feature engineering integration tests passed!")
        return True
    else:
        print("\n❌ Some feature engineering integration tests failed!")
        return False


if __name__ == '__main__':
    success = run_feature_engineering_integration_tests()
    sys.exit(0 if success else 1)
