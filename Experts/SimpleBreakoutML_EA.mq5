//+------------------------------------------------------------------+
//| SimpleBreakoutML_EA.mq5 - Simple Breakout Strategy with ML Data  |
//| Based on previous day high/low breakout and retest               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"

//--- Inputs
input group "Risk Management"
input double RiskPercent = 1.0; // Risk per trade( % of balance)
input double RiskRewardRatio = 2.0; // Risk:Reward ratio(2:1)
input int StopLossBuffer = 20; // Stop loss buffer in pips

input group "Breakout Settings"
input int RetestPips = 10; // Pips beyond previous day high / low for retest confirmation
input int StopLossPips = 15; // Pips beyond retest swing for stop loss
input bool UseVolumeConfirmation = true; // Use volume confirmation for entries
input bool DisableVolumeInTester = true; // Disable volume confirmation in Strategy Tester
input bool UseCandlePatternConfirmation = true; // Use candle pattern confirmation
input bool UseMLVolumeThreshold = true; // Use ML - optimized volume thresholds per symbol

input group "ML Data Collection"
input bool CollectMLData = true; // Collect indicator data for ML training
input bool SaveTradeResults = true; // Save trade outcomes for analysis
input string TestRunIdentifier = ""; // Optional identifier for this test run

input group "ML Model Integration"
input bool UseMLModels = true; // Use trained ML models for trade decisions
input bool UseMLPositionSizing = true; // Use ML for dynamic position sizing
input bool UseMLStopLossAdjustment = true; // Use ML for stop loss adjustments
input bool UseTimeframeSpecificModels = true; // Use separate models for each timeframe
input bool UseDirectionalModels = false; // Use buy/sell directional models (WARNING: May be overfitted)
input bool UseCombinedModels = true; // Use combined success prediction models (Recommended)
input bool UseOnlyCombinedModel = true; // Use ONLY combined model (simplest approach)
input double MLMinPredictionThreshold = 0.55; // Minimum ML prediction to take bullish trade
input double MLMaxPredictionThreshold = 0.45; // Maximum ML prediction to take bearish trade
input double MLMinConfidence = 0.30; // Minimum ML confidence to take trade
input double MLMaxConfidence = 0.85; // Maximum ML confidence to take trade
input double MLPositionSizingMultiplier = 1.0; // ML position sizing multiplier
input double MLStopLossAdjustment = 1.0; // ML stop loss adjustment factor

input group "Session Filtering"
input bool UseSessionFiltering = true; // Use ML session recommendations to filter trades
input bool AllowAllSessions = false; // Allow trades in all sessions(overrides ML session filtering)
input int LondonSessionStart = 8; // London session start hour(server time)
input int LondonSessionEnd = 16; // London session end hour(server time)
input int NYSessionStart = 13; // New York session start hour(server time)
input int NYSessionEnd = 22; // New York session end hour(server time)
input int AsianSessionStart = 1; // Asian session start hour(server time)
input int AsianSessionEnd = 10; // Asian session end hour(server time)

input group "Advanced Session Filtering"
input bool UseAdvancedSessionFiltering = true; // Use advanced ML session filtering with market conditions
input bool UseSessionConditionFiltering = true; // Filter trades based on session - specific market conditions
input bool UseSessionVolatilityFiltering = true; // Filter trades based on session - specific volatility conditions
input bool UseSessionTrendFiltering = true; // Filter trades based on session - specific trend conditions
input bool UseSessionRSIFiltering = true; // Filter trades based on session - specific RSI conditions
input double SessionMinSuccessRate = 0.4; // Minimum success rate to consider session optimal
input int SessionMinTrades = 5; // Minimum trades to consider session valid

//--- Dynamic file names based on test run ID
// These will be constructed in OnInit() to include test run directory
string DATA_FILE_PATH = "";
string RESULTS_FILE_PATH = "";
#define MODEL_PARAMS_FILE "SimpleBreakoutML_EA/ml_model_params_simple.txt"

//--- Dynamic parameter file generation - no hardcoded symbol files needed
// The EA will automatically look for: SimpleBreakoutML_EA/ml_model_params_{SYMBOL}.txt
// If not found, it will fall back to: SimpleBreakoutML_EA/ml_model_params_simple.txt

//--- Test Run ID (generated at initialization)
string actualTestRunID = "";

//--- Global variables
double previousDayHigh = 0;
double previousDayLow = 0;
double newDayLow = 0; // New day low established after bearish breakout
double newDayHigh = 0; // New day high established after bullish breakout
bool hasOpenPosition = false;
int testTotalTrades = 0;
int testWinningTrades = 0;
double testTotalProfit = 0.0;
datetime lastTradeTime = 0;
datetime lastDayCheck = 0; // Track last day check for hourly updates

//--- Global variables for ML parameters
// Volume threshold is now loaded from globalVolumeRatioThreshold in TradeUtils.mqh

//--- Global variables for timeframe-specific ML models
bool timeframeModelsLoaded = false;
string currentTimeframe = "";

//--- Chart objects for previous day levels
string prevDayHighLine = "PrevDayHigh";
string prevDayLowLine = "PrevDayLow";
datetime lastDayChecked = 0;

//--- State machine variables
enum BREAKOUT_STATE {
    WAITING_FOR_BREAKOUT = 0,
    BULLISH_BREAKOUT_DETECTED = 1,
    BEARISH_BREAKOUT_DETECTED = 2,
    WAITING_FOR_BULLISH_RETEST = 3,
    WAITING_FOR_BEARISH_RETEST = 4,
    WAITING_FOR_BULLISH_CLOSE = 5,
    WAITING_FOR_BEARISH_CLOSE = 6
};
BREAKOUT_STATE currentState = WAITING_FOR_BREAKOUT;
datetime lastStateChange = 0;
double breakoutLevel = 0.0;
string breakoutDirection = "";
double swingPoint = 0.0; // The swing high / low that created the retest

//--- Retest tracking variables
bool bullishRetestDetected = false;
double bullishRetestLow = 999999.0;
bool bearishRetestDetected = false;
double bearishRetestHigh = 0.0;

//--- Breakout tracking variables (moved from static to global for daily reset)
double lastBreakoutLevel = 0.0;
string lastBreakoutDirection = "";
int retestBar = -1;
int breakoutBar = -1;
int barsSinceBreakout = 0;

//--- Trade object
CTrade trade;

//--- Enhanced ML data structure (now using TradeUtils.mqh)

//--- Trade tracking structure (now using TradeUtils.mqh)
// TradeInfo and TradeData structures are now defined in TradeUtils.mqh

//--- Test run specific counters
int testRunTradeCounter = 0;

TradeInfo currentTrade;
int barCounter = 0;
datetime lastTradeCheck = 0;

//--- Trade history tracking
struct TradeResult {
    int trade_number;
    double profit;
    bool success;
    datetime close_time;
    string direction;
    double lot_size;
    double entry_price;
    double close_price;
};

