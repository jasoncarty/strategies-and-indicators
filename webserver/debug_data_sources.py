#!/usr/bin/env python3
"""
Debug Data Sources
Investigates why ML trainer shows different trade counts than expected
"""

import json
import os
import glob
import pandas as pd

def find_metatrader_directory():
    """Find MetaTrader Common Files directory"""
    possible_paths = [
        os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
        os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/Common/Files"),
        os.path.expanduser("~/Documents/MetaTrader 5/MQL5/Files"),
        os.path.expanduser("~/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
        "/Applications/MetaTrader 5.app/Contents/Resources/MQL5/Files"
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            return path
    return "."

def analyze_data_files():
    """Analyze all data files to understand the trade count discrepancy"""
    print("🔍 DEBUGGING DATA SOURCE DISCREPANCY")
    print("=" * 50)
    
    mt5_dir = find_metatrader_directory()
    ea_dir = os.path.join(mt5_dir, "SimpleBreakoutML_EA")
    
    print(f"📁 MetaTrader directory: {mt5_dir}")
    print(f"📁 EA directory: {ea_dir}")
    
    if not os.path.exists(ea_dir):
        print("❌ EA directory not found")
        return
    
    # List all files in the EA directory
    print(f"\n📋 Files in EA directory:")
    all_files = os.listdir(ea_dir)
    for file in all_files:
        file_path = os.path.join(ea_dir, file)
        file_size = os.path.getsize(file_path)
        print(f"   {file} ({file_size} bytes)")
    
    # Analyze ML data files
    print(f"\n🔍 ANALYZING ML DATA FILES:")
    ml_data_pattern = os.path.join(ea_dir, "*_ML_Data.json")
    ml_data_files = glob.glob(ml_data_pattern)
    
    total_ml_trades = 0
    for ml_file in ml_data_files:
        print(f"\n📖 Analyzing: {os.path.basename(ml_file)}")
        try:
            with open(ml_file, 'r') as f:
                ml_data = json.load(f)
            
            if isinstance(ml_data, dict) and 'trades' in ml_data:
                trades = ml_data['trades']
                print(f"   📊 Trades in file: {len(trades)}")
                total_ml_trades += len(trades)
                
                # Analyze by symbol
                if trades:
                    symbols = {}
                    test_runs = {}
                    for trade in trades:
                        symbol = trade.get('symbol', 'unknown')
                        test_run = trade.get('test_run_id', 'unknown')
                        symbols[symbol] = symbols.get(symbol, 0) + 1
                        test_runs[test_run] = test_runs.get(test_run, 0) + 1
                    
                    print(f"   💱 Symbols: {symbols}")
                    print(f"   🧪 Test runs: {len(test_runs)}")
                    if len(test_runs) <= 5:
                        for run, count in test_runs.items():
                            print(f"      {run}: {count} trades")
                    else:
                        print(f"      ... {len(test_runs)} test runs total")
            else:
                print(f"   ❌ Unexpected structure")
                
        except Exception as e:
            print(f"   ❌ Error reading file: {e}")
    
    print(f"\n📊 TOTAL ML DATA TRADES: {total_ml_trades}")
    
    # Analyze trade results files
    print(f"\n🔍 ANALYZING TRADE RESULTS FILES:")
    results_pattern = os.path.join(ea_dir, "*_Trade_Results.json")
    results_files = glob.glob(results_pattern)
    
    total_results_trades = 0
    for results_file in results_files:
        print(f"\n📖 Analyzing: {os.path.basename(results_file)}")
        try:
            with open(results_file, 'r') as f:
                results_data = json.load(f)
            
            if isinstance(results_data, dict) and 'trades' in results_data:
                trades = results_data['trades']
                print(f"   📊 Trades in file: {len(trades)}")
                total_results_trades += len(trades)
                
                # Analyze by symbol
                if trades:
                    symbols = {}
                    test_runs = {}
                    for trade in trades:
                        symbol = trade.get('symbol', 'unknown')
                        test_run = trade.get('test_run_id', 'unknown')
                        symbols[symbol] = symbols.get(symbol, 0) + 1
                        test_runs[test_run] = test_runs.get(test_run, 0) + 1
                    
                    print(f"   💱 Symbols: {symbols}")
                    print(f"   🧪 Test runs: {len(test_runs)}")
            else:
                print(f"   ❌ Unexpected structure")
                
        except Exception as e:
            print(f"   ❌ Error reading file: {e}")
    
    print(f"\n📊 TOTAL TRADE RESULTS: {total_results_trades}")
    
    # Check for other results files
    print(f"\n🔍 CHECKING FOR OTHER RESULTS FILES:")
    other_results_pattern = os.path.join(ea_dir, "*_Results.json")
    other_results_files = glob.glob(other_results_pattern)
    
    for results_file in other_results_files:
        if "_Trade_Results.json" not in results_file:  # Skip the one we already checked
            print(f"\n📖 Analyzing: {os.path.basename(results_file)}")
            try:
                with open(results_file, 'r') as f:
                    results_data = json.load(f)
                
                if isinstance(results_data, dict) and 'trades' in results_data:
                    trades = results_data['trades']
                    print(f"   📊 Trades in file: {len(trades)}")
                elif isinstance(results_data, list):
                    print(f"   📊 Trades in file: {len(results_data)}")
                else:
                    print(f"   📊 File structure: {type(results_data)}")
                    
            except Exception as e:
                print(f"   ❌ Error reading file: {e}")
    
    print(f"\n🎯 SUMMARY:")
    print(f"   ML Data trades: {total_ml_trades}")
    print(f"   Trade Results: {total_results_trades}")
    print(f"   Expected EURUSD: 27 trades")
    print(f"   Discrepancy: {total_ml_trades - 27} extra trades")

if __name__ == "__main__":
    analyze_data_files() 