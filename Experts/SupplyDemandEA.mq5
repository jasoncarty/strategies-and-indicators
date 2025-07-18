//+------------------------------------------------------------------+
//| SupplyDemandEA.mq5 - Supply & Demand Trading EA for MT5         |
//| Implements zone detection, S/R confluence, trend filter,        |
//| risk management, and news filter.                               |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"

//--- Inputs
input double RiskPercent = 1.0;                // Risk per trade (% of balance)
input int    SMAPeriod = 50;                   // SMA period for trend filter (daily)
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_D1; // Timeframe for trend filter
input bool   EnableNewsFilter = true;          // Block trades during high-impact news
input int    NewsBlockMinutesBefore = 30;      // Minutes before news to block trading
input int    NewsBlockMinutesAfter = 30;       // Minutes after news to block trading
input bool   EnableSRConfluence = true;        // Require S/R confluence for zone trades
input int    ZoneLookbackBars = 200;           // Bars to look back for zone detection
input int    MinZoneSize = 2;                  // Minimum bars for base (zone) consolidation
input double ZoneTolerance = 10.0;             // Price tolerance (points) for S/R confluence
input color  DemandColor = clrGreen;           // Color for demand zones
input color  SupplyColor = clrRed;             // Color for supply zones
input color  SRSupportColor = clrAqua;         // Color for S/R support lines
input color  SRResistanceColor = clrMagenta;   // Color for S/R resistance lines
input bool   EnableDebugLogs = true;
input int MaxOpenOrders = 1; // Maximum number of open orders
input int MergeSRDistance = 50; // Merge S/R levels within this distance (points) into zones
input ENUM_TIMEFRAMES ConfirmTimeframe = PERIOD_M30; // Lower timeframe for confirmation
input int ConfirmMinCandles = 2; // Minimum number of confirming candles in sequence
input int ConfirmMaxCandles = 20; // Maximum number of candles to look back for confirmation
input bool ConfirmEngulfing = true; // Require engulfing pattern
input bool ConfirmPinBar = true; // Require pin bar pattern
input bool ConfirmSequence = true; // Require bullish/bearish sequence
input int MomentumCandles = 3; // Minimum candles required for momentum filter (descending for buys, ascending for sells)

//--- Structs for zones and S/R
// REMOVE: struct AreaOfInterest, struct SRZone

//--- Globals
CTrade trade;
Zone demandZones[];
Zone supplyZones[];
SRZone supportZones[];
SRZone resistanceZones[];

//--- Helper: Check momentum direction for zone entry
bool CheckMomentumDirection(bool isSupport, double zoneUpper, double zoneLower) {
    double close[];
    ArraySetAsSeries(close, true);
    int bars = MomentumCandles + 1; // +1 for current candle
    if(CopyClose(_Symbol, _Period, 0, bars, close) <= 0) {
        if(EnableDebugLogs) Print("[SDE] Failed to get close data for momentum check");
        return false;
    }
    
    double currentPrice = close[0];
    double zoneMid = (zoneUpper + zoneLower) / 2;
    
    if(isSupport) {
        // For support zones (buys): check if price is descending into zone
        // Need at least MomentumCandles with closes above current price and zone
        int descendingCount = 0;
        for(int i = 1; i <= MomentumCandles; i++) {
            if(close[i] > currentPrice && close[i] > zoneMid) {
                descendingCount++;
            }
        }
        if(EnableDebugLogs) Print("[SDE] Momentum check for support: descendingCount=", descendingCount, " (need ", MomentumCandles, ")");
        return descendingCount >= MomentumCandles;
    } else {
        // For resistance zones (sells): check if price is ascending into zone
        // Need at least MomentumCandles with closes below current price and zone
        int ascendingCount = 0;
        for(int i = 1; i <= MomentumCandles; i++) {
            if(close[i] < currentPrice && close[i] < zoneMid) {
                ascendingCount++;
            }
        }
        if(EnableDebugLogs) Print("[SDE] Momentum check for resistance: ascendingCount=", ascendingCount, " (need ", MomentumCandles, ")");
        return ascendingCount >= MomentumCandles;
    }
}

