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
input int MaxTrackedPositions = 50;            // Maximum number of positions to track simultaneously
input bool EnableRandomTrading = true;         // Enable random trading when no ML predictions available
input double RandomTradeProbability = 0.3;     // Probability of placing random trade (0.0-1.0)

input group "ATR-Based Stop Loss & Take Profit"
input bool UseATRStops = true;                 // Use ATR for dynamic stop loss/take profit
input int ATRPeriod = 14;                      // ATR period for calculation
input double ATRStopLossMultiplier = 2.0;      // ATR multiplier for stop loss
input double ATRTakeProfitMultiplier = 3.0;    // ATR multiplier for take profit
input bool UseDynamicPipRanges = true;         // Use symbol-specific dynamic pip ranges
input double PipMultiplier = 1.0;             // Multiplier for dynamic ranges (1.0 = default, 0.5 = tighter, 2.0 = wider)
input double MinStopLossPips = 20;             // Minimum stop loss in pips (fallback if dynamic disabled)
input double MinTakeProfitPips = 40;           // Minimum take profit in pips (fallback if dynamic disabled)
input double MaxStopLossPips = 50;             // Maximum stop loss in pips (fallback if dynamic disabled)
input double MaxTakeProfitPips = 100;          // Maximum take profit in pips (fallback if dynamic disabled)

input group "News Filtering"
input bool EnableNewsFiltering = true;         // Enable news event filtering
input int NewsMinutesBefore = 30;             // Minutes before news event to block trading
input int NewsMinutesAfter = 30;              // Minutes after news event to block trading
input bool NewsHighImpactOnly = true;         // Block only high-impact news events
input bool NewsEnableDebugLogs = true;        // Enable debug logs for news filtering

input group "Analytics Configuration"
// AnalyticsServerUrl is defined in ea_http_analytics.mqh

//--- Global variables
datetime lastTestTime = 0;
int testCount = 0;
int successCount = 0;
int errorCount = 0;

//--- Position tracking (unified system - no separate arrays needed)
datetime lastPositionOpenTime = 0;
string lastTradeID = ""; // Store the trade ID for matching close

//--- Pending trade data for ML retraining (unified system - no legacy variables needed)

