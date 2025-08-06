//+------------------------------------------------------------------+
//|                        TradeUtils.mqh                            |
//|   Generic trading utility functions for MQL5 EAs                 |
//+------------------------------------------------------------------+
#ifndef __TRADEUTILS_MQH__
#define __TRADEUTILS_MQH__

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percent, stop distance, and symbol
//| Returns lot size (double)
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPercent, double stopDistance, string symbol = NULL)
{
   if(symbol == NULL || symbol == "")
      symbol = _Symbol;
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * riskPercent / 100.0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) return 0;
   double riskPerLot = (stopDistance / tickSize) * tickValue;
   if(riskPerLot == 0) return 0;
   double lotSize = riskAmount / riskPerLot;
   // Apply limits
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate ATR value for a symbol/timeframe/period                |
//| Returns ATR value (double), or 0 on error                        |
//+------------------------------------------------------------------+
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   int atrHandle = iATR(symbol, tf, period);
   if(atrHandle == INVALID_HANDLE)
      return 0;
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0)
   {
      IndicatorRelease(atrHandle);
      return 0;
   }
   double atr = atrBuffer[0];
   IndicatorRelease(atrHandle);
   return atr;
}

//+------------------------------------------------------------------+
//| Calculate stop loss price based on ATR                            |
//| orderType: ORDER_TYPE_BUY/SELL                                   |
//| entryPrice: entry price                                          |
//| atr: ATR value                                                   |
//| atrMultiplier: multiplier for ATR                                |
//| Returns stop loss price (double)                                 |
//+------------------------------------------------------------------+
double CalculateATRStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice, double atr, double atrMultiplier)
{
   double stopDistance = atr * atrMultiplier;
   if(orderType == ORDER_TYPE_BUY)
      return entryPrice - stopDistance;
   else
      return entryPrice + stopDistance;
}

//+------------------------------------------------------------------+
//| Check if current time is within a session                        |
//| sessionStartHour/sessionEndHour: 0-23 (server time)              |
//| Returns 1 if within session                                      |
//+------------------------------------------------------------------+
bool IsWithinSession(int sessionStartHour, int sessionEndHour)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentHour = now.hour;
   return (currentHour >= sessionStartHour && currentHour < sessionEndHour);
}

//+------------------------------------------------------------------+
//| Find swing high in the last N bars                               |
//| symbol: symbol to analyze                                        |
//| tf: timeframe                                                    |
//| bars: number of bars to look back                               |
//| Returns swing high price (double)                               |
//+------------------------------------------------------------------+
double FindSwingHigh(string symbol, ENUM_TIMEFRAMES tf, int bars)
{
   double highs[];
   ArraySetAsSeries(highs, true);
   if(CopyHigh(symbol, tf, 1, bars, highs) != bars)
      return 0;
   return highs[ArrayMaximum(highs, 0, bars)];
}

//+------------------------------------------------------------------+
//| Find swing low in the last N bars                                |
//| symbol: symbol to analyze                                        |
//| tf: timeframe                                                    |
//| bars: number of bars to look back                               |
//| Returns swing low price (double)                                |
//+------------------------------------------------------------------+
double FindSwingLow(string symbol, ENUM_TIMEFRAMES tf, int bars)
{
   double lows[];
   ArraySetAsSeries(lows, true);
   if(CopyLow(symbol, tf, 1, bars, lows) != bars)
      return 0;
   return lows[ArrayMinimum(lows, 0, bars)];
}

//+------------------------------------------------------------------+
//| Place buy order with validation                                  |
//| lot: lot size                                                    |
//| sl: stop loss price                                              |
//| tp: take profit price                                            |
//| magic: magic number                                              |
//| comment: order comment                                           |
//| Returns true if order placed successfully                       |
//+------------------------------------------------------------------+
bool PlaceBuyOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Validate SL/TP for buy order
   if(sl >= ask) {
      Print("SL is not below entry price for buy");
      return false;
   }
   if(tp <= ask) {
      Print("TP is not above entry price for buy");
      return false;
   }
   if((ask - sl) < stopsLevel) {
      Print("SL too close to entry for buy");
      return false;
   }
   if((tp - ask) < stopsLevel) {
      Print("TP too close to entry for buy");
      return false;
   }

   // Place order
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
   req.magic = magic;
   req.comment = comment;
   req.type_filling = ORDER_FILLING_IOC;

   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("Buy order failed: ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Place sell order with validation                                 |
//| lot: lot size                                                    |
//| sl: stop loss price                                              |
//| tp: take profit price                                            |
//| magic: magic number                                              |
//| comment: order comment                                           |
//| Returns true if order placed successfully                       |
//+------------------------------------------------------------------+
bool PlaceSellOrder(double lot, double sl, double tp, ulong magic = 0, string comment = "")
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopsLevel = MathMax(
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)
    ) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   // Validate SL/TP for sell order
   if(sl <= bid) {
      Print("SL is not above entry price for sell");
      return false;
   }
   if(tp >= bid) {
      Print("TP is not below entry price for sell");
      return false;
   }
   if((sl - bid) < stopsLevel) {
      Print("SL too close to entry for sell");
      return false;
   }
   if((bid - tp) < stopsLevel) {
      Print("TP too close to entry for sell");
      return false;
   }

   // Place order
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
   req.magic = magic;
   req.comment = comment;
   req.type_filling = ORDER_FILLING_IOC;

   bool sent = OrderSend(req, res);
   if(!sent || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("Sell order failed: ", GetLastError(),
            " retcode: ", res.retcode,
            " comment: ", res.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Count open positions for a symbol                                |
//| symbol: symbol to count (NULL for current symbol)               |
//| Returns number of open positions                                 |
//+------------------------------------------------------------------+
int CountOpenPositions(string symbol = NULL)
{
   if(symbol == NULL || symbol == "")
      symbol = _Symbol;
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == symbol)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if position is in profit                                   |
//| symbol: symbol to check (NULL for current symbol)               |
//| Returns true if position is profitable                          |
//+------------------------------------------------------------------+
bool IsPositionInProfit(string symbol = NULL)
{
   if(symbol == NULL || symbol == "")
      symbol = _Symbol;
   if(!PositionSelect(symbol)) return false;
   double positionProfit = PositionGetDouble(POSITION_PROFIT);
   return (positionProfit > 0);
}

//+------------------------------------------------------------------+
//| Modify position's stop loss and take profit                      |
//| ticket: position ticket                                          |
//| sl: new stop loss price                                          |
//| tp: new take profit price                                        |
//| Returns true if modification successful                          |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_SLTP;
   request.symbol = _Symbol;
   request.sl = sl;
   request.tp = tp;
   request.position = ticket;
   return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Check if market is open                                          |
//| Returns true if market is open                                   |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   return MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

//+------------------------------------------------------------------+
//| Get current spread in points                                     |
//| symbol: symbol to check (NULL for current symbol)               |
//| Returns spread in points                                         |
//+------------------------------------------------------------------+
double GetSpread(string symbol = NULL)
{
   if(symbol == NULL || symbol == "")
      symbol = _Symbol;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   return (ask - bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                    |
//| maxSpread: maximum acceptable spread in points                   |
//| symbol: symbol to check (NULL for current symbol)               |
//| Returns true if spread is acceptable                            |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(double maxSpread, string symbol = NULL)
{
   return GetSpread(symbol) <= maxSpread;
}

//+------------------------------------------------------------------+
//| Linear regression calculation                                     |
//| x: array of x values                                             |
//| y: array of y values                                             |
//| count: number of points                                          |
//| a: slope (output)                                                |
//| b: intercept (output)                                            |
//| Returns true if calculation successful                           |
//+------------------------------------------------------------------+
bool LinearRegression(const double &x[], const double &y[], const int count, double &a, double &b)
{
   if(count < 2) return false;

   double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;

   for(int i = 0; i < count; i++)
   {
      sum_x += x[i];
      sum_y += y[i];
      sum_xy += x[i] * y[i];
      sum_x2 += x[i] * x[i];
   }

   double d = count * sum_x2 - sum_x * sum_x;
   if(d == 0) return false;

   a = (count * sum_xy - sum_x * sum_y) / d;
   b = (sum_y - a * sum_x) / count;

   return true;
}

//+------------------------------------------------------------------+
//| Check for bullish engulfing pattern                              |
//| open: array of open prices                                       |
//| close: array of close prices                                     |
//| shift: bar shift (0 = current, 1 = previous, etc.)              |
//| Returns true if bullish engulfing detected                      |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(const double &open[], const double &close[], int shift = 1)
{
   if(shift + 1 >= ArraySize(open) || shift + 1 >= ArraySize(close))
      return false;

   bool prevBearish = close[shift + 1] < open[shift + 1];
   bool currBullish = close[shift] > open[shift];
   bool currOpenBelowPrevClose = open[shift] < close[shift + 1];
   bool currCloseAbovePrevOpen = close[shift] > open[shift + 1];

   return prevBearish && currBullish && currOpenBelowPrevClose && currCloseAbovePrevOpen;
}

//+------------------------------------------------------------------+
//| Check for bearish engulfing pattern                              |
//| open: array of open prices                                       |
//| close: array of close prices                                     |
//| shift: bar shift (0 = current, 1 = previous, etc.)              |
//| Returns true if bearish engulfing detected                      |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(const double &open[], const double &close[], int shift = 1)
{
   if(shift + 1 >= ArraySize(open) || shift + 1 >= ArraySize(close))
      return false;

   bool prevBullish = close[shift + 1] > open[shift + 1];
   bool currBearish = close[shift] < open[shift];
   bool currOpenAbovePrevClose = open[shift] > close[shift + 1];
   bool currCloseBelowPrevOpen = close[shift] < open[shift + 1];

   return prevBullish && currBearish && currOpenAbovePrevClose && currCloseBelowPrevOpen;
}

//+------------------------------------------------------------------+
//| Check for hammer pattern                                         |
//| open: array of open prices                                       |
//| high: array of high prices                                       |
//| low: array of low prices                                         |
//| close: array of close prices                                     |
//| shift: bar shift (0 = current, 1 = previous, etc.)              |
//| Returns true if hammer detected                                  |
//+------------------------------------------------------------------+
bool IsHammer(const double &open[], const double &high[], const double &low[], const double &close[], int shift = 0)
{
   if(shift >= ArraySize(open)) return false;

   double bodySize = MathAbs(close[shift] - open[shift]);
   double totalRange = high[shift] - low[shift];
   double lowerWick = MathMin(open[shift], close[shift]) - low[shift];
   double upperWick = high[shift] - MathMax(open[shift], close[shift]);

   if(totalRange == 0) return false;

   bool smallBody = bodySize <= totalRange * 0.3;
   bool longLowerWick = lowerWick >= totalRange * 0.6;
   bool shortUpperWick = upperWick <= totalRange * 0.1;

   return smallBody && longLowerWick && shortUpperWick;
}

//+------------------------------------------------------------------+
//| Check for shooting star pattern                                  |
//| open: array of open prices                                       |
//| high: array of high prices                                       |
//| low: array of low prices                                         |
//| close: array of close prices                                     |
//| shift: bar shift (0 = current, 1 = previous, etc.)              |
//| Returns true if shooting star detected                          |
//+------------------------------------------------------------------+
bool IsShootingStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift = 0)
{
   if(shift >= ArraySize(open)) return false;

   double bodySize = MathAbs(close[shift] - open[shift]);
   double totalRange = high[shift] - low[shift];
   double lowerWick = MathMin(open[shift], close[shift]) - low[shift];
   double upperWick = high[shift] - MathMax(open[shift], close[shift]);

   if(totalRange == 0) return false;

   bool smallBody = bodySize <= totalRange * 0.3;
   bool longUpperWick = upperWick >= totalRange * 0.6;
   bool shortLowerWick = lowerWick <= totalRange * 0.1;

   return smallBody && longUpperWick && shortLowerWick;
}

//+------------------------------------------------------------------+
//| Get volume ratio (current volume / average volume)               |
//| symbol: symbol to check (NULL for current symbol)               |
//| tf: timeframe                                                    |
//| period: period for volume average                                |
//| Returns volume ratio (double)                                    |
//+------------------------------------------------------------------+
double GetVolumeRatio(string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int period = 20)
{
   if(symbol == NULL || symbol == "")
      symbol = _Symbol;

   long volume[];
   ArraySetAsSeries(volume, true);

   if(CopyTickVolume(symbol, tf, 0, period + 1, volume) <= period)
      return 1.0;

   double avgVolume = 0;
   for(int i = 1; i <= period; i++)
   {
      avgVolume += volume[i];
   }
   avgVolume /= period;

   if(avgVolume == 0) return 1.0;

   return (double)volume[0] / avgVolume;
}

//+------------------------------------------------------------------+
//| Check if volume is above threshold                               |
//| minVolumeFactor: minimum volume factor                           |
//| symbol: symbol to check (NULL for current symbol)               |
//| tf: timeframe                                                    |
//| period: period for volume average                                |
//| Returns true if volume is sufficient                            |
//+------------------------------------------------------------------+
bool IsVolumeSufficient(double minVolumeFactor, string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT, int period = 20)
{
   return GetVolumeRatio(symbol, tf, period) >= minVolumeFactor;
}

//+------------------------------------------------------------------+
//| Helper: Extract base/quote currencies from symbol                |
//+------------------------------------------------------------------+
void GetCurrenciesFromSymbol(string symbol, string &base, string &quote)
{
    string clean = symbol;
    int len = StringLen(clean);
    while(len > 0 && !((clean[len-1] >= 'A' && clean[len-1] <= 'Z') || (clean[len-1] >= 'a' && clean[len-1] <= 'z')))
        len--;
    clean = StringSubstr(clean, 0, len);
    base = StringSubstr(clean, 0, 3);
    quote = StringSubstr(clean, 3, 3);
}

//+------------------------------------------------------------------+
//| News Filter: Returns true if relevant news is in block window    |
//+------------------------------------------------------------------+
bool IsNewsTime(string symbol, int minutesBefore = 30, int minutesAfter = 30, bool blockHighImpactOnly = true, bool enableDebugLogs = false)
{
    string base, quote;
    GetCurrenciesFromSymbol(symbol, base, quote);
    datetime from = TimeCurrent() - minutesBefore * 60;
    datetime to   = TimeCurrent() + minutesAfter * 60;
    string currencies[2] = {base, quote};
    for(int c=0; c<2; c++) {
        MqlCalendarValue values[];
        if(CalendarValueHistory(values, from, to, currencies[c])) {
            for(int i = 0; i < ArraySize(values); i++) {
                if(enableDebugLogs) Print("[Utils][News] Checking news event: ", values[i].event_id, " at ", TimeToString(values[i].time));
                MqlCalendarEvent event;
                if(CalendarEventById(values[i].event_id, event)) {
                    if(!blockHighImpactOnly || event.importance == CALENDAR_IMPORTANCE_HIGH) {
                        if(enableDebugLogs) Print("[Utils][News] Blocking trading due to news: ", event.name, " (", currencies[c], ") at ", TimeToString(values[i].time));
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Calculate trailing stop price                                    |
//| positionType: POSITION_TYPE_BUY or POSITION_TYPE_SELL           |
//| entryPrice: position entry price                                 |
//| currentPrice: current market price                               |
//| trailPercent: trailing percentage of initial stop distance      |
//| initialStopDistance: initial stop loss distance                 |
//| Returns new stop loss price                                      |
//+------------------------------------------------------------------+
double CalculateTrailingStop(ENUM_POSITION_TYPE positionType, double entryPrice, double currentPrice,
                           double trailPercent, double initialStopDistance)
{
   double trailDistance = initialStopDistance * (trailPercent / 100.0);

   if(positionType == POSITION_TYPE_BUY)
   {
      return currentPrice - trailDistance;
   }
   else
   {
      return currentPrice + trailDistance;
   }
}

//+------------------------------------------------------------------+
//| Check if price is within a range                                 |
//| price: price to check                                            |
//| rangeHigh: upper bound of range                                 |
//| rangeLow: lower bound of range                                  |
//| tolerance: tolerance in points                                   |
//| Returns true if price is within range                           |
//+------------------------------------------------------------------+
bool IsPriceInRange(double price, double rangeHigh, double rangeLow, double tolerance = 0)
{
   return (price >= rangeLow - tolerance && price <= rangeHigh + tolerance);
}

//+------------------------------------------------------------------+
//| Calculate percentage change                                       |
//| oldValue: old value                                              |
//| newValue: new value                                              |
//| Returns percentage change                                        |
//+------------------------------------------------------------------+
double CalculatePercentageChange(double oldValue, double newValue)
{
   if(oldValue == 0) return 0;
   return ((newValue - oldValue) / oldValue) * 100.0;
}

//+------------------------------------------------------------------+
//| Check if value is within percentage range                        |
//| value: value to check                                            |
//| target: target value                                             |
//| percentRange: percentage range                                   |
//| Returns true if value is within range                           |
//+------------------------------------------------------------------+
bool IsWithinPercentageRange(double value, double target, double percentRange)
{
   double minValue = target * (1 - percentRange / 100.0);
   double maxValue = target * (1 + percentRange / 100.0);
   return (value >= minValue && value <= maxValue);
}

//+------------------------------------------------------------------+
//| Pseudo-News: Detects volatility/volume spikes in tester          |
//| Returns true if current bar is a volatility/volume spike        |
//+------------------------------------------------------------------+
bool IsPseudoNewsEvent(double threshold = 2.0, int lookback = 20, bool enableDebugLogs = false)
{
    if(!MQLInfoInteger(MQL_TESTER)) return false; // Only use in tester

    double high[], low[];
    long volume[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(volume, true);

    if(CopyHigh(_Symbol, _Period, 0, lookback+2, high) <= lookback+1 ||
       CopyLow(_Symbol, _Period, 0, lookback+2, low) <= lookback+1 ||
       CopyTickVolume(_Symbol, _Period, 0, lookback+2, volume) <= lookback+1)
        return false;

    double avgRange = 0;
    long avgVolume = 0;

    if(enableDebugLogs) Print("[Utils][PseudoNews] Copying high, low, volume: high=", high[0], " low=", low[0], " volume=", volume[0]);
    for(int i=2; i<=lookback+1; i++) {
        avgRange += high[i] - low[i];
        avgVolume += volume[i];
    }
    avgRange /= lookback;
    avgVolume /= lookback;

    if(enableDebugLogs) Print("[Utils][PseudoNews] Avg range=", avgRange, " avgVolume=", avgVolume);

    double currRange = high[1] - low[1];
    long currVolume = volume[1];

    if(enableDebugLogs) Print("[Utils][PseudoNews] Curr range=", currRange, " currVolume=", currVolume);

    if(currRange > threshold * avgRange || currVolume > threshold * avgVolume) {
        if(enableDebugLogs) Print("[Utils][PseudoNews] Volatility/volume spike detected: range=", currRange, " avgRange=", avgRange, " volume=", currVolume, " avgVolume=", avgVolume);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Supply/Demand Zone Utilities                                    |
//+------------------------------------------------------------------+
//| Detect supply/demand zones (RBR/DBR/DBD/RBD) and draw them      |
//| Usage:                                                          |
//|   FindSupplyDemandZones(symbol, timeframe, lookbackBars, minZoneSize, demandZones, supplyZones);
//|   DrawZones(symbol, timeframe, demandZones, supplyZones, demandColor, supplyColor, prefix);
//+------------------------------------------------------------------+
struct SDZone {
    double upper;
    double lower;
    datetime startTime;
    datetime endTime;
    bool isDemand; // true = demand, false = supply
};

void FindSupplyDemandZones(string symbol, ENUM_TIMEFRAMES tf, int lookbackBars, int minZoneSize, SDZone &demandZones[], SDZone &supplyZones[])
{
    ArrayResize(demandZones, 0);
    ArrayResize(supplyZones, 0);
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    int bars = MathMin(lookbackBars, Bars(symbol, tf));
    if(CopyOpen(symbol, tf, 0, bars, open) <= 0 ||
       CopyHigh(symbol, tf, 0, bars, high) <= 0 ||
       CopyLow(symbol, tf, 0, bars, low) <= 0 ||
       CopyClose(symbol, tf, 0, bars, close) <= 0) {
        Print("[Utils] Failed to get data for supply/demand zones");
        return;
    }
    double impulseFactor = 1.5;
    int minImpulse = 1;
    int minBase = minZoneSize;
    int maxBase = 5;
    double totalBody = 0;
    for(int i = 0; i < bars; i++) totalBody += MathAbs(close[i] - open[i]);
    double avgBody = totalBody / bars;
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        // DBR
        bool drop = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = open[i+d] - close[i+d];
            if(body < impulseFactor * avgBody) drop = false;
        }
        if(!drop) continue;
        int baseStart = i + minImpulse;
        int baseEnd = baseStart;
        int baseCount = 0;
        for(int b = baseStart; b < baseStart + maxBase && b < bars - minImpulse; b++) {
            double body = MathAbs(close[b] - open[b]);
            if(body < avgBody) {
                baseEnd = b;
                baseCount++;
            } else {
                break;
            }
        }
        if(baseCount < minBase) continue;
        bool rally = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = close[r] - open[r];
            if(body < impulseFactor * avgBody) rally = false;
        }
        if(!rally) continue;
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        SDZone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(symbol, tf, baseStart);
        z.endTime = iTime(symbol, tf, baseEnd);
        z.isDemand = true;
        ArrayResize(demandZones, ArraySize(demandZones)+1);
        demandZones[ArraySize(demandZones)-1] = z;
    }
    // RBD
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        bool rally = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = close[i+d] - open[i+d];
            if(body < impulseFactor * avgBody) rally = false;
        }
        if(!rally) continue;
        int baseStart = i + minImpulse;
        int baseEnd = baseStart;
        int baseCount = 0;
        for(int b = baseStart; b < baseStart + maxBase && b < bars - minImpulse; b++) {
            double body = MathAbs(close[b] - open[b]);
            if(body < avgBody) {
                baseEnd = b;
                baseCount++;
            } else {
                break;
            }
        }
        if(baseCount < minBase) continue;
        bool drop = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = open[r] - close[r];
            if(body < impulseFactor * avgBody) drop = false;
        }
        if(!drop) continue;
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        SDZone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(symbol, tf, baseStart);
        z.endTime = iTime(symbol, tf, baseEnd);
        z.isDemand = false;
        ArrayResize(supplyZones, ArraySize(supplyZones)+1);
        supplyZones[ArraySize(supplyZones)-1] = z;
    }
    // DBD
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        bool drop1 = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = open[i+d] - close[i+d];
            if(body < impulseFactor * avgBody) drop1 = false;
        }
        if(!drop1) continue;
        int baseStart = i + minImpulse;
        int baseEnd = baseStart;
        int baseCount = 0;
        for(int b = baseStart; b < baseStart + maxBase && b < bars - minImpulse; b++) {
            double body = MathAbs(close[b] - open[b]);
            if(body < avgBody) {
                baseEnd = b;
                baseCount++;
            } else {
                break;
            }
        }
        if(baseCount < minBase) continue;
        bool drop2 = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = open[r] - close[r];
            if(body < impulseFactor * avgBody) drop2 = false;
        }
        if(!drop2) continue;
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        SDZone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(symbol, tf, baseStart);
        z.endTime = iTime(symbol, tf, baseEnd);
        z.isDemand = false;
        ArrayResize(supplyZones, ArraySize(supplyZones)+1);
        supplyZones[ArraySize(supplyZones)-1] = z;
    }
    // RBR
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        bool rally1 = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = close[i+d] - open[i+d];
            if(body < impulseFactor * avgBody) rally1 = false;
        }
        if(!rally1) continue;
        int baseStart = i + minImpulse;
        int baseEnd = baseStart;
        int baseCount = 0;
        for(int b = baseStart; b < baseStart + maxBase && b < bars - minImpulse; b++) {
            double body = MathAbs(close[b] - open[b]);
            if(body < avgBody) {
                baseEnd = b;
                baseCount++;
            } else {
                break;
            }
        }
        if(baseCount < minBase) continue;
        bool rally2 = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = close[r] - open[r];
            if(body < impulseFactor * avgBody) rally2 = false;
        }
        if(!rally2) continue;
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        SDZone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(symbol, tf, baseStart);
        z.endTime = iTime(symbol, tf, baseEnd);
        z.isDemand = true;
        ArrayResize(demandZones, ArraySize(demandZones)+1);
        demandZones[ArraySize(demandZones)-1] = z;
    }
}

