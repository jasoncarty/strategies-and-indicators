#!/usr/bin/env python3
"""
Analyze differences between multiple EURUSD+ test runs
"""

import json
from datetime import datetime
import statistics

def correlation(x, y):
    """Calculate correlation coefficient between two lists"""
    if len(x) != len(y) or len(x) < 2:
        return 0.0
    
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x[i] * y[i] for i in range(n))
    sum_x2 = sum(x[i] * x[i] for i in range(n))
    sum_y2 = sum(y[i] * y[i] for i in range(n))
    
    numerator = n * sum_xy - sum_x * sum_y
    denominator = ((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y)) ** 0.5
    
    if denominator == 0:
        return 0.0
    
    return numerator / denominator

def load_test_results(file_path):
    """Load test results from JSON file"""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        return data.get('test_results', [])
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return []

def analyze_eurusd_test_runs():
    """Analyze all EURUSD+ test runs to identify differences"""
    
    # Load test results
    file_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Results.json"
    test_results = load_test_results(file_path)
    
    if not test_results:
        print("No test results found")
        return
    
    # Filter for EURUSD+ tests only
    eurusd_tests = [test for test in test_results if test.get('symbol') == 'EURUSD+']
    
    print(f"EURUSD+ TEST RUNS ANALYSIS")
    print("=" * 80)
    print(f"Found {len(eurusd_tests)} EURUSD+ test runs")
    print()
    
    # Sort by test_run_id to see chronological order
    eurusd_tests.sort(key=lambda x: x.get('test_run_id', ''))
    
    # Display all test runs
    print("ALL EURUSD+ TEST RUNS:")
    print("-" * 80)
    
    for i, test in enumerate(eurusd_tests, 1):
        test_run_id = test.get('test_run_id', 'unknown')
        total_trades = test.get('total_trades', 0)
        winning_trades = test.get('winning_trades', 0)
        losing_trades = test.get('losing_trades', 0)
        win_rate = test.get('win_rate', 0)
        total_profit = test.get('total_profit', 0)
        average_profit = test.get('average_profit', 0)
        profit_factor = test.get('profit_factor', 0)
        max_drawdown = test.get('max_drawdown', 0)
        
        print(f"{i:2d}. {test_run_id}")
        print(f"    Trades: {total_trades} (W:{winning_trades}/L:{losing_trades}) | Win Rate: {win_rate:.1f}%")
        print(f"    Profit: ${total_profit:.2f} | Avg: ${average_profit:.2f} | PF: {profit_factor:.2f} | DD: {max_drawdown:.1f}%")
        print()
    
    # Statistical analysis
    print("STATISTICAL ANALYSIS:")
    print("-" * 80)
    
    # Extract key metrics
    profits = [test.get('total_profit', 0) for test in eurusd_tests]
    win_rates = [test.get('win_rate', 0) for test in eurusd_tests]
    profit_factors = [test.get('profit_factor', 0) for test in eurusd_tests]
    max_drawdowns = [test.get('max_drawdown', 0) for test in eurusd_tests]
    total_trades_list = [test.get('total_trades', 0) for test in eurusd_tests]
    
    print(f"Profit Analysis:")
    print(f"  Mean: ${statistics.mean(profits):.2f}")
    print(f"  Median: ${statistics.median(profits):.2f}")
    print(f"  Min: ${min(profits):.2f}")
    print(f"  Max: ${max(profits):.2f}")
    print(f"  Std Dev: ${statistics.stdev(profits):.2f}")
    print(f"  Range: ${max(profits) - min(profits):.2f}")
    
    print(f"\nWin Rate Analysis:")
    print(f"  Mean: {statistics.mean(win_rates):.1f}%")
    print(f"  Median: {statistics.median(win_rates):.1f}%")
    print(f"  Min: {min(win_rates):.1f}%")
    print(f"  Max: {max(win_rates):.1f}%")
    print(f"  Std Dev: {statistics.stdev(win_rates):.1f}%")
    
    print(f"\nProfit Factor Analysis:")
    print(f"  Mean: {statistics.mean(profit_factors):.2f}")
    print(f"  Median: {statistics.median(profit_factors):.2f}")
    print(f"  Min: {min(profit_factors):.2f}")
    print(f"  Max: {max(profit_factors):.2f}")
    print(f"  Std Dev: {statistics.stdev(profit_factors):.2f}")
    
    print(f"\nMax Drawdown Analysis:")
    print(f"  Mean: {statistics.mean(max_drawdowns):.1f}%")
    print(f"  Median: {statistics.median(max_drawdowns):.1f}%")
    print(f"  Min: {min(max_drawdowns):.1f}%")
    print(f"  Max: {max(max_drawdowns):.1f}%")
    print(f"  Std Dev: {statistics.stdev(max_drawdowns):.1f}%")
    
    print(f"\nTrade Count Analysis:")
    print(f"  Mean: {statistics.mean(total_trades_list):.0f} trades")
    print(f"  Median: {statistics.median(total_trades_list):.0f} trades")
    print(f"  Min: {min(total_trades_list)} trades")
    print(f"  Max: {max(total_trades_list)} trades")
    print(f"  Std Dev: {statistics.stdev(total_trades_list):.0f} trades")
    
    # Identify patterns and anomalies
    print(f"\nPATTERN ANALYSIS:")
    print("-" * 80)
    
    # Find best and worst performing tests
    best_test = max(eurusd_tests, key=lambda x: x.get('total_profit', 0))
    worst_test = min(eurusd_tests, key=lambda x: x.get('total_profit', 0))
    
    print(f"Best Performing Test:")
    print(f"  ID: {best_test.get('test_run_id')}")
    print(f"  Profit: ${best_test.get('total_profit'):.2f}")
    print(f"  Win Rate: {best_test.get('win_rate'):.1f}%")
    print(f"  Profit Factor: {best_test.get('profit_factor'):.2f}")
    print(f"  Max Drawdown: {best_test.get('max_drawdown'):.1f}%")
    
    print(f"\nWorst Performing Test:")
    print(f"  ID: {worst_test.get('test_run_id')}")
    print(f"  Profit: ${worst_test.get('total_profit'):.2f}")
    print(f"  Win Rate: {worst_test.get('win_rate'):.1f}%")
    print(f"  Profit Factor: {worst_test.get('profit_factor'):.2f}")
    print(f"  Max Drawdown: {worst_test.get('max_drawdown'):.1f}%")
    
    # Analyze consistency
    profitable_tests = [test for test in eurusd_tests if test.get('total_profit', 0) > 0]
    losing_tests = [test for test in eurusd_tests if test.get('total_profit', 0) < 0]
    
    print(f"\nConsistency Analysis:")
    print(f"  Profitable Tests: {len(profitable_tests)}/{len(eurusd_tests)} ({len(profitable_tests)/len(eurusd_tests)*100:.1f}%)")
    print(f"  Losing Tests: {len(losing_tests)}/{len(eurusd_tests)} ({len(losing_tests)/len(eurusd_tests)*100:.1f}%)")
    
    # Analyze recent vs older tests
    if len(eurusd_tests) >= 10:
        recent_tests = eurusd_tests[-10:]  # Last 10 tests
        older_tests = eurusd_tests[:-10]   # Earlier tests
        
        recent_avg_profit = statistics.mean([test.get('total_profit', 0) for test in recent_tests])
        older_avg_profit = statistics.mean([test.get('total_profit', 0) for test in older_tests])
        
        print(f"\nRecent vs Older Tests:")
        print(f"  Recent 10 tests avg profit: ${recent_avg_profit:.2f}")
        print(f"  Older tests avg profit: ${older_avg_profit:.2f}")
        print(f"  Difference: ${recent_avg_profit - older_avg_profit:.2f}")
    
    # Identify potential causes of variation
    print(f"\nPOTENTIAL CAUSES OF VARIATION:")
    print("-" * 80)
    
    # Check for correlation between trade count and performance
    trade_count_correlation = correlation(total_trades_list, profits) if len(total_trades_list) > 1 else 0
    print(f"1. Trade Count vs Profit Correlation: {trade_count_correlation:.3f}")
    
    # Check for correlation between win rate and profit
    win_rate_correlation = correlation(win_rates, profits) if len(win_rates) > 1 else 0
    print(f"2. Win Rate vs Profit Correlation: {win_rate_correlation:.3f}")
    
    # Check for correlation between profit factor and profit
    pf_correlation = correlation(profit_factors, profits) if len(profit_factors) > 1 else 0
    print(f"3. Profit Factor vs Profit Correlation: {pf_correlation:.3f}")
    
    # Analyze test run ID patterns
    print(f"\n4. Test Run ID Analysis:")
    test_ids = [test.get('test_run_id', '') for test in eurusd_tests]
    
    # Extract random components from test IDs
    random_components = []
    for test_id in test_ids:
        if '_' in test_id:
            parts = test_id.split('_')
            if len(parts) >= 4:
                try:
                    random_comp = int(parts[3])
                    random_components.append(random_comp)
                except ValueError:
                    pass
    
    if random_components:
        print(f"   Random components range: {min(random_components)} to {max(random_components)}")
        print(f"   This suggests each test run has a unique random seed")
    
    # Recommendations
    print(f"\nRECOMMENDATIONS:")
    print("-" * 80)
    
    profit_variance = statistics.variance(profits) if len(profits) > 1 else 0
    profit_std = statistics.stdev(profits) if len(profits) > 1 else 0
    profit_mean = statistics.mean(profits)
    
    print(f"1. Test Consistency:")
    if profit_std < abs(profit_mean) * 0.2:  # Less than 20% of mean
        print(f"   ✅ Tests are relatively consistent (std dev: ${profit_std:.2f})")
    else:
        print(f"   ⚠️  Tests show high variability (std dev: ${profit_std:.2f})")
    
    print(f"2. Strategy Reliability:")
    profitable_percentage = len(profitable_tests) / len(eurusd_tests) * 100
    if profitable_percentage >= 70:
        print(f"   ✅ Strategy is reliable ({profitable_percentage:.1f}% profitable tests)")
    elif profitable_percentage >= 50:
        print(f"   ⚠️  Strategy is moderately reliable ({profitable_percentage:.1f}% profitable tests)")
    else:
        print(f"   ❌ Strategy needs improvement ({profitable_percentage:.1f}% profitable tests)")
    
    print(f"3. Risk Management:")
    avg_drawdown = statistics.mean(max_drawdowns)
    if avg_drawdown <= 15:
        print(f"   ✅ Good risk management (avg drawdown: {avg_drawdown:.1f}%)")
    elif avg_drawdown <= 25:
        print(f"   ⚠️  Moderate risk (avg drawdown: {avg_drawdown:.1f}%)")
    else:
        print(f"   ❌ High risk (avg drawdown: {avg_drawdown:.1f}%)")
    
    print(f"\n4. Suggested Actions:")
    if profit_std > abs(profit_mean) * 0.3:
        print(f"   - Investigate causes of high variability")
        print(f"   - Check for parameter drift or market condition changes")
        print(f"   - Consider running more tests to establish baseline")
    
    if profitable_percentage < 60:
        print(f"   - Review strategy logic and entry/exit conditions")
        print(f"   - Consider adjusting risk parameters")
        print(f"   - Analyze losing trades for patterns")
    
    if avg_drawdown > 20:
        print(f"   - Tighten stop losses or reduce position sizes")
        print(f"   - Implement better risk management rules")
        print(f"   - Consider adding correlation filters")

def main():
    """Main function"""
    analyze_eurusd_test_runs()

if __name__ == "__main__":
    main() 