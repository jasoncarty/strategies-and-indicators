//+------------------------------------------------------------------+
//| Divergence RSI EA (MT5)                                         |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#property copyright   "Your Name"
#property link        ""
#property version     "1.00"
#property strict

//--- input parameters
input int    RSIPeriod = 14;
input int    SwingLookback = 5;
input double RR = 2.0; // Risk/Reward ratio for TP
input int    MaxLookbackBars = 1000;
input ENUM_TIMEFRAMES HTF = PERIOD_H1;
input double riskPercent = 1.0; // % of balance to risk per trade
input double tpMultiplier = 1.0; // Multiplier for TP distance
input int    maxOrders = 1; // Max open orders at a time
input double ATRMultiplier = 1.5; // Multiplier for ATR-based SL
input int    MinSwingBarDistance = 5; // Minimum bars between swing points
input double MinRSIDiff = 10.0;      // Minimum RSI difference for divergence
input int    TrendMAPeriod = 50;     // MA period for trend filter
input double TrendMAThreshold = 0.0; // Price must be above/below MA by this amount
input ENUM_TIMEFRAMES LTF = PERIOD_M5; // Lower timeframe for entry trigger

//--- global variables
datetime lastLTFBarTime = 0;
datetime lastHTFBarTime = 0;
CTrade trade;
ulong lastClosedTicket = 0;
// Global variables for pending signal
bool pendingBuySignal = false;
bool pendingSellSignal = false;
double pendingHTFPrice = 0.0;
datetime pendingHTFTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime prevHTFBarTime = 0;
   static datetime prevLTFBarTime = 0;

   // Detect new HTF bar (regardless of chart timeframe)
   datetime htfBarTime = iTime(_Symbol, HTF, 0);
   bool htfBarClosed = (htfBarTime != prevHTFBarTime);

   // Detect new LTF bar
   datetime ltfBarTime = iTime(_Symbol, LTF, 0);
   bool ltfBarClosed = (ltfBarTime != prevLTFBarTime);

   // 1. On new HTF bar close, scan for divergence and set pending signal
   if(htfBarClosed)
   {
      prevHTFBarTime = htfBarTime;
      //--- Fetch HTF data (all indicator and price arrays use HTF)
      int htf_bars = MaxLookbackBars + 2*SwingLookback + RSIPeriod + TrendMAPeriod + 10;
      datetime htf_time[]; double htf_open[]; double htf_close[]; double htf_high[]; double htf_low[];
      ArraySetAsSeries(htf_time, true); ArraySetAsSeries(htf_open, true); ArraySetAsSeries(htf_close, true); ArraySetAsSeries(htf_high, true); ArraySetAsSeries(htf_low, true);
      if(CopyTime(_Symbol, HTF, 0, htf_bars, htf_time) <= 0) return;
      if(CopyOpen(_Symbol, HTF, 0, htf_bars, htf_open) <= 0) return;
      if(CopyClose(_Symbol, HTF, 0, htf_bars, htf_close) <= 0) return;
      if(CopyHigh(_Symbol, HTF, 0, htf_bars, htf_high) <= 0) return;
      if(CopyLow(_Symbol, HTF, 0, htf_bars, htf_low) <= 0) return;
      //--- Fetch HTF RSI
      double htf_rsi[]; ArrayResize(htf_rsi, htf_bars);
      int htf_rsi_handle = iRSI(_Symbol, HTF, RSIPeriod, PRICE_CLOSE);
      if(htf_rsi_handle == INVALID_HANDLE) return;
      if(CopyBuffer(htf_rsi_handle, 0, 0, htf_bars, htf_rsi) <= 0) return;
      ArraySetAsSeries(htf_rsi, true);
      //--- Fetch HTF ATR
      double htf_atr[]; ArrayResize(htf_atr, htf_bars);
      int htf_atr_handle = iATR(_Symbol, HTF, RSIPeriod);
      if(htf_atr_handle == INVALID_HANDLE) return;
      if(CopyBuffer(htf_atr_handle, 0, 0, htf_bars, htf_atr) <= 0) return;
      ArraySetAsSeries(htf_atr, true);
      //--- Fetch HTF MA for trend filter
      double htf_ma[]; ArrayResize(htf_ma, htf_bars);
      int htf_ma_handle = iMA(_Symbol, HTF, TrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      if(htf_ma_handle == INVALID_HANDLE) return;
      if(CopyBuffer(htf_ma_handle, 0, 0, htf_bars, htf_ma) <= 0) return;
      ArraySetAsSeries(htf_ma, true);
      int htf_total = ArraySize(htf_time);
      int endBar = MathMin(SwingLookback + MaxLookbackBars, htf_total - SwingLookback);
      //--- Find divergence (same logic as indicator, but only for most recent bar)
      for(int idx = SwingLookback; idx < endBar; idx++) {
         // Find swing lows/highs in price and RSI (HTF)
         bool isPriceLow = true, isPriceHigh = true;
         bool isRSILow = true, isRSIHigh = true;
         for(int j = 1; j <= SwingLookback; j++)
         {
            if(htf_low[idx] > htf_low[idx-(int)j] || htf_low[idx] > htf_low[idx+(int)j]) isPriceLow = false;
            if(htf_high[idx] < htf_high[idx-(int)j] || htf_high[idx] < htf_high[idx+(int)j]) isPriceHigh = false;
            if(htf_rsi[idx] > htf_rsi[idx-(int)j] || htf_rsi[idx] > htf_rsi[idx+(int)j]) isRSILow = false;
            if(htf_rsi[idx] < htf_rsi[idx-(int)j] || htf_rsi[idx] < htf_rsi[idx+(int)j]) isRSIHigh = false;
         }
         // Bullish divergence (HTF)
         if(isPriceLow && isRSILow)
         {
            for(int k = SwingLookback; k < idx - MinSwingBarDistance; k++)
            {
               bool prevIsPriceLow = true, prevIsRSILow = true;
               for(int j = 1; j <= SwingLookback; j++)
               {
                  if(htf_low[k] > htf_low[k-(int)j] || htf_low[k] > htf_low[k+(int)j]) prevIsPriceLow = false;
                  if(htf_rsi[k] > htf_rsi[k-(int)j] || htf_rsi[k] > htf_rsi[k+(int)j]) prevIsRSILow = false;
               }
               double rsiDiff = MathAbs(htf_rsi[idx] - htf_rsi[k]);
               if(prevIsPriceLow && prevIsRSILow && htf_low[idx] < htf_low[k] && htf_rsi[idx] > htf_rsi[k])
               {
                  PrintFormat("Bullish divergence found: idx=%d, k=%d, rsiDiff=%.2f", idx, k, rsiDiff);
                  if((idx - k) < MinSwingBarDistance) { Print("Skipped: swing bar distance too low"); continue; }
                  if(rsiDiff < MinRSIDiff) { Print("Skipped: RSI diff too low"); continue; }
                  if(htf_close[idx] < htf_ma[idx] + TrendMAThreshold) { Print("Skipped: trend filter (not above MA)"); continue; }
                  // Do NOT check for confirmation candle here. Set pending signal only.
                  Print("Bullish divergence signal set, waiting for LTF confirmation");
                  pendingBuySignal = true;
                  pendingHTFPrice = htf_close[idx];
                  pendingHTFTime = htf_time[idx];
                  return;
               }
            }
         }
         // Bearish divergence (HTF)
         if(isPriceHigh && isRSIHigh)
         {
            for(int k = SwingLookback; k < idx - MinSwingBarDistance; k++)
            {
               bool prevIsPriceHigh = true, prevIsRSIHigh = true;
               for(int j = 1; j <= SwingLookback; j++)
               {
                  if(htf_high[k] < htf_high[k-(int)j] || htf_high[k] < htf_high[k+(int)j]) prevIsPriceHigh = false;
                  if(htf_rsi[k] < htf_rsi[k-(int)j] || htf_rsi[k] < htf_rsi[k+(int)j]) prevIsRSIHigh = false;
               }
               double rsiDiff = MathAbs(htf_rsi[idx] - htf_rsi[k]);
               if(prevIsPriceHigh && prevIsRSIHigh && htf_high[idx] > htf_high[k] && htf_rsi[idx] < htf_rsi[k])
               {
                  PrintFormat("Bearish divergence found: idx=%d, k=%d, rsiDiff=%.2f", idx, k, rsiDiff);
                  if((idx - k) < MinSwingBarDistance) { Print("Skipped: swing bar distance too low"); continue; }
                  if(rsiDiff < MinRSIDiff) { Print("Skipped: RSI diff too low"); continue; }
                  if(htf_close[idx] > htf_ma[idx] - TrendMAThreshold) { Print("Skipped: trend filter (not below MA)"); continue; }
                  // Do NOT check for confirmation candle here. Set pending signal only.
                  Print("Bearish divergence signal set, waiting for LTF confirmation");
                  pendingSellSignal = true;
                  pendingHTFPrice = htf_close[idx];
                  pendingHTFTime = htf_time[idx];
                  return;
               }
            }
         }
      }
   }

   // 2. On new LTF bar close, check for entry trigger if pending signal exists
   if(ltfBarClosed)
   {
      prevLTFBarTime = ltfBarTime;
      //--- Fetch LTF data
      int ltf_bars = 10;
      double ltf_open[]; double ltf_close[];
      ArraySetAsSeries(ltf_open, true); ArraySetAsSeries(ltf_close, true);
      if(CopyOpen(_Symbol, LTF, 0, ltf_bars, ltf_open) <= 0) return;
      if(CopyClose(_Symbol, LTF, 0, ltf_bars, ltf_close) <= 0) return;
      // Example: bullish engulfing on LTF for buy entry
      if(pendingBuySignal) {
         Print("Checking for LTF bullish engulfing confirmation...");
         PrintFormat("LTF[2] open=%.5f close=%.5f | LTF[1] open=%.5f close=%.5f", ltf_open[2], ltf_close[2], ltf_open[1], ltf_close[1]);
         bool cond1 = ltf_close[2] < ltf_open[2]; // LTF[2] is bearish
         bool cond2 = ltf_close[1] > ltf_open[1]; // LTF[1] is bullish
         bool cond3 = ltf_open[1] < ltf_close[2]; // Current open < previous close
         bool cond4 = ltf_close[1] > ltf_open[2]; // Current close > previous open
         if(!cond1) Print("LTF[2] is not bearish");
         if(!cond2) Print("LTF[1] is not bullish");
         if(!cond3) Print("LTF[1] open is not below LTF[2] close");
         if(!cond4) Print("LTF[1] close is not above LTF[2] open");
         if(cond1 && cond2 && cond3 && cond4) {
            Print("LTF classic bullish engulfing confirmed, placing buy trade");
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = pendingHTFPrice - ATRMultiplier * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10; // Example SL logic
            double lot = CalculateLotSize(ask, sl, 1.0);
            double stopLossDistance = MathAbs(ask - sl);
            double tp = ask + 2.0 * stopLossDistance;
            OpenBuy(lot, sl, tp);
            pendingBuySignal = false;
         }
      }
      // Example: bearish engulfing on LTF for sell entry
      if(pendingSellSignal) {
         Print("Checking for LTF bearish engulfing confirmation...");
         PrintFormat("LTF[2] open=%.5f close=%.5f | LTF[1] open=%.5f close=%.5f", ltf_open[2], ltf_close[2], ltf_open[1], ltf_close[1]);
         bool cond1 = ltf_close[2] > ltf_open[2]; // LTF[2] is bullish
         bool cond2 = ltf_close[1] < ltf_open[1]; // LTF[1] is bearish
         bool cond3 = ltf_open[1] > ltf_close[2]; // Current open > previous close
         bool cond4 = ltf_close[1] < ltf_open[2]; // Current close < previous open
         if(!cond1) Print("LTF[2] is not bullish");
         if(!cond2) Print("LTF[1] is not bearish");
         if(!cond3) Print("LTF[1] open is not above LTF[2] close");
         if(!cond4) Print("LTF[1] close is not below LTF[2] open");
         if(cond1 && cond2 && cond3 && cond4) {
            Print("LTF classic bearish engulfing confirmed, placing sell trade");
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = pendingHTFPrice + ATRMultiplier * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10; // Example SL logic
            double lot = CalculateLotSize(bid, sl, 1.0);
            double stopLossDistance = MathAbs(sl - bid);
            double tp = bid - 2.0 * stopLossDistance;
            OpenSell(lot, sl, tp);
            pendingSellSignal = false;
         }
      }
   }
  }
