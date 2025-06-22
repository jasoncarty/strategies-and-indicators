//+------------------------------------------------------------------+
//|                                           xauusd-strategy-2.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Support/Resistance Strategy                 |
//| Description:                                                       |
//|   A trading strategy for XAUUSD (Gold) that identifies key         |
//|   support and resistance levels using price action and volume.     |
//|   It trades bounces and breakouts from these levels.              |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Price bounces from support with volume confirmation      |
//|   - SELL: Price bounces from resistance with volume confirmation  |
//|   - Breakout trades with strong momentum                          |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Price reaches next support/resistance level                    |
//|   - Fixed risk-reward ratio                                       |
//|   - Trailing stop on breakout trades                              |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Position sizing based on level distance                       |
//|   - Maximum risk per trade                                        |
//|   - Multiple timeframe confirmation                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Enums
enum TREND_DIRECTION
{
   TREND_NONE = 0,    // No clear trend
   TREND_UP = 1,      // Uptrend
   TREND_DOWN = 2     // Downtrend
};

// Input Parameters
input group "Trend Line Parameters"
input int      SwingLookback = 20;        // Number of bars to look back for swing points
input int      MinSwingStrength = 3;      // Minimum number of touches for valid trend line
input double   BreakoutThreshold = 0.1;    // Percentage beyond trend line for breakout confirmation

input group "Volume Parameters"
input int      VolumeMAPeriod = 20;       // Period for volume moving average
input double   HighVolMultiplier = 1.5;    // High volume threshold (multiple of average)
input double   LowVolMultiplier = 0.7;     // Low volume threshold (multiple of average)

input group "Retest Parameters"
input int      MaxBarsWaitRetest = 10;     // Maximum bars to wait for retest
input double   RetestThreshold = 0.3;      // How close price needs to get to trend line for retest (%)

input group "Risk Management"
input double   RiskPercent = 1.0;          // Risk percent per trade
input double   RewardRatio = 2.0;          // Reward:Risk ratio
input bool     UseBreakEven = true;        // Use break even
input double   BreakEvenProfit = 1.0;      // Points to move stop to break even
input bool     UseTrailingStop = true;     // Use trailing stop
input double   TrailingStart = 2.0;        // Points to start trailing
input double   TrailingStep = 0.5;         // Trailing step

input group "Session Control"
input bool     UseAsianSession = true;     // Trade Asian session
input bool     UseLondonSession = true;    // Trade London session
input bool     UseNewYorkSession = true;   // Trade New York session
input int      AsianOpenHour = 1;          // Asian session open hour (server time)
input int      AsianCloseHour = 9;         // Asian session close hour (server time)
input int      LondonOpenHour = 9;         // London session open hour (server time)
input int      LondonCloseHour = 17;       // London session close hour (server time)
input int      NewYorkOpenHour = 14;       // New York session open hour (server time)
input int      NewYorkCloseHour = 22;      // New York session close hour (server time)

input group "Trend Analysis Parameters"
input int      LongTermLookback = 100;    // Number of bars for long-term trend (broader context)
input int      MidTermLookback = 50;      // Number of bars for mid-term trend
input double   LongTermWeight = 0.5;       // Weight for long-term trend influence (0.1 to 1.0)
input double   MajorSwingThreshold = 0.005; // Major swing point threshold (0.5%)
input double   MinorSwingThreshold = 0.002; // Minor swing point threshold (0.2%)
input int      MinBarsForSwing = 3;       // Minimum bars between swing points
input double   TrendStrengthThreshold = 0.4; // Minimum trend strength to confirm trend (0.0 to 1.0)

input group "Debug Settings"
input bool     EnableDebugLogs = true;    // Enable detailed debug logging

input group "Additional Entry Filters"
input bool     UseRSIFilter = true;       // Use RSI filter
input int      RSIPeriod = 14;            // RSI period
input int      RSIOverbought = 75;        // RSI overbought level
input int      RSIOversold = 25;          // RSI oversold level
input bool     UseMultiTimeframe = true;  // Use multiple timeframe confirmation
input bool     UseDailyLimits = true;     // Use daily loss limits
input int      MaxDailyLosses = 3;        // Maximum number of losses per day
input double   MinChannelWidth = 5.0;     // Minimum channel width in points
input double   MaxChannelWidth = 150.0;   // Maximum channel width in points

// Global Variables
CTrade trade;
int g_volume_ma_handle;
datetime g_last_bar_time = 0;  // Track last bar time
double g_trend_line_price = 0;
datetime g_breakout_time = 0;
bool g_waiting_for_retest = false;
TREND_DIRECTION g_current_trend = TREND_NONE;
double g_retest_level = 0;
int g_trend_line_id = 0;
datetime g_last_trend_time = 0;
int g_swing_point_id = 0;

// Add these global variables after other globals
ENUM_TIMEFRAMES g_current_timeframe;  // Store the current timeframe
datetime g_last_candle_time;          // Last processed candle time
datetime g_last_channel_reset = 0;
bool g_channel_breakout = false;
double g_breakout_price = 0;
int g_bars_since_breakout = 0;
double g_channel_width = 0;

// Add these channel boundary variables
double g_channel_upper = 0;  // Upper channel boundary
double g_channel_lower = 0;  // Lower channel boundary

// Add these global variables at the top with other globals
double g_min_channel_points = 3;  // Minimum points needed to form a channel

// Struct for swing points
struct SwingPoint
{
   datetime time;
   double price;
   bool isHigh;
};

// Add after other global variables
struct TrendFactors {
    int slope_points;
    int swing_points;
    int ma_points;
    int total_points;
};

// Add this structure for multi-timeframe trend analysis
struct TrendContext {
    TREND_DIRECTION main_trend;
    TREND_DIRECTION short_term_trend;
    double trend_strength;
};

// Add these after other global variables
string g_channel_upper_name = "";
string g_channel_lower_name = "";
color g_channel_color_up = clrForestGreen;
color g_channel_color_down = clrCrimson;
color g_channel_color_none = clrDarkGray;

