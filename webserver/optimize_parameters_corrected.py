#!/usr/bin/env python3
"""
Generate optimized parameters based on CORRECT trade performance analysis
BUY trades: 50% win rate, profitable
SELL trades: 12.5% win rate, losing money
"""

def generate_optimized_parameters():
    """Generate parameters optimized for the actual performance data"""
    
    # Based on the CORRECT analysis:
    # - Buy trades: 50% win rate, $646.83 profit ✅ PROFITABLE
    # - Sell trades: 12.5% win rate, -$147.97 profit ❌ LOSING MONEY
    # - Most trades hit stop loss (11/16)
    
    params = {}
    
    # COMBINED MODEL - Conservative approach
    params.update({
        # Risk Management - More conservative
        'combined_min_prediction_threshold': 0.55,  # Increased from 0.52
        'combined_max_prediction_threshold': 0.45,  # Decreased from 0.48
        'combined_min_confidence': 0.45,  # Increased from 0.35
        'combined_max_confidence': 0.85,  # Decreased from 0.9
        'combined_position_sizing_multiplier': 1.0,  # Reduced from 1.2
        'combined_stop_loss_adjustment': 0.8,  # Tighter stops (increased from 0.5)
        
        # Technical Indicators - Optimized for buy trades
        'combined_rsi_bullish_threshold': 25.0,  # More aggressive for buys
        'combined_rsi_bearish_threshold': 75.0,  # More aggressive for sells
        'combined_rsi_weight': 0.08,  # Increased from 0.05
        'combined_stoch_bullish_threshold': 15.0,  # More aggressive
        'combined_stoch_bearish_threshold': 85.0,  # More aggressive
        'combined_stoch_weight': 0.08,  # Increased from 0.05
        'combined_macd_threshold': 0.0001,
        'combined_macd_weight': 0.08,  # Increased from 0.05
        'combined_volume_ratio_threshold': 1.3,  # Reduced from 1.5
        'combined_volume_weight': 0.08,  # Increased from 0.05
        'combined_pattern_bullish_weight': 0.15,  # Increased from 0.12
        'combined_pattern_bearish_weight': 0.10,  # Reduced from 0.12 (sell trades perform poorly)
        'combined_zone_weight': 0.10,  # Increased from 0.08
        'combined_trend_weight': 0.10,  # Increased from 0.08
        'combined_base_confidence': 0.7,  # Reduced from 0.8
        'combined_signal_agreement_weight': 0.6,  # Increased from 0.5
        'combined_neutral_zone_min': 0.45,  # Narrowed
        'combined_neutral_zone_max': 0.55,  # Narrowed
    })
    
    # BUY MODEL - Optimized for profitable buy trades
    params.update({
        'buy_min_prediction_threshold': 0.52,  # Slightly lower (buy trades work well)
        'buy_max_prediction_threshold': 0.48,
        'buy_min_confidence': 0.4,  # Lower threshold (buy trades are profitable)
        'buy_max_confidence': 0.9,
        'buy_position_sizing_multiplier': 1.3,  # Increase size for buy trades
        'buy_stop_loss_adjustment': 0.7,  # Moderate stops
        
        # Technical indicators optimized for buy success
        'buy_rsi_bullish_threshold': 25.0,  # Aggressive for oversold
        'buy_rsi_bearish_threshold': 75.0,
        'buy_rsi_weight': 0.1,  # Higher weight
        'buy_stoch_bullish_threshold': 15.0,  # Aggressive
        'buy_stoch_bearish_threshold': 85.0,
        'buy_stoch_weight': 0.1,  # Higher weight
        'buy_macd_threshold': 0.0001,
        'buy_macd_weight': 0.08,
        'buy_volume_ratio_threshold': 1.2,  # Lower threshold
        'buy_volume_weight': 0.08,
        'buy_pattern_bullish_weight': 0.15,  # Higher for bullish patterns
        'buy_pattern_bearish_weight': 0.08,  # Lower for bearish patterns
        'buy_zone_weight': 0.12,  # Higher weight
        'buy_trend_weight': 0.12,  # Higher weight
        'buy_base_confidence': 0.75,  # Higher base confidence
        'buy_signal_agreement_weight': 0.6,
        'buy_neutral_zone_min': 0.45,
        'buy_neutral_zone_max': 0.55,
    })
    
    # SELL MODEL - Very conservative due to poor performance
    params.update({
        'sell_min_prediction_threshold': 0.6,  # Much higher threshold
        'sell_max_prediction_threshold': 0.4,
        'sell_min_confidence': 0.6,  # Much higher confidence required
        'sell_max_confidence': 0.8,  # Lower max (avoid overconfidence)
        'sell_position_sizing_multiplier': 0.7,  # Reduce size for sell trades
        'sell_stop_loss_adjustment': 0.9,  # Very tight stops
        
        # Technical indicators - very conservative for sells
        'sell_rsi_bullish_threshold': 35.0,  # Less aggressive
        'sell_rsi_bearish_threshold': 65.0,  # Less aggressive
        'sell_rsi_weight': 0.06,  # Lower weight
        'sell_stoch_bullish_threshold': 25.0,  # Less aggressive
        'sell_stoch_bearish_threshold': 75.0,  # Less aggressive
        'sell_stoch_weight': 0.06,  # Lower weight
        'sell_macd_threshold': 0.0001,
        'sell_macd_weight': 0.06,  # Lower weight
        'sell_volume_ratio_threshold': 1.8,  # Higher threshold
        'sell_volume_weight': 0.06,  # Lower weight
        'sell_pattern_bullish_weight': 0.08,  # Lower weight
        'sell_pattern_bearish_weight': 0.12,  # Keep moderate
        'sell_zone_weight': 0.06,  # Lower weight
        'sell_trend_weight': 0.06,  # Lower weight
        'sell_base_confidence': 0.6,  # Lower base confidence
        'sell_signal_agreement_weight': 0.5,
        'sell_neutral_zone_min': 0.4,
        'sell_neutral_zone_max': 0.6,
    })
    
    return params

