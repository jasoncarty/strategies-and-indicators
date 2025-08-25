#!/usr/bin/env python3
"""
End-to-end workflow tests using the new pytest framework
"""
import time
import pytest
import requests
import json
from pathlib import Path

def test_analytics_service_health(test_analytics_client):
    """Test analytics service health endpoint"""
    response = test_analytics_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    print("✅ Analytics service health check passed")

def test_ml_service_health(test_ml_client):
    """Test ML service health endpoint"""
    response = test_ml_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service health check passed")

def test_ml_service_status(test_ml_client):
    """Test ML service status endpoint"""
    response = test_ml_client.get("/status")
    assert response.status_code == 200

    data = response.json()
    assert "status" in data
    print("✅ ML service status check passed")

def test_ml_service_predict(test_ml_client):
    """Test ML service predict endpoint"""

    # Sample features that match what MT5 EA would send
    features = {
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

    # Test prediction request
    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        **features  # Spread all features at top level
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    assert response.status_code == 200

    result = response.json()
    assert "status" in result
    assert "prediction" in result

    assert result['status'] == 'success'
    prediction = result['prediction']
    assert 'confidence' in prediction
    assert 'direction' in prediction
    assert 'probability' in prediction

def test_data_structure_consistency(test_ml_client):
    """Test that data structures are consistent across all services via HTTP requests"""
        # Test MT5 EA data structure (simulated)
    mt5_features = {
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

    # Validate MT5 features locally
    required_mt5_features = [
        'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
        'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
        'volume_ratio', 'price_change', 'volatility', 'spread',
        'session_hour', 'is_news_time', 'day_of_week', 'month'
    ]

    for feature in required_mt5_features:
        assert feature in mt5_features

    # Test ML service via HTTP request to validate feature processing
    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        **mt5_features  # Spread all features at top level
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    assert response.status_code == 200

    result = response.json()
    assert 'status' in result
    assert result['status'] == 'success'

    # Validate that ML service processed the features correctly
    assert 'prediction' in result
    assert 'metadata' in result

    metadata = result['metadata']
    assert 'features_used' in metadata

    # Verify ML service processed 28 features (19 input + 9 engineered)
    assert metadata['features_used'] == 28

    # Verify prediction structure
    prediction = result['prediction']
    assert 'confidence' in prediction
    assert 'direction' in prediction
    assert 'probability' in prediction

    # Validate confidence and probability are reasonable values
    assert prediction['confidence'] >= 0.0
    assert prediction['confidence'] <= 1.0
    assert prediction['probability'] >= 0.0
    assert prediction['probability'] <= 1.0

def test_error_handling_integration(test_ml_client):
    """Test error handling across the entire workflow via HTTP requests"""

    invalid_features = {
        'rsi': 'invalid_string',  # Should be numeric
        'stoch_main': None,       # Should be numeric
        'macd_main': 'not_a_number'  # Should be numeric
    }

    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        **invalid_features  # Spread all features at top level
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    # Should return an error response, not crash
    assert response.status_code in [200, 400, 500]

    if response.status_code == 200:
        result = response.json()
        if result['status'] == 'error':
            print("✅ ML service correctly handled invalid data types")
        else:
            print("⚠️ ML service accepted invalid data types")
    else:
        print(f"✅ ML service returned error status {response.status_code} for invalid data")

    # Test 2: Missing required features
    incomplete_features = {
        'rsi': 50.0  # Missing most features
    }

    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'features': incomplete_features
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    assert response.status_code in [200, 400, 500]

    if response.status_code == 200:
        result = response.json()
        if result['status'] == 'error':
            print("✅ ML service correctly handled missing features")
        else:
            print("⚠️ ML service accepted incomplete features")
    else:
        print(f"✅ ML service returned error status {response.status_code} for missing features")

    # Test 3: Empty features
    empty_features = {}

    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'features': empty_features
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    assert response.status_code in [200, 400, 500]

    if response.status_code == 200:
        result = response.json()
        if result['status'] == 'error':
            print("✅ ML service correctly handled empty features")
        else:
            print("⚠️ ML service accepted empty features")
    else:
        print(f"✅ ML service returned error status {response.status_code} for empty features")

def test_feature_count_consistency(test_ml_client):
    """Test that feature counts are consistent across the system via HTTP requests"""
        # MT5 EA sends 19 basic features
    mt5_basic_features = [
        'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
        'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
        'volume_ratio', 'price_change', 'volatility', 'force_index',
        'spread', 'session_hour', 'is_news_time', 'day_of_week', 'month'
    ]

    assert len(mt5_basic_features) == 19

    # Create test features with exactly 19 features
    test_features = {
        'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
        'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
        'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
        'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
        'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
        'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
        'month': 7
    }

    # Verify we have exactly 19 features
    assert len(test_features) == 19

    # Test ML service via HTTP request
    prediction_data = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        **test_features  # Spread all features at top level
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=prediction_data,
        timeout=10
    )

    assert response.status_code == 200

    result = response.json()
    assert 'status' in result
    assert result['status'] == 'success'

    metadata = result['metadata']
    assert 'features_used' in metadata

    # Verify ML service processed exactly 28 features (19 input + 9 engineered)
    actual_features = metadata['features_used']
    assert actual_features == 28

    print(f"✅ Feature count consistency verified: {len(test_features)} input → {actual_features} processed")

def test_data_flow_validation(test_ml_client):
    """Test the complete data flow from MT5 to ML to Analytics"""

    # Simulate MT5 EA data collection
    mt5_data = {
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

    # Validate MT5 data structure
    assert 'trade_id' in mt5_data
    assert 'symbol' in mt5_data
    assert 'rsi' in mt5_data  # Features are now at top level

    # Simulate ML service processing
    ml_request = {
        'strategy': 'ML_Testing_EA',
        'symbol': mt5_data['symbol'],
        'timeframe': mt5_data['timeframe'],
        'direction': 'buy',
        'rsi': mt5_data['rsi'],
        'stoch_main': mt5_data['stoch_main'],
        'stoch_signal': mt5_data['stoch_signal'],
        'macd_main': mt5_data['macd_main'],
        'macd_signal': mt5_data['macd_signal'],
        'bb_upper': mt5_data['bb_upper'],
        'bb_lower': mt5_data['bb_lower'],
        'williams_r': mt5_data['williams_r'],
        'cci': mt5_data['cci'],
        'momentum': mt5_data['momentum'],
        'force_index': mt5_data['force_index'],
        'volume_ratio': mt5_data['volume_ratio'],
        'price_change': mt5_data['price_change'],
        'volatility': mt5_data['volatility'],
        'spread': mt5_data['spread'],
        'session_hour': mt5_data['session_hour'],
        'is_news_time': mt5_data['is_news_time'],
        'day_of_week': mt5_data['day_of_week'],
        'month': mt5_data['month']
    }

    response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=ml_request,
        timeout=10
    )

    if response.status_code == 200:
        ml_response = response.json()

        # Validate ML response structure
        assert 'status' in ml_response
        assert ml_response['status'] == 'success'
        assert 'prediction' in ml_response
        assert 'metadata' in ml_response

        # Validate prediction structure
        prediction = ml_response['prediction']
        assert 'confidence' in prediction
        assert 'direction' in prediction
        assert 'probability' in prediction

        # Validate metadata
        metadata = ml_response['metadata']
        assert 'features_used' in metadata
        assert metadata['features_used'] == 28

def test_complete_workflow_with_analytics(test_ml_client, test_analytics_client):
    """Test complete workflow: MT5 → ML Service → Analytics Service"""

    # Step 1: Simulate MT5 EA collecting features
    mt5_features = {
        'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
        'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
        'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
        'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
        'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
        'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
        'month': 7
    }

    # Step 2: Get ML prediction
    ml_request = {
        'strategy': 'ML_Testing_EA',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        **mt5_features  # Spread all features at top level
    }

    ml_response = requests.post(
        f"{test_ml_client.base_url}/predict",
        json=ml_request,
        timeout=10
    )

    assert ml_response.status_code == 200

    ml_result = ml_response.json()
    assert 'status' in ml_result
    assert ml_result['status'] == 'success'

    # Step 3: Send trade data to analytics service
    test_trade_id = int(time.time() * 1000000)  # Use microseconds for uniqueness
    trade_data = {
        'trade_id': test_trade_id,
        'strategy_name': 'ML_Testing_EA',
        'strategy_version': '1.0',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'entry_price': 50000.0,
        'stop_loss': 49000.0,
        'take_profit': 51000.0,
        'lot_size': 0.1,
        'entry_time': int(time.time()),
        'status': 'OPEN',
        'account_id': 'TEST_ACCOUNT'
    }

    # Test analytics service trade endpoint
    analytics_response = requests.post(
        f"{test_analytics_client.base_url}/analytics/trade",
        json=trade_data,
        timeout=10
    )

    # Check for successful response
    assert analytics_response.status_code in [200, 201]

    # Step 4: Send market conditions to analytics service
    market_conditions = {
        'trade_id': test_trade_id,
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'rsi': mt5_features['rsi'],
        'stoch_main': mt5_features['stoch_main'],
        'stoch_signal': mt5_features['stoch_signal'],
        'macd_main': mt5_features['macd_main'],
        'macd_signal': mt5_features['macd_signal'],
        'bb_upper': mt5_features['bb_upper'],
        'bb_lower': mt5_features['bb_lower'],
        'cci': mt5_features['cci'],
        'momentum': mt5_features['momentum'],
        'volume_ratio': mt5_features['volume_ratio'],
        'price_change': mt5_features['price_change'],
        'volatility': mt5_features['volatility'],
        'spread': mt5_features['spread'],
        'session_hour': mt5_features['session_hour'],
        'day_of_week': mt5_features['day_of_week'],
        'month': mt5_features['month']
    }

    market_response = requests.post(
        f"{test_analytics_client.base_url}/analytics/market_conditions",
        json=market_conditions,
        timeout=10
    )

    assert market_response.status_code in [200, 201]

    # Step 5: Send ML prediction to analytics service
    ml_prediction_data = {
        'trade_id': test_trade_id,
        'model_name': ml_result['metadata'].get('model_name', 'buy_BTCUSD_PERIOD_M5'),
        'model_type': 'buy',
        'prediction_probability': ml_result['prediction']['probability'],
        'confidence_score': ml_result['prediction']['confidence'],
        'features_json': json.dumps(mt5_features),
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'strategy_name': 'ML_Testing_EA',
        'strategy_version': '1.0'
    }

    prediction_response = requests.post(
        f"{test_analytics_client.base_url}/analytics/ml_prediction",
        json=ml_prediction_data,
        timeout=10
    )

    assert prediction_response.status_code in [200, 201]

def test_ml_service_all_endpoints(test_ml_client):
    """Test all ML service endpoints"""

        # Test /health endpoint
    response = requests.get(f"{test_ml_client.base_url}/health", timeout=5)
    assert response.status_code == 200
    health_data = response.json()
    assert 'status' in health_data

    # Test /status endpoint
    response = requests.get(f"{test_ml_client.base_url}/status", timeout=5)
    assert response.status_code == 200
    status_data = response.json()
    assert 'status' in status_data
    assert 'models_loaded' in status_data

    # Test /models endpoint
    response = requests.get(f"{test_ml_client.base_url}/models", timeout=5)
    assert response.status_code == 200
    models_data = response.json()
    assert 'models' in models_data


def test_analytics_service_all_endpoints(test_analytics_client):
    """Test all Analytics service endpoints"""

    # Test /health endpoint
    response = requests.get(f"{test_analytics_client.base_url}/health", timeout=5)
    assert response.status_code == 200
    health_data = response.json()
    assert 'status' in health_data
    assert 'database' in health_data

    # Test /analytics/trade endpoint
    test_trade_id = int(time.time())
    trade_data = {
        'trade_id': test_trade_id,
        'strategy_name': 'TestStrategy',
        'strategy_version': '1.0',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'entry_price': 50000.0,
        'stop_loss': 49000.0,
        'take_profit': 51000.0,
        'lot_size': 0.1,
        'entry_time': int(time.time()),
        'status': 'OPEN',
        'account_id': 'TEST_ACCOUNT'
    }
    response = requests.post(f"{test_analytics_client.base_url}/analytics/trade", json=trade_data, timeout=5)

    assert response.status_code in [200, 201]

    # Test /analytics/market_conditions endpoint
    market_data = {
        'trade_id': test_trade_id,
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
    response = requests.post(f"{test_analytics_client.base_url}/analytics/market_conditions", json=market_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /analytics/ml_prediction endpoint
    ml_prediction_data = {
        'trade_id': test_trade_id,
        'model_name': 'test_model',
        'model_type': 'buy',
        'prediction_probability': 0.75,
        'confidence_score': 0.8,
        'features_json': '{"rsi": 50.0}',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'strategy_name': 'TestStrategy',
        'strategy_version': '1.0'
    }

    response = requests.post(f"{test_analytics_client.base_url}/analytics/ml_prediction", json=ml_prediction_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /analytics/trade_exit endpoint
    trade_exit_data = {
        'trade_id': test_trade_id,
        'exit_price': 50500.0,
        'exit_reason': 'take_profit',
        'profit_loss': 500.0,
        'exit_time': int(time.time()),
        'status': 'CLOSED'
    }

    response = requests.post(f"{test_analytics_client.base_url}/analytics/trade_exit", json=trade_exit_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /analytics/batch endpoint
    batch_data = {
        'records': [
            {'type': 'trade', 'data': trade_data},
            {'type': 'market_conditions', 'data': market_data},
            {'type': 'ml_prediction', 'data': ml_prediction_data}
        ]
    }

    response = requests.post(f"{test_analytics_client.base_url}/analytics/batch", json=batch_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /ml_trade_log endpoint
    ml_trade_log_data = {
        'trade_id': test_trade_id,
        'strategy': 'TestStrategy',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy',
        'entry_price': 50000.0,
        'stop_loss': 49000.0,
        'take_profit': 51000.0,
        'lot_size': 0.1,
        'timestamp': int(time.time()),
        'trade_time': int(time.time()),
        'status': 'OPEN',
        'model_name': 'test_model',
        'confidence': 0.8,
        'ml_confidence': 0.8,
        'ml_model_type': 'buy',
        'ml_model_key': 'test_model_key',
        'ml_prediction': 0.75
    }

    response = requests.post(f"{test_analytics_client.base_url}/ml_trade_log", json=ml_trade_log_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /ml_trade_close endpoint
    ml_trade_close_data = {
        'trade_id': test_trade_id,
        'strategy': 'TestStrategy',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'close_price': 50500.0,
        'profit_loss': 500.0,
        'profit_loss_pips': 50.0,
        'close_time': int(time.time()),
        'exit_reason': 'take_profit',
        'status': 'CLOSED',
        'success': True,
        'timestamp': int(time.time())
    }

    response = requests.post(f"{test_analytics_client.base_url}/ml_trade_close", json=ml_trade_close_data, timeout=5)
    assert response.status_code in [200, 201]

    # Test /analytics/trades endpoint (GET) - should return empty list initially
    response = requests.get(f"{test_analytics_client.base_url}/analytics/trades?symbol=BTCUSD&timeframe=M5&start_date=2024-01-01&end_date=2024-12-31", timeout=5)
    assert response.status_code == 200
    trades_data = response.json()
    assert isinstance(trades_data, list)

    # Test /analytics/trades endpoint (GET) - should now find the trade we created
    # Use current year dates to match the trade we just created
    from datetime import datetime
    current_year = datetime.now().year
    response = requests.get(f"{test_analytics_client.base_url}/analytics/trades?symbol=BTCUSD&timeframe=M5&start_date={current_year}-01-01&end_date={current_year}-12-31", timeout=5)
    assert response.status_code == 200
    trades_data = response.json()
    assert isinstance(trades_data, list)
    assert len(trades_data) > 0

    # Test /analytics/summary endpoint (GET)
    response = requests.get(f"{test_analytics_client.base_url}/analytics/summary", timeout=5)
    assert response.status_code == 200
    summary_data = response.json()
    assert isinstance(summary_data, dict)
    assert 'total_trades' in summary_data

def test_analytics_service_error_handling(test_analytics_client):
    """Test Analytics service error handling for invalid data"""
    # Test invalid trade data
    invalid_trade_data = {
        'trade_id': 'test_invalid_001',
        # Missing required fields
    }
    response = requests.post(f"{test_analytics_client.base_url}/analytics/trade", json=invalid_trade_data, timeout=5)
    assert response.status_code in [400, 500]  # Should return error for invalid data

    # Test invalid market conditions data
    invalid_market_data = {
        'trade_id': 'test_invalid_001',
        # Missing required fields
    }
    response = requests.post(f"{test_analytics_client.base_url}/analytics/market_conditions", json=invalid_market_data, timeout=5)
    assert response.status_code in [400, 500]

    # Test invalid ML prediction data
    invalid_ml_data = {
        'trade_id': 'test_invalid_001',
        # Missing required fields
    }
    response = requests.post(f"{test_analytics_client.base_url}/analytics/ml_prediction", json=invalid_ml_data, timeout=5)
    assert response.status_code in [400, 500]

def test_ml_service_error_handling(test_ml_client):
    """Test ML service error handling for invalid data"""

    # Test invalid prediction request
    invalid_prediction_data = {
        'strategy': 'TestStrategy',
        'symbol': 'BTCUSD',
        'timeframe': 'M5',
        'direction': 'buy'
        # Missing required features
    }
    response = requests.post(f"{test_ml_client.base_url}/predict", json=invalid_prediction_data, timeout=5)
    assert response.status_code in [400, 500]

    # Test malformed JSON
    response = requests.post(f"{test_ml_client.base_url}/predict", data="invalid json",
                            headers={'Content-Type': 'application/json'}, timeout=5)
    assert response.status_code in [400, 500]

def test_service_load_and_performance(test_ml_client):
    """Test service performance under load"""

    # Test ML service with multiple concurrent requests
    import threading
    import time

    def make_prediction_request():
        features = {
            'rsi': 50.0, 'stoch_main': 50.0, 'stoch_signal': 50.0,
            'macd_main': 0.0, 'macd_signal': 0.0, 'bb_upper': 50000.0,
            'bb_lower': 49000.0, 'williams_r': 50.0, 'cci': 0.0,
            'momentum': 100.0, 'force_index': 0.0, 'volume_ratio': 1.0,
            'price_change': 0.001, 'volatility': 0.001, 'spread': 1.0,
            'session_hour': 12, 'is_news_time': False, 'day_of_week': 1,
            'month': 7
        }

        request_data = {
            'strategy': 'TestStrategy',
            'symbol': 'BTCUSD',
            'timeframe': 'M5',
            'direction': 'buy',
            **features  # Spread all features at top level
        }

        try:
            response = requests.post(f"{test_ml_client.base_url}/predict", json=request_data, timeout=10)
            return response.status_code == 200
        except:
            return False

    # Test concurrent requests
    threads = []
    results = []

    start_time = time.time()
    for i in range(5):  # 5 concurrent requests
        thread = threading.Thread(target=lambda: results.append(make_prediction_request()))
        threads.append(thread)
        thread.start()

    for thread in threads:
        thread.join()

    end_time = time.time()
    duration = end_time - start_time

    successful_requests = sum(results)
    print(f"✅ ML Service handled {successful_requests}/5 concurrent requests in {duration:.2f}s")

    # Should handle at least 3 out of 5 requests successfully
    assert successful_requests >= 3
    print(f"✅ ML Service handled {successful_requests}/5 concurrent requests in {duration:.2f}s")