// Add after other global variables
int g_rsi_handle;
datetime g_last_loss_time = 0;
int g_daily_losses = 0;
double g_daily_loss_points = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Clean up any existing objects from previous runs
   CleanupAllLines();

   // Store the current timeframe
   g_current_timeframe = Period();
   g_last_candle_time = 0;

   // Initialize volume MA indicator
   g_volume_ma_handle = iMA(_Symbol, PERIOD_CURRENT, VolumeMAPeriod, 0, MODE_SMA, VOLUME_TICK);
   if(g_volume_ma_handle == INVALID_HANDLE)
   {
      Print("Failed to create volume MA indicator");
      return INIT_FAILED;
   }

   Print("Strategy initialized on timeframe: ", EnumToString(g_current_timeframe));
   Print("Initial parameters:");
   Print("SwingLookback: ", SwingLookback);
   Print("MinSwingStrength: ", MinSwingStrength);
   Print("BreakoutThreshold: ", BreakoutThreshold);
   Print("RetestThreshold: ", RetestThreshold);

   // Set up trade object
   trade.SetExpertMagicNumber(232323);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   // Initialize RSI
   if(UseRSIFilter)
   {
      g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
      if(g_rsi_handle == INVALID_HANDLE)
      {
         Print("Failed to create RSI indicator");
         return INIT_FAILED;
      }
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupAllLines();

   // Reset channel levels
   g_channel_upper = 0;
   g_channel_lower = 0;

   // Clean up indicators
   if(g_volume_ma_handle != INVALID_HANDLE)
      IndicatorRelease(g_volume_ma_handle);

   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);

   Print("EA deinitialized, all visual objects cleaned up");
}

//+------------------------------------------------------------------+
//| Clean up all trend and channel lines                              |
//+------------------------------------------------------------------+
void CleanupAllLines()
{
   // Delete all objects with our prefixes
   for(int i = ObjectsTotal(0, 0, OBJ_TREND) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_TREND);
      if(StringFind(name, "TrendLine") >= 0 ||
         StringFind(name, "ChannelUpper") >= 0 ||
         StringFind(name, "ChannelLower") >= 0)
      {
         ObjectDelete(0, name);
      }
   }

   // Reset line names
   g_channel_upper_name = "";
   g_channel_lower_name = "";
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime last_debug_time = 0;
   datetime current_time = TimeCurrent();

   // Get current candle time based on timeframe
   datetime current_candle_time = iTime(_Symbol, g_current_timeframe, 0);
   bool is_new_candle = (current_candle_time != g_last_candle_time);

   // Print debug info once per minute
   if(current_time - last_debug_time >= 60)
   {
      if(EnableDebugLogs)
      {
         Print("=== Strategy Status Update ===");
         Print("Current Time: ", TimeToString(current_time));
         Print("Symbol: ", _Symbol, ", Period: ", EnumToString(g_current_timeframe));
         Print("Current Trend: ", EnumToString(g_current_trend));
         Print("Trend Line Price: ", g_trend_line_price);
         Print("Channel Upper: ", g_channel_upper);
         Print("Channel Lower: ", g_channel_lower);
         Print("Waiting for Retest: ", g_waiting_for_retest);
         if(g_waiting_for_retest)
         {
            Print("Retest Level: ", g_retest_level);
            Print("Breakout Time: ", TimeToString(g_breakout_time));
         }
      }
      last_debug_time = current_time;
   }

   if(is_new_candle)
   {
      g_last_candle_time = current_candle_time;
      if(EnableDebugLogs)
      {
         Print("\n=== New ", EnumToString(g_current_timeframe), " Candle ===");
         Print("Time: ", TimeToString(current_candle_time));
      }

      // Basic checks
      if(!IsTradeAllowed())
      {
         if(EnableDebugLogs) Print("Trading not allowed - session check failed");
         return;
      }

      // Update swing points and trend on new candle
      SwingPoint swings[];
      TrendFactors up_factors = {0, 0, 0, 0};
      TrendFactors down_factors = {0, 0, 0, 0};

      if(EnableDebugLogs) Print("\n=== Starting Swing Point and Trend Update ===");

      if(!FindSwingPoints(swings, up_factors, down_factors))
      {
         Print("Failed to find swing points");
         return;
      }

      if(EnableDebugLogs)
      {
         Print("Found ", ArraySize(swings), " swing points");
         for(int i = 0; i < ArraySize(swings); i++)
         {
            Print("Swing ", i, ": ", swings[i].isHigh ? "HIGH" : "LOW",
                  " at price ", swings[i].price,
                  " time ", TimeToString(swings[i].time));
         }
      }

      if(EnableDebugLogs) Print("Updating trend line and channel...");
      UpdateTrendLine(swings);

      // Check for trade opportunities on new candles
      if(PositionsTotal() == 0)
      {
         if(EnableDebugLogs) Print("No open positions - checking for trade setup");
         CheckForTradeSetup();
      }
      else
      {
         if(EnableDebugLogs) Print("Positions open: ", PositionsTotal(), " - managing existing positions");
      }
   }

   // Always manage positions regardless of new candle
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Find swing points                                                 |
//+------------------------------------------------------------------+
bool FindSwingPoints(SwingPoint &swings[], TrendFactors &up_factors, TrendFactors &down_factors)
{
   static double high[], low[], close[];
   ArrayResize(high, LongTermLookback);
   ArrayResize(low, LongTermLookback);
   ArrayResize(close, LongTermLookback);

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, LongTermLookback, high) <= 0 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, LongTermLookback, low) <= 0 ||
      CopyClose(_Symbol, PERIOD_CURRENT, 0, LongTermLookback, close) <= 0)
   {
      Print("Failed to copy price data");
      return false;
   }

   ArrayResize(swings, 0);

   // Get ATR for dynamic thresholds
   double atr = 0;
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         atr = atr_buffer[0];
      }
      IndicatorRelease(atr_handle);
   }

   // Variables for zigzag-like swing detection
   double current_high = high[0];
   double current_low = low[0];
   bool looking_for_high = true;
   datetime current_high_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime current_low_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   int bars_since_last_swing = 0;

   // Use ATR for dynamic swing point threshold
   double swing_threshold = MathMax(atr / close[0], 0.001);  // At least 0.1% movement

   if(EnableDebugLogs)
   {
      Print("\n=== Swing Point Detection ===");
      Print("ATR: ", atr);
      Print("Swing threshold: ", swing_threshold);
   }

   // Clear old swing points
   ObjectsDeleteAll(0, "SwingPoint");

   for(int i = 1; i < LongTermLookback - 1; i++)
   {
      bars_since_last_swing++;

      if(looking_for_high)
      {
         if(high[i] > current_high)
         {
            current_high = high[i];
            current_high_time = iTime(_Symbol, PERIOD_CURRENT, i);
         }
         else if(bars_since_last_swing >= MinBarsForSwing &&
                (current_high - low[i]) / current_high > swing_threshold)
         {
            SwingPoint swing;
            swing.time = current_high_time;
            swing.price = current_high;
            swing.isHigh = true;
            ArrayResize(swings, ArraySize(swings) + 1);
            swings[ArraySize(swings)-1] = swing;

            // Draw swing point arrow
            string point_name = "SwingPoint" + IntegerToString(g_swing_point_id++);
            ObjectCreate(0, point_name, OBJ_ARROW_DOWN, 0, current_high_time, current_high);
            ObjectSetInteger(0, point_name, OBJPROP_COLOR, clrMagenta);
            ObjectSetInteger(0, point_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, point_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);

            looking_for_high = false;
            current_low = low[i];
            current_low_time = iTime(_Symbol, PERIOD_CURRENT, i);
            bars_since_last_swing = 0;

            if(EnableDebugLogs)
            {
               Print("Found HIGH swing point at: ", current_high, " time: ", TimeToString(current_high_time));
            }
         }
      }
      else  // looking for low
      {
         if(low[i] < current_low)
         {
            current_low = low[i];
            current_low_time = iTime(_Symbol, PERIOD_CURRENT, i);
         }
         else if(bars_since_last_swing >= MinBarsForSwing &&
                (high[i] - current_low) / current_low > swing_threshold)
         {
            SwingPoint swing;
            swing.time = current_low_time;
            swing.price = current_low;
            swing.isHigh = false;
            ArrayResize(swings, ArraySize(swings) + 1);
            swings[ArraySize(swings)-1] = swing;

            // Draw swing point arrow
            string point_name = "SwingPoint" + IntegerToString(g_swing_point_id++);
            ObjectCreate(0, point_name, OBJ_ARROW_UP, 0, current_low_time, current_low);
            ObjectSetInteger(0, point_name, OBJPROP_COLOR, clrCyan);
            ObjectSetInteger(0, point_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, point_name, OBJPROP_ANCHOR, ANCHOR_TOP);

            looking_for_high = true;
            current_high = high[i];
            current_high_time = iTime(_Symbol, PERIOD_CURRENT, i);
            bars_since_last_swing = 0;

            if(EnableDebugLogs)
            {
               Print("Found LOW swing point at: ", current_low, " time: ", TimeToString(current_low_time));
            }
         }
      }
   }

   if(EnableDebugLogs)
   {
      Print("Total swing points found: ", ArraySize(swings));
   }

   return ArraySize(swings) > 0;
}

