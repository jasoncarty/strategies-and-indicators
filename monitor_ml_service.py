#!/usr/bin/env python3
"""
ML Service Monitor
==================
Monitor the ML prediction service logs and help with debugging
"""

import time
import requests
import json
from datetime import datetime
import os

def check_service_status():
    """Check if the ML service is running and healthy"""
    try:
        response = requests.get("http://127.0.0.1:5003/status", timeout=5)
        if response.status_code == 200:
            status = response.json()
            print(f"✅ Service Status: {status['status']}")
            print(f"   Models loaded: {status['models_loaded']}")
            print(f"   Predictions: {status['prediction_count']}")
            print(f"   Errors: {status['error_count']}")
            print(f"   Success rate: {status['success_rate']:.1f}%")
            print(f"   Uptime: {status['uptime_seconds']/3600:.1f} hours")
            return True
        else:
            print(f"❌ Service returned status code: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to ML service - is it running?")
        return False
    except Exception as e:
        print(f"❌ Error checking service: {e}")
        return False

def check_log_file():
    """Check the ML service log file for recent activity"""
    log_file = "ML_Webserver/logs/ml_prediction_service.log"

    if not os.path.exists(log_file):
        print("❌ Log file not found:", log_file)
        return

    try:
        with open(log_file, 'r') as f:
            lines = f.readlines()

        if not lines:
            print("📄 Log file is empty")
            return

        print(f"📄 Recent log entries (last 10 lines):")
        print("-" * 50)

        # Show last 10 lines
        for line in lines[-10:]:
            line = line.strip()
            if line:
                # Color code different log levels
                if "ERROR" in line:
                    print(f"🔴 {line}")
                elif "WARNING" in line:
                    print(f"🟡 {line}")
                elif "INFO" in line:
                    print(f"🔵 {line}")
                else:
                    print(f"⚪ {line}")

    except Exception as e:
        print(f"❌ Error reading log file: {e}")

def test_prediction():
    """Test a prediction request"""
    print("\n🧪 Testing prediction request...")

    # Sample features
    sample_features = {
        "rsi": 50.0,
        "stoch_main": 50.0,
        "stoch_signal": 50.0,
        "macd_main": 0.0,
        "macd_signal": 0.0,
        "bb_upper": 1.2000,
        "bb_lower": 1.1800,
        "adx": 25.0,
        "williams_r": 50.0,
        "cci": 0.0,
        "momentum": 100.0,
        "volume_ratio": 1.0,
        "price_change": 0.001,
        "volatility": 0.001,
        "force_index": 0.0,
        "spread": 1.0,
        "session_hour": 12,
        "is_news_time": 0,
        "rsi_regime": 0,
        "stoch_regime": 0,
        "volatility_regime": 0,
        "hour": 12,
        "day_of_week": 1,
        "month": 7,
        "session": 1,
        "is_london_session": 1,
        "is_ny_session": 0,
        "is_asian_session": 0,
        "is_session_overlap": 0
    }

    payload = {
        "strategy": "BreakoutStrategy",
        "symbol": "EURUSD",
        "timeframe": "M15",
        "direction": "buy",
        "features": sample_features
    }

    try:
        start_time = time.time()
        response = requests.post(
            "http://127.0.0.1:5003/predict",
            json=payload,
            headers={'Content-Type': 'application/json'},
            timeout=10
        )
        end_time = time.time()

        print(f"📤 Request sent in {(end_time - start_time)*1000:.1f}ms")
        print(f"📥 Response status: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            print("✅ Prediction successful!")
            print(f"   Confidence: {result.get('confidence', 'N/A'):.3f}")
            print(f"   Probability: {result.get('probability', 'N/A'):.3f}")
            print(f"   Direction: {result.get('direction', 'N/A')}")
            print(f"   Model: {result.get('model_key', 'N/A')}")
        else:
            print(f"❌ Prediction failed: {response.text}")

    except Exception as e:
        print(f"❌ Test failed: {e}")

def monitor_continuously():
    """Monitor the service continuously"""
    print("🔍 Starting continuous monitoring...")
    print("Press Ctrl+C to stop")

    try:
        while True:
            print(f"\n{'='*60}")
            print(f"🕐 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"{'='*60}")

            # Check service status
            if check_service_status():
                # Test prediction
                test_prediction()

            # Check logs
            check_log_file()

            # Wait 30 seconds before next check
            print(f"\n⏳ Waiting 30 seconds before next check...")
            time.sleep(30)

    except KeyboardInterrupt:
        print("\n🛑 Monitoring stopped")

def main():
    print("🤖 ML Service Monitor")
    print("=" * 50)

    # Check if service is running
    if not check_service_status():
        print("\n💡 To start the ML service, run:")
        print("   cd ML_Webserver")
        print("   source ../ml_env/bin/activate")
        print("   python3 ml_prediction_service.py")
        return

    # Show menu
    while True:
        print("\n📋 Choose an option:")
        print("1. Check service status")
        print("2. Test prediction")
        print("3. View recent logs")
        print("4. Start continuous monitoring")
        print("5. Exit")

        choice = input("\nEnter choice (1-5): ").strip()

        if choice == "1":
            check_service_status()
        elif choice == "2":
            test_prediction()
        elif choice == "3":
            check_log_file()
        elif choice == "4":
            monitor_continuously()
        elif choice == "5":
            print("👋 Goodbye!")
            break
        else:
            print("❌ Invalid choice")

if __name__ == "__main__":
    main()
