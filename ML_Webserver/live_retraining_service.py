#!/usr/bin/env python3
"""
Live Retraining Service for ML Models
Automatically retrains models from live trade data collected by the analytics server
"""
import os
import sys
import json
import logging
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import requests
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import joblib
import pickle

# Import from local directory
try:
    from improved_ml_trainer import ImprovedMLTrainer
    from feature_engineering_utils import FeatureEngineeringUtils
except ImportError:
    # Try relative import
    try:
        from .improved_ml_trainer import ImprovedMLTrainer
        from .feature_engineering_utils import FeatureEngineeringUtils
    except ImportError:
        # Try absolute import from project root
        import sys
        from pathlib import Path
        project_root = Path(__file__).parent.parent
        sys.path.insert(0, str(project_root))
        from ML_Webserver.improved_ml_trainer import ImprovedMLTrainer
        from ML_Webserver.feature_engineering_utils import FeatureEngineeringUtils

# Setup logging
# Ensure logs directory exists
import os
logs_dir = Path('logs')
logs_dir.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/live_retraining.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class LiveRetrainingService:
    """Service for automatically retraining ML models from live trade data"""

    def __init__(self, config_path: str = "live_retraining_config.json"):
        self.config = self._load_config(config_path)
        self.analytics_url = self.config.get("analytics_url", "http://127.0.0.1:5001")
        self.models_dir = Path(self.config.get("models_dir", "ml_models"))
        self.retraining_interval = self.config.get("retraining_interval_hours", 24)
        self.min_trades_for_retraining = self.config.get("min_trades_for_retraining", 50)
        self.performance_threshold = self.config.get("performance_threshold", 0.55)
        self.backup_models = self.config.get("backup_models", True)

        # Initialize ML trainer
        self.ml_trainer = ImprovedMLTrainer()

        # Track retraining history
        self.retraining_history = {}
        self.last_retraining_check = {}

        # Threading for background retraining
        self.retraining_thread = None
        self.stop_retraining = False

        logger.info("🚀 Live Retraining Service initialized")
        logger.info(f"   Analytics URL: {self.analytics_url}")
        logger.info(f"   Models Directory: {self.models_dir}")
        logger.info(f"   Retraining Interval: {self.retraining_interval} hours")
        logger.info(f"   Min Trades for Retraining: {self.min_trades_for_retraining}")
        logger.info(f"   Performance Threshold: {self.performance_threshold}")

    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from JSON file"""
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                return json.load(f)
        else:
            # Default configuration
            default_config = {
                "analytics_url": "http://127.0.0.1:5001",
                "models_dir": "ml_models",
                "retraining_interval_hours": 24,
                "min_trades_for_retraining": 50,
                "performance_threshold": 0.55,
                "backup_models": True,
                "symbols": ["XAUUSD+", "EURUSD", "GBPUSD+", "USDJPY+", "USDCAD+", "BTCUSD", "ETHUSD"],
                "timeframes": ["H1", "M15", "M30", "M5"]
            }

            # Save default config
            with open(config_path, 'w') as f:
                json.dump(default_config, f, indent=2)

            logger.info(f"📝 Created default configuration: {config_path}")
            return default_config

    def start_background_retraining(self):
        """Start background retraining thread"""
        if self.retraining_thread and self.retraining_thread.is_alive():
            logger.warning("⚠️ Background retraining already running")
            return

        self.stop_retraining = False
        self.retraining_thread = threading.Thread(target=self._background_retraining_loop)
        self.retraining_thread.daemon = True
        self.retraining_thread.start()

        logger.info("🔄 Background retraining started")

    def stop_background_retraining(self):
        """Stop background retraining thread"""
        self.stop_retraining = True
        if self.retraining_thread:
            self.retraining_thread.join(timeout=5)
        logger.info("🛑 Background retraining stopped")

    def _background_retraining_loop(self):
        """Background loop for checking and retraining models"""
        while not self.stop_retraining:
            try:
                logger.info("🔍 Checking for retraining opportunities...")
                self.check_and_retrain_all_models()

                # Sleep for the configured interval
                sleep_seconds = self.retraining_interval * 3600
                logger.info(f"💤 Sleeping for {self.retraining_interval} hours until next check")
                time.sleep(sleep_seconds)

            except Exception as e:
                logger.error(f"❌ Error in background retraining loop: {e}")
                time.sleep(300)  # Sleep 5 minutes on error

    def check_and_retrain_all_models(self):
        """Check all models for retraining opportunities"""
        symbols = self.config.get("symbols", [])
        timeframes = self.config.get("timeframes", [])

        for symbol in symbols:
            for timeframe in timeframes:
                try:
                    self.check_and_retrain_model(symbol, timeframe)
                except Exception as e:
                    logger.error(f"❌ Error checking {symbol} {timeframe}: {e}")

    def check_and_retrain_model(self, symbol: str, timeframe: str):
        """Check if a specific model needs retraining and retrain if needed"""
        model_key = f"{symbol}_{timeframe}"

        # Check if enough time has passed since last retraining
        last_check = self.last_retraining_check.get(model_key)
        if last_check and (datetime.now() - last_check).total_seconds() < 3600:  # 1 hour minimum
            return

        self.last_retraining_check[model_key] = datetime.now()

        # Get recent trade data
        recent_trades = self._get_recent_trades(symbol, timeframe)

        if len(recent_trades) < self.min_trades_for_retraining:
            logger.info(f"📊 {model_key}: Only {len(recent_trades)} trades (need {self.min_trades_for_retraining})")
            return

        # Check current model performance
        current_performance = self._evaluate_current_model(symbol, timeframe, recent_trades)

        if current_performance >= self.performance_threshold:
            logger.info(f"✅ {model_key}: Current performance {current_performance:.3f} >= threshold {self.performance_threshold}")
            return

        logger.info(f"🔄 {model_key}: Performance {current_performance:.3f} < threshold {self.performance_threshold}, retraining...")

        # Retrain the model
        success = self._retrain_model(symbol, timeframe, recent_trades)

        if success:
            logger.info(f"✅ {model_key}: Retraining completed successfully")
        else:
            logger.error(f"❌ {model_key}: Retraining failed")

    def _get_recent_trades(self, symbol: str, timeframe: str, days: int = 30) -> List[Dict]:
        """Get recent trade data with features from analytics server"""
        try:
            # Calculate date range
            end_date = datetime.now()
            start_date = end_date - timedelta(days=days)

            # Query analytics server for ML training data (trades + features)
            query_params = {
                "symbol": symbol,
                "timeframe": timeframe,
                "start_date": start_date.strftime("%Y-%m-%d"),
                "end_date": end_date.strftime("%Y-%m-%d")
            }

            response = requests.get(
                f"{self.analytics_url}/analytics/ml_training_data",
                params=query_params,
                timeout=30
            )

            if response.status_code == 200:
                trades = response.json()
                logger.info(f"📊 Retrieved {len(trades)} trades with features for {symbol} {timeframe}")
                return trades
            else:
                logger.error(f"❌ Failed to get ML training data: {response.status_code}")
                return []

        except Exception as e:
            logger.error(f"❌ Error getting recent trades: {e}")
            return []

    def _evaluate_current_model(self, symbol: str, timeframe: str, trades: List[Dict]) -> float:
        """Evaluate current model performance on recent trades"""
        if not trades:
            return 0.0

        try:
            # Load current model
            model_path = self.models_dir / f"combined_model_{symbol}_PERIOD_{timeframe}.pkl"
            if not model_path.exists():
                logger.warning(f"⚠️ No current model found for {symbol} {timeframe}")
                return 0.0

            model = joblib.load(model_path)

            # Load feature names to determine expected feature count
            feature_names_path = self.models_dir / f"combined_feature_names_{symbol}_PERIOD_{timeframe}.pkl"
            if feature_names_path.exists():
                with open(feature_names_path, 'rb') as f:
                    expected_feature_names = pickle.load(f)
                expected_feature_count = len(expected_feature_names)
                logger.info(f"📊 Model expects {expected_feature_count} features")
            else:
                # Fallback: assume 19 features for old models
                expected_feature_count = 19
                logger.info(f"📊 No feature names file found, assuming {expected_feature_count} features")

            # Prepare features from trades
            features_list = []
            labels = []

            for trade in trades:
                if 'features' in trade and trade['features']:
                    # Extract features based on model's expected count
                    features = self._extract_features_for_model(trade, expected_feature_count)
                    if features is not None:
                        features_list.append(features)

                        # Determine label based on profit/loss
                        profit_loss = trade.get('profit_loss', 0)
                        label = 1 if profit_loss > 0 else 0
                        labels.append(label)

            if len(features_list) < 10:
                logger.warning(f"⚠️ Insufficient features for evaluation: {len(features_list)}")
                return 0.0

            # Convert to numpy arrays
            X = np.array(features_list)
            y = np.array(labels)

            # Evaluate model
            predictions = model.predict(X)
            accuracy = accuracy_score(y, predictions)

            logger.info(f"📊 {symbol} {timeframe} current accuracy: {accuracy:.3f}")
            return accuracy

        except Exception as e:
            logger.error(f"❌ Error evaluating current model: {e}")
            return 0.0

    def _extract_features_from_trade(self, trade: Dict) -> Optional[List[float]]:
        """Extract features from trade data"""
        try:
            features = trade.get('features', {})
            if not features:
                return None

            # Extract the complete 28 universal features (including engineered features)
            feature_names = [
                # Basic technical indicators (17 features)
                'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
                'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum', 'force_index',
                'volume_ratio', 'price_change', 'volatility', 'spread',
                'session_hour', 'is_news_time',
                # Time features (2 features)
                'day_of_week', 'month',
                # Engineered features (9 features)
                'rsi_regime', 'stoch_regime', 'volatility_regime',
                'hour', 'session', 'is_london_session', 'is_ny_session',
                'is_asian_session', 'is_session_overlap'
            ]

            feature_values = []
            for feature_name in feature_names:
                value = features.get(feature_name, 0.0)
                feature_values.append(float(value))

            logger.debug(f"📊 Extracted {len(feature_values)} features from trade")
            return feature_values

        except Exception as e:
            logger.error(f"❌ Error extracting features: {e}")
            return None

    def _extract_features_for_model(self, trade: Dict, expected_feature_count: int) -> Optional[List[float]]:
        """Extract features from trade data based on model's expected feature count"""
        try:
            features = trade.get('features', {})
            if not features:
                return None

            if expected_feature_count == 28:
                # Use 28 features (including engineered features)
                feature_names = FeatureEngineeringUtils.get_expected_28_features()
            else:
                # Use 19 features (basic features only)
                feature_names = FeatureEngineeringUtils.get_expected_19_features()

            feature_values = []
            for feature_name in feature_names:
                value = features.get(feature_name, 0.0)
                feature_values.append(float(value))

            logger.debug(f"📊 Extracted {len(feature_values)} features for {expected_feature_count}-feature model")
            return feature_values

        except Exception as e:
            logger.error(f"❌ Error extracting features for model: {e}")
            return None

    def _retrain_model(self, symbol: str, timeframe: str, trades: List[Dict]) -> bool:
        """Retrain model with new trade data"""
        try:
            logger.info(f"🔄 Starting retraining for {symbol} {timeframe} with {len(trades)} trades")

            # Backup current model if enabled
            if self.backup_models:
                self._backup_current_model(symbol, timeframe)

            # Prepare training data
            training_data = self._prepare_training_data(trades)

            if len(training_data) < self.min_trades_for_retraining:
                logger.warning(f"⚠️ Insufficient training data: {len(training_data)}")
                return False

            # Retrain models using the improved ML trainer
            success = self.ml_trainer.retrain_models(
                symbol=symbol,
                timeframe=timeframe,
                training_data=training_data,
                models_dir=str(self.models_dir)
            )

            if success:
                # Update retraining history
                self.retraining_history[f"{symbol}_{timeframe}"] = {
                    "last_retraining": datetime.now().isoformat(),
                    "trades_used": len(training_data),
                    "performance": self._evaluate_current_model(symbol, timeframe, trades)
                }

                logger.info(f"✅ Retraining completed for {symbol} {timeframe}")
                return True
            else:
                logger.error(f"❌ Retraining failed for {symbol} {timeframe}")
                return False

        except Exception as e:
            logger.error(f"❌ Error during retraining: {e}")
            return False

    def _prepare_training_data(self, trades: List[Dict]) -> List[Dict]:
        """Prepare training data from trades"""
        training_data = []

        for trade in trades:
            if 'features' in trade and trade['features']:
                features = self._extract_features_from_trade(trade)
                if features is not None:
                    profit_loss = trade.get('profit_loss', 0)
                    label = 1 if profit_loss > 0 else 0

                    training_data.append({
                        'features': features,
                        'label': label,
                        'profit_loss': profit_loss,
                        'trade_id': trade.get('trade_id', ''),
                        'timestamp': trade.get('timestamp', 0)
                    })

        return training_data

    def _backup_current_model(self, symbol: str, timeframe: str):
        """Backup current model before retraining"""
        try:
            backup_dir = self.models_dir / "backups" / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            backup_dir.mkdir(parents=True, exist_ok=True)

            # Backup all model files for this symbol/timeframe
            model_pattern = f"*{symbol}_PERIOD_{timeframe}.pkl"
            for model_file in self.models_dir.glob(model_pattern):
                backup_file = backup_dir / model_file.name
                import shutil
                shutil.copy2(model_file, backup_file)

            logger.info(f"💾 Backed up {symbol} {timeframe} models to {backup_dir}")

        except Exception as e:
            logger.error(f"❌ Error backing up model: {e}")

    def get_retraining_status(self) -> Dict:
        """Get current retraining status"""
        return {
            "service_running": self.retraining_thread and self.retraining_thread.is_alive(),
            "last_retraining_check": self.last_retraining_check,
            "retraining_history": self.retraining_history,
            "config": self.config
        }

    def manual_retrain(self, symbol: str, timeframe: str) -> bool:
        """Manually trigger retraining for a specific model"""
        logger.info(f"🔧 Manual retraining requested for {symbol} {timeframe}")

        # Get recent trades
        recent_trades = self._get_recent_trades(symbol, timeframe, days=7)

        if len(recent_trades) < 10:
            logger.warning(f"⚠️ Insufficient data for manual retraining: {len(recent_trades)} trades")
            return False

        # Force retraining regardless of performance
        return self._retrain_model(symbol, timeframe, recent_trades)