//+------------------------------------------------------------------+
//| Count open orders for this symbol                                |
//+------------------------------------------------------------------+
int CountOpenOrders()
  {
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
  }
//+------------------------------------------------------------------+
//| Calculate lot size based on risk percent                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double sl, double riskPct)
  {
   double risk = riskPct/100.0 * AccountInfoDouble(ACCOUNT_BALANCE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double stopLoss = MathAbs(entry - sl);
   if(stopLoss <= 0.0) return minLot;
   double lot = risk / (stopLoss * contractSize);
   // Normalize lot to allowed step
   lot = MathMax(minLot, MathMin(maxLot, MathFloor(lot/lotStep)*lotStep));
   return lot;
  }
//+------------------------------------------------------------------+
//| Open Buy trade                                                   |
//+------------------------------------------------------------------+
void OpenBuy(double lot, double sl, double tp)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLevel = MathMax(
       SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
       SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
   ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calculate and normalize SL/TP
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Robust SL/TP checks for buy (relative to ask)
   if(sl >= ask) {
      Print("SL is not below entry price for buy, skipping trade.");
      return;
   }
   if(tp <= ask) {
      Print("TP is not above entry price for buy, skipping trade.");
      return;
   }
   if((ask - sl) < stopsLevel) {
      Print("SL too close to entry (actual order price), skipping trade.");
      return;
   }
   if((tp - ask) < stopsLevel) {
      Print("TP too close to entry (actual order price), skipping trade.");
      return;
   }

   // Place order WITH SL/TP
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult res; ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_BUY;
   req.price = ask;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 10;
   req.magic = 123456;
   req.type_filling = ORDER_FILLING_IOC;
   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend failed (Buy): ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment,
            " price: ", ask,
            " sl: ", sl,
            " tp: ", tp,
            " stopsLevel: ", stopsLevel);
   }
  }
//+------------------------------------------------------------------+
//| Open Sell trade                                                  |
//+------------------------------------------------------------------+
void OpenSell(double lot, double sl, double tp)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopsLevel = MathMax(
       SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
       SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
   ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calculate and normalize SL/TP
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Robust SL/TP checks for sell (relative to bid)
   if(sl <= bid) {
      Print("SL is not above entry price for sell, skipping trade.");
      return;
   }
   if(tp >= bid) {
      Print("TP is not below entry price for sell, skipping trade.");
      return;
   }
   if((sl - bid) < stopsLevel) {
      Print("SL too close to entry (actual order price), skipping trade.");
      return;
   }
   if((bid - tp) < stopsLevel) {
      Print("TP too close to entry (actual order price), skipping trade.");
      return;
   }

   // Place order WITH SL/TP
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult res; ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_SELL;
   req.price = bid;
   req.sl = sl;
   req.tp = tp;
   req.deviation = 10;
   req.magic = 123456;
   req.type_filling = ORDER_FILLING_IOC;
   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend failed (Sell): ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment,
            " price: ", bid,
            " sl: ", sl,
            " tp: ", tp,
            " stopsLevel: ", stopsLevel);
   }
  }
//+------------------------------------------------------------------+ 