void DrawZones(string symbol, ENUM_TIMEFRAMES tf, const SDZone &demandZones[], const SDZone &supplyZones[], color demandColor, color supplyColor, string prefix = "SD_ZONE_")
{
    ObjectsDeleteAll(0, prefix);
    for(int i = 0; i < ArraySize(demandZones); i++) {
        string name = prefix + "D_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, demandZones[i].startTime, demandZones[i].upper, demandZones[i].endTime, demandZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, demandColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
    for(int i = 0; i < ArraySize(supplyZones); i++) {
        string name = prefix + "S_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, supplyZones[i].startTime, supplyZones[i].upper, supplyZones[i].endTime, supplyZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, supplyColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//+------------------------------------------------------------------+
//| S/R Zone Utilities                                              |
//+------------------------------------------------------------------+
struct AreaOfInterest {
    double level;
    bool isSupport;
    datetime firstTouch;
    datetime lastTouch;
    int bounceCount;
    double strength;
    int areaId;
};
struct SRZone {
    double upper;
    double lower;
    bool isSupport;
};

// Helper: Add or update an area of interest in the array
void AddAreaOfInterest(double level, bool isSupport, datetime touchTime, double tolerance, AreaOfInterest &areas[])
{
    for(int i = 0; i < ArraySize(areas); i++) {
        if(MathAbs(areas[i].level - level) <= tolerance) {
            areas[i].lastTouch = touchTime;
            areas[i].bounceCount++;
            return;
        }
    }
    ArrayResize(areas, ArraySize(areas) + 1);
    int idx = ArraySize(areas) - 1;
    areas[idx].level = level;
    areas[idx].isSupport = isSupport;
    areas[idx].firstTouch = touchTime;
    areas[idx].lastTouch = touchTime;
    areas[idx].bounceCount = 1;
    areas[idx].strength = 1.0;
    areas[idx].areaId = idx;
}

// Main S/R zone finder: populates supportZones and resistanceZones arrays
void FindSRZones(
    string symbol,
    ENUM_TIMEFRAMES tf,
    int lookbackBars,
    double tolerance,
    int mergeDistancePoints,
    SRZone &supportZones[],
    SRZone &resistanceZones[]
) {
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    int bars = MathMin(lookbackBars, Bars(symbol, tf));
    if(CopyHigh(symbol, tf, 0, bars, high) <= 0 ||
       CopyLow(symbol, tf, 0, bars, low) <= 0 ||
       CopyClose(symbol, tf, 0, bars, close) <= 0) {
        Print("[Utils][SR] Failed to get data for S/R");
        return;
    }
    AreaOfInterest supportAreas[];
    AreaOfInterest resistanceAreas[];
    double supportLevels[];
    double resistanceLevels[];
    for(int i = 2; i < bars - 2; i++) {
        if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2])
            AddAreaOfInterest(high[i], false, iTime(symbol, tf, i), tolerance, resistanceAreas);
        if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2])
            AddAreaOfInterest(low[i], true, iTime(symbol, tf, i), tolerance, supportAreas);
    }
    // Collect levels
    for(int i = 0; i < ArraySize(supportAreas); i++) {
        ArrayResize(supportLevels, ArraySize(supportLevels)+1);
        supportLevels[ArraySize(supportLevels)-1] = supportAreas[i].level;
    }
    for(int i = 0; i < ArraySize(resistanceAreas); i++) {
        ArrayResize(resistanceLevels, ArraySize(resistanceLevels)+1);
        resistanceLevels[ArraySize(resistanceLevels)-1] = resistanceAreas[i].level;
    }
    ArraySort(supportLevels);
    ArraySort(resistanceLevels);
    // Merge support levels into zones
    ArrayResize(supportZones, 0);
    int n = ArraySize(supportLevels);
    int i = 0;
    while(i < n) {
        double lower = supportLevels[i];
        double upper = supportLevels[i];
        int j = i+1;
        while(j < n && MathAbs(supportLevels[j] - upper) <= mergeDistancePoints * SymbolInfoDouble(symbol, SYMBOL_POINT)) {
            upper = supportLevels[j];
            j++;
        }
        SRZone z; z.lower = lower; z.upper = upper; z.isSupport = true;
        ArrayResize(supportZones, ArraySize(supportZones)+1);
        supportZones[ArraySize(supportZones)-1] = z;
        i = j;
    }
    // Merge resistance levels into zones
    ArrayResize(resistanceZones, 0);
    n = ArraySize(resistanceLevels);
    i = 0;
    while(i < n) {
        double lower = resistanceLevels[i];
        double upper = resistanceLevels[i];
        int j = i+1;
        while(j < n && MathAbs(resistanceLevels[j] - upper) <= mergeDistancePoints * SymbolInfoDouble(symbol, SYMBOL_POINT)) {
            upper = resistanceLevels[j];
            j++;
        }
        SRZone z; z.lower = lower; z.upper = upper; z.isSupport = false;
        ArrayResize(resistanceZones, ArraySize(resistanceZones)+1);
        resistanceZones[ArraySize(resistanceZones)-1] = z;
        i = j;
    }
}

