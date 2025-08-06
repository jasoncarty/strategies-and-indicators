#!/usr/bin/env python3
"""
Debug script to check feature names loading
"""

import pickle
import joblib
from pathlib import Path

def debug_feature_names():
    """Debug feature names loading"""

    # Check the actual file content
    feature_file = Path("ml_models/buy_feature_names_BTCUSD_PERIOD_M5.pkl")

    print("🔍 Debugging feature names loading...")
    print("=" * 50)

    if not feature_file.exists():
        print(f"❌ File not found: {feature_file}")
        return

    print(f"📄 File: {feature_file}")
    print(f"📏 File size: {feature_file.stat().st_size} bytes")

    # Try loading with pickle
    try:
        with open(feature_file, 'rb') as f:
            features_pickle = pickle.load(f)
        print(f"✅ Pickle load successful: {len(features_pickle)} features")
        print(f"   Type: {type(features_pickle)}")
        print(f"   Features: {features_pickle}")

        # Check if it's a string that needs to be parsed
        if isinstance(features_pickle, str):
            print(f"⚠️  Features loaded as string: {features_pickle}")
            print(f"   String length: {len(features_pickle)}")

    except Exception as e:
        print(f"❌ Pickle load failed: {e}")

    # Try loading with joblib
    try:
        features_joblib = joblib.load(feature_file)
        print(f"✅ Joblib load successful: {len(features_joblib)} features")
        print(f"   Type: {type(features_joblib)}")
        print(f"   Features: {features_joblib}")

        # Check if it's a string that needs to be parsed
        if isinstance(features_joblib, str):
            print(f"⚠️  Features loaded as string: {features_joblib}")
            print(f"   String length: {len(features_joblib)}")

    except Exception as e:
        print(f"❌ Joblib load failed: {e}")

    # Check if there's a difference
    if 'features_pickle' in locals() and 'features_joblib' in locals():
        if features_pickle == features_joblib:
            print("✅ Pickle and Joblib loads are identical")
        else:
            print("❌ Pickle and Joblib loads are different!")
            print(f"   Pickle: {features_pickle}")
            print(f"   Joblib: {features_joblib}")

if __name__ == "__main__":
    debug_feature_names()
