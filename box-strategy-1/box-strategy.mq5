//+------------------------------------------------------------------+
//|                                               box-strategy.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: Multi-Session Box Breakout Strategy                |
//| Description:                                                       |
//|   A versatile trading strategy that uses session-based price       |
//|   boxes to identify and trade breakouts. It works with multiple    |
//|   currency pairs and adapts to different session characteristics.  |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Price breaks above session box high with momentum        |
//|   - SELL: Price breaks below session box low with momentum        |
//|   - Volume and volatility confirmations                           |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Box-size based take profit                                    |
//|   - Session end exits                                             |
//|   - Trailing stops based on box size                              |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Dynamic position sizing based on box size                     |
//|   - Session-specific risk limits                                  |
//|   - Multiple timeframe risk checks                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_chart_window   // Allow drawing on chart

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Color constants for zones
const color TOP_ZONE_COLOR = C'255,200,200';    // Light red for no-buy zone
const color BOTTOM_ZONE_COLOR = C'200,200,255'; // Light blue for no-sell zone
const color MIDDLE_ZONE_COLOR = C'240,240,240'; // Very light gray for no-trade zone
const color VALID_ZONE_COLOR = C'255,255,255';  // White for valid trade zones
const int ZONE_TRANSPARENCY = 204;           // Zone transparency (0-255, where 204 is 80% opaque)

// Object name prefixes
const string ZONE_PREFIX = "BoxZone_";
const string TOP_ZONE = "TopZone";
const string BOTTOM_ZONE = "BottomZone";
const string MIDDLE_ZONE = "MiddleZone";
const string VALID_TOP_ZONE = "ValidTopZone";
const string VALID_BOTTOM_ZONE = "ValidBottomZone";

// Input Parameters
input double   RiskPercent = 1.0;     // Risk percent per trade
input double   BoxDeviationPips = 50;  // Box deviation in pips (increased for XAUUSD)
input double   DojiBodyPercent = 10;   // Maximum body size % for Doji (increased)
input double   LongBodyPercent = 50;   // Minimum body size % for long candles (decreased)

// Additional input parameters for pattern strength
input int      StrengthPeriod = 10;    // Period for calculating average candle size (decreased)
input double   MinStrength = 50;       // Minimum pattern strength to trade (0-100) (decreased)
input bool     UseVolume = true;       // Use volume in strength calculation

// Additional input parameters for trade zones
input double   TopZonePercent = 40;    // Top zone percentage of box height (decreased)
input double   BottomZonePercent = 40; // Bottom zone percentage of box height (decreased)
input double   MiddleZonePercent = 20; // Middle zone percentage of box height (increased)

// Additional input parameters for risk management
input double   StopLossPercent = 1.0;  // Stop Loss as percentage of account balance
input bool     UseTrailingStop = true; // Use trailing stop
input double   TrailingPercent = 50.0; // Trailing stop as percentage of position size

// Additional input parameters for strategy improvements
input bool     UseVolumeFilter = false;    // Use volume confirmation
input bool     UseHigherTimeframe = false; // Use higher timeframe confirmation
input bool     UseMarketConditions = false; // Use market conditions filter
input bool     UseSessionFilter = false;   // Use trading session filter
input bool     UseDynamicBox = true;      // Use dynamic box based on volatility
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H4;  // Higher timeframe for confirmation
input int      VolumePeriod = 20;         // Period for volume average
input double   MinVolumeFactor = 1.5;     // Minimum volume factor for confirmation
input double   VolatilityFactor = 1.0;    // Factor for dynamic box adjustment

// Trading session times (in broker server time)
input int      LondonOpenHour = 8;        // London session open hour
input int      LondonCloseHour = 16;      // London session close hour
input int      NewYorkOpenHour = 13;      // New York session open hour
input int      NewYorkCloseHour = 21;     // New York session close hour

// Risk Management Parameters
input double   MaxDailyLossPercent = 2.0; // Maximum daily loss (% of balance)
input bool     UseBreakEven = true;       // Enable breakeven stops
input double   BreakEvenProfit = 1.0;     // Profit % to move stop to breakeven
input bool     UsePartialClose = true;     // Enable partial position close
input double   PartialCloseProfit = 0.5;   // Profit % for partial close
input double   PartialClosePercent = 50;   // Percentage of position to close

// Market Condition Parameters
input int      ADXPeriod = 14;            // ADX Period
input int      ADXThreshold = 25;         // Minimum ADX for trend trades
input bool     UseNewsFilter = true;       // Enable news filter
input int      NewsMinutesBefore = 30;    // Minutes before news to stop trading
input int      NewsMinutesAfter = 30;     // Minutes after news to resume trading

// Session visualization parameters
input color   LondonSessionColor = C'230,240,255';   // Light blue for London
input color   NewYorkSessionColor = C'255,240,230';  // Light orange for New York
input color   AsianSessionColor = C'240,255,230';    // Light green for Asian
input int     SessionTransparency = 90;             // Session transparency (0-255)
input bool    ShowSessions = true;                  // Show session backgrounds

// Additional session times
input int     AsianOpenHour = 0;                   // Asian session open hour
input int     AsianCloseHour = 9;                  // Asian session close hour

// Object name prefixes for sessions
const string  SESSION_PREFIX = "Session_";
const string  LONDON_SESSION = "London";
const string  NEWYORK_SESSION = "NewYork";
const string  ASIAN_SESSION = "Asian";

// Additional input parameters for pattern detection
input ENUM_TIMEFRAMES PatternTimeframe = PERIOD_M5;  // Timeframe for pattern detection

// Global Variables
double g_boxHigh;
double g_boxLow;
datetime g_lastDayProcessed;
bool g_isLongPosition = false;
bool g_isShortPosition = false;

// Candlestick pattern enums
enum CANDLE_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_DOJI = 1,
   PATTERN_HAMMER = 2,
   PATTERN_SHOOTING_STAR = 3,
   PATTERN_BULLISH_ENGULFING = 4,
   PATTERN_BEARISH_ENGULFING = 5,
   PATTERN_MORNING_STAR = 6,
   PATTERN_EVENING_STAR = 7,
   PATTERN_BOX_REVERSAL_BULL = 8,  // New pattern for bullish box reversal
   PATTERN_BOX_REVERSAL_BEAR = 9   // New pattern for bearish box reversal
};

// Structure to hold pattern information
struct PatternInfo
{
   CANDLE_PATTERN pattern;
   double strength;
};

//+------------------------------------------------------------------+
//| Check if price is in specific zone                                |
//+------------------------------------------------------------------+
enum PRICE_ZONE
{
   ZONE_TOP,
   ZONE_BOTTOM,
   ZONE_MIDDLE,
   ZONE_VALID_TRADE
};

//+------------------------------------------------------------------+
//| Performance Tracking
//+------------------------------------------------------------------+
struct TradeStats
{
   int totalTrades;
   int winningTrades;
   int losingTrades;
   double grossProfit;
   double grossLoss;
   double largestWin;
   double largestLoss;
   double maxDrawdown;
   datetime lastResetTime;
};

// Global Variables
TradeStats g_stats;
double g_initialBalance;
double g_maxBalance;
datetime g_lastNewsCheck;
bool g_newsEventNearby;

// Structure for session-specific statistics
struct SessionStats
{
   int totalTrades;
   int winningTrades;
   int losingTrades;
   double grossProfit;
   double grossLoss;
   double largestWin;
   double largestLoss;
   double winRate;
   double profitFactor;
   datetime lastResetTime;
};

// Global session statistics
SessionStats g_asianStats;
SessionStats g_londonStats;
SessionStats g_nyStats;

// Add these at the start of the file, after the existing constants
const string DEBUG_PREFIX = "BOX_STRATEGY_DEBUG: ";

