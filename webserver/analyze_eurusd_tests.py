#!/usr/bin/env python3
"""
Analyze EURUSD+ test results to identify differences between test runs
"""

import json
import pandas as pd
from datetime import datetime
import os
import glob

def load_trade_results(file_path):
    """Load trade results from JSON file"""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        return data.get('trade_results', [])
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return []

def analyze_test_runs(trade_results):
    """Analyze different test runs and their characteristics"""
    
    # Group trades by test_run_id
    test_runs = {}
    for trade in trade_results:
        test_run_id = trade.get('test_run_id', 'unknown')
        if test_run_id not in test_runs:
            test_runs[test_run_id] = []
        test_runs[test_run_id].append(trade)
    
    print(f"Found {len(test_runs)} test runs:")
    print("=" * 80)
    
    for test_run_id, trades in test_runs.items():
        print(f"\nTest Run ID: {test_run_id}")
        print(f"Number of trades: {len(trades)}")
        
        # Calculate statistics
        total_profit = sum(trade['profit'] for trade in trades)
        winning_trades = sum(1 for trade in trades if trade['trade_success'])
        losing_trades = len(trades) - winning_trades
        win_rate = (winning_trades / len(trades) * 100) if trades else 0
        
        # Calculate average metrics
        avg_lot_size = sum(trade['lot_size'] for trade in trades) / len(trades)
        avg_trade_duration = sum(trade['trade_duration'] for trade in trades) / len(trades)
        avg_profit = total_profit / len(trades)
        
        # Direction analysis
        buy_trades = sum(1 for trade in trades if trade['direction'] == 'buy')
        sell_trades = sum(1 for trade in trades if trade['direction'] == 'sell')
        
        # Exit reason analysis
        take_profit_trades = sum(1 for trade in trades if trade['exit_reason'] == 'take_profit')
        stop_loss_trades = sum(1 for trade in trades if trade['exit_reason'] == 'stop_loss')
        
        print(f"  Total Profit: ${total_profit:.2f}")
        print(f"  Win Rate: {win_rate:.1f}% ({winning_trades}/{len(trades)})")
        print(f"  Average Profit per Trade: ${avg_profit:.2f}")
        print(f"  Average Lot Size: {avg_lot_size:.2f}")
        print(f"  Average Trade Duration: {avg_trade_duration/3600:.1f} hours")
        print(f"  Buy/Sell Ratio: {buy_trades}/{sell_trades}")
        print(f"  Take Profit/Stop Loss: {take_profit_trades}/{stop_loss_trades}")
        
        # Time range analysis
        if trades:
            start_time = min(trade['close_time'] for trade in trades)
            end_time = max(trade['close_time'] for trade in trades)
            start_dt = datetime.fromtimestamp(start_time)
            end_dt = datetime.fromtimestamp(end_time)
            print(f"  Test Period: {start_dt} to {end_dt}")
            print(f"  Duration: {(end_time - start_time) / 86400:.1f} days")
        
        # Profit distribution analysis
        profits = [trade['profit'] for trade in trades]
        if profits:
            print(f"  Min Profit: ${min(profits):.2f}")
            print(f"  Max Profit: ${max(profits):.2f}")
            print(f"  Profit Std Dev: ${pd.Series(profits).std():.2f}")
        
        # Lot size distribution
        lot_sizes = [trade['lot_size'] for trade in trades]
        if lot_sizes:
            print(f"  Min Lot Size: {min(lot_sizes):.2f}")
            print(f"  Max Lot Size: {max(lot_sizes):.2f}")
            print(f"  Lot Size Std Dev: {pd.Series(lot_sizes).std():.2f}")

