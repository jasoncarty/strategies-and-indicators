//+------------------------------------------------------------------+
//| BreakoutStrategy_ML.mq5                                           |
//| Breakout strategy with ML integration                             |
//| Uses the same state machine as the original strategy             |
//| Includes news event filtering to avoid trading during high-impact news |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Include base strategy functions and ML interface
#include "../../Include/BreakoutStrategy_Base.mqh"
#include "../../Include/MLHttpInterface.mqh"
#include "../../Analytics/ea_http_analytics.mqh"
#include "../../Experts/TradeUtils.mqh"

//--- Input parameters
input double RiskPercent = 1.0;                // Risk per trade (% of balance)
input double RiskRewardRatio = 2.0;            // Risk:Reward ratio (2:1)
input int StopLossBuffer = 20;                 // Stop loss buffer in pips
input bool UseBreakoutFilter = true;           // Use breakout filter
input int BreakoutPeriod = 20;                 // Period for breakout detection
input double BreakoutThreshold = 0.001;        // Breakout threshold
input bool AllowMultipleSimultaneousOrders = false; // Allow multiple simultaneous orders
input int MaxTrackedPositions = 50;            // Maximum number of positions to track simultaneously

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

//--- News Filtering Parameters
input group "News Filtering"
input bool EnableNewsFiltering = true;         // Enable news event filtering
input int NewsMinutesBefore = 30;             // Minutes before news event to block trading
input int NewsMinutesAfter = 30;              // Minutes after news event to block trading
input bool NewsHighImpactOnly = true;         // Block only high-impact news events
input bool NewsEnableDebugLogs = true;        // Enable debug logs for news filtering

//--- Analytics Parameters (defined in header file)

//--- Global variables (matching original strategy)
double previousDayHigh = 0.0;
double previousDayLow = 0.0;
double newDayLow = 0; // New day low established after bearish breakout
double newDayHigh = 0; // New day high established after bullish breakout

datetime lastDayCheck = 0;

//--- Position tracking (unified system - no separate arrays needed)
datetime lastPositionOpenTime = 0;
string lastTradeID = ""; // Store the trade ID for matching close

//--- Analytics data storage for OnTradeTransaction
MLPrediction lastMLPrediction;
MLFeatures lastMarketFeatures;
string lastTradeDirection = "";

//--- Pending trade data for ML retraining (unified system - no legacy variables needed)

//--- State machine variables
BREAKOUT_STATE currentState = WAITING_FOR_BREAKOUT;
datetime lastStateChange = 0;
double breakoutLevel = 0.0;
string breakoutDirection = "";
string bounceDirection = ""; // Direction for bounce trades (separate from breakouts)
double swingPoint = 0.0; // The swing high/low that created the retest

//--- Retest tracking variables
bool bullishRetestDetected = false;
double bullishRetestLow = 999999.0;
bool bearishRetestDetected = false;
double bearishRetestHigh = 0.0;

//--- Bounce tracking variables (new)
bool bounceFromHighDetected = false;
bool bounceFromLowDetected = false;
double bounceHighPoint = 0.0;
double bounceLowPoint = 0.0;
int proximityThreshold = 50; // Points threshold for "near" level detection
bool wasNearHighLevel = false;
bool wasNearLowLevel = false;

//--- Breakout tracking variables
double lastBreakoutLevel = 0.0;
string lastBreakoutDirection = "";
int retestBar = -1;
int breakoutBar = -1;
int barsSinceBreakout = 0;

//--- Chart objects for previous day levels
string prevDayHighLine = "PrevDayHigh";
string prevDayLowLine = "PrevDayLow";

