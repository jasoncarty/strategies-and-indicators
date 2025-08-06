#!/usr/bin/env python3
"""
Check Actual Data
Simple script to see what's actually in the data files
"""

import json
import os

def check_data():
    """Check what's actually in the data files"""
    print("🔍 CHECKING ACTUAL DATA FILES")
    print("=" * 40)
    
    # Find MetaTrader directory
    mt5_dir = os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files")
    ea_dir = os.path.join(mt5_dir, "SimpleBreakoutML_EA")
    
    print(f"📁 EA Directory: {ea_dir}")
    
    if not os.path.exists(ea_dir):
        print("❌ EA directory not found")
        return
    
    # List all files
    print(f"\n📋 Files in directory:")
    files = os.listdir(ea_dir)
    for file in files:
        file_path = os.path.join(ea_dir, file)
        size = os.path.getsize(file_path)
        print(f"   {file} ({size} bytes)")
    
    # Check ML data file
    ml_file = os.path.join(ea_dir, "SimpleBreakoutML_EA_ML_Data.json")
    if os.path.exists(ml_file):
        print(f"\n📖 ML Data File Analysis:")
        try:
            with open(ml_file, 'r') as f:
                data = json.load(f)
            
            if isinstance(data, dict) and 'trades' in data:
                trades = data['trades']
                print(f"   📊 Total trades in file: {len(trades)}")
                
                # Count by symbol
                symbols = {}
                test_runs = {}
                for trade in trades:
                    symbol = trade.get('symbol', 'unknown')
                    test_run = trade.get('test_run_id', 'unknown')
                    symbols[symbol] = symbols.get(symbol, 0) + 1
                    test_runs[test_run] = test_runs.get(test_run, 0) + 1
                
                print(f"   💱 By symbol: {symbols}")
                print(f"   🧪 By test run: {test_runs}")
                
                # Show first few trades
                print(f"\n   📝 First 3 trades:")
                for i, trade in enumerate(trades[:3]):
                    print(f"      Trade {i+1}: {trade.get('symbol', 'N/A')} - {trade.get('test_run_id', 'N/A')}")
            else:
                print(f"   ❌ Unexpected structure: {type(data)}")
                
        except Exception as e:
            print(f"   ❌ Error reading file: {e}")
    else:
        print(f"❌ ML data file not found")
    
    # Check trade results file
    results_file = os.path.join(ea_dir, "SimpleBreakoutML_EA_Trade_Results.json")
    if os.path.exists(results_file):
        print(f"\n📖 Trade Results File Analysis:")
        try:
            with open(results_file, 'r') as f:
                data = json.load(f)
            
            if isinstance(data, dict) and 'trades' in data:
                trades = data['trades']
                print(f"   📊 Total trades in file: {len(trades)}")
                
                # Count by symbol
                symbols = {}
                test_runs = {}
                for trade in trades:
                    symbol = trade.get('symbol', 'unknown')
                    test_run = trade.get('test_run_id', 'unknown')
                    symbols[symbol] = symbols.get(symbol, 0) + 1
                    test_runs[test_run] = test_runs.get(test_run, 0) + 1
                
                print(f"   💱 By symbol: {symbols}")
                print(f"   🧪 By test run: {test_runs}")
            else:
                print(f"   ❌ Unexpected structure: {type(data)}")
                
        except Exception as e:
            print(f"   ❌ Error reading file: {e}")
    else:
        print(f"❌ Trade results file not found")

if __name__ == "__main__":
    check_data() 