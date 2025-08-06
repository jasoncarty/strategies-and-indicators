#!/usr/bin/env python3
"""
Integration tests for all database table scenarios
Tests trade entry, exit, ML predictions, market conditions, and performance tracking
"""
import unittest
import requests
import json
import time
from datetime import datetime, timedelta
from tests.test_db_manager import create_test_database_manager
from tests.test_webserver_manager import create_test_webserver_manager


class TestDatabaseScenarios(unittest.TestCase):
    """Test all database table scenarios and data flow patterns"""

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests"""
        print("🔧 Setting up database scenario test environment...")

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

        print(f"✅ Database scenario test environment ready:")
        print(f"   ML Service: {cls.ml_service_url}")
        print(f"   Analytics Service: {cls.analytics_url}")

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment"""
        print("🧹 Cleaning up database scenario test environment...")
        cls.webserver_manager.stop_all_services()
        cls.db_manager.cleanup_test_database(destroy_database=False)
        print("✅ Database scenario test environment cleaned up")

    def setUp(self):
        """Set up for each test"""
        self.trade_id = int(time.time())  # Use timestamp as unique trade ID
        self.symbol = "BTCUSD"
        self.timeframe = "M5"
        self.strategy = "TestStrategy"
        self.strategy_version = "1.0"

    def test_01_trade_entry_scenario(self):
        """Test complete trade entry scenario - creates records in multiple tables"""
        # Generate a unique trade ID for this specific call with microsecond precision
        import time
        self.trade_id = int(time.time() * 1000000)  # Use microseconds for uniqueness
        print(f"\n🔄 Testing trade entry scenario for trade_id: {self.trade_id}")

        # Step 1: Get ML prediction for trade entry
        ml_features = {
            'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
            'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
            'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
            'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
            'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
            'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
            'month': 7
        }

        ml_request = {
            'strategy': self.strategy,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'direction': 'buy',
            **ml_features  # Spread all features at top level
        }

        ml_response = requests.post(f"{self.ml_service_url}/predict", json=ml_request, timeout=10)
        self.assertEqual(ml_response.status_code, 200,
                        f"ML prediction failed with status {ml_response.status_code}")
        ml_result = ml_response.json()

        print(f"✅ ML prediction: {ml_result['prediction']['direction']} (confidence: {ml_result['prediction']['confidence']:.3f})")

        # Step 2: Record trade entry in analytics
        trade_data = {
            'trade_id': self.trade_id,
            'strategy_name': self.strategy,
            'strategy_version': self.strategy_version,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'direction': 'buy',
            'entry_price': 50000.0,
            'stop_loss': 49000.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'entry_time': int(time.time()),
            'status': 'OPEN',
            'account_id': 'TEST_ACCOUNT'
        }

        trade_response = requests.post(f"{self.analytics_url}/analytics/trade", json=trade_data, timeout=10)

        # Debug: Print response details if there's an error
        if trade_response.status_code != 201:
            print(f"❌ Trade entry failed with status {trade_response.status_code}")
            print(f"❌ Response content: {trade_response.text}")
            print(f"❌ Request data: {trade_data}")

        self.assertEqual(trade_response.status_code, 201,
                        f"Trade entry failed with status {trade_response.status_code}")

        # Update trade_id to the actual created trade ID to ensure uniqueness
        self.trade_id = trade_response.json().get('trade_id')
        print(f"✅ Trade entry recorded: {self.trade_id}")

        # Step 3: Record market conditions
        market_conditions = {
            'trade_id': self.trade_id,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'rsi': ml_features['rsi'],
            'stoch_main': ml_features['stoch_main'],
            'stoch_signal': ml_features['stoch_signal'],
            'macd_main': ml_features['macd_main'],
            'macd_signal': ml_features['macd_signal'],
            'bb_upper': ml_features['bb_upper'],
            'bb_lower': ml_features['bb_lower'],
            'cci': ml_features['cci'],
            'momentum': ml_features['momentum'],
            'volume_ratio': ml_features['volume_ratio'],
            'price_change': ml_features['price_change'],
            'volatility': ml_features['volatility'],
            'spread': ml_features['spread'],
            'session_hour': ml_features['session_hour'],
            'day_of_week': ml_features['day_of_week'],
            'month': ml_features['month']
        }

        market_response = requests.post(f"{self.analytics_url}/analytics/market_conditions", json=market_conditions, timeout=10)
        self.assertEqual(market_response.status_code, 201,
                        f"Market conditions failed with status {market_response.status_code}")

        print(f"✅ Market conditions recorded")

        # Step 4: Record ML prediction
        ml_prediction_data = {
            'trade_id': self.trade_id,
            'model_name': ml_result['metadata'].get('model_name', 'test_model'),
            'model_type': 'buy',
            'prediction_probability': ml_result['prediction']['probability'],
            'confidence_score': ml_result['prediction']['confidence'],
            'features_json': json.dumps(ml_features),
            'timestamp': datetime.now().isoformat(),
            'symbol': self.symbol,
            'timeframe': self.timeframe
        }

        prediction_response = requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=ml_prediction_data, timeout=10)
        self.assertEqual(prediction_response.status_code, 201,
                        f"ML prediction recording failed with status {prediction_response.status_code}")

        print(f"✅ ML prediction recorded")

        # Step 5: Record ML trade log (for model retraining)
        ml_trade_log_data = {
            'trade_id': self.trade_id,
            'strategy': self.strategy,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'direction': 'buy',
            'entry_price': 50000.0,
            'stop_loss': 49000.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'ml_prediction': ml_result['prediction']['probability'],
            'ml_confidence': ml_result['prediction']['confidence'],
            'ml_model_type': 'buy',
            'ml_model_key': ml_result['metadata'].get('model_name', 'test_model'),
            'trade_time': int(time.time()),
            'features_json': json.dumps(ml_features),
            'status': 'OPEN',
            'timestamp': int(time.time())
        }

        ml_log_response = requests.post(f"{self.analytics_url}/ml_trade_log", json=ml_trade_log_data, timeout=10)
        self.assertEqual(ml_log_response.status_code, 201,
                        f"ML trade log failed with status {ml_log_response.status_code}")

        print(f"✅ ML trade log recorded")

        # Verify all records were created
        self._verify_trade_entry_records()

    def test_02_trade_exit_scenario(self):
        """Test complete trade exit scenario - updates existing records"""
        print(f"\n🔄 Testing trade exit scenario for trade_id: {self.trade_id}")

        # First create a trade entry
        self.test_01_trade_entry_scenario()

        # Step 1: Record trade exit
        trade_exit_data = {
            'trade_id': self.trade_id,
            'exit_price': 50500.0,
            'exit_reason': 'take_profit',
            'profit_loss': 500.0,
            'exit_time': int(time.time()),
            'status': 'CLOSED'
        }

        exit_response = requests.post(f"{self.analytics_url}/analytics/trade_exit", json=trade_exit_data, timeout=10)
        self.assertEqual(exit_response.status_code, 200,
                        f"Trade exit failed with status {exit_response.status_code}")

        print(f"✅ Trade exit recorded: profit_loss = {trade_exit_data['profit_loss']}")

        # Step 2: Record ML trade close (for model retraining)
        ml_trade_close_data = {
            'trade_id': self.trade_id,
            'strategy': self.strategy,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'close_price': 50500.0,
            'profit_loss': 500.0,
            'profit_loss_pips': 50.0,
            'close_time': int(time.time()),
            'exit_reason': 'take_profit',
            'status': 'CLOSED',
            'success': True,
            'timestamp': int(time.time())
        }

        ml_close_response = requests.post(f"{self.analytics_url}/ml_trade_close", json=ml_trade_close_data, timeout=10)
        self.assertEqual(ml_close_response.status_code, 201,
                        f"ML trade close failed with status {ml_close_response.status_code}")

        print(f"✅ ML trade close recorded")

        # Verify all records were updated
        self._verify_trade_exit_records()

        # Additional verification: Check that ml_trade_logs was updated
        self._verify_ml_trade_logs_updated_record()

    def test_03_batch_operations_scenario(self):
        """Test batch operations - multiple trades at once"""
        print(f"\n🔄 Testing batch operations scenario")

        # Create multiple trades for batch processing
        trades = []
        market_conditions = []
        ml_predictions = []

        for i in range(3):
            trade_id = int(time.time()) + i

            # Trade data
            trade_data = {
                'trade_id': trade_id,
                'strategy_name': self.strategy,
                'strategy_version': self.strategy_version,
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'direction': 'buy' if i % 2 == 0 else 'sell',
                'entry_price': 50000.0 + (i * 100),
                'stop_loss': 49000.0 + (i * 100),
                'take_profit': 51000.0 + (i * 100),
                'lot_size': 0.1,
                'entry_time': int(time.time()),
                'status': 'OPEN',
                'account_id': 'TEST_ACCOUNT'
            }
            trades.append(trade_data)

            # Market conditions
            market_data = {
                'trade_id': trade_id,
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'rsi': 50.0 + i,
                'stoch_main': 50.0 + i,
                'stoch_signal': 50.0 + i,
                'macd_main': 0.0 + i,
                'macd_signal': 0.0 + i,
                'bb_upper': 50000.0 + (i * 100),
                'bb_lower': 49000.0 + (i * 100),
                'cci': 0.0 + i,
                'momentum': 100.0 + i,
                'volume_ratio': 1.0,
                'price_change': 0.001,
                'volatility': 0.001,
                'spread': 1.0,
                'session_hour': 12,
                'day_of_week': 1,
                'month': 7
            }
            market_conditions.append(market_data)

            # ML prediction
            ml_data = {
                'trade_id': trade_id,
                'model_name': 'test_model',
                'model_type': 'buy' if i % 2 == 0 else 'sell',
                'prediction_probability': 0.75 + (i * 0.05),
                'confidence_score': 0.8 + (i * 0.05),
                'features_json': '{"rsi": 50.0}',
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'strategy_name': self.strategy,
                'strategy_version': self.strategy_version
            }
            ml_predictions.append(ml_data)

        # Send batch request
        batch_data = {
            'records': []
        }

        # Add trades
        for trade in trades:
            batch_data['records'].append({
                'type': 'trade',
                'data': trade
            })

        # Add market conditions
        for market in market_conditions:
            batch_data['records'].append({
                'type': 'market_conditions',
                'data': market
            })

        # Add ML predictions
        for ml_pred in ml_predictions:
            batch_data['records'].append({
                'type': 'ml_prediction',
                'data': ml_pred
            })

        batch_response = requests.post(f"{self.analytics_url}/analytics/batch", json=batch_data, timeout=15)
        self.assertEqual(batch_response.status_code, 200,
                        f"Batch operation failed with status {batch_response.status_code}")

        print(f"✅ Batch operation recorded {len(trades)} trades")

    def test_04_performance_tracking_scenario(self):
        """Test performance tracking - strategy and model performance"""
        print(f"\n🔄 Testing performance tracking scenario")

        # Create some trades first
        self.test_03_batch_operations_scenario()

        # Test strategy performance summary
        summary_response = requests.get(f"{self.analytics_url}/analytics/summary", timeout=10)
        self.assertEqual(summary_response.status_code, 200,
                        f"Summary failed with status {summary_response.status_code}")

        summary_data = summary_response.json()
        print(f"✅ Strategy performance summary: {summary_data}")

        # Test trades retrieval
        from datetime import datetime, timedelta

        # Get date range for the last 7 days
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=7)

        trades_response = requests.get(
            f"{self.analytics_url}/analytics/trades",
            params={
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat()
            },
            timeout=10
        )
        self.assertEqual(trades_response.status_code, 200,
                        f"Trades retrieval failed with status {trades_response.status_code}")

        trades_data = trades_response.json()
        print(f"✅ Retrieved {len(trades_data)} trades")

    def test_05_error_handling_scenarios(self):
        """Test error handling for various invalid scenarios"""
        print(f"\n🔄 Testing error handling scenarios")

        # Test invalid trade data (missing required fields)
        invalid_trade = {
            'trade_id': self.trade_id,
            'symbol': self.symbol,
            # Missing required fields
        }

        response = requests.post(f"{self.analytics_url}/analytics/trade", json=invalid_trade, timeout=10)
        self.assertIn(response.status_code, [400, 500],
                     f"Invalid trade should return error, got {response.status_code}")
        print(f"✅ Invalid trade properly rejected with status {response.status_code}")

        # Test invalid ML prediction data
        invalid_ml = {
            'trade_id': self.trade_id,
            'model_name': 'test_model',
            # Missing required fields
        }

        response = requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=invalid_ml, timeout=10)
        self.assertIn(response.status_code, [400, 500],
                     f"Invalid ML prediction should return error, got {response.status_code}")
        print(f"✅ Invalid ML prediction properly rejected with status {response.status_code}")

        # Test non-existent trade ID
        non_existent_trade = {
            'trade_id': 999999999,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
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

        response = requests.post(f"{self.analytics_url}/analytics/market_conditions", json=non_existent_trade, timeout=10)
        # This might succeed or fail depending on foreign key constraints
        print(f"✅ Non-existent trade test completed with status {response.status_code}")

    def test_06_data_consistency_scenarios(self):
        """Test data consistency across all tables"""
        print(f"\n🔄 Testing data consistency scenarios")

        # Create a complete trade scenario
        self.test_02_trade_exit_scenario()

        # Verify data consistency
        self._verify_data_consistency()

    def test_07_ml_trade_log_creates_trade(self):
        """Test that ML trade logs create corresponding trades in the trades table"""
        print(f"\n🔄 Testing ML trade log creates trade for trade_id: {self.trade_id}")

        # Generate a unique trade ID for this test
        test_trade_id = int(time.time() * 1000000)  # Use microseconds for uniqueness

        # Create ML trade log data (simulating what the EA sends)
        ml_trade_log_data = {
            'trade_id': str(test_trade_id),
            'strategy': self.strategy,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'direction': 'BUY',
            'entry_price': 50000.0,
            'stop_loss': 49500.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'ml_prediction': 0.85,  # FIXED: should be a float, not a string
            'ml_confidence': 0.85,
            'ml_model_type': 'buy',
            'ml_model_key': f'{self.symbol}_{self.timeframe}',
            'trade_time': int(time.time()),
            'status': 'OPEN',
            'timestamp': int(time.time()),
            # ML features
            'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
            'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
            'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
            'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
            'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
            'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
            'month': 7
        }

                # Send ML trade log to analytics service
        response = requests.post(f"{self.analytics_url}/ml_trade_log", json=ml_trade_log_data, timeout=10)

        if response.status_code != 201:
            print(f"❌ ML trade log failed with status {response.status_code}")
            print(f"❌ Response content: {response.text}")
            print(f"❌ Request data: {ml_trade_log_data}")

        self.assertEqual(response.status_code, 201,
                        f"ML trade log should be created, got status {response.status_code}")

        print(f"✅ ML trade log created with status {response.status_code}")

                        # Verify that a corresponding trade was created in the trades table
        # Use pymysql directly with test database config
        import pymysql

        test_config = self.db_manager.get_test_config()
        if not test_config:
            self.fail("Test database configuration not available")

        with pymysql.connect(**test_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check if trade exists in trades table
                cursor.execute("SELECT COUNT(*) as count FROM trades WHERE trade_id = %s", (str(test_trade_id),))
                result = cursor.fetchone()
                trade_exists = result['count'] > 0
                self.assertTrue(trade_exists, f"Trade {test_trade_id} should exist in trades table after ML trade log")

                # Get the trade details
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (str(test_trade_id),))
                trade_result = cursor.fetchone()

                self.assertIsNotNone(trade_result, "Trade query should return results")

                # Verify the trade has the correct data
                self.assertEqual(str(trade_result['trade_id']), str(test_trade_id))
                self.assertEqual(trade_result['symbol'], self.symbol)
                self.assertEqual(trade_result['timeframe'], self.timeframe)
                self.assertEqual(trade_result['direction'], 'BUY')
                self.assertEqual(float(trade_result['entry_price']), 50000.0)
                self.assertEqual(float(trade_result['stop_loss']), 49500.0)
                self.assertEqual(float(trade_result['take_profit']), 51000.0)
                self.assertEqual(float(trade_result['lot_size']), 0.1)
                self.assertEqual(trade_result['strategy_name'], self.strategy)
                self.assertEqual(trade_result['status'], 'OPEN')

                print(f"✅ Trade {test_trade_id} correctly created in trades table with all data")

                # Clean up test data
                cursor.execute("DELETE FROM ml_trade_logs WHERE trade_id = %s", (str(test_trade_id),))
                cursor.execute("DELETE FROM trades WHERE trade_id = %s", (str(test_trade_id),))
                connection.commit()
                print(f"✅ Test data cleaned up")

    def _verify_trade_entry_records(self):
        """Verify that trade entry created records in all relevant tables"""
        print("🔍 Verifying trade entry records...")

        # Import the verification functions from the database verification test
        from tests.integration.test_database_verification import TestDatabaseVerification

        # Create a temporary instance to use its verification methods
        temp_verifier = TestDatabaseVerification()
        temp_verifier.trade_id = self.trade_id
        temp_verifier.symbol = self.symbol
        temp_verifier.timeframe = self.timeframe
        temp_verifier.strategy = self.strategy
        temp_verifier.strategy_version = self.strategy_version
        temp_verifier.db_config = self.db_manager.get_test_config()

        # Verify records exist in all relevant tables
        temp_verifier._verify_trades_table_record()
        temp_verifier._verify_market_conditions_table_record()
        temp_verifier._verify_ml_predictions_table_record()
        temp_verifier._verify_ml_trade_logs_table_record()

        print(f"✅ Trade entry verification completed for trade_id: {self.trade_id}")

    def _verify_trade_exit_records(self):
        """Verify that trade exit updated records in all relevant tables"""
        print("🔍 Verifying trade exit records...")

        # Import the verification functions from the database verification test
        from tests.integration.test_database_verification import TestDatabaseVerification

        # Create a temporary instance to use its verification methods
        temp_verifier = TestDatabaseVerification()
        temp_verifier.trade_id = self.trade_id
        temp_verifier.symbol = self.symbol
        temp_verifier.timeframe = self.timeframe
        temp_verifier.strategy = self.strategy
        temp_verifier.strategy_version = self.strategy_version
        temp_verifier.db_config = self.db_manager.get_test_config()

        # Verify updated records exist in all relevant tables
        temp_verifier._verify_trades_table_updated_record()
        temp_verifier._verify_ml_trade_closes_table_record()

        print(f"✅ Trade exit verification completed for trade_id: {self.trade_id}")

    def _verify_ml_trade_logs_updated_record(self):
        """Verify that ml_trade_logs record was updated with close information"""
        print("🔍 Verifying ml_trade_logs updated record...")

        import pymysql

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM ml_trade_logs WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"Updated ml_trade_logs record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['status'], 'CLOSED')
                self.assertEqual(float(result['close_price']), 50500.0)
                self.assertEqual(float(result['profit_loss']), 500.0)
                self.assertIsNotNone(result['close_time'])
                self.assertEqual(result['exit_reason'], 'take_profit')

                print(f"✅ ML trade logs updated record verified for trade_id: {self.trade_id}")

    def _verify_data_consistency(self):
        """Verify data consistency across all tables"""
        print("🔍 Verifying data consistency...")

        # Import the verification functions from the database verification test
        from tests.integration.test_database_verification import TestDatabaseVerification

        # Create a temporary instance to use its verification methods
        temp_verifier = TestDatabaseVerification()
        temp_verifier.trade_id = self.trade_id
        temp_verifier.symbol = self.symbol
        temp_verifier.timeframe = self.timeframe
        temp_verifier.strategy = self.strategy
        temp_verifier.strategy_version = self.strategy_version
        temp_verifier.db_config = self.db_manager.get_test_config()

        # Verify foreign key relationships
        temp_verifier._verify_foreign_key_relationships()

        # Verify data types and constraints
        temp_verifier._verify_data_types()
        temp_verifier._verify_constraints()

        # Verify business logic consistency
        self._verify_business_logic_consistency()

        print("✅ Data consistency verification completed")

    def _verify_business_logic_consistency(self):
        """Verify business logic consistency across tables"""
        print("🔍 Verifying business logic consistency...")

        # Import pymysql for database queries
        import pymysql

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Verify that trade status is consistent
                cursor.execute("""
                    SELECT t.status, t.entry_time, t.exit_time, t.profit_loss
                    FROM trades t
                    WHERE t.trade_id = %s
                """, (self.trade_id,))
                trade_result = cursor.fetchone()

                if trade_result:
                    # If trade is CLOSED, it should have exit_time and profit_loss
                    if trade_result['status'] == 'CLOSED':
                        self.assertIsNotNone(trade_result['exit_time'],
                                           "Closed trade should have exit_time")
                        self.assertIsNotNone(trade_result['profit_loss'],
                                           "Closed trade should have profit_loss")

                    # If trade is OPEN, it should not have exit_time
                    elif trade_result['status'] == 'OPEN':
                        self.assertIsNone(trade_result['exit_time'],
                                        "Open trade should not have exit_time")

                # Verify that ML prediction confidence is within valid range (0-1)
                cursor.execute("""
                    SELECT prediction_probability, confidence_score
                    FROM ml_predictions
                    WHERE trade_id = %s
                """, (self.trade_id,))
                ml_result = cursor.fetchone()

                if ml_result:
                    self.assertGreaterEqual(float(ml_result['prediction_probability']), 0,
                                          "Prediction probability should be >= 0")
                    self.assertLessEqual(float(ml_result['prediction_probability']), 1,
                                       "Prediction probability should be <= 1")
                    self.assertGreaterEqual(float(ml_result['confidence_score']), 0,
                                          "Confidence score should be >= 0")
                    self.assertLessEqual(float(ml_result['confidence_score']), 1,
                                       "Confidence score should be <= 1")

                # Verify that market conditions have reasonable values
                cursor.execute("""
                    SELECT rsi, stoch_main, stoch_signal, macd_main, macd_signal
                    FROM market_conditions
                    WHERE trade_id = %s
                """, (self.trade_id,))
                market_result = cursor.fetchone()

                if market_result:
                    # RSI should be between 0 and 100
                    if market_result['rsi'] is not None:
                        self.assertGreaterEqual(float(market_result['rsi']), 0,
                                              "RSI should be >= 0")
                        self.assertLessEqual(float(market_result['rsi']), 100,
                                           "RSI should be <= 100")

                    # Stochastic values should be between 0 and 100
                    if market_result['stoch_main'] is not None:
                        self.assertGreaterEqual(float(market_result['stoch_main']), 0,
                                              "Stochastic main should be >= 0")
                        self.assertLessEqual(float(market_result['stoch_main']), 100,
                                           "Stochastic main should be <= 100")

                    if market_result['stoch_signal'] is not None:
                        self.assertGreaterEqual(float(market_result['stoch_signal']), 0,
                                              "Stochastic signal should be >= 0")
                        self.assertLessEqual(float(market_result['stoch_signal']), 100,
                                           "Stochastic signal should be <= 100")

        print("✅ Business logic consistency verified")


if __name__ == '__main__':
    unittest.main()
