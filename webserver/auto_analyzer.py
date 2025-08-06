#!/usr/bin/env python3
"""
Auto Analyzer for Strategy Tester Results
Monitors StrategyTester_Results.json for changes and automatically analyzes results
"""

import json
import os
import time
import glob
from datetime import datetime
from pathlib import Path
import pandas as pd

class StrategyResultsAnalyzer:
    def _extract_symbol_from_path(self, file_path: Path) -> str:
        """Extract symbol from file path dynamically"""
        # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
        path_parts = file_path.parts
        for i, part in enumerate(path_parts):
            if part in ['Models', 'BreakoutStrategy'] and i + 1 < len(path_parts):
                potential_symbol = path_parts[i + 1]
                # Check if it looks like a symbol (6 characters, mostly letters)
                if len(potential_symbol) == 6 and potential_symbol.isalpha():
                    return potential_symbol

        # Try to extract from filename
        filename = file_path.name
        # Look for patterns like buy_EURUSD_PERIOD_H1.pkl
        symbol_match = re.search(r'[a-z]+_([A-Z]{6})_PERIOD_', filename)
        if symbol_match:
            return symbol_match.group(1)

        # Default fallback
        return "UNKNOWN_SYMBOL"

    def __init__(self, results_file="StrategyTester_Results.json"):
        self.results_file = results_file
        self.last_modified = 0
        self.last_results = None
        
        # Find the actual file path
        self.file_path = self.find_results_file()
        if self.file_path:
            print(f"📊 Monitoring: {self.file_path}")
        else:
            print("❌ StrategyTester_Results.json not found")
    
    def find_results_file(self):
        """Find the StrategyTester_Results.json file in common locations"""
        possible_paths = [
            # MetaTrader Common Files directory (macOS)
            "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Results.json",
            # Current directory
            "./StrategyTester_Results.json",
            # Parent directory
            "../StrategyTester_Results.json",
            # Common Files relative to current directory
            "../../Common/Files/StrategyTester_Results.json"
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                return path
        
        # Try to find it using glob
        for root, dirs, files in os.walk("/Users/jasoncarty"):
            if "StrategyTester_Results.json" in files:
                return os.path.join(root, "StrategyTester_Results.json")
        
        return None
    
    def load_results(self):
        """Load and parse the results file"""
        try:
            if not self.file_path or not os.path.exists(self.file_path):
                return None
            
            with open(self.file_path, 'r') as f:
                data = json.load(f)
            
            return data
        except Exception as e:
            print(f"❌ Error loading results: {e}")
            return None
    
    def analyze_results(self, data):
        """Analyze the strategy test results"""
        if not data or 'test_results' not in data:
            print("❌ No test results found in file")
            return
        
        results = data['test_results']
        if not results:
            print("❌ No test results found")
            return
        
        # Get the latest result
        latest_result = results[-1]
        
        print("\n" + "="*60)
        print("🎯 STRATEGY TESTER RESULTS ANALYSIS")
        print("="*60)
        
        # Basic info
        print(f"📊 Test Run ID: {latest_result.get('test_run_id', 'N/A')}")
        print(f"📈 Symbol: {latest_result.get('symbol', 'N/A')}")
        print(f"⏰ Timeframe: {latest_result.get('timeframe', 'N/A')}")
        print(f"📅 Test Date: {datetime.fromtimestamp(latest_result.get('test_start_time', 0))}")
        
        # Performance metrics
        total_trades = latest_result.get('total_trades', 0)
        winning_trades = latest_result.get('winning_trades', 0)
        losing_trades = latest_result.get('losing_trades', 0)
        total_profit = latest_result.get('total_profit', 0)
        win_rate = latest_result.get('win_rate', 0)
        profit_factor = latest_result.get('profit_factor', 0)
        max_drawdown = latest_result.get('max_drawdown', 0)
        average_profit = latest_result.get('average_profit', 0)
        
        print(f"\n📈 PERFORMANCE METRICS:")
        print(f"   Total Trades: {total_trades}")
        print(f"   Winning Trades: {winning_trades}")
        print(f"   Losing Trades: {losing_trades}")
        print(f"   Win Rate: {win_rate:.2f}%")
        print(f"   Total Profit: ${total_profit:.2f}")
        print(f"   Average Profit per Trade: ${average_profit:.2f}")
        print(f"   Profit Factor: {profit_factor:.2f}")
        print(f"   Max Drawdown: {max_drawdown:.2f}%")
        
        # Analysis and recommendations
        print(f"\n🔍 ANALYSIS:")
        
        # Trade frequency analysis
        if total_trades > 0:
            trades_per_month = total_trades / 18  # Assuming 18-month test period
            print(f"   Trade Frequency: {trades_per_month:.1f} trades/month")
            
            if trades_per_month < 2:
                print("   ⚠️  Low trade frequency - consider relaxing signal requirements")
            elif trades_per_month > 10:
                print("   ⚠️  High trade frequency - consider tightening signal requirements")
            else:
                print("   ✅ Good trade frequency")
        
        # Profitability analysis
        if total_profit > 0:
            print("   ✅ Profitable strategy")
            
            if profit_factor >= 1.5:
                print("   ✅ Excellent profit factor")
            elif profit_factor >= 1.2:
                print("   ✅ Good profit factor")
            else:
                print("   ⚠️  Low profit factor - consider improving risk management")
        else:
            print("   ❌ Unprofitable strategy")
        
        # Win rate analysis
        if win_rate >= 50:
            print("   ✅ Good win rate")
        elif win_rate >= 40:
            print("   ⚠️  Moderate win rate - consider improving entry signals")
        else:
            print("   ❌ Low win rate - strategy needs improvement")
        
        # Risk analysis
        if max_drawdown <= 5:
            print("   ✅ Excellent risk control")
        elif max_drawdown <= 10:
            print("   ✅ Good risk control")
        elif max_drawdown <= 20:
            print("   ⚠️  Moderate risk - consider reducing position sizes")
        else:
            print("   ❌ High risk - strategy needs risk management improvement")
        
        # Monthly profit projection
        if total_profit > 0:
            monthly_profit = total_profit / 18  # Assuming 18-month test period
            print(f"\n📊 MONTHLY PROJECTION:")
            print(f"   Current Monthly Profit: ${monthly_profit:.2f}")
            
            # Calculate what's needed for 20% monthly target
            account_size = 10000  # Assuming $10K account
            target_monthly = account_size * 0.20
            print(f"   20% Monthly Target: ${target_monthly:.2f}")
            
            if monthly_profit >= target_monthly:
                print("   🎯 TARGET ACHIEVED!")
            else:
                shortfall = target_monthly - monthly_profit
                print(f"   📈 Need additional ${shortfall:.2f}/month to reach target")
                
                # Recommendations for improvement
                print(f"\n💡 RECOMMENDATIONS:")
                if trades_per_month < 5:
                    print("   - Increase trade frequency by relaxing signal requirements")
                if average_profit < 10:
                    print("   - Improve profit per trade with better risk:reward ratios")
                if win_rate < 45:
                    print("   - Improve entry signals for higher win rate")
                if max_drawdown > 10:
                    print("   - Reduce risk by using smaller position sizes")
        
        print("="*60)
        print("✅ Analysis complete - ready for next test")
        print("="*60 + "\n")
    
    def monitor_file(self):
        """Monitor the results file for changes"""
        print("🔍 Starting file monitor...")
        print("📊 Waiting for new strategy test results...")
        print("💡 Run a strategy test in MetaTrader to see automatic analysis")
        
        while True:
            try:
                if not self.file_path or not os.path.exists(self.file_path):
                    time.sleep(5)
                    continue
                
                # Check if file has been modified
                current_modified = os.path.getmtime(self.file_path)
                
                if current_modified > self.last_modified:
                    print(f"\n🔄 File updated at {datetime.now().strftime('%H:%M:%S')}")
                    
                    # Load and analyze the new results
                    data = self.load_results()
                    if data:
                        self.analyze_results(data)
                        self.last_modified = current_modified
                        self.last_results = data
                    
                    print("📊 Waiting for next test results...")
                
                time.sleep(2)  # Check every 2 seconds
                
            except KeyboardInterrupt:
                print("\n👋 Stopping file monitor...")
                break
            except Exception as e:
                print(f"❌ Error in monitor: {e}")
                time.sleep(5)

def main():
    analyzer = StrategyResultsAnalyzer()
    analyzer.monitor_file()

if __name__ == "__main__":
    main() 