//--- New day detection variables
static int lastProcessedDay = -1;
static int lastProcessedSession = -1;
static datetime lastD1Bar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("🚀 BreakoutStrategy_ML initialized");
    Print("   Risk per trade: ", RiskPercent, "%");
    Print("   Risk:Reward ratio: ", RiskRewardRatio, ":1");
    Print("   Stop Loss Buffer: ", StopLossBuffer, " pips");
    Print("   ML Integration: ", UseML ? "Enabled" : "Disabled");

    // Show news filtering configuration
    Print("📰 News Filtering Configuration:");
    Print("   Enabled: ", EnableNewsFiltering ? "Yes" : "No");
    if(EnableNewsFiltering) {
        Print("   Minutes before news: ", NewsMinutesBefore);
        Print("   Minutes after news: ", NewsMinutesAfter);
        Print("   High-impact only: ", NewsHighImpactOnly ? "Yes" : "No");
        Print("   Debug logs: ", NewsEnableDebugLogs ? "Yes" : "No");
    }

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

    // Initialize position tracking (unified system)
    Print("✅ Position tracking initialized (unified system)");

    // Scan for existing open positions and add them to tracking system
    string ea_identifier = GenerateEAIdentifier();
    Print("🔍 Scanning for existing open positions with identifier: '", ea_identifier, "'");
    g_ml_interface.ScanForExistingOpenPositions(ea_identifier, MaxTrackedPositions,
                                                   RecordTradeEntry, RecordMarketConditions, EnableHttpAnalytics, MLStrategyName + "_ML", SetTradeIDFromTicket);

    // Update previous day levels
    UpdatePreviousDayLevels();

            // Draw previous day levels on chart
        TradeUtils::DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);

    return(INIT_SUCCEEDED);
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

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clear previous day level lines
            TradeUtils::ClearPreviousDayLines(prevDayHighLine, prevDayLowLine);

    Print("🛑 BreakoutStrategy_ML deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for new day (more flexible than just hourly)
    bool isNewDay = false;

    // Method 1: Check if we've moved to a new calendar day
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day != lastProcessedDay) {
        isNewDay = true;
        lastProcessedDay = dt.day;
        Print("🔄 New calendar day detected - Day: ", dt.day);
    }

    // Method 2: Check if we've moved to a new D1 bar (most reliable for trading)
    datetime currentD1Bar = iTime(_Symbol, PERIOD_D1, 0);
    if(currentD1Bar != lastD1Bar && currentD1Bar > 0) {
        isNewDay = true;
        lastD1Bar = currentD1Bar;
        Print("🔄 New D1 bar detected - New trading day");
    }

    if(isNewDay) {
        Print("🔄 New day detected - Resetting EA state");
        ResetDailyState();
        UpdatePreviousDayLevels();
        TradeUtils::DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);
    } else if(TimeCurrent() - lastDayCheck > 3600) { // Keep hourly updates
        UpdatePreviousDayLevels();
        // Update chart lines when previous day levels change
        TradeUtils::DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);
        lastDayCheck = TimeCurrent();
    }

    // Only run main strategy logic on new candle close
    if(!TradeUtils::IsNewBar()) {
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

    // Check for high-impact news events
    if(EnableNewsFiltering) {
        Print("📰 Checking for news events...");
        if(TradeUtils::IsNewsTime(_Symbol, NewsMinutesBefore, NewsMinutesAfter, NewsHighImpactOnly, NewsEnableDebugLogs)) {
            Print("⚠️ Skipping trade signals - news event detected");
            Print("   News filtering: ", NewsMinutesBefore, " minutes before and ", NewsMinutesAfter, " minutes after");
            Print("   High-impact only: ", NewsHighImpactOnly ? "Yes" : "No");
            return;
        }
        Print("✅ No blocking news events detected - proceeding with trade signals");
    } else {
        Print("📰 News filtering disabled - proceeding with trade signals");
    }

    // Check if we just completed a bullish confirmation
    if(currentState == WAITING_FOR_BREAKOUT && breakoutDirection == "bullish" && bullishRetestDetected) {
        Print("🔄 Bullish trade signal detected - validating with ML");

        if(UseML) {
            MLPrediction prediction = GetMLPrediction("buy");

            // Record ML prediction for analysis (regardless of whether trade is placed)
            if(prediction.is_valid && EnableHttpAnalytics) {
                MLFeatures features;
                g_ml_interface.CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "BUY");
                RecordGeneralMLPrediction("buy_model_improved", "BUY", prediction.probability, prediction.confidence, features_json, "BreakoutStrategy_ML");
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
            TradeUtils::PlaceBuyOrder();
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
                g_ml_interface.CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "SELL");
                RecordGeneralMLPrediction("sell_model_improved", "SELL", prediction.probability, prediction.confidence, features_json, "BreakoutStrategy_ML");
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
            TradeUtils::PlaceSellOrder();
        }

        ResetBreakoutStateVariables();
        bearishRetestDetected = false;
    }

    // NEW: Check for bounce from high signal (SELL opportunity)
    if(currentState == BOUNCE_FROM_HIGH_DETECTED && bounceFromHighDetected) {
        Print("🔄 Bounce from high detected - validating SELL with ML");

        if(UseML) {
            MLPrediction prediction = GetMLPrediction("sell");

            // Record ML prediction for analysis (regardless of whether trade is placed)
            if(prediction.is_valid && EnableHttpAnalytics) {
                MLFeatures features;
                g_ml_interface.CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "SELL");
                RecordGeneralMLPrediction("sell_model_improved", "SELL", prediction.probability, prediction.confidence, features_json, "BreakoutStrategy_ML");
                Print("📊 Recorded bounce SELL prediction for analysis");
            }

            if(g_ml_interface.IsSignalValid(prediction)) {
                Print("✅ ML validation passed for bounce - placing sell order");
                PlaceSellOrderWithML(prediction);

                // Reset bounce state after successful trade
                currentState = WAITING_FOR_BREAKOUT;
                ResetBounceVariables();
            } else {
                Print("❌ ML validation failed for bounce - falling back to breakout strategy");

                // Fallback to original breakout logic if this was a retest completion
                if(bullishRetestDetected) {
                    currentState = WAITING_FOR_BULLISH_CLOSE;
                    Print("🔄 Falling back to WAITING_FOR_BULLISH_CLOSE for breakout confirmation");
                } else {
                    currentState = WAITING_FOR_BREAKOUT;
                }
                ResetBounceVariables();
            }
        } else {
            Print("🔄 ML disabled - placing bounce sell order");
            TradeUtils::PlaceSellOrder();

            // Reset bounce state after trade
            currentState = WAITING_FOR_BREAKOUT;
            ResetBounceVariables();
        }
    }

    // NEW: Check for bounce from low signal (BUY opportunity)
    if(currentState == BOUNCE_FROM_LOW_DETECTED && bounceFromLowDetected) {
        Print("🔄 Bounce from low detected - validating BUY with ML");

        if(UseML) {
            MLPrediction prediction = GetMLPrediction("buy");

            // Record ML prediction for analysis (regardless of whether trade is placed)
            if(prediction.is_valid && EnableHttpAnalytics) {
                MLFeatures features;
                g_ml_interface.CollectMarketFeatures(features);
                string features_json = g_ml_interface.CreateFeatureJSON(features, "BUY");
                RecordGeneralMLPrediction("buy_model_improved", "BUY", prediction.probability, prediction.confidence, features_json, "BreakoutStrategy_ML");
                Print("📊 Recorded bounce BUY prediction for analysis");
            }

            if(g_ml_interface.IsSignalValid(prediction)) {
                Print("✅ ML validation passed for bounce - placing buy order");
                PlaceBuyOrderWithML(prediction);

                // Reset bounce state after successful trade
                currentState = WAITING_FOR_BREAKOUT;
                ResetBounceVariables();
            } else {
                Print("❌ ML validation failed for bounce - falling back to breakout strategy");

                // Fallback to original breakout logic if this was a retest completion
                if(bearishRetestDetected) {
                    currentState = WAITING_FOR_BEARISH_CLOSE;
                    Print("🔄 Falling back to WAITING_FOR_BEARISH_CLOSE for breakout confirmation");
                } else {
                    currentState = WAITING_FOR_BREAKOUT;
                }
                ResetBounceVariables();
            }
        } else {
            Print("🔄 ML disabled - placing bounce buy order");
            TradeUtils::PlaceBuyOrder();

            // Reset bounce state after trade
            currentState = WAITING_FOR_BREAKOUT;
            ResetBounceVariables();
        }
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
    g_ml_interface.CollectMarketFeatures(features);

    return g_ml_interface.GetPrediction(features, direction);
}


