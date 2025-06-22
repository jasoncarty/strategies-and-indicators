//+------------------------------------------------------------------+
//|                                           xauusd-strategy-1.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Trend Following Strategy                    |
//| Description:                                                       |
//|   A basic trend following strategy for XAUUSD (Gold) that uses     |
//|   moving averages and momentum indicators to identify and trade    |
//|   with the prevailing trend.                                       |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Price above MA with positive momentum                     |
//|   - SELL: Price below MA with negative momentum                    |
//|   - Momentum confirmation using RSI                                |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Moving average crossover                                       |
//|   - Fixed take profit and stop loss                               |
//|   - RSI reversal signals                                          |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Fixed position sizing                                         |
//|   - Basic money management rules                                  |
//|   - Maximum open positions limit                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Trading parameters
input double   RiskPercent = 1.0;          // Risk percent per trade
input int      ATRPeriod = 14;             // ATR Period
input double   ATRMultiplier = 1.5;        // ATR Multiplier for stops
input int      EMAPeriod1 = 13;            // Fast EMA Period (adjusted for better trend detection)
input int      EMAPeriod2 = 34;            // Medium EMA Period (adjusted for better trend detection)
input int      EMAPeriod3 = 89;            // Slow EMA Period (adjusted for better trend detection)
input int      RSIPeriod = 14;             // RSI Period
input double   RSIUpperThreshold = 60;     // RSI upper threshold for trend following (adjusted)
input double   RSILowerThreshold = 40;     // RSI lower threshold for trend following (adjusted)
input bool     UseNewsFilter = true;        // Use news filter
input int      NewsMinutesBefore = 30;     // Minutes before news to stop trading
input int      NewsMinutesAfter = 30;      // Minutes after news to resume trading
input bool     UseVolatilityFilter = true;  // Use volatility filter
input double   MinATR = 0.5;               // Minimum ATR value for XAUUSD
input double   MaxATR = 25.0;              // Maximum ATR value for XAUUSD
input bool     UseSessionFilter = true;     // Use session filter
input bool     TradeLondonSession = true;   // Trade London session
input bool     TradeNewYorkSession = true;  // Trade New York session
input int      MaxSpread = 50;             // Maximum allowed spread in points

// Session times (server time)
input int      LondonOpenHour = 8;         // London session open hour
input int      LondonCloseHour = 16;       // London session close hour
input int      NewYorkOpenHour = 13;       // New York session open hour
input int      NewYorkCloseHour = 21;      // New York session close hour

// Risk management
input bool     UseBreakEven = true;        // Use break even
input double   BreakEvenProfit = 1.0;      // Points to move stop to break even (reduced)
input bool     UseTrailingStop = true;     // Use trailing stop
input double   TrailingStart = 1.5;        // Points to start trailing (reduced)
input double   TrailingStep = 0.3;         // Trailing step in points (reduced for smoother trailing)

// Additional trend confirmation
input bool     UseVolumeTrend = true;      // Use volume for trend confirmation
input int      VolumePeriod = 20;          // Period for volume MA