// Add at the start of the file after includes
CTrade trade;  // Global trade object

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print(DEBUG_PREFIX, "Starting initialization...");

   // Initialize global variables
   g_boxHigh = 0;
   g_boxLow = 0;
   g_lastDayProcessed = 0;
   g_isLongPosition = false;
   g_isShortPosition = false;

   // Set up chart appearance
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, true); // Enable volume display

   // Clean up existing objects
   DeleteZoneObjects();
   DeleteSessionObjects();

   // Initialize statistics
   ResetStats();
   ResetSessionStats(g_asianStats);
   ResetSessionStats(g_londonStats);
   ResetSessionStats(g_nyStats);

   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_maxBalance = g_initialBalance;
   g_lastNewsCheck = 0;

   // Force initial box calculation
   if(!CalculateBox())
   {
      Print(DEBUG_PREFIX, "Failed to calculate initial box - check data availability");
      return INIT_FAILED;
   }

   // Draw initial zones and sessions
   DrawZones();
   if(ShowSessions)
      DrawSessions();

   Print(DEBUG_PREFIX, "Initialization completed successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Reset trading statistics                                          |
//+------------------------------------------------------------------+
void ResetStats()
{
   g_stats.totalTrades = 0;
   g_stats.winningTrades = 0;
   g_stats.losingTrades = 0;
   g_stats.grossProfit = 0;
   g_stats.grossLoss = 0;
   g_stats.largestWin = 0;
   g_stats.largestLoss = 0;
   g_stats.maxDrawdown = 0;
   g_stats.lastResetTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Reset session statistics                                          |
//+------------------------------------------------------------------+
void ResetSessionStats(SessionStats &stats)
{
   stats.totalTrades = 0;
   stats.winningTrades = 0;
   stats.losingTrades = 0;
   stats.grossProfit = 0;
   stats.grossLoss = 0;
   stats.largestWin = 0;
   stats.largestLoss = 0;
   stats.winRate = 0;
   stats.profitFactor = 0;
   stats.lastResetTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if we've hit daily loss limit                              |
//+------------------------------------------------------------------+
bool IsDailyLossLimitExceeded()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = g_initialBalance - currentBalance;
   double maxLossAmount = g_initialBalance * MaxDailyLossPercent / 100;

   return (dailyLoss >= maxLossAmount);
}

//+------------------------------------------------------------------+
//| Update trading statistics                                         |
//+------------------------------------------------------------------+
void UpdateStats(double profit)
{
   // Update global stats
   g_stats.totalTrades++;

   if(profit > 0)
   {
      g_stats.winningTrades++;
      g_stats.grossProfit += profit;
      g_stats.largestWin = MathMax(g_stats.largestWin, profit);
   }
   else
   {
      g_stats.losingTrades++;
      g_stats.grossLoss += MathAbs(profit);
      g_stats.largestLoss = MathMin(g_stats.largestLoss, profit);
   }

   // Update max balance and drawdown
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_maxBalance = MathMax(g_maxBalance, currentBalance);
   double currentDrawdown = (g_maxBalance - currentBalance) / g_maxBalance * 100;
   g_stats.maxDrawdown = MathMax(g_stats.maxDrawdown, currentDrawdown);

   // Update session-specific stats
   string currentSession = GetCurrentSession();
   if(currentSession == "Asian")
      UpdateSessionStats(g_asianStats, profit);
   else if(currentSession == "London")
      UpdateSessionStats(g_londonStats, profit);
   else if(currentSession == "NewYork")
      UpdateSessionStats(g_nyStats, profit);

   // Print all statistics
   PrintStats();
   PrintSessionStats();
}

//+------------------------------------------------------------------+
//| Print trading statistics                                          |
//+------------------------------------------------------------------+
void PrintStats()
{
   Print("=== Trading Statistics ===");
   Print("Total Trades: ", g_stats.totalTrades);
   Print("Win Rate: ", g_stats.totalTrades > 0 ?
         (double)g_stats.winningTrades/g_stats.totalTrades * 100 : 0, "%");
   Print("Gross Profit: ", g_stats.grossProfit);
   Print("Gross Loss: ", g_stats.grossLoss);
   Print("Net Profit: ", g_stats.grossProfit - g_stats.grossLoss);
   Print("Largest Win: ", g_stats.largestWin);
   Print("Largest Loss: ", g_stats.largestLoss);
   Print("Max Drawdown: ", g_stats.maxDrawdown, "%");
}

//+------------------------------------------------------------------+
//| Check market conditions                                           |
//+------------------------------------------------------------------+
bool AreMarketConditionsFavorable(ENUM_POSITION_TYPE type)
{
   // Check ADX for trend strength
   double adx[];
   ArraySetAsSeries(adx, true);
   int adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADXPeriod);
   CopyBuffer(adxHandle, 0, 0, 1, adx);
   if(adx[0] < ADXThreshold) return false;

   // Check for nearby high-impact news events
   if(UseNewsFilter && IsNewsEventNearby())
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check for nearby news events                                      |
//+------------------------------------------------------------------+
bool IsNewsEventNearby()
{
   if(!UseNewsFilter) return false;

   datetime currentTime = TimeCurrent();

   // Only check every minute
   if(currentTime - g_lastNewsCheck < 60)
      return g_newsEventNearby;

   g_lastNewsCheck = currentTime;

   // This is where you would integrate with your news calendar
   // For demonstration, we'll just avoid trading during major session opens
   MqlDateTime time;
   TimeToStruct(currentTime, time);

   // Avoid trading around London and New York opens
   int minuteOfDay = time.hour * 60 + time.min;
   int londonOpenMinute = LondonOpenHour * 60;
   int nyOpenMinute = NewYorkOpenHour * 60;

   g_newsEventNearby = (MathAbs(minuteOfDay - londonOpenMinute) < NewsMinutesBefore ||
                       MathAbs(minuteOfDay - nyOpenMinute) < NewsMinutesBefore);

   return g_newsEventNearby;
}

//+------------------------------------------------------------------+
//| Manage partial close and breakeven                                |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;

   double positionProfit = PositionGetDouble(POSITION_PROFIT);
   double positionVolume = PositionGetDouble(POSITION_VOLUME);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentStop = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   // Calculate profit percentage
   double profitPercent = positionProfit / g_initialBalance * 100;

   // Handle partial close
   if(UsePartialClose && profitPercent >= PartialCloseProfit &&
      positionVolume > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      double closeVolume = positionVolume * PartialClosePercent / 100;
      if(trade.PositionClosePartial(ticket, closeVolume))
      {
         Print(DEBUG_PREFIX, "Partial close executed - Volume: ", closeVolume);
      }
      else
      {
         Print(DEBUG_PREFIX, "Failed to execute partial close. Error: ", GetLastError(),
               " Description: ", GetErrorDescription(trade.ResultRetcode()));
      }
   }

   // Handle breakeven stop
   if(UseBreakEven && profitPercent >= BreakEvenProfit && currentStop != openPrice)
   {
      if(trade.PositionModify(ticket, openPrice, PositionGetDouble(POSITION_TP)))
      {
         Print(DEBUG_PREFIX, "Stop moved to breakeven at: ", openPrice);
      }
      else
      {
         Print(DEBUG_PREFIX, "Failed to move stop to breakeven. Error: ", GetLastError(),
               " Description: ", GetErrorDescription(trade.ResultRetcode()));
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Basic checks
   if(Bars(_Symbol, PERIOD_CURRENT) < 100)
   {
      Print(DEBUG_PREFIX, "Not enough historical data - waiting for more bars");
      return;
   }

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Only process once per bar
   if(lastBarTime == currentBarTime)
   {
      // Just update trailing stops and manage existing positions
      if(UseTrailingStop)
         UpdateTrailingStops();
      ManagePositions();
      return;
   }
   lastBarTime = currentBarTime;

   // Recalculate box every bar for more dynamic adaptation
   if(!CalculateBox())
   {
      Print(DEBUG_PREFIX, "Failed to calculate box - skipping this bar");
      return;
   }
   DrawZones();

   // Update session visualization if enabled
   if(ShowSessions)
   {
      UpdateSessionVisualization();
   }

   // Check daily loss limit
   if(IsDailyLossLimitExceeded())
   {
      Print(DEBUG_PREFIX, "Daily loss limit exceeded - No new trades allowed");
      return;
   }

   // Check if we're in an active trading session
   if(!IsActiveSession())
   {
      Print(DEBUG_PREFIX, "Not in active trading session");
      return;
   }

   // Get current price and check if it's valid
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentPrice <= 0) return;

   // Get pattern information
   PatternInfo currentPatternInfo = IdentifyPatternWithStrength(1);
   PRICE_ZONE currentZone = GetPriceZone(currentPrice);

   Print(DEBUG_PREFIX, "Bar Analysis:");
   Print(DEBUG_PREFIX, "Current Price: ", currentPrice);
   Print(DEBUG_PREFIX, "Zone: ", GetZoneName(currentZone));
   Print(DEBUG_PREFIX, "Pattern: ", GetPatternName(currentPatternInfo.pattern));
   Print(DEBUG_PREFIX, "Pattern Strength: ", currentPatternInfo.strength);

   // Check for existing positions
   if(PositionsTotal() > 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == 123456)
         {
            ManagePositions();
            return;
         }
      }
   }

   // Process potential trades
   ProcessTrades(currentPatternInfo, currentZone, currentPrice);
}

//+------------------------------------------------------------------+
//| Process potential trades                                          |
//+------------------------------------------------------------------+
void ProcessTrades(PatternInfo &patternInfo, PRICE_ZONE currentZone, double currentPrice)
{
   // Additional market condition checks
   bool isVolatilityFavorable = CheckVolatilityConditions();
   bool isTrendFavorable = CheckTrendConditions();

   if(!isVolatilityFavorable || !isTrendFavorable)
   {
      Print(DEBUG_PREFIX, "Market conditions not favorable for trading");
      return;
   }

   // Check for bullish setup
   if(!g_isLongPosition && patternInfo.pattern == PATTERN_BOX_REVERSAL_BULL &&
      (currentZone == ZONE_BOTTOM || currentZone == ZONE_VALID_TRADE))
   {
      if(ValidateBuySetup(patternInfo, currentZone))
      {
         OpenBuy(g_boxHigh);
      }
   }
   // Check for bearish setup
   else if(!g_isShortPosition && patternInfo.pattern == PATTERN_BOX_REVERSAL_BEAR &&
           (currentZone == ZONE_TOP || currentZone == ZONE_VALID_TRADE))
   {
      if(ValidateSellSetup(patternInfo, currentZone))
      {
         OpenSell(g_boxLow);
      }
   }
}

//+------------------------------------------------------------------+
//| Check volatility conditions                                       |
//+------------------------------------------------------------------+
bool CheckVolatilityConditions()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);

   if(atrHandle == INVALID_HANDLE)
      return false;

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0)
   {
      IndicatorRelease(atrHandle);
      return false;
   }
   IndicatorRelease(atrHandle);

   // Check if current ATR is within acceptable range
   if(_Symbol == "XAUUSD")
   {
      return atr[0] >= 0.5 && atr[0] <= 5.0; // Adjust these values based on XAUUSD volatility
   }
   else
   {
      return atr[0] >= 0.0002 && atr[0] <= 0.002; // Adjust for forex pairs
   }
}

//+------------------------------------------------------------------+
//| Check trend conditions                                            |
//+------------------------------------------------------------------+
bool CheckTrendConditions()
{
   double ma20[], ma50[];
   ArraySetAsSeries(ma20, true);
   ArraySetAsSeries(ma50, true);

   int ma20Handle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
   int ma50Handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);

   if(ma20Handle == INVALID_HANDLE || ma50Handle == INVALID_HANDLE)
      return false;

   if(CopyBuffer(ma20Handle, 0, 0, 2, ma20) <= 0 ||
      CopyBuffer(ma50Handle, 0, 0, 2, ma50) <= 0)
   {
      IndicatorRelease(ma20Handle);
      IndicatorRelease(ma50Handle);
      return false;
   }

   IndicatorRelease(ma20Handle);
   IndicatorRelease(ma50Handle);

   // Check if MAs are aligned for trend
   return MathAbs(ma20[0] - ma50[0]) > 0.0001; // Minimum distance between MAs
}

//+------------------------------------------------------------------+
//| Validate buy setup                                                |
//+------------------------------------------------------------------+
bool ValidateBuySetup(PatternInfo &patternInfo, PRICE_ZONE currentZone)
{
   if(patternInfo.strength < MinStrength)
   {
      Print(DEBUG_PREFIX, "Buy setup rejected - Insufficient pattern strength");
      return false;
   }

   bool volumeOk = !UseVolumeFilter || IsVolumeConfirmed(1);
   bool timeframeOk = !UseHigherTimeframe || IsHigherTimeframeConfirmed(POSITION_TYPE_BUY);
   bool marketOk = !UseMarketConditions || AreMarketConditionsFavorable(POSITION_TYPE_BUY);

   Print(DEBUG_PREFIX, "Buy Setup Validation:");
   Print(DEBUG_PREFIX, "Pattern Strength: ", patternInfo.strength);
   Print(DEBUG_PREFIX, "Volume Check: ", volumeOk);
   Print(DEBUG_PREFIX, "Higher Timeframe: ", timeframeOk);
   Print(DEBUG_PREFIX, "Market Conditions: ", marketOk);

   return volumeOk && timeframeOk && marketOk;
}

