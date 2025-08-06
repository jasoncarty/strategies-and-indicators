#!/usr/bin/env python3
"""
Historical Data Downloader
Downloads forex data from multiple free sources
"""

import pandas as pd
import requests
import os
import sys
import argparse
from datetime import datetime, timedelta
import time
from pathlib import Path

class HistoricalDataDownloader:
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
        self.data_dir = "historical_data"
        os.makedirs(self.data_dir, exist_ok=True)
        
    def download_from_histdata(self, symbol, start_date, end_date, timeframe='1m'):
        """
        Download from HistData.com (free tier)
        """
        print(f"📥 Downloading {symbol} from HistData.com...")
        
        # HistData format mapping
        timeframe_map = {
            '1m': '1m',
            '5m': '5m', 
            '15m': '15m',
            '30m': '30m',
            '1h': '1h',
            '4h': '4h',
            '1d': '1d'
        }
        
        tf = timeframe_map.get(timeframe, '1m')
        
        # HistData URL format
        base_url = "https://www.histdata.com/download-free-forex-data"
        
        # For now, provide instructions
        print(f"📋 HistData.com Instructions:")
        print(f"1. Go to: {base_url}")
        print(f"2. Select: {symbol}")
        print(f"3. Select: {tf} timeframe")
        print(f"4. Select: {start_date} to {end_date}")
        print(f"5. Download and extract CSV files")
        print(f"6. Use our converter to process them")
        
        return False  # Manual download required
    
    def download_from_truefx(self, symbol, start_date, end_date):
        """
        Download from TrueFX (free tier)
        """
        print(f"📥 Downloading {symbol} from TrueFX...")
        
        # TrueFX provides monthly files
        print(f"📋 TrueFX Instructions:")
        print(f"1. Go to: https://www.truefx.com/market-data-free/")
        print(f"2. Download monthly files for {symbol}")
        print(f"3. Extract and combine CSV files")
        print(f"4. Use our converter to process them")
        
        return False  # Manual download required
    
    def download_from_yahoo_finance(self, symbol, start_date, end_date):
        """
        Download from Yahoo Finance (free)
        """
        print(f"📥 Downloading {symbol} from Yahoo Finance...")
        
        try:
            # Convert forex symbol to Yahoo format
            yahoo_symbol = f"{symbol}=X"  # e.g., EURUSD=X
            
            # Download data
            url = f"https://query1.finance.yahoo.com/v8/finance/chart/{yahoo_symbol}?period1={int(start_date.timestamp())}&period2={int(end_date.timestamp())}&interval=1m"
            
            response = requests.get(url)
            if response.status_code == 200:
                data = response.json()
                
                if 'chart' in data and 'result' in data['chart'] and data['chart']['result']:
                    result = data['chart']['result'][0]
                    
                    # Extract OHLCV data
                    timestamps = result['timestamp']
                    quotes = result['indicators']['quote'][0]
                    
                    df = pd.DataFrame({
                        'DateTime': pd.to_datetime(timestamps, unit='s'),
                        'Open': quotes['open'],
                        'High': quotes['high'],
                        'Low': quotes['low'],
                        'Close': quotes['close'],
                        'Volume': quotes['volume']
                    })
                    
                    # Remove NaN values
                    df = df.dropna()
                    
                    if len(df) > 0:
                        filename = f"{symbol}_yahoo_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.csv"
                        filepath = os.path.join(self.data_dir, filename)
                        df.to_csv(filepath, index=False)
                        
                        print(f"✅ Downloaded {len(df)} records to {filepath}")
                        return filepath
                    else:
                        print("❌ No data found")
                        return None
                else:
                    print("❌ No data available for this symbol/date range")
                    return None
                    
        except Exception as e:
            print(f"❌ Error downloading from Yahoo Finance: {e}")
            return None
    
    def download_from_alpha_vantage(self, symbol, start_date, end_date):
        """
        Download from Alpha Vantage (free tier - 5 calls per minute)
        """
        print(f"📥 Downloading {symbol} from Alpha Vantage...")
        
        # Alpha Vantage requires API key
        api_key = os.getenv('ALPHA_VANTAGE_API_KEY')
        if not api_key:
            print("❌ Alpha Vantage API key not found")
            print("📋 To use Alpha Vantage:")
            print("1. Get free API key from: https://www.alphavantage.co/support/#api-key")
            print("2. Set environment variable: export ALPHA_VANTAGE_API_KEY=your_key")
            return None
        
        try:
            # Alpha Vantage forex endpoint
            url = f"https://www.alphavantage.co/query?function=FX_INTRADAY&from_symbol={symbol[:3]}&to_symbol={symbol[3:6]}&interval=1min&apikey={api_key}"
            
            response = requests.get(url)
            if response.status_code == 200:
                data = response.json()
                
                if 'Time Series FX (1min)' in data:
                    time_series = data['Time Series FX (1min)']
                    
                    records = []
                    for timestamp, values in time_series.items():
                        dt = pd.to_datetime(timestamp)
                        if start_date <= dt <= end_date:
                            records.append({
                                'DateTime': dt,
                                'Open': float(values['1. open']),
                                'High': float(values['2. high']),
                                'Low': float(values['3. low']),
                                'Close': float(values['4. close']),
                                'Volume': 0  # Alpha Vantage doesn't provide volume for forex
                            })
                    
                    if records:
                        df = pd.DataFrame(records)
                        filename = f"{symbol}_alphavantage_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.csv"
                        filepath = os.path.join(self.data_dir, filename)
                        df.to_csv(filepath, index=False)
                        
                        print(f"✅ Downloaded {len(df)} records to {filepath}")
                        return filepath
                    else:
                        print("❌ No data found for specified date range")
                        return None
                else:
                    print("❌ No data available for this symbol")
                    return None
                    
        except Exception as e:
            print(f"❌ Error downloading from Alpha Vantage: {e}")
            return None
    
    def combine_csv_files(self, pattern, output_file):
        """
        Combine multiple CSV files into one
        """
        print(f"🔄 Combining CSV files matching pattern: {pattern}")
        
        import glob
        csv_files = glob.glob(pattern)
        
        if not csv_files:
            print("❌ No CSV files found matching pattern")
            return None
        
        print(f"📁 Found {len(csv_files)} files to combine")
        
        combined_df = pd.DataFrame()
        
        for file in sorted(csv_files):
            print(f"📖 Reading {file}...")
            try:
                df = pd.read_csv(file)
                combined_df = pd.concat([combined_df, df], ignore_index=True)
            except Exception as e:
                print(f"❌ Error reading {file}: {e}")
        
        if len(combined_df) > 0:
            # Sort by datetime
            combined_df['DateTime'] = pd.to_datetime(combined_df['DateTime'])
            combined_df = combined_df.sort_values('DateTime').reset_index(drop=True)
            
            # Remove duplicates
            combined_df = combined_df.drop_duplicates(subset=['DateTime'])
            
            # Save combined file
            combined_df.to_csv(output_file, index=False)
            
            print(f"✅ Combined {len(combined_df)} records to {output_file}")
            return output_file
        else:
            print("❌ No data to combine")
            return None
    
    def download_comprehensive_data(self, symbol, start_date, end_date, sources=['yahoo', 'histdata', 'truefx']):
        """
        Download data from multiple sources
        """
        print(f"🚀 Starting comprehensive data download for {symbol}")
        print(f"📅 Date range: {start_date} to {end_date}")
        print(f"📊 Sources: {', '.join(sources)}")
        
        downloaded_files = []
        
        for source in sources:
            print(f"\n--- {source.upper()} ---")
            
            if source == 'yahoo':
                file = self.download_from_yahoo_finance(symbol, start_date, end_date)
                if file:
                    downloaded_files.append(file)
                    
            elif source == 'histdata':
                self.download_from_histdata(symbol, start_date, end_date)
                
            elif source == 'truefx':
                self.download_from_truefx(symbol, start_date, end_date)
                
            elif source == 'alphavantage':
                file = self.download_from_alpha_vantage(symbol, start_date, end_date)
                if file:
                    downloaded_files.append(file)
            
            # Rate limiting
            time.sleep(1)
        
        print(f"\n📊 Download Summary:")
        print(f"✅ Downloaded files: {len(downloaded_files)}")
        for file in downloaded_files:
            print(f"   📁 {file}")
        
        return downloaded_files

