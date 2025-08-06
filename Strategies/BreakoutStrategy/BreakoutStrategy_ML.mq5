//+------------------------------------------------------------------+
//| BreakoutStrategy_ML.mq5                                           |
//| Breakout strategy with ML integration                             |
//| Uses the same state machine as the original strategy             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Include base strategy functions and ML interface
#include "../../Include/BreakoutStrategy_Base.mqh"
#include "../../Include/MLHttpInterface.mqh"
#include "../../Analytics/ea_http_analytics.mqh"

//--- Input parameters
input double RiskPercent = 1.0;                // Risk per trade (% of balance)
input double RiskRewardRatio = 2.0;            // Risk:Reward ratio (2:1)
input int StopLossBuffer = 20;                 // Stop loss buffer in pips
input bool UseBreakoutFilter = true;           // Use breakout filter
input int BreakoutPeriod = 20;                 // Period for breakout detection
input double BreakoutThreshold = 0.001;        // Breakout threshold
input bool AllowMultipleSimultaneousOrders = false; // Allow multiple simultaneous orders

//--- ML Parameters
input group "ML Configuration"
input string MLStrategyName = "BreakoutStrategy"; // ML Strategy name
input bool UseML = true;                       // Use ML predictions
input string MLApiUrl = "http://127.0.0.1:5003"; // ML API server URL
input double MLMinConfidence = 0.30;           // Minimum ML confidence
input double MLMaxConfidence = 0.85;           // Maximum ML confidence
input int MLRequestTimeout = 5000;             // ML request timeout (ms)
input bool MLUseDirectionalModels = true;      // Use buy/sell specific models
input bool MLUseCombinedModels = true;         // Use combined models

//--- Analytics Parameters (defined in header file)

//--- Global variables (matching original strategy)
double previousDayHigh = 0.0;
double previousDayLow = 0.0;
double newDayLow = 0; // New day low established after bearish breakout
double newDayHigh = 0; // New day high established after bullish breakout
bool hasOpenPosition = false;
datetime lastDayCheck = 0;

//--- Position tracking for closed position detection
ulong lastKnownPositionTicket = 0;
datetime lastPositionOpenTime = 0;
string lastTradeID = ""; // Store the trade ID for matching close

//--- Analytics data storage for OnTradeTransaction
MLPrediction lastMLPrediction;
MLFeatures lastMarketFeatures;
string lastTradeDirection = "";

//--- Pending trade data for ML retraining
bool pendingTradeData = false;
MLPrediction pendingPrediction;
MLFeatures pendingFeatures;
string pendingDirection = "";
double pendingEntry = 0.0;
double pendingStopLoss = 0.0;
double pendingTakeProfit = 0.0;
double pendingLotSize = 0.0;

//--- State machine variables
BREAKOUT_STATE currentState = WAITING_FOR_BREAKOUT;
datetime lastStateChange = 0;
double breakoutLevel = 0.0;
string breakoutDirection = "";
double swingPoint = 0.0; // The swing high/low that created the retest

//--- Retest tracking variables
bool bullishRetestDetected = false;
double bullishRetestLow = 999999.0;
bool bearishRetestDetected = false;
double bearishRetestHigh = 0.0;

//--- Breakout tracking variables
double lastBreakoutLevel = 0.0;
string lastBreakoutDirection = "";
int retestBar = -1;
int breakoutBar = -1;
int barsSinceBreakout = 0;

//--- Chart objects for previous day levels
string prevDayHighLine = "PrevDayHigh";
string prevDayLowLine = "PrevDayLow";

