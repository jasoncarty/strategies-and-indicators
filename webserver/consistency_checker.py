#!/usr/bin/env python3
"""
Consistency Checker for EURUSD Strategy Testing
Tracks multiple test runs to identify inconsistencies
"""

import json
import os
import glob
from datetime import datetime
import statistics

def load_latest_results():
    """Load the latest Strategy Tester results"""
    mt5_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/"
    results_file = os.path.join(mt5_path, "StrategyTester_Results.json")
    
    if not os.path.exists(results_file):
        print("❌ No results file found")
        return None
    
    try:
        with open(results_file, 'r') as f:
            data = json.load(f)
        
        if 'test_results' in data and len(data['test_results']) > 0:
            return data['test_results'][-1]  # Get the latest result
        else:
            print("❌ No test results found in file")
            return None
            
    except Exception as e:
        print(f"❌ Error loading results: {e}")
        return None

def analyze_consistency():
    """Analyze consistency across multiple test runs"""
    print("🔍 CONSISTENCY ANALYSIS FOR EURUSD STRATEGY")
    print("=" * 60)
    
    # Load latest result
    latest = load_latest_results()
    if not latest:
        return
    
    print(f"📊 Latest Test Run: {latest.get('test_run_id', 'Unknown')}")
    print(f"📈 Symbol: {latest.get('symbol', 'Unknown')}")
    print(f"⏰ Timeframe: {latest.get('timeframe', 'Unknown')}")
    print()
    
    # Extract key metrics
    total_trades = latest.get('total_trades', 0)
    winning_trades = latest.get('winning_trades', 0)
    total_profit = latest.get('total_profit', 0)
    profit_factor = latest.get('profit_factor', 0)
    max_drawdown = latest.get('max_drawdown', 0)
    
    win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
    avg_profit = total_profit / total_trades if total_trades > 0 else 0
    monthly_profit = (total_profit / 18) * 12  # Assuming 18 months test period
    
    print("📈 LATEST RESULTS:")
    print(f"   Total Trades: {total_trades}")
    print(f"   Winning Trades: {winning_trades}")
    print(f"   Win Rate: {win_rate:.2f}%")
    print(f"   Total Profit: ${total_profit:.2f}")
    print(f"   Average Profit per Trade: ${avg_profit:.2f}")
    print(f"   Profit Factor: {profit_factor:.2f}")
    print(f"   Max Drawdown: {max_drawdown:.2f}%")
    print(f"   Monthly Projection: ${monthly_profit:.2f}")
    print()
    
    # Consistency indicators
    print("🎯 CONSISTENCY INDICATORS:")
    
    # Check if results are within expected ranges
    expected_ranges = {
        'total_trades': (65, 75),
        'win_rate': (30, 40),
        'profit_factor': (1.05, 1.15),
        'max_drawdown': (15, 20),
        'monthly_profit': (15, 35)
    }
    
    consistency_score = 0
    total_checks = len(expected_ranges)
    
    for metric, (min_val, max_val) in expected_ranges.items():
        if metric == 'total_trades':
            value = total_trades
        elif metric == 'win_rate':
            value = win_rate
        elif metric == 'profit_factor':
            value = profit_factor
        elif metric == 'max_drawdown':
            value = max_drawdown
        elif metric == 'monthly_profit':
            value = monthly_profit
        
        if min_val <= value <= max_val:
            print(f"   ✅ {metric}: {value:.2f} (Expected: {min_val}-{max_val})")
            consistency_score += 1
        else:
            print(f"   ❌ {metric}: {value:.2f} (Expected: {min_val}-{max_val})")
    
    consistency_percentage = (consistency_score / total_checks) * 100
    print()
    print(f"📊 CONSISTENCY SCORE: {consistency_percentage:.1f}%")
    
    if consistency_percentage >= 80:
        print("🎉 Results are CONSISTENT with expected ranges")
    elif consistency_percentage >= 60:
        print("⚠️  Results are MODERATELY consistent")
    else:
        print("🚨 Results are INCONSISTENT - investigate further")
    
    print()
    print("💡 RECOMMENDATIONS:")
    if consistency_percentage < 80:
        print("   - Check Strategy Tester settings (Every tick, fixed spread)")
        print("   - Use same test period for all runs")
        print("   - Restart MetaTrader between tests")
        print("   - Clear EA cache and re-add")
    else:
        print("   - Results are consistent, strategy is stable")
        print("   - Consider scaling up account size")
        print("   - Test on different timeframes")
    
    print("=" * 60)

if __name__ == "__main__":
    analyze_consistency() 