#!/usr/bin/env python3
"""
Temporary ML Disabler
Helps disable ML temporarily to prevent further losses
"""

import os
import json
from datetime import datetime

def create_safe_parameters():
    """Create safe parameter files that disable ML"""
    print("🛡️  Creating safe ML parameters...")
    
    # Safe parameters that effectively disable ML
    safe_params = {
        'min_prediction_threshold': 0.99,  # Very high - almost never triggers
        'max_prediction_threshold': 0.01,  # Very low - almost never triggers
        'min_confidence': 0.95,           # Very high confidence required
        'max_confidence': 0.05,           # Very low max confidence
        'position_sizing_multiplier': 1.0,
        'stop_loss_adjustment': 1.0,
        'rsi_bullish_threshold': 30.0,
        'rsi_bearish_threshold': 70.0,
        'rsi_weight': 0.0,               # Disable RSI ML
        'stoch_bullish_threshold': 20.0,
        'stoch_bearish_threshold': 80.0,
        'stoch_weight': 0.0,             # Disable Stochastic ML
        'macd_threshold': 0.0000,
        'macd_weight': 0.0,              # Disable MACD ML
        'volume_ratio_threshold': 1.50,
        'volume_weight': 0.0,            # Disable Volume ML
        'pattern_bullish_weight': 0.0,   # Disable Pattern ML
        'pattern_bearish_weight': 0.0,   # Disable Pattern ML
        'zone_weight': 0.0,              # Disable Zone ML
        'trend_weight': 0.0,             # Disable Trend ML
        'base_confidence': 0.0,          # Disable base confidence
        'signal_agreement_weight': 0.0,  # Disable signal agreement
        'neutral_zone_min': 0.0,
        'neutral_zone_max': 1.0,
        'ml_disabled_note': 'ML temporarily disabled for safety',
        'disabled_date': datetime.now().isoformat()
    }
    
    # Save to multiple parameter files
    param_files = [
        'ml_models/ml_model_params_simple.txt',
        'ml_models/ml_model_params_EURUSD.txt',
        'ml_models/ml_model_params_GBPUSD.txt',
        'ml_models/ml_model_params_USDJPY.txt',
        'ml_models/ml_model_params_XAUUSD.txt',
        'ml_models/ml_model_params_improved.txt'
    ]
    
    for param_file in param_files:
        try:
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(param_file), exist_ok=True)
            
            with open(param_file, 'w') as f:
                for key, value in safe_params.items():
                    if isinstance(value, float):
                        f.write(f"{key}={value:.4f}\n")
                    elif isinstance(value, str):
                        f.write(f"{key}={value}\n")
                    else:
                        f.write(f"{key}={value}\n")
            
            print(f"✅ Created safe parameters: {param_file}")
            
        except Exception as e:
            print(f"⚠️  Error creating {param_file}: {e}")
    
    return safe_params

def create_ea_backup_instructions():
    """Create instructions for backing up EA settings"""
    print("\n📋 EA BACKUP INSTRUCTIONS")
    print("=" * 50)
    
    instructions = """
    🔄 TEMPORARY ML DISABLE INSTRUCTIONS
    
    To safely disable ML in your EA:
    
    1. **Backup Current Settings**:
       - Copy your current EA parameters
       - Note down any custom settings
    
    2. **Disable ML in EA**:
       Set these parameters in your EA:
       
       input bool UseMLModels = false;           // Disable ML
       input bool UseMLPositionSizing = false;   // Disable ML position sizing
       input bool UseMLStopLossAdjustment = false; // Disable ML stop loss
    
    3. **Use Conservative Settings**:
       input double RiskPercent = 0.5;           // Reduce risk
       input double RiskRewardRatio = 2.0;       // Keep 2:1 ratio
       input int StopLossBuffer = 25;            // Increase buffer
    
    4. **Test on Demo Account**:
       - Run the EA on demo first
       - Monitor for 1-2 weeks
       - Ensure stable performance
    
    5. **Re-enable ML Later** (when ready):
       - Collect more diverse data
       - Use conservative ML thresholds
       - Monitor performance closely
    
    ⚠️  IMPORTANT: Always test changes on demo first!
    """
    
    print(instructions)
    
    # Save instructions to file
    with open('ml_models/ML_DISABLE_INSTRUCTIONS.txt', 'w') as f:
        f.write(instructions)
    
    print("✅ Instructions saved to: ml_models/ML_DISABLE_INSTRUCTIONS.txt")

def create_recovery_plan():
    """Create a recovery plan for re-enabling ML"""
    print("\n📈 ML RECOVERY PLAN")
    print("=" * 50)
    
    recovery_plan = """
    🔄 ML RECOVERY PLAN
    
    Phase 1: Data Collection (2-4 weeks)
    - Test EA on multiple symbols (EURUSD, GBPUSD, USDJPY, XAUUSD)
    - Test on multiple timeframes (M5, M15, H1, H4, D1)
    - Collect data from different market conditions
    - Ensure no data leakage in collection
    
    Phase 2: Data Validation (1 week)
    - Run data quality analysis
    - Check for data leakage
    - Validate feature quality
    - Ensure temporal separation
    
    Phase 3: Conservative ML Training (1 week)
    - Use improved ML trainer
    - Implement time series validation
    - Start with very conservative thresholds
    - Test on out-of-sample data
    
    Phase 4: Gradual Re-enabling (2-4 weeks)
    - Enable ML with very conservative settings
    - Monitor performance closely
    - Gradually adjust thresholds
    - Keep fallback to non-ML mode
    
    Phase 5: Full ML Integration (ongoing)
    - Optimize ML parameters
    - Implement continuous monitoring
    - Regular model retraining
    - Performance tracking
    
    🎯 SUCCESS CRITERIA:
    - Win rate > 50%
    - Profit factor > 1.2
    - Maximum drawdown < 10%
    - Consistent performance across symbols
    
    ⚠️  STOP CRITERIA:
    - Win rate < 40%
    - Profit factor < 1.0
    - Maximum drawdown > 15%
    - Inconsistent performance
    """
    
    print(recovery_plan)
    
    # Save recovery plan to file
    with open('ml_models/ML_RECOVERY_PLAN.txt', 'w') as f:
        f.write(recovery_plan)
    
    print("✅ Recovery plan saved to: ml_models/ML_RECOVERY_PLAN.txt")

def main():
    """Main function"""
    print("🛡️  ML TEMPORARY DISABLER")
    print("=" * 50)
    print("This tool helps safely disable ML to prevent further losses")
    print()
    
    # Create safe parameters
    safe_params = create_safe_parameters()
    
    # Create backup instructions
    create_ea_backup_instructions()
    
    # Create recovery plan
    create_recovery_plan()
    
    print("\n" + "=" * 50)
    print("✅ ML DISABLE COMPLETE")
    print("=" * 50)
    print("🎯 NEXT STEPS:")
    print("1. Update your EA parameters to disable ML")
    print("2. Test on demo account for 1-2 weeks")
    print("3. Monitor performance closely")
    print("4. Follow the recovery plan when ready")
    print()
    print("📁 Files created:")
    print("   - ml_models/ml_model_params_*.txt (safe parameters)")
    print("   - ml_models/ML_DISABLE_INSTRUCTIONS.txt")
    print("   - ml_models/ML_RECOVERY_PLAN.txt")
    print()
    print("🆘 If you need immediate help:")
    print("   - Disable ML in your EA immediately")
    print("   - Use conservative risk management")
    print("   - Test all changes on demo first")
    print()
    print("💡 Remember: It's better to have a simple, profitable strategy")
    print("   than a complex, losing one.")

if __name__ == "__main__":
    main() 