//+------------------------------------------------------------------+
//| Check if it's a new bar                                           |
//+------------------------------------------------------------------+
bool IsNewBar() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, _Period, 0);

    if(currentBarTime != lastBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("🚀 BreakoutStrategy_ML initialized");
    Print("   Risk per trade: ", RiskPercent, "%");
    Print("   Risk:Reward ratio: ", RiskRewardRatio, ":1");
    Print("   Stop Loss Buffer: ", StopLossBuffer, " pips");
    Print("   ML Integration: ", UseML ? "Enabled" : "Disabled");

    // Initialize ML interface
    if(UseML) {
        // Configure ML interface with input parameters
        g_ml_interface.config.api_url = MLApiUrl;
        g_ml_interface.config.min_confidence = MLMinConfidence;
        g_ml_interface.config.max_confidence = MLMaxConfidence;
        g_ml_interface.config.prediction_timeout = MLRequestTimeout;
        g_ml_interface.config.use_directional_models = MLUseDirectionalModels;
        g_ml_interface.config.use_combined_models = MLUseCombinedModels;

        // Set symbol and timeframe
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
        Print("   API URL: ", MLApiUrl);
        Print("   Symbol: ", _Symbol);
        Print("   Timeframe: ", EnumToString(_Period));
        Print("   Confidence range: ", MLMinConfidence, " - ", MLMaxConfidence);
    }

    // Initialize HTTP analytics
    if(EnableHttpAnalytics) {
        InitializeHttpAnalytics(MLStrategyName + "_ML", "1.00");
        Print("✅ HTTP Analytics system initialized");
    }

    // Update previous day levels
    UpdatePreviousDayLevels();

    // Draw previous day levels on chart
    DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clear previous day level lines
    ClearPreviousDayLines(prevDayHighLine, prevDayLowLine);

    Print("🛑 BreakoutStrategy_ML deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for new day (keep this on every tick for accurate day detection)
    if(TimeCurrent() - lastDayCheck > 3600) { // Check every hour
        UpdatePreviousDayLevels();
        // Update chart lines when previous day levels change
        DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);
        lastDayCheck = TimeCurrent();
    }

    // Check for closed positions and record analytics (keep this on every tick)
    CheckForClosedPositions();

    // Only run main strategy logic on new candle close
    if(!IsNewBar()) {
        return; // Exit early if not a new candle
    }

    // Log new candle processing
    Print("🕯️ Processing new ", EnumToString(_Period), " candle at ", TimeToString(TimeCurrent()));

    // Process the state machine (only on new candle)
    ProcessBreakoutStateMachine();

    // Log current state for debugging
    LogCurrentState();

    // Check for trade signals with ML validation (only on new candle)
    CheckForTradeSignalsWithML();
}

//+------------------------------------------------------------------+
//| Check for trade signals with ML validation                       |
//+------------------------------------------------------------------+
void CheckForTradeSignalsWithML() {
    // Check if we have an open position for this EA specifically
    if(HasOpenPositionForThisEA()) return; // Don't open new positions if we have one

    // Check if we just completed a bullish confirmation
    if(currentState == WAITING_FOR_BREAKOUT && breakoutDirection == "bullish" && bullishRetestDetected) {
        Print("🔄 Bullish trade signal detected - validating with ML");

        if(UseML) {
            MLPrediction prediction = GetMLPrediction("buy");

            // Record ML prediction for analysis (regardless of whether trade is placed)
            if(prediction.is_valid && EnableHttpAnalytics) {
                MLFeatures features;
                CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "BUY");
                RecordGeneralMLPrediction("buy_model_improved", "buy", prediction.probability, prediction.confidence, features_json);
                Print("📊 Recorded BUY prediction for analysis");
            }

            if(g_ml_interface.IsSignalValid(prediction)) {
                Print("✅ ML validation passed - placing buy order");
                PlaceBuyOrderWithML(prediction);
            } else {
                Print("❌ ML validation failed - skipping trade");
            }
        } else {
            Print("🔄 ML disabled - placing buy order");
            PlaceBuyOrder();
        }

        ResetBreakoutStateVariables();
        bullishRetestDetected = false;
    }

    // Check if we just completed a bearish confirmation
    if(currentState == WAITING_FOR_BREAKOUT && breakoutDirection == "bearish" && bearishRetestDetected) {
        Print("🔄 Bearish trade signal detected - validating with ML");

        if(UseML) {
            MLPrediction prediction = GetMLPrediction("sell");

            // Record ML prediction for analysis (regardless of whether trade is placed)
            if(prediction.is_valid && EnableHttpAnalytics) {
                MLFeatures features;
                CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "SELL");
                RecordGeneralMLPrediction("sell_model_improved", "sell", prediction.probability, prediction.confidence, features_json);
                Print("📊 Recorded SELL prediction for analysis");
            }

            if(g_ml_interface.IsSignalValid(prediction)) {
                Print("✅ ML validation passed - placing sell order");
                PlaceSellOrderWithML(prediction);
            } else {
                Print("❌ ML validation failed - skipping trade");
            }
        } else {
            Print("🔄 ML disabled - placing sell order");
            PlaceSellOrder();
        }

        ResetBreakoutStateVariables();
        bearishRetestDetected = false;
    }
}

