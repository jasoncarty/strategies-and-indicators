//+------------------------------------------------------------------+
//|                        TradeUtils.mqh                            |
//|   Generic trading utility functions for MQL5 EAs                 |
//|                                                                  |
//|   USAGE: All functions are now in the TradeUtils namespace      |
//|   Example: TradeUtils::CalculateLotSize(2.0, 100.0)            |
//|   Example: TradeUtils::GetATR(_Symbol, PERIOD_H1, 14)          |
//|                                                                  |
//|   This prevents naming conflicts with EA functions               |
//+------------------------------------------------------------------+
#ifndef __TRADEUTILS_MQH__
#define __TRADEUTILS_MQH__

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| TradeUtils Namespace - Contains all utility functions            |
//+------------------------------------------------------------------+
namespace TradeUtils
{
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


#endif // __TRADEUTILS_MQH__
