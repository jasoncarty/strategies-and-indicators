# 🤖 ML Training Automation System

## Overview

This automation system creates a complete pipeline for multi-symbol ML trading, from strategy testing to model deployment. It removes hardcoded symbols, automates strategy testing, trains ML models with 29 features, and deploys everything to the correct MT5 directories.

## 🎯 Features

- **Multi-Symbol Support**: Forex, Crypto, Commodities
- **Automated Strategy Testing**: Batch testing across symbols and timeframes
- **29-Feature ML Training**: Uses the complete feature set from `improved_ml_trainer.py`
- **Automated Deployment**: Deploys models to correct MT5 directories
- **Continuous Monitoring**: Watches for new test data and retrains automatically
- **Symbol-Agnostic EAs**: Removes hardcoded currency pairs

## 📁 File Structure

```
strategies-and-indicators/
├── automate_ml_training.py          # Main automation script
├── remove_hardcoded_symbols.py      # Symbol cleaning script
├── ml_automation_config.json        # Configuration file
├── ML_AUTOMATION_README.md          # This file
├── webserver/
│   ├── improved_ml_trainer.py       # 29-feature ML trainer
│   └── ml_models/                   # Trained models
└── Strategies/
    └── BreakoutStrategy/
        └── BreakoutStrategy_ML.mq5  # Symbol-agnostic EA
```

## 🚀 Quick Start

### 1. Clean Hardcoded Symbols

```bash
python remove_hardcoded_symbols.py
```

This removes hardcoded currency pairs from all EA files and makes them symbol-agnostic.

### 2. Run Full Automation Pipeline

```bash
# Test specific symbols
python automate_ml_training.py --symbols EURUSD,GBPUSD,XAUUSD,BTCUSD

# Test all configured symbols
python automate_ml_training.py

# Run in continuous monitoring mode
python automate_ml_training.py --monitor
```

### 3. Monitor for New Data

```bash
# Check every 5 minutes for new strategy test data
python automate_ml_training.py --monitor --interval 300
```

## 📊 Supported Symbols

### Forex Majors
- EURUSD+, GBPUSD+, USDJPY+, AUDUSD+, USDCAD+, NZDUSD+

### Forex Minors
- EURGBP+, EURJPY+, GBPJPY+, AUDCAD+, AUDNZD+, CADJPY+

### Commodities
- XAUUSD+, XAGUSD+, OILUSD+

### Crypto (Weekend Trading)
- BTCUSD+, ETHUSD+, LTCUSD+, XRPUSD+, ADAUSD+, DOTUSD+

## ⏰ Supported Timeframes

- M5, M15, M30, H1, H4

## 🔧 Configuration

Edit `ml_automation_config.json` to customize:

```json
{
  "symbols": {
    "forex_majors": ["EURUSD+", "GBPUSD+", ...],
    "crypto": ["BTCUSD+", "ETHUSD+", ...]
  },
  "timeframes": ["M5", "M15", "M30", "H1", "H4"],
  "strategy_testing": {
    "start_date": "2023.01.01",
    "end_date": "2024.12.31",
    "optimization": "genetic"
  }
}
```

## 📈 ML Features (29 Total)

### Base Features (18)
- rsi, stoch_main, stoch_signal, macd_main, macd_signal
- bb_upper, bb_lower, adx, williams_r, cci, momentum
- volume_ratio, price_change, volatility, force_index
- spread, session_hour, is_news_time

### Engineered Features (11)
- rsi_regime, stoch_regime, volatility_regime
- hour, day_of_week, month, session
- is_london_session, is_ny_session, is_asian_session, is_session_overlap

## 🔄 Automation Pipeline

### Step 1: Strategy Testing
1. Creates batch file for MT5 Strategy Tester
2. Tests `SimpleBreakoutML_EA` across all symbols/timeframes
3. Saves data to `MT5_Common_Files/SimpleBreakoutML_EA/{Symbol}_{test_run_id}_{timeframe}`

### Step 2: Data Monitoring
1. Monitors for new `*_ML_Data.json` files
2. Detects when new strategy test data is available
3. Triggers ML training pipeline

### Step 3: ML Training
1. Uses `improved_ml_trainer.py` with 29 features
2. Trains timeframe-specific and symbol-specific models
3. Generates model files (.pkl) and parameter files (.txt)

### Step 4: Model Deployment
1. Creates directory structure: `Models/BreakoutStrategy/{Symbol}/{Timeframe}/`
2. Copies model files to correct locations
3. Creates feature files with 29 features
4. Copies parameter files to `BreakoutStrategy/` directory

## 📋 Directory Structure After Deployment