//+------------------------------------------------------------------+
//| Validate sell setup                                               |
//+------------------------------------------------------------------+
bool ValidateSellSetup(PatternInfo &patternInfo, PRICE_ZONE currentZone)
{
   if(patternInfo.strength < MinStrength)
   {
      Print(DEBUG_PREFIX, "Sell setup rejected - Insufficient pattern strength");
      return false;
   }

   bool volumeOk = !UseVolumeFilter || IsVolumeConfirmed(1);
   bool timeframeOk = !UseHigherTimeframe || IsHigherTimeframeConfirmed(POSITION_TYPE_SELL);
   bool marketOk = !UseMarketConditions || AreMarketConditionsFavorable(POSITION_TYPE_SELL);

   Print(DEBUG_PREFIX, "Sell Setup Validation:");
   Print(DEBUG_PREFIX, "Pattern Strength: ", patternInfo.strength);
   Print(DEBUG_PREFIX, "Volume Check: ", volumeOk);
   Print(DEBUG_PREFIX, "Higher Timeframe: ", timeframeOk);
   Print(DEBUG_PREFIX, "Market Conditions: ", marketOk);

   return volumeOk && timeframeOk && marketOk;
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(!PositionSelectByTicket(ticket)) continue;

      // Check if position belongs to our EA
      if(PositionGetInteger(POSITION_MAGIC) != 123456) continue;

      // Manage partial close and breakeven
      ManagePosition(ticket);

      // Update trailing stop if enabled
      if(UseTrailingStop)
         UpdateTrailingStops();

      // Regular position management
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      PRICE_ZONE currentZone = GetPriceZone(currentPrice);
      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Store profit before closing for statistics
      double positionProfit = PositionGetDouble(POSITION_PROFIT);

      // Only close positions if they're in the opposite extreme zone
      bool shouldClose = false;
      if(positionType == POSITION_TYPE_BUY && currentZone == ZONE_TOP)
      {
         Print(DEBUG_PREFIX, "Closing buy position - Price in Top Zone");
         shouldClose = true;
      }
      else if(positionType == POSITION_TYPE_SELL && currentZone == ZONE_BOTTOM)
      {
         Print(DEBUG_PREFIX, "Closing sell position - Price in Bottom Zone");
         shouldClose = true;
      }

      if(shouldClose)
      {
         if(trade.PositionClose(ticket))
         {
            if(positionType == POSITION_TYPE_BUY)
               g_isLongPosition = false;
            else
               g_isShortPosition = false;

            UpdateStats(positionProfit);
            Print(DEBUG_PREFIX, "Position closed successfully. Profit: ", positionProfit);
         }
         else
         {
            Print(DEBUG_PREFIX, "Failed to close position. Error: ", GetLastError(),
                  " Description: ", GetErrorDescription(trade.ResultRetcode()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss price based on account balance                |
//+------------------------------------------------------------------+
double CalculateStopLossPrice(ENUM_POSITION_TYPE type, double entryPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double stopLossAmount = accountBalance * StopLossPercent / 100;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // For XAUUSD, adjust the calculation
   if(_Symbol == "XAUUSD")
   {
      // XAUUSD typically has a point value of 0.01
      // Convert stopLossAmount to points
      double stopLossPoints = (stopLossAmount / tickValue) * point;

      // Ensure minimum stop distance
      double minStopPoints = 100 * point; // Minimum 100 points for XAUUSD
      stopLossPoints = MathMax(stopLossPoints, minStopPoints);

      // Calculate stop loss price
      if(type == POSITION_TYPE_BUY)
         return entryPrice - stopLossPoints;
      else
         return entryPrice + stopLossPoints;
   }
   else
   {
      // Original calculation for other symbols
      double stopLossPips = stopLossAmount / (tickValue * CalculateLotSize(g_boxHigh - g_boxLow));

      if(type == POSITION_TYPE_BUY)
         return entryPrice - (stopLossPips * point);
      else
         return entryPrice + (stopLossPips * point);
   }
}

//+------------------------------------------------------------------+
//| Validate if order meets minimum profit potential                   |
//+------------------------------------------------------------------+
bool ValidateOrderProfitPotential(ENUM_POSITION_TYPE type, double entry, double takeProfit, double stopLoss)
{
   double potentialLoss = MathAbs(entry - stopLoss);
   double potentialProfit = MathAbs(entry - takeProfit);

   // Check if potential profit is greater than stop loss
   return potentialProfit > potentialLoss;
}

//+------------------------------------------------------------------+
//| Open Buy Position                                                 |
//+------------------------------------------------------------------+
void OpenBuy(double takeProfit)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = CalculateStopLossPrice(POSITION_TYPE_BUY, entryPrice);

   // Get minimum stop level in points and convert to price
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minStopDistance = stopLevel * point;

   // If stop level is 0 or invalid, use a minimum of 10 points
   if(minStopDistance <= 0)
   {
      minStopDistance = 10 * point;
      Print(DEBUG_PREFIX, "Using default minimum stop distance of 10 points");
   }

   Print(DEBUG_PREFIX, "Stop Level Check - Minimum Distance: ", minStopDistance,
         " Points (", stopLevel, " points)");

   // Adjust stop loss if too close
   double minSL = entryPrice - minStopDistance;
   if(stopLoss > minSL)  // Remember for buy orders, SL is below entry
   {
      stopLoss = minSL;
      Print(DEBUG_PREFIX, "Stop Loss adjusted to meet minimum distance requirement: ", stopLoss);
   }

   // Adjust take profit if too close
   double minTP = entryPrice + minStopDistance;
   if(takeProfit < minTP)
   {
      takeProfit = minTP;
      Print(DEBUG_PREFIX, "Take Profit adjusted to meet minimum distance requirement: ", takeProfit);
   }

   Print(DEBUG_PREFIX, "Order Levels - Entry: ", entryPrice,
         " SL: ", stopLoss, " (", MathAbs(entryPrice - stopLoss)/point, " points)",
         " TP: ", takeProfit, " (", MathAbs(takeProfit - entryPrice)/point, " points)");

   // Additional validation for stop levels
   if(MathAbs(entryPrice - stopLoss) <= minStopDistance)
   {
      Print(DEBUG_PREFIX, "Stop loss too close to entry price - Adjusting distance");
      stopLoss = entryPrice - (minStopDistance * 1.1); // Add 10% margin
   }

   if(MathAbs(takeProfit - entryPrice) <= minStopDistance)
   {
      Print(DEBUG_PREFIX, "Take profit too close to entry price - Adjusting distance");
      takeProfit = entryPrice + (minStopDistance * 1.1); // Add 10% margin
   }

   // Validate if order meets profit potential requirements
   if(!ValidateOrderProfitPotential(POSITION_TYPE_BUY, entryPrice, takeProfit, stopLoss))
   {
      Print(DEBUG_PREFIX, "Buy order rejected - Insufficient profit potential");
      return;
   }

   double lotSize = CalculateLotSize(g_boxHigh - g_boxLow);

   // Get supported filling modes
   int filling_mode = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   Print(DEBUG_PREFIX, "Symbol filling modes: ", filling_mode);

   // Set appropriate filling mode
   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      trade.SetTypeFilling(ORDER_FILLING_FOK);
      Print(DEBUG_PREFIX, "Using FOK filling mode");
   }
   else if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      trade.SetTypeFilling(ORDER_FILLING_IOC);
      Print(DEBUG_PREFIX, "Using IOC filling mode");
   }
   else
   {
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
      Print(DEBUG_PREFIX, "Using RETURN filling mode");
   }

   // Set deviation and magic number
   trade.SetDeviationInPoints(10);
   trade.SetExpertMagicNumber(123456);

   // Final validation of stop levels before execution
   if(MathAbs(entryPrice - stopLoss) > minStopDistance &&
      MathAbs(takeProfit - entryPrice) > minStopDistance)
   {
      // Execute the trade
      bool success = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit);

      if(success)
      {
         g_isLongPosition = true;
         g_isShortPosition = false;
         Print(DEBUG_PREFIX, "Buy order opened - Entry: ", entryPrice, " TP: ", takeProfit, " SL: ", stopLoss);

         if(UseTrailingStop)
         {
            double trailingDistance = MathAbs(entryPrice - stopLoss);
            double trailingStep = trailingDistance * TrailingPercent / 100;
            GlobalVariableSet("TrailingStop_" + IntegerToString(trade.ResultOrder()), stopLoss);
            GlobalVariableSet("TrailingStep_" + IntegerToString(trade.ResultOrder()), trailingStep);
            Print(DEBUG_PREFIX, "Trailing stop initialized - Distance: ", trailingDistance, " Step: ", trailingStep);
         }
      }
      else
      {
         Print(DEBUG_PREFIX, "Failed to open buy order. Error: ", GetLastError(),
               " Description: ", GetErrorDescription(trade.ResultRetcode()),
               " Retcode: ", trade.ResultRetcode(),
               " Volume: ", lotSize,
               " Bid: ", SymbolInfoDouble(_Symbol, SYMBOL_BID),
               " Ask: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      }
   }
   else
   {
      Print(DEBUG_PREFIX, "Order rejected - Stop levels too close to entry price");
      Print(DEBUG_PREFIX, "SL Distance: ", MathAbs(entryPrice - stopLoss)/point, " points");
      Print(DEBUG_PREFIX, "TP Distance: ", MathAbs(takeProfit - entryPrice)/point, " points");
      Print(DEBUG_PREFIX, "Minimum Required: ", minStopDistance/point, " points");
   }
}

//+------------------------------------------------------------------+
//| Open Sell Position                                                |
//+------------------------------------------------------------------+
void OpenSell(double takeProfit)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = CalculateStopLossPrice(POSITION_TYPE_SELL, entryPrice);

   // Get minimum stop level in points and convert to price
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minStopDistance = stopLevel * point;

   // If stop level is 0 or invalid, use a minimum of 10 points
   if(minStopDistance <= 0)
   {
      minStopDistance = 10 * point;
      Print(DEBUG_PREFIX, "Using default minimum stop distance of 10 points");
   }

   Print(DEBUG_PREFIX, "Stop Level Check - Minimum Distance: ", minStopDistance,
         " Points (", stopLevel, " points)");

   // Adjust stop loss if too close
   double minSL = entryPrice + minStopDistance;
   if(stopLoss < minSL)  // Remember for sell orders, SL is above entry
   {
      stopLoss = minSL;
      Print(DEBUG_PREFIX, "Stop Loss adjusted to meet minimum distance requirement: ", stopLoss);
   }

   // Adjust take profit if too close
   double minTP = entryPrice - minStopDistance;
   if(takeProfit > minTP)
   {
      takeProfit = minTP;
      Print(DEBUG_PREFIX, "Take Profit adjusted to meet minimum distance requirement: ", takeProfit);
   }

   Print(DEBUG_PREFIX, "Order Levels - Entry: ", entryPrice,
         " SL: ", stopLoss, " (", MathAbs(entryPrice - stopLoss)/point, " points)",
         " TP: ", takeProfit, " (", MathAbs(takeProfit - entryPrice)/point, " points)");

   // Additional validation for stop levels
   if(MathAbs(entryPrice - stopLoss) <= minStopDistance)
   {
      Print(DEBUG_PREFIX, "Stop loss too close to entry price - Adjusting distance");
      stopLoss = entryPrice + (minStopDistance * 1.1); // Add 10% margin
   }

   if(MathAbs(takeProfit - entryPrice) <= minStopDistance)
   {
      Print(DEBUG_PREFIX, "Take profit too close to entry price - Adjusting distance");
      takeProfit = entryPrice - (minStopDistance * 1.1); // Add 10% margin
   }

   // Validate if order meets profit potential requirements
   if(!ValidateOrderProfitPotential(POSITION_TYPE_SELL, entryPrice, takeProfit, stopLoss))
   {
      Print(DEBUG_PREFIX, "Sell order rejected - Insufficient profit potential");
      return;
   }

   double lotSize = CalculateLotSize(g_boxHigh - g_boxLow);

   // Get supported filling modes
   int filling_mode = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   Print(DEBUG_PREFIX, "Symbol filling modes: ", filling_mode);

   // Set appropriate filling mode
   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      trade.SetTypeFilling(ORDER_FILLING_FOK);
      Print(DEBUG_PREFIX, "Using FOK filling mode");
   }
   else if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      trade.SetTypeFilling(ORDER_FILLING_IOC);
      Print(DEBUG_PREFIX, "Using IOC filling mode");
   }
   else
   {
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
      Print(DEBUG_PREFIX, "Using RETURN filling mode");
   }

   // Set deviation and magic number
   trade.SetDeviationInPoints(10);
   trade.SetExpertMagicNumber(123456);

   // Final validation of stop levels before execution
   if(MathAbs(entryPrice - stopLoss) > minStopDistance &&
      MathAbs(takeProfit - entryPrice) > minStopDistance)
   {
      // Execute the trade
      bool success = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit);

      if(success)
      {
         g_isShortPosition = true;
         g_isLongPosition = false;
         Print(DEBUG_PREFIX, "Sell order opened - Entry: ", entryPrice, " TP: ", takeProfit, " SL: ", stopLoss);

         if(UseTrailingStop)
         {
            double trailingDistance = MathAbs(entryPrice - stopLoss);
            double trailingStep = trailingDistance * TrailingPercent / 100;
            GlobalVariableSet("TrailingStop_" + IntegerToString(trade.ResultOrder()), stopLoss);
            GlobalVariableSet("TrailingStep_" + IntegerToString(trade.ResultOrder()), trailingStep);
            Print(DEBUG_PREFIX, "Trailing stop initialized - Distance: ", trailingDistance, " Step: ", trailingStep);
         }
      }
      else
      {
         Print(DEBUG_PREFIX, "Failed to open sell order. Error: ", GetLastError(),
               " Description: ", GetErrorDescription(trade.ResultRetcode()),
               " Retcode: ", trade.ResultRetcode(),
               " Volume: ", lotSize,
               " Bid: ", SymbolInfoDouble(_Symbol, SYMBOL_BID),
               " Ask: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      }
   }
   else
   {
      Print(DEBUG_PREFIX, "Order rejected - Stop levels too close to entry price");
      Print(DEBUG_PREFIX, "SL Distance: ", MathAbs(entryPrice - stopLoss)/point, " points");
      Print(DEBUG_PREFIX, "TP Distance: ", MathAbs(takeProfit - entryPrice)/point, " points");
      Print(DEBUG_PREFIX, "Minimum Required: ", minStopDistance/point, " points");
   }
}

//+------------------------------------------------------------------+
//| Identify candlestick pattern                                      |
//+------------------------------------------------------------------+
CANDLE_PATTERN IdentifyPattern(int shift)
{
   double open1 = iOpen(_Symbol, PatternTimeframe, shift);
   double close1 = iClose(_Symbol, PatternTimeframe, shift);
   double high1 = iHigh(_Symbol, PatternTimeframe, shift);
   double low1 = iLow(_Symbol, PatternTimeframe, shift);

   double open2 = iOpen(_Symbol, PatternTimeframe, shift + 1);
   double close2 = iClose(_Symbol, PatternTimeframe, shift + 1);
   double high2 = iHigh(_Symbol, PatternTimeframe, shift + 1);
   double low2 = iLow(_Symbol, PatternTimeframe, shift + 1);

   double open3 = iOpen(_Symbol, PatternTimeframe, shift + 2);
   double close3 = iClose(_Symbol, PatternTimeframe, shift + 2);

   // Calculate candle properties
   double body1 = MathAbs(close1 - open1);
   double upperWick1 = high1 - MathMax(open1, close1);
   double lowerWick1 = MathMin(open1, close1) - low1;
   double totalSize1 = high1 - low1;

   // Print pattern detection debug info
   Print(DEBUG_PREFIX, "Pattern Detection on ", EnumToString(PatternTimeframe), ":");
   Print(DEBUG_PREFIX, "Current Candle - Open: ", open1, " High: ", high1, " Low: ", low1, " Close: ", close1);
   Print(DEBUG_PREFIX, "Body Size: ", body1, " Upper Wick: ", upperWick1, " Lower Wick: ", lowerWick1);

   // Check for Box Reversal patterns first
   if(IsBullishBoxReversal(open1, high1, low1, close1, g_boxLow))
   {
      Print(DEBUG_PREFIX, "Bullish Box Reversal pattern detected");
      return PATTERN_BOX_REVERSAL_BULL;
   }

   if(IsBearishBoxReversal(open1, high1, low1, close1, g_boxHigh))
   {
      Print(DEBUG_PREFIX, "Bearish Box Reversal pattern detected");
      return PATTERN_BOX_REVERSAL_BEAR;
   }

   // Check for Doji
   if(IsDoji(open1, high1, low1, close1))
   {
      Print(DEBUG_PREFIX, "Doji pattern detected");
      return PATTERN_DOJI;
   }

   // Check for Hammer
   if(IsHammer(open1, high1, low1, close1))
   {
      Print(DEBUG_PREFIX, "Hammer pattern detected");
      return PATTERN_HAMMER;
   }

   // Check for Shooting Star
   if(IsShootingStar(open1, high1, low1, close1))
   {
      Print(DEBUG_PREFIX, "Shooting Star pattern detected");
      return PATTERN_SHOOTING_STAR;
   }

   // Check for Engulfing patterns
   if(IsBullishEngulfing(open1, close1, open2, close2))
   {
      Print(DEBUG_PREFIX, "Bullish Engulfing pattern detected");
      return PATTERN_BULLISH_ENGULFING;
   }

   if(IsBearishEngulfing(open1, close1, open2, close2))
   {
      Print(DEBUG_PREFIX, "Bearish Engulfing pattern detected");
      return PATTERN_BEARISH_ENGULFING;
   }

   // Check for Morning/Evening Star
   if(IsMorningStar(open1, close1, open2, close2, open3, close3))
   {
      Print(DEBUG_PREFIX, "Morning Star pattern detected");
      return PATTERN_MORNING_STAR;
   }

   if(IsEveningStar(open1, close1, open2, close2, open3, close3))
   {
      Print(DEBUG_PREFIX, "Evening Star pattern detected");
      return PATTERN_EVENING_STAR;
   }

   Print(DEBUG_PREFIX, "No pattern detected");
   return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| Check for Doji pattern                                            |
//+------------------------------------------------------------------+
bool IsDoji(double open, double high, double low, double close)
{
   double totalSize = high - low;
   double body = MathAbs(close - open);

   return (body <= totalSize * DojiBodyPercent / 100);
}

//+------------------------------------------------------------------+
//| Check for Hammer pattern                                          |
//+------------------------------------------------------------------+
bool IsHammer(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalSize = high - low;

   return (lowerWick > 2 * body) && (upperWick < body) && (body > 0);
}

//+------------------------------------------------------------------+
//| Check for Shooting Star pattern                                   |
//+------------------------------------------------------------------+
bool IsShootingStar(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalSize = high - low;

   return (upperWick > 2 * body) && (lowerWick < body) && (body > 0);
}

//+------------------------------------------------------------------+
//| Check for Bullish Engulfing pattern                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(double open1, double close1, double open2, double close2)
{
   return (close2 < open2) &&           // Previous candle is bearish
          (close1 > open1) &&           // Current candle is bullish
          (open1 < close2) &&           // Opens below previous close
          (close1 > open2);             // Closes above previous open
}

//+------------------------------------------------------------------+
//| Check for Bearish Engulfing pattern                              |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(double open1, double close1, double open2, double close2)
{
   return (close2 > open2) &&           // Previous candle is bullish
          (close1 < open1) &&           // Current candle is bearish
          (open1 > close2) &&           // Opens above previous close
          (close1 < open2);             // Closes below previous open
}

//+------------------------------------------------------------------+
//| Check for Morning Star pattern                                    |
//+------------------------------------------------------------------+
bool IsMorningStar(double open1, double close1, double open2, double close2, double open3, double close3)
{
   return (close3 < open3) &&           // First candle is bearish
          (MathAbs(open2 - close2) < MathAbs(open3 - close3) * 0.3) &&  // Second candle is small
          (close1 > open1) &&           // Third candle is bullish
          (close1 > (open3 + close3) / 2);  // Closes above midpoint of first candle
}

//+------------------------------------------------------------------+
//| Check for Evening Star pattern                                    |
//+------------------------------------------------------------------+
bool IsEveningStar(double open1, double close1, double open2, double close2, double open3, double close3)
{
   return (close3 > open3) &&           // First candle is bullish
          (MathAbs(open2 - close2) < MathAbs(open3 - close3) * 0.3) &&  // Second candle is small
          (close1 < open1) &&           // Third candle is bearish
          (close1 < (open3 + close3) / 2);  // Closes below midpoint of first candle
}

//+------------------------------------------------------------------+
//| Check for Box Reversal pattern                                    |
//+------------------------------------------------------------------+
bool IsBullishBoxReversal(double open, double high, double low, double close, double boxLow)
{
   double totalSize = high - low;
   double body = close - open;
   double lowerWick = open - low;

   // Calculate distances from box boundary
   double distanceToBox = MathAbs(low - boxLow);
   double boxHeight = g_boxHigh - g_boxLow;
   double boxProximityThreshold = boxHeight * 0.05; // Increased from 0.03 to 0.05 for XAUUSD

   // Enhanced conditions for bullish box reversal:
   bool nearBox = distanceToBox <= boxProximityThreshold;  // Closer to box boundary
   bool strongClose = (close - open) > 0 && (close - open) > (totalSize * 0.5);  // Decreased from 0.6 to 0.5
   bool closeNearHigh = (high - close) <= (totalSize * 0.1);  // Increased from 0.05 to 0.1
   bool decentSize = body >= (totalSize * 0.6);  // Decreased from 0.7 to 0.6
   bool smallLowerWick = lowerWick <= (totalSize * 0.3);  // Increased from 0.2 to 0.3

   // Check previous candles for confirmation
   bool previousBearish = false;
   bool volumeIncreasing = false;

   if(nearBox || strongClose)  // Changed from AND to OR for more opportunities
   {
      // Check previous 3 candles
      for(int i = 1; i <= 3; i++)
      {
         double prevClose = iClose(_Symbol, PatternTimeframe, i);
         double prevOpen = iOpen(_Symbol, PatternTimeframe, i);
         double prevVolume = iVolume(_Symbol, PatternTimeframe, i);
         double currVolume = iVolume(_Symbol, PatternTimeframe, i-1);

         if(i == 1)
         {
            previousBearish = prevClose < prevOpen;
            volumeIncreasing = currVolume > prevVolume;
         }
      }
   }

   Print(DEBUG_PREFIX, "Box Reversal Analysis (Bullish) - Box Height: ", boxHeight);
   Print(DEBUG_PREFIX, "Distance to Box: ", distanceToBox,
         ", Threshold: ", boxProximityThreshold,
         " (", (distanceToBox/boxHeight)*100, "% of box height)");
   Print(DEBUG_PREFIX, "Conditions - Near Box: ", nearBox,
         ", Strong Close: ", strongClose,
         ", Close Near High: ", closeNearHigh,
         ", Decent Size: ", decentSize,
         ", Small Lower Wick: ", smallLowerWick,
         ", Previous Bearish: ", previousBearish,
         ", Volume Increasing: ", volumeIncreasing);

   // Return true if most conditions are met (relaxed requirements)
   return (nearBox || strongClose) && closeNearHigh && (decentSize || smallLowerWick) && (previousBearish || volumeIncreasing);
}

bool IsBearishBoxReversal(double open, double high, double low, double close, double boxHigh)
{
   double totalSize = high - low;
   double body = open - close;
   double upperWick = high - open;

   // Calculate distances from box boundary
   double distanceToBox = MathAbs(high - boxHigh);
   double boxHeight = g_boxHigh - g_boxLow;
   double boxProximityThreshold = boxHeight * 0.05; // Increased from 0.03 to 0.05 for XAUUSD

   // Enhanced conditions for bearish box reversal:
   bool nearBox = distanceToBox <= boxProximityThreshold;  // Closer to box boundary
   bool strongClose = (open - close) > 0 && (open - close) > (totalSize * 0.5);  // Decreased from 0.6 to 0.5
   bool closeNearLow = (close - low) <= (totalSize * 0.1);  // Increased from 0.05 to 0.1
   bool decentSize = body >= (totalSize * 0.6);  // Decreased from 0.7 to 0.6
   bool smallUpperWick = upperWick <= (totalSize * 0.3);  // Increased from 0.2 to 0.3

   // Check previous candles for confirmation
   bool previousBullish = false;
   bool volumeIncreasing = false;

   if(nearBox || strongClose)  // Changed from AND to OR for more opportunities
   {
      // Check previous 3 candles
      for(int i = 1; i <= 3; i++)
      {
         double prevClose = iClose(_Symbol, PatternTimeframe, i);
         double prevOpen = iOpen(_Symbol, PatternTimeframe, i);
         double prevVolume = iVolume(_Symbol, PatternTimeframe, i);
         double currVolume = iVolume(_Symbol, PatternTimeframe, i-1);

         if(i == 1)
         {
            previousBullish = prevClose > prevOpen;
            volumeIncreasing = currVolume > prevVolume;
         }
      }
   }

   Print(DEBUG_PREFIX, "Box Reversal Analysis (Bearish) - Box Height: ", boxHeight);
   Print(DEBUG_PREFIX, "Distance to Box: ", distanceToBox,
         ", Threshold: ", boxProximityThreshold,
         " (", (distanceToBox/boxHeight)*100, "% of box height)");
   Print(DEBUG_PREFIX, "Conditions - Near Box: ", nearBox,
         ", Strong Close: ", strongClose,
         ", Close Near Low: ", closeNearLow,
         ", Decent Size: ", decentSize,
         ", Small Upper Wick: ", smallUpperWick,
         ", Previous Bullish: ", previousBullish,
         ", Volume Increasing: ", volumeIncreasing);

   // Return true if most conditions are met (relaxed requirements)
   return (nearBox || strongClose) && closeNearLow && (decentSize || smallUpperWick) && (previousBullish || volumeIncreasing);
}

//+------------------------------------------------------------------+
//| Calculate pattern strength (0-100)                                |
//+------------------------------------------------------------------+
double CalculatePatternStrength(CANDLE_PATTERN pattern, int shift)
{
   // If no pattern is detected, return 0 strength
   if(pattern == PATTERN_NONE)
      return 0.0;

   double strength = 0.0;
   double weightSum = 0.0;

   // Get candle data
   double open1 = iOpen(_Symbol, PatternTimeframe, shift);
   double close1 = iClose(_Symbol, PatternTimeframe, shift);
   double high1 = iHigh(_Symbol, PatternTimeframe, shift);
   double low1 = iLow(_Symbol, PatternTimeframe, shift);
   double volume1 = (double)iVolume(_Symbol, PatternTimeframe, shift);

   // Calculate average candle size and volume
   double avgSize = 0.0;
   double avgVolume = 0.0;
   for(int i = shift + 1; i <= shift + StrengthPeriod; i++)
   {
      avgSize += (iHigh(_Symbol, PatternTimeframe, i) - iLow(_Symbol, PatternTimeframe, i));
      if(UseVolume) avgVolume += (double)iVolume(_Symbol, PatternTimeframe, i);
   }
   avgSize /= (double)StrengthPeriod;
   if(UseVolume) avgVolume /= (double)StrengthPeriod;

   // 1. Size Factor (0-30 points) - Enhanced
   double sizeFactor = 30 * (high1 - low1) / avgSize;
   sizeFactor = MathMin(sizeFactor * 1.2, 30); // Boost size factor but maintain cap
   strength += sizeFactor;
   weightSum += 30;

   // 2. Volume Factor (0-20 points) - Enhanced
   if(UseVolume)
   {
      double volumeFactor = 20 * volume1 / avgVolume;
      // Add bonus for increasing volume trend
      if(shift >= 2)
      {
         double vol2 = iVolume(_Symbol, PatternTimeframe, shift + 1);
         double vol3 = iVolume(_Symbol, PatternTimeframe, shift + 2);
         if(volume1 > vol2 && vol2 > vol3)
            volumeFactor *= 1.2; // 20% bonus for increasing volume
      }
      volumeFactor = MathMin(volumeFactor, 20);
      strength += volumeFactor;
      weightSum += 20;
   }

   // 3. Trend Context (0-20 points) - Enhanced
   double trendPoints = CalculateTrendContext(shift);
   // Add momentum analysis
   double momentum = 0;
   if(shift >= 5)
   {
      double price5ago = iClose(_Symbol, PatternTimeframe, shift + 5);
      double currentPrice = iClose(_Symbol, PatternTimeframe, shift);
      momentum = ((currentPrice - price5ago) / price5ago) * 100;
      if(MathAbs(momentum) > 0.5) // If strong momentum
         trendPoints *= 1.2; // 20% bonus
   }
   strength += trendPoints;
   weightSum += 20;

   // 4. Pattern-Specific Strength (0-30 points)
   double patternPoints = 0;
   switch(pattern)
   {
      case PATTERN_BOX_REVERSAL_BULL:
      case PATTERN_BOX_REVERSAL_BEAR:
         patternPoints = CalculateBoxReversalStrength(shift, pattern);
         break;
      default:
         patternPoints = 15; // Base points for other patterns
   }
   strength += patternPoints;
   weightSum += 30;

   // Normalize strength to 0-100 scale
   return (strength / weightSum) * 100;
}

// New function to calculate box reversal pattern strength
double CalculateBoxReversalStrength(int shift, CANDLE_PATTERN pattern)
{
   double points = 0;
   double open1 = iOpen(_Symbol, PatternTimeframe, shift);
   double close1 = iClose(_Symbol, PatternTimeframe, shift);
   double high1 = iHigh(_Symbol, PatternTimeframe, shift);
   double low1 = iLow(_Symbol, PatternTimeframe, shift);

   // Calculate body and wick ratios
   double totalSize = high1 - low1;
   double body = MathAbs(close1 - open1);
   double bodyRatio = body / totalSize;

   // Points for body size (0-10)
   points += bodyRatio * 10;

   // Points for close position (0-10)
   if(pattern == PATTERN_BOX_REVERSAL_BULL)
   {
      double upperPortion = (close1 - low1) / totalSize;
      points += upperPortion * 10;
   }
   else
   {
      double lowerPortion = (high1 - close1) / totalSize;
      points += lowerPortion * 10;
   }

   // Points for previous trend confirmation (0-10)
   if(shift >= 3)
   {
      bool trendConfirmed = false;
      if(pattern == PATTERN_BOX_REVERSAL_BULL)
      {
         double prev1 = iClose(_Symbol, PatternTimeframe, shift + 1);
         double prev2 = iClose(_Symbol, PatternTimeframe, shift + 2);
         double prev3 = iClose(_Symbol, PatternTimeframe, shift + 3);
         trendConfirmed = (prev1 < prev2 && prev2 < prev3); // Downtrend before bullish reversal
      }
      else
      {
         double prev1 = iClose(_Symbol, PatternTimeframe, shift + 1);
         double prev2 = iClose(_Symbol, PatternTimeframe, shift + 2);
         double prev3 = iClose(_Symbol, PatternTimeframe, shift + 3);
         trendConfirmed = (prev1 > prev2 && prev2 > prev3); // Uptrend before bearish reversal
      }
      if(trendConfirmed) points += 10;
   }

   return points;
}

//+------------------------------------------------------------------+
//| Calculate trend context points                                     |
//+------------------------------------------------------------------+
double CalculateTrendContext(int shift)
{
   double points = 0;

   // Calculate short-term trend (last 5 bars)
   double shortTrend = iClose(_Symbol, PERIOD_CURRENT, shift) -
                      iClose(_Symbol, PERIOD_CURRENT, shift + 5);

   // Calculate medium-term trend (last 10 bars)
   double mediumTrend = iClose(_Symbol, PERIOD_CURRENT, shift) -
                       iClose(_Symbol, PERIOD_CURRENT, shift + 10);

   // For bullish patterns
   if(iClose(_Symbol, PERIOD_CURRENT, shift) > iOpen(_Symbol, PERIOD_CURRENT, shift))
   {
      if(shortTrend < 0) points += 10;  // Potential reversal
      if(mediumTrend < 0) points += 10; // Stronger reversal context
   }
   // For bearish patterns
   else
   {
      if(shortTrend > 0) points += 10;  // Potential reversal
      if(mediumTrend > 0) points += 10; // Stronger reversal context
   }

   return points;
}

//+------------------------------------------------------------------+
//| Calculate Hammer/Shooting Star strength                           |
//+------------------------------------------------------------------+
double CalculateHammerStrength(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double totalSize = high - low;

   // Calculate points based on wick-to-body ratio
   double wickRatio = MathMax(upperWick, lowerWick) / body;
   double points = MathMin(wickRatio * 10, 20);

   // Add points for size relative to recent bars
   points += MathMin(totalSize / body, 10);

   return points;
}

//+------------------------------------------------------------------+
//| Calculate Engulfing pattern strength                              |
//+------------------------------------------------------------------+
double CalculateEngulfingStrength(int shift)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);

   // Calculate how much larger the engulfing candle is
   double engulfingSize = MathAbs(close1 - open1);
   double engulfedSize = MathAbs(close2 - open2);
   double ratio = engulfingSize / engulfedSize;

   return MathMin(ratio * 15, 30);
}