// Global variables
CTrade trade;
int g_atr_handle;
int g_ema1_handle;
int g_ema2_handle;
int g_ema3_handle;
int g_rsi_handle;
datetime g_last_bar_time;
bool g_trend_up = false;
bool g_trend_down = false;
int g_volume_ma_handle;
bool g_volume_trend_up = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicator handles
   g_atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   g_ema1_handle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod1, 0, MODE_EMA, PRICE_CLOSE);
   g_ema2_handle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod2, 0, MODE_EMA, PRICE_CLOSE);
   g_ema3_handle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod3, 0, MODE_EMA, PRICE_CLOSE);
   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);

   // Initialize volume MA handle
   if(UseVolumeTrend)
      g_volume_ma_handle = iMA(_Symbol, PERIOD_CURRENT, VolumePeriod, 0, MODE_SMA, VOLUME_REAL);

   if(g_atr_handle == INVALID_HANDLE || g_ema1_handle == INVALID_HANDLE ||
      g_ema2_handle == INVALID_HANDLE || g_ema3_handle == INVALID_HANDLE ||
      g_rsi_handle == INVALID_HANDLE ||
      (UseVolumeTrend && g_volume_ma_handle == INVALID_HANDLE))
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   // Set up trade object
   trade.SetExpertMagicNumber(123456);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(g_atr_handle);
   IndicatorRelease(g_ema1_handle);
   IndicatorRelease(g_ema2_handle);
   IndicatorRelease(g_ema3_handle);
   IndicatorRelease(g_rsi_handle);
   if(UseVolumeTrend)
      IndicatorRelease(g_volume_ma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar_time == g_last_bar_time)
   {
      ManagePositions();
      return;
   }
   g_last_bar_time = current_bar_time;

   // Basic checks
   if(!IsTradeAllowed())
   {
      Print("Trade not allowed at ", TimeToString(TimeCurrent()));
      return;
   }
   if(!IsMarketConditionsSuitable())
   {
      Print("Market conditions not suitable at ", TimeToString(TimeCurrent()));
      return;
   }

   // Get indicator values
   double atr[], ema1[], ema2[], ema3[], rsi[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ema1, true);
   ArraySetAsSeries(ema2, true);
   ArraySetAsSeries(ema3, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(g_atr_handle, 0, 0, 2, atr) <= 0)
   {
      Print("Failed to copy ATR buffer");
      return;
   }
   if(CopyBuffer(g_ema1_handle, 0, 0, 2, ema1) <= 0)
   {
      Print("Failed to copy EMA1 buffer");
      return;
   }
   if(CopyBuffer(g_ema2_handle, 0, 0, 2, ema2) <= 0)
   {
      Print("Failed to copy EMA2 buffer");
      return;
   }
   if(CopyBuffer(g_ema3_handle, 0, 0, 2, ema3) <= 0)
   {
      Print("Failed to copy EMA3 buffer");
      return;
   }
   if(CopyBuffer(g_rsi_handle, 0, 0, 2, rsi) <= 0)
   {
      Print("Failed to copy RSI buffer");
      return;
   }

   // Update trend status
   UpdateTrendStatus(ema1[0], ema2[0], ema3[0]);

   // Print debug information
   if(PositionsTotal() == 0)
   {
      Print("Current conditions - ATR: ", atr[0], " RSI: ", rsi[0],
            " EMAs: ", ema1[0], "/", ema2[0], "/", ema3[0],
            " Trend Up: ", g_trend_up, " Trend Down: ", g_trend_down,
            " Volume Trend Up: ", g_volume_trend_up);

      // Modified entry conditions with stronger confirmation
      if(g_trend_up)  // Uptrend
      {
         if(rsi[0] < RSIUpperThreshold && rsi[0] > RSILowerThreshold)  // RSI in optimal range
         {
            Print("Attempting to open BUY position in uptrend, RSI: ", rsi[0]);
            OpenBuy(atr[0]);
         }
         else
         {
            Print("Uptrend detected but RSI outside optimal range: ", rsi[0]);
         }
      }
      else if(g_trend_down)  // Downtrend
      {
         if(rsi[0] > RSILowerThreshold && rsi[0] < RSIUpperThreshold)  // RSI in optimal range
         {
            Print("Attempting to open SELL position in downtrend, RSI: ", rsi[0]);
            OpenSell(atr[0]);
         }
         else
         {
            Print("Downtrend detected but RSI outside optimal range: ", rsi[0]);
         }
      }
      else
      {
         Print("No clear trend detected");
      }
   }

   ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                       |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   // Check spread
   double current_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(current_spread > MaxSpread)
   {
      Print("Spread too high: ", current_spread);
      return false;
   }

   // Check session
   if(UseSessionFilter && !IsActiveSession())
   {
      Print("Not in active session");
      return false;
   }

   // Check news
   if(UseNewsFilter && IsNewsTime())
   {
      Print("News filter active");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within active trading session            |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int current_hour = time.hour;

   bool london_active = TradeLondonSession &&
                       current_hour >= LondonOpenHour &&
                       current_hour < LondonCloseHour;

   bool ny_active = TradeNewYorkSession &&
                   current_hour >= NewYorkOpenHour &&
                   current_hour < NewYorkCloseHour;

   return london_active || ny_active;
}