```
MT5_Common_Files/
├── Models/
│   └── BreakoutStrategy/
│       ├── EURUSD/
│       │   ├── H1/
│       │   │   ├── buy_model_improved.pkl
│       │   │   ├── sell_model_improved.pkl
│       │   │   ├── buy_feature_names_EURUSD_PERIOD_H1.pkl
│       │   │   └── ...
│       │   ├── H4/
│       │   └── ...
│       ├── XAUUSD/
│       └── BTCUSD/
└── BreakoutStrategy/
    ├── ml_model_params_EURUSD_PERIOD_H1.txt
    ├── ml_model_params_XAUUSD_PERIOD_H1.txt
    └── ...
```

## 🎮 Usage Examples

### Single Run (All Symbols)
```bash
python automate_ml_training.py
```

### Specific Symbols Only
```bash
python automate_ml_training.py --symbols EURUSD,XAUUSD,BTCUSD
```

### Custom Timeframes
```bash
python automate_ml_training.py --timeframes M15,H1,H4
```

### Continuous Monitoring
```bash
# Check every 10 minutes
python automate_ml_training.py --monitor --interval 600
```

### Weekend Crypto Testing
```bash
# Test only crypto symbols (weekend trading)
python automate_ml_training.py --symbols BTCUSD,ETHUSD,LTCUSD,XRPUSD
```

## 🔍 Monitoring and Logs

### Log Files
- `ml_automation.log`: Main automation log
- `processed_files_cache.json`: Tracks processed data files

### Log Levels
- INFO: Normal operations
- WARNING: Issues that don't stop execution
- ERROR: Critical failures

### Example Log Output
```
2024-01-15 10:00:00 - INFO - 🚀 ML Training Automation initialized
2024-01-15 10:00:01 - INFO - 📁 Found MT5 directory: /path/to/MT5
2024-01-15 10:00:02 - INFO - 🆕 Found 3 new data files
2024-01-15 10:00:03 - INFO - 🤖 Training ML models for 3 data files
2024-01-15 10:00:15 - INFO - ✅ ML training completed successfully
2024-01-15 10:00:16 - INFO - 📦 Deploying models to MT5 directories
2024-01-15 10:00:20 - INFO - ✅ Model deployment completed
```

## 🛠️ Troubleshooting

### Common Issues

1. **MT5 Directory Not Found**
   - Check `ml_automation_config.json` paths
   - Verify MT5 installation location

2. **ML Training Fails**
   - Check Python dependencies: `pip install -r webserver/requirements.txt`
   - Verify data files exist in MT5 Common Files

3. **Permission Errors**
   - Ensure write access to MT5 Common Files directory
   - Run as administrator if needed

4. **Symbol Not Found**
   - Verify symbol names include '+' suffix (e.g., "EURUSD+")
   - Check broker symbol availability

### Debug Mode
```bash
# Enable verbose logging
export PYTHONPATH=.
python -u automate_ml_training.py --debug
```

## 🔄 Integration with BreakoutStrategy_ML

The automation system prepares everything needed for the `BreakoutStrategy_ML.mq5` EA:

1. **Models**: Trained ML models in correct directories
2. **Parameters**: Symbol-specific parameter files
3. **Features**: 29-feature files for each symbol/timeframe
4. **Symbol-Agnostic**: EA works with any symbol

### EA Configuration
```mql5
// In BreakoutStrategy_ML.mq5
input bool UseML = true;                       // Use ML predictions
input string MLApiUrl = "http://127.0.0.1:5003"; // ML API server URL
input double MLMinConfidence = 0.30;           // Minimum ML confidence
input double MLMaxConfidence = 0.85;           // Maximum ML confidence
```

## 📈 Performance Optimization

### Strategy Testing
- Use genetic optimization for faster testing
- Test multiple timeframes in parallel
- Use appropriate date ranges (1-2 years)

### ML Training
- 29 features provide comprehensive market analysis
- Timeframe-specific models improve accuracy
- Symbol-specific models capture unique characteristics

### Deployment
- Automated file management reduces errors
- Consistent directory structure
- Backup and restore capabilities

## 🔮 Future Enhancements

1. **Web Dashboard**: Monitor automation status
2. **Email Alerts**: Notify when new models are ready
3. **Performance Tracking**: Track model accuracy over time
4. **Auto-Optimization**: Automatically adjust parameters
5. **Cloud Deployment**: Deploy to cloud servers

## 📞 Support

For issues or questions:
1. Check the log files for error details
2. Verify configuration in `ml_automation_config.json`
3. Ensure all dependencies are installed
4. Test with a single symbol first

---

**Happy Trading! 🚀📈**
