#!/usr/bin/env python3
"""
Batch Dukascopy to MT5 Converter
Processes multiple Dukascopy CSV files and combines them
"""

import os
import glob
import pandas as pd
from datetime import datetime
import argparse
from dukascopy_to_mt5_converter import DukascopyToMT5Converter

class BatchConverter:
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

    def __init__(self, mt5_dir):
        self.mt5_dir = mt5_dir
        self.converter = DukascopyToMT5Converter()
        self.converter.mt5_data_dir = mt5_dir
        
    def find_dukascopy_files(self, directory, pattern="*_Ticks_*.csv"):
        """Find all Dukascopy CSV files in a directory"""
        search_pattern = os.path.join(directory, pattern)
        files = glob.glob(search_pattern)
        return sorted(files)
    
    def extract_symbol_from_filename(self, filename):
        """Extract symbol from Dukascopy filename"""
        basename = os.path.basename(filename)
        # Expected format: SYMBOL_Ticks_DATE-DATE.csv
        parts = basename.split('_')
        if len(parts) >= 2:
            return parts[0]
        return None
    
    def extract_date_from_filename(self, filename):
        """Extract date from Dukascopy filename"""
        basename = os.path.basename(filename)
        # Expected format: SYMBOL_Ticks_DATE-DATE.csv
        parts = basename.split('_')
        if len(parts) >= 3:
            date_part = parts[2].replace('.csv', '')
            return date_part
        return None
    
    def process_single_file(self, csv_file, symbol, timeframe='M1'):
        """Process a single Dukascopy CSV file"""
        print(f"🔄 Processing: {os.path.basename(csv_file)}")
        
        # Read and clean data
        df = self.converter.read_dukascopy_csv(csv_file)
        if df is None:
            print(f"❌ Failed to read {csv_file}")
            return None
        
        # Clean data
        df = self.converter.clean_and_validate_data(df)
        
        # Convert to MT5 format
        mt5_df = self.converter.convert_to_mt5_format(df, symbol, timeframe)
        
        return mt5_df
    
    def combine_dataframes(self, dataframes):
        """Combine multiple dataframes into one"""
        if not dataframes:
            return None
        
        print(f"🔄 Combining {len(dataframes)} datasets...")
        
        # Combine all dataframes
        combined_df = pd.concat(dataframes, ignore_index=True)
        
        # Sort by time
        combined_df = combined_df.sort_values('Time').reset_index(drop=True)
        
        # Remove duplicates
        combined_df = combined_df.drop_duplicates(subset=['Time'])
        
        print(f"✅ Combined {len(combined_df)} total records")
        return combined_df
    
    def save_combined_data(self, df, symbol, timeframe='M1'):
        """Save combined data in MT5 format"""
        if df is None or len(df) == 0:
            print("❌ No data to save")
            return None
        
        # Create symbol directory
        symbol_dir = os.path.join(self.mt5_dir, symbol)
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
        
        print(f"✅ Saved combined MT5 data: {filepath}")
        print(f"📊 File size: {os.path.getsize(filepath) / 1024:.1f} KB")
        
        return filepath
    
    def create_import_script(self, symbol, filepath):
        """Create import script for the combined data"""
        script_content = f"""
//+------------------------------------------------------------------+
//| Import Combined Dukascopy Data Script                            |
//+------------------------------------------------------------------+
#property copyright "Auto-generated"
#property version   "1.00"
#property script_show_inputs

void OnStart()
{{
    string symbol = "{symbol}";
    string filename = "{os.path.basename(filepath)}";
    
    Print("=== Combined Dukascopy Data Import Instructions ===");
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
    Print("✅ Data file location: Files/", symbol, "/", filename);
    Print("📊 Combined data from multiple days");
    Print("================================");
}}
"""
        
        script_path = os.path.join(self.mt5_dir, "Scripts", "ImportCombinedData.mq5")
        os.makedirs(os.path.dirname(script_path), exist_ok=True)
        
        with open(script_path, 'w') as f:
            f.write(script_content)
        
        print(f"✅ Created import script: {script_path}")
        return script_path
    
    def process_directory(self, directory, symbol=None, timeframe='M1'):
        """Process all Dukascopy files in a directory"""
        print(f"🚀 Starting batch conversion for directory: {directory}")
        
        # Find all CSV files
        csv_files = self.find_dukascopy_files(directory)
        
        if not csv_files:
            print(f"❌ No Dukascopy CSV files found in {directory}")
            return False
        
        print(f"📁 Found {len(csv_files)} CSV files:")
        for file in csv_files:
            print(f"   📄 {os.path.basename(file)}")
        
        # Group files by symbol
        symbol_files = {}
        for file in csv_files:
            file_symbol = self.extract_symbol_from_filename(file)
            if file_symbol:
                if file_symbol not in symbol_files:
                    symbol_files[file_symbol] = []
                symbol_files[file_symbol].append(file)
        
        print(f"\n📊 Files grouped by symbol:")
        for sym, files in symbol_files.items():
            print(f"   {sym}: {len(files)} files")
        
        # Process each symbol
        for sym, files in symbol_files.items():
            if symbol and sym != symbol:
                continue  # Skip if specific symbol requested
                
            print(f"\n🎯 Processing symbol: {sym}")
            
            # Process each file
            dataframes = []
            for file in files:
                df = self.process_single_file(file, sym, timeframe)
                if df is not None:
                    dataframes.append(df)
            
            if dataframes:
                # Combine all dataframes
                combined_df = self.combine_dataframes(dataframes)
                
                if combined_df is not None:
                    # Save combined data
                    filepath = self.save_combined_data(combined_df, sym, timeframe)
                    
                    if filepath:
                        # Create import script
                        script_path = self.create_import_script(sym, filepath)
                        
                        print(f"\n🎉 Batch conversion complete for {sym}!")
                        print(f"📁 Combined data: {filepath}")
                        print(f"📜 Import script: {script_path}")
                        print(f"📊 Total records: {len(combined_df)}")
                        
                        # Show date range
                        if len(combined_df) > 0:
                            first_time = pd.to_datetime(combined_df['Time'].iloc[0], unit='s')
                            last_time = pd.to_datetime(combined_df['Time'].iloc[-1], unit='s')
                            print(f"📅 Date range: {first_time} to {last_time}")
            else:
                print(f"❌ No valid data found for {sym}")
        
        return True