// Draw S/R zones as rectangles (not lines) for visual confluence
void DrawSRZones(
    string symbol,
    ENUM_TIMEFRAMES tf,
    const SRZone &supportZones[],
    const SRZone &resistanceZones[],
    color supportColor,
    color resistanceColor,
    int lookbackBars,
    string prefix = "SR_ZONE_"
) {
    ObjectsDeleteAll(0, prefix);
    datetime left = iTime(symbol, tf, lookbackBars-1);
    datetime right = iTime(symbol, tf, 0);
    for(int i = 0; i < ArraySize(supportZones); i++) {
        string name = prefix + "S_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, left, supportZones[i].upper, right, supportZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, supportColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
    for(int i = 0; i < ArraySize(resistanceZones); i++) {
        string name = prefix + "R_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, left, resistanceZones[i].upper, right, resistanceZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, resistanceColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}
// Usage:
//   FindSRZones(symbol, tf, lookbackBars, tolerance, mergeDistancePoints, supportZones, resistanceZones);
//   DrawSRZones(symbol, tf, supportZones, resistanceZones, supportColor, resistanceColor, lookbackBars, prefix);

//+------------------------------------------------------------------+
//| Machine Learning Utilities                                       |
//+------------------------------------------------------------------+

//--- ML Feature collection structure
struct MLFeatures {
    double rsi;
    double stoch_main;
    double stoch_signal;
    double ad;
    double volume;
    double ma;
    double atr;
    double macd_main;
    double macd_signal;
    double bb_upper;
    double bb_lower;
    double spread;
    string candle_pattern;
    string candle_seq;
    string zone_type;
    double zone_upper;
    double zone_lower;
    datetime zone_start;
    datetime zone_end;
    string trend;
    double volume_ratio;
    double price_change;
    double volatility;
    int session_hour;
    bool is_news_time;
    double current_price;
    double entry_price;
    double stop_loss;
    double take_profit;
    double lot_size;
    string trade_direction;
    datetime trade_time;
    bool trade_success;
    double trade_profit;
    double trade_duration;
    // Advanced indicators
    double williams_r;
    double cci;
    double momentum;
    double force_index;
    double bb_position;
};

//--- Global ML model parameters (Combined model)
double globalMinPredictionThreshold = 0.55;
double globalMaxPredictionThreshold = 0.45;
double globalMinPredictionConfidence = 0.30;
double globalMaxPredictionConfidence = 0.85;
double globalPositionSizingMultiplier = 1.0;
double globalStopLossAdjustment = 1.0;

//--- Global ML model parameters (Combined model - loaded from optimized file)
double globalRSIBullishThreshold = 30.0;
double globalRSIBearishThreshold = 70.0;
double globalRSIWeight = 0.08;
double globalStochBullishThreshold = 20.0;
double globalStochBearishThreshold = 80.0;
double globalStochWeight = 0.08;
double globalMACDThreshold = 0.0;
double globalMACDWeight = 0.08;
double globalVolumeRatioThreshold = 1.5;

//--- Global ML session filtering variables
string globalOptimalSessions = "";
bool globalSessionFilteringEnabled = false;
double globalLondonSessionWeight = 1.0;
double globalNYSessionWeight = 1.0;
double globalAsianSessionWeight = 1.0;
double globalOffHoursSessionWeight = 1.0;
double globalLondonMinSuccessRate = 0.4;
double globalNYMinSuccessRate = 0.4;
double globalAsianMinSuccessRate = 0.4;
int globalLondonMinTrades = 5;
int globalNYMinTrades = 5;
int globalAsianMinTrades = 5;
double globalVolumeWeight = 0.08;
double globalPatternBullishWeight = 0.12;
double globalPatternBearishWeight = 0.12;
double globalZoneWeight = 0.08;
double globalTrendWeight = 0.08;
double globalBaseConfidence = 0.6;
double globalSignalAgreementWeight = 0.5;
double globalNeutralZoneMin = 0.4;
double globalNeutralZoneMax = 0.6;

//--- Global ML model parameters (Buy-specific model)
double globalBuyRSIBullishThreshold = 30.0;
double globalBuyRSIBearishThreshold = 70.0;
double globalBuyRSIWeight = 0.08;
double globalBuyStochBullishThreshold = 20.0;
double globalBuyStochBearishThreshold = 80.0;
double globalBuyStochWeight = 0.08;
double globalBuyMACDThreshold = 0.0;
double globalBuyMACDWeight = 0.08;
double globalBuyVolumeRatioThreshold = 1.5;
double globalBuyVolumeWeight = 0.08;
double globalBuyPatternBullishWeight = 0.12;
double globalBuyPatternBearishWeight = 0.12;
double globalBuyZoneWeight = 0.08;
double globalBuyTrendWeight = 0.08;
double globalBuyBaseConfidence = 0.6;
double globalBuySignalAgreementWeight = 0.5;
double globalBuyMinPredictionThreshold = 0.52;
double globalBuyMaxPredictionThreshold = 0.48;
double globalBuyMinConfidence = 0.35;
double globalBuyMaxConfidence = 0.9;
double globalBuyPositionSizingMultiplier = 1.2;
double globalBuyStopLossAdjustment = 0.5;

//--- Global ML model parameters (Sell-specific model)
double globalSellRSIBullishThreshold = 30.0;
double globalSellRSIBearishThreshold = 70.0;
double globalSellRSIWeight = 0.08;
double globalSellStochBullishThreshold = 20.0;
double globalSellStochBearishThreshold = 80.0;
double globalSellStochWeight = 0.08;
double globalSellMACDThreshold = 0.0;
double globalSellMACDWeight = 0.08;
double globalSellVolumeRatioThreshold = 1.5;
double globalSellVolumeWeight = 0.08;
double globalSellPatternBullishWeight = 0.12;
double globalSellPatternBearishWeight = 0.12;
double globalSellZoneWeight = 0.08;
double globalSellTrendWeight = 0.08;
double globalSellBaseConfidence = 0.6;
double globalSellSignalAgreementWeight = 0.5;
double globalSellMinPredictionThreshold = 0.52;
double globalSellMaxPredictionThreshold = 0.48;
double globalSellMinConfidence = 0.35;
double globalSellMaxConfidence = 0.9;
double globalSellPositionSizingMultiplier = 1.2;
double globalSellStopLossAdjustment = 0.5;

//+------------------------------------------------------------------+
//| ML Utility Functions                                             |
//+------------------------------------------------------------------+

//--- Helper: Collect ML features
void CollectMLFeatures(MLFeatures &features, string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    // RSI
    int rsiHandle = iRSI(symbol, tf, 14, PRICE_CLOSE);
    if(rsiHandle != INVALID_HANDLE) {
        double buf[];
        ArrayResize(buf, 1);
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(rsiHandle, 0, 0, 1, buf) > 0) {
            features.rsi = buf[0];
            if(!MathIsValidNumber(features.rsi)) {
                features.rsi = 50.0; // Default if invalid
            }
        } else {
            features.rsi = 50.0; // Default if copy failed
        }
        IndicatorRelease(rsiHandle);
    } else {
        features.rsi = 50.0; // Default if handle invalid
    }

    // Stochastic
    int stochHandle = iStochastic(symbol, tf, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    if(stochHandle != INVALID_HANDLE) {
        double bufMain[1], bufSignal[1];
        if(CopyBuffer(stochHandle, 0, 0, 1, bufMain) > 0 && MathIsValidNumber(bufMain[0])) {
            features.stoch_main = bufMain[0];
        } else {
            features.stoch_main = 50.0; // Default if invalid
        }
        if(CopyBuffer(stochHandle, 1, 0, 1, bufSignal) > 0 && MathIsValidNumber(bufSignal[0])) {
            features.stoch_signal = bufSignal[0];
        } else {
            features.stoch_signal = 50.0; // Default if invalid
        }
        IndicatorRelease(stochHandle);
    } else {
        features.stoch_main = 50.0; // Default if handle invalid
        features.stoch_signal = 50.0;
    }

    // Accumulation/Distribution
    int adHandle = iAD(symbol, tf, VOLUME_TICK);
    if(adHandle != INVALID_HANDLE) {
        double buf[1];
        if(CopyBuffer(adHandle, 0, 0, 1, buf) > 0) features.ad = buf[0];
        IndicatorRelease(adHandle);
    }

    // Volume
    features.volume = (double)iVolume(symbol, tf, 0);

    // MA
    int maHandle = iMA(symbol, tf, 50, 0, MODE_SMA, PRICE_CLOSE);
    if(maHandle != INVALID_HANDLE) {
        double buf[1];
        if(CopyBuffer(maHandle, 0, 0, 1, buf) > 0) features.ma = buf[0];
        IndicatorRelease(maHandle);
    }

    // ATR
    features.atr = GetATR(symbol, tf, 14);

    // MACD
    int macdHandle = iMACD(symbol, tf, 12, 26, 9, PRICE_CLOSE);
    if(macdHandle != INVALID_HANDLE) {
        double bufMain[1], bufSignal[1];
        if(CopyBuffer(macdHandle, 0, 0, 1, bufMain) > 0 && MathIsValidNumber(bufMain[0])) {
            features.macd_main = bufMain[0];
        } else {
            features.macd_main = 0.0; // Default if invalid
        }
        if(CopyBuffer(macdHandle, 1, 0, 1, bufSignal) > 0 && MathIsValidNumber(bufSignal[0])) {
            features.macd_signal = bufSignal[0];
        } else {
            features.macd_signal = 0.0; // Default if invalid
        }
        IndicatorRelease(macdHandle);
    } else {
        features.macd_main = 0.0; // Default if handle invalid
        features.macd_signal = 0.0;
    }

    // Bollinger Bands
    int bbHandle = iBands(symbol, tf, 20, 2, 0, PRICE_CLOSE);
    if(bbHandle != INVALID_HANDLE) {
        double bufUpper[1], bufLower[1];
        if(CopyBuffer(bbHandle, 1, 0, 1, bufUpper) > 0) features.bb_upper = bufUpper[0];
        if(CopyBuffer(bbHandle, 2, 0, 1, bufLower) > 0) features.bb_lower = bufLower[0];
        IndicatorRelease(bbHandle);
    }

    // Spread
    features.spread = GetSpread(symbol);

    // Multi-timeframe trend direction
    features.trend = "none";

    // Current timeframe trend
    bool currentUptrend = false, currentDowntrend = false;
    int currentSMAHandle = iMA(symbol, tf, 20, 0, MODE_SMA, PRICE_CLOSE);
    if(currentSMAHandle != INVALID_HANDLE) {
        double currentSMABuf[2];
        if(CopyBuffer(currentSMAHandle, 0, 0, 2, currentSMABuf) > 0) {
            double currentPrice = iClose(symbol, tf, 0);
            currentUptrend = currentPrice > currentSMABuf[0];
            currentDowntrend = currentPrice < currentSMABuf[0];
        }
        IndicatorRelease(currentSMAHandle);
    }

    // Higher timeframe trend (M15)
    bool higherUptrend = false, higherDowntrend = false;
    int higherSMAHandle = iMA(symbol, PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
    if(higherSMAHandle != INVALID_HANDLE) {
        double higherSMABuf[2];
        if(CopyBuffer(higherSMAHandle, 0, 0, 2, higherSMABuf) > 0) {
            double higherPrice = iClose(symbol, PERIOD_M15, 0);
            higherUptrend = higherPrice > higherSMABuf[0];
            higherDowntrend = higherPrice < higherSMABuf[0];
        }
        IndicatorRelease(higherSMAHandle);
    }

    // Determine overall trend with higher timeframe priority
    if(higherUptrend && currentUptrend) {
        features.trend = "strong_bullish";
    } else if(higherDowntrend && currentDowntrend) {
        features.trend = "strong_bearish";
    } else if(higherUptrend) {
        features.trend = "bullish";
    } else if(higherDowntrend) {
        features.trend = "bearish";
    } else if(currentUptrend) {
        features.trend = "weak_bullish";
    } else if(currentDowntrend) {
        features.trend = "weak_bearish";
    }

    // Candle pattern
    double open[3], close[3], high[3], low[3];
    CopyOpen(symbol, tf, 0, 3, open);
    CopyClose(symbol, tf, 0, 3, close);
    CopyHigh(symbol, tf, 0, 3, high);
    CopyLow(symbol, tf, 0, 3, low);
    features.candle_pattern = "none";
    if(IsBullishEngulfing(open, close, 1)) features.candle_pattern = "bullish_engulfing";
    else if(IsBearishEngulfing(open, close, 1)) features.candle_pattern = "bearish_engulfing";
    else if(IsHammer(open, high, low, close, 0)) features.candle_pattern = "hammer";
    else if(IsShootingStar(open, high, low, close, 0)) features.candle_pattern = "shooting_star";

    // Candle sequence
    string seq = "";
    for(int i=2; i>=0; i--) seq += (close[i]>open[i] ? "B" : "S");
    features.candle_seq = seq;

    // S/D zone context
    DetectSupplyDemandZones(features, symbol, tf);

    // Volume ratio (current volume vs average)
    double avgVolume = 0;
    int validVolumes = 0;

    for(int i = 1; i <= 20; i++) {
        long volume = iVolume(symbol, tf, i);
        if(volume > 0) {
            avgVolume += (double)volume;
            validVolumes++;
        }
    }

    if(validVolumes > 0) {
        avgVolume /= validVolumes;
        features.volume_ratio = avgVolume > 0 ? features.volume / avgVolume : 1.0;

        // Strategy Tester volume handling
        if(features.volume_ratio < 0.1) {
            features.volume_ratio = 0.8 + (MathRand() % 40) / 100.0; // 0.8 to 1.2 range
        }
    } else {
        features.volume_ratio = 1.0; // Neutral volume ratio
    }

    // Price change
    double currentPrice = iClose(symbol, tf, 0);
    features.current_price = currentPrice;
    features.price_change = (currentPrice - iClose(symbol, tf, 1)) / iClose(symbol, tf, 1) * 100;

    // Volatility (ATR as percentage of price)
    features.volatility = features.atr / currentPrice * 100;

    // Additional advanced indicators
    // Williams %R
    int williamsHandle = iWPR(symbol, tf, 14);
    if(williamsHandle != INVALID_HANDLE) {
        double williamsBuf[1];
        if(CopyBuffer(williamsHandle, 0, 0, 1, williamsBuf) > 0) {
            features.williams_r = williamsBuf[0];
        }
        IndicatorRelease(williamsHandle);
    }

    // CCI (Commodity Channel Index)
    int cciHandle = iCCI(symbol, tf, 14, PRICE_TYPICAL);
    if(cciHandle != INVALID_HANDLE) {
        double cciBuf[1];
        if(CopyBuffer(cciHandle, 0, 0, 1, cciBuf) > 0) {
            features.cci = cciBuf[0];
        }
        IndicatorRelease(cciHandle);
    }

    // Momentum
    int momentumHandle = iMomentum(symbol, tf, 14, PRICE_CLOSE);
    if(momentumHandle != INVALID_HANDLE) {
        double momentumBuf[1];
        if(CopyBuffer(momentumHandle, 0, 0, 1, momentumBuf) > 0) {
            features.momentum = momentumBuf[0];
        }
        IndicatorRelease(momentumHandle);
    }

    // Force Index
    features.force_index = features.volume * features.price_change;

    // Price position relative to Bollinger Bands
    if(features.bb_upper > features.bb_lower) {
        features.bb_position = (currentPrice - features.bb_lower) / (features.bb_upper - features.bb_lower);
    } else {
        features.bb_position = 0.5; // Neutral position
    }

    // Session hour
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    features.session_hour = dt.hour;

    // News time (simplified)
    features.is_news_time = false;
}

//--- Helper: Detect Supply/Demand Zones for ML features
void DetectSupplyDemandZones(MLFeatures &features, string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    features.zone_type = "none";
    features.zone_upper = 0;
    features.zone_lower = 0;
    features.zone_start = 0;
    features.zone_end = 0;

    // Get recent price data for zone detection
    double high[50], low[50], close[50];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    if(CopyHigh(symbol, tf, 0, 50, high) > 0 &&
       CopyLow(symbol, tf, 0, 50, low) > 0 &&
       CopyClose(symbol, tf, 0, 50, close) > 0) {

        double currentPrice = close[0];

        // Find recent swing highs and lows
        double swingHighs[10], swingLows[10];
        int highCount = 0, lowCount = 0;

        // Look for swing highs (resistance zones)
        for(int i = 2; i < 48; i++) {
            if(high[i] > high[i-1] && high[i] > high[i-2] &&
               high[i] > high[i+1] && high[i] > high[i+2]) {
                if(highCount < 10) {
                    swingHighs[highCount] = high[i];
                    highCount++;
                }
            }
        }

        // Look for swing lows (support zones)
        for(int i = 2; i < 48; i++) {
            if(low[i] < low[i-1] && low[i] < low[i-2] &&
               low[i] < low[i+1] && low[i] < low[i+2]) {
                if(lowCount < 10) {
                    swingLows[lowCount] = low[i];
                    lowCount++;
                }
            }
        }

        // Check if current price is near a supply zone (resistance)
        for(int i = 0; i < highCount; i++) {
            double zoneUpper = swingHighs[i] + (GetATR(symbol, tf, 14) * 0.5);
            double zoneLower = swingHighs[i] - (GetATR(symbol, tf, 14) * 0.5);

            if(currentPrice >= zoneLower && currentPrice <= zoneUpper) {
                features.zone_type = "supply";
                features.zone_upper = zoneUpper;
                features.zone_lower = zoneLower;
                features.zone_start = TimeCurrent() - (50 - i) * PeriodSeconds(tf);
                features.zone_end = TimeCurrent();
                break;
            }
        }

        // Check if current price is near a demand zone (support)
        if(features.zone_type == "none") {
            for(int i = 0; i < lowCount; i++) {
                double zoneUpper = swingLows[i] + (GetATR(symbol, tf, 14) * 0.5);
                double zoneLower = swingLows[i] - (GetATR(symbol, tf, 14) * 0.5);

                if(currentPrice >= zoneLower && currentPrice <= zoneUpper) {
                    features.zone_type = "demand";
                    features.zone_upper = zoneUpper;
                    features.zone_lower = zoneLower;
                    features.zone_start = TimeCurrent() - (50 - i) * PeriodSeconds(tf);
                    features.zone_end = TimeCurrent();
                    break;
                }
            }
        }
    }
}

//--- Helper: Get ML prediction using loaded parameters
double GetMLPrediction(MLFeatures &features, string direction = "combined") {
    double prediction = 0.5; // Neutral starting point

    // Select appropriate model parameters based on direction
    double rsi_bullish, rsi_bearish, rsi_weight;
    double stoch_bullish, stoch_bearish, stoch_weight;
    double volume_threshold, volume_weight;
    double macd_threshold, macd_weight;
    double trend_weight;
    double pattern_bullish, pattern_bearish;
    double zone_weight;

    if(direction == "buy") {
        // Use BUY-specific parameters
        rsi_bullish = globalBuyRSIBullishThreshold;
        rsi_bearish = globalBuyRSIBearishThreshold;
        rsi_weight = globalBuyRSIWeight;
        stoch_bullish = globalBuyStochBullishThreshold;
        stoch_bearish = globalBuyStochBearishThreshold;
        stoch_weight = globalBuyStochWeight;
        volume_threshold = globalBuyVolumeRatioThreshold;
        volume_weight = globalBuyVolumeWeight;
        macd_threshold = globalBuyMACDThreshold;
        macd_weight = globalBuyMACDWeight;
        trend_weight = globalBuyTrendWeight;
        pattern_bullish = globalBuyPatternBullishWeight;
        pattern_bearish = globalBuyPatternBearishWeight;
        zone_weight = globalBuyZoneWeight;
    } else if(direction == "sell") {
        // Use SELL-specific parameters
        rsi_bullish = globalSellRSIBullishThreshold;
        rsi_bearish = globalSellRSIBearishThreshold;
        rsi_weight = globalSellRSIWeight;
        stoch_bullish = globalSellStochBullishThreshold;
        stoch_bearish = globalSellStochBearishThreshold;
        stoch_weight = globalSellStochWeight;
        volume_threshold = globalSellVolumeRatioThreshold;
        volume_weight = globalSellVolumeWeight;
        macd_threshold = globalSellMACDThreshold;
        macd_weight = globalSellMACDWeight;
        trend_weight = globalSellTrendWeight;
        pattern_bullish = globalSellPatternBullishWeight;
        pattern_bearish = globalSellPatternBearishWeight;
        zone_weight = globalSellZoneWeight;
    } else {
        // Use COMBINED parameters
        rsi_bullish = globalRSIBullishThreshold;
        rsi_bearish = globalRSIBearishThreshold;
        rsi_weight = globalRSIWeight;
        stoch_bullish = globalStochBullishThreshold;
        stoch_bearish = globalStochBearishThreshold;
        stoch_weight = globalStochWeight;
        volume_threshold = globalVolumeRatioThreshold;
        volume_weight = globalVolumeWeight;
        macd_threshold = globalMACDThreshold;
        macd_weight = globalMACDWeight;
        trend_weight = globalTrendWeight;
        pattern_bullish = globalPatternBullishWeight;
        pattern_bearish = globalPatternBearishWeight;
        zone_weight = globalZoneWeight;
    }

    // RSI signals
    if(features.rsi < rsi_bullish) {
        double rsi_strength = (rsi_bullish - features.rsi) / rsi_bullish; // 0 to 1
        prediction += rsi_weight * rsi_strength;
    } else if(features.rsi > rsi_bearish) {
        double rsi_strength = (features.rsi - rsi_bearish) / (100.0 - rsi_bearish); // 0 to 1
        prediction -= rsi_weight * rsi_strength;
    } else {
        // RSI in neutral zone - give small bullish bias if above 50
        if(features.rsi > 50.0) {
            prediction += rsi_weight * 0.3; // Small bullish bias
        } else {
            prediction -= rsi_weight * 0.3; // Small bearish bias
        }
    }

    // Stochastic signals
    if(features.stoch_main < stoch_bullish) {
        double stoch_strength = (stoch_bullish - features.stoch_main) / stoch_bullish; // 0 to 1
        prediction += stoch_weight * stoch_strength;
    } else if(features.stoch_main > stoch_bearish) {
        double stoch_strength = (features.stoch_main - stoch_bearish) / (100.0 - stoch_bearish); // 0 to 1
        prediction -= stoch_weight * stoch_strength;
    } else {
        // Stochastic in neutral zone - give small bias based on position
        if(features.stoch_main > 50.0) {
            prediction += stoch_weight * 0.3; // Small bullish bias
        } else {
            prediction -= stoch_weight * 0.3; // Small bearish bias
        }
    }

    // MACD signals
    double macd_diff = features.macd_main - features.macd_signal;
    if(macd_diff > macd_threshold) {
        double macd_strength = MathMin(macd_diff / 0.001, 1.0); // Normalize to reasonable range
        prediction += macd_weight * macd_strength;
    } else if(macd_diff < -macd_threshold) {
        double macd_strength = MathMin(MathAbs(macd_diff) / 0.001, 1.0);
        prediction -= macd_weight * macd_strength;
    }

    // Volume confirmation
    if(features.volume_ratio > volume_threshold) {
        double volume_strength = MathMin((features.volume_ratio - volume_threshold) / volume_threshold, 1.0);
        prediction += volume_weight * volume_strength;
    } else if(features.volume_ratio > 0.8) {
        // Even if not above threshold, give some credit for reasonable volume
        prediction += volume_weight * 0.3;
    }

    // Trend alignment
    if(features.trend == "bullish") {
        prediction += trend_weight;
    } else if(features.trend == "bearish") {
        prediction -= trend_weight;
    }

    // Candle pattern signals
    if(features.candle_pattern == "bullish_engulfing")
        prediction += pattern_bullish;
    else if(features.candle_pattern == "bearish_engulfing")
        prediction -= pattern_bearish;
    else if(features.candle_pattern == "hammer")
        prediction += pattern_bullish * 0.8; // Slightly less weight
    else if(features.candle_pattern == "shooting_star")
        prediction -= pattern_bearish * 0.8; // Slightly less weight

    // Zone context
    if(features.zone_type == "demand")
        prediction += zone_weight;
    else if(features.zone_type == "supply")
        prediction -= zone_weight;

    // Normalize to 0-1 range
    prediction = MathMax(0.0, MathMin(1.0, prediction));

    return prediction;
}

//--- Helper: Calculate ML confidence
double CalculateMLConfidence(MLFeatures &features, string direction = "combined") {
    // Use direction-specific ML-optimized parameters
    double base_confidence, signal_agreement_weight;
    double rsi_bullish, rsi_bearish;
    double stoch_bullish, stoch_bearish;
    double volume_threshold, macd_threshold;

    if(direction == "buy") {
        // Use BUY-specific parameters
        base_confidence = globalBuyBaseConfidence;
        signal_agreement_weight = globalBuySignalAgreementWeight;
        rsi_bullish = globalBuyRSIBullishThreshold;
        rsi_bearish = globalBuyRSIBearishThreshold;
        stoch_bullish = globalBuyStochBullishThreshold;
        stoch_bearish = globalBuyStochBearishThreshold;
        volume_threshold = globalBuyVolumeRatioThreshold;
        macd_threshold = globalBuyMACDThreshold;
    } else if(direction == "sell") {
        // Use SELL-specific parameters
        base_confidence = globalSellBaseConfidence;
        signal_agreement_weight = globalSellSignalAgreementWeight;
        rsi_bullish = globalSellRSIBullishThreshold;
        rsi_bearish = globalSellRSIBearishThreshold;
        stoch_bullish = globalSellStochBullishThreshold;
        stoch_bearish = globalSellStochBearishThreshold;
        volume_threshold = globalSellVolumeRatioThreshold;
        macd_threshold = globalSellMACDThreshold;
    } else {
        // Use COMBINED parameters
        base_confidence = globalBaseConfidence;
        signal_agreement_weight = globalSignalAgreementWeight;
        rsi_bullish = globalRSIBullishThreshold;
        rsi_bearish = globalRSIBearishThreshold;
        stoch_bullish = globalStochBullishThreshold;
        stoch_bearish = globalStochBearishThreshold;
        volume_threshold = globalVolumeRatioThreshold;
        macd_threshold = globalMACDThreshold;
    }

    double confidence = base_confidence;

    // Count agreeing signals
    int bullishSignals = 0;
    int bearishSignals = 0;

    // RSI
    if(features.rsi < rsi_bullish) bullishSignals++;
    else if(features.rsi > rsi_bearish) bearishSignals++;

    // Stochastic
    if(features.stoch_main < stoch_bullish) bullishSignals++;
    else if(features.stoch_main > stoch_bearish) bearishSignals++;

    // MACD
    if(features.macd_main > features.macd_signal + macd_threshold) bullishSignals++;
    else bearishSignals++;

    // Volume
    if(features.volume_ratio > volume_threshold) bullishSignals++;

    // Trend
    if(features.trend == "bullish") bullishSignals++;
    else if(features.trend == "bearish") bearishSignals++;

    // Candle pattern
    if(features.candle_pattern == "bullish_engulfing" || features.candle_pattern == "hammer") bullishSignals++;
    else if(features.candle_pattern == "bearish_engulfing" || features.candle_pattern == "shooting_star") bearishSignals++;

    // Zone
    if(features.zone_type == "demand") bullishSignals++;
    else if(features.zone_type == "supply") bearishSignals++;

    // Calculate confidence based on signal agreement
    int totalSignals = bullishSignals + bearishSignals;
    if(totalSignals > 0) {
        int maxSignals = MathMax(bullishSignals, bearishSignals);
        confidence = base_confidence + (double)maxSignals / (double)totalSignals * signal_agreement_weight;
    }

    // Add some base confidence for having any signals
    if(totalSignals > 0) {
        confidence += 0.05; // Reduced bonus to prevent overflow
    }

    // Ensure minimum confidence
    confidence = MathMax(confidence, 0.5); // Increased minimum to 50% confidence
    confidence = MathMin(confidence, 0.85); // Reduced cap to 85% to prevent overflow

    return confidence;
}

//--- Helper: Calculate dynamic position size
double CalculateDynamicPositionSize(double baseLot, double signalStrength, double mlConfidence, double volatility, bool useVolatilityAdjustment = true) {
    // Start with base multiplier
    double positionMultiplier = 1.0;

    // 1. Signal Strength Adjustment (0.5x to 1.5x)
    // Higher signal strength = larger position
    double signalMultiplier = 0.5 + (signalStrength * 1.0); // 0.5 to 1.5
    positionMultiplier *= signalMultiplier;

    // 2. ML Confidence Adjustment (0.8x to 1.2x)
    // Higher ML confidence = larger position
    double confidenceMultiplier = 0.8 + (mlConfidence * 0.4); // 0.8 to 1.2
    positionMultiplier *= confidenceMultiplier;

    // 3. Volatility Adjustment (if enabled)
    if(useVolatilityAdjustment) {
        // Lower volatility = larger position (more predictable)
        // Higher volatility = smaller position (more risky)
        double avgVolatility = 0.5; // Average volatility (50%)
        double volatilityRatio = avgVolatility / MathMax(volatility, 0.1); // Avoid division by zero
        double volatilityMultiplier = MathMax(0.7, MathMin(1.3, volatilityRatio)); // 0.7 to 1.3
        positionMultiplier *= volatilityMultiplier;
    }

    // 4. Apply ML position sizing
    double mlPositionMultiplier = 1.0;
    mlPositionMultiplier = globalPositionSizingMultiplier;
    positionMultiplier *= mlPositionMultiplier;

    // 5. Apply limits
    positionMultiplier = MathMax(0.5, MathMin(2.0, positionMultiplier));

    // Calculate final position size
    double finalLot = baseLot * positionMultiplier;

    return finalLot;
}

//+------------------------------------------------------------------+
//| Get current session based on time                                 |
//+------------------------------------------------------------------+
string GetCurrentSession() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = dt.hour;

    // Use default session times if not defined
    int londonStart = 8, londonEnd = 16;
    int nyStart = 13, nyEnd = 22;
    int asianStart = 1, asianEnd = 10;

    if(currentHour >= londonStart && currentHour < londonEnd) {
        return "london";
    } else if(currentHour >= nyStart && currentHour < nyEnd) {
        return "ny";
    } else if(currentHour >= asianStart && currentHour < asianEnd) {
        return "asian";
    } else {
        return "off_hours";
    }
}

//+------------------------------------------------------------------+
//| Get symbol session recommendation                                 |
//+------------------------------------------------------------------+
string GetSymbolSessionRecommendation(string symbol) {
    // This function would return ML-based session recommendations
    // For now, return a default recommendation
    return "london_ny";
}

//+------------------------------------------------------------------+
//| Advanced session filtering with ML parameters                     |
//+------------------------------------------------------------------+
bool IsOptimalSessionAdvanced(string symbol, bool useAdvanced, bool useCondition,
                              bool useVolatility, bool useTrend, bool useRSI,
                              double minSuccessRate, int minTrades) {
    // This function implements advanced session filtering
    // For now, return true to allow all sessions
    return true;
}

//+------------------------------------------------------------------+
//| Volume analysis structure and function                            |
//+------------------------------------------------------------------+
struct VolumeAnalysis {
    long currentVolume;
    long averageVolume;
    double volumeRatio;
    bool isHighVolume;
    bool isOptimalVolume;
};

VolumeAnalysis AnalyzeVolume(int period, double minRatio, double optimalRatio, bool enableDebug) {
    VolumeAnalysis analysis;

    // Get current volume
    analysis.currentVolume = iVolume(_Symbol, _Period, 0);

    // Calculate average volume
    long volumes[];
    ArraySetAsSeries(volumes, true);
    int copied = CopyTickVolume(_Symbol, _Period, 1, period, volumes);

    if(copied > 0) {
        long totalVolume = 0;
        for(int i = 0; i < copied; i++) {
            totalVolume += volumes[i];
        }
        analysis.averageVolume = totalVolume / copied;
    } else {
        analysis.averageVolume = analysis.currentVolume;
    }

    // Calculate volume ratio
    analysis.volumeRatio = analysis.averageVolume > 0 ? (double)analysis.currentVolume / analysis.averageVolume : 1.0;

    // Determine volume characteristics
    analysis.isHighVolume = analysis.volumeRatio >= minRatio;
    analysis.isOptimalVolume = analysis.volumeRatio >= optimalRatio;

    return analysis;
}

//--- Helper: Get currency pair-specific parameter file
string GetCurrencyPairParamFile(string eaName = "") {
    string symbol = _Symbol;

    // Remove the + suffix if present (broker-specific naming)
    string baseSymbol = symbol;
    if(StringFind(symbol, "+") >= 0) {
        baseSymbol = StringSubstr(symbol, 0, StringFind(symbol, "+"));
    }

    // Map symbols to specific parameter files
    if(baseSymbol == "EURUSD") return eaName + "/ml_model_params_EURUSD.txt";
    else if(baseSymbol == "GBPUSD") return eaName + "/ml_model_params_GBPUSD.txt";
    else if(baseSymbol == "USDJPY") return eaName + "/ml_model_params_USDJPY.txt";
    else if(baseSymbol == "GBPJPY") return eaName + "/ml_model_params_GBPJPY.txt";
    else if(baseSymbol == "XAUUSD") return eaName + "/ml_model_params_XAUUSD.txt";
    else {
        // For other pairs, use generic file
        return eaName + "/ml_model_params_simple.txt";
    }
}

//--- Helper: Update EA input parameters based on ML training results
void UpdateEAInputParameters(string eaName = "", string timeframe = "") {
    string paramFile;

    // If timeframe is specified, try to load timeframe-specific parameters
    if(timeframe != "") {
        paramFile = eaName + "/ml_model_params_" + timeframe + ".txt";
        Print("🔍 Looking for timeframe-specific parameters: ", paramFile);

        int handle = FileOpen(paramFile, FILE_TXT|FILE_ANSI|FILE_READ|FILE_COMMON, ',');
        if(handle != INVALID_HANDLE) {
            Print("✅ Found timeframe-specific parameters for ", timeframe);
            FileClose(handle);
        } else {
            Print("⚠️  No timeframe-specific parameters found, falling back to symbol-specific parameters");
            paramFile = GetCurrencyPairParamFile(eaName);
        }
    } else {
        paramFile = GetCurrencyPairParamFile(eaName);
    }

    // Load the latest ML model parameters (simple key=value format)
    int handle = FileOpen(paramFile, FILE_TXT|FILE_ANSI|FILE_READ|FILE_COMMON, ',');
    if(handle == INVALID_HANDLE) {
        Print("⚠️  No ML model parameters found for ", _Symbol, ", using default input parameters");
        Print("💡 To optimize for ", _Symbol, ", run ML training and ensure ", paramFile, " exists");
        return;
    }

    // Parse simple key=value format - Load ALL ML parameters
    while(!FileIsEnding(handle)) {
        string line = FileReadString(handle);

        // Skip empty lines
        if(StringLen(line) == 0) continue;

        // Parse key=value format
        int equalPos = StringFind(line, "=");
        if(equalPos > 0) {
            string key = StringSubstr(line, 0, equalPos);
            string valueStr = StringSubstr(line, equalPos + 1);
            double value = StringToDouble(valueStr);

            if(MathIsValidNumber(value)) {
                // Update global parameters based on key
                if(StringFind(key, "combined_min_prediction_threshold") >= 0) {
                    globalMinPredictionThreshold = value;
                }
                else if(StringFind(key, "combined_max_prediction_threshold") >= 0) {
                    globalMaxPredictionThreshold = value;
                }
                else if(StringFind(key, "combined_min_confidence") >= 0) {
                    globalMinPredictionConfidence = value;
                }
                else if(StringFind(key, "combined_max_confidence") >= 0) {
                    globalMaxPredictionConfidence = value;
                }
                else if(StringFind(key, "combined_position_sizing_multiplier") >= 0) {
                    globalPositionSizingMultiplier = value;
                }
                else if(StringFind(key, "combined_stop_loss_adjustment") >= 0) {
                    globalStopLossAdjustment = value;
                }

                // RSI Parameters
                else if(StringFind(key, "combined_rsi_bullish_threshold") >= 0) {
                    globalRSIBullishThreshold = value;
                }
                else if(StringFind(key, "combined_rsi_bearish_threshold") >= 0) {
                    globalRSIBearishThreshold = value;
                }
                else if(StringFind(key, "combined_rsi_weight") >= 0) {
                    globalRSIWeight = value;
                }

                // Stochastic Parameters
                else if(StringFind(key, "combined_stoch_bullish_threshold") >= 0) {
                    globalStochBullishThreshold = value;
                }
                else if(StringFind(key, "combined_stoch_bearish_threshold") >= 0) {
                    globalStochBearishThreshold = value;
                }
                else if(StringFind(key, "combined_stoch_weight") >= 0) {
                    globalStochWeight = value;
                }

                // MACD Parameters
                else if(StringFind(key, "combined_macd_threshold") >= 0) {
                    globalMACDThreshold = value;
                }
                else if(StringFind(key, "combined_macd_weight") >= 0) {
                    globalMACDWeight = value;
                }

                // Volume Parameters
                else if(StringFind(key, "combined_volume_ratio_threshold") >= 0) {
                    globalVolumeRatioThreshold = value;
                }
                else if(StringFind(key, "combined_volume_weight") >= 0) {
                    globalVolumeWeight = value;
                }

                // Pattern Parameters
                else if(StringFind(key, "combined_pattern_bullish_weight") >= 0) {
                    globalPatternBullishWeight = value;
                }
                else if(StringFind(key, "combined_pattern_bearish_weight") >= 0) {
                    globalPatternBearishWeight = value;
                }

                // Zone and Trend Parameters
                else if(StringFind(key, "combined_zone_weight") >= 0) {
                    globalZoneWeight = value;
                }
                else if(StringFind(key, "combined_trend_weight") >= 0) {
                    globalTrendWeight = value;
                }

                // Confidence Parameters
                else if(StringFind(key, "combined_base_confidence") >= 0) {
                    globalBaseConfidence = value;
                }
                else if(StringFind(key, "combined_signal_agreement_weight") >= 0) {
                    globalSignalAgreementWeight = value;
                }

                // BUY Model Parameters
                else if(StringFind(key, "buy_rsi_bullish_threshold") >= 0) {
                    globalBuyRSIBullishThreshold = value;
                }
                else if(StringFind(key, "buy_rsi_bearish_threshold") >= 0) {
                    globalBuyRSIBearishThreshold = value;
                }
                else if(StringFind(key, "buy_rsi_weight") >= 0) {
                    globalBuyRSIWeight = value;
                }
                else if(StringFind(key, "buy_stoch_bullish_threshold") >= 0) {
                    globalBuyStochBullishThreshold = value;
                }
                else if(StringFind(key, "buy_stoch_bearish_threshold") >= 0) {
                    globalBuyStochBearishThreshold = value;
                }
                else if(StringFind(key, "buy_stoch_weight") >= 0) {
                    globalBuyStochWeight = value;
                }
                else if(StringFind(key, "buy_macd_threshold") >= 0) {
                    globalBuyMACDThreshold = value;
                }
                else if(StringFind(key, "buy_macd_weight") >= 0) {
                    globalBuyMACDWeight = value;
                }
                else if(StringFind(key, "buy_volume_ratio_threshold") >= 0) {
                    globalBuyVolumeRatioThreshold = value;
                }
                else if(StringFind(key, "buy_volume_weight") >= 0) {
                    globalBuyVolumeWeight = value;
                }
                else if(StringFind(key, "buy_pattern_bullish_weight") >= 0) {
                    globalBuyPatternBullishWeight = value;
                }
                else if(StringFind(key, "buy_pattern_bearish_weight") >= 0) {
                    globalBuyPatternBearishWeight = value;
                }
                else if(StringFind(key, "buy_zone_weight") >= 0) {
                    globalBuyZoneWeight = value;
                }
                else if(StringFind(key, "buy_trend_weight") >= 0) {
                    globalBuyTrendWeight = value;
                }
                else if(StringFind(key, "buy_base_confidence") >= 0) {
                    globalBuyBaseConfidence = value;
                }
                else if(StringFind(key, "buy_signal_agreement_weight") >= 0) {
                    globalBuySignalAgreementWeight = value;
                }
                else if(StringFind(key, "buy_min_prediction_threshold") >= 0) {
                    globalBuyMinPredictionThreshold = value;
                }
                else if(StringFind(key, "buy_max_prediction_threshold") >= 0) {
                    globalBuyMaxPredictionThreshold = value;
                }
                else if(StringFind(key, "buy_min_confidence") >= 0) {
                    globalBuyMinConfidence = value;
                }
                else if(StringFind(key, "buy_max_confidence") >= 0) {
                    globalBuyMaxConfidence = value;
                }
                else if(StringFind(key, "buy_position_sizing_multiplier") >= 0) {
                    globalBuyPositionSizingMultiplier = value;
                }
                else if(StringFind(key, "buy_stop_loss_adjustment") >= 0) {
                    globalBuyStopLossAdjustment = value;
                }

                // SELL Model Parameters
                else if(StringFind(key, "sell_rsi_bullish_threshold") >= 0) {
                    globalSellRSIBullishThreshold = value;
                }
                else if(StringFind(key, "sell_rsi_bearish_threshold") >= 0) {
                    globalSellRSIBearishThreshold = value;
                }
                else if(StringFind(key, "sell_rsi_weight") >= 0) {
                    globalSellRSIWeight = value;
                }
                else if(StringFind(key, "sell_stoch_bullish_threshold") >= 0) {
                    globalSellStochBullishThreshold = value;
                }
                else if(StringFind(key, "sell_stoch_bearish_threshold") >= 0) {
                    globalSellStochBearishThreshold = value;
                }
                else if(StringFind(key, "sell_stoch_weight") >= 0) {
                    globalSellStochWeight = value;
                }
                else if(StringFind(key, "sell_macd_threshold") >= 0) {
                    globalSellMACDThreshold = value;
                }
                else if(StringFind(key, "sell_macd_weight") >= 0) {
                    globalSellMACDWeight = value;
                }
                else if(StringFind(key, "sell_volume_ratio_threshold") >= 0) {
                    globalSellVolumeRatioThreshold = value;
                }
                else if(StringFind(key, "sell_volume_weight") >= 0) {
                    globalSellVolumeWeight = value;
                }
                else if(StringFind(key, "sell_pattern_bullish_weight") >= 0) {
                    globalSellPatternBullishWeight = value;
                }
                else if(StringFind(key, "sell_pattern_bearish_weight") >= 0) {
                    globalSellPatternBearishWeight = value;
                }
                else if(StringFind(key, "sell_zone_weight") >= 0) {
                    globalSellZoneWeight = value;
                }
                else if(StringFind(key, "sell_trend_weight") >= 0) {
                    globalSellTrendWeight = value;
                }
                else if(StringFind(key, "sell_base_confidence") >= 0) {
                    globalSellBaseConfidence = value;
                }
                else if(StringFind(key, "sell_signal_agreement_weight") >= 0) {
                    globalSellSignalAgreementWeight = value;
                }
                else if(StringFind(key, "sell_min_prediction_threshold") >= 0) {
                    globalSellMinPredictionThreshold = value;
                }
                else if(StringFind(key, "sell_max_prediction_threshold") >= 0) {
                    globalSellMaxPredictionThreshold = value;
                }
                else if(StringFind(key, "sell_min_confidence") >= 0) {
                    globalSellMinConfidence = value;
                }
                else if(StringFind(key, "sell_max_confidence") >= 0) {
                    globalSellMaxConfidence = value;
                }
                else if(StringFind(key, "sell_position_sizing_multiplier") >= 0) {
                    globalSellPositionSizingMultiplier = value;
                }
                else if(StringFind(key, "sell_stop_loss_adjustment") >= 0) {
                    globalSellStopLossAdjustment = value;
                }
            }
        }
    }
    FileClose(handle);

    Print("✅ ML-optimized parameters loaded from: ", paramFile);
}

//+------------------------------------------------------------------+
//| Data Collection and ML Utilities                                 |
//+------------------------------------------------------------------+

//--- TradeData structure for OnTester function
struct TradeData {
    int ticket;
    int trade_id;
    string symbol;
    string type;
    double volume;
    double open_price;
    double close_price;
    datetime open_time;
    datetime close_time;
    double profit;
    double swap;
    double commission;
    double net_profit;
    string trading_conditions_json;
};

//--- TradeInfo structure for ML data collection
struct TradeInfo {
    ulong ticket;
    string symbol;
    string direction;
    double entry_price;
    double stop_loss;
    double take_profit;
    double lot_size;
    datetime entry_time;
    MLFeatures features;
    double actual_profit;
    bool is_closed;
    datetime close_time;
    int trade_number;
    int trade_id;
};

//+------------------------------------------------------------------+
//| Generate unique test run identifier                              |
//+------------------------------------------------------------------+
string GenerateTestRunID(string customIdentifier = "", string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    // If user provided a custom identifier, use it
    if(StringLen(customIdentifier) > 0) {
        return customIdentifier;
    }

    // Generate unique identifier based on timestamp, symbol, and random component
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Add milliseconds and random component for uniqueness
    int randomComponent = MathRand() % 10000; // 0-9999 random number

    string uniqueID = symbol + "_" +
                     IntegerToString(dt.year) +
                     StringFormat("%02d", dt.mon) +
                     StringFormat("%02d", dt.day) + "_" +
                     StringFormat("%02d", dt.hour) +
                     StringFormat("%02d", dt.min) +
                     StringFormat("%02d", dt.sec) + "_" +
                     StringFormat("%04d", randomComponent) + "_" +
                     EnumToString(tf);

    return uniqueID;
}

//+------------------------------------------------------------------+
//| Collect trade data from history                                  |
//+------------------------------------------------------------------+
int CollectTradeDataFromHistory(TradeData &trades[], string symbol = NULL) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;

    int tradeCount = 0;

    if(HistorySelect(0, TimeCurrent())) {
        uint totalDeals = HistoryDealsTotal();
        Print("📊 Found ", totalDeals, " total deals in history");

        for(uint i = 0; i < totalDeals; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0) {
                // Only process deals for this symbol
                if(HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol) {
                    // Skip opening deals, only process closing deals
                    if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
                        ArrayResize(trades, tradeCount + 1);

                        trades[tradeCount].ticket = (int)ticket;
                        // Calculate trade_id based on ticket value to match ML data
                        // Formula: trade_id = (ticket - 1) / 2
                        trades[tradeCount].trade_id = (int)((ticket - 1) / 2);
                        trades[tradeCount].symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
                        trades[tradeCount].volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                        trades[tradeCount].close_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
                        trades[tradeCount].close_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                        trades[tradeCount].profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                        trades[tradeCount].swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
                        trades[tradeCount].commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

                        // Find the corresponding opening deal to get entry information
                        ulong positionId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
                        bool foundOpeningDeal = false;
                        for(uint j = 0; j < totalDeals; j++) {
                            ulong openTicket = HistoryDealGetTicket(j);
                            if(openTicket == positionId) {
                                trades[tradeCount].open_price = HistoryDealGetDouble(openTicket, DEAL_PRICE);
                                trades[tradeCount].open_time = (datetime)HistoryDealGetInteger(openTicket, DEAL_TIME);
                                trades[tradeCount].type = (HistoryDealGetInteger(openTicket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";

                                // Add commission from opening deal
                                trades[tradeCount].commission += HistoryDealGetDouble(openTicket, DEAL_COMMISSION);

                                foundOpeningDeal = true;
                                break;
                            }
                        }

                        // Calculate net profit after getting all commission data
                        trades[tradeCount].net_profit = trades[tradeCount].profit + trades[tradeCount].swap + trades[tradeCount].commission;

                        // If we couldn't find the opening deal, use the closing deal type as fallback
                        if(!foundOpeningDeal) {
                            trades[tradeCount].type = (HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
                            Print("⚠️  Could not find opening deal for position ", positionId, ", using closing deal type as fallback");
                        }

                        // If we couldn't find the opening deal, use the close price as fallback
                        if(trades[tradeCount].open_price == 0) {
                            trades[tradeCount].open_price = trades[tradeCount].close_price;
                            trades[tradeCount].open_time = trades[tradeCount].close_time - 3600; // Assume 1 hour duration
                        }

                        tradeCount++;

                        if(tradeCount <= 5) { // Only print first few for debugging
                            Print("✅ Trade ", tradeCount, ": ", trades[tradeCount-1].type,
                                  " Entry: ", DoubleToString(trades[tradeCount-1].open_price, _Digits),
                                  " Exit: ", DoubleToString(trades[tradeCount-1].close_price, _Digits),
                                  " Profit: $", DoubleToString(trades[tradeCount-1].net_profit, 2));
                        }
                    }
                }
            }
        }

        Print("📊 Successfully collected ", tradeCount, " completed trades");
    } else {
        Print("❌ Failed to select history for trade collection");
    }

    return tradeCount;
}

//+------------------------------------------------------------------+
//| Collect ML data for trade                                        |
//+------------------------------------------------------------------+
void CollectMLDataForTrade(TradeInfo &tradeInfo, string direction, double entry, double sl, double tp, double lot, string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    // Collect comprehensive ML features
    CollectMLFeatures(tradeInfo.features, symbol, tf);

    // Update trade-specific data
    tradeInfo.features.entry_price = entry;
    tradeInfo.features.stop_loss = sl;
    tradeInfo.features.take_profit = tp;
    tradeInfo.features.lot_size = lot;
    tradeInfo.features.trade_direction = direction;
    tradeInfo.features.trade_time = TimeCurrent();

    // Update trade info
    tradeInfo.symbol = symbol;
    tradeInfo.direction = direction;
    tradeInfo.entry_price = entry;
    tradeInfo.stop_loss = sl;
    tradeInfo.take_profit = tp;
    tradeInfo.lot_size = lot;
    tradeInfo.entry_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Save ML data to file                                             |
//+------------------------------------------------------------------+
void SaveMLData(const TradeInfo &tradeInfo, string fileName, string testRunID = "", string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    string json = "{";
    json += "\"trade_id\":" + IntegerToString(tradeInfo.trade_id) + ",";
    json += "\"test_run_id\":\"" + testRunID + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":\"" + EnumToString(tf) + "\",";
    json += "\"direction\":\"" + tradeInfo.features.trade_direction + "\",";
    json += "\"lot\":" + DoubleToString(tradeInfo.features.lot_size, 2) + ",";
    json += "\"sl\":" + DoubleToString(tradeInfo.features.stop_loss, _Digits) + ",";
    json += "\"tp\":" + DoubleToString(tradeInfo.features.take_profit, _Digits) + ",";
    json += "\"entry\":" + DoubleToString(tradeInfo.features.entry_price, _Digits) + ",";
    json += "\"rsi\":" + DoubleToString(tradeInfo.features.rsi, 2) + ",";
    json += "\"stoch_main\":" + DoubleToString(tradeInfo.features.stoch_main, 2) + ",";
    json += "\"stoch_signal\":" + DoubleToString(tradeInfo.features.stoch_signal, 2) + ",";
    json += "\"ad\":" + DoubleToString(tradeInfo.features.ad, 2) + ",";
    json += "\"volume\":" + DoubleToString(tradeInfo.features.volume, 0) + ",";
    json += "\"ma\":" + DoubleToString(tradeInfo.features.ma, _Digits) + ",";
    json += "\"atr\":" + DoubleToString(tradeInfo.features.atr, _Digits) + ",";
    json += "\"macd_main\":" + DoubleToString(tradeInfo.features.macd_main, 4) + ",";
    json += "\"macd_signal\":" + DoubleToString(tradeInfo.features.macd_signal, 4) + ",";
    json += "\"bb_upper\":" + DoubleToString(tradeInfo.features.bb_upper, _Digits) + ",";
    json += "\"bb_lower\":" + DoubleToString(tradeInfo.features.bb_lower, _Digits) + ",";
    json += "\"spread\":" + DoubleToString(tradeInfo.features.spread, 1) + ",";
    json += "\"candle_pattern\":\"" + tradeInfo.features.candle_pattern + "\",";
    json += "\"candle_seq\":\"" + tradeInfo.features.candle_seq + "\",";
    json += "\"zone_type\":\"" + tradeInfo.features.zone_type + "\",";
    json += "\"zone_upper\":" + DoubleToString(tradeInfo.features.zone_upper, _Digits) + ",";
    json += "\"zone_lower\":" + DoubleToString(tradeInfo.features.zone_lower, _Digits) + ",";
    json += "\"zone_start\":" + IntegerToString(tradeInfo.features.zone_start) + ",";
    json += "\"zone_end\":" + IntegerToString(tradeInfo.features.zone_end) + ",";
    json += "\"trend\":\"" + tradeInfo.features.trend + "\",";
    json += "\"volume_ratio\":" + DoubleToString(tradeInfo.features.volume_ratio, 2) + ",";
    json += "\"price_change\":" + DoubleToString(tradeInfo.features.price_change, 2) + ",";
    json += "\"volatility\":" + DoubleToString(tradeInfo.features.volatility, 2) + ",";
    json += "\"williams_r\":" + DoubleToString(tradeInfo.features.williams_r, 2) + ",";
    json += "\"cci\":" + DoubleToString(tradeInfo.features.cci, 2) + ",";
    json += "\"momentum\":" + DoubleToString(tradeInfo.features.momentum, 2) + ",";
    json += "\"force_index\":" + DoubleToString(tradeInfo.features.force_index, 2) + ",";
    json += "\"bb_position\":" + DoubleToString(tradeInfo.features.bb_position, 4) + ",";
    json += "\"session_hour\":" + IntegerToString(tradeInfo.features.session_hour) + ",";
    json += "\"is_news_time\":" + (tradeInfo.features.is_news_time ? "true" : "false") + ",";
    json += "\"current_price\":" + DoubleToString(tradeInfo.features.current_price, _Digits) + ",";
    json += "\"entry_price\":" + DoubleToString(tradeInfo.features.entry_price, _Digits) + ",";
    json += "\"stop_loss\":" + DoubleToString(tradeInfo.features.stop_loss, _Digits) + ",";
    json += "\"take_profit\":" + DoubleToString(tradeInfo.features.take_profit, _Digits) + ",";
    json += "\"lot_size\":" + DoubleToString(tradeInfo.features.lot_size, 2) + ",";
    json += "\"trade_direction\":\"" + tradeInfo.features.trade_direction + "\",";
    json += "\"trade_time\":" + IntegerToString(tradeInfo.features.trade_time) + ",";
    json += "\"timestamp\":" + IntegerToString(TimeCurrent()) + "}";

    // Save to file
    int handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_READ|FILE_WRITE|FILE_COMMON, '\n');
    if(handle == INVALID_HANDLE) {
        handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
        if(handle != INVALID_HANDLE) {
            FileWrite(handle, "{\"trades\":[" + json + "]}");
            FileClose(handle);
        }
    } else {
        string existingContent = "";
        while(!FileIsEnding(handle)) {
            existingContent += FileReadString(handle);
        }
        FileClose(handle);

        if(StringLen(existingContent) > 0) {
            int lastBracketPos = StringFind(existingContent, "]}");
            if(lastBracketPos > 0) {
                string newContent = StringSubstr(existingContent, 0, lastBracketPos) + "," + json + "]}";
                handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
                if(handle != INVALID_HANDLE) {
                    FileWrite(handle, newContent);
                    FileClose(handle);
                }
            }
        } else {
            handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
            if(handle != INVALID_HANDLE) {
                FileWrite(handle, "{\"trades\":[" + json + "]}");
                FileClose(handle);
            }
        }
    }

    Print("📊 Enhanced ML data saved for ", tradeInfo.features.trade_direction, " trade");
}

//+------------------------------------------------------------------+
//| Save trade results for ML training                               |
//+------------------------------------------------------------------+
void SaveTradeResultsForML(const TradeData &trades[], int tradeCount, string fileName, string testRunID = "", string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    Print("📝 Saving trade results for ML training...");

    // Create trade results JSON in the format expected by the ML trainer
    string json = "{";
    json += "\"trade_results\":[";

    for(int i = 0; i < tradeCount; i++) {
        if(i > 0) json += ",";
        json += "{";
        json += "\"test_run_id\":\"" + testRunID + "\",";
        json += "\"trade_id\":" + IntegerToString(trades[i].trade_id) + ",";
        json += "\"symbol\":\"" + trades[i].symbol + "\",";
        json += "\"direction\":\"" + trades[i].type + "\",";
        json += "\"volume\":" + DoubleToString(trades[i].volume, 2) + ",";
        json += "\"open_price\":" + DoubleToString(trades[i].open_price, _Digits) + ",";
        json += "\"close_price\":" + DoubleToString(trades[i].close_price, _Digits) + ",";
        json += "\"open_time\":" + IntegerToString(trades[i].open_time) + ",";
        json += "\"close_time\":" + IntegerToString(trades[i].close_time) + ",";
        json += "\"profit\":" + DoubleToString(trades[i].profit, 2) + ",";
        json += "\"swap\":" + DoubleToString(trades[i].swap, 2) + ",";
        json += "\"commission\":" + DoubleToString(trades[i].commission, 2) + ",";
        json += "\"net_profit\":" + DoubleToString(trades[i].net_profit, 2) + ",";
        json += "\"trade_duration\":" + IntegerToString(trades[i].close_time - trades[i].open_time) + ",";
        json += "\"trade_success\":" + (trades[i].net_profit > 0 ? "true" : "false") + ",";

        // Determine exit reason based on profit and price movement
        string exitReason = "unknown";
        if(trades[i].type == "BUY") {
            if(trades[i].net_profit > 0)
                exitReason = "take_profit";
            else
                exitReason = "stop_loss";
        } else { // SELL
            if(trades[i].net_profit > 0)
                exitReason = "take_profit";
            else
                exitReason = "stop_loss";
        }

        json += "\"exit_reason\":\"" + exitReason + "\"";
        json += "}";
    }
    json += "]}";

    // Save to trade results file
    int handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_READ|FILE_WRITE|FILE_COMMON, '\n');
    if(handle == INVALID_HANDLE) {
        handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
        if(handle != INVALID_HANDLE) {
            FileWrite(handle, json);
            FileClose(handle);
            Print("✅ Trade results for ML training saved to: ", fileName);
        }
    } else {
        string existingContent = "";
        while(!FileIsEnding(handle)) {
            existingContent += FileReadString(handle);
        }
        FileClose(handle);

        if(StringLen(existingContent) > 0) {
            // Parse existing content and append new trades
            int lastBracketPos = StringFind(existingContent, "]}");
            if(lastBracketPos > 0) {
                string newContent = StringSubstr(existingContent, 0, lastBracketPos) + ",";
                // Extract just the trade_results array from the new JSON
                int startPos = StringFind(json, "\"trade_results\":[") + 15;
                int endPos = StringFind(json, "]}");
                if(startPos > 14 && endPos > startPos) {
                    string tradeResultsArray = StringSubstr(json, startPos, endPos - startPos);
                    newContent += tradeResultsArray + "]}";
                    handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
                    if(handle != INVALID_HANDLE) {
                        FileWrite(handle, newContent);
                        FileClose(handle);
                        Print("✅ Trade results appended to: ", fileName);
                    }
                }
            }
        } else {
            handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE|FILE_COMMON, '\n');
            if(handle != INVALID_HANDLE) {
                FileWrite(handle, json);
                FileClose(handle);
                Print("✅ Trade results for ML training saved to: ", fileName);
            }
        }
    }

    Print("📊 Trade results summary for ML training:");
    Print("   Total trades: ", tradeCount);
    int profitableTrades = 0;
    double localTestTotalProfit = 0.0;
    for(int i = 0; i < tradeCount; i++) {
        if(trades[i].net_profit > 0) profitableTrades++;
        testTotalProfit += trades[i].net_profit;
    }
    Print("   Profitable trades: ", profitableTrades);
    Print("   Total profit: $", DoubleToString(testTotalProfit, 2));
    if(tradeCount > 0) {
        double winRate = (double)profitableTrades / tradeCount * 100.0;
        Print("   Win rate: ", DoubleToString(winRate, 2), "%");
    }
}

//+------------------------------------------------------------------+
//| Save comprehensive trade results                                 |
//+------------------------------------------------------------------+
void SaveComprehensiveTradeResults(const TradeData &trades[], int tradeCount, double resultsTotalProfit, int resultsTotalTrades, int resultsWinningTrades, double winRate, string fileName, string testRunID = "", string symbol = NULL, ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    if(tf == PERIOD_CURRENT) tf = _Period;

    Print("📝 Saving comprehensive trade results...");

    // Get additional statistics
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
    double maxDrawdown = TesterStatistics(STAT_BALANCEDD_PERCENT);
    double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
    double grossLoss = TesterStatistics(STAT_GROSS_LOSS);
    double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);

    // Create comprehensive JSON with proper structure
    string json = "{";
    json += "\"test_summary\":{";
    json += "\"test_run_id\":\"" + testRunID + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":\"" + EnumToString(tf) + "\",";
    json += "\"total_profit\":" + DoubleToString(resultsTotalProfit, 2) + ",";
    json += "\"total_trades\":" + IntegerToString(resultsTotalTrades) + ",";
    json += "\"winning_trades\":" + IntegerToString(resultsWinningTrades) + ",";
    json += "\"losing_trades\":" + IntegerToString(resultsTotalTrades - resultsWinningTrades) + ",";
    json += "\"win_rate\":" + DoubleToString(winRate, 2) + ",";
    json += "\"profit_factor\":" + DoubleToString(profitFactor, 2) + ",";
    json += "\"max_drawdown\":" + DoubleToString(maxDrawdown, 2) + ",";
    json += "\"gross_profit\":" + DoubleToString(grossProfit, 2) + ",";
    json += "\"gross_loss\":" + DoubleToString(grossLoss, 2) + ",";
    json += "\"expected_payoff\":" + DoubleToString(expectedPayoff, 2) + ",";
    json += "\"test_timestamp\":" + IntegerToString(TimeCurrent()) + "},";

    // Add individual trades with test_run_id
    json += "\"trades\":[";
    for(int i = 0; i < tradeCount; i++) {
        if(i > 0) json += ",";
        json += "{";
        json += "\"test_run_id\":\"" + testRunID + "\",";
        json += "\"trade_id\":" + IntegerToString(trades[i].trade_id) + ",";
        json += "\"ticket\":" + IntegerToString(trades[i].ticket) + ",";
        json += "\"type\":\"" + trades[i].type + "\",";
        json += "\"volume\":" + DoubleToString(trades[i].volume, 2) + ",";
        json += "\"open_price\":" + DoubleToString(trades[i].open_price, _Digits) + ",";
        json += "\"close_price\":" + DoubleToString(trades[i].close_price, _Digits) + ",";
        json += "\"open_time\":" + IntegerToString(trades[i].open_time) + ",";
        json += "\"close_time\":" + IntegerToString(trades[i].close_time) + ",";
        json += "\"profit\":" + DoubleToString(trades[i].profit, 2) + ",";
        json += "\"swap\":" + DoubleToString(trades[i].swap, 2) + ",";
        json += "\"commission\":" + DoubleToString(trades[i].commission, 2) + ",";
        json += "\"net_profit\":" + DoubleToString(trades[i].net_profit, 2) + ",";
        json += "\"trade_duration\":" + IntegerToString(trades[i].close_time - trades[i].open_time) + ",";
        json += "\"trade_success\":" + (trades[i].net_profit > 0 ? "true" : "false") + ",";

        // Determine exit reason based on profit and price movement
        string exitReason = "unknown";
        if(trades[i].type == "BUY") {
            if(trades[i].net_profit > 0)
                exitReason = "take_profit";
            else
                exitReason = "stop_loss";
        } else { // SELL
            if(trades[i].net_profit > 0)
                exitReason = "take_profit";
            else
                exitReason = "stop_loss";
        }

        json += "\"exit_reason\":\"" + exitReason + "\"";
        json += "}";
    }
    json += "]}";

    // Save to comprehensive results file
    int handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_READ|FILE_WRITE, '\n');
    if(handle == INVALID_HANDLE) {
        handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE, '\n');
        if(handle != INVALID_HANDLE) {
            FileWrite(handle, "{\"comprehensive_results\":[" + json + "]}");
            FileClose(handle);
            Print("✅ Comprehensive trade results saved to: ", fileName);
        }
    } else {
        string existingContent = "";
        while(!FileIsEnding(handle)) {
            existingContent += FileReadString(handle);
        }
        FileClose(handle);

        if(StringLen(existingContent) > 0) {
            int lastBracketPos = StringFind(existingContent, "]}");
            if(lastBracketPos > 0) {
                string newContent = StringSubstr(existingContent, 0, lastBracketPos) + "," + json + "]}";
                handle = FileOpen(fileName, FILE_TXT|FILE_ANSI|FILE_WRITE, '\n');
                if(handle != INVALID_HANDLE) {
                    FileWrite(handle, newContent);
                    FileClose(handle);
                    Print("✅ Comprehensive trade results appended to: ", fileName);
                }
            }
        } else {
            handle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
            if(handle != INVALID_HANDLE) {
                FileWrite(handle, "{\"comprehensive_results\":[" + json + "]}");
                FileClose(handle);
                Print("✅ Comprehensive trade results saved to: ", fileName);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Strategy Tester statistics                                   |
//+------------------------------------------------------------------+
void GetStrategyTesterStats(double &localTestTotalProfit, int &localTestTotalTrades, int &localTestWinningTrades, double &winRate, double &profitFactor, double &maxDrawdown, double &grossProfit, double &grossLoss, double &expectedPayoff) {
    localTestTotalProfit = TesterStatistics(STAT_PROFIT);
    localTestTotalTrades = (int)TesterStatistics(STAT_TRADES);
    localTestWinningTrades = (int)TesterStatistics(STAT_PROFIT_TRADES);
    int losingTrades = localTestTotalTrades - localTestWinningTrades;
    winRate = localTestTotalTrades > 0 ? ((double)localTestWinningTrades / localTestTotalTrades) * 100.0 : 0.0;
    profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
    maxDrawdown = TesterStatistics(STAT_BALANCEDD_PERCENT);
    grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
    grossLoss = TesterStatistics(STAT_GROSS_LOSS);
    expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);

    Print("📊 Strategy Tester Results:");
    Print("   Total Profit: $", DoubleToString(testTotalProfit, 2));
    Print("   Total Trades: ", testTotalTrades);
    Print("   Winning Trades: ", testWinningTrades);
    Print("   Losing Trades: ", losingTrades);
    Print("   Win Rate: ", DoubleToString(winRate, 2), "%");
    Print("   Profit Factor: ", DoubleToString(profitFactor, 2));
    Print("   Max Drawdown: ", DoubleToString(maxDrawdown, 2), "%");
    Print("   Gross Profit: $", DoubleToString(grossProfit, 2));
    Print("   Gross Loss: $", DoubleToString(grossLoss, 2));
    Print("   Expected Payoff: $", DoubleToString(expectedPayoff, 2));
}

//+------------------------------------------------------------------+
//| ML Model Evaluation Functions                                    |
//+------------------------------------------------------------------+

//--- Evaluate ML model for bullish trade
bool EvaluateMLForBullishTrade(bool useMLModels, double minPredictionThreshold, double minConfidence) {
    if(!useMLModels) return true; // Skip ML if disabled

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction for bullish trade
    double prediction = GetMLPrediction(features, "buy");
    double confidence = CalculateMLConfidence(features, "buy");

    Print("🤖 ML Bullish Evaluation:");
    Print("   Prediction: ", DoubleToString(prediction, 4));
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Min Threshold: ", DoubleToString(minPredictionThreshold, 4));
    Print("   Min Confidence: ", DoubleToString(minConfidence, 4));

    // Check if ML conditions are met
    bool predictionOK = prediction >= minPredictionThreshold;
    bool confidenceOK = confidence >= minConfidence;

    if(predictionOK && confidenceOK) {
        Print("✅ ML conditions met for bullish trade");
        return true;
    } else {
        Print("❌ ML conditions not met for bullish trade");
        if(!predictionOK) Print("   ❌ Prediction below threshold");
        if(!confidenceOK) Print("   ❌ Confidence below threshold");
        return false;
    }
}

//--- Evaluate ML model for bearish trade
bool EvaluateMLForBearishTrade(bool useMLModels, double maxPredictionThreshold, double minConfidence) {
    if(!useMLModels) return true; // Skip ML if disabled

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction for bearish trade
    double prediction = GetMLPrediction(features, "sell");
    double confidence = CalculateMLConfidence(features, "sell");

    Print("🤖 ML Bearish Evaluation:");
    Print("   Prediction: ", DoubleToString(prediction, 4));
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Max Threshold: ", DoubleToString(maxPredictionThreshold, 4));
    Print("   Min Confidence: ", DoubleToString(minConfidence, 4));

    // Check if ML conditions are met
    bool predictionOK = prediction <= maxPredictionThreshold;
    bool confidenceOK = confidence >= minConfidence;

    if(predictionOK && confidenceOK) {
        Print("✅ ML conditions met for bearish trade");
        return true;
    } else {
        Print("❌ ML conditions not met for bearish trade");
        if(!predictionOK) Print("   ❌ Prediction above threshold");
        if(!confidenceOK) Print("   ❌ Confidence below threshold");
        return false;
    }
}

//--- Get ML-adjusted position size
double GetMLAdjustedPositionSize(double baseLotSize, string direction, bool useMLPositionSizing, double positionSizingMultiplier) {
    if(!useMLPositionSizing) return baseLotSize; // Skip ML if disabled

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction and confidence
    double prediction = GetMLPrediction(features, direction);
    double confidence = CalculateMLConfidence(features, direction);

    // Calculate volatility (ATR as percentage of price)
    double volatility = features.atr / features.current_price * 100;

    // Calculate dynamic position size using ML
    double adjustedLotSize = CalculateDynamicPositionSize(
        baseLotSize,
        prediction,
        confidence,
        volatility,
        true // Use volatility adjustment
    );

    // Apply ML position sizing multiplier
    adjustedLotSize *= positionSizingMultiplier;

    // CRITICAL: Validate and normalize lot size to broker requirements
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    // Ensure lot size is within broker limits
    adjustedLotSize = MathMax(minLot, MathMin(maxLot, adjustedLotSize));

    // Normalize to broker's lot step
    adjustedLotSize = MathRound(adjustedLotSize / lotStep) * lotStep;

    // Additional safety: cap at reasonable maximum (2x base lot size)
    double maxReasonableLot = baseLotSize * 2.0;
    if(adjustedLotSize > maxReasonableLot) {
        Print("⚠️  ML adjusted lot size too large, capping at 2x base lot size");
        adjustedLotSize = maxReasonableLot;
        adjustedLotSize = MathRound(adjustedLotSize / lotStep) * lotStep;
    }

    Print("🤖 ML Position Sizing:");
    Print("   Base Lot Size: ", DoubleToString(baseLotSize, 2));
    Print("   ML Adjusted Lot Size: ", DoubleToString(adjustedLotSize, 2));
    Print("   Broker Min Lot: ", DoubleToString(minLot, 2));
    Print("   Broker Max Lot: ", DoubleToString(maxLot, 2));
    Print("   Broker Lot Step: ", DoubleToString(lotStep, 2));
    Print("   Prediction: ", DoubleToString(prediction, 4));
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Volatility: ", DoubleToString(volatility, 2), "%");

    return adjustedLotSize;
}

//--- Get ML-adjusted stop loss
double GetMLAdjustedStopLoss(double baseStopLoss, string direction, bool useMLStopLossAdjustment, double stopLossAdjustment) {
    if(!useMLStopLossAdjustment) return baseStopLoss; // Skip ML if disabled

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction and confidence
    double prediction = GetMLPrediction(features, direction);
    double confidence = CalculateMLConfidence(features, direction);

    // Get current price for distance calculation
    double currentPrice = SymbolInfoDouble(_Symbol, direction == "buy" ? SYMBOL_ASK : SYMBOL_BID);

    // Calculate base stop distance in pips
    double baseStopDistancePips = 0.0;
    if(direction == "buy") {
        baseStopDistancePips = (currentPrice - baseStopLoss) / _Point;
    } else {
        baseStopDistancePips = (baseStopLoss - currentPrice) / _Point;
    }

    // Calculate adjustment factor based on ML confidence
    // Higher confidence = tighter stop loss (reduce pips)
    // Lower confidence = wider stop loss (increase pips)
    double confidenceAdjustment = 1.0;

    // Conservative adjustment: 0.8 to 1.2 (20% max adjustment)
    if(direction == "buy") {
        // For bullish trades, higher confidence = tighter stop (fewer pips)
        confidenceAdjustment = 1.0 - (confidence - 0.5) * 0.4; // 0.8 to 1.2 range
    } else {
        // For bearish trades, higher confidence = tighter stop (fewer pips)
        confidenceAdjustment = 1.0 - (confidence - 0.5) * 0.4; // 0.8 to 1.2 range
    }

    // Apply ML adjustment to stop distance in pips
    double adjustedStopDistancePips = baseStopDistancePips * confidenceAdjustment * stopLossAdjustment;

    // Ensure minimum stop distance (at least 5 pips)
    double minStopDistancePips = 5.0;
    if(adjustedStopDistancePips < minStopDistancePips) {
        Print("⚠️  ML adjusted stop distance too small, using minimum: ", DoubleToString(minStopDistancePips, 1), " pips");
        adjustedStopDistancePips = minStopDistancePips;
    }

    // Calculate adjusted stop loss price from adjusted distance
    double adjustedStopLoss = 0.0;
    if(direction == "buy") {
        adjustedStopLoss = currentPrice - (adjustedStopDistancePips * _Point);
    } else {
        adjustedStopLoss = currentPrice + (adjustedStopDistancePips * _Point);
    }

    Print("🤖 ML Stop Loss Adjustment (Pip-based):");
    Print("   Current Price: ", DoubleToString(currentPrice, _Digits));
    Print("   Base Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
    Print("   Base Stop Distance: ", DoubleToString(baseStopDistancePips, 1), " pips");
    Print("   ML Adjusted Distance: ", DoubleToString(adjustedStopDistancePips, 1), " pips");
    Print("   ML Adjusted Stop Loss: ", DoubleToString(adjustedStopLoss, _Digits));
    Print("   Direction: ", direction);
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Confidence Adjustment: ", DoubleToString(confidenceAdjustment, 4));

    return adjustedStopLoss;
}

//--- Get comprehensive ML analysis
void GetMLAnalysis(string direction, double &prediction, double &confidence, string &recommendation,
                   bool useMLModels, double minPredictionThreshold, double maxPredictionThreshold, double minConfidence) {
    if(!useMLModels) {
        prediction = 0.5;
        confidence = 0.5;
        recommendation = "ML disabled";
        return;
    }

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction and confidence
    prediction = GetMLPrediction(features, direction);
    confidence = CalculateMLConfidence(features, direction);

    // Determine recommendation
    if(direction == "buy") {
        if(prediction >= minPredictionThreshold && confidence >= minConfidence) {
            recommendation = "STRONG_BUY";
        } else if(prediction >= 0.5 && confidence >= minConfidence) {
            recommendation = "BUY";
        } else if(prediction >= 0.4) {
            recommendation = "WEAK_BUY";
        } else {
            recommendation = "HOLD";
        }
    } else {
        if(prediction <= maxPredictionThreshold && confidence >= minConfidence) {
            recommendation = "STRONG_SELL";
        } else if(prediction <= 0.5 && confidence >= minConfidence) {
            recommendation = "SELL";
        } else if(prediction <= 0.6) {
            recommendation = "WEAK_SELL";
        } else {
            recommendation = "HOLD";
        }
    }

    Print("🤖 ML Analysis for ", direction, ":");
    Print("   Prediction: ", DoubleToString(prediction, 4));
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Recommendation: ", recommendation);
}


//+------------------------------------------------------------------+
//| Get detailed candle pattern                                        |
//+------------------------------------------------------------------+
string GetDetailedCandlePattern(int lookback = 3) {
    double open[], close[], high[], low[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);

    if(CopyOpen(_Symbol, _Period, 0, lookback, open) < lookback ||
       CopyClose(_Symbol, _Period, 0, lookback, close) < lookback ||
       CopyHigh(_Symbol, _Period, 0, lookback, high) < lookback ||
       CopyLow(_Symbol, _Period, 0, lookback, low) < lookback) {
        return "none";
    }

    // Check for bullish engulfing
    if(IsBullishEngulfing(open, close, 1)) {
        return "bullish_engulfing";
    }

    // Check for bearish engulfing
    if(IsBearishEngulfing(open, close, 1)) {
        return "bearish_engulfing";
    }

    // Check for hammer
    if(IsHammer(open, high, low, close, 0)) {
        return "hammer";
    }

    // Check for shooting star
    if(IsShootingStar(open, high, low, close, 0)) {
        return "shooting_star";
    }

    // Check for strong bullish candle
    double currentBody = MathAbs(close[0] - open[0]);
    double currentRange = high[0] - low[0];
    if(currentRange > 0) {
        double bodyRatio = currentBody / currentRange;
        if(close[0] > open[0] && bodyRatio > 0.7) {
            return "strong_bullish";
        } else if(close[0] < open[0] && bodyRatio > 0.7) {
            return "strong_bearish";
        }
    }

    return "none";
}

//+------------------------------------------------------------------+
//| Get candle sequence                                               |
//+------------------------------------------------------------------+
string GetCandleSequence() {
    double open[3], close[3];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);

    if(CopyOpen(_Symbol, _Period, 0, 3, open) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, close) < 3) {
        return "";
    }

    string seq = "";
    for(int i = 2; i >= 0; i--) {
        seq += (close[i] > open[i] ? "B" : "S");
    }
    return seq;
}

//+------------------------------------------------------------------+
//| Get RSI value                                                     |
//+------------------------------------------------------------------+
double GetRSI(int period = 14) {
    int rsiHandle = iRSI(_Symbol, _Period, period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE) return 50.0;

    double rsiBuffer[];
    ArraySetAsSeries(rsiBuffer, true);
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) <= 0) {
        IndicatorRelease(rsiHandle);
        return 50.0;
    }

    double value = rsiBuffer[0];
    IndicatorRelease(rsiHandle);
    return value;
}