//--- Helper: Check for new bar
bool IsNewBar() {
    static datetime lastBarTime = 0;
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime == lastBarTime) return false;
    lastBarTime = barTime;
    return true;
}

//--- Helper: Get daily SMA 50 trend
int GetTrendDirection() {
    int smaHandle = iMA(_Symbol, TrendTimeframe, SMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if(smaHandle == INVALID_HANDLE) return 0;
    double smaBuf[2];
    ArraySetAsSeries(smaBuf, true);
    if(CopyBuffer(smaHandle, 0, 0, 2, smaBuf) <= 0) {
        IndicatorRelease(smaHandle);
        return 0;
    }
    double price = iClose(_Symbol, TrendTimeframe, 0);
    IndicatorRelease(smaHandle);
    if(price > smaBuf[0]) return 1; // Bullish
    if(price < smaBuf[0]) return -1; // Bearish
    return 0;
}

//--- Helper: Draw S/R lines
void DrawSRZones(string symbol, ENUM_TIMEFRAMES timeframe, SRZone supportZones[], SRZone resistanceZones[], color supportColor, color resistanceColor, int lookbackBars, string prefix) {
    ObjectsDeleteAll(0, prefix);
    datetime left = iTime(symbol, timeframe, lookbackBars-1);
    datetime right = iTime(symbol, timeframe, 0);
    // Draw support zones
    for(int i = 0; i < ArraySize(supportZones); i++) {
        string name = prefix + "S_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, left, supportZones[i].upper, right, supportZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, supportColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
    // Draw resistance zones
    for(int i = 0; i < ArraySize(resistanceZones); i++) {
        string name = prefix + "R_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, left, resistanceZones[i].upper, right, resistanceZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, resistanceColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//--- Helper: Detect supply/demand zones (RBR/DBR/DBD/RBD)
void FindSupplyDemandZones() {
    ArrayResize(demandZones, 0);
    ArrayResize(supplyZones, 0);
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    int bars = MathMin(ZoneLookbackBars, Bars(_Symbol, _Period));
    if(CopyOpen(_Symbol, _Period, 0, bars, open) <= 0 ||
       CopyHigh(_Symbol, _Period, 0, bars, high) <= 0 ||
       CopyLow(_Symbol, _Period, 0, bars, low) <= 0 ||
       CopyClose(_Symbol, _Period, 0, bars, close) <= 0) {
        if(EnableDebugLogs) Print("[SDE] Failed to get data for zones");
        return;
    }
    // Parameters for impulse/base detection
    double impulseFactor = 1.5; // Impulse candle body must be at least 1.5x average body size
    int minImpulse = 1; // Minimum impulse candles before/after base
    int minBase = MinZoneSize; // Minimum base candles
    int maxBase = 5; // Maximum base candles
    // Calculate average body size
    double totalBody = 0;
    for(int i = 0; i < bars; i++) totalBody += MathAbs(close[i] - open[i]);
    double avgBody = totalBody / bars;
    // Scan for patterns
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        // --- DBR: Drop-Base-Rally ---
        // 1. Drop: at least minImpulse strong bearish candle(s)
        bool drop = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = open[i+d] - close[i+d];
            if(body < impulseFactor * avgBody) drop = false;
        }
        if(!drop) continue;
        // 2. Base: 2-5 small-bodied candles
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
        // 3. Rally: at least minImpulse strong bullish candle(s)
        bool rally = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = close[r] - open[r];
            if(body < impulseFactor * avgBody) rally = false;
        }
        if(!rally) continue;
        // Zone is the base only
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        Zone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(_Symbol, _Period, baseStart);
        z.endTime = iTime(_Symbol, _Period, baseEnd);
        z.isDemand = true;
        z.isActive = true;
        ArrayResize(demandZones, ArraySize(demandZones)+1);
        demandZones[ArraySize(demandZones)-1] = z;
    }
    // --- RBD: Rally-Base-Drop ---
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        // 1. Rally: at least minImpulse strong bullish candle(s)
        bool rally = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = close[i+d] - open[i+d];
            if(body < impulseFactor * avgBody) rally = false;
        }
        if(!rally) continue;
        // 2. Base: 2-5 small-bodied candles
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
        // 3. Drop: at least minImpulse strong bearish candle(s)
        bool drop = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = open[r] - close[r];
            if(body < impulseFactor * avgBody) drop = false;
        }
        if(!drop) continue;
        // Zone is the base only
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        Zone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(_Symbol, _Period, baseStart);
        z.endTime = iTime(_Symbol, _Period, baseEnd);
        z.isDemand = false;
        z.isActive = true;
        ArrayResize(supplyZones, ArraySize(supplyZones)+1);
        supplyZones[ArraySize(supplyZones)-1] = z;
    }
    // --- DBD: Drop-Base-Drop ---
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        // 1. Drop: at least minImpulse strong bearish candle(s)
        bool drop1 = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = open[i+d] - close[i+d];
            if(body < impulseFactor * avgBody) drop1 = false;
        }
        if(!drop1) continue;
        // 2. Base: 2-5 small-bodied candles
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
        // 3. Drop: at least minImpulse strong bearish candle(s)
        bool drop2 = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = open[r] - close[r];
            if(body < impulseFactor * avgBody) drop2 = false;
        }
        if(!drop2) continue;
        // Zone is the base only
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        Zone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(_Symbol, _Period, baseStart);
        z.endTime = iTime(_Symbol, _Period, baseEnd);
        z.isDemand = false;
        z.isActive = true;
        ArrayResize(supplyZones, ArraySize(supplyZones)+1);
        supplyZones[ArraySize(supplyZones)-1] = z;
    }
    // --- RBR: Rally-Base-Rally ---
    for(int i = maxBase + minImpulse; i < bars - maxBase - minImpulse; i++) {
        // 1. Rally: at least minImpulse strong bullish candle(s)
        bool rally1 = true;
        for(int d = 0; d < minImpulse; d++) {
            double body = close[i+d] - open[i+d];
            if(body < impulseFactor * avgBody) rally1 = false;
        }
        if(!rally1) continue;
        // 2. Base: 2-5 small-bodied candles
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
        // 3. Rally: at least minImpulse strong bullish candle(s)
        bool rally2 = true;
        for(int r = baseEnd + 1; r <= baseEnd + minImpulse; r++) {
            double body = close[r] - open[r];
            if(body < impulseFactor * avgBody) rally2 = false;
        }
        if(!rally2) continue;
        // Zone is the base only
        double zUpper = high[baseStart];
        double zLower = low[baseStart];
        for(int b = baseStart + 1; b <= baseEnd; b++) {
            if(high[b] > zUpper) zUpper = high[b];
            if(low[b] < zLower) zLower = low[b];
        }
        Zone z;
        z.upper = zUpper;
        z.lower = zLower;
        z.startTime = iTime(_Symbol, _Period, baseStart);
        z.endTime = iTime(_Symbol, _Period, baseEnd);
        z.isDemand = true;
        z.isActive = true;
        ArrayResize(demandZones, ArraySize(demandZones)+1);
        demandZones[ArraySize(demandZones)-1] = z;
    }
}

