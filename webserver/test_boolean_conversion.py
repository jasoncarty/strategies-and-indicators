#!/usr/bin/env python3
"""
Test Boolean to Numeric Conversion
Tests the conversion of boolean trade_success values to numeric
"""

import pandas as pd
import json

def test_boolean_conversion():
    """Test converting boolean trade_success to numeric"""
    print("🧪 Testing boolean to numeric conversion...")
    
    # Create sample data with boolean trade_success
    sample_data = {
        'test_run_id': ['TEST_1', 'TEST_2', 'TEST_3', 'TEST_4'],
        'trade_success': [True, False, True, False],
        'profit': [100.0, -50.0, 75.0, -25.0]
    }
    
    df = pd.DataFrame(sample_data)
    print(f"📊 Original data:")
    print(df)
    print(f"📊 trade_success dtype: {df['trade_success'].dtype}")
    print(f"📊 trade_success values: {df['trade_success'].tolist()}")
    
    # Test the conversion
    df['success'] = df['trade_success'].astype(float)
    print(f"\n📊 After conversion:")
    print(f"📊 success dtype: {df['success'].dtype}")
    print(f"📊 success values: {df['success'].tolist()}")
    print(f"📊 success mean: {df['success'].mean():.3f}")
    
    # Test with JSON data (like from the trade results file)
    json_data = [
        {"test_run_id": "TEST_1", "trade_success": True, "profit": 100.0},
        {"test_run_id": "TEST_2", "trade_success": False, "profit": -50.0},
        {"test_run_id": "TEST_3", "trade_success": True, "profit": 75.0},
        {"test_run_id": "TEST_4", "trade_success": False, "profit": -25.0}
    ]
    
    print(f"\n📊 Testing with JSON-like data:")
    json_df = pd.DataFrame(json_data)
    print(f"📊 JSON trade_success dtype: {json_df['trade_success'].dtype}")
    print(f"📊 JSON trade_success values: {json_df['trade_success'].tolist()}")
    
    # Convert to numeric
    json_df['success'] = json_df['trade_success'].astype(float)
    print(f"📊 JSON success dtype: {json_df['success'].dtype}")
    print(f"📊 JSON success values: {json_df['success'].tolist()}")
    print(f"📊 JSON success mean: {json_df['success'].mean():.3f}")
    
    print("\n✅ Boolean to numeric conversion test completed successfully!")

if __name__ == "__main__":
    test_boolean_conversion() 