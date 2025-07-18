//+------------------------------------------------------------------+
//|                                    ICT_FVG_Trader_EA_Optimized.mq5 |
//|                                  Copyright 2024, Jason Carty           |
//|                     https://github.com/jason-carty/mt5-trader-ea  |
//+------------------------------------------------------------------+

#include "../WebServerAPI.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <MovingAverages.mqh>

#property copyright "Copyright 2024"
#property version   "2.0"
#property description "ICT Fair Value Gap and Imbalance Trading Expert Advisor - ML Optimized"
#property description "Enhanced with ML-based insights for improved performance"
#property description "Focuses on volume analysis, ATR optimization, and symbol-specific settings"
#property link      "https://github.com/jason-carty/mt5-trader-ea"

// Risk Management Parameters - OPTIMIZED
input group "Risk Management - ML Optimized"
input double RiskPercent = 0.8;          // Risk percentage per trade (reduced from 1.0% based on ML analysis)
input double RRRatio = 2.5;              // Risk:Reward ratio (increased from 2.0 for better profitability)
input double MinLotSize = 0.01;          // Minimum lot size
input double MaxLotSize = 50.0;          // Maximum lot size (reduced from 100.0 based on ML analysis)
input int    MaxPositions = 3;           // Maximum number of open positions (reduced from 5)

// Stop Loss Parameters - ENHANCED ATR USAGE
input group "Stop Loss Settings - ML Optimized"
input bool   UseATRStopLoss = true;      // Use ATR-based stop loss (critical based on ML)
input double ATRMultiplier = 1.5;        // ATR multiplier (reduced from 2.0 for tighter stops)
input int    ATRPeriod = 14;             // ATR period
input bool   UseTrailingStop = true;     // Use trailing stop
input double TrailStartPercent = 30.0;   // Percentage of SL distance to move before trailing (increased)
input double TrailDistancePercent = 60.0; // Percentage of initial SL to maintain as trail distance (increased)

// Volume Analysis - MOST IMPORTANT FEATURE
input group "Volume Analysis - ML Critical"
input bool   RequireVolumeConfirmation = true; // Require volume confirmation (CRITICAL)
input double MinVolumeRatio = 1.2;       // Minimum volume ratio (reduced from 1.5)
input double OptimalVolumeRatio = 2.0;   // Optimal volume ratio for best trades
input int    VolumeLookback = 20;        // Bars to analyze for volume
input bool   UseVolumeWeightedSizing = true; // Use volume ratio to adjust position size

// Imbalance Confirmation Parameters - ENHANCED
input group "Imbalance Settings - ML Optimized"
input int    ImbalanceConfirmationBars = 2;   // Number of bars to confirm imbalance (increased from 1)
input double MinImbalanceRatio = 2.0;         // Minimum ratio between buy/sell volume (increased from 1.5)
input int    MinImbalanceVolume = 75;         // Minimum volume for imbalance consideration (increased from 50)
input bool   RequireStackedImbalance = false; // Require stacked imbalances for entry
input bool   UseEnhancedFVGDetection = true;  // Use enhanced FVG detection logic

// Trading Parameters
input group "Trading Settings"
input bool   RequireConfirmation = false; // Ask for confirmation before placing trades (disabled for automation)
input int    MagicNumber = 123456;       // Magic number for order identification

// ICT Kill Zone Settings - OPTIMIZED
input group "ICT Kill Zone Settings - ML Optimized"
input bool   UseKillZones = true;        // Only trade during ICT kill zones
input bool   UseLondonKillZone = true;   // London Kill Zone (7:00-10:00 GMT)
input int    LondonKillZoneStart = 7;    // London Kill Zone start hour (GMT)
input int    LondonKillZoneEnd = 10;     // London Kill Zone end hour (GMT)
input bool   UseNewYorkKillZone = true;  // New York Kill Zone (13:00-16:00 GMT)
input int    NewYorkKillZoneStart = 13;  // New York Kill Zone start hour (GMT)
input int    NewYorkKillZoneEnd = 16;    // New York Kill Zone end hour (GMT)
input bool   UseAsianKillZone = false;   // Asian Kill Zone (22:00-02:00 GMT next day)
input int    AsianKillZoneStart = 22;    // Asian Kill Zone start hour (GMT)
input int    AsianKillZoneEnd = 2;       // Asian Kill Zone end hour (GMT next day)
input bool   UseLondonOpenKillZone = true; // London Open Kill Zone (7:00-9:00 GMT)
input int    LondonOpenKillZoneStart = 7; // London Open Kill Zone start hour (GMT)
input int    LondonOpenKillZoneEnd = 9;   // London Open Kill Zone end hour (GMT)
input bool   UseNewYorkOpenKillZone = true; // New York Open Kill Zone (13:00-15:00 GMT)
input int    NewYorkOpenKillZoneStart = 13; // New York Open Kill Zone start hour (GMT)
input int    NewYorkOpenKillZoneEnd = 15;   // New York Open Kill Zone end hour (GMT)

// Enhanced ICT Strategy Parameters - OPTIMIZED
input group "Market Structure & Bias - ML Enhanced"
input bool   UseMarketStructureFilter = true;  // Use market structure analysis
input ENUM_TIMEFRAMES StructureTimeframe = PERIOD_H1;  // Timeframe for market structure analysis (changed from H4)
input int    StructureLookback = 50;          // Bars to analyze for market structure
input bool   RequireLiquiditySweep = true;    // Require liquidity sweep before kill zone
input int    LiquiditySweepLookback = 20;     // Bars to look back for liquidity sweeps
input double MinSweepDistance = 10.0;         // Minimum distance for liquidity sweep (points)

input group "Optimal Trade Entry (OTE) Settings"
input bool   UseOTEFilter = true;             // Use OTE point filtering
input bool   UseFibonacciLevels = true;       // Use Fibonacci retracement levels
input double FibLevel1 = 0.236;               // First Fibonacci level
input double FibLevel2 = 0.382;               // Second Fibonacci level
input double FibLevel3 = 0.618;               // Third Fibonacci level
input double FibLevel4 = 0.786;               // Fourth Fibonacci level
input bool   UseOrderBlocks = true;           // Use order block detection
input int    OrderBlockLookback = 10;         // Bars to look back for order blocks
input double OrderBlockMinSize = 5.0;         // Minimum order block size (points)

input group "Standard Deviation Settings"
input bool   UseStandardDeviation = true;     // Use standard deviation for targets
input int    StdDevPeriod = 20;               // Period for standard deviation calculation
input double StdDevMultiplier = 1.0;          // Multiplier for standard deviation

input group "Lower Timeframe Analysis - ML Optimized"
input bool   UseLowerTimeframeTriggers = true; // Use lower timeframe for precise entries
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_M5; // Lower timeframe for entry triggers (changed from M15)
input int    LTFStructureLookback = 20;       // Bars to analyze for LTF structure breaks
input bool   RequireLTFConfirmation = true;   // Require LTF confirmation candle
input bool   RequireOTERetest = true;         // Require retest of OTE zone on LTF
input double OTERetestTolerance = 10.0;       // Tolerance for OTE retest (points)
input int    MinLTFConditions = 2;            // Minimum number of LTF conditions required (1-3)
input bool   RequireStructureBreak = true;    // Require LTF structure break
input bool   AllowLTFOnlyTrades = false;      // Allow trades based purely on LTF signals (no FVG required)
input bool   RequireMarketStructureForLTF = true; // Require market structure alignment for LTF-only trades

