"""
Automated ML Model Retraining Pipeline
Integrates with AdvancedRetrainingFramework for systematic model improvement
"""

import os
import time
import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
import requests
import numpy as np
from advanced_retraining_framework import AdvancedRetrainingFramework

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/automated_retraining.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AutomatedRetrainingPipeline:
    """
    Automated pipeline for retraining ML models based on:
    - Performance degradation alerts
    - Confidence inversion detection
    - Time-based retraining schedules
    - Market regime changes
    """

    def __init__(self,
                 analytics_url: str = os.getenv('ANALYTICS_URL', "http://localhost:5001"),
                 ml_service_url: str = os.getenv('ML_SERVICE_URL', "http://localhost:5003"),
                 models_dir: str = "ml_models",
                 check_interval_minutes: int = 60):

        self.analytics_url = analytics_url
        self.ml_service_url = ml_service_url
        self.models_dir = Path(models_dir)
        self.check_interval = check_interval_minutes * 60  # Convert to seconds

        # Initialize advanced retraining framework
        self.retraining_framework = AdvancedRetrainingFramework(models_dir)

        # Retraining configuration
        self.auto_retrain_critical = True
        self.auto_retrain_warnings = False  # Manual review for warnings
        self.max_concurrent_retraining = 1  # Reduced to 1 to avoid overwhelming system
        self.retraining_cooldown_hours = 12  # Increased cooldown for failed retraining

        # Track retraining status
        self.retraining_history = {}
        self.active_retraining = {}

        # Performance thresholds
        self.retrain_thresholds = {
            'confidence_inversion': True,  # Always retrain
            'win_rate_below': 0.40,       # Increased from 35% to 40%
            'calibration_error_above': 0.30,  # Increased from 25% to 30%
            'days_since_training': 30,    # 30 days
            'health_score_below': 50      # Reduced from 60 to 50 (more lenient)
        }

    def check_model_alerts(self) -> Dict[str, Any]:
        """Check for model degradation alerts from analytics server"""
        try:
            response = requests.get(f"{self.analytics_url}/analytics/model_alerts", timeout=30)
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Failed to get model alerts: {response.status_code}")
                return {"alerts": [], "summary": {}}
        except Exception as e:
            logger.error(f"Analytics URL: {os.getenv('ANALYTICS_URL')}")
            logger.error(f"Error checking model alerts: {e}")
            return {"alerts": [], "summary": {}}

    def discover_new_models(self) -> List[Dict[str, Any]]:
        """Discover symbols/timeframes that have training data but no models"""
        try:
            logger.info("🔍 Discovering new models from available training data...")

            # Get all symbols/timeframes with recent training data
            response = requests.get(f"{self.analytics_url}/analytics/model_discovery", timeout=30)
            if response.status_code == 200:
                discovery_data = response.json()
                logger.info(f"✅ Discovered {len(discovery_data.get('new_models', []))} potential new models")
                return discovery_data.get('new_models', [])
            else:
                logger.warning(f"Model discovery endpoint returned {response.status_code}")
                return []

        except Exception as e:
            logger.error(f"Error discovering new models: {e}")
            return []

    def check_model_health(self) -> Dict[str, Any]:
        """Check overall model health status"""
        try:
            response = requests.get(f"{self.analytics_url}/analytics/model_health", timeout=30)
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Failed to get model health: {response.status_code}")
                return {"models": [], "summary": {}}
        except Exception as e:
            logger.error(f"Error checking model health: {e}")
            return {"models": [], "summary": {}}

    def get_training_data(self, symbol: str, timeframe: str, days: int = 90) -> List[Dict]:
        """Get training data for a specific model"""
        try:
            end_date = datetime.now()
            start_date = end_date - timedelta(days=days)

            params = {
                "symbol": symbol,
                "timeframe": timeframe,
                "start_date": start_date.strftime("%Y-%m-%d"),
                "end_date": end_date.strftime("%Y-%m-%d")
            }

            response = requests.get(
                f"{self.analytics_url}/analytics/ml_training_data",
                params=params,
                timeout=30
            )

            if response.status_code == 200:
                training_data = response.json()
                logger.info(f"Retrieved {len(training_data)} training samples for {symbol} {timeframe}")
                return training_data
            else:
                logger.error(f"Failed to get training data: {response.status_code}")
                return []

        except Exception as e:
            logger.error(f"Error getting training data for {symbol} {timeframe}: {e}")
            return []

    def should_retrain_model(self, model_key: str, alerts: List[Dict],
                           health_data: Optional[Dict] = None) -> Dict[str, Any]:
        """Determine if a model should be retrained based on alerts and health data"""

        retrain_reason = None
        priority = 'low'
        urgency = 'normal'

        # Check for critical alerts
        for alert in alerts:
            if alert['type'] == 'confidence_inversion':
                retrain_reason = "Critical: Confidence inversion detected"
                priority = 'critical'
                urgency = 'immediate'
                break

        # Check for warning alerts
        if not retrain_reason:
            for alert in alerts:
                if alert['level'] == 'warning':
                    if alert['type'] == 'low_win_rate':
                        retrain_reason = f"Warning: Low win rate ({alert.get('current_metrics', {}).get('win_rate', 0):.1f}%)"
                        priority = 'high'
                        urgency = 'soon'
                        break
                    elif alert['type'] == 'high_average_loss':
                        retrain_reason = f"Warning: High average loss (${alert.get('current_metrics', {}).get('avg_profit_loss', 0):.2f})"
                        priority = 'high'
                        urgency = 'soon'
                        break

        # Check health data if available
        if health_data and not retrain_reason:
            for model in health_data.get('models', []):
                if model['model_key'] == model_key:
                    if model['health_score'] < self.retrain_thresholds['health_score_below']:
                        retrain_reason = f"Low health score: {model['health_score']}/100"
                        priority = 'medium'
                        urgency = 'normal'
                    break

        # Check if model is already being retrained
        if model_key in self.active_retraining:
            last_retrain = self.active_retraining[model_key]['started_at']
            hours_since = (datetime.now() - last_retrain).total_seconds() / 3600

            if hours_since < self.retraining_cooldown_hours:
                return {
                    'should_retrain': False,
                    'reason': f"Retraining in progress (started {hours_since:.1f} hours ago)",
                    'priority': 'none',
                    'urgency': 'none'
                }

        # Gate auto-retrains for lenient first-time models until enough data/time accumulates
        try:
            direction, symbol, _, timeframe = model_key.split('_')
            metadata_path = self.models_dir / f"{direction}_metadata_{symbol}_PERIOD_{timeframe}.json"
            if metadata_path.exists():
                with open(metadata_path, 'r') as f:
                    metadata = json.load(f)

                used_lenient = metadata.get('used_lenient_threshold', False)
                training_date_str = metadata.get('training_date')

                if used_lenient and training_date_str:
                    # Compute days since training
                    try:
                        training_dt = datetime.fromisoformat(training_date_str)
                    except Exception:
                        training_dt = datetime.strptime(training_date_str[:19], '%Y-%m-%dT%H:%M:%S')

                    days_since = (datetime.now() - training_dt).days

                    # Count new closed trades with features since training
                    new_trades = self._count_new_trades_since_training(symbol, timeframe, training_dt)

                    min_days = 14
                    min_trades = 50
                    if days_since < min_days and new_trades < min_trades:
                        return {
                            'should_retrain': False,
                            'reason': f"Lenient model awaiting data: {days_since}d < {min_days} and {new_trades} < {min_trades} new trades",
                            'priority': 'none',
                            'urgency': 'none'
                        }
        except Exception as e:
            logger.warning(f"⚠️ Lenient gating check failed for {model_key}: {e}")

        return {
            'should_retrain': retrain_reason is not None,
            'reason': retrain_reason,
            'priority': priority,
            'urgency': urgency
        }

    def _count_new_trades_since_training(self, symbol: str, timeframe: str, since_dt: datetime) -> int:
        """Count number of closed trades with features since a given datetime using analytics service."""
        try:
            start_date = since_dt.strftime('%Y-%m-%d')
            end_date = datetime.now().strftime('%Y-%m-%d')
            params = {
                'symbol': symbol,
                'timeframe': timeframe,
                'start_date': start_date,
                'end_date': end_date,
            }
            resp = requests.get(f"{self.analytics_url}/analytics/ml_training_data", params=params, timeout=20)
            if resp.status_code == 200:
                data = resp.json()
                return len(data) if isinstance(data, list) else 0
            logger.warning(f"⚠️ Failed to count trades since training ({resp.status_code}) for {symbol} {timeframe}")
            return 0
        except Exception as e:
            logger.warning(f"⚠️ Error counting new trades since training for {symbol} {timeframe}: {e}")
            return 0

    def retrain_model(self, model_key: str, reason: str, priority: str) -> bool:
        """Retrain a specific model"""
        try:
            # Parse model key to get symbol and timeframe
            # Format: buy_EURUSD+_PERIOD_M5
            parts = model_key.split('_')
            if len(parts) < 3:
                logger.error(f"Invalid model key format: {model_key}")
                return False

            direction = parts[0]  # buy/sell
            symbol = parts[1]     # EURUSD+
            timeframe = parts[3]  # M5

            logger.info(f"🔄 Starting retraining for {model_key}")
            logger.info(f"   Reason: {reason}")
            logger.info(f"   Priority: {priority}")

            # Mark as actively retraining
            self.active_retraining[model_key] = {
                'started_at': datetime.now(),
                'reason': reason,
                'priority': priority,
                'status': 'in_progress'
            }

            # Get training data
            training_data = self.get_training_data(symbol, timeframe)
            if not training_data:
                logger.error(f"No training data available for {symbol} {timeframe}")
                self.active_retraining[model_key]['status'] = 'failed'
                return False

            # Use advanced retraining framework (strict only for retrains)
            success = self.retraining_framework.retrain_model(symbol, timeframe, training_data, direction, allow_lenient_threshold=False)

            if success:
                self.active_retraining[model_key]['status'] = 'completed'
                self.active_retraining[model_key]['completed_at'] = datetime.now()

                # Add to retraining history
                self.retraining_history[model_key] = {
                    'last_retrained': datetime.now().isoformat(),
                    'reason': reason,
                    'priority': priority,
                    'success': True,
                    'training_samples': len(training_data)
                }

                logger.info(f"✅ Retraining completed successfully for {model_key}")
                return True
            else:
                self.active_retraining[model_key]['status'] = 'failed'

                # Log detailed failure information
                logger.error(f"❌ Retraining failed for {model_key}")
                logger.error(f"   Symbol: {symbol}")
                logger.error(f"   Timeframe: {timeframe}")
                logger.error(f"   Direction: {direction}")
                logger.error(f"   Training samples: {len(training_data)}")
                logger.error(f"   Reason for retraining: {reason}")

                # Check for common failure reasons and provide specific diagnostics
                if len(training_data) < 20:
                    logger.error(f"   ❌ Insufficient training data: {len(training_data)} samples (minimum: 20)")
                elif len(training_data) < 50:
                    logger.warning(f"   ⚠️ Limited training data: {len(training_data)} samples (recommended: 50+)")

                # Check if features are present and analyze them
                if training_data and 'features' in training_data[0]:
                    features = training_data[0]['features']
                    if isinstance(features, dict):
                        feature_count = len(features)
                        logger.error(f"   Features available: {feature_count}")

                        # Check for missing or invalid features
                        invalid_features = []
                        for key, value in features.items():
                            if value is None or (isinstance(value, (int, float)) and (np.isnan(value) if hasattr(np, 'isnan') else False)):
                                invalid_features.append(key)

                        if invalid_features:
                            logger.error(f"   ❌ Invalid features found: {invalid_features[:5]}{'...' if len(invalid_features) > 5 else ''}")

                        # Check feature types
                        numeric_features = [k for k, v in features.items() if isinstance(v, (int, float)) and not (hasattr(np, 'isnan') and np.isnan(v))]
                        logger.error(f"   Numeric features: {len(numeric_features)}")

                    else:
                        logger.error(f"   ❌ Features format invalid: expected dict, got {type(features)}")
                else:
                    logger.error(f"   ❌ No features found in training data")

                # Analyze training data quality
                if training_data:
                    # Check for profit/loss distribution
                    profits = [row.get('profit_loss', 0) for row in training_data if row.get('profit_loss') is not None]
                    if profits:
                        wins = sum(1 for p in profits if p > 0)
                        total = len(profits)
                        win_rate = (wins / total * 100) if total > 0 else 0
                        logger.error(f"   Win rate in training data: {win_rate:.1f}% ({wins}/{total})")

                        # Check for class imbalance
                        if win_rate < 20 or win_rate > 80:
                            logger.error(f"   ⚠️ Severe class imbalance detected: {win_rate:.1f}% wins")

                # Store comprehensive error details for debugging
                self.active_retraining[model_key]['error_details'] = {
                    'symbol': symbol,
                    'timeframe': timeframe,
                    'direction': direction,
                    'training_samples': len(training_data),
                    'reason': reason,
                    'feature_count': len(training_data[0]['features']) if training_data and 'features' in training_data[0] and isinstance(training_data[0]['features'], dict) else 0,
                    'data_quality_issues': self._analyze_data_quality(training_data),
                    'failure_time': datetime.now().isoformat()
                }

                return False

        except Exception as e:
            import traceback

            logger.error(f"❌ Exception during retraining of {model_key}: {e}")
            logger.error(f"   Exception type: {type(e).__name__}")
            logger.error(f"   Full traceback:")
            logger.error(traceback.format_exc())

            if model_key in self.active_retraining:
                self.active_retraining[model_key]['status'] = 'failed'
                self.active_retraining[model_key]['error'] = str(e)
                self.active_retraining[model_key]['exception_type'] = type(e).__name__
                self.active_retraining[model_key]['traceback'] = traceback.format_exc()
                self.active_retraining[model_key]['failure_time'] = datetime.now().isoformat()

            return False

    def create_new_model(self, symbol: str, timeframe: str, direction: str, reason: str) -> bool:
        """Create a new model from scratch using available training data"""
        try:
            model_key = f"{direction}_{symbol}_PERIOD_{timeframe}"
            # Guard 1: skip if we already have an in-flight creation for this key
            if model_key in self.active_retraining and self.active_retraining[model_key].get('status') in {'creating','in_progress'}:
                logger.info(f"⏳ Skipping new model creation for {model_key}: already in progress")
                return False

            # Guard 2: skip if model artifacts already exist on disk
            model_path = self.models_dir / f"{direction}_model_{symbol}_PERIOD_{timeframe}.pkl"
            scaler_path = self.models_dir / f"{direction}_scaler_{symbol}_PERIOD_{timeframe}.pkl"
            feature_names_path = self.models_dir / f"{direction}_feature_names_{symbol}_PERIOD_{timeframe}.pkl"
            metadata_path = self.models_dir / f"{direction}_metadata_{symbol}_PERIOD_{timeframe}.json"

            def _exists_min(p: Path, min_bytes: int) -> bool:
                try:
                    return p.exists() and p.stat().st_size >= min_bytes
                except Exception:
                    return False

            if _exists_min(model_path, 1024) and _exists_min(scaler_path, 200) and _exists_min(feature_names_path, 100) and _exists_min(metadata_path, 150):
                logger.info(f"🛑 Skipping new model creation for {model_key}: artifacts already exist")
                return True
            logger.info(f"🆕 Creating new model: {model_key}")
            logger.info(f"   Symbol: {symbol}")
            logger.info(f"   Timeframe: {timeframe}")
            logger.info(f"   Direction: {direction}")
            logger.info(f"   Reason: {reason}")

            # Mark as actively creating
            self.active_retraining[model_key] = {
                'started_at': datetime.now(),
                'reason': reason,
                'priority': 'high',
                'status': 'creating',
                'type': 'new_model'
            }

            # Get training data for this symbol/timeframe combination
            training_data = self.get_training_data(symbol, timeframe)
            if not training_data:
                logger.error(f"No training data available for {symbol} {timeframe}")
                self.active_retraining[model_key]['status'] = 'failed'
                return False

            logger.info(f"📊 Retrieved {len(training_data)} training samples for new {symbol} {timeframe} model")

            # Use advanced retraining framework to create the model
            # For first-time creation, allow lenient threshold
            success = self.retraining_framework.retrain_model(symbol, timeframe, training_data, direction, allow_lenient_threshold=True)

            if success:
                self.active_retraining[model_key]['status'] = 'completed'
                self.active_retraining[model_key]['completed_at'] = datetime.now()

                # Add to retraining history
                self.retraining_history[model_key] = {
                    'last_retrained': datetime.now().isoformat(),
                    'reason': reason,
                    'priority': 'high',
                    'success': True,
                    'training_samples': len(training_data),
                    'type': 'new_model_creation'
                }

                logger.info(f"✅ New model created successfully: {model_key}")
                return True
            else:
                self.active_retraining[model_key]['status'] = 'failed'
                logger.error(f"❌ Failed to create new model: {model_key}")
                return False

        except Exception as e:
            import traceback
            logger.error(f"❌ Exception during new model creation of {model_key}: {e}")
            logger.error(f"   Exception type: {type(e).__name__}")
            logger.error(f"   Full traceback:")
            logger.error(traceback.format_exc())

            # Also log training data details for debugging
            logger.error(f"   Debug info: Training data count: {len(training_data) if 'training_data' in locals() else 'N/A'}")
            if 'training_data' in locals() and training_data:
                sample = training_data[0]
                logger.error(f"   Debug info: Sample data keys: {list(sample.keys()) if isinstance(sample, dict) else 'Not a dict'}")
                if isinstance(sample, dict) and 'features' in sample:
                    features = sample['features']
                    logger.error(f"   Debug info: Features type: {type(features)}, is_dict: {isinstance(features, dict)}")
                    if isinstance(features, dict):
                        logger.error(f"   Debug info: Feature keys: {list(features.keys())}")
                        logger.error(f"   Debug info: Feature values sample: {list(features.values())[:3]}")

            if model_key in self.active_retraining:
                self.active_retraining[model_key]['status'] = 'failed'
                self.active_retraining[model_key]['error'] = str(e)
                self.active_retraining[model_key]['exception_type'] = type(e).__name__
                self.active_retraining[model_key]['traceback'] = traceback.format_exc()
                self.active_retraining[model_key]['failure_time'] = datetime.now().isoformat()

            return False

        except Exception as e:
            import traceback

            logger.error(f"❌ Exception during retraining of {model_key}: {e}")
            logger.error(f"   Exception type: {type(e).__name__}")
            logger.error(f"   Full traceback:")
            logger.error(traceback.format_exc())

            if model_key in self.active_retraining:
                self.active_retraining[model_key]['status'] = 'failed'
                self.active_retraining[model_key]['error'] = str(e)
                self.active_retraining[model_key]['exception_type'] = type(e).__name__
                self.active_retraining[model_key]['traceback'] = traceback.format_exc()
                self.active_retraining[model_key]['failure_time'] = datetime.now().isoformat()

            return False

    def _analyze_data_quality(self, training_data: List[Dict]) -> Dict[str, Any]:
        """Analyze training data quality and identify potential issues"""
        if not training_data:
            return {'error': 'No training data provided'}

        analysis = {
            'total_samples': len(training_data),
            'issues': [],
            'warnings': []
        }

        try:
            # Check sample size
            if len(training_data) < 20:
                analysis['issues'].append(f"Insufficient data: {len(training_data)} samples (minimum: 20)")
            elif len(training_data) < 50:
                analysis['warnings'].append(f"Limited data: {len(training_data)} samples (recommended: 50+)")

            # Check features
            if 'features' in training_data[0]:
                features = training_data[0]['features']
                if isinstance(features, dict):
                    feature_count = len(features)
                    analysis['feature_count'] = feature_count

                    # Check for invalid features
                    invalid_features = []
                    for key, value in features.items():
                        if value is None or (isinstance(value, (int, float)) and np.isnan(value)):
                            invalid_features.append(key)

                    if invalid_features:
                        analysis['issues'].append(f"Invalid features: {len(invalid_features)} features with None/NaN values")
                        analysis['invalid_features'] = invalid_features[:10]  # Limit to first 10

                    # Check feature types
                    numeric_features = [k for k, v in features.items() if isinstance(v, (int, float)) and not np.isnan(v)]
                    analysis['numeric_features'] = len(numeric_features)

                    if len(numeric_features) < feature_count * 0.8:
                        analysis['warnings'].append(f"Low numeric feature ratio: {len(numeric_features)}/{feature_count}")
                else:
                    analysis['issues'].append(f"Invalid features format: expected dict, got {type(features)}")
            else:
                analysis['issues'].append("No features found in training data")

            # Check profit/loss distribution
            profits = [row.get('profit_loss', 0) for row in training_data if row.get('profit_loss') is not None]
            if profits:
                wins = sum(1 for p in profits if p > 0)
                total = len(profits)
                win_rate = (wins / total * 100) if total > 0 else 0
                analysis['win_rate'] = win_rate
                analysis['wins'] = wins
                analysis['total_trades'] = total

                # Check for class imbalance
                if win_rate < 20:
                    analysis['issues'].append(f"Severe class imbalance: {win_rate:.1f}% wins (too few winning trades)")
                elif win_rate > 80:
                    analysis['issues'].append(f"Severe class imbalance: {win_rate:.1f}% wins (too few losing trades)")
                elif win_rate < 30 or win_rate > 70:
                    analysis['warnings'].append(f"Moderate class imbalance: {win_rate:.1f}% wins")

                # Check profit distribution
                if profits:
                    avg_profit = np.mean(profits)
                    std_profit = np.std(profits)
                    analysis['avg_profit'] = avg_profit
                    analysis['std_profit'] = std_profit

                    if abs(avg_profit) < 0.01:  # Very small average profit
                        analysis['warnings'].append(f"Very small average profit: ${avg_profit:.4f}")

                    if std_profit < 0.01:  # Very low volatility
                        analysis['warnings'].append(f"Very low profit volatility: ${std_profit:.4f}")

            # Check for missing critical fields
            required_fields = ['profit_loss', 'features']
            missing_fields = []
            for field in required_fields:
                if field not in training_data[0]:
                    missing_fields.append(field)

            if missing_fields:
                analysis['issues'].append(f"Missing required fields: {missing_fields}")

        except Exception as e:
            analysis['error'] = f"Error during analysis: {str(e)}"

        return analysis

    def process_retraining_queue(self) -> Dict[str, Any]:
        """Process the retraining queue based on alerts and health data"""
        try:
            logger.info("🔄 Processing retraining queue...")

            # Get current alerts and health data
            alerts_data = self.check_model_alerts()
            health_data = self.check_model_health()

            # Discover new models that need to be created
            new_models = self.discover_new_models()

            # Combine existing alerts with new model discoveries
            all_models_to_process = []

            # Add existing alerts
            if alerts_data.get('alerts'):
                for alert in alerts_data['alerts']:
                    all_models_to_process.append({
                        'model_key': alert['model_key'],
                        'type': 'existing_model',
                        'reason': 'degradation_alert',
                        'priority': 'high' if alert['alert_level'] == 'critical' else 'medium'
                    })

            # Add new model discoveries
            for new_model in new_models:
                all_models_to_process.append({
                    'model_key': f"{new_model['direction']}_{new_model['symbol']}_PERIOD_{new_model['timeframe']}",
                    'type': 'new_model',
                    'reason': 'new_model_discovery',
                    'priority': 'high',
                    'discovery_data': new_model
                })

            if not all_models_to_process:
                logger.info("No models to process (alerts or new discoveries)")
                return {"processed": 0, "retrained": 0, "skipped": 0, "new_models": 0}

            # Process each model (existing alerts + new discoveries)
            processed = 0
            retrained = 0
            skipped = 0
            new_models_created = 0

            for model_info in all_models_to_process:
                model_key = model_info['model_key']
                model_type = model_info['type']
                reason = model_info['reason']
                priority = model_info['priority']

                processed += 1

                if model_type == 'new_model':
                    # This is a new model discovery - create it from scratch
                    logger.info(f"🆕 Creating new model: {model_key}")
                    logger.info(f"   Reason: {reason}")
                    logger.info(f"   Priority: {priority}")

                    # Check if we can start more retraining
                    active_count = len([k for k, v in self.active_retraining.items()
                                     if v['status'] == 'in_progress'])

                    if active_count >= self.max_concurrent_retraining:
                        logger.info(f"Max concurrent retraining reached, skipping {model_key}")
                        skipped += 1
                        continue

                    # Create new model using discovery data
                    discovery_data = model_info['discovery_data']
                    success = self.create_new_model(
                        discovery_data['symbol'],
                        discovery_data['timeframe'],
                        discovery_data['direction'],
                        reason
                    )

                    if success:
                        new_models_created += 1
                        logger.info(f"✅ New model created successfully: {model_key}")
                    else:
                        skipped += 1
                        logger.error(f"❌ Failed to create new model: {model_key}")

                    continue

                # Handle existing model alerts vs new model creation
                if model_type == 'existing_model':
                    # Handle existing model alerts
                    if model_key in alerts_data.get('alerts', []):
                        alerts = alerts_data['alerts'][model_key]
                        # Check if retraining is needed
                        retrain_decision = self.should_retrain_model(model_key, alerts, health_data)
                    else:
                        # No alerts for this model, skip
                        retrain_decision = {'should_retrain': False, 'reason': 'No alerts found', 'priority': 'low'}
                elif model_type == 'new_model':
                    # For new models, we always want to create them
                    retrain_decision = {'should_retrain': True, 'reason': 'new_model_discovery', 'priority': 'high'}
                else:
                    # Unknown model type, skip
                    retrain_decision = {'should_retrain': False, 'reason': 'Unknown model type', 'priority': 'low'}

                if retrain_decision['should_retrain']:
                    # Check if we can start more retraining
                    active_count = len([k for k, v in self.active_retraining.items()
                                     if v['status'] == 'in_progress'])

                    if active_count >= self.max_concurrent_retraining:
                        logger.info(f"Max concurrent retraining reached, skipping {model_key}")
                        skipped += 1
                        continue

                    # Start retraining or model creation
                    if model_type == 'new_model':
                        # Create new model from scratch
                        discovery_data = model_info['discovery_data']
                        success = self.create_new_model(
                            discovery_data['symbol'],
                            discovery_data['timeframe'],
                            discovery_data['direction'],
                            retrain_decision['reason']
                        )
                        if success:
                            new_models_created += 1
                        else:
                            skipped += 1
                    else:
                        # Retrain existing model
                        success = self.retrain_model(
                            model_key,
                            retrain_decision['reason'],
                            retrain_decision['priority']
                        )
                        if success:
                            retrained += 1
                        else:
                            skipped += 1
                else:
                    skipped += 1
                    logger.info(f"Skipping {model_key}: {retrain_decision['reason']}")

            # Clean up completed retraining
            self._cleanup_completed_retraining()

            # Reload ML service models if any were created or retrained
            if retrained > 0 or new_models_created > 0:
                logger.info(f"🔄 Reloading ML service models after {retrained} retrains and {new_models_created} new models")
                reload_success = self._reload_ml_service_models()
                if not reload_success:
                    logger.warning("⚠️ Failed to reload ML service models - they may not be available until service restart")

            result = {
                "processed": processed,
                "retrained": retrained,
                "skipped": skipped,
                "new_models_created": new_models_created,
                "active_retraining": len([k for k, v in self.active_retraining.items()
                                       if v['status'] == 'in_progress'])
            }

            logger.info(f"✅ Retraining queue processed: {result}")
            return result

        except Exception as e:
            logger.error(f"❌ Error processing retraining queue: {e}")
            return {"processed": 0, "retrained": 0, "skipped": 0, "error": str(e)}

    def _cleanup_completed_retraining(self):
        """Clean up completed retraining entries"""
        current_time = datetime.now()
        to_remove = []

        for model_key, status in self.active_retraining.items():
            if status['status'] in ['completed', 'failed']:
                # Keep for 24 hours for history
                if (current_time - status.get('completed_at', status['started_at'])).total_seconds() > 86400:
                    to_remove.append(model_key)

        for model_key in to_remove:
            del self.active_retraining[model_key]

    def get_retraining_status(self) -> Dict[str, Any]:
        """Get current retraining status"""
        return {
            "active_retraining": self.active_retraining,
            "retraining_history": self.retraining_history,
            "configuration": {
                "auto_retrain_critical": self.auto_retrain_critical,
                "auto_retrain_warnings": self.auto_retrain_warnings,
                "max_concurrent_retraining": self.max_concurrent_retraining,
                "retraining_cooldown_hours": self.retraining_cooldown_hours,
                "check_interval_minutes": self.check_interval // 60
            }
        }

    def get_detailed_retraining_status(self, model_key: str = None) -> Dict[str, Any]:
        """Get detailed retraining status for debugging"""
        if model_key:
            if model_key in self.active_retraining:
                return {
                    'model_key': model_key,
                    'status': self.active_retraining[model_key]
                }
            else:
                return {'error': f'Model {model_key} not found in active retraining'}

        # Return all retraining statuses with detailed error information
        failed_models = {}
        for key, status in self.active_retraining.items():
            if status['status'] == 'failed':
                failed_models[key] = {
                    'error': status.get('error', 'Unknown error'),
                    'exception_type': status.get('exception_type', 'N/A'),
                    'failure_time': status.get('failure_time', 'N/A'),
                    'error_details': status.get('error_details', {}),
                    'reason': status.get('reason', 'N/A'),
                    'started_at': status.get('started_at', 'N/A')
                }

        return {
            'active_retraining': self.active_retraining,
            'retraining_history': self.retraining_history,
            'failed_models_details': failed_models,
            'total_active': len([k for k, v in self.active_retraining.items() if v['status'] == 'in_progress']),
            'total_failed': len([k for k, v in self.active_retraining.items() if v['status'] == 'failed']),
            'total_completed': len([k for k, v in self.active_retraining.items() if v['status'] == 'completed'])
        }

    def run_continuous_monitoring(self):
        """Run continuous monitoring and retraining"""
        logger.info("🚀 Starting continuous monitoring and retraining pipeline")
        logger.info(f"   Check interval: {self.check_interval // 60} minutes")
        logger.info(f"   Max concurrent retraining: {self.max_concurrent_retraining}")

        try:
            while True:
                logger.info("🔄 Running retraining check...")

                # Process retraining queue
                result = self.process_retraining_queue()

                # Log summary
                if result.get('retrained', 0) > 0:
                    logger.info(f"🎉 Retrained {result['retrained']} models in this cycle")

                # Wait for next check
                logger.info(f"⏰ Next check in {self.check_interval // 60} minutes")
                time.sleep(self.check_interval)

        except KeyboardInterrupt:
            logger.info("🛑 Continuous monitoring stopped by user")
        except Exception as e:
            logger.error(f"❌ Continuous monitoring error: {e}")
            raise

    def manual_retrain(self, model_key: str, reason: str = "Manual retraining") -> bool:
        """Manually trigger retraining for a specific model"""
        logger.info(f"🔧 Manual retraining requested for {model_key}")
        return self.retrain_model(model_key, reason, 'manual')

    def _reload_ml_service_models(self) -> bool:
        """Reload models in the ML service after retraining"""
        try:
            logger.info("🔄 Reloading models in ML service...")
            response = requests.post(f"{self.ml_service_url}/reload_models", timeout=30)

            if response.status_code == 200:
                result = response.json()
                if result.get('status') == 'success':
                    model_count = result.get('models_loaded', 0)
                    logger.info(f"✅ Successfully reloaded {model_count} models in ML service")
                    return True
                else:
                    logger.error(f"❌ ML service reload failed: {result.get('message', 'Unknown error')}")
                    return False
            else:
                logger.error(f"❌ ML service reload request failed with status {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"❌ Error reloading ML service models: {e}")
            return False

    def debug_retraining_failure(self, model_key: str) -> Dict[str, Any]:
        """Debug a specific retraining failure"""
        if model_key not in self.active_retraining:
            return {'error': f'Model {model_key} not found in active retraining'}

        status = self.active_retraining[model_key]
        if status['status'] != 'failed':
            return {'error': f'Model {model_key} is not in failed status (current: {status["status"]})'}

        # Get detailed error information
        error_info = {
            'model_key': model_key,
            'status': status['status'],
            'started_at': status.get('started_at', 'N/A'),
            'failure_time': status.get('failure_time', 'N/A'),
            'reason': status.get('reason', 'N/A'),
            'error': status.get('error', 'No error message'),
            'exception_type': status.get('exception_type', 'N/A'),
            'error_details': status.get('error_details', {})
        }

        # Add traceback if available
        if 'traceback' in status:
            error_info['traceback'] = status['traceback']

        return error_info

def main():
    """Example usage and testing"""
    import sys

    pipeline = AutomatedRetrainingPipeline()

    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == "debug" and len(sys.argv) > 2:
            model_key = sys.argv[2]
            print(f"🔍 Debugging retraining failure for {model_key}")
            debug_info = pipeline.debug_retraining_failure(model_key)
            print(json.dumps(debug_info, indent=2, default=str))
            return
        elif command == "status":
            print("📊 Current retraining status:")
            status = pipeline.get_detailed_retraining_status()
            print(json.dumps(status, indent=2, default=str))
            return
        elif command == "help":
            print("Available commands:")
            print("  python automated_retraining_pipeline.py status          - Show detailed status")
            print("  python automated_retraining_pipeline.py debug MODEL_KEY - Debug specific failure")
            print("  python automated_retraining_pipeline.py                 - Run full pipeline test")
            return

    # Default: Test alert checking
    print("🔍 Checking model alerts...")
    alerts = pipeline.check_model_alerts()
    print(f"Found {len(alerts.get('alerts', []))} models with alerts")

    # Test health checking
    print("🏥 Checking model health...")
    health = pipeline.check_model_health()
    print(f"Overall health: {health.get('summary', {}).get('overall_health', 0):.1f}%")

    # Test retraining queue processing
    print("🔄 Processing retraining queue...")
    result = pipeline.process_retraining_queue()
    print(f"Result: {result}")

    # Show status
    print("📊 Current status:")
    status = pipeline.get_retraining_status()
    print(f"Active retraining: {len(status['active_retraining'])}")
    print(f"Retraining history: {len(status['retraining_history'])}")

    # Show failed models if any
    detailed_status = pipeline.get_detailed_retraining_status()
    if detailed_status['total_failed'] > 0:
        print(f"\n❌ Failed models ({detailed_status['total_failed']}):")
        for model_key, details in detailed_status['failed_models_details'].items():
            print(f"  - {model_key}: {details.get('error', 'Unknown error')}")

if __name__ == "__main__":
    main()
