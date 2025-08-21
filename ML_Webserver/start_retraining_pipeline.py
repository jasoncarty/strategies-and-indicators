#!/usr/bin/env python3
"""
Start the Automated ML Retraining Pipeline
Run this script to start continuous monitoring and retraining
"""

import sys
import os
import logging
from pathlib import Path

# Add the current directory to Python path
sys.path.append(str(Path(__file__).parent))

try:
    from automated_retraining_pipeline import AutomatedRetrainingPipeline
    print("✅ Successfully imported AutomatedRetrainingPipeline")
except ImportError as e:
    print(f"❌ Failed to import AutomatedRetrainingPipeline: {e}")
    print("   Make sure all dependencies are installed:")
    print("   pip install scikit-learn pandas numpy requests")
    sys.exit(1)

def main():
    """Start the automated retraining pipeline"""
    print("🚀 Starting Automated ML Retraining Pipeline")
    print("=" * 50)

    # Configuration
    analytics_url = "http://localhost:5001"  # Analytics server URL
    models_dir = "ml_models"                 # Directory for ML models
    check_interval = 60                      # Check every 60 minutes

    print(f"📊 Analytics Server: {analytics_url}")
    print(f"📁 Models Directory: {models_dir}")
    print(f"⏰ Check Interval: {check_interval} minutes")
    print(f"🔄 Max Concurrent Retraining: 2 models")
    print(f"🛡️ Auto-retrain Critical: Enabled")
    print(f"⚠️ Auto-retrain Warnings: Disabled (manual review)")
    print()

    try:
        # Initialize pipeline
        pipeline = AutomatedRetrainingPipeline(
            analytics_url=analytics_url,
            models_dir=models_dir,
            check_interval_minutes=check_interval
        )

        print("✅ Pipeline initialized successfully")
        print("🔍 Testing connection to analytics server...")

        # Test connection
        alerts = pipeline.check_model_alerts()
        health = pipeline.check_model_health()

        if alerts and health:
            print(f"✅ Analytics server connection successful")
            print(f"   Found {len(alerts.get('alerts', []))} models with alerts")
            print(f"   Found {len(health.get('models', []))} models in health check")
        else:
            print("⚠️ Analytics server connection issues - some features may not work")

        print()
        print("🚀 Starting continuous monitoring...")
        print("   Press Ctrl+C to stop")
        print("=" * 50)

        # Start continuous monitoring
        pipeline.run_continuous_monitoring()

    except KeyboardInterrupt:
        print("\n🛑 Pipeline stopped by user")
    except Exception as e:
        print(f"❌ Pipeline failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