def main():
    parser = argparse.ArgumentParser(description='Download historical forex data from multiple sources')
    parser.add_argument('symbol', help='Symbol name (e.g., EURUSD)')
    parser.add_argument('--start-date', default='2024-01-01', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end-date', default='2024-12-31', help='End date (YYYY-MM-DD)')
    parser.add_argument('--sources', nargs='+', default=['yahoo'], 
                       choices=['yahoo', 'histdata', 'truefx', 'alphavantage'],
                       help='Data sources to use')
    
    args = parser.parse_args()
    
    # Parse dates
    start_date = datetime.strptime(args.start_date, '%Y-%m-%d')
    end_date = datetime.strptime(args.end_date, '%Y-%m-%d')
    
    # Initialize downloader
    downloader = HistoricalDataDownloader()
    
    # Download data
    files = downloader.download_comprehensive_data(args.symbol, start_date, end_date, args.sources)
    
    if files:
        print(f"\n🎉 Download complete!")
        print(f"📋 Next steps:")
        print(f"1. Use our converter to process the downloaded files")
        print(f"2. Import the converted data into MT5")
        print(f"3. Run your EA backtests with the comprehensive data")
    else:
        print(f"\n❌ No data downloaded")
        print(f"📋 Try manual downloads from the sources mentioned above")

if __name__ == "__main__":
    main() 