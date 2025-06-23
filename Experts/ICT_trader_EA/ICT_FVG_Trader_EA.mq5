//+------------------------------------------------------------------+
//|                                                ICT_FVG_Trader_EA.mq5 |
//|                                  Copyright 2024, Jason Carty           |
//|                     https://github.com/jason-carty/mt5-trader-ea  |
//+------------------------------------------------------------------+

#include "../WebServerAPI.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <MovingAverages.mqh>

#property copyright "Copyright 2024"
#property version   "1.00"
#property description "ICT Fair Value Gap and Imbalance Trading Expert Advisor"
#property description "Implements ICT concepts for trading Fair Value Gaps (FVGs)"
#property description "and volume imbalances with precise stop loss placement."
#property link      "https://github.com/jason-carty/mt5-trader-ea"

// Risk Management Parameters
input group "Risk Management"
input double RiskPercent = 1.0;          // Risk percentage per trade (1 = 1%)
input double RRRatio = 2.0;              // Risk:Reward ratio (2 = 2x stop loss distance)
input double MinLotSize = 0.01;          // Minimum lot size
input double MaxLotSize = 100.0;         // Maximum lot size
input int    MaxPositions = 5;           // Maximum number of open positions

// Stop Loss Parameters
input group "Stop Loss Settings"
input bool   UseATRStopLoss = true;      // Use ATR-based stop loss
input double ATRMultiplier = 2.0;        // ATR multiplier for stop loss
input int    ATRPeriod = 14;             // ATR period
input bool   UseTrailingStop = true;     // Use trailing stop
input double TrailStartPercent = 20.0;   // Percentage of SL distance to move before trailing
input double TrailDistancePercent = 50.0; // Percentage of initial SL to maintain as trail distance

// Imbalance Confirmation Parameters
input group "Imbalance Settings"
input int    ImbalanceConfirmationBars = 1;   // Number of bars to confirm imbalance (1-3)
input double MinImbalanceRatio = 1.5;         // Minimum ratio between buy/sell volume for imbalance
input int    MinImbalanceVolume = 50;         // Minimum volume for imbalance consideration
input bool   RequireStackedImbalance = false; // Require stacked imbalances for entry
input bool   RequireVolumeConfirmation = true; // Require volume confirmation

// Trading Parameters
input group "Trading Settings"
input bool   RequireConfirmation = true;  // Ask for confirmation before placing trades
input int    MagicNumber = 123456;       // Magic number for order identification

// News Filter Settings
input int NewsBlockMinutesBefore = 30; // Minutes before news to block trading
input int NewsBlockMinutesAfter  = 30; // Minutes after news to block trading
input bool BlockHighImpactOnly   = true; // Only block for high-impact news

// ICT Kill Zone Settings
input group "ICT Kill Zone Settings"
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

// Enhanced ICT Strategy Parameters
input group "Market Structure & Bias"
input bool   UseMarketStructureFilter = true;  // Use market structure analysis
input ENUM_TIMEFRAMES StructureTimeframe = PERIOD_H4;  // Timeframe for market structure analysis
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

input group "Lower Timeframe Analysis"
input bool   UseLowerTimeframeTriggers = true; // Use lower timeframe for precise entries
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_M15; // Lower timeframe for entry triggers
input int    LTFStructureLookback = 20;       // Bars to analyze for LTF structure breaks
input bool   RequireLTFConfirmation = true;   // Require LTF confirmation candle
input bool   RequireOTERetest = true;         // Require retest of OTE zone on LTF
input double OTERetestTolerance = 10.0;       // Tolerance for OTE retest (points)
input int    MinLTFConditions = 2;            // Minimum number of LTF conditions required (1-3)
input bool   RequireStructureBreak = true;    // Require LTF structure break
input bool   AllowLTFOnlyTrades = false;      // Allow trades based purely on LTF signals (no FVG required)
input bool   RequireMarketStructureForLTF = true; // Require market structure alignment for LTF-only trades

//+------------------------------------------------------------------+
//| Struct for storing imbalance information                          |
//+------------------------------------------------------------------+
struct ImbalanceInfo
{
    bool exists;
    double gapStart;    // Price where the gap starts
    double gapEnd;      // Price where the gap ends
    datetime time;      // Time of the imbalance
    bool isBullish;     // True for bullish imbalance (gap up)
    long volume;        // Volume at the imbalance
    double volumeRatio; // Ratio between current and average volume
    bool isFVG;        // Whether this is a fair value gap
    bool isFilled;     // Whether this FVG has been filled
    datetime fillTime;  // When the FVG was filled
};

//+------------------------------------------------------------------+
//| Struct for market structure analysis                              |
//+------------------------------------------------------------------+
struct MarketStructure
{
    bool isBullish;           // Overall market bias
    double lastSwingHigh;     // Last significant swing high
    double lastSwingLow;      // Last significant swing low
    datetime swingHighTime;   // Time of last swing high
    datetime swingLowTime;    // Time of last swing low
    bool hasLiquiditySweep;   // Whether liquidity was swept recently
    datetime sweepTime;       // Time of last liquidity sweep
    double sweepLevel;        // Level that was swept
    bool isSweepHigh;         // True if high was swept, false if low
};

//+------------------------------------------------------------------+
//| Struct for order block information                                |
//+------------------------------------------------------------------+
struct OrderBlock
{
    bool exists;
    double high;
    double low;
    datetime time;
    bool isBullish;           // True for bullish order block (support)
    double volume;            // Volume at the order block
    bool isActive;            // Whether this order block is still active
};

//+------------------------------------------------------------------+
//| Struct for optimal trade entry point                             |
//+------------------------------------------------------------------+
struct OTEPoint
{
    bool exists;
    double level;
    datetime time;
    string type;              // "FVG", "Fib", "OrderBlock", "StdDev"
    double strength;          // Strength of the OTE point (0-1)
    bool isSupport;           // True for support, false for resistance
};

//+------------------------------------------------------------------+
//| Struct for lower timeframe analysis                               |
//+------------------------------------------------------------------+
struct LowerTimeframeAnalysis
{
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

//+------------------------------------------------------------------+
//| Struct for storing trading conditions                             |
//+------------------------------------------------------------------+
struct TradingConditions
{
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

    // Risk management
    double riskAmount;
    double riskPercent;
    double rewardRiskRatio;

