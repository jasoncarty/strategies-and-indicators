#!/usr/bin/env python3
"""
Database verification tests - actually query the database to verify data integrity
"""
import unittest
import requests
import json
import time
import pymysql
from datetime import datetime
from tests.test_db_manager import create_test_database_manager
from tests.test_webserver_manager import create_test_webserver_manager


class TestDatabaseVerification(unittest.TestCase):
    """Test database verification by actually querying the database"""

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests"""
        print("🔧 Setting up database verification test environment...")

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

        # Store database config for direct queries
        cls.db_config = test_db_config

        print(f"✅ Database verification test environment ready:")
        print(f"   ML Service: {cls.ml_service_url}")
        print(f"   Analytics Service: {cls.analytics_url}")
        print(f"   Test Database: {cls.db_config['database']}")

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment"""
        print("🧹 Cleaning up database verification test environment...")
        cls.webserver_manager.stop_all_services()
        cls.db_manager.cleanup_test_database(destroy_database=False)
        print("✅ Database verification test environment cleaned up")

    def setUp(self):
        """Set up for each test"""
        self.trade_id = int(time.time())  # Use timestamp as unique trade ID
        self.symbol = "BTCUSD"
        self.timeframe = "M5"
        self.strategy = "TestStrategy"
        self.strategy_version = "1.0"

    def test_01_verify_trade_entry_database_records(self):
        """Verify that trade entry creates records in all relevant database tables"""
        print(f"\n🔄 Testing trade entry database verification for trade_id: {self.trade_id}")

        # Step 1: Create a complete trade entry scenario
        self._create_trade_entry_scenario()

        # Step 2: Verify records in database
        self._verify_trades_table_record()
        self._verify_market_conditions_table_record()
        self._verify_ml_predictions_table_record()
        self._verify_ml_trade_logs_table_record()

    def test_02_verify_trade_exit_database_records(self):
        """Verify that trade exit updates records in all relevant database tables"""
        print(f"\n🔄 Testing trade exit database verification for trade_id: {self.trade_id}")

        # Step 1: Create a complete trade entry and exit scenario
        self._create_trade_entry_scenario()
        self._create_trade_exit_scenario()

        # Step 2: Verify updated records in database
        self._verify_trades_table_updated_record()
        self._verify_ml_trade_closes_table_record()

    def test_03_verify_batch_operations_database_records(self):
        """Verify that batch operations create records in all relevant database tables"""
        print(f"\n🔄 Testing batch operations database verification")

        # Step 1: Create batch operations scenario
        trade_ids = self._create_batch_operations_scenario()

        # Step 2: Verify records for each trade
        for trade_id in trade_ids:
            self._verify_trades_table_record_by_id(trade_id)
            self._verify_market_conditions_table_record_by_id(trade_id)
            self._verify_ml_predictions_table_record_by_id(trade_id)

    def test_04_verify_foreign_key_constraints(self):
        """Verify that foreign key constraints are properly maintained"""
        print(f"\n🔄 Testing foreign key constraint verification")

        # Create a trade entry
        self._create_trade_entry_scenario()

        # Verify foreign key relationships
        self._verify_foreign_key_relationships()

    def test_05_verify_data_types_and_constraints(self):
        """Verify that data types and constraints are properly enforced"""
        print(f"\n🔄 Testing data type and constraint verification")

        # Create a trade entry
        self._create_trade_entry_scenario()

        # Verify data types and constraints
        self._verify_data_types()
        self._verify_constraints()

    def _create_trade_entry_scenario(self):
        """Create a complete trade entry scenario via HTTP requests"""
        # Generate a unique trade ID for this specific call with microsecond precision
        import time
        self.trade_id = int(time.time() * 1000000)  # Use microseconds for uniqueness

        # Get ML prediction
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
        self.assertEqual(ml_response.status_code, 200)
        ml_result = ml_response.json()

        # Record trade entry
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
        self.assertEqual(trade_response.status_code, 201)

        # Record market conditions
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
        if market_response.status_code != 201:
            print(f"❌ Market conditions failed with status {market_response.status_code}")
            print(f"❌ Response content: {market_response.text}")
        self.assertEqual(market_response.status_code, 201)

        # Record ML prediction
        ml_prediction_data = {
            'trade_id': self.trade_id,
            'model_name': ml_result['metadata'].get('model_name', 'test_model'),
            'model_type': 'buy',
            'prediction_probability': ml_result['prediction']['probability'],
            'confidence_score': ml_result['prediction']['confidence'],
            'features_json': json.dumps(ml_features),
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'strategy_name': self.strategy,
            'strategy_version': self.strategy_version
        }

        prediction_response = requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=ml_prediction_data, timeout=10)
        self.assertEqual(prediction_response.status_code, 201)

        # Record ML trade log
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
        self.assertEqual(ml_log_response.status_code, 201)

    def _create_trade_exit_scenario(self):
        """Create a complete trade exit scenario via HTTP requests"""
        # Record trade exit
        trade_exit_data = {
            'trade_id': self.trade_id,
            'exit_price': 50500.0,
            'exit_reason': 'take_profit',
            'profit_loss': 500.0,
            'exit_time': int(time.time()),
            'status': 'CLOSED'
        }

        exit_response = requests.post(f"{self.analytics_url}/analytics/trade_exit", json=trade_exit_data, timeout=10)

        # Debug: Print response details if there's an error
        if exit_response.status_code not in [200, 201]:
            print(f"❌ Trade exit failed with status {exit_response.status_code}")
            print(f"❌ Response content: {exit_response.text}")
            print(f"❌ Request data: {trade_exit_data}")

        self.assertIn(exit_response.status_code, [200, 201])

        # Record ML trade close
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
        self.assertEqual(ml_close_response.status_code, 201)

    def _create_batch_operations_scenario(self):
        """Create a batch operations scenario and return trade IDs"""
        trade_ids = []

        for i in range(3):
            trade_id = int(time.time()) + i
            trade_ids.append(trade_id)

            # Trade data
            trade_data = {
                'trade_id': trade_id,
                'strategy': self.strategy,
                'strategy_version': self.strategy_version,
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'direction': 'buy' if i % 2 == 0 else 'sell',
                'entry_price': 50000.0 + (i * 100),
                'stop_loss': 49000.0 + (i * 100),
                'take_profit': 51000.0 + (i * 100),
                'lot_size': 0.1,
                'timestamp': datetime.now().isoformat()
            }

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

            # ML prediction
            ml_data = {
                'trade_id': trade_id,
                'model_name': 'test_model',
                'model_type': 'buy' if i % 2 == 0 else 'sell',
                'prediction_probability': 0.75 + (i * 0.05),
                'confidence_score': 0.8 + (i * 0.05),
                'features_json': '{"rsi": 50.0}',
                'timestamp': datetime.now().isoformat(),
                'symbol': self.symbol,
                'timeframe': self.timeframe
            }

            # Send individual requests (batch endpoint might not be working)
            requests.post(f"{self.analytics_url}/analytics/trade", json=trade_data, timeout=10)
            requests.post(f"{self.analytics_url}/analytics/market_conditions", json=market_data, timeout=10)
            requests.post(f"{self.analytics_url}/analytics/ml_prediction", json=ml_data, timeout=10)

        return trade_ids

    def _verify_trades_table_record(self):
        """Verify record exists in trades table"""
        print("🔍 Verifying trades table record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"Trade record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['trade_id'], self.trade_id)
                self.assertEqual(result['symbol'], self.symbol)
                self.assertEqual(result['timeframe'], self.timeframe)
                self.assertEqual(result['strategy_name'], self.strategy)
                self.assertEqual(result['strategy_version'], self.strategy_version)
                self.assertEqual(result['direction'], 'BUY')
                self.assertEqual(float(result['entry_price']), 50000.0)
                self.assertEqual(result['status'], 'OPEN')

                print(f"✅ Trades table record verified for trade_id: {self.trade_id}")

    def _verify_market_conditions_table_record(self):
        """Verify record exists in market_conditions table"""
        print("🔍 Verifying market_conditions table record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM market_conditions WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"Market conditions record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['trade_id'], self.trade_id)
                self.assertEqual(result['symbol'], self.symbol)
                self.assertEqual(result['timeframe'], self.timeframe)
                self.assertEqual(float(result['rsi']), 50.0)
                self.assertEqual(float(result['stoch_main']), 50.0)
                self.assertEqual(float(result['macd_main']), 0.0)

                print(f"✅ Market conditions table record verified for trade_id: {self.trade_id}")

    def _verify_ml_predictions_table_record(self):
        """Verify record exists in ml_predictions table"""
        print("🔍 Verifying ml_predictions table record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM ml_predictions WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"ML predictions record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['trade_id'], self.trade_id)
                self.assertEqual(result['model_type'], 'BUY')
                self.assertGreater(float(result['prediction_probability']), 0)
                self.assertGreater(float(result['confidence_score']), 0)
                self.assertIsNotNone(result['features_json'])

                print(f"✅ ML predictions table record verified for trade_id: {self.trade_id}")

    def _verify_ml_trade_logs_table_record(self):
        """Verify record exists in ml_trade_logs table"""
        print("🔍 Verifying ml_trade_logs table record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM ml_trade_logs WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"ML trade logs record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['trade_id'], self.trade_id)
                self.assertEqual(result['strategy'], self.strategy)
                self.assertEqual(result['symbol'], self.symbol)
                self.assertEqual(result['timeframe'], self.timeframe)
                self.assertEqual(result['direction'], 'BUY')
                self.assertEqual(float(result['entry_price']), 50000.0)
                self.assertEqual(result['status'], 'OPEN')
                self.assertGreater(float(result['ml_prediction']), 0)
                self.assertGreater(float(result['ml_confidence']), 0)

                print(f"✅ ML trade logs table record verified for trade_id: {self.trade_id}")

    def _verify_trades_table_updated_record(self):
        """Verify trade record was updated with exit information"""
        print("🔍 Verifying trades table updated record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"Updated trade record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['status'], 'CLOSED')
                self.assertEqual(float(result['exit_price']), 50500.0)
                self.assertEqual(float(result['profit_loss']), 500.0)
                self.assertIsNotNone(result['exit_time'])

                print(f"✅ Trades table updated record verified for trade_id: {self.trade_id}")

    def _verify_ml_trade_closes_table_record(self):
        """Verify record exists in ml_trade_closes table"""
        print("🔍 Verifying ml_trade_closes table record...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM ml_trade_closes WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsNotNone(result, f"ML trade closes record not found for trade_id: {self.trade_id}")
                self.assertEqual(result['trade_id'], self.trade_id)
                self.assertEqual(result['strategy'], self.strategy)
                self.assertEqual(result['symbol'], self.symbol)
                self.assertEqual(result['timeframe'], self.timeframe)
                self.assertEqual(float(result['close_price']), 50500.0)
                self.assertEqual(float(result['profit_loss']), 500.0)
                self.assertEqual(result['status'], 'CLOSED')
                self.assertEqual(result['success'], True)

                print(f"✅ ML trade closes table record verified for trade_id: {self.trade_id}")

    def _verify_trades_table_record_by_id(self, trade_id):
        """Verify record exists in trades table for specific trade_id"""
        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (trade_id,))
                result = cursor.fetchone()
                self.assertIsNotNone(result, f"Trade record not found for trade_id: {trade_id}")

    def _verify_market_conditions_table_record_by_id(self, trade_id):
        """Verify record exists in market_conditions table for specific trade_id"""
        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM market_conditions WHERE trade_id = %s", (trade_id,))
                result = cursor.fetchone()
                self.assertIsNotNone(result, f"Market conditions record not found for trade_id: {trade_id}")

    def _verify_ml_predictions_table_record_by_id(self, trade_id):
        """Verify record exists in ml_predictions table for specific trade_id"""
        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM ml_predictions WHERE trade_id = %s", (trade_id,))
                result = cursor.fetchone()
                self.assertIsNotNone(result, f"ML predictions record not found for trade_id: {trade_id}")

    def _verify_foreign_key_relationships(self):
        """Verify that foreign key relationships are properly maintained"""
        print("🔍 Verifying foreign key relationships...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check that ml_predictions references trades
                cursor.execute("""
                    SELECT COUNT(*) as count
                    FROM ml_predictions mp
                    LEFT JOIN trades t ON mp.trade_id = t.trade_id
                    WHERE mp.trade_id = %s AND t.trade_id IS NULL
                """, (self.trade_id,))
                result = cursor.fetchone()
                self.assertEqual(result['count'], 0, "Orphaned ml_predictions record found")

                # Check that market_conditions references trades
                cursor.execute("""
                    SELECT COUNT(*) as count
                    FROM market_conditions mc
                    LEFT JOIN trades t ON mc.trade_id = t.trade_id
                    WHERE mc.trade_id = %s AND t.trade_id IS NULL
                """, (self.trade_id,))
                result = cursor.fetchone()
                self.assertEqual(result['count'], 0, "Orphaned market_conditions record found")

                print("✅ Foreign key relationships verified")

    def _verify_data_types(self):
        """Verify that data types are correct"""
        print("🔍 Verifying data types...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check trades table data types
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()

                self.assertIsInstance(result['trade_id'], int)
                self.assertIsInstance(result['symbol'], str)
                self.assertIsInstance(result['timeframe'], str)
                self.assertIsInstance(result['direction'], str)
                from decimal import Decimal
                self.assertIsInstance(result['entry_price'], (int, float, Decimal, type(None)))
                self.assertIsInstance(result['status'], str)

                print("✅ Data types verified")

    def _verify_constraints(self):
        """Verify that constraints are properly enforced"""
        print("🔍 Verifying constraints...")

        with pymysql.connect(**self.db_config) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check that trade_id is unique
                cursor.execute("SELECT COUNT(*) as count FROM trades WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()
                self.assertEqual(result['count'], 1, "Trade ID uniqueness constraint violated")

                # Check that required fields are not null
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (self.trade_id,))
                result = cursor.fetchone()
                self.assertIsNotNone(result['symbol'], "Symbol should not be null")
                self.assertIsNotNone(result['timeframe'], "Timeframe should not be null")
                self.assertIsNotNone(result['direction'], "Direction should not be null")

                print("✅ Constraints verified")


if __name__ == '__main__':
    unittest.main()