// Symbol-Specific Optimizations - ML Based
input group "Symbol-Specific Settings - ML Optimized"
input bool   UseSymbolOptimization = true;    // Use symbol-specific optimizations
input double EURUSDRiskMultiplier = 1.2;      // EURUSD+ risk multiplier (performs better)
input double XAUUSDRiskMultiplier = 0.8;      // XAUUSD+ risk multiplier (performs worse)
input bool   PreferEURUSD = true;             // Prefer EURUSD+ trades when possible
input bool   AvoidH4Timeframe = true;         // Avoid H4 timeframe trades (performs worst)

// Trading Restrictions - ENHANCED
input group "Trading Restrictions - ML Optimized"
input bool RestrictToICTMacros = true; // Only trade during ICT Macro times
input string CustomRestrictTimes = ""; // e.g. "10:00-10:10,14:00-15:00" (24h, EST)
input int ServerToESTOffset = -7;      // Hours to subtract from server time to get EST
// News Filter Settings
input int NewsBlockMinutesBefore = 30; // Minutes before news to block trading
input int NewsBlockMinutesAfter  = 30; // Minutes after news to block trading
input bool BlockHighImpactOnly   = true; // Only block for high-impact news

// ML-Based Performance Tracking
input group "ML Performance Tracking"
input bool   EnableMLTracking = true;         // Enable ML-based performance tracking
input int    PerformanceLookback = 100;       // Number of trades to analyze for ML insights

// Global variables
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
ulong currentPositionTicket = 0;
double initialStopLoss = 0;
datetime lastBarTime = 0;
bool isNewBar = false;
bool isNewLTFCandle = false;

// Lower Timeframe Analysis Global Variables
struct LowerTimeframeAnalysis {
    bool hasStructureBreak;   // Whether there's a break of structure on LTF
    bool hasConfirmationCandle; // Whether there's a confirmation candle
    bool hasOTERetest;        // Whether price retested the OTE zone
    datetime structureBreakTime; // Time of structure break
    datetime confirmationTime;   // Time of confirmation candle
    datetime retestTime;      // Time of OTE retest
    double structureBreakLevel; // Level where structure broke
    double confirmationLevel;   // Level of confirmation
    double retestLevel;       // Level of OTE retest
    bool isBullishBreak;      // True for bullish break, false for bearish
};

LowerTimeframeAnalysis g_ltfAnalysis;    // Current lower timeframe analysis
datetime g_lastLTFCandleTime = 0;        // Track last lower timeframe candle time

// ML Performance tracking
struct MLPerformanceData {
    int totalTrades;
    int winningTrades;
    double totalProfit;
    double avgVolumeRatio;
    double avgATRValue;
    double avgLotSize;
    double winRate;
    double profitFactor;
};

MLPerformanceData mlData = {};

// Enhanced volume analysis structure
struct VolumeAnalysis {
    double currentVolume;
    double averageVolume;
    double volumeRatio;
    double volumeMA;
    bool isHighVolume;
    bool isOptimalVolume;
    double volumeWeight;
};

// Enhanced FVG detection structure
struct EnhancedFVGInfo {
    bool exists;
    bool isBullish;
    double gapStart;
    double gapEnd;
    bool isFilled;
    datetime fillTime;
    double volumeRatio;
    double atrValue;
    double strength;
    bool hasVolumeConfirmation;
    bool hasATRConfirmation;
};

// Trading Conditions structure
struct TradingConditions {
    // Basic trade info
    datetime entryTime;
    ENUM_ORDER_TYPE orderType;
    double entryPrice;
    double stopLoss;
    double targetPrice;
    double lotSize;

    // Market conditions at entry
    double currentPrice;
    double atrValue;
    double volume;
    double volumeRatio;

    // ICT Strategy conditions
    bool inKillZone;
    string killZoneType;
    bool hasMarketStructure;
    bool marketStructureBullish;
    bool hasLiquiditySweep;
    datetime liquiditySweepTime;
    double liquiditySweepLevel;

    // FVG/Imbalance conditions
    bool hasFVG;
    string fvgType;  // "Bullish", "Bearish"
    double fvgStart;
    double fvgEnd;
    bool fvgFilled;
    datetime fvgTime;
    double fvgStrength;

    // OTE conditions
    bool hasOTE;
    string oteType;  // "FVG", "Fib", "OrderBlock", "StdDev"
    double oteLevel;
    double oteStrength;

    // Lower timeframe conditions
    bool hasLTFBreak;
    bool hasLTFConfirmation;
    bool hasOTERetest;
    string ltfBreakType;  // "Bullish", "Bearish"

    // Fibonacci levels
    bool nearFibLevel;
    double fibLevel;
    string fibType;  // "0.236", "0.382", "0.618", "0.786"

    // Order block conditions
    bool nearOrderBlock;
    double orderBlockHigh;
    double orderBlockLow;
    bool orderBlockBullish;

    // Volume conditions
    bool volumeConfirmation;
    double volumeRatioValue;
    bool hasVolumeConfirmation;
    bool hasATRConfirmation;

    // Risk management
    double riskAmount;
    double riskPercent;
    double rewardRiskRatio;

    // Additional context
    string additionalNotes;
};

// Time interval structure
struct TimeInterval {
   int startHour;
   int startMinute;
   int endHour;
   int endMinute;
};

const TimeInterval ICTMacros[] = {
   {2, 33, 3, 0},    // London Macro 1
   {4, 3, 4, 30},    // London Macro 2
   {8, 50, 9, 10},   // NY AM Macro 1
   {9, 50, 10, 10},  // NY AM Macro 2
   {10, 50, 11, 10}, // NY AM Macro 3
   {11, 50, 12, 10}, // NY Lunch Macro
   {13, 10, 13, 40}, // NY PM Macro
   {15, 15, 15, 45}  // NY Last Hour Macro
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== ICT FVG Trader EA Optimized v2.0 ===");
    Print("ML-Based Optimizations Applied:");
    Print("- Enhanced Volume Analysis (Most Important Feature)");
    Print("- Optimized ATR Usage (Second Most Important)");
    Print("- Improved Position Sizing (Lot Size Critical)");
    Print("- Symbol-Specific Risk Adjustments");
    Print("- Timeframe Filtering (Avoid H4)");
    Print("- Enhanced FVG Detection");
    
    // Initialize trade object
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialize symbol info
    symbolInfo.Name(_Symbol);
    symbolInfo.RefreshRates();
    
    // Initialize ML performance tracking
    if(EnableMLTracking) {
        InitializeMLTracking();
    }
    
    Print("EA Initialized Successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== ICT FVG Trader EA Optimized Deinitialized ===");
    if(EnableMLTracking) {
        PrintMLPerformanceSummary();
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime != lastBarTime)
    {
        isNewBar = true;
        lastBarTime = currentBarTime;
        
        // Check for new LTF candle
        datetime currentLTFTime = iTime(_Symbol, LowerTimeframe, 0);
        static datetime lastLTFTime = 0;
        if(currentLTFTime != lastLTFTime)
        {
            isNewLTFCandle = true;
            lastLTFTime = currentLTFTime;
            
            // Lower Timeframe Analysis - on every lower timeframe candle close
            if(UseLowerTimeframeTriggers)
            {
                Print("=== Processing New Lower Timeframe Candle (", EnumToString(LowerTimeframe), ") ===");
                Print("LTF Time: ", TimeToString(iTime(_Symbol, LowerTimeframe, 0)));
                
                g_ltfAnalysis = AnalyzeLowerTimeframeStructure();
            }
        }
        else
        {
            isNewLTFCandle = false;
        }
    }
    else
    {
        isNewBar = false;
    }
    
    // Update trailing stops
    CheckTrailingStop();
    
    // Check for new trading opportunities on new bar or LTF candle
    if(isNewBar || isNewLTFCandle)
    {
        CheckForTradingOpportunities();
    }
}

