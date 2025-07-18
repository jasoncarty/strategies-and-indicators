//+------------------------------------------------------------------+
//| SimpleBreakoutML_EA.mq5 - Simple Breakout Strategy with ML Data  |
//| Based on previous day high/low breakout and retest               |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"

//--- Inputs
input group "Risk Management"
input double RiskPercent = 1.0; // Risk per trade (% of balance)
input double RiskRewardRatio = 2.0; // Risk:Reward ratio (2:1)
input int StopLossBuffer = 20; // Stop loss buffer in pips

input group "Breakout Settings"
input int RetestPips = 10; // Pips beyond previous day high/low for retest confirmation
input int StopLossPips = 15; // Pips beyond retest swing for stop loss
input bool UseVolumeConfirmation = true; // Use volume confirmation for entries
input bool DisableVolumeInTester = true; // Disable volume confirmation in Strategy Tester
input bool UseCandlePatternConfirmation = true; // Use candle pattern confirmation

input group "ML Data Collection"
input bool CollectMLData = true; // Collect indicator data for ML training
input bool SaveTradeResults = true; // Save trade outcomes for analysis
input string TestRunIdentifier = ""; // Optional identifier for this test run

input group "ML Model Integration"
input bool UseMLModels = true; // Use trained ML models for trade decisions
input bool UseMLPositionSizing = true; // Use ML for dynamic position sizing
input bool UseMLStopLossAdjustment = true; // Use ML for stop loss adjustments
input double MLMinPredictionThreshold = 0.55; // Minimum ML prediction to take bullish trade
input double MLMaxPredictionThreshold = 0.45; // Maximum ML prediction to take bearish trade
input double MLMinConfidence = 0.30; // Minimum ML confidence to take trade
input double MLMaxConfidence = 0.85; // Maximum ML confidence to take trade
input double MLPositionSizingMultiplier = 1.0; // ML position sizing multiplier
input double MLStopLossAdjustment = 1.0; // ML stop loss adjustment factor

//--- Hard-coded file names for consistency
#define DATA_FILE_NAME "SimpleBreakoutML_EA/SimpleBreakoutML_EA_ML_Data.json"
#define RESULTS_FILE_NAME "SimpleBreakoutML_EA/SimpleBreakoutML_EA_Results.json"
#define TRADE_RESULTS_FILE_NAME "SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json"
#define MODEL_PARAMS_FILE "SimpleBreakoutML_EA/ml_model_params_simple.txt"

//--- Currency pair-specific parameter files
#define MODEL_PARAMS_EURUSD "SimpleBreakoutML_EA/ml_model_params_EURUSD.txt"
#define MODEL_PARAMS_GBPUSD "SimpleBreakoutML_EA/ml_model_params_GBPUSD.txt"
#define MODEL_PARAMS_USDJPY "SimpleBreakoutML_EA/ml_model_params_USDJPY.txt"
#define MODEL_PARAMS_GBPJPY "SimpleBreakoutML_EA/ml_model_params_GBPJPY.txt"
#define MODEL_PARAMS_XAUUSD "SimpleBreakoutML_EA/ml_model_params_XAUUSD.txt"
#define MODEL_PARAMS_GENERIC "SimpleBreakoutML_EA/ml_model_params_simple.txt" // Fallback for other pairs

//--- Test Run ID (generated at initialization)
string actualTestRunID = "";

//--- Global variables
double previousDayHigh = 0;
double previousDayLow = 0;
double newDayLow = 0; // New day low established after bearish breakout
double newDayHigh = 0; // New day high established after bullish breakout
bool hasOpenPosition = false;
int totalTrades = 0;
int winningTrades = 0;
double totalProfit = 0.0;
datetime lastTradeTime = 0;

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
double swingPoint = 0.0; // The swing high/low that created the retest

