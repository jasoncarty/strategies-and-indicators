#!/usr/bin/env python3
"""
Test Enhanced Functions
Verify that the enhanced volume and candle analysis functions are working
"""

import json
import pandas as pd
import numpy as np
from datetime import datetime

def test_enhanced_functions():
    """Test the enhanced volume and candle analysis functions"""
    print("🧪 TESTING ENHANCED FUNCTIONS")
    print("=" * 50)
    
    # Load the ML data to check current state
    try:
        with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_ML_Data.json', 'r') as f:
            data = json.load(f)
        
        trades = data['trades']
        df = pd.DataFrame(trades)
        
        print("📊 CURRENT DATA STATE:")
        print(f"Total trades: {len(df)}")
        print(f"Volume statistics:")
        print(f"  - Min volume: {df['volume'].min()}")
        print(f"  - Max volume: {df['volume'].max()}")
        print(f"  - Mean volume: {df['volume'].mean():.2f}")
        print(f"  - Unique volume values: {df['volume'].nunique()}")
        
        print(f"\n📊 CANDLE PATTERN ANALYSIS:")
        print(f"  - Unique patterns: {df['candle_pattern'].nunique()}")
        print(f"  - Pattern distribution:")
        pattern_counts = df['candle_pattern'].value_counts()
        for pattern, count in pattern_counts.items():
            percentage = (count / len(df)) * 100
            print(f"    {pattern}: {count} ({percentage:.1f}%)")
        
        print(f"\n📊 CANDLE SEQUENCE ANALYSIS:")
        print(f"  - Unique sequences: {df['candle_seq'].nunique()}")
        print(f"  - Most common sequences:")
        seq_counts = df['candle_seq'].value_counts().head(10)
        for seq, count in seq_counts.items():
            percentage = (count / len(df)) * 100
            print(f"    {seq}: {count} ({percentage:.1f}%)")
        
        print(f"\n📊 VOLUME RATIO ANALYSIS:")
        if 'volume_ratio' in df.columns:
            print(f"  - Min ratio: {df['volume_ratio'].min():.2f}")
            print(f"  - Max ratio: {df['volume_ratio'].max():.2f}")
            print(f"  - Mean ratio: {df['volume_ratio'].mean():.2f}")
            print(f"  - Unique ratios: {df['volume_ratio'].nunique()}")
        else:
            print("  - No volume_ratio column found")
        
        # Check for missing values
        print(f"\n🔍 MISSING VALUES CHECK:")
        missing_data = df.isnull().sum()
        if missing_data.sum() > 0:
            print("  Missing values found:")
            for col, missing in missing_data.items():
                if missing > 0:
                    print(f"    {col}: {missing} ({missing/len(df)*100:.1f}%)")
        else:
            print("  ✅ No missing values found")
        
        # Check for constant features
        print(f"\n🔍 CONSTANT FEATURES CHECK:")
        constant_features = []
        for col in df.select_dtypes(include=[np.number]).columns:
            if df[col].nunique() == 1:
                constant_features.append(col)
        
        if constant_features:
            print("  Constant features found:")
            for col in constant_features:
                print(f"    {col}: {df[col].iloc[0]}")
        else:
            print("  ✅ No constant features found")
        
        print(f"\n🎯 RECOMMENDATIONS:")
        print("  1. Run a new test with the enhanced functions")
        print("  2. Check if volume data is now properly collected")
        print("  3. Verify candle patterns are more diverse")
        print("  4. Ensure volume ratios are meaningful")
        
    except Exception as e:
        print(f"❌ Error loading data: {e}")

def create_test_plan():
    """Create a test plan for the enhanced functions"""
    print("\n📋 TEST PLAN FOR ENHANCED FUNCTIONS")
    print("=" * 50)
    
    print("1. COMPILE AND TEST EA:")
    print("   - Compile SimpleBreakoutML_EA.mq5")
    print("   - Check for compilation errors")
    print("   - Verify TradeUtils.mqh is included properly")
    
    print("\n2. RUN STRATEGY TESTER:")
    print("   - Run a short test (1-2 months)")
    print("   - Check if enhanced volume analysis is working")
    print("   - Verify candle patterns are being detected")
    
    print("\n3. ANALYZE RESULTS:")
    print("   - Check ML data file for improved volume values")
    print("   - Verify candle patterns are more diverse")
    print("   - Confirm volume ratios are meaningful")
    
    print("\n4. COMPARE WITH PREVIOUS DATA:")
    print("   - Volume should not all be 1")
    print("   - Candle patterns should be more varied")
    print("   - Volume ratios should show real market conditions")

if __name__ == "__main__":
    test_enhanced_functions()
    create_test_plan() 