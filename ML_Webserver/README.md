# ML WebServer - Complete Machine Learning System

This directory contains the complete machine learning system for automated trading, including model prediction, training, and live retraining capabilities.

## 🏗️ **System Architecture**

```
ML_Webserver/
├── ml_prediction_service.py     # Live prediction API (Flask)
├── live_retraining_service.py   # Automatic model retraining
├── improved_ml_trainer.py       # Model training engine
├── ml_models/                   # Model storage (213 models)
├── start_live_retraining.sh     # Startup script
├── live_retraining_config.json  # Configuration
└── README.md                    # This file
```

## 🚀 **Services**

### 1. **ML Prediction Service** (`ml_prediction_service.py`)
- **Purpose**: Real-time ML predictions for EAs
- **Port**: 5003
- **Features**:
  - Web-based model serving (no MT5 dependencies)
  - 24 universal features
  - Support for 7 symbols across multiple timeframes
  - Automatic model selection

### 2. **Live Retraining Service** (`live_retraining_service.py`)
- **Purpose**: Automatic model improvement from live trade data
- **Features**:
  - Background retraining every 24 hours
  - Performance-based retraining triggers
  - Model backup system
  - Multi-symbol support

### 3. **ML Trainer** (`improved_ml_trainer.py`)
- **Purpose**: Model training and retraining engine
- **Features**:
  - Time series validation
  - Feature engineering
  - Buy/Sell/Combined models
  - Universal 24-feature support

## 📊 **Model Inventory**

| Symbol | Models | Timeframes | Status |
|--------|--------|------------|---------|
| **BTCUSD** | 39 | H1, H4, M5, M15, M30 | ✅ Complete |
| **EURUSD** | 18 | H1, M15 | ✅ Complete |
| **XAUUSD+** | 33 | H1, M15 | ✅ Complete |
| **GBPUSD+** | 33 | H1, M15 | ✅ Complete |
| **USDJPY+** | 27 | H1, M15 | ✅ Complete |
| **ETHUSD** | 27 | H1, M15 | ✅ Complete |
| **USDCAD+** | 36 | H1, M15 | ✅ Complete |

**Total: 213 model files**

## 🛠️ **Quick Start**

### 1. **Start Analytics Server** (Required)
```bash
cd ../analytics
nohup python app.py > analytics_server.log 2>&1 &
```

### 2. **Start ML Prediction Service**
```bash
cd ML_Webserver
nohup python ml_prediction_service.py > ml_prediction.log 2>&1 &
```

### 3. **Start Live Retraining Service**
```bash
cd ML_Webserver
./start_live_retraining.sh
```

## 📋 **Management Commands**

### **Live Retraining Service**
```bash
# Check status
python live_retraining_service.py --status

# Manual retraining
python live_retraining_service.py --manual-retrain XAUUSD+_H1

# Check all models
python live_retraining_service.py --check-all

# Stop service
python live_retraining_service.py --stop
```

### **ML Prediction Service**
```bash
# Health check
curl http://127.0.0.1:5003/health

# Get prediction
curl -X POST http://127.0.0.1:5003/predict \
  -H "Content-Type: application/json" \
  -d '{"symbol": "XAUUSD+", "timeframe": "H1", "features": {...}}'
```

## ⚙️ **Configuration**

### **Live Retraining Config** (`live_retraining_config.json`)
```json
{
  "analytics_url": "http://127.0.0.1:5001",
  "models_dir": "ml_models",
  "retraining_interval_hours": 24,
  "min_trades_for_retraining": 50,
  "performance_threshold": 0.55,
  "backup_models": true,
  "symbols": ["XAUUSD+", "EURUSD", "GBPUSD+", "USDJPY+", "USDCAD+", "BTCUSD", "ETHUSD"],
  "timeframes": ["H1", "M15", "M30", "M5"]
}
```

## 🔧 **Model Training**

### **Manual Training**
```bash
# Train specific symbol/timeframe
python improved_ml_trainer.py --symbol XAUUSD+ --timeframe H1

# Train all models
python improved_ml_trainer.py --all-symbols
```

### **Live Retraining**
The system automatically:
1. **Monitors model performance** from live trades
2. **Triggers retraining** when performance < 55%
3. **Backs up old models** before updating
4. **Deploys new models** seamlessly

## 📈 **Performance Monitoring**

### **Model Performance**
- **Accuracy Threshold**: 55% (configurable)
- **Retraining Trigger**: Performance drops below threshold
- **Data Requirements**: Minimum 50 closed trades
- **Backup Strategy**: Automatic before retraining

### **System Health**
```bash
# Check all services
curl http://127.0.0.1:5001/health  # Analytics
curl http://127.0.0.1:5003/health  # ML Prediction
python live_retraining_service.py --status  # Retraining
```

## 🔄 **Data Flow**

1. **EAs** → Send trade data to **Analytics Server** (port 5001)
2. **Analytics Server** → Stores data in MySQL database
3. **Live Retraining Service** → Monitors performance & triggers retraining
4. **ML Trainer** → Retrains models with new data
5. **ML Prediction Service** → Serves updated models (port 5003)
6. **EAs** → Get predictions from updated models

## 🛡️ **Safety Features**

- **Model Backups**: Automatic before retraining
- **Performance Validation**: Only deploy if improved
- **Error Handling**: Graceful degradation
- **Logging**: Comprehensive audit trail
- **Configuration**: External JSON files

## 📝 **Logs**

- **ML Prediction**: `ml_prediction.log`
- **Live Retraining**: `live_retraining.log`
- **Analytics Server**: `analytics_server.log`

## 🚨 **Troubleshooting**

### **Common Issues**

1. **Analytics Server Not Running**
   ```bash
   cd ../analytics && python app.py
   ```

2. **Model Not Found**
   ```bash
   # Check model files
   ls ml_models/*XAUUSD*_PERIOD_H1.pkl
   ```

3. **Retraining Not Triggering**
   ```bash
   # Check trade data
   python live_retraining_service.py --status
   ```

4. **Import Errors**
   ```bash
   # Ensure all files are in ML_Webserver directory
   ls -la *.py
   ```

## 🎯 **Next Steps**

- **Option D**: Advanced ML Features (ensemble models, feature selection)
- **Production Deployment**: Docker containers, load balancing
- **Monitoring Dashboard**: Web-based performance monitoring
- **Alert System**: Email/SMS notifications for model issues

---

**Status**: ✅ Production Ready
**Last Updated**: 2025-07-30
**Version**: 1.0.0
