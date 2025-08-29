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
import requests
from flask import Flask, request, jsonify
import threading
warnings.filterwarnings('ignore')

# Import shared feature engineering utilities
from feature_engineering_utils import FeatureEngineeringUtils

# Import risk manager
from risk_manager import MLRiskManager

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
        self.response_times = []
        self.avg_response_time = 0

        # Analytics service connection for model health
        analytics_url = os.getenv('ANALYTICS_URL', 'http://localhost:5001')
        logger.info(f'analytics_url: {analytics_url}')
        self.analytics_url = analytics_url

        # Initialize risk manager
        self.risk_manager = MLRiskManager()

        # Load models
        self._load_all_models()

        logger.info(f"ML Prediction Service initialized")
        logger.info(f"Models directory: {self.models_dir}")
        logger.info(f"Loaded {len(self.models)} models")
        logger.info(f"Analytics service URL: {self.analytics_url}")

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
        # Also handle 7-letter symbols like TESTUSD
        symbol_match = re.search(r'[a-z_]+_([A-Z]{6,7}\+?)_PERIOD_', filename)
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
                      features: Dict, direction: str = "", enhanced: bool = False) -> Dict:
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
        start_time = time.time()
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

            # Calculate confidence (corrected - distance from 0.5, scaled to 0-1)
            confidence = abs(probability - 0.5) * 2  # This is actually correct!
            # Alternative: confidence = max(probability, 1 - probability)

                        # Get model metadata
            metadata = self.model_metadata.get(model_key, {})
            model_type = metadata.get('model_type', 'unknown')

            if enhanced:
                # Enhanced response with trade decision
                health_data, confidence_threshold = self._get_model_health_and_threshold(model_key)
                should_trade = confidence >= confidence_threshold

                # Calculate trade parameters if we should trade
                trade_params = {}
                if should_trade:
                    trade_params = self._calculate_trade_parameters(symbol, direction, features)

                result = {
                    'status': 'success',
                    'should_trade': int(should_trade),  # Convert to int (0 or 1) for JSON serialization
                    'confidence_threshold': float(confidence_threshold),
                    'model_health': health_data,
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
                    'trade_parameters': trade_params if should_trade else None,
                    'metadata': {
                        'features_used': len(prepared_features[0]),
                        'model_file': metadata.get('file_path', 'unknown'),
                        'loaded_at': metadata.get('loaded_at', 'unknown')
                    }
                }
            else:
                # Legacy response format (backward compatible)
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

            # Track response time
            response_time = (time.time() - start_time) * 1000  # Convert to milliseconds
            self.response_times.append(response_time)
            if len(self.response_times) > 100:  # Keep only last 100 measurements
                self.response_times.pop(0)
            self.avg_response_time = sum(self.response_times) / len(self.response_times)

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
                    logger.warning(f"Scaler mismatch for {model_key}: {e}")
                    logger.warning(f"Model expects {X.shape[1]} features, scaler expects {self.scalers[model_key].n_features_in_}")
                    # Try to handle feature mismatch by truncating or padding
                    if X.shape[1] > self.scalers[model_key].n_features_in_:
                        logger.warning(f"Truncating features from {X.shape[1]} to {self.scalers[model_key].n_features_in_}")
                        X = X[:, :self.scalers[model_key].n_features_in_]
                    elif X.shape[1] < self.scalers[model_key].n_features_in_:
                        logger.warning(f"Padding features from {X.shape[1]} to {self.scalers[model_key].n_features_in_}")
                        padding = np.zeros((1, self.scalers[model_key].n_features_in_ - X.shape[1]))
                        X = np.hstack([X, padding])

                    try:
                        X_scaled = self.scalers[model_key].transform(X)
                        logger.info(f"Successfully scaled features after adjustment")
                        return X_scaled
                    except Exception as e2:
                        logger.warning(f"Still failed after adjustment, using unscaled features: {e2}")
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

    def _get_model_health_and_threshold(self, model_key: str) -> Tuple[Dict, float]:
        """
        Get model health information and determine confidence threshold

        Args:
            model_key: The model key to check

        Returns:
            Tuple of (health_data, confidence_threshold)
        """
        try:
            # Try to get model health from analytics service
            response = requests.get(
                f"{self.analytics_url}/analytics/model_health",
                timeout=5
            )

            if response.status_code == 200:
                health_data = response.json()
                for model in health_data.get('models', []):
                    if model['model_key'] == model_key:
                        # Determine confidence threshold based on health status
                        if model['status'] == 'critical':
                            threshold = float(os.getenv('THRESHOLD_CRITICAL', 0.7))  # Broken confidence system
                        elif model['status'] == 'warning':
                            threshold = float(os.getenv('THRESHOLD_WARNING', 0.6))  # Concerning but not broken
                        else:
                            threshold = float(os.getenv('THRESHOLD_NORMAL', 0.3))  # Healthy model

                        return model, threshold

            # Fallback: return default health data and threshold
            return {'status': 'unknown', 'health_score': 50}, 0.5

        except Exception as e:
            logger.warning(f"Could not fetch model health for {model_key}: {e}")
            # Fallback: return default health data and threshold
            return {'status': 'unknown', 'health_score': 50}, 0.5

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

    def _calculate_trade_parameters(self, symbol: str, direction: str, features: Dict) -> Dict:
        """
        Calculate trade parameters based on features and market conditions

        Args:
            symbol: Trading symbol
            direction: Trade direction (BUY/SELL)
            features: Market features including current price

        Returns:
            Dictionary with trade parameters
        """
        try:
            # Extract current price from features (assuming it's provided)
            current_price = features.get('current_price', 0.0)

            if current_price <= 0:
                logger.warning("No current price provided, using default trade parameters")
                return {
                    'entry_price': 0.0,
                    'stop_loss': 0.0,
                    'take_profit': 0.0,
                    'lot_size': 0.1,
                    'risk_validation': {'status': 'error', 'reason': 'No current price'}
                }

            # Calculate ATR-based stop loss and take profit
            atr = features.get('atr', 0.001)  # Average True Range
            if atr <= 0:
                atr = current_price * 0.001  # Default to 0.1% of price

            # Risk management: 2:1 reward-to-risk ratio
            stop_loss_distance = atr * 2
            take_profit_distance = atr * 4

            if direction.upper() == 'BUY':
                stop_loss = current_price - stop_loss_distance
                take_profit = current_price + take_profit_distance
            else:  # SELL
                stop_loss = current_price + stop_loss_distance
                take_profit = current_price - take_profit_distance

            # Get account balance from features
            account_balance = features.get('account_balance', 10000)  # Default $10k

            # Use risk manager for lot size calculation
            lot_size, lot_calculation = self.risk_manager.calculate_optimal_lot_size(
                symbol, current_price, stop_loss, account_balance
            )

            # Check if new trade is allowed based on risk management rules
            can_trade, trade_validation = self.risk_manager.can_open_new_trade(
                symbol, lot_size, stop_loss_distance, direction.lower()
            )

            # Get current risk status
            risk_status = self.risk_manager.get_risk_status()

            # Prepare trade parameters with risk validation
            trade_params = {
                'entry_price': round(current_price, 5),
                'stop_loss': round(stop_loss, 5),
                'take_profit': round(take_profit, 5),
                'lot_size': round(lot_size, 2),
                'risk_validation': {
                    'can_trade': can_trade,
                    'validation_details': trade_validation,
                    'risk_status': risk_status['status'],
                    'portfolio_risk': risk_status['portfolio']['total_risk_percent'],
                    'current_drawdown': risk_status['portfolio']['current_drawdown_percent']
                },
                'lot_calculation': lot_calculation,
                'risk_metrics': {
                    'stop_distance': round(stop_loss_distance, 5),
                    'risk_reward_ratio': 2.0,
                    'atr_value': round(atr, 5)
                }
            }

            # If risk management blocks the trade, adjust parameters
            if not can_trade:
                logger.warning(f"Risk management blocked trade for {symbol}: {trade_validation.get('reason', 'Unknown')}")
                trade_params['risk_validation']['blocked_reason'] = trade_validation.get('reason', 'Unknown')
                # Set lot size to 0 to indicate blocked trade
                trade_params['lot_size'] = 0.0

            logger.info(f"Trade parameters calculated for {symbol} {direction}:")
            logger.info(f"  Entry: {trade_params['entry_price']}, SL: {trade_params['stop_loss']}, TP: {trade_params['take_profit']}")
            logger.info(f"  Lot Size: {trade_params['lot_size']}, Can Trade: {can_trade}")
            logger.info(f"  Risk Status: {risk_status['status']}, Portfolio Risk: {risk_status['portfolio']['total_risk_percent']:.2f}%")

            return trade_params

        except Exception as e:
            logger.error(f"Error calculating trade parameters: {e}")
            return {
                'entry_price': 0.0,
                'stop_loss': 0.0,
                'take_profit': 0.0,
                'lot_size': 0.1,
                'risk_validation': {'status': 'error', 'reason': str(e)}
            }

