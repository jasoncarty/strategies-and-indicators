//+------------------------------------------------------------------+
//| ML_Testing_EA.mq5                                                 |
//| Simple EA for testing ML prediction service                       |
//| Requests predictions every 5 minutes and logs results             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Include ML interface and analytics
#include "../../Include/MLHttpInterface.mqh"
#include "../../Analytics/ea_http_analytics.mqh"

//--- Input parameters
input group "ML Configuration"
input string MLStrategyName = "ML_Testing_EA"; // ML Strategy name
input string MLApiUrl = "http://127.0.0.1:5003"; // ML API server URL
input double MLMinConfidence = 0.30;           // Minimum ML confidence
input double MLMaxConfidence = 0.85;           // Maximum ML confidence
input int MLRequestTimeout = 5000;             // ML request timeout (ms)
input bool MLUseDirectionalModels = true;      // Use buy/sell specific models
input bool MLUseCombinedModels = true;         // Use combined models

input group "Testing Configuration"
input int TestIntervalMinutes = 5;             // Test interval in minutes
input bool EnableTrading = false;              // Enable actual trading (for safety)
input bool AllowMultipleSimultaneousOrders = false; // Allow multiple simultaneous orders
input double TestLotSize = 0.01;               // Lot size for test trades

input group "ATR-Based Stop Loss & Take Profit"
input bool UseATRStops = true;                 // Use ATR for dynamic stop loss/take profit
input int ATRPeriod = 14;                      // ATR period for calculation
input double ATRStopLossMultiplier = 2.0;      // ATR multiplier for stop loss
input double ATRTakeProfitMultiplier = 3.0;    // ATR multiplier for take profit
input double MinStopLossPips = 20;             // Minimum stop loss in pips (fallback)
input double MinTakeProfitPips = 40;           // Minimum take profit in pips (fallback)
input double MaxStopLossPips = 200;            // Maximum stop loss in pips (fallback)
input double MaxTakeProfitPips = 400;          // Maximum take profit in pips (fallback)

input group "Analytics Configuration"
// AnalyticsServerUrl is defined in ea_http_analytics.mqh

//--- Global variables
datetime lastTestTime = 0;
int testCount = 0;
int successCount = 0;
int errorCount = 0;

//--- Position tracking for closed position detection
ulong lastKnownPositionTicket = 0;
datetime lastPositionOpenTime = 0;
string lastTradeID = ""; // Store the trade ID for matching close

//--- Pending trade data for ML retraining
bool pendingTradeData = false;
MLPrediction pendingPrediction;
MLFeatures pendingFeatures;
string pendingDirection = "";
double pendingEntry = 0.0;
double pendingStopLoss = 0.0;
double pendingTakeProfit = 0.0;
double pendingLotSize = 0.0;