//+------------------------------------------------------------------+
//| Clear previous day level lines                                    |
//+------------------------------------------------------------------+
void ClearPreviousDayLines(string prevDayHighLine = "PrevDayHigh", string prevDayLowLine = "PrevDayLow") {
    ObjectDelete(0, prevDayHighLine);
    ObjectDelete(0, prevDayLowLine);
}

//+------------------------------------------------------------------+
//| Draw previous day levels on chart                                 |
//+------------------------------------------------------------------+
void DrawPreviousDayLevels(double previousDayHigh, double previousDayLow, string prevDayHighLine = "PrevDayHigh", string prevDayLowLine = "PrevDayLow") {
    // Draw high line
    ObjectCreate(0, prevDayHighLine, OBJ_HLINE, 0, 0, previousDayHigh);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, prevDayHighLine, OBJPROP_WIDTH, 2);

    // Draw low line
    ObjectCreate(0, prevDayLowLine, OBJ_HLINE, 0, 0, previousDayLow);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, prevDayLowLine, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Check if it's a new bar                                           |
//+------------------------------------------------------------------+
bool IsNewBar() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, _Period, 0);

    if(currentBarTime != lastBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get enhanced candle sequence                                       |
//+------------------------------------------------------------------+
string GetEnhancedCandleSequence(int lookback = 5) {
    double open[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);

    if(CopyOpen(_Symbol, _Period, 0, lookback, open) < lookback ||
       CopyClose(_Symbol, _Period, 0, lookback, close) < lookback) {
        return "";
    }

    string sequence = "";
    for(int i = lookback - 1; i >= 0; i--) {
        sequence += (close[i] > open[i] ? "B" : "S");
    }

    return sequence;
}

//+------------------------------------------------------------------+
//| Check if current session is optimal based on ML recommendations   |
//+------------------------------------------------------------------+
bool IsOptimalSession(string symbol, bool useSessionFiltering, bool allowAllSessions,
                      int londonSessionStart, int londonSessionEnd,
                      int nySessionStart, int nySessionEnd,
                      int asianSessionStart, int asianSessionEnd) {
    if(!useSessionFiltering || allowAllSessions) {
        Print("⏰ Session filtering: DISABLED - allowing all sessions");
        return true; // Allow all sessions if filtering is disabled
    }

    // Get current session
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = dt.hour;

    // Determine which session we're in
    string currentSession = "none";
    if(IsWithinSession(londonSessionStart, londonSessionEnd)) {
        currentSession = "london";
    } else if (IsWithinSession(nySessionStart, nySessionEnd)) {
        currentSession = "ny";
    } else if (IsWithinSession(asianSessionStart, asianSessionEnd)) {
        currentSession = "asian";
    }

    // Get symbol-specific session recommendations from ML parameters
    string sessionRecommendation = GetSymbolSessionRecommendation(symbol);

    // Check if current session matches recommendation
    bool isOptimal = false;

    if(sessionRecommendation == "all" || sessionRecommendation == "any") {
        isOptimal = true;
    } else if (sessionRecommendation == "london" && currentSession == "london") {
        isOptimal = true;
    } else if (sessionRecommendation == "ny" && currentSession == "ny") {
        isOptimal = true;
    } else if (sessionRecommendation == "asian" && currentSession == "asian") {
        isOptimal = true;
    } else if (sessionRecommendation == "london_ny" && (currentSession == "london" || currentSession == "ny")) {
        isOptimal = true;
    } else if (sessionRecommendation == "european" && (currentSession == "london")) {
        isOptimal = true;
    }

    // Enhanced logging for debugging
    Print("⏰ Session Debug - Symbol: ", symbol, " Current Hour: ", currentHour, " Current Session: ", currentSession);
    Print("⏰ Session Debug - Recommendation: ", sessionRecommendation, " Is Optimal: ", isOptimal);

    if(!isOptimal) {
        Print("⏰ Session filtering: Current session(", currentSession, ") not optimal for ", symbol,
              " (recommended: ", sessionRecommendation, ")");
    } else {
        Print("⏰ Session filtering: Current session(", currentSession, ") is optimal for ", symbol);
    }

    return isOptimal;
}

//+------------------------------------------------------------------+
//| Indicator functions                                               |
//+------------------------------------------------------------------+

//--- Get Stochastic
double GetStochasticMain(int k_period = 5, int d_period = 3, int slowing = 3) {
    int stochHandle = iStochastic(_Symbol, _Period, k_period, d_period, slowing, MODE_SMA, STO_LOWHIGH);
    if(stochHandle == INVALID_HANDLE) return 50.0;

    double stochBuffer[];
    ArraySetAsSeries(stochBuffer, true);
    if(CopyBuffer(stochHandle, 0, 0, 1, stochBuffer) <= 0) {
        IndicatorRelease(stochHandle);
        return 50.0;
    }

    double value = stochBuffer[0];
    IndicatorRelease(stochHandle);
    return value;
}

double GetStochasticSignal(int k_period = 5, int d_period = 3, int slowing = 3) {
    int stochHandle = iStochastic(_Symbol, _Period, k_period, d_period, slowing, MODE_SMA, STO_LOWHIGH);
    if(stochHandle == INVALID_HANDLE) return 50.0;

    double stochBuffer[];
    ArraySetAsSeries(stochBuffer, true);
    if(CopyBuffer(stochHandle, 1, 0, 1, stochBuffer) <= 0) {
        IndicatorRelease(stochHandle);
        return 50.0;
    }

    double value = stochBuffer[0];
    IndicatorRelease(stochHandle);
    return value;
}

//--- Get MACD
double GetMACDMain(int fast_ema = 12, int slow_ema = 26, int signal_sma = 9) {
    int macdHandle = iMACD(_Symbol, _Period, fast_ema, slow_ema, signal_sma, PRICE_CLOSE);
    if(macdHandle == INVALID_HANDLE) return 0.0;

    double macdBuffer[];
    ArraySetAsSeries(macdBuffer, true);
    if(CopyBuffer(macdHandle, 0, 0, 1, macdBuffer) <= 0) {
        IndicatorRelease(macdHandle);
        return 0.0;
    }

    double value = macdBuffer[0];
    IndicatorRelease(macdHandle);
    return value;
}

double GetMACDSignal(int fast_ema = 12, int slow_ema = 26, int signal_sma = 9) {
    int macdHandle = iMACD(_Symbol, _Period, fast_ema, slow_ema, signal_sma, PRICE_CLOSE);
    if(macdHandle == INVALID_HANDLE) return 0.0;

    double macdBuffer[];
    ArraySetAsSeries(macdBuffer, true);
    if(CopyBuffer(macdHandle, 1, 0, 1, macdBuffer) <= 0) {
        IndicatorRelease(macdHandle);
        return 0.0;
    }

    double value = macdBuffer[0];
    IndicatorRelease(macdHandle);
    return value;
}

//--- Get Bollinger Bands
double GetBollingerUpper(int period = 20, double deviation = 2.0) {
    int bbHandle = iBands(_Symbol, _Period, period, 0, deviation, PRICE_CLOSE);
    if(bbHandle == INVALID_HANDLE) return 0.0;

    double bbBuffer[];
    ArraySetAsSeries(bbBuffer, true);
    if(CopyBuffer(bbHandle, 1, 0, 1, bbBuffer) <= 0) {
        IndicatorRelease(bbHandle);
        return 0.0;
    }

    double value = bbBuffer[0];
    IndicatorRelease(bbHandle);
    return value;
}

double GetBollingerLower(int period = 20, double deviation = 2.0) {
    int bbHandle = iBands(_Symbol, _Period, period, 0, deviation, PRICE_CLOSE);
    if(bbHandle == INVALID_HANDLE) return 0.0;

    double bbBuffer[];
    ArraySetAsSeries(bbBuffer, true);
    if(CopyBuffer(bbHandle, 2, 0, 1, bbBuffer) <= 0) {
        IndicatorRelease(bbHandle);
        return 0.0;
    }

    double value = bbBuffer[0];
    IndicatorRelease(bbHandle);
    return value;
}

double GetBollingerPosition(int period = 20, double deviation = 2.0) {
    double currentPrice = iClose(_Symbol, _Period, 0);
    double upper = GetBollingerUpper(period, deviation);
    double lower = GetBollingerLower(period, deviation);

    if(upper == lower) return 0.5;
    return (currentPrice - lower) / (upper - lower);
}

//--- Get ADX
double GetADX(int period = 14) {
    int adxHandle = iADX(_Symbol, _Period, period);
    if(adxHandle == INVALID_HANDLE) return 0.0;

    double adxBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    if(CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) <= 0) {
        IndicatorRelease(adxHandle);
        return 0.0;
    }

    double value = adxBuffer[0];
    IndicatorRelease(adxHandle);
    return value;
}