//+------------------------------------------------------------------+
//| Check if it's news time                                          |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   // This is a placeholder for news checking logic
   // You would need to implement actual news checking based on your data source
   return false;
}

//+------------------------------------------------------------------+
//| Check if market conditions are suitable for trading               |
//+------------------------------------------------------------------+
bool IsMarketConditionsSuitable()
{
   if(!UseVolatilityFilter) return true;

   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(g_atr_handle, 0, 0, 1, atr) <= 0)
   {
      Print("Failed to copy ATR for market conditions check");
      return false;
   }

   Print("Current ATR: ", atr[0], " Min ATR: ", MinATR, " Max ATR: ", MaxATR);
   return (atr[0] >= MinATR && atr[0] <= MaxATR);
}

//+------------------------------------------------------------------+
//| Update trend status based on EMAs and volume                      |
//+------------------------------------------------------------------+
void UpdateTrendStatus(double ema1, double ema2, double ema3)
{
   g_trend_up = (ema1 > ema2) && (ema2 > ema3);
   g_trend_down = (ema1 < ema2) && (ema2 < ema3);

   if(UseVolumeTrend)
   {
      double volume[], volume_ma[];
      ArraySetAsSeries(volume, true);
      ArraySetAsSeries(volume_ma, true);

      if(CopyBuffer(VOLUME_REAL, 0, 0, 2, volume) > 0 &&
         CopyBuffer(g_volume_ma_handle, 0, 0, 2, volume_ma) > 0)
      {
         g_volume_trend_up = volume[0] > volume_ma[0];

         // Adjust trend signals based on volume
         g_trend_up = g_trend_up && g_volume_trend_up;
         g_trend_down = g_trend_down && !g_volume_trend_up;
      }
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
//| Open buy position                                                 |
//+------------------------------------------------------------------+
void OpenBuy(double atr)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stop_loss = entry - (atr * ATRMultiplier);
   double take_profit = entry + (atr * ATRMultiplier * 1.5);

   double lot_size = CalculateLotSize(entry - stop_loss);
   if(lot_size == 0) return;

   trade.Buy(lot_size, _Symbol, 0, stop_loss, take_profit, "XAUUSD Strategy 1");
}

//+------------------------------------------------------------------+
//| Open sell position                                                |
//+------------------------------------------------------------------+
void OpenSell(double atr)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_loss = entry + (atr * ATRMultiplier);
   double take_profit = entry - (atr * ATRMultiplier * 1.5);

   double lot_size = CalculateLotSize(stop_loss - entry);
   if(lot_size == 0) return;

   trade.Sell(lot_size, _Symbol, 0, stop_loss, take_profit, "XAUUSD Strategy 1");
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
      double stop_loss = PositionGetDouble(POSITION_SL);
      double take_profit = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Break even logic
      if(UseBreakEven && stop_loss != entry)
      {
         double profit_distance = type == POSITION_TYPE_BUY ?
                                current_price - entry :
                                entry - current_price;

         if(profit_distance >= BreakEvenProfit)
         {
            trade.PositionModify(ticket, entry, take_profit);
         }
      }

      // Trailing stop logic
      if(UseTrailingStop)
      {
         double profit_distance = type == POSITION_TYPE_BUY ?
                                current_price - entry :
                                entry - current_price;

         if(profit_distance >= TrailingStart)
         {
            double new_stop = type == POSITION_TYPE_BUY ?
                            current_price - TrailingStep :
                            current_price + TrailingStep;

            if((type == POSITION_TYPE_BUY && new_stop > stop_loss) ||
               (type == POSITION_TYPE_SELL && new_stop < stop_loss))
            {
               trade.PositionModify(ticket, new_stop, take_profit);
            }
         }
      }
   }
}
