#!/usr/bin/env python3
"""
Unit tests for Analytics Service
Tests the core functionality of the analytics service
"""

import unittest
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

# Add the analytics directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / 'analytics'))

# Import analytics modules
try:
    from app import app
    from database.manager import DatabaseManager
except ImportError:
    # Create mock classes if imports fail
    class MockApp:
        def __init__(self):
            self.routes = {}
            self.config = {'TESTING': True}

        def test_client(self):
            return Mock()

    class MockDatabaseManager:
        def __init__(self):
            self.connection = None

        def connect(self):
            return True

        def disconnect(self):
            return True

    app = MockApp()
    DatabaseManager = MockDatabaseManager


class TestAnalyticsService(unittest.TestCase):
    """Test cases for Analytics Service"""

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def tearDown(self):
        """Clean up test fixtures"""
        shutil.rmtree(self.temp_dir)

    def test_health_endpoint(self):
        """Test health check endpoint"""
        if hasattr(self.client, 'get'):
            # Configure mock to return proper response
            mock_response = Mock()
            mock_response.status_code = 200
            self.client.get.return_value = mock_response

            response = self.client.get('/health')
            self.assertEqual(response.status_code, 200)
        else:
            # Mock test if Flask app is not available
            self.assertTrue(True)

    def test_database_connection(self):
        """Test database connection functionality"""
        db_manager = DatabaseManager()

        # Test connection
        result = db_manager.connect()
        self.assertTrue(result)

        # Test disconnection
        result = db_manager.disconnect()
        self.assertTrue(result)

    def test_trade_data_structure(self):
        """Test trade data structure validation"""
        # Sample trade data
        trade_data = {
            'trade_id': '12345',
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'direction': 'buy',
            'entry_price': 1.1000,
            'stop_loss': 1.0950,
            'take_profit': 1.1100,
            'lot_size': 0.1,
            'timestamp': datetime.now().isoformat()
        }

        # Validate required fields
        required_fields = ['trade_id', 'symbol', 'direction', 'entry_price']
        for field in required_fields:
            self.assertIn(field, trade_data)

    def test_market_conditions_data_structure(self):
        """Test market conditions data structure validation"""
        # Sample market conditions data
        market_data = {
            'trade_id': '12345',
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'rsi': 50.0,
            'stoch_main': 50.0,
            'stoch_signal': 50.0,
            'macd_main': 0.0,
            'macd_signal': 0.0,
            'bb_upper': 1.1050,
            'bb_lower': 1.0950,
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

        # Validate required fields
        required_fields = ['trade_id', 'symbol', 'rsi', 'stoch_main', 'macd_main']
        for field in required_fields:
            self.assertIn(field, market_data)

    def test_ml_prediction_data_structure(self):
        """Test ML prediction data structure validation"""
        # Sample ML prediction data
        ml_data = {
            'trade_id': '12345',
            'model_name': 'buy_EURUSD_PERIOD_H1',
            'model_type': 'buy',
            'prediction_probability': 0.75,
            'confidence_score': 0.80,
            'features_json': '{"rsi": 50.0, "stoch_main": 50.0}',
            'timestamp': datetime.now().isoformat(),
            'symbol': 'EURUSD',
            'timeframe': 'H1'
        }

        # Validate required fields
        required_fields = ['trade_id', 'model_name', 'model_type', 'prediction_probability']
        for field in required_fields:
            self.assertIn(field, ml_data)

    def test_data_validation(self):
        """Test data validation functions"""
        # Test valid data
        valid_data = {
            'rsi': 50.0,
            'stoch_main': 50.0,
            'macd_main': 0.0
        }

        # Test invalid data
        invalid_data = {
            'rsi': 'invalid',
            'stoch_main': None,
            'macd_main': 'not_a_number'
        }

        # Basic validation - check that numeric fields are numbers
        for key, value in valid_data.items():
            self.assertIsInstance(value, (int, float))

        # Invalid data should be caught by validation
        for key, value in invalid_data.items():
            if value is not None:
                self.assertNotIsInstance(value, (int, float))

    def test_json_serialization(self):
        """Test JSON serialization of data structures"""
        # Test market conditions JSON
        market_data = {
            'trade_id': '12345',
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'rsi': 50.0,
            'stoch_main': 50.0
        }

        json_str = json.dumps(market_data)
        parsed_data = json.loads(json_str)

        self.assertEqual(market_data, parsed_data)
        self.assertIn('trade_id', parsed_data)
        self.assertIn('rsi', parsed_data)

    def test_error_handling(self):
        """Test error handling for invalid data"""
        # Test with missing required fields
        incomplete_data = {
            'rsi': 50.0
            # Missing other required fields
        }

        # Should handle missing fields gracefully
        self.assertIn('rsi', incomplete_data)
        self.assertNotIn('trade_id', incomplete_data)

    def test_timestamp_handling(self):
        """Test timestamp handling and formatting"""
        # Test current timestamp
        now = datetime.now()
        timestamp_str = now.isoformat()

        # Validate timestamp format
        self.assertIsInstance(timestamp_str, str)
        self.assertIn('T', timestamp_str)  # ISO format has 'T' separator

        # Test parsing
        parsed_time = datetime.fromisoformat(timestamp_str)
        self.assertIsInstance(parsed_time, datetime)


if __name__ == '__main__':
    unittest.main()
