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
                 analytics_url: str = "http://localhost:5001",
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
                logger.error(f"❌ Retraining failed for {model_key}")
                return False

        except Exception as e:
            logger.error(f"❌ Error during retraining of {model_key}: {e}")
            if model_key in self.active_retraining:
                self.active_retraining[model_key]['status'] = 'failed'
                self.active_retraining[model_key]['error'] = str(e)
            return False

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

def main():
    """Example usage and testing"""
    pipeline = AutomatedRetrainingPipeline()

    # Test alert checking
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

if __name__ == "__main__":
    main()
