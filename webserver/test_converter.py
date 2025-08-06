#!/usr/bin/env python3
"""
Test script for Dukascopy to MT5 converter
"""

import os
import sys
from dukascopy_to_mt5_converter import DukascopyToMT5Converter

def test_converter():
    """Test the converter with sample data"""
    
    # Find CSV files in current directory
    csv_files = [f for f in os.listdir('.') if f.endswith('.csv')]
    
    if not csv_files:
        print("❌ No CSV files found in current directory")
        print("📋 Please place your Dukascopy CSV file in this directory")
        return
    
    print("📁 Found CSV files:")
    for i, file in enumerate(csv_files, 1):
        print(f"   {i}. {file}")
    
    # Let user choose file
    if len(csv_files) == 1:
        csv_file = csv_files[0]
        print(f"✅ Using: {csv_file}")
    else:
        try:
            choice = int(input(f"Choose file (1-{len(csv_files)}): ")) - 1
            csv_file = csv_files[choice]
        except (ValueError, IndexError):
            print("❌ Invalid choice")
            return
    
    # Get symbol name
    symbol = input("Enter symbol name (e.g., EURUSD): ").strip().upper()
    if not symbol:
        print("❌ Symbol name required")
        return
    
    # Get timeframe
    timeframes = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1']
    print("Available timeframes:")
    for i, tf in enumerate(timeframes, 1):
        print(f"   {i}. {tf}")
    
    try:
        tf_choice = int(input(f"Choose timeframe (1-{len(timeframes)}): ")) - 1
        timeframe = timeframes[tf_choice]
    except (ValueError, IndexError):
        timeframe = 'M1'
        print(f"✅ Using default timeframe: {timeframe}")
    
    # Initialize converter
    converter = DukascopyToMT5Converter()
    
    # Try to find MT5 directory
    if not converter.find_mt5_data_directory():
        print("❌ Could not find MT5 directory automatically")
        mt5_dir = input("Enter MT5 data directory path: ").strip()
        if mt5_dir:
            converter.mt5_data_dir = mt5_dir
        else:
            print("❌ MT5 directory required")
            return
    
    # Perform conversion
    print(f"\n🚀 Starting conversion...")
    success = converter.convert_file(csv_file, symbol, timeframe)
    
    if success:
        print(f"\n🎉 Conversion successful!")
        print(f"📋 Next steps:")
        print(f"1. Open MT5")
        print(f"2. Go to View → History Center")
        print(f"3. Select {symbol} and verify the imported data")
        print(f"4. Run your EA backtest with the new data")
    else:
        print(f"\n❌ Conversion failed")

if __name__ == "__main__":
    test_converter() 