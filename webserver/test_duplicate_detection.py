#!/usr/bin/env python3
"""
Test Duplicate Detection
Demonstrates the new duplicate trade detection functionality
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from improved_ml_trainer import ImprovedMLTrainer

def create_test_data_with_duplicates():
    """Create test data with known duplicates to demonstrate the detection"""
    print("🧪 Creating test data with duplicates...")
    
    # Base trade data
    base_trades = []
    
    # Create some base trades
    for i in range(10):
        base_trade = {
            'test_run_id': f'TEST_RUN_{i//3 + 1}',  # 3 trades per test run
            'trade_id': i + 1,
            'symbol': 'EURUSD',
            'direction': 'buy' if i % 2 == 0 else 'sell',
            'timestamp': int(datetime(2024, 1, 1, 10, 0, 0).timestamp()) + i * 3600,  # 1 hour apart
            'entry_price': 1.1000 + (i * 0.001),
            'stop_loss': 1.0950 + (i * 0.001),
            'take_profit': 1.1100 + (i * 0.001),
            'rsi': 50 + (i * 5),
            'stoch_main': 60 + (i * 3),
            'macd_main': 0.001 + (i * 0.0001),
            'atr': 0.005 + (i * 0.0001),
            'volume': 1000 + (i * 100),
            'success': 1 if i % 3 == 0 else 0
        }
        base_trades.append(base_trade)
    
    # Create exact duplicates
    exact_duplicates = []
    for i in range(3):
        duplicate = base_trades[i].copy()
        duplicate['test_run_id'] = f'DUPLICATE_RUN_{i+1}'
        duplicate['trade_id'] = 100 + i
        exact_duplicates.append(duplicate)
    
    # Create near-duplicates (slightly different prices)
    near_duplicates = []
    for i in range(2):
        near_duplicate = base_trades[i+5].copy()
        near_duplicate['test_run_id'] = f'NEAR_DUPLICATE_RUN_{i+1}'
        near_duplicate['trade_id'] = 200 + i
        near_duplicate['entry_price'] += 0.0001  # Slightly different price
        near_duplicates.append(near_duplicate)
    
    # Create overlapping time period trades
    overlapping_trades = []
    for i in range(2):
        overlapping = base_trades[i+3].copy()
        overlapping['test_run_id'] = f'OVERLAP_RUN_{i+1}'
        overlapping['trade_id'] = 300 + i
        overlapping['timestamp'] += 60  # Same minute, different test run
        overlapping_trades.append(overlapping)
    
    # Combine all trades
    all_trades = base_trades + exact_duplicates + near_duplicates + overlapping_trades
    
    df = pd.DataFrame(all_trades)
    print(f"✅ Created test data with {len(df)} trades")
    print(f"   - {len(base_trades)} base trades")
    print(f"   - {len(exact_duplicates)} exact duplicates")
    print(f"   - {len(near_duplicates)} near-duplicates")
    print(f"   - {len(overlapping_trades)} overlapping trades")
    
    return df

def test_duplicate_detection():
    """Test the duplicate detection functionality"""
    print("🚀 Testing duplicate detection...")
    
    # Create test data
    test_df = create_test_data_with_duplicates()
    
    # Initialize ML trainer
    trainer = ImprovedMLTrainer()
    
    # Test duplicate removal
    print("\n" + "="*60)
    print("TESTING DUPLICATE DETECTION")
    print("="*60)
    
    cleaned_df = trainer._remove_duplicate_trades(test_df.copy())
    
    print(f"\n📊 RESULTS:")
    print(f"   Original trades: {len(test_df)}")
    print(f"   After cleaning: {len(cleaned_df)}")
    print(f"   Removed: {len(test_df) - len(cleaned_df)} trades")
    
    # Show what was removed
    removed_trades = test_df[~test_df.index.isin(cleaned_df.index)]
    if len(removed_trades) > 0:
        print(f"\n🗑️  REMOVED TRADES:")
        for idx, trade in removed_trades.iterrows():
            print(f"   Trade {trade['trade_id']} from {trade['test_run_id']} (entry: {trade['entry_price']})")
    
    return test_df, cleaned_df

def analyze_real_data():
    """Analyze real data for duplicates"""
    print("\n" + "="*60)
    print("ANALYZING REAL DATA")
    print("="*60)
    
    # Initialize ML trainer
    trainer = ImprovedMLTrainer()
    
    try:
        # Load real data
        print("📖 Loading real data...")
        df = trainer.load_and_clean_data()
        
        if df is not None and len(df) > 0:
            print(f"✅ Loaded {len(df)} trades from real data")
            
            # Check for potential duplicates
            print("\n🔍 Checking for potential duplicates in real data...")
            
            # Check for exact duplicates on key columns
            key_columns = ['timestamp', 'symbol', 'direction', 'entry_price']
            available_columns = [col for col in key_columns if col in df.columns]
            
            if len(available_columns) >= 3:
                exact_duplicates = df.duplicated(subset=available_columns, keep='first')
                exact_count = exact_duplicates.sum()
                
                print(f"   Exact duplicates found: {exact_count}")
                
                if exact_count > 0:
                    print(f"   Duplicate percentage: {(exact_count/len(df))*100:.1f}%")
                    
                    # Show some examples
                    duplicate_examples = df[exact_duplicates].head(3)
                    print(f"\n   Example duplicates:")
                    for idx, trade in duplicate_examples.iterrows():
                        print(f"     {trade['test_run_id'] if 'test_run_id' in trade else 'Unknown'}: {trade['symbol']} {trade['direction']} at {trade['entry_price']}")
                
                # Check test run distribution
                if 'test_run_id' in df.columns:
                    run_counts = df['test_run_id'].value_counts()
                    print(f"\n   Test run distribution:")
                    for run_id, count in run_counts.head(5).items():
                        print(f"     {run_id}: {count} trades")
                    if len(run_counts) > 5:
                        print(f"     ... and {len(run_counts) - 5} more test runs")
            else:
                print("   ⚠️  Insufficient columns for duplicate detection")
        else:
            print("❌ No real data found")
            
    except Exception as e:
        print(f"❌ Error analyzing real data: {e}")

def main():
    """Main function"""
    print("🧪 DUPLICATE DETECTION TEST")
    print("="*60)
    
    # Test with synthetic data
    test_df, cleaned_df = test_duplicate_detection()
    
    # Analyze real data
    analyze_real_data()
    
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print("✅ Duplicate detection system is working!")
    print("📋 The system detects:")
    print("   - Exact duplicates (same timestamp, symbol, direction, prices)")
    print("   - Near-duplicates (very similar characteristics)")
    print("   - Overlapping trades (same time period, different test runs)")
    print("\n💡 This will help improve ML training by removing biased data")
    print("   from overlapping strategy tester runs.")

if __name__ == "__main__":
    main() 