//--- Retest tracking variables
bool bullishRetestDetected = false;
double bullishRetestLow = 999999.0;
bool bearishRetestDetected = false;
double bearishRetestHigh = 0.0;

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
    
    // Reset test run specific counters
    testRunTradeCounter = 0;
    
    Print("Simple Breakout ML EA initialized");
    Print("Test Run ID: ", actualTestRunID);
    Print("Risk per trade: ", RiskPercent, "%");
    Print("Risk:Reward ratio: ", RiskRewardRatio, ":1");
    Print("Retest pips: ", RetestPips);
    Print("Stop loss pips: ", StopLossPips);
    Print("ML data collection: ", (CollectMLData ? "enabled" : "disabled"));
    Print("Trade results saving: ", (SaveTradeResults ? "enabled" : "disabled"));
    
    // Set up trade object
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Update EA input parameters based on ML training results
    UpdateEAInputParameters("SimpleBreakoutML_EA");
    
    // Log ML model status
    if(UseMLModels) {
        Print("🤖 ML Model Integration: ENABLED");
        Print("   ML Position Sizing: ", (UseMLPositionSizing ? "enabled" : "disabled"));
        Print("   ML Stop Loss Adjustment: ", (UseMLStopLossAdjustment ? "enabled" : "disabled"));
        Print("   ML Min Prediction Threshold: ", DoubleToString(MLMinPredictionThreshold, 4));
        Print("   ML Max Prediction Threshold: ", DoubleToString(MLMaxPredictionThreshold, 4));
        Print("   ML Min Confidence: ", DoubleToString(MLMinConfidence, 4));
        Print("   ML Max Confidence: ", DoubleToString(MLMaxConfidence, 4));
        Print("   ML Position Sizing Multiplier: ", DoubleToString(MLPositionSizingMultiplier, 2));
        Print("   ML Stop Loss Adjustment: ", DoubleToString(MLStopLossAdjustment, 2));
    } else {
        Print("🤖 ML Model Integration: DISABLED");
    }
    
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
    Print("Total trades tracked: ", totalTrades);
    Print("Winning trades: ", winningTrades);
    Print("Total profit: $", DoubleToString(totalProfit, 2));
    
    if(totalTrades > 0) {
        double winRate = (double)winningTrades / totalTrades * 100;
        Print("Win rate: ", DoubleToString(winRate, 2), "%");
        Print("Average profit per trade: $", DoubleToString(totalProfit / totalTrades, 2));
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
    // Increment bar counter for tracking
    barCounter++;
    
    // Check for new day and update previous day levels
    static datetime lastDayCheck = 0;
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    // Debug logging for day detection
    static int lastLoggedHour = -1;
    if(dt.hour != lastLoggedHour) {
        Print("🔍 DEBUG: Current time - Hour: ", dt.hour, " Min: ", dt.min, " Day: ", dt.day);
        lastLoggedHour = dt.hour;
    }
    
    if(dt.hour == 0 && dt.min == 0 && currentTime != lastDayCheck) {
        Print("🔄 New day detected - Resetting EA state");
        ClearPreviousDayLines();
        UpdatePreviousDayLevels();
        newDayLow = 0;
        newDayHigh = 0;
        lastDayCheck = currentTime;
        lastDayChecked = currentTime;
        currentState = WAITING_FOR_BREAKOUT; // Reset state on new day
        Print("🔄 State reset to WAITING_FOR_BREAKOUT");
    } else if(currentTime - lastDayCheck > 3600) {
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
        DrawPreviousDayLevels();
    }
}