def analyze_trade_patterns(trade_results):
    """Analyze patterns in trades to identify potential issues"""
    
    print("\n" + "=" * 80)
    print("TRADE PATTERN ANALYSIS")
    print("=" * 80)
    
    # Check for consecutive losses/wins
    consecutive_losses = 0
    max_consecutive_losses = 0
    consecutive_wins = 0
    max_consecutive_wins = 0
    
    for trade in trade_results:
        if trade['trade_success']:
            consecutive_wins += 1
            consecutive_losses = 0
            max_consecutive_wins = max(max_consecutive_wins, consecutive_wins)
        else:
            consecutive_losses += 1
            consecutive_wins = 0
            max_consecutive_losses = max(max_consecutive_losses, consecutive_losses)
    
    print(f"Max consecutive wins: {max_consecutive_wins}")
    print(f"Max consecutive losses: {max_consecutive_losses}")
    
    # Analyze lot size progression
    lot_sizes = [trade['lot_size'] for trade in trade_results]
    print(f"\nLot size progression:")
    print(f"  First 10 trades: {lot_sizes[:10]}")
    print(f"  Last 10 trades: {lot_sizes[-10:]}")
    
    # Check for lot size anomalies
    avg_lot_size = sum(lot_sizes) / len(lot_sizes)
    lot_size_variance = sum((lot - avg_lot_size) ** 2 for lot in lot_sizes) / len(lot_sizes)
    print(f"  Average lot size: {avg_lot_size:.2f}")
    print(f"  Lot size variance: {lot_size_variance:.4f}")
    
    # Analyze trade timing
    close_times = [trade['close_time'] for trade in trade_results]
    time_diffs = [close_times[i] - close_times[i-1] for i in range(1, len(close_times))]
    
    if time_diffs:
        avg_time_between_trades = sum(time_diffs) / len(time_diffs)
        print(f"\nTrade timing:")
        print(f"  Average time between trades: {avg_time_between_trades/3600:.1f} hours")
        print(f"  Min time between trades: {min(time_diffs)/3600:.1f} hours")
        print(f"  Max time between trades: {max(time_diffs)/3600:.1f} hours")

def check_for_multiple_test_files():
    """Check for multiple test result files that might contain different test runs"""
    
    print("\n" + "=" * 80)
    print("SEARCHING FOR MULTIPLE TEST FILES")
    print("=" * 80)
    
    # Common MetaTrader directories
    possible_paths = [
        "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/",
        "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/MQL5/Files/",
        "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/",
        "./",
        "../"
    ]
    
    test_files = []
    for path in possible_paths:
        if os.path.exists(path):
            # Look for various test result files
            patterns = [
                "*StrategyTester*Results*.json",
                "*Trade*Results*.json",
                "*Test*Results*.json",
                "*Results*.json"
            ]
            
            for pattern in patterns:
                files = glob.glob(os.path.join(path, pattern))
                test_files.extend(files)
    
    # Remove duplicates
    test_files = list(set(test_files))
    
    print(f"Found {len(test_files)} potential test result files:")
    for file_path in test_files:
        print(f"  {file_path}")
        
        # Try to load and analyze each file
        try:
            trades = load_trade_results(file_path)
            if trades:
                test_run_ids = set(trade.get('test_run_id', 'unknown') for trade in trades)
                print(f"    Contains {len(trades)} trades from {len(test_run_ids)} test runs")
                print(f"    Test run IDs: {list(test_run_ids)[:3]}...")  # Show first 3
        except Exception as e:
            print(f"    Error reading file: {e}")

def main():
    """Main analysis function"""
    
    # Primary file path
    primary_file = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Trade_Results.json"
    
    print("EURUSD+ TEST RESULTS ANALYSIS")
    print("=" * 80)
    
    # Load and analyze primary file
    trade_results = load_trade_results(primary_file)
    
    if not trade_results:
        print("No trade results found in primary file")
        return
    
    print(f"Loaded {len(trade_results)} trades from primary file")
    
    # Analyze test runs
    analyze_test_runs(trade_results)
    
    # Analyze trade patterns
    analyze_trade_patterns(trade_results)
    
    # Check for multiple test files
    check_for_multiple_test_files()
    
    print("\n" + "=" * 80)
    print("RECOMMENDATIONS")
    print("=" * 80)
    
    # Based on analysis, provide recommendations
    test_run_ids = set(trade.get('test_run_id', 'unknown') for trade in trade_results)
    
    if len(test_run_ids) == 1:
        print("⚠️  All trades are from a single test run. To analyze differences between test runs:")
        print("   1. Run multiple separate Strategy Tester sessions")
        print("   2. Each session should have a different test_run_id")
        print("   3. Check if EA is properly resetting between tests")
        print("   4. Verify that test settings are consistent")
    else:
        print(f"✅ Found {len(test_run_ids)} different test runs")
        print("   Analyze the differences in performance between these runs")

if __name__ == "__main__":
    main() 