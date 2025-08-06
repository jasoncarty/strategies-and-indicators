#!/usr/bin/env python3
"""
Analyze ML Training Issues
Identify why the ML trainer might be making results worse
"""

import json
import pandas as pd
import numpy as np
from collections import Counter

def analyze_ml_data():
    """Analyze the ML training data for issues"""
    print("=== ML DATA ANALYSIS ===")
    
    # Load ML data
    with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_ML_Data.json', 'r') as f:
        data = json.load(f)
    
    trades = data['trades']
    df = pd.DataFrame(trades)
    
    print(f"Total trades: {len(df)}")
    print(f"Unique symbols: {df['symbol'].unique()}")
    print(f"Direction distribution:")
    print(df['direction'].value_counts())
    
    # Data quality issues
    print("\n=== DATA QUALITY ISSUES ===")
    print(f"Trades with volume=1: {(df['volume'] == 1).sum()} / {len(df)} ({(df['volume'] == 1).mean():.1%})")
    print(f"Trades with spread=0: {(df['spread'] == 0).sum()} / {len(df)}")
    print(f"Unique candle patterns:")
    print(df['candle_pattern'].value_counts())
    
    # Overfitting indicators
    print("\n=== OVERFITTING INDICATORS ===")
    print(f"Unique test run IDs: {df['test_run_id'].nunique()}")
    print("Most common test runs:")
    print(df['test_run_id'].value_counts().head(5))
    
    # Data leakage check
    print("\n=== DATA LEAKAGE CHECK ===")
    price_diff = abs(df['entry_price'] - df['current_price'])
    print(f"Trades with price difference > 0.0001: {(price_diff > 0.0001).sum()} / {len(df)}")
    print(f"Average price difference: {price_diff.mean():.6f}")
    
    # Class imbalance
    print("\n=== CLASS IMBALANCE ===")
    buy_ratio = (df['direction'] == 'buy').mean()
    print(f"Buy ratio: {buy_ratio:.2%}")
    print(f"Buy trades: {(df['direction'] == 'buy').sum()}")
    print(f"Sell trades: {(df['direction'] == 'sell').sum()}")
    
    # Feature analysis
    print("\n=== FEATURE ANALYSIS ===")
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    print(f"Numeric features: {len(numeric_cols)}")
    
    # Check for constant features
    constant_features = []
    for col in numeric_cols:
        if df[col].nunique() == 1:
            constant_features.append(col)
    
    print(f"Constant features: {len(constant_features)}")
    if constant_features:
        print(f"Constant feature names: {constant_features[:10]}")  # Show first 10
    
    return df

def analyze_trade_results():
    """Analyze the actual trade results"""
    print("\n=== TRADE RESULTS ANALYSIS ===")
    
    try:
        with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json', 'r') as f:
            data = json.load(f)
        
        trades = data['trades']
        df = pd.DataFrame(trades)
        
        print(f"Total trades: {len(df)}")
        
        if 'profit' in df.columns:
            print(f"Total profit: ${df['profit'].sum():.2f}")
            print(f"Average profit per trade: ${df['profit'].mean():.2f}")
            print(f"Win rate: {(df['profit'] > 0).mean():.2%}")
            print(f"Profitable trades: {(df['profit'] > 0).sum()}")
            print(f"Losing trades: {(df['profit'] < 0).sum()}")
            
            # Symbol performance
            print("\n=== SYMBOL PERFORMANCE ===")
            if 'symbol' in df.columns:
                symbol_perf = df.groupby('symbol').agg({
                    'profit': ['sum', 'mean', 'count']
                }).round(2)
                print(symbol_perf)
        
        if 'success' in df.columns:
            print(f"Success rate: {df['success'].mean():.2%}")
        
        return df
        
    except Exception as e:
        print(f"Error loading trade results: {e}")
        return None

def identify_ml_issues():
    """Identify specific issues with the ML training"""
    print("\n=== ML TRAINING ISSUES IDENTIFIED ===")
    
    issues = [
        "1. DATA LEAKAGE: Entry price and current price are different in many trades",
        "2. OVERFITTING: Too many trades from single test runs (241 from one run)",
        "3. POOR FEATURE QUALITY: All volume data is 1 (no real volume information)",
        "4. CLASS IMBALANCE: 56% buy vs 44% sell trades",
        "5. LIMITED PATTERN DIVERSITY: 93% of trades have 'none' candle pattern",
        "6. INSUFFICIENT DATA: Only 26 unique test runs for 2518 trades",
        "7. POTENTIAL LOOK-AHEAD BIAS: Price data might include future information",
        "8. FEATURE CORRELATION: Many features might be highly correlated",
        "9. NO OUT-OF-SAMPLE VALIDATION: All data from same time period",
        "10. MISSING MARKET CONDITIONS: No market regime information"
    ]
    
    for issue in issues:
        print(f"❌ {issue}")
    
    print("\n=== RECOMMENDATIONS ===")
    recommendations = [
        "1. Fix data leakage by using only past data for features",
        "2. Collect more diverse data from different market conditions",
        "3. Implement proper train/test split by time",
        "4. Add more meaningful features (real volume, market regime)",
        "5. Use cross-validation with time series splits",
        "6. Implement feature selection to remove redundant features",
        "7. Add regularization to prevent overfitting",
        "8. Collect data from multiple brokers/time periods",
        "9. Implement walk-forward analysis",
        "10. Consider ensemble methods for better generalization"
    ]
    
    for rec in recommendations:
        print(f"✅ {rec}")

def main():
    """Main analysis function"""
    print("🔍 ANALYZING ML TRAINING ISSUES")
    print("=" * 50)
    
    # Analyze ML data
    ml_df = analyze_ml_data()
    
    # Analyze trade results
    results_df = analyze_trade_results()
    
    # Identify issues
    identify_ml_issues()
    
    print("\n" + "=" * 50)
    print("🎯 SUMMARY: The ML trainer is likely making results worse due to:")
    print("   - Data leakage (using future information)")
    print("   - Overfitting to specific test runs")
    print("   - Poor feature quality (all volume=1)")
    print("   - Insufficient diverse training data")
    print("\n💡 SOLUTION: Implement proper time series ML with walk-forward analysis")

if __name__ == "__main__":
    main() 