//--- Analytics tracking variables (for comprehensive recording)
MLPrediction lastMLPrediction;  // Use MLPrediction from MLHttpInterface.mqh
MLFeatures lastMarketFeatures;  // Use MLFeatures from MLHttpInterface.mqh
string lastTradeDirection = "";

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
    Print("   Random Trading Enabled: ", EnableRandomTrading ? "Yes" : "No");
    if(EnableRandomTrading) {
        Print("   Random Trade Probability: ", DoubleToString(RandomTradeProbability * 100, 1), "%");
    }
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

    // Show news filtering configuration
    Print("📰 News Filtering Configuration:");
    Print("   Enabled: ", EnableNewsFiltering ? "Yes" : "No");
    if(EnableNewsFiltering) {
        Print("   Minutes before news: ", NewsMinutesBefore);
        Print("   Minutes after news: ", NewsMinutesAfter);
        Print("   High-impact only: ", NewsHighImpactOnly ? "Yes" : "No");
        Print("   Debug logs: ", NewsEnableDebugLogs ? "Yes" : "No");
    }

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

    // Initialize position tracking (unified system)
    Print("✅ Position tracking initialized (unified system)");

    // Scan for existing open positions and add them to tracking system
    string ea_identifier = GenerateEAIdentifier();
    Print("🔍 Scanning for existing open positions with identifier: '", ea_identifier, "'");
    g_ml_interface.ScanForExistingOpenPositions(ea_identifier, MaxTrackedPositions,
                                                   RecordTradeEntry, RecordMarketConditions, EnableHttpAnalytics, MLStrategyName + "_Testing", SetTradeIDFromTicket);

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
    MLFeatures features;  // Use MLFeatures from MLHttpInterface.mqh
    g_ml_interface.CollectMarketFeatures(features);

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

    // Execute random trade if ML predictions failed and random trading is enabled
    if(EnableRandomTrading && (!buyPrediction.is_valid || !sellPrediction.is_valid)) {
        ExecuteRandomTrade();
    }

    Print("✅ ML test #", testCount, " completed");
    Print("   Current success rate: ", DoubleToString((double)successCount / testCount * 100, 1), "%");
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

    // Check for high-impact news events
    if(EnableNewsFiltering) {
        Print("📰 Checking for news events...");
        if(TradeUtils::IsNewsTime(_Symbol, NewsMinutesBefore, NewsMinutesAfter, NewsHighImpactOnly, NewsEnableDebugLogs)) {
            Print("⚠️ Skipping trade - news event detected");
            Print("   News filtering: ", NewsMinutesBefore, " minutes before and ", NewsMinutesAfter, " minutes after");
            Print("   High-impact only: ", NewsHighImpactOnly ? "Yes" : "No");
            return;
        }
        Print("✅ No blocking news events detected - proceeding with trade");
    } else {
        Print("📰 News filtering disabled - proceeding with trade");
    }

    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place trade - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    int remaining_capacity = g_ml_interface.GetRemainingTradeCapacity(MaxTrackedPositions);
    Print("✅ Capacity available: ", remaining_capacity, " slots remaining");

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

    // Store prediction data for later recording in OnTradeTransaction
    lastMLPrediction = bestPrediction;
    g_ml_interface.CollectMarketFeatures(lastMarketFeatures); // Get fresh market features
    lastTradeDirection = tradeDirection;

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

    // Use ML Testing EA order placement functions
    bool success = false;
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    if(tradeDirection == "BUY") {
        success = PlaceMLTestingBuyOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    } else {
        success = PlaceMLTestingSellOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    }

    if(success) {
        Print("✅ Test trade executed successfully");
        Print("   Direction: ", tradeDirection);
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   ML Confidence: ", DoubleToString(bestPrediction.confidence, 3));

        // Store trade data for ML retraining using the new array-based system
        if(EnableHttpAnalytics) {
            MLFeatures features;  // Use MLFeatures from MLHttpInterface.mqh
            g_ml_interface.CollectMarketFeatures(features);

            // Register pending trade with ML interface for proper tracking
            g_ml_interface.RegisterPendingTrade(tradeDirection, entry, stopLoss, takeProfit, TestLotSize, bestPrediction, features, MaxTrackedPositions);
            Print("📊 Trade data registered for ML retraining (unified tracking system)");
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

            // Get dynamic ranges for this symbol
            double minSL, maxSL, minTP, maxTP;
            GetDynamicPipRanges(minSL, maxSL, minTP, maxTP);

            // Convert pips to points for fallback calculations
            double pipsToPoints = (_Digits == 2) ? 100 : 10;
            double minStopPips = minSL * pipsToPoints * point;
            double maxStopPips = maxSL * pipsToPoints * point;
            double minTpPips = minTP * pipsToPoints * point;
            double maxTpPips = maxTP * pipsToPoints * point;

            // Use ATR with dynamic limits
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
            // Fallback to dynamic pip distances
            double minSL, maxSL, minTP, maxTP;
            GetDynamicPipRanges(minSL, maxSL, minTP, maxTP);

            double pipsToPoints = (_Digits == 2) ? 100 : 10;
            stopDistance = MathMax(minSL * pipsToPoints * point, minStopDistance * point);
            tpDistance = MathMax(minTP * pipsToPoints * point, minTpDistance * point);
        }
    } else {
        // Use dynamic pip distances (fallback)
        double minSL, maxSL, minTP, maxTP;
        GetDynamicPipRanges(minSL, maxSL, minTP, maxTP);

        double pipsToPoints = (_Digits == 2) ? 100 : 10;
        stopDistance = MathMax(minSL * pipsToPoints * point, minStopDistance * point);
        tpDistance = MathMax(minTP * pipsToPoints * point, minTpDistance * point);

        Print("🔍 Dynamic pip-based calculations:");
        Print("   Min Stop Loss: ", DoubleToString(minSL, 1), " pips");
        Print("   Min Take Profit: ", DoubleToString(minTP, 1), " pips");
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
//| Get dynamic pip ranges based on symbol type and volatility        |
//+------------------------------------------------------------------+
void GetDynamicPipRanges(double &minSL, double &maxSL, double &minTP, double &maxTP)
{
    if(!UseDynamicPipRanges) {
        // Use static values if dynamic is disabled
        minSL = MinStopLossPips;
        maxSL = MaxStopLossPips;
        minTP = MinTakeProfitPips;
        maxTP = MaxTakeProfitPips;
        Print("🔧 Using static pip ranges - SL: ", minSL, "-", maxSL, " pips, TP: ", minTP, "-", maxTP, " pips");
        return;
    }

    string symbol = _Symbol;

    // Define symbol-specific ranges based on typical volatility
    if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) {
        // Gold: High volatility, larger ranges
        minSL = 50; maxSL = 200; minTP = 100; maxTP = 400;
        Print("🥇 GOLD detected - Using precious metals ranges");
    }
    else if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "BITCOIN") >= 0) {
        // Bitcoin: Extreme volatility, very large ranges
        minSL = 200; maxSL = 1000; minTP = 400; maxTP = 2000;
        Print("₿ BITCOIN detected - Using crypto ranges");
    }
    else if(StringFind(symbol, "ETH") >= 0 || StringFind(symbol, "ETHEREUM") >= 0) {
        // Ethereum: High volatility, large ranges
        minSL = 100; maxSL = 500; minTP = 200; maxTP = 1000;
        Print("⟠ ETHEREUM detected - Using crypto ranges");
    }
    else if(StringFind(symbol, "JPY") >= 0) {
        // JPY pairs: Different pip scale, moderate ranges
        minSL = 15; maxSL = 60; minTP = 30; maxTP = 120;
        Print("¥ JPY pair detected - Using JPY ranges");
    }
    else if(StringFind(symbol, "EUR") >= 0 || StringFind(symbol, "GBP") >= 0 ||
            StringFind(symbol, "USD") >= 0 || StringFind(symbol, "AUD") >= 0 ||
            StringFind(symbol, "CAD") >= 0 || StringFind(symbol, "CHF") >= 0) {
        // Major currency pairs: Standard ranges
        minSL = 15; maxSL = 40; minTP = 30; maxTP = 80;
        Print("💱 Major currency pair detected - Using forex ranges");
    }
    else {
        // Unknown symbol: Use conservative ranges
        minSL = 20; maxSL = 50; minTP = 40; maxTP = 100;
        Print("❓ Unknown symbol type - Using default ranges");
    }

    // Apply user multiplier
    minSL *= PipMultiplier;
    maxSL *= PipMultiplier;
    minTP *= PipMultiplier;
    maxTP *= PipMultiplier;

    Print("🔧 Dynamic pip ranges for ", symbol, " - SL: ", DoubleToString(minSL, 1), "-", DoubleToString(maxSL, 1),
          " pips, TP: ", DoubleToString(minTP, 1), "-", DoubleToString(maxTP, 1), " pips (multiplier: ", DoubleToString(PipMultiplier, 1), ")");
}

