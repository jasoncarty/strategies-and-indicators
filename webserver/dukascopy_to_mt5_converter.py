#!/usr/bin/env python3
"""
Dukascopy to MT5 Tick Data Converter
Converts Dukascopy CSV tick data to MT5-compatible format
"""

import pandas as pd
import numpy as np
import os
import sys
import argparse
from datetime import datetime, timedelta
import pytz
from pathlib import Path

class DukascopyToMT5Converter:
    def _extract_symbol_from_path(self, file_path: Path) -> str:
        """Extract symbol from file path dynamically"""
        # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
        path_parts = file_path.parts
        for i, part in enumerate(path_parts):
            if part in ['Models', 'BreakoutStrategy'] and i + 1 < len(path_parts):
                potential_symbol = path_parts[i + 1]
                # Check if it looks like a symbol (6 characters, mostly letters)
                if len(potential_symbol) == 6 and potential_symbol.isalpha():
                    return potential_symbol

        # Try to extract from filename
        filename = file_path.name
        # Look for patterns like buy_EURUSD_PERIOD_H1.pkl
        symbol_match = re.search(r'[a-z]+_([A-Z]{6})_PERIOD_', filename)
        if symbol_match:
            return symbol_match.group(1)

        # Default fallback
        return "UNKNOWN_SYMBOL"

    def __init__(self):
        self.utc_tz = pytz.UTC
        self.mt5_data_dir = None
        
    def find_mt5_data_directory(self):
        """Find MT5 data directory on Mac"""
        possible_paths = [
            os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/*/MQL5/Files"),
            os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/*/MQL5/History"),
            os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/*/MQL5/Common/Files"),
        ]
        
        for path_pattern in possible_paths:
            import glob
            matches = glob.glob(path_pattern)
            if matches:
                # Use the first match (most recent terminal)
                self.mt5_data_dir = matches[0]
                print(f"✅ Found MT5 data directory: {self.mt5_data_dir}")
                return True
        
        print("❌ Could not find MT5 data directory automatically")
        return False
    
    def read_dukascopy_csv(self, csv_file):
        """Read Dukascopy CSV file and parse it correctly"""
        print(f"📖 Reading Dukascopy CSV: {csv_file}")
        
        try:
            # First, let's check if there's a header row
            with open(csv_file, 'r') as f:
                first_line = f.readline().strip()
            
            # Check if first line contains header text
            has_header = any(keyword in first_line.lower() for keyword in ['time', 'bid', 'ask', 'volume', 'local'])
            
            if has_header:
                print("📋 Detected header row, skipping...")
                # Read with header
                df = pd.read_csv(csv_file, header=0)
                
                # Handle volume columns properly
                if 'AskVolume' in df.columns and 'BidVolume' in df.columns:
                    # Sum the volumes
                    df['Volume'] = df['AskVolume'] + df['BidVolume']
                    # Drop the original volume columns
                    df = df.drop(['AskVolume', 'BidVolume'], axis=1)
                elif 'Volume' in df.columns:
                    # Keep existing Volume column
                    pass
                else:
                    # Create a default volume column
                    df['Volume'] = 1.0
                
                # Rename datetime column
                if 'Local time' in df.columns:
                    df = df.rename(columns={'Local time': 'DateTime'})
                
                # Parse datetime - handle timezone format
                def parse_datetime_with_timezone(dt_str):
                    # Remove timezone info and parse
                    if 'GMT' in dt_str:
                        # Extract the datetime part before GMT
                        dt_part = dt_str.split(' GMT')[0]
                        return pd.to_datetime(dt_part, format='%d.%m.%Y %H:%M:%S.%f')
                    else:
                        return pd.to_datetime(dt_str, format='%d.%m.%Y %H:%M:%S.%f')
                
                df['DateTime'] = df['DateTime'].apply(parse_datetime_with_timezone)
                
            else:
                # No header, use standard Dukascopy format
                df = pd.read_csv(csv_file, header=None, 
                               names=['Date', 'Time', 'Bid', 'Ask', 'Volume'])
                
                # Combine date and time
                df['DateTime'] = pd.to_datetime(df['Date'] + ' ' + df['Time'], 
                                              format='%Y.%m.%d %H:%M:%S.%f')
            
            print(f"✅ Loaded {len(df)} tick records")
            print(f"📅 Date range: {df['DateTime'].min()} to {df['DateTime'].max()}")
            print(f"📊 Columns: {list(df.columns)}")
            
            return df
            
        except Exception as e:
            print(f"❌ Error reading CSV: {e}")
            print(f"🔍 Let's examine the first few lines of the file...")
            
            # Show first few lines for debugging
            try:
                with open(csv_file, 'r') as f:
                    for i, line in enumerate(f):
                        if i < 5:  # Show first 5 lines
                            print(f"   Line {i+1}: {line.strip()}")
                        else:
                            break
            except Exception as debug_e:
                print(f"   Could not read file for debugging: {debug_e}")
            
            return None
    
    def clean_and_validate_data(self, df):
        """Clean and validate the tick data"""
        print("🧹 Cleaning and validating data...")
        
        initial_count = len(df)
        
        # Remove rows with invalid prices
        df = df[(df['Bid'] > 0) & (df['Ask'] > 0) & (df['Bid'] < df['Ask'])]
        
        # Remove rows with invalid volume
        df = df[df['Volume'] >= 0]
        
        # Remove duplicate timestamps (keep first occurrence)
        df = df.drop_duplicates(subset=['DateTime'], keep='first')
        
        # Sort by datetime
        df = df.sort_values('DateTime').reset_index(drop=True)
        
        # Calculate spread
        df['Spread'] = df['Ask'] - df['Bid']
        
        # Remove extreme spreads (likely data errors)
        spread_threshold = df['Spread'].quantile(0.99) * 2  # 2x 99th percentile
        df = df[df['Spread'] <= spread_threshold]
        
        final_count = len(df)
        removed_count = initial_count - final_count
        
        print(f"✅ Data cleaning complete:")
        print(f"   Initial records: {initial_count}")
        print(f"   Final records: {final_count}")
        print(f"   Removed records: {removed_count} ({removed_count/initial_count*100:.1f}%)")
        
        return df
    
    def convert_to_mt5_format(self, df, symbol, timeframe='M1'):
        """Convert tick data to MT5 candle format"""
        print(f"🔄 Converting to MT5 {timeframe} format for {symbol}...")
        
        # Ensure datetime is timezone-aware (UTC)
        if df['DateTime'].dt.tz is None:
            df['DateTime'] = df['DateTime'].dt.tz_localize('UTC')
        
        # Resample to desired timeframe
        if timeframe == 'M1':
            freq = '1T'  # 1 minute
        elif timeframe == 'M5':
            freq = '5T'  # 5 minutes
        elif timeframe == 'M15':
            freq = '15T'  # 15 minutes
        elif timeframe == 'M30':
            freq = '30T'  # 30 minutes
        elif timeframe == 'H1':
            freq = '1H'  # 1 hour
        elif timeframe == 'H4':
            freq = '4H'  # 4 hours
        elif timeframe == 'D1':
            freq = '1D'  # 1 day
        else:
            freq = '1T'  # Default to 1 minute
        
        # Create OHLCV data
        ohlcv = df.set_index('DateTime').resample(freq).agg({
            'Bid': 'ohlc',  # Open, High, Low, Close from Bid prices
            'Ask': 'ohlc',  # Open, High, Low, Close from Ask prices
            'Volume': 'sum'
        })
        
        # Flatten column names
        ohlcv.columns = ['Bid_Open', 'Bid_High', 'Bid_Low', 'Bid_Close',
                        'Ask_Open', 'Ask_High', 'Ask_Low', 'Ask_Close',
                        'Volume']
        
        # Calculate mid-price OHLCV (most common approach)
        ohlcv['Open'] = (ohlcv['Bid_Open'] + ohlcv['Ask_Open']) / 2
        ohlcv['High'] = (ohlcv['Bid_High'] + ohlcv['Ask_High']) / 2
        ohlcv['Low'] = (ohlcv['Bid_Low'] + ohlcv['Ask_Low']) / 2
        ohlcv['Close'] = (ohlcv['Bid_Close'] + ohlcv['Ask_Close']) / 2
        
        # Remove rows with no data
        ohlcv = ohlcv.dropna()
        
        # Convert to integer timestamps (MT5 format)
        ohlcv['Time'] = ohlcv.index.astype(np.int64) // 10**9
        
        # Select final columns
        result = ohlcv[['Time', 'Open', 'High', 'Low', 'Close', 'Volume']].copy()
        
        print(f"✅ Converted to {len(result)} {timeframe} candles")
        print(f"📅 Date range: {result.index.min()} to {result.index.max()}")
        
        return result
    
    def save_mt5_format(self, df, symbol, timeframe='M1'):
        """Save data in MT5 format"""
        if not self.mt5_data_dir:
            print("❌ MT5 data directory not found")
            return False
        
        # Create symbol directory
        symbol_dir = os.path.join(self.mt5_data_dir, symbol)
        os.makedirs(symbol_dir, exist_ok=True)
        
        # Determine file extension based on timeframe
        timeframe_map = {
            'M1': '1', 'M5': '5', 'M15': '15', 'M30': '30',
            'H1': '60', 'H4': '240', 'D1': '1440'
        }
        
        file_ext = timeframe_map.get(timeframe, '1')
        filename = f"{symbol}{file_ext}.csv"
        filepath = os.path.join(symbol_dir, filename)
        
        # Save in MT5 format
        df.to_csv(filepath, index=False, header=False)
        
        print(f"✅ Saved MT5 data: {filepath}")
        print(f"📊 File size: {os.path.getsize(filepath) / 1024:.1f} KB")
        
        return filepath
    
    def create_import_script(self, symbol, filepath):
        """Create an MQL5 script to import the data"""
        script_content = f"""
//+------------------------------------------------------------------+
//| Import Dukascopy Data Script                                     |
//+------------------------------------------------------------------+
#property copyright "Auto-generated"
#property version   "1.00"
#property script_show_inputs

void OnStart()
{{
    string symbol = "{symbol}";
    string filename = "{os.path.basename(filepath)}";
    
    Print("=== Dukascopy Data Import Instructions ===");
    Print("Symbol: ", symbol);
    Print("Data file: ", filename);
    Print("");
    Print("📋 Manual Import Steps:");
    Print("1. Go to View → History Center");
    Print("2. Select symbol: ", symbol);
    Print("3. Select timeframe: H1");
    Print("4. Click 'Import' button");
    Print("5. Navigate to the Files directory");
    Print("6. Select file: ", filename);
    Print("7. Configure import settings:");
    Print("   - Date format: YYYY.MM.DD");
    Print("   - Time format: HH:MM:SS");
    Print("   - Separator: Comma");
    Print("   - Skip first line: Yes");
    Print("8. Click 'OK' to import");
    Print("");
    Print("✅ Data file location: Files/USDJPY+/", filename);
    Print("📊 Expected data: 24 H1 candles for July 14, 2025");
    Print("================================");
}}
"""
        
        if self.mt5_data_dir is None:
            print("❌ MT5 data directory not found")
            return None
        script_path = os.path.join(self.mt5_data_dir, "Scripts", "ImportDukascopyData.mq5")
        os.makedirs(os.path.dirname(script_path), exist_ok=True)
        
        with open(script_path, 'w') as f:
            f.write(script_content)
        
        print(f"✅ Created import script: {script_path}")
        return script_path
    
    def convert_file(self, csv_file, symbol, timeframe='M1'):
        """Main conversion function"""
        print(f"🚀 Starting conversion: {csv_file} -> {symbol} ({timeframe})")
        
        # Read CSV
        df = self.read_dukascopy_csv(csv_file)
        if df is None:
            return False
        
        # Clean data
        df = self.clean_and_validate_data(df)
        
        # Convert to MT5 format
        mt5_df = self.convert_to_mt5_format(df, symbol, timeframe)
        
        # Save MT5 format
        filepath = self.save_mt5_format(mt5_df, symbol, timeframe)
        if not filepath:
            return False
        
        # Create import script
        script_path = self.create_import_script(symbol, filepath)
        
        print(f"\n🎉 Conversion complete!")
        print(f"📁 MT5 data file: {filepath}")
        print(f"📜 Import script: {script_path}")
        print(f"\n📋 Next steps:")
        print(f"1. Copy the import script to your MT5 Scripts folder")
        print(f"2. Run the script in MT5 to import the data")
        print(f"3. Verify the data in MT5's History Center")
        
        return True

def main():
    parser = argparse.ArgumentParser(description='Convert Dukascopy CSV to MT5 format')
    parser.add_argument('csv_file', help='Path to Dukascopy CSV file')
    parser.add_argument('symbol', help='Symbol name (e.g., EURUSD)')
    parser.add_argument('--timeframe', default='M1', 
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Target timeframe (default: M1)')
    parser.add_argument('--mt5-dir', help='Custom MT5 data directory path')
    
    args = parser.parse_args()
    
    # Validate input file
    if not os.path.exists(args.csv_file):
        print(f"❌ CSV file not found: {args.csv_file}")
        return 1
    
    # Initialize converter
    converter = DukascopyToMT5Converter()
    
    # Set MT5 directory
    if args.mt5_dir:
        converter.mt5_data_dir = args.mt5_dir
    else:
        if not converter.find_mt5_data_directory():
            print("❌ Please specify MT5 data directory with --mt5-dir")
            return 1
    
    # Perform conversion
    success = converter.convert_file(args.csv_file, args.symbol, args.timeframe)
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main()) 