//--- Helper: Draw supply/demand zones
void DrawZones() {
    ObjectsDeleteAll(0, "SDE_ZONE_");
    for(int i = 0; i < ArraySize(demandZones); i++) {
        string name = "SDE_ZONE_D_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, demandZones[i].startTime, demandZones[i].upper, demandZones[i].endTime, demandZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, DemandColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
    for(int i = 0; i < ArraySize(supplyZones); i++) {
        string name = "SDE_ZONE_S_" + IntegerToString(i);
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, supplyZones[i].startTime, supplyZones[i].upper, supplyZones[i].endTime, supplyZones[i].lower);
        ObjectSetInteger(0, name, OBJPROP_COLOR, SupplyColor);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//--- Helper: Check if zone is near S/R
bool IsZoneNearSR(Zone &z) {
    if(EnableDebugLogs) Print("[SDE][SR] Checking zone bounds: upper=", z.upper, ", lower=", z.lower);
    for(int i = 0; i < ArraySize(supportZones); i++) {
        if(supportZones[i].upper == supportZones[i].lower) continue; // skip zero-height
        if(EnableDebugLogs) Print("[SDE][SR] Support zone ", i, ": upper=", supportZones[i].upper, ", lower=", supportZones[i].lower);
        double overlap = MathMin(z.upper, supportZones[i].upper) - MathMax(z.lower, supportZones[i].lower);
        if(EnableDebugLogs) Print("[SDE][SR] Overlap with support zone ", i, ": ", overlap);
        if(overlap > 0) {
            if(EnableDebugLogs) Print("[SDE][SR] Zone is near SUPPORT zone ", i);
            return true;
        }
    }
    for(int i = 0; i < ArraySize(resistanceZones); i++) {
        if(resistanceZones[i].upper == resistanceZones[i].lower) continue; // skip zero-height
        if(EnableDebugLogs) Print("[SDE][SR] Resistance zone ", i, ": upper=", resistanceZones[i].upper, ", lower=", resistanceZones[i].lower);
        double overlap = MathMin(z.upper, resistanceZones[i].upper) - MathMax(z.lower, resistanceZones[i].lower);
        if(EnableDebugLogs) Print("[SDE][SR] Overlap with resistance zone ", i, ": ", overlap);
        if(overlap > 0) {
            if(EnableDebugLogs) Print("[SDE][SR] Zone is near RESISTANCE zone ", i);
            return true;
        }
    }
    if(EnableDebugLogs) Print("[SDE][SR] Zone is NOT near any S/R zone");
    return false;
}

//--- Helper: Check for open trade in zone
bool HasOpenTradeInZone(Zone &z) {
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            if(entry >= z.lower && entry <= z.upper) return true;
        }
    }
    return false;
}