//--- Get Williams %R
double GetWilliamsR(int period = 14) {
    int wrHandle = iWPR(_Symbol, _Period, period);
    if(wrHandle == INVALID_HANDLE) return -50.0;

    double wrBuffer[];
    ArraySetAsSeries(wrBuffer, true);
    if(CopyBuffer(wrHandle, 0, 0, 1, wrBuffer) <= 0) {
        IndicatorRelease(wrHandle);
        return -50.0;
    }

    double value = wrBuffer[0];
    IndicatorRelease(wrHandle);
    return value;
}

//--- Get CCI
double GetCCI(int period = 14) {
    int cciHandle = iCCI(_Symbol, _Period, period, PRICE_TYPICAL);
    if(cciHandle == INVALID_HANDLE) return 0.0;

    double cciBuffer[];
    ArraySetAsSeries(cciBuffer, true);
    if(CopyBuffer(cciHandle, 0, 0, 1, cciBuffer) <= 0) {
        IndicatorRelease(cciHandle);
        return 0.0;
    }

    double value = cciBuffer[0];
    IndicatorRelease(cciHandle);
    return value;
}

//--- Get Momentum
double GetMomentum(int period = 14) {
    int momentumHandle = iMomentum(_Symbol, _Period, period, PRICE_CLOSE);
    if(momentumHandle == INVALID_HANDLE) return 100.0;

    double momentumBuffer[];
    ArraySetAsSeries(momentumBuffer, true);
    if(CopyBuffer(momentumHandle, 0, 0, 1, momentumBuffer) <= 0) {
        IndicatorRelease(momentumHandle);
        return 100.0;
    }

    double value = momentumBuffer[0];
    IndicatorRelease(momentumHandle);
    return value;
}