//+------------------------------------------------------------------+
//| Get ML prediction for current market conditions                  |
//+------------------------------------------------------------------+
MLPrediction GetMLPrediction(string direction) {
    // Validate ML interface configuration
    if(StringLen(g_ml_interface.config.api_url) == 0) {
        Print("❌ ML API URL not configured");
        MLPrediction error_prediction;
        error_prediction.is_valid = false;
        error_prediction.error_message = "ML API URL not configured";
        return error_prediction;
    }

    // Validate symbol and timeframe
    if(StringLen(_Symbol) == 0 || _Period == 0) {
        Print("❌ Invalid symbol or timeframe");
        MLPrediction error_prediction;
        error_prediction.is_valid = false;
        error_prediction.error_message = "Invalid symbol or timeframe";
        return error_prediction;
    }

    MLFeatures features;
    CollectMarketFeatures(features);

    return g_ml_interface.GetPrediction(features, direction);
}

//+------------------------------------------------------------------+
//| Collect market features for ML prediction                        |
//+------------------------------------------------------------------+
void CollectMarketFeatures(MLFeatures &features) {
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
        if(CopyBuffer(stoch_handle, 0, 0, 1, stoch_main_buffer) <= 0 || CopyBuffer(stoch_handle, 1, 0, 1, stoch_signal_buffer) <= 0) {
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
        if(CopyBuffer(macd_handle, 0, 0, 1, macd_main_buffer) <= 0 || CopyBuffer(macd_handle, 1, 0, 1, macd_signal_buffer) <= 0) {
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
        if(CopyBuffer(bb_handle, 1, 0, 1, bb_upper_buffer) <= 0 || CopyBuffer(bb_handle, 2, 0, 1, bb_lower_buffer) <= 0) {
            Print("❌ Failed to copy Bollinger Bands data");
            features.bb_upper = 0.0;
            features.bb_lower = 0.0;
        } else {
            features.bb_upper = bb_upper_buffer[0];
            features.bb_lower = bb_lower_buffer[0];
        }
    }

    // Additional indicators
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

    // CCI
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

    // Momentum
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
    features.is_news_time = false; // Can be enhanced with news data
    features.day_of_week = dt.day_of_week;
    features.month = dt.mon;

    // Force Index calculation (manual implementation)
    double high_array[], low_array[], close_array_force[];
    ArraySetAsSeries(high_array, true);
    ArraySetAsSeries(low_array, true);
    ArraySetAsSeries(close_array_force, true);

    if(CopyHigh(_Symbol, _Period, 0, 2, high_array) < 2 ||
       CopyLow(_Symbol, _Period, 0, 2, low_array) < 2 ||
       CopyClose(_Symbol, _Period, 0, 2, close_array_force) < 2) {
        Print("❌ Failed to copy price data for Force Index");
        features.force_index = 0.0;
    } else {
        // Force Index = Volume * (Current Close - Previous Close)
        if(volume_array[0] > 0 && close_array[1] != 0) {
            features.force_index = volume_array[0] * (close_array[0] - close_array[1]);
        } else {
            features.force_index = 0.0;
        }
    }

    // Validate all features to ensure they are valid numbers
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

        // Set fallback values for invalid features
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

    Print("✅ Feature collection completed - all features validated");
}

//+------------------------------------------------------------------+
//| Place buy order with ML adjustments                              |
//+------------------------------------------------------------------+
void PlaceBuyOrderWithML(MLPrediction &prediction) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calculate base stop loss based on new day low (original strategy logic)
    double baseStopLoss = CalculateBullishStopLoss(StopLossBuffer);

    // Apply ML adjustments
    double adjustedStopLoss = g_ml_interface.AdjustStopLoss(baseStopLoss, prediction, "buy");
    double stopDistance = entry - adjustedStopLoss;
    double takeProfit = CalculateTakeProfit(entry, adjustedStopLoss, RiskRewardRatio, "buy");

    // Calculate base lot size based on risk percentage
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Apply ML position sizing adjustments
    double adjustedLotSize = g_ml_interface.AdjustPositionSize(baseLotSize, prediction);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = PlaceBuyOrder(adjustedLotSize, adjustedStopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ ML-enhanced buy order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Base Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
        Print("   ML Adjusted Stop Loss: ", DoubleToString(adjustedStopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("   ML Adjusted Lot Size: ", DoubleToString(adjustedLotSize, 2));
        Print("   ML Prediction: ", DoubleToString(prediction.probability, 3));
        Print("   ML Confidence: ", DoubleToString(prediction.confidence, 3));
        hasOpenPosition = true;

        // Record analytics data
        if(EnableHttpAnalytics) {
            // Collect market features for ML retraining
            MLFeatures features;
            CollectMarketFeatures(features);

            // Store prediction data for later recording in OnTradeTransaction
            lastMLPrediction = prediction;
            lastMarketFeatures = features;
            lastTradeDirection = "BUY";

            // Store pending trade data for ML retraining (will be logged when we have actual MT5 ticket)
            pendingTradeData = true;
            pendingPrediction = prediction;
            pendingFeatures = features;
            pendingDirection = "BUY";
            pendingEntry = entry;
            pendingStopLoss = adjustedStopLoss;
            pendingTakeProfit = takeProfit;
            pendingLotSize = adjustedLotSize;

            Print("📊 Trade data stored for ML retraining (waiting for MT5 ticket)");
        }
    } else {
        Print("❌ ML-enhanced buy order failed");
    }
}

//+------------------------------------------------------------------+
//| Place sell order with ML adjustments                             |
//+------------------------------------------------------------------+
void PlaceSellOrderWithML(MLPrediction &prediction) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate base stop loss based on new day high (original strategy logic)
    double baseStopLoss = CalculateBearishStopLoss(StopLossBuffer);

    // Apply ML adjustments
    double adjustedStopLoss = g_ml_interface.AdjustStopLoss(baseStopLoss, prediction, "sell");
    double stopDistance = adjustedStopLoss - entry;
    double takeProfit = CalculateTakeProfit(entry, adjustedStopLoss, RiskRewardRatio, "sell");

    // Calculate base lot size based on risk percentage
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Apply ML position sizing adjustments
    double adjustedLotSize = g_ml_interface.AdjustPositionSize(baseLotSize, prediction);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = PlaceSellOrder(adjustedLotSize, adjustedStopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ ML-enhanced sell order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Base Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
        Print("   ML Adjusted Stop Loss: ", DoubleToString(adjustedStopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("   ML Adjusted Lot Size: ", DoubleToString(adjustedLotSize, 2));
        Print("   ML Prediction: ", DoubleToString(prediction.probability, 3));
        Print("   ML Confidence: ", DoubleToString(prediction.confidence, 3));
        hasOpenPosition = true;

        // Record analytics data
        if(EnableHttpAnalytics) {
            // Collect market features for ML retraining
            MLFeatures features;
            CollectMarketFeatures(features);

            // Store prediction data for later recording in OnTradeTransaction
            lastMLPrediction = prediction;
            lastMarketFeatures = features;
            lastTradeDirection = "SELL";

            // Store pending trade data for ML retraining (will be logged when we have actual MT5 ticket)
            pendingTradeData = true;
            pendingPrediction = prediction;
            pendingFeatures = features;
            pendingDirection = "SELL";
            pendingEntry = entry;
            pendingStopLoss = adjustedStopLoss;
            pendingTakeProfit = takeProfit;
            pendingLotSize = adjustedLotSize;

            Print("📊 Trade data stored for ML retraining (waiting for MT5 ticket)");
        }
    } else {
        Print("❌ ML-enhanced sell order failed");
    }
}

//+------------------------------------------------------------------+
//| Place buy order (fallback without ML)                           |
//+------------------------------------------------------------------+
void PlaceBuyOrder() {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calculate stop loss based on new day low (original strategy logic)
    double stopLoss = CalculateBullishStopLoss(StopLossBuffer);

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "buy");

    // Calculate lot size based on risk percentage
    double stopDistance = entry - stopLoss;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = PlaceBuyOrder(lotSize, stopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ Buy order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));
        hasOpenPosition = true;

        // Record analytics data (without ML)
        if(EnableHttpAnalytics) {
            // Record trade entry will be done in OnTradeTransaction when we have the actual position ticket
            // Record market conditions will be done in OnTradeTransaction when we have the actual position ticket

            // Collect market features for later recording in OnTradeTransaction
            MLFeatures features;
            CollectMarketFeatures(features);

            // Store market features for later recording in OnTradeTransaction
            lastMarketFeatures = features;
            lastTradeDirection = "BUY";
        }
    } else {
        Print("❌ Buy order failed");
    }
}

