//+------------------------------------------------------------------+
//|                                    MultiTimeframe_Trend_EA.mq5 |
//|                                  Copyright 2024, Jason Carty           |
//|                     https://github.com/jason-carty/mt5-trader-ea  |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <MovingAverages.mqh>
#include "../TradeUtils.mqh"

#property copyright "Copyright 2024"
#property version   "1.0"
#property description "Multi-Timeframe Trend Following EA with Support/Resistance Areas"
#property description "Reads higher timeframe trends, finds areas of interest, waits for lower timeframe alignment"
#property link      "https://github.com/jason-carty/mt5-trader-ea"

// Timeframe Parameters
input group "Timeframe Settings"
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H4;    // Higher timeframe for trend analysis
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_M15;    // Lower timeframe for entry signals

// Risk Management Parameters
input group "Risk Management"
input double MaxRiskPercent = 1.0;                    // Maximum risk per trade (%)
input double MinLotSize = 0.01;                       // Minimum lot size
input double MaxLotSize = 50.0;                       // Maximum lot size
input int    MaxPositions = 3;                        // Maximum number of open positions

// Support/Resistance Parameters
input group "Support/Resistance Settings"
input int    MinBounces = 3;                          // Minimum bounces required for area validation;
input int    MaxAgeYears = 3;                         // Maximum age of areas in years;
input double AreaTolerance = 10.0;                    // Tolerance for area identification (points);
input int    LookbackBars = 500;                      // Bars to look back for areas;

// Trend Analysis Parameters
input group "Trend Analysis"
input int    TrendPeriod = 20;                        // Period for trend calculation;
input ENUM_MA_METHOD TrendMethod = MODE_SMA;          // Moving average method for trend;
input ENUM_APPLIED_PRICE TrendPrice = PRICE_CLOSE;    // Price type for trend calculation

// Reversal Candle Parameters
input group "Reversal Candle Settings"
input double MinBodyRatio = 0.4;                      // Minimum body to wick ratio for reversal (reduced from 0.6)
input double MinCandleSize = 2.0;                     // Minimum candle size in points (reduced from 5.0)
input bool   RequireVolumeConfirmation = false;       // Require volume confirmation (changed to false by default)
input double MinVolumeRatio = 1.2;                    // Minimum volume ratio for confirmation (reduced from 1.5)

// Trading Parameters
input group "Trading Settings"
input int    MagicNumber = 234567;                    // Magic number for order identification;
input bool   RequireConfirmation = false;             // Ask for confirmation before placing trades;

// Debug Parameters
input group "Debug Settings"
input bool   EnableDebugLogs = true;                  // Enable debug logging
input bool   DrawAreasOfInterest = true;              // Draw support/resistance areas on chart
input color  SupportColor = clrGreen;                 // Color for support areas;
input color  ResistanceColor = clrRed;                // Color for resistance areas;

// Global variables
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// Time tracking
datetime lastHigherTimeframeBar = 0;
datetime lastLowerTimeframeBar = 0;

// Market structure
enum MARKET_TREND {
    TREND_BULLISH,
    TREND_BEARISH,
    TREND_SIDEWAYS
};

// Support/Resistance area structure
struct AreaOfInterest {
    double level;              // Price level
    bool isSupport;            // True for support, false for resistance
    datetime firstTouch;       // First time price touched this level
    datetime lastTouch;        // Last time price touched this level
    int bounceCount;           // Number of bounces
    double strength;           // Strength based on bounces and recency
    int areaId;                // Unique ID for the area
};

// Current market state
struct MarketState {
    MARKET_TREND higherTimeframeTrend;
    MARKET_TREND lowerTimeframeTrend;
    double nearestSupport;
    double nearestResistance;
    bool nearAreaOfInterest;
    bool reversalCandleFormed;
    ENUM_ORDER_TYPE pendingOrderType;
    double pendingEntryPrice;
    double pendingStopLoss;
    double pendingTakeProfit;
};

MarketState currentMarketState = {};

