#!/usr/bin/env python3
"""
Test script to verify that the EA is properly loading buy/sell specific parameters
"""

import os

def test_parameter_loading():
    """Test that all parameters are properly loaded"""
    
    # Path to the parameter file
    param_file = "ml_models/ml_model_params_simple.txt"
    
    if not os.path.exists(param_file):
        print(f"❌ Parameter file not found: {param_file}")
        return False
    
    # Read the parameter file
    with open(param_file, 'r') as f:
        lines = f.readlines()
    
    # Parse parameters
    params = {}
    for line in lines:
        line = line.strip()
        if '=' in line:
            key, value = line.split('=', 1)
            params[key] = float(value)
    
    print("📊 Parameter Loading Test Results:")
    print("=" * 50)
    
    # Test combined parameters
    print("🔍 COMBINED MODEL PARAMETERS:")
    combined_params = {k: v for k, v in params.items() if k.startswith('combined_')}
    print(f"   Found {len(combined_params)} combined parameters")
    
    # Test buy parameters
    print("\n🔍 BUY MODEL PARAMETERS:")
    buy_params = {k: v for k, v in params.items() if k.startswith('buy_')}
    print(f"   Found {len(buy_params)} buy parameters")
    
    # Test sell parameters
    print("\n🔍 SELL MODEL PARAMETERS:")
    sell_params = {k: v for k, v in params.items() if k.startswith('sell_')}
    print(f"   Found {len(sell_params)} sell parameters")
    
    # Check for key differences
    print("\n🔍 KEY PARAMETER DIFFERENCES:")
    
    # RSI thresholds
    print(f"   RSI Bullish Thresholds:")
    print(f"     Combined: {params.get('combined_rsi_bullish_threshold', 'N/A')}")
    print(f"     Buy: {params.get('buy_rsi_bullish_threshold', 'N/A')}")
    print(f"     Sell: {params.get('sell_rsi_bullish_threshold', 'N/A')}")
    
    print(f"   RSI Bearish Thresholds:")
    print(f"     Combined: {params.get('combined_rsi_bearish_threshold', 'N/A')}")
    print(f"     Buy: {params.get('buy_rsi_bearish_threshold', 'N/A')}")
    print(f"     Sell: {params.get('sell_rsi_bearish_threshold', 'N/A')}")
    
    print(f"   Volume Ratio Thresholds:")
    print(f"     Combined: {params.get('combined_volume_ratio_threshold', 'N/A')}")
    print(f"     Buy: {params.get('buy_volume_ratio_threshold', 'N/A')}")
    print(f"     Sell: {params.get('sell_volume_ratio_threshold', 'N/A')}")
    
    print(f"   Min Prediction Thresholds:")
    print(f"     Combined: {params.get('combined_min_prediction_threshold', 'N/A')}")
    print(f"     Buy: {params.get('buy_min_prediction_threshold', 'N/A')}")
    print(f"     Sell: {params.get('sell_min_prediction_threshold', 'N/A')}")
    
    # Verify all required parameters are present
    required_combined = [
        'combined_rsi_bullish_threshold', 'combined_rsi_bearish_threshold',
        'combined_volume_ratio_threshold', 'combined_min_confidence',
        'combined_max_confidence', 'combined_position_sizing_multiplier'
    ]
    
    required_buy = [
        'buy_rsi_bullish_threshold', 'buy_rsi_bearish_threshold',
        'buy_volume_ratio_threshold', 'buy_min_confidence',
        'buy_max_confidence', 'buy_position_sizing_multiplier'
    ]
    
    required_sell = [
        'sell_rsi_bullish_threshold', 'sell_rsi_bearish_threshold',
        'sell_volume_ratio_threshold', 'sell_min_confidence',
        'sell_max_confidence', 'sell_position_sizing_multiplier'
    ]
    
    print("\n🔍 PARAMETER COMPLETENESS CHECK:")
    
    # Check combined parameters
    missing_combined = [p for p in required_combined if p not in params]
    if missing_combined:
        print(f"   ❌ Missing combined parameters: {missing_combined}")
    else:
        print(f"   ✅ All combined parameters present")
    
    # Check buy parameters
    missing_buy = [p for p in required_buy if p not in params]
    if missing_buy:
        print(f"   ❌ Missing buy parameters: {missing_buy}")
    else:
        print(f"   ✅ All buy parameters present")
    
    # Check sell parameters
    missing_sell = [p for p in required_sell if p not in params]
    if missing_sell:
        print(f"   ❌ Missing sell parameters: {missing_sell}")
    else:
        print(f"   ✅ All sell parameters present")
    
    # Summary
    total_params = len(params)
    print(f"\n📊 SUMMARY:")
    print(f"   Total parameters: {total_params}")
    print(f"   Combined parameters: {len(combined_params)}")
    print(f"   Buy parameters: {len(buy_params)}")
    print(f"   Sell parameters: {len(sell_params)}")
    
    if len(missing_combined) == 0 and len(missing_buy) == 0 and len(missing_sell) == 0:
        print(f"   ✅ All required parameters are present!")
        return True
    else:
        print(f"   ❌ Some required parameters are missing!")
        return False

if __name__ == "__main__":
    success = test_parameter_loading()
    if success:
        print("\n🎉 Parameter loading test PASSED!")
    else:
        print("\n❌ Parameter loading test FAILED!") 