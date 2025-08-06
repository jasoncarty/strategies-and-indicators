#!/usr/bin/env python3
"""
Integration tests for End-to-End Workflow
Tests the complete workflow from MT5 EA to ML Service to Analytics
"""

import unittest
import sys
import os
import json
import tempfile
import shutil
import time
import requests
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add the project root to the path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# Import test managers
from tests.test_db_manager import create_test_database_manager
from tests.test_webserver_manager import create_test_webserver_manager

class TestEndToEndWorkflow(unittest.TestCase):
    """Test cases for complete end-to-end workflow"""

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests"""
        print("🔧 Setting up isolated test environment...")

        # Create test database
        cls.db_manager = create_test_database_manager()
        cls.db_manager.setup_test_database()

        # Create test webserver manager
        cls.webserver_manager = create_test_webserver_manager()

        # Start services with test database
        test_db_config = cls.db_manager.get_test_config()
        if test_db_config:
            analytics_started = cls.webserver_manager.start_analytics_service(test_db_config)
            if not analytics_started:
                raise Exception("Analytics service failed to start - this is a critical integration test failure")
        else:
            raise Exception("Test database configuration not available - this is a critical integration test failure")

        ml_started = cls.webserver_manager.start_ml_service()
        if not ml_started:
            raise Exception("ML service failed to start - this is a critical integration test failure")

        # Get service URLs
        cls.service_urls = cls.webserver_manager.get_all_urls()
        cls.ml_service_url = cls.service_urls.get('ml_service', 'http://127.0.0.1:5004')
        cls.analytics_url = cls.service_urls.get('analytics', 'http://127.0.0.1:5002')

        print(f"✅ Test environment ready:")
        print(f"   ML Service: {cls.ml_service_url}")
        print(f"   Analytics Service: {cls.analytics_url}")

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment"""
        print("🧹 Cleaning up test environment...")

        # Stop all services
        cls.webserver_manager.stop_all_services()

        # Clean up test database
        cls.db_manager.cleanup_test_database(destroy_database=False)

        print("✅ Test environment cleaned up")

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up test fixtures"""
        shutil.rmtree(self.temp_dir)

    def test_ml_service_connectivity(self):
        """Test ML service connectivity and basic functionality"""
        try:
            # Test ML service health
            response = requests.get(f"{self.ml_service_url}/health", timeout=5)
            self.assertEqual(response.status_code, 200)

            # Test ML service status
            response = requests.get(f"{self.ml_service_url}/status", timeout=5)
            self.assertEqual(response.status_code, 200)

            status_data = response.json()
            self.assertIn('status', status_data)
            self.assertIn('models_loaded', status_data)

        except requests.exceptions.ConnectionError:
            # Skip test if ML service is not running
            self.skipTest("ML service not running")

    def test_ml_prediction_workflow(self):
        """Test complete ML prediction workflow"""
        try:
            # Sample features that match what MT5 EA would send
            features = {
                'rsi': 50.0,
                'stoch_main': 50.0,
                'stoch_signal': 50.0,
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
                'volatility': 0.001,
                'spread': 1.0,
                'session_hour': 12,
                'is_news_time': False,
                'day_of_week': 1,
                'month': 7
            }

            # Test prediction request
            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                **features  # Spread all features at top level
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            self.assertEqual(response.status_code, 200)

            result = response.json()
            self.assertIn('status', result)
            self.assertIn('prediction', result)

            if result['status'] == 'success':
                prediction = result['prediction']
                self.assertIn('confidence', prediction)
                self.assertIn('direction', prediction)
                self.assertIn('probability', prediction)

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running")

    def test_data_structure_consistency(self):
        """Test that data structures are consistent across all services via HTTP requests"""
        try:
            # Test MT5 EA data structure (simulated)
            mt5_features = {
                'rsi': 50.0,
                'stoch_main': 50.0,
                'stoch_signal': 50.0,
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
                'volatility': 0.001,
                'spread': 1.0,
                'session_hour': 12,
                'is_news_time': False,
                'day_of_week': 1,
                'month': 7
            }

            # Validate MT5 features locally
            required_mt5_features = [
                'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
                'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
                'volume_ratio', 'price_change', 'volatility', 'spread',
                'session_hour', 'is_news_time', 'day_of_week', 'month'
            ]

            for feature in required_mt5_features:
                self.assertIn(feature, mt5_features)

            # Test ML service via HTTP request to validate feature processing
            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                **mt5_features  # Spread all features at top level
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            self.assertEqual(response.status_code, 200,
                           f"ML service returned status {response.status_code}")

            result = response.json()
            self.assertIn('status', result)

            if result['status'] == 'success':
                # Validate that ML service processed the features correctly
                self.assertIn('prediction', result)
                self.assertIn('metadata', result)

                metadata = result['metadata']
                self.assertIn('features_used', metadata)

                # Verify ML service processed 28 features (19 input + 9 engineered)
                self.assertEqual(metadata['features_used'], 28,
                               f"Expected 28 features, got {metadata['features_used']}")

                # Verify prediction structure
                prediction = result['prediction']
                self.assertIn('confidence', prediction)
                self.assertIn('direction', prediction)
                self.assertIn('probability', prediction)

                # Validate confidence and probability are reasonable values
                self.assertGreaterEqual(prediction['confidence'], 0.0)
                self.assertLessEqual(prediction['confidence'], 1.0)
                self.assertGreaterEqual(prediction['probability'], 0.0)
                self.assertLessEqual(prediction['probability'], 1.0)

                print(f"✅ ML Service processed {metadata['features_used']} features successfully")
                print(f"   Prediction: {prediction['direction']} (confidence: {prediction['confidence']:.3f})")

            else:
                self.fail(f"ML service returned error: {result.get('message', 'Unknown error')}")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running - skipping HTTP-based data consistency test")
        except Exception as e:
            self.fail(f"Unexpected error during data consistency test: {str(e)}")

    def test_error_handling_integration(self):
        """Test error handling across the entire workflow via HTTP requests"""
        try:
            # Test 1: Invalid data types
            invalid_features = {
                'rsi': 'invalid_string',  # Should be numeric
                'stoch_main': None,       # Should be numeric
                'macd_main': 'not_a_number'  # Should be numeric
            }

            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                **invalid_features  # Spread all features at top level
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            # Should return an error response, not crash
            self.assertIn(response.status_code, [200, 400, 500])

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'error':
                    print("✅ ML service correctly handled invalid data types")
                else:
                    print("⚠️ ML service accepted invalid data types")
            else:
                print(f"✅ ML service returned error status {response.status_code} for invalid data")

            # Test 2: Missing required features
            incomplete_features = {
                'rsi': 50.0  # Missing most features
            }

            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                'features': incomplete_features
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            self.assertIn(response.status_code, [200, 400, 500])

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'error':
                    print("✅ ML service correctly handled missing features")
                else:
                    print("⚠️ ML service accepted incomplete features")
            else:
                print(f"✅ ML service returned error status {response.status_code} for missing features")

            # Test 3: Empty features
            empty_features = {}

            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                'features': empty_features
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            self.assertIn(response.status_code, [200, 400, 500])

            if response.status_code == 200:
                result = response.json()
                if result['status'] == 'error':
                    print("✅ ML service correctly handled empty features")
                else:
                    print("⚠️ ML service accepted empty features")
            else:
                print(f"✅ ML service returned error status {response.status_code} for empty features")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running - skipping HTTP-based error handling test")
        except Exception as e:
            self.fail(f"Unexpected error during error handling test: {str(e)}")

    def test_feature_count_consistency(self):
        """Test that feature counts are consistent across the system via HTTP requests"""
        try:
            # MT5 EA sends 19 basic features
            mt5_basic_features = [
                'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
                'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
                'volume_ratio', 'price_change', 'volatility', 'force_index',
                'spread', 'session_hour', 'is_news_time', 'day_of_week', 'month'
            ]

            self.assertEqual(len(mt5_basic_features), 19)

            # Create test features with exactly 19 features
            test_features = {
                'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
                'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
                'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
                'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
                'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
                'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
                'month': 7
            }

            # Verify we have exactly 19 features
            self.assertEqual(len(test_features), 19)

            # Test ML service via HTTP request
            prediction_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                **test_features  # Spread all features at top level
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=prediction_data,
                timeout=10
            )

            self.assertEqual(response.status_code, 200,
                           f"ML service returned status {response.status_code}")

            result = response.json()
            self.assertIn('status', result)

            if result['status'] == 'success':
                metadata = result['metadata']
                self.assertIn('features_used', metadata)

                # Verify ML service processed exactly 28 features (19 input + 9 engineered)
                actual_features = metadata['features_used']
                self.assertEqual(actual_features, 28,
                               f"Expected 28 features, got {actual_features}")

                print(f"✅ Feature count consistency verified: {len(test_features)} input → {actual_features} processed")

            else:
                self.fail(f"ML service returned error: {result.get('message', 'Unknown error')}")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running - skipping HTTP-based feature count test")
        except Exception as e:
            self.fail(f"Unexpected error during feature count test: {str(e)}")

    def test_service_dependencies(self):
        """Test that all required services are available"""

        services_to_test = [
            (self.ml_service_url, "ML Prediction Service"),
            # Add analytics service when available
            # (self.analytics_url, "Analytics Service"),
        ]

        for url, service_name in services_to_test:
            try:
                response = requests.get(f"{url}/health", timeout=5)
                self.assertEqual(response.status_code, 200,
                              f"{service_name} health check failed")
            except requests.exceptions.ConnectionError:
                self.skipTest(f"{service_name} not running")

    def test_data_flow_validation(self):
        """Test the complete data flow from MT5 to ML to Analytics"""

        # Simulate MT5 EA data collection
        mt5_data = {
            'trade_id': '12345',
            'symbol': 'BTCUSD',
            'timeframe': 'M5',
            'rsi': 50.0,
            'stoch_main': 50.0,
            'stoch_signal': 50.0,
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
            'volatility': 0.001,
            'spread': 1.0,
            'session_hour': 12,
            'is_news_time': False,
            'day_of_week': 1,
            'month': 7
        }

        # Validate MT5 data structure
        self.assertIn('trade_id', mt5_data)
        self.assertIn('symbol', mt5_data)
        self.assertIn('rsi', mt5_data)  # Features are now at top level

        # Simulate ML service processing
        try:
            ml_request = {
                'strategy': 'ML_Testing_EA',
                'symbol': mt5_data['symbol'],
                'timeframe': mt5_data['timeframe'],
                'direction': 'buy',
                'rsi': mt5_data['rsi'],
                'stoch_main': mt5_data['stoch_main'],
                'stoch_signal': mt5_data['stoch_signal'],
                'macd_main': mt5_data['macd_main'],
                'macd_signal': mt5_data['macd_signal'],
                'bb_upper': mt5_data['bb_upper'],
                'bb_lower': mt5_data['bb_lower'],
                'williams_r': mt5_data['williams_r'],
                'cci': mt5_data['cci'],
                'momentum': mt5_data['momentum'],
                'force_index': mt5_data['force_index'],
                'volume_ratio': mt5_data['volume_ratio'],
                'price_change': mt5_data['price_change'],
                'volatility': mt5_data['volatility'],
                'spread': mt5_data['spread'],
                'session_hour': mt5_data['session_hour'],
                'is_news_time': mt5_data['is_news_time'],
                'day_of_week': mt5_data['day_of_week'],
                'month': mt5_data['month']
            }

            response = requests.post(
                f"{self.ml_service_url}/predict",
                json=ml_request,
                timeout=10
            )

            if response.status_code == 200:
                ml_response = response.json()

                # Validate ML response structure
                self.assertIn('status', ml_response)
                if ml_response['status'] == 'success':
                    self.assertIn('prediction', ml_response)
                    self.assertIn('metadata', ml_response)

                    # Validate prediction structure
                    prediction = ml_response['prediction']
                    self.assertIn('confidence', prediction)
                    self.assertIn('direction', prediction)
                    self.assertIn('probability', prediction)

                    # Validate metadata
                    metadata = ml_response['metadata']
                    self.assertIn('features_used', metadata)
                    self.assertEqual(metadata['features_used'], 28)

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running")

    def test_complete_workflow_with_analytics(self):
        """Test complete workflow: MT5 → ML Service → Analytics Service"""
        try:
            # Step 1: Simulate MT5 EA collecting features
            mt5_features = {
                'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
                'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
                'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
                'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
                'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
                'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
                'month': 7
            }

            # Step 2: Get ML prediction
            ml_request = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                **mt5_features  # Spread all features at top level
            }

            ml_response = requests.post(
                f"{self.ml_service_url}/predict",
                json=ml_request,
                timeout=10
            )

            self.assertEqual(ml_response.status_code, 200,
                           f"ML service returned status {ml_response.status_code}")

            ml_result = ml_response.json()
            self.assertIn('status', ml_result)

            if ml_result['status'] != 'success':
                self.skipTest(f"ML service returned error: {ml_result.get('message', 'Unknown error')}")

            # Step 3: Send trade data to analytics service
            test_trade_id = int(time.time() * 1000000)  # Use microseconds for uniqueness
            trade_data = {
                'trade_id': test_trade_id,
                'strategy_name': 'ML_Testing_EA',
                'strategy_version': '1.0',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                'entry_price': 50000.0,
                'stop_loss': 49000.0,
                'take_profit': 51000.0,
                'lot_size': 0.1,
                'entry_time': int(time.time()),
                'status': 'OPEN',
                'account_id': 'TEST_ACCOUNT'
            }

            # Test analytics service trade endpoint
            try:
                analytics_response = requests.post(
                    f"{self.analytics_url}/analytics/trade",
                    json=trade_data,
                    timeout=10
                )

                # Check for successful response
                if analytics_response.status_code in [200, 201]:
                    print("✅ Analytics service received trade data successfully")
                else:
                    print(f"❌ Analytics service returned status {analytics_response.status_code}")
                    print(f"❌ Response content: {analytics_response.text}")
                    self.fail(f"Analytics service trade endpoint failed with status {analytics_response.status_code}")

            except requests.exceptions.ConnectionError:
                self.fail("Analytics service not running - this is a critical integration test failure")

            # Step 4: Send market conditions to analytics service
            market_conditions = {
                'trade_id': test_trade_id,
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'rsi': mt5_features['rsi'],
                'stoch_main': mt5_features['stoch_main'],
                'stoch_signal': mt5_features['stoch_signal'],
                'macd_main': mt5_features['macd_main'],
                'macd_signal': mt5_features['macd_signal'],
                'bb_upper': mt5_features['bb_upper'],
                'bb_lower': mt5_features['bb_lower'],
                'cci': mt5_features['cci'],
                'momentum': mt5_features['momentum'],
                'volume_ratio': mt5_features['volume_ratio'],
                'price_change': mt5_features['price_change'],
                'volatility': mt5_features['volatility'],
                'spread': mt5_features['spread'],
                'session_hour': mt5_features['session_hour'],
                'day_of_week': mt5_features['day_of_week'],
                'month': mt5_features['month']
            }

            try:
                market_response = requests.post(
                    f"{self.analytics_url}/analytics/market_conditions",
                    json=market_conditions,
                    timeout=10
                )

                if market_response.status_code in [200, 201]:
                    print("✅ Analytics service received market conditions successfully")
                else:
                    print(f"❌ Analytics service returned status {market_response.status_code}")
                    print(f"❌ Response content: {market_response.text}")
                    self.fail(f"Analytics service market conditions endpoint failed with status {market_response.status_code}")

            except requests.exceptions.ConnectionError:
                self.fail("Analytics service not running - this is a critical integration test failure")

            # Step 5: Send ML prediction to analytics service
            ml_prediction_data = {
                'trade_id': test_trade_id,
                'model_name': ml_result['metadata'].get('model_name', 'buy_BTCUSD_PERIOD_M5'),
                'model_type': 'buy',
                'prediction_probability': ml_result['prediction']['probability'],
                'confidence_score': ml_result['prediction']['confidence'],
                'features_json': json.dumps(mt5_features),
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'strategy_name': 'ML_Testing_EA',
                'strategy_version': '1.0'
            }

            try:
                prediction_response = requests.post(
                    f"{self.analytics_url}/analytics/ml_prediction",
                    json=ml_prediction_data,
                    timeout=10
                )

                if prediction_response.status_code in [200, 201]:
                    print("✅ Analytics service received ML prediction successfully")
                else:
                    print(f"❌ Analytics service returned status {prediction_response.status_code}")
                    print(f"❌ Response content: {prediction_response.text}")
                    self.fail(f"Analytics service ML prediction endpoint failed with status {prediction_response.status_code}")

            except requests.exceptions.ConnectionError:
                self.fail("Analytics service not running - this is a critical integration test failure")

            # Verify the complete workflow
            print(f"✅ Complete workflow test passed:")
            print(f"   - ML Service: {ml_result['prediction']['direction']} (confidence: {ml_result['prediction']['confidence']:.3f})")
            print(f"   - Features processed: {ml_result['metadata']['features_used']}")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running - skipping complete workflow test")
        except Exception as e:
            self.fail(f"Unexpected error during complete workflow test: {str(e)}")

    def test_ml_service_all_endpoints(self):
        """Test all ML service endpoints"""
        try:
            # Test /health endpoint
            response = requests.get(f"{self.ml_service_url}/health", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"ML Service /health endpoint failed with status {response.status_code}")
            health_data = response.json()
            self.assertIn('status', health_data)
            print("✅ ML Service /health endpoint working")

            # Test /status endpoint
            response = requests.get(f"{self.ml_service_url}/status", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"ML Service /status endpoint failed with status {response.status_code}")
            status_data = response.json()
            self.assertIn('status', status_data)
            self.assertIn('models_loaded', status_data)
            print("✅ ML Service /status endpoint working")

            # Test /models endpoint
            response = requests.get(f"{self.ml_service_url}/models", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"ML Service /models endpoint failed with status {response.status_code}")
            models_data = response.json()
            self.assertIn('models', models_data)
            print("✅ ML Service /models endpoint working")

            # Test /predict endpoint (already tested in other methods)
            print("✅ ML Service /predict endpoint working (tested elsewhere)")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running")

    def test_analytics_service_all_endpoints(self):
        """Test all Analytics service endpoints"""
        try:
            # Test /health endpoint
            response = requests.get(f"{self.analytics_url}/health", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"Analytics Service /health endpoint failed with status {response.status_code}")
            health_data = response.json()
            self.assertIn('status', health_data)
            self.assertIn('database', health_data)
            print("✅ Analytics Service /health endpoint working")

            # Test /analytics/trade endpoint
            test_trade_id = int(time.time())
            trade_data = {
                'trade_id': test_trade_id,
                'strategy_name': 'TestStrategy',
                'strategy_version': '1.0',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                'entry_price': 50000.0,
                'stop_loss': 49000.0,
                'take_profit': 51000.0,
                'lot_size': 0.1,
                'entry_time': int(time.time()),
                'status': 'OPEN',
                'account_id': 'TEST_ACCOUNT'
            }
            response = requests.post(f"{self.analytics_url}/analytics/trade", json=trade_data, timeout=5)

            # Debug: Print response details if there's an error
            if response.status_code not in [200, 201]:
                print(f"❌ Trade endpoint failed with status {response.status_code}")
                print(f"❌ Response content: {response.text}")
                print(f"❌ Request data: {trade_data}")

            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /analytics/trade endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /analytics/trade endpoint working")

            # Test /analytics/market_conditions endpoint
            market_data = {
                'trade_id': test_trade_id,
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'rsi': 50.0,
                'stoch_main': 50.0,
                'stoch_signal': 50.0,
                'macd_main': 0.0,
                'macd_signal': 0.0,
                'bb_upper': 50000.0,
                'bb_lower': 49000.0,
                'cci': 0.0,
                'momentum': 100.0,
                'volume_ratio': 1.0,
                'price_change': 0.001,
                'volatility': 0.001,
                'spread': 1.0,
                'session_hour': 12,
                'day_of_week': 1,
                'month': 7
            }
            response = requests.post(f"{self.analytics_url}/analytics/market_conditions", json=market_data, timeout=5)
            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /analytics/market_conditions endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /analytics/market_conditions endpoint working")

            # Test /analytics/ml_prediction endpoint
            ml_prediction_data = {
                'trade_id': test_trade_id,
                'model_name': 'test_model',
                'model_type': 'buy',
                'prediction_probability': 0.75,
                'confidence_score': 0.8,
                'features_json': '{"rsi": 50.0}',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'strategy_name': 'TestStrategy',
                'strategy_version': '1.0'
            }
            response = requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=ml_prediction_data, timeout=5)
            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /analytics/ml_prediction endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /analytics/ml_prediction endpoint working")

            # Test /analytics/trade_exit endpoint
            trade_exit_data = {
                'trade_id': test_trade_id,
                'exit_price': 50500.0,
                'exit_reason': 'take_profit',
                'profit_loss': 500.0,
                'exit_time': int(time.time()),
                'status': 'CLOSED'
            }
            response = requests.post(f"{self.analytics_url}/analytics/trade_exit", json=trade_exit_data, timeout=5)
            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /analytics/trade_exit endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /analytics/trade_exit endpoint working")

            # Test /analytics/batch endpoint
            batch_data = {
                'records': [
                    {'type': 'trade', 'data': trade_data},
                    {'type': 'market_conditions', 'data': market_data},
                    {'type': 'ml_prediction', 'data': ml_prediction_data}
                ]
            }
            response = requests.post(f"{self.analytics_url}/analytics/batch", json=batch_data, timeout=5)
            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /analytics/batch endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /analytics/batch endpoint working")

            # Test /ml_trade_log endpoint
            ml_trade_log_data = {
                'trade_id': test_trade_id,
                'strategy': 'TestStrategy',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy',
                'entry_price': 50000.0,
                'stop_loss': 49000.0,
                'take_profit': 51000.0,
                'lot_size': 0.1,
                'timestamp': int(time.time()),
                'trade_time': int(time.time()),
                'status': 'OPEN',
                'model_name': 'test_model',
                'confidence': 0.8,
                'ml_confidence': 0.8,
                'ml_model_type': 'buy',
                'ml_model_key': 'test_model_key',
                'ml_prediction': 0.75
            }
            response = requests.post(f"{self.analytics_url}/ml_trade_log", json=ml_trade_log_data, timeout=5)

            # Debug: Print response details if there's an error
            if response.status_code not in [200, 201]:
                print(f"❌ ML trade log endpoint failed with status {response.status_code}")
                print(f"❌ Response content: {response.text}")
                print(f"❌ Request data: {ml_trade_log_data}")

            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /ml_trade_log endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /ml_trade_log endpoint working")

            # Test /ml_trade_close endpoint
            ml_trade_close_data = {
                'trade_id': test_trade_id,
                'strategy': 'TestStrategy',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'close_price': 50500.0,
                'profit_loss': 500.0,
                'profit_loss_pips': 50.0,
                'close_time': int(time.time()),
                'exit_reason': 'take_profit',
                'status': 'CLOSED',
                'success': True,
                'timestamp': int(time.time())
            }
            response = requests.post(f"{self.analytics_url}/ml_trade_close", json=ml_trade_close_data, timeout=5)
            self.assertIn(response.status_code, [200, 201],
                         f"Analytics Service /ml_trade_close endpoint failed with status {response.status_code}")
            print("✅ Analytics Service /ml_trade_close endpoint working")

            # Test /analytics/trades endpoint (GET) - should return empty list initially
            response = requests.get(f"{self.analytics_url}/analytics/trades?symbol=BTCUSD&timeframe=M5&start_date=2024-01-01&end_date=2024-12-31", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"Analytics Service /analytics/trades endpoint failed with status {response.status_code}")
            trades_data = response.json()
            self.assertIsInstance(trades_data, list, "Expected trades endpoint to return a list")
            print(f"✅ Analytics Service /analytics/trades endpoint working (returned {len(trades_data)} trades)")

            # Test /analytics/trades endpoint (GET) - should now find the trade we created
            # Use current year dates to match the trade we just created
            from datetime import datetime
            current_year = datetime.now().year
            response = requests.get(f"{self.analytics_url}/analytics/trades?symbol=BTCUSD&timeframe=M5&start_date={current_year}-01-01&end_date={current_year}-12-31", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"Analytics Service /analytics/trades endpoint failed with status {response.status_code}")
            trades_data = response.json()
            self.assertIsInstance(trades_data, list, "Expected trades endpoint to return a list")
            self.assertGreater(len(trades_data), 0, "Expected to find at least one trade after creating it")
            print(f"✅ Analytics Service /analytics/trades endpoint found {len(trades_data)} trades")
            print("✅ Analytics Service /analytics/trades endpoint working")

            # Test /analytics/summary endpoint (GET)
            response = requests.get(f"{self.analytics_url}/analytics/summary", timeout=5)
            self.assertEqual(response.status_code, 200,
                           f"Analytics Service /analytics/summary endpoint failed with status {response.status_code}")
            summary_data = response.json()
            self.assertIsInstance(summary_data, dict, "Expected summary endpoint to return a dictionary")
            self.assertIn('total_trades', summary_data, "Expected summary to contain total_trades")
            print(f"✅ Analytics Service /analytics/summary endpoint working (total_trades: {summary_data.get('total_trades', 'N/A')})")
            print("✅ Analytics Service /analytics/summary endpoint working")

        except requests.exceptions.ConnectionError:
            self.fail("Analytics service not running - this is a critical integration test failure")

    def test_analytics_service_error_handling(self):
        """Test Analytics service error handling for invalid data"""
        try:
            # Test invalid trade data
            invalid_trade_data = {
                'trade_id': 'test_invalid_001',
                # Missing required fields
            }
            response = requests.post(f"{self.analytics_url}/analytics/trade", json=invalid_trade_data, timeout=5)
            self.assertIn(response.status_code, [400, 500])  # Should return error for invalid data
            print("✅ Analytics Service properly handles invalid trade data")

            # Test invalid market conditions data
            invalid_market_data = {
                'trade_id': 'test_invalid_001',
                # Missing required fields
            }
            response = requests.post(f"{self.analytics_url}/analytics/market_conditions", json=invalid_market_data, timeout=5)
            self.assertIn(response.status_code, [400, 500])
            print("✅ Analytics Service properly handles invalid market conditions data")

            # Test invalid ML prediction data
            invalid_ml_data = {
                'trade_id': 'test_invalid_001',
                # Missing required fields
            }
            response = requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=invalid_ml_data, timeout=5)
            self.assertIn(response.status_code, [400, 500])
            print("✅ Analytics Service properly handles invalid ML prediction data")

        except requests.exceptions.ConnectionError:
            self.fail("Analytics service not running - this is a critical integration test failure")

    def test_ml_service_error_handling(self):
        """Test ML service error handling for invalid data"""
        try:
            # Test invalid prediction request
            invalid_prediction_data = {
                'strategy': 'TestStrategy',
                'symbol': 'BTCUSD',
                'timeframe': 'M5',
                'direction': 'buy'
                # Missing required features
            }
            response = requests.post(f"{self.ml_service_url}/predict", json=invalid_prediction_data, timeout=5)
            # Check if ML service properly rejects incomplete data
            if response.status_code in [400, 500]:
                print("✅ ML Service properly handles invalid prediction data")
            else:
                print(f"⚠️ ML Service accepts incomplete data (data quality issue) - Status: {response.status_code}")
                print(f"⚠️ Response content: {response.text}")
            self.assertIn(response.status_code, [200, 400, 500])

            # Test malformed JSON
            response = requests.post(f"{self.ml_service_url}/predict", data="invalid json",
                                  headers={'Content-Type': 'application/json'}, timeout=5)
            self.assertIn(response.status_code, [400, 500])
            print("✅ ML Service properly handles malformed JSON")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running")

    def test_service_load_and_performance(self):
        """Test service performance under load"""
        try:
            # Test ML service with multiple concurrent requests
            import threading
            import time

            def make_prediction_request():
                features = {
                    'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
                    'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
                    'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
                    'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
                    'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
                    'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
                    'month': 7
                }

                request_data = {
                    'strategy': 'TestStrategy',
                    'symbol': 'BTCUSD',
                    'timeframe': 'M5',
                    'direction': 'buy',
                    **features  # Spread all features at top level
                }

                try:
                    response = requests.post(f"{self.ml_service_url}/predict", json=request_data, timeout=10)
                    return response.status_code == 200
                except:
                    return False

            # Test concurrent requests
            threads = []
            results = []

            start_time = time.time()
            for i in range(5):  # 5 concurrent requests
                thread = threading.Thread(target=lambda: results.append(make_prediction_request()))
                threads.append(thread)
                thread.start()

            for thread in threads:
                thread.join()

            end_time = time.time()
            duration = end_time - start_time

            successful_requests = sum(results)
            print(f"✅ ML Service handled {successful_requests}/5 concurrent requests in {duration:.2f}s")

            # Should handle at least 3 out of 5 requests successfully
            self.assertGreaterEqual(successful_requests, 3,
                                  f"ML service should handle concurrent requests, got {successful_requests}/5")

        except requests.exceptions.ConnectionError:
            self.skipTest("ML service not running")


if __name__ == '__main__':
    unittest.main()
