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
                 models_dir: str = "ml_models",
                 check_interval_minutes: int = 60):

        self.analytics_url = analytics_url
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

        return {
            'should_retrain': retrain_reason is not None,
            'reason': retrain_reason,
            'priority': priority,
            'urgency': urgency
        }

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

                        # Use advanced retraining framework
            success = self.retraining_framework.retrain_model(symbol, timeframe, training_data, direction)

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

            if not alerts_data.get('alerts'):
                logger.info("No alerts to process")
                return {"processed": 0, "retrained": 0, "skipped": 0}

            # Group alerts by model
            model_alerts = {}
            for alert in alerts_data['alerts']:
                model_key = alert['model_key']
                if model_key not in model_alerts:
                    model_alerts[model_key] = []
                model_alerts[model_key].extend(alert['alerts'])

            # Process each model
            processed = 0
            retrained = 0
            skipped = 0

            for model_key, alerts in model_alerts.items():
                processed += 1

                # Check if retraining is needed
                retrain_decision = self.should_retrain_model(model_key, alerts, health_data)

                if retrain_decision['should_retrain']:
                    # Check if we can start more retraining
                    active_count = len([k for k, v in self.active_retraining.items()
                                     if v['status'] == 'in_progress'])

                    if active_count >= self.max_concurrent_retraining:
                        logger.info(f"Max concurrent retraining reached, skipping {model_key}")
                        skipped += 1
                        continue

                    # Start retraining
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

            result = {
                "processed": processed,
                "retrained": retrained,
                "skipped": skipped,
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
