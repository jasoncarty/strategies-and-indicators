//+------------------------------------------------------------------+
//|                                           xauusd-strategy-3.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Bollinger Bands Strategy                    |
//| Description:                                                       |
//|   A trading strategy for XAUUSD (Gold) that uses Bollinger Bands   |
//|   for mean reversion trades. It identifies potential reversals     |
//|   when price reaches extreme levels relative to the bands.         |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Price touches lower band with RSI confirmation           |
//|   - SELL: Price touches upper band with RSI confirmation          |
//|   - Additional trend filter using band width                      |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Price reaches middle band                                     |
//|   - Fixed take profit at opposite band                            |
//|   - Time-based exits                                              |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Dynamic position sizing based on volatility                   |
//|   - Maximum risk per trade                                        |
//|   - Volatility-based filters                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Input Parameters
input group "EMA Settings"
input int      EMA_Fast = 50;           // Fast EMA period
input int      EMA_Slow = 200;          // Slow EMA period
input ENUM_APPLIED_PRICE EMA_Price = PRICE_CLOSE;  // EMA price type

input group "RSI Settings"
input int      RSI_Period = 14;         // RSI period
input double   RSI_BuyLevel = 40;       // RSI buy level
input double   RSI_SellLevel = 60;      // RSI sell level

input group "Risk Management"
input double   RiskPercent = 1.0;       // Risk percent per trade
input double   RewardRatio = 2.0;       // Reward:Risk ratio
input bool     UseBreakEven = true;     // Use break even
input double   BreakEvenProfit = 1.0;   // Points to move stop to break even
input bool     UseTrailingStop = true;  // Use trailing stop
input double   TrailingStart = 2.0;     // Points to start trailing
input double   TrailingStep = 0.5;      // Trailing step

input group "Debug Settings"
input bool     EnableDebugLogs = true;  // Enable detailed debug logging

// Global Variables
CTrade trade;
int g_ema_fast_handle;
int g_ema_slow_handle;
int g_rsi_handle;
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   g_ema_fast_handle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, EMA_Price);
   g_ema_slow_handle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, EMA_Price);
   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);

   if(g_ema_fast_handle == INVALID_HANDLE || g_ema_slow_handle == INVALID_HANDLE || g_rsi_handle == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return INIT_FAILED;
   }

   // Set up trade object
   trade.SetExpertMagicNumber(232323);
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
   // Clean up indicators
   if(g_ema_fast_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_fast_handle);
   if(g_ema_slow_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_slow_handle);
   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only check for new trades on new candle
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar_time == g_last_bar_time)
   {
      ManagePositions();
      return;
   }
   g_last_bar_time = current_bar_time;

   // Get indicator values
   double ema_fast[], ema_slow[], rsi[];
   ArraySetAsSeries(ema_fast, true);
   ArraySetAsSeries(ema_slow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(g_ema_fast_handle, 0, 0, 2, ema_fast) <= 0 ||
      CopyBuffer(g_ema_slow_handle, 0, 0, 2, ema_slow) <= 0 ||
      CopyBuffer(g_rsi_handle, 0, 0, 2, rsi) <= 0)
   {
      Print("Failed to copy indicator data");
      return;
   }

   if(EnableDebugLogs)
   {
      Print("\n=== Strategy Analysis ===");
      Print("Fast EMA (", EMA_Fast, "): ", ema_fast[0]);
      Print("Slow EMA (", EMA_Slow, "): ", ema_slow[0]);
      Print("RSI: ", rsi[0]);
      Print("EMA Cross Status: ", (ema_fast[0] > ema_slow[0] ? "Bullish" : "Bearish"));
   }

   // Check for trade conditions if no positions are open
   if(PositionsTotal() == 0)
   {
      // Buy conditions
      if(ema_fast[0] > ema_slow[0] && rsi[0] <= RSI_BuyLevel)
      {
         if(EnableDebugLogs)
         {
            Print("\n=== Buy Signal ===");
            Print("Fast EMA above Slow EMA");
            Print("RSI below buy level: ", rsi[0], " <= ", RSI_BuyLevel);
         }
         OpenBuy();
      }
      // Sell conditions
      else if(ema_fast[0] < ema_slow[0] && rsi[0] >= RSI_SellLevel)
      {
         if(EnableDebugLogs)
         {
            Print("\n=== Sell Signal ===");
            Print("Fast EMA below Slow EMA");
            Print("RSI above sell level: ", rsi[0], " >= ", RSI_SellLevel);
         }
         OpenSell();
      }
   }

   ManagePositions();
}

//+------------------------------------------------------------------+
//| Open buy position                                                 |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Calculate stop loss based on ATR
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

   double stop_loss = entry - (atr * 1.5);
   double take_profit = entry + ((entry - stop_loss) * RewardRatio);

   double lot_size = CalculateLotSize(entry - stop_loss);
   if(lot_size == 0)
   {
      Print("Buy order rejected - Invalid lot size calculated");
      return;
   }

   if(EnableDebugLogs)
   {
      Print("Opening Buy - Entry: ", entry, " SL: ", stop_loss, " TP: ", take_profit, " Lots: ", lot_size);
   }

   if(!trade.Buy(lot_size, _Symbol, 0, stop_loss, take_profit, "EMA-RSI Strategy"))
   {
      Print("Buy order failed - Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                                |
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate stop loss based on ATR
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

   double stop_loss = entry + (atr * 1.5);
   double take_profit = entry - ((stop_loss - entry) * RewardRatio);

   double lot_size = CalculateLotSize(stop_loss - entry);
   if(lot_size == 0)
   {
      Print("Sell order rejected - Invalid lot size calculated");
      return;
   }

   if(EnableDebugLogs)
   {
      Print("Opening Sell - Entry: ", entry, " SL: ", stop_loss, " TP: ", take_profit, " Lots: ", lot_size);
   }

   if(!trade.Sell(lot_size, _Symbol, 0, stop_loss, take_profit, "EMA-RSI Strategy"))
   {
      Print("Sell order failed - Error: ", GetLastError());
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
            if(EnableDebugLogs) Print("Moving to break even - Ticket: ", ticket);
            if(!trade.PositionModify(ticket, entry, take_profit))
            {
               Print("Break even modification failed - Error: ", GetLastError());
            }
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
               if(EnableDebugLogs) Print("Updating trailing stop - Ticket: ", ticket);
               if(!trade.PositionModify(ticket, new_stop, take_profit))
               {
                  Print("Trailing stop modification failed - Error: ", GetLastError());
               }
            }
         }
      }
   }
}