def initialize_ml_service():
    """Initialize the ML service globally"""
    global ml_service
    # Use models directory from environment variable or default to local ml_models
    models_dir = os.getenv('ML_MODELS_DIR', "/app/ml_models")
    ml_service = MLPredictionService(models_dir=str(models_dir))
    return ml_service

# Initialize Flask app with increased request size limits
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB limit
app.config['JSON_MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB JSON limit

# Initialize ML service on app startup
ml_service = initialize_ml_service()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    # Check if models are loaded
    if not ml_service.models:
        return jsonify({'status': 'unhealthy', 'message': 'No models loaded'}), 500

    # Check if analytics service is reachable
    try:
        response = requests.get(f"{ml_service.analytics_url}/health", timeout=30)
        analytics_healthy = response.status_code == 200
    except:
        analytics_healthy = False

    # Get basic performance metrics
    uptime = time.time() - ml_service.start_time
    success_rate = round((ml_service.prediction_count - ml_service.error_count) / max(ml_service.prediction_count, 1) * 100, 2)

    return jsonify({
        'status': 'healthy',
        'service': 'ML Prediction Service',
        'models_loaded': len(ml_service.models),
        'analytics_service': 'healthy' if analytics_healthy else 'unreachable',
        'uptime_seconds': int(uptime),
        'total_predictions': ml_service.prediction_count,
        'success_rate_percent': success_rate,
        'avg_response_time_ms': round(ml_service.avg_response_time, 2),
        'timestamp': datetime.now().isoformat()
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

@app.route('/trade_decision', methods=['POST'])
def trade_decision():
    """Enhanced trade decision endpoint - returns complete trade decision"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

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

        # Get enhanced prediction with trade decision
        result = ml_service.get_prediction(strategy, symbol, timeframe, features, direction, enhanced=True)

        # Check if the result indicates an error and return appropriate HTTP status code
        if result.get('status') == 'error':
            return jsonify(result), 400  # Return 400 Bad Request for validation errors
        else:
            # Ensure all values are JSON serializable
            try:
                return jsonify(result)
            except Exception as json_error:
                logger.error(f"❌ JSON serialization error: {json_error}")
                logger.error(f"   Result structure: {result}")

                # Extract values from the result for simplified fallback
                prediction = result.get('prediction', {})
                should_trade = result.get('should_trade', 0)
                confidence_threshold = result.get('confidence_threshold', 0.0)
                probability = prediction.get('probability', 0.0)
                confidence = prediction.get('confidence', 0.0)

                # Try to create a simplified response
                simplified_result = {
                    'status': 'success',
                    'should_trade': int(should_trade),
                    'confidence_threshold': float(confidence_threshold),
                    'prediction': {
                        'probability': float(probability),
                        'confidence': float(confidence),
                        'direction': direction
                    },
                    'message': 'Simplified response due to serialization error'
                }
                return jsonify(simplified_result)

    except Exception as e:
        logger.error(f"❌ Error in trade_decision endpoint: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/status', methods=['GET'])
def status():
    """Get detailed service status"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    return jsonify(ml_service.get_status())



@app.route('/risk/status', methods=['GET'])
def get_risk_status():
    """Get current risk management status using existing analytics data"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    try:
        # Get current positions from analytics service
        positions_data = get_current_positions_from_analytics()

        # Get portfolio summary from analytics service
        portfolio_data = get_portfolio_summary_from_analytics()

        # Update risk manager with current data
        ml_service.risk_manager.set_portfolio_data(portfolio_data)
        ml_service.risk_manager.set_positions_data(positions_data)

        # Get comprehensive risk status
        risk_status = ml_service.risk_manager.get_risk_status()

        return jsonify({
            'status': 'success',
            'risk_status': risk_status,
            'data_source': 'analytics_service',
            'timestamp': datetime.now().isoformat()
        })

    except Exception as e:
        logger.error(f"❌ Error getting risk status: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

def get_current_positions_from_analytics():
    """Get current open positions from analytics service via HTTP"""
    try:
        import requests

        # Get analytics service URL from environment or use default
        analytics_url = os.getenv('ANALYTICS_URL', 'http://localhost:5001')
        positions_endpoint = f"{analytics_url}/risk/positions"

        logger.info(f"🌐 Requesting positions from analytics service: {positions_endpoint}")

        response = requests.get(positions_endpoint, timeout=10)
        response.raise_for_status()

        data = response.json()

        if data['status'] == 'success':
            positions = data['positions']
            logger.info(f"✅ Retrieved {len(positions)} positions from analytics service")
            return positions
        else:
            logger.warning(f"⚠️ Analytics service returned error: {data.get('message', 'Unknown error')}")
            return []

    except requests.exceptions.RequestException as e:
        logger.error(f"❌ HTTP request failed to analytics service: {e}")
        return []
    except Exception as e:
        logger.error(f"❌ Error getting positions from analytics service: {e}")
        return []

def get_portfolio_summary_from_analytics():
    """Get portfolio summary from analytics service via HTTP"""
    try:
        import requests

        # Get analytics service URL from environment or use default
        analytics_url = os.getenv('ANALYTICS_URL', 'http://localhost:5001')
        portfolio_endpoint = f"{analytics_url}/risk/portfolio"

        logger.info(f"🌐 Requesting portfolio from analytics service: {portfolio_endpoint}")

        response = requests.get(portfolio_endpoint, timeout=10)
        response.raise_for_status()

        data = response.json()

        if data['status'] == 'success':
            portfolio = data['portfolio']
            logger.info(f"✅ Retrieved portfolio from analytics service: {portfolio['total_positions']} positions")
            return portfolio
        else:
            logger.warning(f"⚠️ Analytics service returned error: {data.get('message', 'Unknown error')}")
            return get_default_portfolio()

    except requests.exceptions.RequestException as e:
        logger.error(f"❌ HTTP request failed to analytics service: {e}")
        return get_default_portfolio()
    except Exception as e:
        logger.error(f"❌ Error getting portfolio from analytics service: {e}")
        return get_default_portfolio()

def get_default_portfolio():
    """Get default portfolio data when analytics service is unavailable"""
    return {
        'equity': 10000.0,
        'balance': 10000.0,
        'margin': 0.0,
        'free_margin': 10000.0,
        'total_positions': 0,
        'long_positions': 0,
        'short_positions': 0,
        'total_volume': 0.0,
        'avg_lot_size': 0.0
    }

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

@app.route('/performance', methods=['GET'])
def get_performance_metrics():
    """Get service performance metrics"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    uptime = time.time() - ml_service.start_time

    return jsonify({
        'status': 'success',
        'metrics': {
            'uptime_seconds': int(uptime),
            'uptime_formatted': f"{int(uptime // 3600)}h {int((uptime % 3600) // 60)}m {int(uptime % 60)}s",
            'total_predictions': ml_service.prediction_count,
            'total_errors': ml_service.error_count,
            'success_rate': round((ml_service.prediction_count - ml_service.error_count) / max(ml_service.prediction_count, 1) * 100, 2),
            'models_loaded': len(ml_service.models),
            'avg_response_time_ms': getattr(ml_service, 'avg_response_time', 0)
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/bulk_predict', methods=['POST'])
def bulk_predict():
    """Get predictions for multiple symbols/timeframes at once"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    try:
        data = request.get_json()
        if not data or 'requests' not in data:
            return jsonify({
                'status': 'error',
                'message': 'Missing "requests" array in request body'
            }), 400

        requests_list = data['requests']
        if not isinstance(requests_list, list) or len(requests_list) == 0:
            return jsonify({
                'status': 'error',
                'message': 'Requests must be a non-empty array'
            }), 400

        if len(requests_list) > 10:  # Limit to prevent abuse
            return jsonify({
                'status': 'error',
                'message': 'Maximum 10 requests allowed per call'
            }), 400

        results = []
        for req in requests_list:
            try:
                # Extract required fields
                symbol = req.get('symbol')
                timeframe = req.get('timeframe')
                direction = req.get('direction', 'buy')
                features = req.get('features', {})
                enhanced = req.get('enhanced', False)

                if not symbol or not timeframe:
                    results.append({
                        'status': 'error',
                        'message': 'Missing required fields: symbol and timeframe',
                        'request': req
                    })
                    continue

                # Get prediction
                result = ml_service.get_prediction(
                    symbol=symbol,
                    timeframe=timeframe,
                    direction=direction,
                    features=features,
                    enhanced=enhanced
                )

                results.append({
                    'status': 'success',
                    'request': req,
                    'result': result
                })

            except Exception as e:
                results.append({
                    'status': 'error',
                    'message': str(e),
                    'request': req
                })

        return jsonify({
            'status': 'success',
            'results': results,
            'total_requests': len(requests_list),
            'successful': len([r for r in results if r['status'] == 'success']),
            'timestamp': datetime.now().isoformat()
        })

    except Exception as e:
        logger.error(f"❌ Error in bulk_predict endpoint: {e}")
        return jsonify({
            'status': 'error',
            'message': f'Bulk prediction failed: {str(e)}'
        }), 500

@app.route('/model_versions', methods=['GET'])
def get_model_versions():
    """Get version information for all models"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    try:
        versions = {}
        for model_key in ml_service.models.keys():
            metadata = ml_service.model_metadata.get(model_key, {})
            versions[model_key] = {
                'model_type': metadata.get('model_type', 'unknown'),
                'training_date': metadata.get('training_date', 'unknown'),
                'last_retrained': metadata.get('last_retrained', 'unknown'),
                'model_version': metadata.get('model_version', 1.0),
                'retrained_by': metadata.get('retrained_by', 'unknown'),
                'health_score': metadata.get('health_score', 0),
                'cv_accuracy': metadata.get('cv_accuracy', 0),
                'confidence_correlation': metadata.get('confidence_correlation', 0),
                'training_samples': metadata.get('training_samples', 0),
                'features_used': metadata.get('features_used', []),
                'file_path': metadata.get('file_path', 'unknown'),
                'loaded_at': metadata.get('loaded_at', 'unknown')
            }

        return jsonify({
            'status': 'success',
            'model_versions': versions,
            'total_models': len(versions),
            'timestamp': datetime.now().isoformat()
        })

    except Exception as e:
        logger.error(f"❌ Error getting model versions: {e}")
        return jsonify({
            'status': 'error',
            'message': f'Failed to get model versions: {str(e)}'
        }), 500

@app.route('/reload_models', methods=['POST', 'GET'])
def reload_models():
    """Reload all models from the models directory"""
    if ml_service is None:
        return jsonify({'status': 'error', 'message': 'ML service not initialized'}), 500

    try:
        logger.info("🔄 Reloading models from models directory...")

        # Clear existing models
        ml_service.models.clear()
        ml_service.scalers.clear()
        ml_service.feature_names.clear()
        ml_service.model_metadata.clear()

        # Reload all models
        ml_service._load_all_models()

        # Ensure consistent feature names
        ml_service._ensure_consistent_feature_names()

        models_count = len(ml_service.models)
        logger.info(f"✅ Models reloaded successfully - {models_count} models loaded")

        return jsonify({
            'status': 'success',
            'message': f'Models reloaded successfully',
            'models_loaded': models_count,
            'available_models': list(ml_service.models.keys()),
            'timestamp': datetime.now().isoformat()
        })

    except Exception as e:
        error_msg = f"Failed to reload models: {str(e)}"
        logger.error(f"❌ {error_msg}")
        return jsonify({
            'status': 'error',
            'message': error_msg,
            'timestamp': datetime.now().isoformat()
        }), 500

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
