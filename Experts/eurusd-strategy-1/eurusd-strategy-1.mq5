//+------------------------------------------------------------------+
//|                                           eurusd-strategy-1.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: EURUSD Session-Based Strategy                      |
//| Description:                                                       |
//|   A trading strategy for EURUSD that capitalizes on session        |
//|   transitions and volatility patterns during key trading hours.    |
//|   It focuses on London and NY session overlaps.                    |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY/SELL: Session transition breakouts                         |
//|   - Volume surge confirmation                                      |
//|   - Price action patterns at key levels                           |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Session-based time exits                                      |
//|   - Fixed take profit and stop loss                               |
//|   - Volatility-based trailing stops                               |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Session-specific position sizing                              |
//|   - Time-based risk adjustments                                   |
//|   - Maximum positions per session                                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Input Parameters
input group "Strategy Settings"
input ENUM_TIMEFRAMES TimeframeToTrade = PERIOD_H1;  // Trading timeframe
input bool     EnableDebugLogs = true;   // Enable detailed debug logging

input group "Trend Parameters"
input int      MA_Fast = 8;             // Fast MA period
input int      MA_Medium = 21;          // Medium MA period
input ENUM_MA_METHOD MA_Method = MODE_EMA;  // MA method
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE;  // MA price type

input group "RSI Parameters"
input int      RSI_Period = 14;         // RSI period
input int      RSI_Overbought = 70;     // RSI overbought level
input int      RSI_Oversold = 30;       // RSI oversold level

input group "Risk Management"
input double   RiskPercent = 0.5;       // Risk percent per trade
input double   RewardRatio = 1.5;       // Reward:Risk ratio
input int      MaxSpread = 20;          // Maximum spread in points
input bool     UseTrailingStop = true;  // Use trailing stop
input double   TrailingStart = 30;      // Pips to start trailing
input double   TrailingStep = 10;       // Trailing step in pips

// Global variables
CTrade trade;
int g_ma_fast_handle;
int g_ma_medium_handle;
int g_rsi_handle;
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   g_ma_fast_handle = iMA(_Symbol, TimeframeToTrade, MA_Fast, 0, MA_Method, MA_Price);
   g_ma_medium_handle = iMA(_Symbol, TimeframeToTrade, MA_Medium, 0, MA_Method, MA_Price);
   g_rsi_handle = iRSI(_Symbol, TimeframeToTrade, RSI_Period, PRICE_CLOSE);

   if(g_ma_fast_handle == INVALID_HANDLE || g_ma_medium_handle == INVALID_HANDLE ||
      g_rsi_handle == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
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
   IndicatorRelease(g_ma_fast_handle);
   IndicatorRelease(g_ma_medium_handle);
   IndicatorRelease(g_rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_bar_time = iTime(_Symbol, TimeframeToTrade, 0);
   if(current_bar_time == g_last_bar_time)
   {
      ManagePositions();
      return;
   }
   g_last_bar_time = current_bar_time;

   if(!IsSpreadOK())
   {
      if(EnableDebugLogs) Print("Spread too high: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      return;
   }

   if(PositionsTotal() == 0)
   {
      CheckForEntry();
   }

   ManagePositions();
}

//+------------------------------------------------------------------+
//| Check for new trade entry                                         |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double ma_fast[], ma_medium[], rsi[], close[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_medium, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(g_ma_fast_handle, 0, 0, 3, ma_fast) <= 0 ||
      CopyBuffer(g_ma_medium_handle, 0, 0, 3, ma_medium) <= 0 ||
      CopyBuffer(g_rsi_handle, 0, 0, 2, rsi) <= 0 ||
      CopyClose(_Symbol, TimeframeToTrade, 0, 3, close) <= 0)
      return;

   // Buy Conditions
   bool ma_crossover_buy = ma_fast[1] <= ma_medium[1] && ma_fast[0] > ma_medium[0];
   bool rsi_buy = rsi[0] < RSI_Oversold;
   bool price_momentum_buy = close[0] > close[1];

   // Sell Conditions
   bool ma_crossover_sell = ma_fast[1] >= ma_medium[1] && ma_fast[0] < ma_medium[0];
   bool rsi_sell = rsi[0] > RSI_Overbought;
   bool price_momentum_sell = close[0] < close[1];

   if(EnableDebugLogs)
   {
      Print("\n=== Entry Conditions ===");
      Print("MA Crossover Buy: ", ma_crossover_buy);
      Print("RSI Buy: ", rsi_buy);
      Print("Price Momentum Buy: ", price_momentum_buy);
      Print("MA Crossover Sell: ", ma_crossover_sell);
      Print("RSI Sell: ", rsi_sell);
      Print("Price Momentum Sell: ", price_momentum_sell);
   }

   // Entry decisions
   if(ma_crossover_buy && (rsi_buy || price_momentum_buy))
   {
      OpenBuy();
   }
   else if(ma_crossover_sell && (rsi_sell || price_momentum_sell))
   {
      OpenSell();
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                 |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = GetATR();

   if(atr == 0) return;

   double stop_loss = entry - (atr * 1.5);
   double take_profit = entry + ((entry - stop_loss) * RewardRatio);

   double lot_size = CalculateLotSize(entry - stop_loss);
   if(lot_size == 0) return;

   if(EnableDebugLogs)
   {
      Print("\n=== Opening Buy Position ===");
      Print("Entry: ", entry);
      Print("Stop Loss: ", stop_loss);
      Print("Take Profit: ", take_profit);
      Print("Lot Size: ", lot_size);
   }

   trade.Buy(lot_size, _Symbol, 0, stop_loss, take_profit, "EURUSD Strategy");
}

//+------------------------------------------------------------------+
//| Open sell position                                                |
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = GetATR();

   if(atr == 0) return;

   double stop_loss = entry + (atr * 1.5);
   double take_profit = entry - ((stop_loss - entry) * RewardRatio);

   double lot_size = CalculateLotSize(stop_loss - entry);
   if(lot_size == 0) return;

   if(EnableDebugLogs)
   {
      Print("\n=== Opening Sell Position ===");
      Print("Entry: ", entry);
      Print("Stop Loss: ", stop_loss);
      Print("Take Profit: ", take_profit);
      Print("Lot Size: ", lot_size);
   }

   trade.Sell(lot_size, _Symbol, 0, stop_loss, take_profit, "EURUSD Strategy");
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                     |
//+------------------------------------------------------------------+
double GetATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);

   int atr_handle = iATR(_Symbol, TimeframeToTrade, 14);
   if(atr_handle == INVALID_HANDLE) return 0;

   if(CopyBuffer(atr_handle, 0, 0, 1, atr) <= 0)
   {
      IndicatorRelease(atr_handle);
      return 0;
   }

   double atr_value = atr[0];
   IndicatorRelease(atr_handle);
   return atr_value;
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

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   return lot_size;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spread <= MaxSpread;
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

      // Trailing stop logic
      if(UseTrailingStop)
      {
         double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
         double profit_distance = type == POSITION_TYPE_BUY ?
                                current_price - entry :
                                entry - current_price;

         if(profit_distance >= TrailingStart * pip_value)
         {
            double new_stop = type == POSITION_TYPE_BUY ?
                            current_price - (TrailingStep * pip_value) :
                            current_price + (TrailingStep * pip_value);

            if((type == POSITION_TYPE_BUY && new_stop > stop_loss) ||
               (type == POSITION_TYPE_SELL && new_stop < stop_loss))
            {
               trade.PositionModify(ticket, new_stop, take_profit);
            }
         }
      }
   }
}
