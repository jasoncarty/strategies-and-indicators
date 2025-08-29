#!/usr/bin/env python3
"""
Integration tests for risk management endpoints
Tests actual HTTP communication between ML service and Analytics service
"""

import pytest
import sys
import json
import time
from pathlib import Path
from unittest.mock import Mock, patch
import requests

# Add ML_Webserver to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "ML_Webserver"))

from ml_prediction_service import app as ml_app


class TestRiskManagementEndpointsIntegration:
    """Integration tests for risk management endpoints"""

    @pytest.fixture
    def ml_client(self):
        """Create ML service test client"""
        ml_app.config['TESTING'] = True
        with ml_app.test_client() as client:
            yield client

    @pytest.fixture
    def analytics_base_url(self):
        """Get analytics service base URL from environment"""
        import os
        # Use test environment URL from docker.test.env
        return os.getenv('ANALYTICS_EXTERNAL_URL', 'http://localhost:5008')

    def test_analytics_risk_positions_endpoint(self, analytics_base_url):
        """Test the analytics service /risk/positions endpoint"""
        # Make actual HTTP request to analytics service
        response = requests.get(f"{analytics_base_url}/risk/positions", timeout=10)

        # Verify response structure
        assert response.status_code == 200
        data = response.json()

        # Verify response format
        assert 'status' in data
        assert 'positions' in data
        assert 'count' in data
        assert 'timestamp' in data

        # Verify status is success
        assert data['status'] == 'success'

        # Verify positions is a list
        assert isinstance(data['positions'], list)
        assert data['count'] == len(data['positions'])

        # If there are positions, verify their structure
        if data['positions']:
            position = data['positions'][0]
            required_fields = [
                'ticket', 'symbol', 'direction', 'volume',
                'open_price', 'current_price', 'stop_loss',
                'take_profit', 'profit_loss', 'open_time', 'comment'
            ]

            for field in required_fields:
                assert field in position, f"Missing field: {field}"

            # Verify data types
            assert isinstance(position['ticket'], str)
            assert isinstance(position['symbol'], str)
            assert position['direction'].lower() in ['buy', 'sell']
            assert isinstance(position['volume'], (int, float))
            assert isinstance(position['open_price'], (int, float))
            assert isinstance(position['current_price'], (int, float))

        print(f"✅ Analytics /risk/positions endpoint working - {data['count']} positions")

    def test_analytics_risk_portfolio_endpoint(self, analytics_base_url):
        """Test the analytics service /risk/portfolio endpoint"""
        # Make actual HTTP request to analytics service
        response = requests.get(f"{analytics_base_url}/risk/portfolio", timeout=10)

        # Verify response structure
        assert response.status_code == 200
        data = response.json()

        # Verify response format
        assert 'status' in data
        assert 'portfolio' in data
        assert 'timestamp' in data

        # Verify status is success
        assert data['status'] == 'success'

        # Verify portfolio structure
        portfolio = data['portfolio']
        required_fields = [
            'equity', 'balance', 'margin', 'free_margin',
            'total_positions', 'long_positions', 'short_positions',
            'total_volume', 'avg_lot_size'
        ]

        for field in required_fields:
            assert field in portfolio, f"Missing field: {field}"

        # Verify data types
        assert isinstance(portfolio['equity'], (int, float))
        assert isinstance(portfolio['balance'], (int, float))
        assert isinstance(portfolio['total_positions'], int)
        assert isinstance(portfolio['long_positions'], int)
        assert isinstance(portfolio['short_positions'], int)
        assert isinstance(portfolio['total_volume'], (int, float))
        assert isinstance(portfolio['avg_lot_size'], (int, float))

        # Verify logical consistency
        # Note: total_positions may include test positions or other directions
        # that don't fit into long/short categories
        assert portfolio['total_positions'] >= portfolio['long_positions'] + portfolio['short_positions']
        assert portfolio['total_positions'] >= 0
        assert portfolio['long_positions'] >= 0
        assert portfolio['short_positions'] >= 0

        print(f"✅ Analytics /risk/portfolio endpoint working - {portfolio['total_positions']} total positions")

    def test_ml_risk_status_endpoint_integration(self, ml_client, analytics_base_url):
        """Test the ML service /risk/status endpoint with real analytics service"""
        # First verify analytics service is available
        analytics_response = requests.get(f"{analytics_base_url}/health", timeout=5)
        assert analytics_response.status_code == 200, "Analytics service not healthy"

        # Test ML service risk status endpoint
        response = ml_client.get('/risk/status')

        # Verify response structure
        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify response format
        assert 'status' in data
        assert 'risk_status' in data
        assert 'data_source' in data
        assert 'timestamp' in data

        # Verify status is success
        assert data['status'] == 'success'
        assert data['data_source'] == 'analytics_service'

        # Verify risk status structure
        risk_status = data['risk_status']
        assert 'status' in risk_status
        assert 'portfolio' in risk_status

        # Verify portfolio data
        portfolio = risk_status['portfolio']
        assert 'total_risk_percent' in portfolio
        assert 'current_drawdown_percent' in portfolio

        # Verify data types
        assert isinstance(portfolio['total_risk_percent'], (int, float))
        assert isinstance(portfolio['current_drawdown_percent'], (int, float))

        print(f"✅ ML /risk/status endpoint working with analytics service")
        print(f"   Portfolio Risk: {portfolio['total_risk_percent']:.2f}%")
        print(f"   Current Drawdown: {portfolio['current_drawdown_percent']:.2f}%")

    def test_end_to_end_risk_data_flow(self, analytics_base_url):
        """Test complete data flow from analytics service to ML service"""
        # Step 1: Get positions from analytics service
        positions_response = requests.get(f"{analytics_base_url}/risk/positions", timeout=10)
        assert positions_response.status_code == 200
        positions_data = positions_response.json()

        # Step 2: Get portfolio from analytics service
        portfolio_response = requests.get(f"{analytics_base_url}/risk/portfolio", timeout=10)
        assert portfolio_response.status_code == 200
        portfolio_data = portfolio_response.json()

        # Step 3: Verify data consistency between endpoints
        assert positions_data['count'] == portfolio_data['portfolio']['total_positions']

        # Step 4: Verify position counts match
        actual_long_count = sum(1 for p in positions_data['positions'] if p['direction'].lower() == 'buy')
        actual_short_count = sum(1 for p in positions_data['positions'] if p['direction'].lower() == 'sell')

        assert actual_long_count == portfolio_data['portfolio']['long_positions']
        assert actual_short_count == portfolio_data['portfolio']['short_positions']

        # Step 5: Verify volume calculations
        total_volume = sum(p['volume'] for p in positions_data['positions'])
        if positions_data['count'] > 0:
            avg_lot_size = total_volume / positions_data['count']
            # Allow for small floating point differences
            assert abs(avg_lot_size - portfolio_data['portfolio']['avg_lot_size']) < 0.001

        print(f"✅ End-to-end risk data flow working correctly")
        print(f"   Positions: {positions_data['count']}")
        print(f"   Long: {actual_long_count}, Short: {actual_short_count}")
        print(f"   Total Volume: {total_volume}")

    def test_analytics_service_error_handling(self, analytics_base_url):
        """Test analytics service error handling for invalid requests"""
        # Test invalid endpoint
        response = requests.get(f"{analytics_base_url}/risk/invalid", timeout=10)
        assert response.status_code == 404

        # Test invalid method
        response = requests.post(f"{analytics_base_url}/risk/positions", timeout=10)
        assert response.status_code == 405  # Method not allowed

        print(f"✅ Analytics service error handling working correctly")

    def test_ml_service_error_handling(self, ml_client):
        """Test ML service error handling for risk endpoints"""
        # Test invalid method
        response = ml_client.post('/risk/status')
        assert response.status_code == 405  # Method not allowed

        # Test with no ML service (should be handled gracefully)
        with patch('ml_prediction_service.ml_service', None):
            response = ml_client.get('/risk/status')
            assert response.status_code == 500
            data = json.loads(response.data)
            assert data['status'] == 'error'
            assert 'not initialized' in data['message']

        print(f"✅ ML service error handling working correctly")

    def test_risk_data_consistency_across_requests(self, analytics_base_url):
        """Test that risk data remains consistent across multiple requests"""
        # Make multiple requests to check consistency
        responses = []
        for i in range(3):
            response = requests.get(f"{analytics_base_url}/risk/positions", timeout=10)
            assert response.status_code == 200
            responses.append(response.json())
            time.sleep(0.1)  # Small delay between requests

        # Verify all responses have the same count
        counts = [r['count'] for r in responses]
        assert len(set(counts)) == 1, f"Position count inconsistent: {counts}"

        # Verify all responses have the same timestamp format
        timestamps = [r['timestamp'] for r in responses]
        for timestamp in timestamps:
            assert 'T' in timestamp  # ISO format
            assert timestamp.count(':') == 2  # Valid time format

        print(f"✅ Risk data consistency maintained across {len(responses)} requests")

    def test_risk_endpoints_performance(self, analytics_base_url):
        """Test performance of risk endpoints"""
        # Test positions endpoint performance
        start_time = time.time()
        response = requests.get(f"{analytics_base_url}/risk/positions", timeout=10)
        positions_time = time.time() - start_time

        # Test portfolio endpoint performance
        start_time = time.time()
        response = requests.get(f"{analytics_base_url}/risk/portfolio", timeout=10)
        portfolio_time = time.time() - start_time

        # Verify reasonable performance (should be under 1 second)
        assert positions_time < 1.0, f"Positions endpoint too slow: {positions_time:.3f}s"
        assert portfolio_time < 1.0, f"Portfolio endpoint too slow: {portfolio_time:.3f}s"

        print(f"✅ Risk endpoints performance acceptable")
        print(f"   Positions: {positions_time:.3f}s")
        print(f"   Portfolio: {portfolio_time:.3f}s")


if __name__ == "__main__":
    # Run integration tests
    pytest.main([__file__, "-v", "--tb=short"])
