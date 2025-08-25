#!/usr/bin/env python3
"""
Database verification tests using Docker services
Tests data integrity by actually querying the Docker test database
"""

import pytest
import requests
import json
import time
import pymysql
from datetime import datetime


class TestDatabaseVerification:
    """Integration tests for database verification using Docker services"""

    @pytest.fixture
    def test_database_config(self, request):
        """Get test database configuration from environment variables"""
        return request.getfixturevalue('test_database_config')

    @pytest.fixture
    def analytics_service_url(self, request):
        """Get analytics service URL from Docker environment"""
        return request.getfixturevalue('test_services')['analytics']

    @pytest.fixture
    def ml_service_url(self, request):
        """Get ML service URL from Docker environment"""
        return request.getfixturevalue('test_services')['ml_service']

    @pytest.fixture
    def test_trade_data(self):
        """Generate test trade data"""
        return {
            'trade_id': int(time.time()),  # Use timestamp as unique trade ID
            'symbol': "BTCUSD",
            'timeframe': "M5",
            'strategy': "TestStrategy",
            'strategy_version': "1.0"
        }

    def test_database_connection(self, test_database_config):
        """Test that we can connect to the Docker test database"""
        print(f"🔌 Testing database connection to {test_database_config['host']}:{test_database_config['port']}")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor() as cursor:
                cursor.execute("SELECT VERSION()")
                version = cursor.fetchone()
                print(f"✅ Connected to MySQL version: {version[0]}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to connect to test database: {e}")

    def test_trade_entry_database_records(self, test_database_config, analytics_service_url, test_trade_data):
        """Verify that trade entry creates records in all relevant database tables"""
        print(f"\n🔄 Testing trade entry database verification for trade_id: {test_trade_data['trade_id']}")

        # Step 1: Create a complete trade entry scenario
        trade_data = {
            'trade_id': test_trade_data['trade_id'],
            'strategy_name': test_trade_data['strategy'],
            'strategy_version': test_trade_data['strategy_version'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'direction': 'buy',
            'entry_price': 50000.0,
            'stop_loss': 49500.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'entry_time': int(time.time()),
            'status': 'OPEN',
            'account_id': 'TEST_ACCOUNT'
        }

        # Insert trade via HTTP
        try:
            response = requests.post(f"{analytics_service_url}/analytics/trade", json=trade_data, timeout=10)
            assert response.status_code == 201, f"Trade insert failed with status {response.status_code}"
            print("✅ Trade record created successfully")
        except Exception as e:
            pytest.fail(f"Failed to create trade record: {e}")

        # Step 2: Verify records in database
        self._verify_trades_table_record(test_database_config, test_trade_data['trade_id'])

    def _verify_trades_table_record(self, test_database_config, trade_id):
        """Verify that trade record exists in trades table"""
        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (trade_id,))
                trade_record = cursor.fetchone()

                assert trade_record is not None, f"Trade record not found for trade_id: {trade_id}"
                assert trade_record['symbol'] == 'BTCUSD'
                assert trade_record['timeframe'] == 'M5'
                assert trade_record['strategy_name'] == 'TestStrategy'
                assert trade_record['status'] == 'OPEN'

                print(f"✅ Trade record verified in database: {trade_record['id']}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify trades table record: {e}")

    def test_market_conditions_insert(self, test_database_config, analytics_service_url, test_trade_data):
        """Verify that market conditions can be inserted"""
        print(f"\n🔄 Testing market conditions insert for trade_id: {test_trade_data['trade_id']}")

        # First create a trade record
        trade_data = {
            'trade_id': test_trade_data['trade_id'],
            'strategy_name': test_trade_data['strategy'],
            'strategy_version': test_trade_data['strategy_version'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'direction': 'buy',
            'entry_price': 50000.0,
            'stop_loss': 49500.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'entry_time': int(time.time()),
            'status': 'OPEN',
            'account_id': 'TEST_ACCOUNT'
        }

        try:
            response = requests.post(f"{analytics_service_url}/analytics/trade", json=trade_data, timeout=10)
            assert response.status_code == 201, f"Trade insert failed with status {response.status_code}"
            print("✅ Trade record created successfully")
        except Exception as e:
            pytest.fail(f"Failed to create trade record: {e}")

        # Create market conditions data
        market_conditions = {
            'trade_id': test_trade_data['trade_id'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'rsi': 50.0,
            'stoch_main': 50.0,
            'stoch_signal': 50.0,
            'macd_main': 0.0,
            'macd_signal': 0.0,
            'bb_upper': 50000.0,
            'bb_lower': 49000.0,
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

        try:
            response = requests.post(f"{analytics_service_url}/analytics/market_conditions", json=market_conditions, timeout=10)
            assert response.status_code == 201, f"Market conditions insert failed with status {response.status_code}"
            print("✅ Market conditions inserted successfully")
        except Exception as e:
            pytest.fail(f"Failed to insert market conditions: {e}")

        # Verify in database
        self._verify_market_conditions_record(test_database_config, test_trade_data['trade_id'])

    def _verify_market_conditions_record(self, test_database_config, trade_id):
        """Verify that market conditions record exists"""
        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SELECT * FROM market_conditions WHERE trade_id = %s", (trade_id,))
                record = cursor.fetchone()

                assert record is not None, f"Market conditions record not found for trade_id: {trade_id}"
                assert record['symbol'] == 'BTCUSD'
                assert record['timeframe'] == 'M5'
                # Check that RSI exists and is a reasonable value (0-100)
                assert record['rsi'] is not None, "RSI should not be null"
                assert 0 <= float(record['rsi']) <= 100, f"RSI should be between 0-100, got {record['rsi']}"

                print(f"✅ Market conditions record verified in database: {record['id']}")
                print(f"   RSI: {record['rsi']}, Symbol: {record['symbol']}, Timeframe: {record['timeframe']}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify market conditions record: {e}")

    def test_analytics_service_health(self, analytics_service_url):
        """Test that the analytics service is healthy and accessible"""
        print(f"\n🔍 Testing analytics service health: {analytics_service_url}")

        try:
            response = requests.get(f"{analytics_service_url}/health", timeout=10)
            assert response.status_code == 200, f"Analytics service returned {response.status_code}"

            health_data = response.json()
            assert health_data["status"] == "healthy", f"Analytics service not healthy: {health_data}"

            print(f"✅ Analytics service health: {health_data}")

        except requests.exceptions.RequestException as e:
            pytest.fail(f"Analytics service not accessible: {e}")

    def test_ml_service_health(self, ml_service_url):
        """Test that the ML service is healthy and accessible"""
        print(f"\n🔍 Testing ML service health: {ml_service_url}")

        try:
            response = requests.get(f"{ml_service_url}/health", timeout=10)
            assert response.status_code == 200, f"ML service returned {response.status_code}"

            health_data = response.json()
            assert health_data["status"] == "healthy", f"ML service not healthy: {health_data}"

            print(f"✅ ML service health: {health_data}")

        except requests.exceptions.RequestException as e:
            pytest.fail(f"ML service not accessible: {e}")

    def test_database_tables_exist(self, test_database_config):
        """Test that all expected database tables exist"""
        print(f"\n🔍 Testing database table existence")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor() as cursor:
                cursor.execute("SHOW TABLES")
                tables = cursor.fetchall()
                table_names = [table[0] for table in tables]

                # Check for key tables that should exist
                expected_tables = [
                    'migration_log',
                    'market_conditions',
                    'ml_predictions',
                    'trades',
                    'ml_model_performance'
                ]

                missing_tables = [table for table in expected_tables if table not in table_names]
                assert not missing_tables, f"Missing expected tables: {missing_tables}"

                print(f"✅ All expected tables exist: {', '.join(expected_tables)}")
                print(f"   Total tables in database: {len(table_names)}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify database tables: {e}")
