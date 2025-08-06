#!/usr/bin/env python3
"""
Test script to verify the new combined symbol+timeframe model approach
"""

import os
import sys
import pandas as pd
import numpy as np
from datetime import datetime

# Add the current directory to the path so we can import the trainer
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from improved_ml_trainer import ImprovedMLTrainer

def create_test_data():
    """Create test data with multiple symbols and timeframes"""
    print("🧪 Creating test data with multiple symbols and timeframes...")

    # Create sample data
    np.random.seed(42)
    n_trades = 200

    # Create data for different symbol+timeframe combinations
    data = []

    symbols = ['EURUSD', 'XAUUSD', 'GBPUSD']
    timeframes = ['M5', 'M15', 'H1']

    for symbol in symbols:
        for timeframe in timeframes:
            n_symbol_trades = n_trades // (len(symbols) * len(timeframes))

            for i in range(n_symbol_trades):
                trade = {
                    'test_run_id': f'test_run_{symbol}_{timeframe}',
                    'trade_id': i,
                    'symbol': symbol,
                    'timeframe': timeframe,
                    'timestamp': int(datetime.now().timestamp()) + i,
                    'direction': np.random.choice(['buy', 'sell']),
                    'success': np.random.choice([0, 1], p=[0.4, 0.6]),  # 60% success rate
                    'rsi': np.random.uniform(20, 80),
                    'stoch_main': np.random.uniform(0, 100),
                    'macd_main': np.random.uniform(-0.001, 0.001),
                    'volume_ratio': np.random.uniform(0.5, 2.0),
                    'atr': np.random.uniform(0.0001, 0.001),
                    'profit': np.random.uniform(-100, 200),
                    'net_profit': np.random.uniform(-100, 200),
                    'exit_reason': np.random.choice(['tp', 'sl', 'manual'])
                }
                data.append(trade)

    df = pd.DataFrame(data)
    print(f"✅ Created test data: {len(df)} trades")
    print(f"📊 Symbol distribution: {df['symbol'].value_counts().to_dict()}")
    print(f"📊 Timeframe distribution: {df['timeframe'].value_counts().to_dict()}")
    print(f"📊 Symbol+timeframe combinations: {df.groupby(['symbol', 'timeframe']).size().to_dict()}")

    return df

def test_symbol_timeframe_training():
    """Test the new symbol+timeframe training approach"""
    print("\n🧪 Testing Symbol+Timeframe Training")
    print("=" * 60)

    # Create test data
    df = create_test_data()

    # Initialize trainer
    trainer = ImprovedMLTrainer(
        models_dir='test_models/',
        train_directional_models=True
    )

    # Store the test data
    trainer.df = df

    print("\n🎯 Testing symbol+timeframe specific model training...")

    # Test the new training method
    success = trainer._train_timeframe_specific_models(df)

    if success:
        print("✅ Symbol+timeframe training completed successfully!")

        # Check what models were created
        print("\n📊 Training Summary:")
        for history in trainer.training_history:
            print(f"   Model: {history['direction']}")
            print(f"     Accuracy: {history['avg_accuracy']:.3f}")
            print(f"     AUC: {history['avg_auc']:.3f}")
            print(f"     Samples: {history['n_samples']}")

        # Test model saving
        print("\n💾 Testing model saving...")
        trainer.save_models()

        # Check what files were created
        if os.path.exists('test_models/'):
            files = os.listdir('test_models/')
            print(f"📁 Created {len(files)} files:")
            for file in sorted(files):
                print(f"   📄 {file}")

        print("\n✅ All tests passed!")
        return True
    else:
        print("❌ Symbol+timeframe training failed!")
        return False

def cleanup_test_files():
    """Clean up test files"""
    import shutil
    if os.path.exists('test_models/'):
        shutil.rmtree('test_models/')
        print("🧹 Cleaned up test files")

if __name__ == "__main__":
    try:
        success = test_symbol_timeframe_training()
        if success:
            print("\n🎉 Symbol+timeframe model approach is working correctly!")
        else:
            print("\n❌ Symbol+timeframe model approach has issues!")
    finally:
        cleanup_test_files()