def save_optimized_parameters():
    """Save optimized parameters to file"""
    params = generate_optimized_parameters()
    
    # Save to simple format
    with open('ml_models/ml_model_params_simple_optimized.txt', 'w') as f:
        for key, value in params.items():
            f.write(f'{key}={value}\n')
    
    print("✅ Optimized parameters saved to: ml_models/ml_model_params_simple_optimized.txt")
    
    # Copy to MetaTrader directory
    import shutil
    import os
    
    mt5_dir = '/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/'
    dest_path = os.path.join(mt5_dir, 'ml_model_params_simple_optimized.txt')
    
    shutil.copy('ml_models/ml_model_params_simple_optimized.txt', dest_path)
    print(f"✅ Copied to MetaTrader directory: {dest_path}")
    
    # Print summary
    print("\n📊 OPTIMIZED PARAMETERS SUMMARY:")
    print("=" * 50)
    print("🎯 BUY TRADES (Profitable - 50% win rate):")
    print("   - Lower confidence thresholds (0.4-0.9)")
    print("   - Higher position sizing (1.3x)")
    print("   - Aggressive RSI/Stoch thresholds (25/75)")
    print("   - Higher weights for technical indicators")
    
    print("\n⚠️  SELL TRADES (Losing - 12.5% win rate):")
    print("   - Much higher confidence thresholds (0.6-0.8)")
    print("   - Reduced position sizing (0.7x)")
    print("   - Conservative RSI/Stoch thresholds (35/65)")
    print("   - Lower weights for technical indicators")
    print("   - Very tight stop losses")
    
    print("\n🔄 COMBINED MODEL:")
    print("   - Moderate confidence thresholds (0.45-0.85)")
    print("   - Balanced position sizing (1.0x)")
    print("   - Optimized for overall profitability")
    
    print("\n💡 RECOMMENDATIONS:")
    print("   1. Test with these optimized parameters")
    print("   2. Consider disabling sell trades if performance doesn't improve")
    print("   3. Monitor stop loss performance closely")
    print("   4. Use trailing stops for profitable trades")
    print("   5. Investigate why MT5 shows different results than EA data")

if __name__ == "__main__":
    save_optimized_parameters() 