//--- ATR handle
int atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("🧪 ML Testing EA initialized");
    Print("   API URL: ", MLApiUrl);
    Print("   Test Interval: ", TestIntervalMinutes, " minutes");
    Print("   Trading Enabled: ", EnableTrading ? "Yes" : "No");
    Print("   Multiple Orders Allowed: ", AllowMultipleSimultaneousOrders ? "Yes" : "No");
    Print("   Symbol: ", _Symbol);
    Print("   Timeframe: ", EnumToString(_Period));

    // Debug symbol information
    Print("🔍 Symbol Information:");
    Print("   Point: ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 8));
    Print("   Digits: ", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
    Print("   Spread: ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID), 8));
    Print("   Bid: ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), 8));
    Print("   Ask: ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), 8));

    // Show dynamic stop calculation information
    Print("🔧 Stop Loss & Take Profit Configuration:");
    if(UseATRStops) {
        Print("   Method: ATR-based dynamic stops");
        Print("   ATR Period: ", ATRPeriod);
        Print("   Stop Loss Multiplier: ", ATRStopLossMultiplier);
        Print("   Take Profit Multiplier: ", ATRTakeProfitMultiplier);
        Print("   Min Stop Loss: ", MinStopLossPips, " pips (fallback)");
        Print("   Max Stop Loss: ", MaxStopLossPips, " pips (fallback)");
        Print("   Min Take Profit: ", MinTakeProfitPips, " pips (fallback)");
        Print("   Max Take Profit: ", MaxTakeProfitPips, " pips (fallback)");
    } else {
        Print("   Method: Fixed pip distances");
        Print("   Min Stop Loss: ", MinStopLossPips, " pips");
        Print("   Min Take Profit: ", MinTakeProfitPips, " pips");
    }
    Print("   Min Stop Distance: ", GetSymbolMinStopDistance(), " points (", DoubleToString(GetSymbolMinStopDistance() * SymbolInfoDouble(_Symbol, SYMBOL_POINT), _Digits), " price)");
    Print("   Min TP Distance: ", GetSymbolMinTpDistance(), " points (", DoubleToString(GetSymbolMinTpDistance() * SymbolInfoDouble(_Symbol, SYMBOL_POINT), _Digits), " price)");
    Print("   Broker Stops Level: ", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), " points");
    Print("   Broker Freeze Level: ", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL), " points");

    // Check historical data availability
    Print("🔍 Historical Data Check:");
    int bars = iBars(_Symbol, _Period);
    Print("   Available bars: ", bars);
    if(bars < 100) {
        Print("   ⚠️ Warning: Limited historical data available (", bars, " bars)");
        Print("   This may cause indicator calculation issues");
    }

    // Test indicator handles
    Print("🔍 Testing indicator handles:");
    int test_rsi = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
    int test_macd = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    int test_bb = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    Print("   RSI handle: ", test_rsi == INVALID_HANDLE ? "INVALID" : "OK");
    Print("   MACD handle: ", test_macd == INVALID_HANDLE ? "INVALID" : "OK");
    Print("   Bollinger Bands handle: ", test_bb == INVALID_HANDLE ? "INVALID" : "OK");

    // Initialize ATR handle for dynamic stop loss/take profit
    if(UseATRStops) {
        atrHandle = iATR(_Symbol, _Period, ATRPeriod);
        if(atrHandle == INVALID_HANDLE) {
            Print("❌ Failed to initialize ATR handle");
            return(INIT_FAILED);
        }
        Print("✅ ATR handle initialized successfully");
        Print("   ATR Period: ", ATRPeriod);
        Print("   Stop Loss Multiplier: ", ATRStopLossMultiplier);
        Print("   Take Profit Multiplier: ", ATRTakeProfitMultiplier);
    } else {
        Print("ℹ️ ATR-based stops disabled, using fixed pip distances");
    }

    // Initialize ML interface
    g_ml_interface.config.api_url = MLApiUrl;
    g_ml_interface.config.min_confidence = MLMinConfidence;
    g_ml_interface.config.max_confidence = MLMaxConfidence;
    g_ml_interface.config.prediction_timeout = MLRequestTimeout;
    g_ml_interface.config.use_directional_models = MLUseDirectionalModels;
    g_ml_interface.config.use_combined_models = MLUseCombinedModels;
    g_ml_interface.config.symbol = _Symbol;
    g_ml_interface.config.timeframe = EnumToString(_Period);
    g_ml_interface.config.strategy_name = MLStrategyName;

    if(!g_ml_interface.Initialize(MLStrategyName)) {
        Print("❌ Failed to initialize ML interface");
        Print("   Please ensure the ML API server is running on: ", MLApiUrl);
        return(INIT_FAILED);
    }

    Print("✅ ML interface initialized successfully");
    Print("   Strategy: ", MLStrategyName);
    Print("   Confidence range: ", MLMinConfidence, " - ", MLMaxConfidence);

    // Test connection immediately
    Print("🔍 Testing ML service connection...");
    bool connection_status = g_ml_interface.TestConnection();
    Print("   Connection status: ", connection_status ? "Connected" : "Failed");

    // Initialize HTTP analytics
    if(EnableHttpAnalytics) {
        InitializeHttpAnalytics(MLStrategyName + "_Testing", "1.00");
        Print("✅ HTTP Analytics system initialized");
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Create JSON string from MLFeatures for analytics                  |
//+------------------------------------------------------------------+
string CreateFeaturesJSON(MLFeatures &features) {
    string json = "{";
    json += "\"rsi\":" + DoubleToString(features.rsi, 6) + ",";
    json += "\"stoch_main\":" + DoubleToString(features.stoch_main, 6) + ",";
    json += "\"stoch_signal\":" + DoubleToString(features.stoch_signal, 6) + ",";
    json += "\"macd_main\":" + DoubleToString(features.macd_main, 6) + ",";
    json += "\"macd_signal\":" + DoubleToString(features.macd_signal, 6) + ",";
    json += "\"bb_upper\":" + DoubleToString(features.bb_upper, 6) + ",";
    json += "\"bb_lower\":" + DoubleToString(features.bb_lower, 6) + ",";
    json += "\"williams_r\":" + DoubleToString(features.williams_r, 6) + ",";
    json += "\"cci\":" + DoubleToString(features.cci, 6) + ",";
    json += "\"momentum\":" + DoubleToString(features.momentum, 6) + ",";
    json += "\"force_index\":" + DoubleToString(features.force_index, 6) + ",";
    json += "\"volume_ratio\":" + DoubleToString(features.volume_ratio, 6) + ",";
    json += "\"price_change\":" + DoubleToString(features.price_change, 6) + ",";
    json += "\"volatility\":" + DoubleToString(features.volatility, 6) + ",";
    json += "\"spread\":" + DoubleToString(features.spread, 6) + ",";
    json += "\"session_hour\":" + IntegerToString(features.session_hour) + ",";
    json += "\"day_of_week\":" + IntegerToString(features.day_of_week) + ",";
    json += "\"month\":" + IntegerToString(features.month);
    json += "}";

    return json;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("🛑 ML Testing EA deinitialized");
    Print("   Total tests: ", testCount);
    Print("   Successful: ", successCount);
    Print("   Errors: ", errorCount);
    Print("   Success rate: ", testCount > 0 ? DoubleToString((double)successCount / testCount * 100, 1) : "0", "%");

    // Clean up ATR handle
    if(atrHandle != INVALID_HANDLE) {
        IndicatorRelease(atrHandle);
        Print("✅ ATR handle released");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for closed positions and record analytics
    CheckForClosedPositions();

    // Check if it's time for a new test
    if(TimeCurrent() - lastTestTime >= TestIntervalMinutes * 60) {
        RunMLTest();
        lastTestTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Run ML prediction test                                           |
//+------------------------------------------------------------------+
void RunMLTest() {
    testCount++;
    Print("🧪 Running ML test #", testCount, " at ", TimeToString(TimeCurrent()));

    // Collect market features
    MLFeatures features;
    CollectMarketFeatures(features);

    // Test buy prediction
    Print("📤 Requesting BUY prediction...");
    MLPrediction buyPrediction = g_ml_interface.GetPrediction(features, "buy");

    // Test sell prediction
    Print("📤 Requesting SELL prediction...");
    MLPrediction sellPrediction = g_ml_interface.GetPrediction(features, "sell");

    // Log results
    LogPredictionResults("BUY", buyPrediction);
    LogPredictionResults("SELL", sellPrediction);

        // Analyze results
    AnalyzePredictions(buyPrediction, sellPrediction);

    // Record analytics data
    if(EnableHttpAnalytics) {
        RecordAnalyticsData(features, buyPrediction, sellPrediction);
    }

    // Execute test trade if enabled
    if(EnableTrading) {
        ExecuteTestTrade(buyPrediction, sellPrediction);
    }

    Print("✅ ML test #", testCount, " completed");
    Print("   Current success rate: ", DoubleToString((double)successCount / testCount * 100, 1), "%");
}

//+------------------------------------------------------------------+
//| Collect market features for ML prediction                        |
//+------------------------------------------------------------------+
void CollectMarketFeatures(MLFeatures &features) {
    Print("📊 Collecting market features...");

    // Technical indicators
    int rsi_handle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE) {
        Print("❌ Failed to create RSI indicator handle");
        features.rsi = 50.0;
    } else {
        double rsi_buffer[];
        ArraySetAsSeries(rsi_buffer, true);
        if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) <= 0) {
            Print("❌ Failed to copy RSI data");
            features.rsi = 50.0;
        } else {
            features.rsi = rsi_buffer[0];
        }
    }

    int stoch_handle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    if(stoch_handle == INVALID_HANDLE) {
        Print("❌ Failed to create Stochastic indicator handle");
        features.stoch_main = 50.0;
        features.stoch_signal = 50.0;
    } else {
        double stoch_main_buffer[], stoch_signal_buffer[];
        ArraySetAsSeries(stoch_main_buffer, true);
        ArraySetAsSeries(stoch_signal_buffer, true);
        if(CopyBuffer(stoch_handle, 0, 0, 1, stoch_main_buffer) <= 0 ||
           CopyBuffer(stoch_handle, 1, 0, 1, stoch_signal_buffer) <= 0) {
            Print("❌ Failed to copy Stochastic data");
            features.stoch_main = 50.0;
            features.stoch_signal = 50.0;
        } else {
            features.stoch_main = stoch_main_buffer[0];
            features.stoch_signal = stoch_signal_buffer[0];
        }
    }

    int macd_handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    if(macd_handle == INVALID_HANDLE) {
        Print("❌ Failed to create MACD indicator handle");
        features.macd_main = 0.0;
        features.macd_signal = 0.0;
    } else {
        double macd_main_buffer[], macd_signal_buffer[];
        ArraySetAsSeries(macd_main_buffer, true);
        ArraySetAsSeries(macd_signal_buffer, true);
        if(CopyBuffer(macd_handle, 0, 0, 1, macd_main_buffer) <= 0 ||
           CopyBuffer(macd_handle, 1, 0, 1, macd_signal_buffer) <= 0) {
            Print("❌ Failed to copy MACD data");
            features.macd_main = 0.0;
            features.macd_signal = 0.0;
        } else {
            features.macd_main = macd_main_buffer[0];
            features.macd_signal = macd_signal_buffer[0];
        }
    }

    // Bollinger Bands
    int bb_handle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    if(bb_handle == INVALID_HANDLE) {
        Print("❌ Failed to create Bollinger Bands indicator handle");
        features.bb_upper = 0.0;
        features.bb_lower = 0.0;
    } else {
        double bb_upper_buffer[], bb_lower_buffer[];
        ArraySetAsSeries(bb_upper_buffer, true);
        ArraySetAsSeries(bb_lower_buffer, true);
        if(CopyBuffer(bb_handle, 1, 0, 1, bb_upper_buffer) <= 0 ||
           CopyBuffer(bb_handle, 2, 0, 1, bb_lower_buffer) <= 0) {
            Print("❌ Failed to copy Bollinger Bands data");
            features.bb_upper = 0.0;
            features.bb_lower = 0.0;
        } else {
            features.bb_upper = bb_upper_buffer[0];
            features.bb_lower = bb_lower_buffer[0];
        }
    }

    // Additional indicators (note: adx is not used by the ML models)
    // Williams %R
    int williams_handle = iWPR(_Symbol, _Period, 14);
    if(williams_handle == INVALID_HANDLE) {
        Print("❌ Failed to create Williams %R indicator handle");
        features.williams_r = 50.0;
    } else {
        double williams_buffer[];
        ArraySetAsSeries(williams_buffer, true);
        if(CopyBuffer(williams_handle, 0, 0, 1, williams_buffer) <= 0) {
            Print("❌ Failed to copy Williams %R data");
            features.williams_r = 50.0;
        } else {
            features.williams_r = williams_buffer[0];
        }
    }

    int cci_handle = iCCI(_Symbol, _Period, 14, PRICE_TYPICAL);
    if(cci_handle == INVALID_HANDLE) {
        Print("❌ Failed to create CCI indicator handle");
        features.cci = 0.0;
    } else {
        double cci_buffer[];
        ArraySetAsSeries(cci_buffer, true);
        if(CopyBuffer(cci_handle, 0, 0, 1, cci_buffer) <= 0) {
            Print("❌ Failed to copy CCI data");
            features.cci = 0.0;
        } else {
            features.cci = cci_buffer[0];
        }
    }

    int momentum_handle = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);
    if(momentum_handle == INVALID_HANDLE) {
        Print("❌ Failed to create Momentum indicator handle");
        features.momentum = 100.0;
    } else {
        double momentum_buffer[];
        ArraySetAsSeries(momentum_buffer, true);
        if(CopyBuffer(momentum_handle, 0, 0, 1, momentum_buffer) <= 0) {
            Print("❌ Failed to copy Momentum data");
            features.momentum = 100.0;
        } else {
            features.momentum = momentum_buffer[0];
        }
    }

    // Market conditions
    long volume_array[];
    ArraySetAsSeries(volume_array, true);
    if(CopyTickVolume(_Symbol, _Period, 0, 2, volume_array) < 2) {
        Print("❌ Failed to copy volume data");
        features.volume_ratio = 1.0;
    } else {
        features.volume_ratio = (volume_array[0] > 0) ? (double)volume_array[0] / volume_array[1] : 1.0;
    }

    double close_array[];
    ArraySetAsSeries(close_array, true);
    if(CopyClose(_Symbol, _Period, 0, 2, close_array) < 2) {
        Print("❌ Failed to copy close price data");
        features.price_change = 0.0;
        features.volatility = 0.001;
    } else {
        features.price_change = (close_array[0] - close_array[1]) / close_array[1];
        // Calculate volatility as price change percentage (since we're not using ATR)
        features.volatility = MathAbs(features.price_change);
    }

    features.spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Time-based features
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    features.session_hour = dt.hour;
    features.is_news_time = false;
    features.day_of_week = dt.day_of_week;
    features.month = dt.mon;

    // Force Index calculation (manual implementation)
    if(volume_array[0] > 0 && close_array[1] != 0) {
        features.force_index = volume_array[0] * (close_array[0] - close_array[1]);
    } else {
        features.force_index = 0.0;
    }

    // Validate features
    ValidateFeatures(features);

    Print("✅ Features collected - RSI: ", DoubleToString(features.rsi, 2),
          ", MACD: ", DoubleToString(features.macd_main, 2),
          ", BB_Upper: ", DoubleToString(features.bb_upper, _Digits),
          ", Price Change: ", DoubleToString(features.price_change * 100, 3), "%");
}

//+------------------------------------------------------------------+
//| Validate and fix feature values                                  |
//+------------------------------------------------------------------+
void ValidateFeatures(MLFeatures &features) {
    if(!MathIsValidNumber(features.rsi) || !MathIsValidNumber(features.stoch_main) ||
       !MathIsValidNumber(features.stoch_signal) || !MathIsValidNumber(features.macd_main) ||
       !MathIsValidNumber(features.macd_signal) || !MathIsValidNumber(features.bb_upper) ||
       !MathIsValidNumber(features.bb_lower) || !MathIsValidNumber(features.williams_r) ||
       !MathIsValidNumber(features.cci) || !MathIsValidNumber(features.momentum) ||
       !MathIsValidNumber(features.volume_ratio) || !MathIsValidNumber(features.price_change) ||
       !MathIsValidNumber(features.volatility) || !MathIsValidNumber(features.force_index) ||
       !MathIsValidNumber(features.spread)) {

        Print("❌ Invalid feature values detected - using fallback values");
        Print("   RSI: ", features.rsi, " (valid: ", MathIsValidNumber(features.rsi), ")");
        Print("   Stoch Main: ", features.stoch_main, " (valid: ", MathIsValidNumber(features.stoch_main), ")");
        Print("   Stoch Signal: ", features.stoch_signal, " (valid: ", MathIsValidNumber(features.stoch_signal), ")");
        Print("   MACD Main: ", features.macd_main, " (valid: ", MathIsValidNumber(features.macd_main), ")");
        Print("   MACD Signal: ", features.macd_signal, " (valid: ", MathIsValidNumber(features.macd_signal), ")");
        Print("   BB Upper: ", features.bb_upper, " (valid: ", MathIsValidNumber(features.bb_upper), ")");
        Print("   BB Lower: ", features.bb_lower, " (valid: ", MathIsValidNumber(features.bb_lower), ")");
        Print("   Williams R: ", features.williams_r, " (valid: ", MathIsValidNumber(features.williams_r), ")");
        Print("   CCI: ", features.cci, " (valid: ", MathIsValidNumber(features.cci), ")");
        Print("   Momentum: ", features.momentum, " (valid: ", MathIsValidNumber(features.momentum), ")");
        Print("   Volume Ratio: ", features.volume_ratio, " (valid: ", MathIsValidNumber(features.volume_ratio), ")");
        Print("   Price Change: ", features.price_change, " (valid: ", MathIsValidNumber(features.price_change), ")");
        Print("   Volatility: ", features.volatility, " (valid: ", MathIsValidNumber(features.volatility), ")");
        Print("   Force Index: ", features.force_index, " (valid: ", MathIsValidNumber(features.force_index), ")");
        Print("   Spread: ", features.spread, " (valid: ", MathIsValidNumber(features.spread), ")");

        Print("⚠️ Invalid feature values detected - using fallback values");

        if(!MathIsValidNumber(features.rsi)) features.rsi = 50.0;
        if(!MathIsValidNumber(features.stoch_main)) features.stoch_main = 50.0;
        if(!MathIsValidNumber(features.stoch_signal)) features.stoch_signal = 50.0;
        if(!MathIsValidNumber(features.macd_main)) features.macd_main = 0.0;
        if(!MathIsValidNumber(features.macd_signal)) features.macd_signal = 0.0;
        if(!MathIsValidNumber(features.bb_upper)) features.bb_upper = 0.0;
        if(!MathIsValidNumber(features.bb_lower)) features.bb_lower = 0.0;
        if(!MathIsValidNumber(features.williams_r)) features.williams_r = 50.0;
        if(!MathIsValidNumber(features.cci)) features.cci = 0.0;
        if(!MathIsValidNumber(features.momentum)) features.momentum = 100.0;
        if(!MathIsValidNumber(features.volume_ratio)) features.volume_ratio = 1.0;
        if(!MathIsValidNumber(features.price_change)) features.price_change = 0.0;
        if(!MathIsValidNumber(features.volatility)) features.volatility = 0.001;
        if(!MathIsValidNumber(features.force_index)) features.force_index = 0.0;
        if(!MathIsValidNumber(features.spread)) features.spread = 1.0;
    }
}

//+------------------------------------------------------------------+
//| Log prediction results                                            |
//+------------------------------------------------------------------+
void LogPredictionResults(string direction, MLPrediction &prediction) {
    if(prediction.is_valid) {
        Print("✅ ", direction, " prediction successful:");
        Print("   Confidence: ", DoubleToString(prediction.confidence, 3));
        Print("   Probability: ", DoubleToString(prediction.probability, 3));
        Print("   Direction: ", prediction.direction);
        Print("   Model Type: ", prediction.model_type);
        Print("   Model Key: ", prediction.model_key);
        successCount++;
    } else {
        Print("❌ ", direction, " prediction failed:");
        Print("   Error: ", prediction.error_message);
        errorCount++;
    }
}

//+------------------------------------------------------------------+
//| Analyze predictions and make decisions                           |
//+------------------------------------------------------------------+
void AnalyzePredictions(MLPrediction &buyPrediction, MLPrediction &sellPrediction) {
    Print("📊 Analyzing predictions...");

    if(buyPrediction.is_valid && sellPrediction.is_valid) {
        // Compare predictions
        if(buyPrediction.confidence > sellPrediction.confidence) {
            Print("🎯 BUY signal stronger (", DoubleToString(buyPrediction.confidence, 3),
                  " vs ", DoubleToString(sellPrediction.confidence, 3), ")");

            if(g_ml_interface.IsSignalValid(buyPrediction)) {
                Print("✅ BUY signal meets confidence criteria");
            } else {
                Print("⚠️ BUY signal below confidence threshold");
            }
        } else if(sellPrediction.confidence > buyPrediction.confidence) {
            Print("🎯 SELL signal stronger (", DoubleToString(sellPrediction.confidence, 3),
                  " vs ", DoubleToString(buyPrediction.confidence, 3), ")");

            if(g_ml_interface.IsSignalValid(sellPrediction)) {
                Print("✅ SELL signal meets confidence criteria");
            } else {
                Print("⚠️ SELL signal below confidence threshold");
            }
        } else {
            Print("⚖️ Signals are equal - no clear direction");
        }
    } else {
        Print("⚠️ Cannot analyze - one or both predictions failed");
    }
}

//+------------------------------------------------------------------+
//| Execute test trade if enabled                                    |
//+------------------------------------------------------------------+
void ExecuteTestTrade(MLPrediction &buyPrediction, MLPrediction &sellPrediction) {
    if(!buyPrediction.is_valid || !sellPrediction.is_valid) {
        Print("⚠️ Skipping trade - predictions not valid");
        return;
    }

    // Check if we have open positions for this EA specifically
    Print("🔍 Checking position restriction before trade execution...");
    if(HasOpenPositionForThisEA()) {
        Print("⚠️ Skipping trade - position already open for this EA");
        return;
    }
    Print("✅ No existing positions found - proceeding with trade execution");

    // Determine best signal
    MLPrediction bestPrediction;
    string tradeDirection = "";

    if(buyPrediction.confidence > sellPrediction.confidence && g_ml_interface.IsSignalValid(buyPrediction)) {
        bestPrediction = buyPrediction;
        tradeDirection = "BUY";
    } else if(sellPrediction.confidence > buyPrediction.confidence && g_ml_interface.IsSignalValid(sellPrediction)) {
        bestPrediction = sellPrediction;
        tradeDirection = "SELL";
    } else {
        Print("⚠️ No valid trade signal");
        return;
    }

    // Execute trade
    Print("🚀 Executing ", tradeDirection, " test trade...");

    // Calculate dynamic stop loss and take profit based on symbol requirements
    double entry = (tradeDirection == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss, takeProfit;

    CalculateDynamicStops(entry, tradeDirection, stopLoss, takeProfit);

    Print("   Entry: ", DoubleToString(entry, _Digits));
    Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
    Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));

    // Validate stops before placing order
    if(!ValidateStops(entry, stopLoss, takeProfit, tradeDirection)) {
        Print("❌ Stop validation failed - skipping order placement");
        return;
    }

    // Use TradeUtils functions for robust order placement
    bool success = false;
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    if(tradeDirection == "BUY") {
        success = PlaceBuyOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    } else {
        success = PlaceSellOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    }

    if(success) {
        Print("✅ Test trade executed successfully");
        Print("   Direction: ", tradeDirection);
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   ML Confidence: ", DoubleToString(bestPrediction.confidence, 3));

        // Store trade data for ML retraining (will be logged when we have actual MT5 ticket)
        if(EnableHttpAnalytics) {
            MLFeatures features;
            CollectMarketFeatures(features);

            // Store pending trade data for later logging
            pendingTradeData = true;
            pendingPrediction = bestPrediction;
            pendingFeatures = features;
            pendingDirection = tradeDirection;
            pendingEntry = entry;
            pendingStopLoss = stopLoss;
            pendingTakeProfit = takeProfit;
            pendingLotSize = TestLotSize;

            Print("📊 Trade data stored for ML retraining (waiting for MT5 ticket)");
        }
    } else {
        Print("❌ Test trade failed - TradeUtils function returned false");
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic stop loss and take profit using ATR or fixed distances |
//+------------------------------------------------------------------+
void CalculateDynamicStops(double entry, string direction, double &stopLoss, double &takeProfit)
{
    // Get symbol information
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * point;

    // Get symbol-specific minimum distances
    double minStopDistance = GetSymbolMinStopDistance();
    double minTpDistance = GetSymbolMinTpDistance();

    double stopDistance, tpDistance;

    if(UseATRStops && atrHandle != INVALID_HANDLE) {
        // Use ATR-based calculations
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);

        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
            double currentATR = atrBuffer[0];

            // Calculate ATR-based distances
            double atrStopDistance = currentATR * ATRStopLossMultiplier;
            double atrTpDistance = currentATR * ATRTakeProfitMultiplier;

            // Convert pips to points for fallback calculations
            double pipsToPoints = (_Digits == 2) ? 100 : 10;
            double minStopPips = MinStopLossPips * pipsToPoints * point;
            double maxStopPips = MaxStopLossPips * pipsToPoints * point;
            double minTpPips = MinTakeProfitPips * pipsToPoints * point;
            double maxTpPips = MaxTakeProfitPips * pipsToPoints * point;

            // Use ATR with fallback limits
            stopDistance = MathMax(atrStopDistance, minStopPips);
            stopDistance = MathMin(stopDistance, maxStopPips);
            tpDistance = MathMax(atrTpDistance, minTpPips);
            tpDistance = MathMin(tpDistance, maxTpPips);

            Print("🔍 ATR-based calculations:");
            Print("   Current ATR: ", DoubleToString(currentATR, _Digits));
            Print("   ATR Stop Distance: ", DoubleToString(atrStopDistance, _Digits));
            Print("   ATR TP Distance: ", DoubleToString(atrTpDistance, _Digits));
            Print("   Final Stop Distance: ", DoubleToString(stopDistance, _Digits));
            Print("   Final TP Distance: ", DoubleToString(tpDistance, _Digits));
        } else {
            Print("⚠️ Failed to get ATR value, using fallback calculations");
            // Fallback to fixed pip distances
            double pipsToPoints = (_Digits == 2) ? 100 : 10;
            stopDistance = MathMax(MinStopLossPips * pipsToPoints * point, minStopDistance * point);
            tpDistance = MathMax(MinTakeProfitPips * pipsToPoints * point, minTpDistance * point);
        }
    } else {
        // Use fixed pip distances (fallback)
        double pipsToPoints = (_Digits == 2) ? 100 : 10;
        stopDistance = MathMax(MinStopLossPips * pipsToPoints * point, minStopDistance * point);
        tpDistance = MathMax(MinTakeProfitPips * pipsToPoints * point, minTpDistance * point);

        Print("🔍 Fixed pip-based calculations:");
        Print("   Min Stop Loss: ", MinStopLossPips, " pips");
        Print("   Min Take Profit: ", MinTakeProfitPips, " pips");
    }

    // Ensure minimum broker requirements are met
    stopDistance = MathMax(stopDistance, stopsLevel * 2); // 2x broker minimum for safety
    tpDistance = MathMax(tpDistance, stopsLevel * 2);

    // Ensure symbol-specific minimums are met
    stopDistance = MathMax(stopDistance, minStopDistance * point);
    tpDistance = MathMax(tpDistance, minTpDistance * point);

    Print("🔍 Debug - After broker requirements:");
    Print("   stopDistance: ", DoubleToString(stopDistance, _Digits), " price units");
    Print("   tpDistance: ", DoubleToString(tpDistance, _Digits), " price units");

    // Calculate final stop loss and take profit based on direction
    if(direction == "BUY") {
        stopLoss = NormalizeDouble(entry - stopDistance, _Digits);
        takeProfit = NormalizeDouble(entry + tpDistance, _Digits);
    } else {
        stopLoss = NormalizeDouble(entry + stopDistance, _Digits);
        takeProfit = NormalizeDouble(entry - tpDistance, _Digits);
    }

    Print("🔧 Final Stop Calculation:");
    Print("   Symbol: ", _Symbol);
    Print("   Direction: ", direction);
    Print("   Entry: ", DoubleToString(entry, _Digits));
    Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
    Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
    Print("   Stop Distance: ", DoubleToString(stopDistance, _Digits));
    Print("   TP Distance: ", DoubleToString(tpDistance, _Digits));
}

//+------------------------------------------------------------------+
//| Validate stop loss and take profit levels before order placement  |
//+------------------------------------------------------------------+
bool ValidateStops(double entry, double stopLoss, double takeProfit, string direction)
{
    double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    if(direction == "BUY") {
        if(stopLoss >= entry) {
            Print("❌ Validation failed: Stop loss (", DoubleToString(stopLoss, _Digits), ") >= Entry (", DoubleToString(entry, _Digits), ") for BUY");
            return false;
        }
        if(takeProfit <= entry) {
            Print("❌ Validation failed: Take profit (", DoubleToString(takeProfit, _Digits), ") <= Entry (", DoubleToString(entry, _Digits), ") for BUY");
            return false;
        }
        if((entry - stopLoss) < stopsLevel) {
            Print("❌ Validation failed: Stop loss too close for BUY. Distance: ", DoubleToString(entry - stopLoss, _Digits), " < Required: ", DoubleToString(stopsLevel, _Digits));
            return false;
        }
        if((takeProfit - entry) < stopsLevel) {
            Print("❌ Validation failed: Take profit too close for BUY. Distance: ", DoubleToString(takeProfit - entry, _Digits), " < Required: ", DoubleToString(stopsLevel, _Digits));
            return false;
        }
    } else {
        if(stopLoss <= entry) {
            Print("❌ Validation failed: Stop loss (", DoubleToString(stopLoss, _Digits), ") <= Entry (", DoubleToString(entry, _Digits), ") for SELL");
            return false;
        }
        if(takeProfit >= entry) {
            Print("❌ Validation failed: Take profit (", DoubleToString(takeProfit, _Digits), ") >= Entry (", DoubleToString(entry, _Digits), ") for SELL");
            return false;
        }
        if((stopLoss - entry) < stopsLevel) {
            Print("❌ Validation failed: Stop loss too close for SELL. Distance: ", DoubleToString(stopLoss - entry, _Digits), " < Required: ", DoubleToString(stopsLevel, _Digits));
            return false;
        }
        if((entry - takeProfit) < stopsLevel) {
            Print("❌ Validation failed: Take profit too close for SELL. Distance: ", DoubleToString(entry - takeProfit, _Digits), " < Required: ", DoubleToString(stopsLevel, _Digits));
            return false;
        }
    }

    Print("✅ Stop validation passed for ", direction, " order");
    return true;
}

//+------------------------------------------------------------------+
//| Get symbol-specific minimum stop loss distance in points          |
//+------------------------------------------------------------------+
double GetSymbolMinStopDistance()
{
    // Universal minimum stop distance: 20 pips
    // The pips-to-points conversion will handle different symbols automatically
    return 2000; // 20 pips × 100 = 2000 points for 2-digit symbols, 20 pips × 10 = 200 points for 5-digit symbols
}

//+------------------------------------------------------------------+
//| Get symbol-specific minimum take profit distance in points        |
//+------------------------------------------------------------------+
double GetSymbolMinTpDistance()
{
    // Universal minimum take profit distance: 40 pips
    // The pips-to-points conversion will handle different symbols automatically
    return 4000; // 40 pips × 100 = 4000 points for 2-digit symbols, 40 pips × 10 = 400 points for 5-digit symbols
}

//+------------------------------------------------------------------+
//| Place buy order with validation                                   |
//+------------------------------------------------------------------+
bool PlaceBuyOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Validate SL/TP for buy order
   if(sl >= ask) {
      Print("SL is not below entry price for buy");
      return false;
   }
   if(tp <= ask) {
      Print("TP is not above entry price for buy");
      return false;
   }
   if((ask - sl) < stopsLevel) {
      Print("SL too close to entry for buy");
      return false;
   }
   if((tp - ask) < stopsLevel) {
      Print("TP too close to entry for buy");
      return false;
   }

   // Place order
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult res; ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_BUY;
   req.price = ask;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 10;
   req.magic = magic;
   req.comment = comment;
   req.type_filling = ORDER_FILLING_IOC;

   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("Buy order failed: ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Place sell order with validation                                  |
//+------------------------------------------------------------------+
bool PlaceSellOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Validate SL/TP for sell order
   if(sl <= bid) {
      Print("SL is not above entry price for sell");
      return false;
   }
   if(tp >= bid) {
      Print("TP is not below entry price for sell");
      return false;
   }
   if((sl - bid) < stopsLevel) {
      Print("SL too close to entry for sell");
      return false;
   }
   if((bid - tp) < stopsLevel) {
      Print("TP too close to entry for sell");
      return false;
   }

   // Place order
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult res; ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_SELL;
   req.price = bid;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 10;
   req.magic = magic;
   req.comment = comment;
   req.type_filling = ORDER_FILLING_IOC;

   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("Sell order failed: ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment);
      return false;
   }
       return true;
}

// Note: Trade logging functions moved to MLHttpInterface.mqh to avoid duplication

//+------------------------------------------------------------------+
//| Record analytics data for ML testing                              |
//+------------------------------------------------------------------+
void RecordAnalyticsData(MLFeatures &features, MLPrediction &buyPrediction, MLPrediction &sellPrediction) {
    Print("📊 Recording analytics data...");

    // Record ML predictions (general, no trade required)
    if(buyPrediction.is_valid) {
        string features_json = g_ml_interface.CreateFeatureJSON(features, "BUY");
        RecordGeneralMLPrediction("buy_model_test", "buy", buyPrediction.probability, buyPrediction.confidence, features_json);
        Print("   ✅ Recorded BUY prediction analytics");
    }

    if(sellPrediction.is_valid) {
        string features_json = g_ml_interface.CreateFeatureJSON(features, "SELL");
        RecordGeneralMLPrediction("sell_model_test", "sell", sellPrediction.probability, sellPrediction.confidence, features_json);
        Print("   ✅ Recorded SELL prediction analytics");
    }

    // Record market conditions (general, no trade required)
    RecordGeneralMarketConditions(features);
    Print("   ✅ Recorded market conditions analytics");
}

//+------------------------------------------------------------------+
//| Generate unique trade ID for this strategy (overrides header)    |
//+------------------------------------------------------------------+
string GenerateMLTestingTradeID() {
    // Use MT5 position ticket as trade ID for consistency
    // This will be set when a position is opened
    return "0"; // Placeholder - will be replaced with actual ticket
}

//+------------------------------------------------------------------+
//| Expert trade event - called when trade operations occur         |
//+------------------------------------------------------------------+
void OnTrade() {
    // Position tracking is now handled by OnTradeTransaction() which is more reliable
    // This function is kept for backward compatibility but minimal logging only
    Print("🔄 OnTrade() event triggered - Symbol: ", _Symbol, ", Time: ", TimeToString(TimeCurrent()));
}

//+------------------------------------------------------------------+
//| Expert trade transaction event - called for each trade operation |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    Print("🔄 OnTradeTransaction() called - Transaction type: ", EnumToString(trans.type));
    Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);

    // Check if this is a position opening transaction
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0 && lastKnownPositionTicket == 0) {
        Print("🔍 Potential position opening transaction detected - Position: ", trans.position);

        // Verify this is our position by checking the deal
        if(HistoryDealSelect(trans.deal)) {
            string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
            string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            string ea_identifier = GenerateEAIdentifier();
            ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

            Print("🔍 Deal symbol: ", deal_symbol, ", Comment: ", deal_comment);
            Print("🔍 EA identifier: ", ea_identifier);
            Print("🔍 Deal entry type: ", EnumToString(deal_entry));

            if(deal_symbol == _Symbol && StringFind(deal_comment, ea_identifier) >= 0 && deal_entry == DEAL_ENTRY_IN) {
                Print("✅ Position opening confirmed for this EA - Ticket: ", trans.position);
                lastKnownPositionTicket = trans.position;
                lastPositionOpenTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

                // Set the trade ID to the MT5 position ticket for consistency
                if(lastTradeID == "" || lastTradeID == "0") {
                    lastTradeID = IntegerToString(trans.position);
                    Print("✅ Set trade ID to MT5 position ticket: ", lastTradeID);

                    // Also set the analytics trade ID
                    SetTradeIDFromTicket(trans.position);

                    // Record trade entry analytics now that we have the actual position ticket
                    if(EnableHttpAnalytics) {
                        Print("📊 Recording trade entry analytics...");
                        // Get position details for analytics
                        double entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                        double lot_size = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                        string direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";

                        // For now, use placeholder values for SL/TP (can be enhanced later)
                        double stop_loss = 0.0;
                        double take_profit = 0.0;

                        RecordTradeEntry(direction, entry_price, stop_loss, take_profit, lot_size, MLStrategyName + "_Testing", "1.00");
                        Print("✅ Recorded trade entry analytics");
                    }

                    // Log trade data for ML retraining now that we have the actual MT5 ticket
                    if(pendingTradeData) {
                        Print("📊 Logging trade data for ML retraining with actual MT5 ticket: ", lastTradeID);
                        g_ml_interface.LogTradeForRetraining(lastTradeID, pendingDirection, pendingEntry, pendingStopLoss, pendingTakeProfit, pendingLotSize, pendingPrediction, pendingFeatures);
                        Print("✅ Trade data logged for ML retraining");

                        // Clear pending trade data
                        pendingTradeData = false;
                    }
                }

                Print("🔄 Updated position tracking - Ticket: ", lastKnownPositionTicket, ", Time: ", TimeToString(lastPositionOpenTime));
                Print("🔄 Trade ID for this position: ", lastTradeID);
            } else {
                Print("❌ Deal does not match this EA or is not an entry deal - skipping");
                Print("   Symbol match: ", deal_symbol == _Symbol ? "true" : "false");
                Print("   Comment match: ", StringFind(deal_comment, ea_identifier) >= 0 ? "true" : "false");
                Print("   Entry type: ", deal_entry == DEAL_ENTRY_IN ? "true" : "false");
            }
        } else {
            Print("❌ Could not select deal for position opening check: ", trans.deal);
        }
    }

    // Check if this is a position close transaction
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position == lastKnownPositionTicket && lastKnownPositionTicket != 0) {
        Print("✅ Position close transaction detected for our tracked position!");

        // Get the closing deal details
        if(HistoryDealSelect(trans.deal)) {
            ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

            // Only process if this is actually a closing deal
            if(deal_entry == DEAL_ENTRY_OUT) {
                double close_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                datetime close_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
                ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
                ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

                Print("🔍 Deal details - Price: ", DoubleToString(close_price, _Digits), ", Profit: $", DoubleToString(profit, 2), ", Time: ", TimeToString(close_time));
                Print("🔍 Deal type: ", EnumToString(deal_type), ", Entry: ", EnumToString(deal_entry));

                // Calculate profit/loss in pips
                double profitLossPips = 0.0;
                if(profit != 0) {
                    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                    profitLossPips = profit / (pointValue * 10); // Convert to pips
                }

                Print("✅ Position closed detected via OnTradeTransaction - P&L: $", DoubleToString(profit, 2), " (", DoubleToString(profitLossPips, 1), " pips)");

                // Record trade exit analytics (if enabled)
                if(EnableHttpAnalytics) {
                    Print("📊 Recording trade exit analytics...");
                    RecordTradeExit(close_price, profit, profitLossPips);
                    Print("📊 Recorded trade exit analytics - P&L: $", DoubleToString(profit, 2), " (", DoubleToString(profitLossPips, 1), " pips)");
                } else {
                    Print("⚠️ HTTP Analytics disabled - skipping trade exit recording");
                }

                // Always log trade close for ML retraining
                Print("📊 Logging trade close for ML retraining...");
                Print("🔍 Using stored trade ID: ", lastTradeID);
                g_ml_interface.LogTradeCloseForRetraining(lastTradeID, close_price, profit, profitLossPips, close_time);
                Print("✅ Trade close logged for ML retraining");

                // Reset position tracking
                lastKnownPositionTicket = 0;
                lastPositionOpenTime = 0;
                lastTradeID = ""; // Clear the trade ID
                pendingTradeData = false; // Clear pending trade data
                Print("🔄 Reset position tracking variables");
            } else {
                Print("❌ Deal is not a closing deal (entry type: ", EnumToString(deal_entry), ")");
            }
        } else {
            Print("❌ Could not select deal: ", trans.deal);
        }
    }
}

