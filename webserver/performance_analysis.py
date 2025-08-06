#!/usr/bin/env python3
"""
Performance Analysis Script
Analyzes trading results to identify patterns and optimize parameters
"""

import pandas as pd
import numpy as np
import json
import os
import glob
from datetime import datetime
# import matplotlib.pyplot as plt  # Not used in this version
# import seaborn as sns  # Not used in this version
from collections import defaultdict

class PerformanceAnalyzer:
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

    def __init__(self, data_dir=None):
        """Initialize the performance analyzer"""
        self.data_dir = data_dir or self._find_metatrader_directory()
        self.ea_name = "SimpleBreakoutML_EA"
        
        print(f"📁 Data directory: {self.data_dir}")
        print(f"🎯 Analyzing EA: {self.ea_name}")
        
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
    
    def load_data(self):
        """Load ML data and trade results"""
        print("🔍 Loading trading data...")
        
        # Load ML data
        ml_data_file = os.path.join(self.data_dir, self.ea_name, f"{self.ea_name}_ML_Data.json")
        if os.path.exists(ml_data_file):
            with open(ml_data_file, 'r') as f:
                ml_data = json.load(f)
            print(f"✅ Loaded ML data: {len(ml_data.get('trades', []))} trades")
        else:
            print("❌ ML data file not found")
            return None, None
        
        # Load trade results
        results_file = os.path.join(self.data_dir, self.ea_name, f"{self.ea_name}_Trade_Results.json")
        if os.path.exists(results_file):
            with open(results_file, 'r') as f:
                results_data = json.load(f)
            print(f"✅ Loaded trade results: {len(results_data)} trades")
        else:
            print("❌ Trade results file not found")
            return None, None
        
        return ml_data, results_data
    
    def analyze_symbol_performance(self, ml_data, results_data):
        """Analyze performance by symbol"""
        print("\n📊 Analyzing Symbol Performance...")
        print("=" * 50)
        
        # Create DataFrame from ML data
        trades_df = pd.DataFrame(ml_data['trades'])
        
        # Add results data
        results_df = pd.DataFrame(results_data)
        
        # Merge data
        if 'trade_id' in trades_df.columns and 'trade_id' in results_df.columns:
            merged_df = pd.merge(trades_df, results_df, on='trade_id', how='inner')
        else:
            print("❌ Cannot merge data - missing trade_id")
            return None
        
        # Clean symbol names - use symbol_x from merged data
        if 'symbol_x' in merged_df.columns:
            merged_df['clean_symbol'] = merged_df['symbol_x'].str.replace('+', '')
        elif 'symbol' in merged_df.columns:
            merged_df['clean_symbol'] = merged_df['symbol'].str.replace('+', '')
        else:
            print("❌ No symbol column found in merged data")
            return None
        
        # Calculate success - use trade_success from results if available, otherwise calculate from profit
        if 'trade_success' in merged_df.columns:
            merged_df['success'] = merged_df['trade_success']
        else:
            merged_df['success'] = merged_df['profit'] > 0
        
        # Group by symbol
        symbol_stats = merged_df.groupby('clean_symbol').agg({
            'net_profit': ['count', 'sum', 'mean', 'std'],
            'success': 'mean',
            'volume_x': 'mean',
            'atr': 'mean',
            'rsi': 'mean',
            'volatility': 'mean'
        }).round(4)
        
        # Flatten column names
        symbol_stats.columns = ['_'.join(col).strip() for col in symbol_stats.columns]
        
        # Rename columns for clarity
        symbol_stats = symbol_stats.rename(columns={
            'net_profit_count': 'total_trades',
            'net_profit_sum': 'total_profit',
            'net_profit_mean': 'avg_profit',
            'net_profit_std': 'profit_std',
            'success_mean': 'win_rate',
            'volume_x_mean': 'avg_volume',
            'atr_mean': 'avg_atr',
            'rsi_mean': 'avg_rsi',
            'volatility_mean': 'avg_volatility'
        })
        
        # Calculate additional metrics
        winning_trades = merged_df[merged_df['net_profit'] > 0].groupby('clean_symbol')['net_profit'].sum()
        losing_trades = merged_df[merged_df['net_profit'] < 0].groupby('clean_symbol')['net_profit'].sum().abs()
        
        symbol_stats['profit_factor'] = (winning_trades / losing_trades).fillna(0)
        
        symbol_stats['avg_win'] = merged_df[merged_df['net_profit'] > 0].groupby('clean_symbol')['net_profit'].mean()
        symbol_stats['avg_loss'] = merged_df[merged_df['net_profit'] < 0].groupby('clean_symbol')['net_profit'].mean()
        
        # Sort by total profit
        symbol_stats = symbol_stats.sort_values('total_profit', ascending=False)
        
        print("📊 Symbol Performance Summary:")
        print(symbol_stats[['total_trades', 'total_profit', 'win_rate', 'profit_factor', 'avg_profit']])
        
        return symbol_stats, merged_df
    
    def analyze_time_period_performance(self, merged_df):
        """Analyze performance by time period"""
        print("\n📅 Analyzing Time Period Performance...")
        print("=" * 50)
        
        # Extract year from test_run_id - use test_run_id_x from merged data
        if 'test_run_id_x' in merged_df.columns:
            merged_df['year'] = merged_df['test_run_id_x'].str.extract(r'_(\d{4})\d{4}').astype(int)
        elif 'test_run_id' in merged_df.columns:
            merged_df['year'] = merged_df['test_run_id'].str.extract(r'_(\d{4})\d{4}').astype(int)
        else:
            print("❌ No test_run_id column found")
            return None
        
        # Group by year
        year_stats = merged_df.groupby('year').agg({
            'net_profit': ['count', 'sum', 'mean'],
            'success': 'mean',
            'clean_symbol': 'nunique'
        }).round(4)
        
        year_stats.columns = ['total_trades', 'total_profit', 'avg_profit', 'win_rate', 'symbols_traded']
        year_stats = year_stats.sort_values('total_profit', ascending=False)
        
        print("📊 Year Performance Summary:")
        print(year_stats)
        
        return year_stats
    
    def analyze_session_performance(self, merged_df):
        """Analyze performance by session"""
        print("\n⏰ Analyzing Session Performance...")
        print("=" * 50)
        
        if 'session' not in merged_df.columns:
            print("❌ Session data not available")
            return None
        
        session_stats = merged_df.groupby('session').agg({
            'net_profit': ['count', 'sum', 'mean'],
            'success': 'mean',
            'clean_symbol': 'nunique'
        }).round(4)
        
        session_stats.columns = ['total_trades', 'total_profit', 'avg_profit', 'win_rate', 'symbols_traded']
        session_stats = session_stats.sort_values('total_profit', ascending=False)
        
        print("📊 Session Performance Summary:")
        print(session_stats)
        
        return session_stats
    
    def analyze_market_conditions(self, merged_df):
        """Analyze performance by market conditions"""
        print("\n🌍 Analyzing Market Conditions Performance...")
        print("=" * 50)
        
        # Create market condition classifications
        merged_df['volatility_regime'] = pd.cut(
            merged_df['volatility'], 
            bins=[0, merged_df['volatility'].quantile(0.33), merged_df['volatility'].quantile(0.67), merged_df['volatility'].max()], 
            labels=['low_volatility', 'medium_volatility', 'high_volatility']
        )
        
        merged_df['rsi_regime'] = pd.cut(
            merged_df['rsi'], 
            bins=[0, 30, 70, 100], 
            labels=['oversold', 'neutral', 'overbought']
        )
        
        merged_df['volume_regime'] = pd.cut(
            merged_df['volume_ratio'], 
            bins=[0, 1.0, 1.5, merged_df['volume_ratio'].max()], 
            labels=['low_volume', 'normal_volume', 'high_volume']
        )
        
        # Analyze by volatility regime
        print("📊 Volatility Regime Performance:")
        vol_stats = merged_df.groupby('volatility_regime').agg({
            'net_profit': ['count', 'sum', 'mean'],
            'success': 'mean'
        }).round(4)
        vol_stats.columns = ['total_trades', 'total_profit', 'avg_profit', 'win_rate']
        print(vol_stats)
        
        # Analyze by RSI regime
        print("\n📊 RSI Regime Performance:")
        rsi_stats = merged_df.groupby('rsi_regime').agg({
            'net_profit': ['count', 'sum', 'mean'],
            'success': 'mean'
        }).round(4)
        rsi_stats.columns = ['total_trades', 'total_profit', 'avg_profit', 'win_rate']
        print(rsi_stats)
        
        # Analyze by volume regime
        print("\n📊 Volume Regime Performance:")
        vol_ratio_stats = merged_df.groupby('volume_regime').agg({
            'net_profit': ['count', 'sum', 'mean'],
            'success': 'mean'
        }).round(4)
        vol_ratio_stats.columns = ['total_trades', 'total_profit', 'avg_profit', 'win_rate']
        print(vol_ratio_stats)
        
        return vol_stats, rsi_stats, vol_ratio_stats
    
    def generate_optimization_recommendations(self, symbol_stats, year_stats, session_stats, market_stats):
        """Generate optimization recommendations"""
        print("\n🎯 Optimization Recommendations...")
        print("=" * 50)
        
        recommendations = []
        
        # Symbol-specific recommendations
        print("📊 Symbol-Specific Recommendations:")
        for symbol, stats in symbol_stats.iterrows():
            if stats['total_trades'] >= 5:  # Minimum sample size
                if stats['win_rate'] > 0.5 and stats['total_profit'] > 0:
                    recommendations.append(f"✅ {symbol}: EXCELLENT - {stats['win_rate']:.1%} win rate, ${stats['total_profit']:.2f} profit")
                    print(f"   🎯 {symbol}: Lower thresholds (more aggressive) - Current performance is strong")
                elif stats['win_rate'] < 0.3 or stats['total_profit'] < -100:
                    recommendations.append(f"❌ {symbol}: POOR - {stats['win_rate']:.1%} win rate, ${stats['total_profit']:.2f} profit")
                    print(f"   🎯 {symbol}: Higher thresholds (more conservative) - Current performance is weak")
                else:
                    recommendations.append(f"⚠️  {symbol}: MODERATE - {stats['win_rate']:.1%} win rate, ${stats['total_profit']:.2f} profit")
                    print(f"   🎯 {symbol}: Keep current thresholds - Performance is moderate")
        
        # Time period recommendations
        print("\n📅 Time Period Recommendations:")
        best_year = year_stats.index[0]
        worst_year = year_stats.index[-1]
        print(f"   🎯 Best period: {best_year} (${year_stats.loc[best_year, 'total_profit']:.2f} profit)")
        print(f"   🎯 Worst period: {worst_year} (${year_stats.loc[worst_year, 'total_profit']:.2f} profit)")
        print(f"   🎯 Consider market regime detection for {worst_year} conditions")
        
        # Session recommendations
        if session_stats is not None:
            print("\n⏰ Session Recommendations:")
            best_session = session_stats.index[0]
            print(f"   🎯 Best session: {best_session} (${session_stats.loc[best_session, 'total_profit']:.2f} profit)")
            print(f"   🎯 Focus trading on {best_session} session")
        
        # Market condition recommendations
        if market_stats is not None:
            vol_stats, rsi_stats, vol_ratio_stats = market_stats
            print("\n🌍 Market Condition Recommendations:")
            
            best_vol = vol_stats.loc[vol_stats['total_profit'].idxmax()]
            print(f"   🎯 Best volatility: {vol_stats['total_profit'].idxmax()} (${best_vol['total_profit']:.2f} profit)")
            
            best_rsi = rsi_stats.loc[rsi_stats['total_profit'].idxmax()]
            print(f"   🎯 Best RSI regime: {rsi_stats['total_profit'].idxmax()} (${best_rsi['total_profit']:.2f} profit)")
            
            best_volume = vol_ratio_stats.loc[vol_ratio_stats['total_profit'].idxmax()]
            print(f"   🎯 Best volume regime: {vol_ratio_stats['total_profit'].idxmax()} (${best_volume['total_profit']:.2f} profit)")
        
        return recommendations
    
    def create_symbol_specific_parameters(self, symbol_stats):
        """Create symbol-specific parameter recommendations"""
        print("\n🔧 Creating Symbol-Specific Parameters...")
        print("=" * 50)
        
        symbol_params = {}
        
        for symbol, stats in symbol_stats.iterrows():
            if stats['total_trades'] < 5:  # Skip symbols with insufficient data
                continue
            
            # Base parameters
            base_params = {
                'combined_min_prediction_threshold': 0.52,
                'combined_max_prediction_threshold': 0.48,
                'combined_min_confidence': 0.25,
                'combined_max_confidence': 0.90,
                'combined_position_sizing_multiplier': 1.0,
                'combined_stop_loss_adjustment': 1.0
            }
            
            # Adjust based on performance
            if stats['win_rate'] > 0.5 and stats['total_profit'] > 0:
                # Excellent performance - be more aggressive
                base_params['combined_min_prediction_threshold'] = 0.50
                base_params['combined_max_prediction_threshold'] = 0.50
                base_params['combined_min_confidence'] = 0.20
                base_params['combined_position_sizing_multiplier'] = 1.1
                print(f"   🎯 {symbol}: AGGRESSIVE settings (excellent performance)")
            elif stats['win_rate'] < 0.3 or stats['total_profit'] < -100:
                # Poor performance - be more conservative
                base_params['combined_min_prediction_threshold'] = 0.55
                base_params['combined_max_prediction_threshold'] = 0.45
                base_params['combined_min_confidence'] = 0.35
                base_params['combined_position_sizing_multiplier'] = 0.9
                print(f"   🎯 {symbol}: CONSERVATIVE settings (poor performance)")
            else:
                # Moderate performance - keep balanced
                print(f"   🎯 {symbol}: BALANCED settings (moderate performance)")
            
            symbol_params[symbol] = base_params
        
        return symbol_params
    
    def save_symbol_specific_parameters(self, symbol_params):
        """Save symbol-specific parameters to files"""
        print("\n💾 Saving Symbol-Specific Parameters...")
        print("=" * 50)
        
        models_dir = 'ml_models'
        if not os.path.exists(models_dir):
            os.makedirs(models_dir)
        
        for symbol, params in symbol_params.items():
            param_file = os.path.join(models_dir, f'ml_model_params_{symbol}.txt')
            
            with open(param_file, 'w') as f:
                for key, value in params.items():
                    if isinstance(value, float):
                        f.write(f"{key}={value:.4f}\n")
                    else:
                        f.write(f"{key}={value}\n")
            
            print(f"✅ Saved parameters for {symbol}: {param_file}")
        
        # Copy to MetaTrader directory
        self._copy_parameters_to_metatrader()
    
    def _copy_parameters_to_metatrader(self):
        """Copy parameter files to MetaTrader directory"""
        print("\n�� Copying parameters to MetaTrader directory...")
        
        import shutil
        models_dir = 'ml_models'
        mt_dir = os.path.join(self.data_dir, self.ea_name)
        
        if not os.path.exists(mt_dir):
            os.makedirs(mt_dir)
        
        # Copy all parameter files
        param_files = glob.glob(os.path.join(models_dir, 'ml_model_params_*.txt'))
        for param_file in param_files:
            filename = os.path.basename(param_file)
            dest_file = os.path.join(mt_dir, filename)
            shutil.copy2(param_file, dest_file)
            print(f"✅ Copied: {filename}")
        
        print(f"📁 Successfully copied {len(param_files)} parameter files to MetaTrader directory")
    
    def run_analysis(self):
        """Run the complete performance analysis"""
        print("🚀 Starting Performance Analysis...")
        print("=" * 60)
        
        # Load data
        ml_data, results_data = self.load_data()
        if ml_data is None or results_data is None:
            print("❌ Failed to load data")
            return False
        
        # Analyze performance
        symbol_stats, merged_df = self.analyze_symbol_performance(ml_data, results_data)
        if symbol_stats is None:
            print("❌ Failed to analyze symbol performance")
            return False
        
        year_stats = self.analyze_time_period_performance(merged_df)
        session_stats = self.analyze_session_performance(merged_df)
        market_stats = self.analyze_market_conditions(merged_df)
        
        # Generate recommendations
        recommendations = self.generate_optimization_recommendations(
            symbol_stats, year_stats, session_stats, market_stats if market_stats else (None, None, None)
        )
        
        # Create symbol-specific parameters
        symbol_params = self.create_symbol_specific_parameters(symbol_stats)
        
        # Save parameters
        self.save_symbol_specific_parameters(symbol_params)
        
        print("\n🎉 Performance Analysis Completed!")
        print("📊 Check the generated parameter files for optimized settings")
        
        return True

def main():
    """Main function"""
    analyzer = PerformanceAnalyzer()
    analyzer.run_analysis()

if __name__ == "__main__":
    main() 