//+------------------------------------------------------------------+
//| Place buy order with ML adjustments                              |
//+------------------------------------------------------------------+
void PlaceBuyOrderWithML(MLPrediction &prediction) {
    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place buy order - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calculate base stop loss based on trade type
    double baseStopLoss;
    if(currentState == BOUNCE_FROM_LOW_DETECTED || bounceFromLowDetected) {
        // Bounce trade: use bounce-specific stop loss
        baseStopLoss = CalculateBounceFromLowStopLoss(StopLossBuffer);
        Print("📊 Using bounce-from-low stop loss for BUY trade");
    } else {
        // Breakout trade: use original strategy logic (new day low)
        baseStopLoss = CalculateBullishStopLoss(StopLossBuffer);
        Print("📊 Using breakout stop loss for BUY trade");
    }

    // Apply ML adjustments using new distance-based method
    double adjustedStopLoss = g_ml_interface.CalculateAdjustedStopLoss(entry, baseStopLoss, prediction, "buy");
    double stopDistance = entry - adjustedStopLoss;
    double takeProfit = CalculateTakeProfit(entry, adjustedStopLoss, RiskRewardRatio, "buy");

    // Calculate base lot size based on risk percentage
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Apply ML position sizing adjustments
    double adjustedLotSize = g_ml_interface.AdjustPositionSize(baseLotSize, prediction);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = TradeUtils::PlaceBuyOrder(adjustedLotSize, adjustedStopLoss, takeProfit, 0, tradeComment);

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


        // Record analytics data
        if(EnableHttpAnalytics) {
            // Collect market features for ML retraining
            MLFeatures features;
            g_ml_interface.CollectMarketFeatures(features);

            // Store prediction data for later recording in OnTradeTransaction
            lastMLPrediction = prediction;
            lastMarketFeatures = features;
            lastTradeDirection = "BUY";

            // Register pending trade with ML interface for proper tracking
            g_ml_interface.RegisterPendingTrade("BUY", entry, adjustedStopLoss, takeProfit, adjustedLotSize, prediction, features, MaxTrackedPositions);
            Print("📊 Trade data registered for ML retraining (unified tracking system)");
        }
    } else {
        Print("❌ ML-enhanced buy order failed");
    }
}

