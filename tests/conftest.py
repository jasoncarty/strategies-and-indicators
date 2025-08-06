"""
Pytest configuration and shared fixtures
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch

@pytest.fixture(scope="session")
def temp_test_dir():
    """Create a temporary directory for tests"""
    temp_dir = tempfile.mkdtemp()
    yield temp_dir
    shutil.rmtree(temp_dir)

@pytest.fixture(scope="session")
def mock_ml_service():
    """Mock ML service for testing"""
    with patch('requests.get') as mock_get, \
         patch('requests.post') as mock_post:

        # Mock health check response
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = {
            'status': 'running',
            'models_loaded': 10
        }

        # Mock prediction response
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = {
            'status': 'success',
            'prediction': {
                'confidence': 0.75,
                'direction': 'buy',
                'probability': 0.80
            },
            'metadata': {
                'features_used': 28,
                'model_name': 'buy_BTCUSD_PERIOD_M5'
            }
        }

        yield mock_get, mock_post

@pytest.fixture(scope="session")
def sample_features():
    """Sample features for testing"""
    return {
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

@pytest.fixture(scope="session")
def sample_trade_data():
    """Sample trade data for testing"""
    return {
        'trade_id': '12345',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'entry_price': 50000.0,
        'stop_loss': 49000.0,
        'take_profit': 51000.0,
        'lot_size': 0.1
    }

@pytest.fixture(scope="session")
def sample_market_conditions():
    """Sample market conditions data for testing"""
    return {
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
