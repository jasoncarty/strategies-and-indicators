#!/usr/bin/env python3
"""
Feature Engineering Utilities
Shared module for calculating engineered features consistently across training and prediction
"""

import pandas as pd
import numpy as np
from typing import Dict, Union, List


class FeatureEngineeringUtils:
    """Utility class for consistent feature engineering across training and prediction"""

    @staticmethod
    def calculate_engineered_features(features: Dict[str, Union[float, int]]) -> Dict[str, Union[float, int]]:
        """
        Calculate engineered features from basic features

        Args:
            features: Dictionary of basic features from EA

        Returns:
            Dictionary with engineered features added
        """
        engineered_features = {}

        # Market regime features (3 features) - using numeric values to match LabelEncoder
        rsi = features.get('rsi', 50.0)
        if rsi < 30:
            engineered_features['rsi_regime'] = 0  # oversold (LabelEncoder: 'oversold' -> 0)
        elif rsi >= 70:
            engineered_features['rsi_regime'] = 2  # overbought (LabelEncoder: 'overbought' -> 2)
        else:
            engineered_features['rsi_regime'] = 1  # neutral (LabelEncoder: 'neutral' -> 1)

        stoch_main = features.get('stoch_main', 50.0)
        if stoch_main < 20:
            engineered_features['stoch_regime'] = 0  # oversold (LabelEncoder: 'oversold' -> 0)
        elif stoch_main > 80:
            engineered_features['stoch_regime'] = 2  # overbought (LabelEncoder: 'overbought' -> 2)
        else:
            engineered_features['stoch_regime'] = 1  # neutral (LabelEncoder: 'neutral' -> 1)

        # Volatility regime - using numeric values to match LabelEncoder
        volatility = features.get('volatility', 0.001)
        # LabelEncoder mapping: 'low' -> 0, 'medium' -> 1, 'high' -> 2
        if volatility < 0.0005:
            engineered_features['volatility_regime'] = 0  # low
        elif volatility > 0.002:
            engineered_features['volatility_regime'] = 2  # high
        else:
            engineered_features['volatility_regime'] = 1  # medium

        # Time-based features (6 features)
        session_hour = features.get('session_hour', 12)
        engineered_features['hour'] = session_hour

        # Session classification - using numeric values to match LabelEncoder
        # LabelEncoder mapping: 'asian' -> 0, 'london' -> 1, 'ny' -> 2, 'off_hours' -> 3
        # Note: NY session (13-22) takes precedence over London session (8-16) for overlap hours
        if 13 <= session_hour < 22:
            engineered_features['session'] = 2  # ny
        elif 8 <= session_hour < 16:
            engineered_features['session'] = 1  # london
        elif 1 <= session_hour < 10:
            engineered_features['session'] = 0  # asian
        else:
            engineered_features['session'] = 3  # off_hours

        # Session flags
        engineered_features['is_london_session'] = 1 if 8 <= session_hour < 16 else 0
        engineered_features['is_ny_session'] = 1 if 13 <= session_hour < 22 else 0
        engineered_features['is_asian_session'] = 1 if 1 <= session_hour < 10 else 0
        engineered_features['is_session_overlap'] = 1 if ((8 <= session_hour < 16) or (13 <= session_hour < 22)) else 0

        return engineered_features

    @staticmethod
    def add_engineered_features_to_dataframe(df: pd.DataFrame) -> pd.DataFrame:
        """
        Add engineered features to a pandas DataFrame (for training)

        Args:
            df: DataFrame with basic features

        Returns:
            DataFrame with engineered features added
        """
        # Market regime features
        df['rsi_regime'] = pd.cut(df['rsi'], bins=[0, 30, 70, 100], labels=['oversold', 'neutral', 'overbought'])
        df['stoch_regime'] = pd.cut(df['stoch_main'], bins=[0, 20, 80, 100], labels=['oversold', 'neutral', 'overbought'])

        # Volatility regime - using ATR if available, otherwise volatility
        if 'atr' in df.columns:
            if len(df) == 1:
                # Handle single-row DataFrame
                df['volatility_regime'] = 'medium'  # Default for single row
            else:
                df['volatility_regime'] = pd.qcut(df['atr'], q=3, labels=['low', 'medium', 'high'])
        else:
            if len(df) == 1:
                # Handle single-row DataFrame
                df['volatility_regime'] = 'medium'  # Default for single row
            else:
                df['volatility_regime'] = pd.qcut(df['volatility'], q=3, labels=['low', 'medium', 'high'])

        # Time-based features
        df['hour'] = df['session_hour']
        df['session'] = FeatureEngineeringUtils._classify_session(df['hour'])

        # Session flags
        df['is_london_session'] = ((df['session_hour'] >= 8) & (df['session_hour'] < 16)).astype(int)
        df['is_ny_session'] = ((df['session_hour'] >= 13) & (df['session_hour'] < 22)).astype(int)
        df['is_asian_session'] = ((df['session_hour'] >= 1) & (df['session_hour'] < 10)).astype(int)
        df['is_session_overlap'] = (((df['session_hour'] >= 8) & (df['session_hour'] < 16)) |
                                   ((df['session_hour'] >= 13) & (df['session_hour'] < 22))).astype(int)

        return df

    @staticmethod
    def _classify_session(hours: Union[pd.Series, List[int], int]) -> Union[pd.Series, List[str], str]:
        """
        Classify hours into trading sessions

        Args:
            hours: Hour values (can be Series, List, or single value)

        Returns:
            Session classifications
        """
        if isinstance(hours, pd.Series):
            sessions = []
            for hour in hours:
                # Note: NY session (13-22) takes precedence over London session (8-16) for overlap hours
                if 13 <= hour < 22:
                    sessions.append('ny')
                elif 8 <= hour < 16:
                    sessions.append('london')
                elif 1 <= hour < 10:
                    sessions.append('asian')
                else:
                    sessions.append('off_hours')
            return sessions
        elif isinstance(hours, list):
            sessions = []
            for hour in hours:
                # Note: NY session (13-22) takes precedence over London session (8-16) for overlap hours
                if 13 <= hour < 22:
                    sessions.append('ny')
                elif 8 <= hour < 16:
                    sessions.append('london')
                elif 1 <= hour < 10:
                    sessions.append('asian')
                else:
                    sessions.append('off_hours')
            return sessions
        else:
            # Single value
            hour = hours
            # Note: NY session (13-22) takes precedence over London session (8-16) for overlap hours
            if 13 <= hour < 22:
                return 'ny'
            elif 8 <= hour < 16:
                return 'london'
            elif 1 <= hour < 10:
                return 'asian'
            else:
                return 'off_hours'

    @staticmethod
    def get_expected_28_features() -> List[str]:
        """
        Get the complete list of 28 expected features (basic + engineered)

        Returns:
            List of feature names in the expected order
        """
        return [
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

    @staticmethod
    def get_expected_19_features() -> List[str]:
        """
        Get the list of 19 basic features (without engineered features)

        Returns:
            List of basic feature names
        """
        return [
            'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
            'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum', 'force_index',
            'volume_ratio', 'price_change', 'volatility', 'spread',
            'session_hour', 'is_news_time', 'day_of_week', 'month'
        ]
