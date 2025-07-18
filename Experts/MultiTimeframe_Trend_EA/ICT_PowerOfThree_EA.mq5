//+------------------------------------------------------------------+
//| ICT Power of Three EA (True PO3: Price Action, No Fixed Bars)   |
//| Accumulation/Manipulation by closes relative to daily open      |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"

#property copyright "Copyright 2024"
#property version   "4.0"
#property description "ICT Power of Three (AMD) EA: True price-action PO3, no fixed bars, stddev TP"

// --- Inputs ---
input double ManipulationBuffer = 0.0;              // Buffer (in points) beyond manipulation for SL
input double TP_StdDev_Mult = 2.5;                  // Take profit = entry + direction * N * stddev (accum)
input double SL_Buffer_Points = 10;                 // Extra points beyond manipulation zone for SL
input double MaxRiskPercent = 1.0;                  // Risk per trade (%)
input double MinLotSize = 0.01;
input double MaxLotSize = 50.0;
input int    MaxPositions = 1;
input double RR_Min = 0.5;                          // Minimum RR to allow trade
input double RR_Max = 5.0;                          // Maximum RR to allow trade
input bool   EnableDebugLogs = true;
input bool   DrawPhases = true;
input bool   EnableNewsFilter = true;                // Block trades during high-impact news
input int    NewsBlockMinutesBefore = 30;            // Minutes before news to block trading
input int    NewsBlockMinutesAfter = 30;             // Minutes after news to block trading
input bool   BlockHighImpactOnly = true;             // Only block for high-impact news
input string RestrictedTimes = ""; // Comma-separated restricted intervals, e.g. "11:00-13:00,14:00-15:00"
input ENUM_TIMEFRAMES AnchorTimeframe = PERIOD_D1; // Timeframe used as session open anchor (e.g. PERIOD_D1, PERIOD_H4, etc.)
input double PseudoNewsThreshold = 2.0; // Multiplier for volatility/volume spike in tester
input int    PseudoNewsLookback = 20;   // Lookback bars for pseudo-news in tester
input int    BB_Period = 20;                      // Bollinger Bands period
input double BB_Deviation = 2.0;                  // Bollinger Bands deviation
input bool   EnableBBTrendFilter = true;           // Use BB as trend filter for PO3
input bool   EnableBBTrading = true;               // Enable standalone BB breakout trades

CTrade trade;
double anchorOpen = 0;
datetime lastAnchorBar = 0;
int dayBarCounter = 0;
int firstBarIdx = -1;

// PO3 state
enum PO3_STATE { WAIT_ACCUM, WAIT_MANIP, WAIT_ENTRY, TRADE_DONE };
struct PO3Context {
    PO3_STATE state;
    string accumSide; // "Above" or "Below"
    datetime accumStartTime, accumEndTime;
    double accumHigh, accumLow;
    datetime manipStartTime, manipEndTime;
    double manipHigh, manipLow;
    datetime entryTime;
    double entryPrice, stopLoss, takeProfit;
    string direction; // "Bullish" or "Bearish"
    bool valid;
};
PO3Context ctx = {WAIT_ACCUM};

//+------------------------------------------------------------------+
//| Returns 1 if current time is within any restricted interval      |
//+------------------------------------------------------------------+
bool IsInRestrictedTime(const string intervals) {
    if(intervals == "") return false;
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    int currMinutes = now.hour * 60 + now.min;
    int start, end;
    string arr[];
    int n = StringSplit(intervals, ',', arr);
    for(int i = 0; i < n; i++) {
        string times[];
        if(StringSplit(arr[i], '-', times) == 2) {
            string startStr = times[0];
            string endStr = times[1];
            int sh, sm, eh, em;
            if(EnableDebugLogs) Print("[PO3][Time] Checking restricted time: start=", startStr, " end=", endStr);
            if(EnableDebugLogs) Print("[PO3][Time] Parsed start time: ", StringToTimeParts(startStr, sh, sm));
            if(EnableDebugLogs) Print("[PO3][Time] Parsed end time: ", StringToTimeParts(endStr, eh, em));
            if(EnableDebugLogs) Print("[PO3][Time] Current time: ", now.hour, ":", now.min);
            if(StringToTimeParts(times[0], sh, sm) && StringToTimeParts(times[1], eh, em)) {
                start = sh * 60 + sm;
                end = eh * 60 + em;
                if(start <= currMinutes && currMinutes < end) {
                    if(EnableDebugLogs) Print("[PO3][Time] Trade blocked due to restricted trading time");
                    return true;
                }
            }
        }
    }
    if(EnableDebugLogs) Print("[PO3][Time] Trade not blocked due to restricted trading time");
    return false;
}