//+------------------------------------------------------------------+
//| Enhanced Volume Analysis - ML Critical Feature                   |
//+------------------------------------------------------------------+
VolumeAnalysis AnalyzeVolume()
{
    VolumeAnalysis analysis = {};
    
    // Get recent volume data
    long volumes[];
    ArraySetAsSeries(volumes, true);
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, VolumeLookback + 5, volumes) <= 0)
    {
        Print("Failed to get volume data for analysis");
        return analysis;
    }
    
    // Current volume (last completed bar)
    analysis.currentVolume = (double)volumes[1];
    
    // Calculate average volume (excluding current and last bar)
    double totalVolume = 0;
    for(int i = 2; i < VolumeLookback + 2; i++)
    {
        totalVolume += (double)volumes[i];
    }
    analysis.averageVolume = totalVolume / VolumeLookback;
    
    // Calculate volume ratio
    analysis.volumeRatio = analysis.averageVolume > 0 ? analysis.currentVolume / analysis.averageVolume : 0;
    
    // Determine volume characteristics
    analysis.isHighVolume = analysis.volumeRatio >= MinVolumeRatio;
    analysis.isOptimalVolume = analysis.volumeRatio >= OptimalVolumeRatio;
    
    // Calculate volume weight for position sizing
    if(UseVolumeWeightedSizing)
    {
        analysis.volumeWeight = MathMin(analysis.volumeRatio / OptimalVolumeRatio, 2.0);
        analysis.volumeWeight = MathMax(analysis.volumeWeight, 0.5);
    }
    else
    {
        analysis.volumeWeight = 1.0;
    }
    
    // Calculate volume moving average
    analysis.volumeMA = analysis.averageVolume;
    
    Print("=== Enhanced Volume Analysis ===");
    Print("Current Volume: ", analysis.currentVolume);
    Print("Average Volume: ", analysis.averageVolume);
    Print("Volume Ratio: ", DoubleToString(analysis.volumeRatio, 2));
    Print("Is High Volume: ", analysis.isHighVolume);
    Print("Is Optimal Volume: ", analysis.isOptimalVolume);
    Print("Volume Weight: ", DoubleToString(analysis.volumeWeight, 2));
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Enhanced ATR Analysis - Second Most Important Feature            |
//+------------------------------------------------------------------+
double GetOptimizedATRValue()
{
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    int atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
    
    if(atrHandle == INVALID_HANDLE || CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) <= 0)
    {
        Print("Failed to get ATR values");
        IndicatorRelease(atrHandle);
        return 0;
    }
    
    double currentATR = atrBuffer[0];
    double previousATR = atrBuffer[1];
    double atrChange = previousATR > 0 ? (currentATR - previousATR) / previousATR : 0;
    
    Print("=== Enhanced ATR Analysis ===");
    Print("Current ATR: ", DoubleToString(currentATR, 5));
    Print("Previous ATR: ", DoubleToString(previousATR, 5));
    Print("ATR Change: ", DoubleToString(atrChange * 100, 2), "%");
    
    IndicatorRelease(atrHandle);
    return currentATR;
}

//+------------------------------------------------------------------+
//| Enhanced FVG Detection - Improved Logic                          |
//+------------------------------------------------------------------+
EnhancedFVGInfo FindEnhancedFVG(bool isBullish)
{
    EnhancedFVGInfo fvg = {};
    
    // Get recent price data
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, 10, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_CURRENT, 0, 10, low) <= 0 ||
       CopyClose(_Symbol, PERIOD_CURRENT, 0, 10, close) <= 0 ||
       CopyOpen(_Symbol, PERIOD_CURRENT, 0, 10, open) <= 0)
    {
        Print("Failed to get price data for FVG detection");
        return fvg;
    }
    
    // Enhanced FVG detection logic
    if(isBullish)
    {
        // Bullish FVG: Current low > Previous high
        if(low[0] > high[2] && close[1] > high[2])
        {
            fvg.exists = true;
            fvg.isBullish = true;
            fvg.gapStart = high[2];
            fvg.gapEnd = low[0];
            fvg.strength = (low[0] - high[2]) / _Point; // Gap size in points
            
            // Check if FVG is filled
            if(low[1] <= high[2])
            {
                fvg.isFilled = true;
                fvg.fillTime = iTime(_Symbol, PERIOD_CURRENT, 1);
            }
        }
    }
    else
    {
        // Bearish FVG: Current high < Previous low
        if(high[0] < low[2] && close[1] < low[2])
        {
            fvg.exists = true;
            fvg.isBullish = false;
            fvg.gapStart = low[2];
            fvg.gapEnd = high[0];
            fvg.strength = (low[2] - high[0]) / _Point; // Gap size in points
            
            // Check if FVG is filled
            if(high[1] >= low[2])
            {
                fvg.isFilled = true;
                fvg.fillTime = iTime(_Symbol, PERIOD_CURRENT, 1);
            }
        }
    }
    
    // Add volume and ATR analysis to FVG
    if(fvg.exists)
    {
        VolumeAnalysis volume = AnalyzeVolume();
        fvg.volumeRatio = volume.volumeRatio;
        fvg.hasVolumeConfirmation = volume.isHighVolume;
        
        double atr = GetOptimizedATRValue();
        fvg.atrValue = atr;
        fvg.hasATRConfirmation = atr > 0;
        
        Print("=== Enhanced FVG Detection ===");
        Print("FVG Type: ", fvg.isBullish ? "Bullish" : "Bearish");
        Print("Gap Start: ", DoubleToString(fvg.gapStart, _Digits));
        Print("Gap End: ", DoubleToString(fvg.gapEnd, _Digits));
        Print("Gap Strength: ", DoubleToString(fvg.strength, 0), " points");
        Print("Is Filled: ", fvg.isFilled);
        Print("Volume Ratio: ", DoubleToString(fvg.volumeRatio, 2));
        Print("Has Volume Confirmation: ", fvg.hasVolumeConfirmation);
        Print("ATR Value: ", DoubleToString(fvg.atrValue, 5));
        Print("Has ATR Confirmation: ", fvg.hasATRConfirmation);
    }
    
    return fvg;
}