//+------------------------------------------------------------------+
//| Place sell order with ML adjustments                             |
//+------------------------------------------------------------------+
void PlaceSellOrderWithML(MLPrediction &prediction) {
    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place sell order - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate base stop loss based on trade type
    double baseStopLoss;
    if(currentState == BOUNCE_FROM_HIGH_DETECTED || bounceFromHighDetected) {
        // Bounce trade: use bounce-specific stop loss
        baseStopLoss = CalculateBounceFromHighStopLoss(StopLossBuffer);
        Print("📊 Using bounce-from-high stop loss for SELL trade");
    } else {
        // Breakout trade: use original strategy logic (new day high)
        baseStopLoss = CalculateBearishStopLoss(StopLossBuffer);
        Print("📊 Using breakout stop loss for SELL trade");
    }

    // Apply ML adjustments using new distance-based method
    double adjustedStopLoss = g_ml_interface.CalculateAdjustedStopLoss(entry, baseStopLoss, prediction, "sell");
    double stopDistance = adjustedStopLoss - entry;
    double takeProfit = CalculateTakeProfit(entry, adjustedStopLoss, RiskRewardRatio, "sell");

    // Calculate base lot size based on risk percentage
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Apply ML position sizing adjustments
    double adjustedLotSize = g_ml_interface.AdjustPositionSize(baseLotSize, prediction);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = TradeUtils::PlaceSellOrder(adjustedLotSize, adjustedStopLoss, takeProfit, 0, tradeComment);

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


        // Record analytics data
        if(EnableHttpAnalytics) {
            // Collect market features for ML retraining
            MLFeatures features;
            g_ml_interface.CollectMarketFeatures(features);

            // Store prediction data for later recording in OnTradeTransaction
            lastMLPrediction = prediction;
            lastMarketFeatures = features;
            lastTradeDirection = "SELL";

            // Register pending trade with ML interface for proper tracking
            g_ml_interface.RegisterPendingTrade("SELL", entry, adjustedStopLoss, takeProfit, adjustedLotSize, prediction, features, MaxTrackedPositions);
            Print("📊 Trade data registered for ML retraining (unified tracking system)");


        }
    } else {
        Print("❌ ML-enhanced sell order failed");
    }
}