//+------------------------------------------------------------------+
//| Generate unique EA identifier for position filtering              |
//+------------------------------------------------------------------+
string GenerateEAIdentifier() {
    // EnumToString(_Period) already returns "PERIOD_H1", "PERIOD_M15", etc.
    // So we don't need to add "PERIOD_" prefix
    return MLStrategyName + "_" + _Symbol + "_" + EnumToString(_Period);
}

//+------------------------------------------------------------------+
//| Check if we have an open position for this EA                    |
//+------------------------------------------------------------------+
bool HasOpenPositionForThisEA() {
    // If multiple simultaneous orders are allowed, don't check for existing positions
    if(AllowMultipleSimultaneousOrders) {
        Print("🔍 Multiple simultaneous orders allowed - skipping position check");
        return false;
    }

    // Get the number of open positions
    int total = PositionsTotal();
    string ea_identifier = GenerateEAIdentifier();

    Print("🔍 Checking for open positions - Total positions: ", total, ", EA Identifier: ", ea_identifier);

    // Iterate through all open positions
    for(int i = 0; i < total; i++) {
        // Get the position ticket
        ulong position_ticket = PositionGetTicket(i);

        // Check if the position is for our symbol
        if(PositionSelectByTicket(position_ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
                // Check if this position belongs to our EA by checking the comment
                string position_comment = PositionGetString(POSITION_COMMENT);

                Print("🔍 Position ", i, " - Symbol: ", PositionGetString(POSITION_SYMBOL), ", Comment: ", position_comment);

                // Enhanced filtering: Check for exact EA identifier match
                if(StringFind(position_comment, ea_identifier) >= 0) {
                    Print("✅ Found matching position - Ticket: ", position_ticket, ", Comment: ", position_comment);
                    // Position is still open (if it exists in PositionsTotal, it's open)
                    return true;
                }
            }
        }
    }

    Print("❌ No matching positions found for EA identifier: ", ea_identifier);
    return false;
}