//+------------------------------------------------------------------+
//| ML-Optimized Position Size Calculation                           |
//+------------------------------------------------------------------+
double CalculateOptimizedLotSize(double entryPrice, double stopLoss, VolumeAnalysis &volume)
{
    // Base risk calculation
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    
    // Apply symbol-specific risk multiplier
    double symbolMultiplier = 1.0;
    if(UseSymbolOptimization)
    {
        if(StringFind(_Symbol, "EURUSD") >= 0)
            symbolMultiplier = EURUSDRiskMultiplier;
        else if(StringFind(_Symbol, "XAUUSD") >= 0)
            symbolMultiplier = XAUUSDRiskMultiplier;
    }
    
    riskAmount *= symbolMultiplier;
    
    // Apply volume-based adjustment
    riskAmount *= volume.volumeWeight;
    
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    // Calculate stop loss distance in points
    double stopDistance = MathAbs(entryPrice - stopLoss) / _Point;
    
    // Calculate required position size
    double lotSize = riskAmount / (stopDistance * tickValue);
    
    // Adjust for symbol lot step
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Ensure lot size is within allowed range
    double minLot = MathMax(MinLotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    double maxLot = MathMin(MaxLotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    Print("=== ML-Optimized Lot Size Calculation ===");
    Print("Base Risk Amount: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));
    Print("Symbol Multiplier: ", DoubleToString(symbolMultiplier, 2));
    Print("Volume Weight: ", DoubleToString(volume.volumeWeight, 2));
    Print("Final Risk Amount: ", DoubleToString(riskAmount, 2));
    Print("Stop Distance: ", DoubleToString(stopDistance, 0), " points");
    Print("Lot Size: ", DoubleToString(lotSize, 2));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Enhanced Trading Conditions Check                                |
//+------------------------------------------------------------------+
bool CheckEnhancedEntryConditions(EnhancedFVGInfo &fvg, bool isBuy)
{
    if(!fvg.exists) return false;
    
    // Timeframe filtering (avoid H4 based on ML analysis)
    if(AvoidH4Timeframe && Period() == PERIOD_H4)
    {
        Print("Trade blocked: Avoiding H4 timeframe based on ML analysis");
        return false;
    }
    
    // Volume confirmation (most important feature)
    if(RequireVolumeConfirmation && !fvg.hasVolumeConfirmation)
    {
        Print("Trade blocked: Insufficient volume confirmation");
        return false;
    }
    
    // ATR confirmation (second most important feature)
    if(UseATRStopLoss && !fvg.hasATRConfirmation)
    {
        Print("Trade blocked: No ATR confirmation");
        return false;
    }
    
    // Kill zone check
    if(UseKillZones && !IsInKillZone())
    {
        Print("Trade blocked: Not in kill zone");
        return false;
    }
    
    // Market structure check
    if(UseMarketStructureFilter && !CheckMarketStructure(isBuy))
    {
        Print("Trade blocked: Market structure not aligned");
        return false;
    }
    
    // FVG strength check
    if(fvg.strength < 10) // Minimum 10 points gap
    {
        Print("Trade blocked: FVG too weak (", DoubleToString(fvg.strength, 0), " points)");
        return false;
    }
    
    // Lower Timeframe Analysis check
    if(UseLowerTimeframeTriggers && !CheckLowerTimeframeConditions(isBuy))
    {
        Print("Trade blocked: LTF conditions not met");
        return false;
    }
    
    Print("=== Enhanced Entry Conditions Met ===");
    Print("Volume Confirmation: ", fvg.hasVolumeConfirmation);
    Print("ATR Confirmation: ", fvg.hasATRConfirmation);
    Print("Kill Zone: ", IsInKillZone());
    Print("Market Structure: ", CheckMarketStructure(isBuy));
    Print("FVG Strength: ", DoubleToString(fvg.strength, 0), " points");
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is in kill zone                            |
//+------------------------------------------------------------------+
bool IsInKillZone()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = dt.hour;
    
    // London Kill Zone
    if(UseLondonKillZone && currentHour >= LondonKillZoneStart && currentHour < LondonKillZoneEnd)
        return true;
    
    // New York Kill Zone
    if(UseNewYorkKillZone && currentHour >= NewYorkKillZoneStart && currentHour < NewYorkKillZoneEnd)
        return true;
    
    // Asian Kill Zone (handles overnight)
    if(UseAsianKillZone)
    {
        if(AsianKillZoneStart < AsianKillZoneEnd)
        {
            if(currentHour >= AsianKillZoneStart && currentHour < AsianKillZoneEnd)
                return true;
        }
        else
        {
            if(currentHour >= AsianKillZoneStart || currentHour < AsianKillZoneEnd)
                return true;
        }
    }
    
    // London Open Kill Zone
    if(UseLondonOpenKillZone && currentHour >= LondonOpenKillZoneStart && currentHour < LondonOpenKillZoneEnd)
        return true;
    
    // New York Open Kill Zone
    if(UseNewYorkOpenKillZone && currentHour >= NewYorkOpenKillZoneStart && currentHour < NewYorkOpenKillZoneEnd)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check market structure alignment                                 |
//+------------------------------------------------------------------+
bool CheckMarketStructure(bool isBuy)
{
    // Simple market structure check - can be enhanced
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, StructureTimeframe, 0, StructureLookback, high) <= 0 ||
       CopyLow(_Symbol, StructureTimeframe, 0, StructureLookback, low) <= 0)
    {
        return false;
    }
    
    // Check for higher highs and higher lows (bullish) or lower highs and lower lows (bearish)
    if(isBuy)
    {
        // Check for bullish structure (higher highs and higher lows)
        for(int i = 1; i < 5; i++)
        {
            if(high[i] <= high[i+1] || low[i] <= low[i+1])
                return false;
        }
    }
    else
    {
        // Check for bearish structure (lower highs and lower lows)
        for(int i = 1; i < 5; i++)
        {
            if(high[i] >= high[i+1] || low[i] >= low[i+1])
                return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Main trading logic                                               |
//+------------------------------------------------------------------+
void CheckForTradingOpportunities()
{
    // Check if we can open new positions
    if(PositionsTotal() >= MaxPositions)
    {
        return;
    }
    
    // Get current price
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Find enhanced FVGs
    EnhancedFVGInfo bullishFVG = FindEnhancedFVG(true);
    EnhancedFVGInfo bearishFVG = FindEnhancedFVG(false);
    
    // Check for trading opportunities
    bool tradeFound = false;
    
    // Check filled bearish FVGs for LONG opportunities (opposite direction)
    if(bearishFVG.exists && bearishFVG.isFilled && CheckEnhancedEntryConditions(bearishFVG, true))
    {
        Print("Buy signal confirmed at filled bearish FVG (resistance turned support)");
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double stopLoss = bearishFVG.gapEnd - (10 * _Point);
        double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, true);
        
        VolumeAnalysis volume = AnalyzeVolume();
        double lotSize = CalculateOptimizedLotSize(entryPrice, stopLoss, volume);
        
        if(RequireConfirmation)
        {
            string message = "Buy Signal Detected (Filled Bearish FVG - ML Optimized)\n" +
                           "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                           "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                           "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                           "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                           "Volume Ratio: " + DoubleToString(volume.volumeRatio, 2) + "\n" +
                           "ATR Value: " + DoubleToString(bearishFVG.atrValue, 5);
            
            if(MessageBox(message, "ICT FVG Trader Optimized", MB_YESNO|MB_ICONQUESTION) == IDYES)
            {
                OpenOptimizedPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize, volume, bearishFVG);
                tradeFound = true;
            }
        }
        else
        {
            OpenOptimizedPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize, volume, bearishFVG);
            tradeFound = true;
        }
    }
    
    // Check filled bullish FVGs for SHORT opportunities (opposite direction)
    if(!tradeFound && bullishFVG.exists && bullishFVG.isFilled && CheckEnhancedEntryConditions(bullishFVG, false))
    {
        Print("Sell signal confirmed at filled bullish FVG (support turned resistance)");
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double stopLoss = bullishFVG.gapEnd + (10 * _Point);
        double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, false);
        
        VolumeAnalysis volume = AnalyzeVolume();
        double lotSize = CalculateOptimizedLotSize(entryPrice, stopLoss, volume);
        
        if(RequireConfirmation)
        {
            string message = "Sell Signal Detected (Filled Bullish FVG - ML Optimized)\n" +
                           "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                           "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                           "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                           "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                           "Volume Ratio: " + DoubleToString(volume.volumeRatio, 2) + "\n" +
                           "ATR Value: " + DoubleToString(bullishFVG.atrValue, 5);
            
            if(MessageBox(message, "ICT FVG Trader Optimized", MB_YESNO|MB_ICONQUESTION) == IDYES)
            {
                OpenOptimizedPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize, volume, bullishFVG);
                tradeFound = true;
            }
        }
        else
        {
            OpenOptimizedPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize, volume, bullishFVG);
            tradeFound = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Open optimized position with ML tracking                         |
//+------------------------------------------------------------------+
void OpenOptimizedPosition(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double targetPrice, 
                          double lotSize, VolumeAnalysis &volume, EnhancedFVGInfo &fvg)
{
    // Capture trading conditions for analytics
    TradingConditions conditions = CaptureTradingConditions(orderType, entryPrice, stopLoss, targetPrice, lotSize);
    
    // Log trading conditions to file
    LogTradingConditions(conditions);
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = targetPrice;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "ICT FVG Optimized v2.0";
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            currentPositionTicket = result.order;
            initialStopLoss = stopLoss;
            
            Print("=== Optimized Position Opened ===");
            Print("Ticket: ", currentPositionTicket);
            Print("Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
            Print("Entry: ", DoubleToString(entryPrice, _Digits));
            Print("Stop Loss: ", DoubleToString(stopLoss, _Digits));
            Print("Target: ", DoubleToString(targetPrice, _Digits));
            Print("Lot Size: ", DoubleToString(lotSize, 2));
            Print("Volume Ratio: ", DoubleToString(volume.volumeRatio, 2));
            Print("FVG Strength: ", DoubleToString(fvg.strength, 0), " points");
            Print("Trading conditions logged for analytics");
            
            // Update ML tracking
            if(EnableMLTracking)
            {
                UpdateMLTracking(volume, fvg, lotSize);
            }
        }
        else
        {
            Print("Failed to open position: ", GetTradeRetcodeDescription(result.retcode));
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate target price based on RRR                               |
//+------------------------------------------------------------------+
double CalculateTargetPrice(double entryPrice, double stopLoss, bool isBuy)
{
   double stopDistance = MathAbs(entryPrice - stopLoss);
   double targetDistance = stopDistance * RRRatio;
   return isBuy ? entryPrice + targetDistance : entryPrice - targetDistance;
}

//+------------------------------------------------------------------+
//| Check and update trailing stop                                   |
//+------------------------------------------------------------------+
void CheckTrailingStop()
{
    if(!UseTrailingStop || currentPositionTicket == 0) return;
    
    if(!PositionSelectByTicket(currentPositionTicket)) return;
    
    double currentSL = PositionGetDouble(POSITION_SL);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Calculate points from open to initial SL
    double totalSLPoints = MathAbs(openPrice - initialStopLoss);
    
    // Calculate the minimum price move needed before trailing
    double minPriceMove = totalSLPoints * (TrailStartPercent / 100.0);
    
    // Calculate trail distance
    double trailDistance = totalSLPoints * (TrailDistancePercent / 100.0);
    
    // For buy positions
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        if(currentPrice >= openPrice + minPriceMove)
        {
            double newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
                ModifyPosition(newSL);
            }
        }
    }
    // For sell positions
    else
    {
        if(currentPrice <= openPrice - minPriceMove)
        {
            double newSL = currentPrice + trailDistance;
            if(newSL < currentSL)
            {
                ModifyPosition(newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify position's stop loss                                       |
//+------------------------------------------------------------------+
bool ModifyPosition(double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP);
    request.position = currentPositionTicket;
    
    return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| ML Performance Tracking Functions                                 |
//+------------------------------------------------------------------+
void InitializeMLTracking()
{
    mlData.totalTrades = 0;
    mlData.winningTrades = 0;
    mlData.totalProfit = 0;
    mlData.avgVolumeRatio = 0;
    mlData.avgATRValue = 0;
    mlData.avgLotSize = 0;
    mlData.winRate = 0;
    mlData.profitFactor = 0;
    
    Print("ML Performance Tracking Initialized");
}

void UpdateMLTracking(VolumeAnalysis &volume, EnhancedFVGInfo &fvg, double lotSize)
{
    mlData.totalTrades++;
    mlData.avgVolumeRatio = (mlData.avgVolumeRatio * (mlData.totalTrades - 1) + volume.volumeRatio) / mlData.totalTrades;
    mlData.avgATRValue = (mlData.avgATRValue * (mlData.totalTrades - 1) + fvg.atrValue) / mlData.totalTrades;
    mlData.avgLotSize = (mlData.avgLotSize * (mlData.totalTrades - 1) + lotSize) / mlData.totalTrades;
    
    Print("ML Tracking Updated - Total Trades: ", mlData.totalTrades);
}

void PrintMLPerformanceSummary()
{
    Print("=== ML Performance Summary ===");
    Print("Total Trades: ", mlData.totalTrades);
    Print("Average Volume Ratio: ", DoubleToString(mlData.avgVolumeRatio, 2));
    Print("Average ATR Value: ", DoubleToString(mlData.avgATRValue, 5));
    Print("Average Lot Size: ", DoubleToString(mlData.avgLotSize, 2));
    Print("Win Rate: ", DoubleToString(mlData.winRate * 100, 2), "%");
    Print("Profit Factor: ", DoubleToString(mlData.profitFactor, 2));
}

//+------------------------------------------------------------------+
//| Lower Timeframe Analysis Functions                                 |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis AnalyzeLowerTimeframeStructure()
{
    LowerTimeframeAnalysis result = {};
    
    if(!UseLowerTimeframeTriggers) return result;
    
    Print("=== Analyzing Lower Timeframe Structure (", EnumToString(LowerTimeframe), ") ===");
    
    // Get LTF data
    double highs[], lows[], opens[], closes[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);
    
    int copied = CopyHigh(_Symbol, LowerTimeframe, 0, LTFStructureLookback, highs);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF high data");
        return result;
    }
    
    copied = CopyLow(_Symbol, LowerTimeframe, 0, LTFStructureLookback, lows);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF low data");
        return result;
    }
    
    copied = CopyOpen(_Symbol, LowerTimeframe, 0, LTFStructureLookback, opens);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF open data");
        return result;
    }
    
    copied = CopyClose(_Symbol, LowerTimeframe, 0, LTFStructureLookback, closes);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF close data");
        return result;
    }
    
    // 1. Check for Market Structure Break (BOS)
    result = CheckLowerTimeframeStructureBreak(result, highs, lows, closes);
    
    // 2. Check for Confirmation Candle
    if(RequireLTFConfirmation)
    {
        result = CheckLowerTimeframeConfirmation(result, opens, highs, lows, closes);
    }
    
    // 3. Check for OTE Zone Retest (simplified - no OTE points in optimized version)
    if(RequireOTERetest)
    {
        result = CheckLowerTimeframeOTERetest(result, highs, lows);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check for break of structure on lower timeframe                   |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis CheckLowerTimeframeStructureBreak(LowerTimeframeAnalysis &analysis,
                                                         const double &highs[],
                                                         const double &lows[],
                                                         const double &closes[])
{
    Print("--- Checking for Lower Timeframe Structure Break ---");
    
    // Find recent swing high and low
    double swingHigh = 0, swingLow = DBL_MAX;
    int swingHighIndex = -1, swingLowIndex = -1;
    
    // Look for swing points in the last 10 bars
    for(int i = 2; i < 10; i++)
    {
        // Check for swing high
        if(highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
           highs[i] > highs[i+1] && highs[i] > highs[i+2])
        {
            if(highs[i] > swingHigh)
            {
                swingHigh = highs[i];
                swingHighIndex = i;
            }
        }
        
        // Check for swing low
        if(lows[i] < lows[i-1] && lows[i] < lows[i-2] &&
           lows[i] < lows[i+1] && lows[i] < lows[i+2])
        {
            if(lows[i] < swingLow)
            {
                swingLow = lows[i];
                swingLowIndex = i;
            }
        }
    }
    
    // Check for structure break
    if(swingHighIndex >= 0 && swingLowIndex >= 0)
    {
        // Check if current price broke above swing high (bullish break)
        if(closes[0] > swingHigh + (5 * _Point))
        {
            analysis.hasStructureBreak = true;
            analysis.isBullishBreak = true;
            analysis.structureBreakTime = iTime(_Symbol, LowerTimeframe, 0);
            analysis.structureBreakLevel = swingHigh;
            Print("Bullish Structure Break detected on LTF at ", swingHigh);
        }
        // Check if current price broke below swing low (bearish break)
        else if(closes[0] < swingLow - (5 * _Point))
        {
            analysis.hasStructureBreak = true;
            analysis.isBullishBreak = false;
            analysis.structureBreakTime = iTime(_Symbol, LowerTimeframe, 0);
            analysis.structureBreakLevel = swingLow;
            Print("Bearish Structure Break detected on LTF at ", swingLow);
        }
    }
    
    if(!analysis.hasStructureBreak)
    {
        Print("No structure break detected on LTF");
    }
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Check for confirmation candle from order block on lower timeframe |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis CheckLowerTimeframeConfirmation(LowerTimeframeAnalysis &analysis,
                                                       const double &opens[],
                                                       const double &highs[],
                                                       const double &lows[],
                                                       const double &closes[])
{
    Print("--- Checking for Lower Timeframe Confirmation Candle ---");
    
    // Look for confirmation candle in the last 3 bars
    for(int i = 0; i < 3; i++)
    {
        double bodySize = MathAbs(opens[i] - closes[i]);
        double totalRange = highs[i] - lows[i];
        double bodyRatio = bodySize / totalRange;
        
        // Check for strong confirmation candle (body > 60% of range)
        if(bodyRatio > 0.6 && bodySize > (10 * _Point))
        {
            // Check if it's a bullish confirmation (green candle)
            if(closes[i] > opens[i])
            {
                analysis.hasConfirmationCandle = true;
                analysis.confirmationTime = iTime(_Symbol, LowerTimeframe, i);
                analysis.confirmationLevel = closes[i];
                Print("Bullish Confirmation Candle detected on LTF at ", closes[i]);
                break;
            }
            // Check if it's a bearish confirmation (red candle)
            else if(closes[i] < opens[i])
            {
                analysis.hasConfirmationCandle = true;
                analysis.confirmationTime = iTime(_Symbol, LowerTimeframe, i);
                analysis.confirmationLevel = closes[i];
                Print("Bearish Confirmation Candle detected on LTF at ", closes[i]);
                break;
            }
        }
    }
    
    if(!analysis.hasConfirmationCandle)
    {
        Print("No confirmation candle detected on LTF");
    }
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Check for OTE zone retest on lower timeframe (simplified)         |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis CheckLowerTimeframeOTERetest(LowerTimeframeAnalysis &analysis,
                                                    const double &highs[],
                                                    const double &lows[])
{
    Print("--- Checking for Lower Timeframe OTE Zone Retest ---");
    
    // Simplified OTE retest - check if price retested recent swing levels
    // In the optimized version, we'll use recent swing highs/lows as OTE zones
    
    // Look for recent swing points in the last 10 bars
    for(int i = 2; i < 10; i++)
    {
        // Check for swing high retest
        if(highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
           highs[i] > highs[i+1] && highs[i] > highs[i+2])
        {
            double tolerance = OTERetestTolerance * _Point;
            // Check if current price touched the swing high (within tolerance)
            if(lows[0] <= highs[i] + tolerance && highs[0] >= highs[i] - tolerance)
            {
                analysis.hasOTERetest = true;
                analysis.retestTime = iTime(_Symbol, LowerTimeframe, 0);
                analysis.retestLevel = highs[i];
                Print("OTE Zone Retest detected on LTF: Swing High at ", highs[i]);
                return analysis;
            }
        }
        
        // Check for swing low retest
        if(lows[i] < lows[i-1] && lows[i] < lows[i-2] &&
           lows[i] < lows[i+1] && lows[i] < lows[i+2])
        {
            double tolerance = OTERetestTolerance * _Point;
            // Check if current price touched the swing low (within tolerance)
            if(lows[0] <= lows[i] + tolerance && highs[0] >= lows[i] - tolerance)
            {
                analysis.hasOTERetest = true;
                analysis.retestTime = iTime(_Symbol, LowerTimeframe, 0);
                analysis.retestLevel = lows[i];
                Print("OTE Zone Retest detected on LTF: Swing Low at ", lows[i]);
                return analysis;
            }
        }
    }
    
    if(!analysis.hasOTERetest)
    {
        Print("No OTE zone retest detected on LTF");
    }
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Check if lower timeframe conditions are met                       |
//+------------------------------------------------------------------+
bool CheckLowerTimeframeConditions(bool isBuy)
{
    if(!UseLowerTimeframeTriggers) return true;
    
    int conditionsMet = 0;
    
    // Check structure break
    if(RequireStructureBreak && g_ltfAnalysis.hasStructureBreak)
    {
        if((isBuy && g_ltfAnalysis.isBullishBreak) || (!isBuy && !g_ltfAnalysis.isBullishBreak))
        {
            conditionsMet++;
            Print("LTF Structure Break condition met");
        }
    }
    else if(!RequireStructureBreak)
    {
        conditionsMet++;
    }
    
    // Check confirmation candle
    if(RequireLTFConfirmation && g_ltfAnalysis.hasConfirmationCandle)
    {
        conditionsMet++;
        Print("LTF Confirmation Candle condition met");
    }
    else if(!RequireLTFConfirmation)
    {
        conditionsMet++;
    }
    
    // Check OTE retest
    if(RequireOTERetest && g_ltfAnalysis.hasOTERetest)
    {
        conditionsMet++;
        Print("LTF OTE Retest condition met");
    }
    else if(!RequireOTERetest)
    {
        conditionsMet++;
    }
    
    bool conditionsSatisfied = conditionsMet >= MinLTFConditions;
    Print("LTF Conditions Met: ", conditionsMet, "/", MinLTFConditions, " required");
    
    return conditionsSatisfied;
}

//+------------------------------------------------------------------+
//| Utility Functions                                                 |
//+------------------------------------------------------------------+
string GetTradeRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE: return "Requote";
      case TRADE_RETCODE_REJECT: return "Request rejected";
      case TRADE_RETCODE_CANCEL: return "Request canceled by trader";
      case TRADE_RETCODE_PLACED: return "Order placed";
      case TRADE_RETCODE_DONE: return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL: return "Request completed partially";
      case TRADE_RETCODE_ERROR: return "Request processing error";
      case TRADE_RETCODE_TIMEOUT: return "Request canceled by timeout";
      case TRADE_RETCODE_INVALID: return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume in request";
      case TRADE_RETCODE_INVALID_PRICE: return "Invalid price in request";
      case TRADE_RETCODE_INVALID_STOPS: return "Invalid stops in request";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trading disabled";
      case TRADE_RETCODE_MARKET_CLOSED: return "Market closed";
      case TRADE_RETCODE_NO_MONEY: return "Not enough money";
      case TRADE_RETCODE_PRICE_CHANGED: return "Price changed";
      case TRADE_RETCODE_PRICE_OFF: return "No quotes to process request";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid order expiration date";
      case TRADE_RETCODE_ORDER_CHANGED: return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too frequent requests";
      case TRADE_RETCODE_NO_CHANGES: return "No changes in request";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Autotrading disabled by server";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Autotrading disabled by client terminal";
      case TRADE_RETCODE_LOCKED: return "Request locked for processing";
      case TRADE_RETCODE_FROZEN: return "Order or position frozen";
      case TRADE_RETCODE_INVALID_FILL: return "Invalid order filling type";
      case TRADE_RETCODE_CONNECTION: return "No connection with trade server";
      case TRADE_RETCODE_ONLY_REAL: return "Operation allowed only for live accounts";
      case TRADE_RETCODE_LIMIT_ORDERS: return "Number of pending orders reached limit";
      case TRADE_RETCODE_LIMIT_VOLUME: return "Volume of orders and positions reached limit";
      case TRADE_RETCODE_INVALID_ORDER: return "Incorrect or prohibited order type";
      case TRADE_RETCODE_POSITION_CLOSED: return "Position specified has already been closed";
      default: return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Capture current trading conditions                                |
//+------------------------------------------------------------------+
TradingConditions CaptureTradingConditions(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double targetPrice, double lotSize)
{
   TradingConditions conditions = {};

   // Basic trade info
   conditions.entryTime = TimeCurrent();
   conditions.orderType = orderType;
   conditions.entryPrice = entryPrice;
   conditions.stopLoss = stopLoss;
   conditions.targetPrice = targetPrice;
   conditions.lotSize = lotSize;

   // Market conditions at entry
   conditions.currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   conditions.atrValue = GetOptimizedATRValue();
   conditions.volume = (double)iTickVolume(_Symbol, PERIOD_CURRENT, 0);
   conditions.volumeRatio = AnalyzeVolume().volumeRatio;

   // ICT Strategy conditions
   conditions.inKillZone = IsInKillZone();
   conditions.killZoneType = GetCurrentKillZoneStatus();
   conditions.hasMarketStructure = CheckMarketStructure(orderType == ORDER_TYPE_BUY);
   conditions.marketStructureBullish = orderType == ORDER_TYPE_BUY;

   // FVG/Imbalance conditions
   EnhancedFVGInfo fvgInfo = FindEnhancedFVG(orderType == ORDER_TYPE_BUY);
   conditions.hasFVG = fvgInfo.exists;
   conditions.fvgType = fvgInfo.isBullish ? "Bullish" : "Bearish";
   conditions.fvgStart = fvgInfo.gapStart;
   conditions.fvgEnd = fvgInfo.gapEnd;
   conditions.fvgFilled = fvgInfo.isFilled;
   conditions.fvgTime = fvgInfo.fillTime;
   conditions.fvgStrength = fvgInfo.strength;

   // Lower timeframe conditions
   conditions.hasLTFBreak = g_ltfAnalysis.hasStructureBreak;
   conditions.hasLTFConfirmation = g_ltfAnalysis.hasConfirmationCandle;
   conditions.hasOTERetest = g_ltfAnalysis.hasOTERetest;
   conditions.ltfBreakType = g_ltfAnalysis.isBullishBreak ? "Bullish" : "Bearish";

   // Volume conditions
   conditions.volumeConfirmation = fvgInfo.hasVolumeConfirmation;
   conditions.volumeRatioValue = fvgInfo.volumeRatio;
   conditions.hasVolumeConfirmation = fvgInfo.hasVolumeConfirmation;
   conditions.hasATRConfirmation = fvgInfo.hasATRConfirmation;

   // Risk management
   conditions.riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   conditions.riskPercent = RiskPercent;
   conditions.rewardRiskRatio = RRRatio;

   // Additional context
   conditions.additionalNotes = "ICT FVG Trader Optimized v2.0 - ML Enhanced";

   return conditions;
}

//+------------------------------------------------------------------+
//| Log trading conditions to file                                    |
//+------------------------------------------------------------------+
void LogTradingConditions(const TradingConditions &conditions)
{
   string filename = "trading_conditions_" + IntegerToString(conditions.entryTime) + ".json";
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);

   if(file_handle == INVALID_HANDLE)
   {
      Print("Error opening file '", filename, "'. Error code: ", GetLastError());
      return;
   }

   string json = "{";
   json += "\"entryTime\":\"" + Api_DateTimeToString(conditions.entryTime) + "\",";
   json += "\"orderType\":\"" + (conditions.orderType == ORDER_TYPE_BUY ? "BUY" : "SELL") + "\",";
   json += "\"entryPrice\":" + DoubleToString(conditions.entryPrice, _Digits) + ",";
   json += "\"stopLoss\":" + DoubleToString(conditions.stopLoss, _Digits) + ",";
   json += "\"targetPrice\":" + DoubleToString(conditions.targetPrice, _Digits) + ",";
   json += "\"lotSize\":" + DoubleToString(conditions.lotSize, 2) + ",";
   json += "\"currentPrice\":" + DoubleToString(conditions.currentPrice, _Digits) + ",";
   json += "\"atrValue\":" + DoubleToString(conditions.atrValue, 5) + ",";
   json += "\"volume\":" + DoubleToString(conditions.volume, 0) + ",";
   json += "\"volumeRatio\":" + DoubleToString(conditions.volumeRatio, 2) + ",";
   json += "\"inKillZone\":" + (conditions.inKillZone ? "true" : "false") + ",";
   json += "\"killZoneType\":\"" + conditions.killZoneType + "\",";
   json += "\"hasMarketStructure\":" + (conditions.hasMarketStructure ? "true" : "false") + ",";
   json += "\"marketStructureBullish\":" + (conditions.marketStructureBullish ? "true" : "false") + ",";
   json += "\"hasFVG\":" + (conditions.hasFVG ? "true" : "false") + ",";
   json += "\"fvgType\":\"" + conditions.fvgType + "\",";
   json += "\"fvgStart\":" + DoubleToString(conditions.fvgStart, _Digits) + ",";
   json += "\"fvgEnd\":" + DoubleToString(conditions.fvgEnd, _Digits) + ",";
   json += "\"fvgFilled\":" + (conditions.fvgFilled ? "true" : "false") + ",";
   json += "\"fvgTime\":\"" + Api_DateTimeToString(conditions.fvgTime) + "\",";
   json += "\"hasLTFBreak\":" + (conditions.hasLTFBreak ? "true" : "false") + ",";
   json += "\"hasLTFConfirmation\":" + (conditions.hasLTFConfirmation ? "true" : "false") + ",";
   json += "\"hasOTERetest\":" + (conditions.hasOTERetest ? "true" : "false") + ",";
   json += "\"ltfBreakType\":\"" + conditions.ltfBreakType + "\",";
   json += "\"volumeConfirmation\":" + (conditions.volumeConfirmation ? "true" : "false") + ",";
   json += "\"volumeRatioValue\":" + DoubleToString(conditions.volumeRatioValue, 2) + ",";
   json += "\"riskAmount\":" + DoubleToString(conditions.riskAmount, 2) + ",";
   json += "\"riskPercent\":" + DoubleToString(conditions.riskPercent, 2) + ",";
   json += "\"rewardRiskRatio\":" + DoubleToString(conditions.rewardRiskRatio, 2) + ",";
   json += "\"additionalNotes\":\"" + conditions.additionalNotes + "\"";
   json += "}";

   FileWriteString(file_handle, json);
   FileClose(file_handle);

   Print("Trading conditions logged to file: ", filename);
}

//+------------------------------------------------------------------+
//| Get current kill zone status                                      |
//+------------------------------------------------------------------+
string GetCurrentKillZoneStatus()
{
   if(!UseKillZones) return "Disabled";
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   // London Kill Zone
   if(UseLondonKillZone && currentHour >= LondonKillZoneStart && currentHour < LondonKillZoneEnd)
       return "London Kill Zone";
   
   // New York Kill Zone
   if(UseNewYorkKillZone && currentHour >= NewYorkKillZoneStart && currentHour < NewYorkKillZoneEnd)
       return "New York Kill Zone";
   
   // Asian Kill Zone
   if(UseAsianKillZone)
   {
       if(AsianKillZoneStart < AsianKillZoneEnd)
       {
           if(currentHour >= AsianKillZoneStart && currentHour < AsianKillZoneEnd)
               return "Asian Kill Zone";
       }
       else
       {
           if(currentHour >= AsianKillZoneStart || currentHour < AsianKillZoneEnd)
               return "Asian Kill Zone";
       }
   }
   
   // London Open Kill Zone
   if(UseLondonOpenKillZone && currentHour >= LondonOpenKillZoneStart && currentHour < LondonOpenKillZoneEnd)
       return "London Open Kill Zone";
   
   // New York Open Kill Zone
   if(UseNewYorkOpenKillZone && currentHour >= NewYorkOpenKillZoneStart && currentHour < NewYorkOpenKillZoneEnd)
       return "New York Open Kill Zone";
   
   return "Outside Kill Zone";
}

//+------------------------------------------------------------------+
//| Tester function - Runs automatically after a strategy test       |
//+------------------------------------------------------------------+
double OnTester()
{
    Print("OnTester(): function started. Preparing to send results...");

    StrategyTestResult result;

    // --- Basic Test Information ---
    result.strategy_name = MQLInfoString(MQL_PROGRAM_NAME);
    result.strategy_version = "2.0";  // Optimized version
    result.symbol = _Symbol;
    result.timeframe = EnumToString(_Period);
    result.initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
    result.profit = TesterStatistics(STAT_PROFIT);
    result.final_balance = result.initial_deposit + result.profit;
    result.profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
    result.max_drawdown = TesterStatistics(STAT_BALANCEDD_PERCENT);
    result.total_trades = (int)TesterStatistics(STAT_TRADES);
    result.winning_trades = (int)TesterStatistics(STAT_PROFIT_TRADES);
    result.losing_trades = result.total_trades - result.winning_trades;
    if(result.total_trades > 0)
        result.win_rate = ((double)result.winning_trades / result.total_trades) * 100.0;
    else
        result.win_rate = 0;
    result.sharpe_ratio = TesterStatistics(STAT_SHARPE_RATIO);

    // -- Detailed Statistics
    result.gross_profit = TesterStatistics(STAT_GROSS_PROFIT);
    result.gross_loss = TesterStatistics(STAT_GROSS_LOSS);
    result.recovery_factor = TesterStatistics(STAT_RECOVERY_FACTOR);
    result.expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
    result.long_trades = (int)TesterStatistics(STAT_LONG_TRADES);
    result.short_trades = (int)TesterStatistics(STAT_SHORT_TRADES);
    result.long_trades_won = (int)TesterStatistics(STAT_PROFIT_LONGTRADES);
    result.short_trades_won = (int)TesterStatistics(STAT_PROFIT_SHORTTRADES);
    result.largest_profit = TesterStatistics(STAT_MAX_PROFITTRADE);
    result.largest_loss = TesterStatistics(STAT_MAX_LOSSTRADE);

    // --- Capture all input parameters as JSON ---
    result.parameters = CaptureAllInputParameters();

    TradeData trades[];
    if(HistorySelect(0, TimeCurrent()))
    {
        uint total_deals = HistoryDealsTotal();
        int trade_count = 0;

        for(uint i = 0; i < total_deals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
            {
                if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) continue;

                ArrayResize(trades, trade_count + 1);

                trades[trade_count].ticket = (int)ticket;
                trades[trade_count].symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
                trades[trade_count].type = (HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
                trades[trade_count].volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                trades[trade_count].open_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
                trades[trade_count].open_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

                if(trade_count == 0) result.start_date = trades[trade_count].open_time;
                result.end_date = trades[trade_count].open_time; // Will be updated by last trade

                double close_price = 0;
                datetime close_time = 0;
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
                double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

                for(uint j = i + 1; j < total_deals; j++)
                {
                    ulong close_ticket = HistoryDealGetTicket(j);
                    if(HistoryDealGetInteger(close_ticket, DEAL_POSITION_ID) == ticket)
                    {
                        close_price = HistoryDealGetDouble(close_ticket, DEAL_PRICE);
                        close_time = (datetime)HistoryDealGetInteger(close_ticket, DEAL_TIME);
                        profit += HistoryDealGetDouble(close_ticket, DEAL_PROFIT);
                        swap += HistoryDealGetDouble(close_ticket, DEAL_SWAP);
                        commission += HistoryDealGetDouble(close_ticket, DEAL_COMMISSION);
                        if(close_time > result.end_date) result.end_date = close_time;
                        break;
                    }
                }
                trades[trade_count].close_price = close_price;
                trades[trade_count].close_time = close_time;
                trades[trade_count].profit = profit;
                trades[trade_count].swap = swap;
                trades[trade_count].commission = commission;
                trades[trade_count].net_profit = profit + swap + commission;

                // --- Read and embed trading conditions ---
                string conditions_filename = "trading_conditions_" + (string)ticket + ".json";
                int file_handle = FileOpen(conditions_filename, FILE_READ|FILE_TXT);
                if(file_handle != INVALID_HANDLE)
                {
                    string conditions_json = "";
                    while(!FileIsEnding(file_handle))
                    {
                       conditions_json += FileReadString(file_handle);
                    }
                    FileClose(file_handle);

                    // Embed the JSON string directly
                    trades[trade_count].trading_conditions_json = conditions_json;
                }

                trade_count++;
            }
        }

        // --- Calculate average profit, average loss, average/max consecutive wins/losses ---
        double totalProfit = 0, totalLoss = 0;
        int countProfit = 0, countLoss = 0;
        int maxConsecWins = 0, maxConsecLosses = 0;
        int winStreak = 0, lossStreak = 0;
        int winStreaks = 0, lossStreaks = 0;
        int sumWinStreaks = 0, sumLossStreaks = 0;

        for(int i = 0; i < ArraySize(trades); i++) {
            double profit = trades[i].net_profit;
            if(profit > 0) {
                totalProfit += profit;
                countProfit++;
                winStreak++;
                if(lossStreak > 0) {
                    sumLossStreaks += lossStreak;
                    if(lossStreak > maxConsecLosses) maxConsecLosses = lossStreak;
                    lossStreaks++;
                    lossStreak = 0;
                }
            } else if(profit < 0) {
                totalLoss += profit;
                countLoss++;
                lossStreak++;
                if(winStreak > 0) {
                    sumWinStreaks += winStreak;
                    if(winStreak > maxConsecWins) maxConsecWins = winStreak;
                    winStreaks++;
                    winStreak = 0;
                }
            } else {
                // Flat trade, treat as streak break
                if(winStreak > 0) {
                    sumWinStreaks += winStreak;
                    if(winStreak > maxConsecWins) maxConsecWins = winStreak;
                    winStreaks++;
                    winStreak = 0;
                }
                if(lossStreak > 0) {
                    sumLossStreaks += lossStreak;
                    if(lossStreak > maxConsecLosses) maxConsecLosses = lossStreak;
                    lossStreaks++;
                    lossStreak = 0;
                }
            }
        }
        // Finalize any streaks at the end
        if(winStreak > 0) {
            sumWinStreaks += winStreak;
            if(winStreak > maxConsecWins) maxConsecWins = winStreak;
            winStreaks++;
        }
        if(lossStreak > 0) {
            sumLossStreaks += lossStreak;
            if(lossStreak > maxConsecLosses) maxConsecLosses = lossStreak;
            lossStreaks++;
        }

        double avgProfit = countProfit > 0 ? totalProfit / countProfit : 0;
        double avgLoss = countLoss > 0 ? totalLoss / countLoss : 0;
        double avgConsecWins = winStreaks > 0 ? double(sumWinStreaks) / winStreaks : 0;
        double avgConsecLosses = lossStreaks > 0 ? double(sumLossStreaks) / lossStreaks : 0;

        result.avg_profit = avgProfit;
        result.avg_loss = avgLoss;
        result.max_consecutive_wins = maxConsecWins;
        result.max_consecutive_losses = maxConsecLosses;
        result.avg_consecutive_wins = (int)MathRound(avgConsecWins);
        result.avg_consecutive_losses = (int)MathRound(avgConsecLosses);
    }

    SaveTestResultsToFile(result, trades);

    return TesterStatistics(STAT_PROFIT);
} 