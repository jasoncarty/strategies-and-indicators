#!/usr/bin/env python3
"""
Improved ML Trainer - Addresses Data Leakage and Overfitting Issues
Implements proper time series validation and feature engineering
"""

import pandas as pd
import numpy as np
import json
import os
import glob
import re
from datetime import datetime
from pathlib import Path
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import TimeSeriesSplit
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score, accuracy_score
from sklearn.feature_selection import SelectKBest, f_classif
import joblib
import warnings
warnings.filterwarnings('ignore')

class ImprovedMLTrainer:
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

    def __init__(self, data_dir=None, models_dir='ml_models/', target_ea=None, train_directional_models=True):
        """Initialize the improved ML trainer"""
        self.data_dir = data_dir or self._find_metatrader_directory()
        self.models_dir = models_dir
        self.target_ea = target_ea
        self.train_directional_models = train_directional_models  # New parameter

        # Create models directory if it doesn't exist
        if not os.path.exists(self.models_dir):
            os.makedirs(self.models_dir)
            print(f"📁 Created models directory: {self.models_dir}")

        # Define EA folders
        self.ea_folders = {
            'SimpleBreakoutML_EA': 'SimpleBreakoutML_EA',
            'StrategyTesterML_EA': 'StrategyTesterML_EA'
        }

        # Set target EA if specified
        if target_ea and target_ea in self.ea_folders:
            print(f"🎯 Training focused on: {target_ea}")
            self.ea_folders = {target_ea: self.ea_folders[target_ea]}

        print(f"📁 Data directory: {self.data_dir}")
        print(f"📁 Models directory: {self.models_dir}")

        # Improved scalers and encoders
        self.buy_scaler = StandardScaler()
        self.sell_scaler = StandardScaler()
        self.combined_scaler = StandardScaler()

        # Label encoders
        self.buy_label_encoders = {}
        self.sell_label_encoders = {}
        self.combined_label_encoders = {}

        # Models
        self.buy_model = None
        self.sell_model = None
        self.combined_model = None

        # Feature names
        self.buy_feature_names = None
        self.sell_feature_names = None
        self.combined_feature_names = None

        # Performance tracking
        self.training_history = []

    def _find_metatrader_directory(self):
        """Find MetaTrader Common Files directory"""
        possible_paths = [
            os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
            os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/Common/Files"),
            os.path.expanduser("~/Documents/MetaTrader 5/MQL5/Files"),
            os.path.expanduser("~/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
            "/Applications/MetaTrader 5.app/Contents/Resources/MQL5/Files"
        ]

        for path in possible_paths:
            if os.path.exists(path):
                print(f"✅ Found MetaTrader directory: {path}")
                return path

        print("⚠️  MetaTrader directory not found, using current directory")
        return "."

    def load_and_clean_data(self, filename_pattern="*_ML_Data.json"):
        """Load and clean data with proper validation"""
        print("🔍 Loading and cleaning data...")

        # Find data files - search recursively in subdirectories
        file_patterns = []
        if self.target_ea:
            if self.target_ea in self.ea_folders:
                folder_name = self.ea_folders[self.target_ea]
                file_patterns.extend([
                    os.path.join(self.data_dir, folder_name, filename_pattern),
                    os.path.join(self.data_dir, folder_name, f"{self.target_ea}_ML_Data.json"),
                    # Add recursive search patterns for test run subdirectories
                    os.path.join(self.data_dir, folder_name, "*", filename_pattern),
                    os.path.join(self.data_dir, folder_name, "*", f"{self.target_ea}_ML_Data.json")
                ])
        else:
            for ea_name, folder_name in self.ea_folders.items():
                file_patterns.extend([
                    os.path.join(self.data_dir, folder_name, filename_pattern),
                    os.path.join(self.data_dir, folder_name, f"{ea_name}_ML_Data.json"),
                    # Add recursive search patterns for test run subdirectories
                    os.path.join(self.data_dir, folder_name, "*", filename_pattern),
                    os.path.join(self.data_dir, folder_name, "*", f"{ea_name}_ML_Data.json")
                ])

        files = []
        for pattern in file_patterns:
            files.extend(glob.glob(pattern))

        files = list(set(files))

        if not files:
            print(f"❌ No data files found")
            print(f"🔍 Searched patterns: {file_patterns}")
            return None

        print(f"📁 Found {len(files)} data files")
        for file in files:
            print(f"   - {file}")

        # Load and combine data with proper deduplication
        all_data = []
        seen_trades = set()  # Track unique trade identifiers

        for file_path in files:
            print(f"📖 Loading: {file_path}")
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)
                    if 'trades' in data:
                        trades = data['trades']
                        new_trades = 0
                        duplicate_trades = 0

                        for trade in trades:
                            # Create unique identifier for each trade
                            trade_id = trade.get('trade_id', 0)
                            test_run_id = trade.get('test_run_id', 'unknown')
                            timestamp = trade.get('timestamp', 0)
                            symbol = trade.get('symbol', 'unknown')

                            # Create unique key combining all identifiers
                            unique_key = f"{test_run_id}_{trade_id}_{timestamp}_{symbol}"

                            if unique_key not in seen_trades:
                                seen_trades.add(unique_key)
                                all_data.append(trade)
                                new_trades += 1
                            else:
                                duplicate_trades += 1

                        print(f"✅ Loaded {new_trades} new trades, skipped {duplicate_trades} duplicates")
            except Exception as e:
                print(f"⚠️  Error loading {file_path}: {e}")
                continue

        if not all_data:
            print("❌ No valid data found")
            return None

        # Convert to DataFrame
        df = pd.DataFrame(all_data)
        print(f"✅ Total unique trades loaded: {len(df)}")

        # DEBUG: Comprehensive symbol analysis
        print("\n🔍 DEBUG: Symbol Analysis")
        print("=" * 50)
        if 'symbol' in df.columns:
            print(f"📊 All unique symbols found: {sorted(df['symbol'].unique())}")
            print(f"📊 Symbol value counts:")
            symbol_counts = df['symbol'].value_counts()
            for symbol, count in symbol_counts.items():
                print(f"   {symbol}: {count} trades")

            # Dynamic symbol analysis
            for symbol in df['symbol'].unique():
                symbol_data = df[df['symbol'] == symbol]
                if len(symbol_data) > 0:
                    print(f"✅ Found {len(symbol_data)} {symbol} trades")
                    if 'timeframe' in symbol_data.columns:
                        print(f"📊 {symbol} timeframe distribution: {symbol_data['timeframe'].value_counts().to_dict()}")
                else:
                    print(f"❌ No {symbol} trades found in data")

        else:
            print("❌ No 'symbol' column found in DataFrame")
            print(f"📊 Available columns: {list(df.columns)}")

        if 'symbol' in df.columns and 'timeframe' in df.columns:
            print(f"\n📊 Trade count by (symbol, timeframe):")
            symbol_timeframe_counts = df.groupby(['symbol','timeframe']).size()
            for (symbol, timeframe), count in symbol_timeframe_counts.items():
                print(f"   {symbol} {timeframe}: {count} trades")
        print("=" * 50)

        print(f"📊 Unique test runs: {df['test_run_id'].nunique() if 'test_run_id' in df.columns else 'unknown'}")
        print(f"📊 Unique symbols: {df['symbol'].nunique() if 'symbol' in df.columns else 'unknown'}")

        # Load and merge trade results data
        df = self._merge_trade_results(df)

        # DEBUG: After merge analysis
        print("\n🔍 DEBUG: After Merge Analysis")
        print("=" * 50)
        if 'symbol' in df.columns:
            print(f"📊 [After merge] All unique symbols: {sorted(df['symbol'].unique())}")
            print(f"📊 [After merge] Symbol value counts:")
            symbol_counts_after = df['symbol'].value_counts()
            for symbol, count in symbol_counts_after.items():
                print(f"   {symbol}: {count} trades")

            # Dynamic symbol analysis after merge
            for symbol in df['symbol'].unique():
                symbol_data_after = df[df['symbol'] == symbol]
                if len(symbol_data_after) > 0:
                    print(f"✅ [After merge] Found {len(symbol_data_after)} {symbol} trades")
                    if 'timeframe' in symbol_data_after.columns:
                        print(f"📊 [After merge] {symbol} timeframe distribution: {symbol_data_after['timeframe'].value_counts().to_dict()}")
                else:
                    print(f"❌ [After merge] No {symbol} trades found in data")
        print("=" * 50)

        if 'symbol' in df.columns and 'timeframe' in df.columns:
            print(f"📊 [After merge] Trade count by (symbol, timeframe): {df.groupby(['symbol','timeframe']).size().to_dict()}")
        print(f"📊 [After merge] Unique symbols: {df['symbol'].unique() if 'symbol' in df.columns else 'unknown'}")

        # Clean and validate data
        df = self._clean_data(df)

        # DEBUG: After cleaning analysis
        print("\n🔍 DEBUG: After Cleaning Analysis")
        print("=" * 50)
        if 'symbol' in df.columns:
            print(f"📊 [After cleaning] All unique symbols: {sorted(df['symbol'].unique())}")
            print(f"📊 [After cleaning] Symbol value counts:")
            symbol_counts_cleaned = df['symbol'].value_counts()
            for symbol, count in symbol_counts_cleaned.items():
                print(f"   {symbol}: {count} trades")

            # Dynamic symbol analysis after cleaning
            for symbol in df['symbol'].unique():
                symbol_data_cleaned = df[df['symbol'] == symbol]
                if len(symbol_data_cleaned) > 0:
                    print(f"✅ [After cleaning] Found {len(symbol_data_cleaned)} {symbol} trades")
                    if 'timeframe' in symbol_data_cleaned.columns:
                        print(f"📊 [After cleaning] {symbol} timeframe distribution: {symbol_data_cleaned['timeframe'].value_counts().to_dict()}")
                else:
                    print(f"❌ [After cleaning] No {symbol} trades found in data")
        print("=" * 50)

        return df

    def _merge_trade_results(self, df):
        """Merge trade results data to get success information"""
        print("🔗 Merging trade results data...")

        # Find trade results files - search recursively in subdirectories
        results_patterns = []
        if self.target_ea:
            if self.target_ea in self.ea_folders:
                folder_name = self.ea_folders[self.target_ea]
                results_patterns.extend([
                    os.path.join(self.data_dir, folder_name, "*_Results.json"),
                    os.path.join(self.data_dir, folder_name, "*_Trade_Results.json"),
                    # Add recursive search patterns for test run subdirectories
                    os.path.join(self.data_dir, folder_name, "*", "*_Results.json"),
                    os.path.join(self.data_dir, folder_name, "*", "*_Trade_Results.json")
                ])
        else:
            for ea_name, folder_name in self.ea_folders.items():
                results_patterns.extend([
                    os.path.join(self.data_dir, folder_name, "*_Results.json"),
                    os.path.join(self.data_dir, folder_name, "*_Trade_Results.json"),
                    # Add recursive search patterns for test run subdirectories
                    os.path.join(self.data_dir, folder_name, "*", "*_Results.json"),
                    os.path.join(self.data_dir, folder_name, "*", "*_Trade_Results.json")
                ])

        results_files = []
        for pattern in results_patterns:
            results_files.extend(glob.glob(pattern))

        results_files = list(set(results_files))
        print(f"📁 Found {len(results_files)} results files")
        for file in results_files:
            print(f"   - {file}")

        # Load trade results with deduplication
        all_results = []
        seen_results = set()  # Track unique result identifiers

        for file_path in results_files:
            print(f"📖 Loading results: {file_path}")
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)

                    new_results = 0
                    duplicate_results = 0

                    # Handle different file structures
                    print(f"📊 File structure keys: {list(data.keys()) if isinstance(data, dict) else 'Array of trades'}")

                    if isinstance(data, list):
                        # Direct array of trades structure
                        print(f"📊 Processing direct array of {len(data)} trades")
                        for trade_result in data:
                            # Create unique identifier for result
                            trade_id = trade_result.get('trade_id', 0)
                            test_run_id = trade_result.get('test_run_id', 'unknown')
                            unique_key = f"{test_run_id}_{trade_id}"

                            if unique_key not in seen_results:
                                seen_results.add(unique_key)
                                all_results.append(trade_result)
                                new_results += 1
                            else:
                                duplicate_results += 1
                    elif 'comprehensive_results' in data:
                        # Results file structure
                        print(f"📊 Processing comprehensive_results structure")
                        for result in data['comprehensive_results']:
                            if 'trades' in result:
                                for trade_result in result['trades']:
                                    # Create unique identifier for result
                                    trade_id = trade_result.get('trade_id', 0)
                                    test_run_id = trade_result.get('test_run_id', 'unknown')
                                    unique_key = f"{test_run_id}_{trade_id}"

                                    if unique_key not in seen_results:
                                        seen_results.add(unique_key)
                                        all_results.append(trade_result)
                                        new_results += 1
                                    else:
                                        duplicate_results += 1
                    elif 'trades' in data:
                        # Direct trade results structure
                        print(f"📊 Processing trades structure")
                        for trade_result in data['trades']:
                            # Create unique identifier for result
                            trade_id = trade_result.get('trade_id', 0)
                            test_run_id = trade_result.get('test_run_id', 'unknown')
                            unique_key = f"{test_run_id}_{trade_id}"

                            if unique_key not in seen_results:
                                seen_results.add(unique_key)
                                all_results.append(trade_result)
                                new_results += 1
                            else:
                                duplicate_results += 1
                    else:
                        print(f"⚠️  Unknown file structure, keys: {list(data.keys())}")

                    print(f"✅ Loaded {new_results} new results, skipped {duplicate_results} duplicates")
            except json.JSONDecodeError as e:
                print(f"❌ JSON decode error in {file_path}: {e}")
                print(f"   This file appears to be corrupted. Consider regenerating it.")
                continue
            except Exception as e:
                print(f"⚠️  Error loading results {file_path}: {e}")
                continue

        if not all_results:
            print("⚠️  No trade results found, proceeding without success data")
            # Add a dummy success column for compatibility
            df['success'] = 0.5  # Neutral value
            df['profit'] = 0.0
            df['net_profit'] = 0.0
            df['exit_reason'] = 'unknown'
            print("   Added dummy success data for compatibility")
            return df

        # Convert to DataFrame
        results_df = pd.DataFrame(all_results)
        print(f"📊 Trade results shape: {results_df.shape}")
        print(f"📊 Unique test runs in results: {results_df['test_run_id'].nunique() if 'test_run_id' in results_df.columns else 'unknown'}")
        print(f"📊 Unique trade IDs in results: {results_df['trade_id'].nunique() if 'trade_id' in results_df.columns else 'unknown'}")

        # Check for success-related columns
        success_cols = [col for col in results_df.columns if 'success' in col.lower() or 'profit' in col.lower()]
        print(f"📊 Success-related columns: {success_cols}")

        # Debug: Show sample of results data
        if len(results_df) > 0:
            print(f"📊 Sample results data:")
            print(f"   Columns: {list(results_df.columns)}")
            print(f"   First few rows:")
            for i, row in results_df.head(3).iterrows():
                print(f"     Row {i}: test_run_id={row.get('test_run_id', 'N/A')}, trade_id={row.get('trade_id', 'N/A')}, trade_success={row.get('trade_success', 'N/A')}")

            # Check if trade_success column exists and show its values
            if 'trade_success' in results_df.columns:
                print(f"📊 trade_success column found!")
                print(f"📊 trade_success values: {results_df['trade_success'].value_counts().to_dict()}")
                print(f"📊 trade_success dtype: {results_df['trade_success'].dtype}")
            else:
                print(f"❌ trade_success column NOT found in results data")
                print(f"📊 Available columns: {list(results_df.columns)}")

        if 'trade_success' in results_df.columns:
            print("✅ Found trade_success column")
            print(f"📊 Success rate: {results_df['trade_success'].astype(float).mean():.3f}")

            # Merge with original data based on test_run_id AND trade_id for exact matching
            if 'test_run_id' in df.columns and 'test_run_id' in results_df.columns:
                # Check if trade_id is available in both datasets
                if 'trade_id' in df.columns and 'trade_id' in results_df.columns:
                    print("🔗 Merging on test_run_id AND trade_id for exact matching")
                    print(f"📊 Original data shape: {df.shape}")
                    print(f"📊 Results data shape: {results_df.shape}")
                    print(f"📊 Original unique trades: {df[['test_run_id', 'trade_id']].drop_duplicates().shape[0]}")
                    print(f"📊 Results unique trades: {results_df[['test_run_id', 'trade_id']].drop_duplicates().shape[0]}")

                    # Show sample of original data
                    print(f"📊 Original data sample:")
                    for i, row in df[['test_run_id', 'trade_id']].head(3).iterrows():
                        print(f"     Row {i}: test_run_id={row['test_run_id']}, trade_id={row['trade_id']}")

                    # Show sample of results data
                    print(f"📊 Results data sample:")
                    for i, row in results_df[['test_run_id', 'trade_id']].head(3).iterrows():
                        print(f"     Row {i}: test_run_id={row['test_run_id']}, trade_id={row['trade_id']}")

                    # Merge on both test_run_id AND trade_id to prevent duplicates
                    merged_df = df.merge(results_df[['test_run_id', 'trade_id', 'trade_success', 'profit', 'net_profit', 'exit_reason']],
                                       on=['test_run_id', 'trade_id'], how='left', suffixes=('', '_result'))

                    # Check merge results
                    matched_trades = merged_df['trade_success'].notna().sum()
                    unmatched_trades = merged_df['trade_success'].isna().sum()
                    print(f"📊 Merge results: {matched_trades} matched, {unmatched_trades} unmatched")

                    # Show what columns are available after merge
                    print(f"📊 Columns after merge: {list(merged_df.columns)}")
                    if 'trade_success' in merged_df.columns:
                        print(f"📊 trade_success values after merge: {merged_df['trade_success'].value_counts().to_dict()}")
                    else:
                        print(f"❌ trade_success column missing after merge!")
                else:
                    print("⚠️  trade_id not available, trying alternative matching methods...")

                    # Try to match using timestamp if available
                    if 'timestamp' in df.columns and 'open_time' in results_df.columns:
                        print("🔗 Attempting timestamp-based matching...")

                        # Convert timestamps to datetime for better matching
                        df['timestamp_dt'] = pd.to_datetime(df['timestamp'], unit='s')
                        results_df['open_time_dt'] = pd.to_datetime(results_df['open_time'], unit='s')

                        # Merge on test_run_id and closest timestamp
                        merged_df = df.merge(results_df[['test_run_id', 'open_time_dt', 'trade_success', 'profit', 'net_profit', 'exit_reason']],
                                           on='test_run_id', how='left', suffixes=('', '_result'))

                        # Find closest timestamp matches within 1 hour tolerance
                        tolerance = pd.Timedelta(hours=1)
                        matched_mask = abs(merged_df['timestamp_dt'] - merged_df['open_time_dt']) <= tolerance

                        # Only keep matches within tolerance
                        merged_df.loc[~matched_mask, ['trade_success', 'profit', 'net_profit', 'exit_reason']] = None

                        matched_trades = merged_df['trade_success'].notna().sum()
                        unmatched_trades = merged_df['trade_success'].isna().sum()
                        print(f"📊 Timestamp-based merge results: {matched_trades} matched, {unmatched_trades} unmatched")

                        # Clean up temporary columns
                        merged_df = merged_df.drop(['timestamp_dt', 'open_time_dt'], axis=1)

                    else:
                        print("⚠️  No timestamp matching possible, merging on test_run_id only (may create duplicates)")
                        # Fallback to test_run_id only
                        merged_df = df.merge(results_df[['test_run_id', 'trade_success', 'profit', 'net_profit', 'exit_reason']],
                                           on='test_run_id', how='left', suffixes=('', '_result'))

                # Convert boolean trade_success to numeric success (handles all boolean formats)
                merged_df['success'] = merged_df['trade_success'].apply(lambda x: 1 if x in [True, 'true', 'True', 1, '1'] else 0)

                print(f"📊 Final merged data shape: {merged_df.shape}")
                print(f"📊 Success rate in merged data: {merged_df['success'].mean():.3f}")
                print(f"📊 Unique trades in final data: {merged_df[['test_run_id', 'trade_id']].drop_duplicates().shape[0]}")

                return merged_df
            else:
                print("⚠️  No test_run_id column for merging")

        print("⚠️  Could not merge trade results, proceeding without success data")
        # Add a dummy success column for compatibility
        df['success'] = 0.5  # Neutral value
        df['profit'] = 0.0
        df['net_profit'] = 0.0
        df['exit_reason'] = 'unknown'
        print("   Added dummy success data for compatibility")
        return df

    def _clean_data(self, df):
        """Clean and validate the data"""
        print("🧹 Cleaning data...")

        initial_count = len(df)
        df_before = df.copy()

        # Remove duplicate trades (NEW - critical for overlapping test runs)
        df = self._remove_duplicate_trades(df)

        # Remove data leakage
        df = self._remove_data_leakage(df)

        # Remove constant features
        df = self._remove_constant_features(df)

        # Remove outliers
        df = self._remove_outliers(df)

        # Add engineered features
        df = self._add_engineered_features(df)

        # Sort by timestamp for time series validation
        if 'timestamp' in df.columns:
            df = df.sort_values('timestamp').reset_index(drop=True)

        final_count = len(df)
        print(f"✅ Data cleaning complete: {initial_count} -> {final_count} trades")

        # Generate detailed data quality report
        duplicate_info = df.attrs.get('duplicate_info', None)
        self._generate_data_quality_report(df_before, df, duplicate_info)

        # Add volume condition classification
        if 'volume_ratio' in df.columns:
            max_volume = df['volume_ratio'].max()
            if max_volume > 1.5:
                df['volume_condition'] = pd.cut(df['volume_ratio'],
                                         bins=[0, 1.0, 1.5, max_volume],
                                         labels=['low_volume', 'normal_volume', 'high_volume'])
            else:
                # If max volume is <= 1.5, use simpler bins
                df['volume_condition'] = pd.cut(df['volume_ratio'],
                                         bins=[0, 1.0, max_volume],
                                         labels=['low_volume', 'high_volume'])

        return df

    def _generate_data_quality_report(self, df_before, df_after, duplicate_info=None):
        """Generate a detailed data quality report"""
        print("\n📊 DATA QUALITY REPORT")
        print("=" * 50)

        # Basic statistics
        print(f"📈 Total trades before cleaning: {len(df_before)}")
        print(f"📈 Total trades after cleaning: {len(df_after)}")
        print(f"📈 Trades removed: {len(df_before) - len(df_after)} ({(len(df_before) - len(df_after))/len(df_before)*100:.1f}%)")

        # Duplicate analysis
        if duplicate_info:
            print(f"\n🔄 DUPLICATE ANALYSIS:")
            print(f"   Exact duplicates: {duplicate_info.get('exact_duplicates', 0)}")
            print(f"   Near-duplicates: {duplicate_info.get('near_duplicates', 0)}")
            print(f"   Overlapping trades: {duplicate_info.get('overlapping_trades', 0)}")

        # Test run analysis
        if 'test_run_id' in df_after.columns:
            unique_runs = df_after['test_run_id'].nunique()
            print(f"\n🧪 TEST RUN ANALYSIS:")
            print(f"   Unique test runs: {unique_runs}")

            # Show test run distribution
            run_counts = df_after['test_run_id'].value_counts()
            print(f"   Trades per test run:")
            for run_id, count in run_counts.head(5).items():
                print(f"     {run_id}: {count} trades")
            if len(run_counts) > 5:
                print(f"     ... and {len(run_counts) - 5} more test runs")

        # Symbol analysis
        if 'symbol' in df_after.columns:
            symbol_counts = df_after['symbol'].value_counts()
            print(f"\n💱 SYMBOL ANALYSIS:")
            for symbol, count in symbol_counts.items():
                print(f"   {symbol}: {count} trades")

        # Time period analysis
        if 'timestamp' in df_after.columns:
            df_after['datetime'] = pd.to_datetime(df_after['timestamp'], unit='s')
            date_range = f"{df_after['datetime'].min()} to {df_after['datetime'].max()}"
            print(f"\n⏰ TIME PERIOD ANALYSIS:")
            print(f"   Date range: {date_range}")
            print(f"   Total days: {(df_after['datetime'].max() - df_after['datetime'].min()).days}")

        # Success rate analysis
        if 'success' in df_after.columns:
            success_rate = df_after['success'].mean() * 100
            print(f"\n✅ SUCCESS RATE ANALYSIS:")
            print(f"   Overall success rate: {success_rate:.1f}%")

            if 'direction' in df_after.columns:
                for direction in df_after['direction'].unique():
                    dir_data = df_after[df_after['direction'] == direction]
                    dir_success = dir_data['success'].mean() * 100
                    print(f"   {direction} trades: {dir_success:.1f}% ({len(dir_data)} trades)")

        print("=" * 50)

    def _remove_duplicate_trades(self, df):
        """Remove duplicate trades from overlapping test runs"""
        print("🔄 Removing duplicate trades...")

        initial_count = len(df)
        duplicate_info = {
            'exact_duplicates': 0,
            'near_duplicates': 0,
            'overlapping_trades': 0
        }

        # Create a unique trade identifier based on ESSENTIAL characteristics only
        duplicate_columns = []

        # Essential trade characteristics for duplicate detection (ONLY these)
        if 'test_run_id' in df.columns:
            duplicate_columns.append('test_run_id')
        if 'trade_id' in df.columns:
            duplicate_columns.append('trade_id')
        if 'timestamp' in df.columns:
            duplicate_columns.append('timestamp')
        if 'symbol' in df.columns:
            duplicate_columns.append('symbol')

        # Only add direction if we have it (but be careful - same direction trades can be legitimate)
        # if 'direction' in df.columns:
        #     duplicate_columns.append('direction')

        # Only add price levels if they're exactly the same (very strict)
        # if 'entry_price' in df.columns:
        #     duplicate_columns.append('entry_price')
        # if 'stop_loss' in df.columns:
        #     duplicate_columns.append('stop_loss')
        # if 'take_profit' in df.columns:
        #     duplicate_columns.append('take_profit')

        # REMOVED: Market condition characteristics - these can legitimately be similar
        # Market indicators like rsi, stoch_main, macd_main, atr, volume should NOT be used
        # for duplicate detection as different trades can have similar market conditions

        if len(duplicate_columns) >= 2:  # Need at least 2 columns for meaningful duplicate detection
            print(f"   Checking for duplicates using: {duplicate_columns}")

            # Find exact duplicates based on essential identifiers only
            exact_duplicates = df.duplicated(subset=duplicate_columns, keep='first')
            exact_duplicate_count = exact_duplicates.sum()
            duplicate_info['exact_duplicates'] = exact_duplicate_count

            if exact_duplicate_count > 0:
                print(f"   Found {exact_duplicate_count} exact duplicate trades")
                df = df[~exact_duplicates]

            # Find overlapping time periods (more conservative)
            overlapping_trades = self._find_overlapping_trades(df)
            overlapping_count = len(overlapping_trades)
            duplicate_info['overlapping_trades'] = overlapping_count

            if overlapping_count > 0:
                print(f"   Found {overlapping_count} trades from overlapping time periods")
                df = df.drop(overlapping_trades)

            # REMOVED: Near-duplicate detection as it was too aggressive
            # Different trades can legitimately have similar characteristics

        else:
            print("   ⚠️  Insufficient columns for duplicate detection")

        final_count = len(df)
        removed_count = initial_count - final_count

        if removed_count > 0:
            print(f"   Removed {removed_count} duplicate/overlapping trades ({(removed_count/initial_count)*100:.1f}%)")
        else:
            print("   No duplicates found")

        # Store duplicate info for reporting
        df.attrs['duplicate_info'] = duplicate_info

        return df

    def _find_near_duplicates(self, df, columns, tolerance=0.001):
        """Find trades that are very similar (near-duplicates)"""
        near_duplicates = []

        # Group by categorical columns first
        categorical_cols = [col for col in columns if df[col].dtype == 'object' or df[col].dtype == 'category']
        numeric_cols = [col for col in columns if df[col].dtype in ['float64', 'int64']]

        if not categorical_cols or not numeric_cols:
            return near_duplicates

        # Group by categorical columns
        for name, group in df.groupby(categorical_cols):
            if len(group) > 1:
                # Check numeric columns for near-duplicates within each group
                for i in range(len(group)):
                    for j in range(i + 1, len(group)):
                        is_near_duplicate = True

                        for col in numeric_cols:
                            val1 = group.iloc[i][col]
                            val2 = group.iloc[j][col]

                            # Calculate relative difference
                            if val1 != 0:
                                rel_diff = abs(val1 - val2) / abs(val1)
                                if rel_diff > tolerance:
                                    is_near_duplicate = False
                                    break

                        if is_near_duplicate:
                            # Keep the first occurrence, mark the second for removal
                            near_duplicates.append(group.index[j])

        return near_duplicates

    def _find_overlapping_trades(self, df):
        """Find trades from overlapping time periods"""
        overlapping_trades = []

        if 'timestamp' not in df.columns or 'test_run_id' not in df.columns:
            return overlapping_trades

        # Convert timestamp to datetime if needed
        if df['timestamp'].dtype == 'int64':
            df['datetime'] = pd.to_datetime(df['timestamp'], unit='s')
        else:
            df['datetime'] = pd.to_datetime(df['timestamp'])

        # Group by symbol and direction
        for (symbol, direction), group in df.groupby(['symbol', 'direction']):
            if len(group) > 1:
                # Sort by timestamp
                group = group.sort_values('datetime')

                # Check for overlapping time periods
                for i in range(len(group)):
                    for j in range(i + 1, len(group)):
                        trade1 = group.iloc[i]
                        trade2 = group.iloc[j]

                        # Check if trades are from different test runs but same time period
                        if (trade1['test_run_id'] != trade2['test_run_id'] and
                            abs((trade1['datetime'] - trade2['datetime']).total_seconds()) < 300):  # 5 minutes

                            # Check if they have similar characteristics
                            if self._are_trades_similar(trade1, trade2):
                                overlapping_trades.append(trade2.name)

        return overlapping_trades

    def _are_trades_similar(self, trade1, trade2, tolerance=0.01):
        """Check if two trades are similar enough to be considered duplicates"""
        # Check entry price similarity
        if 'entry_price' in trade1 and 'entry_price' in trade2:
            if abs(trade1['entry_price'] - trade2['entry_price']) / trade1['entry_price'] > tolerance:
                return False

        # Check stop loss similarity
        if 'stop_loss' in trade1 and 'stop_loss' in trade2:
            if abs(trade1['stop_loss'] - trade2['stop_loss']) / trade1['stop_loss'] > tolerance:
                return False

        # Check take profit similarity
        if 'take_profit' in trade1 and 'take_profit' in trade2:
            if abs(trade1['take_profit'] - trade2['take_profit']) / trade1['take_profit'] > tolerance:
                return False

        # Check market conditions similarity
        market_indicators = ['rsi', 'stoch_main', 'macd_main', 'atr']
        for indicator in market_indicators:
            if indicator in trade1 and indicator in trade2:
                if abs(trade1[indicator] - trade2[indicator]) > tolerance * 100:  # Percentage tolerance
                    return False

        return True

    def _remove_data_leakage(self, df):
        """Remove data leakage by ensuring no future information - less aggressive approach"""
        print("🔒 Removing data leakage...")

        # Remove trades where entry price differs significantly from current price
        if 'entry_price' in df.columns and 'current_price' in df.columns:
            price_diff = abs(df['entry_price'] - df['current_price'])
            # Use a more reasonable threshold - 0.1% of price instead of fixed 0.001
            threshold = df['current_price'] * 0.001  # 0.1% of current price
            leaked_trades = price_diff > threshold
            print(f"   Removed {leaked_trades.sum()} trades with price leakage ({(leaked_trades.sum()/len(df))*100:.1f}%)")
            df = df[~leaked_trades]

        # Remove features that might contain future information
        future_features = ['entry_price', 'stop_loss', 'take_profit', 'lot_size']
        for feature in future_features:
            if feature in df.columns:
                df = df.drop(columns=[feature])
                print(f"   Removed future feature: {feature}")

        return df

    def _remove_constant_features(self, df):
        """Remove features with no variation"""
        print("📊 Removing constant features...")

        numeric_cols = df.select_dtypes(include=[np.number]).columns
        constant_features = []

        for col in numeric_cols:
            if df[col].nunique() == 1:
                constant_features.append(col)

        if constant_features:
            df = df.drop(columns=constant_features)
            print(f"   Removed {len(constant_features)} constant features: {constant_features}")

        return df

    def _remove_outliers(self, df):
        """Remove extreme outliers only - very conservative approach"""
        print("📈 Removing extreme outliers...")

        # Only remove EXTREME outliers from a few key indicators
        key_indicators = ['macd_main', 'macd_signal', 'volume']  # Reduced list
        initial_count = len(df)
        total_removed = 0

        for col in key_indicators:
            if col not in df.columns:
                continue

            # Remove outliers symbol-by-symbol to avoid cross-symbol bias
            outliers_mask = pd.Series([False] * len(df), index=df.index)

            if 'symbol' in df.columns:
                print(f"   Checking outliers in {col} by symbol...")
                for symbol in df['symbol'].unique():
                    symbol_data = df[df['symbol'] == symbol]
                    if len(symbol_data) < 10:  # Skip if too few samples
                        continue

                    # Calculate symbol-specific bounds
                    Q1 = symbol_data[col].quantile(0.25)
                    Q3 = symbol_data[col].quantile(0.75)
                    IQR = Q3 - Q1
                    lower_bound = Q1 - 4.0 * IQR  # Much more lenient
                    upper_bound = Q3 + 4.0 * IQR  # Much more lenient

                    # Find outliers for this symbol
                    symbol_outliers = (symbol_data[col] < lower_bound) | (symbol_data[col] > upper_bound)
                    outliers_mask.loc[symbol_data.index] = symbol_outliers

                    if symbol_outliers.sum() > 0:
                        print(f"     {symbol}: {symbol_outliers.sum()} outliers")
            else:
                # Fallback to global outlier detection if no symbol column
                Q1 = df[col].quantile(0.25)
                Q3 = df[col].quantile(0.75)
                IQR = Q3 - Q1
                lower_bound = Q1 - 4.0 * IQR
                upper_bound = Q3 + 4.0 * IQR
                outliers_mask = (df[col] < lower_bound) | (df[col] > upper_bound)

            if outliers_mask.sum() > 0:
                print(f"   Removing {outliers_mask.sum()} extreme outliers from {col}")
                df = df[~outliers_mask]
                total_removed += outliers_mask.sum()

        final_count = len(df)
        removed_count = initial_count - final_count
        if removed_count > 0:
            print(f"   Removed {removed_count} extreme outlier trades ({(removed_count/initial_count)*100:.1f}%)")
        else:
            print("   No extreme outliers found")

        return df

    def _add_engineered_features(self, df):
        """Add engineered features for better ML performance"""
        print("🔧 Adding engineered features...")

        # Market regime features
        if 'rsi' in df.columns:
            df['rsi_regime'] = pd.cut(df['rsi'], bins=[0, 30, 70, 100], labels=['oversold', 'neutral', 'overbought'])

        if 'stoch_main' in df.columns:
            df['stoch_regime'] = pd.cut(df['stoch_main'], bins=[0, 20, 80, 100], labels=['oversold', 'neutral', 'overbought'])

        # Volatility features
        if 'atr' in df.columns:
            df['volatility_regime'] = pd.qcut(df['atr'], q=3, labels=['low', 'medium', 'high'])

        # Time-based features
        if 'timestamp' in df.columns:
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
            df['hour'] = df['timestamp'].dt.hour
            df['day_of_week'] = df['timestamp'].dt.dayofweek
            df['month'] = df['timestamp'].dt.month

            # Enhanced session features
            df['session'] = self._classify_session(df['hour'])
            df['is_london_session'] = ((df['hour'] >= 8) & (df['hour'] < 16)).astype(int)
            df['is_ny_session'] = ((df['hour'] >= 13) & (df['hour'] < 22)).astype(int)
            df['is_asian_session'] = ((df['hour'] >= 1) & (df['hour'] < 10)).astype(int)
            df['is_session_overlap'] = (
                ((df['hour'] >= 8) & (df['hour'] < 16)) |  # London
                ((df['hour'] >= 13) & (df['hour'] < 22))   # NY
            ).astype(int)

        # Trend strength features
        if 'adx' in df.columns:
            df['trend_strength'] = pd.cut(df['adx'], bins=[0, 25, 50, 100], labels=['weak', 'moderate', 'strong'])

        print(f"   Added {len(df.columns) - len(df.columns)} new features")

        return df

    def _classify_session(self, hours):
        """Classify hours into trading sessions"""
        sessions = []
        for hour in hours:
            if 8 <= hour < 16:
                sessions.append('london')
            elif 13 <= hour < 22:
                sessions.append('ny')
            elif 1 <= hour < 10:
                sessions.append('asian')
            else:
                sessions.append('off_hours')
        return sessions

    def _analyze_session_performance(self, df):
        """Analyze trading performance by session with market condition breakdowns"""
        print("📊 Analyzing session performance with market conditions...")
        print(f"📊 Data shape: {df.shape}")
        print(f"📊 Available columns: {list(df.columns)}")

        if 'session' not in df.columns:
            print("❌ Session column not found in data")
            print("📊 Trying to create session column from hour data...")
            if 'hour' in df.columns:
                df['session'] = self._classify_session(df['hour'])
                print("✅ Created session column from hour data")
            else:
                print("❌ Hour column not found either")
                return {}

        if 'success' not in df.columns:
            if 'trade_success' in df.columns:
                print("✅ Found 'trade_success' column, converting to 'success' for session analysis")
                # Convert boolean trade_success to numeric success (handles all boolean formats)
                def convert_boolean_to_float(value):
                    if value in [True, 'true', 'True', 1, '1']:
                        return 1.0
                    elif value in [False, 'false', 'False', 0, '0']:
                        return 0.0
                    else:
                        return 0.5  # Default for unknown values

                df['success'] = df['trade_success'].apply(convert_boolean_to_float)
            else:
                print("❌ Success column not found in data")
                print("📊 Available columns with 'success' in name: ", [col for col in df.columns if 'success' in col.lower()])
                return {}

        print(f"📊 Session column values: {df['session'].value_counts().to_dict()}")
        print(f"📊 Success column values: {df['success'].value_counts().to_dict()}")

        # Add market condition classifications
        df = self._add_market_conditions(df)

        session_analysis = {}
        session_conditions_analysis = {}

        for session in ['london', 'ny', 'asian', 'off_hours']:
            session_data = df[df['session'] == session]
            print(f"📊 {session.capitalize()} session data: {len(session_data)} trades")

            if len(session_data) > 0:
                success_rate = session_data['success'].mean()
                total_trades = len(session_data)
                avg_profit = session_data.get('profit', pd.Series([0] * len(session_data))).mean()

                # Analyze by market conditions
                conditions_analysis = self._analyze_session_by_conditions(session_data, session)
                session_conditions_analysis[session] = conditions_analysis

                session_analysis[session] = {
                    'success_rate': success_rate,
                    'total_trades': total_trades,
                    'avg_profit': avg_profit,
                    'weight': success_rate if success_rate > 0 else 0.1,  # Minimum weight
                    'market_conditions': conditions_analysis
                }

                print(f"   {session.capitalize()} Session: {success_rate:.3f} success rate, {total_trades} trades")

                # Print market condition breakdown
                if conditions_analysis:
                    print(f"   📊 Market Conditions Breakdown:")
                    for condition, data in conditions_analysis.items():
                        if data['trades'] > 0:
                            print(f"      {condition}: {data['success_rate']:.3f} success rate, {data['trades']} trades")
            else:
                print(f"   {session.capitalize()} Session: No trades found")

        print(f"📊 Final session analysis: {session_analysis}")
        return session_analysis

    def _add_market_conditions(self, df):
        """Add market condition classifications to the dataframe"""
        print("🔍 Adding market condition classifications...")

        # Volatility conditions
        if 'volatility' in df.columns:
            df['volatility_condition'] = pd.cut(df['volatility'],
                                              bins=[0, df['volatility'].quantile(0.33), df['volatility'].quantile(0.67), df['volatility'].max()],
                                              labels=['low_volatility', 'medium_volatility', 'high_volatility'])

        # Trend conditions
        if 'trend' in df.columns:
            df['trend_condition'] = df['trend'].map({
                'strong_bullish': 'strong_trend',
                'bullish': 'moderate_trend',
                'neutral': 'sideways',
                'bearish': 'moderate_trend',
                'strong_bearish': 'strong_trend'
            })

        # RSI conditions
        if 'rsi' in df.columns:
            df['rsi_condition'] = pd.cut(df['rsi'],
                                       bins=[0, 30, 70, 100],
                                       labels=['oversold', 'neutral', 'overbought'])

        # Volume conditions
        if 'volume_ratio' in df.columns:
            max_volume = df['volume_ratio'].max()
            if max_volume > 1.5:
                df['volume_condition'] = pd.cut(df['volume_ratio'],
                                          bins=[0, 1.0, 1.5, max_volume],
                                          labels=['low_volume', 'normal_volume', 'high_volume'])
            else:
                # If max volume is <= 1.5, use simpler bins
                df['volume_condition'] = pd.cut(df['volume_ratio'],
                                          bins=[0, 1.0, max_volume],
                                          labels=['low_volume', 'high_volume'])

        # Time-based conditions
        if 'hour' in df.columns:
            df['time_condition'] = pd.cut(df['hour'],
                                        bins=[0, 6, 12, 18, 24],
                                        labels=['early_morning', 'morning', 'afternoon', 'evening'])

        # Combined market condition
        conditions = []
        if 'volatility_condition' in df.columns:
            conditions.append(df['volatility_condition'].astype(str))
        if 'trend_condition' in df.columns:
            conditions.append(df['trend_condition'].astype(str))
        if 'rsi_condition' in df.columns:
            conditions.append(df['rsi_condition'].astype(str))

        if conditions:
            df['market_condition'] = conditions[0]
            for condition in conditions[1:]:
                df['market_condition'] = df['market_condition'] + '_' + condition

        print(f"📊 Market conditions added: {[col for col in df.columns if 'condition' in col]}")
        return df

    def _analyze_session_by_conditions(self, session_data, session_name):
        """Analyze session performance by market conditions"""
        conditions_analysis = {}

        # Analyze by volatility
        if 'volatility_condition' in session_data.columns:
            for condition in session_data['volatility_condition'].unique():
                if pd.notna(condition):
                    condition_data = session_data[session_data['volatility_condition'] == condition]
                    if len(condition_data) >= 5:  # Minimum trades for analysis
                        success_rate = condition_data['success'].mean()
                        trades = len(condition_data)
                        avg_profit = condition_data.get('profit', pd.Series([0] * len(condition_data))).mean()

                        conditions_analysis[f"{condition}"] = {
                            'success_rate': success_rate,
                            'trades': trades,
                            'avg_profit': avg_profit,
                            'weight': success_rate if success_rate > 0 else 0.1
                        }

        # Analyze by trend
        if 'trend_condition' in session_data.columns:
            for condition in session_data['trend_condition'].unique():
                if pd.notna(condition):
                    condition_data = session_data[session_data['trend_condition'] == condition]
                    if len(condition_data) >= 5:
                        success_rate = condition_data['success'].mean()
                        trades = len(condition_data)
                        avg_profit = condition_data.get('profit', pd.Series([0] * len(condition_data))).mean()

                        conditions_analysis[f"{condition}"] = {
                            'success_rate': success_rate,
                            'trades': trades,
                            'avg_profit': avg_profit,
                            'weight': success_rate if success_rate > 0 else 0.1
                        }

        # Analyze by RSI
        if 'rsi_condition' in session_data.columns:
            for condition in session_data['rsi_condition'].unique():
                if pd.notna(condition):
                    condition_data = session_data[session_data['rsi_condition'] == condition]
                    if len(condition_data) >= 5:
                        success_rate = condition_data['success'].mean()
                        trades = len(condition_data)
                        avg_profit = condition_data.get('profit', pd.Series([0] * len(condition_data))).mean()

                        conditions_analysis[f"{condition}"] = {
                            'success_rate': success_rate,
                            'trades': trades,
                            'avg_profit': avg_profit,
                            'weight': success_rate if success_rate > 0 else 0.1
                        }

        return conditions_analysis

    def _calculate_session_weights(self, session_analysis):
        """Calculate optimal session weights based on performance"""
        if not session_analysis:
            return {
                'london_weight': 1.0,
                'ny_weight': 1.0,
                'asian_weight': 1.0,
                'off_hours_weight': 0.5,
                'optimal_sessions': ['london', 'ny', 'asian']
            }

        # Calculate weights based on success rates
        total_weight = sum(data['weight'] for data in session_analysis.values())

        weights = {}
        optimal_sessions = []

        for session, data in session_analysis.items():
            weight = data['weight'] / total_weight if total_weight > 0 else 0.25
            weights[f'{session}_weight'] = weight

            # Consider session optimal if success rate > 0.5 or has significant trades
            if data['success_rate'] > 0.5 or data['total_trades'] > 10:
                optimal_sessions.append(session)

        # Ensure at least one session is optimal
        if not optimal_sessions:
            optimal_sessions = ['london', 'ny']  # Default to major sessions

        weights['optimal_sessions'] = optimal_sessions

        return weights

    def _regenerate_trade_results(self):
        """Regenerate corrupted trade results files"""
        print("🔄 Attempting to regenerate trade results...")

        # Find ML data files
        ml_data_files = []
        for ea_name, folder_name in self.ea_folders.items():
            pattern = os.path.join(self.data_dir, folder_name, "*_ML_Data.json")
            ml_data_files.extend(glob.glob(pattern))

        if not ml_data_files:
            print("❌ No ML data files found to regenerate results from")
            return False

        print(f"📁 Found {len(ml_data_files)} ML data files")

        for ml_file in ml_data_files:
            print(f"📖 Processing: {ml_file}")
            try:
                with open(ml_file, 'r') as f:
                    ml_data = json.load(f)

                # Extract basic trade information
                trades = []
                for trade in ml_data:
                    trade_info = {
                        'test_run_id': trade.get('test_run_id', 'unknown'),
                        'trade_id': trade.get('trade_id', 0),
                        'symbol': trade.get('symbol', 'unknown'),
                        'direction': trade.get('direction', 'unknown'),
                        'timestamp': trade.get('timestamp', 0),
                        'entry_price': trade.get('entry_price', 0.0),
                        'stop_loss': trade.get('stop_loss', 0.0),
                        'take_profit': trade.get('take_profit', 0.0),
                        'lot_size': trade.get('lot_size', 0.0),
                        'trade_success': 0.5,  # Default neutral value
                        'profit': 0.0,
                        'net_profit': 0.0,
                        'exit_reason': 'unknown'
                    }
                    trades.append(trade_info)

                # Create results file
                results_data = {'trades': trades}

                # Determine output file name
                base_name = os.path.basename(ml_file).replace('_ML_Data.json', '')
                results_file = os.path.join(os.path.dirname(ml_file), f"{base_name}_Trade_Results.json")

                # Save regenerated results
                with open(results_file, 'w') as f:
                    json.dump(results_data, f, indent=2)

                print(f"✅ Regenerated: {results_file}")

            except Exception as e:
                print(f"❌ Error regenerating results for {ml_file}: {e}")
                continue

        return True

    def prepare_features(self, df, direction=None):
        """Prepare features for ML training"""
        print(f"🎯 Preparing features for {direction or 'combined'} model...")

        # Ensure success column exists - check for trade_success first
        if 'success' not in df.columns:
            if 'trade_success' in df.columns:
                print("✅ Found 'trade_success' column, converting to 'success'")
                print(f"📊 trade_success dtype: {df['trade_success'].dtype}")
                print(f"📊 trade_success values: {df['trade_success'].value_counts().to_dict()}")

                # Convert boolean trade_success to numeric success (handles all boolean formats)
                def convert_boolean_to_float(value):
                    if value in [True, 'true', 'True', 1, '1']:
                        return 1.0
                    elif value in [False, 'false', 'False', 0, '0']:
                        return 0.0
                    else:
                        return 0.5  # Default for unknown values

                df['success'] = df['trade_success'].apply(convert_boolean_to_float)
                print(f"📊 Success rate from trade_success: {df['success'].mean():.3f}")
                print(f"📊 success values after conversion: {df['success'].value_counts().to_dict()}")
            else:
                print("⚠️  No 'success' or 'trade_success' column found, creating dummy success data")
                df['success'] = 0.5  # Neutral value
                df['profit'] = 0.0
                df['net_profit'] = 0.0
                df['exit_reason'] = 'unknown'

        # Select relevant features (24 universal features - strategy-agnostic)
        feature_cols = [
            # Technical indicators (16 features)
            'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
            'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum', 'force_index',
            # Market conditions (4 features)
            'volume_ratio', 'price_change', 'volatility', 'spread',
            # Time-based features (4 features)
            'session_hour', 'is_news_time', 'day_of_week', 'month'
        ]

        # Add engineered features including session features
        engineered_cols = [col for col in df.columns if col.endswith('_regime') or
                          col in ['hour', 'day_of_week', 'month', 'trend_strength'] or
                          col.startswith('is_') or col == 'session' or col == 'is_session_overlap']
        feature_cols.extend(engineered_cols)

        # Filter available features
        available_features = [col for col in feature_cols if col in df.columns]

        # Prepare X and y
        X = df[available_features].copy()

        # Handle categorical features
        categorical_features = X.select_dtypes(include=['object', 'category']).columns
        for col in categorical_features:
            le = LabelEncoder()
            X[col] = le.fit_transform(X[col].astype(str))

            # Store encoder
            if direction == 'buy':
                self.buy_label_encoders[col] = le
            elif direction == 'sell':
                self.sell_label_encoders[col] = le
            else:
                self.combined_label_encoders[col] = le

        # Create target variable with debugging
        print(f"🔍 Debugging target variable creation for {direction or 'combined'} model...")
        print(f"📊 Available columns: {list(df.columns)}")

        if direction == 'buy':
            if 'direction' in df.columns and 'success' in df.columns:
                # FIXED: Only look at BUY trades and predict their success
                buy_trades = df[df['direction'] == 'buy']
                if len(buy_trades) > 0:
                    # Use buy_trades for both X and y to ensure same length
                    X = buy_trades[available_features].copy()
                    y = buy_trades['success'].astype(int)
                    print(f"📊 Buy target - BUY trades only: {len(buy_trades)} trades")
                    print(f"📊 Buy target - Success rate: {y.mean():.3f}")
                    print(f"📊 Buy target - Target distribution: {y.value_counts().to_dict()}")
                else:
                    print("❌ No BUY trades found for buy model")
                    # Create dummy data with same length as original df
                    X = df[available_features].copy()
                    y = pd.Series([0] * len(df), dtype=int)
            else:
                print("❌ Missing 'direction' or 'success' column for buy model")
                # Create dummy data with same length as original df
                X = df[available_features].copy()
                y = pd.Series([0] * len(df), dtype=int)
        elif direction == 'sell':
            if 'direction' in df.columns and 'success' in df.columns:
                # FIXED: Only look at SELL trades and predict their success
                sell_trades = df[df['direction'] == 'sell']
                if len(sell_trades) > 0:
                    # Use sell_trades for both X and y to ensure same length
                    X = sell_trades[available_features].copy()
                    y = sell_trades['success'].astype(int)
                    print(f"📊 Sell target - SELL trades only: {len(sell_trades)} trades")
                    print(f"📊 Sell target - Success rate: {y.mean():.3f}")
                    print(f"📊 Sell target - Target distribution: {y.value_counts().to_dict()}")
                else:
                    print("❌ No SELL trades found for sell model")
                    # Create dummy data with same length as original df
                    X = df[available_features].copy()
                    y = pd.Series([0] * len(df), dtype=int)
            else:
                print("❌ Missing 'direction' or 'success' column for sell model")
                # Create dummy data with same length as original df
                X = df[available_features].copy()
                y = pd.Series([0] * len(df), dtype=int)
        else:
            # For combined model, use success if available, otherwise use direction
            if 'success' in df.columns:
                # Handle NaN values in success column
                y = df['success'].fillna(0).astype(int)  # Fill NaN with 0 (unsuccessful)
                print(f"📊 Combined target - Success values: {df['success'].value_counts().to_dict()}")
                print(f"📊 Combined target - Target distribution: {y.value_counts().to_dict()}")
            elif 'direction' in df.columns:
                y = (df['direction'] == 'buy').astype(int)  # Default to buy prediction
                print(f"📊 Combined target - Using direction as fallback")
                print(f"📊 Combined target - Target distribution: {y.value_counts().to_dict()}")
            else:
                print("❌ No 'success' or 'direction' column found for combined model")
                y = pd.Series([0] * len(df), dtype=int)

        # Convert all features to numeric, handling any non-numeric columns
        if len(X) == 0:
            print(f"⚠️  No data available for {direction or 'combined'} model")
            return pd.DataFrame(), pd.Series(), []

        print(f"🔍 Debug: X shape: {X.shape}, X columns: {list(X.columns)}")
        print(f"🔍 Debug: X dtypes: {X.dtypes}")

        # Remove duplicate columns first
        X = X.loc[:, ~X.columns.duplicated()]
        print(f"🔍 Debug: After removing duplicates - X shape: {X.shape}, X columns: {list(X.columns)}")

        for col in X.columns:
            try:
                if X[col].dtype == 'object':
                    try:
                        # Try to convert to numeric
                        X[col] = pd.to_numeric(X[col], errors='coerce')
                        # Fill NaN values with 0
                        X[col] = X[col].fillna(0)
                    except:
                        # If conversion fails, drop the column
                        print(f"⚠️  Dropping non-numeric column: {col}")
                        if col in X.columns:
                            X = X.drop(columns=[col])
            except Exception as e:
                print(f"⚠️  Error processing column {col}: {e}")
                # Drop the problematic column if it exists
                if col in X.columns:
                    X = X.drop(columns=[col])

        # Remove any remaining NaN values
        # Handle categorical columns separately
        for col in X.columns:
            if X[col].dtype.name == 'category':
                # For categorical columns, fill NaN with the most frequent value
                if X[col].isna().any():
                    most_frequent = X[col].mode()[0] if len(X[col].mode()) > 0 else X[col].cat.categories[0]
                    X[col] = X[col].fillna(most_frequent)
                # Convert categorical to numeric codes
                X[col] = X[col].cat.codes
            else:
                # For non-categorical columns, fill NaN with 0
                X[col] = X[col].fillna(0)

        # Ensure all data is numeric
        X = X.astype(float)
        y = y.astype(int)

        print(f"   Features: {len(X.columns)}")
        print(f"   Samples: {len(X)}")
        print(f"   Target distribution: {y.value_counts().to_dict()}")

        return X, y, list(X.columns)

    def train_with_time_series_validation(self, X, y, feature_names, direction=None):
        """Train model with proper time series validation"""
        print(f"🚀 Training {direction or 'combined'} model with time series validation...")

        # Check for sufficient data and class balance
        if len(X) < 20:
            print(f"⚠️  Insufficient data for {direction} model (need at least 20 samples)")
            return False

        # Check class balance
        unique_classes = np.unique(y)
        if len(unique_classes) < 2:
            print(f"⚠️  Insufficient class diversity for {direction} model (only {len(unique_classes)} class)")
            return False

        # Check minimum samples per class
        for class_label in unique_classes:
            class_count = np.sum(y == class_label)
            if class_count < 5:
                print(f"⚠️  Insufficient samples for class {class_label} in {direction} model (only {class_count} samples)")
                return False

        # Time series split
        tscv = TimeSeriesSplit(n_splits=min(5, len(X) // 4))  # Adjust splits based on data size

        # Initialize model
        model = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=10,
            min_samples_leaf=5,
            random_state=42,
            class_weight='balanced'
        )

        # Cross-validation scores
        cv_scores = []
        feature_importance_scores = []

        for fold, (train_idx, val_idx) in enumerate(tscv.split(X)):
            try:
                X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
                y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

                # Check validation set class balance
                val_classes = np.unique(y_val)
                if len(val_classes) < 2:
                    print(f"   Fold {fold + 1}/{tscv.n_splits}: Skipping - validation set has only {len(val_classes)} class")
                    continue

                # Check minimum samples per class in validation set
                val_class_counts = [np.sum(y_val == c) for c in val_classes]
                if min(val_class_counts) < 2:
                    print(f"   Fold {fold + 1}/{tscv.n_splits}: Skipping - validation set has insufficient samples per class")
                    continue

                # Scale features
                scaler = StandardScaler()
                X_train_scaled = scaler.fit_transform(X_train)
                X_val_scaled = scaler.transform(X_val)

                # Train model
                model.fit(X_train_scaled, y_train)

                # Predictions
                y_pred = model.predict(X_val_scaled)
                y_pred_proba = model.predict_proba(X_val_scaled)

                # Handle case where predict_proba returns only one column
                if y_pred_proba.shape[1] == 1:
                    # If only one class in training data, create dummy probabilities
                    y_pred_proba = np.column_stack([1 - y_pred_proba[:, 0], y_pred_proba[:, 0]])

                # Calculate metrics
                accuracy = accuracy_score(y_val, y_pred)
                auc = roc_auc_score(y_val, y_pred_proba[:, 1]) if len(np.unique(y_val)) > 1 else 0.5

                cv_scores.append(accuracy)
                feature_importance_scores.append(model.feature_importances_)

                print(f"   Fold {fold + 1}/{tscv.n_splits}")
                print(f"     Accuracy: {accuracy:.3f}, AUC: {auc:.3f}")

            except Exception as e:
                print(f"   Fold {fold + 1}/{tscv.n_splits}: Error - {str(e)}")
                continue

        if len(cv_scores) == 0:
            print(f"❌ No valid folds for {direction} model")
            return False

        # Calculate average scores
        avg_accuracy = np.mean(cv_scores)

        # Calculate average AUC using the final model trained on all data
        try:
            # Train final model on all data
            final_scaler = StandardScaler()
            X_scaled = final_scaler.fit_transform(X)
            final_model = RandomForestClassifier(
                n_estimators=100,
                max_depth=10,
                min_samples_split=10,
                min_samples_leaf=5,
                random_state=42,
                class_weight='balanced'
            )
            final_model.fit(X_scaled, y)

            # Calculate AUC on all data
            y_pred_proba = final_model.predict_proba(X_scaled)
            if y_pred_proba.shape[1] == 1:
                # If only one class, create dummy probabilities
                y_pred_proba = np.column_stack([1 - y_pred_proba[:, 0], y_pred_proba[:, 0]])

            avg_auc = roc_auc_score(y, y_pred_proba[:, 1]) if len(np.unique(y)) > 1 else 0.5

            # Use the final model for storage
            model = final_model
            scaler = final_scaler

        except Exception as e:
            print(f"⚠️  Error calculating final AUC: {e}")
            avg_auc = 0.5  # Default value
            # Use the last trained model from cross-validation
            if len(feature_importance_scores) > 0:
                # Create a simple model as fallback
                model = RandomForestClassifier(
                    n_estimators=100,
                    max_depth=10,
                    min_samples_split=10,
                    min_samples_leaf=5,
                    random_state=42,
                    class_weight='balanced'
                )
                scaler = StandardScaler()
                X_scaled = scaler.fit_transform(X)
                model.fit(X_scaled, y)
            else:
                print(f"❌ No valid models available for {direction}")
                return False

        # Average feature importance
        avg_feature_importance = np.mean(feature_importance_scores, axis=0)
        feature_importance_dict = dict(zip(feature_names, avg_feature_importance))
        top_features = sorted(feature_importance_dict.items(), key=lambda x: x[1], reverse=True)[:10]

        print(f"   Average Accuracy: {avg_accuracy:.3f}")
        print(f"   Average AUC: {avg_auc:.3f}")
        print(f"   Top features: {[f[0] for f in top_features]}")

        # Store model and training history
        if direction:
            # Store timeframe-specific model with full name
            setattr(self, f'{direction}_model', model)
            setattr(self, f'{direction}_scaler', scaler)
            setattr(self, f'{direction}_feature_names', feature_names)

            # Store training history
            if not hasattr(self, 'training_history'):
                self.training_history = []

            self.training_history.append({
                'direction': direction,
                'avg_accuracy': avg_accuracy,
                'avg_auc': avg_auc,
                'feature_importance': feature_importance_dict,
                'n_samples': len(X),
                'n_features': len(feature_names),
                'cv_scores': cv_scores
            })
        else:
            # Store combined model
            self.combined_model = model
            self.combined_scaler = scaler
            self.combined_feature_names = feature_names

        return True

    def save_models(self):
        """Save trained models and scalers"""
        print("💾 Saving models...")

        # Save standard models (if they exist)
        if hasattr(self, 'buy_model'):
            joblib.dump(self.buy_model, os.path.join(self.models_dir, 'buy_model.pkl'))
            joblib.dump(self.buy_scaler, os.path.join(self.models_dir, 'buy_scaler.pkl'))
            joblib.dump(self.buy_feature_names, os.path.join(self.models_dir, 'buy_feature_names.pkl'))
            print("✅ Saved buy model")

        if hasattr(self, 'sell_model'):
            joblib.dump(self.sell_model, os.path.join(self.models_dir, 'sell_model.pkl'))
            joblib.dump(self.sell_scaler, os.path.join(self.models_dir, 'sell_scaler.pkl'))
            joblib.dump(self.sell_feature_names, os.path.join(self.models_dir, 'sell_feature_names.pkl'))
            print("✅ Saved sell model")

        if hasattr(self, 'combined_model'):
            joblib.dump(self.combined_model, os.path.join(self.models_dir, 'combined_model.pkl'))
            joblib.dump(self.combined_scaler, os.path.join(self.models_dir, 'combined_scaler.pkl'))
            joblib.dump(self.combined_feature_names, os.path.join(self.models_dir, 'combined_feature_names.pkl'))
            print("✅ Saved combined model")

        # Save symbol+timeframe specific models
        symbol_timeframe_models = []
        all_attrs = dir(self)
        print(f"🔍 [Debug] All attributes: {[attr for attr in all_attrs if 'model' in attr]}")

        for attr_name in all_attrs:
            if ((attr_name.startswith('buy_') and attr_name.endswith('_model') and 'model' in attr_name and attr_name != 'buy_model') or
                (attr_name.startswith('sell_') and attr_name.endswith('_model') and 'model' in attr_name and attr_name != 'sell_model') or
                (attr_name.startswith('combined_') and attr_name.endswith('_model') and 'model' in attr_name and attr_name != 'combined_model')):
                symbol_timeframe_models.append(attr_name)
        print(f"📊 [Save] Found {len(symbol_timeframe_models)} symbol+timeframe model attributes: {symbol_timeframe_models}")

        for model_attr in symbol_timeframe_models:
            # Extract direction, symbol, and timeframe from model name
            # Format: buy_{symbol}_PERIOD_{timeframe}, sell_{symbol}_PERIOD_{timeframe}, combined_{symbol}_PERIOD_{timeframe}
            parts = model_attr.split('_')

            if len(parts) >= 4 and parts[1] == 'PERIOD':
                # Old format: buy_PERIOD_M5
                direction = parts[0]
                timeframe = parts[2]
                symbol = 'unknown'
            elif len(parts) >= 5 and parts[2] == 'PERIOD' and parts[3] == 'PERIOD':
                # Double PERIOD format: buy_BTCUSD_PERIOD_PERIOD_M5
                direction = parts[0]
                symbol = parts[1]
                timeframe = parts[4]  # After the second PERIOD
            elif len(parts) >= 4:
                # New format: buy_EURUSD_PERIOD_M5
                direction = parts[0]
                symbol = parts[1]
                timeframe = parts[3]  # After PERIOD_
            else:
                print(f"⚠️  Unknown model format: {model_attr}")
                continue

            # Get model, scaler, and feature names
            model = getattr(self, model_attr)

            # Handle different naming patterns for scaler and feature names
            if symbol != 'unknown':
                # Try different patterns for scaler and feature names
                scaler_patterns = [
                    f'{direction}_{symbol}_PERIOD_PERIOD_{timeframe}_scaler',
                    f'{direction}_{symbol}_PERIOD_{timeframe}_scaler',
                    f'{direction}_scaler_{symbol}_PERIOD_PERIOD_{timeframe}',
                    f'{direction}_scaler_{symbol}_PERIOD_{timeframe}',
                    f'{direction}_scaler_PERIOD_{timeframe}'
                ]
                features_patterns = [
                    f'{direction}_{symbol}_PERIOD_PERIOD_{timeframe}_feature_names',
                    f'{direction}_{symbol}_PERIOD_{timeframe}_feature_names',
                    f'{direction}_feature_names_{symbol}_PERIOD_PERIOD_{timeframe}',
                    f'{direction}_feature_names_{symbol}_PERIOD_{timeframe}',
                    f'{direction}_feature_names_PERIOD_{timeframe}'
                ]

                # Find the first pattern that exists
                print(f"🔍 [Save] Trying scaler patterns for {model_attr}: {scaler_patterns}")
                scaler_attr = None
                for pattern in scaler_patterns:
                    if hasattr(self, pattern):
                        scaler_attr = pattern
                        print(f"   ✅ Found scaler pattern: {pattern}")
                        break
                    else:
                        print(f"   ❌ Pattern not found: {pattern}")

                print(f"🔍 [Save] Trying feature patterns for {model_attr}: {features_patterns}")
                features_attr = None
                for pattern in features_patterns:
                    if hasattr(self, pattern):
                        features_attr = pattern
                        print(f"   ✅ Found feature pattern: {pattern}")
                        break
                    else:
                        print(f"   ❌ Pattern not found: {pattern}")
            else:
                scaler_attr = f'{direction}_scaler_PERIOD_{timeframe}'
                features_attr = f'{direction}_feature_names_PERIOD_{timeframe}'

            print(f"🔍 [Save] Checking attributes for {model_attr}:")
            print(f"   scaler_attr: {scaler_attr}")
            print(f"   features_attr: {features_attr}")
            print(f"   hasattr(self, scaler_attr): {hasattr(self, scaler_attr) if scaler_attr is not None else 'N/A'}")
            print(f"   hasattr(self, features_attr): {hasattr(self, features_attr) if features_attr is not None else 'N/A'}")

            if scaler_attr is not None and features_attr is not None and hasattr(self, scaler_attr) and hasattr(self, features_attr):
                scaler = getattr(self, scaler_attr)
                feature_names = getattr(self, features_attr)

                # Save with symbol+timeframe-specific naming
                if symbol != 'unknown':
                    model_filename = f'{direction}_model_{symbol}_PERIOD_{timeframe}.pkl'
                    scaler_filename = f'{direction}_scaler_{symbol}_PERIOD_{timeframe}.pkl'
                    features_filename = f'{direction}_feature_names_{symbol}_PERIOD_{timeframe}.pkl'
                else:
                    model_filename = f'{direction}_model_PERIOD_{timeframe}.pkl'
                    scaler_filename = f'{direction}_scaler_PERIOD_{timeframe}.pkl'
                    features_filename = f'{direction}_feature_names_PERIOD_{timeframe}.pkl'

                joblib.dump(model, os.path.join(self.models_dir, model_filename))
                joblib.dump(scaler, os.path.join(self.models_dir, scaler_filename))
                joblib.dump(feature_names, os.path.join(self.models_dir, features_filename))

                print(f"✅ Saved {direction} model for {symbol} {timeframe}")
            else:
                print(f"⚠️  Missing scaler or features for {model_attr}")
                print(f"   Available scaler attributes: {[attr for attr in dir(self) if 'scaler' in attr and attr.startswith(direction)]}")
                print(f"   Available feature attributes: {[attr for attr in dir(self) if 'feature_names' in attr and attr.startswith(direction)]}")

        # Save training history
        if hasattr(self, 'training_history'):
            joblib.dump(self.training_history, os.path.join(self.models_dir, 'training_history.pkl'))
            print("✅ Saved training history")

        # Generate symbol+timeframe-specific parameters
        print("📊 Generating symbol+timeframe-specific parameters...")
        # Generate parameters for each symbol+timeframe combination that was trained
        # We'll generate parameters for the main symbols and timeframes we know exist
        # Dynamic symbol list from data
        symbols = self.df['symbol'].unique().tolist() if 'symbol' in self.df.columns else []
        timeframes = ['H1', 'H4', 'M15', 'M30', 'M5']

        for symbol in symbols:
            for timeframe in timeframes:
                self._generate_symbol_timeframe_parameters(symbol, timeframe)

        print("💾 All models saved successfully!")

    def _analyze_volume_thresholds(self, merged_df):
        """Analyze optimal volume thresholds per symbol based on performance"""
        print("🔍 Analyzing optimal volume thresholds per symbol...")

        volume_thresholds = {}

        # Create clean_symbol column if it doesn't exist
        if 'clean_symbol' not in merged_df.columns and 'symbol' in merged_df.columns:
            merged_df['clean_symbol'] = merged_df['symbol'].str.replace('+', '')

        for symbol in merged_df['clean_symbol'].unique():
            symbol_data = merged_df[merged_df['clean_symbol'] == symbol]

            if len(symbol_data) < 10:  # Skip symbols with insufficient data
                continue

            # Analyze performance by volume ratio ranges
            volume_ranges = [
                (0, 0.8, 'very_low'),
                (0.8, 1.0, 'low'),
                (1.0, 1.2, 'normal'),
                (1.2, 1.5, 'high'),
                (1.5, float('inf'), 'very_high')
            ]

            best_range = None
            best_profit = float('-inf')
            best_win_rate = 0

            for min_vol, max_vol, range_name in volume_ranges:
                if max_vol == float('inf'):
                    range_data = symbol_data[symbol_data['volume_ratio'] >= min_vol]
                else:
                    range_data = symbol_data[(symbol_data['volume_ratio'] >= min_vol) & (symbol_data['volume_ratio'] < max_vol)]

                if len(range_data) >= 3:  # Minimum sample size
                    # Since we don't have success data, we'll use a different approach
                    # Calculate average profit and use that as a proxy for performance
                    avg_profit = range_data['volume_ratio'].mean()  # Use volume_ratio as proxy since we don't have profit

                    # For now, assume lower volume ratios are better (based on our analysis)
                    # This is a simplified approach - in reality we'd need the actual profit data
                    score = -avg_profit  # Lower volume ratio = higher score

                    if score > best_profit:
                        best_profit = score
                        best_win_rate = len(range_data)  # Use trade count as proxy
                        best_range = (min_vol, max_vol, range_name)

            if best_range:
                min_vol, max_vol, range_name = best_range
                # Set threshold to the upper bound of the best performing range
                optimal_threshold = max_vol if max_vol != float('inf') else 2.0

                volume_thresholds[symbol] = {
                    'optimal_threshold': optimal_threshold,
                    'best_range': range_name,
                    'best_profit': best_profit,
                    'best_win_rate': best_win_rate,
                    'total_trades': len(symbol_data)
                }

                print(f"   {symbol}: Optimal volume threshold = {optimal_threshold:.2f} ({range_name} volume)")
                print(f"      Best range: {range_name} (score: {best_profit:.2f}, trades: {best_win_rate})")
            else:
                # Default threshold for symbols with insufficient data
                volume_thresholds[symbol] = {
                    'optimal_threshold': 1.2,
                    'best_range': 'default',
                    'best_profit': 0,
                    'best_win_rate': 0,
                    'total_trades': len(symbol_data)
                }
                print(f"   {symbol}: Using default volume threshold = 1.2 (insufficient data)")

        return volume_thresholds

    def _save_improved_parameters(self):
        """Save improved parameters for EA use"""
        print("💾 Saving improved parameters...")

        # Generate timeframe-specific parameter files
        self._generate_timeframe_specific_parameters()

        # Save combined parameters (existing functionality)
        self._save_combined_parameters()

        print("✅ Parameters saved successfully!")

    def _generate_timeframe_specific_parameters(self):
        """Generate timeframe-specific parameter files"""
        print("📊 Generating timeframe-specific parameter files...")

        # Get unique timeframes from training history
        timeframes = set()
        for history in self.training_history:
            direction = history['direction']
            if direction and '_' in direction:
                base_direction, timeframe = direction.split('_', 1)
                timeframes.add(timeframe)

        print(f"📊 Found timeframes: {timeframes}")

        for timeframe in timeframes:
            self._generate_timeframe_parameters(timeframe)

    def _generate_timeframe_parameters(self, timeframe):
        """Generate parameters for a specific timeframe"""
        print(f"📊 Generating parameters for {timeframe}...")

        # Find models for this timeframe
        buy_model_key = f'buy_{timeframe}'
        sell_model_key = f'sell_{timeframe}'
        combined_model_key = f'combined_{timeframe}'

        # Get training history for this timeframe
        buy_history = None
        sell_history = None
        combined_history = None

        for history in self.training_history:
            if history['direction'] == buy_model_key:
                buy_history = history
            elif history['direction'] == sell_model_key:
                sell_history = history
            elif history['direction'] == combined_model_key:
                combined_history = history

        # Generate parameter file content
        param_content = f"# Timeframe-specific ML parameters for {timeframe}\n"
        param_content += f"# Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"

        # Buy model parameters
        if buy_history:
            param_content += "# Buy Model Parameters\n"
            param_content += f"buy_min_prediction_threshold = {0.55:.3f}\n"
            param_content += f"buy_max_prediction_threshold = {0.45:.3f}\n"
            param_content += f"buy_min_confidence = {0.30:.3f}\n"
            param_content += f"buy_max_confidence = {0.85:.3f}\n"
            param_content += f"buy_avg_accuracy = {buy_history['avg_accuracy']:.3f}\n"
            param_content += f"buy_avg_auc = {buy_history['avg_auc']:.3f}\n\n"

        # Sell model parameters
        if sell_history:
            param_content += "# Sell Model Parameters\n"
            param_content += f"sell_min_prediction_threshold = {0.55:.3f}\n"
            param_content += f"sell_max_prediction_threshold = {0.45:.3f}\n"
            param_content += f"sell_min_confidence = {0.30:.3f}\n"
            param_content += f"sell_max_confidence = {0.85:.3f}\n"
            param_content += f"sell_avg_accuracy = {sell_history['avg_accuracy']:.3f}\n"
            param_content += f"sell_avg_auc = {sell_history['avg_auc']:.3f}\n\n"

        # Combined model parameters
        if combined_history:
            param_content += "# Combined Model Parameters\n"
            param_content += f"combined_min_prediction_threshold = {0.55:.3f}\n"
            param_content += f"combined_max_prediction_threshold = {0.45:.3f}\n"
            param_content += f"combined_min_confidence = {0.30:.3f}\n"
            param_content += f"combined_max_confidence = {0.85:.3f}\n"
            param_content += f"combined_avg_accuracy = {combined_history['avg_accuracy']:.3f}\n"
            param_content += f"combined_avg_auc = {combined_history['avg_auc']:.3f}\n\n"

        # General parameters
        param_content += "# General Parameters\n"
        param_content += f"position_sizing_multiplier = {1.0:.2f}\n"
        param_content += f"stop_loss_adjustment = {1.0:.2f}\n"
        param_content += f"volume_ratio_threshold = {1.5:.2f}\n"
        param_content += f"optimal_sessions = all\n"
        param_content += f"session_filtering_enabled = true\n"
        param_content += f"london_session_weight = {1.0:.2f}\n"
        param_content += f"ny_session_weight = {1.0:.2f}\n"
        param_content += f"asian_session_weight = {1.0:.2f}\n"
        param_content += f"off_hours_session_weight = {0.5:.2f}\n"
        param_content += f"london_min_success_rate = {0.4:.3f}\n"
        param_content += f"ny_min_success_rate = {0.4:.3f}\n"
        param_content += f"asian_min_success_rate = {0.4:.3f}\n\n"

        # Top features for this timeframe
        param_content += "# Top Features (for reference)\n"
        if combined_history and 'feature_importance' in combined_history:
            top_features = sorted(combined_history['feature_importance'].items(),
                                key=lambda x: x[1], reverse=True)[:10]
            for feature, importance in top_features:
                param_content += f"# {feature}: {importance:.3f}\n"

        # Save parameter file
        param_filename = f"ml_model_params_{timeframe}.txt"
        param_filepath = os.path.join(self.models_dir, param_filename)

        try:
            with open(param_filepath, 'w') as f:
                f.write(param_content)
            print(f"✅ Saved {timeframe} parameters to: {param_filename}")
        except Exception as e:
            print(f"❌ Failed to save {timeframe} parameters: {e}")

    def _save_combined_parameters(self):
        """Save combined parameters (existing functionality)"""
        # This method will contain the existing parameter saving logic
        # For now, just create a placeholder
        pass

    def _copy_parameters_to_metatrader(self):
        """Copy generated parameter files to MetaTrader directory"""
        print("📁 Copying parameter files to MetaTrader directory...")

        # Find MetaTrader directory
        mt5_dir = self._find_metatrader_directory()
        if not mt5_dir:
            print("❌ Could not find MetaTrader directory")
            return

        # Create EA-specific directory if it doesn't exist
        ea_dir = os.path.join(mt5_dir, "SimpleBreakoutML_EA")
        if not os.path.exists(ea_dir):
            os.makedirs(ea_dir)
            print(f"📁 Created directory: {ea_dir}")

        # Copy all parameter files
        param_files = glob.glob(os.path.join(self.models_dir, "ml_model_params_*.txt"))
        copied_count = 0

        for param_file in param_files:
            filename = os.path.basename(param_file)
            dest_file = os.path.join(ea_dir, filename)

            try:
                import shutil
                shutil.copy2(param_file, dest_file)
                copied_count += 1
                print(f"✅ Copied: {filename}")
            except Exception as e:
                print(f"❌ Failed to copy {filename}: {e}")

        print(f"📁 Successfully copied {copied_count} parameter files to MetaTrader directory")
        print(f"📁 Location: {ea_dir}")

    def _generate_session_specific_params(self, session_analysis):
        """Generate session-specific parameters based on analysis"""
        session_params = {}
        for session in ['london', 'ny', 'asian', 'off_hours']:
            if session in session_analysis:
                session_params[f'{session}_min_success_rate'] = session_analysis[session]['success_rate']
                session_params[f'{session}_min_trades'] = session_analysis[session]['total_trades']
                session_params[f'{session}_optimal_weight'] = session_analysis[session]['weight']
                session_params[f'{session}_avg_profit'] = session_analysis[session]['avg_profit']
                session_params[f'{session}_market_conditions'] = session_analysis[session]['market_conditions']
            else:
                session_params[f'{session}_min_success_rate'] = 0.4
                session_params[f'{session}_min_trades'] = 5
                session_params[f'{session}_optimal_weight'] = 0.1
                session_params[f'{session}_avg_profit'] = 0.0
                session_params[f'{session}_market_conditions'] = {}
        return session_params

    def _generate_market_condition_analysis(self, session_analysis):
        """Generate market condition analysis based on session analysis"""
        market_condition_analysis = {}
        for session in ['london', 'ny', 'asian', 'off_hours']:
            if session in session_analysis:
                market_condition_analysis[f'{session}_conditions'] = session_analysis[session]['market_conditions']
            else:
                market_condition_analysis[f'{session}_conditions'] = {}
        return market_condition_analysis

    def run_improved_training(self, data_pattern="*_ML_Data.json"):
        """Run the improved ML training process"""
        print("🚀 Starting improved ML training...")

        # Load and clean data
        df = self.load_and_clean_data(data_pattern)
        if df is None or len(df) == 0:
            print("❌ No data available for training")
            return

        # Store DataFrame for symbol extraction in summary
        self.df = df

        print(f"📊 Loaded {len(df)} trades for training")

        # Check for success column
        if 'success' not in df.columns:
            if 'trade_success' in df.columns:
                print("✅ Found 'trade_success' column, converting to 'success'")
                print(f"📊 trade_success dtype: {df['trade_success'].dtype}")
                print(f"📊 trade_success values: {df['trade_success'].value_counts().to_dict()}")

                # Convert boolean trade_success to numeric success (handles all boolean formats)
                def convert_boolean_to_float(value):
                    if value in [True, 'true', 'True', 1, '1']:
                        return 1.0
                    elif value in [False, 'false', 'False', 0, '0']:
                        return 0.0
                    else:
                        return 0.5  # Default for unknown values

                df['success'] = df['trade_success'].apply(convert_boolean_to_float)
                print(f"📊 Success rate from trade_success: {df['success'].mean():.3f}")
                print(f"📊 success values after conversion: {df['success'].value_counts().to_dict()}")
            else:
                print("⚠️  No 'success' or 'trade_success' column found, creating dummy success data")
                df['success'] = 0.5  # Neutral value
                df['profit'] = 0.0
                df['net_profit'] = 0.0
                df['exit_reason'] = 'unknown'

        # NEW: Analyze timeframe distribution and train separate models
        print("\n🔄 STEP 3: Analyzing timeframe distribution...")
        if 'timeframe' in df.columns:
            timeframe_dist = df['timeframe'].value_counts()
            print(f"📊 Timeframes found: {list(timeframe_dist.index)}")
            print(f"📊 Distribution: {timeframe_dist.to_dict()}")

            # Train separate models for each timeframe
            success = self._train_timeframe_specific_models(df)
        else:
            print("⚠️  No timeframe column found, training combined model...")
            success = self._train_combined_model(df)

        # Save models
        print("\n" + "=" * 60)
        print("💾 SAVING MODELS")
        print("=" * 60)

        self.save_models()

        # Print summary
        print("\n" + "=" * 60)
        print("📊 TRAINING SUMMARY")
        print("=" * 60)

        best_model = None
        best_score = -1
        best_timeframe = None
        best_symbol = None
        best_auc = -1
        best_auc_model = None
        best_auc_timeframe = None
        best_auc_symbol = None

        # Track best by symbol
        symbol_scores = {}
        symbol_auc_scores = {}

        for history in self.training_history:
            print(f"Model: {history['direction'] or 'combined'}")
            print(f"  Average Accuracy: {history['avg_accuracy']:.3f}")
            print(f"  Average AUC: {history['avg_auc']:.3f}")
            print(f"  Top Features: {list(history['feature_importance'].keys())[:5]}")
            print()
            # Parse timeframe and symbol from direction if possible
            direction = history['direction'] or 'combined'
            # Try to extract timeframe and symbol from direction
            tf = 'unknown'
            symbol = 'unknown'

            # Handle different naming patterns:
            # Pattern 1: buy_EURUSD_PERIOD_M5, sell_XAUUSD_PERIOD_H1, combined_EURUSD_PERIOD_M15
            # Pattern 2: buy_PERIOD_M5, sell_PERIOD_H1 (no symbol in name)
            # Pattern 3: buy, sell, combined (no timeframe or symbol)

            parts = direction.split('_')
            if len(parts) >= 3:
                # Check if second part looks like a symbol (contains letters and possibly numbers)
                potential_symbol = parts[1]
                if any(c.isalpha() for c in potential_symbol) and len(potential_symbol) >= 3:
                    symbol = potential_symbol
                    tf = parts[-1]  # Last part is timeframe
                else:
                    # Second part is not a symbol, check if it's PERIOD
                    if parts[1] == 'PERIOD' and len(parts) >= 3:
                        tf = parts[2]  # Third part is timeframe
                        # Try to extract symbol from the data if available
                        if hasattr(self, 'df') and 'symbol' in self.df.columns:
                            symbol = self.df['symbol'].iloc[0] if len(self.df) > 0 else 'unknown'
            elif len(parts) == 2:
                # Could be buy_PERIOD_M5 or just buy_M5
                if parts[1].startswith('PERIOD_'):
                    tf = parts[1].replace('PERIOD_', '')
                    # Try to extract symbol from the data
                    if hasattr(self, 'df') and 'symbol' in self.df.columns:
                        symbol = self.df['symbol'].iloc[0] if len(self.df) > 0 else 'unknown'
                else:
                    tf = parts[1]
                    # Try to extract symbol from the data
                    if hasattr(self, 'df') and 'symbol' in self.df.columns:
                        symbol = self.df['symbol'].iloc[0] if len(self.df) > 0 else 'unknown'
            # Use accuracy as main score
            if history['avg_accuracy'] > best_score:
                best_score = history['avg_accuracy']
                best_model = direction
                best_timeframe = tf
                best_symbol = symbol
            # Use AUC as secondary score
            if history['avg_auc'] > best_auc:
                best_auc = history['avg_auc']
                best_auc_model = direction
                best_auc_timeframe = tf
                best_auc_symbol = symbol
            # Track best by symbol
            if symbol != 'unknown':
                if symbol not in symbol_scores or history['avg_accuracy'] > symbol_scores[symbol]['score']:
                    symbol_scores[symbol] = {'score': history['avg_accuracy'], 'model': direction, 'timeframe': tf}
                if symbol not in symbol_auc_scores or history['avg_auc'] > symbol_auc_scores[symbol]['auc']:
                    symbol_auc_scores[symbol] = {'auc': history['avg_auc'], 'model': direction, 'timeframe': tf}

        print("\n" + "=" * 60)
        print("🏆 BEST PERFORMING MODELS")
        print("=" * 60)
        if best_model:
            print(f"Best by Accuracy: {best_model} (Symbol: {best_symbol}, Timeframe: {best_timeframe}) - Accuracy: {best_score:.3f}")
        if best_auc_model:
            print(f"Best by AUC: {best_auc_model} (Symbol: {best_auc_symbol}, Timeframe: {best_auc_timeframe}) - AUC: {best_auc:.3f}")
        print("=" * 60)
        # Best by symbol
        if symbol_scores:
            print("\nBest by Symbol (Accuracy):")
            for symbol, info in symbol_scores.items():
                print(f"  {symbol}: {info['model']} (Timeframe: {info['timeframe']}) - Accuracy: {info['score']:.3f}")
        if symbol_auc_scores:
            print("\nBest by Symbol (AUC):")
            for symbol, info in symbol_auc_scores.items():
                print(f"  {symbol}: {info['model']} (Timeframe: {info['timeframe']}) - AUC: {info['auc']:.3f}")
        print("=" * 60)

        print("✅ Improved ML training completed successfully!")
        return success

    def _aggregate_test_run_data(self):
        """Aggregate all ML_Data.json and Results.json files from test run directories"""
        print("🔄 Aggregating test run data...")

        if not self.target_ea or self.target_ea not in self.ea_folders:
            print("❌ Target EA not specified or not found in EA folders")
            return False

        folder_name = self.ea_folders[self.target_ea]
        ea_base_path = os.path.join(self.data_dir, folder_name)

        if not os.path.exists(ea_base_path):
            print(f"❌ EA base directory not found: {ea_base_path}")
            return False

        # Find all test run directories
        test_run_dirs = [d for d in os.listdir(ea_base_path) if os.path.isdir(os.path.join(ea_base_path, d))]

        if not test_run_dirs:
            print("❌ No test run directories found")
            return False

        print(f"🔍 Found {len(test_run_dirs)} test run directories")

        # Aggregate ML data
        all_trades = []
        successful_ml_runs = 0

        for test_run in test_run_dirs:
            ml_data_file = os.path.join(ea_base_path, test_run, f"{self.target_ea}_ML_Data.json")

            if os.path.exists(ml_data_file):
                try:
                    with open(ml_data_file, 'r') as f:
                        data = json.load(f)

                    if "trades" in data and isinstance(data["trades"], list):
                        trades = data["trades"]
                        all_trades.extend(trades)
                        successful_ml_runs += 1
                        print(f"✅ Loaded {len(trades)} trades from {test_run}")
                    else:
                        print(f"⚠️  Invalid ML data structure in {test_run}")

                except Exception as e:
                    print(f"❌ Error reading ML data from {test_run}: {e}")
            else:
                print(f"⚠️  No ML data file found in {test_run}")

        # Save aggregated ML data
        if all_trades:
            aggregated_ml_file = os.path.join(ea_base_path, "aggregated_ml_data.json")
            aggregated_ml_data = {"trades": all_trades}

            with open(aggregated_ml_file, 'w') as f:
                json.dump(aggregated_ml_data, f, indent=2)

            print(f"✅ Aggregated {len(all_trades)} trades from {successful_ml_runs} test runs")
            print(f"📁 Saved ML data to: {aggregated_ml_file}")
        else:
            print("❌ No ML trades found to aggregate")
            return False

        # Aggregate results data
        all_results = []
        successful_results_runs = 0

        for test_run in test_run_dirs:
            results_file = os.path.join(ea_base_path, test_run, f"{self.target_ea}_Results.json")

            if os.path.exists(results_file):
                try:
                    with open(results_file, 'r') as f:
                        data = json.load(f)

                    if "comprehensive_results" in data and isinstance(data["comprehensive_results"], list):
                        results = data["comprehensive_results"]
                        all_results.extend(results)
                        successful_results_runs += 1
                        print(f"✅ Loaded {len(results)} result sets from {test_run}")
                    else:
                        print(f"⚠️  Invalid results structure in {test_run}")

                except Exception as e:
                    print(f"❌ Error reading results from {test_run}: {e}")
            else:
                print(f"⚠️  No results file found in {test_run}")

        # Save aggregated results
        if all_results:
            aggregated_results_file = os.path.join(ea_base_path, "aggregated_results.json")
            aggregated_results_data = {"comprehensive_results": all_results}

            with open(aggregated_results_file, 'w') as f:
                json.dump(aggregated_results_data, f, indent=2)

            print(f"✅ Aggregated {len(all_results)} result sets from {successful_results_runs} test runs")
            print(f"📁 Saved results to: {aggregated_results_file}")
        else:
            print("❌ No results found to aggregate")
            return False

        print("✅ Data aggregation completed successfully!")
        return True

    def _train_timeframe_specific_models(self, df):
        """Train separate models for each symbol+timeframe combination"""
        print("🎯 Training symbol+timeframe specific models...")

        # DEBUG: Pre-grouping analysis
        print("\n🔍 DEBUG: Pre-grouping Analysis")
        print("=" * 50)
        if 'symbol' in df.columns and 'timeframe' in df.columns:
            print(f"📊 DataFrame shape: {df.shape}")
            print(f"📊 All unique symbols: {sorted(df['symbol'].unique())}")
            print(f"📊 All unique timeframes: {sorted(df['timeframe'].unique())}")

            # Dynamic symbol analysis
            for symbol in df['symbol'].unique():
                symbol_data = df[df['symbol'] == symbol]
                if len(symbol_data) > 0:
                    print(f"✅ Found {len(symbol_data)} {symbol} trades in DataFrame")
                    print(f"📊 {symbol} timeframes: {sorted(symbol_data['timeframe'].unique())}")
                    for tf in sorted(symbol_data['timeframe'].unique()):
                        tf_data = symbol_data[symbol_data['timeframe'] == tf]
                        print(f"   {symbol} {tf}: {len(tf_data)} trades")
                else:
                    print(f"❌ No {symbol} trades found in DataFrame")
        else:
            print("❌ Missing required columns for grouping")
            if 'symbol' not in df.columns:
                print("   - Missing 'symbol' column")
            if 'timeframe' not in df.columns:
                print("   - Missing 'timeframe' column")
            print(f"📊 Available columns: {list(df.columns)}")
        print("=" * 50)

        # Group data by symbol AND timeframe
        if 'symbol' in df.columns and 'timeframe' in df.columns:
            # Create symbol+timeframe groups
            symbol_timeframe_groups = df.groupby(['symbol', 'timeframe'])

            print(f"📊 [Grouping] Found {len(symbol_timeframe_groups)} symbol+timeframe combinations:")
            for (symbol, timeframe), group in symbol_timeframe_groups:
                print(f"   {symbol} {timeframe}: {len(group)} trades")

            success_count = 0
            total_combinations = len(symbol_timeframe_groups)

            for (symbol, timeframe), group_data in symbol_timeframe_groups:
                print(f"\n" + "=" * 60)
                print(f"🎯 TRAINING {symbol} {timeframe}")
                print("=" * 60)
                print(f"📊 Trades: {len(group_data)}")

                # DEBUG: Group data analysis
                print(f"🔍 DEBUG: Group data for {symbol} {timeframe}")
                print(f"   Group shape: {group_data.shape}")
                print(f"   Group columns: {list(group_data.columns)}")
                if 'direction' in group_data.columns:
                    direction_counts = group_data['direction'].value_counts()
                    print(f"   Direction distribution: {direction_counts.to_dict()}")
                if 'success' in group_data.columns:
                    success_rate = group_data['success'].mean()
                    print(f"   Success rate: {success_rate:.3f}")
                print("=" * 60)

                if len(group_data) < 20:
                    print(f"⚠️  Insufficient data for {symbol} {timeframe} (need at least 20 trades)")
                    continue

                # Train directional models for this symbol+timeframe combination
                if self.train_directional_models:
                    # Train buy model for this symbol+timeframe
                    print(f"\n🎯 Training BUY model for {symbol} {timeframe}")
                    X_buy, y_buy, buy_features = self.prepare_features(group_data, 'buy')
                    if len(X_buy) >= 10:  # Minimum for buy model
                        model_name = f'buy_{symbol}_PERIOD_{timeframe}'
                        if self.train_with_time_series_validation(X_buy, y_buy, buy_features, model_name):
                            success_count += 1
                            print(f"✅ Successfully trained buy model for {symbol} {timeframe}")
                        else:
                            print(f"❌ Failed to train buy model for {symbol} {timeframe}")
                    else:
                        print(f"⚠️  Insufficient buy trades for {symbol} {timeframe} (need at least 10)")

                    # Train sell model for this symbol+timeframe
                    print(f"\n🎯 Training SELL model for {symbol} {timeframe}")
                    X_sell, y_sell, sell_features = self.prepare_features(group_data, 'sell')
                    if len(X_sell) >= 10:  # Minimum for sell model
                        model_name = f'sell_{symbol}_PERIOD_{timeframe}'
                        if self.train_with_time_series_validation(X_sell, y_sell, sell_features, model_name):
                            success_count += 1
                            print(f"✅ Successfully trained sell model for {symbol} {timeframe}")
                        else:
                            print(f"❌ Failed to train sell model for {symbol} {timeframe}")
                    else:
                        print(f"⚠️  Insufficient sell trades for {symbol} {timeframe} (need at least 10)")

                # Train combined model for this symbol+timeframe
                print(f"\n🎯 Training COMBINED model for {symbol} {timeframe}")
                X_combined, y_combined, combined_features = self.prepare_features(group_data)
                if len(X_combined) >= 20:  # Minimum for combined model
                    model_name = f'combined_{symbol}_PERIOD_{timeframe}'
                    if self.train_with_time_series_validation(X_combined, y_combined, combined_features, model_name):
                        success_count += 1
                        print(f"✅ Successfully trained combined model for {symbol} {timeframe}")
                    else:
                        print(f"❌ Failed to train combined model for {symbol} {timeframe}")
                else:
                    print(f"⚠️  Insufficient data for combined model {symbol} {timeframe} (need at least 20)")

            print(f"\n📊 Training Summary:")
            print(f"   Total symbol+timeframe combinations: {total_combinations}")
            print(f"   Successfully trained models: {success_count}")
            print(f"   Success rate: {(success_count/total_combinations)*100:.1f}%")

            return success_count > 0
        else:
            print("⚠️  Missing 'symbol' or 'timeframe' columns, falling back to combined model")
            return self._train_combined_model(df)

    def _train_combined_model(self, df):
        """Train combined model when no timeframe separation is possible"""
        print("🎯 Training combined model (no timeframe separation)...")

        # Train directional models only if requested
        if self.train_directional_models:
            print("\n" + "=" * 60)
            print("🎯 TRAINING BUY MODEL")
            print("=" * 60)

            X_buy, y_buy, buy_features = self.prepare_features(df, 'buy')
            if len(X_buy) > 50:  # Lowered from 100 to 50 for current dataset
                if len(X_buy) < 100:
                    print("⚠️  WARNING: Small dataset detected. Model may overfit.")
                    print("   Consider collecting more data (100+ trades recommended)")
                self.train_with_time_series_validation(X_buy, y_buy, buy_features, 'buy')
            else:
                print("⚠️  Insufficient data for buy model (need at least 50 trades)")

            print("\n" + "=" * 60)
            print("🎯 TRAINING SELL MODEL")
            print("=" * 60)

            X_sell, y_sell, sell_features = self.prepare_features(df, 'sell')
            if len(X_sell) > 50:  # Lowered from 100 to 50 for current dataset
                if len(X_sell) < 100:
                    print("⚠️  WARNING: Small dataset detected. Model may overfit.")
                    print("   Consider collecting more data (100+ trades recommended)")
                self.train_with_time_series_validation(X_sell, y_sell, sell_features, 'sell')
            else:
                print("⚠️  Insufficient data for sell model (need at least 50 trades)")
        else:
            print("ℹ️  Skipping directional models (train_directional_models=False)")

        print("\n" + "=" * 60)
        print("🎯 TRAINING COMBINED MODEL")
        print("=" * 60)

        X_combined, y_combined, combined_features = self.prepare_features(df)
        if len(X_combined) > 50:  # Lowered from 100 to 50 for current dataset
            if len(X_combined) < 100:
                print("⚠️  WARNING: Small dataset detected. Model may overfit.")
                print("   Consider collecting more data (100+ trades recommended)")
            self.train_with_time_series_validation(X_combined, y_combined, combined_features)
        else:
            print("⚠️  Insufficient data for combined model (need at least 50 trades)")

        return True

    def _generate_symbol_timeframe_parameters(self):
        """Generate symbol+timeframe-specific parameter files"""
        print("📊 Generating symbol+timeframe-specific parameter files...")

        # Get unique symbol+timeframe combinations from training history
        symbol_timeframes = set()
        for history in self.training_history:
            direction = history['direction']
            if direction and '_' in direction:
                # Parse direction like: buy_EURUSD_PERIOD_M5, sell_XAUUSD_PERIOD_H1
                parts = direction.split('_')
                if len(parts) >= 4 and parts[1] != 'PERIOD':
                    # New format: buy_EURUSD_PERIOD_M5
                    symbol = parts[1]
                    timeframe = parts[3]  # After PERIOD_
                    symbol_timeframes.add((symbol, timeframe))
                elif len(parts) >= 3 and parts[1] == 'PERIOD':
                    # Old format: buy_PERIOD_M5
                    timeframe = parts[2]
                    symbol_timeframes.add(('unknown', timeframe))

        print(f"📊 Found symbol+timeframe combinations: {symbol_timeframes}")

        for symbol, timeframe in symbol_timeframes:
            self._generate_symbol_timeframe_parameters(symbol, timeframe)

    def _generate_symbol_timeframe_parameters(self, symbol, timeframe):
        """Generate parameters for a specific symbol+timeframe combination"""
        print(f"📊 Generating parameters for {symbol} {timeframe}...")

        # Find models for this symbol+timeframe combination
        models = {}
        for history in self.training_history:
            direction = history['direction']
            if direction:
                parts = direction.split('_')
                # Handle both naming formats:
                # Format 1: buy_{symbol}_PERIOD_PERIOD_{timeframe} (actual format)
                # Format 2: buy_{symbol}_PERIOD_{timeframe} (expected format)
                if len(parts) >= 4:
                    if parts[1] == symbol and parts[3] == timeframe:
                        # Format 2: buy_{symbol}_PERIOD_{timeframe}
                        model_type = parts[0]  # buy, sell, or combined
                        models[model_type] = history
                    elif len(parts) >= 5 and parts[1] == symbol and parts[4] == timeframe:
                        # Format 1: buy_{symbol}_PERIOD_PERIOD_{timeframe}
                        model_type = parts[0]  # buy, sell, or combined
                        models[model_type] = history

        if not models:
            print(f"⚠️  No models found for {symbol} {timeframe}")
            return

        # Generate parameter file content
        param_content = f"# ML Model Parameters for {symbol} {timeframe}\n"
        param_content += f"# Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"

        # Add model performance metrics
        param_content += f"# Model Performance Metrics\n"
        for model_type, history in models.items():
            param_content += f"{model_type.upper()}_MODEL_ACCURACY = {history['avg_accuracy']:.3f}\n"
            param_content += f"{model_type.upper()}_MODEL_AUC = {history['avg_auc']:.3f}\n"
            param_content += f"{model_type.upper()}_MODEL_SAMPLES = {history['n_samples']}\n"
            param_content += f"{model_type.upper()}_MODEL_FEATURES = {history['n_features']}\n\n"

        # Add top features for each model
        param_content += f"# Top Features by Model\n"
        for model_type, history in models.items():
            top_features = sorted(history['feature_importance'].items(), key=lambda x: x[1], reverse=True)[:10]
            param_content += f"{model_type.upper()}_TOP_FEATURES = {[f[0] for f in top_features]}\n"
            param_content += f"{model_type.upper()}_FEATURE_IMPORTANCE = {dict(top_features)}\n\n"

        # Add symbol+timeframe specific settings
        param_content += f"# Symbol+Timeframe Specific Settings\n"
        param_content += f"SYMBOL = {symbol}\n"
        param_content += f"TIMEFRAME = {timeframe}\n"
        param_content += f"MODEL_COMBINATION = {list(models.keys())}\n\n"

        # Add recommended thresholds based on model performance
        param_content += f"# Recommended Thresholds\n"
        best_model = max(models.items(), key=lambda x: x[1]['avg_accuracy'])
        best_accuracy = best_model[1]['avg_accuracy']

        if best_accuracy > 0.7:
            confidence_threshold = 0.6
            param_content += f"CONFIDENCE_THRESHOLD = {confidence_threshold}\n"
            param_content += f"# High accuracy model - can use lower confidence threshold\n"
        elif best_accuracy > 0.6:
            confidence_threshold = 0.7
            param_content += f"CONFIDENCE_THRESHOLD = {confidence_threshold}\n"
            param_content += f"# Medium accuracy model - use moderate confidence threshold\n"
        else:
            confidence_threshold = 0.8
            param_content += f"CONFIDENCE_THRESHOLD = {confidence_threshold}\n"
            param_content += f"# Lower accuracy model - use higher confidence threshold\n"

        # Save parameter file
        param_filename = f"ml_model_params_{symbol}_PERIOD_{timeframe}.txt"
        param_filepath = os.path.join(self.models_dir, param_filename)

        try:
            with open(param_filepath, 'w') as f:
                f.write(param_content)
            print(f"✅ Generated parameter file: {param_filename}")
        except Exception as e:
            print(f"❌ Failed to generate parameter file for {symbol} {timeframe}: {e}")

    def _generate_timeframe_parameters(self, timeframe):
        """Generate parameters for a specific timeframe (legacy method for backward compatibility)"""
        print(f"📊 Generating parameters for timeframe {timeframe}...")

        # This is now a legacy method - the new approach uses symbol+timeframe combinations
        # For backward compatibility, we'll create a basic parameter file
        param_content = f"# ML Model Parameters for {timeframe}\n"
        param_content += f"# Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        param_content += f"# Note: This is a legacy timeframe-only parameter file\n"
        param_content += f"# Consider using symbol+timeframe specific models for better performance\n\n"
        param_content += f"TIMEFRAME = {timeframe}\n"
        param_content += f"LEGACY_MODE = true\n\n"

        # Save parameter file
        param_filename = f"ml_model_params_PERIOD_{timeframe}.txt"
        param_filepath = os.path.join(self.models_dir, param_filename)

        try:
            with open(param_filepath, 'w') as f:
                f.write(param_content)
            print(f"✅ Generated legacy parameter file: {param_filename}")
        except Exception as e:
            print(f"❌ Failed to generate parameter file for {timeframe}: {e}")

    def retrain_models(self, symbol: str, timeframe: str, training_data: list, models_dir: str = None) -> bool:
        """
        Retrain models with new live trade data

        Args:
            symbol: Trading symbol (e.g., 'XAUUSD+')
            timeframe: Timeframe (e.g., 'H1')
            training_data: List of trade dictionaries with features and labels
            models_dir: Directory to save retrained models

        Returns:
            bool: True if retraining successful, False otherwise
        """
        try:
            print(f"🔄 Retraining models for {symbol} {timeframe} with {len(training_data)} trades")

            # Use provided models_dir or default
            if models_dir:
                self.models_dir = models_dir

            # Convert training data to DataFrame
            df = pd.DataFrame(training_data)

            if len(df) < 10:
                print(f"⚠️ Insufficient training data: {len(df)} trades")
                return False

            # Prepare features and labels
            X = np.array([trade['features'] for trade in training_data])
            y = np.array([trade['label'] for trade in training_data])

            # Define feature names (24 universal features)
            feature_names = [
                'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
                'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum', 'force_index',
                'volume_ratio', 'price_change', 'volatility', 'spread',
                'session_hour', 'is_news_time', 'day_of_week', 'month'
            ]

            print(f"📊 Training data shape: {X.shape}")
            print(f"📊 Feature names: {len(feature_names)} features")

            # Train buy model
            if self.train_directional_models:
                print("🔄 Training buy model...")
                buy_success = self._train_retrain_model(
                    X, y, feature_names, 'buy', symbol, timeframe
                )
            else:
                buy_success = True

            # Train sell model
            if self.train_directional_models:
                print("🔄 Training sell model...")
                sell_success = self._train_retrain_model(
                    X, y, feature_names, 'sell', symbol, timeframe
                )
            else:
                sell_success = True

            # Train combined model
            print("🔄 Training combined model...")
            combined_success = self._train_retrain_model(
                X, y, feature_names, 'combined', symbol, timeframe
            )

            if buy_success and sell_success and combined_success:
                print(f"✅ Retraining completed successfully for {symbol} {timeframe}")
                return True
            else:
                print(f"❌ Some models failed to retrain for {symbol} {timeframe}")
                return False

        except Exception as e:
            print(f"❌ Error during retraining: {e}")
            import traceback
            traceback.print_exc()
            return False

    def _train_retrain_model(self, X: np.ndarray, y: np.array, feature_names: list,
                           model_type: str, symbol: str, timeframe: str) -> bool:
        """Train a specific model type for retraining"""
        try:
            # Create and train model
            model = RandomForestClassifier(
                n_estimators=100,
                max_depth=10,
                min_samples_split=5,
                min_samples_leaf=2,
                random_state=42
            )

            # Fit the model
            model.fit(X, y)

            # Create scaler (for consistency with existing models)
            scaler = StandardScaler()
            scaler.fit(X)

            # Save model files
            model_filename = f"{model_type}_model_{symbol}_PERIOD_{timeframe}.pkl"
            scaler_filename = f"{model_type}_scaler_{symbol}_PERIOD_{timeframe}.pkl"
            feature_names_filename = f"{model_type}_feature_names_{symbol}_PERIOD_{timeframe}.pkl"

            model_path = os.path.join(self.models_dir, model_filename)
            scaler_path = os.path.join(self.models_dir, scaler_filename)
            feature_names_path = os.path.join(self.models_dir, feature_names_filename)

            # Save model
            joblib.dump(model, model_path)

            # Save scaler
            joblib.dump(scaler, scaler_path)

            # Save feature names
            joblib.dump(feature_names, feature_names_path)

            print(f"✅ Saved {model_type} model: {model_filename}")
            return True

        except Exception as e:
            print(f"❌ Error training {model_type} model: {e}")
            return False

def main():
    """Main function"""
    import argparse

    parser = argparse.ArgumentParser(description='Improved ML Trainer')
    parser.add_argument('--ea', type=str, help='Target EA name')
    parser.add_argument('--data-dir', type=str, help='Data directory')
    parser.add_argument('--models-dir', type=str, default='ml_models/', help='Models directory')
    parser.add_argument('--no-directional', action='store_true', help='Train only combined models (no buy/sell models)')
    parser.add_argument('--data-pattern', type=str, default='*_ML_Data.json', help='File pattern for data files')

    args = parser.parse_args()

    # Initialize trainer
    trainer = ImprovedMLTrainer(
        data_dir=args.data_dir,
        models_dir=args.models_dir,
        target_ea=args.ea,
        train_directional_models=not args.no_directional  # Invert the flag
    )

    # Run training with custom data pattern
    success = trainer.run_improved_training(data_pattern=args.data_pattern)

    if success:
        print("\n🎉 Training completed successfully!")
        print("📁 Check the ml_models/ directory for improved models and parameters")
    else:
        print("\n❌ Training failed")
        return 1

    return 0

if __name__ == "__main__":
    exit(main())
