"""
Unit tests for recommendation insights module
Tests the recommendation analysis functionality for ML model retraining
"""

import pytest
import json
import time
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, MagicMock
import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from ML_Webserver.recommendation_insights import RecommendationInsights

class TestRecommendationInsights:
    """Test recommendation insights functionality"""

    @pytest.fixture
    def insights_analyzer(self):
        """Create recommendation insights analyzer"""
        with patch('ML_Webserver.recommendation_insights.requests') as mock_requests:
            analyzer = RecommendationInsights('http://localhost:5001')
            yield analyzer

    @pytest.fixture
    def mock_performance_data(self):
        """Mock recommendation performance data"""
        return [
            {
                'ml_model_key': 'test_model',
                'analysis_method': 'ml_enhanced',
                'total_recommendations': 100,
                'correct_recommendations': 65,
                'incorrect_recommendations': 35,
                'accuracy_percentage': 65.0,
                'avg_ml_confidence': 0.75,
                'avg_final_confidence': 0.8,
                'total_profit_if_followed': 1500.0,
                'total_profit_if_opposite': 200.0,
                'total_recommendation_value': 1300.0,
                'avg_profit_per_recommendation': 13.0
            }
        ]

    def test_get_model_recommendation_insights_success(self, insights_analyzer, mock_performance_data):
        """Test successful retrieval of model recommendation insights"""
        # Mock requests response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'data': mock_performance_data}

        with patch('ML_Webserver.recommendation_insights.requests.get', return_value=mock_response):
            insights = insights_analyzer.get_model_recommendation_insights('buy_EURUSD+_PERIOD_M5', days=30)

        # Assertions
        assert insights['model_key'] == 'buy_EURUSD+_PERIOD_M5'
        assert insights['data_points'] == 1
        assert insights['should_retrain'] is not None
        assert insights['retrain_priority'] is not None
        assert 'insights' in insights
        assert 'retraining_suggestions' in insights

    def test_get_model_recommendation_insights_no_data(self, insights_analyzer):
        """Test handling when no recommendation data is available"""
        # Mock empty response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'data': []}

        with patch('ML_Webserver.recommendation_insights.requests.get', return_value=mock_response):
            insights = insights_analyzer.get_model_recommendation_insights('buy_EURUSD+_PERIOD_M5', days=30)

        # Should return default insights
        assert insights['should_retrain'] == False
        assert insights['retrain_priority'] == 'low'
        assert insights['data_points'] == 0

    def test_get_model_recommendation_insights_api_error(self, insights_analyzer):
        """Test handling when API request fails"""
        # Mock API error
        with patch('ML_Webserver.recommendation_insights.requests.get', side_effect=Exception("API Error")):
            insights = insights_analyzer.get_model_recommendation_insights('buy_EURUSD+_PERIOD_M5', days=30)

        # Should return default insights
        assert insights['should_retrain'] == False
        assert insights['retrain_priority'] == 'low'

    def test_analyze_recommendation_performance(self, insights_analyzer, mock_performance_data):
        """Test recommendation performance analysis"""
        insights = insights_analyzer._analyze_recommendation_performance(mock_performance_data, 'test_model')

        # Assertions
        assert insights['total_recommendations'] == 100
        assert insights['overall_accuracy'] == 65.0
        assert insights['correct_recommendations'] == 65
        assert insights['incorrect_recommendations'] == 35
        assert insights['avg_ml_confidence'] == 0.75
        assert insights['avg_final_confidence'] == 0.8
        assert insights['total_profit_if_followed'] == 1500.0
        assert insights['total_profit_if_opposite'] == 200.0
        assert insights['total_recommendation_value'] == 1300.0
        assert insights['avg_profit_per_recommendation'] == 13.0

    def test_generate_retraining_suggestions_low_accuracy(self, insights_analyzer):
        """Test retraining suggestions for low accuracy"""
        insights = {
            'overall_accuracy': 40.0,
            'total_recommendation_value': 50.0,  # Positive value to avoid profitability override
            'confidence_issues': [],  # No confidence issues to avoid conflicts
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')

        assert suggestions['should_retrain'] == True
        assert suggestions['priority'] == 'critical'  # 40% < 45% should be critical
        assert 'Very low accuracy' in suggestions['reason']
        assert 'Retrain with more recent data' in suggestions['recommended_actions']

    def test_generate_retraining_suggestions_high_accuracy(self, insights_analyzer):
        """Test retraining suggestions for high accuracy"""
        insights = {
            'overall_accuracy': 80.0,
            'total_recommendation_value': 1000.0,
            'confidence_issues': [],
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')

        assert suggestions['should_retrain'] == False
        assert suggestions['priority'] == 'low'

    def test_generate_retraining_suggestions_confidence_issues(self, insights_analyzer):
        """Test retraining suggestions for confidence calibration issues"""
        insights = {
            'overall_accuracy': 50.0,
            'total_recommendation_value': 0.0,
            'confidence_issues': ['severely_overconfident'],
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')

        assert suggestions['should_retrain'] == True
        assert suggestions['priority'] == 'critical'
        assert 'overconfident' in suggestions['reason'].lower()
        assert 'confidence calibration' in suggestions['confidence_adjustments'][0]

    def test_generate_retraining_suggestions_negative_value(self, insights_analyzer):
        """Test retraining suggestions for negative recommendation value"""
        insights = {
            'overall_accuracy': 60.0,
            'total_recommendation_value': -500.0,
            'confidence_issues': [],
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')

        assert suggestions['should_retrain'] == True
        assert suggestions['priority'] == 'high'
        assert 'Negative recommendation value' in suggestions['reason']

    def test_assess_data_quality(self, insights_analyzer):
        """Test data quality assessment"""
        import pandas as pd

        # Test with good data
        good_data = pd.DataFrame([
            {'total_recommendations': 100, 'avg_final_confidence': 0.8, 'accuracy_percentage': 70.0}
        ])

        quality = insights_analyzer._assess_data_quality(good_data)
        assert quality['insufficient_data'] == False
        assert quality['low_confidence_data'] == False
        assert quality['total_recommendations'] == 100

        # Test with insufficient data
        insufficient_data = pd.DataFrame([
            {'total_recommendations': 10, 'avg_final_confidence': 0.8, 'accuracy_percentage': 70.0}
        ])

        quality = insights_analyzer._assess_data_quality(insufficient_data)
        assert quality['insufficient_data'] == True

        # Test with low confidence data
        low_confidence_data = pd.DataFrame([
            {'total_recommendations': 100, 'avg_final_confidence': 0.2, 'accuracy_percentage': 70.0}
        ])

        quality = insights_analyzer._assess_data_quality(low_confidence_data)
        assert quality['low_confidence_data'] == True

    def test_get_all_model_insights(self, insights_analyzer, mock_performance_data):
        """Test getting insights for multiple models"""
        model_keys = ['buy_EURUSD+_PERIOD_M5', 'sell_GBPUSD+_PERIOD_M15']

        # Mock responses for each model
        mock_responses = []
        for model_key in model_keys:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {'data': mock_performance_data}
            mock_responses.append(mock_response)

        with patch('ML_Webserver.recommendation_insights.requests.get', side_effect=mock_responses):
            result = insights_analyzer.get_all_model_insights(model_keys, days=30)

        # Assertions
        assert result['models_analyzed'] == 2
        assert len(result['insights']) == 2
        assert 'buy_EURUSD+_PERIOD_M5' in result['insights']
        assert 'sell_GBPUSD+_PERIOD_M15' in result['insights']

    def test_caching_functionality(self, insights_analyzer, mock_performance_data):
        """Test caching functionality"""
        # Mock response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'data': mock_performance_data}

        with patch('ML_Webserver.recommendation_insights.requests.get', return_value=mock_response):
            # First call
            insights1 = insights_analyzer.get_model_recommendation_insights('buy_EURUSD+_PERIOD_M5', days=30)

            # Second call should use cache
            insights2 = insights_analyzer.get_model_recommendation_insights('buy_EURUSD+_PERIOD_M5', days=30)

        # Both should return the same data
        assert insights1['model_key'] == insights2['model_key']
        assert insights1['data_points'] == insights2['data_points']

    def test_get_cached_insights(self, insights_analyzer):
        """Test getting cached insights"""
        # Add to cache
        test_insights = {'model_key': 'test', 'should_retrain': True}
        insights_analyzer.insights_cache['test_model'] = {
            'data': test_insights,
            'timestamp': datetime.now()
        }

        # Get cached insights
        cached = insights_analyzer.get_cached_insights('test_model')
        assert cached == test_insights

    def test_get_cached_insights_expired(self, insights_analyzer):
        """Test getting expired cached insights"""
        # Add expired cache entry
        test_insights = {'model_key': 'test', 'should_retrain': True}
        insights_analyzer.insights_cache['test_model'] = {
            'data': test_insights,
            'timestamp': datetime.now() - timedelta(hours=1)  # Expired
        }

        # Get cached insights (should return None due to expiration)
        cached = insights_analyzer.get_cached_insights('test_model')
        assert cached is None
        assert 'test_model' not in insights_analyzer.insights_cache  # Should be removed

    def test_clear_cache(self, insights_analyzer):
        """Test clearing cache"""
        # Add some cache entries
        insights_analyzer.insights_cache['model1'] = {'data': {}, 'timestamp': datetime.now()}
        insights_analyzer.insights_cache['model2'] = {'data': {}, 'timestamp': datetime.now()}

        # Clear cache
        insights_analyzer.clear_cache()

        # Cache should be empty
        assert len(insights_analyzer.insights_cache) == 0

    def test_invalid_model_key_format(self, insights_analyzer):
        """Test handling of invalid model key format"""
        insights = insights_analyzer.get_model_recommendation_insights('invalid_key', days=30)

        # Should return default insights
        assert insights['should_retrain'] == False
        assert insights['retrain_priority'] == 'low'

    def test_confidence_issues_detection(self, insights_analyzer):
        """Test confidence issues detection"""
        # Test overconfident model
        insights = {
            'overall_accuracy': 50.0,
            'avg_final_confidence': 0.9,
            'total_recommendations': 100,
            'confidence_issues': ['overconfident'],
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')
        assert 'overconfident' in suggestions['reason'].lower()

        # Test underconfident model
        insights = {
            'overall_accuracy': 80.0,
            'avg_final_confidence': 0.3,
            'total_recommendations': 100,
            'confidence_issues': ['underconfident'],
            'data_quality': {'insufficient_data': False}
        }

        suggestions = insights_analyzer._generate_retraining_suggestions(insights, 'test_model')
        assert 'underconfident' in suggestions['reason'].lower()

    def test_model_specific_analysis(self, insights_analyzer):
        """Test model-specific analysis"""
        performance_data = [
            {
                'ml_model_key': 'model_1',
                'analysis_method': 'ml_enhanced',
                'total_recommendations': 50,
                'accuracy_percentage': 45.0,
                'avg_final_confidence': 0.8,
                'total_recommendation_value': -200.0,
                'correct_recommendations': 22,
                'incorrect_recommendations': 28,
                'avg_ml_confidence': 0.7,
                'total_profit_if_followed': 100.0,
                'total_profit_if_opposite': 300.0,
                'avg_profit_per_recommendation': 2.0
            },
            {
                'ml_model_key': 'model_2',
                'analysis_method': 'trade_health',
                'total_recommendations': 30,
                'accuracy_percentage': 75.0,
                'avg_final_confidence': 0.6,
                'total_recommendation_value': 500.0,
                'correct_recommendations': 22,
                'incorrect_recommendations': 8,
                'avg_ml_confidence': 0.5,
                'total_profit_if_followed': 600.0,
                'total_profit_if_opposite': 100.0,
                'avg_profit_per_recommendation': 16.7
            }
        ]

        insights = insights_analyzer._analyze_recommendation_performance(performance_data, 'test_model')

        # Should have analysis for both models
        assert len(insights['model_analysis']) == 2
        assert 'model_1_ml_enhanced' in insights['model_analysis']
        assert 'model_2_trade_health' in insights['model_analysis']

    def test_error_handling_in_analysis(self, insights_analyzer):
        """Test error handling in analysis methods"""
        # Test with empty data
        insights = insights_analyzer._analyze_recommendation_performance([], 'test_model')
        assert insights['total_recommendations'] == 0

        # Test with malformed data
        malformed_data = [{'invalid': 'data'}]
        insights = insights_analyzer._analyze_recommendation_performance(malformed_data, 'test_model')
        assert 'total_recommendations' in insights

if __name__ == '__main__':
    pytest.main([__file__])