TradeResult tradeResults[];
int tradeResultsCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Generate unique test run identifier
    actualTestRunID = GenerateTestRunID(TestRunIdentifier);

    // Construct dynamic file paths with test run directory
    DATA_FILE_PATH = "SimpleBreakoutML_EA/" + actualTestRunID + "/SimpleBreakoutML_EA_ML_Data.json";
    RESULTS_FILE_PATH = "SimpleBreakoutML_EA/" + actualTestRunID + "/SimpleBreakoutML_EA_Results.json";

    // Reset test run specific counters
    testRunTradeCounter = 0;

    Print("Simple Breakout ML EA initialized");
    Print("Test Run ID: ", actualTestRunID);
    Print("Risk per trade: ", RiskPercent, " % ");
    Print("Risk:Reward ratio: ", RiskRewardRatio, ":1");
    Print("Retest pips: ", RetestPips);
    Print("Stop loss pips: ", StopLossPips);
    Print("ML data collection: ", (CollectMLData ? "enabled" : "disabled"));
    Print("Trade results saving: ", (SaveTradeResults ? "enabled" : "disabled"));

    // Set up trade object
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    // Pure ML approach: No parameter file loading needed
    // ML models contain all the learned intelligence
    Print("🤖 Pure ML Mode: Using only ML model predictions");
    Print("   No parameter files needed - models contain learned intelligence");
    Print("   Confidence thresholds: ", MLMinConfidence, " - ", MLMaxConfidence);

    // Log ML model status
    if(UseMLModels) {
        Print("🤖 ML Model Integration: ENABLED");
        Print(" ML Position Sizing: ", (UseMLPositionSizing ? "enabled" : "disabled"));
        Print(" ML Stop Loss Adjustment: ", (UseMLStopLossAdjustment ? "enabled" : "disabled"));
        Print(" ML Min Prediction Threshold: ", DoubleToString(MLMinPredictionThreshold, 4));
        Print(" ML Max Prediction Threshold: ", DoubleToString(MLMaxPredictionThreshold, 4));
        Print(" ML Min Confidence: ", DoubleToString(MLMinConfidence, 4));
        Print(" ML Max Confidence: ", DoubleToString(MLMaxConfidence, 4));
        Print(" ML Position Sizing Multiplier: ", DoubleToString(MLPositionSizingMultiplier, 2));
        Print(" ML Stop Loss Adjustment: ", DoubleToString(MLStopLossAdjustment, 2));
        Print(" ML Volume Threshold: ", DoubleToString(globalVolumeRatioThreshold, 2));

        // Validate ML model settings
        if(UseDirectionalModels) {
            Print("⚠️  WARNING: Directional models enabled - these may be overfitted!");
            Print("   Consider using combined models instead for better generalization");
            Print("   Set UseDirectionalModels=false and UseCombinedModels=true for safer operation");
        }

        if(UseCombinedModels) {
            Print("✅ Combined models enabled (recommended)");
        }

        if(UseOnlyCombinedModel) {
            Print("✅ Using ONLY combined model (simplest approach)");
        }

        if(!UseDirectionalModels && !UseCombinedModels && !UseOnlyCombinedModel) {
            Print("⚠️  WARNING: No ML model type selected!");
            Print("   Set either UseDirectionalModels=true OR UseCombinedModels=true OR UseOnlyCombinedModel=true");
        }

        if(UseDirectionalModels && UseCombinedModels) {
            Print("ℹ️  Both model types enabled - directional models will be used first");
        }
        if(UseCombinedModels && UseOnlyCombinedModel) {
            Print("ℹ️  Combined model and ONLY combined model enabled - using combined model");
        }
    } else {
        Print("🤖 ML Model Integration: DISABLED");
    }

    // Validate ML model settings and provide recommendations
    ValidateMLModelSettings();

    // Log session filtering status and ML-loaded parameters
    if(UseSessionFiltering) {
        Print("⏰ Session Filtering: ENABLED");
        Print(" Allow All Sessions: ", (AllowAllSessions ? "enabled" : "disabled"));
        Print(" London Session: ", LondonSessionStart, ":00 - ", LondonSessionEnd, ":00");
        Print(" NY Session: ", NYSessionStart, ":00 - ", NYSessionEnd, ":00");
        Print(" Asian Session: ", AsianSessionStart, ":00 - ", AsianSessionEnd, ":00");

        // Log ML-loaded session parameters
        Print("📊 ML-Loaded Session Parameters:");
        Print("   Optimal Sessions: ", globalOptimalSessions);
        Print("   Session Filtering Enabled: ", (globalSessionFilteringEnabled ? "yes" : "no"));
        Print("   London Weight: ", DoubleToString(globalLondonSessionWeight, 2));
        Print("   NY Weight: ", DoubleToString(globalNYSessionWeight, 2));
        Print("   Asian Weight: ", DoubleToString(globalAsianSessionWeight, 2));
        Print("   Off-hours Weight: ", DoubleToString(globalOffHoursSessionWeight, 2));
        Print("   London Min Success Rate: ", DoubleToString(globalLondonMinSuccessRate, 3));
        Print("   NY Min Success Rate: ", DoubleToString(globalNYMinSuccessRate, 3));
        Print("   Asian Min Success Rate: ", DoubleToString(globalAsianMinSuccessRate, 3));

        Print(" Symbol Session Recommendation: ", GetSymbolSessionRecommendation(_Symbol));

        // Test session filtering immediately using ML parameters
        bool isOptimal = false;
        if(UseAdvancedSessionFiltering) {
            isOptimal = IsOptimalSessionAdvanced(_Symbol, UseAdvancedSessionFiltering, UseSessionConditionFiltering,
            UseSessionVolatilityFiltering, UseSessionTrendFiltering, UseSessionRSIFiltering,
            SessionMinSuccessRate, SessionMinTrades);
            Print("⏰ Advanced session filtering: ", (isOptimal ? "OPTIMAL" : "NOT OPTIMAL"));
        } else {
            isOptimal = IsOptimalSession(_Symbol, UseSessionFiltering, AllowAllSessions, LondonSessionStart, LondonSessionEnd, NYSessionStart, NYSessionEnd, AsianSessionStart, AsianSessionEnd);
            Print("⏰ Basic session filtering: ", (isOptimal ? "OPTIMAL" : "NOT OPTIMAL"));
        }
    } else {
        Print("⏰ Session Filtering: DISABLED");
    }

    // Dynamic ML model file loading
    Print("🔍 Dynamic ML model file loading for symbol: ", _Symbol);
    string paramFile = GetCurrencyPairParamFile("SimpleBreakoutML_EA");
    Print("📁 Using ML parameter file: ", paramFile);

    // Initialize previous day levels
    UpdatePreviousDayLevels();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("🔄 EA deinitializing - reason: ", reason);

    Print("📈 TRADE RESULTS SUMMARY:");
    Print("Total trades tracked: ", testTotalTrades);
    Print("Winning trades: ", testWinningTrades);
    Print("Total profit: $", DoubleToString(testTotalProfit, 2));

    if(testTotalTrades > 0) {
        double winRate = (double)testWinningTrades / testTotalTrades * 100;
        Print("Win rate: ", DoubleToString(winRate, 2), " % ");
        Print("Average profit per trade: $", DoubleToString(testTotalProfit / testTotalTrades, 2));
    }

    Print("Simple Breakout ML EA deinitialized");
    Print("💡 Note: Comprehensive trade results will be saved by OnTester() function");
    Print("📊 ML data collection: ", (CollectMLData ? "enabled" : "disabled"));
    Print("📊 Trade results saving: ", (SaveTradeResults ? "enabled" : "disabled"));
    Print("🎯 Test Run ID: ", actualTestRunID);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);

    // Debug logging for day detection
    static int lastLoggedHour = -1;
    if(dt.hour != lastLoggedHour) {
        Print("🔍 DEBUG: Current time - Hour: ", dt.hour, " Min: ", dt.min, " Day: ", dt.day);
        lastLoggedHour = dt.hour;
    }

    // Check for new trading day (more flexible than just midnight)
    bool isNewDay = false;

    // Method 1: Check if we've moved to a new calendar day
    static int lastProcessedDay = -1;
    if(dt.day != lastProcessedDay) {
        isNewDay = true;
        lastProcessedDay = dt.day;
        Print("🔄 New calendar day detected - Day: ", dt.day);
    }

    // Method 2: Check if we've moved to a new trading session (London open at 8:00)
    static int lastProcessedSession = -1;
    if(dt.hour == 8 && dt.min == 0 && lastProcessedSession != dt.day) {
        isNewDay = true;
        lastProcessedSession = dt.day;
        Print("🔄 New trading session detected - London open at 8:00");
    }

    // Method 3: Check if we've moved to a new D1 bar (most reliable for trading)
    static datetime lastD1Bar = 0;
    datetime currentD1Bar = iTime(_Symbol, PERIOD_D1, 0);
    if(currentD1Bar != lastD1Bar && currentD1Bar > 0) {
        isNewDay = true;
        lastD1Bar = currentD1Bar;
        Print("🔄 New D1 bar detected - New trading day");
    }

    if(isNewDay) {
        Print("🔄 New day detected - Resetting EA state");
        ResetDailyState();
    } else if (currentTime - lastDayCheck > 3600) {
        Print("🔄 Hourly update - Updating previous day levels");
        UpdatePreviousDayLevels();
        lastDayCheck = currentTime;
    }

    if(!IsNewBar()) return;
    if(PositionsTotal() > 0) return;

    // Log current state for debugging
    static int lastLoggedState = -1;
    if((int)currentState != lastLoggedState) {
        Print("🔄 State changed to: ", (int)currentState);
        lastLoggedState = (int)currentState;
    }

    CheckBreakoutAndRetest();
}

