#!/usr/bin/env python3
"""
Startup script for ML Prediction Service
Easy way to start the ML service with proper configuration
"""

import os
import sys
import time
from pathlib import Path

def main():
    """Start the ML prediction service"""
    print("🤖 ML Prediction Service Startup")
    print("=" * 50)

    # Check if we're in the right directory
    if not Path("ml_prediction_service.py").exists():
        print("❌ ml_prediction_service.py not found in current directory")
        print("   Please run this script from the ML_Webserver directory")
        return

    # Check Python dependencies
    try:
        import numpy as np
        import pandas as pd
        import joblib
        print("✅ All dependencies available")
    except ImportError as e:
        print(f"❌ Missing dependency: {e}")
        print("   Please install required packages:")
        print("   pip install numpy pandas scikit-learn joblib")
        return

    # Check if models directory exists
    models_dir = Path("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/Models").expanduser()
    if not models_dir.exists():
        print("⚠️  Models directory not found")
        print(f"   Expected: {models_dir}")
        print("   Please ensure the MT5 Common Files Models directory exists")
        return

    # Check for .pkl files
    pkl_files = list(models_dir.rglob("*.pkl"))
    if not pkl_files:
        print("⚠️  No .pkl model files found")
        print("   Please run the ML trainer first:")
        print("   cd ../webserver && python improved_ml_trainer.py")
        print("   Then copy the models to the Models directory")
    else:
        print(f"✅ Found {len(pkl_files)} model files")
        for pkl_file in pkl_files[:5]:  # Show first 5
            print(f"   📄 {pkl_file}")
        if len(pkl_files) > 5:
            print(f"   ... and {len(pkl_files) - 5} more")

    print("\n🚀 Starting ML Prediction Service...")
    print("   Press Ctrl+C to stop")
    print("=" * 50)

    # Import and start the service
    try:
        from ml_prediction_service import MLPredictionService

        # Initialize service with correct models directory
        models_dir = Path("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/Models").expanduser()
        service = MLPredictionService(models_dir=str(models_dir))

        # Print status
        status = service.get_status()
        print(f"📊 Service Status:")
        print(f"   Models loaded: {status['models_loaded']}")
        print(f"   Available models: {status['available_models']}")

        if status['models_loaded'] == 0:
            print("\n⚠️  No models loaded - service will run but won't make predictions")
            print("   Please ensure .pkl files are in the Models directory")

        print("\n🔄 Starting feature file monitoring...")
        print("   Service is ready to process predictions!")

        # Start monitoring
        service.monitor_feature_files()

    except KeyboardInterrupt:
        print("\n🛑 Service stopped by user")
    except Exception as e:
        print(f"\n❌ Service error: {e}")
        print("   Check the logs for more details")

if __name__ == "__main__":
    main()
