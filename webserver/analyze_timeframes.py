#!/usr/bin/env python3
"""
Analyze timeframe distribution in ML data
"""

import pandas as pd
import json
import glob
import os

def analyze_timeframes():
    """Analyze timeframe distribution in ML data"""
    print("🔍 Analyzing timeframe distribution in ML data...")

    # Find all ML data files
    data_files = glob.glob('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/*/SimpleBreakoutML_EA_ML_Data.json')

    if not data_files:
        print("❌ No ML data files found")
        return

    print(f"📁 Found {len(data_files)} ML data files")

    all_trades = []
    timeframes = set()

    for file in data_files:
        try:
            with open(file, 'r') as f:
                data = json.load(f)

            if 'trades' in data:
                trades = data['trades']
                all_trades.extend(trades)

                # Extract timeframes
                for trade in trades:
                    timeframe = trade.get('timeframe', 'unknown')
                    timeframes.add(timeframe)

        except Exception as e:
            print(f"❌ Error reading {file}: {e}")

    print(f"\n📊 Timeframes found: {sorted(timeframes)}")
    print(f"📊 Total trades: {len(all_trades)}")

    if not all_trades:
        print("❌ No trades found")
        return

    # Create DataFrame
    df = pd.DataFrame(all_trades)

    print(f"\n📊 Timeframe distribution:")
    if 'timeframe' in df.columns:
        timeframe_dist = df['timeframe'].value_counts()
        print(timeframe_dist)

        print(f"\n📊 Success rate by timeframe:")
        if 'trade_success' in df.columns:
            success_by_timeframe = df.groupby('timeframe')['trade_success'].agg(['count', 'mean']).round(3)
            success_by_timeframe.columns = ['trades', 'success_rate']
            print(success_by_timeframe)

            # Calculate overall success rate
            overall_success = df['trade_success'].mean()
            print(f"\n📊 Overall success rate: {overall_success:.3f}")

            # Check for significant differences
            print(f"\n🔍 Success rate analysis:")
            for timeframe in success_by_timeframe.index:
                success_rate = success_by_timeframe.loc[timeframe, 'success_rate']
                trades = success_by_timeframe.loc[timeframe, 'trades']
                diff = success_rate - overall_success
                print(f"   {timeframe}: {success_rate:.3f} ({trades} trades) - diff: {diff:+.3f}")

    else:
        print("❌ No timeframe column found in data")

    # Check for other relevant columns
    print(f"\n📊 Available columns: {list(df.columns)}")

if __name__ == "__main__":
    analyze_timeframes()