//+------------------------------------------------------------------+
//| Place buy order (fallback without ML)                           |
//+------------------------------------------------------------------+
void PlaceBuyOrder() {
    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place buy order - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calculate stop loss based on trade type
    double stopLoss;
    if(currentState == BOUNCE_FROM_LOW_DETECTED || bounceFromLowDetected) {
        // Bounce trade: use bounce-specific stop loss
        stopLoss = CalculateBounceFromLowStopLoss(StopLossBuffer);
        Print("📊 Using bounce-from-low stop loss for BUY trade (no ML)");
    } else {
        // Breakout trade: use original strategy logic (new day low)
        stopLoss = CalculateBullishStopLoss(StopLossBuffer);
        Print("📊 Using breakout stop loss for BUY trade (no ML)");
    }

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "buy");

    // Calculate lot size based on risk percentage
    double stopDistance = entry - stopLoss;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = TradeUtils::PlaceBuyOrder(lotSize, stopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ Buy order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));


        // Record analytics data (without ML)
        if(EnableHttpAnalytics) {
            // Record trade entry will be done in OnTradeTransaction when we have the actual position ticket
            // Record market conditions will be done in OnTradeTransaction when we have the actual position ticket

            // Collect market features for later recording in OnTradeTransaction
            MLFeatures features;
            g_ml_interface.CollectMarketFeatures(features);

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
    // Check if we can track more trades (unified system)
    if(!g_ml_interface.CanTrackMoreTrades(MaxTrackedPositions)) {
        Print("❌ Cannot place sell order - unified trade array is full");
        Print("⚠️ Wait for existing trades to be processed before placing new trades");
        g_ml_interface.PrintUnifiedTradeArrayStatus(MaxTrackedPositions);
        return;
    }

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate stop loss based on trade type
    double stopLoss;
    if(currentState == BOUNCE_FROM_HIGH_DETECTED || bounceFromHighDetected) {
        // Bounce trade: use bounce-specific stop loss
        stopLoss = CalculateBounceFromHighStopLoss(StopLossBuffer);
        Print("📊 Using bounce-from-high stop loss for SELL trade (no ML)");
    } else {
        // Breakout trade: use original strategy logic (new day high)
        stopLoss = CalculateBearishStopLoss(StopLossBuffer);
        Print("📊 Using breakout stop loss for SELL trade (no ML)");
    }

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "sell");

    // Calculate lot size based on risk percentage
    double stopDistance = stopLoss - entry;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    // Use robust order placement function
    string tradeComment = GenerateEAIdentifier(); // Use the EA identifier as comment
    bool success = TradeUtils::PlaceSellOrder(lotSize, stopLoss, takeProfit, 0, tradeComment);

    if(success) {
        Print("✅ Sell order placed successfully");
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));


        // Record analytics data (without ML)
        if(EnableHttpAnalytics) {
            // Record trade entry will be done in OnTradeTransaction when we have the actual position ticket
            // Record market conditions will be done in OnTradeTransaction when we have the actual position ticket

            // Collect market features for later recording in OnTradeTransaction
            MLFeatures features;
            g_ml_interface.CollectMarketFeatures(features);

            // Store market features for later recording in OnTradeTransaction
            lastMarketFeatures = features;
            lastTradeDirection = "SELL";
        }
    } else {
        Print("❌ Sell order failed");
    }
}