//+------------------------------------------------------------------+
//| Calculate Star pattern strength                                    |
//+------------------------------------------------------------------+
double CalculateStarStrength(int shift)
{
   double points = 0;

   // Middle star size relative to surrounding candles
   double starSize = MathAbs(iClose(_Symbol, PERIOD_CURRENT, shift + 1) -
                            iOpen(_Symbol, PERIOD_CURRENT, shift + 1));
   double firstSize = MathAbs(iClose(_Symbol, PERIOD_CURRENT, shift + 2) -
                             iOpen(_Symbol, PERIOD_CURRENT, shift + 2));
   double thirdSize = MathAbs(iClose(_Symbol, PERIOD_CURRENT, shift) -
                             iOpen(_Symbol, PERIOD_CURRENT, shift));

   // Smaller middle star is better
   points += (1.0 - (starSize / ((firstSize + thirdSize) / 2))) * 15;

   // Gap points
   if(MathAbs(iClose(_Symbol, PERIOD_CURRENT, shift + 1) -
              iClose(_Symbol, PERIOD_CURRENT, shift + 2)) > starSize)
      points += 7.5;

   if(MathAbs(iOpen(_Symbol, PERIOD_CURRENT, shift) -
              iClose(_Symbol, PERIOD_CURRENT, shift + 1)) > starSize)
      points += 7.5;

   return points;
}