//+------------------------------------------------------------------+
//| Place sell order (fallback without ML)                          |
//+------------------------------------------------------------------+
void PlaceSellOrder() {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate stop loss based on new day high (original strategy logic)
    double stopLoss = CalculateBearishStopLoss(StopLossBuffer);

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "sell");

    // Calculate lot size based on risk percentage
    double stopDistance = stopLoss - entry;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = PlaceSellOrder(lotSize, stopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ Sell order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));
        hasOpenPosition = true;

        // Record analytics data (without ML)
        if(EnableHttpAnalytics) {
            // Record trade entry will be done in OnTradeTransaction when we have the actual position ticket
            // Record market conditions will be done in OnTradeTransaction when we have the actual position ticket

            // Collect market features for later recording in OnTradeTransaction
            MLFeatures features;
            CollectMarketFeatures(features);

            // Store market features for later recording in OnTradeTransaction
            lastMarketFeatures = features;
            lastTradeDirection = "SELL";
        }
    } else {
        Print("❌ Sell order failed");
    }
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
//| Clear previous day level lines                                    |
//+------------------------------------------------------------------+
void ClearPreviousDayLines(string highLineName, string lowLineName) {
    ObjectDelete(0, highLineName);
    ObjectDelete(0, lowLineName);
}

//+------------------------------------------------------------------+
//| Draw previous day levels on chart                                 |
//+------------------------------------------------------------------+
void DrawPreviousDayLevels(double highLevel, double lowLevel, string highLineName, string lowLineName) {
    // Draw high line
    ObjectCreate(0, highLineName, OBJ_HLINE, 0, 0, highLevel);
    ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 2);

    // Draw low line
    ObjectCreate(0, lowLineName, OBJ_HLINE, 0, 0, lowLevel);
    ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Generate unique trade ID for this strategy (overrides header)    |
