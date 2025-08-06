#!/usr/bin/env python3
"""
Test script to verify dynamic ML parameter file loading
"""

import os
import glob

def test_dynamic_file_loading():
    """Test dynamic file loading for different symbols"""
    
    # MetaTrader directory
    mt5_dir = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA"
    
    # Test symbols (including some with + suffix)
    test_symbols = [
        "EURUSD",
        "EURUSD+", 
        "GBPUSD",
        "GBPUSD+",
        "USDJPY",
        "USDJPY+",
        "USDCAD",
        "USDCAD+",
        "EURJPY",
        "EURJPY+",
        "XAUUSD",
        "XAUUSD+",
        "NAS100",  # Should fall back to generic
        "SP500",   # Should fall back to generic
        "UNKNOWN"  # Should fall back to generic
    ]
    
    print("🧪 Testing Dynamic ML Parameter File Loading")
    print("=" * 60)
    
    for symbol in test_symbols:
        # Clean symbol name (remove + suffix)
        base_symbol = symbol.replace("+", "")
        
        # Try symbol-specific file first
        symbol_specific_file = f"ml_model_params_{base_symbol}.txt"
        symbol_specific_path = os.path.join(mt5_dir, symbol_specific_file)
        
        # Try generic file as fallback
        generic_file = "ml_model_params_simple.txt"
        generic_path = os.path.join(mt5_dir, generic_file)
        
        # Check which file exists
        if os.path.exists(symbol_specific_path):
            print(f"✅ {symbol:10} -> {symbol_specific_file} (symbol-specific)")
        elif os.path.exists(generic_path):
            print(f"🔄 {symbol:10} -> {generic_file} (generic fallback)")
        else:
            print(f"❌ {symbol:10} -> NO FILE FOUND")
    
    print("\n📊 Summary:")
    print(f"📁 MetaTrader directory: {mt5_dir}")
    
    # List all available parameter files
    param_files = glob.glob(os.path.join(mt5_dir, "ml_model_params_*.txt"))
    print(f"📁 Total parameter files available: {len(param_files)}")
    
    print("\n📋 Available parameter files:")
    for file_path in sorted(param_files):
        filename = os.path.basename(file_path)
        print(f"   - {filename}")

if __name__ == "__main__":
    test_dynamic_file_loading() 