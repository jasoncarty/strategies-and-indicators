#!/usr/bin/env python3
"""
Recommendation Insights for ML Model Retraining
Streamlined analysis module that integrates with the automated retraining pipeline
"""

import os
import json
import logging
import requests
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/recommendation_insights.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class RecommendationInsights:
    """
    Streamlined recommendation analysis for ML model retraining decisions
    Integrates with the automated retraining pipeline
    """

    def __init__(self, analytics_url: str = None):
        """
        Initialize the recommendation insights analyzer

        Args:
            analytics_url: URL of the analytics service
        """
        self.analytics_url = analytics_url or os.getenv('ANALYTICS_URL', 'http://localhost:5001')
        self.insights_cache = {}
        self.cache_duration = 300  # 5 minutes

    def get_model_recommendation_insights(self, model_key: str, days: int = 30) -> Dict[str, Any]:
        """
        Get recommendation insights for a specific model to inform retraining decisions

        Args:
            model_key: Model identifier (e.g., 'buy_EURUSD+_PERIOD_M5')
            days: Number of days to analyze

        Returns:
            Dictionary with recommendation insights and retraining suggestions
        """
        try:
            # Parse model key
            parts = model_key.split('_')
            if len(parts) < 3:
                logger.error(f"Invalid model key format: {model_key}")
                return self._get_default_insights()

            direction = parts[0]
            symbol = parts[1]
            timeframe = parts[3]

            logger.info(f"🔍 Analyzing recommendation insights for {model_key}")

            # Get recommendation performance data
            performance_data = self._get_recommendation_performance(symbol, timeframe, days)

            if not performance_data:
                logger.warning(f"No recommendation data found for {model_key}")
                return self._get_default_insights()

            # Analyze the data
            insights = self._analyze_recommendation_performance(performance_data, model_key)

            # Generate retraining recommendations
            retraining_suggestions = self._generate_retraining_suggestions(insights, model_key)

            # Combine insights
            result = {
                'model_key': model_key,
                'analysis_date': datetime.now().isoformat(),
                'data_points': len(performance_data),
                'insights': insights,
                'retraining_suggestions': retraining_suggestions,
                'should_retrain': retraining_suggestions.get('should_retrain', False),
                'retrain_priority': retraining_suggestions.get('priority', 'low'),
                'retrain_reason': retraining_suggestions.get('reason', 'No specific reason')
            }

            # Cache the results
            self.insights_cache[model_key] = {
                'data': result,
                'timestamp': datetime.now()
            }

            logger.info(f"✅ Generated insights for {model_key}: {result['should_retrain']} retrain, {result['retrain_priority']} priority")
            return result

        except Exception as e:
            logger.error(f"❌ Error analyzing recommendation insights for {model_key}: {e}")
            return self._get_default_insights()

    def _get_recommendation_performance(self, symbol: str, timeframe: str, days: int) -> List[Dict]:
        """Get recommendation performance data from analytics service"""
        try:
            params = {
                'symbol': symbol,
                'timeframe': timeframe,
                'days': days
            }

            response = requests.get(
                f"{self.analytics_url}/recommendation/performance",
                params=params,
                timeout=30
            )

            if response.status_code == 200:
                data = response.json()
                return data.get('data', [])
            else:
                logger.warning(f"Failed to get recommendation performance: {response.status_code}")
                return []

        except Exception as e:
            logger.error(f"Error getting recommendation performance: {e}")
            return []

    def _analyze_recommendation_performance(self, performance_data: List[Dict], model_key: str) -> Dict[str, Any]:
        """Analyze recommendation performance and generate insights"""
        try:
            if not performance_data:
                return self._get_default_insights()['insights']

            # Convert to DataFrame for analysis
            df = pd.DataFrame(performance_data)

            # Basic metrics
            total_recommendations = df['total_recommendations'].sum()
            correct_recommendations = df['correct_recommendations'].sum()
            incorrect_recommendations = df['incorrect_recommendations'].sum()

            overall_accuracy = (correct_recommendations / (correct_recommendations + incorrect_recommendations) * 100) if (correct_recommendations + incorrect_recommendations) > 0 else 0

            # Confidence analysis
            avg_ml_confidence = df['avg_ml_confidence'].mean()
            avg_final_confidence = df['avg_final_confidence'].mean()

            # Profitability analysis
            total_profit_if_followed = df['total_profit_if_followed'].sum()
            total_profit_if_opposite = df['total_profit_if_opposite'].sum()
            total_recommendation_value = df['total_recommendation_value'].sum()
            avg_profit_per_recommendation = df['avg_profit_per_recommendation'].mean()

            # Model-specific analysis
            model_analysis = {}
            for _, row in df.iterrows():
                model_key_analysis = row['ml_model_key']
                analysis_method = row['analysis_method']

                model_analysis[f"{model_key_analysis}_{analysis_method}"] = {
                    'accuracy': row['accuracy_percentage'],
                    'confidence': row['avg_final_confidence'],
                    'recommendations': row['total_recommendations'],
                    'profit_value': row['total_recommendation_value']
                }

            # Confidence calibration analysis
            confidence_issues = []
            if avg_final_confidence > 0.8 and overall_accuracy < 60:
                confidence_issues.append("overconfident")
            elif avg_final_confidence < 0.4 and overall_accuracy > 70:
                confidence_issues.append("underconfident")
            elif avg_final_confidence > 0.6 and overall_accuracy < 50:
                confidence_issues.append("severely_overconfident")

            return {
                'total_recommendations': int(total_recommendations),
                'overall_accuracy': round(overall_accuracy, 2),
                'correct_recommendations': int(correct_recommendations),
                'incorrect_recommendations': int(incorrect_recommendations),
                'avg_ml_confidence': round(avg_ml_confidence, 3),
                'avg_final_confidence': round(avg_final_confidence, 3),
                'total_profit_if_followed': round(total_profit_if_followed, 2),
                'total_profit_if_opposite': round(total_profit_if_opposite, 2),
                'total_recommendation_value': round(total_recommendation_value, 2),
                'avg_profit_per_recommendation': round(avg_profit_per_recommendation, 2),
                'model_analysis': model_analysis,
                'confidence_issues': confidence_issues,
                'data_quality': self._assess_data_quality(df)
            }

        except Exception as e:
            logger.error(f"Error analyzing recommendation performance: {e}")
            return self._get_default_insights()['insights']

    def _generate_retraining_suggestions(self, insights: Dict[str, Any], model_key: str) -> Dict[str, Any]:
        """Generate retraining suggestions based on recommendation insights"""
        try:
            suggestions = {
                'should_retrain': False,
                'priority': 'low',
                'reason': 'No specific issues detected',
                'recommended_actions': [],
                'confidence_adjustments': [],
                'feature_suggestions': []
            }

            # Check accuracy thresholds
            accuracy = insights.get('overall_accuracy', 0)
            if accuracy < 45:
                suggestions['should_retrain'] = True
                suggestions['priority'] = 'critical'
                suggestions['reason'] = f'Very low accuracy: {accuracy:.1f}%'
                suggestions['recommended_actions'].append('Retrain with more recent data')
                suggestions['recommended_actions'].append('Review feature engineering')
            elif accuracy < 55:
                suggestions['should_retrain'] = True
                suggestions['priority'] = 'high'
                suggestions['reason'] = f'Low accuracy: {accuracy:.1f}%'
                suggestions['recommended_actions'].append('Retrain with additional data')
            elif accuracy < 65:
                suggestions['priority'] = 'medium'
                suggestions['reason'] = f'Moderate accuracy: {accuracy:.1f}%'
                suggestions['recommended_actions'].append('Consider retraining if more data available')

            # Check confidence calibration
            confidence_issues = insights.get('confidence_issues', [])
            if 'severely_overconfident' in confidence_issues:
                suggestions['should_retrain'] = True
                suggestions['priority'] = 'critical'
                suggestions['reason'] = 'Severely overconfident model'
                suggestions['confidence_adjustments'].append('Implement confidence calibration')
                suggestions['recommended_actions'].append('Retrain with confidence calibration')
            elif 'overconfident' in confidence_issues:
                suggestions['should_retrain'] = True
                suggestions['priority'] = 'high'
                suggestions['reason'] = 'Overconfident model'
                suggestions['confidence_adjustments'].append('Lower confidence thresholds')
            elif 'underconfident' in confidence_issues:
                suggestions['priority'] = 'medium'
                suggestions['reason'] = 'Underconfident model'
                suggestions['confidence_adjustments'].append('Raise confidence thresholds')

            # Check profitability
            recommendation_value = insights.get('total_recommendation_value', 0)
            if recommendation_value < -100:  # Losing significant money
                suggestions['should_retrain'] = True
                suggestions['priority'] = 'high'
                suggestions['reason'] = f'Negative recommendation value: ${recommendation_value:.2f}'
                suggestions['recommended_actions'].append('Review risk management parameters')
            elif recommendation_value < 0:
                suggestions['priority'] = 'medium'
                suggestions['reason'] = f'Negative recommendation value: ${recommendation_value:.2f}'
                suggestions['recommended_actions'].append('Monitor closely, consider retraining')

            # Check data quality
            data_quality = insights.get('data_quality', {})
            if data_quality.get('insufficient_data', False):
                suggestions['priority'] = 'low'
                suggestions['reason'] = 'Insufficient recommendation data for analysis'
                suggestions['recommended_actions'].append('Wait for more recommendation data')
            elif data_quality.get('low_confidence_data', False):
                suggestions['priority'] = 'medium'
                suggestions['reason'] = 'Low confidence in recommendation data'
                suggestions['recommended_actions'].append('Improve recommendation tracking quality')

            # Model-specific suggestions
            model_analysis = insights.get('model_analysis', {})
            for model_name, analysis in model_analysis.items():
                if analysis['accuracy'] < 50 and analysis['recommendations'] > 10:
                    suggestions['feature_suggestions'].append(f"Review features for {model_name} (accuracy: {analysis['accuracy']:.1f}%)")

            return suggestions

        except Exception as e:
            logger.error(f"Error generating retraining suggestions: {e}")
            return {
                'should_retrain': False,
                'priority': 'low',
                'reason': 'Error in analysis',
                'recommended_actions': ['Check recommendation data quality']
            }

    def _assess_data_quality(self, df: pd.DataFrame) -> Dict[str, Any]:
        """Assess the quality of recommendation data"""
        try:
            total_recommendations = df['total_recommendations'].sum()

            quality = {
                'insufficient_data': total_recommendations < 20,
                'low_confidence_data': df['avg_final_confidence'].mean() < 0.3,
                'high_variance': df['accuracy_percentage'].std() > 30,
                'total_recommendations': int(total_recommendations)
            }

            return quality

        except Exception as e:
            logger.error(f"Error assessing data quality: {e}")
            return {
                'insufficient_data': True,
                'low_confidence_data': True,
                'high_variance': True,
                'total_recommendations': 0
            }

    def _get_default_insights(self) -> Dict[str, Any]:
        """Get default insights when analysis fails"""
        return {
            'model_key': 'unknown',
            'analysis_date': datetime.now().isoformat(),
            'data_points': 0,
            'insights': {
                'total_recommendations': 0,
                'overall_accuracy': 0,
                'correct_recommendations': 0,
                'incorrect_recommendations': 0,
                'avg_ml_confidence': 0,
                'avg_final_confidence': 0,
                'total_profit_if_followed': 0,
                'total_profit_if_opposite': 0,
                'total_recommendation_value': 0,
                'avg_profit_per_recommendation': 0,
                'model_analysis': {},
                'confidence_issues': [],
                'data_quality': {'insufficient_data': True}
            },
            'retraining_suggestions': {
                'should_retrain': False,
                'priority': 'low',
                'reason': 'No recommendation data available',
                'recommended_actions': ['Collect more recommendation data'],
                'confidence_adjustments': [],
                'feature_suggestions': []
            },
            'should_retrain': False,
            'retrain_priority': 'low',
            'retrain_reason': 'No recommendation data available'
        }

    def get_cached_insights(self, model_key: str) -> Optional[Dict[str, Any]]:
        """Get cached insights if available and not expired"""
        if model_key in self.insights_cache:
            cache_entry = self.insights_cache[model_key]
            if (datetime.now() - cache_entry['timestamp']).total_seconds() < self.cache_duration:
                return cache_entry['data']
            else:
                # Remove expired cache entry
                del self.insights_cache[model_key]
        return None

    def clear_cache(self):
        """Clear the insights cache"""
        self.insights_cache.clear()
        logger.info("Cleared recommendation insights cache")

    def get_all_model_insights(self, model_keys: List[str], days: int = 30) -> Dict[str, Any]:
        """Get insights for multiple models"""
        try:
            logger.info(f"🔍 Analyzing recommendation insights for {len(model_keys)} models")

            all_insights = {}
            retrain_candidates = []

            for model_key in model_keys:
                # Check cache first
                cached_insights = self.get_cached_insights(model_key)
                if cached_insights:
                    all_insights[model_key] = cached_insights
                else:
                    insights = self.get_model_recommendation_insights(model_key, days)
                    all_insights[model_key] = insights

                # Track retrain candidates
                if insights.get('should_retrain', False):
                    retrain_candidates.append({
                        'model_key': model_key,
                        'priority': insights.get('retrain_priority', 'low'),
                        'reason': insights.get('retrain_reason', 'Unknown')
                    })

            # Sort retrain candidates by priority
            priority_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
            retrain_candidates.sort(key=lambda x: priority_order.get(x['priority'], 4))

            result = {
                'analysis_date': datetime.now().isoformat(),
                'models_analyzed': len(model_keys),
                'retrain_candidates': retrain_candidates,
                'total_retrain_candidates': len(retrain_candidates),
                'insights': all_insights
            }

            logger.info(f"✅ Analysis complete: {len(retrain_candidates)} models need retraining")
            return result

        except Exception as e:
            logger.error(f"❌ Error analyzing all model insights: {e}")
            return {
                'analysis_date': datetime.now().isoformat(),
                'models_analyzed': 0,
                'retrain_candidates': [],
                'total_retrain_candidates': 0,
                'insights': {},
                'error': str(e)
            }

