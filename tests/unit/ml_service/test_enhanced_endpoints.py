#!/usr/bin/env python3
"""
Unit tests for enhanced ML prediction service endpoints
Tests the new /trade_decision endpoint and enhanced functionality
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import json

# Add ML_Webserver to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "ML_Webserver"))

from ml_prediction_service import app


class TestEnhancedEndpoints:
    """Test enhanced ML prediction service endpoints"""

    @pytest.fixture
    def client(self):
        """Create test client"""
        app.config['TESTING'] = True
        with app.test_client() as client:
            yield client

    @pytest.fixture
    def mock_ml_service(self):
        """Mock ML prediction service"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            mock_service.get_prediction.return_value = {
                'status': 'success',
                'prediction': {
                    'direction': 'buy',
                    'confidence': 0.85,
                    'strategy': 'ML_Testing_EA',
                    'symbol': 'EURUSD+',
                    'timeframe': 'M5'
                },
                'metadata': {
                    'model_used': 'buy_EURUSD+_PERIOD_M5',
                    'prediction_time': '2025-01-21T15:30:00'
                },
                'should_trade': True,
                'confidence_threshold': 0.3,
                'model_health': {
                    'status': 'healthy',
                    'health_score': 85
                },
                'trade_parameters': {
                    'entry_price': 1.0835,
                    'stop_loss': 1.0820,
                    'take_profit': 1.0860,
                    'lot_size': 0.1
                }
            }
            yield mock_service

    def test_trade_decision_endpoint_success(self, client, mock_ml_service):
        """Test successful trade decision endpoint"""
        # Test data
        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {
                'rsi': 65.5,
                'stoch_main': 75.2,
                'macd_main': 0.0012,
                'current_price': 1.0835,
                'atr': 0.0015,
                'account_balance': 10000,
                'risk_per_pip': 1.0
            },
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify enhanced response structure
        assert data['status'] == 'success'
        assert 'should_trade' in data
        assert 'confidence_threshold' in data
        assert 'model_health' in data
        assert 'trade_parameters' in data
        assert 'prediction' in data
        assert 'metadata' in data

        # Verify trade decision
        assert data['should_trade'] is True
        assert data['confidence_threshold'] == 0.3
        assert data['model_health']['status'] == 'healthy'

        # Verify trade parameters
        trade_params = data['trade_parameters']
        assert trade_params['entry_price'] == 1.0835
        assert trade_params['stop_loss'] == 1.0820
        assert trade_params['take_profit'] == 1.0860
        assert trade_params['lot_size'] == 0.1

        # Verify prediction data
        prediction = data['prediction']
        assert prediction['direction'] == 'buy'
        assert prediction['strategy'] == 'ML_Testing_EA'
        assert prediction['symbol'] == 'EURUSD+'
        assert prediction['timeframe'] == 'M5'

    def test_trade_decision_endpoint_missing_data(self, client, mock_ml_service):
        """Test trade decision endpoint with missing required data"""
        # Test with missing strategy
        test_data = {
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'message' in data

        # Test with missing symbol
        test_data = {
            'strategy': 'ML_Testing_EA',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'message' in data

        # Test with missing features
        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'success'

    def test_trade_decision_endpoint_invalid_direction(self, client, mock_ml_service):
        """Test trade decision endpoint with invalid direction"""
        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'invalid_direction'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'success'
        # The endpoint doesn't validate direction, it just passes it through

    def test_trade_decision_endpoint_ml_service_error(self, client, mock_ml_service):
        """Test trade decision endpoint when ML service fails"""
        # Mock ML service failure
        mock_ml_service.get_prediction.side_effect = Exception("ML service error")

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 500
        data = json.loads(response.data)
        assert 'message' in data

    def test_trade_decision_endpoint_confidence_thresholds(self, client, mock_ml_service):
        """Test trade decision endpoint with different confidence thresholds"""
        # Test with high confidence (should trade)
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.3,
            'model_health': {'status': 'healthy', 'health_score': 85},
            'trade_parameters': {'entry_price': 1.0835, 'stop_loss': 1.0820, 'take_profit': 1.0860, 'lot_size': 0.1}
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5, 'current_price': 1.0835, 'atr': 0.0015},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['should_trade'] is True

        # Test with low confidence (should not trade)
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.25},
            'metadata': {'model_used': 'test_model'},
            'should_trade': False,
            'confidence_threshold': 0.7,
            'model_health': {'status': 'critical', 'health_score': 30},
            'trade_parameters': {'entry_price': 0, 'stop_loss': 0, 'take_profit': 0, 'lot_size': 0.1}
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['should_trade'] is False
        assert data['confidence_threshold'] == 0.7
        assert data['model_health']['status'] == 'critical'

    def test_trade_decision_endpoint_trade_parameters(self, client, mock_ml_service):
        """Test trade decision endpoint trade parameter calculation"""
        # Test BUY direction
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.3,
            'model_health': {'status': 'healthy', 'health_score': 85},
            'trade_parameters': {
                'entry_price': 1.0835,
                'stop_loss': 1.0820,  # Below entry for BUY
                'take_profit': 1.0860,  # Above entry for BUY
                'lot_size': 0.1
            }
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5, 'current_price': 1.0835, 'atr': 0.0015},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)

        trade_params = data['trade_parameters']
        assert trade_params['entry_price'] == 1.0835
        assert trade_params['stop_loss'] < trade_params['entry_price']  # Below for BUY
        assert trade_params['take_profit'] > trade_params['entry_price']  # Above for BUY

        # Test SELL direction
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'sell', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.3,
            'model_health': {'status': 'healthy', 'health_score': 85},
            'trade_parameters': {
                'entry_price': 1.0835,
                'stop_loss': 1.0850,  # Above entry for SELL
                'take_profit': 1.0810,  # Below entry for SELL
                'lot_size': 0.1
            }
        }

        test_data['direction'] = 'sell'
        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)

        trade_params = data['trade_parameters']
        assert trade_params['entry_price'] == 1.0835
        assert trade_params['stop_loss'] > trade_params['entry_price']  # Above for SELL
        assert trade_params['take_profit'] < trade_params['entry_price']  # Below for SELL

    def test_trade_decision_endpoint_model_health_integration(self, client, mock_ml_service):
        """Test trade decision endpoint with model health integration"""
        # Test healthy model
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.3,
            'model_health': {'status': 'healthy', 'health_score': 85},
            'trade_parameters': {'entry_price': 1.0835, 'stop_loss': 1.0820, 'take_profit': 1.0860, 'lot_size': 0.1}
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5, 'current_price': 1.0835, 'atr': 0.0015},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['model_health']['status'] == 'healthy'
        assert data['confidence_threshold'] == 0.3

        # Test warning model
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.6,
            'model_health': {'status': 'warning', 'health_score': 55},
            'trade_parameters': {'entry_price': 1.0835, 'stop_loss': 1.0820, 'take_profit': 1.0860, 'lot_size': 0.1}
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['model_health']['status'] == 'warning'
        assert data['confidence_threshold'] == 0.6

        # Test critical model
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.7,
            'model_health': {'status': 'critical', 'health_score': 30},
            'trade_parameters': {'entry_price': 1.0835, 'stop_loss': 1.0820, 'take_profit': 1.0860, 'lot_size': 0.1}
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['model_health']['status'] == 'critical'
        assert data['confidence_threshold'] == 0.7

    def test_trade_decision_endpoint_feature_handling(self, client, mock_ml_service):
        """Test trade decision endpoint feature handling"""
        # Test with minimal features
        minimal_features = {'rsi': 65.5}

        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {'direction': 'buy', 'confidence': 0.85},
            'metadata': {'model_used': 'test_model'},
            'should_trade': True,
            'confidence_threshold': 0.3,
            'model_health': {'status': 'healthy', 'health_score': 85},
            'trade_parameters': {'entry_price': 0, 'stop_loss': 0, 'take_profit': 0, 'lot_size': 0.1}
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': minimal_features,
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'success'

        # Test with comprehensive features
        comprehensive_features = {
            'rsi': 65.5,
            'stoch_main': 75.2,
            'macd_main': 0.0012,
            'bb_upper': 1.0850,
            'bb_lower': 1.0820,
            'current_price': 1.0835,
            'atr': 0.0015,
            'account_balance': 10000,
            'risk_per_pip': 1.0
        }

        test_data['features'] = comprehensive_features
        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'success'

    def test_trade_decision_endpoint_error_scenarios(self, client, mock_ml_service):
        """Test trade decision endpoint error scenarios"""
        # Test with invalid JSON
        response = client.post('/trade_decision', data='invalid json')
        assert response.status_code == 500
        # Flask returns 500 for JSON parsing errors

        # Test with empty request body
        response = client.post('/trade_decision')
        assert response.status_code == 500
        # Flask returns 500 for parsing errors when no JSON data is provided

        # Test with ML service returning error
        mock_ml_service.get_prediction.return_value = {
            'status': 'error',
            'message': 'Feature preparation failed'
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'buy'
        }

        response = client.post('/trade_decision', json=test_data)
        assert response.status_code == 400  # ML service errors are returned as 400 Bad Request
        data = json.loads(response.data)
        assert data['status'] == 'error'

    def test_legacy_predict_endpoint_compatibility(self, client, mock_ml_service):
        """Test that legacy /predict endpoint still works"""
        # Mock legacy response
        mock_ml_service.get_prediction.return_value = {
            'status': 'success',
            'prediction': {
                'direction': 'buy',
                'confidence': 0.85,
                'strategy': 'ML_Testing_EA',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            },
            'metadata': {
                'model_used': 'buy_EURUSD+_PERIOD_M5',
                'prediction_time': '2025-01-21T15:30:00'
            }
        }

        test_data = {
            'strategy': 'ML_Testing_EA',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'features': {'rsi': 65.5},
            'direction': 'buy'
        }

        response = client.post('/predict', json=test_data)
        assert response.status_code == 200
        data = json.loads(response.data)

        # Should not contain enhanced fields
        assert 'should_trade' not in data
        assert 'confidence_threshold' not in data
        assert 'model_health' not in data
        assert 'trade_parameters' not in data

        # Should contain legacy fields
        assert 'prediction' in data
        assert 'metadata' in data
        assert data['status'] == 'success'


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