    // Additional context
    string additionalNotes;
};

//+------------------------------------------------------------------+
//| Global variables                                                   |
//+------------------------------------------------------------------+
bool isTradeAllowed = false;
ulong currentPositionTicket = 0;         // Track the current position ticket
double initialStopLoss = 0;              // Store initial stop loss for trailing calculation
datetime lastBarTime = 0;                // Store the last processed bar time
ImbalanceInfo g_foundImbalances[];       // Array to store found imbalances
int g_lastProcessedBar = -1;             // Last bar we processed

// Enhanced ICT Strategy Global Variables
MarketStructure g_marketStructure;       // Current market structure
OrderBlock g_orderBlocks[];              // Array to store order blocks
OTEPoint g_otePoints[];                  // Array to store OTE points
double g_fibLevels[];                    // Array to store Fibonacci levels

// Lower Timeframe Analysis Global Variables
LowerTimeframeAnalysis g_ltfAnalysis;    // Current lower timeframe analysis
datetime g_lastLTFCandleTime = 0;        // Track last lower timeframe candle time

// Locked Analysis Timeframes - These won't change when chart timeframe changes
ENUM_TIMEFRAMES g_lockedCurrentTimeframe = PERIOD_CURRENT;    // Locked current timeframe for FVG detection
ENUM_TIMEFRAMES g_lockedStructureTimeframe = PERIOD_CURRENT;  // Locked structure timeframe
ENUM_TIMEFRAMES g_lockedLowerTimeframe = PERIOD_CURRENT;      // Locked lower timeframe

// Kill Zone Caching - Avoid checking kill zones on every tick
bool g_cachedKillZoneStatus = true;      // Cached kill zone status (true = trading allowed)
datetime g_lastKillZoneCheck = 0;        // Last time we checked kill zone status
int g_lastKillZoneHour = -1;             // Last hour we checked (for hourly updates)

// Global trade object
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verify inputs
   if(RiskPercent <= 0 || RiskPercent > 100)
   {
      Print("Invalid Risk Percent value. Must be between 0 and 100");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(RRRatio <= 0)
   {
      Print("Invalid Risk:Reward ratio. Must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(ATRMultiplier <= 0)
   {
      Print("Invalid ATR Multiplier. Must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(MaxPositions <= 0)
   {
      Print("Invalid MaxPositions value. Must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(ImbalanceConfirmationBars < 1 || ImbalanceConfirmationBars > 3)
   {
      Print("Invalid ImbalanceConfirmationBars. Must be between 1 and 3");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(MinImbalanceRatio <= 1.0)
   {
      Print("Invalid MinImbalanceRatio. Must be greater than 1.0");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Validate kill zone parameters
   if(UseKillZones)
   {
      // Validate London Kill Zone
      if(UseLondonKillZone && (LondonKillZoneStart < 0 || LondonKillZoneStart > 23 ||
         LondonKillZoneEnd < 0 || LondonKillZoneEnd > 23 || LondonKillZoneStart >= LondonKillZoneEnd))
      {
         return(INIT_PARAMETERS_INCORRECT);
      }

      // Validate New York Kill Zone
      if(UseNewYorkKillZone && (NewYorkKillZoneStart < 0 || NewYorkKillZoneStart > 23 ||
         NewYorkKillZoneEnd < 0 || NewYorkKillZoneEnd > 23 || NewYorkKillZoneStart >= NewYorkKillZoneEnd))
      {
         return(INIT_PARAMETERS_INCORRECT);
      }

      // Validate Asian Kill Zone (can span midnight)
      if(UseAsianKillZone && (AsianKillZoneStart < 0 || AsianKillZoneStart > 23 ||
         AsianKillZoneEnd < 0 || AsianKillZoneEnd > 23))
      {
         return(INIT_PARAMETERS_INCORRECT);
      }

      // Validate London Open Kill Zone
      if(UseLondonOpenKillZone && (LondonOpenKillZoneStart < 0 || LondonOpenKillZoneStart > 23 ||
         LondonOpenKillZoneEnd < 0 || LondonOpenKillZoneEnd > 23 || LondonOpenKillZoneStart >= LondonOpenKillZoneEnd))
      {
         return(INIT_PARAMETERS_INCORRECT);
      }

      // Validate New York Open Kill Zone
      if(UseNewYorkOpenKillZone && (NewYorkOpenKillZoneStart < 0 || NewYorkOpenKillZoneStart > 23 ||
         NewYorkOpenKillZoneEnd < 0 || NewYorkOpenKillZoneEnd > 23 || NewYorkOpenKillZoneStart >= NewYorkOpenKillZoneEnd))
      {
         return(INIT_PARAMETERS_INCORRECT);
      }

      Print("=== ICT Kill Zone Configuration ===");
      Print("Kill Zones Enabled: ", UseKillZones);
      if(UseLondonKillZone) Print("London Kill Zone: ", LondonKillZoneStart, ":00-", LondonKillZoneEnd, ":00 GMT");
      if(UseNewYorkKillZone) Print("New York Kill Zone: ", NewYorkKillZoneStart, ":00-", NewYorkKillZoneEnd, ":00 GMT");
      if(UseAsianKillZone) Print("Asian Kill Zone: ", AsianKillZoneStart, ":00-", AsianKillZoneEnd, ":00 GMT next day");
      if(UseLondonOpenKillZone) Print("London Open Kill Zone: ", LondonOpenKillZoneStart, ":00-", LondonOpenKillZoneEnd, ":00 GMT");
      if(UseNewYorkOpenKillZone) Print("New York Open Kill Zone: ", NewYorkOpenKillZoneStart, ":00-", NewYorkOpenKillZoneEnd, ":00 GMT");
   }
   else
   {
      Print("ICT Kill Zones disabled - trading allowed at all times");
   }

   // Validate enhanced ICT strategy parameters
   if(UseMarketStructureFilter)
   {
      if(StructureLookback <= 0 || StructureLookback > 200)
      {
         Print("Invalid StructureLookback. Must be between 1 and 200");
         return(INIT_PARAMETERS_INCORRECT);
      }
   }

   if(RequireLiquiditySweep)
   {
      if(LiquiditySweepLookback <= 0 || LiquiditySweepLookback > 100)
      {
         Print("Invalid LiquiditySweepLookback. Must be between 1 and 100");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(MinSweepDistance <= 0)
      {
         Print("Invalid MinSweepDistance. Must be greater than 0");
         return(INIT_PARAMETERS_INCORRECT);
      }
   }

   if(UseFibonacciLevels)
   {
      if(FibLevel1 <= 0 || FibLevel1 >= 1.0 || FibLevel2 <= 0 || FibLevel2 >= 1.0 ||
         FibLevel3 <= 0 || FibLevel3 >= 1.0 || FibLevel4 <= 0 || FibLevel4 >= 1.0)
      {
         Print("Invalid Fibonacci levels. Must be between 0 and 1");
         return(INIT_PARAMETERS_INCORRECT);
      }
   }

   if(UseOrderBlocks)
   {
      if(OrderBlockLookback <= 0 || OrderBlockLookback > 50)
      {
         Print("Invalid OrderBlockLookback. Must be between 1 and 50");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(OrderBlockMinSize <= 0)
      {
         Print("Invalid OrderBlockMinSize. Must be greater than 0");
         return(INIT_PARAMETERS_INCORRECT);
      }
   }

   if(UseStandardDeviation)
   {
      if(StdDevPeriod <= 0 || StdDevPeriod > 100)
      {
         Print("Invalid StdDevPeriod. Must be between 1 and 100");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(StdDevMultiplier <= 0)
      {
         Print("Invalid StdDevMultiplier. Must be greater than 0");
         return(INIT_PARAMETERS_INCORRECT);
      }
   }

   Print("=== Enhanced ICT Strategy Configuration ===");
   Print("Market Structure Filter: ", UseMarketStructureFilter);
   Print("Liquidity Sweep Required: ", RequireLiquiditySweep);
   Print("OTE Filter: ", UseOTEFilter);
   Print("Fibonacci Levels: ", UseFibonacciLevels);
   Print("Order Blocks: ", UseOrderBlocks);
   Print("Standard Deviation: ", UseStandardDeviation);

   // Validate lower timeframe parameters
   if(UseLowerTimeframeTriggers)
   {
      if(LTFStructureLookback <= 0 || LTFStructureLookback > 50)
      {
         Print("Invalid LTFStructureLookback. Must be between 1 and 50");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(OTERetestTolerance <= 0)
      {
         Print("Invalid OTERetestTolerance. Must be greater than 0");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(MinLTFConditions < 1 || MinLTFConditions > 3)
      {
         Print("Invalid MinLTFConditions. Must be between 1 and 3");
         return(INIT_PARAMETERS_INCORRECT);
      }
      Print("Lower Timeframe Analysis: ", EnumToString(LowerTimeframe));
      Print("LTF Structure Lookback: ", LTFStructureLookback);
      Print("OTE Retest Tolerance: ", OTERetestTolerance, " points");
      Print("Minimum LTF Conditions Required: ", MinLTFConditions);
   }

   // Validate LTF-only trading parameters
   if(AllowLTFOnlyTrades)
   {
      Print("LTF-Only Trading Mode: ENABLED");
      Print("Market Structure Required for LTF-Only: ", RequireMarketStructureForLTF);
      Print("Warning: LTF-only trades bypass FVG requirements!");
   }

   // Lock analysis timeframes to prevent changes during runtime
   g_lockedCurrentTimeframe = Period();  // Lock to current chart timeframe
   g_lockedStructureTimeframe = StructureTimeframe;  // Lock to input parameter
   g_lockedLowerTimeframe = LowerTimeframe;  // Lock to input parameter

   Print("=== Locked Analysis Timeframes ===");
   Print("Current Timeframe (FVG Detection): ", EnumToString(g_lockedCurrentTimeframe));
   Print("Structure Timeframe: ", EnumToString(g_lockedStructureTimeframe));
   Print("Lower Timeframe: ", EnumToString(g_lockedLowerTimeframe));
   Print("Note: Analysis timeframes are locked. Use timeframe buttons for visual analysis only.");

   // Initialize kill zone cache
   g_lastKillZoneHour = -1;  // Force first check
   g_cachedKillZoneStatus = true;  // Default to allowing trading
   g_lastKillZoneCheck = 0;
   Print("=== Kill Zone Cache Initialized ===");

   // Check if we have any existing position
   CheckAndUpdatePositionStatus();

   // Initialize FVG tracking
   if(ArrayResize(g_foundImbalances, 0) < 0)
   {
      Print("Failed to initialize imbalances array");
      return(INIT_FAILED);
   }

   // Scan historical bars for existing FVGs on startup
   Print("=== Scanning Historical Bars for FVGs ===");
   for(int i = 200; i > 0; i--)  // Scan from oldest to newest
   {
      ImbalanceInfo historicalFVG = CheckForImbalance(i);
      if(historicalFVG.exists && historicalFVG.isFVG)
      {
         int size = ArraySize(g_foundImbalances);
         ArrayResize(g_foundImbalances, size + 1);
         g_foundImbalances[size] = historicalFVG;
         Print("Found historical FVG at ", TimeToString(historicalFVG.time),
               " Direction: ", (historicalFVG.isBullish ? "Bullish" : "Bearish"),
               " Gap Start: ", DoubleToString(historicalFVG.gapStart, _Digits),
               " Gap End: ", DoubleToString(historicalFVG.gapEnd, _Digits));
      }
   }
   Print("Historical scan complete. Found ", ArraySize(g_foundImbalances), " FVGs");

   g_lastProcessedBar = -1;

   // Create timeframe buttons
   CreateTimeframeButtons();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all FVG objects
   ObjectsDeleteAll(0, "FVG_");

   // Clean up all ICT strategy visualization objects
   ObjectsDeleteAll(0, "MS_");      // Market Structure
   ObjectsDeleteAll(0, "OB_");      // Order Blocks
   ObjectsDeleteAll(0, "Fib_");     // Fibonacci Levels
   ObjectsDeleteAll(0, "OTE_");     // OTE Points
   ObjectsDeleteAll(0, "LTF_");     // Lower Timeframe Analysis
   ObjectsDeleteAll(0, "StdDev_");  // Standard Deviation
   ObjectsDeleteAll(0, "TF_Button_"); // Timeframe Buttons

   // Clear the imbalances array
   ArrayFree(g_foundImbalances);
   Print("Cleaned up ", ArraySize(g_foundImbalances), " stored imbalances");
   Print("Cleaned up all visualization objects");
}

//+------------------------------------------------------------------+
//| Check for ICT volume imbalance                                    |
//+------------------------------------------------------------------+
ImbalanceInfo CheckForImbalance(int shift)
{
    ImbalanceInfo result = {false, 0, 0, 0, false, 0, 0, false};

    // Get candle data with error checking
    if(shift < 1 || shift >= Bars(_Symbol, g_lockedCurrentTimeframe))
    {
        return result;
    }

    datetime checkTime = iTime(_Symbol, g_lockedCurrentTimeframe, shift);

    // Add validation for data access
    int copied;
    double prices[];
    ArraySetAsSeries(prices, true);

    // Validate we can get all required data
    copied = CopyHigh(_Symbol, g_lockedCurrentTimeframe, shift - 1, 3, prices);
    if(copied != 3)
    {
        return result;
    }
    double next_high = prices[0];
    double current_high = prices[1];
    double prev_high = prices[2];

    copied = CopyLow(_Symbol, g_lockedCurrentTimeframe, shift - 1, 3, prices);
    if(copied != 3)
    {
        return result;
    }
    double next_low = prices[0];
    double current_low = prices[1];
    double prev_low = prices[2];

    copied = CopyOpen(_Symbol, g_lockedCurrentTimeframe, shift - 1, 3, prices);
    if(copied != 3)
    {
        return result;
    }
    double next_open = prices[0];
    double current_open = prices[1];
    double prev_open = prices[2];

    copied = CopyClose(_Symbol, g_lockedCurrentTimeframe, shift - 1, 3, prices);
    if(copied != 3)
    {
        return result;
    }
    double next_close = prices[0];
    double current_close = prices[1];
    double prev_close = prices[2];

    // Check for bearish FVG (gap down)
    // For bearish FVG, check if there's a gap between previous low and next high
    double bearish_gap = prev_low - next_high;
    double bearish_gap_points = bearish_gap / _Point;

    // Check for bullish FVG (gap up)
    // For bullish FVG, check if there's a gap between next low and previous high
    double bullish_gap = next_low - prev_high;
    double bullish_gap_points = bullish_gap / _Point;

    // Check for valid gaps (minimum 5 points)
    if(bearish_gap_points >= 5)
    {
        result.exists = true;
        result.isBullish = false;
        result.gapStart = prev_low;
        result.gapEnd = next_high;
        result.time = checkTime;
        result.isFVG = true;
    }
    else if(bullish_gap_points >= 5)
    {
        result.exists = true;
        result.isBullish = true;
        result.gapStart = prev_high;
        result.gapEnd = next_low;
        result.time = checkTime;
        result.isFVG = true;
    }

    return result;
}

//+------------------------------------------------------------------+
//| Check if price has filled the imbalance                           |
//+------------------------------------------------------------------+
bool IsImbalanceFilled(const ImbalanceInfo &imbalance)
{
    if(!imbalance.exists) return false;

    // Get the high and low of the last COMPLETED candle
    double last_completed_high = iHigh(_Symbol, g_lockedCurrentTimeframe, 1);
    double last_completed_low = iLow(_Symbol, g_lockedCurrentTimeframe, 1);

    // For bullish imbalances, check if price returned to gap area
    if(imbalance.isBullish)
    {
        return last_completed_low <= imbalance.gapEnd &&
               last_completed_low >= imbalance.gapStart;
    }
    // For bearish imbalances, check if price returned to gap area
    else
    {
        return last_completed_high >= imbalance.gapEnd &&
               last_completed_high <= imbalance.gapStart;
    }
}

//+------------------------------------------------------------------+
//| Check for stacked imbalances                                      |
//+------------------------------------------------------------------+
bool CheckStackedImbalances(bool isBullish, int lookback = 3)
{
    int stackedCount = 0;
    ImbalanceInfo lastImbalance = {false, 0, 0, 0, false, 0, 0, false};

    for(int i = 0; i < lookback; i++)
    {
        ImbalanceInfo current = CheckForImbalance(i);

        if(current.exists && current.isBullish == isBullish)
        {
            // For first imbalance
            if(stackedCount == 0)
            {
                stackedCount++;
                lastImbalance = current;
            }
            // For subsequent imbalances, check if they're properly stacked
            else
            {
                // For bullish imbalances, each should be higher than the last
                if(isBullish && current.gapStart > lastImbalance.gapEnd)
                {
                    stackedCount++;
                    lastImbalance = current;
                }
                // For bearish imbalances, each should be lower than the last
                else if(!isBullish && current.gapStart < lastImbalance.gapEnd)
                {
                    stackedCount++;
                    lastImbalance = current;
                }
            }
        }
    }

    return stackedCount >= 2;
}

//+------------------------------------------------------------------+
//| Check for imbalance confirmation                                  |
//+------------------------------------------------------------------+
bool ConfirmImbalance(bool isBullish)
{
    ImbalanceInfo imbalance = CheckForImbalance(ImbalanceConfirmationBars);
    if(!imbalance.exists || imbalance.isBullish != isBullish)
    {
        return false;
    }

    // Check if the imbalance has been filled
    if(IsImbalanceFilled(imbalance))
    {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                   |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if we already have a position in this direction              |
//+------------------------------------------------------------------+
bool HasPositionInDirection(bool isBuy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if((isBuy && posType == POSITION_TYPE_BUY) || (!isBuy && posType == POSITION_TYPE_SELL))
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
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
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    // Only print essential information, not detailed calculations
    Print("Lot Size: ", DoubleToString(lotSize, 2), " (Risk: ", DoubleToString(RiskPercent, 2), "%, Stop: ", DoubleToString(stopDistance, 0), " pts)");

    return(lotSize);
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
//| Check if we should update trailing stop                           |
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

    // Calculate the minimum price move needed before trailing (TrailStartPercent of SL distance)
    double minPriceMove = totalSLPoints * (TrailStartPercent / 100.0);

    // Calculate trail distance (TrailDistancePercent of initial SL)
    double trailDistance = totalSLPoints * (TrailDistancePercent / 100.0);

    // For buy positions
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        // Only start trailing if price has moved enough
        if(currentPrice >= openPrice + minPriceMove)
        {
            // New SL will be the current price minus the trail distance
            double newSL = currentPrice - trailDistance;

            // Only modify if new SL is higher than current SL
            if(newSL > currentSL)
            {
                ModifyPosition(newSL);
                Print("Updated Buy Stop Loss: ", newSL,
                      " Current Price: ", currentPrice,
                      " Trail Distance: ", trailDistance);
            }
        }
    }
    // For sell positions
    else
    {
        // Only start trailing if price has moved enough
        if(currentPrice <= openPrice - minPriceMove)
        {
            // New SL will be the current price plus the trail distance
            double newSL = currentPrice + trailDistance;

            // Only modify if new SL is lower than current SL
            if(newSL < currentSL)
            {
                ModifyPosition(newSL);
                Print("Updated Sell Stop Loss: ", newSL,
                      " Current Price: ", currentPrice,
                      " Trail Distance: ", trailDistance);
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
//| Open a new position                                               |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double targetPrice, double lotSize)
{
   TradingConditions conditions = {};
   OpenPosition(orderType, entryPrice, stopLoss, targetPrice, lotSize, conditions);
}

//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss, double targetPrice, double lotSize, TradingConditions &conditions)
{
   // Capture trading conditions if provided
   if(conditions.entryTime == 0) // If conditions not provided, capture them now
   {
      conditions = CaptureTradingConditions(orderType, entryPrice, stopLoss, targetPrice, lotSize);
   }

   // Log the trading conditions
   LogTradingConditions(conditions);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   // Get the filling mode allowed for the symbol
   long filling = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, filling))
   {
      Print("Failed to get filling mode");
      return;
   }

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = targetPrice;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "ICT FVG Trader EA";

   // Set appropriate filling mode
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      request.type_filling = ORDER_FILLING_FOK;
   }
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      request.type_filling = ORDER_FILLING_IOC;
   }
   else
   {
      request.type_filling = ORDER_FILLING_RETURN;
   }

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Order placed successfully. Ticket: ", result.order);
         Print("Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", targetPrice);
         Print("Lot Size: ", lotSize, " Risk: ", RiskPercent, "%");
         currentPositionTicket = result.order;
         initialStopLoss = stopLoss;

         // Save trading conditions to file for later analysis
         SaveTradingConditionsToFile(result.order, conditions);
      }
      else
      {
         Print("Error placing order: ", result.retcode, " - ", GetErrorDescription(result.retcode));
      }
   }
}

//+------------------------------------------------------------------+
//| Close current position                                            |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   // Get position info to determine lot size and type
   double volume = 0;
   ENUM_POSITION_TYPE posType;

   if(PositionSelectByTicket(ticket))
   {
      volume = PositionGetDouble(POSITION_VOLUME);
      posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   }
   else
   {
      Print("Error selecting position");
      return;
   }

   // Get the filling mode allowed for the symbol
   long filling = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, filling))
   {
      Print("Failed to get filling mode");
      return;
   }

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.position = ticket;
   request.price = posType == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "ICT FVG Trader EA - Close";

   // Set appropriate filling mode
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      request.type_filling = ORDER_FILLING_FOK;
   }
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      request.type_filling = ORDER_FILLING_IOC;
   }
   else
   {
      request.type_filling = ORDER_FILLING_RETURN;
   }

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Position closed successfully");
         currentPositionTicket = 0;
      }
      else
      {
         Print("Error closing position: ", result.retcode, " - ", GetErrorDescription(result.retcode));
      }
   }
}

//+------------------------------------------------------------------+
//| Get human-readable error description                              |
//+------------------------------------------------------------------+
string GetErrorDescription(int error_code)
{
   switch(error_code)
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
//| Check for volume confirmation                                      |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation(bool isBullish)
{
    if(!RequireVolumeConfirmation) return true;

    // Get recent volume data
    long volumes[];
    ArraySetAsSeries(volumes, true);
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, 20, volumes) <= 0)
    {
        Print("Failed to get volume data");
        return false;
    }

    Print("=== Volume Confirmation Analysis ===");

    // Calculate average volume (excluding the last completed bar)
    double avgVolume = 0;
    for(int i = 2; i < 20; i++)  // Start from i=2 to exclude current and last bar
    {
        avgVolume += (double)volumes[i];
    }
    avgVolume /= 18.0;  // Average of 18 bars

    // Use last completed bar's volume
    long lastBarVolume = volumes[1];  // Bar 1 is the last completed bar

    Print("Last Bar Volume: ", lastBarVolume);
    Print("Average Volume: ", avgVolume);
    Print("Min Required Ratio: ", MinImbalanceRatio);
    Print("Volume Ratio: ", (double)lastBarVolume / avgVolume);

    // More lenient volume requirement
    if(lastBarVolume >= (long)(avgVolume * 1.2))  // Reduced from MinImbalanceRatio to 1.2
    {
        Print("Volume is significant enough");
        return true;
    }

    Print("Volume not significant enough");
    return false;
}

//+------------------------------------------------------------------+
//| Check if price is near an imbalance level                         |
//+------------------------------------------------------------------+
bool IsPriceNearImbalance(double price, const ImbalanceInfo &imbalance, bool checkSupport)
{
    if(!imbalance.exists) return false;

    // Get last completed bar's high and low
    double lastBarHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double lastBarLow = iLow(_Symbol, PERIOD_CURRENT, 1);
    datetime checkBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    double atr = 0;
    if(UseATRStopLoss)
    {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        int atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
        if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
        {
            atr = atrBuffer[0];
            IndicatorRelease(atrHandle);
        }
    }

    // For FVGs, we want to be more precise with the proximity threshold
    // Using 50% of the FVG size or 0.5 * ATR, whichever is larger
    double gapSize = MathAbs(imbalance.gapStart - imbalance.gapEnd);
    double proximityThreshold = atr > 0 ? MathMax(gapSize * 0.5, atr * 0.5) : gapSize * 0.5;

    double distance;
    if(imbalance.isBullish)
    {
        // For bullish FVGs, check distance from bar low to gap end (support)
        distance = MathAbs(lastBarLow - imbalance.gapEnd);
    }
    else
    {
        // For bearish FVGs, check distance from bar high to gap end (resistance)
        distance = MathAbs(lastBarHigh - imbalance.gapEnd);
    }

    bool isNear = distance <= proximityThreshold;

    Print("=== Price Near FVG Analysis ===");
    Print("Check Bar Time: ", TimeToString(checkBarTime));
    Print("Last Bar High: ", lastBarHigh);
    Print("Last Bar Low: ", lastBarLow);
    Print("Current Price: ", price, " (for reference)");
    Print("FVG Level: ", imbalance.gapEnd);
    Print("Distance: ", distance);
    Print("Gap Size: ", gapSize);
    Print("ATR: ", atr);
    Print("Threshold: ", proximityThreshold);
    Print("Is Near: ", isNear);

    return isNear;
}

//+------------------------------------------------------------------+
//| Check for rejection at FVG level                                   |
//+------------------------------------------------------------------+
bool HasRejectionSignal(const ImbalanceInfo &imbalance)
{
    if(!imbalance.exists) return false;

    // Get last completed bar's data
    double lastBarHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double lastBarLow = iLow(_Symbol, PERIOD_CURRENT, 1);
    double lastBarClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    double lastBarOpen = iOpen(_Symbol, PERIOD_CURRENT, 1);
    datetime checkBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    // Calculate threshold using same logic as IsPriceNearImbalance
    double atr = 0;
    if(UseATRStopLoss)
    {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        int atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
        if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
        {
            atr = atrBuffer[0];
            IndicatorRelease(atrHandle);
        }
    }

    double gapSize = MathAbs(imbalance.gapStart - imbalance.gapEnd);
    double proximityThreshold = atr > 0 ? MathMax(gapSize * 0.5, atr) : gapSize * 0.5;

    Print("=== Rejection Signal Analysis ===");
    Print("Check Bar Time: ", TimeToString(checkBarTime));
    Print("Analyzing candle - O:", lastBarOpen, " H:", lastBarHigh, " L:", lastBarLow, " C:", lastBarClose);

    // For bearish FVG (resistance)
    if(!imbalance.isBullish)
    {
        // Check for bearish rejection candle
        double upperWick = lastBarHigh - MathMax(lastBarOpen, lastBarClose);
        double bodySize = MathAbs(lastBarOpen - lastBarClose);

        // Consider both relative and absolute wick sizes
        bool hasSignificantRelativeWick = upperWick > (bodySize * 0.2);  // Reduced from 0.3 to 0.2
        bool hasSignificantAbsoluteWick = upperWick > (20 * _Point);     // Consider 20 points as significant
        bool hasUpperWick = hasSignificantRelativeWick || hasSignificantAbsoluteWick;

        bool isRedCandle = lastBarClose < lastBarOpen;
        double distanceToResistance = MathAbs(lastBarHigh - imbalance.gapEnd);
        bool nearResistance = distanceToResistance <= proximityThreshold;

        Print("Upper Wick Size: ", upperWick / _Point, " points");
        Print("Body Size: ", bodySize / _Point, " points");
        Print("Has Significant Relative Wick (>20% body): ", hasSignificantRelativeWick);
        Print("Has Significant Absolute Wick (>20pts): ", hasSignificantAbsoluteWick);
        Print("Has Upper Wick: ", hasUpperWick);
        Print("Is Red Candle: ", isRedCandle);
        Print("Distance to Resistance: ", distanceToResistance);
        Print("Threshold: ", proximityThreshold);
        Print("Near Resistance: ", nearResistance);

        if(hasUpperWick && (isRedCandle || bodySize < (5 * _Point)) && nearResistance)
        {
            Print("Valid Bearish Rejection Found");
            return true;
        }
    }
    // For bullish FVG (support)
    else
    {
        // Check for bullish rejection candle
        double lowerWick = MathMin(lastBarOpen, lastBarClose) - lastBarLow;
        double bodySize = MathAbs(lastBarOpen - lastBarClose);

        // Consider both relative and absolute wick sizes
        bool hasSignificantRelativeWick = lowerWick > (bodySize * 0.2);  // Reduced from 0.3 to 0.2
        bool hasSignificantAbsoluteWick = lowerWick > (20 * _Point);     // Consider 20 points as significant
        bool hasLowerWick = hasSignificantRelativeWick || hasSignificantAbsoluteWick;

        bool isGreenCandle = lastBarClose > lastBarOpen;
        double distanceToSupport = MathAbs(lastBarLow - imbalance.gapEnd);
        bool nearSupport = distanceToSupport <= proximityThreshold;

        Print("Lower Wick Size: ", lowerWick / _Point, " points");
        Print("Body Size: ", bodySize / _Point, " points");
        Print("Has Significant Relative Wick (>20% body): ", hasSignificantRelativeWick);
        Print("Has Significant Absolute Wick (>20pts): ", hasSignificantAbsoluteWick);
        Print("Has Lower Wick: ", hasLowerWick);
        Print("Is Green Candle: ", isGreenCandle);
        Print("Distance to Support: ", distanceToSupport);
        Print("Threshold: ", proximityThreshold);
        Print("Near Support: ", nearSupport);

        if(hasLowerWick && (isGreenCandle || bodySize < (5 * _Point)) && nearSupport)
        {
            Print("Valid Bullish Rejection Found");
            return true;
        }
    }

    Print("No valid rejection signal found");
    return false;
}

//+------------------------------------------------------------------+
//| Sort FVGs by price level                                          |
//+------------------------------------------------------------------+
void SortFVGsByPrice()
{
    int size = ArraySize(g_foundImbalances);
    if(size <= 1) return;

    // Bubble sort - simple but effective for small arrays
    for(int i = 0; i < size - 1; i++)
    {
        for(int j = 0; j < size - i - 1; j++)
        {
            // Compare gap ends (the levels price will interact with)
            if(g_foundImbalances[j].gapEnd > g_foundImbalances[j + 1].gapEnd)
            {
                // Swap
                ImbalanceInfo temp = g_foundImbalances[j];
                g_foundImbalances[j] = g_foundImbalances[j + 1];
                g_foundImbalances[j + 1] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find FVGs near current price                                      |
//+------------------------------------------------------------------+
void FindNearbyFVGs(const double price, ImbalanceInfo &nearestBullish, ImbalanceInfo &nearestBearish)
{
    // Initialize with empty imbalances
    nearestBullish.exists = false;
    nearestBearish.exists = false;

    double minBullishDistance = DBL_MAX;
    double minBearishDistance = DBL_MAX;

    // First sort FVGs by price
    SortFVGsByPrice();

    Print("=== Finding Nearby FVGs ===");
    Print("Current Price: ", price);

    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        if(!g_foundImbalances[i].exists || !g_foundImbalances[i].isFVG) continue;

        double distance = MathAbs(price - g_foundImbalances[i].gapEnd);

        // For bullish FVGs, we only care about those below current price
        if(g_foundImbalances[i].isBullish && g_foundImbalances[i].gapEnd < price)
        {
            if(distance < minBullishDistance)
            {
                minBullishDistance = distance;
                nearestBullish = g_foundImbalances[i];
                Print("Found closer bullish FVG at ", g_foundImbalances[i].gapEnd,
                      " Distance: ", distance,
                      " Time: ", TimeToString(g_foundImbalances[i].time));
            }
        }
        // For bearish FVGs, we only care about those above current price
        else if(!g_foundImbalances[i].isBullish && g_foundImbalances[i].gapEnd > price)
        {
            if(distance < minBearishDistance)
            {
                minBearishDistance = distance;
                nearestBearish = g_foundImbalances[i];
                Print("Found closer bearish FVG at ", g_foundImbalances[i].gapEnd,
                      " Distance: ", distance,
                      " Time: ", TimeToString(g_foundImbalances[i].time));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for valid entry conditions                                   |
//+------------------------------------------------------------------+
bool CheckEntryConditions(const ImbalanceInfo &imbalance)
{
    if(!imbalance.exists || !imbalance.isFVG) return false;

    // Get current bar time and FVG formation bar time
    datetime currentBarTime = iTime(_Symbol, g_lockedCurrentTimeframe, 1);  // Using bar 1 (last completed)
    int formationBarShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, imbalance.time);
    int currentBarShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, currentBarTime);

    // For filled FVGs, check the fill time instead
    if(imbalance.isFilled)
    {
        int fillBarShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, imbalance.fillTime);

        // Skip if we haven't completed at least one bar after the fill
        if(fillBarShift <= currentBarShift + 1)
        {
            Print("Skipping trade check for filled FVG - Need one complete bar after fill. Fill bar: ", fillBarShift,
                  " Current bar: ", currentBarShift);
            return false;
        }
    }
    else
    {
        // Skip if we haven't completed at least one bar after the formation bar
        if(formationBarShift <= currentBarShift + 1)
        {
            Print("Skipping trade check for unfilled FVG - Need one complete bar after formation. Formation bar: ", formationBarShift,
                  " Current bar: ", currentBarShift);
            return false;
        }
    }

    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Enhanced ICT Strategy Checks
    Print("=== Enhanced ICT Entry Condition Analysis ===");

    // 1. Market Structure Check
    if(UseMarketStructureFilter)
    {
        bool structureAligned = (imbalance.isBullish && g_marketStructure.isBullish) ||
                               (!imbalance.isBullish && !g_marketStructure.isBullish);

        if(!structureAligned)
        {
            Print("Trade direction not aligned with market structure");
            Print("FVG Direction: ", (imbalance.isBullish ? "Bullish" : "Bearish"));
            Print("Market Structure: ", (g_marketStructure.isBullish ? "Bullish" : "Bearish"));
            return false;
        }
        Print("Market structure aligned with trade direction");
    }

    // 2. Liquidity Sweep Check
    if(RequireLiquiditySweep)
    {
        if(!g_marketStructure.hasLiquiditySweep)
        {
            Print("No liquidity sweep detected - trade blocked");
            return false;
        }

        // Check if sweep was recent (within last 10 bars)
        int sweepBarShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, g_marketStructure.sweepTime);
        if(sweepBarShift > 10)
        {
            Print("Liquidity sweep too old - trade blocked");
            return false;
        }
        Print("Recent liquidity sweep confirmed");
    }

    // 3. OTE Point Check
    if(UseOTEFilter)
    {
        OTEPoint nearestOTE;
        bool isNearOTE = IsPriceNearOTEPoint(current_price, imbalance.isBullish, nearestOTE);

        if(!isNearOTE)
        {
            Print("Price not near any OTE point - trade blocked");
            return false;
        }
        Print("Price near OTE point: ", nearestOTE.type, " at ", nearestOTE.level);
    }

    // 4. Lower Timeframe Triggers Check
    if(UseLowerTimeframeTriggers)
    {
        int conditionsMet = 0;
        int totalConditions = 0;

        // Check for structure break alignment
        if(RequireStructureBreak)
        {
            totalConditions++;
            if(g_ltfAnalysis.hasStructureBreak)
            {
                bool structureAligned = (imbalance.isBullish && g_ltfAnalysis.isBullishBreak) ||
                                       (!imbalance.isBullish && !g_ltfAnalysis.isBullishBreak);

                if(structureAligned)
                {
                    conditionsMet++;
                    Print("Lower timeframe structure break aligned with trade direction");
                }
                else
                {
                    Print("Lower timeframe structure break not aligned with trade direction");
                    Print("FVG Direction: ", (imbalance.isBullish ? "Bullish" : "Bearish"));
                    Print("LTF Structure Break: ", (g_ltfAnalysis.isBullishBreak ? "Bullish" : "Bearish"));
                }
            }
            else
            {
                Print("No lower timeframe structure break detected");
            }
        }

        // Check for confirmation candle
        if(RequireLTFConfirmation)
        {
            totalConditions++;
            if(g_ltfAnalysis.hasConfirmationCandle)
            {
                conditionsMet++;
                Print("Lower timeframe confirmation candle detected");
            }
            else
            {
                Print("No lower timeframe confirmation candle");
            }
        }

        // Check for OTE retest
        if(RequireOTERetest)
        {
            totalConditions++;
            if(g_ltfAnalysis.hasOTERetest)
            {
                conditionsMet++;
                Print("Lower timeframe OTE zone retest confirmed");
            }
            else
            {
                Print("No lower timeframe OTE zone retest");
            }
        }

        // Check if we meet the minimum conditions requirement
        if(conditionsMet < MinLTFConditions)
        {
            Print("Lower timeframe conditions not met. Required: ", MinLTFConditions,
                  " Met: ", conditionsMet, " Total possible: ", totalConditions);
            return false;
        }

        Print("Lower timeframe conditions met: ", conditionsMet, "/", totalConditions,
              " (Required: ", MinLTFConditions, ")");
    }

    // Find nearest FVGs in both directions
    ImbalanceInfo nearestBullish, nearestBearish;
    FindNearbyFVGs(current_price, nearestBullish, nearestBearish);

    // For filled FVGs, we want to be more lenient with the nearest check
    bool isNearest = true;
    if(!imbalance.isFilled)
    {
        // Only proceed if this is the nearest unfilled FVG in its direction
        if(imbalance.isBullish && nearestBullish.exists)
        {
            if(imbalance.time != nearestBullish.time)
            {
                Print("Skipping unfilled bullish FVG - not the nearest one");
                isNearest = false;
            }
        }
        else if(!imbalance.isBullish && nearestBearish.exists)
        {
            if(imbalance.time != nearestBearish.time)
            {
                Print("Skipping unfilled bearish FVG - not the nearest one");
                isNearest = false;
            }
        }
    }

    if(!isNearest) return false;

    // Check if price is near the FVG level
    bool isPriceNear = IsPriceNearImbalance(current_price, imbalance, imbalance.isBullish);
    if(!isPriceNear) return false;

    // Check for rejection signal
    bool hasRejection = HasRejectionSignal(imbalance);
    if(!hasRejection) return false;

    // Additional volume confirmation
    bool hasVolumeConfirmation = CheckVolumeConfirmation(!imbalance.isBullish);  // Inverse because we're looking for rejection
    if(!hasVolumeConfirmation) return false;

    string tradeType = imbalance.isFilled ? "filled" : "unfilled";
    Print("Valid entry conditions found for ", (imbalance.isBullish ? "Bullish" : "Bearish"),
          " FVG at ", imbalance.gapEnd, " (", tradeType, ")");
    return true;
}

//+------------------------------------------------------------------+
//| Find the most recent valid imbalance                              |
//+------------------------------------------------------------------+
ImbalanceInfo FindRecentImbalance(bool isBullish)
{
    ImbalanceInfo result = {false, 0, 0, 0, false, 0, 0, false};
    datetime mostRecentTime = 0;
    datetime mostRecentFillTime = 0;

    // First check our stored FVGs
    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        if(g_foundImbalances[i].exists &&
           g_foundImbalances[i].isBullish == isBullish &&
           g_foundImbalances[i].isFVG)
        {
            // For unfilled FVGs, track by formation time
            if(!g_foundImbalances[i].isFilled)
            {
                if(mostRecentTime == 0 || g_foundImbalances[i].time > mostRecentTime)
                {
                    result = g_foundImbalances[i];
                    mostRecentTime = g_foundImbalances[i].time;
                }
            }
            // For filled FVGs, track by fill time
            else
            {
                if(mostRecentFillTime == 0 || g_foundImbalances[i].fillTime > mostRecentFillTime)
                {
                    // Only update if we haven't found an unfilled FVG or if this filled FVG is more recent
                    if(mostRecentTime == 0)
                    {
                        result = g_foundImbalances[i];
                        mostRecentFillTime = g_foundImbalances[i].fillTime;
                    }
                }
            }
        }
    }

    // Only print when we actually find something (for debugging)
    if(result.exists)
    {
        Print("Found recent ", (result.isBullish ? "Bullish" : "Bearish"), " FVG at ", TimeToString(result.time),
              " Level: ", result.gapEnd, " (", (result.isFilled ? "filled" : "unfilled"), ")");
    }

    return result;
}

//+------------------------------------------------------------------+
//| Check if we have a new bar                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if we have a new lower timeframe candle                     |
//+------------------------------------------------------------------+
bool IsNewLowerTimeframeCandle()
{
    datetime currentLTFCandleTime = iTime(_Symbol, g_lockedLowerTimeframe, 0);
    if(currentLTFCandleTime != g_lastLTFCandleTime)
    {
        g_lastLTFCandleTime = currentLTFCandleTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Draw FVG visualization                                            |
//+------------------------------------------------------------------+
void DrawFVG(const ImbalanceInfo &imbalance, int index)
{
    if(!imbalance.exists) return;

    // Delete any existing objects with this prefix
    string prefix = "FVG_" + TimeToString(imbalance.time) + "_" + IntegerToString(index);
    ObjectDelete(0, prefix + "_rect");
    ObjectDelete(0, prefix + "_label");

    // Skip drawing if FVG is filled
    if(imbalance.isFilled)
    {
        return;
    }

    // Calculate box coordinates
    datetime startTime = imbalance.time;
    datetime endTime = startTime + (PeriodSeconds(PERIOD_CURRENT) * 20); // Extend to 20 bars for better visibility

    // Create rectangle object
    string rectName = prefix + "_rect";
    if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, startTime, imbalance.gapStart, endTime, imbalance.gapEnd))
    {
        Print("Failed to create FVG box. Error: ", GetLastError());
        return;
    }

    // Set colors and style
    color boxColor = imbalance.isBullish ? clrLime : clrRed;
    color fillColor = imbalance.isBullish ? C'00,50,00' : C'50,00,00';  // Darker, more transparent colors

    ObjectSetInteger(0, rectName, OBJPROP_COLOR, boxColor);
    ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, rectName, OBJPROP_BACK, true);  // Draw behind the price
    ObjectSetInteger(0, rectName, OBJPROP_FILL, true);  // Fill the rectangle
    ObjectSetInteger(0, rectName, OBJPROP_BGCOLOR, fillColor);
    ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, rectName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, false);  // Changed from true to false

    // Create label
    string labelName = prefix + "_label";
    double gap_points = MathAbs(imbalance.gapStart - imbalance.gapEnd) / _Point;
    string labelText = StringFormat("%s FVG\nGap: %.1f pts",
                                  imbalance.isBullish ? "Bullish" : "Bearish",
                                  gap_points);

    if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, startTime,
                    imbalance.isBullish ? imbalance.gapEnd : imbalance.gapStart))
    {
        Print("Failed to create FVG label. Error: ", GetLastError());
        return;
    }

    ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
    ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, boxColor);
    ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, imbalance.isBullish ? ANCHOR_LOWER : ANCHOR_UPPER);
    ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, false);  // Changed from true to false
}