//+------------------------------------------------------------------+
//| Update trend line and check for breakouts                         |
//+------------------------------------------------------------------+
void UpdateTrendLine(SwingPoint &swings[])
{
   if(EnableDebugLogs)
   {
      Print("\n=== UpdateTrendLine Start ===");
      Print("Number of swing points: ", ArraySize(swings));
   }

   // Clean up old lines before drawing new ones
   CleanupAllLines();

   if(ArraySize(swings) < MinSwingStrength)
   {
      if(EnableDebugLogs) Print("Not enough swing points for trend line: ", ArraySize(swings), " < ", MinSwingStrength);
      return;
   }

   double x[], y[];
   int count = 0;

   // Prepare data for linear regression
   for(int i = 0; i < ArraySize(swings); i++)
   {
      ArrayResize(x, count + 1);
      ArrayResize(y, count + 1);
      x[count] = (double)(swings[i].time - swings[ArraySize(swings)-1].time);
      y[count] = swings[i].price;
      count++;
   }

   if(EnableDebugLogs)
   {
      Print("Points for regression: ", count);
      for(int i = 0; i < count; i++)
      {
         Print("Point ", i, ": x=", x[i], " y=", y[i]);
      }
   }

   double a, b;
   if(LinearRegression(x, y, count, a, b))
   {
      double previous_price = g_trend_line_price;
      g_trend_line_price = a * (double)(iTime(_Symbol, PERIOD_CURRENT, 0) - swings[ArraySize(swings)-1].time) + b;

      if(EnableDebugLogs)
      {
         Print("Linear regression successful");
         Print("Slope (a): ", a);
         Print("Intercept (b): ", b);
         Print("Previous trend price: ", previous_price);
         Print("New trend price: ", g_trend_line_price);
      }

      // Calculate trend direction and strength
      TREND_DIRECTION previous_trend = g_current_trend;
      double slope_threshold = 0.00001;

      if(MathAbs(a) > slope_threshold)
      {
         g_current_trend = a > 0 ? TREND_UP : TREND_DOWN;
      }
      else
      {
         g_current_trend = TREND_NONE;
      }

      if(EnableDebugLogs)
      {
         Print("Previous trend: ", EnumToString(previous_trend));
         Print("New trend: ", EnumToString(g_current_trend));
      }

      // Draw trend line
      datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(current_time != g_last_trend_time)
      {
         string line_name = "TrendLine" + IntegerToString(g_trend_line_id);

         // Delete old trend line
         ObjectDelete(0, line_name);

         // Create new trend line
         if(!ObjectCreate(0, line_name, OBJ_TREND, 0,
                      swings[ArraySize(swings)-1].time, swings[ArraySize(swings)-1].price,
                      current_time, g_trend_line_price))
         {
            Print("Failed to create trend line object");
         }
         else
         {
            color trend_color = g_current_trend == TREND_UP ? clrGreen :
                              g_current_trend == TREND_DOWN ? clrRed : clrGray;

            ObjectSetInteger(0, line_name, OBJPROP_COLOR, trend_color);
            ObjectSetInteger(0, line_name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, line_name, OBJPROP_RAY_RIGHT, true);

            if(EnableDebugLogs)
            {
               Print("Drew trend line: ", line_name);
               Print("Start point: time=", TimeToString(swings[ArraySize(swings)-1].time),
                     " price=", swings[ArraySize(swings)-1].price);
               Print("End point: time=", TimeToString(current_time),
                     " price=", g_trend_line_price);
            }
         }

         g_last_trend_time = current_time;
         g_trend_line_id++;
      }

      // Add channel visualization
      if(EnableDebugLogs) Print("Calculating and drawing channel...");
      CalculateAndDrawChannel(swings, a, b);
   }
   else
   {
      if(EnableDebugLogs) Print("Linear regression failed");
   }
}