//--- Get Trend Direction
string GetTrendDirection(ENUM_TIMEFRAMES timeframe, int ma_fast = 20, int ma_slow = 50) {
    int fastHandle = iMA(_Symbol, timeframe, ma_fast, 0, MODE_SMA, PRICE_CLOSE);
    int slowHandle = iMA(_Symbol, timeframe, ma_slow, 0, MODE_SMA, PRICE_CLOSE);

    if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE) return "none";

    double fastBuffer[2], slowBuffer[2];
    ArraySetAsSeries(fastBuffer, true);
    ArraySetAsSeries(slowBuffer, true);

    if(CopyBuffer(fastHandle, 0, 0, 2, fastBuffer) <= 0 ||
       CopyBuffer(slowHandle, 0, 0, 2, slowBuffer) <= 0) {
        IndicatorRelease(fastHandle);
        IndicatorRelease(slowHandle);
        return "none";
    }

    double currentPrice = iClose(_Symbol, timeframe, 0);
    string trend = "none";

    if(currentPrice > fastBuffer[0] && fastBuffer[0] > slowBuffer[0]) {
        trend = "bullish";
    } else if(currentPrice < fastBuffer[0] && fastBuffer[0] < slowBuffer[0]) {
        trend = "bearish";
    }

    IndicatorRelease(fastHandle);
    IndicatorRelease(slowHandle);
    return trend;
}

