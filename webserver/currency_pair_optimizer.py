#!/usr/bin/env python3
"""
Currency Pair Optimizer - Demonstrates currency pair-specific parameter optimization
"""

import os
import json
import pandas as pd
from datetime import datetime

class CurrencyPairOptimizer:
    def __init__(self, models_dir='ml_models/'):
        self.models_dir = models_dir
        os.makedirs(models_dir, exist_ok=True)
        
        # Common broker symbol suffixes
        self.broker_suffixes = ['+', '.a', '.b', '.c', '.raw', '.pro', '.ecn', '.stp']
        
        # Currency pair characteristics
        self.currency_pairs = {
            'EURUSD': {
                'name': 'EURUSD',
                'volatility_multiplier': 1.0,  # Base volatility
                'spread_adjustment': 1.0,      # Base spread
                'session_weight': 1.0,         # Base session weight
                'description': 'Major pair - London/NY session focus',
                'typical_spread': 1.0,         # 1 pip typical spread
                'session_hours': 'London/NY',  # Most active sessions
                'correlation_notes': 'Correlates with GBP/USD, inverse to USD/CHF',
                'broker_symbols': ['EURUSD', 'EURUSD+', 'EURUSD.a', 'EURUSD.pro']  # Common broker formats
            },
            'GBPUSD': {
                'name': 'GBPUSD', 
                'volatility_multiplier': 1.2,  # Higher volatility
                'spread_adjustment': 1.1,      # Slightly higher spread
                'session_weight': 1.1,         # London session focus
                'description': 'Major pair - Higher volatility, London focus',
                'typical_spread': 1.2,         # 1.2 pip typical spread
                'session_hours': 'London',     # London session focus
                'correlation_notes': 'Correlates with EUR/USD, sensitive to UK news',
                'broker_symbols': ['GBPUSD', 'GBPUSD+', 'GBPUSD.a', 'GBPUSD.pro']
            },
            'USDJPY': {
                'name': 'USDJPY',
                'volatility_multiplier': 0.8,  # Lower volatility
                'spread_adjustment': 0.9,      # Lower spread
                'session_weight': 0.9,         # Asian session focus
                'description': 'Major pair - Lower volatility, Asian focus',
                'typical_spread': 0.9,         # 0.9 pip typical spread
                'session_hours': 'Asian',      # Asian session focus
                'correlation_notes': 'Safe haven pair, inverse to risk sentiment',
                'broker_symbols': ['USDJPY', 'USDJPY+', 'USDJPY.a', 'USDJPY.pro']
            },
            'GBPJPY': {
                'name': 'GBPJPY',
                'volatility_multiplier': 1.5,  # High volatility
                'spread_adjustment': 1.3,      # Higher spread
                'session_weight': 1.2,         # London/Asian crossover
                'description': 'Cross pair - High volatility, London/Asian crossover',
                'typical_spread': 2.0,         # 2 pip typical spread
                'session_hours': 'London/Asian', # Crossover sessions
                'correlation_notes': 'High volatility, GBP/JPY = GBP/USD × USD/JPY',
                'broker_symbols': ['GBPJPY', 'GBPJPY+', 'GBPJPY.a', 'GBPJPY.pro']
            },
            'XAUUSD': {
                'name': 'XAUUSD',
                'volatility_multiplier': 1.8,  # Very high volatility
                'spread_adjustment': 1.5,      # High spread
                'session_weight': 1.3,         # All sessions
                'description': 'Commodity - Very high volatility, all sessions',
                'typical_spread': 3.0,         # 3 pip typical spread
                'session_hours': 'All',        # All sessions active
                'correlation_notes': 'Safe haven, inverse to USD strength',
                'broker_symbols': ['XAUUSD', 'XAUUSD+', 'XAUUSD.a', 'XAUUSD.pro']
            }
        }
    
    def normalize_symbol(self, symbol):
        """Normalize broker symbol to base currency pair"""
        base_symbol = symbol
        
        # Remove common broker suffixes
        for suffix in self.broker_suffixes:
            if symbol.endswith(suffix):
                base_symbol = symbol[:-len(suffix)]
                break
        
        return base_symbol
    
    def get_pair_config(self, symbol):
        """Get currency pair configuration for a given symbol"""
        base_symbol = self.normalize_symbol(symbol)
        
        if base_symbol in self.currency_pairs:
            return self.currency_pairs[base_symbol]
        else:
            print(f"⚠️  Unknown currency pair: {symbol} (base: {base_symbol})")
            return None
    
    def generate_base_parameters(self):
        """Generate base parameters that will be adjusted for each currency pair"""
        return {
            'combined_min_prediction_threshold': 0.55,
            'combined_max_prediction_threshold': 0.45,
            'combined_min_confidence': 0.30,
            'combined_max_confidence': 0.85,
            'combined_position_sizing_multiplier': 1.0,
            'combined_stop_loss_adjustment': 1.0,
            'combined_rsi_bullish_threshold': 30.0,
            'combined_rsi_bearish_threshold': 70.0,
            'combined_rsi_weight': 0.08,
            'combined_stoch_bullish_threshold': 20.0,
            'combined_stoch_bearish_threshold': 80.0,
            'combined_stoch_weight': 0.08,
            'combined_macd_threshold': 0.0,
            'combined_macd_weight': 0.08,
            'combined_volume_ratio_threshold': 1.5,
            'combined_volume_weight': 0.08,
            'combined_pattern_bullish_weight': 0.12,
            'combined_pattern_bearish_weight': 0.12,
            'combined_zone_weight': 0.08,
            'combined_trend_weight': 0.08,
            'combined_base_confidence': 0.6,
            'combined_signal_agreement_weight': 0.5,
            'combined_neutral_zone_min': 0.4,
            'combined_neutral_zone_max': 0.6,
            
            # Buy model parameters
            'buy_min_prediction_threshold': 0.52,
            'buy_max_prediction_threshold': 0.48,
            'buy_min_confidence': 0.35,
            'buy_max_confidence': 0.9,
            'buy_position_sizing_multiplier': 1.2,
            'buy_stop_loss_adjustment': 0.5,
            'buy_rsi_bullish_threshold': 30.0,
            'buy_rsi_bearish_threshold': 70.0,
            'buy_rsi_weight': 0.08,
            'buy_stoch_bullish_threshold': 20.0,
            'buy_stoch_bearish_threshold': 80.0,
            'buy_stoch_weight': 0.08,
            'buy_macd_threshold': 0.0,
            'buy_macd_weight': 0.08,
            'buy_volume_ratio_threshold': 1.5,
            'buy_volume_weight': 0.08,
            'buy_pattern_bullish_weight': 0.12,
            'buy_pattern_bearish_weight': 0.12,
            'buy_zone_weight': 0.08,
            'buy_trend_weight': 0.08,
            'buy_base_confidence': 0.6,
            'buy_signal_agreement_weight': 0.5,
            
            # Sell model parameters
            'sell_min_prediction_threshold': 0.52,
            'sell_max_prediction_threshold': 0.48,
            'sell_min_confidence': 0.35,
            'sell_max_confidence': 0.9,
            'sell_position_sizing_multiplier': 1.2,
            'sell_stop_loss_adjustment': 0.5,
            'sell_rsi_bullish_threshold': 30.0,
            'sell_rsi_bearish_threshold': 70.0,
            'sell_rsi_weight': 0.08,
            'sell_stoch_bullish_threshold': 20.0,
            'sell_stoch_bearish_threshold': 80.0,
            'sell_stoch_weight': 0.08,
            'sell_macd_threshold': 0.0,
            'sell_macd_weight': 0.08,
            'sell_volume_ratio_threshold': 1.5,
            'sell_volume_weight': 0.08,
            'sell_pattern_bullish_weight': 0.12,
            'sell_pattern_bearish_weight': 0.12,
            'sell_zone_weight': 0.08,
            'sell_trend_weight': 0.08,
            'sell_base_confidence': 0.6,
            'sell_signal_agreement_weight': 0.5
        }
    
    def adjust_parameters_for_pair(self, base_params, pair_config):
        """Adjust base parameters for specific currency pair characteristics"""
        adjusted_params = {}
        
        for key, value in base_params.items():
            val = value
            
            # Apply currency pair-specific adjustments
            if 'threshold' in key and 'rsi' in key:
                # Adjust RSI thresholds based on volatility
                if 'bullish' in key:
                    val = max(20, min(40, val * pair_config['volatility_multiplier']))
                elif 'bearish' in key:
                    val = min(80, max(60, val / pair_config['volatility_multiplier']))
            
            elif 'threshold' in key and 'stoch' in key:
                # Adjust Stochastic thresholds based on volatility
                if 'bullish' in key:
                    val = max(15, min(30, val * pair_config['volatility_multiplier']))
                elif 'bearish' in key:
                    val = min(85, max(70, val / pair_config['volatility_multiplier']))
            
            elif 'volume_ratio_threshold' in key:
                # Adjust volume threshold based on session weight
                val = max(1.0, min(2.5, val * pair_config['session_weight']))
            
            elif 'confidence' in key and 'min' in key:
                # Adjust minimum confidence based on spread
                val = max(0.25, min(0.45, val * pair_config['spread_adjustment']))
            
            elif 'confidence' in key and 'max' in key:
                # Adjust maximum confidence based on spread
                val = min(0.95, max(0.75, val / pair_config['spread_adjustment']))
            
            elif 'position_sizing_multiplier' in key:
                # Adjust position sizing based on volatility
                val = max(0.5, min(2.0, val / pair_config['volatility_multiplier']))
            
            elif 'stop_loss_adjustment' in key:
                # Adjust stop loss based on volatility
                val = max(0.3, min(1.5, val * pair_config['volatility_multiplier']))
            
            adjusted_params[key] = val
        
        return adjusted_params
    
    def save_pair_parameters(self, pair_name, adjusted_params):
        """Save currency pair-specific parameters to file"""
        # Convert to key=value format
        param_content = []
        for key, value in adjusted_params.items():
            param_content.append(f"{key}={value:.4f}")
        
        # Save pair-specific file
        pair_file = os.path.join(self.models_dir, f'ml_model_params_{pair_name}.txt')
        with open(pair_file, 'w') as f:
            f.write('\n'.join(param_content))
        
        return pair_file
    
    def test_broker_symbols(self):
        """Test broker symbol normalization with various formats"""
        print("🧪 Testing broker symbol normalization...")
        print("=" * 60)
        
        test_symbols = [
            'EURUSD+',    # Your broker format
            'GBPUSD+',    # Your broker format
            'USDJPY+',    # Your broker format
            'GBPJPY+',    # Your broker format
            'XAUUSD+',    # Your broker format
            'EURUSD.a',   # Alternative broker format
            'GBPUSD.pro', # Alternative broker format
            'USDJPY.ecn', # Alternative broker format
            'UNKNOWN+',   # Unknown pair
            'EURUSD',     # Standard format
        ]
        
        for symbol in test_symbols:
            base_symbol = self.normalize_symbol(symbol)
            config = self.get_pair_config(symbol)
            
            if config:
                print(f"✅ {symbol:12} -> {base_symbol:8} | {config['description']}")
                print(f"   Volatility: {config['volatility_multiplier']}x | Spread: {config['spread_adjustment']}x | Sessions: {config['session_hours']}")
            else:
                print(f"❌ {symbol:12} -> {base_symbol:8} | Unknown currency pair")
        
        print("=" * 60)
    
    def generate_all_pair_parameters(self):
        """Generate parameters for all currency pairs"""
        print("🎯 Generating currency pair-specific parameters...")
        
        # Test broker symbol normalization first
        self.test_broker_symbols()
        print()
        
        base_params = self.generate_base_parameters()
        generated_files = []
        
        for pair, config in self.currency_pairs.items():
            print(f"\n📊 Processing {pair}...")
            print(f"   {config['description']}")
            print(f"   Volatility multiplier: {config['volatility_multiplier']}")
            print(f"   Spread adjustment: {config['spread_adjustment']}")
            print(f"   Session weight: {config['session_weight']}")
            print(f"   Typical spread: {config['typical_spread']} pips")
            print(f"   Session hours: {config['session_hours']}")
            print(f"   Correlation: {config['correlation_notes']}")
            print(f"   Broker symbols: {', '.join(config['broker_symbols'])}")
            
            # Adjust parameters for this pair
            adjusted_params = self.adjust_parameters_for_pair(base_params, config)
            
            # Save pair-specific file
            pair_file = self.save_pair_parameters(pair, adjusted_params)
            generated_files.append(pair_file)
            
            print(f"✅ {pair} parameters saved to: {pair_file}")
            
            # Show key adjustments
            print("   Key adjustments:")
            if 'rsi_bullish_threshold' in adjusted_params:
                print(f"     RSI Bullish: {base_params['combined_rsi_bullish_threshold']:.1f} → {adjusted_params['combined_rsi_bullish_threshold']:.1f}")
            if 'volume_ratio_threshold' in adjusted_params:
                print(f"     Volume Threshold: {base_params['combined_volume_ratio_threshold']:.2f} → {adjusted_params['combined_volume_ratio_threshold']:.2f}")
            if 'min_confidence' in adjusted_params:
                print(f"     Min Confidence: {base_params['combined_min_confidence']:.3f} → {adjusted_params['combined_min_confidence']:.3f}")
        
        # Also save generic parameters
        generic_file = os.path.join(self.models_dir, 'ml_model_params_simple.txt')
        param_content = [f"{key}={value:.4f}" for key, value in base_params.items()]
        with open(generic_file, 'w') as f:
            f.write('\n'.join(param_content))
        generated_files.append(generic_file)
        
        print(f"\n✅ Generic parameters saved to: {generic_file}")
        print(f"📁 Total files generated: {len(generated_files)}")
        
        return generated_files
    
    def create_parameter_summary(self):
        """Create a summary of all currency pair parameters"""
        summary = {
            'generated_at': datetime.now().isoformat(),
            'currency_pairs': {},
            'parameter_files': []
        }
        
        # Add currency pair information
        for pair, config in self.currency_pairs.items():
            summary['currency_pairs'][pair] = {
                'description': config['description'],
                'volatility_multiplier': config['volatility_multiplier'],
                'spread_adjustment': config['spread_adjustment'],
                'session_weight': config['session_weight'],
                'typical_spread': config['typical_spread'],
                'session_hours': config['session_hours'],
                'correlation_notes': config['correlation_notes'],
                'parameter_file': f'ml_model_params_{pair}.txt'
            }
        
        # Check which files exist
        for pair in self.currency_pairs.keys():
            pair_file = os.path.join(self.models_dir, f'ml_model_params_{pair}.txt')
            if os.path.exists(pair_file):
                summary['parameter_files'].append(pair_file)
        
        # Add generic file
        generic_file = os.path.join(self.models_dir, 'ml_model_params_simple.txt')
        if os.path.exists(generic_file):
            summary['parameter_files'].append(generic_file)
        
        # Save summary
        summary_file = os.path.join(self.models_dir, 'currency_pair_summary.json')
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"📋 Parameter summary saved to: {summary_file}")
        return summary_file

def main():
    """Main function to demonstrate currency pair optimization"""
    print("🎯 Currency Pair Optimizer")
    print("=" * 50)
    
    optimizer = CurrencyPairOptimizer()
    
    # Generate all currency pair parameters
    generated_files = optimizer.generate_all_pair_parameters()
    
    # Create summary
    summary_file = optimizer.create_parameter_summary()
    
    print("\n🎉 Currency pair optimization complete!")
    print(f"📁 Generated {len(generated_files)} parameter files")
    print(f"📋 Summary saved to: {summary_file}")
    
    print("\n💡 Usage:")
    print("1. Copy parameter files to MetaTrader's Common Files directory")
    print("2. EA will automatically load the correct file based on the trading symbol")
    print("3. Each currency pair will use optimized parameters for its characteristics")
    
    print("\n🔧 Currency Pair Characteristics:")
    for pair, config in optimizer.currency_pairs.items():
        print(f"   {pair}: {config['description']}")
        print(f"      Volatility: {config['volatility_multiplier']}x")
        print(f"      Spread: {config['spread_adjustment']}x")
        print(f"      Sessions: {config['session_hours']}")

if __name__ == "__main__":
    main() 