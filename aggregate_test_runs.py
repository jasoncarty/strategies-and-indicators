#!/usr/bin/env python3
"""
Aggregate JSON files from all test runs for ML training
Combines all ML_Data.json and Results.json files across test run directories
"""

import os
import json
import glob
from pathlib import Path

def aggregate_ml_data():
    """Aggregate all ML_Data.json files from test run directories"""
    
    # Path to MT5 Common Files directory
    mt5_common_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
    ea_base_path = os.path.join(mt5_common_path, "SimpleBreakoutML_EA")
    
    if not os.path.exists(ea_base_path):
        print(f"❌ EA base directory not found: {ea_base_path}")
        return
    
    # Find all test run directories
    test_run_dirs = [d for d in os.listdir(ea_base_path) if os.path.isdir(os.path.join(ea_base_path, d))]
    
    if not test_run_dirs:
        print("❌ No test run directories found")
        return
    
    print(f"🔍 Found {len(test_run_dirs)} test run directories")
    
    # Aggregate ML data
    all_trades = []
    successful_runs = 0
    
    for test_run in test_run_dirs:
        ml_data_file = os.path.join(ea_base_path, test_run, "SimpleBreakoutML_EA_ML_Data.json")
        
        if os.path.exists(ml_data_file):
            try:
                with open(ml_data_file, 'r') as f:
                    data = json.load(f)
                
                if "trades" in data and isinstance(data["trades"], list):
                    trades = data["trades"]
                    all_trades.extend(trades)
                    successful_runs += 1
                    print(f"✅ Loaded {len(trades)} trades from {test_run}")
                else:
                    print(f"⚠️  Invalid structure in {test_run}")
                    
            except Exception as e:
                print(f"❌ Error reading {test_run}: {e}")
        else:
            print(f"⚠️  No ML data file found in {test_run}")
    
    # Save aggregated ML data
    if all_trades:
        aggregated_file = os.path.join(ea_base_path, "aggregated_ml_data.json")
        aggregated_data = {"trades": all_trades}
        
        with open(aggregated_file, 'w') as f:
            json.dump(aggregated_data, f, indent=2)
        
        print(f"✅ Aggregated {len(all_trades)} trades from {successful_runs} test runs")
        print(f"📁 Saved to: {aggregated_file}")
    else:
        print("❌ No trades found to aggregate")

def aggregate_results():
    """Aggregate all Results.json files from test run directories"""
    
    # Path to MT5 Common Files directory
    mt5_common_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
    ea_base_path = os.path.join(mt5_common_path, "SimpleBreakoutML_EA")
    
    if not os.path.exists(ea_base_path):
        print(f"❌ EA base directory not found: {ea_base_path}")
        return
    
    # Find all test run directories
    test_run_dirs = [d for d in os.listdir(ea_base_path) if os.path.isdir(os.path.join(ea_base_path, d))]
    
    if not test_run_dirs:
        print("❌ No test run directories found")
        return
    
    # Aggregate results
    all_results = []
    successful_runs = 0
    
    for test_run in test_run_dirs:
        results_file = os.path.join(ea_base_path, test_run, "SimpleBreakoutML_EA_Results.json")
        
        if os.path.exists(results_file):
            try:
                with open(results_file, 'r') as f:
                    data = json.load(f)
                
                if "comprehensive_results" in data and isinstance(data["comprehensive_results"], list):
                    results = data["comprehensive_results"]
                    all_results.extend(results)
                    successful_runs += 1
                    print(f"✅ Loaded {len(results)} result sets from {test_run}")
                else:
                    print(f"⚠️  Invalid structure in {test_run}")
                    
            except Exception as e:
                print(f"❌ Error reading {test_run}: {e}")
        else:
            print(f"⚠️  No results file found in {test_run}")
    
    # Save aggregated results
    if all_results:
        aggregated_file = os.path.join(ea_base_path, "aggregated_results.json")
        aggregated_data = {"comprehensive_results": all_results}
        
        with open(aggregated_file, 'w') as f:
            json.dump(aggregated_data, f, indent=2)
        
        print(f"✅ Aggregated {len(all_results)} result sets from {successful_runs} test runs")
        print(f"📁 Saved to: {aggregated_file}")
    else:
        print("❌ No results found to aggregate")

if __name__ == "__main__":
    print("🧪 Aggregating JSON files from all test runs")
    print("=" * 50)
    
    print("\n📊 Aggregating ML Data...")
    aggregate_ml_data()
    
    print("\n📈 Aggregating Results...")
    aggregate_results()
    
    print("\n✅ Aggregation complete!")