//+------------------------------------------------------------------+
//| Check for closed positions using OnTrade event                  |
//+------------------------------------------------------------------+
void CheckForClosedPositionsOnTrade() {
    Print("🔍 CheckForClosedPositionsOnTrade() called - Symbol: ", _Symbol, ", EA: ", MLStrategyName);
    Print("🔍 Current lastKnownPositionTicket: ", lastKnownPositionTicket);
    Print("🔍 Current lastPositionOpenTime: ", TimeToString(lastPositionOpenTime));

    // Check if we had a position before but don't have one now
    if(lastKnownPositionTicket != 0) {
        Print("🔍 Checking if position ", lastKnownPositionTicket, " still exists...");

        // Check if our last known position still exists
        bool positionStillExists = false;
        int total = PositionsTotal();
        Print("🔍 Total open positions: ", total);

        for(int i = 0; i < total; i++) {
            ulong position_ticket = PositionGetTicket(i);
            Print("🔍 Checking position ", i, " - Ticket: ", position_ticket);
            if(position_ticket == lastKnownPositionTicket) {
                positionStillExists = true;
                Print("✅ Position ", lastKnownPositionTicket, " still exists");
                break;
            }
        }

                                // If position no longer exists, it was closed
        if(!positionStillExists) {
            Print("🚨 Position ", lastKnownPositionTicket, " no longer exists - checking position history...");

            // Try to get position history directly
            if(HistorySelectByPosition(lastKnownPositionTicket)) {
                Print("✅ Successfully selected position history for ticket: ", lastKnownPositionTicket);

                // Get the number of deals for this position
                int deals = HistoryDealsTotal();
                Print("🔍 Total deals for this position: ", deals);

                if(deals > 0) {
                    // Find the closing deal (should be the last one)
                    ulong closing_deal_ticket = HistoryDealGetTicket(deals - 1);
                    Print("🔍 Closing deal ticket: ", closing_deal_ticket);

                    // Get closing deal details
                    double close_price = HistoryDealGetDouble(closing_deal_ticket, DEAL_PRICE);
                    double profit = HistoryDealGetDouble(closing_deal_ticket, DEAL_PROFIT);
                    datetime close_time = (datetime)HistoryDealGetInteger(closing_deal_ticket, DEAL_TIME);
                    ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(closing_deal_ticket, DEAL_TYPE);
                    ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(closing_deal_ticket, DEAL_ENTRY);

                    Print("🔍 Deal details - Price: ", DoubleToString(close_price, _Digits), ", Profit: $", DoubleToString(profit, 2), ", Time: ", TimeToString(close_time));
                    Print("🔍 Deal type: ", EnumToString(deal_type), ", Entry: ", EnumToString(deal_entry));

                    // Calculate profit/loss in pips
                    double profitLossPips = 0.0;
                    if(profit != 0) {
                        double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                        profitLossPips = profit / (pointValue * 10); // Convert to pips
                    }

                    Print("✅ Position closed detected via OnTrade - P&L: $", DoubleToString(profit, 2), " (", DoubleToString(profitLossPips, 1), " pips)");

                    // Record trade exit analytics (if enabled)
                    if(EnableHttpAnalytics) {
                        Print("📊 Recording trade exit analytics...");
                        RecordTradeExit(close_price, profit, profitLossPips);
                        Print("📊 Recorded trade exit analytics - P&L: $", DoubleToString(profit, 2), " (", DoubleToString(profitLossPips, 1), " pips)");
                    } else {
                        Print("⚠️ HTTP Analytics disabled - skipping trade exit recording");
                    }

                    // Always log trade close for ML retraining
                    Print("📊 Logging trade close for ML retraining...");
                    string ea_identifier = GenerateEAIdentifier();
                    Print("🔍 Using EA identifier: ", ea_identifier);
                    g_ml_interface.LogTradeCloseForRetraining(ea_identifier, close_price, profit, profitLossPips, close_time);
                    Print("✅ Trade close logged for ML retraining");

                    // Reset position tracking
                    lastKnownPositionTicket = 0;
                    lastPositionOpenTime = 0;
                    Print("🔄 Reset position tracking variables");
                } else {
                    Print("❌ No deals found for position ", lastKnownPositionTicket, " - may need to wait for history to update");
                }
            } else {
                Print("❌ Could not select position history for ticket: ", lastKnownPositionTicket, " - may need to wait for history to update");
                // Don't reset position tracking yet - let it try again on next OnTrade call
            }
        }
    }

    // Track new positions
    Print("🔍 Tracking new positions...");
    int total = PositionsTotal();
    Print("🔍 Total open positions: ", total);

    for(int i = 0; i < total; i++) {
        ulong position_ticket = PositionGetTicket(i);
        Print("🔍 Checking position ", i, " - Ticket: ", position_ticket);

        if(PositionSelectByTicket(position_ticket)) {
            string position_symbol = PositionGetString(POSITION_SYMBOL);
            Print("🔍 Position symbol: ", position_symbol);

            if(position_symbol == _Symbol) {
                string position_comment = PositionGetString(POSITION_COMMENT);
                string ea_identifier = GenerateEAIdentifier();
                Print("🔍 Position comment: ", position_comment);
                Print("🔍 EA identifier: ", ea_identifier);
                Print("🔍 StringFind result: ", StringFind(position_comment, ea_identifier));

                if(StringFind(position_comment, ea_identifier) >= 0) {
                    Print("✅ Found matching position for this EA - Ticket: ", position_ticket);
                    lastKnownPositionTicket = position_ticket;
                    lastPositionOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
                    Print("🔄 Updated position tracking - Ticket: ", lastKnownPositionTicket, ", Time: ", TimeToString(lastPositionOpenTime));
                    break;
                } else {
                    Print("❌ Position comment does not match EA identifier");
                }
            } else {
                Print("❌ Position symbol does not match current symbol");
            }
        } else {
            Print("❌ Could not select position by ticket: ", position_ticket);
        }
    }

    Print("🔍 CheckForClosedPositionsOnTrade() completed");
}

//+------------------------------------------------------------------+
//| Check for closed positions and record analytics                  |
//+------------------------------------------------------------------+
void CheckForClosedPositions() {
    // This function is now deprecated in favor of OnTrade event
    // Keep it for backward compatibility but it won't be called
}