def main():
    """Example usage"""
    import argparse

    parser = argparse.ArgumentParser(description='Analyze recommendation insights for ML models')
    parser.add_argument('--model-key', help='Specific model key to analyze')
    parser.add_argument('--days', type=int, default=30, help='Number of days to analyze')
    parser.add_argument('--analytics-url', help='Analytics service URL')

    args = parser.parse_args()

    # Initialize analyzer
    analyzer = RecommendationInsights(args.analytics_url)

    if args.model_key:
        # Analyze specific model
        logger.info(f"🔍 Analyzing model: {args.model_key}")
        insights = analyzer.get_model_recommendation_insights(args.model_key, args.days)

        print(f"\n📊 Recommendation Insights for {args.model_key}")
        print(f"Should Retrain: {insights['should_retrain']}")
        print(f"Priority: {insights['retrain_priority']}")
        print(f"Reason: {insights['retrain_reason']}")
        print(f"Data Points: {insights['data_points']}")

        if insights['insights']['total_recommendations'] > 0:
            print(f"Overall Accuracy: {insights['insights']['overall_accuracy']:.1f}%")
            print(f"Avg Confidence: {insights['insights']['avg_final_confidence']:.3f}")
            print(f"Recommendation Value: ${insights['insights']['total_recommendation_value']:.2f}")
    else:
        # Analyze all models (would need model keys from somewhere)
        logger.info("No specific model provided. Use --model-key to analyze a specific model.")

if __name__ == "__main__":
    main()