//+------------------------------------------------------------------+
//| Get symbol-specific minimum stop loss distance in points          |
//+------------------------------------------------------------------+
double GetSymbolMinStopDistance()
{
    double minSL, maxSL, minTP, maxTP;
    GetDynamicPipRanges(minSL, maxSL, minTP, maxTP);

    // Convert to points
    double pipsToPoints = (_Digits == 2) ? 100 : 10;
    return minSL * pipsToPoints;
}

//+------------------------------------------------------------------+
//| Get symbol-specific minimum take profit distance in points        |
//+------------------------------------------------------------------+
double GetSymbolMinTpDistance()
{
    double minSL, maxSL, minTP, maxTP;
    GetDynamicPipRanges(minSL, maxSL, minTP, maxTP);

    // Convert to points
    double pipsToPoints = (_Digits == 2) ? 100 : 10;
    return minTP * pipsToPoints;
}

//+------------------------------------------------------------------+
//| Place buy order using TradeUtils                                  |
//+------------------------------------------------------------------+
bool PlaceMLTestingBuyOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
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
bool PlaceMLTestingSellOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
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

//+------------------------------------------------------------------+
//| Execute random trade for data collection when ML predictions fail |
//+------------------------------------------------------------------+
void ExecuteRandomTrade() {
    Print("🎲 Executing random trade for data collection...");

    // Check if we have open positions for this EA specifically
    if(HasOpenPositionForThisEA()) {
        Print("⚠️ Skipping random trade - position already open for this EA");
        return;
    }

    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place random trade - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    // Generate random number to determine if we should place a trade
    double randomValue = MathRand() / 32767.0; // Normalize to 0.0-1.0
    Print("🎲 Random value: ", DoubleToString(randomValue, 3), " (threshold: ", DoubleToString(RandomTradeProbability, 3), ")");

    if(randomValue > RandomTradeProbability) {
        Print("🎲 Random trade skipped (below probability threshold)");
        return;
    }

    // Randomly choose direction (50/50 chance)
    string tradeDirection = (MathRand() % 2 == 0) ? "BUY" : "SELL";
    Print("🎲 Random trade direction: ", tradeDirection);

    // Store data for analytics tracking (random trade - no ML prediction)
    g_ml_interface.CollectMarketFeatures(lastMarketFeatures); // Get current market features
    lastTradeDirection = tradeDirection;
    // Note: lastMLPrediction will remain from previous test (or default values)

    // Execute random trade
    Print("🚀 Executing random ", tradeDirection, " trade...");

    // Calculate dynamic stop loss and take profit
    double entry = (tradeDirection == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss, takeProfit;

    CalculateDynamicStops(entry, tradeDirection, stopLoss, takeProfit);

    Print("   Entry: ", DoubleToString(entry, _Digits));
    Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
    Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));

    // Validate stops before placing order
    if(!ValidateStops(entry, stopLoss, takeProfit, tradeDirection)) {
        Print("❌ Stop validation failed - skipping random order placement");
        return;
    }

    // Use ML Testing EA order placement functions
    bool success = false;
    string tradeComment = GenerateEAIdentifier(); // Use consistent EA identifier
    if(tradeDirection == "BUY") {
        success = PlaceMLTestingBuyOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    } else {
        success = PlaceMLTestingSellOrder(TestLotSize, stopLoss, takeProfit, 0, tradeComment);
    }

    if(success) {
        Print("✅ Random trade executed successfully");
        Print("   Direction: ", tradeDirection);
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   ML Confidence: RANDOM (no ML prediction available)");

        // Store trade data for ML retraining (will be logged when we have actual MT5 ticket)
        if(EnableHttpAnalytics) {
            MLFeatures features;  // Use MLFeatures from MLHttpInterface.mqh
            g_ml_interface.CollectMarketFeatures(features);

            // Create a dummy prediction for random trades
            MLPrediction randomPrediction;
            randomPrediction.is_valid = true;
            randomPrediction.confidence = 0.5; // Neutral confidence for random trades
            randomPrediction.probability = 0.5;
            randomPrediction.direction = tradeDirection;
            randomPrediction.model_type = "RANDOM";
            randomPrediction.model_key = "RANDOM_MODEL";
            randomPrediction.error_message = "";

            // Register pending trade with ML interface for proper tracking
            g_ml_interface.RegisterPendingTrade(tradeDirection, entry, stopLoss, takeProfit, TestLotSize, randomPrediction, features, MaxTrackedPositions);
            Print("📊 Random trade data registered for ML retraining (unified tracking system)");
        }
    } else {
        Print("❌ Random trade failed - TradeUtils function returned false");
    }
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
        RecordGeneralMLPrediction("buy_model_test", "BUY", buyPrediction.probability, buyPrediction.confidence, features_json, MLStrategyName + "_Testing");
        Print("   ✅ Recorded BUY prediction analytics");
    }

    if(sellPrediction.is_valid) {
        string features_json = g_ml_interface.CreateFeatureJSON(features, "SELL");
        RecordGeneralMLPrediction("sell_model_test", "SELL", sellPrediction.probability, sellPrediction.confidence, features_json, MLStrategyName + "_Testing");
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
//| Expert trade transaction event - called for each trade operation |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    // Debug logging to track parameter values
    Print("🔍 OnTradeTransaction - About to call HandleCompleteTradeTransactionUnified:");
    Print("   lastTradeDirection: '", lastTradeDirection, "' (type: string, length: ", StringLen(lastTradeDirection), ")");
    Print("   lastMLPrediction.is_valid: ", lastMLPrediction.is_valid ? "true" : "false");
    Print("   lastMLPrediction.direction: '", lastMLPrediction.direction, "'");

    // Use unified trade transaction handler with analytics callback (unified system)
    string ea_identifier = GenerateEAIdentifier();
    g_ml_interface.HandleCompleteTradeTransactionUnified(trans, request, result,
                                                lastPositionOpenTime,
                                                lastTradeID, EnableHttpAnalytics,
                                                ea_identifier, MLStrategyName + "_Testing",
                                                lastMLPrediction, lastMarketFeatures, lastTradeDirection,
                                                SetTradeIDFromTicket, RecordTradeEntry, RecordMarketConditions, MLPredictionCallback, RecordTradeExit,
                                                MaxTrackedPositions);
}