// Arrays to store areas of interest
AreaOfInterest supportAreas[];
AreaOfInterest resistanceAreas[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== Multi-Timeframe Trend EA v1.0 ===");
    Print("Higher Timeframe: ", EnumToString(HigherTimeframe));
    Print("Lower Timeframe: ", EnumToString(LowerTimeframe));
    
    // Initialize trade object
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialize symbol info
    symbolInfo.Name(_Symbol);
    symbolInfo.RefreshRates();
    
    // Initialize time tracking
    lastHigherTimeframeBar = iTime(_Symbol, HigherTimeframe, 0);
    lastLowerTimeframeBar = iTime(_Symbol, LowerTimeframe, 0);
    
    // Initialize areas of interest
    InitializeAreasOfInterest();
    
    Print("EA Initialized Successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== Multi-Timeframe Trend EA Deinitialized ===");
    
    // Clean up drawings
    if(DrawAreasOfInterest)
    {
        ObjectsDeleteAll(0, "MT_Area_");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new candles on different timeframes
    bool newHigherTimeframeBar = CheckNewBar(HigherTimeframe, lastHigherTimeframeBar);
    bool newLowerTimeframeBar = CheckNewBar(LowerTimeframe, lastLowerTimeframeBar);
    
    // Update market state based on new candles
    if(newHigherTimeframeBar)
    {
        if(IsNewsTime(_Symbol, 30, 30, true, EnableDebugLogs)) return;
        if(EnableDebugLogs) Print("=== New Higher Timeframe Bar ===");
        
        // Store previous trend before analyzing new one
        MARKET_TREND previousTrend = currentMarketState.higherTimeframeTrend;
        
        AnalyzeHigherTimeframeTrend();
        UpdateAreasOfInterest();
        
        // Check if trend changed and close profitable positions if needed
        if(previousTrend != currentMarketState.higherTimeframeTrend)
        {
            if(EnableDebugLogs) Print("Higher timeframe trend changed from ", EnumToString(previousTrend), " to ", EnumToString(currentMarketState.higherTimeframeTrend));
            CloseProfitablePositionsOnTrendChange();
        }
    }
    
    if(newLowerTimeframeBar)
    {
        // Check for news filter
        if(IsNewsTime(_Symbol, 30, 30, true, EnableDebugLogs)) return;
        if(EnableDebugLogs) Print("=== New Lower Timeframe Bar ===");
        AnalyzeLowerTimeframeTrend();
        CheckTrendAlignment();
        CheckForReversalCandles();
        CheckForTradeOpportunities();
    }
    
    // Update trailing stops
    UpdateTrailingStops();

    
}

//+------------------------------------------------------------------+
//| Check for new bar on specified timeframe                         |
//+------------------------------------------------------------------+
bool CheckNewBar(ENUM_TIMEFRAMES timeframe, datetime &lastBarTime)
{
    datetime currentBarTime = iTime(_Symbol, timeframe, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Analyze higher timeframe trend                                   |
//+------------------------------------------------------------------+
void AnalyzeHigherTimeframeTrend()
{
    double maBuffer[];
    ArraySetAsSeries(maBuffer, true);
    
    int maHandle = iMA(_Symbol, HigherTimeframe, TrendPeriod, 0, TrendMethod, TrendPrice);
    if(maHandle == INVALID_HANDLE || CopyBuffer(maHandle, 0, 0, 3, maBuffer) <= 0)
    {
        Print("Failed to get higher timeframe MA data");
        IndicatorRelease(maHandle);
        return;
    }
    
    double currentMA = maBuffer[0];
    double previousMA = maBuffer[1];
    double olderMA = maBuffer[2];
    
    // Get current price
    double currentPrice = iClose(_Symbol, HigherTimeframe, 0);
    
    // Determine trend
    if(currentPrice > currentMA && currentMA > previousMA && previousMA > olderMA)
    {
        currentMarketState.higherTimeframeTrend = TREND_BULLISH;
        if(EnableDebugLogs) Print("Higher Timeframe Trend: BULLISH");
    }
    else if(currentPrice < currentMA && currentMA < previousMA && previousMA < olderMA)
    {
        currentMarketState.higherTimeframeTrend = TREND_BEARISH;
        if(EnableDebugLogs) Print("Higher Timeframe Trend: BEARISH");
    }
    else
    {
        currentMarketState.higherTimeframeTrend = TREND_SIDEWAYS;
        if(EnableDebugLogs) Print("Higher Timeframe Trend: SIDEWAYS");
    }
    
    IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| Analyze lower timeframe trend                                    |
//+------------------------------------------------------------------+
void AnalyzeLowerTimeframeTrend()
{
    double maBuffer[];
    ArraySetAsSeries(maBuffer, true);
    
    int maHandle = iMA(_Symbol, LowerTimeframe, TrendPeriod, 0, TrendMethod, TrendPrice);
    if(maHandle == INVALID_HANDLE || CopyBuffer(maHandle, 0, 0, 3, maBuffer) <= 0)
    {
        Print("Failed to get lower timeframe MA data");
        IndicatorRelease(maHandle);
        return;
    }
    
    double currentMA = maBuffer[0];
    double previousMA = maBuffer[1];
    double olderMA = maBuffer[2];
    
    // Get current price
    double currentPrice = iClose(_Symbol, LowerTimeframe, 0);
    
    // Determine trend
    if(currentPrice > currentMA && currentMA > previousMA && previousMA > olderMA)
    {
        currentMarketState.lowerTimeframeTrend = TREND_BULLISH;
        if(EnableDebugLogs) Print("Lower Timeframe Trend: BULLISH");
    }
    else if(currentPrice < currentMA && currentMA < previousMA && previousMA < olderMA)
    {
        currentMarketState.lowerTimeframeTrend = TREND_BEARISH;
        if(EnableDebugLogs) Print("Lower Timeframe Trend: BEARISH");
    }
    else
    {
        currentMarketState.lowerTimeframeTrend = TREND_SIDEWAYS;
        if(EnableDebugLogs) Print("Lower Timeframe Trend: SIDEWAYS");
    }
    
    IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| Check if trends are aligned                                      |
//+------------------------------------------------------------------+
void CheckTrendAlignment()
{
    if(EnableDebugLogs)
    {
        Print("Trend alignment check removed - focusing on areas of interest only");
    }
}

//+------------------------------------------------------------------+
//| Initialize areas of interest                                     |
//+------------------------------------------------------------------+
void InitializeAreasOfInterest()
{
    ArrayResize(supportAreas, 0);
    ArrayResize(resistanceAreas, 0);
    
    // Find existing areas from historical data
    FindAreasOfInterest();
    
    if(EnableDebugLogs)
    {
        Print("Initialized Areas of Interest:");
        Print("Support Areas: ", ArraySize(supportAreas));
        Print("Resistance Areas: ", ArraySize(resistanceAreas));
    }
}

//+------------------------------------------------------------------+
//| Find areas of interest from historical data                      |
//+------------------------------------------------------------------+
void FindAreasOfInterest()
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    // Get data from higher timeframe for area identification
    if(CopyHigh(_Symbol, HigherTimeframe, 0, LookbackBars, high) <= 0 ||
       CopyLow(_Symbol, HigherTimeframe, 0, LookbackBars, low) <= 0 ||
       CopyClose(_Symbol, HigherTimeframe, 0, LookbackBars, close) <= 0)
    {
        Print("Failed to get historical data for area identification");
        return;
    }
    
    // Find swing highs (potential resistance)
    for(int i = 2; i < LookbackBars - 2; i++)
    {
        if(high[i] > high[i-1] && high[i] > high[i-2] &&
           high[i] > high[i+1] && high[i] > high[i+2])
        {
            AddAreaOfInterest(high[i], false, iTime(_Symbol, HigherTimeframe, i));
        }
    }
    
    // Find swing lows (potential support)
    for(int i = 2; i < LookbackBars - 2; i++)
    {
        if(low[i] < low[i-1] && low[i] < low[i-2] &&
           low[i] < low[i+1] && low[i] < low[i+2])
        {
            AddAreaOfInterest(low[i], true, iTime(_Symbol, HigherTimeframe, i));
        }
    }
    
    // Validate areas based on bounces and age
    ValidateAreasOfInterest();
}

//+------------------------------------------------------------------+
//| Add area of interest                                             |
//+------------------------------------------------------------------+
void AddAreaOfInterest(double level, bool isSupport, datetime touchTime)
{
    AreaOfInterest areas[];
    if(isSupport)
    {
        ArrayCopy(areas, supportAreas);
    }
    else
    {
        ArrayCopy(areas, resistanceAreas);
    }
    
    // Check if area already exists (within tolerance)
    for(int i = 0; i < ArraySize(areas); i++)
    {
        if(MathAbs(areas[i].level - level) <= AreaTolerance * _Point)
        {
            // Update existing area
            areas[i].lastTouch = touchTime;
            areas[i].bounceCount++;
            areas[i].strength = CalculateAreaStrength(areas[i]);
            
            if(isSupport)
            {
                ArrayCopy(supportAreas, areas);
            }
            else
            {
                ArrayCopy(resistanceAreas, areas);
            }
            return;
        }
    }
    
    // Add new area
    ArrayResize(areas, ArraySize(areas) + 1);
    int index = ArraySize(areas) - 1;
    
    areas[index].level = level;
    areas[index].isSupport = isSupport;
    areas[index].firstTouch = touchTime;
    areas[index].lastTouch = touchTime;
    areas[index].bounceCount = 1;
    areas[index].strength = 1.0;
    areas[index].areaId = (isSupport ? ArraySize(supportAreas) : ArraySize(resistanceAreas)) + index;
    
    if(isSupport)
    {
        ArrayCopy(supportAreas, areas);
    }
    else
    {
        ArrayCopy(resistanceAreas, areas);
    }
}

//+------------------------------------------------------------------+
//| Calculate area strength based on bounces and recency             |
//+------------------------------------------------------------------+
double CalculateAreaStrength(const AreaOfInterest &area)
{
    double bounceScore = MathMin(area.bounceCount / (double)MinBounces, 3.0);
    
    // Age penalty (newer areas are stronger)
    datetime currentTime = TimeCurrent();
    double ageInDays = (currentTime - area.lastTouch) / 86400.0;
    double agePenalty = MathMax(0.1, 1.0 - (ageInDays / (MaxAgeYears * 365.0)));
    
    return bounceScore * agePenalty;
}

//+------------------------------------------------------------------+
//| Validate areas of interest                                       |
//+------------------------------------------------------------------+
void ValidateAreasOfInterest()
{
    datetime currentTime = TimeCurrent();
    datetime maxAge = currentTime - (MaxAgeYears * 365 * 24 * 60 * 60);
    
    // Filter support areas
    AreaOfInterest validSupports[];
    for(int i = 0; i < ArraySize(supportAreas); i++)
    {
        if(supportAreas[i].bounceCount >= MinBounces && 
           supportAreas[i].lastTouch >= maxAge)
        {
            ArrayResize(validSupports, ArraySize(validSupports) + 1);
            validSupports[ArraySize(validSupports) - 1] = supportAreas[i];
        }
    }
    ArrayCopy(supportAreas, validSupports);
    
    // Filter resistance areas
    AreaOfInterest validResistances[];
    for(int i = 0; i < ArraySize(resistanceAreas); i++)
    {
        if(resistanceAreas[i].bounceCount >= MinBounces && 
           resistanceAreas[i].lastTouch >= maxAge)
        {
            ArrayResize(validResistances, ArraySize(validResistances) + 1);
            validResistances[ArraySize(validResistances) - 1] = resistanceAreas[i];
        }
    }
    ArrayCopy(resistanceAreas, validResistances);
    
    // Draw areas on chart
    if(DrawAreasOfInterest)
    {
        DrawAreasOnChart();
    }
}

//+------------------------------------------------------------------+
//| Draw areas of interest on chart                                  |
//+------------------------------------------------------------------+
void DrawAreasOnChart()
{
    // Clear existing drawings
    ObjectsDeleteAll(0, "MT_Area_");
    
    // Draw support areas
    for(int i = 0; i < ArraySize(supportAreas); i++)
    {
        string name = "MT_Area_S_" + IntegerToString(supportAreas[i].areaId);
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, supportAreas[i].level);
        ObjectSetInteger(0, name, OBJPROP_COLOR, SupportColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetString(0, name, OBJPROP_TEXT, "Support " + DoubleToString(supportAreas[i].level, _Digits) + 
                       " (Bounces: " + IntegerToString(supportAreas[i].bounceCount) + ")");
    }
    
    // Draw resistance areas
    for(int i = 0; i < ArraySize(resistanceAreas); i++)
    {
        string name = "MT_Area_R_" + IntegerToString(resistanceAreas[i].areaId);
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, resistanceAreas[i].level);
        ObjectSetInteger(0, name, OBJPROP_COLOR, ResistanceColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetString(0, name, OBJPROP_TEXT, "Resistance " + DoubleToString(resistanceAreas[i].level, _Digits) + 
                       " (Bounces: " + IntegerToString(resistanceAreas[i].bounceCount) + ")");
    }
}

//+------------------------------------------------------------------+
//| Update areas of interest                                         |
//+------------------------------------------------------------------+
void UpdateAreasOfInterest()
{
    double ltfHigh = iHigh(_Symbol, LowerTimeframe, 1);
    double ltfLow = iLow(_Symbol, LowerTimeframe, 1);
    
    currentMarketState.nearAreaOfInterest = false;
    currentMarketState.nearestSupport = 0;
    currentMarketState.nearestResistance = 0;
    
    // Find nearest support
    for(int i = 0; i < ArraySize(supportAreas); i++)
    {
        if((ltfLow <= supportAreas[i].level + (AreaTolerance * _Point)) &&
           (ltfHigh >= supportAreas[i].level - (AreaTolerance * _Point)))
        {
            currentMarketState.nearAreaOfInterest = true;
            currentMarketState.nearestSupport = supportAreas[i].level;
            if(EnableDebugLogs) Print("Near Support Area (by wick): ", DoubleToString(supportAreas[i].level, _Digits));
            break;
        }
    }
    
    // Find nearest resistance
    for(int i = 0; i < ArraySize(resistanceAreas); i++)
    {
        if((ltfLow <= resistanceAreas[i].level + (AreaTolerance * _Point)) &&
           (ltfHigh >= resistanceAreas[i].level - (AreaTolerance * _Point)))
        {
            currentMarketState.nearAreaOfInterest = true;
            currentMarketState.nearestResistance = resistanceAreas[i].level;
            if(EnableDebugLogs) Print("Near Resistance Area (by wick): ", DoubleToString(resistanceAreas[i].level, _Digits));
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Check for reversal candles                                       |
//+------------------------------------------------------------------+
void CheckForReversalCandles()
{
    if(!currentMarketState.nearAreaOfInterest)
    {
        currentMarketState.reversalCandleFormed = false;
        if(EnableDebugLogs) Print("No reversal check: Near area=", currentMarketState.nearAreaOfInterest);
        return;
    }
    
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, LowerTimeframe, 0, 3, open) <= 0 ||
       CopyHigh(_Symbol, LowerTimeframe, 0, 3, high) <= 0 ||
       CopyLow(_Symbol, LowerTimeframe, 0, 3, low) <= 0 ||
       CopyClose(_Symbol, LowerTimeframe, 0, 3, close) <= 0)
    {
        if(EnableDebugLogs) Print("Failed to get candle data for reversal check");
        currentMarketState.reversalCandleFormed = false;
        return;
    }
    
    // Use the last completed bar (index 1)
    double o = open[1];
    double h = high[1];
    double l = low[1];
    double c = close[1];
    
    if(EnableDebugLogs) Print("Checking reversal candles - Open:", o, " High:", h, " Low:", l, " Close:", c);
    
    // Check for zero-range bar
    if(h == l && o == c && h == o)
    {
        if(EnableDebugLogs) Print("Zero-range bar detected (no price movement) - possible data issue or market closed");
        currentMarketState.reversalCandleFormed = false;
        return;
    }
    
    // Only allow trades in the direction of the higher timeframe trend
    // Buy: only if HTF trend is bullish
    if(currentMarketState.nearestSupport > 0 && currentMarketState.higherTimeframeTrend == TREND_BULLISH)
    {
        if(EnableDebugLogs) Print("Checking bullish reversal at support level:", currentMarketState.nearestSupport, " (HTF trend: BULLISH)");
        if(IsBullishReversalCandle(o, h, l, c))
        {
            currentMarketState.reversalCandleFormed = true;
            currentMarketState.pendingOrderType = ORDER_TYPE_BUY;
            currentMarketState.pendingEntryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(EnableDebugLogs) Print("Bullish Reversal Candle Detected at Support (HTF trend respected)");
        }
        else
        {
            if(EnableDebugLogs) Print("Bullish reversal candle conditions not met");
            currentMarketState.reversalCandleFormed = false;
        }
    }
    // Sell: only if HTF trend is bearish
    else if(currentMarketState.nearestResistance > 0 && currentMarketState.higherTimeframeTrend == TREND_BEARISH)
    {
        if(EnableDebugLogs) Print("Checking bearish reversal at resistance level:", currentMarketState.nearestResistance, " (HTF trend: BEARISH)");
        if(IsBearishReversalCandle(o, h, l, c))
        {
            currentMarketState.reversalCandleFormed = true;
            currentMarketState.pendingOrderType = ORDER_TYPE_SELL;
            currentMarketState.pendingEntryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(EnableDebugLogs) Print("Bearish Reversal Candle Detected at Resistance (HTF trend respected)");
        }
        else
        {
            if(EnableDebugLogs) Print("Bearish reversal candle conditions not met");
            currentMarketState.reversalCandleFormed = false;
        }
    }
    else
    {
        if(EnableDebugLogs) Print("Reversal detected but ignored due to higher timeframe trend direction");
        currentMarketState.reversalCandleFormed = false;
    }
}

//+------------------------------------------------------------------+
//| Check if candle is bullish reversal                              |
//+------------------------------------------------------------------+
bool IsBullishReversalCandle(double open, double high, double low, double close)
{
    double bodySize = close - open;
    double totalRange = high - low;
    
    if(EnableDebugLogs) Print("Bullish reversal check - Body size:", bodySize, " Total range:", totalRange);
    
    if(bodySize <= 0 || totalRange <= 0) 
    {
        if(EnableDebugLogs) Print("Invalid candle: body size or total range <= 0");
        return false;
    }
    
    double bodyRatio = bodySize / totalRange;
    
    if(EnableDebugLogs) Print("Body ratio:", bodyRatio, " (min required:", MinBodyRatio, ")");
    
    // Check body to wick ratio
    if(bodyRatio < MinBodyRatio) 
    {
        if(EnableDebugLogs) Print("Body ratio too low");
        return false;
    }
    
    // Check minimum candle size
    if(totalRange < MinCandleSize * _Point) 
    {
        if(EnableDebugLogs) Print("Candle size too small: ", totalRange, " < ", MinCandleSize * _Point);
        return false;
    }
    
    // Check volume confirmation if required
    if(RequireVolumeConfirmation)
    {
        if(!CheckVolumeConfirmation()) 
        {
            if(EnableDebugLogs) Print("Volume confirmation failed");
            return false;
        }
    }
    
    if(EnableDebugLogs) Print("Bullish reversal candle conditions met!");
    return true;
}

//+------------------------------------------------------------------+
//| Check if candle is bearish reversal                              |
//+------------------------------------------------------------------+
bool IsBearishReversalCandle(double open, double high, double low, double close)
{
    double bodySize = open - close;
    double totalRange = high - low;
    
    if(EnableDebugLogs) Print("Bearish reversal check - Body size:", bodySize, " Total range:", totalRange);
    
    if(bodySize <= 0 || totalRange <= 0) 
    {
        if(EnableDebugLogs) Print("Invalid candle: body size or total range <= 0");
        return false;
    }
    
    double bodyRatio = bodySize / totalRange;
    
    if(EnableDebugLogs) Print("Body ratio:", bodyRatio, " (min required:", MinBodyRatio, ")");
    
    // Check body to wick ratio
    if(bodyRatio < MinBodyRatio) 
    {
        if(EnableDebugLogs) Print("Body ratio too low");
        return false;
    }
    
    // Check minimum candle size
    if(totalRange < MinCandleSize * _Point) 
    {
        if(EnableDebugLogs) Print("Candle size too small: ", totalRange, " < ", MinCandleSize * _Point);
        return false;
    }
    
    // Check volume confirmation if required
    if(RequireVolumeConfirmation)
    {
        if(!CheckVolumeConfirmation()) 
        {
            if(EnableDebugLogs) Print("Volume confirmation failed");
            return false;
        }
    }
    
    if(EnableDebugLogs) Print("Bearish reversal candle conditions met!");
    return true;
}

//+------------------------------------------------------------------+
//| Check volume confirmation                                        |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation()
{
    long volumes[];
    ArraySetAsSeries(volumes, true);
    
    if(CopyTickVolume(_Symbol, LowerTimeframe, 0, 20, volumes) <= 0)
    {
        return false;
    }
    
    double currentVolume = (double)volumes[1]; // Last completed bar
    
    // Calculate average volume
    double avgVolume = 0;
    for(int i = 2; i < 20; i++)
    {
        avgVolume += (double)volumes[i];
    }
    avgVolume /= 18.0;
    
    double volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 0;
    
    return volumeRatio >= MinVolumeRatio;
}

//+------------------------------------------------------------------+
//| Check for trade opportunities                                    |
//+------------------------------------------------------------------+
void CheckForTradeOpportunities()
{
    if(!currentMarketState.reversalCandleFormed) return;
    
    // Check if we can open new positions
    if(CountOpenPositions(_Symbol) >= MaxPositions)
    {
        if(EnableDebugLogs) Print("Maximum positions reached");
        return;
    }
    
    // Calculate stop loss and take profit
    CalculateStopLossAndTakeProfit();
    
    // Calculate lot size
    double stopDistance = MathAbs(currentMarketState.pendingEntryPrice - currentMarketState.pendingStopLoss);
    double lotSize = CalculateLotSize(MaxRiskPercent, stopDistance, _Symbol);
    
    if(lotSize <= 0)
    {
        if(EnableDebugLogs) Print("Invalid lot size calculated");
        return;
    }
    
    // Execute trade
    if(RequireConfirmation)
    {
        string message = "Trade Signal Detected\n" +
                        "Type: " + (currentMarketState.pendingOrderType == ORDER_TYPE_BUY ? "BUY" : "SELL") + "\n" +
                        "Entry: " + DoubleToString(currentMarketState.pendingEntryPrice, _Digits) + "\n" +
                        "Stop Loss: " + DoubleToString(currentMarketState.pendingStopLoss, _Digits) + "\n" +
                        "Take Profit: " + DoubleToString(currentMarketState.pendingTakeProfit, _Digits) + "\n" +
                        "Lot Size: " + DoubleToString(lotSize, 2);
        
        if(MessageBox(message, "Multi-Timeframe Trend EA", MB_YESNO|MB_ICONQUESTION) == IDYES)
        {
            ExecuteTrade();
        }
    }
    else
    {
        ExecuteTrade();
    }
}

//+------------------------------------------------------------------+
//| Calculate stop loss and take profit                              |
//+------------------------------------------------------------------+
void CalculateStopLossAndTakeProfit()
{
    double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    double buffer = MathMax(stopsLevel, spread * 2); // Use at least the minimum stop level or 2x spread

    if(currentMarketState.pendingOrderType == ORDER_TYPE_BUY)
    {
        // For buy orders, stop loss is previous swing low minus buffer
        double swingLow = FindSwingLow(_Symbol, LowerTimeframe, 20);
        if(swingLow > 0)
        {
            currentMarketState.pendingStopLoss = swingLow - buffer;
        }
        else
        {
            // Fallback: use a fixed distance below entry
            currentMarketState.pendingStopLoss = currentMarketState.pendingEntryPrice - (buffer * 10);
        }
        // Take profit is always 2x stop loss distance from entry
        double stopDistance = currentMarketState.pendingEntryPrice - currentMarketState.pendingStopLoss;
        currentMarketState.pendingTakeProfit = currentMarketState.pendingEntryPrice + 2 * stopDistance;
    }
    else // ORDER_TYPE_SELL
    {
        // For sell orders, stop loss is previous swing high plus buffer
        double swingHigh = FindSwingHigh(_Symbol, LowerTimeframe, 20);
        if(swingHigh > 0)
        {
            currentMarketState.pendingStopLoss = swingHigh + buffer;
        }
        else
        {
            // Fallback: use a fixed distance above entry
            currentMarketState.pendingStopLoss = currentMarketState.pendingEntryPrice + (buffer * 10);
        }
        // Take profit is always 2x stop loss distance from entry
        double stopDistance = currentMarketState.pendingStopLoss - currentMarketState.pendingEntryPrice;
        currentMarketState.pendingTakeProfit = currentMarketState.pendingEntryPrice - 2 * stopDistance;
    }

    // Validate that stop loss and take profit are in correct direction
    if(currentMarketState.pendingOrderType == ORDER_TYPE_BUY)
    {
        if(currentMarketState.pendingStopLoss >= currentMarketState.pendingEntryPrice)
        {
            currentMarketState.pendingStopLoss = currentMarketState.pendingEntryPrice - (buffer * 10);
        }
        if(currentMarketState.pendingTakeProfit <= currentMarketState.pendingEntryPrice)
        {
            currentMarketState.pendingTakeProfit = currentMarketState.pendingEntryPrice + (buffer * 20);
        }
    }
    else // ORDER_TYPE_SELL
    {
        if(currentMarketState.pendingStopLoss <= currentMarketState.pendingEntryPrice)
        {
            currentMarketState.pendingStopLoss = currentMarketState.pendingEntryPrice + (buffer * 10);
        }
        if(currentMarketState.pendingTakeProfit >= currentMarketState.pendingEntryPrice)
        {
            currentMarketState.pendingTakeProfit = currentMarketState.pendingEntryPrice - (buffer * 20);
        }
    }

    if(EnableDebugLogs)
    {
        Print("Entry Price: ", DoubleToString(currentMarketState.pendingEntryPrice, _Digits));
        Print("Stop Loss: ", DoubleToString(currentMarketState.pendingStopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(currentMarketState.pendingTakeProfit, _Digits));
        Print("SL buffer used: ", DoubleToString(buffer, _Digits));
        // Calculate and display risk-reward ratio
        double stopDistance = MathAbs(currentMarketState.pendingEntryPrice - currentMarketState.pendingStopLoss);
        double profitDistance = MathAbs(currentMarketState.pendingEntryPrice - currentMarketState.pendingTakeProfit);
        double riskRewardRatio = profitDistance / stopDistance;
        Print("Risk-Reward Ratio: 1:", DoubleToString(riskRewardRatio, 2));
    }
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade()
{
    double lotSize = CalculateLotSize(MaxRiskPercent, MathAbs(currentMarketState.pendingEntryPrice - currentMarketState.pendingStopLoss), _Symbol);
    
    bool tradeResult = false;
    if(currentMarketState.pendingOrderType == ORDER_TYPE_BUY)
        tradeResult = PlaceBuyOrder(lotSize, currentMarketState.pendingStopLoss, currentMarketState.pendingTakeProfit, MagicNumber, "MT Trend EA v1.0");
    else
        tradeResult = PlaceSellOrder(lotSize, currentMarketState.pendingStopLoss, currentMarketState.pendingTakeProfit, MagicNumber, "MT Trend EA v1.0");
    if(tradeResult)
    {
        Print("=== Trade Executed Successfully ===");
        Print("Type: ", currentMarketState.pendingOrderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
        Print("Entry: ", DoubleToString(currentMarketState.pendingEntryPrice, _Digits));
        Print("Stop Loss: ", DoubleToString(currentMarketState.pendingStopLoss, _Digits));
        Print("Take Profit: ", DoubleToString(currentMarketState.pendingTakeProfit, _Digits));
        Print("Lot Size: ", DoubleToString(lotSize, 2));
        currentMarketState.reversalCandleFormed = false;
    }
    else
    {
        Print("Failed to execute trade");
    }
}

//+------------------------------------------------------------------+
//| Update trailing stops                                            |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
    // This function can be expanded to implement trailing stops if needed
    // For now, we'll use fixed stop loss and take profit levels
}

//+------------------------------------------------------------------+
//| Get trade retcode description                                    |
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
//| Close profitable positions on trend change                        |
//+------------------------------------------------------------------+
void CloseProfitablePositionsOnTrendChange()
{
    if(EnableDebugLogs) Print("Checking for profitable positions to close due to trend change...");
    
    int totalPositions = CountOpenPositions(_Symbol);
    int closedCount = 0;
    
    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            // Check if this position belongs to our EA
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                double positionProfit = PositionGetDouble(POSITION_PROFIT);
                double positionSwap = PositionGetDouble(POSITION_SWAP);
                double totalProfit = positionProfit + positionSwap;
                
                if(EnableDebugLogs) 
                {
                    Print("Position ", ticket, " - Profit: ", DoubleToString(positionProfit, 2), 
                          " Swap: ", DoubleToString(positionSwap, 2), 
                          " Total: ", DoubleToString(totalProfit, 2));
                }
                
                // Close position if it's in profit
                if(totalProfit > 0)
                {
                    if(trade.PositionClose(ticket))
                    {
                        closedCount++;
                        if(EnableDebugLogs) 
                        {
                            Print("Closed profitable position ", ticket, " with total profit: ", DoubleToString(totalProfit, 2));
                        }
                    }
                    else
                    {
                        if(EnableDebugLogs) 
                        {
                            Print("Failed to close position ", ticket, " Error: ", GetLastError());
                        }
                    }
                }
                else
                {
                    if(EnableDebugLogs) Print("Position ", ticket, " not in profit, keeping open");
                }
            }
        }
    }
    
    if(EnableDebugLogs) Print("Trend change position management complete. Closed ", closedCount, " profitable positions.");
} 