//+------------------------------------------------------------------+
//| Update FVG visualizations                                         |
//+------------------------------------------------------------------+
void UpdateFVGVisualizations()
{
    // Clear old visualizations
    ObjectsDeleteAll(0, "FVG_");
    ChartRedraw();  // Force redraw after clearing

    // Draw all stored FVGs
    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        if(g_foundImbalances[i].exists && g_foundImbalances[i].isFVG)
        {
            DrawFVG(g_foundImbalances[i], i);
        }
    }

    ChartRedraw();  // Force redraw after adding new objects
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // News filter: block trading if relevant news is near
    if(IsNewsTime()) {
        return; // Silent return - no need to print every tick
    }

    // Always check position status and trailing stop (light operations)
    CheckAndUpdatePositionStatus();

    if(currentPositionTicket > 0)
    {
        CheckTrailingStop();
    }

    // Check for new higher timeframe bar
    bool isNewBar = IsNewBar();

    // Check for new lower timeframe candle
    bool isNewLTFCandle = false;
    if(UseLowerTimeframeTriggers)
    {
        isNewLTFCandle = IsNewLowerTimeframeCandle();
    }

    // Early return if no new candles and no position to manage
    if(!isNewBar && !isNewLTFCandle && currentPositionTicket == 0)
    {
        return; // No work needed
    }

    // ICT Kill Zone filter: block trading if not in kill zone
    if(!IsInKillZone()) {
        // Only print once per candle, not every tick
        if(isNewBar || isNewLTFCandle)
        {
            Print("Trading blocked - not in ICT kill zone.");
        }
        return;
    }

    // Enhanced ICT Strategy Analysis - only on higher timeframe candle close
    if(isNewBar)
    {
        Print("=== Processing New Higher Timeframe Bar (", EnumToString(g_lockedCurrentTimeframe), ") ===");
        Print("Time: ", TimeToString(iTime(_Symbol, g_lockedCurrentTimeframe, 0)));

        if(UseMarketStructureFilter)
        {
            g_marketStructure = AnalyzeMarketStructure();
        }

        if(UseOrderBlocks)
        {
            FindOrderBlocks();
        }

        if(UseFibonacciLevels)
        {
            CalculateFibonacciLevels();
        }

        if(UseOTEFilter)
        {
            FindOTEPoints();
        }

        // Check for new FVG only when we have 3 completed candles
        ImbalanceInfo newImbalance = CheckForImbalance(2);
        if(newImbalance.exists && newImbalance.isFVG)
        {
            Print("New FVG found at ", TimeToString(newImbalance.time));
            int size = ArraySize(g_foundImbalances);
            ArrayResize(g_foundImbalances, size + 1);
            g_foundImbalances[size] = newImbalance;
            Print("Added new FVG to array. Total FVGs: ", size + 1);
        }

        // Maintain FVG array and update visualizations on higher timeframe
        MaintainFVGArray();
        UpdateAllVisualizations();
    }

    // Lower Timeframe Analysis - on every lower timeframe candle close
    if(UseLowerTimeframeTriggers && isNewLTFCandle)
    {
        Print("=== Processing New Lower Timeframe Candle (", EnumToString(g_lockedLowerTimeframe), ") ===");
        Print("LTF Time: ", TimeToString(iTime(_Symbol, g_lockedLowerTimeframe, 0)));

        g_ltfAnalysis = AnalyzeLowerTimeframeStructure();

        // Update LTF visualizations
        if(UseLowerTimeframeTriggers)
        {
            DrawLowerTimeframeAnalysis();
            ChartRedraw();
        }
    }

    // Only proceed with trading logic if we have new candles and no position
    if(currentPositionTicket == 0 && (isNewBar || isNewLTFCandle))
    {
        // Get ATR values if using ATR-based stops (only when needed for trading)
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        int atrHandle = INVALID_HANDLE;

        if(UseATRStopLoss)
        {
            atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
            if(atrHandle == INVALID_HANDLE || CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) <= 0)
            {
                Print("Failed to get ATR values");
                return;
            }
        }

        // Get current price
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Find recent imbalances from stored FVGs
        ImbalanceInfo recentBullish = FindRecentImbalance(true);
        ImbalanceInfo recentBearish = FindRecentImbalance(false);

        // Check for trading opportunities at filled FVGs first
        bool tradeFound = false;

        // Check filled bearish FVGs for LONG opportunities (opposite direction)
        if(recentBearish.exists && recentBearish.isFilled)
        {
            if(CheckEntryConditions(recentBearish))
            {
                Print("Buy signal confirmed at filled bearish FVG (resistance turned support)");
                double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                // Place SL below the FVG end since we're going long at previous resistance
                double stopLoss = recentBearish.gapEnd - (10 * _Point);
                double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, true);
                double lotSize = CalculateLotSize(entryPrice, stopLoss);

                if(RequireConfirmation)
                {
                    string message = "Buy Signal Detected (Filled Bearish FVG - Resistance turned Support)\n" +
                                   "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                                   "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                                   "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                                   "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                                   "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                                   "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                                   "Previous Resistance Now Support\n" +
                                   "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                                   "Kill Zone: " + GetCurrentKillZoneStatus();

                    if(MessageBox(message, "ICT FVG Trader Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                    {
                        OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                        tradeFound = true;
                    }
                }
                else
                {
                    OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                    tradeFound = true;
                }
            }
        }

        // Check filled bullish FVGs for SHORT opportunities (opposite direction)
        if(!tradeFound && recentBullish.exists && recentBullish.isFilled)
        {
            if(CheckEntryConditions(recentBullish))
            {
                Print("Sell signal confirmed at filled bullish FVG (support turned resistance)");
                double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                // Place SL above the FVG end since we're going short at previous support
                double stopLoss = recentBullish.gapEnd + (10 * _Point);
                double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, false);
                double lotSize = CalculateLotSize(entryPrice, stopLoss);

                if(RequireConfirmation)
                {
                    string message = "Sell Signal Detected (Filled Bullish FVG - Support turned Resistance)\n" +
                                   "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                                   "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                                   "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                                   "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                                   "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                                   "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                                   "Previous Support Now Resistance\n" +
                                   "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                                   "Kill Zone: " + GetCurrentKillZoneStatus();

                    if(MessageBox(message, "ICT FVG Trader Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                    {
                        OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                        tradeFound = true;
                    }
                }
                else
                {
                    OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                    tradeFound = true;
                }
            }
        }

        // If no filled FVG opportunities found, check unfilled FVGs
        if(!tradeFound)
        {
            // Check for sell setup at unfilled bearish FVG
            if(recentBearish.exists && !recentBearish.isFilled)
            {
                if(CheckEntryConditions(recentBearish))
                {
                    Print("Sell signal confirmed at unfilled bearish FVG");
                    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    double stopLoss = MathMax(recentBearish.gapStart, recentBearish.gapEnd) + (10 * _Point);  // Place SL above FVG
                    double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, false);
                    double lotSize = CalculateLotSize(entryPrice, stopLoss);

                    if(RequireConfirmation)
                    {
                        string message = "Sell Signal Detected (Unfilled FVG)\n" +
                                       "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                                       "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                                       "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                                       "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                                       "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                                       "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                                       "Unfilled Fair Value Gap Resistance\n" +
                                       "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                                       "Kill Zone: " + GetCurrentKillZoneStatus();

                        if(MessageBox(message, "ICT FVG Trader Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                        {
                            OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                        }
                    }
                    else
                    {
                        OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                    }
                }
            }
            // Check for buy setup at unfilled bullish FVG
            else if(recentBullish.exists && !recentBullish.isFilled)
            {
                if(CheckEntryConditions(recentBullish))
                {
                    Print("Buy signal confirmed at unfilled bullish FVG");
                    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double stopLoss = MathMin(recentBearish.gapStart, recentBearish.gapEnd) - (10 * _Point);  // Place SL below FVG
                    double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, true);
                    double lotSize = CalculateLotSize(entryPrice, stopLoss);

                    if(RequireConfirmation)
                    {
                        string message = "Buy Signal Detected (Unfilled FVG)\n" +
                                       "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                                       "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                                       "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                                       "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                                       "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                                       "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                                       "Unfilled Fair Value Gap Support\n" +
                                       "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                                       "Kill Zone: " + GetCurrentKillZoneStatus();

                        if(MessageBox(message, "ICT FVG Trader Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                        {
                            OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                        }
                    }
                    else
                    {
                        OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                    }
                }
            }
        }

        // LTF-only trading logic (must be inside this block for tradeFound scope)
        if(!tradeFound && AllowLTFOnlyTrades && isNewLTFCandle)
        {
            Print("=== Checking for LTF-Only Trading Opportunities ===");
            // Check for BUY opportunity based on LTF signals
            if(CheckLTFOnlyEntryConditions(true))
            {
                Print("LTF-Only BUY signal confirmed");
                double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double stopLoss;
                if(UseATRStopLoss && atrHandle != INVALID_HANDLE)
                    stopLoss = entryPrice - (atrBuffer[0] * ATRMultiplier);
                else
                    stopLoss = entryPrice - (50 * _Point);
                double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, true);
                double lotSize = CalculateLotSize(entryPrice, stopLoss);
                if(RequireConfirmation)
                {
                    string message = "LTF-Only BUY Signal Detected\n" +
                        "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                        "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                        "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                        "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                        "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                        "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                        "Based on Lower Timeframe Signals Only\n" +
                        "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                        "Kill Zone: " + GetCurrentKillZoneStatus();
                    if(MessageBox(message, "ICT FVG Trader - LTF-Only Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                    {
                        OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                        tradeFound = true;
                    }
                }
                else
                {
                    OpenPosition(ORDER_TYPE_BUY, entryPrice, stopLoss, targetPrice, lotSize);
                    tradeFound = true;
                }
            }
            // Check for SELL opportunity based on LTF signals
            if(!tradeFound && CheckLTFOnlyEntryConditions(false))
            {
                Print("LTF-Only SELL signal confirmed");
                double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double stopLoss;
                if(UseATRStopLoss && atrHandle != INVALID_HANDLE)
                    stopLoss = entryPrice + (atrBuffer[0] * ATRMultiplier);
                else
                    stopLoss = entryPrice + (50 * _Point);
                double targetPrice = CalculateTargetPrice(entryPrice, stopLoss, false);
                double lotSize = CalculateLotSize(entryPrice, stopLoss);
                if(RequireConfirmation)
                {
                    string message = "LTF-Only SELL Signal Detected\n" +
                        "Bar Time: " + TimeToString(lastBarTime) + "\n" +
                        "Entry Price: " + DoubleToString(entryPrice, _Digits) + "\n" +
                        "Stop Loss: " + DoubleToString(stopLoss, _Digits) + "\n" +
                        "Target Price: " + DoubleToString(targetPrice, _Digits) + "\n" +
                        "Risk: " + DoubleToString(RiskPercent, 2) + "%\n" +
                        "Lot Size: " + DoubleToString(lotSize, 2) + "\n" +
                        "Based on Lower Timeframe Signals Only\n" +
                        "Stop Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 0) + " points\n" +
                        "Kill Zone: " + GetCurrentKillZoneStatus();
                    if(MessageBox(message, "ICT FVG Trader - LTF-Only Signal", MB_YESNO|MB_ICONQUESTION) == IDYES)
                    {
                        OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                        tradeFound = true;
                    }
                }
                else
                {
                    OpenPosition(ORDER_TYPE_SELL, entryPrice, stopLoss, targetPrice, lotSize);
                    tradeFound = true;
                }
            }
        }

        // Clean up ATR handle
        if(atrHandle != INVALID_HANDLE)
            IndicatorRelease(atrHandle);
    }
}

