//+------------------------------------------------------------------+
//|                                           xauusd-strategy-5.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Asian Session Box Strategy                  |
//| Description:                                                       |
//|   A trading strategy for XAUUSD (Gold) that trades based on the    |
//|   Asian session box breakout. It identifies key levels during the  |
//|   Asian session and trades breakouts during London/NY sessions.    |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Price breaks above Asian session high                     |
//|   - SELL: Price breaks below Asian session low                     |
//|   - Only trades during London/NY sessions                          |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Fixed take profit based on box size                           |
//|   - Stop loss at opposite side of the box                         |
//|   - Session-based exits                                           |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Position sizing based on box size                             |
//|   - Maximum risk per trade limit                                  |
//|   - Session-based risk controls                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"

// Include necessary files
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>

// Create trade object
CTrade trade;

// Input Parameters for Moving Averages
input group "Moving Average Settings"
input int      MA_Period = 55;              // MA Period for Channel
input ENUM_MA_METHOD MA_Method = MODE_SMA;  // MA Method
input ENUM_APPLIED_PRICE MA_Price_High = PRICE_HIGH;  // MA Applied Price (High)
input ENUM_APPLIED_PRICE MA_Price_Low = PRICE_LOW;    // MA Applied Price (Low)
input ENUM_TIMEFRAMES HTF = PERIOD_H4;      // Higher Timeframe for 200 MA
input int      HTF_MA_Period = 200;         // Higher Timeframe MA Period
input bool     UseHTFFilter = true;         // Use Higher Timeframe MA Filter

// Input Parameters for Trading Direction
input group "Trading Direction"
input bool     OnlyLongTrades = true;      // Only Take Long Trades

// Input Parameters for Risk Management
input group "Risk Management"
input double   RiskPercent = 0.5;           // Risk per trade (%)
input double   RR_Ratio = 1.5;              // Risk:Reward ratio
input bool     UseATRStopLoss = true;       // Use ATR for Stop Loss
input double   ATR_Multiplier = 2.5;        // ATR Multiplier for Stop Loss
input int      ATR_Period = 14;             // ATR Period
input bool     UsePartialClose = true;      // Use Partial Close at Target
input double   PartialClosePercent = 50.0;  // Percentage to Close at Target

// Input Parameters for Session Trading
input group "Trading Sessions"
input bool     TradeAsianSession = true;    // Trade Asian Session
input int      AsianSessionStartHour = 1;   // Asian Session Start Hour (Server Time)
input int      AsianSessionEndHour = 10;    // Asian Session End Hour (Server Time)
input bool     TradeNYSession = true;       // Trade New York Session
input int      NYSessionStartHour = 13;     // NY Session Start Hour (Server Time)
input int      NYSessionEndHour = 22;       // NY Session End Hour (Server Time)

// Global Variables
int ma_high_handle;        // Handle for High MA
int ma_low_handle;         // Handle for Low MA
int htf_ma_handle;         // Handle for HTF MA
int atr_handle;           // Handle for ATR
int heiken_handle;        // Handle for Heiken Ashi
datetime lastTradeTime;   // Time of last trade
bool inTrade = false;     // Flag for open position

// Structure for Heiken Ashi values
struct HeikenAshi {
   double open;
   double high;
   double low;
   double close;
};