//+------------------------------------------------------------------+
//| Update previous day high and low levels                         |
//+------------------------------------------------------------------+
void UpdatePreviousDayLevels() {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);

    // Get previous day data
    if(CopyHigh(_Symbol, PERIOD_D1, 1, 1, high) > 0 &&
    CopyLow(_Symbol, PERIOD_D1, 1, 1, low) > 0) {

        previousDayHigh = high[0];
        previousDayLow = low[0];

        Print("Previous day - High: ", DoubleToString(previousDayHigh, _Digits),
        " Low: ", DoubleToString(previousDayLow, _Digits));

        // Update chart lines
        DrawPreviousDayLevels(previousDayHigh, previousDayLow, prevDayHighLine, prevDayLowLine);
    }
}

//+------------------------------------------------------------------+
//| Reset all state variables for new trading day                   |
//+------------------------------------------------------------------+
void ResetDailyState() {
    Print("🔄 Resetting daily state variables...");

    // Clear previous day chart lines
    ClearPreviousDayLines(prevDayHighLine, prevDayLowLine);

    // Update previous day levels
    UpdatePreviousDayLevels();

    // Reset breakout state variables
    currentState = WAITING_FOR_BREAKOUT;
    breakoutLevel = 0.0;
    breakoutDirection = "";
    swingPoint = 0.0;

    // Reset retest tracking variables
    bullishRetestDetected = false;
    bullishRetestLow = 999999.0;
    bearishRetestDetected = false;
    bearishRetestHigh = 0.0;

    // Reset new day levels
    newDayLow = 0;
    newDayHigh = 0;

    // Reset timing variables
    lastStateChange = 0;
    lastDayCheck = TimeCurrent();
    lastDayChecked = TimeCurrent();

    // Reset breakout tracking variables (now global)
    lastBreakoutLevel = 0.0;
    lastBreakoutDirection = "";
    retestBar = -1;
    breakoutBar = -1;
    barsSinceBreakout = 0;

    // Call the existing reset function to ensure all variables are reset
    ResetBreakoutStateVariables();

    Print("✅ Daily state reset complete");
    Print("   State: WAITING_FOR_BREAKOUT");
    Print("   Previous Day High: ", DoubleToString(previousDayHigh, _Digits));
    Print("   Previous Day Low: ", DoubleToString(previousDayLow, _Digits));
}