//--- Get Price Position
double GetPricePosition(double high, double low) {
    double currentPrice = iClose(_Symbol, _Period, 0);
    if(high == low) return 0.5;
    return (currentPrice - low) / (high - low);
}

//+------------------------------------------------------------------+
//| Store trade details for result tracking                          |
//+------------------------------------------------------------------+
void StoreTradeDetails(string direction, double entry, double stopLoss, double takeProfit, double lotSize, datetime entryTime) {
    // This function stores trade details that will be used later for result analysis
    // The actual trade results will be collected from the strategy tester history in OnTester()
    Print("📝 Stored trade details - Direction: ", direction, " Entry: ", DoubleToString(entry, _Digits), " Time: ", TimeToString(entryTime));
}

//+------------------------------------------------------------------+
//| Get candle pattern                                                |
//+------------------------------------------------------------------+
string GetCandlePattern() {
    double open[3], close[3], high[3], low[3];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);

    if(CopyOpen(_Symbol, _Period, 0, 3, open) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, close) < 3 ||
       CopyHigh(_Symbol, _Period, 0, 3, high) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, low) < 3) {
        return "none";
    }

    // Check for bullish engulfing
    if(IsBullishEngulfing(open, close, 1)) {
        return "bullish";
    }

    // Check for bearish engulfing
    if(IsBearishEngulfing(open, close, 1)) {
        return "bearish";
    }

    // Check for hammer
    if(IsHammer(open, high, low, close, 0)) {
        return "hammer";
    }

    // Check for shooting star
    if(IsShootingStar(open, high, low, close, 0)) {
        return "shooting_star";
    }

    return "none";
}