//+------------------------------------------------------------------+
//| Calculate Doji strength                                           |
//+------------------------------------------------------------------+
double CalculateDojiStrength(double open, double high, double low, double close)
{
   double body = MathAbs(close - open);
   double totalSize = high - low;

   // Perfect doji has zero body
   double bodyRatio = 1.0 - (body / totalSize);
   double points = bodyRatio * 20;

   // Add points for size of wicks
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   // Equal wicks are better for doji
   double wickRatio = MathMin(upperWick, lowerWick) / MathMax(upperWick, lowerWick);
   points += wickRatio * 10;

   return points;
}

//+------------------------------------------------------------------+
//| Identify pattern with strength                                    |
//+------------------------------------------------------------------+
PatternInfo IdentifyPatternWithStrength(int shift)
{
   PatternInfo result;
   result.pattern = IdentifyPattern(shift);
   result.strength = (result.pattern != PATTERN_NONE) ? CalculatePatternStrength(result.pattern, shift) : 0.0;
   return result;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100);

   // Get symbol contract specifications
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   // Calculate required margin per lot
   double margin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   if(margin <= 0)
   {
      // If margin is not directly available, calculate it from leverage
      double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(leverage <= 0) leverage = 100; // Default to 1:100 if no leverage info
      double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double priceAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      margin = (contractSize * priceAsk) / leverage;
   }

   Print(DEBUG_PREFIX, "Lot Size Calculation:");
   Print(DEBUG_PREFIX, "Account Balance: ", accountBalance);
   Print(DEBUG_PREFIX, "Risk Amount: ", riskAmount);
   Print(DEBUG_PREFIX, "Margin per Lot: ", margin);

   // Calculate maximum lots based on margin
   double maxLotsByMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) / margin;

   // Calculate lots based on risk
   double pipValue = tickValue * (stopLoss / tickSize);
   double lotSize = 0;

   if(pipValue > 0)
   {
      lotSize = riskAmount / pipValue;
      lotSize = NormalizeDouble(lotSize, 2);
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
   }

   // Ensure lot size doesn't exceed margin-based maximum
   lotSize = MathMin(lotSize, maxLotsByMargin);

   // Apply min/max limits
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   Print(DEBUG_PREFIX, "Calculated Lot Size: ", lotSize);
   Print(DEBUG_PREFIX, "Maximum Lots by Margin: ", maxLotsByMargin);
   Print(DEBUG_PREFIX, "Final Lot Size: ", lotSize);

   return lotSize;
}