//+------------------------------------------------------------------+
//| Check for breakout and retest                                    |
//+------------------------------------------------------------------+
void CheckBreakoutAndRetest() {
    double currentPrice = iClose(_Symbol, _Period, 0);
    double currentHigh = iHigh(_Symbol, _Period, 0);
    double previousHigh = iHigh(_Symbol, _Period, 1);
    double previousLow = iLow(_Symbol, _Period, 1);
    double currentLow = iLow(_Symbol, _Period, 0);
    static double lastBreakoutLevel = 0.0;
    static string lastBreakoutDirection = "";
    double previousBarClose = iClose(_Symbol, _Period, 1);
    static int retestBar = -1;
    static int breakoutBar = -1;
    static int barsSinceBreakout = 0;
    switch((int)currentState) {
        case WAITING_FOR_BREAKOUT:
            // Look for bullish breakout
            for(int i = 1; i <= 10; i++) {
                double barHigh = iHigh(_Symbol, _Period, i);
                if(barHigh > previousDayHigh + (5 * _Point)) {
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barHigh;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    Print("🔔 Bullish breakout detected at bar ", i, " - High: ", DoubleToString(barHigh, _Digits));
                    break;
                }
            }
            // Look for bearish breakout
            for(int j = 1; j <= 10; j++) {
                double barLow = iLow(_Symbol, _Period, j);
                if(barLow < previousDayLow - (5 * _Point)) {
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barLow;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = j;
                    barsSinceBreakout = 0;
                    Print("🔔 Bearish breakout detected at bar ", j, " - Low: ", DoubleToString(barLow, _Digits));
                    break;
                }
            }
            break;
        case BULLISH_BREAKOUT_DETECTED:
            // Wait for price to move above previous day high and establish new day high
            if(previousHigh > previousDayHigh + (5 * _Point)) {
                // Always update new day high to the highest high since breakout
                if(newDayHigh == 0 || previousHigh > newDayHigh) {
                    newDayHigh = previousHigh;
                    Print("📈 New day high established at: ", DoubleToString(newDayHigh, _Digits));
                }
                currentState = WAITING_FOR_BULLISH_RETEST;
                Print("➡️  Waiting for bullish retest at level: ", DoubleToString(previousDayHigh, _Digits));
            }
            break;
        case BEARISH_BREAKOUT_DETECTED:
            // Wait for price to move below previous day low and establish new day low
            if(previousLow < previousDayLow - (5 * _Point)) {
                // Always update new day low to the lowest low since breakout
                if(newDayLow == 0 || previousLow < newDayLow) {
                    newDayLow = previousLow;
                    Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
                }
                currentState = WAITING_FOR_BEARISH_RETEST;
                Print("➡️  Waiting for bearish retest at level: ", DoubleToString(previousDayLow, _Digits));
            }
            break;
        case WAITING_FOR_BULLISH_RETEST:
            // Always update new day low to the lowest low since breakout (this will be our retest low)
            if(newDayHigh == 0 || previousHigh > newDayHigh) {
                newDayHigh = previousHigh;
                Print("📈 New day high established at: ", DoubleToString(newDayHigh, _Digits));
            }

            if(previousLow <= previousDayHigh) {
                Print("🔍 DEBUG: Retest completed - Price bounced back down from previous day high. Current low: ", DoubleToString(currentHigh, _Digits), " Previous day high: ", DoubleToString(previousDayHigh, _Digits));
                
                // Immediately go to WAITING_FOR_BULLISH_CLOSE state
                swingPoint = newDayLow; // Use new day high as the stop loss level
                currentState = WAITING_FOR_BULLISH_CLOSE;
                breakoutDirection = "bullish";
                bullishRetestDetected = true;
                Print("🎯 Bullish retest completed - Moving to WAITING_FOR_BULLISH_CLOSE");
                Print("🎯 Previous day high: ", DoubleToString(previousDayHigh, _Digits));
                Print("🎯 NEW day high (confirmation level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 NEW day low (stop loss level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 Waiting for close above new day high with momentum");
            }
            // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;
        case WAITING_FOR_BEARISH_RETEST:
            Print("🔍 DEBUG: In WAITING_FOR_BEARISH_RETEST - Retest detected: ", bearishRetestDetected, " Retest high: ", DoubleToString(bearishRetestHigh, _Digits));

            if(newDayLow == 0 || previousLow < newDayLow) {
                newDayLow = previousLow;
                Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
            }
            // Always update new day high to the highest high since breakout (this will be our retest high)
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                newDayHigh = previousHigh;
                Print("📈 New day high updated to: ", DoubleToString(newDayHigh, _Digits));
            }
            
            if(previousHigh >= previousDayLow) {
                Print("🔍 DEBUG: Retest completed - Price bounced back up from previous day low. Current high: ", DoubleToString(currentHigh, _Digits), " Previous day low: ", DoubleToString(previousDayLow, _Digits));
                
                // Immediately go to WAITING_FOR_BEARISH_CLOSE state
                swingPoint = newDayHigh; // Use new day high as the stop loss level
                currentState = WAITING_FOR_BEARISH_CLOSE;
                breakoutDirection = "bearish";
                bearishRetestDetected = true;
                Print("🎯 Bearish retest completed - Moving to WAITING_FOR_BEARISH_CLOSE");
                Print("🎯 Previous day low: ", DoubleToString(previousDayLow, _Digits));
                Print("🎯 NEW day low (confirmation level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 NEW day high (stop loss level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 Waiting for close below new day low with momentum");
            }
            // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;
        case WAITING_FOR_BULLISH_CLOSE:
            if(newDayLow == 0 || previousLow < newDayLow) {
                newDayLow = previousLow;
                Print("📈 New day low established at: ", DoubleToString(newDayLow, _Digits));
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
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                newDayHigh = previousHigh;
                Print("📈 New day high updated to: ", DoubleToString(newDayHigh, _Digits));
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
//| Check for bullish confirmation                                   |
//+------------------------------------------------------------------+
bool CheckBullishConfirmation() {
    bool confirmation = true;
    
    // Volume confirmation with debug logging
    if(UseVolumeConfirmation && !(DisableVolumeInTester && MQLInfoInteger(MQL_TESTER))) {
        // Get raw volume data for debugging
        long currentVolume = iVolume(_Symbol, _Period, 0);
        long volumeArray[21];
        ArraySetAsSeries(volumeArray, true);
        int copied = CopyTickVolume(_Symbol, _Period, 0, 21, volumeArray);
        
        Print("🔍 Volume Debug - Current Volume: ", currentVolume, " Copied: ", copied);
        if(copied > 0) {
            Print("🔍 Volume Debug - Current Tick Volume: ", volumeArray[0]);
            Print("🔍 Volume Debug - Previous 5 volumes: ", volumeArray[1], ", ", volumeArray[2], ", ", volumeArray[3], ", ", volumeArray[4], ", ", volumeArray[5]);
        }
        
        // Calculate volume ratio manually for better control
        double volumeRatio = CalculateVolumeRatio();
        
        if(volumeRatio < 1.2) {
            confirmation = false;
            Print("❌ Volume confirmation failed - ratio: ", DoubleToString(volumeRatio, 2));
        } else {
            Print("✅ Volume confirmation passed - ratio: ", DoubleToString(volumeRatio, 2));
        }
    } else if(DisableVolumeInTester && MQLInfoInteger(MQL_TESTER)) {
        Print("ℹ️  Volume confirmation disabled in Strategy Tester");
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
    double rsi = GetRSI();
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
        long volumeArray[21];
        ArraySetAsSeries(volumeArray, true);
        int copied = CopyTickVolume(_Symbol, _Period, 0, 21, volumeArray);
        
        Print("🔍 Volume Debug - Current Volume: ", currentVolume, " Copied: ", copied);
        if(copied > 0) {
            Print("🔍 Volume Debug - Current Tick Volume: ", volumeArray[0]);
            Print("🔍 Volume Debug - Previous 5 volumes: ", volumeArray[1], ", ", volumeArray[2], ", ", volumeArray[3], ", ", volumeArray[4], ", ", volumeArray[5]);
        }
        
        // Calculate volume ratio manually for better control
        double volumeRatio = CalculateVolumeRatio();
        
        if(volumeRatio < 1.2) {
            confirmation = false;
            Print("❌ Volume confirmation failed - ratio: ", DoubleToString(volumeRatio, 2));
        } else {
            Print("✅ Volume confirmation passed - ratio: ", DoubleToString(volumeRatio, 2));
        }
    } else if(DisableVolumeInTester && MQLInfoInteger(MQL_TESTER)) {
        Print("ℹ️  Volume confirmation disabled in Strategy Tester");
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
            double open[3], close[3], high[3], low[3];
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
    double rsi = GetRSI();
    if(rsi < 40) { // More strict - RSI should be below 40 for bearish signal
        confirmation = false;
        Print("❌ RSI confirmation failed - RSI too oversold: ", DoubleToString(rsi, 2));
    } else if(rsi > 70) {
        // RSI overbought is good for bearish signal
        Print("✅ RSI overbought - good for bearish signal: ", DoubleToString(rsi, 2));
    } else {
        Print("ℹ️  RSI neutral: ", DoubleToString(rsi, 2));
    }
    

    
    if(confirmation) {
        Print("✅ Bearish confirmation passed");
    } else {
        Print("❌ Bearish confirmation failed");
    }
    
    return confirmation;
}

//+------------------------------------------------------------------+
//| Calculate volume ratio with better Strategy Tester support       |
//+------------------------------------------------------------------+
double CalculateVolumeRatio() {
    long volumeArray[21];
    ArraySetAsSeries(volumeArray, true);
    
    // Try to get tick volume data
    int copied = CopyTickVolume(_Symbol, _Period, 0, 21, volumeArray);
    
    if(copied < 20) {
        Print("⚠️  Could not get enough volume data, using fallback calculation");
        // Fallback: use regular volume data
        long currentVolume = iVolume(_Symbol, _Period, 0);
        long avgVolume = 0;
        int validVolumes = 0;
        
        for(int i = 1; i <= 20; i++) {
            long vol = iVolume(_Symbol, _Period, i);
            if(vol > 0) {
                avgVolume += vol;
                validVolumes++;
            }
        }
        
        if(validVolumes > 0) {
            avgVolume /= validVolumes;
            double ratio = avgVolume > 0 ? (double)currentVolume / avgVolume : 1.0;
            Print("🔍 Fallback Volume Ratio: ", DoubleToString(ratio, 2), " (Current: ", currentVolume, " Avg: ", avgVolume, ")");
            return ratio;
        } else {
            Print("⚠️  No valid volume data available, using neutral ratio");
            return 1.0;
        }
    }
    
    // Calculate average volume from previous 20 bars
    long avgVolume = 0;
    int validVolumes = 0;
    
    for(int i = 1; i <= 20; i++) {
        if(volumeArray[i] > 0) {
            avgVolume += volumeArray[i];
            validVolumes++;
        }
    }
    
    if(validVolumes > 0) {
        avgVolume /= validVolumes;
        double ratio = avgVolume > 0 ? (double)volumeArray[0] / avgVolume : 1.0;
        Print("🔍 Volume Ratio: ", DoubleToString(ratio, 2), " (Current: ", volumeArray[0], " Avg: ", avgVolume, ")");
        return ratio;
    } else {
        Print("⚠️  No valid volume data in array, using neutral ratio");
        return 1.0;
    }
}

//+------------------------------------------------------------------+
//| Place bullish trade                                              |
//+------------------------------------------------------------------+
void PlaceBullishTrade() {
    // Evaluate ML model for bullish trade
    if(!EvaluateMLForBullishTrade(UseMLModels, MLMinPredictionThreshold, MLMinConfidence)) {
        Print("❌ ML model rejected bullish trade");
        return;
    }
    
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
        Print("NEW day low (base stop loss level): ", DoubleToString(newDayLow, _Digits));
        Print("ML Adjusted Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("ML Adjusted Lot Size: ", DoubleToString(lotSize, 2));
        Print("ML Recommendation: ", recommendation);
        Print("ML Prediction: ", DoubleToString(prediction, 4));
        Print("ML Confidence: ", DoubleToString(confidence, 4));
        
        // Enhanced ML data collection
        if(CollectMLData) {
            CollectMLDataForTrade(currentTrade, "buy", entry, stopLoss, takeProfit, lotSize);
            SaveMLData(currentTrade, DATA_FILE_NAME, actualTestRunID);
        }
        
        totalTrades++;
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Place bearish trade                                              |
//+------------------------------------------------------------------+
void PlaceBearishTrade() {
    // Evaluate ML model for bearish trade
    if(!EvaluateMLForBearishTrade(UseMLModels, MLMaxPredictionThreshold, MLMinConfidence)) {
        Print("❌ ML model rejected bearish trade");
        return;
    }
    
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
        Print("NEW day high (base stop loss level): ", DoubleToString(newDayHigh, _Digits));
        Print("ML Adjusted Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("Base Lot Size: ", DoubleToString(baseLotSize, 2));
        Print("ML Adjusted Lot Size: ", DoubleToString(lotSize, 2));
        Print("ML Recommendation: ", recommendation);
        Print("ML Prediction: ", DoubleToString(prediction, 4));
        Print("ML Confidence: ", DoubleToString(confidence, 4));
        
        // Enhanced ML data collection
        if(CollectMLData) {
            CollectMLDataForTrade(currentTrade, "sell", entry, stopLoss, takeProfit, lotSize);
            SaveMLData(currentTrade, DATA_FILE_NAME, actualTestRunID);
        }
        
        totalTrades++;
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| OnTester function - Runs automatically after a strategy test     |
//+------------------------------------------------------------------+
double OnTester() {
    Print("🎯 OnTester(): Starting comprehensive trade results collection...");
    
    // Get Strategy Tester statistics using centralized function
    double testTotalProfit, winRate, profitFactor, maxDrawdown, grossProfit, grossLoss, expectedPayoff;
    int testTotalTrades, testWinningTrades;
    GetStrategyTesterStats(testTotalProfit, testTotalTrades, testWinningTrades, winRate, profitFactor, maxDrawdown, grossProfit, grossLoss, expectedPayoff);
    
    // Collect all deals from the test using centralized function
    TradeData trades[];
    int tradeCount = CollectTradeDataFromHistory(trades);
    
    // Save comprehensive trade results using centralized function
    SaveComprehensiveTradeResults(trades, tradeCount, testTotalProfit, testTotalTrades, testWinningTrades, winRate, RESULTS_FILE_NAME, actualTestRunID);
    
    Print("🎯 OnTester(): Trade results collection completed successfully");
    
    // Also save trade results in the specific format expected by the ML trainer
    SaveTradeResultsForML(trades, tradeCount, TRADE_RESULTS_FILE_NAME, actualTestRunID);
    
    return testTotalProfit; // Return the total profit as the optimization criterion
}

//+------------------------------------------------------------------+
//| Helper functions for indicators                                  |
//+------------------------------------------------------------------+

//--- Get RSI
double GetRSI() {
    int handle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 50.0;
}

//--- Get Stochastic
double GetStochasticMain() {
    int handle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 50.0;
}

double GetStochasticSignal() {
    int handle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 1, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 50.0;
}

//--- Get MACD
double GetMACDMain() {
    int handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 0.0;
}

double GetMACDSignal() {
    int handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 1, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 0.0;
}



//--- Get Bollinger Bands
double GetBollingerUpper() {
    int handle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 1, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 0.0;
}

double GetBollingerLower() {
    int handle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 2, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 0.0;
}

double GetBollingerPosition() {
    double upper = GetBollingerUpper();
    double lower = GetBollingerLower();
    double currentPrice = iClose(_Symbol, _Period, 0);
    
    if(upper > lower) {
        return (currentPrice - lower) / (upper - lower);
    }
    return 0.5;
}

//--- Get ADX
double GetADX() {
    int handle = iADX(_Symbol, _Period, 14);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 25.0;
}

//--- Get Williams %R
double GetWilliamsR() {
    int handle = iWPR(_Symbol, _Period, 14);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return -50.0;
}

//--- Get CCI
double GetCCI() {
    int handle = iCCI(_Symbol, _Period, 14, PRICE_TYPICAL);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 0.0;
}

//--- Get Momentum
double GetMomentum() {
    int handle = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);
    if(handle != INVALID_HANDLE) {
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0) {
            IndicatorRelease(handle);
            return buf[0];
        }
        IndicatorRelease(handle);
    }
    return 100.0;
}

//--- Get Candle Pattern
string GetCandlePattern() {
    double open[3], close[3], high[3], low[3];
    CopyOpen(_Symbol, _Period, 0, 3, open);
    CopyClose(_Symbol, _Period, 0, 3, close);
    CopyHigh(_Symbol, _Period, 0, 3, high);
    CopyLow(_Symbol, _Period, 0, 3, low);
    
    // First check for specific patterns
    if(IsBullishEngulfing(open, close, 1)) return "bullish";
    else if(IsBearishEngulfing(open, close, 1)) return "bearish";
    else if(IsHammer(open, high, low, close, 0)) return "hammer";
    else if(IsShootingStar(open, high, low, close, 0)) return "shooting_star";
    
    // Check for candle sequences (more important for breakout strategy)
    string sequence = GetCandleSequence();
    
    // Debug logging for candle analysis
    static int debugCounter = 0;
    debugCounter++;
    if(debugCounter % 10 == 0) { // Log every 10th call to avoid spam
        Print("🔍 Candle Analysis - Sequence: ", sequence);
        Print("🔍 Current Candle - Open: ", DoubleToString(open[0], _Digits), " Close: ", DoubleToString(close[0], _Digits));
        Print("🔍 Previous Candle - Open: ", DoubleToString(open[1], _Digits), " Close: ", DoubleToString(close[1], _Digits));
        Print("🔍 Two Bars Ago - Open: ", DoubleToString(open[2], _Digits), " Close: ", DoubleToString(close[2], _Digits));
    }
    
    // Strong bearish sequences
    if(sequence == "SSS") {
        if(debugCounter % 10 == 0) Print("🎯 Detected SSS - Strong bearish sequence");
        return "bearish"; // Three consecutive bearish candles
    }
    else if(sequence == "SSB") {
        if(debugCounter % 10 == 0) Print("🎯 Detected SSB - Two bearish followed by bullish (potential reversal)");
        return "bearish"; // Two bearish followed by bullish (potential reversal)
    }
    else if(sequence == "BSS") {
        if(debugCounter % 10 == 0) Print("🎯 Detected BSS - Bullish followed by two bearish (trend change)");
        return "bearish"; // Bullish followed by two bearish (trend change)
    }
    
    // Strong bullish sequences
    else if(sequence == "BBB") {
        if(debugCounter % 10 == 0) Print("🎯 Detected BBB - Strong bullish sequence");
        return "bullish"; // Three consecutive bullish candles
    }
    else if(sequence == "BBS") {
        if(debugCounter % 10 == 0) Print("🎯 Detected BBS - Two bullish followed by bearish (potential reversal)");
        return "neutral"; // Two bullish followed by bearish (potential reversal) - not clearly bullish
    }
    else if(sequence == "SBB") {
        if(debugCounter % 10 == 0) Print("🎯 Detected SBB - Bearish followed by two bullish (trend change)");
        return "bullish"; // Bearish followed by two bullish (trend change) - this is bullish
    }
    
    // Check for strong individual candles
    double currentBody = MathAbs(close[0] - open[0]);
    double currentRange = high[0] - low[0];
    double bodyRatio = currentRange > 0 ? currentBody / currentRange : 0;
    
    // Strong bearish candle (large body, small wicks)
    if(close[0] < open[0] && bodyRatio > 0.6) {
        if(debugCounter % 10 == 0) Print("🎯 Detected strong bearish candle - Body ratio: ", DoubleToString(bodyRatio, 2));
        return "bearish";
    }
    // Strong bullish candle (large body, small wicks)
    else if(close[0] > open[0] && bodyRatio > 0.6) {
        if(debugCounter % 10 == 0) Print("🎯 Detected strong bullish candle - Body ratio: ", DoubleToString(bodyRatio, 2));
        return "bullish";
    }
    
    if(debugCounter % 10 == 0) Print("❌ No significant pattern detected - Sequence: ", sequence, " Body ratio: ", DoubleToString(bodyRatio, 2));
    return "none";
}

//--- Get Candle Sequence
string GetCandleSequence() {
    double open[3], close[3];
    CopyOpen(_Symbol, _Period, 0, 3, open);
    CopyClose(_Symbol, _Period, 0, 3, close);
    
    string seq = "";
    for(int i = 2; i >= 0; i--) {
        seq += (close[i] > open[i] ? "B" : "S");
    }
    return seq;
}

//--- Get Trend Direction
string GetTrendDirection(ENUM_TIMEFRAMES timeframe) {
    int ma20Handle = iMA(_Symbol, timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ma50Handle = iMA(_Symbol, timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(ma20Handle != INVALID_HANDLE && ma50Handle != INVALID_HANDLE) {
        double ma20[2], ma50[2];
        ArraySetAsSeries(ma20, true);
        ArraySetAsSeries(ma50, true);
        
        if(CopyBuffer(ma20Handle, 0, 0, 2, ma20) > 0 && 
           CopyBuffer(ma50Handle, 0, 0, 2, ma50) > 0) {
            
            double currentPrice = iClose(_Symbol, timeframe, 0);
            
            IndicatorRelease(ma20Handle);
            IndicatorRelease(ma50Handle);
            
            if(ma20[0] > ma50[0] && currentPrice > ma20[0]) return "bullish";
            else if(ma20[0] < ma50[0] && currentPrice < ma20[0]) return "bearish";
            else return "neutral";
        }
        
        IndicatorRelease(ma20Handle);
        IndicatorRelease(ma50Handle);
    }
    
    return "neutral";
}

//--- Get Price Position
double GetPricePosition() {
    double high = previousDayHigh;
    double low = previousDayLow;
    double currentPrice = iClose(_Symbol, _Period, 0);
    
    if(high > low) {
        return (currentPrice - low) / (high - low);
    }
    return 0.5;
}

//--- Check for new bar
bool IsNewBar() {
    static datetime lastBarTime = 0;
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime == lastBarTime) return false;
    lastBarTime = barTime;
    return true;
}

//+------------------------------------------------------------------+
//| Find the highest point of the bearish retest (beyond prev day low) |
//+------------------------------------------------------------------+
double FindBearishRetestHigh() {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    // Look back up to 20 bars to find the retest area
    if(CopyHigh(_Symbol, _Period, 0, 20, high) > 0 && 
       CopyLow(_Symbol, _Period, 0, 20, low) > 0) {
        
        double retestHigh = 0.0;
        bool foundRetest = false;
        
        // Find the highest point in the retest area (beyond previous day low)
        for(int i = 0; i < 20; i++) {
            // Check if this bar is part of the retest (low touches or goes beyond prev day low)
            if(low[i] <= previousDayLow + (RetestPips * _Point)) {
                foundRetest = true;
                if(high[i] > retestHigh) {
                    retestHigh = high[i];
                }
            }
        }
        
        if(foundRetest && retestHigh > 0) {
            Print("🎯 Bearish retest high found: ", DoubleToString(retestHigh, _Digits));
            return retestHigh;
        }
    }
    
    // Fallback to previous swing high if no retest found
    Print("⚠️  No bearish retest found, using fallback swing high");
    return FindSwingHigh(10);
}

//+------------------------------------------------------------------+
//| Find the lowest point of the bullish retest (beyond prev day high) |
//+------------------------------------------------------------------+
double FindBullishRetestLow() {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    // Look back up to 20 bars to find the retest area
    if(CopyHigh(_Symbol, _Period, 0, 20, high) > 0 && 
       CopyLow(_Symbol, _Period, 0, 20, low) > 0) {
        
        double retestLow = 999999.0;
        bool foundRetest = false;
        
        // Find the lowest point in the retest area (beyond previous day high)
        for(int i = 0; i < 20; i++) {
            // Check if this bar is part of the retest (high touches or goes beyond prev day high)
            if(high[i] >= previousDayHigh - (RetestPips * _Point)) {
                foundRetest = true;
                if(low[i] < retestLow) {
                    retestLow = low[i];
                }
            }
        }
        
        if(foundRetest && retestLow < 999999.0) {
            Print("🎯 Bullish retest low found: ", DoubleToString(retestLow, _Digits));
            return retestLow;
        }
    }
    
    // Fallback to previous swing low if no retest found
    Print("⚠️  No bullish retest found, using fallback swing low");
    return FindSwingLow(10);
}

//+------------------------------------------------------------------+
//| Find swing high within specified bars                           |
//+------------------------------------------------------------------+
double FindSwingHigh(int bars) {
    double high[];
    ArraySetAsSeries(high, true);
    
    if(CopyHigh(_Symbol, _Period, 0, bars, high) > 0) {
        double swingHigh = high[0];
        for(int i = 1; i < bars; i++) {
            if(high[i] > swingHigh) {
                swingHigh = high[i];
            }
        }
        return swingHigh;
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Find swing low within specified bars                            |
//+------------------------------------------------------------------+
double FindSwingLow(int bars) {
    double low[];
    ArraySetAsSeries(low, true);
    
    if(CopyLow(_Symbol, _Period, 0, bars, low) > 0) {
        double swingLow = low[0];
        for(int i = 1; i < bars; i++) {
            if(low[i] < swingLow) {
                swingLow = low[i];
            }
        }
        return swingLow;
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get current position count                                       |
//+------------------------------------------------------------------+
int GetCurrentPositionCount() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Draw previous day high and low lines on chart                   |
//+------------------------------------------------------------------+
void DrawPreviousDayLevels() {
    // Delete existing lines first
    ObjectDelete(0, prevDayHighLine);
    ObjectDelete(0, prevDayLowLine);
    
    // Draw previous day high line
    ObjectCreate(0, prevDayHighLine, OBJ_HLINE, 0, 0, previousDayHigh);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_COLOR, clrGreen);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_WIDTH, 2);
    ObjectSetString(0, prevDayHighLine, OBJPROP_TEXT, "Previous day - High: " + DoubleToString(previousDayHigh, _Digits));
    
    // Draw previous day low line
    ObjectCreate(0, prevDayLowLine, OBJ_HLINE, 0, 0, previousDayLow);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_WIDTH, 2);
    ObjectSetString(0, prevDayLowLine, OBJPROP_TEXT, "Previous day - Low: " + DoubleToString(previousDayLow, _Digits));
    
    Print("📊 Chart lines drawn - High: ", DoubleToString(previousDayHigh, _Digits), " Low: ", DoubleToString(previousDayLow, _Digits));
}

//+------------------------------------------------------------------+
//| Clear previous day lines from chart                              |
//+------------------------------------------------------------------+
void ClearPreviousDayLines() {
    ObjectDelete(0, prevDayHighLine);
    ObjectDelete(0, prevDayLowLine);
    Print("🗑️  Previous day lines cleared from chart");
} 

//+------------------------------------------------------------------+
//| ML Model Evaluation Functions (now using TradeUtils.mqh)         |
//+------------------------------------------------------------------+
// All ML evaluation functions are now centralized in TradeUtils.mqh 