//+------------------------------------------------------------------+
//| Calculate volume ratio with enhanced analysis from TradeUtils    |
//+------------------------------------------------------------------+
double CalculateVolumeRatio() {
    // Use enhanced volume analysis from TradeUtils
    VolumeAnalysis volume = AnalyzeVolume(20, 1.2, 1.5, false);

    Print("🔍 Enhanced Volume Analysis:");
    Print(" Current Volume: ", volume.currentVolume);
    Print(" Average Volume: ", volume.averageVolume);
    Print(" Volume Ratio: ", DoubleToString(volume.volumeRatio, 2));
    Print(" Is High Volume: ", volume.isHighVolume);
    Print(" Is Optimal Volume: ", volume.isOptimalVolume);

    return volume.volumeRatio;
}

//+------------------------------------------------------------------+
//| Check if ML session filtering should override input parameters    |
//+------------------------------------------------------------------+
bool ShouldUseMLSessionFiltering() {
    // Use ML session filtering if:
    // 1. Session filtering is enabled in input parameters
    // 2. ML session filtering is enabled in loaded parameters
    // 3. We have valid ML session data
        return UseSessionFiltering &&
           globalSessionFilteringEnabled &&
           globalOptimalSessions != "" &&
           globalOptimalSessions != "all";
}

//+------------------------------------------------------------------+
//| Get ML-adjusted session filtering parameters                      |
//+------------------------------------------------------------------+
void GetMLAdjustedSessionParameters(bool &useAdvanced, bool &useCondition, bool &useVolatility,
                                   bool &useTrend, bool &useRSI, double &minSuccessRate, int &minTrades) {
    // Use input parameters as defaults
    useAdvanced = UseAdvancedSessionFiltering;
    useCondition = UseSessionConditionFiltering;
    useVolatility = UseSessionVolatilityFiltering;
    useTrend = UseSessionTrendFiltering;
    useRSI = UseSessionRSIFiltering;
    minSuccessRate = SessionMinSuccessRate;
    minTrades = SessionMinTrades;

    // Override with ML parameters if available
    if(ShouldUseMLSessionFiltering()) {
        // Use ML-loaded success rates for current session
        string currentSession = GetCurrentSession();
        if(currentSession == "london") {
            minSuccessRate = globalLondonMinSuccessRate;
            minTrades = globalLondonMinTrades;
        } else if(currentSession == "ny") {
            minSuccessRate = globalNYMinSuccessRate;
            minTrades = globalNYMinTrades;
        } else if(currentSession == "asian") {
            minSuccessRate = globalAsianMinSuccessRate;
            minTrades = globalAsianMinTrades;
        }

        Print("📊 Using ML-adjusted session parameters for ", currentSession, " session:");
        Print("   Min Success Rate: ", DoubleToString(minSuccessRate, 3));
        Print("   Min Trades: ", minTrades);
    }
}

//--- Evaluate ML model for combined trade (success prediction)
bool EvaluateMLForCombinedTrade(bool useMLModels, string direction, double predictionThreshold, double minConfidence) {
    if(!useMLModels) return true; // Skip ML if disabled

    // Collect current ML features
    MLFeatures features;
    CollectMLFeatures(features);

    // Get ML prediction for combined model (success prediction)
    double prediction = GetMLPrediction(features, "combined");
    double confidence = CalculateMLConfidence(features, "combined");

    Print("🤖 ML Combined Evaluation for ", direction, ":");
    Print("   Prediction: ", DoubleToString(prediction, 4));
    Print("   Confidence: ", DoubleToString(confidence, 4));
    Print("   Threshold: ", DoubleToString(predictionThreshold, 4));
    Print("   Min Confidence: ", DoubleToString(minConfidence, 4));

    // For combined model, we predict success probability
    // Higher prediction = higher chance of success
    bool predictionOK = false;

    if(direction == "buy") {
        // For buy trades, we want high success probability
        predictionOK = prediction >= predictionThreshold;
    } else if(direction == "sell") {
        // For sell trades, we want high success probability (same logic)
        predictionOK = prediction >= predictionThreshold;
    }

    bool confidenceOK = confidence >= minConfidence;

    if(predictionOK && confidenceOK) {
        Print("✅ ML combined model conditions met for ", direction, " trade");
        return true;
    } else {
        Print("❌ ML combined model conditions not met for ", direction, " trade");
        if(!predictionOK) Print("   ❌ Prediction below threshold");
        if(!confidenceOK) Print("   ❌ Confidence below threshold");
        return false;
    }
}

#endif // __TRADEUTILS_MQH__
