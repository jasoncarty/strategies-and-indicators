#!/usr/bin/env python3
"""
Test Merge Fix
Simple script to test the merge logic fix
"""

import pandas as pd
import numpy as np

def test_merge_logic():
    """Test the merge logic to ensure it doesn't create duplicates"""
    print("🧪 TESTING MERGE LOGIC FIX")
    print("=" * 40)
    
    # Create sample ML data (27 trades)
    ml_data = []
    for i in range(27):
        ml_data.append({
            'test_run_id': f'test_run_001',
            'trade_id': i + 1,
            'symbol': 'EURUSD',
            'direction': 'buy' if i % 2 == 0 else 'sell',
            'entry_price': 1.1000 + (i * 0.0001),
            'rsi': 50 + np.random.randint(-20, 20),
            'macd_main': np.random.uniform(-0.001, 0.001),
            'volume': np.random.uniform(0.8, 1.5)
        })
    
    # Create sample trade results (27 trades)
    results_data = []
    for i in range(27):
        results_data.append({
            'test_run_id': f'test_run_001',
            'trade_id': i + 1,
            'trade_success': True if np.random.random() > 0.5 else False,
            'profit': np.random.uniform(-100, 100),
            'net_profit': np.random.uniform(-100, 100),
            'exit_reason': 'take_profit' if np.random.random() > 0.5 else 'stop_loss'
        })
    
    # Create DataFrames
    df = pd.DataFrame(ml_data)
    results_df = pd.DataFrame(results_data)
    
    print(f"📊 ML Data shape: {df.shape}")
    print(f"📊 Results Data shape: {results_df.shape}")
    
    # Test the OLD merge logic (test_run_id only)
    print("\n🔍 TESTING OLD MERGE LOGIC (test_run_id only):")
    old_merged = df.merge(results_df[['test_run_id', 'trade_success', 'profit', 'net_profit', 'exit_reason']], 
                         on='test_run_id', how='left', suffixes=('', '_result'))
    print(f"   Old merge result: {old_merged.shape}")
    
    # Test the NEW merge logic (test_run_id AND trade_id)
    print("\n🔍 TESTING NEW MERGE LOGIC (test_run_id AND trade_id):")
    new_merged = df.merge(results_df[['test_run_id', 'trade_id', 'trade_success', 'profit', 'net_profit', 'exit_reason']], 
                         on=['test_run_id', 'trade_id'], how='left', suffixes=('', '_result'))
    print(f"   New merge result: {new_merged.shape}")
    
    # Check for duplicates in old merge
    old_duplicates = old_merged.duplicated(subset=['test_run_id', 'trade_id']).sum()
    new_duplicates = new_merged.duplicated(subset=['test_run_id', 'trade_id']).sum()
    
    print(f"\n📊 DUPLICATE ANALYSIS:")
    print(f"   Old merge duplicates: {old_duplicates}")
    print(f"   New merge duplicates: {new_duplicates}")
    
    if old_merged.shape[0] > df.shape[0]:
        print(f"   ❌ OLD LOGIC: Created {old_merged.shape[0] - df.shape[0]} extra rows!")
    else:
        print(f"   ✅ OLD LOGIC: No extra rows created")
    
    if new_merged.shape[0] == df.shape[0]:
        print(f"   ✅ NEW LOGIC: Correct number of rows maintained!")
    else:
        print(f"   ❌ NEW LOGIC: Unexpected row count!")
    
    print(f"\n🎯 CONCLUSION:")
    if new_merged.shape[0] == 27:
        print(f"   ✅ FIX SUCCESSFUL: Merge now correctly maintains 27 trades")
    else:
        print(f"   ❌ FIX FAILED: Still getting {new_merged.shape[0]} trades instead of 27")

if __name__ == "__main__":
    test_merge_logic() 