// Add global variable for tracking partial closes
ulong partialClosedTickets[];  // Array to store tickets of partially closed positions

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade settings
   trade.SetExpertMagicNumber(555555);  // Unique identifier for this EA
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);

   // Initialize indicators
   ma_high_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MA_Method, MA_Price_High);
   ma_low_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MA_Method, MA_Price_Low);
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   heiken_handle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi");

   if(UseHTFFilter)
      htf_ma_handle = iMA(_Symbol, HTF, HTF_MA_Period, 0, MODE_SMA, PRICE_CLOSE);

   // Check if indicators were created successfully
   if(ma_high_handle == INVALID_HANDLE || ma_low_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE || heiken_handle == INVALID_HANDLE ||
      (UseHTFFilter && htf_ma_handle == INVALID_HANDLE))
   {
      Print("Error creating indicators!");
      return INIT_FAILED;
   }

   // Initialize position tracking array
   ArrayResize(partialClosedTickets, 0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up indicator handles
   IndicatorRelease(ma_high_handle);
   IndicatorRelease(ma_low_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(heiken_handle);
   if(UseHTFFilter)
      IndicatorRelease(htf_ma_handle);
}

//+------------------------------------------------------------------+
//| Get Heiken Ashi values                                            |
//+------------------------------------------------------------------+
HeikenAshi GetHeikenAshiValues(int shift)
{
   HeikenAshi ha;
   double haBuffer[];  // Change to 1D array
   ArraySetAsSeries(haBuffer, true);

   // Copy Heiken Ashi values - adjust buffer copying
   if(CopyBuffer(heiken_handle, 0, shift, 1, haBuffer) > 0)
   {
      ha.open = haBuffer[0];    // Open from buffer 0
   }
   if(CopyBuffer(heiken_handle, 1, shift, 1, haBuffer) > 0)
   {
      ha.high = haBuffer[0];    // High from buffer 1
   }
   if(CopyBuffer(heiken_handle, 2, shift, 1, haBuffer) > 0)
   {
      ha.low = haBuffer[0];     // Low from buffer 2
   }
   if(CopyBuffer(heiken_handle, 3, shift, 1, haBuffer) > 0)
   {
      ha.close = haBuffer[0];   // Close from buffer 3
   }

   return ha;
}

//+------------------------------------------------------------------+
//| Check if current time is within allowed trading sessions           |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentHour = now.hour;

   bool asianSessionActive = TradeAsianSession &&
                           currentHour >= AsianSessionStartHour &&
                           currentHour < AsianSessionEndHour;

   bool nySessionActive = TradeNYSession &&
                        currentHour >= NYSessionStartHour &&
                        currentHour < NYSessionEndHour;

   return asianSessionActive || nySessionActive;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize == 0) return 0;

   double riskPerLot = (stopLossPoints / tickSize) * tickValue;
   if(riskPerLot == 0) return 0;

   double lotSize = riskAmount / riskPerLot;

   // Apply limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we're in a valid trading session
   if(!IsValidTradingSession())
      return;

   // Get indicator values
   double ma_high[], ma_low[], atr[], htf_ma[];
   ArraySetAsSeries(ma_high, true);
   ArraySetAsSeries(ma_low, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(htf_ma, true);

   // Copy indicator values
   if(CopyBuffer(ma_high_handle, 0, 0, 2, ma_high) <= 0 ||
      CopyBuffer(ma_low_handle, 0, 0, 2, ma_low) <= 0 ||
      CopyBuffer(atr_handle, 0, 0, 1, atr) <= 0)
      return;

   // Get current price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get Heiken Ashi values for current and previous candles
   HeikenAshi currentHA = GetHeikenAshiValues(0);
   HeikenAshi previousHA = GetHeikenAshiValues(1);

   // Check if price is within the channel
   bool inChannel = currentPrice > ma_low[0] && currentPrice < ma_high[0];

   // Get HTF trend if filter is enabled
   bool htfTrendAligned = true;
   if(UseHTFFilter)
   {
      if(CopyBuffer(htf_ma_handle, 0, 0, 1, htf_ma) > 0)
      {
         htfTrendAligned = (currentPrice > htf_ma[0] && currentHA.close > currentHA.open) ||  // Bullish alignment
                          (!OnlyLongTrades && currentPrice < htf_ma[0] && currentHA.close < currentHA.open);  // Bearish alignment (if shorts allowed)
      }
   }

   // Manage open positions
   if(PositionsTotal() > 0)
   {
      ManagePositions(currentHA);
      return;
   }

   // Skip if price is within the channel
   if(inChannel)
      return;

   // Calculate ATR-based stop loss
   double atrStopLoss = atr[0] * ATR_Multiplier;

   // Check for buy setup
   if(currentPrice > ma_high[0] &&                    // Price above upper channel
      currentHA.close > currentHA.open &&             // Green Heiken Ashi candle
      previousHA.close > previousHA.open &&           // Previous candle also green
      (!UseHTFFilter || currentPrice > htf_ma[0]))    // Above HTF MA if filter enabled
   {
      double stopLoss = UseATRStopLoss ? currentPrice - atrStopLoss : previousHA.low;
      double takeProfit = currentPrice + (currentPrice - stopLoss) * RR_Ratio;

      double lotSize = CalculateLotSize(MathAbs(currentPrice - stopLoss) / _Point);

      if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "XAUUSD-Strat5"))
      {
         Print("Buy order placed - Entry: ", currentPrice, " SL: ", stopLoss, " TP: ", takeProfit);
         inTrade = true;
         lastTradeTime = TimeCurrent();
      }
   }

   // Check for sell setup - only if shorts are allowed
   else if(!OnlyLongTrades &&                        // Only if shorts are allowed
           currentPrice < ma_low[0] &&                // Price below lower channel
           currentHA.close < currentHA.open &&        // Red Heiken Ashi candle
           previousHA.close < previousHA.open &&      // Previous candle also red
           (!UseHTFFilter || currentPrice < htf_ma[0])) // Below HTF MA if filter enabled
   {
      double stopLoss = UseATRStopLoss ? currentPrice + atrStopLoss : previousHA.high;
      double takeProfit = currentPrice - (stopLoss - currentPrice) * RR_Ratio;

      double lotSize = CalculateLotSize(MathAbs(stopLoss - currentPrice) / _Point);

      if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "XAUUSD-Strat5"))
      {
         Print("Sell order placed - Entry: ", currentPrice, " SL: ", stopLoss, " TP: ", takeProfit);
         inTrade = true;
         lastTradeTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManagePositions(HeikenAshi &currentHA)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionSelectByTicket(ticket))
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double stopLoss = PositionGetDouble(POSITION_SL);
         double takeProfit = PositionGetDouble(POSITION_TP);
         double positionProfit = PositionGetDouble(POSITION_PROFIT);
         double positionVolume = PositionGetDouble(POSITION_VOLUME);

         // Check for trend reversal based on Heiken Ashi
         bool trendReversed = (posType == POSITION_TYPE_BUY && currentHA.close < currentHA.open) ||
                            (!OnlyLongTrades && posType == POSITION_TYPE_SELL && currentHA.close > currentHA.open);

         // Calculate if we've reached the partial take profit level
         double profitTarget = MathAbs(takeProfit - openPrice) * 0.5;  // 50% of the way to take profit
         bool targetReached = (posType == POSITION_TYPE_BUY && currentPrice >= openPrice + profitTarget) ||
                            (!OnlyLongTrades && posType == POSITION_TYPE_SELL && currentPrice <= openPrice - profitTarget);

         // Check if position was already partially closed
         bool alreadyPartiallyClosed = false;
         for(int j = 0; j < ArraySize(partialClosedTickets); j++)
         {
            if(partialClosedTickets[j] == ticket)
            {
               alreadyPartiallyClosed = true;
               break;
            }
         }

         // Handle partial close and move stop to break even
         if(UsePartialClose && targetReached && !alreadyPartiallyClosed)
         {
            double volumeToClose = positionVolume * PartialClosePercent / 100.0;
            if(trade.PositionClosePartial(ticket, volumeToClose))
            {
               // Move stop loss to break even
               trade.PositionModify(ticket, openPrice, takeProfit);

               // Add ticket to partially closed array
               int size = ArraySize(partialClosedTickets);
               ArrayResize(partialClosedTickets, size + 1);
               partialClosedTickets[size] = ticket;

               Print("Partial close executed and stop moved to break even");
            }
         }

         // Close position if trend reverses after partial close
         if(trendReversed && currentPrice > openPrice)
         {
            trade.PositionClose(ticket);
            Print("Position closed due to trend reversal");

            // Remove ticket from partially closed array if it exists
            for(int j = 0; j < ArraySize(partialClosedTickets); j++)
            {
               if(partialClosedTickets[j] == ticket)
               {
                  ArrayRemove(partialClosedTickets, j, 1);
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper function to remove element from array                       |
//+------------------------------------------------------------------+
void ArrayRemove(ulong &arr[], int pos, int count)
{
   int total = ArraySize(arr);
   for(int i = pos; i < total - count; i++)
   {
      arr[i] = arr[i + count];
   }
   ArrayResize(arr, total - count);
}
