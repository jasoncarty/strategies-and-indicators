//+------------------------------------------------------------------+
//| ICT Power Of Three Indicator (Accumulation, Manipulation, Distribution)
//| Replicates TradingView/FluxCharts logic for MT5                 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0

#include <MovingAverages.mqh>

// === Input Parameters (match TradingView) ===
input string AlgorithmMode = "Small Manipulation";     // [Small Manipulation, Short Accumulation, Big Manipulation]
input string BreakoutMethod = "Wick";                 // [Close, Wick]
input int    ATRLen = 50;                             // ATR period
input double AccumulationExpandMult = 0.5;            // Accumulation expansion multiplier
input int    AccumulationLengthHigh = 40;             // High accumulation length
input int    AccumulationLengthLow = 11;              // Low accumulation length
input double AccumulationATRMultHigh = 5.0;           // High accumulation ATR multiplier
input double AccumulationATRMultLow = 2.0;            // Low accumulation ATR multiplier
input double ManipulationATRMultHigh = 1.0;           // High manipulation ATR multiplier
input double ManipulationATRMultLow = 0.6;            // Low manipulation ATR multiplier
input double slATRMult = 5.0;                         // Stop loss ATR multiplier (dynamic method)
input double RR = 0.86;                               // Risk/reward ratio (dynamic method)
input int MaxLookbackBars = 2000;

// === Colors ===
color AccumColor = clrYellow;
color ManipColor = clrRed;
color EntryColor = clrGreen;

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DeleteAllPO3Objects();
}