//+------------------------------------------------------------------+
//| Get color component functions                                      |
//+------------------------------------------------------------------+
int GetRValue(color clr) { return (clr >> 16) & 0xFF; }
int GetGValue(color clr) { return (clr >> 8) & 0xFF; }
int GetBValue(color clr) { return clr & 0xFF; }

//+------------------------------------------------------------------+
//| Draw stored FVGs                                                  |
//+------------------------------------------------------------------+
void DrawStoredFVGs()
{
    // Clear existing drawings
    ObjectsDeleteAll(0, "FVG_");

    // Draw each stored imbalance
    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        DrawFVG(g_foundImbalances[i], i);
    }
}

//+------------------------------------------------------------------+
//| Maintain FVG array by removing filled or old FVGs                  |
//+------------------------------------------------------------------+
void MaintainFVGArray()
{
    if(ArraySize(g_foundImbalances) == 0) return;

    // Get completed candle data for checking fills
    double currentBarHigh = iHigh(_Symbol, g_lockedCurrentTimeframe, 1);  // Last completed candle
    double currentBarLow = iLow(_Symbol, g_lockedCurrentTimeframe, 1);
    datetime currentBarTime = iTime(_Symbol, g_lockedCurrentTimeframe, 1);

    // Temporary array for valid FVGs
    ImbalanceInfo tempImbalances[];
    int validCount = 0;
    ArrayResize(tempImbalances, ArraySize(g_foundImbalances));

    // Calculate bar thresholds dynamically based on timeframe
    ENUM_TIMEFRAMES currentTimeframe = Period();
    int minutesPerBar = PeriodSeconds(currentTimeframe) / 60;  // Convert seconds to minutes

    // Calculate how many bars make up 1 and 2 days based on current timeframe
    int barsPerDay = (24 * 60) / minutesPerBar;  // 24 hours * 60 minutes / minutes per bar
    int maxBarsBack = 2 * barsPerDay;  // 2 days worth of bars
    int maxFilledBarsBack = barsPerDay;  // 1 day worth of bars

    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        bool keepFVG = true;
        int barShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, g_foundImbalances[i].time);

        // Remove filled FVGs after 1 day worth of bars
        if(g_foundImbalances[i].isFilled)
        {
            int fillBarShift = iBarShift(_Symbol, g_lockedCurrentTimeframe, g_foundImbalances[i].fillTime);
            if(fillBarShift > maxFilledBarsBack)
            {
                keepFVG = false;
            }
        }
        // Remove unfilled FVGs after 2 days worth of bars
        else if(barShift > maxBarsBack)
        {
            keepFVG = false;
        }
        // Only check for fills if we're past the FVG formation candles
        else if(currentBarTime > (g_foundImbalances[i].time + PeriodSeconds(PERIOD_CURRENT)))
        {
            // Check for fills using the last completed bar
            double lower = MathMin(g_foundImbalances[i].gapStart, g_foundImbalances[i].gapEnd);
            double upper = MathMax(g_foundImbalances[i].gapStart, g_foundImbalances[i].gapEnd);

            if(!g_foundImbalances[i].isBullish)  // Bearish FVG
            {
                // Fill if high >= upper boundary
                if(!g_foundImbalances[i].isFilled && currentBarHigh >= upper)
                {
                    g_foundImbalances[i].isFilled = true;
                    g_foundImbalances[i].fillTime = currentBarTime;
                }
            }
            else  // Bullish FVG
            {
                // Fill if low <= lower boundary
                if(!g_foundImbalances[i].isFilled && currentBarLow <= lower)
                {
                    g_foundImbalances[i].isFilled = true;
                    g_foundImbalances[i].fillTime = currentBarTime;
                }
            }
        }

        // Keep valid FVG
        if(keepFVG)
        {
            tempImbalances[validCount] = g_foundImbalances[i];
            validCount++;
        }
    }

    // Update main array with valid FVGs
    ArrayResize(g_foundImbalances, validCount);
    ArrayCopy(g_foundImbalances, tempImbalances, 0, 0, validCount);
}

