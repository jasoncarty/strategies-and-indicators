#!/usr/bin/env python3
"""
Check if the EURUSD+ test differences are due to optimization settings
"""

import json
import os
from datetime import datetime

def check_optimization_causes():
    """Check potential causes for the test variations"""
    
    print("🔍 INVESTIGATING EURUSD+ TEST VARIATIONS")
    print("=" * 80)
    
    # Load the last 7 test results
    file_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Results.json"
    
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        test_results = data.get('test_results', [])
    except Exception as e:
        print(f"Error loading test results: {e}")
        return
    
    # Get last 7 EURUSD+ tests
    eurusd_tests = [test for test in test_results if test.get('symbol', '').startswith('EURUSD')]
    last_7_tests = eurusd_tests[-7:] if len(eurusd_tests) >= 7 else eurusd_tests
    
    print(f"📊 Analyzing {len(last_7_tests)} recent EURUSD+ tests")
    print()
    
    # Check for optimization patterns
    print("🔍 OPTIMIZATION ANALYSIS:")
    print("-" * 40)
    
    # 1. Check if all tests have same timestamp (indicates optimization run)
    timestamps = [test.get('test_start_time', 0) for test in last_7_tests]
    unique_timestamps = set(timestamps)
    
    if len(unique_timestamps) == 1:
        print("✅ All tests have identical timestamps - This indicates an OPTIMIZATION RUN")
        print("   MetaTrader ran multiple tests simultaneously with different parameters")
    else:
        print("❌ Tests have different timestamps - These are separate manual runs")
    
    # 2. Check test run ID patterns
    print("\n🔍 TEST RUN ID PATTERNS:")
    print("-" * 40)
    
    for i, test in enumerate(last_7_tests, 1):
        test_id = test.get('test_run_id', 'unknown')
        # Extract the random component from the ID
        parts = test_id.split('_')
        if len(parts) >= 4:
            random_component = parts[3]
            print(f"Test {i}: Random component = {random_component}")
        else:
            print(f"Test {i}: {test_id}")
    
    # 3. Check for parameter variations
    print("\n🔍 PARAMETER VARIATION ANALYSIS:")
    print("-" * 40)
    
    # Check if any tests have different input parameters
    print("The variations could be due to:")
    print("1. Strategy Tester Optimization Mode:")
    print("   - Different random seeds for each test")
    print("   - Slightly different parameter values")
    print("   - Market data processing variations")
    
    print("\n2. EA Parameter Changes:")
    print("   - Different ML confidence thresholds")
    print("   - Different risk percentages")
    print("   - Different position sizing parameters")
    
    print("\n3. Market Data Variations:")
    print("   - Different spread settings")
    print("   - Different slippage settings")
    print("   - Different commission settings")
    
    # 4. Check the actual profit variations
    profits = [test.get('total_profit', 0) for test in last_7_tests]
    trade_counts = [test.get('total_trades', 0) for test in last_7_tests]
    win_rates = [test.get('win_rate', 0) for test in last_7_tests]
    
    print(f"\n📊 VARIATION ANALYSIS:")
    print("-" * 40)
    print(f"Profit Range: ${min(profits):.2f} to ${max(profits):.2f}")
    print(f"Profit Variation: ${max(profits) - min(profits):.2f} ({(max(profits) - min(profits))/min(profits)*100:.1f}%)")
    print(f"Trade Count Range: {min(trade_counts)} to {max(trade_counts)}")
    print(f"Win Rate Range: {min(win_rates):.1f}% to {max(win_rates):.1f}%")
    
    # 5. Determine if variations are significant
    print(f"\n🎯 SIGNIFICANCE ANALYSIS:")
    print("-" * 40)
    
    profit_variation_pct = (max(profits) - min(profits)) / min(profits) * 100
    trade_variation_pct = (max(trade_counts) - min(trade_counts)) / min(trade_counts) * 100
    winrate_variation_pct = max(win_rates) - min(win_rates)
    
    print(f"Profit variation: {profit_variation_pct:.1f}%")
    print(f"Trade count variation: {trade_variation_pct:.1f}%")
    print(f"Win rate variation: {winrate_variation_pct:.1f}%")
    
    if profit_variation_pct < 20 and trade_variation_pct < 5 and winrate_variation_pct < 5:
        print("✅ Variations are MINIMAL - Strategy is CONSISTENT")
        print("   This is normal for optimization runs with small parameter changes")
    else:
        print("⚠️  Variations are SIGNIFICANT - Check for parameter changes")
    
    # 6. Recommendations
    print(f"\n💡 RECOMMENDATIONS:")
    print("-" * 40)
    
    if len(unique_timestamps) == 1:
        print("1. These are optimization test results - variations are normal")
        print("2. The strategy is actually quite consistent (small variations)")
        print("3. Use the BEST performing test as your baseline")
        print("4. For manual testing, ensure you use the SAME settings each time")
    else:
        print("1. These are separate manual test runs")
        print("2. Check your Strategy Tester settings for consistency")
        print("3. Verify no EA parameters were changed between tests")
        print("4. Ensure the same date range and market data was used")
    
    print("\n5. To get consistent results:")
    print("   - Use the same Strategy Tester settings")
    print("   - Use the same date range")
    print("   - Don't change EA parameters between tests")
    print("   - Use 'Every tick' mode for most accurate results")

if __name__ == "__main__":
    check_optimization_causes() 