//+------------------------------------------------------------------+
//| Check if current time is within active trading session            |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   if(!UseSessionFilter) return true;

   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);

   // Check if we're in any major session
   bool inLondon = (time.hour >= LondonOpenHour && time.hour < LondonCloseHour);
   bool inNewYork = (time.hour >= NewYorkOpenHour && time.hour < NewYorkCloseHour);
   bool inAsian = (time.hour >= AsianOpenHour && time.hour < AsianCloseHour);

   // Print current session status
   Print(DEBUG_PREFIX, "Session Check - Asian: ", inAsian ? "Active" : "Inactive",
         ", London: ", inLondon ? "Active" : "Inactive",
         ", New York: ", inNewYork ? "Active" : "Inactive",
         " (Hour: ", time.hour, ")");

   return inLondon || inNewYork || inAsian;  // Return true if in any major session
}

//+------------------------------------------------------------------+
//| Check if volume confirms the signal                               |
//+------------------------------------------------------------------+
bool IsVolumeConfirmed(int shift)
{
   if(!UseVolumeFilter) return true;

   // Get current candle's volume
   double currentVolume = (double)iVolume(_Symbol, PatternTimeframe, shift);

   // Calculate average volume
   double avgVolume = 0;
   for(int i = shift + 1; i <= shift + VolumePeriod; i++)
   {
      avgVolume += (double)iVolume(_Symbol, PatternTimeframe, i);
   }
   avgVolume /= VolumePeriod;

   // Calculate recent volume trend (last 3 candles)
   double vol1 = (double)iVolume(_Symbol, PatternTimeframe, shift + 1);
   double vol2 = (double)iVolume(_Symbol, PatternTimeframe, shift + 2);
   double vol3 = (double)iVolume(_Symbol, PatternTimeframe, shift + 3);
   bool increasingVolume = currentVolume > vol1 && vol1 > vol2;

   // Volume is confirmed if either:
   // 1. Current volume is significantly higher than average (MinVolumeFactor)
   // 2. Volume is showing an increasing trend
   bool volumeAboveAverage = (currentVolume > avgVolume * MinVolumeFactor);
   bool confirmed = volumeAboveAverage || increasingVolume;

   Print(DEBUG_PREFIX, "Volume Analysis:");
   Print(DEBUG_PREFIX, "Current Volume: ", currentVolume);
   Print(DEBUG_PREFIX, "Average Volume (", VolumePeriod, " periods): ", avgVolume);
   Print(DEBUG_PREFIX, "Required Factor: ", MinVolumeFactor, "x average");
   Print(DEBUG_PREFIX, "Recent Volumes - Current:", currentVolume,
         " Previous:", vol1,
         " 2 Back:", vol2,
         " 3 Back:", vol3);
   Print(DEBUG_PREFIX, "Volume Above Average: ", volumeAboveAverage,
         " (", currentVolume/avgVolume, "x average)");
   Print(DEBUG_PREFIX, "Increasing Volume Trend: ", increasingVolume);
   Print(DEBUG_PREFIX, "Volume Confirmed: ", confirmed);

   return confirmed;
}

//+------------------------------------------------------------------+
//| Check if higher timeframe confirms the direction                  |
//+------------------------------------------------------------------+
bool IsHigherTimeframeConfirmed(ENUM_POSITION_TYPE type)
{
   if(!UseHigherTimeframe) return true;

   // Get higher timeframe data
   double htf_close = iClose(_Symbol, HigherTimeframe, 1);
   double htf_open = iOpen(_Symbol, HigherTimeframe, 1);
   double htf_high = iHigh(_Symbol, HigherTimeframe, 1);
   double htf_low = iLow(_Symbol, HigherTimeframe, 1);

   // Calculate candle properties
   double htf_body = MathAbs(htf_close - htf_open);
   double htf_total_size = htf_high - htf_low;
   bool htf_is_bullish = htf_close > htf_open;

   // Get previous candles for trend
   double prev_close1 = iClose(_Symbol, HigherTimeframe, 2);
   double prev_close2 = iClose(_Symbol, HigherTimeframe, 3);
   double prev_close3 = iClose(_Symbol, HigherTimeframe, 4);

   // Calculate simple trend
   bool uptrend = htf_close > prev_close1 && prev_close1 > prev_close2;
   bool downtrend = htf_close < prev_close1 && prev_close1 < prev_close2;

   // Calculate momentum
   bool strong_momentum = htf_body > (htf_total_size * 0.5); // Body is more than 50% of total size

   Print(DEBUG_PREFIX, "Higher Timeframe Analysis (", EnumToString(HigherTimeframe), "):");
   Print(DEBUG_PREFIX, "Candle - Open: ", htf_open, " High: ", htf_high, " Low: ", htf_low, " Close: ", htf_close);
   Print(DEBUG_PREFIX, "Is Bullish: ", htf_is_bullish, " Strong Momentum: ", strong_momentum);
   Print(DEBUG_PREFIX, "Trend - Up: ", uptrend, " Down: ", downtrend);

   if(type == POSITION_TYPE_BUY)
   {
      // For buy signals, we want:
      // 1. Current candle is bullish with good momentum, or
      // 2. Clear uptrend in place
      bool confirmed = (htf_is_bullish && strong_momentum) || uptrend;
      Print(DEBUG_PREFIX, "Buy Signal Higher TF Confirmation: ", confirmed);
      return confirmed;
   }
   else
   {
      // For sell signals, we want:
      // 1. Current candle is bearish with good momentum, or
      // 2. Clear downtrend in place
      bool confirmed = (!htf_is_bullish && strong_momentum) || downtrend;
      Print(DEBUG_PREFIX, "Sell Signal Higher TF Confirmation: ", confirmed);
      return confirmed;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all zone objects
   DeleteZoneObjects();

   // Clean up session objects
   DeleteSessionObjects();

   // Clean up any indicators
   IndicatorRelease(iATR(_Symbol, PERIOD_D1, 14));
}

//+------------------------------------------------------------------+
//| Delete session visualization objects                              |
//+------------------------------------------------------------------+
void DeleteSessionObjects()
{
   ObjectDelete(0, SESSION_PREFIX + LONDON_SESSION);
   ObjectDelete(0, SESSION_PREFIX + NEWYORK_SESSION);
   ObjectDelete(0, SESSION_PREFIX + ASIAN_SESSION);
}

//+------------------------------------------------------------------+
//| Draw trading sessions on chart                                    |
//+------------------------------------------------------------------+
void DrawSessions()
{
   if(!ShowSessions) return;

   // Delete existing session objects
   DeleteSessionObjects();

   datetime currentTime = TimeCurrent();
   MqlDateTime time;
   TimeToStruct(currentTime, time);

   // Get start of current day
   datetime startOfDay = currentTime - (time.hour * 3600 + time.min * 60 + time.sec);

   // Calculate session times for visualization
   datetime asianOpen = startOfDay + AsianOpenHour * 3600;
   datetime asianClose = startOfDay + AsianCloseHour * 3600;
   datetime londonOpen = startOfDay + LondonOpenHour * 3600;
   datetime londonClose = startOfDay + LondonCloseHour * 3600;
   datetime nyOpen = startOfDay + NewYorkOpenHour * 3600;
   datetime nyClose = startOfDay + NewYorkCloseHour * 3600;

   // Get price range for rectangles
   double upperPrice = ChartGetDouble(0, CHART_PRICE_MAX);
   double lowerPrice = ChartGetDouble(0, CHART_PRICE_MIN);

   // Draw Asian session
   DrawSessionRectangle(SESSION_PREFIX + ASIAN_SESSION,
                       asianOpen, asianClose,
                       upperPrice, lowerPrice,
                       AsianSessionColor,
                       "Asian Session");

   // Draw London session
   DrawSessionRectangle(SESSION_PREFIX + LONDON_SESSION,
                       londonOpen, londonClose,
                       upperPrice, lowerPrice,
                       LondonSessionColor,
                       "London Session");

   // Draw New York session
   DrawSessionRectangle(SESSION_PREFIX + NEWYORK_SESSION,
                       nyOpen, nyClose,
                       upperPrice, lowerPrice,
                       NewYorkSessionColor,
                       "New York Session");

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw a single session rectangle                                   |
//+------------------------------------------------------------------+
void DrawSessionRectangle(string name, datetime time1, datetime time2,
                         double price1, double price2, color clr,
                         string description)
{
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);  // Make visible
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);

   // Set transparency
   color transparentColor = ChartSetTransparency(clr, 20);  // More transparent
   ObjectSetInteger(0, name, OBJPROP_COLOR, transparentColor);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, description);
}

