#!/usr/bin/env python3
"""
Integration tests for all database table scenarios using Docker services
Tests trade entry, exit, ML predictions, market conditions, and performance tracking
"""

import pytest
import requests
import json
import time
from datetime import datetime, timedelta
import pymysql


class TestDatabaseScenarios:
    """Integration tests for all database table scenarios using Docker services"""

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
            'trade_id': int(time.time() * 1000000),  # Use microseconds for uniqueness
            'symbol': "BTCUSD",
            'timeframe': "M5",
            'strategy': "TestStrategy",
            'strategy_version': "1.0"
        }

    def test_trade_entry_scenario(self, test_database_config, analytics_service_url, ml_service_url, test_trade_data):
        """Test complete trade entry scenario - creates records in multiple tables"""
        print(f"\n🔄 Testing trade entry scenario for trade_id: {test_trade_data['trade_id']}")

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
            'strategy': test_trade_data['strategy'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'direction': 'buy',
            **ml_features  # Spread all features at top level
        }

        try:
            ml_response = requests.post(f"{ml_service_url}/predict", json=ml_request, timeout=10)
            assert ml_response.status_code == 200, f"ML prediction failed with status {ml_response.status_code}"
            ml_result = ml_response.json()

            print(f"✅ ML prediction: {ml_result['prediction']['direction']} (confidence: {ml_result['prediction']['confidence']:.3f})")
        except Exception as e:
            pytest.fail(f"ML prediction failed: {e}")

        # Step 2: Create trade record
        trade_data = {
            'trade_id': test_trade_data['trade_id'],
            'strategy_name': test_trade_data['strategy'],
            'strategy_version': test_trade_data['strategy_version'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'direction': 'buy',
            'entry_price': 50000.0,
            'stop_loss': 49000.0,
            'take_profit': 51000.0,
            'lot_size': 0.1,
            'entry_time': int(time.time()),
            'status': 'OPEN',
            'account_id': 'TEST_ACCOUNT'
        }

        try:
            trade_response = requests.post(f"{analytics_service_url}/analytics/trade", json=trade_data, timeout=10)
            assert trade_response.status_code == 201, f"Trade creation failed with status {trade_response.status_code}"
            print("✅ Trade record created")
        except Exception as e:
            pytest.fail(f"Trade creation failed: {e}")

        # Step 3: Record market conditions
        market_conditions = {
            'trade_id': test_trade_data['trade_id'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
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

        try:
            market_response = requests.post(f"{analytics_service_url}/analytics/market_conditions", json=market_conditions, timeout=10)
            assert market_response.status_code == 201, f"Market conditions failed with status {market_response.status_code}"
            print("✅ Market conditions recorded")
        except Exception as e:
            pytest.fail(f"Market conditions failed: {e}")

        # Step 4: Record ML prediction
        ml_prediction_data = {
            'trade_id': test_trade_data['trade_id'],
            'model_name': ml_result['metadata'].get('model_name', 'test_model'),
            'model_type': 'buy',
            'prediction_probability': ml_result['prediction']['probability'],
            'confidence_score': ml_result['prediction']['confidence'],
            'features_json': json.dumps(ml_features),
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'strategy_name': test_trade_data['strategy'],
            'strategy_version': test_trade_data['strategy_version']
        }

        try:
            prediction_response = requests.post(f"{analytics_service_url}/analytics/ml_prediction", json=ml_prediction_data, timeout=10)
            assert prediction_response.status_code == 201, f"ML prediction recording failed with status {prediction_response.status_code}"
            print("✅ ML prediction recorded")
        except Exception as e:
            pytest.fail(f"ML prediction recording failed: {e}")

        # Step 5: Record ML trade log
        ml_trade_log_data = {
            'trade_id': test_trade_data['trade_id'],
            'strategy': test_trade_data['strategy'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
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

        try:
            ml_log_response = requests.post(f"{analytics_service_url}/ml_trade_log", json=ml_trade_log_data, timeout=10)
            assert ml_log_response.status_code == 201, f"ML trade log failed with status {ml_log_response.status_code}"
            print("✅ ML trade log recorded")
        except Exception as e:
            pytest.fail(f"ML trade log failed: {e}")

        # Verify all records were created in database
        self._verify_trade_entry_records(test_database_config, test_trade_data['trade_id'])

    def _verify_trade_entry_records(self, test_database_config, trade_id):
        """Verify that all trade entry records exist in database"""
        print(f"🔍 Verifying trade entry records for trade_id: {trade_id}")

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
                # Check trades table
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (trade_id,))
                trade_record = cursor.fetchone()
                assert trade_record is not None, f"Trade record not found for trade_id: {trade_id}"
                print("✅ Trade record verified")

                # Check market_conditions table
                cursor.execute("SELECT * FROM market_conditions WHERE trade_id = %s", (trade_id,))
                market_record = cursor.fetchone()
                assert market_record is not None, f"Market conditions record not found for trade_id: {trade_id}"
                print("✅ Market conditions record verified")

                # Check ml_predictions table
                cursor.execute("SELECT * FROM ml_predictions WHERE trade_id = %s", (trade_id,))
                prediction_record = cursor.fetchone()
                assert prediction_record is not None, f"ML prediction record not found for trade_id: {trade_id}"
                print("✅ ML prediction record verified")

                # Check ml_trade_logs table
                cursor.execute("SELECT * FROM ml_trade_logs WHERE trade_id = %s", (trade_id,))
                log_record = cursor.fetchone()
                assert log_record is not None, f"ML trade log record not found for trade_id: {trade_id}"
                print("✅ ML trade log record verified")

            connection.close()
            print("✅ All trade entry records verified successfully")

        except Exception as e:
            pytest.fail(f"Failed to verify trade entry records: {e}")

    def test_trade_exit_scenario(self, test_database_config, analytics_service_url, ml_service_url, test_trade_data):
        """Test complete trade exit scenario - updates records in multiple tables"""
        print(f"\n🔄 Testing trade exit scenario for trade_id: {test_trade_data['trade_id']}")

        # First create a trade entry
        self.test_trade_entry_scenario(test_database_config, analytics_service_url, ml_service_url, test_trade_data)

        # Step 1: Record trade exit
        trade_exit_data = {
            'trade_id': test_trade_data['trade_id'],
            'exit_price': 50500.0,
            'exit_reason': 'take_profit',
            'profit_loss': 500.0,
            'exit_time': int(time.time()),
            'status': 'CLOSED'
        }

        try:
            exit_response = requests.post(f"{analytics_service_url}/analytics/trade_exit", json=trade_exit_data, timeout=10)
            assert exit_response.status_code in [200, 201], f"Trade exit failed with status {exit_response.status_code}"
            print("✅ Trade exit recorded")
        except Exception as e:
            pytest.fail(f"Trade exit failed: {e}")

        # Step 2: Record ML trade close
        ml_trade_close_data = {
            'trade_id': test_trade_data['trade_id'],
            'strategy': test_trade_data['strategy'],
            'symbol': test_trade_data['symbol'],
            'timeframe': test_trade_data['timeframe'],
            'close_price': 50500.0,
            'profit_loss': 500.0,
            'profit_loss_pips': 50.0,
            'close_time': int(time.time()),
            'exit_reason': 'take_profit',
            'status': 'CLOSED',
            'success': True,
            'timestamp': int(time.time())
        }

        try:
            ml_close_response = requests.post(f"{analytics_service_url}/ml_trade_close", json=ml_trade_close_data, timeout=10)
            assert ml_close_response.status_code == 201, f"ML trade close failed with status {ml_close_response.status_code}"
            print("✅ ML trade close recorded")
        except Exception as e:
            pytest.fail(f"ML trade close failed: {e}")

        # Verify all records were updated in database
        self._verify_trade_exit_records(test_database_config, test_trade_data['trade_id'])

    def _verify_trade_exit_records(self, test_database_config, trade_id):
        """Verify that all trade exit records exist in database"""
        print(f"🔍 Verifying trade exit records for trade_id: {trade_id}")

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
                # Check trades table was updated
                cursor.execute("SELECT * FROM trades WHERE trade_id = %s", (trade_id,))
                trade_record = cursor.fetchone()
                assert trade_record is not None, f"Trade record not found for trade_id: {trade_id}"
                assert trade_record['status'] == 'CLOSED', f"Trade status not updated to CLOSED"
                print("✅ Trade record updated to CLOSED")

                # Check ml_trade_closes table
                cursor.execute("SELECT * FROM ml_trade_closes WHERE trade_id = %s", (trade_id,))
                close_record = cursor.fetchone()
                assert close_record is not None, f"ML trade close record not found for trade_id: {trade_id}"
                print("✅ ML trade close record verified")

            connection.close()
            print("✅ All trade exit records verified successfully")

        except Exception as e:
            pytest.fail(f"Failed to verify trade exit records: {e}")

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