// Helper: Check if a new lower timeframe candle has closed
bool IsLowerTimeframeCandleClosed() {
    static datetime lastLTFBarTime = 0;
    datetime ltfBarTime = iTime(_Symbol, ConfirmTimeframe, 0);
    if(ltfBarTime == lastLTFBarTime) return false;
    lastLTFBarTime = ltfBarTime;
    return true;
}

//--- Main OnTick
void OnTick() {
    if(!IsNewBar()) return;
    if(EnableNewsFilter && IsNewsTime(_Symbol, NewsBlockMinutesBefore, NewsBlockMinutesAfter, true, EnableDebugLogs)) {
        if(EnableDebugLogs) Print("[SDE] Trade blocked due to high-impact news");
        return;
    }
    int trend = GetTrendDirection();
    string trendStr = trend == 1 ? "Bullish" : (trend == -1 ? "Bearish" : "None");
    if(EnableDebugLogs) Print("[SDE] Trend: ", trendStr);
    if(trend == 0) {
        if(EnableDebugLogs) Print("[SDE] No clear trend, skipping");
        return;
    }
    // --- S/R ZONE LOGIC (replace old calls)
    FindSRZones(_Symbol, TrendTimeframe, ZoneLookbackBars, ZoneTolerance*_Point, MergeSRDistance, supportZones, resistanceZones);
    DrawSRZones(_Symbol, TrendTimeframe, supportZones, resistanceZones, SRSupportColor, SRResistanceColor, ZoneLookbackBars, "SDE_SR_");
    FindSupplyDemandZones();
    DrawZones();
    if(PositionSelect(_Symbol)) {
        if(EnableDebugLogs) Print("[SDE] Open order exists for symbol, skipping new order placement.");
        return;
    }
    //--- Lower timeframe confirmation state
    static bool pendingConfirmation = false;
    static int pendingSRZoneIndex = -1;
    static bool pendingIsSupport = true;
    static int pendingSDZoneIndex = -1; // Supply/demand zone index for confluence
    //--- Check for new S/R zone entry
    if(!pendingConfirmation) {
        // Check all S/R zones for buy opportunities (price descending into zone with demand confluence)
        for(int i = 0; i < ArraySize(supportZones); i++) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(price >= supportZones[i].lower && price <= supportZones[i].upper) {
                if(trend != 1) { if(EnableDebugLogs) Print("[SDE] Skipping buy opportunity in support zone [", i, "] due to trend != 1"); continue; }
                // Check momentum: price should be descending into zone for buy
                if(!CheckMomentumDirection(true, supportZones[i].upper, supportZones[i].lower)) {
                    if(EnableDebugLogs) Print("[SDE] Skipping support zone [", i, "] due to insufficient descending momentum");
                    continue;
                }
                // Check for demand zone confluence
                bool hasConfluence = false;
                int sdZoneIndex = -1;
                for(int j = 0; j < ArraySize(demandZones); j++) {
                    if(!demandZones[j].isActive) continue;
                    double overlap = MathMin(supportZones[i].upper, demandZones[j].upper) - MathMax(supportZones[i].lower, demandZones[j].lower);
                    if(overlap > 0) {
                        hasConfluence = true;
                        sdZoneIndex = j;
                        break;
                    }
                }
                if(EnableSRConfluence && !hasConfluence) { if(EnableDebugLogs) Print("[SDE] Support zone [", i, "] has no demand zone confluence"); continue; }
                if(EnableDebugLogs) Print("[SDE] Price descended into support zone [", i, "]: ", price, " (", supportZones[i].lower, " - ", supportZones[i].upper, ")");
                if(hasConfluence) {
                    demandZones[sdZoneIndex].isActive = false;
                    if(EnableDebugLogs) Print("[SDE] Found demand zone confluence [", sdZoneIndex, "]");
                }
                if(EnableDebugLogs) Print("[SDE] Waiting for lower timeframe confirmation for BUY in support zone [", i, "]");
                pendingConfirmation = true;
                pendingSRZoneIndex = i;
                pendingIsSupport = true; // true = buy order
                pendingSDZoneIndex = sdZoneIndex;
                break;
            }
        }
        
        // Check resistance zones for buy opportunities (price descending into resistance with demand confluence)
        for(int i = 0; i < ArraySize(resistanceZones); i++) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(price >= resistanceZones[i].lower && price <= resistanceZones[i].upper) {
                if(trend != 1) { if(EnableDebugLogs) Print("[SDE] Skipping buy opportunity in resistance zone [", i, "] due to trend != 1"); continue; }
                // Check momentum: price should be descending into zone for buy
                if(!CheckMomentumDirection(true, resistanceZones[i].upper, resistanceZones[i].lower)) {
                    if(EnableDebugLogs) Print("[SDE] Skipping resistance zone [", i, "] due to insufficient descending momentum");
                    continue;
                }
                // Check for demand zone confluence
                bool hasConfluence = false;
                int sdZoneIndex = -1;
                for(int j = 0; j < ArraySize(demandZones); j++) {
                    if(!demandZones[j].isActive) continue;
                    double overlap = MathMin(resistanceZones[i].upper, demandZones[j].upper) - MathMax(resistanceZones[i].lower, demandZones[j].lower);
                    if(overlap > 0) {
                        hasConfluence = true;
                        sdZoneIndex = j;
                        break;
                    }
                }
                if(EnableSRConfluence && !hasConfluence) { if(EnableDebugLogs) Print("[SDE] Resistance zone [", i, "] has no demand zone confluence"); continue; }
                if(EnableDebugLogs) Print("[SDE] Price descended into resistance zone [", i, "]: ", price, " (", resistanceZones[i].lower, " - ", resistanceZones[i].upper, ")");
                if(hasConfluence) {
                    demandZones[sdZoneIndex].isActive = false;
                    if(EnableDebugLogs) Print("[SDE] Found demand zone confluence [", sdZoneIndex, "]");
                }
                if(EnableDebugLogs) Print("[SDE] Waiting for lower timeframe confirmation for BUY in resistance zone [", i, "]");
                pendingConfirmation = true;
                pendingSRZoneIndex = i;
                pendingIsSupport = true; // true = buy order
                pendingSDZoneIndex = sdZoneIndex;
                break;
            }
        }
        
        // Check all S/R zones for sell opportunities (price ascending into zone with supply confluence)
        for(int i = 0; i < ArraySize(supportZones); i++) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(price >= supportZones[i].lower && price <= supportZones[i].upper) {
                if(trend != -1) { if(EnableDebugLogs) Print("[SDE] Skipping sell opportunity in support zone [", i, "] due to trend != -1"); continue; }
                // Check momentum: price should be ascending into zone for sell
                if(!CheckMomentumDirection(false, supportZones[i].upper, supportZones[i].lower)) {
                    if(EnableDebugLogs) Print("[SDE] Skipping support zone [", i, "] due to insufficient ascending momentum");
                    continue;
                }
                // Check for supply zone confluence
                bool hasConfluence = false;
                int sdZoneIndex = -1;
                for(int j = 0; j < ArraySize(supplyZones); j++) {
                    if(!supplyZones[j].isActive) continue;
                    double overlap = MathMin(supportZones[i].upper, supplyZones[j].upper) - MathMax(supportZones[i].lower, supplyZones[j].lower);
                    if(overlap > 0) {
                        hasConfluence = true;
                        sdZoneIndex = j;
                        break;
                    }
                }
                if(EnableSRConfluence && !hasConfluence) { if(EnableDebugLogs) Print("[SDE] Support zone [", i, "] has no supply zone confluence"); continue; }
                if(EnableDebugLogs) Print("[SDE] Price ascended into support zone [", i, "]: ", price, " (", supportZones[i].lower, " - ", supportZones[i].upper, ")");
                if(hasConfluence) {
                    supplyZones[sdZoneIndex].isActive = false;
                    if(EnableDebugLogs) Print("[SDE] Found supply zone confluence [", sdZoneIndex, "]");
                }
                if(EnableDebugLogs) Print("[SDE] Waiting for lower timeframe confirmation for SELL in support zone [", i, "]");
                pendingConfirmation = true;
                pendingSRZoneIndex = i;
                pendingIsSupport = false; // false = sell order
                pendingSDZoneIndex = sdZoneIndex;
                break;
            }
        }
        
        // Check resistance zones for sell opportunities (price ascending into resistance with supply confluence)
        for(int i = 0; i < ArraySize(resistanceZones); i++) {
            double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(price <= resistanceZones[i].upper && price >= resistanceZones[i].lower) {
                if(trend != -1) { if(EnableDebugLogs) Print("[SDE] Skipping sell opportunity in resistance zone [", i, "] due to trend != -1"); continue; }
                // Check momentum: price should be ascending into zone for sell
                if(!CheckMomentumDirection(false, resistanceZones[i].upper, resistanceZones[i].lower)) {
                    if(EnableDebugLogs) Print("[SDE] Skipping resistance zone [", i, "] due to insufficient ascending momentum");
                    continue;
                }
                // Check for supply zone confluence
                bool hasConfluence = false;
                int sdZoneIndex = -1;
                for(int j = 0; j < ArraySize(supplyZones); j++) {
                    if(!supplyZones[j].isActive) continue;
                    double overlap = MathMin(resistanceZones[i].upper, supplyZones[j].upper) - MathMax(resistanceZones[i].lower, supplyZones[j].lower);
                    if(overlap > 0) {
                        hasConfluence = true;
                        sdZoneIndex = j;
                        break;
                    }
                }
                if(EnableSRConfluence && !hasConfluence) { if(EnableDebugLogs) Print("[SDE] Resistance zone [", i, "] has no supply zone confluence"); continue; }
                if(EnableDebugLogs) Print("[SDE] Price ascended into resistance zone [", i, "]: ", price, " (", resistanceZones[i].lower, " - ", resistanceZones[i].upper, ")");
                if(hasConfluence) {
                    supplyZones[sdZoneIndex].isActive = false;
                    if(EnableDebugLogs) Print("[SDE] Found supply zone confluence [", sdZoneIndex, "]");
                }
                if(EnableDebugLogs) Print("[SDE] Waiting for lower timeframe confirmation for SELL in resistance zone [", i, "]");
                pendingConfirmation = true;
                pendingSRZoneIndex = i;
                pendingIsSupport = false; // false = sell order
                pendingSDZoneIndex = sdZoneIndex;
                break;
            }
        }
    }
    //--- Only check confirmation on new lower timeframe candle
    if(pendingConfirmation && IsLowerTimeframeCandleClosed()) {
        // Get lower timeframe candles
        double ltfOpen[], ltfClose[], ltfHigh[], ltfLow[];
        ArraySetAsSeries(ltfOpen, true);
        ArraySetAsSeries(ltfClose, true);
        ArraySetAsSeries(ltfHigh, true);
        ArraySetAsSeries(ltfLow, true);
        int bars = MathMin(ConfirmMaxCandles, Bars(_Symbol, ConfirmTimeframe));
        if(CopyOpen(_Symbol, ConfirmTimeframe, 0, bars, ltfOpen) <= 0 ||
           CopyClose(_Symbol, ConfirmTimeframe, 0, bars, ltfClose) <= 0 ||
           CopyHigh(_Symbol, ConfirmTimeframe, 0, bars, ltfHigh) <= 0 ||
           CopyLow(_Symbol, ConfirmTimeframe, 0, bars, ltfLow) <= 0) {
            if(EnableDebugLogs) Print("[SDE] Failed to get lower timeframe data for confirmation");
            return;
        }
        // Check if price is still in the S/R zone
        double price = pendingIsSupport ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double zUpper = pendingIsSupport ? supportZones[pendingSRZoneIndex].upper : resistanceZones[pendingSRZoneIndex].upper;
        double zLower = pendingIsSupport ? supportZones[pendingSRZoneIndex].lower : resistanceZones[pendingSRZoneIndex].lower;
        if(price < zLower || price > zUpper) {
            if(EnableDebugLogs) Print("[SDE] Price left S/R zone before confirmation, cancelling pending order");
            pendingConfirmation = false;
            pendingSRZoneIndex = -1;
            pendingSDZoneIndex = -1;
            return;
        }
        // Confirmation logic: check for any enabled pattern
        bool confirmed = false;
        // 1. Sequence of candles
        if(ConfirmSequence) {
            int seqCount = 0;
            for(int i = ConfirmMinCandles-1; i < MathMin(ConfirmMaxCandles, bars); i++) {
                bool seq = true;
                for(int j = 0; j < ConfirmMinCandles; j++) {
                    int idx = i-j;
                    if(pendingIsSupport) {
                        if(ltfClose[idx] <= ltfOpen[idx]) seq = false;
                    } else {
                        if(ltfClose[idx] >= ltfOpen[idx]) seq = false;
                    }
                }
                if(seq) { confirmed = true; if(EnableDebugLogs) Print("[SDE] Sequence confirmation found at LTF bar ", i); break; }
            }
        }
        // 2. Engulfing pattern
        if(ConfirmEngulfing && !confirmed) {
            for(int i = 1; i < MathMin(ConfirmMaxCandles, bars); i++) {
                if(pendingIsSupport) {
                    if(ltfClose[i] > ltfOpen[i] && ltfOpen[i] < ltfClose[i-1] && ltfClose[i] > ltfOpen[i-1] && ltfClose[i] > ltfOpen[i]) {
                        confirmed = true; if(EnableDebugLogs) Print("[SDE] Bullish engulfing confirmation at LTF bar ", i); break;
                    }
                } else {
                    if(ltfClose[i] < ltfOpen[i] && ltfOpen[i] > ltfClose[i-1] && ltfClose[i] < ltfOpen[i-1] && ltfClose[i] < ltfOpen[i]) {
                        confirmed = true; if(EnableDebugLogs) Print("[SDE] Bearish engulfing confirmation at LTF bar ", i); break;
                    }
                }
            }
        }
        // 3. Pin bar
        if(ConfirmPinBar && !confirmed) {
            for(int i = 0; i < MathMin(ConfirmMaxCandles, bars); i++) {
                double body = MathAbs(ltfClose[i] - ltfOpen[i]);
                double range = ltfHigh[i] - ltfLow[i];
                double upperWick = ltfHigh[i] - MathMax(ltfClose[i], ltfOpen[i]);
                double lowerWick = MathMin(ltfClose[i], ltfOpen[i]) - ltfLow[i];
                if(pendingIsSupport) {
                    if(lowerWick > 2*body && lowerWick > upperWick) {
                        confirmed = true; if(EnableDebugLogs) Print("[SDE] Bullish pin bar confirmation at LTF bar ", i); break;
                    }
                } else {
                    if(upperWick > 2*body && upperWick > lowerWick) {
                        confirmed = true; if(EnableDebugLogs) Print("[SDE] Bearish pin bar confirmation at LTF bar ", i); break;
                    }
                }
            }
        }
        // Place order if confirmed
        if(confirmed) {
            int trendNow = GetTrendDirection();
            if(pendingIsSupport && trendNow != 1) { if(EnableDebugLogs) Print("[SDE] Skipping buy order after confirmation due to trend != 1"); pendingConfirmation = false; pendingSRZoneIndex = -1; pendingSDZoneIndex = -1; return; }
            if(!pendingIsSupport && trendNow != -1) { if(EnableDebugLogs) Print("[SDE] Skipping sell order after confirmation due to trend != -1"); pendingConfirmation = false; pendingSRZoneIndex = -1; pendingSDZoneIndex = -1; return; }
            double sl, tp, lot;
            if(pendingIsSupport) {
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                sl = supportZones[pendingSRZoneIndex].lower - ZoneTolerance * _Point;
                double stopDist = entry - sl;
                tp = entry + 2 * stopDist;
                lot = CalculateLotSize(RiskPercent, stopDist, _Symbol);
                if(lot > 0) {
                    if(PlaceBuyOrder(lot, sl, tp, 0, "SDE Buy Confirmed")) {
                        if(EnableDebugLogs) Print("[SDE] Buy order placed after confirmation at ", entry, " SL=", sl, " TP=", tp, " lot=", lot);
                    }
                }
            } else {
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                sl = resistanceZones[pendingSRZoneIndex].upper + ZoneTolerance * _Point;
                double stopDist = sl - entry;
                tp = entry - 2 * stopDist;
                lot = CalculateLotSize(RiskPercent, stopDist, _Symbol);
                if(lot > 0) {
                    if(PlaceSellOrder(lot, sl, tp, 0, "SDE Sell Confirmed")) {
                        if(EnableDebugLogs) Print("[SDE] Sell order placed after confirmation at ", entry, " SL=", sl, " TP=", tp, " lot=", lot);
                    }
                }
            }
            pendingConfirmation = false;
            pendingSRZoneIndex = -1;
            pendingSDZoneIndex = -1;
        }
    }
    //--- Momentum exit: close trades if price closes beyond SMA 50 in opposite direction
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        long type = PositionGetInteger(POSITION_TYPE);
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        int trendNow = GetTrendDirection();
        if((type == POSITION_TYPE_BUY && trendNow != 1) || (type == POSITION_TYPE_SELL && trendNow != -1)) {
            if(trade.PositionClose(PositionGetTicket(i))) {
                if(EnableDebugLogs) Print("[SDE] Closed position ", PositionGetTicket(i), " due to momentum reversal");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit() {
    Print("=== Supply & Demand EA Initialized ===");
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "SDE_");
}
//+------------------------------------------------------------------+ 