//+------------------------------------------------------------------+
//| Custom function to update session visualization                   |
//+------------------------------------------------------------------+
void UpdateSessionVisualization()
{
   static datetime lastUpdate = 0;
   datetime currentTime = TimeCurrent();

   MqlDateTime time1, time2;
   TimeToStruct(currentTime, time1);
   TimeToStruct(lastUpdate, time2);

   // Update sessions every new day or on init
   if(lastUpdate == 0 || time1.day != time2.day)
   {
      DrawSessions();
      lastUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Update session statistics                                         |
//+------------------------------------------------------------------+
void UpdateSessionStats(SessionStats &stats, double profit)
{
   stats.totalTrades++;

   if(profit > 0)
   {
      stats.winningTrades++;
      stats.grossProfit += profit;
      stats.largestWin = MathMax(stats.largestWin, profit);
   }
   else
   {
      stats.losingTrades++;
      stats.grossLoss += MathAbs(profit);
      stats.largestLoss = MathMin(stats.largestLoss, profit);
   }

   // Calculate win rate and profit factor
   stats.winRate = stats.totalTrades > 0 ?
                  (double)stats.winningTrades/stats.totalTrades * 100 : 0;
   stats.profitFactor = stats.grossLoss > 0 ?
                       stats.grossProfit/stats.grossLoss : stats.grossProfit;
}

//+------------------------------------------------------------------+
//| Get current trading session                                       |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int currentHour = time.hour;

   if(currentHour >= AsianOpenHour && currentHour < AsianCloseHour)
      return "Asian";
   else if(currentHour >= LondonOpenHour && currentHour < LondonCloseHour)
      return "London";
   else if(currentHour >= NewYorkOpenHour && currentHour < NewYorkCloseHour)
      return "NewYork";

   return "None";
}

//+------------------------------------------------------------------+
//| Print session statistics                                          |
//+------------------------------------------------------------------+
void PrintSessionStats()
{
   Print("=== Session Trading Statistics ===");

   // Asian Session Stats
   Print("--- Asian Session ---");
   Print("Total Trades: ", g_asianStats.totalTrades);
   Print("Win Rate: ", DoubleToString(g_asianStats.winRate, 2), "%");
   Print("Profit Factor: ", DoubleToString(g_asianStats.profitFactor, 2));
   Print("Gross Profit: ", DoubleToString(g_asianStats.grossProfit, 2));
   Print("Gross Loss: ", DoubleToString(g_asianStats.grossLoss, 2));
   Print("Largest Win: ", DoubleToString(g_asianStats.largestWin, 2));
   Print("Largest Loss: ", DoubleToString(g_asianStats.largestLoss, 2));

   // London Session Stats
   Print("--- London Session ---");
   Print("Total Trades: ", g_londonStats.totalTrades);
   Print("Win Rate: ", DoubleToString(g_londonStats.winRate, 2), "%");
   Print("Profit Factor: ", DoubleToString(g_londonStats.profitFactor, 2));
   Print("Gross Profit: ", DoubleToString(g_londonStats.grossProfit, 2));
   Print("Gross Loss: ", DoubleToString(g_londonStats.grossLoss, 2));
   Print("Largest Win: ", DoubleToString(g_londonStats.largestWin, 2));
   Print("Largest Loss: ", DoubleToString(g_londonStats.largestLoss, 2));

   // New York Session Stats
   Print("--- New York Session ---");
   Print("Total Trades: ", g_nyStats.totalTrades);
   Print("Win Rate: ", DoubleToString(g_nyStats.winRate, 2), "%");
   Print("Profit Factor: ", DoubleToString(g_nyStats.profitFactor, 2));
   Print("Gross Profit: ", DoubleToString(g_nyStats.grossProfit, 2));
   Print("Gross Loss: ", DoubleToString(g_nyStats.grossLoss, 2));
   Print("Largest Win: ", DoubleToString(g_nyStats.largestWin, 2));
   Print("Largest Loss: ", DoubleToString(g_nyStats.largestLoss, 2));
}

//+------------------------------------------------------------------+
//| Delete zone objects                                               |
//+------------------------------------------------------------------+
void DeleteZoneObjects()
{
   ObjectDelete(0, ZONE_PREFIX + TOP_ZONE);
   ObjectDelete(0, ZONE_PREFIX + BOTTOM_ZONE);
   ObjectDelete(0, ZONE_PREFIX + MIDDLE_ZONE);
   ObjectDelete(0, ZONE_PREFIX + VALID_TOP_ZONE);
   ObjectDelete(0, ZONE_PREFIX + VALID_BOTTOM_ZONE);
}

//+------------------------------------------------------------------+
//| Draw trading zones on chart                                       |
//+------------------------------------------------------------------+
void DrawZones()
{
   if(g_boxHigh <= 0 || g_boxLow <= 0 || g_boxHigh <= g_boxLow)
   {
      Print(DEBUG_PREFIX, "Cannot draw zones - Invalid box boundaries");
      return;
   }

   Print(DEBUG_PREFIX, "Drawing zones on chart");

   // Delete existing zones
   DeleteZoneObjects();

   double boxHeight = g_boxHigh - g_boxLow;

   // Calculate zone boundaries
   double topZoneStart = g_boxHigh - (boxHeight * TopZonePercent / 100);
   double bottomZoneEnd = g_boxLow + (boxHeight * BottomZonePercent / 100);
   double middleZoneStart = g_boxLow + (boxHeight - (boxHeight * MiddleZonePercent / 100)) / 2;
   double middleZoneEnd = middleZoneStart + (boxHeight * MiddleZonePercent / 100);

   datetime time = TimeCurrent();
   datetime tomorrow = time + PeriodSeconds(PERIOD_D1);

   // Draw zones with transparency
   color transparentTopColor = ChartSetTransparency(TOP_ZONE_COLOR, 20);
   color transparentBottomColor = ChartSetTransparency(BOTTOM_ZONE_COLOR, 20);
   color transparentMiddleColor = ChartSetTransparency(MIDDLE_ZONE_COLOR, 20);

   // Draw box boundaries first (more visible)
   ObjectCreate(0, ZONE_PREFIX + "BoxHigh", OBJ_HLINE, 0, time, g_boxHigh);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxHigh", OBJPROP_COLOR, clrDarkGray);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxHigh", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxHigh", OBJPROP_WIDTH, 2);

   ObjectCreate(0, ZONE_PREFIX + "BoxLow", OBJ_HLINE, 0, time, g_boxLow);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxLow", OBJPROP_COLOR, clrDarkGray);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxLow", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, ZONE_PREFIX + "BoxLow", OBJPROP_WIDTH, 2);

   // Draw zones
   ObjectCreate(0, ZONE_PREFIX + TOP_ZONE, OBJ_RECTANGLE, 0, time, topZoneStart, tomorrow, g_boxHigh);
   ObjectSetInteger(0, ZONE_PREFIX + TOP_ZONE, OBJPROP_COLOR, transparentTopColor);
   ObjectSetInteger(0, ZONE_PREFIX + TOP_ZONE, OBJPROP_FILL, true);
   ObjectSetInteger(0, ZONE_PREFIX + TOP_ZONE, OBJPROP_BACK, true);
   ObjectSetInteger(0, ZONE_PREFIX + TOP_ZONE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ZONE_PREFIX + TOP_ZONE, OBJPROP_STYLE, STYLE_SOLID);

   ObjectCreate(0, ZONE_PREFIX + BOTTOM_ZONE, OBJ_RECTANGLE, 0, time, g_boxLow, tomorrow, bottomZoneEnd);
   ObjectSetInteger(0, ZONE_PREFIX + BOTTOM_ZONE, OBJPROP_COLOR, transparentBottomColor);
   ObjectSetInteger(0, ZONE_PREFIX + BOTTOM_ZONE, OBJPROP_FILL, true);
   ObjectSetInteger(0, ZONE_PREFIX + BOTTOM_ZONE, OBJPROP_BACK, true);
   ObjectSetInteger(0, ZONE_PREFIX + BOTTOM_ZONE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ZONE_PREFIX + BOTTOM_ZONE, OBJPROP_STYLE, STYLE_SOLID);

   ObjectCreate(0, ZONE_PREFIX + MIDDLE_ZONE, OBJ_RECTANGLE, 0, time, middleZoneStart, tomorrow, middleZoneEnd);
   ObjectSetInteger(0, ZONE_PREFIX + MIDDLE_ZONE, OBJPROP_COLOR, transparentMiddleColor);
   ObjectSetInteger(0, ZONE_PREFIX + MIDDLE_ZONE, OBJPROP_FILL, true);
   ObjectSetInteger(0, ZONE_PREFIX + MIDDLE_ZONE, OBJPROP_BACK, true);
   ObjectSetInteger(0, ZONE_PREFIX + MIDDLE_ZONE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ZONE_PREFIX + MIDDLE_ZONE, OBJPROP_STYLE, STYLE_SOLID);

   Print(DEBUG_PREFIX, "Zones drawn successfully");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Get pattern name for debugging                                    |
//+------------------------------------------------------------------+
string GetPatternName(CANDLE_PATTERN pattern)
{
   switch(pattern)
   {
      case PATTERN_DOJI: return "Doji";
      case PATTERN_HAMMER: return "Hammer";
      case PATTERN_SHOOTING_STAR: return "Shooting Star";
      case PATTERN_BULLISH_ENGULFING: return "Bullish Engulfing";
      case PATTERN_BEARISH_ENGULFING: return "Bearish Engulfing";
      case PATTERN_MORNING_STAR: return "Morning Star";
      case PATTERN_EVENING_STAR: return "Evening Star";
      case PATTERN_BOX_REVERSAL_BULL: return "Bullish Box Reversal";
      case PATTERN_BOX_REVERSAL_BEAR: return "Bearish Box Reversal";
      default: return "None";
   }
}

//+------------------------------------------------------------------+
//| Set color transparency                                            |
//+------------------------------------------------------------------+
color ChartSetTransparency(color clr, uchar transparency)
{
   return((color)((clr & 0xFFFFFF) | ((uchar)(transparency * 255 / 100) << 24)));
}

//+------------------------------------------------------------------+
//| Calculate box boundaries using ATR and price action                |
//+------------------------------------------------------------------+
bool CalculateBox()
{
   datetime currentTime = TimeCurrent();
   if(currentTime <= 0) return false;

   // Initialize ATR
   int atrPeriod = 14;
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);

   if(atrHandle == INVALID_HANDLE)
   {
      Print(DEBUG_PREFIX, "Failed to create ATR indicator handle");
      return false;
   }

   // Copy ATR values
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
   {
      Print(DEBUG_PREFIX, "Failed to copy ATR values");
      IndicatorRelease(atrHandle);
      return false;
   }
   IndicatorRelease(atrHandle);

   // Get recent price data
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   // Copy price data for the last 20 bars
   int bars = 20;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, bars, highs) <= 0 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, bars, lows) <= 0 ||
      CopyClose(_Symbol, PERIOD_CURRENT, 0, bars, closes) <= 0)
   {
      Print(DEBUG_PREFIX, "Failed to copy price data");
      return false;
   }

   // Calculate dynamic box size based on instrument
   double boxMultiplier;
   if(_Symbol == "XAUUSD")
   {
      boxMultiplier = 2.0; // Larger multiplier for XAUUSD due to higher volatility
   }
   else
   {
      boxMultiplier = 1.5; // Standard multiplier for forex pairs
   }

   // Find the recent swing high and low
   double swingHigh = highs[ArrayMaximum(highs, 0, bars)];
   double swingLow = lows[ArrayMinimum(lows, 0, bars)];

   // Calculate recent price volatility
   double volatility = 0;
   for(int i = 1; i < bars; i++)
   {
      volatility += MathAbs(closes[i] - closes[i-1]);
   }
   volatility /= (bars - 1);

   // Calculate dynamic box boundaries
   double currentPrice = closes[0];
   double boxSize = atr[0] * boxMultiplier;

   // Adjust box size based on recent volatility
   if(volatility > atr[0])
   {
      boxSize *= 1.2; // Increase box size in high volatility
   }
   else if(volatility < atr[0] * 0.5)
   {
      boxSize *= 0.8; // Decrease box size in low volatility
   }

   // Calculate box boundaries centered around current price
   g_boxHigh = currentPrice + (boxSize / 2);
   g_boxLow = currentPrice - (boxSize / 2);

   // Adjust boundaries based on recent swing points
   if(g_boxHigh < swingHigh)
   {
      double adjustment = (swingHigh - g_boxHigh) * 0.5;
      g_boxHigh += adjustment;
      g_boxLow += adjustment;
   }
   else if(g_boxLow > swingLow)
   {
      double adjustment = (g_boxLow - swingLow) * 0.5;
      g_boxHigh -= adjustment;
      g_boxLow -= adjustment;
   }

   // Ensure minimum box size
   double minBoxSize;
   if(_Symbol == "XAUUSD")
   {
      minBoxSize = 2.0; // Minimum 2.0 points for XAUUSD
   }
   else
   {
      minBoxSize = 0.0020; // Minimum 20 pips for forex pairs
   }

   if((g_boxHigh - g_boxLow) < minBoxSize)
   {
      double midPoint = (g_boxHigh + g_boxLow) / 2;
      g_boxHigh = midPoint + (minBoxSize / 2);
      g_boxLow = midPoint - (minBoxSize / 2);
   }

   Print(DEBUG_PREFIX, "Box Calculation Details:");
   Print(DEBUG_PREFIX, "Symbol: ", _Symbol);
   Print(DEBUG_PREFIX, "ATR: ", atr[0]);
   Print(DEBUG_PREFIX, "Box Size: ", boxSize);
   Print(DEBUG_PREFIX, "Volatility: ", volatility);
   Print(DEBUG_PREFIX, "Swing High: ", swingHigh);
   Print(DEBUG_PREFIX, "Swing Low: ", swingLow);
   Print(DEBUG_PREFIX, "Current Price: ", currentPrice);
   Print(DEBUG_PREFIX, "Box High: ", g_boxHigh);
   Print(DEBUG_PREFIX, "Box Low: ", g_boxLow);
   Print(DEBUG_PREFIX, "Box Height: ", g_boxHigh - g_boxLow);

   return true;
}

