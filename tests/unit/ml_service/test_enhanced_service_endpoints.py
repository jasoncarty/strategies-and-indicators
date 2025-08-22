#!/usr/bin/env python3
"""
Unit tests for enhanced ML prediction service endpoints
Tests the new endpoints added in the service upgrade
"""

import pytest
import json
import time
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

# Import the Flask app and ML service
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'ML_Webserver'))
from ml_prediction_service import app

class TestEnhancedServiceEndpoints:
    """Test enhanced ML prediction service endpoints"""

    @pytest.fixture
    def client(self):
        """Create test client"""
        app.config['TESTING'] = True
        with app.test_client() as client:
            yield client

    @pytest.fixture
    def mock_ml_service(self):
        """Mock ML service with enhanced functionality"""
        mock_service = Mock()

        # Mock models and metadata
        mock_service.models = {
            'buy_EURUSD+_PERIOD_M5': Mock(),
            'sell_EURUSD+_PERIOD_M5': Mock(),
            'combined_EURUSD+_PERIOD_M5': Mock()
        }

        mock_service.model_metadata = {
            'buy_EURUSD+_PERIOD_M5': {
                'model_type': 'gradient_boosting',
                'training_date': '2024-01-01T00:00:00',
                'last_retrained': '2024-08-01T00:00:00',
                'model_version': 2.0,
                'retrained_by': 'automated_pipeline',
                'health_score': 85,
                'cv_accuracy': 0.72,
                'confidence_correlation': 0.68,
                'training_samples': 150,
                'features_used': ['rsi', 'macd_main', 'bb_upper'],
                'file_path': '/path/to/model.pkl',
                'loaded_at': '2024-08-01T00:00:00'
            }
        }

        # Mock performance tracking
        mock_service.prediction_count = 100
        mock_service.error_count = 5
        mock_service.start_time = time.time() - 3600  # 1 hour ago
        mock_service.response_times = [50, 75, 100, 125, 150]  # milliseconds
        mock_service.avg_response_time = 100.0

        # Mock analytics URL
        mock_service.analytics_url = 'http://localhost:5001'

        return mock_service



    def test_performance_endpoint_success(self, client, mock_ml_service):
        """Test successful performance metrics endpoint"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            response = client.get('/performance')
            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['status'] == 'success'
            assert 'metrics' in data

            metrics = data['metrics']
            assert metrics['total_predictions'] == 100
            assert metrics['total_errors'] == 5
            assert metrics['success_rate'] == 95.0
            assert metrics['models_loaded'] == 3
            assert metrics['avg_response_time_ms'] == 100.0

    def test_bulk_predict_endpoint_success(self, client, mock_ml_service):
        """Test successful bulk prediction endpoint"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            # Mock the get_prediction method
            mock_ml_service.get_prediction.return_value = {
                'status': 'success',
                'prediction': {'probability': 0.75, 'confidence': 0.8}
            }

            request_data = {
                'requests': [
                    {
                        'symbol': 'EURUSD+',
                        'timeframe': 'M5',
                        'direction': 'buy',
                        'features': {'rsi': 50},
                        'enhanced': False
                    },
                    {
                        'symbol': 'EURUSD+',
                        'timeframe': 'M5',
                        'direction': 'sell',
                        'features': {'rsi': 70},
                        'enhanced': True
                    }
                ]
            }

            response = client.post('/bulk_predict',
                                data=json.dumps(request_data),
                                content_type='application/json')

            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['status'] == 'success'
            assert len(data['results']) == 2
            assert data['total_requests'] == 2
            assert data['successful'] == 2

    def test_bulk_predict_endpoint_missing_requests(self, client, mock_ml_service):
        """Test bulk prediction endpoint with missing requests array"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            request_data = {'invalid_key': 'value'}

            response = client.post('/bulk_predict',
                                data=json.dumps(request_data),
                                content_type='application/json')

            assert response.status_code == 400

            data = json.loads(response.data)
            assert data['status'] == 'error'
            assert 'Missing "requests" array' in data['message']

    def test_bulk_predict_endpoint_too_many_requests(self, client, mock_ml_service):
        """Test bulk prediction endpoint with too many requests"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            # Create 11 requests (over the limit of 10)
            requests = [{'symbol': 'EURUSD+', 'timeframe': 'M5', 'features': {}} for _ in range(11)]
            request_data = {'requests': requests}

            response = client.post('/bulk_predict',
                                data=json.dumps(request_data),
                                content_type='application/json')

            assert response.status_code == 400

            data = json.loads(response.data)
            assert data['status'] == 'error'
            assert 'Maximum 10 requests allowed' in data['message']

    def test_model_versions_endpoint_success(self, client, mock_ml_service):
        """Test successful model versions endpoint"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            response = client.get('/model_versions')
            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['status'] == 'success'
            assert 'model_versions' in data
            assert data['total_models'] == 3

            # Check specific model version data
            eurusd_model = data['model_versions']['buy_EURUSD+_PERIOD_M5']
            assert eurusd_model['model_type'] == 'gradient_boosting'
            assert eurusd_model['model_version'] == 2.0
            assert eurusd_model['retrained_by'] == 'automated_pipeline'
            assert eurusd_model['health_score'] == 85

    def test_enhanced_health_endpoint_success(self, client, mock_ml_service):
        """Test enhanced health endpoint with analytics service available"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            with patch('requests.get') as mock_get:
                mock_get.return_value.status_code = 200

                response = client.get('/health')
                assert response.status_code == 200

                data = json.loads(response.data)
                assert data['status'] == 'healthy'
                assert data['service'] == 'ML Prediction Service'
                assert data['models_loaded'] == 3
                assert data['analytics_service'] == 'healthy'
                assert data['total_predictions'] == 100
                assert data['success_rate_percent'] == 95.0
                assert data['avg_response_time_ms'] == 100.0

    def test_enhanced_health_endpoint_analytics_unreachable(self, client, mock_ml_service):
        """Test enhanced health endpoint when analytics service is unreachable"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            with patch('requests.get') as mock_get:
                mock_get.side_effect = Exception("Connection failed")

                response = client.get('/health')
                assert response.status_code == 200

                data = json.loads(response.data)
                assert data['status'] == 'healthy'
                assert data['analytics_service'] == 'unreachable'

    def test_enhanced_health_endpoint_no_models(self, client):
        """Test enhanced health endpoint when no models are loaded"""
        mock_service = Mock()
        mock_service.models = {}

        with patch('ml_prediction_service.ml_service', mock_service):
            response = client.get('/health')
            assert response.status_code == 500

            data = json.loads(response.data)
            assert data['status'] == 'unhealthy'
            assert 'No models loaded' in data['message']

    def test_reload_models_endpoint_get_method(self, client, mock_ml_service):
        """Test reload models endpoint with GET method"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            # Mock the reload methods
            mock_ml_service._load_all_models.return_value = None
            mock_ml_service._ensure_consistent_feature_names.return_value = None

            response = client.get('/reload_models')
            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['status'] == 'success'
            assert 'Models reloaded successfully' in data['message']

    def test_reload_models_endpoint_post_method(self, client, mock_ml_service):
        """Test reload models endpoint with POST method"""
        with patch('ml_prediction_service.ml_service', mock_ml_service):
            # Mock the reload methods
            mock_ml_service._load_all_models.return_value = None
            mock_ml_service._ensure_consistent_feature_names.return_value = None

            response = client.post('/reload_models')
            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['status'] == 'success'
            assert 'Models reloaded successfully' in data['message']

    def test_endpoint_error_handling(self, client):
        """Test error handling when ML service is not initialized"""
        with patch('ml_prediction_service.ml_service', None):
            # Test all new endpoints
            endpoints = ['/performance', '/bulk_predict', '/model_versions']

            for endpoint in endpoints:
                if endpoint == '/bulk_predict':
                    response = client.post(endpoint, data='{}', content_type='application/json')
                else:
                    response = client.get(endpoint)

                assert response.status_code == 500

                data = json.loads(response.data)
                assert data['status'] == 'error'
                assert 'ML service not initialized' in data['message']

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
