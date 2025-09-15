"""
Integration tests for retraining pipeline with recommendation analysis
Tests the full integration of recommendation analysis into the automated retraining pipeline
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

from ML_Webserver.automated_retraining_pipeline import AutomatedRetrainingPipeline
from ML_Webserver.recommendation_insights import RecommendationInsights

class TestRetrainingPipelineIntegration:
    """Integration tests for retraining pipeline with recommendation analysis"""

    @pytest.fixture
    def mock_analytics_responses(self):
        """Mock analytics service responses"""
        return {
            'model_alerts': {
                'alerts': [
                    {
                        'model_key': 'buy_EURUSD+_PERIOD_M5',
                        'alert_level': 'warning',
                        'type': 'low_win_rate',
                        'current_metrics': {'win_rate': 45.0}
                    }
                ]
            },
            'model_health': {
                'models': [
                    {
                        'model_key': 'buy_EURUSD+_PERIOD_M5',
                        'health_score': 60,
                        'accuracy': 0.55
                    }
                ],
                'summary': {'overall_health': 60.0}
            },
            'recommendation_performance': {
                'data': [
                    {
                        'ml_model_key': 'buy_model_EURUSD+_PERIOD_M5',
                        'analysis_method': 'ml_enhanced',
                        'total_recommendations': 100,
                        'correct_recommendations': 45,
                        'incorrect_recommendations': 55,
                        'accuracy_percentage': 45.0,
                        'avg_ml_confidence': 0.8,
                        'avg_final_confidence': 0.85,
                        'total_profit_if_followed': 500.0,
                        'total_profit_if_opposite': 800.0,
                        'total_recommendation_value': -300.0,
                        'avg_profit_per_recommendation': -3.0
                    }
                ]
            },
            'model_discovery': {
                'new_models': [
                    {
                        'symbol': 'GBPUSD+',
                        'timeframe': 'M15',
                        'direction': 'buy'
                    }
                ]
            }
        }

    @pytest.fixture
    def pipeline(self, mock_analytics_responses):
        """Create retraining pipeline with mocked dependencies"""
        with patch('ML_Webserver.automated_retraining_pipeline.requests') as mock_requests:
            # Mock all analytics service calls
            def mock_get(url, **kwargs):
                mock_response = Mock()
                if 'model_alerts' in url:
                    mock_response.status_code = 200
                    mock_response.json.return_value = mock_analytics_responses['model_alerts']
                elif 'model_health' in url:
                    mock_response.status_code = 200
                    mock_response.json.return_value = mock_analytics_responses['model_health']
                elif 'recommendation/performance' in url:
                    mock_response.status_code = 200
                    mock_response.json.return_value = mock_analytics_responses['recommendation_performance']
                elif 'model_discovery' in url:
                    mock_response.status_code = 200
                    mock_response.json.return_value = mock_analytics_responses['model_discovery']
                else:
                    mock_response.status_code = 404
                    mock_response.json.return_value = {}
                return mock_response

            mock_requests.get.side_effect = mock_get
            mock_requests.post.return_value.status_code = 200
            mock_requests.post.return_value.json.return_value = {'status': 'success'}

            # Create pipeline
            pipeline = AutomatedRetrainingPipeline(
                analytics_url='http://localhost:5001',
                ml_service_url='http://localhost:5003',
                models_dir='test_models',
                check_interval_minutes=1
            )

            # Mock the retraining framework
            pipeline.retraining_framework = Mock()
            pipeline.retraining_framework.retrain_model.return_value = True

            yield pipeline

    def test_get_recommendation_based_retraining_suggestions(self, pipeline):
        """Test getting recommendation-based retraining suggestions"""
        # Mock existing models by patching Path.glob
        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [
                Mock(stem='buy_model_EURUSD+_PERIOD_M5'),
                Mock(stem='sell_model_GBPUSD+_PERIOD_M15')
            ]

            suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Assertions
        assert 'retrain_candidates' in suggestions
        assert 'total_candidates' in suggestions
        assert 'models_analyzed' in suggestions
        assert suggestions['models_analyzed'] == 2

    def test_process_retraining_queue_with_recommendations(self, pipeline):
        """Test processing retraining queue with recommendation analysis"""
        # Mock existing models by patching Path.glob
        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [
                Mock(stem='buy_model_EURUSD+_PERIOD_M5')
            ]

            result = pipeline.process_retraining_queue()

        # Assertions
        assert 'processed' in result
        assert 'retrained' in result
        assert 'skipped' in result
        assert 'new_models_created' in result
        assert 'recommendation_retrained' in result
        assert 'recommendation_candidates' in result

    def test_recommendation_analysis_status(self, pipeline):
        """Test getting recommendation analysis status"""
        # Mock existing models by patching Path.glob
        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [
                Mock(stem='buy_model_EURUSD+_PERIOD_M5')
            ]

            status = pipeline.get_recommendation_analysis_status()

        # Assertions
        assert 'analysis_date' in status
        assert 'recommendation_candidates' in status
        assert 'models_analyzed' in status
        assert 'insights_summary' in status
        assert 'cache_info' in status

    def test_recommendation_insights_integration(self, pipeline):
        """Test recommendation insights integration"""
        # Test getting insights for a specific model
        insights = pipeline.recommendation_analyzer.get_model_recommendation_insights(
            'buy_EURUSD+_PERIOD_M5', days=30
        )

        # Assertions
        assert 'model_key' in insights
        assert 'should_retrain' in insights
        assert 'retrain_priority' in insights
        assert 'insights' in insights
        assert 'retraining_suggestions' in insights

    def test_retraining_decision_with_recommendations(self, pipeline):
        """Test retraining decision based on recommendation analysis"""
        # Mock recommendation insights that suggest retraining
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'high',
                    'retrain_reason': 'Low accuracy: 45.0%',
                    'insights': {
                        'overall_accuracy': 45.0,
                        'total_recommendation_value': -300.0,
                        'confidence_issues': ['overconfident']
                    }
                }
            }
        }

        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [Mock(stem='buy_model_EURUSD+_PERIOD_M5')]

            with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                             return_value=mock_insights):
                suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should have retrain candidates
        assert suggestions['total_candidates'] > 0
        assert len(suggestions['retrain_candidates']) > 0

        # Check candidate details
        candidate = suggestions['retrain_candidates'][0]
        assert candidate['priority'] == 'high'
        assert 'Low accuracy' in candidate['reason']

    def test_retraining_decision_without_recommendations(self, pipeline):
        """Test retraining decision when no recommendation issues"""
        # Mock recommendation insights that don't suggest retraining
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': False,
                    'retrain_priority': 'low',
                    'retrain_reason': 'No specific issues detected',
                    'insights': {
                        'overall_accuracy': 75.0,
                        'total_recommendation_value': 1000.0,
                        'confidence_issues': []
                    }
                }
            }
        }

        with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                         return_value=mock_insights):
            suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should have no retrain candidates
        assert suggestions['total_candidates'] == 0
        assert len(suggestions['retrain_candidates']) == 0

    def test_confidence_calibration_issues(self, pipeline):
        """Test handling of confidence calibration issues"""
        # Mock insights with confidence issues
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'critical',
                    'retrain_reason': 'Severely overconfident model',
                    'insights': {
                        'overall_accuracy': 50.0,
                        'avg_final_confidence': 0.9,
                        'confidence_issues': ['severely_overconfident']
                    }
                }
            }
        }

        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [Mock(stem='buy_model_EURUSD+_PERIOD_M5')]

            with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                             return_value=mock_insights):
                suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should have critical priority candidate
        assert suggestions['total_candidates'] > 0
        candidate = suggestions['retrain_candidates'][0]
        assert candidate['priority'] == 'critical'
        assert 'overconfident' in candidate['reason'].lower()

    def test_negative_recommendation_value(self, pipeline):
        """Test handling of negative recommendation value"""
        # Mock insights with negative value
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'high',
                    'retrain_reason': 'Negative recommendation value: $-500.00',
                    'insights': {
                        'overall_accuracy': 60.0,
                        'total_recommendation_value': -500.0,
                        'confidence_issues': []
                    }
                }
            }
        }

        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [Mock(stem='buy_model_EURUSD+_PERIOD_M5')]

            with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                             return_value=mock_insights):
                suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should have high priority candidate
        assert suggestions['total_candidates'] > 0
        candidate = suggestions['retrain_candidates'][0]
        assert candidate['priority'] == 'high'
        assert 'Negative recommendation value' in candidate['reason']

    def test_insufficient_data_handling(self, pipeline):
        """Test handling of insufficient recommendation data"""
        # Mock insights with insufficient data
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': False,
                    'retrain_priority': 'low',
                    'retrain_reason': 'Insufficient recommendation data for analysis',
                    'insights': {
                        'total_recommendations': 5,
                        'overall_accuracy': 0,
                        'data_quality': {'insufficient_data': True}
                    }
                }
            }
        }

        with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                         return_value=mock_insights):
            suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should have no retrain candidates due to insufficient data
        assert suggestions['total_candidates'] == 0

    def test_caching_behavior(self, pipeline):
        """Test caching behavior in recommendation analysis"""
        # Mock insights
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'medium',
                    'retrain_reason': 'Moderate accuracy: 65.0%',
                    'insights': {
                        'overall_accuracy': 65.0,
                        'total_recommendations': 50
                    }
                }
            }
        }

        with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                         return_value=mock_insights):
            # First call
            suggestions1 = pipeline.get_recommendation_based_retraining_suggestions()

            # Second call should use cache
            suggestions2 = pipeline.get_recommendation_based_retraining_suggestions()

        # Both should return the same results
        assert suggestions1['total_candidates'] == suggestions2['total_candidates']

    def test_error_handling_in_recommendation_analysis(self, pipeline):
        """Test error handling in recommendation analysis"""
        # Mock error in recommendation analysis
        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [Mock(stem='buy_model_EURUSD+_PERIOD_M5')]

            with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                             side_effect=Exception("Analysis error")):
                suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should handle error gracefully
        assert 'error' in suggestions
        assert suggestions['total_candidates'] == 0

    def test_retraining_priority_ordering(self, pipeline):
        """Test that retraining candidates are ordered by priority"""
        # Mock multiple candidates with different priorities
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'critical',
                    'retrain_reason': 'Critical issue',
                    'insights': {}
                },
                'sell_GBPUSD+_PERIOD_M15': {
                    'should_retrain': True,
                    'retrain_priority': 'high',
                    'retrain_reason': 'High priority issue',
                    'insights': {}
                },
                'buy_AUDUSD+_PERIOD_M30': {
                    'should_retrain': True,
                    'retrain_priority': 'medium',
                    'retrain_reason': 'Medium priority issue',
                    'insights': {}
                }
            }
        }

        with patch('pathlib.Path.glob') as mock_glob:
            mock_glob.return_value = [
                Mock(stem='buy_model_EURUSD+_PERIOD_M5'),
                Mock(stem='sell_model_GBPUSD+_PERIOD_M15'),
                Mock(stem='buy_model_AUDUSD+_PERIOD_M30')
            ]

            with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                             return_value=mock_insights):
                suggestions = pipeline.get_recommendation_based_retraining_suggestions()

        # Should be ordered by priority
        candidates = suggestions['retrain_candidates']
        assert len(candidates) == 3
        assert candidates[0]['priority'] == 'critical'
        assert candidates[1]['priority'] == 'high'
        assert candidates[2]['priority'] == 'medium'

    def test_integration_with_existing_alerts(self, pipeline):
        """Test integration with existing model alerts"""
        # Mock both alerts and recommendation suggestions
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'high',
                    'retrain_reason': 'Recommendation analysis: Low accuracy',
                    'insights': {}
                }
            }
        }

        with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                         return_value=mock_insights):
            result = pipeline.process_retraining_queue()

        # Should process both alerts and recommendations
        assert result['processed'] > 0
        assert 'recommendation_candidates' in result

    def test_retraining_with_recommendation_insights(self, pipeline):
        """Test actual retraining with recommendation insights"""
        # Mock successful retraining
        pipeline.retraining_framework.retrain_model.return_value = True

        # Mock recommendation insights suggesting retraining
        mock_insights = {
            'insights': {
                'buy_EURUSD+_PERIOD_M5': {
                    'should_retrain': True,
                    'retrain_priority': 'high',
                    'retrain_reason': 'Low accuracy: 45.0%',
                    'recommended_actions': ['Retrain with more recent data'],
                    'confidence_adjustments': ['Lower confidence thresholds'],
                    'insights': {}
                }
            }
        }

        with patch.object(pipeline.recommendation_analyzer, 'get_all_model_insights',
                         return_value=mock_insights):
            with patch('pathlib.Path.glob') as mock_glob:
                mock_glob.return_value = [Mock(stem='buy_model_EURUSD+_PERIOD_M5')]

                result = pipeline.process_retraining_queue()

        # Should have processed recommendations
        assert result['recommendation_candidates'] > 0

if __name__ == '__main__':
    pytest.main([__file__])
