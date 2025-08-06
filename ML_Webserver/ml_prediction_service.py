#!/usr/bin/env python3
"""
ML Prediction Service with HTTP API
Real-time prediction service for MetaTrader 5 Expert Advisors
Loads trained .pkl models and provides predictions via HTTP API
Fully web-based - no MT5 file system dependencies
"""

import os
import json
import time
import glob
import logging
import numpy as np
import pandas as pd
import joblib
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import warnings
from flask import Flask, request, jsonify
import threading
warnings.filterwarnings('ignore')

# Import shared feature engineering utilities
from feature_engineering_utils import FeatureEngineeringUtils

# Configure logging
# Only set up file logging if we're running the service directly
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('logs/ml_prediction_service.log'),
            logging.StreamHandler()
        ]
    )
else:
    # For imports, just use basic logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[logging.StreamHandler()]
    )
logger = logging.getLogger(__name__)

# Initialize Flask app with increased request size limits
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB limit
app.config['JSON_MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB JSON limit
ml_service = None

class MLPredictionService:
    """Main ML prediction service for real-time trading predictions"""

    def __init__(self, models_dir: str = "ml_models"):
        """
        Initialize the ML prediction service

        Args:
            models_dir: Directory containing trained .pkl models
        """
        self.models_dir = Path(models_dir)

        # Load all available models
        self.models = {}
        self.scalers = {}
        self.feature_names = {}
        self.model_metadata = {}

        # Performance tracking
        self.prediction_count = 0
        self.error_count = 0
        self.start_time = time.time()

        # Load models
        self._load_all_models()

        logger.info(f"ML Prediction Service initialized")
        logger.info(f"Models directory: {self.models_dir}")
        logger.info(f"Loaded {len(self.models)} models")

    def _ensure_consistent_feature_names(self):
        """Ensure all feature names files contain the complete 28 universal features"""
        logger.info("🔧 Ensuring consistent feature names across all models...")

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
        for model_key, feature_names in self.feature_names.items():
            if feature_names is None:
                logger.warning(f"Model {model_key} has None feature names, skipping")
                continue

            # Handle different feature counts
            if len(feature_names) == 29 and 'adx' in feature_names:
                # Remove adx from 29-feature files
                feature_names = [f for f in feature_names if f != 'adx']
                self.feature_names[model_key] = feature_names
                logger.info(f"Removed 'adx' from {model_key} (29 -> 28 features)")
                updated_count += 1
            elif len(feature_names) != 28:
                # Only update if the model has fewer than 19 features (the minimum expected)
                if len(feature_names) < 19:
                    logger.warning(f"Model {model_key} has {len(feature_names)} features, updating to 28")
                    self.feature_names[model_key] = complete_features
                    updated_count += 1
                else:
                    logger.info(f"Model {model_key} has {len(feature_names)} features (19-feature model), keeping as-is")

        if updated_count > 0:
            logger.info(f"✅ Updated {updated_count} models to use consistent 28 features")
        else:
            logger.info("✅ All models already have consistent 28 features")

    def _extract_symbol_from_path(self, file_path: Path) -> str:
        """Extract symbol from file path dynamically"""
        filename = file_path.name

        # Try to extract from filename first (prioritize filename for + suffix)
        # Look for patterns like buy_feature_names_BTCUSD_PERIOD_H1.pkl or buy_feature_names_XAUUSD+_PERIOD_H1.pkl
        symbol_match = re.search(r'[a-z_]+_([A-Z]{6}\+?)_PERIOD_', filename)
        if symbol_match:
            extracted_symbol = symbol_match.group(1)
            # If filename contains + suffix, use it
            if '+' in extracted_symbol:
                return extracted_symbol

        # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
        path_parts = file_path.parts
        for i, part in enumerate(path_parts):
            if part in ['Models', 'BreakoutStrategy'] and i + 1 < len(path_parts):
                potential_symbol = path_parts[i + 1]
                # Check if it looks like a symbol (6-7 characters, mostly letters, may end with +)
                if (len(potential_symbol) in [6, 7] and
                    (potential_symbol.isalpha() or (potential_symbol.endswith('+') and potential_symbol[:-1].isalpha()))):
                    return potential_symbol

        # Fallback to filename extraction (for non-+ symbols)
        if symbol_match:
            return symbol_match.group(1)

        # Default fallback
        return "UNKNOWN_SYMBOL"

    def _load_all_models(self):
        """Load all available .pkl models from the models directory"""
        if not self.models_dir.exists():
            logger.warning(f"Models directory does not exist: {self.models_dir}")
            return

        # Find all .pkl files (excluding backup directories)
        pkl_files = []
        for pkl_file in self.models_dir.rglob("*.pkl"):
            # Skip backup directories
            if "backup" not in str(pkl_file):
                pkl_files.append(pkl_file)
        logger.info(f"Found {len(pkl_files)} .pkl files (excluding backups)")

        # Track loaded models to avoid duplicates
        loaded_model_keys = set()

        for pkl_file in pkl_files:
            try:
                filename = pkl_file.name

                # Only process model files, skip feature_names and scaler files
                if not ("_model_" in filename and filename.endswith(".pkl")):
                    continue

                # Handle webserver directory structure (flat structure)
                if "webserver" in str(self.models_dir) or "ml_models" in str(self.models_dir):
                    # Extract model info from filename
                    # Format: buy_model_BTCUSD_PERIOD_M5.pkl, sell_model_ETHUSD_PERIOD_H1.pkl, etc.
                    if "buy_model" in filename:
                        model_type = "buy"
                    elif "sell_model" in filename:
                        model_type = "sell"
                    elif "combined_model" in filename:
                        model_type = "combined"
                    else:
                        continue

                    # Extract timeframe from filename
                    timeframe = "H1"  # Default
                    if "PERIOD_H1" in filename:
                        timeframe = "H1"
                    elif "PERIOD_H4" in filename:
                        timeframe = "H4"
                    elif "PERIOD_M15" in filename:
                        timeframe = "M15"
                    elif "PERIOD_M30" in filename:
                        timeframe = "M30"
                    elif "PERIOD_M5" in filename:
                        timeframe = "M5"

                    # Dynamic symbol detection from file path
                    # Extract symbol from file path or filename
                    symbol = self._extract_symbol_from_path(pkl_file)

                    # Create model key: buy_{symbol}_PERIOD_{timeframe}
                    model_key = f"{model_type}_{symbol}_PERIOD_{timeframe}"

                    # Load model (all files with model in name are actual models)
                    if "model" in filename and filename.endswith(".pkl"):
                        # Load model
                        model = joblib.load(pkl_file)
                        self.models[model_key] = model

                        # Try to load corresponding scaler and feature names
                        scaler_filename = filename.replace("_model_", "_scaler_")
                        features_filename = filename.replace("_model_", "_feature_names_")

                        scaler_file = pkl_file.parent / scaler_filename
                        features_file = pkl_file.parent / features_filename

                        if scaler_file.exists():
                            self.scalers[model_key] = joblib.load(scaler_file)
                            logger.info(f"Loaded scaler for {model_key}")

                        if features_file.exists():
                            self.feature_names[model_key] = joblib.load(features_file)
                            logger.info(f"Loaded feature names for {model_key}")

                        # Store metadata
                        self.model_metadata[model_key] = {
                            'strategy': 'BreakoutStrategy',
                            'model_type': model_type,
                            'symbol': symbol,
                            'timeframe': timeframe,
                            'file_path': str(pkl_file),
                            'loaded_at': datetime.now().isoformat()
                        }

                        logger.info(f"✅ Loaded model: {model_key}")

                else:
                    # Handle structured directory (original format)
                    # Format: Models/BreakoutStrategy/{symbol}/{timeframe}/{model_type}_model.pkl
                    path_parts = pkl_file.parts

                    if len(path_parts) >= 4:
                        strategy = path_parts[-4]  # BreakoutStrategy
                        timeframe = path_parts[-2] # H1, H4, M5, M15, M30
                        filename = path_parts[-1]  # buy_model.pkl

                        # Extract model type from filename
                        if "buy_model" in filename:
                            model_type = "buy"
                        elif "sell_model" in filename:
                            model_type = "sell"
                        elif "combined_model" in filename:
                            model_type = "combined"
                        else:
                            continue

                        # Extract symbol from path
                        symbol = path_parts[-3]  # EURUSD, XAUUSD+, etc.

                        # Create model key
                        model_key = f"{model_type}_{symbol}_PERIOD_{timeframe}"

                        if model_key not in loaded_model_keys:
                            # Load model
                            model = joblib.load(pkl_file)
                            self.models[model_key] = model

                            # Try to load corresponding scaler and feature names
                            scaler_filename = filename.replace("_model_", "_scaler_")
                            features_filename = filename.replace("_model_", "_feature_names_")

                            scaler_file = pkl_file.parent / scaler_filename
                            features_file = pkl_file.parent / features_filename

                            if scaler_file.exists():
                                self.scalers[model_key] = joblib.load(scaler_file)
                                logger.info(f"Loaded scaler for {model_key}")

                            if features_file.exists():
                                self.feature_names[model_key] = joblib.load(features_file)
                                logger.info(f"Loaded feature names for {model_key}")

                            # Store metadata
                            self.model_metadata[model_key] = {
                                'strategy': strategy,
                                'model_type': model_type,
                                'symbol': symbol,
                                'timeframe': timeframe,
                                'file_path': str(pkl_file),
                                'loaded_at': datetime.now().isoformat()
                            }

                            loaded_model_keys.add(model_key)
                            logger.info(f"✅ Loaded model: {model_key}")

            except Exception as e:
                logger.error(f"Error loading model {pkl_file}: {e}")

        # Ensure consistent feature names across all models
        self._ensure_consistent_feature_names()

        logger.info(f"✅ Model loading completed - {len(self.models)} models loaded")

    def get_prediction(self, strategy: str, symbol: str, timeframe: str,
                      features: Dict, direction: str = "") -> Dict:
        """
        Get ML prediction for given features

        Args:
            strategy: Trading strategy name
            symbol: Trading symbol (e.g., EURUSD, XAUUSD+)
            timeframe: Timeframe (H1, H4, M5, M15, M30)
            features: Feature dictionary
            direction: Trade direction (buy, sell, or empty for auto)

        Returns:
            Dictionary with prediction results
        """
        try:
            self.prediction_count += 1

            logger.info(f"🔮 Prediction request - Strategy: {strategy}, Symbol: {symbol}, Timeframe: {timeframe}, Direction: {direction}")

            # Select appropriate model
            model_key = self._select_model(symbol, timeframe, direction)
            if not model_key:
                return self._create_error_response("No suitable model found")

            # Prepare features for the selected model
            prepared_features = self._prepare_features(features, model_key)
            if prepared_features is None:
                return self._create_error_response("Feature preparation failed")

            # Get model and make prediction
            model = self.models[model_key]
            prediction = model.predict_proba(prepared_features)[0]

            # Determine prediction type and probability
            if len(prediction) == 2:  # Binary classification (buy/sell)
                if direction.lower() == "buy":
                    probability = prediction[1]  # Probability of positive class (buy)
                elif direction.lower() == "sell":
                    probability = prediction[0]  # Probability of negative class (sell)
                else:
                    # Auto direction - use the higher probability
                    probability = max(prediction)
            else:  # Multi-class or regression
                probability = prediction[0]

            # Calculate confidence (simplified - could be enhanced)
            confidence = abs(probability - 0.5) * 2  # Scale to 0-1

            # Get model metadata
            metadata = self.model_metadata.get(model_key, {})
            model_type = metadata.get('model_type', 'unknown')

            result = {
                'status': 'success',
                'prediction': {
                    'probability': float(probability),
                    'confidence': float(confidence),
                    'model_key': model_key,
                    'model_type': model_type,
                    'direction': direction,
                    'strategy': strategy,
                    'symbol': symbol,
                    'timeframe': timeframe,
                    'timestamp': datetime.now().isoformat()
                },
                'metadata': {
                    'features_used': len(prepared_features[0]),
                    'model_file': metadata.get('file_path', 'unknown'),
                    'loaded_at': metadata.get('loaded_at', 'unknown')
                }
            }

            logger.info(f"✅ Prediction successful - Probability: {probability:.3f}, Confidence: {confidence:.3f}")
            return result

        except Exception as e:
            self.error_count += 1
            error_msg = f"Prediction error: {str(e)}"
            logger.error(f"❌ {error_msg}")
            return self._create_error_response(error_msg)

    def _select_model(self, symbol: str, timeframe: str, direction: str) -> str:
        """
        Select the most appropriate model for the given parameters

        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            direction: Trade direction

        Returns:
            Model key or None if no suitable model found
        """
        # Try to find exact match first
        if direction.lower() in ['buy', 'sell']:
            model_key = f"{direction}_{symbol}_PERIOD_{timeframe}"
            if model_key in self.models:
                return model_key

        # Try combined model
        combined_key = f"combined_{symbol}_PERIOD_{timeframe}"
        if combined_key in self.models:
            return combined_key

        # Try buy model as fallback
        buy_key = f"buy_{symbol}_PERIOD_{timeframe}"
        if buy_key in self.models:
            return buy_key

        # Try sell model as fallback
        sell_key = f"sell_{symbol}_PERIOD_{timeframe}"
        if sell_key in self.models:
            return sell_key

        # Log available models for debugging
        available_models = list(self.models.keys())
        logger.warning(f"No suitable model found for {symbol} {timeframe} {direction}")
        logger.warning(f"Available models: {available_models}")

        return None

    def _prepare_features(self, features: Dict, model_key: str) -> Optional[np.ndarray]:
        """Prepare features for ML prediction"""
        try:
            if model_key not in self.feature_names:
                logger.error(f"Model {model_key} not found in feature names")
                return None

            expected_features = self.feature_names[model_key]
            logger.info(f"Prepared {len(expected_features)} features for {model_key}")

            # Validate that features dictionary is not empty
            if not features:
                logger.error("Empty features dictionary provided")
                raise ValueError("Empty features dictionary provided")

            # Generate complete feature set including engineered features
            complete_features = self._generate_ml_features(features)

            # Create feature array based on what the model expects
            feature_array = []

            # Validate that all required features are present
            missing_features = []
            for feature in expected_features:
                if feature not in complete_features:
                    missing_features.append(feature)
                else:
                    feature_array.append(float(complete_features[feature]))

            if missing_features:
                error_msg = f"Missing required features: {missing_features}"
                logger.error(error_msg)
                raise ValueError(error_msg)

            # Convert to numpy array
            X = np.array(feature_array).reshape(1, -1)

            # Scale features if scaler is available
            if model_key in self.scalers:
                try:
                    X_scaled = self.scalers[model_key].transform(X)
                    logger.info(f"Model expects {X.shape[1]} features, scaler expects {self.scalers[model_key].n_features_in_}")
                    return X_scaled
                except Exception as e:
                    logger.warning(f"Scaler mismatch, using unscaled features: {e}")
                    return X
            else:
                logger.warning(f"No scaler found for {model_key}, using unscaled features")
                return X

        except Exception as e:
            logger.error(f"Feature preparation failed: {e}")
            return None

    def _generate_ml_features(self, features: Dict) -> Dict:
        """
        Generate complete ML feature set from raw features

        Args:
            features: Raw feature dictionary from EA

        Returns:
            Complete feature dictionary with engineered features
        """
        # Start with the basic features
        ml_features = {
            # Technical indicators (17 features)
            'rsi': features.get('rsi', 50.0),
            'stoch_main': features.get('stoch_main', 50.0),
            'stoch_signal': features.get('stoch_signal', 50.0),
            'macd_main': features.get('macd_main', 0.0),
            'macd_signal': features.get('macd_signal', 0.0),
            'bb_upper': features.get('bb_upper', 0.0),
            'bb_lower': features.get('bb_lower', 0.0),
            'williams_r': features.get('williams_r', 50.0),
            'cci': features.get('cci', 0.0),
            'momentum': features.get('momentum', 100.0),
            'force_index': features.get('force_index', 0.0),
            'volume_ratio': features.get('volume_ratio', 1.0),
            'price_change': features.get('price_change', 0.0),
            'volatility': features.get('volatility', 0.001),
            'spread': features.get('spread', 1.0),
            'session_hour': features.get('session_hour', 12),
            'is_news_time': features.get('is_news_time', False),
            'day_of_week': features.get('day_of_week', 1),
            'month': features.get('month', 7)
        }

        # Add engineered features (9 features)
        ml_features.update(self._calculate_engineered_features(ml_features))

        return ml_features

    def _calculate_engineered_features(self, features: Dict) -> Dict:
        """
        Calculate engineered features from basic features using shared utility

        Args:
            features: Basic feature dictionary

        Returns:
            Dictionary with engineered features
        """
        return FeatureEngineeringUtils.calculate_engineered_features(features)

    def _create_error_response(self, error_message: str) -> Dict:
        """Create standardized error response"""
        return {
            'status': 'error',
            'message': error_message,
            'timestamp': datetime.now().isoformat()
        }

    def get_status(self) -> Dict:
        """Get service status and statistics"""
        return {
            'status': 'running',
            'models_loaded': len(self.models),
            'available_models': list(self.models.keys()),
            'prediction_count': self.prediction_count,
            'error_count': self.error_count,
            'uptime': time.time() - self.start_time,
            'timestamp': datetime.now().isoformat()
        }

def initialize_ml_service():
    """Initialize the ML service globally"""
    global ml_service
    # Use local ml_models directory - fully web-based
    models_dir = Path("ml_models")
    ml_service = MLPredictionService(models_dir=str(models_dir))
    return ml_service

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    return jsonify({
        'status': 'healthy',
        'service': 'ML Prediction Service',
        'models_loaded': len(ml_service.models),
        'available_models': list(ml_service.models.keys()),
        'uptime': time.time() - ml_service.start_time
    })

@app.route('/predict', methods=['POST'])
def predict():
    """Get ML prediction endpoint"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    # Log raw request data with better error handling
    try:
        raw_data = request.get_data()
        raw_data_str = raw_data.decode('utf-8', errors='ignore')

        # Check if JSON is complete
        if raw_data_str and not raw_data_str.strip().endswith('}'):
            logger.error(f"❌ Incomplete JSON detected - data appears to be truncated")
            logger.error(f"   Expected JSON to end with '}}', but got: {raw_data_str[-50:]}")
            return jsonify({'status': 'error', 'message': 'Incomplete JSON data - request appears to be truncated'}), 400

    except Exception as e:
        logger.warning(f"   Could not decode raw request data: {e}")

    try:
        data = request.get_json()
        if not data:
            return jsonify({'status': 'error', 'message': 'No JSON data provided'}), 400

                # Extract parameters
        strategy = data.get('strategy', '')
        symbol = data.get('symbol', '')
        timeframe = data.get('timeframe', '')
        direction = data.get('direction', '')

        # Features are at the top level, not nested - filter out non-feature fields
        features = {k: v for k, v in data.items() if k not in ['strategy', 'symbol', 'timeframe', 'direction']}



        if not all([strategy, symbol, timeframe]):
            return jsonify({'status': 'error', 'message': 'Missing required parameters: strategy, symbol, timeframe'}), 400

        # Get prediction
        result = ml_service.get_prediction(strategy, symbol, timeframe, features, direction)

        # Check if the result indicates an error and return appropriate HTTP status code
        if result.get('status') == 'error':
            return jsonify(result), 400  # Return 400 Bad Request for validation errors
        else:
            return jsonify(result)

    except Exception as e:
        logger.error(f"❌ Error in predict endpoint: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/status', methods=['GET'])
def status():
    """Get detailed service status"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    return jsonify(ml_service.get_status())

@app.route('/models', methods=['GET'])
def list_models():
    """List all available models"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    return jsonify({
        'status': 'success',
        'models': ml_service.model_metadata,
        'count': len(ml_service.models)
    })

def main():
    """Main function to run the ML prediction service"""
    global ml_service

    logger.info("🚀 Starting ML Prediction Service...")

    # Initialize ML service
    ml_service = initialize_ml_service()

    if not ml_service.models:
        logger.warning("⚠️ No models loaded - service may not function properly")

    # Get port from environment variable or use default
    port = int(os.getenv('ML_SERVICE_PORT', 5003))

    logger.info("✅ ML Prediction Service ready")
    logger.info(f"📊 Loaded {len(ml_service.models)} models")
    logger.info(f"🌐 Starting Flask server on http://127.0.0.1:{port}")

    # Run Flask app
    app.run(host='127.0.0.1', port=port, debug=False)

if __name__ == "__main__":
    main()