def main():
    parser = argparse.ArgumentParser(description='Batch convert Dukascopy CSV files to MT5 format')
    parser.add_argument('directory', help='Directory containing Dukascopy CSV files')
    parser.add_argument('--symbol', help='Specific symbol to process (optional)')
    parser.add_argument('--timeframe', default='M1', 
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Target timeframe (default: M1)')
    parser.add_argument('--mt5-dir', help='MT5 data directory path')
    
    args = parser.parse_args()
    
    # Validate directory
    if not os.path.exists(args.directory):
        print(f"❌ Directory not found: {args.directory}")
        return 1
    
    # Set MT5 directory
    mt5_dir = args.mt5_dir
    if not mt5_dir:
        # Try to find MT5 directory automatically
        converter = DukascopyToMT5Converter()
        if converter.find_mt5_data_directory():
            mt5_dir = converter.mt5_data_dir
        else:
            print("❌ Please specify MT5 data directory with --mt5-dir")
            return 1
    
    # Initialize batch converter
    batch_converter = BatchConverter(mt5_dir)
    
    # Process directory
    success = batch_converter.process_directory(args.directory, args.symbol, args.timeframe)
    
    if success:
        print(f"\n🎉 Batch conversion completed successfully!")
        print(f"📋 Next steps:")
        print(f"1. Copy the import script to your MT5 Scripts folder")
        print(f"2. Run the script in MT5 to import the combined data")
        print(f"3. Verify the data in MT5's History Center")
    else:
        print(f"\n❌ Batch conversion failed")
    
    return 0 if success else 1

if __name__ == "__main__":
    import sys
    sys.exit(main()) 