//+------------------------------------------------------------------+
//| Generate unique EA identifier for position filtering              |
//+------------------------------------------------------------------+
string GenerateEAIdentifier() {
    // Shorten to stay within MT5's 31-character comment limit
    // Use abbreviations: ML_Test instead of ML_Testing_EA, remove PERIOD_ prefix
    string shortened_strategy = "ML_Test";
    string timeframe = EnumToString(_Period);

    // Remove "PERIOD_" prefix from timeframe (saves 7 chars)
    if(StringFind(timeframe, "PERIOD_") == 0) {
        timeframe = StringSubstr(timeframe, 7);
    }

    // Format: ML_Test_XAUUSD+_H1 (max ~20 chars)
    string identifier = shortened_strategy + "_" + _Symbol + "_" + timeframe;

    // Ensure we stay under 31 characters
    if(StringLen(identifier) > 31) {
        // Truncate symbol if needed (keep first part)
        int max_symbol_len = 31 - StringLen(shortened_strategy) - StringLen(timeframe) - 2; // -2 for underscores
        if(max_symbol_len > 0) {
            string truncated_symbol = StringSubstr(_Symbol, 0, max_symbol_len);
            identifier = shortened_strategy + "_" + truncated_symbol + "_" + timeframe;
        }
    }

    Print("🔍 Generated EA identifier: '", identifier, "' (", StringLen(identifier), " chars)");
    return identifier;
}

//+------------------------------------------------------------------+
//| ML Prediction Callback for analytics                              |
//+------------------------------------------------------------------+
void MLPredictionCallback(string model_name, string model_type, double probability, double confidence, string features_json) {
    // Debug logging to track parameter types
    Print("🔍 MLPredictionCallback received:");
    Print("   model_name: '", model_name, "' (type: string, length: ", StringLen(model_name), ")");
    Print("   model_type: '", model_type, "' (type: string, length: ", StringLen(model_type), ")");
    Print("   probability: ", probability, " (type: double)");
    Print("   confidence: ", confidence, " (type: double)");
    Print("   features_json length: ", StringLen(features_json));

    RecordGeneralMLPrediction(model_name, model_type, probability, confidence, features_json, MLStrategyName + "_Testing");
}

//+------------------------------------------------------------------+
//| Check if we have an open position for this EA                    |
//+------------------------------------------------------------------+
bool HasOpenPositionForThisEA() {
    return g_ml_interface.HasOpenPositionForThisEAUnified(AllowMultipleSimultaneousOrders);
}

//+------------------------------------------------------------------+
//| Print unified trade array status for debugging                    |
//+------------------------------------------------------------------+
void PrintUnifiedTradeArrayStatus() {
    g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
}

