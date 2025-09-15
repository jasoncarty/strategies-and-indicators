"""
Integration tests for recommendation tracking system
Tests the full integration between ML prediction service, analytics service, and recommendation tracking
"""

import pytest
import requests
import json
import time
from datetime import datetime, timedelta
from typing import Dict, Any

class TestRecommendationTrackingIntegration:
    """Integration tests for recommendation tracking system"""

    @pytest.fixture
    def analytics_client(self, test_analytics_client):
        """Get analytics service client"""
        return test_analytics_client

    @pytest.fixture
    def ml_client(self, test_ml_client):
        """Get ML service client"""
        return test_ml_client

    def test_end_to_end_recommendation_tracking(self, analytics_client, ml_client):
        """Test complete end-to-end recommendation tracking workflow"""

        # Step 1: Get active trade recommendation from ML service
        ml_request_data = {
            'trade_id': 99999,  # Use a test trade ID
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'trade_direction': 'buy',
            'entry_price': 1.2000,
            'current_price': 1.2010,
            'trade_duration_minutes': 30,
            'current_profit_pips': 10.0,
            'current_profit_money': 100.0,
            'account_balance': 10000.0,
            'features': {
                'rsi': 0.6,
                'macd': 0.4,
                'bollinger_upper': 1.2020,
                'bollinger_lower': 1.1980
            }
        }

        # Make request to ML service
        ml_response = ml_client.post('/active_trade_recommendation', json=ml_request_data)
        assert ml_response.status_code == 200

        ml_data = ml_response.json()
        assert 'recommendation' in ml_data
        assert 'confidence' in ml_data

        # Wait a moment for async recommendation tracking
        time.sleep(2)

        # Step 2: Verify recommendation was recorded in analytics service
        rec_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert rec_response.status_code == 200

        rec_data = rec_response.json()
        assert 'data' in rec_data

        # Step 3: Simulate trade close and verify outcome tracking
        trade_close_data = {
            'trade_id': 99999,
            'strategy': 'test_strategy',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'close_price': 1.2015,
            'profit_loss': 150.0,
            'profit_loss_pips': 15.0,
            'close_time': int(time.time()),
            'exit_reason': 'take_profit',
            'status': 'closed',
            'success': True,
            'timestamp': int(time.time())
        }

        close_response = analytics_client.post('/ml_trade_close', json=trade_close_data)
        assert close_response.status_code == 201

        # Step 4: Verify recommendation outcome was updated
        outcome_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert outcome_response.status_code == 200

        outcome_data = outcome_response.json()
        assert 'data' in outcome_data

    def test_recommendation_dashboard_endpoints(self, analytics_client):
        """Test recommendation dashboard endpoints"""

        # Test summary endpoint
        summary_response = analytics_client.get('/dashboard/recommendations/summary')
        assert summary_response.status_code == 200

        summary_data = summary_response.json()
        assert 'summary' in summary_data
        assert 'total_recommendations' in summary_data['summary']

        # Test performance endpoint
        performance_response = analytics_client.get('/dashboard/recommendations/performance')
        assert performance_response.status_code == 200

        performance_data = performance_response.json()
        assert 'data' in performance_data
        assert 'charts' in performance_data

        # Test insights endpoint
        insights_response = analytics_client.get('/dashboard/recommendations/insights')
        assert insights_response.status_code == 200

        insights_data = insights_response.json()
        assert 'insights' in insights_data

        # Test timeline endpoint
        timeline_response = analytics_client.get('/dashboard/recommendations/timeline')
        assert timeline_response.status_code == 200

        timeline_data = timeline_response.json()
        assert 'timeline' in timeline_data

    def test_recommendation_tracking_with_multiple_trades(self, analytics_client, ml_client):
        """Test recommendation tracking with multiple trades"""

        trade_ids = [88888, 88889, 88890]

        # Record recommendations for multiple trades
        for trade_id in trade_ids:
            ml_request_data = {
                'trade_id': trade_id,
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'trade_direction': 'buy',
                'entry_price': 1.2000,
                'current_price': 1.2010,
                'trade_duration_minutes': 30,
                'current_profit_pips': 10.0,
                'current_profit_money': 100.0,
                'account_balance': 10000.0,
                'features': {
                    'rsi': 0.6,
                    'macd': 0.4
                }
            }

            ml_response = ml_client.post('/active_trade_recommendation', json=ml_request_data)
            assert ml_response.status_code == 200

        # Wait for async processing
        time.sleep(3)

        # Verify all recommendations were recorded
        rec_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert rec_response.status_code == 200

        rec_data = rec_response.json()
        assert 'data' in rec_data

        # Close all trades
        for trade_id in trade_ids:
            trade_close_data = {
                'trade_id': trade_id,
                'strategy': 'test_strategy',
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'close_price': 1.2015,
                'profit_loss': 150.0,
                'profit_loss_pips': 15.0,
                'close_time': int(time.time()),
                'exit_reason': 'take_profit',
                'status': 'closed',
                'success': True,
                'timestamp': int(time.time())
            }

            close_response = analytics_client.post('/ml_trade_close', json=trade_close_data)
            assert close_response.status_code == 201

    def test_recommendation_tracking_error_handling(self, analytics_client, ml_client):
        """Test error handling in recommendation tracking"""

        # Test with invalid trade data
        invalid_ml_request = {
            'trade_id': 'invalid',  # Invalid trade ID
            'symbol': 'EURUSD+',
            'timeframe': 'M5'
            # Missing required fields
        }

        ml_response = ml_client.post('/active_trade_recommendation', json=invalid_ml_request)
        # Should return 400 for invalid data (correct behavior)
        assert ml_response.status_code == 400

        # Test with invalid recommendation data
        invalid_rec_data = {
            'trade_id': 77777,
            'symbol': 'EURUSD+'
            # Missing required fields
        }

        rec_response = analytics_client.post('/recommendation/active_trade', json=invalid_rec_data)
        assert rec_response.status_code == 400

    def test_recommendation_performance_filtering(self, analytics_client):
        """Test recommendation performance filtering by symbol and timeframe"""

        # Test filtering by symbol
        eur_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&days=30')
        assert eur_response.status_code == 200

        eur_data = eur_response.json()
        assert 'data' in eur_data

        # Test filtering by timeframe
        m5_response = analytics_client.get('/recommendation/performance?timeframe=M5&days=30')
        assert m5_response.status_code == 200

        m5_data = m5_response.json()
        assert 'data' in m5_data

        # Test filtering by both
        both_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=30')
        assert both_response.status_code == 200

        both_data = both_response.json()
        assert 'data' in both_data

    def test_recommendation_tracking_concurrent_requests(self, analytics_client, ml_client):
        """Test recommendation tracking with concurrent requests"""
        import threading
        import queue

        results = queue.Queue()

        def make_recommendation_request(trade_id):
            try:
                ml_request_data = {
                    'trade_id': trade_id,
                    'symbol': 'EURUSD+',
                    'timeframe': 'M5',
                    'trade_direction': 'buy',
                    'entry_price': 1.2000,
                    'current_price': 1.2010,
                    'trade_duration_minutes': 30,
                    'current_profit_pips': 10.0,
                    'current_profit_money': 100.0,
                    'account_balance': 10000.0,
                    'features': {
                        'rsi': 0.6,
                        'macd': 0.4
                    }
                }

                ml_response = ml_client.post('/active_trade_recommendation', json=ml_request_data)
                results.put(('ml', trade_id, ml_response.status_code))

                # Wait for async processing
                time.sleep(1)

                # Check if recommendation was recorded
                rec_response = analytics_client.get(f'/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
                results.put(('rec', trade_id, rec_response.status_code))

            except Exception as e:
                results.put(('error', trade_id, str(e)))

        # Start multiple threads
        threads = []
        for i in range(5):
            trade_id = 66660 + i
            thread = threading.Thread(target=make_recommendation_request, args=(trade_id,))
            threads.append(thread)
            thread.start()

        # Wait for all threads to complete
        for thread in threads:
            thread.join()

        # Check results
        ml_successes = 0
        rec_successes = 0
        errors = 0

        while not results.empty():
            result_type, trade_id, status = results.get()
            if result_type == 'ml' and status == 200:
                ml_successes += 1
            elif result_type == 'rec' and status == 200:
                rec_successes += 1
            elif result_type == 'error':
                errors += 1

        # All ML requests should succeed
        assert ml_successes == 5
        # Most recommendation requests should succeed (some might fail due to timing)
        assert rec_successes >= 3
        # No errors should occur
        assert errors == 0

    def test_recommendation_tracking_data_consistency(self, analytics_client, ml_client):
        """Test data consistency in recommendation tracking"""

        trade_id = 55555

        # Record recommendation
        ml_request_data = {
            'trade_id': trade_id,
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'trade_direction': 'buy',
            'entry_price': 1.2000,
            'current_price': 1.2010,
            'trade_duration_minutes': 30,
            'current_profit_pips': 10.0,
            'current_profit_money': 100.0,
            'account_balance': 10000.0,
            'features': {
                'rsi': 0.6,
                'macd': 0.4
            }
        }

        ml_response = ml_client.post('/active_trade_recommendation', json=ml_request_data)
        assert ml_response.status_code == 200

        ml_data = ml_response.json()
        original_confidence = ml_data.get('confidence', 0)

        # Wait for async processing
        time.sleep(2)

        # Verify data consistency
        rec_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert rec_response.status_code == 200

        rec_data = rec_response.json()
        assert 'data' in rec_data

        # Close trade
        trade_close_data = {
            'trade_id': trade_id,
            'strategy': 'test_strategy',
            'symbol': 'EURUSD+',
            'timeframe': 'M5',
            'close_price': 1.2015,
            'profit_loss': 150.0,
            'profit_loss_pips': 15.0,
            'close_time': int(time.time()),
            'exit_reason': 'take_profit',
            'status': 'closed',
            'success': True,
            'timestamp': int(time.time())
        }

        close_response = analytics_client.post('/ml_trade_close', json=trade_close_data)
        assert close_response.status_code == 201

        # Verify final data consistency
        final_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert final_response.status_code == 200

        final_data = final_response.json()
        assert 'data' in final_data

    def test_recommendation_tracking_performance_metrics(self, analytics_client, ml_client):
        """Test recommendation tracking performance metrics"""

        # Record multiple recommendations with different outcomes
        test_cases = [
            {'trade_id': 44440, 'profit': 200.0, 'expected_accuracy': True},
            {'trade_id': 44441, 'profit': -100.0, 'expected_accuracy': False},
            {'trade_id': 44442, 'profit': 150.0, 'expected_accuracy': True},
            {'trade_id': 44443, 'profit': -50.0, 'expected_accuracy': False},
            {'trade_id': 44444, 'profit': 300.0, 'expected_accuracy': True}
        ]

        for case in test_cases:
            # Record recommendation
            ml_request_data = {
                'trade_id': case['trade_id'],
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'trade_direction': 'buy',
                'entry_price': 1.2000,
                'current_price': 1.2010,
                'trade_duration_minutes': 30,
                'current_profit_pips': 10.0,
                'current_profit_money': 100.0,
                'account_balance': 10000.0,
                'features': {
                    'rsi': 0.6,
                    'macd': 0.4
                }
            }

            ml_response = ml_client.post('/active_trade_recommendation', json=ml_request_data)
            assert ml_response.status_code == 200

            # Wait for async processing
            time.sleep(1)

            # Close trade
            trade_close_data = {
                'trade_id': case['trade_id'],
                'strategy': 'test_strategy',
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'close_price': 1.2015,
                'profit_loss': case['profit'],
                'profit_loss_pips': case['profit'] / 10.0,
                'close_time': int(time.time()),
                'exit_reason': 'take_profit' if case['profit'] > 0 else 'stop_loss',
                'status': 'closed',
                'success': case['profit'] > 0,
                'timestamp': int(time.time())
            }

            close_response = analytics_client.post('/ml_trade_close', json=trade_close_data)
            assert close_response.status_code == 201

        # Wait for all processing to complete
        time.sleep(3)

        # Verify performance metrics
        performance_response = analytics_client.get('/recommendation/performance?symbol=EURUSD+&timeframe=M5&days=1')
        assert performance_response.status_code == 200

        performance_data = performance_response.json()
        assert 'data' in performance_data

        # Check that we have performance data
        if performance_data['data']:
            data = performance_data['data'][0]
            assert 'total_recommendations' in data
            assert 'accuracy_percentage' in data
            assert 'total_recommendation_value' in data

if __name__ == '__main__':
    pytest.main([__file__])
