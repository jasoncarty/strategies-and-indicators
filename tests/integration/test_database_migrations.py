#!/usr/bin/env python3
"""
Integration tests for database migrations and schema verification
"""
import unittest
import pymysql
import os
import sys
from pathlib import Path
from datetime import datetime
import time

# Add the project root to the path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from tests.test_db_manager import create_test_database_manager
from tests.test_webserver_manager import create_test_webserver_manager


class TestDatabaseMigrations(unittest.TestCase):
    """Test database migrations and schema verification"""

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests"""
        print("🔧 Setting up database migration test environment...")

        # Create test database
        cls.db_manager = create_test_database_manager()
        cls.db_manager.setup_test_database()

        # Create test webserver manager
        cls.webserver_manager = create_test_webserver_manager()

        # Start analytics service with test database
        test_db_config = cls.db_manager.get_test_config()
        if test_db_config:
            analytics_started = cls.webserver_manager.start_analytics_service(test_db_config)
            if not analytics_started:
                raise Exception("Analytics service failed to start - this is a critical integration test failure")
        else:
            raise Exception("Test database configuration not available - this is a critical integration test failure")

        # Get service URLs
        cls.service_urls = cls.webserver_manager.get_all_urls()
        cls.analytics_url = cls.service_urls.get('analytics', 'http://127.0.0.1:5002')

        print(f"✅ Database migration test environment ready:")
        print(f"   Analytics Service: {cls.analytics_url}")
        print(f"   Test Database: {cls.db_manager.test_db_name}")

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment"""
        print("🧹 Cleaning up database migration test environment...")

        # Stop all services
        cls.webserver_manager.stop_all_services()

        # Clean up test database
        cls.db_manager.cleanup_test_database(destroy_database=False)

        print("✅ Database migration test environment cleaned up")

    def test_01_verify_migration_log_table_exists(self):
        """Verify that migration_log table exists and contains expected migrations"""
        print("\n🔄 Testing migration log table verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check if migration_log table exists
                cursor.execute("SHOW TABLES LIKE 'migration_log'")
                result = cursor.fetchall()

                self.assertTrue(result, "Migration log table should exist")
                print("✅ Migration log table exists")

                # Check migration log entries
                cursor.execute("SELECT * FROM migration_log ORDER BY id")
                migrations = cursor.fetchall()

                # Dynamically count migration files from filesystem
                migrations_dir = Path(__file__).parent.parent.parent / 'analytics' / 'database' / 'migrations'
                migration_files = sorted([f.name for f in migrations_dir.glob("*.sql")])
                expected_migrations = len(migration_files)

                self.assertEqual(len(migrations), expected_migrations,
                               f"Expected {expected_migrations} migrations, found {len(migrations)}")

                # Verify all migration files from filesystem have been executed
                executed_filenames = [migration['filename'] for migration in migrations]
                for migration_file in migration_files:
                    self.assertIn(migration_file, executed_filenames,
                                f"Migration file {migration_file} has not been executed")

                print(f"✅ Found {len(migrations)} migration records")
                for migration in migrations:
                    print(f"   - {migration['filename']} (executed at {migration['executed_at']})")

    def test_02_verify_market_conditions_table_schema(self):
        """Verify that market_conditions table has the correct schema"""
        print("\n🔄 Testing market conditions table schema verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE market_conditions")
                columns = cursor.fetchall()

                # Expected columns (after all migrations - removed atr, added williams_r and force_index)
                expected_columns = {
                    'id': 'bigint',
                    'trade_id': 'bigint',  # Changed from varchar to bigint in migration 004
                    'symbol': 'varchar',
                    'timeframe': 'varchar',
                    'rsi': 'decimal',
                    'stoch_main': 'decimal',
                    'stoch_signal': 'decimal',
                    'macd_main': 'decimal',
                    'macd_signal': 'decimal',
                    'bb_upper': 'decimal',
                    'bb_lower': 'decimal',
                    'cci': 'decimal',
                    'momentum': 'decimal',
                    'volume_ratio': 'decimal',
                    'price_change': 'decimal',
                    'volatility': 'decimal',
                    'spread': 'decimal',
                    'session_hour': 'int',
                    'day_of_week': 'int',
                    'month': 'int',
                    'recorded_at': 'timestamp',
                    'williams_r': 'decimal',
                    'force_index': 'decimal'
                }

                # Verify column count
                self.assertEqual(len(columns), len(expected_columns),
                               f"Expected {len(expected_columns)} columns, found {len(columns)}")

                # Verify each expected column exists
                actual_columns = {col['Field']: col['Type'] for col in columns}

                for expected_col, expected_type in expected_columns.items():
                    self.assertIn(expected_col, actual_columns,
                                f"Expected column '{expected_col}' not found")

                    # Check type (loosely - just verify it contains the expected type)
                    actual_type = actual_columns[expected_col].lower()
                    self.assertTrue(expected_type in actual_type,
                                  f"Column '{expected_col}' has type '{actual_type}', expected '{expected_type}'")

                # Verify removed columns don't exist
                removed_columns = ['adx', 'breakout_level', 'retest_level', 'swing_point', 'breakout_direction', 'atr']
                for removed_col in removed_columns:
                    self.assertNotIn(removed_col, actual_columns,
                                   f"Removed column '{removed_col}' still exists")

                print(f"✅ Market conditions table has correct schema with {len(columns)} columns")
                print("✅ All expected columns present")
                print("✅ All removed columns absent")

    def test_03_verify_trades_table_schema(self):
        """Verify that trades table has the correct schema"""
        print("\n🔄 Testing trades table schema verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE trades")
                columns = cursor.fetchall()

                # Expected columns (actual schema has 21 columns)
                expected_columns = {
                    'id': 'bigint',
                    'trade_id': 'bigint',  # Changed from varchar to bigint in migration 004
                    'symbol': 'varchar',
                    'timeframe': 'varchar',
                    'direction': 'enum',
                    'entry_price': 'decimal',
                    'exit_price': 'decimal',
                    'stop_loss': 'decimal',
                    'take_profit': 'decimal',
                    'lot_size': 'decimal',
                    'profit_loss': 'decimal',
                    'profit_loss_pips': 'decimal',
                    'entry_time': 'datetime',
                    'exit_time': 'datetime',
                    'duration_seconds': 'int',
                    'status': 'enum',
                    'strategy_name': 'varchar',
                    'strategy_version': 'varchar',
                    'account_id': 'varchar',
                    'created_at': 'timestamp',
                    'updated_at': 'timestamp'  # Added in migration
                }

                # Verify column count
                self.assertEqual(len(columns), len(expected_columns),
                               f"Expected {len(expected_columns)} columns, found {len(columns)}")

                # Verify each expected column exists
                actual_columns = {col['Field']: col['Type'] for col in columns}

                for expected_col, expected_type in expected_columns.items():
                    self.assertIn(expected_col, actual_columns,
                                f"Expected column '{expected_col}' not found")

                    # Check type (loosely)
                    actual_type = actual_columns[expected_col].lower()
                    self.assertTrue(expected_type in actual_type,
                                  f"Column '{expected_col}' has type '{actual_type}', expected '{expected_type}'")

                print(f"✅ Trades table has correct schema with {len(columns)} columns")

    def test_04_verify_ml_predictions_table_schema(self):
        """Verify that ml_predictions table has the correct schema"""
        print("\n🔄 Testing ML predictions table schema verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE ml_predictions")
                columns = cursor.fetchall()

                # Expected columns
                expected_columns = {
                    'id': 'bigint',
                    'trade_id': 'bigint',  # Changed from varchar to bigint in migration 004
                    'model_name': 'varchar',
                    'model_type': 'enum',
                    'prediction_probability': 'decimal',
                    'confidence_score': 'decimal',
                    'features_json': 'json',
                    'prediction_time': 'timestamp',
                    'symbol': 'varchar',
                    'timeframe': 'varchar',
                    'strategy_name': 'varchar',
                    'strategy_version': 'varchar'
                }

                # Verify column count
                self.assertEqual(len(columns), len(expected_columns),
                               f"Expected {len(expected_columns)} columns, found {len(columns)}")

                # Verify each expected column exists
                actual_columns = {col['Field']: col['Type'] for col in columns}

                for expected_col, expected_type in expected_columns.items():
                    self.assertIn(expected_col, actual_columns,
                                f"Expected column '{expected_col}' not found")

                    # Check type (loosely)
                    actual_type = actual_columns[expected_col].lower()
                    self.assertTrue(expected_type in actual_type,
                                  f"Column '{expected_col}' has type '{actual_type}', expected '{expected_type}'")

                print(f"✅ ML predictions table has correct schema with {len(columns)} columns")

    def test_05_verify_ml_trade_logs_table_schema(self):
        """Verify that ml_trade_logs table has the correct schema"""
        print("\n🔄 Testing ML trade logs table schema verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE ml_trade_logs")
                columns = cursor.fetchall()

                # Expected columns
                expected_columns = {
                    'id': 'int',
                    'trade_id': 'bigint',  # Changed from varchar to bigint in migration 004
                    'strategy': 'varchar',
                    'symbol': 'varchar',
                    'timeframe': 'varchar',
                    'direction': 'enum',
                    'entry_price': 'decimal',
                    'stop_loss': 'decimal',
                    'take_profit': 'decimal',
                    'lot_size': 'decimal',
                    'ml_prediction': 'decimal',
                    'ml_confidence': 'decimal',
                    'ml_model_type': 'varchar',
                    'ml_model_key': 'varchar',
                    'trade_time': 'bigint',
                    'features_json': 'json',
                    'status': 'enum',
                    'profit_loss': 'decimal',
                    'close_price': 'decimal',
                    'close_time': 'bigint',
                    'exit_reason': 'varchar',
                    'timestamp': 'bigint',
                    'created_at': 'timestamp',
                    'updated_at': 'timestamp'
                }

                # Verify column count
                self.assertEqual(len(columns), len(expected_columns),
                               f"Expected {len(expected_columns)} columns, found {len(columns)}")

                # Verify each expected column exists
                actual_columns = {col['Field']: col['Type'] for col in columns}

                for expected_col, expected_type in expected_columns.items():
                    self.assertIn(expected_col, actual_columns,
                                f"Expected column '{expected_col}' not found")

                    # Check type (loosely)
                    actual_type = actual_columns[expected_col].lower()
                    self.assertTrue(expected_type in actual_type,
                                  f"Column '{expected_col}' has type '{actual_type}', expected '{expected_type}'")

                print(f"✅ ML trade logs table has correct schema with {len(columns)} columns")

    def test_06_verify_ml_trade_closes_table_schema(self):
        """Verify that ml_trade_closes table has the correct schema"""
        print("\n🔄 Testing ML trade closes table schema verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE ml_trade_closes")
                columns = cursor.fetchall()

                # Expected columns
                expected_columns = {
                    'id': 'int',
                    'trade_id': 'bigint',  # Changed from varchar to bigint in migration 004
                    'strategy': 'varchar',
                    'symbol': 'varchar',
                    'timeframe': 'varchar',
                    'close_price': 'decimal',
                    'profit_loss': 'decimal',
                    'profit_loss_pips': 'decimal',
                    'close_time': 'bigint',
                    'exit_reason': 'varchar',
                    'status': 'enum',
                    'success': 'tinyint',
                    'timestamp': 'bigint',
                    'created_at': 'timestamp'
                }

                # Verify column count
                self.assertEqual(len(columns), len(expected_columns),
                               f"Expected {len(expected_columns)} columns, found {len(columns)}")

                # Verify each expected column exists
                actual_columns = {col['Field']: col['Type'] for col in columns}

                for expected_col, expected_type in expected_columns.items():
                    self.assertIn(expected_col, actual_columns,
                                f"Expected column '{expected_col}' not found")

                    # Check type (loosely)
                    actual_type = actual_columns[expected_col].lower()
                    self.assertTrue(expected_type in actual_type,
                                  f"Column '{expected_col}' has type '{actual_type}', expected '{expected_type}'")

                print(f"✅ ML trade closes table has correct schema with {len(columns)} columns")

    def test_07_verify_foreign_key_constraints(self):
        """Verify that foreign key constraints are properly set up"""
        print("\n🔄 Testing foreign key constraints verification...")

        with pymysql.connect(**self.db_manager.get_test_config()) as connection:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get foreign key constraints
                cursor.execute("""
                    SELECT
                        TABLE_NAME,
                        COLUMN_NAME,
                        CONSTRAINT_NAME,
                        REFERENCED_TABLE_NAME,
                        REFERENCED_COLUMN_NAME
                    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
                    WHERE REFERENCED_TABLE_SCHEMA = DATABASE()
                    AND REFERENCED_TABLE_NAME IS NOT NULL
                    ORDER BY TABLE_NAME, COLUMN_NAME
                """)
                foreign_keys = cursor.fetchall()

                # Expected foreign key relationships
                expected_fks = [
                    ('market_conditions', 'trade_id', 'trades', 'trade_id'),
                    ('ml_predictions', 'trade_id', 'trades', 'trade_id'),
                ]

                # Verify foreign key count
                self.assertEqual(len(foreign_keys), len(expected_fks),
                               f"Expected {len(expected_fks)} foreign keys, found {len(foreign_keys)}")

                # Verify each expected foreign key exists
                actual_fks = [(fk['TABLE_NAME'], fk['COLUMN_NAME'],
                              fk['REFERENCED_TABLE_NAME'], fk['REFERENCED_COLUMN_NAME'])
                             for fk in foreign_keys]

                for expected_fk in expected_fks:
                    self.assertIn(expected_fk, actual_fks,
                                f"Expected foreign key {expected_fk} not found")

                print(f"✅ Found {len(foreign_keys)} foreign key constraints")
                for fk in foreign_keys:
                    print(f"   - {fk['TABLE_NAME']}.{fk['COLUMN_NAME']} -> {fk['REFERENCED_TABLE_NAME']}.{fk['REFERENCED_COLUMN_NAME']}")

    def test_08_verify_market_conditions_insert_works(self):
        """Verify that market conditions insert works with the current schema"""
        print("\n🔄 Testing market conditions insert functionality...")

        # First create a trade record
        trade_data = {
            'trade_id': int(time.time()),  # Use unique timestamp as trade_id
            'strategy_name': 'TestStrategy',
            'strategy_version': '1.0',
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'direction': 'buy',
            'entry_price': 1.1000,
            'stop_loss': 1.0950,
            'take_profit': 1.1050,
            'lot_size': 0.1,
            'entry_time': int(time.time()),
            'status': 'OPEN',
            'account_id': 'TEST_ACCOUNT'
        }

        # Insert trade via HTTP
        import requests
        trade_response = requests.post(f"{self.analytics_url}/analytics/trade",
                                     json=trade_data, timeout=10)
        self.assertEqual(trade_response.status_code, 201,
                        f"Trade insert failed with status {trade_response.status_code}")

        # Now try to insert market conditions
        market_conditions = {
            'trade_id': trade_data['trade_id'],  # Use the same trade_id as the trade
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'rsi': 50.0,
            'stoch_main': 50.0,
            'stoch_signal': 50.0,
            'macd_main': 0.0,
            'macd_signal': 0.0,
            'bb_upper': 1.1000,
            'bb_lower': 1.0900,
            'cci': 0.0,
            'momentum': 0.0,
            'volume_ratio': 1.0,
            'price_change': 0.0,
            'volatility': 0.0,
            'spread': 0.0,
            'session_hour': 10,
            'day_of_week': 1,
            'month': 8
        }

        market_response = requests.post(f"{self.analytics_url}/analytics/market_conditions",
                                      json=market_conditions, timeout=10)

        if market_response.status_code != 201:
            print(f"❌ Market conditions insert failed with status {market_response.status_code}")
            print(f"❌ Response: {market_response.text}")
            self.fail(f"Market conditions insert failed with status {market_response.status_code}")

        print("✅ Market conditions insert works correctly")

    def test_09_verify_production_vs_test_schema_consistency(self):
        """Verify that production and test database schemas are consistent"""
        print("\n🔄 Testing production vs test schema consistency...")

        # Get test database schema
        test_config = self.db_manager.get_test_config()
        with pymysql.connect(**test_config) as test_conn:
            with test_conn.cursor(pymysql.cursors.DictCursor) as test_cursor:
                test_cursor.execute("DESCRIBE market_conditions")
                test_columns = test_cursor.fetchall()

        # Get production database schema
        from analytics.database.config import db_config
        with pymysql.connect(**db_config.get_connection_params()) as prod_conn:
            with prod_conn.cursor(pymysql.cursors.DictCursor) as prod_cursor:
                prod_cursor.execute("DESCRIBE market_conditions")
                prod_columns = prod_cursor.fetchall()

        # Compare schemas
        test_schema = {col['Field']: col['Type'] for col in test_columns}
        prod_schema = {col['Field']: col['Type'] for col in prod_columns}

        # Verify same number of columns
        self.assertEqual(len(test_schema), len(prod_schema),
                        f"Schema mismatch: test has {len(test_schema)} columns, production has {len(prod_schema)} columns")

        # Verify same columns
        self.assertEqual(set(test_schema.keys()), set(prod_schema.keys()),
                        f"Column mismatch: test has {set(test_schema.keys())}, production has {set(prod_schema.keys())}")

        # Verify same types (loosely)
        for col in test_schema:
            test_type = test_schema[col].lower()
            prod_type = prod_schema[col].lower()

            # Extract base type (before precision/scale)
            test_base = test_type.split('(')[0]
            prod_base = prod_type.split('(')[0]

            self.assertEqual(test_base, prod_base,
                           f"Type mismatch for column '{col}': test has '{test_type}', production has '{prod_type}'")

        print("✅ Production and test database schemas are consistent")


if __name__ == '__main__':
    unittest.main(verbosity=2)
