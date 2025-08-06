#!/usr/bin/env python3
"""
Test script for MT5 Strategy Tester Web Server API
"""

import requests
import json
from datetime import datetime

# Server configuration
BASE_URL = "http://localhost:5000"

def test_server_connection():
    """Test if the server is running"""
    try:
        response = requests.get(f"{BASE_URL}/api")
        if response.status_code == 200:
            print("✓ Server is running")
            return True
        else:
            print(f"✗ Server returned status code: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("✗ Cannot connect to server. Make sure it's running on http://localhost:5000")
        return False

def test_save_test():
    """Test saving a strategy test"""
    test_data = {
        "strategy_name": "Test Strategy",
        "symbol": "DYNAMIC_SYMBOL",
        "timeframe": "H1",
        "start_date": "2024-01-01T00:00:00",
        "end_date": "2024-12-31T23:59:59",
        "initial_deposit": 10000.0,
        "final_balance": 11500.0,
        "profit": 1500.0,
        "profit_factor": 1.5,
        "max_drawdown": 5.2,
        "total_trades": 100,
        "winning_trades": 65,
        "losing_trades": 35,
        "win_rate": 65.0,
        "sharpe_ratio": 1.2,
        "parameters": json.dumps({"param1": "value1", "param2": "value2"}),
        "trades": [
            {
                "ticket": 12345,
                "symbol": "DYNAMIC_SYMBOL",
                "type": "BUY",
                "volume": 0.1,
                "open_price": 1.0850,
                "close_price": 1.0870,
                "open_time": "2024-01-01T10:00:00",
                "close_time": "2024-01-01T12:00:00",
                "profit": 20.0,
                "swap": 0.0,
                "commission": -1.0,
                "net_profit": 19.0
            },
            {
                "ticket": 12346,
                "symbol": "DYNAMIC_SYMBOL",
                "type": "SELL",
                "volume": 0.1,
                "open_price": 1.0870,
                "close_price": 1.0850,
                "open_time": "2024-01-01T14:00:00",
                "close_time": "2024-01-01T16:00:00",
                "profit": 20.0,
                "swap": 0.0,
                "commission": -1.0,
                "net_profit": 19.0
            }
        ]
    }

    try:
        response = requests.post(f"{BASE_URL}/api/test", json=test_data)
        if response.status_code == 201:
            result = response.json()
            print(f"✓ Test saved successfully with ID: {result.get('test_id')}")
            return result.get('test_id')
        else:
            print(f"✗ Failed to save test. Status: {response.status_code}")
            print(f"Response: {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error saving test: {e}")
        return None

def test_get_tests():
    """Test getting all tests"""
    try:
        response = requests.get(f"{BASE_URL}/api/tests")
        if response.status_code == 200:
            result = response.json()
            print(f"✓ Retrieved {result.get('count', 0)} tests")
            return result.get('tests', [])
        else:
            print(f"✗ Failed to get tests. Status: {response.status_code}")
            return []
    except Exception as e:
        print(f"✗ Error getting tests: {e}")
        return []

def test_get_test(test_id):
    """Test getting a specific test"""
    try:
        response = requests.get(f"{BASE_URL}/api/test/{test_id}")
        if response.status_code == 200:
            result = response.json()
            test = result.get('test', {})
            print(f"✓ Retrieved test: {test.get('strategy_name')}")
            print(f"  - Profit: ${test.get('profit', 0):.2f}")
            print(f"  - Trades: {len(test.get('trades', []))}")
            return True
        else:
            print(f"✗ Failed to get test {test_id}. Status: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Error getting test: {e}")
        return False

def test_get_stats():
    """Test getting statistics"""
    try:
        response = requests.get(f"{BASE_URL}/api/stats")
        if response.status_code == 200:
            result = response.json()
            stats = result.get('stats', {})
            print(f"✓ Retrieved statistics:")
            print(f"  - Total tests: {stats.get('total_tests', 0)}")
            print(f"  - Profitable tests: {stats.get('profitable_tests', 0)}")
            print(f"  - Success rate: {stats.get('success_rate', 0):.1f}%")
            return True
        else:
            print(f"✗ Failed to get stats. Status: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Error getting stats: {e}")
        return False

def test_delete_test(test_id):
    """Test deleting a test"""
    try:
        response = requests.delete(f"{BASE_URL}/api/test/{test_id}")
        if response.status_code == 200:
            print(f"✓ Test {test_id} deleted successfully")
            return True
        else:
            print(f"✗ Failed to delete test {test_id}. Status: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Error deleting test: {e}")
        return False

def main():
    """Run all tests"""
    print("MT5 Strategy Tester Web Server API Test")
    print("=" * 40)

    # Test server connection
    if not test_server_connection():
        return

    print()

    # Test saving a test
    test_id = test_save_test()
    if test_id is None:
        return

    print()

    # Test getting all tests
    tests = test_get_tests()

    print()

    # Test getting specific test
    test_get_test(test_id)

    print()

    # Test getting statistics
    test_get_stats()

    print()

    # Test deleting the test
    test_delete_test(test_id)

    print()
    print("All tests completed!")

if __name__ == "__main__":
    main()
