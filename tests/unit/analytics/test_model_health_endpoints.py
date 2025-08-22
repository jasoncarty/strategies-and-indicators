#!/usr/bin/env python3
"""
Unit tests for new analytics endpoints
Tests model health, calibration, alerts, and retraining status endpoints
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import json

# Add analytics to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "analytics"))

from app import app


class TestModelHealthEndpoints:
    """Test new model health and retraining endpoints"""

    @pytest.fixture
    def client(self):
        """Create test client"""
        app.config['TESTING'] = True
        with app.test_client() as client:
            yield client

    @pytest.fixture
    def mock_db_connection(self):
        """Mock database connection"""
        with patch('app.analytics_db') as mock_db:
            mock_db.connect.return_value = None
            mock_db.disconnect.return_value = None
            mock_db.execute_query.return_value = []
            yield mock_db

    def test_model_health_endpoint(self, client, mock_db_connection):
        """Test /analytics/model_health endpoint"""
        # Mock database response for models query
        mock_db_connection.execute_query.side_effect = [
            # First query: models list
            [{
                'ml_model_key': 'buy_EURUSD+_PERIOD_M5',
                'ml_model_type': 'gradient_boosting',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            }],
            # Second query: recent performance
            [{
                'total_trades': 150,
                'winning_trades': 90,
                'avg_confidence': 0.75,
                'avg_prediction': 0.75,
                'avg_profit_loss': 15.50,
                'total_profit_loss': 2325.0,
                'profit_loss_std': 25.0
            }],
            # Third query: confidence analysis
            [{
                'confidence_level': 'low',
                'win_rate': 0.6
            }, {
                'confidence_level': 'high',
                'win_rate': 0.7
            }]
        ]

        response = client.get('/analytics/model_health')

        assert response.status_code == 200
        data = json.loads(response.data)

        assert 'models' in data
        assert 'summary' in data
        assert len(data['models']) > 0

        # Check first model data
        model = data['models'][0]
        assert 'model_key' in model
        assert 'health_score' in model
        assert 'status' in model

    def test_model_calibration_endpoint(self, client, mock_db_connection):
        """Test /analytics/model/<model_key>/calibration endpoint"""
        # Mock database response for calibration
        mock_db_connection.execute_query.side_effect = [
            # First query: calibration data
            [{
                'confidence_bucket': '0.0-0.2',
                'total_trades': 25,
                'winning_trades': 15,
                'avg_profit_loss': 12.50,
                'avg_confidence': 0.1,
                'avg_prediction': 0.1,
                'total_profit_loss': 312.5
            }],
            # Second query: confidence performance correlation
            [{
                'low_conf_win_rate': 0.6,
                'high_conf_win_rate': 0.4
            }]
        ]

        response = client.get('/analytics/model/buy_EURUSD+_PERIOD_M5/calibration')

        assert response.status_code == 200
        data = json.loads(response.data)

        assert 'calibration_buckets' in data
        assert 'overall_metrics' in data
        assert 'confidence_inversion_detected' in data['overall_metrics']

    def test_model_alerts_endpoint(self, client, mock_db_connection):
        """Test /analytics/model_alerts endpoint"""
        # Mock database response for alerts
        mock_db_connection.execute_query.side_effect = [
            # First query: models list
            [{
                'ml_model_key': 'buy_EURUSD+_PERIOD_M5',
                'ml_model_type': 'gradient_boosting',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            }],
            # Second query: recent performance
            [{
                'total_trades': 150,
                'winning_trades': 67,
                'avg_confidence': 0.82,
                'avg_prediction': 0.82,
                'avg_profit_loss': -8.50,
                'total_profit_loss': -1275.0,
                'profit_loss_std': 15.0,
                'earliest_trade': 1234567890,
                'latest_trade': 1234567890
            }],
            # Third query: confidence analysis
            [{
                'confidence_level': 'low',
                'win_rate': 0.6,
                'trade_count': 50
            }, {
                'confidence_level': 'high',
                'win_rate': 0.4,
                'trade_count': 100
            }]
        ]

        response = client.get('/analytics/model_alerts')

        assert response.status_code == 200
        data = json.loads(response.data)

        assert 'alerts' in data
        assert 'summary' in data
        assert len(data['alerts']) > 0

        # Check alert structure
        alert = data['alerts'][0]
        assert 'model_key' in alert
        assert 'alerts' in alert
        assert isinstance(alert['alerts'], list)

    def test_model_retraining_status_endpoint(self, client):
        """Test /analytics/model_retraining_status endpoint"""
        # Create mock metadata files
        mock_metadata = {
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'direction': 'buy',
            'last_retrained': '2025-08-21T15:30:00',
            'training_date': '2025-08-21T10:00:00',
            'health_score': 75,
            'cv_accuracy': 0.68,
            'confidence_correlation': 0.45,
            'training_samples': 120,
            'model_type': 'advanced_retraining_framework',
            'retrained_by': 'automated_pipeline',
            'model_version': 2.0
        }

        # Mock file system operations
        with patch('pathlib.Path.exists') as mock_exists, \
             patch('pathlib.Path.glob') as mock_glob, \
             patch('builtins.open', create=True) as mock_open:

            mock_exists.return_value = True
            mock_glob.return_value = ['mock_metadata.json']
            mock_open.return_value.__enter__.return_value.read.return_value = json.dumps(mock_metadata)

            response = client.get('/analytics/model_retraining_status')

            assert response.status_code == 200
            data = json.loads(response.data)

            assert 'models' in data
            assert 'summary' in data
            assert len(data['models']) > 0

            # Check model data structure
            model = data['models'][0]
            assert model['model_key'] == 'buy_EURUSD+_PERIOD_M5'
            assert model['last_retrained'] == '2025-08-21T15:30:00'
            assert model['model_version'] == 2.0
            assert model['retrained_by'] == 'automated_pipeline'

    def test_model_retraining_status_no_directory(self, client):
        """Test retraining status endpoint when ML models directory doesn't exist"""
        with patch('pathlib.Path.exists') as mock_exists:
            mock_exists.return_value = False

            response = client.get('/analytics/model_retraining_status')

            assert response.status_code == 200
            data = json.loads(response.data)

            assert data['models'] == []
            assert 'No ML models directory found' in data['summary']

    def test_model_retraining_status_invalid_metadata(self, client):
        """Test retraining status endpoint with invalid metadata files"""
        with patch('pathlib.Path.exists') as mock_exists, \
             patch('pathlib.Path.glob') as mock_glob, \
             patch('builtins.open', create=True) as mock_open:

            mock_exists.return_value = True
            mock_glob.return_value = ['invalid_metadata.json']
            mock_open.side_effect = Exception("Invalid JSON")

            response = client.get('/analytics/model_retraining_status')

            assert response.status_code == 200
            data = json.loads(response.data)

            # Should handle invalid files gracefully
            assert data['models'] == []

    def test_model_health_endpoint_database_error(self, client, mock_db_connection):
        """Test model health endpoint with database error"""
        mock_db_connection.execute_query.side_effect = Exception("Database error")

        response = client.get('/analytics/model_health')

        assert response.status_code == 500
        data = json.loads(response.data)
        assert 'error' in data

    def test_model_calibration_endpoint_invalid_model(self, client, mock_db_connection):
        """Test calibration endpoint with invalid model key"""
        mock_db_connection.execute_query.return_value = []

        response = client.get('/analytics/model/invalid_model_key/calibration')

        assert response.status_code == 404
        data = json.loads(response.data)

        # Should return error for invalid models
        assert 'error' in data
        assert data['model_key'] == 'invalid_model_key'

    def test_model_alerts_endpoint_no_alerts(self, client, mock_db_connection):
        """Test alerts endpoint when no alerts are found"""
        mock_db_connection.execute_query.return_value = []

        response = client.get('/analytics/model_alerts')

        assert response.status_code == 200
        data = json.loads(response.data)

        assert data['alerts'] == []
        assert data['summary'] == "No models found"

    def test_model_health_summary_calculation(self, client, mock_db_connection):
        """Test that model health summary is calculated correctly"""
        # Mock multiple models with different health scores
        mock_db_connection.execute_query.side_effect = [
            # First query: models list
            [{
                'ml_model_key': 'buy_EURUSD+_PERIOD_M5',
                'ml_model_type': 'gradient_boosting',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            }, {
                'ml_model_key': 'sell_EURUSD+_PERIOD_M5',
                'ml_model_type': 'gradient_boosting',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            }],
            # Second query: first model performance
            [{
                'total_trades': 100,
                'winning_trades': 70,
                'avg_confidence': 0.8,
                'avg_prediction': 0.8,
                'avg_profit_loss': 20.0,
                'total_profit_loss': 2000.0,
                'profit_loss_std': 30.0
            }],
            # Third query: first model confidence analysis
            [{
                'confidence_level': 'low',
                'win_rate': 0.7
            }, {
                'confidence_level': 'high',
                'win_rate': 0.8
            }],
            # Fourth query: second model performance
            [{
                'total_trades': 80,
                'winning_trades': 35,
                'avg_confidence': 0.6,
                'avg_prediction': 0.6,
                'avg_profit_loss': -15.0,
                'total_profit_loss': -1200.0,
                'profit_loss_std': 20.0
            }],
            # Fifth query: second model confidence analysis
            [{
                'confidence_level': 'low',
                'win_rate': 0.5
            }, {
                'confidence_level': 'high',
                'win_rate': 0.4
            }]
        ]

        response = client.get('/analytics/model_health')

        assert response.status_code == 200
        data = json.loads(response.data)

        summary = data['summary']
        assert 'overall_health' in summary
        assert 'healthy_models' in summary
        assert 'warning_models' in summary
        assert 'critical_models' in summary

        # Should have 2 models total
        assert summary['total_models'] == 2

    def test_model_alerts_alert_detection(self, client, mock_db_connection):
        """Test that alerts are properly detected and categorized"""
        # Mock model with critical issues
        mock_db_connection.execute_query.side_effect = [
            # First query: models list
            [{
                'ml_model_key': 'buy_EURUSD+_PERIOD_M5',
                'ml_model_type': 'gradient_boosting',
                'symbol': 'EURUSD+',
                'timeframe': 'M5'
            }],
            # Second query: recent performance
            [{
                'total_trades': 100,
                'winning_trades': 35,
                'avg_confidence': 0.85,
                'avg_prediction': 0.85,
                'avg_profit_loss': -25.0,
                'total_profit_loss': -2500.0,
                'profit_loss_std': 30.0,
                'earliest_trade': 1234567890,
                'latest_trade': 1234567890
            }],
            # Third query: confidence analysis
            [{
                'confidence_level': 'low',
                'win_rate': 0.6,
                'trade_count': 40
            }, {
                'confidence_level': 'high',
                'win_rate': 0.3,
                'trade_count': 60
            }]
        ]

        response = client.get('/analytics/model_alerts')

        assert response.status_code == 200
        data = json.loads(response.data)

        # Should detect critical alerts
        assert len(data['alerts']) > 0
        alert = data['alerts'][0]

        # Should have multiple alert types
        assert len(alert['alerts']) > 1

        # Check for specific alert types
        alert_types = [a['type'] for a in alert['alerts']]
        assert 'confidence_inversion' in alert_types or 'low_win_rate' in alert_types


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
