#!/usr/bin/env python3
"""
Test ML Parameter Loading
Verifies that ML parameters are correctly loaded and optimized
"""

import os
import glob

def test_parameter_loading():
    """Test parameter loading for different symbols"""
    print("🧪 Testing ML Parameter Loading")
    print("=" * 50)
    
    # Test symbols
    test_symbols = ['EURUSD', 'GBPUSD', 'USDCAD']
    
    for symbol in test_symbols:
        param_file = f"ml_models/ml_model_params_{symbol}.txt"
        
        if os.path.exists(param_file):
            print(f"✅ {symbol}: Parameter file exists")
            
            # Read parameters
            params = {}
            with open(param_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line:
                        key, value = line.split('=', 1)
                        params[key] = value
            
            # Display key parameters
            print(f"   📊 Key parameters for {symbol}:")
            print(f"      combined_min_prediction_threshold: {params.get('combined_min_prediction_threshold', 'MISSING')}")
            print(f"      combined_max_prediction_threshold: {params.get('combined_max_prediction_threshold', 'MISSING')}")
            print(f"      combined_min_confidence: {params.get('combined_min_confidence', 'MISSING')}")
            print(f"      combined_max_confidence: {params.get('combined_max_confidence', 'MISSING')}")
            print(f"      combined_volume_ratio_threshold: {params.get('combined_volume_ratio_threshold', 'MISSING')}")
            
            # Check if using optimized thresholds
            min_threshold = float(params.get('combined_min_prediction_threshold', '0.55'))
            if min_threshold < 0.55:
                print(f"   ✅ {symbol}: Using optimized prediction threshold")
            else:
                print(f"   ⚠️  {symbol}: Using default prediction threshold")
                
            # Check volume threshold
            volume_threshold = float(params.get('combined_volume_ratio_threshold', '1.2'))
            if volume_threshold < 1.2:
                print(f"   🎯 {symbol}: Using optimized volume threshold ({volume_threshold:.2f})")
            else:
                print(f"   ⚠️  {symbol}: Using default volume threshold")
        else:
            print(f"❌ {symbol}: Parameter file not found")
    
    print("\n📋 Summary:")
    print("The EA should be using these parameters for trade decisions.")
    print("If all parameters are default values (0.55, 0.45, etc.),")
    print("the ML training may not be providing significant optimization.")

if __name__ == "__main__":
    test_parameter_loading() 