//+------------------------------------------------------------------+
//| Linear regression calculation                                     |
//+------------------------------------------------------------------+
bool LinearRegression(const double &x[], const double &y[], const int count,
                     double &a, double &b)
{
   if(count < 2)
   {
      if(EnableDebugLogs) Print("LinearRegression: Not enough points (", count, ")");
      return false;
   }

   double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;

   for(int i = 0; i < count; i++)
   {
      sum_x += x[i];
      sum_y += y[i];
      sum_xy += x[i] * y[i];
      sum_x2 += x[i] * x[i];
   }

   double d = count * sum_x2 - sum_x * sum_x;
   if(d == 0)
   {
      if(EnableDebugLogs) Print("LinearRegression: Division by zero detected");
      return false;
   }

   a = (count * sum_xy - sum_x * sum_y) / d;
   b = (sum_y - a * sum_x) / count;

   if(EnableDebugLogs)
   {
      Print("LinearRegression results - Slope: ", a, " Intercept: ", b);
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check for trade setup                                            |
//+------------------------------------------------------------------+
void CheckForTradeSetup()
{
   if(g_channel_upper == 0 || g_channel_lower == 0)
   {
      if(EnableDebugLogs) Print("No valid channel yet");
      return;
   }

   // Get recent price data
   double close[], open[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   // Get more bars to ensure we have complete data
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 5, close) <= 0 ||
      CopyOpen(_Symbol, PERIOD_CURRENT, 0, 5, open) <= 0 ||
      CopyHigh(_Symbol, PERIOD_CURRENT, 0, 5, high) <= 0 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, 5, low) <= 0)
   {
      Print("Failed to copy price data");
      return;
   }

   // Get ATR for dynamic thresholds
   double atr = 0;
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         atr = atr_buffer[0];
      }
      IndicatorRelease(atr_handle);
   }

   // Get volume confirmation
   long volume[];
   double volume_ma[];
   ArraySetAsSeries(volume, true);
   ArraySetAsSeries(volume_ma, true);

   if(CopyBuffer(g_volume_ma_handle, 0, 0, 2, volume_ma) <= 0 ||
      CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, 2, volume) <= 0)
   {
      Print("Failed to copy volume data");
      return;
   }

   double volume_ratio = (double)volume[1] / volume_ma[1];  // Check volume of the completed candle
   bool moderate_volume = volume_ratio > LowVolMultiplier;

   // Channel touch detection
   bool touched_lower = low[2] <= g_channel_lower + (atr * 0.5);
   bool touched_upper = high[2] >= g_channel_upper - (atr * 0.5);

   // Pattern detection
   bool bullish_engulfing = close[1] > open[1] &&      // Current candle is bullish
                           open[1] < close[2] &&        // Opens below previous close
                           close[1] > open[2];          // Closes above previous open

   bool bullish_hammer = close[1] > open[1] &&         // Bullish close
                        (close[1] - low[1]) > (high[1] - close[1]) * 1.5 && // Long lower wick
                        (high[1] - low[1]) > atr * 0.5;  // Significant size

   bool bearish_engulfing = close[1] < open[1] &&      // Current candle is bearish
                           open[1] > close[2] &&        // Opens above previous close
                           close[1] < open[2];          // Closes below previous open

   bool shooting_star = close[1] < open[1] &&          // Bearish close
                       (high[1] - close[1]) > (close[1] - low[1]) * 1.5 && // Long upper wick
                       (high[1] - low[1]) > atr * 0.5;  // Significant size

   if(EnableDebugLogs)
   {
      Print("\n=== Detailed Setup Analysis ===");
      Print("Channel Conditions:");
      Print("- Channel width: ", DoubleToString(g_channel_upper - g_channel_lower, 2));
      Print("- Min width required: ", MinChannelWidth);
      Print("- Max width allowed: ", MaxChannelWidth);
      Print("- Channel conditions met: ", CheckChannelConditions());

      Print("\nTrend Analysis:");
      Print("- Current trend: ", EnumToString(g_current_trend));
      Print("- Higher timeframe trend aligned (Buy): ", CheckMultiTimeframeTrend(true));
      Print("- Higher timeframe trend aligned (Sell): ", CheckMultiTimeframeTrend(false));

      Print("\nRSI Analysis:");
      Print("- Current RSI: ", DoubleToString(GetCurrentRSI(), 2));
      Print("- Buy conditions met: ", CheckRSIConditions(true));
      Print("- Sell conditions met: ", CheckRSIConditions(false));

      Print("\nPattern Detection:");
      Print("- Touched lower channel: ", touched_lower);
      Print("- Touched upper channel: ", touched_upper);
      Print("- Bullish engulfing: ", bullish_engulfing);
      Print("- Bullish hammer: ", bullish_hammer);
      Print("- Bearish engulfing: ", bearish_engulfing);
      Print("- Shooting star: ", shooting_star);

      Print("\nVolume Analysis:");
      Print("- Volume ratio: ", volume_ratio);
      Print("- Moderate volume: ", moderate_volume);
   }

   // Buy setup with additional conditions
   bool valid_buy_setup = g_current_trend == TREND_UP &&
                         touched_lower &&
                         (bullish_engulfing || bullish_hammer) &&
                         moderate_volume &&
                         CheckRSIConditions(true) &&
                         CheckMultiTimeframeTrend(true) &&
                         CheckChannelConditions();

   // Sell setup with additional conditions
   bool valid_sell_setup = g_current_trend == TREND_DOWN &&
                          touched_upper &&
                          (bearish_engulfing || shooting_star) &&
                          moderate_volume &&
                          CheckRSIConditions(false) &&
                          CheckMultiTimeframeTrend(false) &&
                          CheckChannelConditions();

   if(valid_buy_setup)
   {
      if(EnableDebugLogs)
      {
         Print("\n=== Valid Buy Setup Found ===");
         Print("Pattern: ", (bullish_engulfing ? "Bullish Engulfing" : "Bullish Hammer"));
         Print("RSI: ", DoubleToString(GetCurrentRSI(), 2));
         Print("Channel width: ", DoubleToString(g_channel_upper - g_channel_lower, 2));
      }
      OpenBuy();
   }
   else if(valid_sell_setup)
   {
      if(EnableDebugLogs)
      {
         Print("\n=== Valid Sell Setup Found ===");
         Print("Pattern: ", (bearish_engulfing ? "Bearish Engulfing" : "Shooting Star"));
         Print("RSI: ", DoubleToString(GetCurrentRSI(), 2));
         Print("Channel width: ", DoubleToString(g_channel_upper - g_channel_lower, 2));
      }
      OpenSell();
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                 |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Calculate dynamic stop loss based on ATR and channel
   double atr = 0;
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         atr = atr_buffer[0];
      }
      IndicatorRelease(atr_handle);
   }

   // Place stop loss below the channel or recent low, whichever is closer
   double channel_based_stop = g_channel_lower - (atr * 0.5);
   double recent_low = 0;

   double low[];
   ArraySetAsSeries(low, true);
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, 5, low) > 0)
   {
      recent_low = low[ArrayMinimum(low, 0, 5)] - (atr * 0.3);
   }

   double stop_loss = MathMax(channel_based_stop, recent_low);
   double take_profit = entry + (entry - stop_loss) * RewardRatio;

   double lot_size = CalculateLotSize(entry - stop_loss);
   if(lot_size == 0)
   {
      Print("Buy order rejected - Invalid lot size calculated");
      return;
   }

   Print("Attempting Buy - Entry: ", entry, " SL: ", stop_loss, " TP: ", take_profit, " Lots: ", lot_size);

   if(!trade.Buy(lot_size, _Symbol, 0, stop_loss, take_profit, "Channel Bounce"))
   {
      Print("Buy order failed - Error: ", GetLastError());
   }
   else
   {
      Print("Buy order placed successfully - Ticket: ", trade.ResultOrder());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                                |
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_loss = g_retest_level * (1 + RetestThreshold);
   double take_profit = entry - (stop_loss - entry) * RewardRatio;

   double lot_size = CalculateLotSize(stop_loss - entry);
   if(lot_size == 0)
   {
      Print("Sell order rejected - Invalid lot size calculated");
      return;
   }

   Print("Attempting Sell - Entry: ", entry, " SL: ", stop_loss, " TP: ", take_profit, " Lots: ", lot_size);

   if(!trade.Sell(lot_size, _Symbol, 0, stop_loss, take_profit, "XAUUSD Breakout"))
   {
      Print("Sell order failed - Error: ", GetLastError());
   }
   else
   {
      Print("Sell order placed successfully - Ticket: ", trade.ResultOrder());
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_distance)
{
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * RiskPercent / 100;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_size == 0) return 0;

   double risk_per_lot = (stop_distance / tick_size) * tick_value;
   if(risk_per_lot == 0) return 0;

   double lot_size = risk_amount / risk_per_lot;

   // Apply limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   return lot_size;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on all conditions               |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   if(!IsActiveSession()) return false;

   // Check daily limits
   if(UseDailyLimits)
   {
      MqlDateTime current_time, last_loss_time;
      TimeToStruct(TimeCurrent(), current_time);
      TimeToStruct(g_last_loss_time, last_loss_time);

      // Reset daily counters if it's a new day
      if(current_time.day != last_loss_time.day)
      {
         g_daily_losses = 0;
         g_daily_loss_points = 0;
      }

      if(g_daily_losses >= MaxDailyLosses)
      {
         if(EnableDebugLogs) Print("Maximum daily losses reached: ", g_daily_losses);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within active trading session            |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   if(!UseLondonSession && !UseNewYorkSession && !UseAsianSession) return true;

   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int current_hour = time.hour;

   static datetime last_session_check = 0;
   datetime current_time = TimeCurrent();

   // Log session status every 15 minutes
   if(current_time - last_session_check >= 900)  // 900 seconds = 15 minutes
   {
      Print("\n=== Session Status Check ===");
      Print("Current server time: ", TimeToString(current_time));
      Print("Current hour (server time): ", current_hour);

      if(UseAsianSession)
      {
         bool is_asian = (current_hour >= AsianOpenHour && current_hour < AsianCloseHour) ||
                        (AsianOpenHour > AsianCloseHour && (current_hour >= AsianOpenHour || current_hour < AsianCloseHour));
         Print("Asian Session (", AsianOpenHour, ":00 - ", AsianCloseHour, ":00): ",
               (is_asian ? "ACTIVE" : "inactive"));
      }
      else Print("Asian Session: disabled");

      if(UseLondonSession)
      {
         bool is_london = current_hour >= LondonOpenHour && current_hour < LondonCloseHour;
         Print("London Session (", LondonOpenHour, ":00 - ", LondonCloseHour, ":00): ",
               (is_london ? "ACTIVE" : "inactive"));
      }
      else Print("London Session: disabled");

      if(UseNewYorkSession)
      {
         bool is_ny = current_hour >= NewYorkOpenHour && current_hour < NewYorkCloseHour;
         Print("New York Session (", NewYorkOpenHour, ":00 - ", NewYorkCloseHour, ":00): ",
               (is_ny ? "ACTIVE" : "inactive"));
      }
      else Print("New York Session: disabled");

      last_session_check = current_time;
   }

   bool asian_active = UseAsianSession &&
                      ((current_hour >= AsianOpenHour && current_hour < AsianCloseHour) ||
                       (AsianOpenHour > AsianCloseHour && (current_hour >= AsianOpenHour || current_hour < AsianCloseHour)));

   bool london_active = UseLondonSession &&
                       current_hour >= LondonOpenHour &&
                       current_hour < LondonCloseHour;

   bool ny_active = UseNewYorkSession &&
                   current_hour >= NewYorkOpenHour &&
                   current_hour < NewYorkCloseHour;

   bool is_active = asian_active || london_active || ny_active;

   // Log when session status changes
   static bool last_active_status = false;
   if(is_active != last_active_status)
   {
      Print("\n=== Trading Session Status Change ===");
      Print("Time: ", TimeToString(current_time));
      Print("Trading ", (is_active ? "ENABLED" : "DISABLED"), " due to session rules");
      last_active_status = is_active;
   }

   return is_active;
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

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != trade.RequestMagic()) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
      double original_sl = PositionGetDouble(POSITION_SL);
      double take_profit = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Calculate profit distance and total target distance
      double profit_distance = type == POSITION_TYPE_BUY ?
                             current_price - entry :
                             entry - current_price;

      double total_target = type == POSITION_TYPE_BUY ?
                           take_profit - entry :
                           entry - take_profit;

      // Calculate progress towards target as a percentage
      double progress_percent = (profit_distance / total_target) * 100;

      if(EnableDebugLogs)
      {
         Print("\n=== Position Management ===");
         Print("Ticket: ", ticket);
         Print("Type: ", EnumToString(type));
         Print("Entry: ", entry);
         Print("Current: ", current_price);
         Print("TP: ", take_profit);
         Print("Original SL: ", original_sl);
         Print("Progress to target: ", DoubleToString(progress_percent, 2), "%");
      }

      // Dynamic trailing stop logic
      if(UseTrailingStop && progress_percent > 0)  // Only trail if in profit
      {
         double trail_distance = 0;

         if(progress_percent >= 50)  // If reached 50% of target
         {
            // Start with 10% trail and tighten as price moves higher
            double base_trail_percent = 10;
            double additional_tightening = (progress_percent - 50) * 0.4;  // 0.4% tighter for each 1% progress
            double trail_percent = MathMax(base_trail_percent - additional_tightening, 5);  // Don't go tighter than 5%

            trail_distance = (total_target * trail_percent) / 100;

            double new_stop = type == POSITION_TYPE_BUY ?
                            current_price - trail_distance :
                            current_price + trail_distance;

            // Only modify if new stop is better than current
            bool should_modify = type == POSITION_TYPE_BUY ?
                               (new_stop > original_sl && new_stop > PositionGetDouble(POSITION_SL)) :
                               (new_stop < original_sl && new_stop < PositionGetDouble(POSITION_SL));

            if(should_modify)
            {
               if(EnableDebugLogs)
               {
                  Print("Updating trailing stop:");
                  Print("- Progress: ", DoubleToString(progress_percent, 2), "%");
                  Print("- Trail percent: ", DoubleToString(trail_percent, 2), "%");
                  Print("- Trail distance: ", DoubleToString(trail_distance, 2));
                  Print("- New stop: ", DoubleToString(new_stop, 2));
               }

               if(!trade.PositionModify(ticket, new_stop, take_profit))
               {
                  Print("Failed to modify trailing stop - Error: ", GetLastError());
               }
            }
         }
      }

      // Break even logic
      if(UseBreakEven && original_sl != entry)
      {
         if(profit_distance >= BreakEvenProfit)
         {
            if(EnableDebugLogs) Print("Moving to break even - Ticket: ", ticket);
            if(!trade.PositionModify(ticket, entry, take_profit))
            {
               Print("Break even modification failed - Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add this function for longer-term trend analysis                   |
//+------------------------------------------------------------------+
TrendContext AnalyzeLongerTermTrend()
{
    TrendContext context;
    context.main_trend = TREND_NONE;
    context.short_term_trend = TREND_NONE;
    context.trend_strength = 0;

    double close[], ma50[], ma100[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(ma50, true);
    ArraySetAsSeries(ma100, true);

    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, LongTermLookback, close) <= 0)
        return context;

    int ma50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    int ma100_handle = iMA(_Symbol, PERIOD_CURRENT, 100, 0, MODE_SMA, PRICE_CLOSE);

    if(CopyBuffer(ma50_handle, 0, 0, LongTermLookback, ma50) <= 0 ||
       CopyBuffer(ma100_handle, 0, 0, LongTermLookback, ma100) <= 0)
    {
        Print("Failed to copy MA data");
        return context;
    }

    // Calculate trend metrics
    int up_count = 0, down_count = 0;
    int ma_crossovers = 0;
    bool last_ma50_above = ma50[0] > ma100[0];

    for(int i = 1; i < LongTermLookback; i++)
    {
        // Count price movements
        if(close[i-1] > close[i]) up_count++;
        else if(close[i-1] < close[i]) down_count++;

        // Count MA crossovers
        bool current_ma50_above = ma50[i] > ma100[i];
        if(current_ma50_above != last_ma50_above)
            ma_crossovers++;
        last_ma50_above = current_ma50_above;
    }

    // Calculate trend strength based on multiple factors
    double price_direction = (double)MathAbs(up_count - down_count) / LongTermLookback;
    double ma_stability = 1.0 - ((double)ma_crossovers / LongTermLookback);
    context.trend_strength = (price_direction + ma_stability) / 2;

    Print("\n=== Detailed Trend Analysis ===");
    Print("Up movements: ", up_count, ", Down movements: ", down_count);
    Print("MA Crossovers: ", ma_crossovers);
    Print("Price Direction Strength: ", DoubleToString(price_direction, 2));
    Print("MA Stability: ", DoubleToString(ma_stability, 2));
    Print("Overall Trend Strength: ", DoubleToString(context.trend_strength, 2));

    // More aggressive trend determination
    bool strong_ma_alignment = ma50[0] > ma100[0] && ma50[1] > ma100[1] && ma50[2] > ma100[2];
    bool price_above_mas = close[0] > ma50[0] && ma50[0] > ma100[0];
    bool price_below_mas = close[0] < ma50[0] && ma50[0] < ma100[0];

    Print("MA Alignment: ", (strong_ma_alignment ? "Strong" : "Weak"));
    Print("Price Position: ", (price_above_mas ? "Above MAs" : price_below_mas ? "Below MAs" : "Between MAs"));

    // Determine main trend with more sensitivity
    if(context.trend_strength >= TrendStrengthThreshold)
    {
        if(price_above_mas || (up_count > down_count && strong_ma_alignment))
        {
            context.main_trend = TREND_UP;
            Print("Uptrend confirmed by price position and MA alignment");
        }
        else if(price_below_mas || (down_count > up_count && !strong_ma_alignment))
        {
            context.main_trend = TREND_DOWN;
            Print("Downtrend confirmed by price position and MA alignment");
        }
    }
    else
    {
        Print("Trend strength below threshold (", TrendStrengthThreshold, ")");
    }

    // Short-term trend based on recent price action
    int recent_bars = 20;
    int recent_up = 0, recent_down = 0;
    for(int i = 1; i < recent_bars; i++)
    {
        if(close[i-1] > close[i]) recent_up++;
        else if(close[i-1] < close[i]) recent_down++;
    }

    if(recent_up > recent_down * 1.5)  // More sensitive short-term detection
    {
        context.short_term_trend = TREND_UP;
        Print("Short-term Uptrend (", recent_up, " up vs ", recent_down, " down)");
    }
    else if(recent_down > recent_up * 1.5)
    {
        context.short_term_trend = TREND_DOWN;
        Print("Short-term Downtrend (", recent_up, " up vs ", recent_down, " down)");
    }
    else
    {
        Print("No clear short-term trend (", recent_up, " up vs ", recent_down, " down)");
    }

    return context;
}

//+------------------------------------------------------------------+
//| Calculate and draw channel                                        |
//+------------------------------------------------------------------+
void CalculateAndDrawChannel(const SwingPoint &swings[], double trend_slope, double trend_intercept)
{
   if(ArraySize(swings) < g_min_channel_points)
   {
      if(EnableDebugLogs) Print("Not enough points for channel: ", ArraySize(swings));
      return;
   }

   // Create unique names for new channel lines
   string upper_name = "ChannelUpper" + IntegerToString(g_trend_line_id);
   string lower_name = "ChannelLower" + IntegerToString(g_trend_line_id);

   // Store old channel values for comparison
   double old_upper = g_channel_upper;
   double old_lower = g_channel_lower;

   // Get ATR for dynamic thresholds
   double atr = 0;
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         atr = atr_buffer[0];
      }
      IndicatorRelease(atr_handle);
   }

   // Calculate distances from trend line
   double max_distance_above = 0;
   double max_distance_below = 0;
   datetime max_above_time = 0;
   datetime max_below_time = 0;

   // Track points for channel validation
   int points_above = 0;
   int points_below = 0;
   double avg_distance = 0;
   int valid_swings = 0;

   // Arrays to store distances for standard deviation calculation
   double distances[];
   ArrayResize(distances, 0);

   for(int i = 0; i < ArraySize(swings); i++)
   {
      // Only use recent swing points (within last 50 bars)
      int bars_ago = iBarShift(_Symbol, PERIOD_CURRENT, swings[i].time);
      if(bars_ago > 50) continue;  // Increased from 30 to 50 bars

      valid_swings++;

      // Calculate expected y value on trend line
      double time_diff = (double)(swings[i].time - swings[ArraySize(swings)-1].time);
      double trend_line_price = trend_slope * time_diff + trend_intercept;

      // Calculate vertical distance from point to trend line
      double distance = swings[i].price - trend_line_price;

      // Store distance for standard deviation calculation
      ArrayResize(distances, ArraySize(distances) + 1);
      distances[ArraySize(distances) - 1] = MathAbs(distance);

      avg_distance += MathAbs(distance);

      if(distance > 0)
      {
         points_above++;
         if(distance > max_distance_above)
         {
            max_distance_above = distance;
            max_above_time = swings[i].time;
         }
      }
      else
      {
         points_below++;
         if(distance < max_distance_below)
         {
            max_distance_below = distance;
            max_below_time = swings[i].time;
         }
      }
   }

   // Exit if not enough recent valid swing points
   if(valid_swings < g_min_channel_points)
   {
      if(EnableDebugLogs) Print("Not enough recent swing points: ", valid_swings);
      return;
   }

   avg_distance /= valid_swings;

   // Calculate standard deviation of distances
   double sum_sq = 0;
   for(int i = 0; i < ArraySize(distances); i++)
   {
      sum_sq += MathPow(distances[i] - avg_distance, 2);
   }
   double std_dev = MathSqrt(sum_sq / ArraySize(distances));

   // Calculate channel width and symmetry metrics
   double channel_width = MathAbs(max_distance_above - max_distance_below);
   double width_ratio = MathMax(max_distance_above, MathAbs(max_distance_below)) /
                       MathMin(max_distance_above, MathAbs(max_distance_below));

   // Get current price for percentage-based calculations
   double current_price = iClose(_Symbol, PERIOD_CURRENT, 0);

   // XAUUSD-specific channel validation
   bool valid_distribution = points_above >= 1 && points_below >= 1;  // Need points on both sides

   // Width check based on percentage of price and ATR
   double width_percent = channel_width / current_price * 100;  // Channel width as percentage of price
   double min_width = atr * 2;  // Minimum width to avoid noise
   double max_width = MathMax(atr * 10, current_price * 0.05);  // Max width is larger of 10x ATR or 5% of price
   bool reasonable_width = channel_width >= min_width && channel_width <= max_width;

   bool width_symmetry = width_ratio < 2.5;  // Allow some asymmetry but not too much
   bool consistent_touches = std_dev < avg_distance;  // Use standard deviation for consistency check

   if(EnableDebugLogs)
   {
      Print("\n=== Channel Validation Details ===");
      Print("Points above/below: ", points_above, "/", points_below);
      Print("Channel width: ", channel_width);
      Print("Width as % of price: ", width_percent, "%");
      Print("Min allowed width: ", min_width);
      Print("Max allowed width: ", max_width);
      Print("Width ratio: ", width_ratio);
      Print("Average distance: ", avg_distance);
      Print("Distance StdDev: ", std_dev);
      Print("ATR: ", atr);
      Print("Valid distribution: ", valid_distribution);
      Print("Reasonable width: ", reasonable_width);
      Print("Width symmetry: ", width_symmetry);
      Print("Consistent touches: ", consistent_touches);
   }

   if(!valid_distribution || !reasonable_width || !width_symmetry || !consistent_touches)
   {
      if(EnableDebugLogs)
      {
         Print("=== Invalid Channel ===");
         Print("Failed checks:");
         if(!valid_distribution) Print("- Distribution");
         if(!reasonable_width) Print("- Width");
         if(!width_symmetry) Print("- Symmetry");
         if(!consistent_touches) Print("- Consistency");
      }
      return;
   }

   // Calculate channel boundaries with time projection
   datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   double time_projection = (double)(current_time - swings[ArraySize(swings)-1].time);
   g_channel_upper = trend_slope * time_projection + trend_intercept + max_distance_above;
   g_channel_lower = trend_slope * time_projection + trend_intercept + max_distance_below;
   g_trend_line_price = trend_slope * time_projection + trend_intercept;

   // Create channel lines only if they're significantly different from previous ones
   double channel_change_threshold = 0.0001;  // 0.01% change threshold
   bool should_update =
      g_channel_upper_name == "" ||  // First time drawing (no existing channel)
      g_channel_upper == 0 || g_channel_lower == 0 ||  // No previous channel values
      old_upper == 0 || old_lower == 0 ||  // No previous channel values
      MathAbs((g_channel_upper - old_upper) / old_upper) > channel_change_threshold ||  // Significant upper change
      MathAbs((g_channel_lower - old_lower) / old_lower) > channel_change_threshold;  // Significant lower change

   if(EnableDebugLogs)
   {
      Print("\n=== Channel Update Check ===");
      Print("Current channel names: upper=", g_channel_upper_name, " lower=", g_channel_lower_name);
      Print("Old channel values: upper=", old_upper, " lower=", old_lower);
      Print("New channel values: upper=", g_channel_upper, " lower=", g_channel_lower);
      Print("Should update: ", should_update);
      if(!should_update)
      {
         Print("Changes too small: ");
         Print("Upper change: ", MathAbs((g_channel_upper - old_upper) / old_upper));
         Print("Lower change: ", MathAbs((g_channel_lower - old_lower) / old_lower));
      }
   }

   if(should_update)
   {
      if(EnableDebugLogs)
      {
         Print("\n=== Drawing New Channel ===");
         Print("Old channel: ", old_upper, " / ", old_lower);
         Print("New channel: ", g_channel_upper, " / ", g_channel_lower);
      }

      // Create channel lines
      if(!ObjectCreate(0, upper_name, OBJ_TREND, 0,
                    swings[ArraySize(swings)-1].time, trend_intercept + max_distance_above,
                    current_time, g_channel_upper))
      {
         Print("Failed to create upper channel line");
         return;
      }

      if(!ObjectCreate(0, lower_name, OBJ_TREND, 0,
                    swings[ArraySize(swings)-1].time, trend_intercept + max_distance_below,
                    current_time, g_channel_lower))
      {
         Print("Failed to create lower channel line");
         ObjectDelete(0, upper_name);  // Clean up upper line if lower fails
         return;
      }

      // Set channel properties
      color channel_color = g_current_trend == TREND_UP ? g_channel_color_up :
                           g_current_trend == TREND_DOWN ? g_channel_color_down :
                           g_channel_color_none;

      // Upper channel properties
      ObjectSetInteger(0, upper_name, OBJPROP_COLOR, channel_color);
      ObjectSetInteger(0, upper_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, upper_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, upper_name, OBJPROP_RAY_RIGHT, true);

      // Lower channel properties
      ObjectSetInteger(0, lower_name, OBJPROP_COLOR, channel_color);
      ObjectSetInteger(0, lower_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lower_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, lower_name, OBJPROP_RAY_RIGHT, true);

      // Update channel line names
      g_channel_upper_name = upper_name;
      g_channel_lower_name = lower_name;
   }
   else if(EnableDebugLogs)
   {
      Print("Channel unchanged, skipping redraw");
   }
}

//+------------------------------------------------------------------+
//| Check for channel breakout and reset                              |
//+------------------------------------------------------------------+
bool CheckChannelBreakout()
{
   if(g_channel_upper == 0 || g_channel_lower == 0) return false;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   g_channel_width = g_channel_upper - g_channel_lower;

   // Get ATR for dynamic thresholds
   double atr = 0;
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         atr = atr_buffer[0];
      }
      IndicatorRelease(atr_handle);
   }

   // Use ATR for breakout thresholds
   double upper_breakout = g_channel_upper + (atr * 0.5);
   double lower_breakout = g_channel_lower - (atr * 0.5);

   // Check for significant breakout
   if(close > upper_breakout || close < lower_breakout)
   {
      if(!g_channel_breakout)  // New breakout
      {
         g_channel_breakout = true;
         g_breakout_price = close;
         g_bars_since_breakout = 0;

         // Force channel reset on confirmed breakout
         g_channel_upper = 0;
         g_channel_lower = 0;

         if(EnableDebugLogs)
         {
            Print("\n=== Breakout Detected ===");
            Print("Price: ", close);
            Print("Channel width: ", g_channel_width);
            Print("ATR: ", atr);
            Print("Breakout distance: ", MathAbs(close - (close > upper_breakout ? g_channel_upper : g_channel_lower)));
         }
      }
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Reset channel after confirmed breakout                            |
//+------------------------------------------------------------------+
void ResetChannelAfterBreakout()
{
   if(!g_channel_breakout) return;

   g_bars_since_breakout++;
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);

   // Wait for price to stabilize (minimum 5 bars) and confirm new trend
   if(g_bars_since_breakout >= 5)
   {
      bool trend_confirmed = false;

      if(close > g_channel_upper)
      {
         // Confirm upward breakout
         double lowest_since_breakout = close;
         for(int i = 1; i < g_bars_since_breakout; i++)
         {
            lowest_since_breakout = MathMin(lowest_since_breakout, iLow(_Symbol, PERIOD_CURRENT, i));
         }
         trend_confirmed = lowest_since_breakout > g_channel_upper;
      }
      else if(close < g_channel_lower)
      {
         // Confirm downward breakout
         double highest_since_breakout = close;
         for(int i = 1; i < g_bars_since_breakout; i++)
         {
            highest_since_breakout = MathMax(highest_since_breakout, iHigh(_Symbol, PERIOD_CURRENT, i));
         }
         trend_confirmed = highest_since_breakout < g_channel_lower;
      }

      if(trend_confirmed)
      {
         if(EnableDebugLogs)
         {
            Print("Resetting channel after confirmed breakout");
            Print("Bars since breakout: ", g_bars_since_breakout);
            Print("Original breakout price: ", g_breakout_price);
            Print("Current price: ", close);
         }

         // Reset channel
         g_channel_upper = 0;
         g_channel_lower = 0;
         g_channel_breakout = false;
         g_last_channel_reset = TimeCurrent();

         // Clean up old channel lines
         ObjectDelete(0, g_channel_upper_name);
         ObjectDelete(0, g_channel_lower_name);
         g_channel_upper_name = "";
         g_channel_lower_name = "";

         // Reset trend line
         ObjectDelete(0, "TrendLine" + IntegerToString(g_trend_line_id));
         g_trend_line_id++;
      }
   }
}

//+------------------------------------------------------------------+
//| Check RSI conditions                                              |
//+------------------------------------------------------------------+
bool CheckRSIConditions(bool is_buy)
{
   if(!UseRSIFilter) return true;

   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(g_rsi_handle, 0, 0, 2, rsi) <= 0)
   {
      Print("Failed to copy RSI data");
      return false;
   }

   if(is_buy)
   {
      return rsi[1] < RSIOversold;  // Previous completed candle
   }
   else
   {
      return rsi[1] > RSIOverbought;
   }
}

//+------------------------------------------------------------------+
//| Check channel conditions                                          |
//+------------------------------------------------------------------+
bool CheckChannelConditions()
{
   if(g_channel_upper == 0 || g_channel_lower == 0) return false;

   double channel_width = g_channel_upper - g_channel_lower;

   if(EnableDebugLogs)
   {
      Print("Channel width: ", channel_width);
      Print("Minimum required: ", MinChannelWidth);
      Print("Maximum allowed: ", MaxChannelWidth);
   }

   return channel_width >= MinChannelWidth && channel_width <= MaxChannelWidth;
}

//+------------------------------------------------------------------+
//| Check trend alignment across timeframes                           |
//+------------------------------------------------------------------+
bool CheckMultiTimeframeTrend(bool is_buy)
{
   if(!UseMultiTimeframe) return true;

   ENUM_TIMEFRAMES higher_tf = GetHigherTimeframe(Period());
   if(higher_tf == PERIOD_CURRENT) return true;

   // Get MA values for higher timeframe
   int ma_handle = iMA(_Symbol, higher_tf, 20, 0, MODE_SMA, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE) return false;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(ma_handle, 0, 0, 2, ma) <= 0)
   {
      IndicatorRelease(ma_handle);
      return false;
   }
   IndicatorRelease(ma_handle);

   double current_price = iClose(_Symbol, higher_tf, 0);

   if(is_buy)
   {
      return current_price > ma[0] && ma[0] > ma[1];  // Price above MA and MA rising
   }
   else
   {
      return current_price < ma[0] && ma[0] < ma[1];  // Price below MA and MA falling
   }
}

//+------------------------------------------------------------------+
//| Get next higher timeframe                                         |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetHigherTimeframe(ENUM_TIMEFRAMES current_tf)
{
   switch(current_tf)
   {
      case PERIOD_M1:  return PERIOD_M5;
      case PERIOD_M5:  return PERIOD_M15;
      case PERIOD_M15: return PERIOD_M30;
      case PERIOD_M30: return PERIOD_H1;
      case PERIOD_H1:  return PERIOD_H4;
      case PERIOD_H4:  return PERIOD_D1;
      default:         return current_tf;
   }
}

//+------------------------------------------------------------------+
//| Get current RSI value                                             |
//+------------------------------------------------------------------+
double GetCurrentRSI()
{
   if(!UseRSIFilter) return 50.0;

   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(g_rsi_handle, 0, 0, 1, rsi) <= 0)
      return 50.0;

   return rsi[0];
}