// Note: Trade logging functions moved to MLHttpInterface.mqh to avoid duplication

//+------------------------------------------------------------------+
//| Expert trade transaction event - called for each trade operation |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    // Use unified trade transaction handler with position tracking (unified system)
    string ea_identifier = GenerateEAIdentifier();
    g_ml_interface.HandleCompleteTradeTransactionUnified(trans, request, result,
                                                            lastPositionOpenTime,
                                                            lastTradeID, EnableHttpAnalytics,
                                                            ea_identifier, MLStrategyName + "_ML",
                                                            lastMLPrediction, lastMarketFeatures, lastTradeDirection,
                                                            SetTradeIDFromTicket, RecordTradeEntry, RecordMarketConditions, MLPredictionCallback, RecordTradeExit,
                                                            MaxTrackedPositions);

    // Note: Analytics and position status updates are handled by the utility function with callback
    // EA-specific trade exit analytics would go here if needed
}

//+------------------------------------------------------------------+
//| ML Prediction Callback for analytics                              |
//+------------------------------------------------------------------+
void MLPredictionCallback(string model_name, string model_type, double probability, double confidence, string features_json) {
    RecordGeneralMLPrediction(model_name, model_type, probability, confidence, features_json, "BreakoutStrategy_ML");
}

//+------------------------------------------------------------------+
//| Generate unique EA identifier for position filtering              |
//+------------------------------------------------------------------+
string GenerateEAIdentifier() {
    // Shorten to stay within MT5's 31-character comment limit
    // Use abbreviations: Breakout instead of BreakoutStrategy, remove PERIOD_ prefix
    string shortened_strategy = "Breakout";
    string timeframe = EnumToString(_Period);

    // Remove "PERIOD_" prefix from timeframe (saves 7 chars)
    if(StringFind(timeframe, "PERIOD_") == 0) {
        timeframe = StringSubstr(timeframe, 7);
    }

    // Format: Breakout_USDJPY+_M5 (max ~20 chars)
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
//| Generate unique trade ID for this strategy (overrides header)    |
//+------------------------------------------------------------------+
string GenerateBreakoutTradeID() {
    // Use MT5 position ticket as trade ID for consistency
    // This will be set when a position is opened
    return "0"; // Placeholder - will be replaced with actual ticket
}

//+------------------------------------------------------------------+
//| Reset all state variables for new trading day                   |
//+------------------------------------------------------------------+
void ResetDailyState() {
    Print("🔄 Resetting daily state variables...");

    // Reset breakout state variables
    currentState = WAITING_FOR_BREAKOUT;
    breakoutLevel = 0.0;
    breakoutDirection = "";
    swingPoint = 0.0;

    // Reset retest tracking variables
    bullishRetestDetected = false;
    bearishRetestDetected = false;

    // Reset new day levels (THIS IS THE KEY!)
    newDayLow = 0;
    newDayHigh = 0;

    // Reset timing variables
    lastStateChange = 0;

    // Call the existing reset function to ensure all variables are reset
    ResetBreakoutStateVariables();

    Print("✅ Daily state reset complete");
    Print("   State: WAITING_FOR_BREAKOUT");
    Print("   Previous Day High: ", DoubleToString(previousDayHigh, _Digits));
    Print("   Previous Day Low: ", DoubleToString(previousDayLow, _Digits));
}




