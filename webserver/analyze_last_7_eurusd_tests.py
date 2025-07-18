#!/usr/bin/env python3
"""
Analyze only the last 7 EURUSD+ test runs to identify the real cause of differences
"""

import json
from datetime import datetime
import statistics

def load_test_results(file_path):
    """Load test results from JSON file"""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        return data.get('test_results', [])
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return []

def analyze_last_7_eurusd_tests():
    """Analyze only the last 7 EURUSD+ test runs"""
    
    # Load test results
    file_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Results.json"
    test_results = load_test_results(file_path)
    
    if not test_results:
        print("❌ No test results found")
        return
    
    # Filter for EURUSD+ tests only
    eurusd_tests = [test for test in test_results if test.get('symbol', '').startswith('EURUSD')]
    
    if not eurusd_tests:
        print("❌ No EURUSD+ tests found")
        return
    
    print(f"📊 Found {len(eurusd_tests)} total EURUSD+ tests")
    
    # Get only the last 7 tests
    last_7_tests = eurusd_tests[-7:] if len(eurusd_tests) >= 7 else eurusd_tests
    
    print(f"\n🎯 ANALYZING LAST {len(last_7_tests)} EURUSD+ TESTS:")
    print("=" * 80)
    
    # Sort by timestamp to see chronological order
    last_7_tests.sort(key=lambda x: x.get('test_start_time', 0))
    
    # Analyze each test
    profits = []
    total_trades_list = []
    win_rates = []
    profit_factors = []
    max_drawdowns = []
    test_ids = []
    
    for i, test in enumerate(last_7_tests, 1):
        test_id = test.get('test_run_id', 'unknown')
        symbol = test.get('symbol', 'unknown')
        total_trades = test.get('total_trades', 0)
        winning_trades = test.get('winning_trades', 0)
        total_profit = test.get('total_profit', 0.0)
        win_rate = test.get('win_rate', 0.0)
        profit_factor = test.get('profit_factor', 0.0)
        max_drawdown = test.get('max_drawdown', 0.0)
        test_start_time = test.get('test_start_time', 0)
        
        # Convert timestamp to readable date
        try:
            test_date = datetime.fromtimestamp(test_start_time).strftime('%Y-%m-%d %H:%M:%S')
        except:
            test_date = "unknown"
        
        print(f"\n📈 Test {i}: {test_id}")
        print(f"   Date: {test_date}")
        print(f"   Symbol: {symbol}")
        print(f"   Total Trades: {total_trades}")
        print(f"   Winning Trades: {winning_trades}")
        print(f"   Win Rate: {win_rate:.2f}%")
        print(f"   Total Profit: ${total_profit:.2f}")
        print(f"   Profit Factor: {profit_factor:.2f}")
        print(f"   Max Drawdown: {max_drawdown:.2f}%")
        
        profits.append(total_profit)
        total_trades_list.append(total_trades)
        win_rates.append(win_rate)
        profit_factors.append(profit_factor)
        max_drawdowns.append(max_drawdown)
        test_ids.append(test_id)
    
    # Calculate statistics
    if len(profits) > 1:
        print(f"\n📊 STATISTICAL ANALYSIS:")
        print("=" * 80)
        print(f"Profit Range: ${min(profits):.2f} to ${max(profits):.2f}")
        print(f"Profit Standard Deviation: ${statistics.stdev(profits):.2f}")
        print(f"Mean Profit: ${statistics.mean(profits):.2f}")
        print(f"Median Profit: ${statistics.median(profits):.2f}")
        
        print(f"\nTrade Count Range: {min(total_trades_list)} to {max(total_trades_list)}")
        print(f"Trade Count Standard Deviation: {statistics.stdev(total_trades_list):.1f}")
        print(f"Mean Trade Count: {statistics.mean(total_trades_list):.1f}")
        
        print(f"\nWin Rate Range: {min(win_rates):.1f}% to {max(win_rates):.1f}%")
        print(f"Win Rate Standard Deviation: {statistics.stdev(win_rates):.1f}%")
        print(f"Mean Win Rate: {statistics.mean(win_rates):.1f}%")
        
        print(f"\nProfit Factor Range: {min(profit_factors):.2f} to {max(profit_factors):.2f}")
        print(f"Profit Factor Standard Deviation: {statistics.stdev(profit_factors):.2f}")
        print(f"Mean Profit Factor: {statistics.mean(profit_factors):.2f}")
        
        print(f"\nMax Drawdown Range: {min(max_drawdowns):.1f}% to {max(max_drawdowns):.1f}%")
        print(f"Max Drawdown Standard Deviation: {statistics.stdev(max_drawdowns):.1f}%")
        print(f"Mean Max Drawdown: {statistics.mean(max_drawdowns):.1f}%")
    
    # Look for patterns in test IDs
    print(f"\n🔍 TEST ID ANALYSIS:")
    print("=" * 80)
    for i, test_id in enumerate(test_ids):
        print(f"Test {i+1}: {test_id}")
    
    # Check if test IDs follow a pattern
    print(f"\n🔍 POTENTIAL CAUSES OF DIFFERENCES:")
    print("=" * 80)
    
    # 1. Check if different parameter files were used
    print("1. PARAMETER FILE DIFFERENCES:")
    print("   - Check if different ML parameter files were loaded")
    print("   - Look for changes in ml_model_params_EURUSD.txt")
    print("   - Check if separate buy/sell models were used vs combined")
    
    # 2. Check if different EA versions were used
    print("\n2. EA VERSION DIFFERENCES:")
    print("   - Check if EA code was modified between tests")
    print("   - Look for changes in input parameters")
    print("   - Check if different TradeUtils.mqh was used")
    
    # 3. Check if different market data was used
    print("\n3. MARKET DATA DIFFERENCES:")
    print("   - Check if different date ranges were tested")
    print("   - Look for different market conditions")
    print("   - Check if different timeframes were used")
    
    # 4. Check if different account settings were used
    print("\n4. ACCOUNT SETTINGS DIFFERENCES:")
    print("   - Check if different initial balance was used")
    print("   - Look for different spread settings")
    print("   - Check if different commission settings")
    
    # 5. Check if different Strategy Tester settings were used
    print("\n5. STRATEGY TESTER SETTINGS:")
    print("   - Check if 'Every tick' vs '1 minute OHLC' was used")
    print("   - Look for different optimization settings")
    print("   - Check if 'Visual mode' was enabled/disabled")
    
    # 6. Check for external factors
    print("\n6. EXTERNAL FACTORS:")
    print("   - Check if ML training was run between tests")
    print("   - Look for changes in market volatility")
    print("   - Check if different news events affected the period")
    
    print(f"\n💡 RECOMMENDATIONS:")
    print("=" * 80)
    print("1. Compare the exact Strategy Tester settings between tests")
    print("2. Check if any EA parameters were changed")
    print("3. Verify the same date range was used")
    print("4. Check if ML parameter files were updated")
    print("5. Look for any code changes in the EA")
    print("6. Verify the same account settings were used")

if __name__ == "__main__":
    analyze_last_7_eurusd_tests() 