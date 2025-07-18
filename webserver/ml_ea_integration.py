#!/usr/bin/env python3
"""
ML EA Integration Script
Provides real-time ML predictions for the Neural Network Trade Logger EA
"""

import pandas as pd
import numpy as np
import joblib
import json
import os
from datetime import datetime
from flask import Flask, request, jsonify
import warnings
warnings.filterwarnings('ignore')

class MLEAIntegration:
    def __init__(self, model_path='ml_models/'):
        self.model_path = model_path
        self.scaler = None
        self.label_encoder = None
        self.model = None
        self.load_models()
    
    def load_models(self):
        """Load the trained ML models"""
        try:
            # Load scaler
            scaler_path = os.path.join(self.model_path, 'scaler.pkl')
            if os.path.exists(scaler_path):
                self.scaler = joblib.load(scaler_path)
                print(f"✅ Loaded scaler from {scaler_path}")
            
            # Load label encoder
            encoder_path = os.path.join(self.model_path, 'label_encoder.pkl')
            if os.path.exists(encoder_path):
                self.label_encoder = joblib.load(encoder_path)
                print(f"✅ Loaded label encoder from {encoder_path}")
            
            # Load prediction model
            model_path = os.path.join(self.model_path, 'trade_success_predictor.pkl')
            if os.path.exists(model_path):
                self.model = joblib.load(model_path)
                print(f"✅ Loaded prediction model from {model_path}")
            
            return True
        except Exception as e:
            print(f"❌ Error loading models: {e}")
            return False
    
    def preprocess_features(self, features_dict):
        """Preprocess features for ML prediction"""
        try:
            # Convert to DataFrame
            df = pd.DataFrame([features_dict])
            
            # Handle categorical features
            categorical_features = ['candle_pattern', 'candle_seq', 'zone_type', 'trend']
            for feature in categorical_features:
                if feature in df.columns and df[feature].iloc[0] != 'none':
                    # Encode categorical features
                    if self.label_encoder is not None:
                        try:
                            df[f'{feature}_encoded'] = self.label_encoder.transform([df[feature].iloc[0]])[0]
                        except:
                            df[f'{feature}_encoded'] = 0
                    else:
                        df[f'{feature}_encoded'] = 0
                else:
                    df[f'{feature}_encoded'] = 0
            
            # Select numeric features for ML
            numeric_features = [
                'rsi', 'stoch_main', 'stoch_signal', 'ad', 'volume', 'ma', 'atr',
                'macd_main', 'macd_signal', 'bb_upper', 'bb_lower', 'spread',
                'volume_ratio', 'price_change', 'volatility', 'session_hour'
            ]
            
            # Add encoded categorical features
            encoded_features = [f'{f}_encoded' for f in categorical_features]
            all_features = numeric_features + encoded_features
            
            # Filter available features
            available_features = [f for f in all_features if f in df.columns]
            
            if not available_features:
                print("❌ No features available for prediction")
                return None
            
            # Extract feature values
            feature_values = df[available_features].values
            
            # Scale features if scaler is available
            if self.scaler is not None:
                try:
                    feature_values = self.scaler.transform(feature_values)
                except Exception as e:
                    print(f"⚠️  Scaling failed: {e}")
            
            return feature_values
            
        except Exception as e:
            print(f"❌ Error preprocessing features: {e}")
            return None
    
    def predict_trade_success(self, features_dict):
        """Predict trade success probability"""
        try:
            if self.model is None:
                print("❌ No ML model loaded")
                return None
            
            # Preprocess features
            feature_values = self.preprocess_features(features_dict)
            if feature_values is None:
                return None
            
            # Make prediction
            prediction_proba = self.model.predict_proba(feature_values)[0]
            success_probability = prediction_proba[1]  # Probability of success
            
            # Calculate confidence based on feature agreement
            confidence = self.calculate_confidence(features_dict)
            
            # Determine direction
            direction = self.determine_direction(features_dict, success_probability)
            
            return {
                'prediction': success_probability,
                'confidence': confidence,
                'direction': direction,
                'features_used': len(feature_values[0]),
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            print(f"❌ Error making prediction: {e}")
            return None
    
    def calculate_confidence(self, features_dict):
        """Calculate confidence based on feature agreement"""
        try:
            confidence = 0.5  # Base confidence
            
            # Count agreeing signals
            bullish_signals = 0
            bearish_signals = 0
            
            # RSI signals
            rsi = features_dict.get('rsi', 50)
            if rsi < 30:
                bullish_signals += 1
            elif rsi > 70:
                bearish_signals += 1
            
            # Stochastic signals
            stoch = features_dict.get('stoch_main', 50)
            if stoch < 20:
                bullish_signals += 1
            elif stoch > 80:
                bearish_signals += 1
            
            # MACD signals
            macd_main = features_dict.get('macd_main', 0)
            macd_signal = features_dict.get('macd_signal', 0)
            if macd_main > macd_signal:
                bullish_signals += 1
            else:
                bearish_signals += 1
            
            # Volume confirmation
            volume_ratio = features_dict.get('volume_ratio', 1.0)
            if volume_ratio > 1.5:
                bullish_signals += 1
            
            # Trend alignment
            trend = features_dict.get('trend', 'none')
            if trend == 'bullish':
                bullish_signals += 1
            elif trend == 'bearish':
                bearish_signals += 1
            
            # Candle pattern
            pattern = features_dict.get('candle_pattern', 'none')
            if pattern in ['bullish_engulfing', 'hammer']:
                bullish_signals += 1
            elif pattern in ['bearish_engulfing', 'shooting_star']:
                bearish_signals += 1
            
            # Zone context
            zone_type = features_dict.get('zone_type', 'none')
            if zone_type == 'demand':
                bullish_signals += 1
            elif zone_type == 'supply':
                bearish_signals += 1
            
            # Calculate confidence based on signal agreement
            total_signals = bullish_signals + bearish_signals
            if total_signals > 0:
                max_signals = max(bullish_signals, bearish_signals)
                confidence = 0.5 + (max_signals / total_signals) * 0.4
            
            return min(confidence, 0.95)  # Cap at 95%
            
        except Exception as e:
            print(f"❌ Error calculating confidence: {e}")
            return 0.5
    
    def determine_direction(self, features_dict, prediction):
        """Determine trade direction based on features and prediction"""
        try:
            # Base direction on prediction probability
            if prediction > 0.6:
                return 'buy'
            elif prediction < 0.4:
                return 'sell'
            else:
                return 'neutral'
                
        except Exception as e:
            print(f"❌ Error determining direction: {e}")
            return 'neutral'
    
    def get_feature_importance(self):
        """Get feature importance from the model"""
        try:
            if self.model is None or not hasattr(self.model, 'feature_importances_'):
                return None
            
            # Get feature names
            feature_names = []
            numeric_features = [
                'rsi', 'stoch_main', 'stoch_signal', 'ad', 'volume', 'ma', 'atr',
                'macd_main', 'macd_signal', 'bb_upper', 'bb_lower', 'spread',
                'volume_ratio', 'price_change', 'volatility', 'session_hour'
            ]
            categorical_features = ['candle_pattern', 'candle_seq', 'zone_type', 'trend']
            
            for feature in numeric_features:
                feature_names.append(feature)
            
            for feature in categorical_features:
                feature_names.append(f'{feature}_encoded')
            
            # Create importance DataFrame
            importance_df = pd.DataFrame({
                'feature': feature_names[:len(self.model.feature_importances_)],
                'importance': self.model.feature_importances_
            })
            
            return importance_df.sort_values('importance', ascending=False)
            
        except Exception as e:
            print(f"❌ Error getting feature importance: {e}")
            return None

# Flask app for API integration
app = Flask(__name__)
ml_integration = MLEAIntegration()

@app.route('/api/ml/predict', methods=['POST'])
def predict_trade():
    """API endpoint for trade prediction"""
    try:
        # Get features from request
        features = request.json
        
        if not features:
            return jsonify({
                'success': False,
                'error': 'No features provided'
            }), 400
        
        # Make prediction
        result = ml_integration.predict_trade_success(features)
        
        if result is None:
            return jsonify({
                'success': False,
                'error': 'Failed to make prediction'
            }), 500
        
        return jsonify({
            'success': True,
            'result': result
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/ml/importance', methods=['GET'])
def get_feature_importance():
    """API endpoint for feature importance"""
    try:
        importance_df = ml_integration.get_feature_importance()
        
        if importance_df is None:
            return jsonify({
                'success': False,
                'error': 'No feature importance available'
            }), 500
        
        return jsonify({
            'success': True,
            'importance': importance_df.to_dict('records')
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/ml/status', methods=['GET'])
def get_ml_status():
    """API endpoint for ML system status"""
    try:
        status = {
            'model_loaded': ml_integration.model is not None,
            'scaler_loaded': ml_integration.scaler is not None,
            'encoder_loaded': ml_integration.label_encoder is not None,
            'model_path': ml_integration.model_path
        }
        
        return jsonify({
            'success': True,
            'status': status
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

if __name__ == '__main__':
    print("🚀 Starting ML EA Integration Server...")
    print(f"📁 Model path: {ml_integration.model_path}")
    
    # Test prediction with sample data
    sample_features = {
        'rsi': 45.5,
        'stoch_main': 35.2,
        'stoch_signal': 40.1,
        'ad': 1234567.89,
        'volume': 1000,
        'ma': 1.2345,
        'atr': 0.0012,
        'macd_main': 0.0005,
        'macd_signal': 0.0003,
        'bb_upper': 1.2400,
        'bb_lower': 1.2300,
        'spread': 1.2,
        'candle_pattern': 'hammer',
        'candle_seq': 'BBS',
        'zone_type': 'demand',
        'trend': 'bullish',
        'volume_ratio': 1.8,
        'price_change': 0.15,
        'volatility': 0.12,
        'session_hour': 14
    }
    
    print("🧪 Testing prediction with sample data...")
    result = ml_integration.predict_trade_success(sample_features)
    
    if result:
        print(f"✅ Test prediction successful:")
        print(f"   Prediction: {result['prediction']:.4f}")
        print(f"   Confidence: {result['confidence']:.4f}")
        print(f"   Direction: {result['direction']}")
    else:
        print("❌ Test prediction failed")
    
    # Start Flask server
    print("🌐 Starting API server on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=False) 