//+------------------------------------------------------------------+
//| Helper: Parse "HH:MM" to hours and minutes                      |
//+------------------------------------------------------------------+
bool StringToTimeParts(const string &s, int &h, int &m) {
    int colon = StringFind(s, ":");
    if(colon < 0) return false;
    h = StringToInteger(StringSubstr(s, 0, colon));
    m = StringToInteger(StringSubstr(s, colon+1));
    return (h >= 0 && h < 24 && m >= 0 && m < 60);
}

//+------------------------------------------------------------------+
//| Helper: Get Bollinger Bands arrays for current symbol/period     |
//+------------------------------------------------------------------+
void GetBollingerBands(double &upper[], double &middle[], double &lower[], int barsCount) {
    int bbHandle = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    if(bbHandle == INVALID_HANDLE) {
        ArrayResize(upper, 0); ArrayResize(middle, 0); ArrayResize(lower, 0);
        return;
    }
    ArraySetAsSeries(upper, true);
    ArraySetAsSeries(middle, true);
    ArraySetAsSeries(lower, true);
    CopyBuffer(bbHandle, 1, 0, barsCount, upper);   // Upper band (empirical)
    CopyBuffer(bbHandle, 0, 0, barsCount, middle);  // Middle band (SMA, empirical)
    CopyBuffer(bbHandle, 2, 0, barsCount, lower);   // Lower band (empirical)
    IndicatorRelease(bbHandle);
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick() {
    static datetime lastBarTime = 0;
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime == lastBarTime) return;
    lastBarTime = barTime;

    // --- Load price data ---
    double high[], low[], close[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(close, true);
    int bars = 200;
    if(CopyHigh(_Symbol, _Period, 0, bars, high) <= 0 || CopyLow(_Symbol, _Period, 0, bars, low) <= 0 || CopyClose(_Symbol, _Period, 0, bars, close) <= 0) {
        if(EnableDebugLogs) Print("[PO3] Not enough bars loaded.");
        return;
    }
    // --- Bollinger Bands ---
    double bbUpper[], bbMiddle[], bbLower[];
    GetBollingerBands(bbUpper, bbMiddle, bbLower, bars);

    // --- Bias shift exit logic (now using BB trend) ---
    int posTotal = PositionsTotal();
    for(int i = 0; i < posTotal; i++) {
        if(PositionGetSymbol(i) == _Symbol) {
            long type = PositionGetInteger(POSITION_TYPE);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double profit = PositionGetDouble(POSITION_PROFIT);
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            // Use iBarShift to get the correct index for the last closed bar
            datetime lastClosedBarTime = iTime(_Symbol, _Period, 1);
            int barIdx = iBarShift(_Symbol, _Period, lastClosedBarTime, true);
            double bbUpperVal = 0, bbMiddleVal = 0, bbLowerVal = 0;
            int bbHandle = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
            if(bbHandle != INVALID_HANDLE) {
                double upperBuf[1], middleBuf[1], lowerBuf[1];
                if(CopyBuffer(bbHandle, 1, barIdx, 1, upperBuf) > 0) bbUpperVal = upperBuf[0];   // Upper band (empirical)
                if(CopyBuffer(bbHandle, 0, barIdx, 1, middleBuf) > 0) bbMiddleVal = middleBuf[0]; // Middle band (SMA, empirical)
                if(CopyBuffer(bbHandle, 2, barIdx, 1, lowerBuf) > 0) bbLowerVal = lowerBuf[0];    // Lower band (empirical)
                // Debug: print BB and close for 5 bars around barIdx
                for(int i=barIdx-2; i<=barIdx+2; i++) {
                    double uArr[1], mArr[1], lArr[1];
                    double u=0, m=0, l=0, c=0;
                    if(CopyBuffer(bbHandle, 1, i, 1, uArr) > 0) u = uArr[0];
                    if(CopyBuffer(bbHandle, 0, i, 1, mArr) > 0) m = mArr[0];
                    if(CopyBuffer(bbHandle, 2, i, 1, lArr) > 0) l = lArr[0];
                    c = iClose(_Symbol, _Period, i);
                    Print("[PO3][BB][DEBUG] i=", i, " time=", TimeToString(iTime(_Symbol, _Period, i)), " upper=", u, " middle=", m, " lower=", l, " close=", c);
                }
                IndicatorRelease(bbHandle);
            }
            bool closeDueToBias = false;
            string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : ((type == POSITION_TYPE_SELL) ? "SELL" : "OTHER");
            if(EnableDebugLogs) Print("[PO3][BiasExit][DEBUG] ticket=", ticket, " type=", typeStr, " entry=", entry, " profit=", profit, " barIdx=", barIdx, " barTime=", TimeToString(lastClosedBarTime), " close=", close[barIdx], " bbUpper=", bbUpperVal, " bbMiddle=", bbMiddleVal, " bbLower=", bbLowerVal);
            if(type == POSITION_TYPE_BUY && close[barIdx] <= bbMiddleVal) closeDueToBias = true;
            if(type == POSITION_TYPE_SELL && close[barIdx] >= bbMiddleVal) closeDueToBias = true;
            if(closeDueToBias) {
                if(profit > 0) {
                    if(EnableDebugLogs) Print("[PO3][BiasExit] Closing position ", ticket, " due to BB trend shift and profit. Type=", type, " Entry=", entry, " Profit=", profit, " close=", close[barIdx], " middle=", bbMiddleVal);
                    trade.PositionClose(ticket);
                } else {
                    if(EnableDebugLogs) Print("[PO3][BiasExit] BB trend shifted against position ", ticket, " but not in profit yet. Type=", type, " Entry=", entry, " Profit=", profit, " close=", close[barIdx], " middle=", bbMiddleVal);
                }
            } else {
                if(EnableDebugLogs) Print("[PO3][BiasExit][DEBUG] No close triggered for ticket=", ticket, " type=", typeStr, " close=", close[barIdx], " bbMiddle=", bbMiddleVal);
            }
        }
    }

    // --- Detect start of new anchor period ---
    datetime anchorNow = iTime(_Symbol, AnchorTimeframe, 0);
    if(anchorNow != lastAnchorBar) {
        lastAnchorBar = anchorNow;
        int anchorBarIdx = -1;
        for(int i = Bars(_Symbol, AnchorTimeframe) - 1; i >= 0; i--) {
            datetime t = iTime(_Symbol, AnchorTimeframe, i);
            if(t == anchorNow) {
                anchorBarIdx = i;
                break;
            }
        }
        if(anchorBarIdx != -1) {
            anchorOpen = iOpen(_Symbol, AnchorTimeframe, anchorBarIdx);
            if(EnableDebugLogs) Print("[PO3] Anchor open detected at barIdx=", anchorBarIdx, " time=", TimeToString(iTime(_Symbol, AnchorTimeframe, anchorBarIdx)), " open=", anchorOpen);
        }
        // Reset all PO3 context indices and values
        ctx = PO3Context();
        ctx.accumStartTime = 0; ctx.accumEndTime = 0;
        ctx.manipStartTime = 0; ctx.manipEndTime = 0;
        ctx.entryTime = 0;
        ctx.accumHigh = 0; ctx.accumLow = 0; ctx.manipHigh = 0; ctx.manipLow = 0;
        ctx.accumSide = ""; ctx.direction = ""; ctx.valid = false;
        ctx.state = WAIT_ACCUM;
        dayBarCounter = 0;
        if(EnableDebugLogs) Print("[PO3] New anchor period: ", TimeToString(anchorNow), " Anchor Open=", anchorOpen);
    }

    // --- Robust detection of new bar ---
    static datetime lastProcessedBarTime = 0;
    datetime latestClosedBarTime = iTime(_Symbol, _Period, 1); // 1 = last closed bar
    bool isNewBar = (latestClosedBarTime != lastProcessedBarTime);
    if(isNewBar) {
        IsInRestrictedTime(RestrictedTimes);
        lastProcessedBarTime = latestClosedBarTime;
        if(EnableDebugLogs) Print("[PO3] New bar detected: ", TimeToString(latestClosedBarTime));
        int barIdx = 1; // 1 = last closed bar
        dayBarCounter++;
        if(EnableDebugLogs) Print("[PO3] dayBarCounter=", dayBarCounter);
        switch(ctx.state) {
            case WAIT_ACCUM: {
                // Accumulation: track closes on one side of daily open
                if(ctx.accumSide == "" && iTime(_Symbol, _Period, barIdx) >= anchorNow) {
                    // Start accumulation
                    ctx.accumSide = (close[barIdx] > anchorOpen) ? "Above" : (close[barIdx] < anchorOpen ? "Below" : "");
                    ctx.accumStartTime = iTime(_Symbol, _Period, barIdx);
                    ctx.accumEndTime = iTime(_Symbol, _Period, barIdx) + PeriodSeconds(_Period);
                    ctx.accumHigh = high[barIdx];
                    ctx.accumLow = low[barIdx];
                    if(EnableDebugLogs) Print("[PO3] Accumulation started at ", TimeToString(ctx.accumStartTime), " side=", ctx.accumSide);
                } else if(ctx.accumSide != "") {
                    bool stillAccum = (ctx.accumSide == "Above" && close[barIdx] > anchorOpen) ||
                                      (ctx.accumSide == "Below" && close[barIdx] < anchorOpen);
                    if(stillAccum) {
                        ctx.accumEndTime = iTime(_Symbol, _Period, barIdx) + PeriodSeconds(_Period);
                        if(high[barIdx] > ctx.accumHigh) ctx.accumHigh = high[barIdx];
                        if(low[barIdx] < ctx.accumLow) ctx.accumLow = low[barIdx];
                        if(EnableDebugLogs) Print("[PO3] Accumulation updated: start=", TimeToString(ctx.accumStartTime), " end=", TimeToString(ctx.accumEndTime), " low=", ctx.accumLow, " high=", ctx.accumHigh);
                    }
                    else if(
                        ctx.accumEndTime > ctx.accumStartTime &&
                        ((ctx.accumSide == "Above" && close[barIdx] < anchorOpen) ||
                         (ctx.accumSide == "Below" && close[barIdx] > anchorOpen))
                    ) {
                        // Manipulation starts
                        ctx.manipStartTime = iTime(_Symbol, _Period, barIdx);
                        ctx.manipEndTime = iTime(_Symbol, _Period, barIdx) + PeriodSeconds(_Period);
                        // Use iBarShift to get the correct bar index for the manipulation start time
                        int manipBarIdx = iBarShift(_Symbol, _Period, ctx.manipStartTime, true);
                        ctx.manipHigh = high[manipBarIdx];
                        ctx.manipLow = low[manipBarIdx];
                        ctx.direction = (ctx.accumSide == "Above") ? "Bullish" : "Bearish";
                        if(EnableDebugLogs) Print("[PO3] Manipulation started at ", TimeToString(ctx.manipStartTime), " direction=", ctx.direction, " anchored to daily open=", anchorOpen);
                        ctx.state = WAIT_MANIP;
                    }
                    else if(
                        (ctx.accumSide == "Above" && close[barIdx] < anchorOpen) || (ctx.accumSide == "Below" && close[barIdx] > anchorOpen)
                    ) {
                        if(ctx.accumEndTime <= ctx.accumStartTime) {
                            if(EnableDebugLogs) Print("[PO3] Manipulation skipped: not enough accumulation bars (start=", TimeToString(ctx.accumStartTime), ", end=", TimeToString(ctx.accumEndTime), ")");
                        }
                        else if(
                            (ctx.accumSide == "Above" && close[barIdx-1] <= anchorOpen) ||
                            (ctx.accumSide == "Below" && close[barIdx-1] >= anchorOpen)
                        ) {
                            if(EnableDebugLogs) Print("[PO3] Manipulation skipped: previous bar not on accumulation side (prevClose=", close[barIdx-1], ", dailyOpen=", anchorOpen, ")");
                        }
                    }
                }
                break;
            }
            case WAIT_MANIP: {
                // Manipulation: track closes on opposite side
                if((ctx.direction == "Bullish" && close[barIdx] < anchorOpen) || (ctx.direction == "Bearish" && close[barIdx] > anchorOpen)) {
                    ctx.manipEndTime = iTime(_Symbol, _Period, barIdx) + PeriodSeconds(_Period);
                    if(high[barIdx] > ctx.manipHigh) ctx.manipHigh = high[barIdx];
                    if(low[barIdx] < ctx.manipLow) ctx.manipLow = low[barIdx];
                    if(EnableDebugLogs) Print("[PO3] Manipulation updated: start=", TimeToString(ctx.manipStartTime), " end=", TimeToString(ctx.manipEndTime), " low=", ctx.manipLow, " high=", ctx.manipHigh);
                } else {
                    // Only allow entry if manipulation covers more than one bar
                    if(ctx.manipEndTime > ctx.manipStartTime) {
                        ctx.entryTime = iTime(_Symbol, _Period, barIdx);
                        ctx.entryPrice = close[barIdx];
                        double stopDist = 0;
                        double tp = 0;
                        if(ctx.direction == "Bullish") {
                            ctx.stopLoss = ctx.manipLow - SL_Buffer_Points * _Point;
                            stopDist = ctx.entryPrice - ctx.stopLoss;
                            tp = ctx.entryPrice + (2 * stopDist);
                        } else {
                            ctx.stopLoss = ctx.manipHigh + SL_Buffer_Points * _Point;
                            stopDist = ctx.stopLoss - ctx.entryPrice;
                            tp = ctx.entryPrice - (2 * stopDist);
                        }
                        ctx.takeProfit = tp;
                        if(EnableDebugLogs) Print("[PO3][TP] 2R TP calculation: direction=", ctx.direction, " entry=", ctx.entryPrice, " stopLoss=", ctx.stopLoss, " stopDist=", stopDist, " TP=", tp);
                        if(EnableDebugLogs) Print("[PO3][SL] Stop loss calculation: direction=", ctx.direction, ", stopLoss=", ctx.stopLoss, ", manipHigh=", ctx.manipHigh, ", manipLow=", ctx.manipLow, ", buffer=", SL_Buffer_Points * _Point);
                        ctx.valid = true;
                        if(EnableDebugLogs) Print("[PO3] Entry: ", ctx.direction, " Entry=", ctx.entryPrice, " SL=", ctx.stopLoss, " TP=", ctx.takeProfit);

                        // Before the entry checks for bullish/bearish breakout:
                        double lot = CalculateLotSize(MaxRiskPercent, stopDist);

                        bool biasOK = true;
                        if(ctx.direction == "Bullish" && close[barIdx] <= bbMiddle[barIdx]) biasOK = false;
                        if(ctx.direction == "Bearish" && close[barIdx] >= bbMiddle[barIdx]) biasOK = false;
                        if(EnableDebugLogs) Print("[PO3][BBTrend] BB filter applied: direction=", ctx.direction, " close=", close[barIdx], " middle=", bbMiddle[barIdx], " biasOK=", biasOK);
                        if(!biasOK) {
                            if(EnableDebugLogs) Print("[PO3] Trade skipped due to BB trend filter: direction=", ctx.direction, " close=", close[barIdx], " middle=", bbMiddle[barIdx]);
                            ctx.state = TRADE_DONE;
                            break;
                        }

                        if(EnableNewsFilter && (IsNewsTime(_Symbol, NewsBlockMinutesBefore, NewsBlockMinutesAfter, BlockHighImpactOnly, EnableDebugLogs) || IsPseudoNewsEvent(PseudoNewsThreshold, PseudoNewsLookback, EnableDebugLogs))) {
                            if(EnableDebugLogs) Print("[PO3][News] Trade blocked due to news event or pseudo-news event");
                            ctx.state = TRADE_DONE;
                            break;
                        }

                        if(IsInRestrictedTime(RestrictedTimes)) {
                            if(EnableDebugLogs) Print("[PO3][Time] Trade blocked due to restricted trading time");
                            ctx.state = TRADE_DONE;
                            break;
                        }

                        if(ctx.direction == "Bearish" && close[barIdx] < ctx.accumLow) {
                            if(lot > 0 && PositionsTotal() < MaxPositions) {
                                PlaceSellOrder(lot, ctx.stopLoss, ctx.takeProfit, trade.RequestMagic(), "PO3 Sell");
                                if(EnableDebugLogs) Print("[PO3] Trade placed: Lot=", lot);
                            }
                            if(EnableDebugLogs) Print("[PO3] Distribution/Entry detected at bar ", barIdx, " after manipulation range start=", TimeToString(ctx.manipStartTime), " end=", TimeToString(ctx.manipEndTime));
                        } else if(ctx.direction == "Bullish" && close[barIdx] > ctx.accumHigh) {
                            if(lot > 0 && PositionsTotal() < MaxPositions) {
                                PlaceBuyOrder(lot, ctx.stopLoss, ctx.takeProfit, trade.RequestMagic(), "PO3 Buy");
                                if(EnableDebugLogs) Print("[PO3] Trade placed: Lot=", lot);
                            }
                            if(EnableDebugLogs) Print("[PO3] Distribution/Entry detected at bar ", barIdx, " after manipulation range start=", TimeToString(ctx.manipStartTime), " end=", TimeToString(ctx.manipEndTime));
                        } else {
                            if(EnableDebugLogs) Print("[PO3] Entry skipped: close did not return to accumulation side (close=", close[barIdx], ", dailyOpen=", anchorOpen, ", direction=", ctx.direction, ")");
                            ctx.state = WAIT_ENTRY;
                        }
                    } else {
                        if(EnableDebugLogs) Print("[PO3] Manipulation phase too short, no entry.");
                    }
                    ctx.state = WAIT_ENTRY;
                }
                break;
            }
            case WAIT_ENTRY: {
                // On each new bar, check for breakout
                bool validEntry = false;
                if(ctx.direction == "Bearish" && close[barIdx] < ctx.accumLow) validEntry = true;
                if(ctx.direction == "Bullish" && close[barIdx] > ctx.accumHigh) validEntry = true;
                if(EnableDebugLogs) Print("[PO3][WAIT_ENTRY] Entry breakout check: direction=", ctx.direction, ", close=", close[barIdx], ", accumLow=", ctx.accumLow, ", accumHigh=", ctx.accumHigh, ", validEntry=", validEntry);
                if(validEntry) {
                    if(EnableNewsFilter && (IsNewsTime(_Symbol, NewsBlockMinutesBefore, NewsBlockMinutesAfter, BlockHighImpactOnly, EnableDebugLogs) || IsPseudoNewsEvent(PseudoNewsThreshold, PseudoNewsLookback, EnableDebugLogs))) {
                        if(EnableDebugLogs) Print("[PO3][News] Trade blocked due to news event or pseudo-news event");
                        ctx.state = TRADE_DONE;
                        break;
                    }
                    if(IsInRestrictedTime(RestrictedTimes)) {
                        if(EnableDebugLogs) Print("[PO3][Time] Trade blocked due to restricted trading time");
                        ctx.state = TRADE_DONE;
                        break;
                    }
                    double stopDist = MathAbs(close[barIdx] - ctx.stopLoss);
                    double lot = CalculateLotSize(MaxRiskPercent, stopDist);
                    ctx.entryPrice = close[barIdx];
                    ctx.entryTime = iTime(_Symbol, _Period, barIdx);
                    // Bollinger Bands trend filter in WAIT_ENTRY
                    bool bbTrendOK = true;
                    if(ctx.direction == "Bullish" && close[barIdx] <= bbMiddle[barIdx]) bbTrendOK = false;
                    if(ctx.direction == "Bearish" && close[barIdx] >= bbMiddle[barIdx]) bbTrendOK = false;
                    if(EnableDebugLogs) Print("[PO3][BBTrend] BB filter applied (WAIT_ENTRY): direction=", ctx.direction, " close=", close[barIdx], " middle=", bbMiddle[barIdx], " bbTrendOK=", bbTrendOK);
                    if(!bbTrendOK) {
                        if(EnableDebugLogs) Print("[PO3] Trade skipped due to BB trend filter in WAIT_ENTRY");
                        ctx.state = TRADE_DONE;
                        break;
                    }
                    // Recalculate TP based on actual entry price and stop loss
                    if(ctx.direction == "Bullish") {
                        ctx.takeProfit = ctx.entryPrice + 2 * (ctx.entryPrice - ctx.stopLoss);
                    } else {
                        ctx.takeProfit = ctx.entryPrice - 2 * (ctx.stopLoss - ctx.entryPrice);
                    }
                    if(ctx.direction == "Bearish") {
                        if(lot > 0 && PositionsTotal() < MaxPositions) {
                            PlaceSellOrder(lot, ctx.stopLoss, ctx.takeProfit, trade.RequestMagic(), "PO3 Sell");
                            if(EnableDebugLogs) Print("[PO3] Trade placed: Lot=", lot);
                        }
                    } else {
                        if(lot > 0 && PositionsTotal() < MaxPositions) {
                            PlaceBuyOrder(lot, ctx.stopLoss, ctx.takeProfit, trade.RequestMagic(), "PO3 Buy");
                            if(EnableDebugLogs) Print("[PO3] Trade placed: Lot=", lot);
                        }
                    }
                    if(EnableDebugLogs) Print("[PO3] Distribution/Entry detected at bar ", barIdx, " after manipulation range start=", TimeToString(ctx.manipStartTime), " end=", TimeToString(ctx.manipEndTime));
                    ctx.state = TRADE_DONE;
                }
                break;
            }
            case TRADE_DONE: {
                // Awaiting next day
                break;
            }
        }
    }
    // --- Standalone Bollinger Bands breakout trades ---
    if(EnableBBTrading && PositionsTotal() < MaxPositions) {
        int bbBarIdx = 1; // last closed bar
        // Block BB trades if news filter is active
        if(EnableNewsFilter && (IsNewsTime(_Symbol, NewsBlockMinutesBefore, NewsBlockMinutesAfter, BlockHighImpactOnly, EnableDebugLogs) || IsPseudoNewsEvent(PseudoNewsThreshold, PseudoNewsLookback, EnableDebugLogs))) {
            if(EnableDebugLogs) Print("[BB][News] Trade blocked due to news event or pseudo-news event");
        } else {
            // Buy breakout: close above upper band
            if(close[bbBarIdx] > bbUpper[bbBarIdx]) {
                double bbSL = bbMiddle[bbBarIdx];
                double bbTP = close[bbBarIdx] + 2 * (close[bbBarIdx] - bbSL);
                double bbStopDist = MathAbs(close[bbBarIdx] - bbSL);
                double lot = CalculateLotSize(MaxRiskPercent, bbStopDist);
                if(lot > 0) {
                    PlaceBuyOrder(lot, bbSL, bbTP, trade.RequestMagic(), "BB Buy");
                    if(EnableDebugLogs) Print("[BB] Buy breakout: close=", close[bbBarIdx], " upper=", bbUpper[bbBarIdx], " SL=", bbSL, " TP=", bbTP, " lot=", lot);
                }
            }
            // Sell breakout: close below lower band
            else if(close[bbBarIdx] < bbLower[bbBarIdx]) {
                double bbSL = bbMiddle[bbBarIdx];
                double bbTP = close[bbBarIdx] - 2 * (bbSL - close[bbBarIdx]);
                double bbStopDist = MathAbs(bbSL - close[bbBarIdx]);
                double lot = CalculateLotSize(MaxRiskPercent, bbStopDist);
                if(lot > 0) {
                    PlaceSellOrder(lot, bbSL, bbTP, trade.RequestMagic(), "BB Sell");
                    if(EnableDebugLogs) Print("[BB] Sell breakout: close=", close[bbBarIdx], " lower=", bbLower[bbBarIdx], " SL=", bbSL, " TP=", bbTP, " lot=", lot);
                }
            }
        }
    }
    // Always call the draw function at the very end of OnTick
    if(DrawPhases) DrawPO3Phases(ctx);
}

//+------------------------------------------------------------------+
//| Draw PO3 Phases: open, accum, manip, entry                       |
//+------------------------------------------------------------------+
void DrawPO3Phases(const PO3Context &c) {
    // Always ensure the latest daily open line is present and at the correct price
    string dayStr = TimeToString(lastAnchorBar, TIME_DATE);
    string lineName = "PO3_HigherTimeFrame_Open_" + dayStr;
    // Delete all previous daily open lines except the current one
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--) {
        string objName = ObjectName(0, i);
        if(StringFind(objName, "PO3_HigherTimeFrame_Open_") == 0 && objName != lineName) {
            if(EnableDebugLogs) Print("[PO3][Draw] Deleting previous higher timframe open line: ", objName);
            ObjectDelete(0, objName);
        }
    }
    if(ObjectFind(0, lineName) < 0) {
        ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, anchorOpen);
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrAqua);
        ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
        if(EnableDebugLogs) Print("[PO3][Draw] Creating higher timframe open line: ", lineName);
    } else {
        if(EnableDebugLogs) Print("[PO3][Draw] Updating higher timframe open line: ", lineName);
        ObjectSetDouble(0, lineName, OBJPROP_PRICE, anchorOpen); // Update price in case it changed
    }
    
    // Accumulation box
    if(c.accumStartTime > 0 && c.accumEndTime > c.accumStartTime) {
        ObjectDelete(0, "PO3_Accum");
        bool created = ObjectCreate(0, "PO3_Accum", OBJ_RECTANGLE, 0, c.accumStartTime, c.accumHigh, c.accumEndTime, c.accumLow);
        if(created) {
            ObjectSetInteger(0, "PO3_Accum", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "PO3_Accum", OBJPROP_BACK, false);
            ObjectSetInteger(0, "PO3_Accum", OBJPROP_FILL, true);
            ObjectSetInteger(0, "PO3_Accum", OBJPROP_SELECTABLE, true);
            if(EnableDebugLogs) Print("[PO3][Draw] Accum box: start=", TimeToString(c.accumStartTime), " end=", TimeToString(c.accumEndTime), " high=", c.accumHigh, " low=", c.accumLow);
        } else {
            if(EnableDebugLogs) Print("[PO3][Draw] Failed to create Accum box: ", GetLastError());
        }
    }
    
    // Manipulation box
    if(c.manipStartTime > 0 && c.manipEndTime > c.manipStartTime) {
        ObjectDelete(0, "PO3_Manip");
        bool created = ObjectCreate(0, "PO3_Manip", OBJ_RECTANGLE, 0, c.manipStartTime, c.manipHigh, c.manipEndTime, c.manipLow);
        if(created) {
            ObjectSetInteger(0, "PO3_Manip", OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, "PO3_Manip", OBJPROP_BACK, false);
            ObjectSetInteger(0, "PO3_Manip", OBJPROP_FILL, true);
            ObjectSetInteger(0, "PO3_Manip", OBJPROP_SELECTABLE, true);
            if(EnableDebugLogs) Print("[PO3][Draw] Manip box: start=", TimeToString(c.manipStartTime), " end=", TimeToString(c.manipEndTime), " high=", c.manipHigh, " low=", c.manipLow);
        } else {
            if(EnableDebugLogs) Print("[PO3][Draw] Failed to create Manip box: ", GetLastError());
        }
    }
    
    // Entry arrow
    if(c.valid && c.entryTime > 0 && MathAbs(c.entryPrice) < 1e6) {
        datetime entryTime = c.entryTime;
        ObjectDelete(0, "PO3_Entry");
        bool created = ObjectCreate(0, "PO3_Entry", OBJ_ARROW, 0, entryTime, c.entryPrice);
        if(created) {
            ObjectSetInteger(0, "PO3_Entry", OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, "PO3_Entry", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, "PO3_Entry", OBJPROP_ARROWCODE, 233); // Up arrow
            if(EnableDebugLogs) Print("[PO3][Draw] Entry arrow created: time=", TimeToString(entryTime), " price=", c.entryPrice);
        } else {
            if(EnableDebugLogs) Print("[PO3][Draw] Failed to create Entry arrow: ", GetLastError());
        }
    }
}
