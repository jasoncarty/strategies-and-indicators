#!/usr/bin/env python3
"""
Test script to simulate service feature loading
"""

import joblib
from pathlib import Path

def test_service_loading():
    """Test how the service loads feature names"""

    print("🧪 Testing service feature loading...")
    print("=" * 50)

    # Simulate the service loading process
    models_dir = Path("ml_models")
    feature_names = {}

    # Find all .pkl files
    pkl_files = list(models_dir.rglob("*.pkl"))
    print(f"Found {len(pkl_files)} .pkl files")

    for pkl_file in pkl_files:
        filename = pkl_file.name

        # Handle webserver directory structure (flat structure)
        if "webserver" in str(models_dir) or "ml_models" in str(models_dir):
            # Extract model info from filename
            if "buy_model" in filename:
                model_type = "buy"
            elif "sell_model" in filename:
                model_type = "sell"
            elif "combined_model" in filename:
                model_type = "combined"
            else:
                continue

            # Extract symbol and timeframe from filename
            # Format: buy_model_BTCUSD_PERIOD_M5.pkl
            parts = filename.replace(".pkl", "").split("_")
            if len(parts) >= 4:
                symbol = parts[2]  # BTCUSD
                timeframe = parts[4]  # M5

                # Create model key
                model_key = f"{model_type}_{symbol}_PERIOD_{timeframe}"

                # Try to load corresponding feature names
                features_filename = filename.replace("model.pkl", "feature_names.pkl")
                features_file = pkl_file.parent / features_filename

                if features_file.exists():
                    try:
                        loaded_features = joblib.load(features_file)
                        feature_names[model_key] = loaded_features
                        print(f"✅ Loaded feature names for {model_key}: {len(loaded_features)} features")
                        print(f"   Features: {loaded_features}")
                        print(f"   Type: {type(loaded_features)}")
                    except Exception as e:
                        print(f"❌ Error loading features for {model_key}: {e}")

    print("\n🔧 Testing feature consistency check...")
    print("=" * 30)

    # The complete 28 universal features (strategy-agnostic)
    complete_features = [
        # Base features (17)
        'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
        'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
        'volume_ratio', 'price_change', 'volatility', 'force_index',
        'spread', 'session_hour', 'is_news_time',
        # Time features (2)
        'day_of_week', 'month',
        # Engineered features (9)
        'rsi_regime', 'stoch_regime', 'volatility_regime',
        'hour', 'session', 'is_london_session', 'is_ny_session', 'is_asian_session', 'is_session_overlap'
    ]

    updated_count = 0
    for model_key, feature_names_list in feature_names.items():
        if feature_names_list is None:
            print(f"⚠️  Model {model_key} has None feature names, skipping")
            continue

        print(f"🔍 Checking {model_key}: {len(feature_names_list)} features")

        # Handle different feature counts
        if len(feature_names_list) == 29 and 'adx' in feature_names_list:
            # Remove adx from 29-feature files
            feature_names_list = [f for f in feature_names_list if f != 'adx']
            feature_names[model_key] = feature_names_list
            print(f"   Removed 'adx' from {model_key} (29 -> 28 features)")
            updated_count += 1
        elif len(feature_names_list) != 28:
            print(f"   ⚠️  Model {model_key} has {len(feature_names_list)} features, updating to 28")
            feature_names[model_key] = complete_features
            updated_count += 1
        else:
            print(f"   ✅ Model {model_key} already has 28 features")

    print(f"\n📊 Summary:")
    print(f"   Models loaded: {len(feature_names)}")
    print(f"   Models updated: {updated_count}")

if __name__ == "__main__":
    test_service_loading()