//+------------------------------------------------------------------+
//| Helper: Delete all PO3 objects from the chart                    |
//+------------------------------------------------------------------+
void DeleteAllPO3Objects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "PO3_") == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // Only run calculations at the close of a candle (not on every tick)
    if (rates_total <= 1 || !IsNewCandle())
        return(rates_total);

    // === Parameter selection logic ===
    int accumulationLength = 40;
    double accumulationATRMult = 5.0;
    double manipulationATRMult = 0.6;
    if(AlgorithmMode == "Small Manipulation") {
        accumulationLength = AccumulationLengthHigh;
        accumulationATRMult = AccumulationATRMultHigh;
        manipulationATRMult = ManipulationATRMultLow;
    } else if(AlgorithmMode == "Short Accumulation") {
        accumulationLength = AccumulationLengthLow;
        accumulationATRMult = AccumulationATRMultLow;
        manipulationATRMult = ManipulationATRMultHigh;
    } else if(AlgorithmMode == "Big Manipulation") {
        accumulationLength = AccumulationLengthHigh;
        accumulationATRMult = AccumulationATRMultHigh;
        manipulationATRMult = ManipulationATRMultHigh;
    }

    // === Main loop (state machine per bar) ===
    int state = 0; // 0=WAIT_ACCUM, 1=WAIT_MANIP, 2=WAIT_ENTRY, 3=TRADE_DONE
    int accumStart = -1, accumEnd = -1;
    double accumTop = 0, accumBottom = 0;
    int manipStart = -1, manipEnd = -1;
    double manipTop = 0, manipBottom = 0;
    string manipDir = "";
    int entryIdx = -1;
    double entryPrice = 0, slTarget = 0, tpTarget = 0;
    string entryType = "";

    Print("rates_total: ", rates_total);
    Print("MaxLookbackBars: ", MaxLookbackBars);
    Print("accumulationLength: ", accumulationLength);
    Print("ATRLen: ", ATRLen);

    int startBar = MathMax(0, rates_total - MaxLookbackBars - accumulationLength - ATRLen - 2);
    int endBar = rates_total-accumulationLength-ATRLen-2;
    for(int bar = startBar; bar <= endBar; bar++) {
        // === Accumulation detection (previous N bars, not including current bar) ===
        double highest = high[bar+1];
        double lowest = low[bar+1];
        for(int j=bar+1; j<=bar+accumulationLength; j++) {
            if(high[j] > highest) highest = high[j];
            if(low[j] < lowest) lowest = low[j];
        }
        // True ATR over last ATRLen bars ending at bar+accumulationLength
        double tr = 0, atr = 0;
        double prevClose = close[bar+1];
        int atrStart = bar+2;
        int atrEnd = atrStart + ATRLen - 1;
        int atrCount = 0;
        for(int i = atrStart; i <= atrEnd; i++) {
            double highLow = high[i] - low[i];
            double highClose = MathAbs(high[i] - prevClose);
            double lowClose = MathAbs(low[i] - prevClose);
            tr = MathMax(highLow, MathMax(highClose, lowClose));
            atr += tr;
            prevClose = close[i];
            atrCount++;
        }
        if(atrCount > 0) atr /= atrCount;
        else atr = 0;
        double accRange = highest - lowest;
        double accThreshold = atr * accumulationATRMult;
        if(accRange <= accThreshold) {
            // Accumulation found
            accumStart = bar+1;
            accumEnd = bar+accumulationLength;
            accumTop = highest + (atr * AccumulationExpandMult);
            accumBottom = lowest - (atr * AccumulationExpandMult);
            Print("[DEBUG] Accumulation: bar=", bar, " start=", TimeToString(time[accumStart]), " end=", TimeToString(time[accumEnd]), " high=", highest, " low=", lowest, " range=", accRange, " threshold=", accThreshold);
            // Draw accumulation box
            string accumName = "PO3_Accum_"+IntegerToString(accumStart);
            if(ObjectFind(0, accumName) == -1) {
                ObjectCreate(0, accumName, OBJ_RECTANGLE, 0, time[accumEnd], accumBottom, time[accumStart], accumTop);
            }
            ObjectSetInteger(0, accumName, OBJPROP_COLOR, AccumColor);
            ObjectSetInteger(0, accumName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, accumName, OBJPROP_BACK, true);
            // Set rectangle corners (accumEnd, accumBottom) and (accumStart, accumTop)
            ObjectSetInteger(0, accumName, OBJPROP_TIME, 0, time[accumEnd]);
            ObjectSetDouble(0, accumName, OBJPROP_PRICE, 0, accumBottom);
            ObjectSetInteger(0, accumName, OBJPROP_TIME, 1, time[accumStart]);
            ObjectSetDouble(0, accumName, OBJPROP_PRICE, 1, accumTop);
            // === Manipulation detection ===
            for(int m=accumEnd+1; m<rates_total-1; m++) {
                double breakoutHigh = (BreakoutMethod == "Wick") ? high[m] : close[m];
                double breakoutLow = (BreakoutMethod == "Wick") ? low[m] : close[m];
                if(breakoutHigh > accumTop + (atr * manipulationATRMult)) {
                    manipStart = accumEnd;
                    manipEnd = m;
                    manipTop = breakoutHigh;
                    manipBottom = accumBottom;
                    manipDir = "Bullish";
                    Print("[DEBUG] Manipulation (Bullish): start=", TimeToString(time[manipStart]), " end=", TimeToString(time[manipEnd]), " top=", manipTop, " bottom=", manipBottom);
                    // Draw manipulation box
                    string manipName = "PO3_Manip_"+IntegerToString(manipEnd);
                    if(ObjectFind(0, manipName) == -1) {
                        ObjectCreate(0, manipName, OBJ_RECTANGLE, 0, time[manipEnd], manipBottom, time[manipStart], manipTop);
                    }
                    ObjectSetInteger(0, manipName, OBJPROP_COLOR, ManipColor);
                    ObjectSetInteger(0, manipName, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, manipName, OBJPROP_BACK, true);
                    // Set rectangle corners (manipEnd, manipBottom) and (manipStart, manipTop)
                    ObjectSetInteger(0, manipName, OBJPROP_TIME, 0, time[manipEnd]);
                    ObjectSetDouble(0, manipName, OBJPROP_PRICE, 0, manipBottom);
                    ObjectSetInteger(0, manipName, OBJPROP_TIME, 1, time[manipStart]);
                    ObjectSetDouble(0, manipName, OBJPROP_PRICE, 1, manipTop);
                    // Entry
                    entryIdx = manipEnd+1;
                    entryPrice = close[entryIdx];
                    entryType = "Short";
                    slTarget = entryPrice + atr * slATRMult;
                    tpTarget = entryPrice - (MathAbs(entryPrice - slTarget) * RR);
                    Print("[DEBUG] Entry (Short): idx=", entryIdx, " time=", TimeToString(time[entryIdx]), " price=", entryPrice);
                    // Draw entry arrow
                    string entryName = "PO3_Entry_"+IntegerToString(entryIdx);
                    if(ObjectFind(0, entryName) == -1) {
                        ObjectCreate(0, entryName, OBJ_ARROW, 0, time[entryIdx], entryPrice);
                    }
                    ObjectSetInteger(0, entryName, OBJPROP_COLOR, EntryColor);
                    ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, entryName, OBJPROP_TIME, 0, time[entryIdx]);
                    ObjectSetDouble(0, entryName, OBJPROP_PRICE, 0, entryPrice);
                    break;
                } else if(breakoutLow < accumBottom - (atr * manipulationATRMult)) {
                    manipStart = accumEnd;
                    manipEnd = m;
                    manipTop = accumTop;
                    manipBottom = breakoutLow;
                    manipDir = "Bearish";
                    Print("[DEBUG] Manipulation (Bearish): start=", TimeToString(time[manipStart]), " end=", TimeToString(time[manipEnd]), " top=", manipTop, " bottom=", manipBottom);
                    // Draw manipulation box
                    string manipName = "PO3_Manip_"+IntegerToString(manipEnd);
                    if(ObjectFind(0, manipName) == -1) {
                        ObjectCreate(0, manipName, OBJ_RECTANGLE, 0, time[manipEnd], manipBottom, time[manipStart], manipTop);
                    }
                    ObjectSetInteger(0, manipName, OBJPROP_COLOR, ManipColor);
                    ObjectSetInteger(0, manipName, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, manipName, OBJPROP_BACK, true);
                    // Set rectangle corners (manipEnd, manipBottom) and (manipStart, manipTop)
                    ObjectSetInteger(0, manipName, OBJPROP_TIME, 0, time[manipEnd]);
                    ObjectSetDouble(0, manipName, OBJPROP_PRICE, 0, manipBottom);
                    ObjectSetInteger(0, manipName, OBJPROP_TIME, 1, time[manipStart]);
                    ObjectSetDouble(0, manipName, OBJPROP_PRICE, 1, manipTop);
                    // Entry
                    entryIdx = manipEnd+1;
                    entryPrice = close[entryIdx];
                    entryType = "Long";
                    slTarget = entryPrice - atr * slATRMult;
                    tpTarget = entryPrice + (MathAbs(entryPrice - slTarget) * RR);
                    Print("[DEBUG] Entry (Long): idx=", entryIdx, " time=", TimeToString(time[entryIdx]), " price=", entryPrice);
                    // Draw entry arrow
                    string entryName = "PO3_Entry_"+IntegerToString(entryIdx);
                    if(ObjectFind(0, entryName) == -1) {
                        ObjectCreate(0, entryName, OBJ_ARROW, 0, time[entryIdx], entryPrice);
                    }
                    ObjectSetInteger(0, entryName, OBJPROP_COLOR, EntryColor);
                    ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, entryName, OBJPROP_TIME, 0, time[entryIdx]);
                    ObjectSetDouble(0, entryName, OBJPROP_PRICE, 0, entryPrice);
                    break;
                }
            }
            // Only show the first valid setup per bar
            // break;
        }
    }
    return(rates_total);
}
//+------------------------------------------------------------------+
//| Helper: Detect fresh bar (run only at candle close)                |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
    static datetime lastTime = 0;
    datetime currentTime = iTime(_Symbol, _Period, 0);
    if(currentTime != lastTime) {
        lastTime = currentTime;
        return true;
    }
    return false;
}
//+------------------------------------------------------------------+
//| End of ICT Power Of Three Indicator                              |
//+------------------------------------------------------------------+ 