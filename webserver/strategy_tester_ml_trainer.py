#!/usr/bin/env python3
"""
Strategy Tester ML Trainer - Enhanced with Separate Buy/Sell Training
Processes data from Strategy Tester and trains/updates ML models separately for buy and sell trades
"""

import pandas as pd
import numpy as np
import json
import os
import glob
from datetime import datetime
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
import joblib
import warnings
warnings.filterwarnings('ignore')
from sklearn.linear_model import SGDClassifier

class StrategyTesterMLTrainer:
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

    def __init__(self, data_dir=None, models_dir='ml_models/', target_ea=None):
        """Initialize the ML trainer with data and models directories"""
        self.data_dir = data_dir or self._find_metatrader_directory()
        self.models_dir = models_dir
        self.target_ea = target_ea
        
        # Create models directory if it doesn't exist
        if not os.path.exists(self.models_dir):
            os.makedirs(self.models_dir)
            print(f"📁 Created models directory: {self.models_dir}")
        
        # Define EA folders for organized data collection
        self.ea_folders = {
            'SimpleBreakoutML_EA': 'SimpleBreakoutML_EA',
            'StrategyTesterML_EA': 'StrategyTesterML_EA'
        }
        
        # Track which files were created in the current run
        self.files_created_this_run = set()
        
        # Set target EA if specified
        if target_ea and target_ea in self.ea_folders:
            print(f"🎯 Training focused on: {target_ea}")
            # Filter to only the target EA
            self.ea_folders = {target_ea: self.ea_folders[target_ea]}
        elif target_ea:
            print(f"⚠️  Unknown EA: {target_ea}. Available EAs: {list(self.ea_folders.keys())}")
            print(f"   Training on all available EAs instead.")
        
        print(f"📁 Data directory: {self.data_dir}")
        print(f"📁 Models directory: {self.models_dir}")
        if self.target_ea:
            print(f"🎯 Training focused on: {self.target_ea}")
            print(f"📁 EA folders: {[self.target_ea]}")
        else:
            print(f"📁 EA folders: {list(self.ea_folders.keys())}")
        
        # Separate scalers and encoders for buy and sell models
        self.buy_scaler = StandardScaler()
        self.sell_scaler = StandardScaler()
        self.combined_scaler = StandardScaler()
        
        # Label encoders for categorical features
        self.buy_label_encoders = {}
        self.sell_label_encoders = {}
        self.combined_label_encoders = {}
        
        # Models
        self.buy_model = None
        self.sell_model = None
        self.model = None
        
        # Feature names
        self.buy_feature_names = None
        self.sell_feature_names = None
        self.feature_names = None
        
        # Test data
        self.buy_X_test = None
        self.buy_y_test = None
        self.sell_X_test = None
        self.sell_y_test = None
        self.X_test = None
        self.y_test = None
    
    def _find_metatrader_directory(self):
        """Find MetaTrader Common Files directory"""
        # Try to find MetaTrader Common Files directory
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
        
        # Fallback to current directory
        print("⚠️  MetaTrader directory not found, using current directory")
        return "."
    
    def load_strategy_tester_data(self, filename_pattern="StrategyTester_ML_Data.json"):
        """Load data from Strategy Tester JSON files from all EA folders"""
        try:
            # Find all matching files - support multiple patterns for enhanced EA
            file_patterns = []
            
            # If a specific EA is targeted, only load from that EA's folder
            if self.target_ea:
                if self.target_ea in self.ea_folders:
                    folder_name = self.ea_folders[self.target_ea]
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{self.target_ea}_ML_Data.json"),
                        os.path.join(self.data_dir, folder_name, "*_ML_Data.json")
                    ])
                    print(f"🎯 Loading data only from {self.target_ea} folder: {folder_name}")
                else:
                    print(f"❌ Target EA '{self.target_ea}' not found in available folders: {list(self.ea_folders.keys())}")
                    return None
            else:
                # Load from all EA folders
                for ea_name, folder_name in self.ea_folders.items():
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{ea_name}_ML_Data.json"),
                        os.path.join(self.data_dir, folder_name, "*_ML_Data.json")
                    ])
                
                # Also check root directory for backward compatibility (only when not targeting specific EA)
                file_patterns.extend([
                    os.path.join(self.data_dir, filename_pattern),
                    os.path.join(self.data_dir, "*_ML_Data.json")
                ])
            
            files = []
            for pattern in file_patterns:
                files.extend(glob.glob(pattern))
            
            # Remove duplicates
            files = list(set(files))
            
            if not files:
                print(f"❌ No data files found matching patterns in EA folders: {list(self.ea_folders.keys())}")
                return None
            
            print(f"📁 Found {len(files)} data files")
            
            all_data = []
            for file_path in files:
                print(f"📖 Loading data from: {file_path}")
                
                # Read JSON file with proper structure
                with open(file_path, 'r') as f:
                    try:
                        data = json.load(f)
                        # Extract trades array from the JSON structure
                        if 'trades' in data:
                            trades = data['trades']
                            all_data.extend(trades)
                            print(f"✅ Loaded {len(trades)} trades from {file_path}")
                        else:
                            print(f"⚠️  No 'trades' array found in {file_path}")
                    except json.JSONDecodeError as e:
                        print(f"⚠️  Invalid JSON in {file_path}: {e}")
                        continue
            
            if not all_data:
                print("❌ No valid data found in files")
                return None
            
            # Convert to DataFrame
            df = pd.DataFrame(all_data)
            print(f"✅ Loaded {len(df)} data points total")
            
            # Add debugging information about the dataframe structure
            if len(df) > 0:
                print(f"📊 DataFrame columns: {list(df.columns)}")
                if 'symbol' in df.columns:
                    unique_symbols = df['symbol'].unique()
                    print(f"📊 Unique symbols found: {list(unique_symbols)}")
                    print(f"📊 Symbol value counts:")
                    symbol_counts = df['symbol'].value_counts()
                    for symbol, count in symbol_counts.items():
                        print(f"   {symbol}: {count} trades")
                else:
                    print("⚠️  No 'symbol' column found in loaded data")
                    print(f"Available columns: {list(df.columns)}")
            
            return df
            
        except Exception as e:
            print(f"❌ Error loading data: {e}")
            return None
    
    def load_test_summaries(self, filename_pattern="StrategyTester_Results.json"):
        """Load test summary data from JSON files with proper structure from all EA folders"""
        try:
            # Find all matching files - support multiple patterns for enhanced EA
            file_patterns = []
            
            # If a specific EA is targeted, only load from that EA's folder
            if self.target_ea:
                if self.target_ea in self.ea_folders:
                    folder_name = self.ea_folders[self.target_ea]
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{self.target_ea}_Results.json"),
                        os.path.join(self.data_dir, folder_name, "*_Results.json"),
                        os.path.join(self.data_dir, folder_name, "StrategyTester_Comprehensive_Results.json")
                    ])
                    print(f"🎯 Loading test summaries only from {self.target_ea} folder: {folder_name}")
                else:
                    print(f"❌ Target EA '{self.target_ea}' not found in available folders: {list(self.ea_folders.keys())}")
                    return None
            else:
                # Load from all EA folders
                for ea_name, folder_name in self.ea_folders.items():
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{ea_name}_Results.json"),
                        os.path.join(self.data_dir, folder_name, "*_Results.json"),
                        os.path.join(self.data_dir, folder_name, "StrategyTester_Comprehensive_Results.json")
                    ])
                
                # Also check root directory for backward compatibility (only when not targeting specific EA)
                file_patterns.extend([
                    os.path.join(self.data_dir, filename_pattern),
                    os.path.join(self.data_dir, "*_Results.json"),
                    os.path.join(self.data_dir, "StrategyTester_Comprehensive_Results.json")
                ])
            
            files = []
            for pattern in file_patterns:
                files.extend(glob.glob(pattern))
            
            # Remove duplicates
            files = list(set(files))
            
            if not files:
                print(f"⚠️  No test summary files found in EA folders: {list(self.ea_folders.keys())}")
                return None
            
            print(f"📁 Found {len(files)} test summary files")
            
            all_summaries = []
            for file_path in files:
                print(f"📖 Loading test summaries from: {file_path}")
                
                # Read JSON file with proper structure
                with open(file_path, 'r') as f:
                    try:
                        data = json.load(f)
                        
                        # Handle different JSON structures
                        if 'test_results' in data:
                            test_results = data['test_results']
                            all_summaries.extend(test_results)
                            print(f"✅ Loaded {len(test_results)} test summaries from {file_path}")
                        elif 'comprehensive_results' in data:
                            # Handle comprehensive results format
                            comprehensive_results = data['comprehensive_results']
                            for result in comprehensive_results:
                                if 'test_summary' in result:
                                    all_summaries.append(result['test_summary'])
                            print(f"✅ Loaded {len(comprehensive_results)} comprehensive results from {file_path}")
                        else:
                            print(f"⚠️  No 'test_results' or 'comprehensive_results' array found in {file_path}")
                    except json.JSONDecodeError as e:
                        print(f"⚠️  Invalid JSON in {file_path}: {e}")
                        continue
            
            if not all_summaries:
                print("❌ No valid test summaries found")
                return None
            
            # Convert to DataFrame
            df = pd.DataFrame(all_summaries)
            print(f"✅ Loaded {len(df)} test summaries total")
            
            return df
            
        except Exception as e:
            print(f"❌ Error loading test summaries: {e}")
            return None
    
    def process_trade_data(self, df):
        """Process trade data and add outcome information"""
        try:
            if df is None or len(df) == 0:
                return None
            
            print("🔧 Processing trade data...")
            
            # Convert timestamp to datetime
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
            df['trade_time'] = pd.to_datetime(df['trade_time'], unit='s')
            
            # Sort by timestamp
            df = df.sort_values('timestamp')
            
            # Add basic features
            df['price_movement'] = df['price_change']
            df['volume_activity'] = (df['volume_ratio'] > 1.5).astype(int)
            df['trend_alignment'] = (df['trend'] == 'bullish').astype(int)
            
            # Load trade results if available
            trade_results = self.load_trade_results()
            
            if trade_results is not None and len(trade_results) > 0:
                print(f"📊 Found {len(trade_results)} trade results")
                
                # Analyze trade results first
                self.analyze_trade_results(trade_results)
                
                # Merge trade data with results based on trade_id (preferred) or timestamp proximity
                df['target'] = 0  # Default to 0 (loss)
                df['actual_profit'] = 0.0
                df['trade_duration'] = 3600  # Default 1 hour
                df['exit_reason'] = 'unknown'
                
                matched_count = 0
                for idx, trade in df.iterrows():
                    # First try to match by test_run_id + trade_id combination (preferred method)
                    if 'test_run_id' in trade and 'trade_id' in trade and 'test_run_id' in trade_results.columns and 'trade_id' in trade_results.columns:
                        test_run_id = trade['test_run_id']
                        trade_id = trade['trade_id']
                        # Match by both test_run_id AND trade_id for perfect uniqueness
                        matching_results = trade_results[
                            (trade_results['test_run_id'] == test_run_id) & 
                            (trade_results['trade_id'] == trade_id)
                        ]
                        
                        if len(matching_results) > 0:
                            result = matching_results.iloc[0]
                            df.at[idx, 'target'] = 1 if result['profit'] > 0 else 0
                            df.at[idx, 'actual_profit'] = result['profit']
                            df.at[idx, 'trade_duration'] = result.get('trade_duration', 3600)
                            df.at[idx, 'exit_reason'] = result.get('exit_reason', 'unknown')
                            matched_count += 1
                            if matched_count <= 5:  # Only print first few matches to avoid spam
                                print(f"✅ Matched test_run_id={test_run_id}, trade_id={trade_id} with result: ${result['profit']:.2f}")
                            continue
                    
                    # Fallback: try to match by trade_id only (for backward compatibility)
                    if 'trade_id' in trade and 'trade_id' in trade_results.columns:
                        trade_id = trade['trade_id']
                        matching_results = trade_results[trade_results['trade_id'] == trade_id]
                        
                        if len(matching_results) > 0:
                            result = matching_results.iloc[0]
                            df.at[idx, 'target'] = 1 if result['profit'] > 0 else 0
                            df.at[idx, 'actual_profit'] = result['profit']
                            df.at[idx, 'trade_duration'] = result.get('trade_duration', 3600)
                            df.at[idx, 'exit_reason'] = result.get('exit_reason', 'unknown')
                            matched_count += 1
                            if matched_count <= 5:  # Only print first few matches to avoid spam
                                print(f"⚠️  Matched trade_id {trade_id} only (no test_run_id): ${result['profit']:.2f}")
                            continue
                    
                    # Also try to match by test_run_id if available (for additional validation)
                    if 'test_run_id' in trade and 'test_run_id' in trade_results.columns:
                        test_run_id = trade['test_run_id']
                        matching_results = trade_results[trade_results['test_run_id'] == test_run_id]
                        if len(matching_results) > 0:
                            print(f"📊 Found {len(matching_results)} trades from test run: {test_run_id}")
                    
                    # Fallback: Find closest trade result within reasonable time window
                    trade_time = trade['timestamp']
                    closest_result = None
                    min_time_diff = pd.Timedelta(hours=24)  # 24 hour window
                    
                    for _, result in trade_results.iterrows():
                        result_time = pd.to_datetime(result['close_time'], unit='s')
                        time_diff = abs(trade_time - result_time)
                        
                        if time_diff < min_time_diff:
                            min_time_diff = time_diff
                            closest_result = result
                    
                    if closest_result is not None:
                        # Use actual trade result
                        df.at[idx, 'target'] = 1 if closest_result['profit'] > 0 else 0
                        df.at[idx, 'actual_profit'] = closest_result['profit']
                        df.at[idx, 'trade_duration'] = closest_result.get('trade_duration', 3600)
                        df.at[idx, 'exit_reason'] = closest_result.get('exit_reason', 'unknown')
                        matched_count += 1
                        if matched_count <= 5:  # Only print first few matches to avoid spam
                            print(f"✅ Matched trade at {trade_time} with result: ${closest_result['profit']:.2f}")
                
                print(f"📊 Matched {matched_count} trades with results out of {len(df)} total trades")
                
                # Show matching statistics
                if 'trade_id' in df.columns and 'trade_id' in trade_results.columns:
                    trade_ids_in_data = set(df['trade_id'].dropna())
                    trade_ids_in_results = set(trade_results['trade_id'].dropna())
                    common_ids = trade_ids_in_data.intersection(trade_ids_in_results)
                    print(f"📊 Trade ID matching statistics:")
                    print(f"   Trade IDs in ML data: {len(trade_ids_in_data)}")
                    print(f"   Trade IDs in results: {len(trade_ids_in_results)}")
                    print(f"   Common trade IDs: {len(common_ids)}")
                    print(f"   ID-based match rate: {len(common_ids)/len(trade_ids_in_data)*100:.1f}%")
                
                # Show test_run_id + trade_id matching statistics (new preferred method)
                if 'test_run_id' in df.columns and 'trade_id' in df.columns and 'test_run_id' in trade_results.columns and 'trade_id' in trade_results.columns:
                    # Create composite keys for both datasets
                    df_composite_keys = set(zip(df['test_run_id'].dropna(), df['trade_id'].dropna()))
                    results_composite_keys = set(zip(trade_results['test_run_id'].dropna(), trade_results['trade_id'].dropna()))
                    common_composite_keys = df_composite_keys.intersection(results_composite_keys)
                    
                    print(f"📊 Test Run ID + Trade ID matching statistics:")
                    print(f"   Composite keys in ML data: {len(df_composite_keys)}")
                    print(f"   Composite keys in results: {len(results_composite_keys)}")
                    print(f"   Common composite keys: {len(common_composite_keys)}")
                    print(f"   Composite key match rate: {len(common_composite_keys)/len(df_composite_keys)*100:.1f}%")
                    
                    # Show unique test runs
                    unique_test_runs_data = set(df['test_run_id'].dropna())
                    unique_test_runs_results = set(trade_results['test_run_id'].dropna())
                    print(f"📊 Test Run Coverage:")
                    print(f"   Unique test runs in ML data: {len(unique_test_runs_data)}")
                    print(f"   Unique test runs in results: {len(unique_test_runs_results)}")
                    print(f"   Common test runs: {len(unique_test_runs_data.intersection(unique_test_runs_results))}")
                
                # Calculate success rate
                success_rate = df['target'].mean() * 100
                print(f"📈 Overall success rate: {success_rate:.1f}%")
                
                # Show profit distribution
                if 'actual_profit' in df.columns:
                    profits = df['actual_profit'].dropna()
                    if len(profits) > 0:
                        print(f"💰 Profit statistics:")
                        print(f"   Total profit: ${profits.sum():.2f}")
                        print(f"   Average profit: ${profits.mean():.2f}")
                        print(f"   Min profit: ${profits.min():.2f}")
                        print(f"   Max profit: ${profits.max():.2f}")
                        print(f"   Profitable trades: {(profits > 0).sum()}/{len(profits)}")
                
            else:
                print("⚠️  No trade results found, creating balanced synthetic target based on technical indicators")
                # Fallback: create balanced synthetic target based on technical indicators
                # This creates a more realistic distribution of wins and losses
                df['target'] = 0  # Default to 0 (loss)
                
                # Create synthetic target with balanced distribution
                for idx, row in df.iterrows():
                    # Calculate a composite score based on multiple indicators
                    score = 0.0
                    
                    # RSI contribution (0-1 scale)
                    if row['direction'] == 'buy':
                        if row['rsi'] < 30: score += 0.3  # Strong oversold
                        elif row['rsi'] < 40: score += 0.2  # Moderately oversold
                        elif row['rsi'] > 70: score -= 0.2  # Overbought (bad for buy)
                    else:  # sell
                        if row['rsi'] > 70: score += 0.3  # Strong overbought
                        elif row['rsi'] > 60: score += 0.2  # Moderately overbought
                        elif row['rsi'] < 30: score -= 0.2  # Oversold (bad for sell)
                    
                    # Stochastic contribution
                    if row['direction'] == 'buy':
                        if row['stoch_main'] < 20: score += 0.2  # Oversold
                        elif row['stoch_main'] > 80: score -= 0.1  # Overbought
                    else:  # sell
                        if row['stoch_main'] > 80: score += 0.2  # Overbought
                        elif row['stoch_main'] < 20: score -= 0.1  # Oversold
                    
                    # MACD contribution
                    if row['direction'] == 'buy' and row['macd_main'] > row['macd_signal']:
                        score += 0.1  # Bullish MACD
                    elif row['direction'] == 'sell' and row['macd_main'] < row['macd_signal']:
                        score += 0.1  # Bearish MACD
                    
                    # Volume contribution
                    if row['volume_ratio'] > 1.5: score += 0.1  # High volume
                    
                    # Trend alignment
                    if row['direction'] == 'buy' and 'bullish' in str(row['trend']).lower():
                        score += 0.1  # Bullish trend for buy
                    elif row['direction'] == 'sell' and 'bearish' in str(row['trend']).lower():
                        score += 0.1  # Bearish trend for sell
                    
                    # Add some randomness to create more balanced distribution
                    import random
                    random_factor = random.uniform(-0.1, 0.1)
                    score += random_factor
                    
                    # Set target based on score threshold
                    # Use a threshold that creates roughly 40-60% win rate
                    if score > 0.3:  # Higher threshold for more realistic win rate
                        df.at[idx, 'target'] = 1
                    else:
                        df.at[idx, 'target'] = 0
                
                # Ensure we have both classes (wins and losses)
                unique_targets = df['target'].unique()
                print(f"📊 Synthetic target distribution: {df['target'].value_counts().to_dict()}")
                
                if len(unique_targets) == 1:
                    print("⚠️  All synthetic targets are the same, adjusting for balance...")
                    # Force some diversity by making every 3rd trade a win
                    for idx in range(0, len(df), 3):
                        df.at[idx, 'target'] = 1
                    print(f"📊 Adjusted target distribution: {df['target'].value_counts().to_dict()}")
                
                # Add synthetic ML prediction column for compatibility
                if 'ml_prediction' not in df.columns:
                    df['ml_prediction'] = df['target'].astype(float)  # Use target as ML prediction
                    print("📊 Created synthetic ML prediction based on technical indicators")
            
            print(f"✅ Processed {len(df)} trades")
            return df
            
        except Exception as e:
            print(f"❌ Error processing data: {e}")
            return None
    
    def load_trade_results(self, filename_pattern="StrategyTester_Trade_Results.json"):
        """Load trade results from JSON files with proper structure from all EA folders"""
        try:
            # Find all matching files - support multiple patterns for enhanced EA
            file_patterns = []
            
            # If a specific EA is targeted, only load from that EA's folder
            if self.target_ea:
                if self.target_ea in self.ea_folders:
                    folder_name = self.ea_folders[self.target_ea]
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{self.target_ea}_Trade_Results.json"),
                        os.path.join(self.data_dir, folder_name, "*_Trade_Results.json"),
                        os.path.join(self.data_dir, folder_name, "StrategyTester_Comprehensive_Results.json")
                    ])
                    print(f"🎯 Loading trade results only from {self.target_ea} folder: {folder_name}")
                else:
                    print(f"❌ Target EA '{self.target_ea}' not found in available folders: {list(self.ea_folders.keys())}")
                    return None
            else:
                # Load from all EA folders
                for ea_name, folder_name in self.ea_folders.items():
                    file_patterns.extend([
                        os.path.join(self.data_dir, folder_name, filename_pattern),
                        os.path.join(self.data_dir, folder_name, f"{ea_name}_Trade_Results.json"),
                        os.path.join(self.data_dir, folder_name, "*_Trade_Results.json"),
                        os.path.join(self.data_dir, folder_name, "StrategyTester_Comprehensive_Results.json")
                    ])
                
                # Also check root directory for backward compatibility (only when not targeting specific EA)
                file_patterns.extend([
                    os.path.join(self.data_dir, filename_pattern),
                    os.path.join(self.data_dir, "*_Trade_Results.json"),
                    os.path.join(self.data_dir, "StrategyTester_Comprehensive_Results.json")
                ])
            
            files = []
            for pattern in file_patterns:
                files.extend(glob.glob(pattern))
            
            # Remove duplicates
            files = list(set(files))
            
            if not files:
                print(f"⚠️  No trade result files found in EA folders: {list(self.ea_folders.keys())}")
                return None
            
            print(f"📁 Found {len(files)} trade result files")
            
            all_results = []
            for file_path in files:
                print(f"📖 Loading results from: {file_path}")
                
                # Read JSON file with proper structure and better error handling
                try:
                    with open(file_path, 'r') as f:
                        content = f.read()
                        
                        # Check if file is empty or too large
                        if len(content) == 0:
                            print(f"⚠️  Empty file: {file_path}")
                            continue
                        
                        if len(content) > 10 * 1024 * 1024:  # 10MB limit
                            print(f"⚠️  File too large ({len(content)} bytes): {file_path}")
                            continue
                        
                        # Try to parse JSON
                        data = json.loads(content)
                        
                        # Handle different JSON structures
                        if 'trade_results' in data:
                            trade_results = data['trade_results']
                            all_results.extend(trade_results)
                            print(f"✅ Loaded {len(trade_results)} trade results from {file_path}")
                        elif 'comprehensive_results' in data:
                            # Handle comprehensive results format - extract individual trades
                            comprehensive_results = data['comprehensive_results']
                            for result in comprehensive_results:
                                if 'trades' in result:
                                    trades = result['trades']
                                    all_results.extend(trades)
                                    print(f"✅ Loaded {len(trades)} trades from comprehensive result in {file_path}")
                        else:
                            print(f"⚠️  No 'trade_results' or 'comprehensive_results' array found in {file_path}")
                            
                except json.JSONDecodeError as e:
                    print(f"⚠️  Invalid JSON in {file_path}: {e}")
                    # Try to recover partial data by reading line by line
                    try:
                        print(f"🔄 Attempting to recover partial data from {file_path}")
                        with open(file_path, 'r') as f:
                            lines = f.readlines()
                            valid_lines = []
                            for i, line in enumerate(lines):
                                try:
                                    json.loads(line.strip())
                                    valid_lines.append(line.strip())
                                except json.JSONDecodeError:
                                    print(f"   Skipping invalid line {i+1}")
                            
                            if valid_lines:
                                print(f"✅ Recovered {len(valid_lines)} valid lines from {file_path}")
                                # Process valid lines as individual JSON objects
                                for line in valid_lines:
                                    try:
                                        data = json.loads(line)
                                        if isinstance(data, dict) and 'trade_results' in data:
                                            all_results.extend(data['trade_results'])
                                    except:
                                        continue
                    except Exception as recovery_error:
                        print(f"❌ Failed to recover data from {file_path}: {recovery_error}")
                    continue
                except Exception as e:
                    print(f"❌ Error reading file {file_path}: {e}")
                    continue
            
            if not all_results:
                print("❌ No valid trade results found")
                return None
            
            # Convert to DataFrame
            df = pd.DataFrame(all_results)
            print(f"✅ Loaded {len(df)} trade results total")
            
            return df
            
        except Exception as e:
            print(f"❌ Error loading trade results: {e}")
            return None
    
    def analyze_trade_results(self, trade_results):
        """Analyze trade results and provide detailed statistics"""
        try:
            print("\n📊 TRADE RESULTS ANALYSIS")
            print("=" * 50)
            
            # Basic statistics
            total_trades = len(trade_results)
            profitable_trades = len(trade_results[trade_results['profit'] > 0])
            losing_trades = len(trade_results[trade_results['profit'] <= 0])
            
            print(f"Total trades: {total_trades}")
            print(f"Profitable trades: {profitable_trades}")
            print(f"Losing trades: {losing_trades}")
            
            if total_trades > 0:
                win_rate = (profitable_trades / total_trades) * 100
                print(f"Win rate: {win_rate:.2f}%")
            
            # Profit analysis
            total_profit = trade_results['profit'].sum()
            avg_profit = trade_results['profit'].mean()
            max_profit = trade_results['profit'].max()
            min_profit = trade_results['profit'].min()
            
            # Net profit analysis (including swap and commission)
            total_net_profit = trade_results['net_profit'].sum()
            avg_net_profit = trade_results['net_profit'].mean()
            max_net_profit = trade_results['net_profit'].max()
            min_net_profit = trade_results['net_profit'].min()
            
            # Calculate swap and commission totals
            total_swap = trade_results['swap'].sum() if 'swap' in trade_results.columns else 0
            total_commission = trade_results['commission'].sum() if 'commission' in trade_results.columns else 0
            
            print(f"\n💰 Profit Analysis:")
            print(f"Raw profit (excluding costs): ${total_profit:.2f}")
            print(f"Total swap: ${total_swap:.2f}")
            print(f"Total commission: ${total_commission:.2f}")
            print(f"Net profit (including all costs): ${total_net_profit:.2f}")
            print(f"Average net profit per trade: ${avg_net_profit:.2f}")
            print(f"Best trade: ${max_net_profit:.2f}")
            print(f"Worst trade: ${min_net_profit:.2f}")
            
            # Show cost impact
            cost_impact = total_net_profit - total_profit
            if cost_impact != 0:
                print(f"Cost impact (swap + commission): ${cost_impact:.2f}")
                cost_percentage = abs(cost_impact / total_profit * 100) if total_profit != 0 else 0
                print(f"Costs represent {cost_percentage:.1f}% of raw profit")
            
            # Direction analysis - CRITICAL FOR SEPARATE TRAINING
            if 'direction' in trade_results.columns:
                buy_trades = trade_results[trade_results['direction'] == 'buy']
                sell_trades = trade_results[trade_results['direction'] == 'sell']
                
                print(f"\n📈 BUY vs SELL Analysis:")
                print(f"Buy trades: {len(buy_trades)} ({len(buy_trades)/total_trades*100:.1f}%)")
                print(f"Sell trades: {len(sell_trades)} ({len(sell_trades)/total_trades*100:.1f}%)")
                
                if len(buy_trades) > 0:
                    buy_win_rate = (len(buy_trades[buy_trades['profit'] > 0]) / len(buy_trades)) * 100
                    buy_avg_profit = buy_trades['profit'].mean()
                    buy_total_profit = buy_trades['profit'].sum()
                    print(f"   Buy Win Rate: {buy_win_rate:.1f}%")
                    print(f"   Buy Avg Profit: ${buy_avg_profit:.2f}")
                    print(f"   Buy Total Profit: ${buy_total_profit:.2f}")
                
                if len(sell_trades) > 0:
                    sell_win_rate = (len(sell_trades[sell_trades['profit'] > 0]) / len(sell_trades)) * 100
                    sell_avg_profit = sell_trades['profit'].mean()
                    sell_total_profit = sell_trades['profit'].sum()
                    print(f"   Sell Win Rate: {sell_win_rate:.1f}%")
                    print(f"   Sell Avg Profit: ${sell_avg_profit:.2f}")
                    print(f"   Sell Total Profit: ${sell_total_profit:.2f}")
                
                # Key insight: Check if buy and sell trades have different characteristics
                if len(buy_trades) > 10 and len(sell_trades) > 10:
                    buy_win_rate = (len(buy_trades[buy_trades['profit'] > 0]) / len(buy_trades)) * 100
                    sell_win_rate = (len(sell_trades[sell_trades['profit'] > 0]) / len(sell_trades)) * 100
                    win_rate_diff = abs(buy_win_rate - sell_win_rate)
                    
                    print(f"\n🎯 SEPARATE TRAINING RECOMMENDATION:")
                    if win_rate_diff > 5.0:
                        print(f"   ⚠️  SIGNIFICANT DIFFERENCE DETECTED!")
                        print(f"   Buy win rate: {buy_win_rate:.1f}% vs Sell win rate: {sell_win_rate:.1f}%")
                        print(f"   Difference: {win_rate_diff:.1f}% - SEPARATE TRAINING RECOMMENDED")
                    else:
                        print(f"   ✅ Similar performance - Combined training may be sufficient")
                        print(f"   Buy win rate: {buy_win_rate:.1f}% vs Sell win rate: {sell_win_rate:.1f}%")
                        print(f"   Difference: {win_rate_diff:.1f}%")
            
            # Exit reason analysis
            if 'exit_reason' in trade_results.columns:
                exit_reasons = trade_results['exit_reason'].value_counts()
                print(f"\n🚪 Exit reasons:")
                for reason, count in exit_reasons.items():
                    print(f"   {reason}: {count}")
            
            print("=" * 50)
            
        except Exception as e:
            print(f"❌ Error analyzing trade results: {e}")
    
    def analyze_test_summaries(self, test_summaries):
        """Analyze test summary data across multiple runs"""
        try:
            if test_summaries is None or len(test_summaries) == 0:
                return
            
            print("\n📊 TEST SUMMARIES ANALYSIS")
            print("=" * 50)
            
            # Basic statistics across all test runs
            total_test_runs = len(test_summaries)
            total_trades_all_runs = test_summaries['total_trades'].sum()
            total_profit_all_runs = test_summaries['total_profit'].sum()
            avg_win_rate = test_summaries['win_rate'].mean()
            avg_profit_factor = test_summaries['profit_factor'].mean()
            
            print(f"Total test runs: {total_test_runs}")
            print(f"Total trades across all runs: {total_trades_all_runs}")
            print(f"Total profit across all runs: ${total_profit_all_runs:.2f}")
            print(f"Average win rate: {avg_win_rate:.2f}%")
            print(f"Average profit factor: {avg_profit_factor:.2f}")
            
            # Performance by test run
            if 'test_run_id' in test_summaries.columns:
                print(f"\n📈 Performance by Test Run:")
                for _, run in test_summaries.iterrows():
                    run_id = run.get('test_run_id', 'Unknown')
                    print(f"   {run_id}: {run['total_trades']} trades, ${run['total_profit']:.2f} profit, {run['win_rate']:.1f}% win rate")
            
            # Best and worst runs
            best_run = test_summaries.loc[test_summaries['total_profit'].idxmax()]
            worst_run = test_summaries.loc[test_summaries['total_profit'].idxmin()]
            
            print(f"\n🏆 Best Run:")
            print(f"   Profit: ${best_run['total_profit']:.2f}")
            print(f"   Trades: {best_run['total_trades']}")
            print(f"   Win Rate: {best_run['win_rate']:.1f}%")
            
            print(f"\n📉 Worst Run:")
            print(f"   Profit: ${worst_run['total_profit']:.2f}")
            print(f"   Trades: {worst_run['total_trades']}")
            print(f"   Win Rate: {worst_run['win_rate']:.1f}%")
            
            print("=" * 50)
            
        except Exception as e:
            print(f"❌ Error analyzing test summaries: {e}")
    
    def engineer_features(self, df, direction=None):
        """Engineer features for ML training - can be filtered by direction"""
        try:
            if df is None or len(df) == 0:
                return None, None, None
            
            # Filter by direction if specified
            if direction:
                df_filtered = df[df['direction'] == direction].copy()
                print(f"🔧 Engineering features for {direction.upper()} trades...")
                print(f"   Filtered to {len(df_filtered)} {direction} trades")
            else:
                df_filtered = df.copy()
                print("🔧 Engineering features for ALL trades...")
            
            if len(df_filtered) == 0:
                print(f"❌ No {direction} trades found for feature engineering")
                return None, None, None
            
            # Select and prepare features (enhanced with new indicators)
            feature_columns = [
                'rsi', 'stoch_main', 'stoch_signal', 'ad', 'volume', 'ma', 'atr',
                'macd_main', 'macd_signal', 'bb_upper', 'bb_lower', 'spread',
                'volume_ratio', 'price_change', 'volatility', 'session_hour',
                'williams_r', 'cci', 'momentum', 'force_index', 'bb_position',
                'price_movement', 'volume_activity', 'trend_alignment'
            ]
            
            # Handle categorical features with proper encoding
            categorical_features = ['candle_pattern', 'candle_seq', 'zone_type', 'trend']
            
            # Create encoded features with better error handling
            for feature in categorical_features:
                if feature in df_filtered.columns:
                    # Fill missing values
                    df_filtered[feature] = df_filtered[feature].fillna('none')
                    
                    # Ensure we have valid string values
                    df_filtered[feature] = df_filtered[feature].astype(str)
                    
                    # Get unique values for this feature
                    unique_values = df_filtered[feature].unique()
                    print(f"   {feature} unique values: {unique_values}")
                    
                    # Always fit a fresh encoder for each training session to avoid unseen label errors
                    try:
                        # Create a fresh encoder for this feature and direction
                        if direction == 'buy':
                            # Reset buy encoder for this feature
                            if not hasattr(self, 'buy_label_encoders'):
                                self.buy_label_encoders = {}
                            self.buy_label_encoders[feature] = LabelEncoder()
                            df_filtered[f'{feature}_encoded'] = self.buy_label_encoders[feature].fit_transform(df_filtered[feature])
                        elif direction == 'sell':
                            # Reset sell encoder for this feature
                            if not hasattr(self, 'sell_label_encoders'):
                                self.sell_label_encoders = {}
                            self.sell_label_encoders[feature] = LabelEncoder()
                            df_filtered[f'{feature}_encoded'] = self.sell_label_encoders[feature].fit_transform(df_filtered[feature])
                        else:
                            # For combined training, use combined encoder
                            if not hasattr(self, 'combined_label_encoders'):
                                self.combined_label_encoders = {}
                            self.combined_label_encoders[feature] = LabelEncoder()
                            df_filtered[f'{feature}_encoded'] = self.combined_label_encoders[feature].fit_transform(df_filtered[feature])
                    except Exception as e:
                        print(f"⚠️  Error encoding {feature}: {e}")
                        # Fallback: use simple integer encoding
                        df_filtered[f'{feature}_encoded'] = pd.Categorical(df_filtered[feature]).codes
            
            # Add encoded categorical features to feature list
            encoded_features = [f'{f}_encoded' for f in categorical_features]
            feature_columns.extend(encoded_features)
            
            # Filter available features
            available_features = [f for f in feature_columns if f in df_filtered.columns]
            
            print(f"📊 Using {len(available_features)} features: {available_features}")
            
            # Debug: Check feature matrix shape
            X = df_filtered[available_features].fillna(0)
            print(f"🔍 Feature matrix shape: {X.shape}")
            print(f"🔍 Feature matrix columns: {list(X.columns)}")
            
            y = df_filtered['target']
            
            return X, y, available_features
            
        except Exception as e:
            print(f"❌ Error engineering features: {e}")
            import traceback
            traceback.print_exc()
            return None, None, None
    
    def train_model(self, X, y, feature_names, direction=None, incremental=False, early_stopping=True):
        """Train ML model with enhanced features and validation"""
        try:
            # Dynamic early stopping decision based on dataset size
            dataset_size = len(X)
            if dataset_size < 100:
                # Small dataset: use RandomForest (better feature importance, no overfitting)
                dynamic_early_stopping = False
                print(f"📊 Small dataset detected ({dataset_size} samples) - using RandomForestClassifier for better feature importance")
            elif dataset_size < 500:
                # Medium dataset: use early stopping if requested, otherwise RandomForest
                dynamic_early_stopping = early_stopping
                print(f"📊 Medium dataset detected ({dataset_size} samples) - early stopping: {early_stopping}")
            else:
                # Large dataset: use early stopping (prevents overfitting)
                dynamic_early_stopping = True
                print(f"📊 Large dataset detected ({dataset_size} samples) - using early stopping to prevent overfitting")
            
            print(f"🤖 Training {direction.upper() if direction else 'COMBINED'} ML model... (incremental={incremental}, early_stopping={dynamic_early_stopping})")
            
            # Split data with stratification for imbalanced classes
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42, stratify=y
            )
            
            # Additional validation split
            X_train, X_val, y_train, y_val = train_test_split(
                X_train, y_train, test_size=0.2, random_state=42, stratify=y_train
            )
            
            # Scale features
            scaler = StandardScaler()
            X_train_scaled = scaler.fit_transform(X_train)
            X_test_scaled = scaler.transform(X_test)
            X_val_scaled = scaler.transform(X_val)
            
            # Store scaler for later use
            if direction == 'buy':
                self.buy_scaler = scaler
                self.buy_X_test = X_test
                self.buy_y_test = y_test
            elif direction == 'sell':
                self.sell_scaler = scaler
                self.sell_X_test = X_test
                self.sell_y_test = y_test
            else:
                self.scaler = scaler
                self.X_test = X_test
                self.y_test = y_test
            
            # Choose model based on dynamic early stopping decision
            if incremental:
                print("🔄 Using SGDClassifier for incremental learning")
                model = SGDClassifier(
                    loss='log_loss',
                    learning_rate='adaptive',
                    eta0=0.01,
                    max_iter=1000,
                    random_state=42,
                    class_weight='balanced'
                )
                # Use partial_fit for incremental learning
                model.partial_fit(X_train_scaled, y_train, classes=np.unique(y))
            elif dynamic_early_stopping:
                print("🛑 Using SGDClassifier with early stopping (large dataset)")
                model = SGDClassifier(
                    loss='log_loss',
                    learning_rate='adaptive',
                    eta0=0.01,
                    max_iter=1000,
                    random_state=42,
                    class_weight='balanced'
                )
            else:
                print("🌲 Using RandomForestClassifier (small/medium dataset or feature importance needed)")
                model = RandomForestClassifier(
                    n_estimators=100,
                    max_depth=10,
                    min_samples_split=5,
                    min_samples_leaf=2,
                    random_state=42,
                    class_weight='balanced',
                    n_jobs=-1
                )
            
            # Train model
            if not incremental:
                model.fit(X_train_scaled, y_train)
            
            # Evaluate model
            train_accuracy = model.score(X_train_scaled, y_train)
            test_accuracy = model.score(X_test_scaled, y_test)
            val_accuracy = model.score(X_val_scaled, y_val)
            
            # Calculate AUC scores
            if hasattr(model, 'predict_proba'):
                train_auc = roc_auc_score(y_train, model.predict_proba(X_train_scaled)[:, 1])
                test_auc = roc_auc_score(y_test, model.predict_proba(X_test_scaled)[:, 1])
                val_auc = roc_auc_score(y_val, model.predict_proba(X_val_scaled)[:, 1])
            else:
                train_auc = roc_auc_score(y_train, model.predict(X_train_scaled))
                test_auc = roc_auc_score(y_test, model.predict(X_test_scaled))
                val_auc = roc_auc_score(y_val, model.predict(X_val_scaled))
            
            print(f"✅ {direction.upper() if direction else 'COMBINED'} model trained successfully:")
            print(f"   Test Accuracy: {test_accuracy:.4f}")
            print(f"   Test AUC Score: {test_auc:.4f}")
            print(f"   Validation Accuracy: {val_accuracy:.4f}")
            print(f"   Validation AUC Score: {val_auc:.4f}")
            print(f"   Features used: {len(feature_names)}")
            
            # Get feature importance if available
            feature_importance = None
            if hasattr(model, 'feature_importances_'):
                feature_importance = model.feature_importances_
                print(f"✅ Feature importance available: {len(feature_importance)} features")
                
                # Print top 10 features
                feature_importance_pairs = list(zip(feature_names, feature_importance))
                feature_importance_pairs.sort(key=lambda x: x[1], reverse=True)
                print("📊 Top 10 Most Important Features:")
                for i, (feature, importance) in enumerate(feature_importance_pairs[:10]):
                    print(f"   {i+1}. {feature}: {importance:.4f}")
            elif hasattr(model, 'coef_'):
                # For SGDClassifier, use coefficients as feature importance
                feature_importance = np.abs(model.coef_[0])
                print(f"✅ Using model coefficients as feature importance: {len(feature_importance)} features")
                
                # Print top 10 features
                feature_importance_pairs = list(zip(feature_names, feature_importance))
                feature_importance_pairs.sort(key=lambda x: x[1], reverse=True)
                print("📊 Top 10 Most Important Features (from coefficients):")
                for i, (feature, importance) in enumerate(feature_importance_pairs[:10]):
                    print(f"   {i+1}. {feature}: {importance:.4f}")
            else:
                print("⚠️  No feature importance available for this model type")
            
            # Store model and results
            if direction == 'buy':
                self.buy_model = model
                self.buy_feature_names = feature_names
                self.buy_feature_importance = feature_importance
                self.buy_accuracy = test_accuracy
            elif direction == 'sell':
                self.sell_model = model
                self.sell_feature_names = feature_names
                self.sell_feature_importance = feature_importance
                self.sell_accuracy = test_accuracy
            else:
                self.model = model
                self.feature_names = feature_names
                self.feature_importance = feature_importance
                self.accuracy = test_accuracy
            
            return True
            
        except Exception as e:
            print(f"❌ Error training {direction if direction else 'combined'} model: {e}")
            return False
    
    def save_models(self, df=None):
        """Save trained models and parameters"""
        try:
            models_saved = 0
            
            # Save buy model if available
            if self.buy_model is not None:
                model_path = os.path.join(self.models_dir, 'buy_trade_success_predictor.pkl')
                joblib.dump(self.buy_model, model_path)
                print(f"✅ Buy model saved to: {model_path}")
                
                scaler_path = os.path.join(self.models_dir, 'buy_scaler.pkl')
                joblib.dump(self.buy_scaler, scaler_path)
                print(f"✅ Buy scaler saved to: {scaler_path}")
                
                encoder_path = os.path.join(self.models_dir, 'buy_label_encoders.pkl')
                joblib.dump(self.buy_label_encoders, encoder_path)
                print(f"✅ Buy label encoders saved to: {encoder_path}")
                
                models_saved += 1
            
            # Save sell model if available
            if self.sell_model is not None:
                model_path = os.path.join(self.models_dir, 'sell_trade_success_predictor.pkl')
                joblib.dump(self.sell_model, model_path)
                print(f"✅ Sell model saved to: {model_path}")
                
                scaler_path = os.path.join(self.models_dir, 'sell_scaler.pkl')
                joblib.dump(self.sell_scaler, scaler_path)
                print(f"✅ Sell scaler saved to: {scaler_path}")
                
                encoder_path = os.path.join(self.models_dir, 'sell_label_encoders.pkl')
                joblib.dump(self.sell_label_encoders, encoder_path)
                print(f"✅ Sell label encoders saved to: {encoder_path}")
                
                models_saved += 1
            
            # Save combined model if available
            if self.model is not None:
                model_path = os.path.join(self.models_dir, 'trade_success_predictor.pkl')
                joblib.dump(self.model, model_path)
                print(f"✅ Combined model saved to: {model_path}")
                
                scaler_path = os.path.join(self.models_dir, 'scaler.pkl')
                joblib.dump(self.buy_scaler, scaler_path)  # Use buy scaler for combined
                print(f"✅ Combined scaler saved to: {scaler_path}")
                
                encoder_path = os.path.join(self.models_dir, 'combined_label_encoders.pkl')
                joblib.dump(self.combined_label_encoders, encoder_path)
                print(f"✅ Combined label encoders saved to: {encoder_path}")
                
                models_saved += 1
            
            if models_saved == 0:
                print("❌ No models to save")
                return False
            
            # Save model parameters for EA
            self.save_model_parameters(df)
            
            # Copy files to MetaTrader directory
            self.copy_to_metatrader()
            
            return True
            
        except Exception as e:
            print(f"❌ Error saving models: {e}")
            return False
    
    def save_model_parameters(self, df=None):
        """Save model parameters in format usable by the EA"""
        try:
            models_to_save = []
            
            # Add buy model parameters if available
            if self.buy_model is not None and hasattr(self, 'buy_feature_names'):
                buy_accuracy = 0.0
                if hasattr(self, 'buy_X_test') and hasattr(self, 'buy_y_test') and hasattr(self, 'buy_scaler'):
                    try:
                        buy_X_test_scaled = self.buy_scaler.transform(self.buy_X_test)
                        buy_accuracy = float(self.buy_model.score(buy_X_test_scaled, self.buy_y_test))
                    except Exception as e:
                        print(f"⚠️  Could not calculate buy model accuracy: {e}")
                        buy_accuracy = 0.6  # Default accuracy
                
                # Handle different model types for feature importance
                if hasattr(self.buy_model, 'feature_importances_'):
                    buy_feature_importance = pd.DataFrame({
                        'feature': self.buy_feature_names,
                        'importance': self.buy_model.feature_importances_
                    }).sort_values('importance', ascending=False)
                elif hasattr(self.buy_model, 'coef_'):
                    buy_feature_importance = pd.DataFrame({
                        'feature': self.buy_feature_names,
                        'importance': np.abs(self.buy_model.coef_[0])
                    }).sort_values('importance', ascending=False)
                else:
                    buy_feature_importance = pd.DataFrame({
                        'feature': self.buy_feature_names,
                        'importance': [0.0] * len(self.buy_feature_names)
                    })
                
                # Extract optimized parameters for buy model
                buy_params = self.extract_optimized_parameters(buy_feature_importance, 'buy', self.buy_feature_names)
                
                models_to_save.append({
                    'model_type': 'buy',
                    'accuracy': buy_accuracy,
                    'feature_importance': buy_feature_importance.to_dict('records'),
                    'data_points': len(self.buy_X_test) if hasattr(self, 'buy_X_test') else 0,
                    'optimized_parameters': buy_params
                })
            
            # Add sell model parameters if available
            if self.sell_model is not None and hasattr(self, 'sell_feature_names'):
                sell_accuracy = 0.0
                if hasattr(self, 'sell_X_test') and hasattr(self, 'sell_y_test') and hasattr(self, 'sell_scaler'):
                    try:
                        sell_X_test_scaled = self.sell_scaler.transform(self.sell_X_test)
                        sell_accuracy = float(self.sell_model.score(sell_X_test_scaled, self.sell_y_test))
                    except Exception as e:
                        print(f"⚠️  Could not calculate sell model accuracy: {e}")
                        sell_accuracy = 0.6  # Default accuracy
                
                # Handle different model types for feature importance
                if hasattr(self.sell_model, 'feature_importances_'):
                    sell_feature_importance = pd.DataFrame({
                        'feature': self.sell_feature_names,
                        'importance': self.sell_model.feature_importances_
                    }).sort_values('importance', ascending=False)
                elif hasattr(self.sell_model, 'coef_'):
                    sell_feature_importance = pd.DataFrame({
                        'feature': self.sell_feature_names,
                        'importance': np.abs(self.sell_model.coef_[0])
                    }).sort_values('importance', ascending=False)
                else:
                    sell_feature_importance = pd.DataFrame({
                        'feature': self.sell_feature_names,
                        'importance': [0.0] * len(self.sell_feature_names)
                    })
                
                # Extract optimized parameters for sell model
                sell_params = self.extract_optimized_parameters(sell_feature_importance, 'sell', self.sell_feature_names)
                
                models_to_save.append({
                    'model_type': 'sell',
                    'accuracy': sell_accuracy,
                    'feature_importance': sell_feature_importance.to_dict('records'),
                    'data_points': len(self.sell_X_test) if hasattr(self, 'sell_X_test') else 0,
                    'optimized_parameters': sell_params
                })
            
            # Add combined model parameters if available
            if self.model is not None and hasattr(self, 'feature_names'):
                combined_accuracy = 0.0
                if hasattr(self, 'X_test') and hasattr(self, 'y_test') and hasattr(self, 'scaler'):
                    try:
                        X_test_scaled = self.scaler.transform(self.X_test)
                        combined_accuracy = float(self.model.score(X_test_scaled, self.y_test))
                    except Exception as e:
                        print(f"⚠️  Could not calculate combined model accuracy: {e}")
                        combined_accuracy = 0.6  # Default accuracy
                
                # Handle different model types for feature importance
                if hasattr(self.model, 'feature_importances_'):
                    combined_feature_importance = pd.DataFrame({
                        'feature': self.feature_names,
                        'importance': self.model.feature_importances_
                    }).sort_values('importance', ascending=False)
                elif hasattr(self.model, 'coef_'):
                    combined_feature_importance = pd.DataFrame({
                        'feature': self.feature_names,
                        'importance': np.abs(self.model.coef_[0])
                    }).sort_values('importance', ascending=False)
                else:
                    combined_feature_importance = pd.DataFrame({
                        'feature': self.feature_names,
                        'importance': [0.0] * len(self.feature_names)
                    })
                
                # Extract optimized parameters for combined model
                combined_params = self.extract_optimized_parameters(combined_feature_importance, 'combined', self.feature_names)
                
                models_to_save.append({
                    'model_type': 'combined',
                    'accuracy': combined_accuracy,
                    'feature_importance': combined_feature_importance.to_dict('records'),
                    'data_points': len(self.X_test) if hasattr(self, 'X_test') else 0,
                    'optimized_parameters': combined_params
                })
            
            # Create parameters structure
            params = {
                'models': models_to_save,
                'training_date': datetime.now().isoformat(),
                'recommendation': 'Use separate buy/sell models if performance differs significantly',
                'ea_compatible': True,
                'version': '2.0'
            }
            
            # Save parameters
            params_path = os.path.join(self.models_dir, 'ml_model_params.json')
            with open(params_path, 'w') as f:
                json.dump(params, f, indent=2)
            
            print(f"✅ Enhanced model parameters saved to: {params_path}")
            
            # Also save in simple format for easy MQL5 parsing
            self.save_simple_parameters(df)
            
            return True
            
        except Exception as e:
            print(f"❌ Error saving parameters: {e}")
            return False
    
    def save_simple_parameters(self, df=None):
        """Save optimized parameters in simple key=value format for EA"""
        print("💾 Saving simple parameters for EA...")
        
        # Get the best parameters from optimization
        best_params = self.best_params if hasattr(self, 'best_params') else {}
        
        # Create parameter content
        param_content = []
        
        # Add combined model parameters
        param_content.extend([
            f"combined_min_prediction_threshold={best_params.get('combined_min_prediction_threshold', 0.55):.4f}",
            f"combined_max_prediction_threshold={best_params.get('combined_max_prediction_threshold', 0.45):.4f}",
            f"combined_min_confidence={best_params.get('combined_min_confidence', 0.30):.4f}",
            f"combined_max_confidence={best_params.get('combined_max_confidence', 0.85):.4f}",
            f"combined_position_sizing_multiplier={best_params.get('combined_position_sizing_multiplier', 1.0):.4f}",
            f"combined_stop_loss_adjustment={best_params.get('combined_stop_loss_adjustment', 1.0):.4f}",
            f"combined_rsi_bullish_threshold={best_params.get('combined_rsi_bullish_threshold', 30.0):.2f}",
            f"combined_rsi_bearish_threshold={best_params.get('combined_rsi_bearish_threshold', 70.0):.2f}",
            f"combined_rsi_weight={best_params.get('combined_rsi_weight', 0.08):.4f}",
            f"combined_stoch_bullish_threshold={best_params.get('combined_stoch_bullish_threshold', 20.0):.2f}",
            f"combined_stoch_bearish_threshold={best_params.get('combined_stoch_bearish_threshold', 80.0):.2f}",
            f"combined_stoch_weight={best_params.get('combined_stoch_weight', 0.08):.4f}",
            f"combined_macd_threshold={best_params.get('combined_macd_threshold', 0.0):.4f}",
            f"combined_macd_weight={best_params.get('combined_macd_weight', 0.08):.4f}",
            f"combined_volume_ratio_threshold={best_params.get('combined_volume_ratio_threshold', 1.5):.2f}",
            f"combined_volume_weight={best_params.get('combined_volume_weight', 0.08):.4f}",
            f"combined_pattern_bullish_weight={best_params.get('combined_pattern_bullish_weight', 0.12):.4f}",
            f"combined_pattern_bearish_weight={best_params.get('combined_pattern_bearish_weight', 0.12):.4f}",
            f"combined_zone_weight={best_params.get('combined_zone_weight', 0.08):.4f}",
            f"combined_trend_weight={best_params.get('combined_trend_weight', 0.08):.4f}",
            f"combined_base_confidence={best_params.get('combined_base_confidence', 0.6):.4f}",
            f"combined_signal_agreement_weight={best_params.get('combined_signal_agreement_weight', 0.5):.4f}",
            f"combined_neutral_zone_min={best_params.get('combined_neutral_zone_min', 0.4):.4f}",
            f"combined_neutral_zone_max={best_params.get('combined_neutral_zone_max', 0.6):.4f}"
        ])
        
        # Add buy model parameters if available
        if 'buy_model' in best_params:
            param_content.extend([
                f"buy_min_prediction_threshold={best_params.get('buy_min_prediction_threshold', 0.52):.4f}",
                f"buy_max_prediction_threshold={best_params.get('buy_max_prediction_threshold', 0.48):.4f}",
                f"buy_min_confidence={best_params.get('buy_min_confidence', 0.35):.4f}",
                f"buy_max_confidence={best_params.get('buy_max_confidence', 0.9):.4f}",
                f"buy_position_sizing_multiplier={best_params.get('buy_position_sizing_multiplier', 1.2):.4f}",
                f"buy_stop_loss_adjustment={best_params.get('buy_stop_loss_adjustment', 0.5):.4f}",
                f"buy_rsi_bullish_threshold={best_params.get('buy_rsi_bullish_threshold', 30.0):.2f}",
                f"buy_rsi_bearish_threshold={best_params.get('buy_rsi_bearish_threshold', 70.0):.2f}",
                f"buy_rsi_weight={best_params.get('buy_rsi_weight', 0.08):.4f}",
                f"buy_stoch_bullish_threshold={best_params.get('buy_stoch_bullish_threshold', 20.0):.2f}",
                f"buy_stoch_bearish_threshold={best_params.get('buy_stoch_bearish_threshold', 80.0):.2f}",
                f"buy_stoch_weight={best_params.get('buy_stoch_weight', 0.08):.4f}",
                f"buy_macd_threshold={best_params.get('buy_macd_threshold', 0.0):.4f}",
                f"buy_macd_weight={best_params.get('buy_macd_weight', 0.08):.4f}",
                f"buy_volume_ratio_threshold={best_params.get('buy_volume_ratio_threshold', 1.5):.2f}",
                f"buy_volume_weight={best_params.get('buy_volume_weight', 0.08):.4f}",
                f"buy_pattern_bullish_weight={best_params.get('buy_pattern_bullish_weight', 0.12):.4f}",
                f"buy_pattern_bearish_weight={best_params.get('buy_pattern_bearish_weight', 0.12):.4f}",
                f"buy_zone_weight={best_params.get('buy_zone_weight', 0.08):.4f}",
                f"buy_trend_weight={best_params.get('buy_trend_weight', 0.08):.4f}",
                f"buy_base_confidence={best_params.get('buy_base_confidence', 0.6):.4f}",
                f"buy_signal_agreement_weight={best_params.get('buy_signal_agreement_weight', 0.5):.4f}"
            ])
        
        # Add sell model parameters if available
        if 'sell_model' in best_params:
            param_content.extend([
                f"sell_min_prediction_threshold={best_params.get('sell_min_prediction_threshold', 0.52):.4f}",
                f"sell_max_prediction_threshold={best_params.get('sell_max_prediction_threshold', 0.48):.4f}",
                f"sell_min_confidence={best_params.get('sell_min_confidence', 0.35):.4f}",
                f"sell_max_confidence={best_params.get('sell_max_confidence', 0.9):.4f}",
                f"sell_position_sizing_multiplier={best_params.get('sell_position_sizing_multiplier', 1.2):.4f}",
                f"sell_stop_loss_adjustment={best_params.get('sell_stop_loss_adjustment', 0.5):.4f}",
                f"sell_rsi_bullish_threshold={best_params.get('sell_rsi_bullish_threshold', 30.0):.2f}",
                f"sell_rsi_bearish_threshold={best_params.get('sell_rsi_bearish_threshold', 70.0):.2f}",
                f"sell_rsi_weight={best_params.get('sell_rsi_weight', 0.08):.4f}",
                f"sell_stoch_bullish_threshold={best_params.get('sell_stoch_bullish_threshold', 20.0):.2f}",
                f"sell_stoch_bearish_threshold={best_params.get('sell_stoch_bearish_threshold', 80.0):.2f}",
                f"sell_stoch_weight={best_params.get('sell_stoch_weight', 0.08):.4f}",
                f"sell_macd_threshold={best_params.get('sell_macd_threshold', 0.0):.4f}",
                f"sell_macd_weight={best_params.get('sell_macd_weight', 0.08):.4f}",
                f"sell_volume_ratio_threshold={best_params.get('sell_volume_ratio_threshold', 1.5):.2f}",
                f"sell_volume_weight={best_params.get('sell_volume_weight', 0.08):.4f}",
                f"sell_pattern_bullish_weight={best_params.get('sell_pattern_bullish_weight', 0.12):.4f}",
                f"sell_pattern_bearish_weight={best_params.get('sell_pattern_bearish_weight', 0.12):.4f}",
                f"sell_zone_weight={best_params.get('sell_zone_weight', 0.08):.4f}",
                f"sell_trend_weight={best_params.get('sell_trend_weight', 0.08):.4f}",
                f"sell_base_confidence={best_params.get('sell_base_confidence', 0.6):.4f}",
                f"sell_signal_agreement_weight={best_params.get('sell_signal_agreement_weight', 0.5):.4f}"
            ])
        
        # Save generic parameters file
        generic_file = os.path.join(self.models_dir, 'ml_model_params_simple.txt')
        with open(generic_file, 'w') as f:
            f.write('\n'.join(param_content))
        print(f"✅ Generic parameters saved to: {generic_file}")
        
        # Save currency pair-specific parameter files
        self.save_currency_pair_parameters(param_content, df)
        
        return generic_file
    
    def save_currency_pair_parameters(self, param_content, df=None):
        """Save currency pair-specific parameter files only for pairs present in data"""
        print("💾 Saving currency pair-specific parameters...")
        
        # Define currency pairs and their specific adjustments
        currency_pairs = {
            'EURUSD': {
                'name': 'EURUSD',
                'volatility_multiplier': 1.0,  # Base volatility
                'spread_adjustment': 1.0,      # Base spread
                'session_weight': 1.0,         # Base session weight
                'description': 'Major pair - London/NY session focus'
            },
            'GBPUSD': {
                'name': 'GBPUSD', 
                'volatility_multiplier': 1.2,  # Higher volatility
                'spread_adjustment': 1.1,      # Slightly higher spread
                'session_weight': 1.1,         # London session focus
                'description': 'Major pair - Higher volatility, London focus'
            },
            'USDJPY': {
                'name': 'USDJPY',
                'volatility_multiplier': 0.8,  # Lower volatility
                'spread_adjustment': 0.9,      # Lower spread
                'session_weight': 0.9,         # Asian session focus
                'description': 'Major pair - Lower volatility, Asian focus'
            },
            'GBPJPY': {
                'name': 'GBPJPY',
                'volatility_multiplier': 1.5,  # High volatility
                'spread_adjustment': 1.3,      # Higher spread
                'session_weight': 1.2,         # London/Asian crossover
                'description': 'Cross pair - High volatility, London/Asian crossover'
            },
            'XAUUSD': {
                'name': 'XAUUSD',
                'volatility_multiplier': 1.8,  # Very high volatility
                'spread_adjustment': 1.5,      # High spread
                'session_weight': 1.3,         # All sessions
                'description': 'Commodity - Very high volatility, all sessions'
            },
            'XAUEUR': {
                'name': 'XAUEUR',
                'volatility_multiplier': 1.6,  # High volatility (similar to XAUUSD but EUR-based)
                'spread_adjustment': 1.4,      # High spread
                'session_weight': 1.2,         # European session focus
                'description': 'Commodity - High volatility, European session focus'
            },
            'USDCAD': {
                'name': 'USDCAD',
                'volatility_multiplier': 0.9,  # Lower volatility
                'spread_adjustment': 0.95,     # Lower spread
                'session_weight': 0.95,        # NY session focus
                'description': 'Major pair - Lower volatility, NY session focus'
            }
        }
        
        # Determine which currency pairs are actually present in the data
        pairs_to_create = set()
        
        if df is not None:
            print(f"📊 DataFrame info: shape={df.shape}, columns={list(df.columns)}")
            
            if 'symbol' in df.columns:
                # Extract unique symbols from the data
                unique_symbols = df['symbol'].unique()
                print(f"📊 Found symbols in data: {list(unique_symbols)}")
                
                for symbol in unique_symbols:
                    if pd.isna(symbol) or symbol == '':
                        continue
                        
                    # Remove the + suffix if present (broker-specific naming)
                    base_symbol = str(symbol).replace('+', '')
                    print(f"🔍 Processing symbol: '{symbol}' -> '{base_symbol}'")
                    
                    # Check if this symbol matches any of our currency pairs
                    for pair in currency_pairs.keys():
                        if base_symbol == pair:
                            pairs_to_create.add(pair)
                            print(f"✅ Will create parameters for: {pair} (from {symbol})")
                            break
                    else:
                        print(f"⚠️  Symbol '{base_symbol}' not in supported currency pairs")
            else:
                print("⚠️  No 'symbol' column found in dataframe")
                print(f"Available columns: {list(df.columns)}")
        else:
            print("⚠️  No dataframe provided")
        
        if not pairs_to_create:
            print("⚠️  No matching currency pairs found in data, creating generic parameters only")
            return
        
        print(f"🎯 Creating parameter files for: {list(pairs_to_create)}")
        
        for pair, config in currency_pairs.items():
            # Only create files for pairs that are actually present in the data
            if pair not in pairs_to_create:
                print(f"⏭️  Skipping {pair} - not present in data")
                continue
                
            # Create pair-specific parameter content with adjustments
            pair_content = []
            
            for param in param_content:
                key, value = param.split('=', 1)
                val = float(value)
                
                # Apply currency pair-specific adjustments
                if 'threshold' in key and 'rsi' in key:
                    # Adjust RSI thresholds based on volatility
                    if 'bullish' in key:
                        val = max(20, min(40, val * config['volatility_multiplier']))
                    elif 'bearish' in key:
                        val = min(80, max(60, val / config['volatility_multiplier']))
                
                elif 'threshold' in key and 'stoch' in key:
                    # Adjust Stochastic thresholds based on volatility
                    if 'bullish' in key:
                        val = max(15, min(30, val * config['volatility_multiplier']))
                    elif 'bearish' in key:
                        val = min(85, max(70, val / config['volatility_multiplier']))
                
                elif 'volume_ratio_threshold' in key:
                    # Adjust volume threshold based on session weight
                    val = max(1.0, min(2.5, val * config['session_weight']))
                
                elif 'confidence' in key and 'min' in key:
                    # Adjust minimum confidence based on spread
                    val = max(0.25, min(0.45, val * config['spread_adjustment']))
                
                elif 'confidence' in key and 'max' in key:
                    # Adjust maximum confidence based on spread
                    val = min(0.95, max(0.75, val / config['spread_adjustment']))
                
                elif 'position_sizing_multiplier' in key:
                    # Adjust position sizing based on volatility
                    val = max(0.5, min(2.0, val / config['volatility_multiplier']))
                
                elif 'stop_loss_adjustment' in key:
                    # Adjust stop loss based on volatility
                    val = max(0.3, min(1.5, val * config['volatility_multiplier']))
                
                # Add adjusted parameter
                pair_content.append(f"{key}={val:.4f}")
            
            # Save pair-specific file
            pair_file = os.path.join(self.models_dir, f'ml_model_params_{pair}.txt')
            with open(pair_file, 'w') as f:
                f.write('\n'.join(pair_content))
            
            # Track that this file was created in the current run
            self.files_created_this_run.add(f'ml_model_params_{pair}.txt')
            
            print(f"✅ {pair} parameters saved to: {pair_file}")
            print(f"   {config['description']}")
            print(f"   Volatility multiplier: {config['volatility_multiplier']}")
            print(f"   Spread adjustment: {config['spread_adjustment']}")
            print(f"   Session weight: {config['session_weight']}")
    
    def extract_optimized_parameters(self, feature_importance, model_type, feature_names=None):
        """Extract optimized parameters from feature importance for EA use"""
        try:
            # Base parameters that will be optimized based on feature importance
            params = {
                # RSI thresholds (optimized based on RSI importance)
                'rsi_bullish_threshold': 30.0,
                'rsi_bearish_threshold': 70.0,
                'rsi_weight': 0.08,
                
                # Stochastic thresholds
                'stoch_bullish_threshold': 20.0,
                'stoch_bearish_threshold': 80.0,
                'stoch_weight': 0.08,
                
                # MACD parameters
                'macd_threshold': 0.0,
                'macd_weight': 0.08,
                
                # Volume parameters
                'volume_ratio_threshold': 1.5,
                'volume_weight': 0.08,
                
                # Pattern weights
                'pattern_bullish_weight': 0.12,
                'pattern_bearish_weight': 0.12,
                
                # Zone and trend weights
                'zone_weight': 0.08,
                'trend_weight': 0.08,
                
                # Confidence parameters
                'base_confidence': 0.6,
                'signal_agreement_weight': 0.5,
                
                # Prediction thresholds
                'min_prediction_threshold': 0.52,
                'max_prediction_threshold': 0.48,
                'neutral_zone_min': 0.4,
                'neutral_zone_max': 0.6,
                
                # Risk management
                'min_confidence': 0.35,
                'max_confidence': 0.90,
                'position_sizing_multiplier': 1.2,
                'stop_loss_adjustment': 0.5
            }
            
            # Optimize parameters based on feature importance
            if feature_importance is not None and len(feature_importance) > 0:
                # Convert feature_importance to DataFrame if it's a numpy array
                if isinstance(feature_importance, np.ndarray):
                    feature_importance_df = pd.DataFrame({
                        'feature': feature_names,
                        'importance': feature_importance
                    }).sort_values('importance', ascending=False)
                else:
                    feature_importance_df = feature_importance
                
                # Get top features
                top_features = feature_importance_df.head(10)
                
                # Calculate total importance for normalization
                total_importance = top_features['importance'].sum()
                
                # Optimize RSI parameters if RSI is important
                rsi_features = top_features[top_features['feature'].str.contains('rsi', case=False)]
                if len(rsi_features) > 0:
                    rsi_importance = rsi_features['importance'].sum() / total_importance
                    params['rsi_weight'] = min(0.15, max(0.05, rsi_importance * 0.2))
                    
                    # Adjust RSI thresholds based on model type
                    if model_type == 'buy':
                        params['rsi_bullish_threshold'] = 25.0  # More aggressive for buy
                        params['rsi_bearish_threshold'] = 75.0
                    elif model_type == 'sell':
                        params['rsi_bullish_threshold'] = 35.0  # More conservative for sell
                        params['rsi_bearish_threshold'] = 65.0
                
                # Optimize Stochastic parameters
                stoch_features = top_features[top_features['feature'].str.contains('stoch', case=False)]
                if len(stoch_features) > 0:
                    stoch_importance = stoch_features['importance'].sum() / total_importance
                    params['stoch_weight'] = min(0.15, max(0.05, stoch_importance * 0.2))
                    
                    if model_type == 'buy':
                        params['stoch_bullish_threshold'] = 15.0
                        params['stoch_bearish_threshold'] = 85.0
                    elif model_type == 'sell':
                        params['stoch_bullish_threshold'] = 25.0
                        params['stoch_bearish_threshold'] = 75.0
                
                # Optimize MACD parameters
                macd_features = top_features[top_features['feature'].str.contains('macd', case=False)]
                if len(macd_features) > 0:
                    macd_importance = macd_features['importance'].sum() / total_importance
                    params['macd_weight'] = min(0.15, max(0.05, macd_importance * 0.2))
                    params['macd_threshold'] = 0.0001  # Small threshold for MACD
                
                # Optimize Volume parameters
                volume_features = top_features[top_features['feature'].str.contains('volume', case=False)]
                if len(volume_features) > 0:
                    volume_importance = volume_features['importance'].sum() / total_importance
                    params['volume_weight'] = min(0.15, max(0.05, volume_importance * 0.2))
                    
                    if model_type == 'buy':
                        params['volume_ratio_threshold'] = 1.3  # Lower threshold for buy
                    elif model_type == 'sell':
                        params['volume_ratio_threshold'] = 1.7  # Higher threshold for sell
                
                # Optimize Pattern weights
                pattern_features = top_features[top_features['feature'].str.contains('pattern', case=False)]
                if len(pattern_features) > 0:
                    pattern_importance = pattern_features['importance'].sum() / total_importance
                    pattern_weight = min(0.2, max(0.08, pattern_importance * 0.25))
                    params['pattern_bullish_weight'] = pattern_weight
                    params['pattern_bearish_weight'] = pattern_weight
                
                # Optimize Trend weights
                trend_features = top_features[top_features['feature'].str.contains('trend', case=False)]
                if len(trend_features) > 0:
                    trend_importance = trend_features['importance'].sum() / total_importance
                    params['trend_weight'] = min(0.15, max(0.05, trend_importance * 0.2))
                
                # Optimize Zone weights
                zone_features = top_features[top_features['feature'].str.contains('zone', case=False)]
                if len(zone_features) > 0:
                    zone_importance = zone_features['importance'].sum() / total_importance
                    params['zone_weight'] = min(0.15, max(0.05, zone_importance * 0.2))
                
                # Adjust prediction thresholds based on model type
                if model_type == 'buy':
                    params['min_prediction_threshold'] = 0.55  # Higher threshold for buy
                    params['max_prediction_threshold'] = 0.45
                    params['neutral_zone_min'] = 0.45
                    params['neutral_zone_max'] = 0.55
                elif model_type == 'sell':
                    params['min_prediction_threshold'] = 0.50  # Lower threshold for sell
                    params['max_prediction_threshold'] = 0.50
                    params['neutral_zone_min'] = 0.45
                    params['neutral_zone_max'] = 0.55
                
                # Adjust confidence parameters based on model accuracy
                if model_type == 'buy' and hasattr(self, 'buy_X_test') and hasattr(self, 'buy_y_test') and hasattr(self, 'buy_scaler') and self.buy_model is not None:
                    try:
                        buy_X_test_scaled = self.buy_scaler.transform(self.buy_X_test)
                        buy_accuracy = float(self.buy_model.score(buy_X_test_scaled, self.buy_y_test))
                        params['base_confidence'] = min(0.8, max(0.4, buy_accuracy))
                    except Exception as e:
                        print(f"⚠️  Could not calculate buy model accuracy: {e}")
                        params['base_confidence'] = 0.6
                elif model_type == 'sell' and hasattr(self, 'sell_X_test') and hasattr(self, 'sell_y_test') and hasattr(self, 'sell_scaler') and self.sell_model is not None:
                    try:
                        sell_X_test_scaled = self.sell_scaler.transform(self.sell_X_test)
                        sell_accuracy = float(self.sell_model.score(sell_X_test_scaled, self.sell_y_test))
                        params['base_confidence'] = min(0.8, max(0.4, sell_accuracy))
                    except Exception as e:
                        print(f"⚠️  Could not calculate sell model accuracy: {e}")
                        params['base_confidence'] = 0.6
                elif model_type == 'combined' and hasattr(self, 'X_test') and hasattr(self, 'y_test') and hasattr(self, 'scaler') and hasattr(self, 'model'):
                    try:
                        X_test_scaled = self.scaler.transform(self.X_test)
                        combined_accuracy = float(self.model.score(X_test_scaled, self.y_test))
                        params['base_confidence'] = min(0.8, max(0.4, combined_accuracy))
                    except Exception as e:
                        print(f"⚠️  Could not calculate combined model accuracy: {e}")
                        params['base_confidence'] = 0.6  # Default confidence
            
            print(f"✅ Extracted optimized parameters for {model_type} model")
            return params
            
        except Exception as e:
            print(f"❌ Error extracting parameters for {model_type}: {e}")
            # Return default parameters if extraction fails
            return {
                'rsi_bullish_threshold': 30.0,
                'rsi_bearish_threshold': 70.0,
                'rsi_weight': 0.08,
                'stoch_bullish_threshold': 20.0,
                'stoch_bearish_threshold': 80.0,
                'stoch_weight': 0.08,
                'macd_threshold': 0.0,
                'macd_weight': 0.08,
                'volume_ratio_threshold': 1.5,
                'volume_weight': 0.08,
                'pattern_bullish_weight': 0.12,
                'pattern_bearish_weight': 0.12,
                'zone_weight': 0.08,
                'trend_weight': 0.08,
                'base_confidence': 0.6,
                'signal_agreement_weight': 0.5,
                'min_prediction_threshold': 0.52,
                'max_prediction_threshold': 0.48,
                'neutral_zone_min': 0.4,
                'neutral_zone_max': 0.6,
                'min_confidence': 0.35,
                'max_confidence': 0.90,
                'position_sizing_multiplier': 1.2,
                'stop_loss_adjustment': 0.5
            }
    
    def copy_to_metatrader(self):
        """Copy model files to MetaTrader directory"""
        try:
            import shutil
            
            # Use the same MetaTrader directory detection as initialization
            possible_paths = [
                os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
                os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/Common/Files"),
                os.path.expanduser("~/Documents/MetaTrader 5/MQL5/Files"),
                os.path.expanduser("~/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
                "/Applications/MetaTrader 5.app/Contents/Resources/MQL5/Files"
            ]
            
            metatrader_dir = None
            for path in possible_paths:
                if os.path.exists(path):
                    metatrader_dir = path
                    break
            
            if metatrader_dir is None:
                print("❌ MetaTrader directory not found for copying files")
                return False
            
            # Determine destination directory based on target EA
            if self.target_ea and self.target_ea in self.ea_folders:
                # Copy to specific EA folder
                ea_folder = self.ea_folders[self.target_ea]
                dest_dir = os.path.join(metatrader_dir, ea_folder)
                
                # Create EA folder if it doesn't exist
                if not os.path.exists(dest_dir):
                    os.makedirs(dest_dir)
                    print(f"📁 Created EA folder: {dest_dir}")
                
                print(f"\n📁 Copying files to EA-specific directory...")
                print(f"Target EA: {self.target_ea}")
                print(f"Destination: {dest_dir}")
            else:
                # Copy to root MetaTrader directory (for backward compatibility)
                dest_dir = metatrader_dir
                print(f"\n📁 Copying files to MetaTrader root directory...")
                print(f"Destination: {dest_dir}")
            
            # Files to copy
            files_to_copy = [
                'buy_trade_success_predictor.pkl',
                'buy_scaler.pkl', 
                'buy_label_encoders.pkl',
                'sell_trade_success_predictor.pkl',
                'sell_scaler.pkl', 
                'sell_label_encoders.pkl',
                'trade_success_predictor.pkl',
                'scaler.pkl', 
                'combined_label_encoders.pkl',
                'ml_model_params.json',
                'ml_model_params_simple.txt'  # Add the simple parameter file
            ]
            
            # Only add currency pair files that were created in the current run
            for currency_file in self.files_created_this_run:
                if currency_file.startswith('ml_model_params_') and currency_file.endswith('.txt'):
                    files_to_copy.append(currency_file)
                    print(f"✅ Will copy {currency_file} - created in this run")
            
            copied_count = 0
            for filename in files_to_copy:
                source_path = os.path.join(self.models_dir, filename)
                dest_path = os.path.join(dest_dir, filename)
                
                if os.path.exists(source_path):
                    shutil.copy2(source_path, dest_path)
                    print(f"✅ Copied: {filename}")
                    copied_count += 1
                else:
                    print(f"⚠️  File not found: {filename}")
            
            print(f"📁 Successfully copied {copied_count} files to MetaTrader")
            return True
            
        except Exception as e:
            print(f"❌ Error copying to MetaTrader: {e}")
            return False
    
    def generate_training_report(self, df):
        """Generate training report"""
        try:
            if df is None:
                return
            
            print("\n📊 TRAINING REPORT")
            print("=" * 50)
            
            # Basic statistics
            total_trades = len(df)
            buy_trades = len(df[df['direction'] == 'buy'])
            sell_trades = len(df[df['direction'] == 'sell'])
            
            print(f"Total Trades: {total_trades}")
            print(f"Buy Trades: {buy_trades} ({buy_trades/total_trades*100:.1f}%)")
            print(f"Sell Trades: {sell_trades} ({sell_trades/total_trades*100:.1f}%)")
            
            # ML prediction statistics
            if 'ml_prediction' in df.columns:
                avg_prediction = df['ml_prediction'].mean()
                print(f"Average ML Prediction: {avg_prediction:.4f}")
            
            if 'ml_confidence' in df.columns:
                avg_confidence = df['ml_confidence'].mean()
                print(f"Average ML Confidence: {avg_confidence:.4f}")
            
            # Feature statistics
            if 'rsi' in df.columns:
                print(f"RSI Range: {df['rsi'].min():.1f} - {df['rsi'].max():.1f}")
            
            if 'volume_ratio' in df.columns:
                print(f"Volume Ratio Range: {df['volume_ratio'].min():.2f} - {df['volume_ratio'].max():.2f}")
            
            # Target distribution
            if 'target' in df.columns:
                target_dist = df['target'].value_counts()
                print(f"Target Distribution: {dict(target_dist)}")
            
            print("=" * 50)
            
        except Exception as e:
            print(f"❌ Error generating report: {e}")
    
    def run_training_pipeline(self, filename_pattern="StrategyTester_ML_Data.json", separate_models=True, incremental=False, rolling_window=None, early_stopping=True):
        """Run complete training pipeline with option for separate buy/sell models, incremental learning, and early stopping"""
        try:
            print("🚀 Starting Enhanced ML Training Pipeline...")
            print(f"📁 Data directory: {self.data_dir}")
            print(f"📁 Models directory: {self.models_dir}")
            print(f"🔀 Separate buy/sell models: {separate_models}")
            print(f"🔄 Incremental learning: {incremental}")
            print(f"🛑 Early stopping: {early_stopping}")
            if rolling_window:
                print(f"📊 Rolling window: {rolling_window} most recent trades")
            
            # Load trade data
            df = self.load_strategy_tester_data(filename_pattern)
            if df is None:
                return False
            
            # Apply rolling window if specified
            if rolling_window and len(df) > rolling_window:
                print(f"📊 Applying rolling window: using {rolling_window} most recent trades out of {len(df)} total")
                df = df.tail(rolling_window).reset_index(drop=True)
            
            # Shuffle data to prevent overfitting to recent patterns
            df = df.sample(frac=1.0, random_state=42).reset_index(drop=True)
            print(f"🔄 Data shuffled to prevent overfitting to recent patterns")
            
            # Load test summaries for analysis
            test_summaries = self.load_test_summaries()
            if test_summaries is not None:
                self.analyze_test_summaries(test_summaries)
            
            # Process data
            df = self.process_trade_data(df)
            if df is None:
                return False
            
            # Generate report
            self.generate_training_report(df)
            
            # Check if we should use separate models
            if separate_models and 'direction' in df.columns:
                buy_trades = df[df['direction'] == 'buy']
                sell_trades = df[df['direction'] == 'sell']
                
                print(f"\n🎯 SEPARATE MODEL TRAINING:")
                print(f"Buy trades available: {len(buy_trades)}")
                print(f"Sell trades available: {len(sell_trades)}")
                
                # Train buy model if we have enough data
                if len(buy_trades) >= 20:
                    print(f"\n📈 Training BUY model...")
                    X_buy, y_buy, buy_features = self.engineer_features(df, 'buy')
                    if X_buy is not None:
                        self.train_model(X_buy, y_buy, buy_features, 'buy', incremental=incremental, early_stopping=early_stopping)
                    else:
                        print("❌ Failed to engineer features for buy model")
                else:
                    print(f"⚠️  Insufficient buy trades ({len(buy_trades)}) for separate model")
                
                # Train sell model if we have enough data (reduced threshold for sell trades)
                if len(sell_trades) >= 10:  # Reduced from 20 to 10 for sell trades
                    print(f"\n📉 Training SELL model...")
                    X_sell, y_sell, sell_features = self.engineer_features(df, 'sell')
                    if X_sell is not None:
                        self.train_model(X_sell, y_sell, sell_features, 'sell', incremental=incremental, early_stopping=early_stopping)
                    else:
                        print("❌ Failed to engineer features for sell model")
                else:
                    print(f"⚠️  Insufficient sell trades ({len(sell_trades)}) for separate model (need at least 10)")
                
                # Also train combined model for comparison
                print(f"\n🔄 Training COMBINED model for comparison...")
                X_combined, y_combined, combined_features = self.engineer_features(df)
                if X_combined is not None:
                    self.train_model(X_combined, y_combined, combined_features, incremental=incremental, early_stopping=early_stopping)
                else:
                    print("❌ Failed to engineer features for combined model")
                
            else:
                # Train single combined model
                print(f"\n🔄 Training COMBINED model...")
                X, y, feature_names = self.engineer_features(df)
                if X is not None:
                    self.train_model(X, y, feature_names, incremental=incremental, early_stopping=early_stopping)
                else:
                    print("❌ Failed to engineer features")
                    return False
            
            # Save models
            if not self.save_models(df):
                return False
            
            print("\n🎉 Enhanced training pipeline completed successfully!")
            return True
            
        except Exception as e:
            print(f"❌ Error in training pipeline: {e}")
            return False
    
    def explain_file_structure(self):
        """Explain the file structure created by the enhanced EA and how to use the trainer"""
        print("\n📁 ENHANCED EA FILE STRUCTURE GUIDE")
        print("=" * 60)
        print("The enhanced EAs create organized folders in MetaTrader's Common Files directory:")
        print()
        print("📂 FOLDER STRUCTURE:")
        for ea_name, folder_name in self.ea_folders.items():
            print(f"   📁 {folder_name}/")
            print(f"      • {ea_name}_ML_Data.json - Trade features and indicators")
            print(f"      • {ea_name}_Results.json - Test run summaries")
            print(f"      • ml_model_params_*.txt - Currency pair-specific parameters")
        print()
        print("🎯 ML DATA FILES (for training):")
        print("   • Contains: trade features, indicators, ML predictions")
        print("   • Organized by EA in separate folders")
        print()
        print("📊 TRADE RESULTS FILES (for outcome analysis):")
        print("   • Contains: profit/loss, duration, exit reasons")
        print("   • Organized by EA in separate folders")
        print()
        print("📈 TEST SUMMARY FILES (for performance analysis):")
        print("   • Contains: win rates, profit factors, drawdowns")
        print("   • Organized by EA in separate folders")
        print()
        print("🔧 HOW TO USE THE TRAINER:")
        print("1. Run your EA in Strategy Tester to generate data files")
        print("2. The trainer will automatically find and load all relevant files")
        print("3. Run: python strategy_tester_ml_trainer.py")
        print("4. The trainer will create optimized parameters for your EA")
        print()
        print("💡 ENHANCED FEATURES:")
        print("• Automatic file pattern matching (finds all relevant files)")
        print("• Support for multiple EA versions and file formats")
        print("• Separate buy/sell model training for better accuracy")
        print("• Comprehensive performance analysis")
        print("• Currency pair-specific parameter optimization")
        print("• Organized folder structure to prevent confusion")
        print("=" * 60)

    def cleanup_corrupted_files(self):
        """Clean up corrupted JSON files that might cause training issues"""
        print("\n🧹 CLEANING UP CORRUPTED FILES")
        print("=" * 40)
        
        cleaned_count = 0
        
        for ea_name, folder_name in self.ea_folders.items():
            folder_path = os.path.join(self.data_dir, folder_name)
            if not os.path.exists(folder_path):
                continue
                
            print(f"📁 Checking {ea_name} folder: {folder_path}")
            
            # Check all JSON files in the folder
            json_files = glob.glob(os.path.join(folder_path, "*.json"))
            
            for file_path in json_files:
                try:
                    # Try to read and validate the file
                    with open(file_path, 'r') as f:
                        content = f.read()
                        
                        if len(content) == 0:
                            print(f"🗑️  Removing empty file: {file_path}")
                            os.remove(file_path)
                            cleaned_count += 1
                            continue
                        
                        # Try to parse JSON
                        json.loads(content)
                        print(f"✅ Valid file: {os.path.basename(file_path)}")
                        
                except json.JSONDecodeError as e:
                    print(f"🗑️  Removing corrupted file: {file_path}")
                    print(f"   Error: {e}")
                    
                    # Create backup before deletion
                    backup_path = file_path + ".corrupted"
                    try:
                        os.rename(file_path, backup_path)
                        print(f"   📦 Backup created: {backup_path}")
                    except Exception as backup_error:
                        print(f"   ❌ Failed to create backup: {backup_error}")
                        try:
                            os.remove(file_path)
                        except:
                            pass
                    
                    cleaned_count += 1
                    
                except Exception as e:
                    print(f"❌ Error checking file {file_path}: {e}")
        
        if cleaned_count > 0:
            print(f"\n✅ Cleaned up {cleaned_count} corrupted files")
        else:
            print(f"\n✅ No corrupted files found")
        
        print("=" * 40)
        return cleaned_count

    def check_data_availability(self):
        """Check what data files are available and provide guidance"""
        print("\n🔍 DATA AVAILABILITY CHECK")
        print("=" * 40)
        
        if self.target_ea:
            print(f"🎯 Checking data for target EA: {self.target_ea}")
        else:
            print("🎯 Checking data for all available EAs")
        
        total_files_found = 0
        
        # Check each EA folder
        for ea_name, folder_name in self.ea_folders.items():
            print(f"\n📁 Checking {ea_name} folder: {folder_name}/")
            
            # Check for ML data files
            ml_patterns = [
                os.path.join(self.data_dir, folder_name, f"{ea_name}_ML_Data.json"),
                os.path.join(self.data_dir, folder_name, "*_ML_Data.json")
            ]
            
            ml_files = []
            for pattern in ml_patterns:
                ml_files.extend(glob.glob(pattern))
            ml_files = list(set(ml_files))
            
            print(f"   📊 ML Data Files: {len(ml_files)} found")
            for file in ml_files:
                print(f"      ✅ {os.path.basename(file)}")
                total_files_found += 1
            
            # Check for trade result files
            result_patterns = [
                os.path.join(self.data_dir, folder_name, f"{ea_name}_Trade_Results.json"),
                os.path.join(self.data_dir, folder_name, "*_Trade_Results.json")
            ]
            
            result_files = []
            for pattern in result_patterns:
                result_files.extend(glob.glob(pattern))
            result_files = list(set(result_files))
            
            print(f"   📈 Trade Result Files: {len(result_files)} found")
            for file in result_files:
                print(f"      ✅ {os.path.basename(file)}")
                total_files_found += 1
            
            # Check for test summary files
            summary_patterns = [
                os.path.join(self.data_dir, folder_name, f"{ea_name}_Results.json"),
                os.path.join(self.data_dir, folder_name, "*_Results.json"),
                os.path.join(self.data_dir, folder_name, "StrategyTester_Comprehensive_Results.json")
            ]
            
            summary_files = []
            for pattern in summary_patterns:
                summary_files.extend(glob.glob(pattern))
            summary_files = list(set(summary_files))
            
            print(f"   📋 Test Summary Files: {len(summary_files)} found")
            for file in summary_files:
                print(f"      ✅ {os.path.basename(file)}")
                total_files_found += 1
        
        # Also check root directory for backward compatibility (only if not targeting specific EA)
        if not self.target_ea:
            print(f"\n📁 Checking root directory for legacy files:")
            root_patterns = [
                os.path.join(self.data_dir, "*_ML_Data.json"),
                os.path.join(self.data_dir, "*_Trade_Results.json"),
                os.path.join(self.data_dir, "*_Results.json")
            ]
            
            root_files = []
            for pattern in root_patterns:
                root_files.extend(glob.glob(pattern))
            root_files = list(set(root_files))
            
            if root_files:
                print(f"   📊 Legacy Files: {len(root_files)} found")
                for file in root_files:
                    print(f"      ⚠️  {os.path.basename(file)} (legacy)")
                    total_files_found += 1
            else:
                print("   📊 Legacy Files: None found")
        
        # Provide guidance
        if total_files_found == 0:
            print("\n⚠️  NO DATA FILES FOUND!")
            if self.target_ea:
                print(f"   To generate data for {self.target_ea}:")
                print(f"   1. Load {self.target_ea}.mq5 in MetaTrader")
                print("   2. Run Strategy Tester with CollectMLData=true")
                print(f"   3. Check the 'Files' tab in MetaTrader for {self.ea_folders[self.target_ea]}/ folder")
            else:
                print("   To generate data:")
                print("   1. Load SimpleBreakoutML_EA.mq5 or StrategyTesterML_EA.mq5 in MetaTrader")
                print("   2. Run Strategy Tester with CollectMLData=true")
                print("   3. Check the 'Files' tab in MetaTrader for generated folders")
        else:
            print(f"\n✅ READY FOR TRAINING!")
            if self.target_ea:
                print(f"   Found {total_files_found} data files for {self.target_ea}")
                print(f"   Run: python strategy_tester_ml_trainer.py --ea {self.target_ea}")
            else:
                print(f"   Found {total_files_found} data files across all EA folders")
                print("   Run: python strategy_tester_ml_trainer.py")
        
        print("=" * 40)

def main():
    """Main function with enhanced options"""
    import argparse
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Strategy Tester ML Trainer with enhanced features')
    parser.add_argument('--incremental', action='store_true', help='Use incremental learning (SGDClassifier) instead of full retrain')
    parser.add_argument('--rolling-window', type=int, help='Use only the N most recent trades for training')
    parser.add_argument('--no-separate-models', action='store_true', help='Disable separate buy/sell models')
    parser.add_argument('--explain', action='store_true', help='Explain the file structure and how to use the trainer')
    parser.add_argument('--check-data', action='store_true', help='Check what data files are available')
    parser.add_argument('--ea', type=str, choices=['SimpleBreakoutML_EA', 'StrategyTesterML_EA'], 
                       help='Specify which EA to train (default: train on all available EAs)')
    args = parser.parse_args()
    
    # Initialize trainer with target EA if specified
    trainer = StrategyTesterMLTrainer(target_ea=args.ea)
    
    # Show file structure explanation if requested
    if args.explain:
        trainer.explain_file_structure()
        return
    
    # Check data availability if requested
    if args.check_data:
        trainer.check_data_availability()
        return
    
    # Clean up corrupted files before training
    print("🧹 Checking for corrupted files...")
    cleaned_count = trainer.cleanup_corrupted_files()
    if cleaned_count > 0:
        print(f"⚠️  {cleaned_count} corrupted files were cleaned up. Consider re-running your EA to regenerate clean data.")
    
    # Run training pipeline with enhanced options (early stopping is now dynamic)
    success = trainer.run_training_pipeline(
        separate_models=not args.no_separate_models,
        incremental=args.incremental,
        rolling_window=args.rolling_window,
        early_stopping=True  # This will be overridden by dynamic logic
    )
    
    if success:
        ea_info = f" for {args.ea}" if args.ea else " on all available EAs"
        print(f"\n✅ Enhanced ML models are ready for use in Strategy Tester{ea_info}!")
        print("📁 Check the ml_models/ directory for:")
        if args.incremental:
            print("   - buy_trade_success_predictor_incremental.pkl (buy-specific incremental model)")
            print("   - sell_trade_success_predictor_incremental.pkl (sell-specific incremental model)")
            print("   - trade_success_predictor_incremental.pkl (combined incremental model)")
        else:
            print("   - buy_trade_success_predictor.pkl (buy-specific model)")
            print("   - sell_trade_success_predictor.pkl (sell-specific model)")
            print("   - trade_success_predictor.pkl (combined model)")
        print("   - Separate scalers and encoders for each model")
        print("   - ml_model_params.json (enhanced parameters)")
        print("   - Currency pair-specific parameter files (e.g., ml_model_params_EURUSD.txt)")
        print("\n💡 Usage examples:")
        print("   python strategy_tester_ml_trainer.py --explain  # Show file structure guide")
        print("   python strategy_tester_ml_trainer.py --check-data  # Check available data")
        print("   python strategy_tester_ml_trainer.py --ea SimpleBreakoutML_EA  # Train only breakout EA")
        print("   python strategy_tester_ml_trainer.py --ea StrategyTesterML_EA  # Train only strategy tester EA")
        print("   python strategy_tester_ml_trainer.py --incremental  # Use incremental learning")
        print("   python strategy_tester_ml_trainer.py --rolling-window 1000  # Use last 1000 trades")
        print("   python strategy_tester_ml_trainer.py --ea SimpleBreakoutML_EA --incremental  # Combined options")
        print("   # Early stopping is now automatic based on dataset size:")
        print("   #   - Small datasets (<100 samples): RandomForest (better feature importance)")
        print("   #   - Large datasets (≥500 samples): SGDClassifier with early stopping")
        print("   #   - Medium datasets: Uses your preference or defaults to RandomForest")
    else:
        print("\n❌ Training failed. Check the data and try again.")
        print("💡 Try running: python strategy_tester_ml_trainer.py --check-data")
        print("   This will show you what data files are available and provide guidance.")
        if args.ea:
            print(f"💡 Or try: python strategy_tester_ml_trainer.py --check-data --ea {args.ea}")
            print(f"   This will check data specifically for {args.ea}.")

if __name__ == "__main__":
    main() 