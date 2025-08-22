#!/usr/bin/env python3
"""
Test script for the enhanced ML prediction service
Demonstrates the new trade decision endpoint
"""

import requests
import json

def test_enhanced_prediction():
    """Test the new trade decision endpoint"""

    # Test data - similar to what an EA would send
    test_data = {
        "strategy": "ML_Testing_EA",
        "symbol": "EURUSD+",
        "timeframe": "M5",
        "direction": "BUY",
        "rsi": 65.5,
        "stoch_main": 75.2,
        "stoch_signal": 70.1,
        "macd_main": 0.0012,
        "macd_signal": 0.0008,
        "bb_upper": 1.0850,
        "bb_lower": 1.0820,
        "williams_r": 25.5,
        "cci": 45.2,
        "momentum": 100.5,
        "force_index": 0.0001,
        "volume_ratio": 1.2,
        "price_change": 0.0005,
        "volatility": 0.0008,
        "spread": 1.0,
        "session_hour": 14,
        "is_news_time": False,
        "day_of_week": 2,
        "month": 8,
        "current_price": 1.0835,
        "atr": 0.0015,
        "account_balance": 10000,
        "risk_per_pip": 1.0
    }

    print("🧪 Testing Enhanced ML Prediction Service")
    print("=" * 50)

    # Test the new trade decision endpoint
    try:
        print("📡 Testing /trade_decision endpoint...")
        response = requests.post(
            "http://localhost:5000/trade_decision",
            json=test_data,
            timeout=10
        )

        if response.status_code == 200:
            result = response.json()
            print("✅ Trade decision successful!")
            print(f"   Should Trade: {result.get('should_trade', 'N/A')}")
            print(f"   Confidence Threshold: {result.get('confidence_threshold', 'N/A')}")
            print(f"   Model Health: {result.get('model_health', {}).get('status', 'N/A')}")

            if result.get('should_trade'):
                trade_params = result.get('trade_parameters', {})
                print("   📊 Trade Parameters:")
                print(f"      Entry Price: {trade_params.get('entry_price', 'N/A')}")
                print(f"      Stop Loss: {trade_params.get('stop_loss', 'N/A')}")
                print(f"      Take Profit: {trade_params.get('take_profit', 'N/A')}")
                print(f"      Lot Size: {trade_params.get('lot_size', 'N/A')}")

            prediction = result.get('prediction', {})
            print("   🔮 Prediction Details:")
            print(f"      Direction: {prediction.get('direction', 'N/A')}")
            print(f"      Confidence: {prediction.get('confidence', 'N/A'):.3f}")
            print(f"      Probability: {prediction.get('probability', 'N/A'):.3f}")
            print(f"      Model: {prediction.get('model_key', 'N/A')}")

        else:
            print(f"❌ Trade decision failed: {response.status_code}")
            print(f"   Response: {response.text}")

    except requests.exceptions.ConnectionError:
        print("❌ Could not connect to ML prediction service")
        print("   Make sure the service is running on http://localhost:5000")
    except Exception as e:
        print(f"❌ Error testing trade decision: {e}")

    print("\n" + "=" * 50)

    # Test the legacy predict endpoint for comparison
    try:
        print("📡 Testing legacy /predict endpoint...")
        response = requests.post(
            "http://localhost:5000/predict",
            json=test_data,
            timeout=10
        )

        if response.status_code == 200:
            result = response.json()
            print("✅ Legacy prediction successful!")
            print(f"   Direction: {result.get('prediction', {}).get('direction', 'N/A')}")
            print(f"   Confidence: {result.get('prediction', {}).get('confidence', 'N/A'):.3f}")
            print(f"   Probability: {result.get('prediction', {}).get('probability', 'N/A'):.3f}")
        else:
            print(f"❌ Legacy prediction failed: {response.status_code}")

    except Exception as e:
        print(f"❌ Error testing legacy prediction: {e}")

if __name__ == "__main__":
    test_enhanced_prediction()
