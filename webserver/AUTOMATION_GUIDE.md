# Automated Trading Workflow Guide

This guide explains how to use the `automated_trading_workflow.py` script to streamline your trading strategy development process.

## 🚀 Overview

The automated workflow script handles the complete process from running Strategy Tester to training ML models and updating EA parameters. This eliminates manual steps and reduces errors.

## 📋 Prerequisites

1. **MetaTrader 5** installed and configured
2. **Python** with required packages (pandas, numpy, scikit-learn, etc.)
3. **EA files** in the `Experts/` directory
4. **ML trainer** (`strategy_tester_ml_trainer.py`) in the `webserver/` directory

## 🔧 Setup Validation

Before running the workflow, validate your setup:

```bash
# List available EAs
python automated_trading_workflow.py --list-eas

# Validate setup
python automated_trading_workflow.py --validate
```

## 🎯 Basic Usage

### Complete Workflow (Recommended)

Run the entire process from Strategy Tester to ML training:

```bash
# Basic workflow
python automated_trading_workflow.py --ea SimpleBreakoutML_EA

# With custom settings
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --symbol EURUSD+ \
  --timeframe M5 \
  --start-date 2023.10.01 \
  --end-date 2023.12.31
```

### Individual Steps

Run specific parts of the workflow:

```bash
# Only analyze existing results
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --analyze-only

# Only train ML models
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --train-only

# Train with incremental learning
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --train-only --incremental
```

## ⚙️ Advanced Options

### Optimization Mode

Run optimization instead of single test:

```bash
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --optimize \
  --optimization-passes 20
```

### ML Training Options

```bash
# Use incremental learning (faster for large datasets)
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --incremental

# Disable separate buy/sell models (use combined model only)
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --no-separate-models

# Combine options
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --incremental \
  --no-separate-models
```

## 📊 Workflow Steps

The complete workflow consists of 4 main steps:

### 1. Strategy Tester Execution
- **Manual Step**: Configure and run Strategy Tester in MT5
- **Automated**: Script provides configuration guidance
- **Output**: ML data and trade results files

### 2. Results Analysis
- **Automated**: Script analyzes result files
- **Checks**: File integrity, data structure, file sizes
- **Output**: Analysis report

### 3. ML Model Training
- **Automated**: Runs the ML trainer
- **Features**: Separate buy/sell models, incremental learning
- **Output**: Trained models and parameter files

### 4. EA Parameter Update
- **Automated**: Copies parameter files to MT5
- **Features**: Currency pair-specific parameters
- **Output**: Updated EA ready for testing

## 🔄 Iteration Process

The typical iteration cycle:

```bash
# 1. Run complete workflow
python automated_trading_workflow.py --ea SimpleBreakoutML_EA

# 2. Review results in webserver/ml_models/
# 3. Adjust EA parameters if needed
# 4. Repeat with different settings

# Quick iteration (skip Strategy Tester)
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --train-only
```

## 📁 File Structure

The script expects this structure:

```
strategies-and-indicators/
├── Experts/
│   ├── SimpleBreakoutML_EA.mq5
│   └── StrategyTesterML_EA.mq5
├── webserver/
│   ├── automated_trading_workflow.py
│   ├── strategy_tester_ml_trainer.py
│   └── ml_models/
└── [MT5 Files Directory]/
    └── SimpleBreakoutML_EA/
        ├── SimpleBreakoutML_EA_ML_Data.json
        ├── SimpleBreakoutML_EA_Trade_Results.json
        └── SimpleBreakoutML_EA_Results.json
```

## 🛠️ Troubleshooting

### Common Issues

1. **MT5 Not Found**
   ```bash
   # Check MT5 installation
   python automated_trading_workflow.py --validate
   ```

2. **EA Not Found**
   ```bash
   # List available EAs
   python automated_trading_workflow.py --list-eas
   ```

3. **No Result Files**
   - Ensure `CollectMLData=true` in EA settings
   - Ensure `SaveTradeResults=true` in EA settings
   - Check MT5 Files directory path

4. **ML Training Fails**
   ```bash
   # Check data availability
   python strategy_tester_ml_trainer.py --check-data --ea SimpleBreakoutML_EA
   ```

### Debug Mode

For detailed debugging:

```bash
# Run with verbose output
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --validate

# Check individual components
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --analyze-only
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --train-only
```

## 💡 Best Practices

1. **Start Small**: Begin with short date ranges for quick iteration
2. **Validate First**: Always run `--validate` before full workflow
3. **Backup Data**: Keep copies of successful result files
4. **Monitor Resources**: Large optimizations can be resource-intensive
5. **Document Changes**: Keep notes of parameter changes and results

## 🎯 Example Workflows

### Quick Test
```bash
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --start-date 2023.12.01 \
  --end-date 2023.12.31
```

### Full Optimization
```bash
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --optimize \
  --optimization-passes 50 \
  --incremental
```

### Rapid Iteration
```bash
# Run Strategy Tester manually, then:
python automated_trading_workflow.py \
  --ea SimpleBreakoutML_EA \
  --train-only \
  --incremental
```

## 📈 Expected Output

Successful workflow completion shows:

```
🎉 Complete workflow finished successfully!
============================================================
✅ Strategy Tester completed
✅ Results analyzed
✅ ML models trained
✅ EA parameters updated

💡 Next steps:
   1. Review the ML training results in webserver/ml_models/
   2. Test the updated EA in Strategy Tester
   3. Repeat the workflow to iterate and improve
```

## 🔗 Related Scripts

- `strategy_tester_ml_trainer.py`: ML model training
- `test_trainer_fixes.py`: Test script for trainer fixes
- `clean_and_restart.py`: Clean up and restart workflow

## 📞 Support

If you encounter issues:

1. Run `--validate` to check setup
2. Check the troubleshooting section
3. Review error messages carefully
4. Ensure all prerequisites are met 