//+------------------------------------------------------------------+
string GenerateBreakoutTradeID() {
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
                hasOpenPosition = true;

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

                        RecordTradeEntry(direction, entry_price, stop_loss, take_profit, lot_size, MLStrategyName + "_ML", "1.00");
                        Print("✅ Recorded trade entry analytics");

                        // Record market conditions for every trade (regardless of ML prediction)
                        if(lastMarketFeatures.rsi != 0) { // Check if we have valid features
                            RecordMarketConditions(lastMarketFeatures);
                            Print("✅ Recorded market conditions analytics");
                        }

                        // Record ML prediction if we have stored data
                        if(lastTradeDirection != "") {
                            // Record ML prediction with features JSON
                            string model_name = (lastTradeDirection == "BUY") ? "buy_model_improved" : "sell_model_improved";
                            string features_json = g_ml_interface.CreateFeatureJSON(lastMarketFeatures, lastTradeDirection);
                            RecordMLPrediction(model_name, StringToLower(lastTradeDirection), lastMLPrediction.probability, lastMLPrediction.confidence, features_json);
                            Print("✅ Recorded ML prediction analytics with features");

                            // Clear stored data
                            lastTradeDirection = "";
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
                if(EnableHttpAnalytics && g_analytics_trade_id != "") {
                    Print("📊 Recording trade exit analytics...");
                    RecordTradeExit(close_price, profit, profitLossPips);
                    Print("📊 Recorded trade exit analytics");
                } else {
                    Print("⚠️ HTTP Analytics disabled or no trade ID - skipping trade exit recording");
                }

                // Always log trade close for ML retraining (independent of analytics)
                Print("📊 Logging trade close for ML retraining...");
                Print("🔍 Using stored trade ID: ", lastTradeID);
                g_ml_interface.LogTradeCloseForRetraining(lastTradeID, close_price, profit, profitLossPips, close_time);
                Print("✅ Trade close logged for ML retraining");

                // Reset position tracking
                hasOpenPosition = false;
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

    // Iterate through all open positions
    for(int i = 0; i < total; i++) {
        // Get the position ticket
        ulong position_ticket = PositionGetTicket(i);

        // Check if the position is for our symbol
        if(PositionSelectByTicket(position_ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
                // Check if this position belongs to our EA by checking the comment
                string position_comment = PositionGetString(POSITION_COMMENT);

                // Enhanced filtering: Check for exact EA identifier match
                if(StringFind(position_comment, ea_identifier) >= 0) {
                    // Position is still open (if it exists in PositionsTotal, it's open)
                    return true;
                }
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check for closed positions using OnTrade event                  |
//+------------------------------------------------------------------+
void CheckForClosedPositionsOnTrade() {
    Print("🔍 CheckForClosedPositionsOnTrade() called - Symbol: ", _Symbol, ", EA: ", MLStrategyName);
    Print("🔍 Current hasOpenPosition: ", hasOpenPosition ? "true" : "false");
    Print("🔍 Current lastKnownPositionTicket: ", lastKnownPositionTicket);
    Print("🔍 Current lastPositionOpenTime: ", TimeToString(lastPositionOpenTime));

    // Check if we had a position before but don't have one now
    if(hasOpenPosition && lastKnownPositionTicket != 0) {
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
                    if(EnableHttpAnalytics && g_analytics_trade_id != "") {
                        Print("📊 Recording trade exit analytics...");
                        RecordTradeExit(close_price, profit, profitLossPips);
                        Print("📊 Recorded trade exit analytics");
                    } else {
                        Print("⚠️ HTTP Analytics disabled or no trade ID - skipping trade exit recording");
                    }

                    // Always log trade close for ML retraining (independent of analytics)
                    Print("📊 Logging trade close for ML retraining...");
                    string ea_identifier = GenerateEAIdentifier();
                    Print("🔍 Using EA identifier: ", ea_identifier);
                    g_ml_interface.LogTradeCloseForRetraining(ea_identifier, close_price, profit, profitLossPips, close_time);
                    Print("✅ Trade close logged for ML retraining");

                    // Reset position tracking
                    hasOpenPosition = false;
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
    } else {
        Print("🔍 No previous position to check for closure (hasOpenPosition: ", hasOpenPosition ? "true" : "false", ", lastKnownPositionTicket: ", lastKnownPositionTicket, ")");
    }

    // Update our position tracking based on actual open positions
    Print("🔍 Updating position tracking...");
    bool currentHasPosition = HasOpenPositionForThisEA();
    Print("🔍 Current has position: ", currentHasPosition ? "true" : "false");

    // If we have a position now but didn't before, track it
    if(currentHasPosition && !hasOpenPosition) {
        Print("🔍 New position detected - tracking it...");
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
    }

    hasOpenPosition = currentHasPosition;
    Print("🔍 Updated hasOpenPosition to: ", hasOpenPosition ? "true" : "false");
    Print("🔍 CheckForClosedPositionsOnTrade() completed");
}

//+------------------------------------------------------------------+
//| Check for closed positions and record analytics                  |
//+------------------------------------------------------------------+
void CheckForClosedPositions() {
    // This function is now deprecated in favor of OnTrade event
    // Keep it for backward compatibility but it won't be called
}