//+------------------------------------------------------------------+
//| Check for breakout and retest                                    |
//+------------------------------------------------------------------+
void CheckBreakoutAndRetest() {
    double currentPrice = iClose(_Symbol, _Period, 0);
    double previousClose = iClose(_Symbol, _Period, 1);
    double previousHigh = iHigh(_Symbol, _Period, 1);
    double previousLow = iLow(_Symbol, _Period, 1);
    double currentLow = iLow(_Symbol, _Period, 0);
    double previousBarClose = iClose(_Symbol, _Period, 1);

    switch((int)currentState) {
        case WAITING_FOR_BREAKOUT:
            // Look for bullish breakout
            for(int i = 1; i <= 10; i++) {
                double barClose = iClose(_Symbol, _Period, i);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    Print("🔔 Bullish breakout detected at bar ", i, " - High: ", DoubleToString(barClose, _Digits));
                    break;
                }
            }
                // Look for bearish breakout
            for(int j = 1; j <= 10; j++) {
                double barClose = iClose(_Symbol, _Period, j);
                if(barClose < previousDayLow - (5 * _Point)) {
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = j;
                    barsSinceBreakout = 0;
                    Print("🔔 Bearish breakout detected at bar ", j, " - Low: ", DoubleToString(barClose, _Digits));
                    break;
                }
            }
            break;
        case BULLISH_BREAKOUT_DETECTED:
            // Wait for price to move above previous day high and establish new day high
            if(previousClose > previousDayHigh + (5 * _Point)) {
                // Always update new day high to the highest high since breakout
                if(newDayHigh == 0 || previousHigh > newDayHigh) {
                    newDayHigh = previousHigh;
                    Print("📈 New day high established at: ", DoubleToString(newDayHigh, _Digits));
                }
                currentState = WAITING_FOR_BULLISH_RETEST;
                Print("➡️ Waiting for bullish retest at level: ", DoubleToString(previousDayHigh, _Digits));
            }
            break;
        case BEARISH_BREAKOUT_DETECTED:
            // Wait for price to move below previous day low and establish new day low
            if(previousClose < previousDayLow - (5 * _Point)) {
                    // Always update new day low to the lowest low since breakout
                if(newDayLow == 0 || previousLow < newDayLow) {
                    newDayLow = previousLow;
                    Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
                }
                currentState = WAITING_FOR_BEARISH_RETEST;
                Print("➡️ Waiting for bearish retest at level: ", DoubleToString(previousDayLow, _Digits));
            }
            break;
        case WAITING_FOR_BULLISH_RETEST:
            // Always update new day low to the lowest low since breakout (this will be our retest low)
            if(newDayLow == 0 || previousLow < newDayLow) {
                newDayLow = previousLow;
                Print("📉 New day low (retest low) established at: ", DoubleToString(newDayLow, _Digits));
            }

            if(previousClose <= previousDayHigh) {
                Print("🔍 DEBUG: Retest completed - Price bounced back down from previous day high. Current low: ", DoubleToString(currentLow, _Digits), " Previous day high: ", DoubleToString(previousDayHigh, _Digits));

                // Immediately go to WAITING_FOR_BULLISH_CLOSE state
                swingPoint = newDayLow; // Use new day low as the stop loss level
                currentState = WAITING_FOR_BULLISH_CLOSE;
                breakoutDirection = "bullish";
                bullishRetestDetected = true;
                Print("🎯 Bullish retest completed - Moving to WAITING_FOR_BULLISH_CLOSE");
                Print("🎯 Previous day high: ", DoubleToString(previousDayHigh, _Digits));
                Print("🎯 NEW day high(confirmation level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 NEW day low(stop loss level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 Waiting for close above new day high with momentum");
            }
            // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;
        case WAITING_FOR_BEARISH_RETEST:
            Print("🔍 DEBUG: In WAITING_FOR_BEARISH_RETEST - Retest detected: ", bearishRetestDetected, " Retest high: ", DoubleToString(bearishRetestHigh, _Digits));

            if(newDayLow == 0 || previousClose < newDayLow) {
                newDayLow = previousClose;
                Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
            }
                // Always update new day high to the highest high since breakout (this will be our retest high)
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                newDayHigh = previousHigh;
                Print("📈 New day high updated to: ", DoubleToString(newDayHigh, _Digits));
            }

            if(previousHigh >= previousDayLow) {
                Print("🔍 DEBUG: Retest completed - Price bounced back up from previous day low. Current high: ", DoubleToString(previousHigh, _Digits), " Previous day low: ", DoubleToString(previousDayLow, _Digits));

                // Immediately go to WAITING_FOR_BEARISH_CLOSE state
                swingPoint = newDayHigh; // Use new day high as the stop loss level
                currentState = WAITING_FOR_BEARISH_CLOSE;
                breakoutDirection = "bearish";
                bearishRetestDetected = true;
                Print("🎯 Bearish retest completed - Moving to WAITING_FOR_BEARISH_CLOSE");
                Print("🎯 Previous day low: ", DoubleToString(previousDayLow, _Digits));
                Print("🎯 NEW day low(confirmation level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 NEW day high(stop loss level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 Waiting for close below new day low with momentum");
            }
                // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;
        case WAITING_FOR_BULLISH_CLOSE:
            // Check for opposite breakout (bearish) while waiting for bullish close
            for(int k = 1; k <= 10; k++) {
                double barClose = iClose(_Symbol, _Period, k);
                if(barClose < previousDayLow - (5 * _Point)) {
                    // Reset state variables and transition to bearish breakout state
                    ResetBreakoutStateVariables();
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = k;
                    barsSinceBreakout = 0;
                    Print("🔄 Opposite breakout detected while waiting for bullish close!");
                    Print("🔔 Bearish breakout detected at bar ", k, " - Low: ", DoubleToString(barClose, _Digits));
                    return; // Exit early to avoid processing bullish logic
                }
            }

            // Update new day low if price goes lower (better risk management)
            if(newDayLow == 0 || previousLow < newDayLow) {
                double oldNewDayLow = newDayLow;
                newDayLow = previousLow;
                Print("📉 New day low updated during close phase: ", DoubleToString(oldNewDayLow, _Digits), " -> ", DoubleToString(newDayLow, _Digits));
                Print("   This improves stop loss placement for better risk management");
            }

            Print("🔍 DEBUG: In WAITING_FOR_BULLISH_CLOSE - Previous bar close: ", DoubleToString(previousBarClose, _Digits), " New day high: ", DoubleToString(newDayHigh, _Digits));
            Print("🔍 DEBUG: Need previous bar close above: ", DoubleToString(newDayHigh, _Digits));

            if(newDayHigh > 0 && previousBarClose > newDayHigh) {
                Print("✅ Bullish confirmation - Previous bar closed above NEW day high with momentum, placing buy order.");
                PlaceBullishTrade();
                currentState = WAITING_FOR_BREAKOUT;
            } else {
                Print("⏳ Waiting for previous bar to close above NEW day high: ", DoubleToString(newDayHigh, _Digits));
            }
            break;
        case WAITING_FOR_BEARISH_CLOSE:
            // Check for opposite breakout (bullish) while waiting for bearish close
            for(int k = 1; k <= 10; k++) {
                double barClose = iClose(_Symbol, _Period, k);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    // Reset state variables and transition to bullish breakout state
                    ResetBreakoutStateVariables();
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = k;
                    barsSinceBreakout = 0;
                    Print("🔄 Opposite breakout detected while waiting for bearish close!");
                    Print("🔔 Bullish breakout detected at bar ", k, " - High: ", DoubleToString(barClose, _Digits));
                    return; // Exit early to avoid processing bearish logic
                }
            }

            // Update new day high if price goes higher (better risk management)
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                double oldNewDayHigh = newDayHigh;
                newDayHigh = previousHigh;
                Print("📈 New day high updated during close phase: ", DoubleToString(oldNewDayHigh, _Digits), " -> ", DoubleToString(newDayHigh, _Digits));
                Print("   This improves stop loss placement for better risk management");
            }

            Print("🔍 DEBUG: In WAITING_FOR_BEARISH_CLOSE - Previous bar close: ", DoubleToString(previousBarClose, _Digits), " New day low: ", DoubleToString(newDayLow, _Digits));
            Print("🔍 DEBUG: Need previous bar close below: ", DoubleToString(newDayLow, _Digits));

            if(newDayLow > 0 && previousBarClose < newDayLow) {
                Print("✅ Bearish confirmation - Previous bar closed below NEW day low with momentum, placing sell order.");
                PlaceBearishTrade();
                currentState = WAITING_FOR_BREAKOUT;
            } else {
                Print("⏳ Waiting for previous bar to close below NEW day low: ", DoubleToString(newDayLow, _Digits));
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| Reset state variables when transitioning between breakout states  |
//+------------------------------------------------------------------+
void ResetBreakoutStateVariables() {
    newDayHigh = 0;
    newDayLow = 0;
    bullishRetestDetected = false;
    bearishRetestDetected = false;
    bearishRetestHigh = 0;
    bullishRetestLow = 0;
    Print("🔄 Reset breakout state variables");
}

//+------------------------------------------------------------------+
//| Check for bullish confirmation                                   |
//+------------------------------------------------------------------+
bool CheckBullishConfirmation() {
    bool confirmation = true;

    // Volume confirmation with debug logging
    if(UseVolumeConfirmation && !(DisableVolumeInTester && MQLInfoInteger(MQL_TESTER))) {
        // Get raw volume data for debugging
        long currentVolume = iVolume(_Symbol, _Period, 0);
        long volumeArray[];
        ArrayResize(volumeArray, 50);
        ArraySetAsSeries(volumeArray, true);
        int copied = CopyTickVolume(_Symbol, _Period, 0, 21, volumeArray);

        Print("🔍 Volume Debug - Current Volume: ", currentVolume, " Copied: ", copied);
        if(copied > 0) {
            Print("🔍 Volume Debug - Current Tick Volume: ", volumeArray[0]);
            Print("🔍 Volume Debug - Previous 5 volumes: ", volumeArray[1], ", ", volumeArray[2], ", ", volumeArray[3], ", ", volumeArray[4], ", ", volumeArray[5]);
        }

        // Calculate volume ratio manually for better control
        double volumeRatio = CalculateVolumeRatio();

        // Use ML-optimized volume threshold from global variable
        double volumeThreshold = UseMLVolumeThreshold ? globalVolumeRatioThreshold : 1.2;

        if(volumeRatio < volumeThreshold) {
            confirmation = false;
            Print("❌ Volume confirmation failed - ratio: ", DoubleToString(volumeRatio, 2), " (threshold: ", DoubleToString(volumeThreshold, 2), ")");
        } else {
            Print("✅ Volume confirmation passed - ratio: ", DoubleToString(volumeRatio, 2), " (threshold: ", DoubleToString(volumeThreshold, 2), ")");
        }
    } else if (DisableVolumeInTester && MQLInfoInteger(MQL_TESTER)) {
        Print("ℹ️ Volume confirmation disabled in Strategy Tester");
    }

    // Candle pattern confirmation
    if(UseCandlePatternConfirmation && confirmation) {
        string pattern = GetCandlePattern();
        if(pattern != "bullish" && pattern != "hammer") {
            confirmation = false;
            Print("❌ Candle pattern confirmation failed - pattern: ", pattern);
        }
    }

    // RSI confirmation (not oversold)
    double rsi = GetRSI(14);
    if(rsi < 30) {
        confirmation = false;
        Print("❌ RSI confirmation failed - RSI too oversold: ", DoubleToString(rsi, 2));
    }

    if(confirmation) {
        Print("✅ Bullish confirmation passed");
    }

    return confirmation;
}

//+------------------------------------------------------------------+
//| Check for bearish confirmation                                   |
//+------------------------------------------------------------------+
bool CheckBearishConfirmation() {
    bool confirmation = true;

    // Volume confirmation with debug logging
    if(UseVolumeConfirmation && !(DisableVolumeInTester && MQLInfoInteger(MQL_TESTER))) {
        // Get raw volume data for debugging
        long currentVolume = iVolume(_Symbol, _Period, 0);
        long volumeArray[];
        ArrayResize(volumeArray, 21);
        ArraySetAsSeries(volumeArray, true);
        int copied = CopyTickVolume(_Symbol, _Period, 0, 21, volumeArray);

        Print("🔍 Volume Debug - Current Volume: ", currentVolume, " Copied: ", copied);
        if(copied > 0) {
            Print("🔍 Volume Debug - Current Tick Volume: ", volumeArray[0]);
            Print("🔍 Volume Debug - Previous 5 volumes: ", volumeArray[1], ", ", volumeArray[2], ", ", volumeArray[3], ", ", volumeArray[4], ", ", volumeArray[5]);
        }

        // Calculate volume ratio manually for better control
        double volumeRatio = CalculateVolumeRatio();

        // Use ML-optimized volume threshold from global variable
        double volumeThreshold = UseMLVolumeThreshold ? globalVolumeRatioThreshold : 1.2;

        if(volumeRatio < volumeThreshold) {
            confirmation = false;
            Print("❌ Volume confirmation failed - ratio: ", DoubleToString(volumeRatio, 2), " (threshold: ", DoubleToString(volumeThreshold, 2), ")");
        } else {
            Print("✅ Volume confirmation passed - ratio: ", DoubleToString(volumeRatio, 2), " (threshold: ", DoubleToString(volumeThreshold, 2), ")");
        }
    } else if (DisableVolumeInTester && MQLInfoInteger(MQL_TESTER)) {
        Print("ℹ️ Volume confirmation disabled in Strategy Tester");
    }

    // Candle pattern confirmation - More strict for bearish signals
    if(UseCandlePatternConfirmation && confirmation) {
        string pattern = GetCandlePattern();
        string sequence = GetCandleSequence();

        // For bearish signals, require stronger confirmation
        bool validBearishPattern = false;

        // Strong bearish patterns
        if(pattern == "bearish") {
            validBearishPattern = true;
        }
        else if(pattern == "shooting_star") {
            validBearishPattern = true;
        }
        // Strong bearish sequences
        else if(sequence == "SSS") {
            validBearishPattern = true;
        }
        else if(sequence == "BSS") {
            validBearishPattern = true;
        }
        // Check for strong bearish candle
        else {
            double open[], close[], high[], low[]; // Dynamic array allocation
    ArrayResize(open, 10);
    ArrayResize(close, 10);
    ArrayResize(high, 10);
    ArrayResize(low, 10);
            CopyOpen(_Symbol, _Period, 0, 3, open);
            CopyClose(_Symbol, _Period, 0, 3, close);
            CopyHigh(_Symbol, _Period, 0, 3, high);
            CopyLow(_Symbol, _Period, 0, 3, low);

            double currentBody = MathAbs(close[0] - open[0]);
            double currentRange = high[0] - low[0];
            double bodyRatio = currentRange > 0 ? currentBody / currentRange : 0;

            // Require strong bearish candle (large body, small wicks)
            if(close[0] < open[0] && bodyRatio > 0.7) {
                validBearishPattern = true;
                Print("✅ Strong bearish candle detected - Body ratio: ", DoubleToString(bodyRatio, 2));
            }
        }

        if(!validBearishPattern) {
            confirmation = false;
            Print("❌ Candle pattern confirmation failed - pattern: ", pattern, " sequence: ", sequence);
        } else {
            Print("✅ Candle pattern confirmation passed - pattern: ", pattern, " sequence: ", sequence);
        }
    }

    // RSI confirmation - More strict for bearish signals
    double rsi = GetRSI(14);
    if(rsi < 40) { // More strict - RSI should be below 40 for bearish signal
        confirmation = false;
        Print("❌ RSI confirmation failed - RSI too oversold: ", DoubleToString(rsi, 2));
    } else if (rsi > 70) {
        // RSI overbought is good for bearish signal
        Print("✅ RSI overbought - good for bearish signal: ", DoubleToString(rsi, 2));
    } else {
        Print("ℹ️ RSI neutral: ", DoubleToString(rsi, 2));
    }



    if(confirmation) {
        Print("✅ Bearish confirmation passed");
    } else {
        Print("❌ Bearish confirmation failed");
    }

    return confirmation;
}



//+------------------------------------------------------------------+
//| Place bullish trade                                              |
//+------------------------------------------------------------------+
void PlaceBullishTrade() {
    Print("🎯 Attempting to place bullish trade for ", _Symbol);

    // Check session filtering with ML-adjusted parameters
    bool useAdvanced, useCondition, useVolatility, useTrend, useRSI;
    double minSuccessRate;
    int minTrades;

    GetMLAdjustedSessionParameters(useAdvanced, useCondition, useVolatility, useTrend, useRSI, minSuccessRate, minTrades);

    if(useAdvanced) {
        if(!IsOptimalSessionAdvanced(_Symbol, useAdvanced, useCondition, useVolatility, useTrend, useRSI, minSuccessRate, minTrades)) {
            Print("⏰ Advanced session filtering: Skipping bullish trade - not in optimal session for ", _Symbol);
            return;
        }
        Print("✅ Advanced session filtering passed for bullish trade");
    } else {
        // Check if we should use ML session filtering instead of basic filtering
        if(ShouldUseMLSessionFiltering()) {
            Print("📊 Using ML session filtering instead of basic filtering");
            string currentSession = GetCurrentSession();
            string optimalSessions = globalOptimalSessions;

            bool isOptimal = false;
            if(optimalSessions == "all" || optimalSessions == "any") {
                isOptimal = true;
            } else if(optimalSessions == "london" && currentSession == "london") {
                isOptimal = true;
            } else if(optimalSessions == "ny" && currentSession == "ny") {
                isOptimal = true;
            } else if(optimalSessions == "asian" && currentSession == "asian") {
                isOptimal = true;
            } else if(optimalSessions == "london_ny" && (currentSession == "london" || currentSession == "ny")) {
                isOptimal = true;
            }

            if(!isOptimal) {
                Print("⏰ ML session filtering: Skipping bullish trade - current session (", currentSession, ") not in optimal sessions (", optimalSessions, ")");
                return;
            }
            Print("✅ ML session filtering passed for bullish trade");
        } else {
                    if(!IsOptimalSession(_Symbol, UseSessionFiltering, AllowAllSessions, LondonSessionStart, LondonSessionEnd, NYSessionStart, NYSessionEnd, AsianSessionStart, AsianSessionEnd)) {
            Print("⏰ Session filtering: Skipping bullish trade - not in optimal session for ", _Symbol);
            return;
        }
            Print("✅ Basic session filtering passed for bullish trade");
        }
    }

    // Evaluate ML model for bullish trade
    Print("🤖 Evaluating ML model for bullish trade...");

    bool mlApproved = true;
    string mlReason = "";

    // Check if we should use directional models
    if(UseDirectionalModels && UseMLModels && !UseOnlyCombinedModel) {
        Print("⚠️  WARNING: Using directional models (may be overfitted)");
        if(!EvaluateMLForBullishTrade(UseMLModels, MLMinPredictionThreshold, MLMinConfidence)) {
            mlApproved = false;
            mlReason = "Directional model rejected";
        } else {
            mlReason = "Directional model approved";
        }
    }
    // Check if we should use combined models
    else if((UseCombinedModels || UseOnlyCombinedModel) && UseMLModels) {
        Print("✅ Using combined model (recommended)");
        if(!EvaluateMLForCombinedTrade(UseMLModels, "buy", MLMinPredictionThreshold, MLMinConfidence)) {
            mlApproved = false;
            mlReason = "Combined model rejected";
        } else {
            mlReason = "Combined model approved";
        }
    }
    // If neither is enabled, skip ML evaluation
    else if(!UseMLModels) {
        Print("ℹ️  ML models disabled");
        mlApproved = true;
        mlReason = "ML disabled";
    }
    else {
        Print("⚠️  No ML model type selected");
        mlApproved = false;
        mlReason = "No model type selected";
    }

    if(!mlApproved) {
        Print("❌ ML model rejected bullish trade: ", mlReason);
        return;
    }
    Print("✅ ML model approved bullish trade: ", mlReason);

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // For bullish trades: Stop loss below the NEW day low
    double baseStopLoss = newDayLow - (StopLossBuffer * _Point); // Add small buffer below new day low

    // Get ML-adjusted stop loss
    double stopLoss = GetMLAdjustedStopLoss(baseStopLoss, "buy", UseMLStopLossAdjustment, MLStopLossAdjustment);

    double stopDistance = entry - stopLoss;
    double takeProfit = entry + (stopDistance * RiskRewardRatio);

    // Calculate base lot size using TradeUtils
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance, _Symbol);

    // Get ML-adjusted position size
    double lotSize = GetMLAdjustedPositionSize(baseLotSize, "buy", UseMLPositionSizing, MLPositionSizingMultiplier);

    // Get comprehensive ML analysis
    double prediction, confidence;
    string recommendation;
    GetMLAnalysis("buy", prediction, confidence, recommendation, UseMLModels, MLMinPredictionThreshold, MLMaxPredictionThreshold, MLMinConfidence);

    // Place buy order using TradeUtils
    if(PlaceBuyOrder(lotSize, stopLoss, takeProfit, 0, "BreakoutBull")) {
        Print("✅ Bullish breakout trade placed with ML integration");
        Print("Entry: ", DoubleToString(entry, _Digits));
        Print("NEW day low(base stop loss level): ", DoubleToString(newDayLow, _Digits));
        Print("ML Adjusted Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("ML Adjusted Lot Size: ", DoubleToString(lotSize, 2));
        Print("ML Recommendation: ", recommendation);
        Print("ML Prediction: ", DoubleToString(prediction, 4));
        Print("ML Confidence: ", DoubleToString(confidence, 4));

        // Enhanced ML data collection
        if(CollectMLData) {
            // Initialize trade info with unique ID
            currentTrade.trade_id = ++testRunTradeCounter;
            CollectMLDataForTrade(currentTrade, "buy", entry, stopLoss, takeProfit, lotSize);
            SaveMLData(currentTrade, DATA_FILE_PATH, actualTestRunID);
        }

        // Track trade for results
        testTotalTrades++;
        lastTradeTime = TimeCurrent();

        // Store trade details for later result tracking
        StoreTradeDetails("BUY", entry, stopLoss, takeProfit, lotSize, TimeCurrent());
    }
}

//+------------------------------------------------------------------+
//| Place bearish trade                                              |
//+------------------------------------------------------------------+
void PlaceBearishTrade() {
    Print("🎯 Attempting to place bearish trade for ", _Symbol);

    // Check session filtering with ML-adjusted parameters
    bool useAdvanced, useCondition, useVolatility, useTrend, useRSI;
    double minSuccessRate;
    int minTrades;

    GetMLAdjustedSessionParameters(useAdvanced, useCondition, useVolatility, useTrend, useRSI, minSuccessRate, minTrades);

    if(useAdvanced) {
        if(!IsOptimalSessionAdvanced(_Symbol, useAdvanced, useCondition, useVolatility, useTrend, useRSI, minSuccessRate, minTrades)) {
            Print("⏰ Advanced session filtering: Skipping bearish trade - not in optimal session for ", _Symbol);
            return;
        }
        Print("✅ Advanced session filtering passed for bearish trade");
    } else {
        // Check if we should use ML session filtering instead of basic filtering
        if(ShouldUseMLSessionFiltering()) {
            Print("📊 Using ML session filtering instead of basic filtering");
            string currentSession = GetCurrentSession();
            string optimalSessions = globalOptimalSessions;

            bool isOptimal = false;
            if(optimalSessions == "all" || optimalSessions == "any") {
                isOptimal = true;
            } else if(optimalSessions == "london" && currentSession == "london") {
                isOptimal = true;
            } else if(optimalSessions == "ny" && currentSession == "ny") {
                isOptimal = true;
            } else if(optimalSessions == "asian" && currentSession == "asian") {
                isOptimal = true;
            } else if(optimalSessions == "london_ny" && (currentSession == "london" || currentSession == "ny")) {
                isOptimal = true;
            }

            if(!isOptimal) {
                Print("⏰ ML session filtering: Skipping bearish trade - current session (", currentSession, ") not in optimal sessions (", optimalSessions, ")");
                return;
            }
            Print("✅ ML session filtering passed for bearish trade");
        } else {
                    if(!IsOptimalSession(_Symbol, UseSessionFiltering, AllowAllSessions, LondonSessionStart, LondonSessionEnd, NYSessionStart, NYSessionEnd, AsianSessionStart, AsianSessionEnd)) {
            Print("⏰ Session filtering: Skipping bearish trade - not in optimal session for ", _Symbol);
            return;
        }
            Print("✅ Basic session filtering passed for bearish trade");
        }
    }

    // Evaluate ML model for bearish trade
    Print("🤖 Evaluating ML model for bearish trade...");

    bool mlApproved = true;
    string mlReason = "";

    // Check if we should use directional models
    if(UseDirectionalModels && UseMLModels && !UseOnlyCombinedModel) {
        Print("⚠️  WARNING: Using directional models (may be overfitted)");
        if(!EvaluateMLForBearishTrade(UseMLModels, MLMaxPredictionThreshold, MLMinConfidence)) {
            mlApproved = false;
            mlReason = "Directional model rejected";
        } else {
            mlReason = "Directional model approved";
        }
    }
    // Check if we should use combined models
    else if((UseCombinedModels || UseOnlyCombinedModel) && UseMLModels) {
        Print("✅ Using combined model (recommended)");
        if(!EvaluateMLForCombinedTrade(UseMLModels, "sell", MLMaxPredictionThreshold, MLMinConfidence)) {
            mlApproved = false;
            mlReason = "Combined model rejected";
        } else {
            mlReason = "Combined model approved";
        }
    }
    // If neither is enabled, skip ML evaluation
    else if(!UseMLModels) {
        Print("ℹ️  ML models disabled");
        mlApproved = true;
        mlReason = "ML disabled";
    }
    else {
        Print("⚠️  No ML model type selected");
        mlApproved = false;
        mlReason = "No model type selected";
    }

    if(!mlApproved) {
        Print("❌ ML model rejected bearish trade: ", mlReason);
        return;
    }
    Print("✅ ML model approved bearish trade: ", mlReason);

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // For bearish trades: Stop loss above the NEW day high
    double baseStopLoss = newDayHigh + (StopLossBuffer * _Point); // Add small buffer above new day high

    // Get ML-adjusted stop loss
    double stopLoss = GetMLAdjustedStopLoss(baseStopLoss, "sell", UseMLStopLossAdjustment, MLStopLossAdjustment);

    double stopDistance = stopLoss - entry;
    double takeProfit = entry - (stopDistance * RiskRewardRatio);

    // Calculate base lot size using TradeUtils
    double baseLotSize = CalculateLotSize(RiskPercent, stopDistance, _Symbol);

    // Get ML-adjusted position size
    double lotSize = GetMLAdjustedPositionSize(baseLotSize, "sell", UseMLPositionSizing, MLPositionSizingMultiplier);

    // Get comprehensive ML analysis
    double prediction, confidence;
    string recommendation;
    GetMLAnalysis("sell", prediction, confidence, recommendation, UseMLModels, MLMinPredictionThreshold, MLMaxPredictionThreshold, MLMinConfidence);

    // Place sell order using TradeUtils
    if(PlaceSellOrder(lotSize, stopLoss, takeProfit, 0, "BreakoutBear")) {
        Print("✅ Bearish breakout trade placed with ML integration");
        Print("Entry: ", DoubleToString(entry, _Digits));
        Print("NEW day high(base stop loss level): ", DoubleToString(newDayHigh, _Digits));
        Print("ML Adjusted Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("ML Adjusted Lot Size: ", DoubleToString(lotSize, 2));
        Print("ML Recommendation: ", recommendation);
        Print("ML Prediction: ", DoubleToString(prediction, 4));
        Print("ML Confidence: ", DoubleToString(confidence, 4));

        // Enhanced ML data collection
        if(CollectMLData) {
            // Initialize trade info with unique ID
            currentTrade.trade_id = ++testRunTradeCounter;
            CollectMLDataForTrade(currentTrade, "sell", entry, stopLoss, takeProfit, lotSize);
            SaveMLData(currentTrade, DATA_FILE_PATH, actualTestRunID);
        }

        // Track trade for results
        testTotalTrades++;
        lastTradeTime = TimeCurrent();

        // Store trade details for later result tracking
        StoreTradeDetails("SELL", entry, stopLoss, takeProfit, lotSize, TimeCurrent());
    }
}

//+------------------------------------------------------------------+
//| OnTester function - Runs automatically after a strategy test     |
//+------------------------------------------------------------------+
double OnTester() {
    Print("🎯 OnTester(): Starting comprehensive trade results collection...");

    // Get Strategy Tester statistics using centralized function
    double testerTotalProfit, winRate, profitFactor, maxDrawdown, grossProfit, grossLoss, expectedPayoff;
    int testerTotalTrades, testerWinningTrades;
    GetStrategyTesterStats(testerTotalProfit, testerTotalTrades, testerWinningTrades, winRate, profitFactor, maxDrawdown, grossProfit, grossLoss, expectedPayoff);

    // Collect all deals from the test using centralized function
    TradeData trades[];
    int tradeCount = CollectTradeDataFromHistory(trades, _Symbol);

    Print("📊 Collected ", tradeCount, " trades from history");

    // Save comprehensive trade results using centralized function
    SaveComprehensiveTradeResults(trades, tradeCount, testerTotalProfit, testerTotalTrades, testerWinningTrades, winRate, RESULTS_FILE_PATH, actualTestRunID);

    // Additional: Save a simple summary file for debugging
    SaveTradeSummary(testerTotalProfit, testerTotalTrades, testerWinningTrades, winRate, actualTestRunID);

    Print("🎯 OnTester(): Trade results collection completed successfully");
    Print("📊 Summary: ", testerTotalTrades, " trades, ", testerWinningTrades, " winners, $", DoubleToString(testerTotalProfit, 2), " profit");

    return testerTotalProfit; // Return the total profit as the optimization criterion
}

//+------------------------------------------------------------------+
//| Save trade summary for debugging                                 |
//+------------------------------------------------------------------+
void SaveTradeSummary(double summaryTotalProfit, int summaryTotalTrades, int summaryWinningTrades, double winRate, string testRunID) {
    string summaryFile = "SimpleBreakoutML_EA / SimpleBreakoutML_EA_Summary.txt";

    string summary = "=== TRADE SUMMARY ===\n";
    summary += "Test Run ID: " + testRunID + "\n";
    summary += "Symbol: " + _Symbol + "\n";
    summary += "Total Trades: " + IntegerToString(summaryTotalTrades) + "\n";
    summary += "Winning Trades: " + IntegerToString(summaryWinningTrades) + "\n";
    summary += "Losing Trades: " + IntegerToString(summaryTotalTrades - summaryWinningTrades) + "\n";
    summary += "Win Rate: " + DoubleToString(winRate, 2) + " % \n";
    summary += "Total Profit: $" + DoubleToString(summaryTotalProfit, 2) + "\n";
    summary += "Average Profit per Trade: $" + (summaryTotalTrades > 0 ? DoubleToString(summaryTotalProfit / summaryTotalTrades, 2) : "0.00") + "\n";
    summary += "Timestamp: " + TimeToString(TimeCurrent()) + "\n";
    summary += "=====================\n\n";

    // Improved file handling to properly append data from multiple test runs
    string existingContent = "";
    int handle = FileOpen(summaryFile, FILE_TXT|FILE_ANSI|FILE_READ|FILE_COMMON, '\n');
    if(handle != INVALID_HANDLE) {
        // Read existing content
        while(!FileIsEnding(handle)) {
            existingContent += FileReadString(handle);
        }
        FileClose(handle);
    }

    // Prepare new content by appending to existing content
    string newContent = existingContent + summary;

    // Write the content back to file
    handle = FileOpen(summaryFile, FILE_TXT|FILE_ANSI|FILE_READ|FILE_WRITE|FILE_COMMON, '\n');
    if(handle != INVALID_HANDLE) {
        FileWrite(handle, newContent);
        FileClose(handle);
        Print("✅ Trade summary saved to: ", summaryFile, " (Test Run: ", testRunID, ")");
    } else {
        Print("❌ Failed to save trade summary to: ", summaryFile);
    }
}

//+------------------------------------------------------------------+
//| Get current timeframe string for model selection                  |
//+------------------------------------------------------------------+
string GetCurrentTimeframeString() {
    switch(_Period) {
        case PERIOD_M1:  return "PERIOD_M1";
        case PERIOD_M5:  return "PERIOD_M5";
        case PERIOD_M15: return "PERIOD_M15";
        case PERIOD_M30: return "PERIOD_M30";
        case PERIOD_H1:  return "PERIOD_H1";
        case PERIOD_H4:  return "PERIOD_H4";
        case PERIOD_D1:  return "PERIOD_D1";
        case PERIOD_W1:  return "PERIOD_W1";
        case PERIOD_MN1: return "PERIOD_MN1";
        default:         return "PERIOD_H1"; // Default fallback
    }
}

//+------------------------------------------------------------------+
//| Helper functions for chart management                              |
//+------------------------------------------------------------------+









//+------------------------------------------------------------------+
//| Validate ML model settings and provide recommendations            |
//+------------------------------------------------------------------+
void ValidateMLModelSettings() {
    Print("🔍 Validating ML model settings...");

    // Check for potential issues
    bool hasIssues = false;

    if(UseDirectionalModels && !UseCombinedModels) {
        Print("⚠️  WARNING: Only directional models enabled");
        Print("   These models showed 100% accuracy in training, indicating overfitting");
        Print("   Recommendation: Enable combined models for better generalization");
        hasIssues = true;
    }

    if(!UseDirectionalModels && !UseCombinedModels && UseMLModels) {
        Print("❌ ERROR: ML models enabled but no model type selected");
        Print("   Set UseCombinedModels=true (recommended) or UseDirectionalModels=true");
        hasIssues = true;
    }

    if(UseDirectionalModels && UseCombinedModels) {
        Print("ℹ️  Both model types enabled - directional models will be used first");
        Print("   Consider using only combined models for safer operation");
    }

    if(UseOnlyCombinedModel && UseMLModels) {
        Print("✅ Using ONLY combined model (simplest approach)");
    }

    if(!hasIssues && UseCombinedModels) {
        Print("✅ ML model settings validated - using combined models (recommended)");
    }

    // Provide threshold recommendations
    if(UseMLModels) {
        Print("📊 ML Threshold Recommendations:");
        Print("   For Combined Models: 0.55-0.65 (success probability)");
        Print("   For Directional Models: 0.55-0.65 (direction confidence)");
        Print("   Current Buy Threshold: ", DoubleToString(MLMinPredictionThreshold, 3));
        Print("   Current Sell Threshold: ", DoubleToString(MLMaxPredictionThreshold, 3));

        // Warn about extreme thresholds
        if(MLMinPredictionThreshold > 0.8) {
            Print("⚠️  High buy threshold may result in few trades");
        }
        if(MLMaxPredictionThreshold < 0.2) {
            Print("⚠️  Low sell threshold may result in few trades");
        }
    }
}








