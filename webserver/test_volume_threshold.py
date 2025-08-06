#!/usr/bin/env python3
"""
Test Volume Threshold Function
Verifies that the ML volume thresholds are correctly generated and accessible
"""

import os
import json

def test_volume_thresholds():
    """Test volume threshold generation and accessibility"""
    print("🧪 Testing Volume Threshold Function")
    print("=" * 50)
    
    # Test symbols
    test_symbols = ['EURUSD', 'GBPUSD', 'USDCAD']
    
    for symbol in test_symbols:
        param_file = f"ml_models/ml_model_params_{symbol}.txt"
        
        if os.path.exists(param_file):
            print(f"✅ {symbol}: Parameter file exists")
            
            # Read volume threshold
            volume_threshold = None
            with open(param_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('combined_volume_ratio_threshold='):
                        volume_threshold = float(line.split('=')[1])
                        break
            
            if volume_threshold is not None:
                print(f"   📊 Volume threshold: {volume_threshold:.2f}")
                
                # Check if it's optimized
                if volume_threshold < 1.2:
                    print(f"   🎯 {symbol}: Using optimized volume threshold ({volume_threshold:.2f})")
                    print(f"      This means {symbol} performs better with lower volume conditions")
                else:
                    print(f"   ⚠️  {symbol}: Using default volume threshold")
            else:
                print(f"   ❌ {symbol}: Volume threshold not found in parameter file")
        else:
            print(f"❌ {symbol}: Parameter file not found")
    
    print("\n📋 Summary:")
    print("The EA should now use these symbol-specific volume thresholds")
    print("for volume confirmation instead of the hardcoded 1.2 ratio.")
    print("Lower thresholds mean the symbol performs better with lower volume conditions.")

if __name__ == "__main__":
    test_volume_thresholds() 