def main():
    """Main function to run the live retraining service"""
    import argparse

    parser = argparse.ArgumentParser(description="Live Retraining Service for ML Models")
    parser.add_argument("--config", default="live_retraining_config.json", help="Configuration file path")
    parser.add_argument("--start", action="store_true", help="Start background retraining")
    parser.add_argument("--stop", action="store_true", help="Stop background retraining")
    parser.add_argument("--status", action="store_true", help="Show retraining status")
    parser.add_argument("--manual-retrain", help="Manually retrain model (format: SYMBOL_TIMEFRAME)")
    parser.add_argument("--check-all", action="store_true", help="Check all models for retraining")

    args = parser.parse_args()

    # Initialize service
    service = LiveRetrainingService(args.config)

    if args.start:
        service.start_background_retraining()
        try:
            # Keep running
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            service.stop_background_retraining()

    elif args.stop:
        service.stop_background_retraining()

    elif args.status:
        status = service.get_retraining_status()
        print(json.dumps(status, indent=2))

    elif args.manual_retrain:
        symbol, timeframe = args.manual_retrain.split('_', 1)
        success = service.manual_retrain(symbol, timeframe)
        print(f"Manual retraining {'succeeded' if success else 'failed'}")

    elif args.check_all:
        service.check_and_retrain_all_models()

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