//+------------------------------------------------------------------+
//| Get the current price zone                                        |
//+------------------------------------------------------------------+
PRICE_ZONE GetPriceZone(double price)
{
   double boxHeight = g_boxHigh - g_boxLow;
   double topZoneSize = boxHeight * TopZonePercent / 100;
   double bottomZoneSize = boxHeight * BottomZonePercent / 100;
   double middleZoneSize = boxHeight * MiddleZonePercent / 100;

   // Calculate zone boundaries
   double topZoneStart = g_boxHigh - topZoneSize;
   double bottomZoneEnd = g_boxLow + bottomZoneSize;
   double middleZoneStart = g_boxLow + (boxHeight - middleZoneSize) / 2;
   double middleZoneEnd = middleZoneStart + middleZoneSize;

   // Determine current zone
   if(price >= topZoneStart)
      return ZONE_TOP;
   else if(price <= bottomZoneEnd)
      return ZONE_BOTTOM;
   else if(price >= middleZoneStart && price <= middleZoneEnd)
      return ZONE_MIDDLE;
   else
      return ZONE_VALID_TRADE;
}

//+------------------------------------------------------------------+
//| Get zone name for logging                                         |
//+------------------------------------------------------------------+
string GetZoneName(PRICE_ZONE zone)
{
   switch(zone)
   {
      case ZONE_TOP:
         return "Top Zone";
      case ZONE_BOTTOM:
         return "Bottom Zone";
      case ZONE_MIDDLE:
         return "Middle Zone";
      default:
         return "Valid Trade Zone";
   }
}

// Add helper function for error descriptions
string GetErrorDescription(int error_code)
{
   switch(error_code)
   {
      case TRADE_RETCODE_DONE:           return "Request completed";
      case TRADE_RETCODE_REJECT:         return "Request rejected";
      case TRADE_RETCODE_CANCEL:         return "Request canceled by trader";
      case TRADE_RETCODE_PLACED:         return "Order placed";
      case TRADE_RETCODE_DONE_PARTIAL:   return "Request partially completed";
      case TRADE_RETCODE_ERROR:          return "Request processing error";
      case TRADE_RETCODE_TIMEOUT:        return "Request canceled by timeout";
      case TRADE_RETCODE_INVALID:        return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume in request";
      case TRADE_RETCODE_INVALID_PRICE:  return "Invalid price in request";
      case TRADE_RETCODE_INVALID_STOPS:  return "Invalid stops in request";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trading is disabled";
      case TRADE_RETCODE_MARKET_CLOSED:  return "Market is closed";
      case TRADE_RETCODE_NO_MONEY:       return "Not enough money";
      case TRADE_RETCODE_PRICE_CHANGED:  return "Prices changed";
      case TRADE_RETCODE_PRICE_OFF:      return "No quotes to process request";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid order expiration";
      case TRADE_RETCODE_ORDER_CHANGED:  return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too frequent requests";
      case TRADE_RETCODE_NO_CHANGES:     return "No changes in request";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Autotrading disabled by server";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Autotrading disabled by client terminal";
      case TRADE_RETCODE_LOCKED:         return "Request locked for processing";
      case TRADE_RETCODE_FROZEN:         return "Order or position frozen";
      case TRADE_RETCODE_INVALID_FILL:   return "Invalid order filling type";
      case TRADE_RETCODE_CONNECTION:     return "No connection with trade server";
      case TRADE_RETCODE_ONLY_REAL:      return "Operation allowed only for live accounts";
      case TRADE_RETCODE_LIMIT_ORDERS:   return "Number of pending orders reached limit";
      case TRADE_RETCODE_LIMIT_VOLUME:   return "Volume of orders and positions reached limit";
      default:                           return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions                           |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   if(!UseTrailingStop) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(!PositionSelectByTicket(ticket)) continue;

      // Check if position belongs to our EA
      if(PositionGetInteger(POSITION_MAGIC) != 123456) continue;

      double currentStop = GlobalVariableGet("TrailingStop_" + IntegerToString(ticket));
      double trailingStep = GlobalVariableGet("TrailingStep_" + IntegerToString(ticket));

      if(currentStop == 0 || trailingStep == 0) continue;

      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      bool shouldUpdate = false;
      double newStop = 0;

      if(positionType == POSITION_TYPE_BUY)
      {
         newStop = currentPrice - trailingStep;
         shouldUpdate = (newStop > currentStop);
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         newStop = currentPrice + trailingStep;
         shouldUpdate = (newStop < currentStop);
      }

      if(shouldUpdate)
      {
         trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
         if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            GlobalVariableSet("TrailingStop_" + IntegerToString(ticket), newStop);
            Print(DEBUG_PREFIX, "Updated trailing stop for ticket ", ticket, " to: ", newStop);
         }
         else
         {
            Print(DEBUG_PREFIX, "Failed to update trailing stop. Error: ", GetLastError(),
                  " Description: ", GetErrorDescription(trade.ResultRetcode()));
         }
      }
   }
}