//+------------------------------------------------------------------+
//| Check if our position is still open                               |
//+------------------------------------------------------------------+
void CheckAndUpdatePositionStatus()
{
   if(currentPositionTicket > 0)
   {
      // Try to select the position
      if(!PositionSelectByTicket(currentPositionTicket))
      {
         // Position not found - it was closed externally (SL/TP hit)
         Print("Position ", currentPositionTicket, " was closed externally (SL/TP hit)");
         currentPositionTicket = 0;
      }
      else
      {
         // Double check it's our position
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         {
            currentPositionTicket = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Clean symbol of broker suffixes                          |
//+------------------------------------------------------------------+
string CleanSymbol(string symbol) {
    int len = StringLen(symbol);
    while(len > 0 && !((symbol[len-1] >= 'A' && symbol[len-1] <= 'Z') || (symbol[len-1] >= 'a' && symbol[len-1] <= 'z')))
        len--;
    return StringSubstr(symbol, 0, len);
}

//+------------------------------------------------------------------+
//| Helper: Extract base/quote currencies from symbol                |
//+------------------------------------------------------------------+
void GetCurrenciesFromSymbol(string symbol, string &base, string &quote) {
    string clean = CleanSymbol(symbol);
    base = StringSubstr(clean, 0, 3);
    quote = StringSubstr(clean, 3, 3);
}

//+------------------------------------------------------------------+
//| News Filter: Returns true if relevant news is in block window    |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
    string base, quote;
    GetCurrenciesFromSymbol(_Symbol, base, quote);
    datetime from = TimeCurrent() - NewsBlockMinutesBefore * 60;
    datetime to   = TimeCurrent() + NewsBlockMinutesAfter * 60;
    string currencies[2] = {base, quote};

    for(int c=0; c<2; c++)
    {
        MqlCalendarValue values[];
        if(CalendarValueHistory(values, from, to, currencies[c]))
        {
            for(int i = 0; i < ArraySize(values); i++)
            {
                MqlCalendarEvent event;
                if(CalendarEventById(values[i].event_id, event))
                {
                    if(!BlockHighImpactOnly || event.importance == CALENDAR_IMPORTANCE_HIGH)
                    {
                        Print("Blocking trading due to news: ", event.name, " (", currencies[c], ") at ", TimeToString(values[i].time));
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| ICT Kill Zone Filter: Returns true if current time is in kill zone |
//+------------------------------------------------------------------+
bool IsInKillZone()
{
    if(!UseKillZones) return true;  // If kill zones disabled, always allow trading

    // Get current time
    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    int currentHour = time.hour;
    int currentMinute = time.min;

    // Check if we need to update the cached status (only when hour changes)
    if(g_lastKillZoneHour != currentHour)
    {
        // Convert current time to GMT (assuming server time is GMT)
        int gmtHour = currentHour;

        bool inKillZone = false;
        string activeZone = "";

        // Check London Kill Zone
        if(UseLondonKillZone)
        {
            if(gmtHour >= LondonKillZoneStart && gmtHour < LondonKillZoneEnd)
            {
                inKillZone = true;
                activeZone = "London Kill Zone";
            }
        }

        // Check New York Kill Zone
        if(UseNewYorkKillZone && !inKillZone)
        {
            if(gmtHour >= NewYorkKillZoneStart && gmtHour < NewYorkKillZoneEnd)
            {
                inKillZone = true;
                activeZone = "New York Kill Zone";
            }
        }

        // Check Asian Kill Zone (spans midnight)
        if(UseAsianKillZone && !inKillZone)
        {
            if((gmtHour >= AsianKillZoneStart) || (gmtHour < AsianKillZoneEnd))
            {
                inKillZone = true;
                activeZone = "Asian Kill Zone";
            }
        }

        // Check London Open Kill Zone (more specific)
        if(UseLondonOpenKillZone && !inKillZone)
        {
            if(gmtHour >= LondonOpenKillZoneStart && gmtHour < LondonOpenKillZoneEnd)
            {
                inKillZone = true;
                activeZone = "London Open Kill Zone";
            }
        }

        // Check New York Open Kill Zone (more specific)
        if(UseNewYorkOpenKillZone && !inKillZone)
        {
            if(gmtHour >= NewYorkOpenKillZoneStart && gmtHour < NewYorkOpenKillZoneEnd)
            {
                inKillZone = true;
                activeZone = "New York Open Kill Zone";
            }
        }

        // Update cached status
        g_cachedKillZoneStatus = inKillZone;
        g_lastKillZoneHour = currentHour;
        g_lastKillZoneCheck = TimeCurrent();

        // Only print when status changes (not on every tick)
        if(!inKillZone)
        {
            Print("=== ICT Kill Zone Status Updated ===");
            Print("Current Time (GMT): ", gmtHour, ":", currentMinute);
            Print("Trading BLOCKED - Not in any ICT Kill Zone");
            Print("Available Kill Zones:");
            if(UseLondonKillZone) Print("  London: ", LondonKillZoneStart, ":00-", LondonKillZoneEnd, ":00 GMT");
            if(UseNewYorkKillZone) Print("  New York: ", NewYorkKillZoneStart, ":00-", NewYorkKillZoneEnd, ":00 GMT");
            if(UseAsianKillZone) Print("  Asian: ", AsianKillZoneStart, ":00-", AsianKillZoneEnd, ":00 GMT next day");
            if(UseLondonOpenKillZone) Print("  London Open: ", LondonOpenKillZoneStart, ":00-", LondonOpenKillZoneEnd, ":00 GMT");
            if(UseNewYorkOpenKillZone) Print("  New York Open: ", NewYorkOpenKillZoneStart, ":00-", NewYorkOpenKillZoneEnd, ":00 GMT");
        }
        else
        {
            Print("=== ICT Kill Zone Status Updated ===");
            Print("Current Time (GMT): ", gmtHour, ":", currentMinute);
            Print("Trading ALLOWED - In ", activeZone);
        }
    }

    // Return cached status (much faster than recalculating every tick)
    return g_cachedKillZoneStatus;
}

//+------------------------------------------------------------------+
//| Get current kill zone status as string                           |
//+------------------------------------------------------------------+
string GetCurrentKillZoneStatus()
{
    if(!UseKillZones) return "Kill Zones Disabled";

    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    int gmtHour = time.hour;

    // Check London Kill Zone
    if(UseLondonKillZone && gmtHour >= LondonKillZoneStart && gmtHour < LondonKillZoneEnd)
    {
        return "London Kill Zone (" + IntegerToString(LondonKillZoneStart) + ":00-" + IntegerToString(LondonKillZoneEnd) + ":00 GMT)";
    }

    // Check New York Kill Zone
    if(UseNewYorkKillZone && gmtHour >= NewYorkKillZoneStart && gmtHour < NewYorkKillZoneEnd)
    {
        return "New York Kill Zone (" + IntegerToString(NewYorkKillZoneStart) + ":00-" + IntegerToString(NewYorkKillZoneEnd) + ":00 GMT)";
    }

    // Check Asian Kill Zone (spans midnight)
    if(UseAsianKillZone && ((gmtHour >= AsianKillZoneStart) || (gmtHour < AsianKillZoneEnd)))
    {
        return "Asian Kill Zone (" + IntegerToString(AsianKillZoneStart) + ":00-" + IntegerToString(AsianKillZoneEnd) + ":00 GMT next day)";
    }

    // Check London Open Kill Zone
    if(UseLondonOpenKillZone && gmtHour >= LondonOpenKillZoneStart && gmtHour < LondonOpenKillZoneEnd)
    {
        return "London Open Kill Zone (" + IntegerToString(LondonOpenKillZoneStart) + ":00-" + IntegerToString(LondonOpenKillZoneEnd) + ":00 GMT)";
    }

    // Check New York Open Kill Zone
    if(UseNewYorkOpenKillZone && gmtHour >= NewYorkOpenKillZoneStart && gmtHour < NewYorkOpenKillZoneEnd)
    {
        return "New York Open Kill Zone (" + IntegerToString(NewYorkOpenKillZoneStart) + ":00-" + IntegerToString(NewYorkOpenKillZoneEnd) + ":00 GMT)";
    }

    return "Outside Kill Zones";
}

//+------------------------------------------------------------------+
//| Analyze market structure and determine bias                       |
//+------------------------------------------------------------------+
MarketStructure AnalyzeMarketStructure()
{
    MarketStructure result = {false, 0, 0, 0, 0, false, 0, 0, false};

    if(!UseMarketStructureFilter) return result;

    Print("=== Market Structure Analysis ===");

    // Get data from higher timeframe
    double highs[], lows[], closes[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(closes, true);

    int copied = CopyHigh(_Symbol, g_lockedStructureTimeframe, 0, StructureLookback, highs);
    if(copied != StructureLookback)
    {
        Print("Failed to get high data for market structure analysis");
        return result;
    }

    copied = CopyLow(_Symbol, g_lockedStructureTimeframe, 0, StructureLookback, lows);
    if(copied != StructureLookback)
    {
        Print("Failed to get low data for market structure analysis");
        return result;
    }

    copied = CopyClose(_Symbol, g_lockedStructureTimeframe, 0, StructureLookback, closes);
    if(copied != StructureLookback)
    {
        Print("Failed to get close data for market structure analysis");
        return result;
    }

    // Find swing highs and lows
    double swingHigh = 0, swingLow = DBL_MAX;
    datetime swingHighTime = 0, swingLowTime = 0;
    int swingHighIndex = -1, swingLowIndex = -1;

    // Look for swing points in the last StructureLookback bars
    for(int i = 2; i < StructureLookback - 2; i++)
    {
        // Check for swing high
        if(highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
           highs[i] > highs[i+1] && highs[i] > highs[i+2])
        {
            if(highs[i] > swingHigh)
            {
                swingHigh = highs[i];
                swingHighIndex = i;
                swingHighTime = iTime(_Symbol, g_lockedStructureTimeframe, i);
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
                swingLowTime = iTime(_Symbol, g_lockedStructureTimeframe, i);
            }
        }
    }

    // Determine market bias based on recent swing points
    if(swingHighIndex >= 0 && swingLowIndex >= 0)
    {
        // If swing high is more recent than swing low, market is bearish
        if(swingHighIndex < swingLowIndex)
        {
            result.isBullish = false;
            Print("Market Structure: BEARISH (Recent swing high at ", swingHigh, ")");
        }
        else
        {
            result.isBullish = true;
            Print("Market Structure: BULLISH (Recent swing low at ", swingLow, ")");
        }

        result.lastSwingHigh = swingHigh;
        result.lastSwingLow = swingLow;
        result.swingHighTime = swingHighTime;
        result.swingLowTime = swingLowTime;
    }
    else
    {
        // Fallback: use current price vs recent average
        double currentPrice = closes[0];
        double avgPrice = 0;
        for(int i = 0; i < 20; i++)
        {
            avgPrice += closes[i];
        }
        avgPrice /= 20.0;

        result.isBullish = currentPrice > avgPrice;
        Print("Market Structure: ", (result.isBullish ? "BULLISH" : "BEARISH"), " (Price vs 20-bar average)");
    }

    // Check for liquidity sweeps
    if(RequireLiquiditySweep)
    {
        result = CheckLiquiditySweeps(result);
    }

    return result;
}

//+------------------------------------------------------------------+
//| Check for liquidity sweeps (price taking out previous highs/lows) |
//+------------------------------------------------------------------+
MarketStructure CheckLiquiditySweeps(MarketStructure &structure)
{
    Print("=== Liquidity Sweep Analysis ===");

    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    int copied = CopyHigh(_Symbol, g_lockedCurrentTimeframe, 0, LiquiditySweepLookback, highs);
    if(copied != LiquiditySweepLookback)
    {
        Print("Failed to get high data for liquidity sweep analysis");
        return structure;
    }

    copied = CopyLow(_Symbol, g_lockedCurrentTimeframe, 0, LiquiditySweepLookback, lows);
    if(copied != LiquiditySweepLookback)
    {
        Print("Failed to get low data for liquidity sweep analysis");
        return structure;
    }

    // Look for recent liquidity sweeps
    for(int i = 1; i < LiquiditySweepLookback - 1; i++)
    {
        // Check for high sweep (price went above previous high then came back down)
        double previousHigh = 0;
        for(int j = i + 1; j < LiquiditySweepLookback; j++)
        {
            if(highs[j] > previousHigh) previousHigh = highs[j];
        }

        if(highs[i] > previousHigh + (MinSweepDistance * _Point))
        {
            // Check if price came back down after the sweep
            if(lows[i] < highs[i] - (MinSweepDistance * _Point) ||
               (i > 0 && lows[i-1] < highs[i] - (MinSweepDistance * _Point)))
            {
                structure.hasLiquiditySweep = true;
                structure.sweepTime = iTime(_Symbol, PERIOD_CURRENT, i);
                structure.sweepLevel = highs[i];
                structure.isSweepHigh = true;
                Print("Liquidity Sweep Detected: HIGH swept at ", structure.sweepLevel,
                      " on ", TimeToString(structure.sweepTime));
                break;
            }
        }

        // Check for low sweep (price went below previous low then came back up)
        double previousLow = DBL_MAX;
        for(int j = i + 1; j < LiquiditySweepLookback; j++)
        {
            if(lows[j] < previousLow) previousLow = lows[j];
        }

        if(lows[i] < previousLow - (MinSweepDistance * _Point))
        {
            // Check if price came back up after the sweep
            if(highs[i] > lows[i] + (MinSweepDistance * _Point) ||
               (i > 0 && highs[i-1] > lows[i] + (MinSweepDistance * _Point)))
            {
                structure.hasLiquiditySweep = true;
                structure.sweepTime = iTime(_Symbol, PERIOD_CURRENT, i);
                structure.sweepLevel = lows[i];
                structure.isSweepHigh = false;
                Print("Liquidity Sweep Detected: LOW swept at ", structure.sweepLevel,
                      " on ", TimeToString(structure.sweepTime));
                break;
            }
        }
    }

    if(!structure.hasLiquiditySweep)
    {
        Print("No recent liquidity sweeps detected");
    }

    return structure;
}

//+------------------------------------------------------------------+
//| Find order blocks (areas where institutional orders were placed)  |
//+------------------------------------------------------------------+
void FindOrderBlocks()
{
    if(!UseOrderBlocks) return;

    Print("=== Order Block Detection ===");

    // Clear existing order blocks
    ArrayResize(g_orderBlocks, 0);

    double highs[], lows[], opens[], closes[];
    long volumes[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(volumes, true);

    int copied = CopyHigh(_Symbol, g_lockedCurrentTimeframe, 0, OrderBlockLookback, highs);
    if(copied != OrderBlockLookback) return;

    copied = CopyLow(_Symbol, g_lockedCurrentTimeframe, 0, OrderBlockLookback, lows);
    if(copied != OrderBlockLookback) return;

    copied = CopyOpen(_Symbol, g_lockedCurrentTimeframe, 0, OrderBlockLookback, opens);
    if(copied != OrderBlockLookback) return;

    copied = CopyClose(_Symbol, g_lockedCurrentTimeframe, 0, OrderBlockLookback, closes);
    if(copied != OrderBlockLookback) return;

    copied = CopyTickVolume(_Symbol, g_lockedCurrentTimeframe, 0, OrderBlockLookback, volumes);
    if(copied != OrderBlockLookback) return;

    // Calculate average volume
    double avgVolume = 0;
    for(int i = 0; i < OrderBlockLookback; i++)
    {
        avgVolume += (double)volumes[i];
    }
    avgVolume /= OrderBlockLookback;

    // Look for order blocks
    for(int i = 1; i < OrderBlockLookback - 1; i++)
    {
        double bodySize = MathAbs(opens[i] - closes[i]);
        double totalRange = highs[i] - lows[i];
        double bodyRatio = bodySize / totalRange;

        // Order block criteria:
        // 1. Strong directional move (body > 60% of range)
        // 2. Above average volume
        // 3. Minimum size requirement
        if(bodyRatio > 0.6 && volumes[i] > avgVolume * 1.2 &&
           bodySize > (OrderBlockMinSize * _Point))
        {
            OrderBlock block = {false, 0, 0, 0, false, 0, true};
            block.exists = true;
            block.time = iTime(_Symbol, PERIOD_CURRENT, i);
            block.volume = (double)volumes[i];

            // Determine if bullish or bearish order block
            if(closes[i] > opens[i])  // Bullish candle
            {
                block.isBullish = true;
                block.high = opens[i];  // Order block starts at open
                block.low = lows[i];    // Order block ends at low
                Print("Bullish Order Block found at ", TimeToString(block.time),
                      " Level: ", block.low, " - ", block.high);
            }
            else  // Bearish candle
            {
                block.isBullish = false;
                block.high = highs[i];  // Order block starts at high
                block.low = closes[i];  // Order block ends at close
                Print("Bearish Order Block found at ", TimeToString(block.time),
                      " Level: ", block.low, " - ", block.high);
            }

            // Add to array
            int size = ArraySize(g_orderBlocks);
            ArrayResize(g_orderBlocks, size + 1);
            g_orderBlocks[size] = block;
        }
    }

    Print("Found ", ArraySize(g_orderBlocks), " order blocks");
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci retracement levels                            |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels()
{
    if(!UseFibonacciLevels) return;

    Print("=== Fibonacci Levels Calculation ===");

    // Clear existing levels
    ArrayResize(g_fibLevels, 0);

    // Get recent swing high and low from market structure
    if(g_marketStructure.lastSwingHigh <= 0 || g_marketStructure.lastSwingLow <= 0)
    {
        Print("Cannot calculate Fibonacci levels - no swing points available");
        return;
    }

    double swingHigh = g_marketStructure.lastSwingHigh;
    double swingLow = g_marketStructure.lastSwingLow;
    double range = swingHigh - swingLow;

    // Calculate Fibonacci levels
    double fib236 = swingHigh - (range * FibLevel1);
    double fib382 = swingHigh - (range * FibLevel2);
    double fib618 = swingHigh - (range * FibLevel3);
    double fib786 = swingHigh - (range * FibLevel4);

    // Add levels to array
    ArrayResize(g_fibLevels, 4);
    g_fibLevels[0] = fib236;
    g_fibLevels[1] = fib382;
    g_fibLevels[2] = fib618;
    g_fibLevels[3] = fib786;

    Print("Fibonacci Levels (from ", swingHigh, " to ", swingLow, "):");
    Print("  23.6%: ", fib236);
    Print("  38.2%: ", fib382);
    Print("  61.8%: ", fib618);
    Print("  78.6%: ", fib786);
}

//+------------------------------------------------------------------+
//| Find optimal trade entry (OTE) points                            |
//+------------------------------------------------------------------+
void FindOTEPoints()
{
    if(!UseOTEFilter) return;

    Print("=== Optimal Trade Entry (OTE) Analysis ===");

    // Clear existing OTE points
    ArrayResize(g_otePoints, 0);

    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double proximityThreshold = 20 * _Point;  // 20 points proximity threshold

    // 1. Add FVGs as OTE points
    for(int i = 0; i < ArraySize(g_foundImbalances); i++)
    {
        if(g_foundImbalances[i].exists && g_foundImbalances[i].isFVG)
        {
            OTEPoint ote = {false, 0, 0, "", 0, false};
            ote.exists = true;
            ote.level = g_foundImbalances[i].gapEnd;
            ote.time = g_foundImbalances[i].time;
            ote.type = "FVG";
            ote.isSupport = g_foundImbalances[i].isBullish;

            // Calculate strength based on gap size and recency
            double gapSize = MathAbs(g_foundImbalances[i].gapStart - g_foundImbalances[i].gapEnd);
            int barsAgo = iBarShift(_Symbol, PERIOD_CURRENT, g_foundImbalances[i].time);
            ote.strength = MathMin(1.0, (gapSize / (50 * _Point)) * (1.0 - (barsAgo / 100.0)));

            // Add to array
            int size = ArraySize(g_otePoints);
            ArrayResize(g_otePoints, size + 1);
            g_otePoints[size] = ote;

            Print("OTE Point (FVG): ", ote.level, " Type: ", (ote.isSupport ? "Support" : "Resistance"),
                  " Strength: ", DoubleToString(ote.strength, 2));
        }
    }

    // 2. Add Fibonacci levels as OTE points
    if(UseFibonacciLevels && ArraySize(g_fibLevels) > 0)
    {
        for(int i = 0; i < ArraySize(g_fibLevels); i++)
        {
            OTEPoint ote = {false, 0, 0, "", 0, false};
            ote.exists = true;
            ote.level = g_fibLevels[i];
            ote.time = TimeCurrent();
            ote.type = "Fibonacci";
            ote.isSupport = g_marketStructure.isBullish;  // Support in bullish market, resistance in bearish
            ote.strength = 0.7;  // Medium strength for Fibonacci levels

            // Add to array
            int size = ArraySize(g_otePoints);
            ArrayResize(g_otePoints, size + 1);
            g_otePoints[size] = ote;

            Print("OTE Point (Fibonacci): ", ote.level, " Type: ", (ote.isSupport ? "Support" : "Resistance"));
        }
    }

    // 3. Add order blocks as OTE points
    if(UseOrderBlocks)
    {
        for(int i = 0; i < ArraySize(g_orderBlocks); i++)
        {
            if(g_orderBlocks[i].exists && g_orderBlocks[i].isActive)
            {
                OTEPoint ote = {false, 0, 0, "", 0, false};
                ote.exists = true;
                ote.level = g_orderBlocks[i].isBullish ? g_orderBlocks[i].low : g_orderBlocks[i].high;
                ote.time = g_orderBlocks[i].time;
                ote.type = "OrderBlock";
                ote.isSupport = g_orderBlocks[i].isBullish;
                ote.strength = 0.8;  // High strength for order blocks

                // Add to array
                int size = ArraySize(g_otePoints);
                ArrayResize(g_otePoints, size + 1);
                g_otePoints[size] = ote;

                Print("OTE Point (OrderBlock): ", ote.level, " Type: ", (ote.isSupport ? "Support" : "Resistance"));
            }
        }
    }

    // 4. Add standard deviation levels if enabled
    if(UseStandardDeviation)
    {
        double stdDevLevel = CalculateStandardDeviationLevel();
        if(stdDevLevel > 0)
        {
            OTEPoint ote = {false, 0, 0, "", 0, false};
            ote.exists = true;
            ote.level = stdDevLevel;
            ote.time = TimeCurrent();
            ote.type = "StdDev";
            ote.isSupport = g_marketStructure.isBullish;
            ote.strength = 0.6;  // Medium strength for standard deviation

            // Add to array
            int size = ArraySize(g_otePoints);
            ArrayResize(g_otePoints, size + 1);
            g_otePoints[size] = ote;

            Print("OTE Point (StdDev): ", ote.level, " Type: ", (ote.isSupport ? "Support" : "Resistance"));
        }
    }

    Print("Total OTE Points found: ", ArraySize(g_otePoints));
}

//+------------------------------------------------------------------+
//| Calculate standard deviation level for price targets              |
//+------------------------------------------------------------------+
double CalculateStandardDeviationLevel()
{
    if(!UseStandardDeviation) return 0;

    double closes[];
    ArraySetAsSeries(closes, true);

    int copied = CopyClose(_Symbol, g_lockedCurrentTimeframe, 0, StdDevPeriod, closes);
    if(copied != StdDevPeriod) return 0;

    // Calculate mean
    double mean = 0;
    for(int i = 0; i < StdDevPeriod; i++)
    {
        mean += closes[i];
    }
    mean /= StdDevPeriod;

    // Calculate standard deviation
    double variance = 0;
    for(int i = 0; i < StdDevPeriod; i++)
    {
        variance += MathPow(closes[i] - mean, 2);
    }
    variance /= StdDevPeriod;
    double stdDev = MathSqrt(variance);

    // Calculate target level
    double currentPrice = closes[0];
    double targetLevel = currentPrice + (stdDev * StdDevMultiplier);

    Print("Standard Deviation Level: ", targetLevel, " (Current: ", currentPrice, " + ", stdDev * StdDevMultiplier, ")");

    return targetLevel;
}

//+------------------------------------------------------------------+
//| Check if price is near an OTE point                               |
//+------------------------------------------------------------------+
bool IsPriceNearOTEPoint(double price, bool isBuy, OTEPoint &nearestOTE)
{
    if(!UseOTEFilter || ArraySize(g_otePoints) == 0) return false;

    double minDistance = DBL_MAX;
    bool found = false;

    for(int i = 0; i < ArraySize(g_otePoints); i++)
    {
        if(!g_otePoints[i].exists) continue;

        double distance = MathAbs(price - g_otePoints[i].level);
        double proximityThreshold = 30 * _Point;  // 30 points proximity

        // For buy trades, look for support levels below current price
        if(isBuy && g_otePoints[i].isSupport && g_otePoints[i].level < price)
        {
            if(distance < minDistance && distance <= proximityThreshold)
            {
                minDistance = distance;
                nearestOTE = g_otePoints[i];
                found = true;
            }
        }
        // For sell trades, look for resistance levels above current price
        else if(!isBuy && !g_otePoints[i].isSupport && g_otePoints[i].level > price)
        {
            if(distance < minDistance && distance <= proximityThreshold)
            {
                minDistance = distance;
                nearestOTE = g_otePoints[i];
                found = true;
            }
        }
    }

    if(found)
    {
        Print("Price near OTE Point: ", nearestOTE.level, " Type: ", nearestOTE.type,
              " Distance: ", DoubleToString(minDistance / _Point, 1), " points");
    }

    return found;
}

//+------------------------------------------------------------------+
//| Analyze lower timeframe for structure breaks and confirmations    |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis AnalyzeLowerTimeframeStructure()
{
    LowerTimeframeAnalysis result = {false, false, false, 0, 0, 0, 0, 0, 0, false};

    if(!UseLowerTimeframeTriggers) return result;

    Print("=== Lower Timeframe Analysis (", EnumToString(g_lockedLowerTimeframe), ") ===");

    // Get data from lower timeframe
    double highs[], lows[], opens[], closes[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);

    int copied = CopyHigh(_Symbol, g_lockedLowerTimeframe, 0, LTFStructureLookback, highs);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF high data");
        return result;
    }

    copied = CopyLow(_Symbol, g_lockedLowerTimeframe, 0, LTFStructureLookback, lows);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF low data");
        return result;
    }

    copied = CopyOpen(_Symbol, g_lockedLowerTimeframe, 0, LTFStructureLookback, opens);
    if(copied != LTFStructureLookback)
    {
        Print("Failed to get LTF open data");
        return result;
    }

    copied = CopyClose(_Symbol, g_lockedLowerTimeframe, 0, LTFStructureLookback, closes);
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

    // 3. Check for OTE Zone Retest
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
            analysis.structureBreakTime = iTime(_Symbol, g_lockedLowerTimeframe, 0);
            analysis.structureBreakLevel = swingHigh;
            Print("Bullish Structure Break detected on LTF at ", swingHigh);
        }
        // Check if current price broke below swing low (bearish break)
        else if(closes[0] < swingLow - (5 * _Point))
        {
            analysis.hasStructureBreak = true;
            analysis.isBullishBreak = false;
            analysis.structureBreakTime = iTime(_Symbol, g_lockedLowerTimeframe, 0);
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
                analysis.confirmationTime = iTime(_Symbol, g_lockedLowerTimeframe, i);
                analysis.confirmationLevel = closes[i];
                Print("Bullish Confirmation Candle detected on LTF at ", closes[i]);
                break;
            }
            // Check if it's a bearish confirmation (red candle)
            else if(closes[i] < opens[i])
            {
                analysis.hasConfirmationCandle = true;
                analysis.confirmationTime = iTime(_Symbol, g_lockedLowerTimeframe, i);
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
//| Check for OTE zone retest on lower timeframe                      |
//+------------------------------------------------------------------+
LowerTimeframeAnalysis CheckLowerTimeframeOTERetest(LowerTimeframeAnalysis &analysis,
                                                    const double &highs[],
                                                    const double &lows[])
{
    Print("--- Checking for Lower Timeframe OTE Zone Retest ---");

    if(ArraySize(g_otePoints) == 0)
    {
        Print("No OTE points available for retest check");
        return analysis;
    }

    // Check if price retested any OTE zone in the last 5 bars
    for(int i = 0; i < 5; i++)
    {
        for(int j = 0; j < ArraySize(g_otePoints); j++)
        {
            if(!g_otePoints[j].exists) continue;

            double oteLevel = g_otePoints[j].level;
            double tolerance = OTERetestTolerance * _Point;

            // Check if price touched the OTE zone (within tolerance)
            if(lows[i] <= oteLevel + tolerance && highs[i] >= oteLevel - tolerance)
            {
                analysis.hasOTERetest = true;
                analysis.retestTime = iTime(_Symbol, g_lockedLowerTimeframe, i);
                analysis.retestLevel = oteLevel;
                Print("OTE Zone Retest detected on LTF: ", g_otePoints[j].type, " at ", oteLevel);
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
//| Draw market structure visualization                                |
//+------------------------------------------------------------------+
void DrawMarketStructure()
{
    if(!UseMarketStructureFilter) return;

    Print("=== Drawing Market Structure ===");

    // Clear existing market structure objects
    ObjectsDeleteAll(0, "MS_");

    // Draw swing high and low
    if(g_marketStructure.lastSwingHigh > 0)
    {
        string swingHighName = "MS_SwingHigh";
        if(!ObjectCreate(0, swingHighName, OBJ_HLINE, 0, 0, g_marketStructure.lastSwingHigh))
        {
            Print("Failed to create swing high line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, swingHighName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, swingHighName, OBJPROP_STYLE, STYLE_DASHDOT);
            ObjectSetInteger(0, swingHighName, OBJPROP_WIDTH, 2);
            ObjectSetString(0, swingHighName, OBJPROP_TEXT, "Swing High");
        }

        // Add label
        string swingHighLabel = "MS_SwingHigh_Label";
        if(!ObjectCreate(0, swingHighLabel, OBJ_TEXT, 0, TimeCurrent(), g_marketStructure.lastSwingHigh))
        {
            Print("Failed to create swing high label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, swingHighLabel, OBJPROP_TEXT, "Swing High");
            ObjectSetString(0, swingHighLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, swingHighLabel, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, swingHighLabel, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, swingHighLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    if(g_marketStructure.lastSwingLow > 0)
    {
        string swingLowName = "MS_SwingLow";
        if(!ObjectCreate(0, swingLowName, OBJ_HLINE, 0, 0, g_marketStructure.lastSwingLow))
        {
            Print("Failed to create swing low line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, swingLowName, OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, swingLowName, OBJPROP_STYLE, STYLE_DASHDOT);
            ObjectSetInteger(0, swingLowName, OBJPROP_WIDTH, 2);
            ObjectSetString(0, swingLowName, OBJPROP_TEXT, "Swing Low");
        }

        // Add label
        string swingLowLabel = "MS_SwingLow_Label";
        if(!ObjectCreate(0, swingLowLabel, OBJ_TEXT, 0, TimeCurrent(), g_marketStructure.lastSwingLow))
        {
            Print("Failed to create swing low label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, swingLowLabel, OBJPROP_TEXT, "Swing Low");
            ObjectSetString(0, swingLowLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, swingLowLabel, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, swingLowLabel, OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, swingLowLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    // Draw liquidity sweep if detected
    if(g_marketStructure.hasLiquiditySweep)
    {
        string sweepName = "MS_LiquiditySweep";
        if(!ObjectCreate(0, sweepName, OBJ_HLINE, 0, 0, g_marketStructure.sweepLevel))
        {
            Print("Failed to create liquidity sweep line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, sweepName, OBJPROP_COLOR, clrMagenta);
            ObjectSetInteger(0, sweepName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, sweepName, OBJPROP_WIDTH, 3);
            ObjectSetString(0, sweepName, OBJPROP_TEXT, "Liquidity Sweep");
        }

        // Add label
        string sweepLabel = "MS_LiquiditySweep_Label";
        if(!ObjectCreate(0, sweepLabel, OBJ_TEXT, 0, TimeCurrent(), g_marketStructure.sweepLevel))
        {
            Print("Failed to create liquidity sweep label. Error: ", GetLastError());
        }
        else
        {
            string sweepText = "Liquidity Sweep (" + (g_marketStructure.isSweepHigh ? "High" : "Low") + ")";
            ObjectSetString(0, sweepLabel, OBJPROP_TEXT, sweepText);
            ObjectSetString(0, sweepLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, sweepLabel, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, sweepLabel, OBJPROP_COLOR, clrMagenta);
            ObjectSetInteger(0, sweepLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    // Draw market bias arrow
    string biasName = "MS_Bias";
    datetime biasTime = TimeCurrent() - (PeriodSeconds(PERIOD_CURRENT) * 10);
    double biasPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(!ObjectCreate(0, biasName, OBJ_ARROW, 0, biasTime, biasPrice))
    {
        Print("Failed to create market bias arrow. Error: ", GetLastError());
    }
    else
    {
        ObjectSetInteger(0, biasName, OBJPROP_ARROWCODE, g_marketStructure.isBullish ? 233 : 234);
        ObjectSetInteger(0, biasName, OBJPROP_COLOR, g_marketStructure.isBullish ? clrLime : clrRed);
        ObjectSetInteger(0, biasName, OBJPROP_WIDTH, 3);
        ObjectSetString(0, biasName, OBJPROP_TEXT, g_marketStructure.isBullish ? "Bullish" : "Bearish");
    }
}

//+------------------------------------------------------------------+
//| Draw order blocks visualization                                   |
//+------------------------------------------------------------------+
void DrawOrderBlocks()
{
    if(!UseOrderBlocks) return;

    Print("=== Drawing Order Blocks ===");

    // Clear existing order block objects
    ObjectsDeleteAll(0, "OB_");

    for(int i = 0; i < ArraySize(g_orderBlocks); i++)
    {
        if(!g_orderBlocks[i].exists || !g_orderBlocks[i].isActive) continue;

        string obName = "OB_" + IntegerToString(i);
        datetime startTime = g_orderBlocks[i].time;
        datetime endTime = startTime + (PeriodSeconds(PERIOD_CURRENT) * 50); // Extend for visibility

        // Create rectangle for order block
        if(!ObjectCreate(0, obName, OBJ_RECTANGLE, 0, startTime, g_orderBlocks[i].high, endTime, g_orderBlocks[i].low))
        {
            Print("Failed to create order block rectangle. Error: ", GetLastError());
            continue;
        }

        // Set colors based on type
        color obColor = g_orderBlocks[i].isBullish ? clrLime : clrRed;
        color fillColor = g_orderBlocks[i].isBullish ? C'00,40,00' : C'40,00,00';

        ObjectSetInteger(0, obName, OBJPROP_COLOR, obColor);
        ObjectSetInteger(0, obName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, obName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, obName, OBJPROP_BACK, true);
        ObjectSetInteger(0, obName, OBJPROP_FILL, true);
        ObjectSetInteger(0, obName, OBJPROP_BGCOLOR, fillColor);

        // Add label
        string obLabel = "OB_Label_" + IntegerToString(i);
        string obText = (g_orderBlocks[i].isBullish ? "Bullish" : "Bearish") + " Order Block";

        if(!ObjectCreate(0, obLabel, OBJ_TEXT, 0, startTime, g_orderBlocks[i].high))
        {
            Print("Failed to create order block label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, obLabel, OBJPROP_TEXT, obText);
            ObjectSetString(0, obLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, obLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, obLabel, OBJPROP_COLOR, obColor);
            ObjectSetInteger(0, obLabel, OBJPROP_ANCHOR, ANCHOR_UPPER);
        }

        Print("Drew order block ", i, " at ", TimeToString(startTime), " Level: ", g_orderBlocks[i].low, " - ", g_orderBlocks[i].high);
    }
}

//+------------------------------------------------------------------+
//| Draw Fibonacci levels visualization                               |
//+------------------------------------------------------------------+
void DrawFibonacciLevels()
{
    if(!UseFibonacciLevels || ArraySize(g_fibLevels) == 0) return;

    Print("=== Drawing Fibonacci Levels ===");

    // Clear existing Fibonacci objects
    ObjectsDeleteAll(0, "Fib_");

    string fibNames[] = {"23.6%", "38.2%", "61.8%", "78.6%"};
    color fibColors[] = {clrGold, clrOrange, clrDarkOrange, clrRed};

    for(int i = 0; i < ArraySize(g_fibLevels); i++)
    {
        string fibName = "Fib_" + fibNames[i];

        if(!ObjectCreate(0, fibName, OBJ_HLINE, 0, 0, g_fibLevels[i]))
        {
            Print("Failed to create Fibonacci line ", fibNames[i], ". Error: ", GetLastError());
            continue;
        }

        ObjectSetInteger(0, fibName, OBJPROP_COLOR, fibColors[i]);
        ObjectSetInteger(0, fibName, OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, fibName, OBJPROP_WIDTH, 1);
        ObjectSetString(0, fibName, OBJPROP_TEXT, "Fib " + fibNames[i]);

        // Add label
        string fibLabel = "Fib_Label_" + fibNames[i];
        if(!ObjectCreate(0, fibLabel, OBJ_TEXT, 0, TimeCurrent(), g_fibLevels[i]))
        {
            Print("Failed to create Fibonacci label ", fibNames[i], ". Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, fibLabel, OBJPROP_TEXT, "Fib " + fibNames[i]);
            ObjectSetString(0, fibLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, fibLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, fibLabel, OBJPROP_COLOR, fibColors[i]);
            ObjectSetInteger(0, fibLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }

        Print("Drew Fibonacci level ", fibNames[i], " at ", g_fibLevels[i]);
    }
}

//+------------------------------------------------------------------+
//| Draw OTE points visualization                                     |
//+------------------------------------------------------------------+
void DrawOTEPoints()
{
    if(!UseOTEFilter || ArraySize(g_otePoints) == 0) return;

    Print("=== Drawing OTE Points ===");

    // Clear existing OTE objects
    ObjectsDeleteAll(0, "OTE_");

    for(int i = 0; i < ArraySize(g_otePoints); i++)
    {
        if(!g_otePoints[i].exists) continue;

        string oteName = "OTE_" + IntegerToString(i);
        datetime oteTime = g_otePoints[i].time;
        double oteLevel = g_otePoints[i].level;

        // Create arrow for OTE point
        if(!ObjectCreate(0, oteName, OBJ_ARROW, 0, oteTime, oteLevel))
        {
            Print("Failed to create OTE point arrow. Error: ", GetLastError());
            continue;
        }

        // Set arrow properties based on type and strength
        color oteColor;
        int arrowCode;

        if(g_otePoints[i].type == "FVG")
        {
            oteColor = g_otePoints[i].isSupport ? clrLime : clrRed;
            arrowCode = g_otePoints[i].isSupport ? 233 : 234; // Up arrow for support, down for resistance
        }
        else if(g_otePoints[i].type == "Fibonacci")
        {
            oteColor = clrGold;
            arrowCode = g_otePoints[i].isSupport ? 233 : 234;
        }
        else if(g_otePoints[i].type == "OrderBlock")
        {
            oteColor = clrMagenta;
            arrowCode = g_otePoints[i].isSupport ? 233 : 234;
        }
        else if(g_otePoints[i].type == "StdDev")
        {
            oteColor = clrCyan;
            arrowCode = g_otePoints[i].isSupport ? 233 : 234;
        }
        else
        {
            oteColor = clrWhite;
            arrowCode = 233;
        }

        ObjectSetInteger(0, oteName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, oteName, OBJPROP_COLOR, oteColor);
        ObjectSetInteger(0, oteName, OBJPROP_WIDTH, 2);

        // Add label with type and strength
        string oteLabel = "OTE_Label_" + IntegerToString(i);
        string oteText = g_otePoints[i].type + " (" + DoubleToString(g_otePoints[i].strength, 2) + ")";

        if(!ObjectCreate(0, oteLabel, OBJ_TEXT, 0, oteTime, oteLevel))
        {
            Print("Failed to create OTE label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, oteLabel, OBJPROP_TEXT, oteText);
            ObjectSetString(0, oteLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, oteLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, oteLabel, OBJPROP_COLOR, oteColor);
            ObjectSetInteger(0, oteLabel, OBJPROP_ANCHOR, g_otePoints[i].isSupport ? ANCHOR_LOWER : ANCHOR_UPPER);
        }

        Print("Drew OTE point ", i, " Type: ", g_otePoints[i].type, " Level: ", oteLevel, " Strength: ", g_otePoints[i].strength);
    }
}

//+------------------------------------------------------------------+
//| Draw lower timeframe analysis visualization                       |
//+------------------------------------------------------------------+
void DrawLowerTimeframeAnalysis()
{
    if(!UseLowerTimeframeTriggers) return;

    Print("=== Drawing Lower Timeframe Analysis ===");

    // Clear existing LTF objects
    ObjectsDeleteAll(0, "LTF_");

    // Draw structure break
    if(g_ltfAnalysis.hasStructureBreak)
    {
        string bosName = "LTF_StructureBreak";
        if(!ObjectCreate(0, bosName, OBJ_HLINE, 0, 0, g_ltfAnalysis.structureBreakLevel))
        {
            Print("Failed to create LTF structure break line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, bosName, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, bosName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, bosName, OBJPROP_WIDTH, 2);
            ObjectSetString(0, bosName, OBJPROP_TEXT, "LTF Structure Break");
        }

        // Add label
        string bosLabel = "LTF_StructureBreak_Label";
        if(!ObjectCreate(0, bosLabel, OBJ_TEXT, 0, TimeCurrent(), g_ltfAnalysis.structureBreakLevel))
        {
            Print("Failed to create LTF structure break label. Error: ", GetLastError());
        }
        else
        {
            string bosText = "LTF BOS (" + (g_ltfAnalysis.isBullishBreak ? "Bullish" : "Bearish") + ")";
            ObjectSetString(0, bosLabel, OBJPROP_TEXT, bosText);
            ObjectSetString(0, bosLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, bosLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, bosLabel, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, bosLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    // Draw confirmation candle
    if(g_ltfAnalysis.hasConfirmationCandle)
    {
        string confName = "LTF_Confirmation";
        if(!ObjectCreate(0, confName, OBJ_HLINE, 0, 0, g_ltfAnalysis.confirmationLevel))
        {
            Print("Failed to create LTF confirmation line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, confName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, confName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, confName, OBJPROP_WIDTH, 1);
            ObjectSetString(0, confName, OBJPROP_TEXT, "LTF Confirmation");
        }

        // Add label
        string confLabel = "LTF_Confirmation_Label";
        if(!ObjectCreate(0, confLabel, OBJ_TEXT, 0, TimeCurrent(), g_ltfAnalysis.confirmationLevel))
        {
            Print("Failed to create LTF confirmation label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, confLabel, OBJPROP_TEXT, "LTF Confirmation");
            ObjectSetString(0, confLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, confLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, confLabel, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, confLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    // Draw OTE retest
    if(g_ltfAnalysis.hasOTERetest)
    {
        string retestName = "LTF_OTERetest";
        if(!ObjectCreate(0, retestName, OBJ_HLINE, 0, 0, g_ltfAnalysis.retestLevel))
        {
            Print("Failed to create LTF OTE retest line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, retestName, OBJPROP_COLOR, clrCyan);
            ObjectSetInteger(0, retestName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, retestName, OBJPROP_WIDTH, 1);
            ObjectSetString(0, retestName, OBJPROP_TEXT, "LTF OTE Retest");
        }

        // Add label
        string retestLabel = "LTF_OTERetest_Label";
        if(!ObjectCreate(0, retestLabel, OBJ_TEXT, 0, TimeCurrent(), g_ltfAnalysis.retestLevel))
        {
            Print("Failed to create LTF OTE retest label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, retestLabel, OBJPROP_TEXT, "LTF OTE Retest");
            ObjectSetString(0, retestLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, retestLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, retestLabel, OBJPROP_COLOR, clrCyan);
            ObjectSetInteger(0, retestLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }
}

//+------------------------------------------------------------------+
//| Draw standard deviation levels                                    |
//+------------------------------------------------------------------+
void DrawStandardDeviationLevels()
{
    if(!UseStandardDeviation) return;

    Print("=== Drawing Standard Deviation Levels ===");

    // Clear existing StdDev objects
    ObjectsDeleteAll(0, "StdDev_");

    double stdDevLevel = CalculateStandardDeviationLevel();
    if(stdDevLevel > 0)
    {
        string stdDevName = "StdDev_Level";
        if(!ObjectCreate(0, stdDevName, OBJ_HLINE, 0, 0, stdDevLevel))
        {
            Print("Failed to create standard deviation line. Error: ", GetLastError());
        }
        else
        {
            ObjectSetInteger(0, stdDevName, OBJPROP_COLOR, clrCyan);
            ObjectSetInteger(0, stdDevName, OBJPROP_STYLE, STYLE_DASHDOT);
            ObjectSetInteger(0, stdDevName, OBJPROP_WIDTH, 1);
            ObjectSetString(0, stdDevName, OBJPROP_TEXT, "StdDev Target");
        }

        // Add label
        string stdDevLabel = "StdDev_Label";
        if(!ObjectCreate(0, stdDevLabel, OBJ_TEXT, 0, TimeCurrent(), stdDevLevel))
        {
            Print("Failed to create standard deviation label. Error: ", GetLastError());
        }
        else
        {
            ObjectSetString(0, stdDevLabel, OBJPROP_TEXT, "StdDev Target");
            ObjectSetString(0, stdDevLabel, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, stdDevLabel, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, stdDevLabel, OBJPROP_COLOR, clrCyan);
            ObjectSetInteger(0, stdDevLabel, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }

        Print("Drew standard deviation level at ", stdDevLevel);
    }
}

//+------------------------------------------------------------------+
//| Update all visualizations                                         |
//+------------------------------------------------------------------+
void UpdateAllVisualizations()
{
    Print("=== Updating All Visualizations ===");

    // Update FVG visualizations (existing function)
    UpdateFVGVisualizations();

    // Update ICT strategy visualizations
    if(UseMarketStructureFilter)
    {
        DrawMarketStructure();
    }

    if(UseOrderBlocks)
    {
        DrawOrderBlocks();
    }

    if(UseFibonacciLevels)
    {
        DrawFibonacciLevels();
    }

    if(UseOTEFilter)
    {
        DrawOTEPoints();
    }

    if(UseLowerTimeframeTriggers)
    {
        DrawLowerTimeframeAnalysis();
    }

    if(UseStandardDeviation)
    {
        DrawStandardDeviationLevels();
    }

    // Force chart redraw
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create timeframe buttons on chart                                 |
//+------------------------------------------------------------------+
void CreateTimeframeButtons()
{
    Print("=== Creating Timeframe Buttons ===");

    // Button properties
    int buttonWidth = 60;
    int buttonHeight = 25;
    int startX = 10;
    int startY = 30;
    int spacing = 5;

    // Common timeframe buttons
    string timeframes[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};
    ENUM_TIMEFRAMES tfValues[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};

    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        string buttonName = "TF_Button_" + timeframes[i];
        int x = startX + (i * (buttonWidth + spacing));

        // Create button
        if(!ObjectCreate(0, buttonName, OBJ_BUTTON, 0, 0, 0))
        {
            Print("Failed to create button ", buttonName, ". Error: ", GetLastError());
            continue;
        }

        // Set button properties
        ObjectSetInteger(0, buttonName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, buttonName, OBJPROP_YDISTANCE, startY);
        ObjectSetInteger(0, buttonName, OBJPROP_XSIZE, buttonWidth);
        ObjectSetInteger(0, buttonName, OBJPROP_YSIZE, buttonHeight);
        ObjectSetString(0, buttonName, OBJPROP_TEXT, timeframes[i]);
        ObjectSetString(0, buttonName, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, buttonName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, clrDarkBlue);
        ObjectSetInteger(0, buttonName, OBJPROP_BORDER_COLOR, clrGray);
        ObjectSetInteger(0, buttonName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, buttonName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, buttonName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, buttonName, OBJPROP_BACK, false);
        ObjectSetInteger(0, buttonName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, buttonName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, buttonName, OBJPROP_HIDDEN, false);
        ObjectSetInteger(0, buttonName, OBJPROP_ZORDER, 1000);

        // Store timeframe value in object description
        ObjectSetString(0, buttonName, OBJPROP_TOOLTIP, "Switch to " + timeframes[i] + " timeframe");

        Print("Created timeframe button: ", timeframes[i], " at position (", x, ", ", startY, ")");
    }

    // Highlight current timeframe button
    HighlightCurrentTimeframeButton();

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Highlight the current timeframe button                            |
//+------------------------------------------------------------------+
void HighlightCurrentTimeframeButton()
{
    ENUM_TIMEFRAMES currentTF = Period();
    string currentTFString = "";

    // Convert current timeframe to string
    switch(currentTF)
    {
        case PERIOD_M1:  currentTFString = "M1"; break;
        case PERIOD_M5:  currentTFString = "M5"; break;
        case PERIOD_M15: currentTFString = "M15"; break;
        case PERIOD_M30: currentTFString = "M30"; break;
        case PERIOD_H1:  currentTFString = "H1"; break;
        case PERIOD_H4:  currentTFString = "H4"; break;
        case PERIOD_D1:  currentTFString = "D1"; break;
        default:         currentTFString = "H1"; break;
    }

    // Reset all buttons to default colors
    string timeframes[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};
    for(int i = 0; i < ArraySize(timeframes); i++)
    {
        string buttonName = "TF_Button_" + timeframes[i];
        if(ObjectFind(0, buttonName) >= 0)
        {
            if(timeframes[i] == currentTFString)
            {
                // Highlight current timeframe button
                ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, clrLime);
                ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrBlack);
                ObjectSetInteger(0, buttonName, OBJPROP_BORDER_COLOR, clrDarkGreen);
            }
            else
            {
                // Reset to default colors
                ObjectSetInteger(0, buttonName, OBJPROP_BGCOLOR, clrDarkBlue);
                ObjectSetInteger(0, buttonName, OBJPROP_COLOR, clrWhite);
                ObjectSetInteger(0, buttonName, OBJPROP_BORDER_COLOR, clrGray);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle timeframe button clicks                                    |
//+------------------------------------------------------------------+
void HandleTimeframeButtonClick(const string &sparam)
{
    if(StringFind(sparam, "TF_Button_") == 0)
    {
        // Extract timeframe from button name
        string tfString = StringSubstr(sparam, 10); // Remove "TF_Button_" prefix

        ENUM_TIMEFRAMES newTimeframe = PERIOD_CURRENT;

        // Convert string to timeframe
        if(tfString == "M1") newTimeframe = PERIOD_M1;
        else if(tfString == "M5") newTimeframe = PERIOD_M5;
        else if(tfString == "M15") newTimeframe = PERIOD_M15;
        else if(tfString == "M30") newTimeframe = PERIOD_M30;
        else if(tfString == "H1") newTimeframe = PERIOD_H1;
        else if(tfString == "H4") newTimeframe = PERIOD_H4;
        else if(tfString == "D1") newTimeframe = PERIOD_D1;

        // Switch timeframe
        if(newTimeframe != PERIOD_CURRENT)
        {
            Print("Switching to timeframe: ", tfString);
            ChartSetInteger(0, 16, (long)newTimeframe); // 16 is CHART_PERIOD

            // Update button highlighting
            HighlightCurrentTimeframeButton();

            // Force chart redraw
            ChartRedraw();
        }
    }
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // Handle button clicks
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        HandleTimeframeButtonClick(sparam);
    }
}

//+------------------------------------------------------------------+
//| Check entry conditions for LTF-only trades (no FVG required)      |
//+------------------------------------------------------------------+
bool CheckLTFOnlyEntryConditions(bool isBuy)
{
    if(!AllowLTFOnlyTrades) return false;

    Print("=== Checking LTF-Only Entry Conditions ===");
    Print("Trade Direction: ", (isBuy ? "BUY" : "SELL"));

    // 1. Market Structure Check (if required)
    if(RequireMarketStructureForLTF && UseMarketStructureFilter)
    {
        bool structureAligned = (isBuy && g_marketStructure.isBullish) ||
                               (!isBuy && !g_marketStructure.isBullish);

        if(!structureAligned)
        {
            Print("LTF-Only Trade: Market structure not aligned");
            Print("Trade Direction: ", (isBuy ? "Bullish" : "Bearish"));
            Print("Market Structure: ", (g_marketStructure.isBullish ? "Bullish" : "Bearish"));
            return false;
        }
        Print("LTF-Only Trade: Market structure aligned");
    }

    // 2. Lower Timeframe Conditions Check
    if(!UseLowerTimeframeTriggers)
    {
        Print("LTF-Only Trade: Lower timeframe triggers disabled");
        return false;
    }

    int conditionsMet = 0;
    int totalConditions = 0;

    // Check for structure break alignment
    if(RequireStructureBreak)
    {
        totalConditions++;
        if(g_ltfAnalysis.hasStructureBreak)
        {
            bool structureAligned = (isBuy && g_ltfAnalysis.isBullishBreak) ||
                                   (!isBuy && !g_ltfAnalysis.isBullishBreak);

            if(structureAligned)
            {
                conditionsMet++;
                Print("LTF-Only Trade: Structure break aligned");
            }
            else
            {
                Print("LTF-Only Trade: Structure break not aligned");
            }
        }
        else
        {
            Print("LTF-Only Trade: No structure break detected");
        }
    }

    // Check for confirmation candle
    if(RequireLTFConfirmation)
    {
        totalConditions++;
        if(g_ltfAnalysis.hasConfirmationCandle)
        {
            conditionsMet++;
            Print("LTF-Only Trade: Confirmation candle detected");
        }
        else
        {
            Print("LTF-Only Trade: No confirmation candle");
        }
    }

    // Check for OTE retest
    if(RequireOTERetest)
    {
        totalConditions++;
        if(g_ltfAnalysis.hasOTERetest)
        {
            conditionsMet++;
            Print("LTF-Only Trade: OTE retest confirmed");
        }
        else
        {
            Print("LTF-Only Trade: No OTE retest");
        }
    }

    // Check if we meet the minimum conditions requirement
    if(conditionsMet < MinLTFConditions)
    {
        Print("LTF-Only Trade: Conditions not met. Required: ", MinLTFConditions,
              " Met: ", conditionsMet, " Total possible: ", totalConditions);
        return false;
    }

    Print("LTF-Only Trade: All conditions met (", conditionsMet, "/", totalConditions, ")");
    return true;
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
    result.symbol = _Symbol;
    result.timeframe = EnumToString(_Period);
    result.initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
    result.profit = TesterStatistics(STAT_PROFIT);
    result.final_balance = result.initial_deposit + result.profit;
    result.profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
    result.max_drawdown = TesterStatistics(STAT_BALANCE_DD);
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

    // --- Performance Metrics ---
    result.parameters = "{}"; // Placeholder

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

                // --- NEW: Read and embed trading conditions ---
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

                    // This is a bit of a hack, but we embed the JSON string directly
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
        result.avg_consecutive_wins = avgConsecWins;
        result.avg_consecutive_losses = avgConsecLosses;
    }

    SaveTestResultsToFile(result, trades);

    return TesterStatistics(STAT_PROFIT);
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
   conditions.currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get ATR value
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
   {
      conditions.atrValue = atrBuffer[0];
   }

   // Get volume data
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, 20, volumes) > 0)
   {
      conditions.volume = (double)volumes[1]; // Last completed bar

      // Calculate volume ratio
      double avgVolume = 0;
      for(int i = 2; i < 20; i++)
      {
         avgVolume += (double)volumes[i];
      }
      avgVolume /= 18.0;
      conditions.volumeRatio = avgVolume > 0 ? conditions.volume / avgVolume : 0;
   }

   // ICT Strategy conditions
   conditions.inKillZone = IsInKillZone();
   conditions.killZoneType = GetCurrentKillZoneStatus();
   conditions.hasMarketStructure = UseMarketStructureFilter;
   conditions.marketStructureBullish = g_marketStructure.isBullish;
   conditions.hasLiquiditySweep = g_marketStructure.hasLiquiditySweep;
   conditions.liquiditySweepTime = g_marketStructure.sweepTime;
   conditions.liquiditySweepLevel = g_marketStructure.sweepLevel;

   // FVG conditions - find the most recent relevant FVG
   ImbalanceInfo recentFVG = FindRecentImbalance(orderType == ORDER_TYPE_BUY ? false : true); // Opposite direction
   conditions.hasFVG = recentFVG.exists;
   if(conditions.hasFVG)
   {
      conditions.fvgType = recentFVG.isBullish ? "Bullish" : "Bearish";
      conditions.fvgStart = recentFVG.gapStart;
      conditions.fvgEnd = recentFVG.gapEnd;
      conditions.fvgFilled = recentFVG.isFilled;
      conditions.fvgTime = recentFVG.time;
   }

   // OTE conditions
   conditions.hasOTE = ArraySize(g_otePoints) > 0;
   if(conditions.hasOTE)
   {
      // Find the closest OTE point
      double closestDistance = 999999;
      for(int i = 0; i < ArraySize(g_otePoints); i++)
      {
         double distance = MathAbs(entryPrice - g_otePoints[i].level);
         if(distance < closestDistance)
         {
            closestDistance = distance;
            conditions.oteType = g_otePoints[i].type;
            conditions.oteLevel = g_otePoints[i].level;
            conditions.oteStrength = g_otePoints[i].strength;
         }
      }
   }

   // Lower timeframe conditions
   conditions.hasLTFBreak = g_ltfAnalysis.hasStructureBreak;
   conditions.hasLTFConfirmation = g_ltfAnalysis.hasConfirmationCandle;
   conditions.hasOTERetest = g_ltfAnalysis.hasOTERetest;
   conditions.ltfBreakType = g_ltfAnalysis.isBullishBreak ? "Bullish" : "Bearish";

   // Fibonacci conditions
   conditions.nearFibLevel = false;
   for(int i = 0; i < ArraySize(g_fibLevels); i++)
   {
      double distance = MathAbs(entryPrice - g_fibLevels[i]) / _Point;
      if(distance < 20) // Within 20 points
      {
         conditions.nearFibLevel = true;
         conditions.fibLevel = g_fibLevels[i];
         conditions.fibType = GetFibLevelName(g_fibLevels[i]);
         break;
      }
   }

   // Order block conditions
   conditions.nearOrderBlock = false;
   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
   {
      if(g_orderBlocks[i].exists && g_orderBlocks[i].isActive)
      {
         if(entryPrice >= g_orderBlocks[i].low && entryPrice <= g_orderBlocks[i].high)
         {
            conditions.nearOrderBlock = true;
            conditions.orderBlockHigh = g_orderBlocks[i].high;
            conditions.orderBlockLow = g_orderBlocks[i].low;
            conditions.orderBlockBullish = g_orderBlocks[i].isBullish;
            break;
         }
      }
   }

   // Volume conditions
   conditions.volumeConfirmation = CheckVolumeConfirmation(orderType == ORDER_TYPE_BUY);
   conditions.volumeRatioValue = conditions.volumeRatio;

   // Risk management
   conditions.riskAmount = MathAbs(entryPrice - stopLoss) * lotSize * 100000; // Approximate risk in account currency
   conditions.riskPercent = RiskPercent;
   conditions.rewardRiskRatio = MathAbs(targetPrice - entryPrice) / MathAbs(entryPrice - stopLoss);

   return conditions;
}

//+------------------------------------------------------------------+
//| Get Fibonacci level name                                          |
//+------------------------------------------------------------------+
string GetFibLevelName(double level)
{
   if(MathAbs(level - 0.236) < 0.001) return "0.236";
   if(MathAbs(level - 0.382) < 0.001) return "0.382";
   if(MathAbs(level - 0.618) < 0.001) return "0.618";
   if(MathAbs(level - 0.786) < 0.001) return "0.786";
   return "Custom";
}

//+------------------------------------------------------------------+
//| Log trading conditions to console                                 |
//+------------------------------------------------------------------+
void LogTradingConditions(const TradingConditions &conditions)
{
   Print("=== TRADING CONDITIONS LOG ===");
   Print("Entry Time: ", TimeToString(conditions.entryTime));
   Print("Order Type: ", EnumToString(conditions.orderType));
   Print("Entry Price: ", DoubleToString(conditions.entryPrice, _Digits));
   Print("Stop Loss: ", DoubleToString(conditions.stopLoss, _Digits));
   Print("Target Price: ", DoubleToString(conditions.targetPrice, _Digits));
   Print("Lot Size: ", DoubleToString(conditions.lotSize, 2));
   Print("Current Price: ", DoubleToString(conditions.currentPrice, _Digits));
   Print("ATR Value: ", DoubleToString(conditions.atrValue, _Digits));
   Print("Volume: ", DoubleToString(conditions.volume, 0));
   Print("Volume Ratio: ", DoubleToString(conditions.volumeRatio, 2));
   Print("In Kill Zone: ", conditions.inKillZone ? "Yes" : "No");
   Print("Kill Zone Type: ", conditions.killZoneType);
   Print("Market Structure Bullish: ", conditions.marketStructureBullish ? "Yes" : "No");
   Print("Has Liquidity Sweep: ", conditions.hasLiquiditySweep ? "Yes" : "No");
   Print("Has FVG: ", conditions.hasFVG ? "Yes" : "No");
   if(conditions.hasFVG)
   {
      Print("FVG Type: ", conditions.fvgType);
      Print("FVG Filled: ", conditions.fvgFilled ? "Yes" : "No");
   }
   Print("Has OTE: ", conditions.hasOTE ? "Yes" : "No");
   Print("Has LTF Break: ", conditions.hasLTFBreak ? "Yes" : "No");
   Print("Has LTF Confirmation: ", conditions.hasLTFConfirmation ? "Yes" : "No");
   Print("Near Fib Level: ", conditions.nearFibLevel ? "Yes" : "No");
   Print("Near Order Block: ", conditions.nearOrderBlock ? "Yes" : "No");
   Print("Volume Confirmation: ", conditions.volumeConfirmation ? "Yes" : "No");
   Print("Risk Amount: ", DoubleToString(conditions.riskAmount, 2));
   Print("Risk Percent: ", DoubleToString(conditions.riskPercent, 2));
   Print("Reward/Risk Ratio: ", DoubleToString(conditions.rewardRiskRatio, 2));
   Print("================================");
}

//+------------------------------------------------------------------+
//| Save trading conditions to file                                   |
//+------------------------------------------------------------------+
void SaveTradingConditionsToFile(ulong ticket, const TradingConditions &conditions)
{
   string filename = "trading_conditions_" + IntegerToString(ticket) + ".json";
   int fileHandle = FileOpen(filename, FILE_WRITE|FILE_TXT);

   if(fileHandle != INVALID_HANDLE)
   {
      string json = "{";
      json += "\"ticket\":" + IntegerToString(ticket) + ",";
      json += "\"entryTime\":\"" + Api_DateTimeToString(conditions.entryTime) + "\",";
      json += "\"orderType\":\"" + EnumToString(conditions.orderType) + "\",";
      json += "\"entryPrice\":" + DoubleToString(conditions.entryPrice, _Digits) + ",";
      json += "\"stopLoss\":" + DoubleToString(conditions.stopLoss, _Digits) + ",";
      json += "\"targetPrice\":" + DoubleToString(conditions.targetPrice, _Digits) + ",";
      json += "\"lotSize\":" + DoubleToString(conditions.lotSize, 2) + ",";
      json += "\"currentPrice\":" + DoubleToString(conditions.currentPrice, _Digits) + ",";
      json += "\"atrValue\":" + DoubleToString(conditions.atrValue, _Digits) + ",";
      json += "\"volume\":" + DoubleToString(conditions.volume, 0) + ",";
      json += "\"volumeRatio\":" + DoubleToString(conditions.volumeRatio, 2) + ",";
      json += "\"inKillZone\":" + (conditions.inKillZone ? "true" : "false") + ",";
      json += "\"killZoneType\":\"" + conditions.killZoneType + "\",";
      json += "\"hasMarketStructure\":" + (conditions.hasMarketStructure ? "true" : "false") + ",";
      json += "\"marketStructureBullish\":" + (conditions.marketStructureBullish ? "true" : "false") + ",";
      json += "\"hasLiquiditySweep\":" + (conditions.hasLiquiditySweep ? "true" : "false") + ",";
      json += "\"hasFVG\":" + (conditions.hasFVG ? "true" : "false") + ",";
      json += "\"fvgType\":\"" + conditions.fvgType + "\",";
      json += "\"fvgFilled\":" + (conditions.fvgFilled ? "true" : "false") + ",";
      json += "\"hasOTE\":" + (conditions.hasOTE ? "true" : "false") + ",";
      json += "\"oteType\":\"" + conditions.oteType + "\",";
      json += "\"hasLTFBreak\":" + (conditions.hasLTFBreak ? "true" : "false") + ",";
      json += "\"hasLTFConfirmation\":" + (conditions.hasLTFConfirmation ? "true" : "false") + ",";
      json += "\"nearFibLevel\":" + (conditions.nearFibLevel ? "true" : "false") + ",";
      json += "\"nearOrderBlock\":" + (conditions.nearOrderBlock ? "true" : "false") + ",";
      json += "\"volumeConfirmation\":" + (conditions.volumeConfirmation ? "true" : "false") + ",";
      json += "\"riskAmount\":" + DoubleToString(conditions.riskAmount, 2) + ",";
      json += "\"riskPercent\":" + DoubleToString(conditions.riskPercent, 2) + ",";
      json += "\"rewardRiskRatio\":" + DoubleToString(conditions.rewardRiskRatio, 2);
      json += "}";

      FileWriteString(fileHandle, json);
      FileClose(fileHandle);
      Print("Trading conditions saved to: ", filename);
   }
   else
   {
      Print("Failed to save trading conditions to file");
   }
}
