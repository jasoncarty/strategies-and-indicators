#!/usr/bin/env python3
"""
Unit tests for risk management functionality in ML prediction service
Tests the new risk management integration and enhanced response structure
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import json

# Add ML_Webserver to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "ML_Webserver"))

from ml_prediction_service import app


class TestRiskManagement:
    """Test risk management functionality"""

    @pytest.fixture
    def client(self):
        """Create test client"""
        app.config['TESTING'] = True
        with app.test_client() as client:
            yield client

    def test_trade_decision_with_risk_management(self, client):
        """Test trade decision endpoint with risk management integration"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            # Mock the risk manager
            mock_risk_manager = Mock()
            mock_risk_manager.calculate_optimal_lot_size.return_value = (0.1, {'risk_amount': 100.0, 'stop_distance': 0.0015})
            mock_risk_manager.can_open_new_trade.return_value = (True, {'status': 'approved'})
            mock_risk_manager.get_risk_status.return_value = {
                'status': 'healthy',
                'portfolio': {
                    'total_risk_percent': 0.02,
                    'current_drawdown_percent': 0.01
                }
            }

            mock_service.risk_manager = mock_risk_manager

            # Mock the get_prediction method to return enhanced response
            mock_service.get_prediction.return_value = {
                'status': 'success',
                'should_trade': 1,
                'confidence_threshold': 0.3,
                'model_health': {
                    'status': 'healthy',
                    'health_score': 85
                },
                'prediction': {
                    'probability': 0.85,
                    'confidence': 0.7,
                    'model_key': 'buy_EURUSD+_PERIOD_M5',
                    'model_type': 'binary',
                    'direction': 'buy',
                    'strategy': 'ML_Testing_EA',
                    'symbol': 'EURUSD+',
                    'timeframe': 'M5',
                    'timestamp': '2025-01-21T15:30:00'
                },
                'trade_parameters': {
                    'entry_price': 1.0835,
                    'stop_loss': 1.0820,
                    'take_profit': 1.0860,
                    'lot_size': 0.1,
                    'risk_validation': {
                        'can_trade': True,
                        'validation_details': {'status': 'approved'},
                        'risk_status': 'healthy',
                        'portfolio_risk': 0.02,
                        'current_drawdown': 0.01
                    },
                    'lot_calculation': {'risk_amount': 100.0, 'stop_distance': 0.0015},
                    'risk_metrics': {
                        'stop_distance': 0.0015,
                        'risk_reward_ratio': 2.0,
                        'atr_value': 0.0015
                    }
                },
                'metadata': {
                    'features_used': 7,
                    'model_file': 'buy_EURUSD+_PERIOD_M5.pkl',
                    'loaded_at': '2025-01-21T15:00:00'
                }
            }

            test_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'rsi': 65.5,
                'stoch_main': 75.2,
                'macd_main': 0.0012,
                'current_price': 1.0835,
                'atr': 0.0015,
                'account_balance': 10000,
                'risk_per_pip': 1.0,
                'direction': 'buy'
            }

            response = client.post('/trade_decision', json=test_data)

            assert response.status_code == 200
            data = json.loads(response.data)

            # Verify enhanced response structure with risk management
            assert data['status'] == 'success'
            assert data['should_trade'] == 1
            assert 'trade_parameters' in data

            # Verify risk management data
            trade_params = data['trade_parameters']
            assert 'risk_validation' in trade_params
            assert 'risk_metrics' in trade_params
            assert 'lot_calculation' in trade_params

            # Verify risk validation
            risk_validation = trade_params['risk_validation']
            assert risk_validation['can_trade'] is True
            assert risk_validation['risk_status'] == 'healthy'
            assert 'portfolio_risk' in risk_validation
            assert 'current_drawdown' in risk_validation

            # Verify risk metrics
            risk_metrics = trade_params['risk_metrics']
            assert risk_metrics['risk_reward_ratio'] == 2.0
            assert 'stop_distance' in risk_metrics
            assert 'atr_value' in risk_metrics

    def test_risk_manager_integration(self, client):
        """Test that risk manager methods are called correctly when calculating trade parameters"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            # Mock the risk manager
            mock_risk_manager = Mock()
            mock_risk_manager.calculate_optimal_lot_size.return_value = (0.1, {'risk_amount': 100.0, 'stop_distance': 0.0015})
            mock_risk_manager.can_open_new_trade.return_value = (True, {'status': 'approved'})
            mock_risk_manager.get_risk_status.return_value = {
                'status': 'healthy',
                'portfolio': {
                    'total_risk_percent': 0.02,
                    'current_drawdown_percent': 0.01
                }
            }

            mock_service.risk_manager = mock_risk_manager

            # Mock the _calculate_trade_parameters method to actually call the risk manager
            def mock_calculate_trade_parameters(symbol, direction, features):
                # This simulates what the real method does
                current_price = features.get('current_price', 0.0)
                atr = features.get('atr', 0.001)
                account_balance = features.get('account_balance', 10000)

                # Call risk manager methods
                lot_size, lot_calculation = mock_risk_manager.calculate_optimal_lot_size(
                    symbol, current_price, current_price - atr * 2, account_balance
                )

                can_trade, trade_validation = mock_risk_manager.can_open_new_trade(
                    symbol, lot_size, atr * 2, direction.lower()
                )

                risk_status = mock_risk_manager.get_risk_status()

                return {
                    'entry_price': current_price,
                    'stop_loss': current_price - atr * 2,
                    'take_profit': current_price + atr * 4,
                    'lot_size': lot_size,
                    'risk_validation': {
                        'can_trade': can_trade,
                        'validation_details': trade_validation,
                        'risk_status': risk_status['status'],
                        'portfolio_risk': risk_status['portfolio']['total_risk_percent'],
                        'current_drawdown': risk_status['portfolio']['current_drawdown_percent']
                    },
                    'lot_calculation': lot_calculation,
                    'risk_metrics': {
                        'stop_distance': atr * 2,
                        'risk_reward_ratio': 2.0,
                        'atr_value': atr
                    }
                }

            # Mock the get_prediction method to use our custom trade parameters calculation
            def mock_get_prediction(strategy, symbol, timeframe, features, direction, enhanced=False):
                if enhanced:
                    return {
                        'status': 'success',
                        'should_trade': 1,
                        'confidence_threshold': 0.3,
                        'model_health': {'status': 'healthy', 'health_score': 85},
                        'prediction': {
                            'probability': 0.85,
                            'confidence': 0.7,
                            'direction': direction,
                            'strategy': strategy,
                            'symbol': symbol,
                            'timeframe': timeframe
                        },
                        'trade_parameters': mock_calculate_trade_parameters(symbol, direction, features),
                        'metadata': {'features_used': len(features)}
                    }
                else:
                    return {'status': 'success', 'prediction': {'direction': direction}}

            mock_service.get_prediction.side_effect = mock_get_prediction

            # Test the endpoint
            test_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'current_price': 1.0835,
                'atr': 0.0015,
                'account_balance': 10000,
                'direction': 'buy'
            }

            response = client.post('/trade_decision', json=test_data)
            assert response.status_code == 200

            # Verify risk manager methods were called
            mock_risk_manager.calculate_optimal_lot_size.assert_called_once()
            mock_risk_manager.can_open_new_trade.assert_called_once()
            mock_risk_manager.get_risk_status.assert_called_once()

    def test_trade_blocked_by_risk_management(self, client):
        """Test trade decision when risk management blocks the trade"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            # Mock risk manager to block trade
            mock_risk_manager = Mock()
            mock_risk_manager.calculate_optimal_lot_size.return_value = (0.0, {'risk_amount': 0.0, 'stop_distance': 0.0015})
            mock_risk_manager.can_open_new_trade.return_value = (False, {'status': 'blocked', 'reason': 'Max positions exceeded'})
            mock_risk_manager.get_risk_status.return_value = {
                'status': 'warning',
                'portfolio': {
                    'total_risk_percent': 0.15,
                    'current_drawdown_percent': 0.05
                }
            }

            mock_service.risk_manager = mock_risk_manager

            # Mock get_prediction to return blocked trade
            mock_service.get_prediction.return_value = {
                'status': 'success',
                'should_trade': 0,
                'confidence_threshold': 0.3,
                'model_health': {'status': 'healthy', 'health_score': 85},
                'prediction': {
                    'probability': 0.85,
                    'confidence': 0.7,
                    'direction': 'buy',
                    'strategy': 'ML_Testing_EA',
                    'symbol': 'EURUSD+',
                    'timeframe': 'M5'
                },
                'trade_parameters': {
                    'entry_price': 1.0835,
                    'stop_loss': 1.0820,
                    'take_profit': 1.0860,
                    'lot_size': 0.0,  # Blocked trade
                    'risk_validation': {
                        'can_trade': False,
                        'validation_details': {'status': 'blocked', 'reason': 'Max positions exceeded'},
                        'risk_status': 'warning',
                        'portfolio_risk': 0.15,
                        'current_drawdown': 0.05,
                        'blocked_reason': 'Max positions exceeded'
                    }
                },
                'metadata': {'features_used': 7}
            }

            test_data = {
                'strategy': 'ML_Testing_EA',
                'symbol': 'EURUSD+',
                'timeframe': 'M5',
                'current_price': 1.0835,
                'atr': 0.0015,
                'account_balance': 10000,
                'direction': 'buy'
            }

            response = client.post('/trade_decision', json=test_data)
            assert response.status_code == 200

            data = json.loads(response.data)
            assert data['should_trade'] == 0
            assert data['trade_parameters']['lot_size'] == 0.0
            assert data['trade_parameters']['risk_validation']['can_trade'] is False

    def test_risk_status_endpoint(self, client):
        """Test the risk status endpoint"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            # Mock the analytics service calls
            with patch('ml_prediction_service.get_current_positions_from_analytics') as mock_positions:
                with patch('ml_prediction_service.get_portfolio_summary_from_analytics') as mock_portfolio:
                    mock_positions.return_value = [
                        {
                            'ticket': '12345',
                            'symbol': 'EURUSD+',
                            'direction': 'buy',
                            'volume': 0.1,
                            'open_price': 1.0800,
                            'current_price': 1.0835,
                            'stop_loss': 1.0780,
                            'take_profit': 1.0850,
                            'profit_loss': 35.0,
                            'open_time': '2025-01-21T15:00:00',
                            'comment': 'ML_Testing_EA'
                        }
                    ]

                    mock_portfolio.return_value = {
                        'equity': 10000.0,
                        'balance': 10000.0,
                        'margin': 0.0,
                        'free_margin': 10000.0,
                        'total_positions': 1,
                        'long_positions': 1,
                        'short_positions': 0,
                        'total_volume': 0.1,
                        'avg_lot_size': 0.1
                    }

                    # Mock risk manager
                    mock_risk_manager = Mock()
                    mock_risk_manager.get_risk_status.return_value = {
                        'status': 'healthy',
                        'portfolio': {
                            'total_risk_percent': 0.02,
                            'current_drawdown_percent': 0.01
                        },
                        'positions': {
                            'total': 1,
                            'long': 1,
                            'short': 0
                        }
                    }

                    mock_service.risk_manager = mock_risk_manager

                    response = client.get('/risk/status')
                    assert response.status_code == 200

                    data = json.loads(response.data)
                    assert data['status'] == 'success'
                    assert 'risk_status' in data
                    assert data['data_source'] == 'analytics_service'

    def test_analytics_service_integration(self, client):
        """Test integration with analytics service for risk data"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            with patch('ml_prediction_service.requests.get') as mock_get:
                # Mock successful analytics service response
                mock_positions_response = Mock()
                mock_positions_response.json.return_value = {
                    'status': 'success',
                    'positions': [
                        {
                            'ticket': '12345',
                            'symbol': 'EURUSD+',
                            'direction': 'buy',
                            'volume': 0.1,
                            'open_price': 1.0800,
                            'current_price': 1.0835,
                            'stop_loss': 1.0780,
                            'take_profit': 1.0850,
                            'profit_loss': 35.0,
                            'open_time': '2025-01-21T15:00:00',
                            'comment': 'ML_Testing_EA'
                        }
                    ],
                    'count': 1
                }
                mock_positions_response.raise_for_status.return_value = None

                mock_portfolio_response = Mock()
                mock_portfolio_response.json.return_value = {
                    'status': 'success',
                    'portfolio': {
                        'equity': 10000.0,
                        'balance': 10000.0,
                        'total_positions': 1,
                        'long_positions': 1,
                        'short_positions': 0
                    }
                }
                mock_portfolio_response.raise_for_status.return_value = None

                # Configure mock to return different responses for different URLs
                def mock_get_side_effect(url, **kwargs):
                    if 'positions' in url:
                        return mock_positions_response
                    elif 'portfolio' in url:
                        return mock_portfolio_response
                    else:
                        raise Exception(f"Unexpected URL: {url}")

                mock_get.side_effect = mock_get_side_effect

                # Mock risk manager
                mock_risk_manager = Mock()
                mock_risk_manager.get_risk_status.return_value = {
                    'status': 'healthy',
                    'portfolio': {'total_risk_percent': 0.02}
                }
                mock_service.risk_manager = mock_risk_manager

                response = client.get('/risk/status')
                assert response.status_code == 200

                # Verify analytics service was called
                assert mock_get.call_count == 2

    def test_analytics_service_fallback(self, client):
        """Test fallback behavior when analytics service is unavailable"""
        with patch('ml_prediction_service.ml_service') as mock_service:
            with patch('ml_prediction_service.requests.get') as mock_get:
                # Mock analytics service failure
                mock_get.side_effect = Exception("Connection failed")

                # Mock risk manager
                mock_risk_manager = Mock()
                mock_risk_manager.get_risk_status.return_value = {
                    'status': 'healthy',
                    'portfolio': {'total_risk_percent': 0.0}
                }
                mock_service.risk_manager = mock_risk_manager

                response = client.get('/risk/status')
                assert response.status_code == 200

                data = json.loads(response.data)
                assert data['status'] == 'success'
                # Should use default portfolio data when analytics service fails
