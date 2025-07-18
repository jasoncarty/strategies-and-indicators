#!/usr/bin/env python3
"""
Generate optimized parameters based on CORRECT trade performance analysis
SELL trades: 50% win rate, profitable ✅
BUY trades: 12.5% win rate, losing money ❌
"""

def generate_optimized_parameters():
    """Generate parameters optimized for the actual performance data"""
    
    # Based on the CORRECT analysis (after fixing the direction bug):
    # - Sell trades: 50% win rate, profitable ✅
    # - Buy trades: 12.5% win rate, losing money ❌
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
        
        # Technical Indicators - Optimized for sell trades (which are profitable)
        'combined_rsi_bullish_threshold': 30.0,  # Standard
        'combined_rsi_bearish_threshold': 70.0,  # Standard
        'combined_rsi_weight': 0.08,  # Increased from 0.05
        'combined_stoch_bullish_threshold': 20.0,  # Standard
        'combined_stoch_bearish_threshold': 80.0,  # Standard
        'combined_stoch_weight': 0.08,  # Increased from 0.05
        'combined_macd_threshold': 0.0001,
        'combined_macd_weight': 0.08,  # Increased from 0.05
        'combined_volume_ratio_threshold': 1.3,  # Reduced from 1.5
        'combined_volume_weight': 0.08,  # Increased from 0.05
        'combined_pattern_bullish_weight': 0.10,  # Reduced from 0.12 (buy trades perform poorly)
        'combined_pattern_bearish_weight': 0.15,  # Increased from 0.12 (sell trades perform well)
        'combined_zone_weight': 0.10,  # Increased from 0.08
        'combined_trend_weight': 0.10,  # Increased from 0.08
        'combined_base_confidence': 0.7,  # Reduced from 0.8
        'combined_signal_agreement_weight': 0.6,  # Increased from 0.5
        'combined_neutral_zone_min': 0.45,  # Narrowed
        'combined_neutral_zone_max': 0.55,  # Narrowed
    })
    
    # BUY MODEL - Very conservative due to poor performance
    params.update({
        'buy_min_prediction_threshold': 0.6,  # Much higher threshold
        'buy_max_prediction_threshold': 0.4,
        'buy_min_confidence': 0.6,  # Much higher confidence required
        'buy_max_confidence': 0.8,  # Lower max (avoid overconfidence)
        'buy_position_sizing_multiplier': 0.7,  # Reduce size for buy trades
        'buy_stop_loss_adjustment': 0.9,  # Very tight stops
        
        # Technical indicators - very conservative for buys
        'buy_rsi_bullish_threshold': 35.0,  # Less aggressive
        'buy_rsi_bearish_threshold': 65.0,  # Less aggressive
        'buy_rsi_weight': 0.06,  # Lower weight
        'buy_stoch_bullish_threshold': 25.0,  # Less aggressive
        'buy_stoch_bearish_threshold': 75.0,  # Less aggressive
        'buy_stoch_weight': 0.06,  # Lower weight
        'buy_macd_threshold': 0.0001,
        'buy_macd_weight': 0.06,  # Lower weight
        'buy_volume_ratio_threshold': 1.8,  # Higher threshold
        'buy_volume_weight': 0.06,  # Lower weight
        'buy_pattern_bullish_weight': 0.08,  # Lower weight
        'buy_pattern_bearish_weight': 0.12,  # Keep moderate
        'buy_zone_weight': 0.06,  # Lower weight
        'buy_trend_weight': 0.06,  # Lower weight
        'buy_base_confidence': 0.6,  # Lower base confidence
        'buy_signal_agreement_weight': 0.5,
        'buy_neutral_zone_min': 0.4,
        'buy_neutral_zone_max': 0.6,
    })
    
    # SELL MODEL - Optimized for profitable sell trades
    params.update({
        'sell_min_prediction_threshold': 0.52,  # Slightly lower (sell trades work well)
        'sell_max_prediction_threshold': 0.48,
        'sell_min_confidence': 0.4,  # Lower threshold (sell trades are profitable)
        'sell_max_confidence': 0.9,
        'sell_position_sizing_multiplier': 1.3,  # Increase size for sell trades
        'sell_stop_loss_adjustment': 0.7,  # Moderate stops
        
        # Technical indicators optimized for sell success
        'sell_rsi_bullish_threshold': 25.0,  # Aggressive for oversold
        'sell_rsi_bearish_threshold': 75.0,
        'sell_rsi_weight': 0.1,  # Higher weight
        'sell_stoch_bullish_threshold': 15.0,  # Aggressive
        'sell_stoch_bearish_threshold': 85.0,
        'sell_stoch_weight': 0.1,  # Higher weight
        'sell_macd_threshold': 0.0001,
        'sell_macd_weight': 0.08,
        'sell_volume_ratio_threshold': 1.2,  # Lower threshold
        'sell_volume_weight': 0.08,
        'sell_pattern_bullish_weight': 0.08,  # Lower for bullish patterns
        'sell_pattern_bearish_weight': 0.15,  # Higher for bearish patterns
        'sell_zone_weight': 0.12,  # Higher weight
        'sell_trend_weight': 0.12,  # Higher weight
        'sell_base_confidence': 0.75,  # Higher base confidence
        'sell_signal_agreement_weight': 0.6,
        'sell_neutral_zone_min': 0.45,
        'sell_neutral_zone_max': 0.55,
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
    print("⚠️  BUY TRADES (Losing - 12.5% win rate):")
    print("   - Much higher confidence thresholds (0.6-0.8)")
    print("   - Reduced position sizing (0.7x)")
    print("   - Conservative RSI/Stoch thresholds (35/65)")
    print("   - Lower weights for technical indicators")
    print("   - Very tight stop losses")
    
    print("\n🎯 SELL TRADES (Profitable - 50% win rate):")
    print("   - Lower confidence thresholds (0.4-0.9)")
    print("   - Higher position sizing (1.3x)")
    print("   - Aggressive RSI/Stoch thresholds (25/75)")
    print("   - Higher weights for technical indicators")
    
    print("\n🔄 COMBINED MODEL:")
    print("   - Moderate confidence thresholds (0.45-0.85)")
    print("   - Balanced position sizing (1.0x)")
    print("   - Optimized for overall profitability")
    print("   - Higher weights for bearish patterns (sell trades)")
    
    print("\n💡 RECOMMENDATIONS:")
    print("   1. Test with these optimized parameters")
    print("   2. Consider focusing more on sell trades")
    print("   3. Be very selective with buy trades")
    print("   4. Monitor stop loss performance closely")
    print("   5. The direction bug has been fixed in the EA")

if __name__ == "__main__":
    save_optimized_parameters() 