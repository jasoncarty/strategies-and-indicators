#!/usr/bin/env python3
"""
ML Diagnostic Tool for ICT FVG Trader EA
Analyzes trading performance and identifies issues using machine learning
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.ensemble import RandomForestClassifier, IsolationForest
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
import joblib
import warnings
warnings.filterwarnings('ignore')
from app import db
import json

class TradingEADiagnostic:
    def __init__(self, db_engine):
        self.db_engine = db_engine
        self.scaler = StandardScaler()
        self.label_encoder = LabelEncoder()
        self.models = {}
        
    def load_trading_data(self):
        """Load trading data from database"""
        try:
            print("[DEBUG] db_engine:", self.db_engine)
            # Load strategy tests with parameters
            tests_query = """
                SELECT * FROM strategy_test 
                ORDER BY test_date DESC
            """
            tests_df = pd.read_sql(tests_query, self.db_engine)
            print(f"[DEBUG] Loaded {len(tests_df)} strategy_test rows")
            print(f"[DEBUG] tests_df columns: {list(tests_df.columns)}")
            
            # Load trades with strategy info
            trades_query = """
                SELECT t.*, st.strategy_name, st.strategy_version, st.symbol as strategy_symbol, st.timeframe, st.parameters
                FROM trade t
                JOIN strategy_test st ON t.strategy_test_id = st.id
                ORDER BY t.open_time DESC
            """
            trades_df = pd.read_sql(trades_query, self.db_engine)
            print(f"[DEBUG] Loaded {len(trades_df)} trade rows")
            print(f"[DEBUG] trades_df columns: {list(trades_df.columns)}")
            
            # Load trading conditions
            conditions_query = """
                SELECT tc.*, t.symbol as trade_symbol, t.type, t.profit
                FROM trading_conditions tc
                JOIN trade t ON tc.trade_id = t.id
                ORDER BY tc.entry_time DESC
            """
            conditions_df = pd.read_sql(conditions_query, self.db_engine)
            print(f"[DEBUG] Loaded {len(conditions_df)} trading_conditions rows")
            print(f"[DEBUG] conditions_df columns: {list(conditions_df.columns)}")
            
            return tests_df, trades_df, conditions_df
        except Exception as e:
            print(f"[ERROR] Exception in load_trading_data: {e}")
            return None, None, None
    
    def parse_parameters(self, parameters_json):
        """Parse JSON parameters string into a dictionary"""
        try:
            if parameters_json and parameters_json != 'null':
                return json.loads(parameters_json)
            return {}
        except Exception as e:
            print(f"[WARNING] Failed to parse parameters: {e}")
            return {}
    
    def extract_parameter_features(self, parameters_dict):
        """Extract key parameter features for ML analysis"""
        features = {}
        
        # Debug: Check what parameters we're processing
        print(f"[DEBUG] Processing parameters: {list(parameters_dict.keys())}")
        
        # ICT Strategy specific parameters
        ict_params = [
            'UseKillZone', 'KillZoneStartHour', 'KillZoneEndHour',
            'UseFVG', 'FVGMinSize', 'FVGMaxAge',
            'UseATRStopLoss', 'ATRPeriod', 'ATRMultiplier',
            'UseMarketStructureFilter', 'StructureTimeframe',
            'UseStandardDeviation', 'StdDevPeriod', 'StdDevMultiplier',
            'UseLowerTimeframeTriggers', 'LowerTimeframe',
            'RiskPercent', 'RewardRiskRatio',
            'UseVolumeConfirmation', 'VolumeRatioThreshold'
        ]
        
        param_count = 0
        for param in ict_params:
            if param in parameters_dict:
                value = parameters_dict[param]
                # Convert boolean to int for ML
                if isinstance(value, bool):
                    features[f'param_{param}'] = int(value)
                elif isinstance(value, (int, float)):
                    features[f'param_{param}'] = value
                else:
                    # For string parameters, create categorical features
                    features[f'param_{param}'] = str(value)
                param_count += 1
                print(f"[DEBUG] Added parameter {param}: {value} -> {features[f'param_{param}']}")
        
        print(f"[DEBUG] Total parameters extracted: {param_count}")
        return features
    
    def engineer_features(self, trades_df, conditions_df):
        """Create ML features from trading data"""
        if trades_df is None or conditions_df is None:
            return None
            
        # Debug: Check symbol data before merge
        print(f"[DEBUG] trades_df symbol column: {list(trades_df.columns)}")
        if 'strategy_symbol' in trades_df.columns:
            print(f"[DEBUG] Unique symbols in trades_df: {trades_df['strategy_symbol'].unique()}")
        
        # Debug: Check parameters column before merge
        if 'parameters' in trades_df.columns:
            print(f"[DEBUG] Parameters column sample values:")
            param_sample = trades_df['parameters'].dropna().head(5)
            for i, param in enumerate(param_sample):
                print(f"  Sample {i+1}: {param[:100]}...")
        
        # Merge trades with conditions
        feature_df = trades_df.merge(conditions_df, left_on='id', right_on='trade_id', how='left')
        
        # Debug: Check merged data
        print(f"[DEBUG] Merged data shape: {feature_df.shape}")
        print(f"[DEBUG] Merged columns: {list(feature_df.columns)}")
        
        # Extract parameters
        feature_df = self.extract_parameters(feature_df)
        
        # Debug: Check parameter extraction
        if 'parameters' in feature_df.columns:
            param_variations = set()
            for params in feature_df['parameters'].dropna():
                try:
                    param_dict = json.loads(params)
                    param_variations.add(tuple(sorted(param_dict.items())))
                except:
                    continue
            
            print(f"[DEBUG] Total parameter variations found: {len(param_variations)}")
            if len(param_variations) == 1:
                print("[DEBUG] ⚠️  WARNING: All trades have identical parameters!")
                print(f"[DEBUG] Parameter set: {list(param_variations)[0][:3]}...")  # Show first 3
            else:
                print("[DEBUG] Found multiple parameter variations:")
                for i, param_set in enumerate(list(param_variations)[:3]):  # Show first 3 variations
                    print(f"  Variation {i+1}: {dict(param_set)}")
            
            # Debug: Check which parameters actually vary
            if len(param_variations) > 1:
                print("[DEBUG] Analyzing parameter variations:")
                param_sets = list(param_variations)
                all_params = set()
                for param_set in param_sets:
                    all_params.update(dict(param_set).keys())
                
                for param_name in sorted(all_params):
                    values = set()
                    for param_set in param_sets:
                        param_dict = dict(param_set)
                        if param_name in param_dict:
                            values.add(param_dict[param_name])
                    
                    if len(values) == 1:
                        print(f"    {param_name}: {values} (CONSTANT)")
                    else:
                        print(f"    {param_name}: {values} (VARYING)")
        
        # After merging, ensure we have a 'profit' column
        profit_col = None
        if 'profit' in feature_df.columns:
            profit_col = 'profit'
        elif 'profit_x' in feature_df.columns:
            profit_col = 'profit_x'
        elif 'profit_y' in feature_df.columns:
            profit_col = 'profit_y'
        else:
            raise KeyError("No profit column found in feature_df!")
        if profit_col != 'profit':
            feature_df['profit'] = feature_df[profit_col]
        
        # Create target variable (profitable trade)
        feature_df['target'] = (feature_df['profit'] > 0).astype(int)
        
        # Select relevant features
        numeric_features = [
            'profit', 'volume', 'spread', 'swap', 'commission', 'lot_size',
            'atr_value', 'has_fvg', 'in_kill_zone', 'volume_ratio'
        ]
        
        # Get parameter columns (they start with 'param_')
        param_columns = [col for col in feature_df.columns if col.startswith('param_')]
        print(f"[DEBUG] Parameter columns in feature_df: {param_columns}")
        
        # Debug: Show sample values for parameter columns
        print("[DEBUG] Parameter column sample values:")
        for col in param_columns[:3]:  # Show first 3
            unique_vals = feature_df[col].unique()
            print(f"  {col}: {unique_vals}")
        
        # Add categorical encoding for string parameters
        feature_df = self.encode_categorical_parameters(feature_df, param_columns)
        
        # Ensure all expected numeric features exist, using available columns or filling with 0
        def get_first_available_column(df, names, fill_value=0):
            for name in names:
                if name in df.columns:
                    return df[name]
            return fill_value

        # List of expected numeric features and their possible alternatives
        numeric_feature_map = {
            'volume': ['volume', 'volume_x', 'volume_y'],
            'spread': ['spread', 'spread_x', 'spread_y'],
            'swap': ['swap', 'swap_x', 'swap_y'],
            'commission': ['commission', 'commission_x', 'commission_y'],
            'lot_size': ['lot_size', 'lot_size_x', 'lot_size_y'],
            'atr_value': ['atr_value', 'atr_value_x', 'atr_value_y'],
            'has_fvg': ['has_fvg', 'has_fvg_x', 'has_fvg_y'],
            'in_kill_zone': ['in_kill_zone', 'in_kill_zone_x', 'in_kill_zone_y'],
            'volume_ratio': ['volume_ratio', 'volume_ratio_x', 'volume_ratio_y'],
        }
        for feature, alternatives in numeric_feature_map.items():
            if feature not in feature_df.columns:
                feature_df[feature] = get_first_available_column(feature_df, alternatives, 0)

        # Now select only columns that exist for all_features
        all_features = [f for f in numeric_features + param_columns if f in feature_df.columns]

        # Add symbol and timeframe for analysis
        if 'strategy_symbol' in feature_df.columns:
            feature_df['symbol'] = feature_df['strategy_symbol']
        if 'strategy_timeframe' in feature_df.columns:
            feature_df['timeframe'] = feature_df['strategy_timeframe']
        
        # Debug: Final feature set
        print(f"[DEBUG] Final feature_df symbols: {feature_df['symbol'].unique()}")
        print(f"[DEBUG] Final feature_df columns: {list(feature_df.columns)}")
        print(f"[DEBUG] Final feature_df shape: {feature_df.shape}")
        
        return feature_df[all_features + ['target', 'symbol', 'timeframe']]
    
    def encode_categorical_parameters(self, df, param_columns):
        """Encode categorical string parameters to numeric values for ML analysis"""
        from sklearn.preprocessing import LabelEncoder
        
        for col in param_columns:
            if col in df.columns and df[col].dtype == 'object':
                # Check if this column has string values that need encoding
                unique_vals = df[col].unique()
                if len(unique_vals) > 1 and any(isinstance(v, str) for v in unique_vals):
                    print(f"[DEBUG] Encoding categorical parameter: {col}")
                    print(f"[DEBUG]   Unique values: {unique_vals}")
                    
                    # Create label encoder
                    le = LabelEncoder()
                    
                    # Fit and transform the column
                    df[f"{col}_encoded"] = le.fit_transform(df[col].astype(str))
                    
                    # Replace original column with encoded version
                    df[col] = df[f"{col}_encoded"]
                    df.drop(f"{col}_encoded", axis=1, inplace=True)
                    
                    print(f"[DEBUG]   Encoded values: {dict(zip(le.classes_, le.transform(le.classes_)))}")
        
        return df
    
    def detect_anomalies(self, feature_df):
        """Detect anomalous trading patterns"""
        if feature_df is None or len(feature_df) < 10:
            return None
            
        # Prepare features for anomaly detection
        anomaly_features = feature_df.select_dtypes(include=[np.number]).drop(['target', 'profit'], axis=1, errors='ignore')
        
        # Fill NaN values
        anomaly_features = anomaly_features.fillna(0)
        
        # Detect anomalies using Isolation Forest
        iso_forest = IsolationForest(contamination=0.1, random_state=42)
        anomalies = iso_forest.fit_predict(anomaly_features)
        
        # Add anomaly labels to dataframe
        feature_df['is_anomaly'] = (anomalies == -1).astype(int)
        
        return feature_df
    
    def analyze_feature_importance(self, feature_df):
        """Analyze which features are most important for profitability"""
        if feature_df is None or len(feature_df) < 10:
            return None
            
        # Prepare features
        X = feature_df.select_dtypes(include=[np.number]).drop(['target', 'profit', 'is_anomaly'], axis=1, errors='ignore')
        y = feature_df['target']
        
        # Debug: Check what features are being analyzed
        print(f"[DEBUG] Features for importance analysis: {list(X.columns)}")
        param_features = [col for col in X.columns if col.startswith('param_')]
        print(f"[DEBUG] Parameter features in analysis: {param_features}")
        
        # Fill NaN values
        X = X.fillna(0)
        
        # Debug: Check feature variance (low variance = low importance)
        feature_variance = X.var()
        print(f"[DEBUG] Feature variance:")
        for feature, variance in feature_variance.items():
            print(f"  {feature}: {variance:.6f}")
        
        # Train Random Forest for feature importance
        rf = RandomForestClassifier(n_estimators=100, random_state=42)
        rf.fit(X, y)
        
        # Get feature importance
        importance_df = pd.DataFrame({
            'feature': X.columns,
            'importance': rf.feature_importances_
        }).sort_values('importance', ascending=False)
        
        # Debug: Show parameter importance specifically
        param_importance = importance_df[importance_df['feature'].str.startswith('param_')]
        if not param_importance.empty:
            print(f"[DEBUG] Parameter importance:")
            for _, row in param_importance.iterrows():
                print(f"  {row['feature']}: {row['importance']:.6f}")
        
        return importance_df
    
    def cluster_trading_patterns(self, feature_df, n_clusters=3):
        """Cluster trades into different patterns"""
        if feature_df is None or len(feature_df) < 10:
            return None
            
        # Prepare features for clustering
        cluster_features = feature_df.select_dtypes(include=[np.number]).drop(['target', 'profit', 'is_anomaly'], axis=1, errors='ignore')
        cluster_features = cluster_features.fillna(0)
        
        # Scale features
        scaled_features = self.scaler.fit_transform(cluster_features)
        
        # Perform clustering
        kmeans = KMeans(n_clusters=n_clusters, random_state=42)
        clusters = kmeans.fit_predict(scaled_features)
        
        # Add cluster labels
        feature_df['cluster'] = clusters
        
        # Analyze clusters
        cluster_analysis = feature_df.groupby('cluster').agg({
            'target': ['mean', 'count'],
            'profit': ['mean', 'std'],
            'atr_value': 'mean',
            'volume_ratio': 'mean',
            'in_kill_zone': 'mean',
            'has_fvg': 'mean'
        }).round(3)
        
        return feature_df, cluster_analysis
    
    def predict_trade_success(self, feature_df):
        """Build a model to predict trade success"""
        if feature_df is None or len(feature_df) < 20:
            return None
            
        # Prepare features
        X = feature_df.select_dtypes(include=[np.number]).drop(['target', 'profit', 'is_anomaly', 'cluster'], axis=1, errors='ignore')
        y = feature_df['target']
        
        # Fill NaN values
        X = X.fillna(0)
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.3, random_state=42)
        
        # Train model
        rf = RandomForestClassifier(n_estimators=100, random_state=42)
        rf.fit(X_train, y_train)
        
        # Make predictions
        y_pred = rf.predict(X_test)
        y_pred_proba = rf.predict_proba(X_test)[:, 1]
        
        # Calculate metrics
        accuracy = rf.score(X_test, y_test)
        auc_score = roc_auc_score(y_test, y_pred_proba)
        
        # Store model
        self.models['trade_success_predictor'] = rf
        
        return {
            'accuracy': accuracy,
            'auc_score': auc_score,
            'classification_report': classification_report(y_test, y_pred),
            'feature_importance': self.analyze_feature_importance(feature_df)
        }
    
    def generate_diagnostic_report(self):
        """Generate comprehensive diagnostic report"""
        print("🔍 Loading trading data...")
        tests_df, trades_df, conditions_df = self.load_trading_data()
        
        if trades_df is None:
            print("❌ No trading data found!")
            return
        
        print(f"📊 Loaded {len(trades_df)} trades and {len(conditions_df)} trading conditions")
        
        # Engineer features
        print("🔧 Engineering features...")
        feature_df = self.engineer_features(trades_df, conditions_df)
        
        if feature_df is None:
            print("❌ Failed to engineer features!")
            return
        
        # Detect anomalies
        print("🚨 Detecting anomalies...")
        feature_df = self.detect_anomalies(feature_df)
        
        # Analyze feature importance
        print("📈 Analyzing feature importance...")
        importance_df = self.analyze_feature_importance(feature_df)
        
        # Cluster patterns
        print("🎯 Clustering trading patterns...")
        feature_df, cluster_analysis = self.cluster_trading_patterns(feature_df)
        
        # Predict trade success
        print("🔮 Building prediction model...")
        prediction_results = self.predict_trade_success(feature_df)
        
        # New analyses
        print("📊 Analyzing by symbol...")
        symbol_analysis = self.analyze_by_symbol(feature_df)
        
        print("⏰ Analyzing by timeframe...")
        timeframe_analysis = self.analyze_by_timeframe(feature_df)
        
        print("⚙️ Analyzing parameter effectiveness...")
        parameter_analysis = self.analyze_parameter_effectiveness(feature_df)
        
        # Weighted performance analysis
        print("🎯 Calculating weighted scores...")
        weighted_analysis = self.analyze_weighted_performance(feature_df, symbol_analysis, timeframe_analysis, cluster_analysis)
        
        # Generate report
        self._print_diagnostic_report(feature_df, importance_df, cluster_analysis, prediction_results, 
                                    symbol_analysis, timeframe_analysis, parameter_analysis, weighted_analysis)
        
        return {
            'feature_df': feature_df,
            'importance_df': importance_df,
            'cluster_analysis': cluster_analysis,
            'prediction_results': prediction_results,
            'symbol_analysis': symbol_analysis,
            'timeframe_analysis': timeframe_analysis,
            'parameter_analysis': parameter_analysis,
            'weighted_analysis': weighted_analysis
        }
    
    def _print_diagnostic_report(self, feature_df, importance_df, cluster_analysis, prediction_results, 
                                symbol_analysis, timeframe_analysis, parameter_analysis, weighted_analysis):
        """Print comprehensive diagnostic report"""
        print("\n" + "="*80)
        print("🧠 ML DIAGNOSTIC REPORT FOR ICT FVG TRADER EA")
        print("="*80)
        
        # Overall performance
        total_trades = len(feature_df)
        profitable_trades = feature_df['target'].sum()
        win_rate = (profitable_trades / total_trades) * 100
        avg_profit = feature_df['profit'].mean()
        
        print(f"\n📊 OVERALL PERFORMANCE:")
        print(f"   Total Trades: {total_trades}")
        print(f"   Profitable Trades: {profitable_trades}")
        print(f"   Win Rate: {win_rate:.1f}%")
        print(f"   Average Profit: ${avg_profit:.2f}")
        
        # Anomaly detection
        anomalies = feature_df['is_anomaly'].sum()
        anomaly_rate = (anomalies / total_trades) * 100
        print(f"\n🚨 ANOMALY DETECTION:")
        print(f"   Anomalous Trades: {anomalies}")
        print(f"   Anomaly Rate: {anomaly_rate:.1f}%")
        
        if anomalies > 0:
            anomaly_trades = feature_df[feature_df['is_anomaly'] == 1]
            anomaly_win_rate = (anomaly_trades['target'].sum() / len(anomaly_trades)) * 100
            print(f"   Anomaly Win Rate: {anomaly_win_rate:.1f}%")
        
        # Feature importance
        if importance_df is not None:
            print(f"\n🎯 TOP 10 MOST IMPORTANT FEATURES:")
            for i, row in importance_df.head(10).iterrows():
                print(f"   {row['feature']}: {row['importance']:.3f}")
        
        # Cluster analysis
        if cluster_analysis is not None:
            print(f"\n🎨 TRADING PATTERN CLUSTERS:")
            for cluster_id in cluster_analysis.index:
                cluster_data = cluster_analysis.loc[cluster_id]
                win_rate = cluster_data[('target', 'mean')] * 100
                trade_count = cluster_data[('target', 'count')]
                avg_profit = cluster_data[('profit', 'mean')]
                
                print(f"   Cluster {cluster_id}: {trade_count} trades, {win_rate:.1f}% win rate, ${avg_profit:.2f} avg profit")
        
        # Prediction model performance
        if prediction_results is not None:
            print(f"\n🔮 PREDICTION MODEL PERFORMANCE:")
            print(f"   Accuracy: {prediction_results['accuracy']:.3f}")
            print(f"   AUC Score: {prediction_results['auc_score']:.3f}")
        
        # Volume analysis (if volume data exists)
        volume_analysis = {}
        if 'volume' in feature_df.columns:
            high_volume_trades = feature_df[feature_df['volume'] > feature_df['volume'].median()]
            volume_analysis = {
                'high_volume_win_rate': (high_volume_trades['target'] == 1).mean() if len(high_volume_trades) > 0 else 0,
                'high_volume_count': len(high_volume_trades),
                'avg_volume': feature_df['volume'].mean()
            }
        else:
            volume_analysis = {
                'high_volume_win_rate': 0,
                'high_volume_count': 0,
                'avg_volume': 0
            }
        
        # Symbol analysis
        if symbol_analysis:
            print(f"\n📊 ANALYSIS BY SYMBOL:")
            for symbol, data in symbol_analysis.items():
                print(f"   Symbol: {symbol}")
                print(f"      Trade Count: {data['trade_count']}")
                print(f"      Win Rate: {data['win_rate']:.1f}%")
                print(f"      Average Profit: ${data['avg_profit']:.2f}")
                print(f"      Total Profit: ${data['total_profit']:.2f}")
                print(f"      Profit Factor: {data['profit_factor']:.2f}")
        
        # Timeframe analysis
        if timeframe_analysis:
            print(f"\n📊 ANALYSIS BY TIMEFRAME:")
            for timeframe, data in timeframe_analysis.items():
                print(f"   Timeframe: {timeframe}")
                print(f"      Trade Count: {data['trade_count']}")
                print(f"      Win Rate: {data['win_rate']:.1f}%")
                print(f"      Average Profit: ${data['avg_profit']:.2f}")
                print(f"      Total Profit: ${data['total_profit']:.2f}")
                print(f"      Profit Factor: {data['profit_factor']:.2f}")
        
        # Parameter analysis
        if parameter_analysis:
            print(f"\n⚙️ ANALYSIS BY PARAMETER:")
            for param, data in parameter_analysis.items():
                print(f"   Parameter: {param}")
                print(f"      Trade Count: {data['trade_count']}")
                print(f"      Win Rate: {data['win_rate']:.1f}%")
                print(f"      Average Profit: ${data['avg_profit']:.2f}")
                print(f"      Total Profit: ${data['total_profit']:.2f}")
        
        # Weighted performance analysis
        if weighted_analysis:
            print(f"\n🎯 WEIGHTED PERFORMANCE ANALYSIS:")
            print("="*50)
            
            # Overall strategy score
            overall_stats = {
                'win_rate': (feature_df['target'].sum() / len(feature_df)) * 100,
                'avg_profit': feature_df['profit'].mean(),
                'trade_count': len(feature_df),
                'profit_factor': abs(feature_df[feature_df['profit'] > 0]['profit'].sum() / 
                                   feature_df[feature_df['profit'] < 0]['profit'].sum()) if len(feature_df[feature_df['profit'] < 0]) > 0 else float('inf')
            }
            
            overall_score = self.calculate_weighted_score(overall_stats, 'trade')
            print(f"📊 OVERALL STRATEGY SCORE: {overall_score['total_score']}/100 ({overall_score['grade']})")
            print("   Breakdown:")
            for metric, score in overall_score['breakdown'].items():
                print(f"     {metric}: {score} points")
            
            # Symbol scores
            if symbol_analysis:
                print(f"\n📈 SYMBOL PERFORMANCE RANKINGS:")
                symbol_scores = []
                for symbol, data in symbol_analysis.items():
                    score_result = self.calculate_weighted_score(data, 'symbol')
                    symbol_scores.append({
                        'symbol': symbol,
                        'score': score_result['total_score'],
                        'grade': score_result['grade'],
                        'data': data
                    })
                
                # Sort by score
                symbol_scores.sort(key=lambda x: x['score'], reverse=True)
                for i, symbol_score in enumerate(symbol_scores[:5]):  # Top 5
                    print(f"   {i+1}. {symbol_score['symbol']}: {symbol_score['score']}/100 ({symbol_score['grade']})")
            
            # Timeframe scores
            if timeframe_analysis:
                print(f"\n⏰ TIMEFRAME PERFORMANCE RANKINGS:")
                timeframe_scores = []
                for timeframe, data in timeframe_analysis.items():
                    score_result = self.calculate_weighted_score(data, 'timeframe')
                    timeframe_scores.append({
                        'timeframe': timeframe,
                        'score': score_result['total_score'],
                        'grade': score_result['grade'],
                        'data': data
                    })
                
                # Sort by score
                timeframe_scores.sort(key=lambda x: x['score'], reverse=True)
                for i, timeframe_score in enumerate(timeframe_scores):
                    print(f"   {i+1}. {timeframe_score['timeframe']}: {timeframe_score['score']}/100 ({timeframe_score['grade']})")
            
            print(f"\n📊 OVERALL WEIGHTED SCORE: {weighted_analysis['overall_score']['total_score']}/100 ({weighted_analysis['overall_score']['grade']})")
            print("   Breakdown:")
            for metric, score in weighted_analysis['overall_score']['breakdown'].items():
                print(f"     {metric}: {score} points")
        
        # Recommendations
        print(f"\n💡 RECOMMENDATIONS:")
        self._generate_recommendations(feature_df, importance_df, cluster_analysis)
        
        print("\n" + "="*80)
    
    def _generate_recommendations(self, feature_df, importance_df, cluster_analysis):
        """Generate specific recommendations based on analysis"""
        recommendations = []
        
        # Check win rate
        win_rate = (feature_df['target'].sum() / len(feature_df)) * 100
        if win_rate < 50:
            recommendations.append("⚠️  Low win rate detected. Consider tightening entry criteria.")
        
        # Check kill zone effectiveness (if column exists)
        if 'in_kill_zone' in feature_df.columns:
            kill_zone_trades = feature_df[feature_df['in_kill_zone'] == 1]
            if len(kill_zone_trades) > 0:
                kill_zone_win_rate = (kill_zone_trades['target'].sum() / len(kill_zone_trades)) * 100
                if kill_zone_win_rate < win_rate:
                    recommendations.append("⚠️  Kill zone trades underperforming. Review kill zone timing.")
        
        # Check FVG effectiveness (if column exists)
        if 'has_fvg' in feature_df.columns:
            fvg_trades = feature_df[feature_df['has_fvg'] == 1]
            if len(fvg_trades) > 0:
                fvg_win_rate = (fvg_trades['target'].sum() / len(fvg_trades)) * 100
                if fvg_win_rate < win_rate:
                    recommendations.append("⚠️  FVG trades underperforming. Review FVG detection logic.")
        
        # Check volume analysis (if volume data exists)
        if 'volume' in feature_df.columns:
            high_volume_trades = feature_df[feature_df['volume'] > feature_df['volume'].median()]
            if len(high_volume_trades) > 0:
                volume_win_rate = (high_volume_trades['target'].sum() / len(high_volume_trades)) * 100
                if volume_win_rate > win_rate:
                    recommendations.append("✅ High volume trades are effective. Consider volume-based filtering.")
        
        # Check risk management (if lot_size data exists)
        if 'lot_size' in feature_df.columns:
            high_lot_trades = feature_df[feature_df['lot_size'] > feature_df['lot_size'].median()]
            if len(high_lot_trades) > 0:
                high_lot_win_rate = (high_lot_trades['target'].sum() / len(high_lot_trades)) * 100
                if high_lot_win_rate < win_rate:
                    recommendations.append("⚠️  High lot size trades underperforming. Consider reducing position sizes.")
        
        # Print recommendations
        if recommendations:
            for rec in recommendations:
                print(f"   {rec}")
        else:
            print("   ✅ No major issues detected. Strategy appears to be working well.")
    
    def save_models(self, filepath='ml_models/'):
        """Save trained models for later use"""
        import os
        os.makedirs(filepath, exist_ok=True)
        
        for name, model in self.models.items():
            joblib.dump(model, f"{filepath}/{name}.pkl")
        
        # Save scaler and encoder
        joblib.dump(self.scaler, f"{filepath}/scaler.pkl")
        joblib.dump(self.label_encoder, f"{filepath}/label_encoder.pkl")
        
        print(f"💾 Models saved to {filepath}")

    def analyze_by_symbol(self, feature_df):
        """Analyze performance by symbol"""
        if 'symbol' not in feature_df.columns:
            return None
            
        symbol_analysis = {}
        for symbol in feature_df['symbol'].unique():
            symbol_data = feature_df[feature_df['symbol'] == symbol]
            if len(symbol_data) > 10:  # Only analyze symbols with sufficient data
                symbol_analysis[symbol] = {
                    'trade_count': len(symbol_data),
                    'win_rate': (symbol_data['target'].sum() / len(symbol_data)) * 100,
                    'avg_profit': symbol_data['profit'].mean(),
                    'total_profit': symbol_data['profit'].sum(),
                    'profit_factor': abs(symbol_data[symbol_data['profit'] > 0]['profit'].sum() / 
                                       symbol_data[symbol_data['profit'] < 0]['profit'].sum()) if len(symbol_data[symbol_data['profit'] < 0]) > 0 else float('inf')
                }
        
        return symbol_analysis
    
    def analyze_by_timeframe(self, feature_df):
        """Analyze performance by timeframe"""
        if 'timeframe' not in feature_df.columns:
            return None
            
        timeframe_analysis = {}
        for timeframe in feature_df['timeframe'].unique():
            timeframe_data = feature_df[feature_df['timeframe'] == timeframe]
            if len(timeframe_data) > 10:  # Only analyze timeframes with sufficient data
                timeframe_analysis[timeframe] = {
                    'trade_count': len(timeframe_data),
                    'win_rate': (timeframe_data['target'].sum() / len(timeframe_data)) * 100,
                    'avg_profit': timeframe_data['profit'].mean(),
                    'total_profit': timeframe_data['profit'].sum(),
                    'profit_factor': abs(timeframe_data[timeframe_data['profit'] > 0]['profit'].sum() / 
                                       timeframe_data[timeframe_data['profit'] < 0]['profit'].sum()) if len(timeframe_data[timeframe_data['profit'] < 0]) > 0 else float('inf')
                }
        
        return timeframe_analysis
    
    def analyze_parameter_effectiveness(self, feature_df):
        """Analyze which parameters are most effective"""
        param_columns = [col for col in feature_df.columns if col.startswith('param_')]
        if not param_columns:
            return None
            
        param_analysis = {}
        for param_col in param_columns:
            param_name = param_col.replace('param_', '')
            
            # Analyze boolean parameters
            if feature_df[param_col].dtype in ['int64', 'bool'] and feature_df[param_col].nunique() == 2:
                param_values = feature_df[param_col].unique()
                for value in param_values:
                    value_data = feature_df[feature_df[param_col] == value]
                    if len(value_data) > 10:
                        key = f"{param_name}_{value}"
                        param_analysis[key] = {
                            'trade_count': len(value_data),
                            'win_rate': (value_data['target'].sum() / len(value_data)) * 100,
                            'avg_profit': value_data['profit'].mean(),
                            'total_profit': value_data['profit'].sum()
                        }
            
            # Analyze numeric parameters
            elif feature_df[param_col].dtype in ['float64', 'int64'] and feature_df[param_col].nunique() > 2:
                # Split into high/low values
                median_val = feature_df[param_col].median()
                low_data = feature_df[feature_df[param_col] <= median_val]
                high_data = feature_df[feature_df[param_col] > median_val]
                
                if len(low_data) > 10:
                    param_analysis[f"{param_name}_low"] = {
                        'trade_count': len(low_data),
                        'win_rate': (low_data['target'].sum() / len(low_data)) * 100,
                        'avg_profit': low_data['profit'].mean(),
                        'total_profit': low_data['profit'].sum()
                    }
                
                if len(high_data) > 10:
                    param_analysis[f"{param_name}_high"] = {
                        'trade_count': len(high_data),
                        'win_rate': (high_data['target'].sum() / len(high_data)) * 100,
                        'avg_profit': high_data['profit'].mean(),
                        'total_profit': high_data['profit'].sum()
                    }
        
        return param_analysis

    def calculate_weighted_score(self, data, score_type='trade'):
        """
        Calculate weighted scores similar to app.py but enhanced for ML analysis.
        Supports different scoring for trades, clusters, symbols, timeframes.
        """
        if score_type == 'trade':
            return self._calculate_trade_score(data)
        elif score_type == 'cluster':
            return self._calculate_cluster_score(data)
        elif score_type == 'symbol':
            return self._calculate_symbol_score(data)
        elif score_type == 'timeframe':
            return self._calculate_timeframe_score(data)
        else:
            return self._calculate_general_score(data)
    
    def _calculate_trade_score(self, trade_data):
        """Calculate weighted score for individual trade"""
        score = 0
        breakdown = {}
        
        # Profit factor (0-20 points)
        if 'profit_factor' in trade_data and trade_data['profit_factor']:
            pf = trade_data['profit_factor']
            if pf >= 2.0:
                pf_score = 20
            elif pf >= 1.5:
                pf_score = 15 + (pf - 1.5) * 10
            elif pf >= 1.2:
                pf_score = 10 + (pf - 1.2) * 16.67
            else:
                pf_score = max(0, pf * 8.33)
            breakdown['profit_factor'] = round(pf_score, 2)
            score += pf_score
        
        # Win rate (0-15 points)
        if 'win_rate' in trade_data and trade_data['win_rate']:
            wr = trade_data['win_rate']
            if wr >= 70:
                wr_score = 15
            elif wr >= 60:
                wr_score = 10 + (wr - 60) * 0.5
            elif wr >= 50:
                wr_score = 5 + (wr - 50) * 0.5
            else:
                wr_score = max(0, wr * 0.1)
            breakdown['win_rate'] = round(wr_score, 2)
            score += wr_score
        
        # Average profit (0-15 points)
        if 'avg_profit' in trade_data and trade_data['avg_profit']:
            ap = trade_data['avg_profit']
            if ap >= 10:
                ap_score = 15
            elif ap >= 5:
                ap_score = 10 + (ap - 5) * 1
            elif ap >= 1:
                ap_score = 5 + (ap - 1) * 1.25
            else:
                ap_score = max(0, ap * 5)
            breakdown['avg_profit'] = round(ap_score, 2)
            score += ap_score
        
        # Trade count (0-10 points) - More trades = more significance
        if 'trade_count' in trade_data and trade_data['trade_count']:
            tc = trade_data['trade_count']
            if tc >= 100:
                tc_score = 10
            elif tc >= 50:
                tc_score = 7 + (tc - 50) * 0.06
            elif tc >= 20:
                tc_score = 4 + (tc - 20) * 0.1
            else:
                tc_score = tc * 0.2
            breakdown['trade_count'] = round(tc_score, 2)
            score += tc_score
        
        # Risk-adjusted metrics (0-20 points)
        if 'profit_factor' in trade_data and 'win_rate' in trade_data:
            risk_score = 0
            pf = trade_data['profit_factor']
            wr = trade_data['win_rate']
            
            # Combine profit factor and win rate for risk-adjusted score
            if pf >= 1.5 and wr >= 60:
                risk_score = 20
            elif pf >= 1.2 and wr >= 50:
                risk_score = 15
            elif pf >= 1.0 and wr >= 45:
                risk_score = 10
            else:
                risk_score = max(0, (pf * 10 + wr * 0.1) / 2)
            
            breakdown['risk_adjusted'] = round(risk_score, 2)
            score += risk_score
        
        # Consistency bonus (0-10 points)
        if 'win_rate' in trade_data and 'trade_count' in trade_data:
            wr = trade_data['win_rate']
            tc = trade_data['trade_count']
            if tc >= 50 and wr >= 55:
                consistency_score = 10
            elif tc >= 30 and wr >= 50:
                consistency_score = 7
            elif tc >= 20 and wr >= 45:
                consistency_score = 5
            else:
                consistency_score = 0
            breakdown['consistency'] = round(consistency_score, 2)
            score += consistency_score
        
        # ML-specific bonus (0-10 points)
        if 'prediction_accuracy' in trade_data:
            acc = trade_data['prediction_accuracy']
            ml_score = min(10, acc * 10)
            breakdown['ml_accuracy'] = round(ml_score, 2)
            score += ml_score
        
        return {
            'total_score': round(score, 2),
            'breakdown': breakdown,
            'grade': self._get_grade(score)
        }
    
    def _calculate_cluster_score(self, cluster_data):
        """Calculate weighted score for trading pattern clusters"""
        return self._calculate_trade_score(cluster_data)
    
    def _calculate_symbol_score(self, symbol_data):
        """Calculate weighted score for symbol performance"""
        return self._calculate_trade_score(symbol_data)
    
    def _calculate_timeframe_score(self, timeframe_data):
        """Calculate weighted score for timeframe performance"""
        return self._calculate_trade_score(timeframe_data)
    
    def _calculate_general_score(self, data):
        """Calculate general weighted score"""
        return self._calculate_trade_score(data)
    
    def _get_grade(self, score):
        """Convert score to letter grade"""
        if score >= 90:
            return 'A+'
        elif score >= 85:
            return 'A'
        elif score >= 80:
            return 'A-'
        elif score >= 75:
            return 'B+'
        elif score >= 70:
            return 'B'
        elif score >= 65:
            return 'B-'
        elif score >= 60:
            return 'C+'
        elif score >= 55:
            return 'C'
        elif score >= 50:
            return 'C-'
        elif score >= 40:
            return 'D'
        else:
            return 'F'
    
    def analyze_weighted_performance(self, feature_df, symbol_analysis, timeframe_analysis, cluster_analysis):
        """Analyze performance using weighted scoring system"""
        print("\n🎯 WEIGHTED PERFORMANCE ANALYSIS:")
        print("="*50)
        
        # Overall strategy score
        overall_stats = {
            'win_rate': (feature_df['target'].sum() / len(feature_df)) * 100,
            'avg_profit': feature_df['profit'].mean(),
            'trade_count': len(feature_df),
            'profit_factor': abs(feature_df[feature_df['profit'] > 0]['profit'].sum() / 
                               feature_df[feature_df['profit'] < 0]['profit'].sum()) if len(feature_df[feature_df['profit'] < 0]) > 0 else float('inf')
        }
        
        overall_score = self.calculate_weighted_score(overall_stats, 'trade')
        print(f"📊 OVERALL STRATEGY SCORE: {overall_score['total_score']}/100 ({overall_score['grade']})")
        print("   Breakdown:")
        for metric, score in overall_score['breakdown'].items():
            print(f"     {metric}: {score} points")
        
        # Symbol scores
        if symbol_analysis:
            print(f"\n📈 SYMBOL PERFORMANCE RANKINGS:")
            symbol_scores = []
            for symbol, data in symbol_analysis.items():
                score_result = self.calculate_weighted_score(data, 'symbol')
                symbol_scores.append({
                    'symbol': symbol,
                    'score': score_result['total_score'],
                    'grade': score_result['grade'],
                    'data': data
                })
            
            # Sort by score
            symbol_scores.sort(key=lambda x: x['score'], reverse=True)
            for i, symbol_score in enumerate(symbol_scores[:5]):  # Top 5
                print(f"   {i+1}. {symbol_score['symbol']}: {symbol_score['score']}/100 ({symbol_score['grade']})")
        
        # Timeframe scores
        if timeframe_analysis:
            print(f"\n⏰ TIMEFRAME PERFORMANCE RANKINGS:")
            timeframe_scores = []
            for timeframe, data in timeframe_analysis.items():
                score_result = self.calculate_weighted_score(data, 'timeframe')
                timeframe_scores.append({
                    'timeframe': timeframe,
                    'score': score_result['total_score'],
                    'grade': score_result['grade'],
                    'data': data
                })
            
            # Sort by score
            timeframe_scores.sort(key=lambda x: x['score'], reverse=True)
            for i, timeframe_score in enumerate(timeframe_scores):
                print(f"   {i+1}. {timeframe_score['timeframe']}: {timeframe_score['score']}/100 ({timeframe_score['grade']})")
        
        return {
            'overall_score': overall_score,
            'symbol_scores': symbol_scores if symbol_analysis else None,
            'timeframe_scores': timeframe_scores if timeframe_analysis else None
        }

    def extract_parameters(self, df):
        """Expand the 'parameters' JSON column into separate param_ columns."""
        import json
        from pandas import isnull
        
        # Find all unique parameter keys
        param_keys = set()
        for params in df['parameters'].dropna():
            try:
                param_dict = json.loads(params)
                param_keys.update(param_dict.keys())
            except Exception as e:
                continue
        
        # For each key, create a new column
        for key in param_keys:
            col_name = f'param_{key}'
            df[col_name] = None
            for idx, params in df['parameters'].items():
                if isnull(params):
                    continue
                try:
                    param_dict = json.loads(params)
                    value = param_dict.get(key, None)
                    df.at[idx, col_name] = value
                except Exception as e:
                    continue
        return df

def main():
    """Main function to run the diagnostic tool"""
    from app import app
    
    with app.app_context():
        diagnostic = TradingEADiagnostic(db.engine)
        results = diagnostic.generate_diagnostic_report()
        
        if results:
            # Save models for future use
            diagnostic.save_models()
            
            print("\n🎉 Diagnostic analysis complete!")
            print("📁 Models saved for future predictions")

if __name__ == "__main__":
    main() 