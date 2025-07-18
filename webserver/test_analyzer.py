#!/usr/bin/env python3
"""
Test script to analyze current StrategyTester_Results.json
"""

import json
import os
from datetime import datetime

def analyze_current_results():
    # Try to find the results file
    possible_paths = [
        "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Results.json",
        "./StrategyTester_Results.json",
        "../StrategyTester_Results.json"
    ]
    
    file_path = None
    for path in possible_paths:
        if os.path.exists(path):
            file_path = path
            break
    
    if not file_path:
        print("❌ StrategyTester_Results.json not found")
        return
    
    print(f"📊 Found results file: {file_path}")
    
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        
        if 'test_results' not in data or not data['test_results']:
            print("❌ No test results found")
            return
        
        # Get the latest result
        latest_result = data['test_results'][-1]
        
        print("\n" + "="*60)
        print("🎯 CURRENT STRATEGY TESTER RESULTS")
        print("="*60)
        
        # Basic info
        print(f"📊 Test Run ID: {latest_result.get('test_run_id', 'N/A')}")
        print(f"📈 Symbol: {latest_result.get('symbol', 'N/A')}")
        print(f"⏰ Timeframe: {latest_result.get('timeframe', 'N/A')}")
        
        # Performance metrics
        total_trades = latest_result.get('total_trades', 0)
        winning_trades = latest_result.get('winning_trades', 0)
        total_profit = latest_result.get('total_profit', 0)
        win_rate = latest_result.get('win_rate', 0)
        profit_factor = latest_result.get('profit_factor', 0)
        max_drawdown = latest_result.get('max_drawdown', 0)
        average_profit = latest_result.get('average_profit', 0)
        
        print(f"\n📈 PERFORMANCE METRICS:")
        print(f"   Total Trades: {total_trades}")
        print(f"   Winning Trades: {winning_trades}")
        print(f"   Win Rate: {win_rate:.2f}%")
        print(f"   Total Profit: ${total_profit:.2f}")
        print(f"   Average Profit per Trade: ${average_profit:.2f}")
        print(f"   Profit Factor: {profit_factor:.2f}")
        print(f"   Max Drawdown: {max_drawdown:.2f}%")
        
        # Monthly projection
        if total_profit > 0:
            monthly_profit = total_profit / 18  # Assuming 18-month test period
            print(f"\n📊 MONTHLY PROJECTION:")
            print(f"   Current Monthly Profit: ${monthly_profit:.2f}")
            
            account_size = 10000  # Assuming $10K account
            target_monthly = account_size * 0.20
            print(f"   20% Monthly Target: ${target_monthly:.2f}")
            
            if monthly_profit >= target_monthly:
                print("   🎯 TARGET ACHIEVED!")
            else:
                shortfall = target_monthly - monthly_profit
                print(f"   📈 Need additional ${shortfall:.2f}/month to reach target")
        
        print("="*60)
        
    except Exception as e:
        print(f"❌ Error analyzing results: {e}")

if __name__ == "__main__":
    analyze_current_results() 