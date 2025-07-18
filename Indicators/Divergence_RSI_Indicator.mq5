//+------------------------------------------------------------------+
//| Divergence RSI Indicator (MT5)                                   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0

#include <MovingAverages.mqh>

// Input parameters
input int    RSIPeriod = 14;
input int    SwingLookback = 5; // Bars left/right for swing high/low
input double RR = 2.0; // Risk/Reward ratio for TP
color BullDivColor = clrLime;
color BearDivColor = clrRed;
color BuyArrowColor = clrAqua;
color SellArrowColor = clrMagenta;
color SLColor = clrOrange;
color TPColor = clrGreen;
input bool EnableAlerts = false; // Enable pop-up alerts for divergences
input int MaxLookbackBars = 1000; // Maximum bars to look back for divergence detection
input ENUM_TIMEFRAMES HTF = PERIOD_H1; // Higher timeframe for divergence detection

// Arrow symbols
#define ARROW_BUY  233 // Wingdings up arrow
#define ARROW_SELL 234 // Wingdings down arrow

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
    // Cleanup all objects at the start to avoid duplicates on refresh/timeframe change
    ArraySetAsSeries(time, true);
    if(rates_total < RSIPeriod + SwingLookback*2 + 2)
        return(rates_total);

    // Calculate RSI
    double rsi[];
    ArrayResize(rsi, rates_total);
    int rsi_handle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE)
        return(rates_total);
    if(CopyBuffer(rsi_handle, 0, 0, rates_total, rsi) <= 0)
        return(rates_total);
    ArraySetAsSeries(rsi, true);

    // --- Fetch HTF data ---
    int htf_bars = MaxLookbackBars + 2*SwingLookback + RSIPeriod + 10;
    datetime htf_time[]; double htf_close[]; double htf_high[]; double htf_low[];
    ArraySetAsSeries(htf_time, true); ArraySetAsSeries(htf_close, true); ArraySetAsSeries(htf_high, true); ArraySetAsSeries(htf_low, true);
    if(CopyTime(_Symbol, HTF, 0, htf_bars, htf_time) <= 0) return(rates_total);
    if(CopyClose(_Symbol, HTF, 0, htf_bars, htf_close) <= 0) return(rates_total);
    if(CopyHigh(_Symbol, HTF, 0, htf_bars, htf_high) <= 0) return(rates_total);
    if(CopyLow(_Symbol, HTF, 0, htf_bars, htf_low) <= 0) return(rates_total);
    // --- Fetch HTF RSI ---
    double htf_rsi[]; ArrayResize(htf_rsi, htf_bars);
    int htf_rsi_handle = iRSI(_Symbol, HTF, RSIPeriod, PRICE_CLOSE);
    if(htf_rsi_handle == INVALID_HANDLE) return(rates_total);
    if(CopyBuffer(htf_rsi_handle, 0, 0, htf_bars, htf_rsi) <= 0) return(rates_total);
    ArraySetAsSeries(htf_rsi, true);
    // --- Divergence detection on HTF ---
    int htf_total = ArraySize(htf_time);
    int endBar = MathMin(SwingLookback + MaxLookbackBars, htf_total - SwingLookback);
    // Debug: Print most recent bar time on chart
    Print("[DEBUG] Most recent chart bar time: ", TimeToString(time[0]));
    // Debug: Print oldest bar time on chart
    Print("[DEBUG] Oldest chart bar time: ", TimeToString(time[rates_total-1]));
    // Debug: Print most recent HTF bar time
    Print("[DEBUG] Most recent HTF bar time: ", TimeToString(htf_time[0]), "  HTF[MaxLookbackBars] time: ", TimeToString(htf_time[MathMin(MaxLookbackBars, ArraySize(htf_time)-1)]));
    // Reverse loop: from most recent to less recent
    for(int i = SwingLookback; i < endBar; i++) {
        int idx = i; // most recent = SwingLookback, less recent as i increases
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
            for(int k = idx+1; k < htf_total - SwingLookback; k++)
            {
                bool prevIsPriceLow = true, prevIsRSILow = true;
                for(int j = 1; j <= SwingLookback; j++)
                {
                    if(htf_low[k] > htf_low[k-(int)j] || htf_low[k] > htf_low[k+(int)j]) prevIsPriceLow = false;
                    if(htf_rsi[k] > htf_rsi[k-(int)j] || htf_rsi[k] > htf_rsi[k+(int)j]) prevIsRSILow = false;
                }
                if(prevIsPriceLow && prevIsRSILow && htf_low[idx] < htf_low[k] && htf_rsi[idx] > htf_rsi[k])
                {
                    double sl = htf_low[idx] - (htf_low[k] - htf_low[idx]);
                    double tp = htf_low[idx] + RR * (htf_low[idx] - sl);
                    int entryBar = idx-1;
                    int endBar = 0;
                    string outcome = "none";
                    for(int b = entryBar; b >= 0; b--) {
                        if(htf_low[b] <= sl) { endBar = b; outcome = "sl"; break; }
                        if(htf_high[b] >= tp) { endBar = b; outcome = "tp"; break; }
                    }
                    // Map HTF times to current chart bars for drawing
                    int entryIdx = iBarShift(_Symbol, _Period, htf_time[entryBar], true);
                    int endIdx = iBarShift(_Symbol, _Period, htf_time[endBar], true);
                    if(entryIdx < 0 || endIdx < 0) break;
                    // Debug: Print HTF bar time: mapped to chart bar
                    Print("[DEBUG] HTF bar time: ", TimeToString(htf_time[entryBar]), " mapped to chart bar: ", entryIdx, " (", TimeToString(time[entryIdx]), ")");
                    // Debug: Print horizontal line parameters
                    PrintFormat("[DEBUG] SL Line: entryIdx=%d, entryTime=%s, entryPrice=%.5f, endIdx=%d, endTime=%s, sl=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), sl, endIdx, TimeToString(time[endIdx], TIME_DATE|TIME_SECONDS), sl);
                    PrintFormat("[DEBUG] TP Line: entryIdx=%d, entryTime=%s, entryPrice=%.5f, endIdx=%d, endTime=%s, tp=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), tp, endIdx, TimeToString(time[endIdx], TIME_DATE|TIME_SECONDS), tp);
                    // Draw SL/TP horizontal lines: always from entryIdx (entry) to endIdx (SL/TP hit), extending right
                    if (entryIdx != endIdx) {
                        string slLine = "SL_Bull_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, slLine, OBJ_TREND, 0, time[entryIdx], sl, time[endIdx], sl);
                        ObjectSetInteger(0, slLine, OBJPROP_COLOR, (outcome=="sl" ? clrRed : SLColor));
                        ObjectSetInteger(0, slLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, slLine, OBJPROP_STYLE, STYLE_DASH);
                        string tpLine = "TP_Bull_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, tpLine, OBJ_TREND, 0, time[entryIdx], tp, time[endIdx], tp);
                        ObjectSetInteger(0, tpLine, OBJPROP_COLOR, (outcome=="tp" ? clrGreen : TPColor));
                        ObjectSetInteger(0, tpLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, tpLine, OBJPROP_STYLE, STYLE_DASH);
                    } else if (entryIdx - 1 >= 0) {
                        // Debug: Print horizontal line parameters for fallback case
                        PrintFormat("[DEBUG] SL Line (fallback): entryIdx=%d, entryTime=%s, entryPrice=%.5f, nextIdx=%d, nextTime=%s, sl=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), sl, entryIdx-1, TimeToString(time[entryIdx-1], TIME_DATE|TIME_SECONDS), sl);
                        PrintFormat("[DEBUG] TP Line (fallback): entryIdx=%d, entryTime=%s, entryPrice=%.5f, nextIdx=%d, nextTime=%s, tp=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), tp, entryIdx-1, TimeToString(time[entryIdx-1], TIME_DATE|TIME_SECONDS), tp);
                        string slLine = "SL_Bull_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, slLine, OBJ_TREND, 0, time[entryIdx], sl, time[entryIdx-1], sl);
                        ObjectSetInteger(0, slLine, OBJPROP_COLOR, (outcome=="sl" ? clrRed : SLColor));
                        ObjectSetInteger(0, slLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, slLine, OBJPROP_STYLE, STYLE_DASH);
                        string tpLine = "TP_Bull_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, tpLine, OBJ_TREND, 0, time[entryIdx], tp, time[entryIdx-1], tp);
                        ObjectSetInteger(0, tpLine, OBJPROP_COLOR, (outcome=="tp" ? clrGreen : TPColor));
                        ObjectSetInteger(0, tpLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, tpLine, OBJPROP_STYLE, STYLE_DASH);
                    }
                    // Entry label
                    string lblBuy = "Lbl_Buy_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblBuy, OBJ_RECTANGLE_LABEL, 0, time[entryIdx], low[entryIdx]);
                    ObjectSetString(0, lblBuy, OBJPROP_TEXT, "Buy (HTF)");
                    ObjectSetInteger(0, lblBuy, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblBuy, OBJPROP_BGCOLOR, clrGreen);
                    ObjectSetInteger(0, lblBuy, OBJPROP_FONTSIZE, 10);
                    // SL label
                    string lblSL = "Lbl_SL_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblSL, OBJ_RECTANGLE_LABEL, 0, time[endIdx], sl);
                    ObjectSetString(0, lblSL, OBJPROP_TEXT, "SL");
                    ObjectSetInteger(0, lblSL, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblSL, OBJPROP_BGCOLOR, SLColor);
                    ObjectSetInteger(0, lblSL, OBJPROP_FONTSIZE, 10);
                    // TP label
                    string lblTP = "Lbl_TP_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblTP, OBJ_RECTANGLE_LABEL, 0, time[endIdx], tp);
                    ObjectSetString(0, lblTP, OBJPROP_TEXT, "TP");
                    ObjectSetInteger(0, lblTP, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblTP, OBJPROP_BGCOLOR, TPColor);
                    ObjectSetInteger(0, lblTP, OBJPROP_FONTSIZE, 10);
                    // Alert
                    string msg = StringFormat("Bullish RSI Divergence (HTF): Buy at %.5f, SL at %.5f, TP at %.5f, Time: %s", htf_low[idx], sl, tp, TimeToString(htf_time[entryBar]));
                    if(EnableAlerts) Alert(msg);
                    Print(msg);
                    // Draw entry arrow
                    string arrowName = "Arrow_Buy_"+IntegerToString(idx);
                    ObjectCreate(0, arrowName, OBJ_ARROW, 0, time[entryIdx], low[entryIdx]);
                    ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
                    ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, ARROW_BUY);
                    ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
                    // Vertical lines from entry to SL/TP
                    string vlineSL = "VLine_Buy_SL_"+IntegerToString(idx);
                    ObjectCreate(0, vlineSL, OBJ_TREND, 0, time[entryIdx], htf_low[idx], time[entryIdx], sl);
                    ObjectSetInteger(0, vlineSL, OBJPROP_COLOR, SLColor);
                    ObjectSetInteger(0, vlineSL, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, vlineSL, OBJPROP_STYLE, STYLE_DASH);
                    string vlineTP = "VLine_Buy_TP_"+IntegerToString(idx);
                    ObjectCreate(0, vlineTP, OBJ_TREND, 0, time[entryIdx], htf_low[idx], time[entryIdx], tp);
                    ObjectSetInteger(0, vlineTP, OBJPROP_COLOR, TPColor);
                    ObjectSetInteger(0, vlineTP, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, vlineTP, OBJPROP_STYLE, STYLE_DASH);
                    break;
                }
            }
        }
        // Bearish divergence (HTF)
        if(isPriceHigh && isRSIHigh)
        {
            for(int k = idx+1; k < htf_total - SwingLookback; k++)
            {
                bool prevIsPriceHigh = true, prevIsRSIHigh = true;
                for(int j = 1; j <= SwingLookback; j++)
                {
                    if(htf_high[k] < htf_high[k-(int)j] || htf_high[k] < htf_high[k+(int)j]) prevIsPriceHigh = false;
                    if(htf_rsi[k] < htf_rsi[k-(int)j] || htf_rsi[k] < htf_rsi[k+(int)j]) prevIsRSIHigh = false;
                }
                if(prevIsPriceHigh && prevIsRSIHigh && htf_high[idx] > htf_high[k] && htf_rsi[idx] < htf_rsi[k])
                {
                    double sl = htf_high[idx] + (htf_high[idx] - htf_high[k]);
                    double tp = htf_high[idx] - RR * (sl - htf_high[idx]);
                    int entryBar = idx-1;
                    int endBar = 0;
                    string outcome = "none";
                    for(int b = entryBar; b >= 0; b--) {
                        if(htf_high[b] >= sl) { endBar = b; outcome = "sl"; break; }
                        if(htf_low[b] <= tp) { endBar = b; outcome = "tp"; break; }
                    }
                    // Map HTF times to current chart bars for drawing
                    int entryIdx = iBarShift(_Symbol, _Period, htf_time[entryBar], true);
                    int endIdx = iBarShift(_Symbol, _Period, htf_time[endBar], true);
                    if(entryIdx < 0 || endIdx < 0) break;
                    // Debug: Print HTF bar time: mapped to chart bar
                    Print("[DEBUG] HTF bar time: ", TimeToString(htf_time[entryBar]), " mapped to chart bar: ", entryIdx, " (", TimeToString(time[entryIdx]), ")");
                    // Debug: Print horizontal line parameters
                    PrintFormat("[DEBUG] SL Line: entryIdx=%d, entryTime=%s, entryPrice=%.5f, endIdx=%d, endTime=%s, sl=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), sl, endIdx, TimeToString(time[endIdx], TIME_DATE|TIME_SECONDS), sl);
                    PrintFormat("[DEBUG] TP Line: entryIdx=%d, entryTime=%s, entryPrice=%.5f, endIdx=%d, endTime=%s, tp=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), tp, endIdx, TimeToString(time[endIdx], TIME_DATE|TIME_SECONDS), tp);
                    // Draw SL/TP horizontal lines: always from entryIdx (entry) to endIdx (SL/TP hit), extending right
                    if (entryIdx != endIdx) {
                        string slLine = "SL_Bear_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, slLine, OBJ_TREND, 0, time[entryIdx], sl, time[endIdx], sl);
                        ObjectSetInteger(0, slLine, OBJPROP_COLOR, (outcome=="sl" ? clrRed : SLColor));
                        ObjectSetInteger(0, slLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, slLine, OBJPROP_STYLE, STYLE_DASH);
                        string tpLine = "TP_Bear_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, tpLine, OBJ_TREND, 0, time[entryIdx], tp, time[endIdx], tp);
                        ObjectSetInteger(0, tpLine, OBJPROP_COLOR, (outcome=="tp" ? clrGreen : TPColor));
                        ObjectSetInteger(0, tpLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, tpLine, OBJPROP_STYLE, STYLE_DASH);
                    } else if (entryIdx - 1 >= 0) {
                        // Debug: Print horizontal line parameters for fallback case
                        PrintFormat("[DEBUG] SL Line (fallback): entryIdx=%d, entryTime=%s, entryPrice=%.5f, nextIdx=%d, nextTime=%s, sl=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), sl, entryIdx-1, TimeToString(time[entryIdx-1], TIME_DATE|TIME_SECONDS), sl);
                        PrintFormat("[DEBUG] TP Line (fallback): entryIdx=%d, entryTime=%s, entryPrice=%.5f, nextIdx=%d, nextTime=%s, tp=%.5f", entryIdx, TimeToString(time[entryIdx], TIME_DATE|TIME_SECONDS), tp, entryIdx-1, TimeToString(time[entryIdx-1], TIME_DATE|TIME_SECONDS), tp);
                        string slLine = "SL_Bear_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, slLine, OBJ_TREND, 0, time[entryIdx], sl, time[entryIdx-1], sl);
                        ObjectSetInteger(0, slLine, OBJPROP_COLOR, (outcome=="sl" ? clrRed : SLColor));
                        ObjectSetInteger(0, slLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, slLine, OBJPROP_STYLE, STYLE_DASH);
                        string tpLine = "TP_Bear_HTF_" + IntegerToString(idx);
                        ObjectCreate(0, tpLine, OBJ_TREND, 0, time[entryIdx], tp, time[entryIdx-1], tp);
                        ObjectSetInteger(0, tpLine, OBJPROP_COLOR, (outcome=="tp" ? clrGreen : TPColor));
                        ObjectSetInteger(0, tpLine, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, tpLine, OBJPROP_STYLE, STYLE_DASH);
                    }
                    // Entry label
                    string lblSell = "Lbl_Sell_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblSell, OBJ_RECTANGLE_LABEL, 0, time[entryIdx], high[entryIdx]);
                    ObjectSetString(0, lblSell, OBJPROP_TEXT, "Sell (HTF)");
                    ObjectSetInteger(0, lblSell, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblSell, OBJPROP_BGCOLOR, clrRed);
                    ObjectSetInteger(0, lblSell, OBJPROP_FONTSIZE, 10);
                    // SL label
                    string lblSL = "Lbl_SL_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblSL, OBJ_RECTANGLE_LABEL, 0, time[endIdx], sl);
                    ObjectSetString(0, lblSL, OBJPROP_TEXT, "SL");
                    ObjectSetInteger(0, lblSL, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblSL, OBJPROP_BGCOLOR, SLColor);
                    ObjectSetInteger(0, lblSL, OBJPROP_FONTSIZE, 10);
                    // TP label
                    string lblTP = "Lbl_TP_HTF_"+IntegerToString(idx);
                    ObjectCreate(0, lblTP, OBJ_RECTANGLE_LABEL, 0, time[endIdx], tp);
                    ObjectSetString(0, lblTP, OBJPROP_TEXT, "TP");
                    ObjectSetInteger(0, lblTP, OBJPROP_COLOR, clrWhite);
                    ObjectSetInteger(0, lblTP, OBJPROP_BGCOLOR, TPColor);
                    ObjectSetInteger(0, lblTP, OBJPROP_FONTSIZE, 10);
                    // Alert
                    string msg = StringFormat("Bearish RSI Divergence (HTF): Sell at %.5f, SL at %.5f, TP at %.5f, Time: %s", htf_high[idx], sl, tp, TimeToString(htf_time[entryBar]));
                    if(EnableAlerts) Alert(msg);
                    Print(msg);
                    // Draw entry arrow
                    string arrowName = "Arrow_Sell_"+IntegerToString(idx);
                    ObjectCreate(0, arrowName, OBJ_ARROW, 0, time[entryIdx], high[entryIdx]);
                    ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
                    ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, ARROW_SELL);
                    ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
                    // Vertical lines from entry to SL/TP
                    string vlineSL = "VLine_Sell_SL_"+IntegerToString(idx);
                    ObjectCreate(0, vlineSL, OBJ_TREND, 0, time[entryIdx], htf_high[idx], time[entryIdx], sl);
                    ObjectSetInteger(0, vlineSL, OBJPROP_COLOR, SLColor);
                    ObjectSetInteger(0, vlineSL, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, vlineSL, OBJPROP_STYLE, STYLE_DASH);
                    string vlineTP = "VLine_Sell_TP_"+IntegerToString(idx);
                    ObjectCreate(0, vlineTP, OBJ_TREND, 0, time[entryIdx], htf_high[idx], time[entryIdx], tp);
                    ObjectSetInteger(0, vlineTP, OBJPROP_COLOR, TPColor);
                    ObjectSetInteger(0, vlineTP, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(0, vlineTP, OBJPROP_STYLE, STYLE_DASH);
                    break;
                }
            }
        }
    }
    IndicatorRelease(htf_rsi_handle);
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DeleteAllDivObjects();
}

//+------------------------------------------------------------------+
//| Helper: Delete all divergence objects                            |
//+------------------------------------------------------------------+
void DeleteAllDivObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "BullDiv_") == 0 || StringFind(name, "BearDiv_") == 0 ||
           StringFind(name, "BuyArrow_") == 0 || StringFind(name, "SellArrow_") == 0 ||
           StringFind(name, "SL_Bull_") == 0 || StringFind(name, "SL_Bear_") == 0 ||
           StringFind(name, "TP_Bull_") == 0 || StringFind(name, "TP_Bear_") == 0 ||
           StringFind(name, "Lbl_Buy_") == 0 || StringFind(name, "Lbl_Sell_") == 0 ||
           StringFind(name, "Lbl_SL_") == 0 || StringFind(name, "Lbl_TP_") == 0 ||
           StringFind(name, "Arrow_Buy_") == 0 || StringFind(name, "Arrow_Sell_") == 0 ||
           StringFind(name, "VLine_Buy_SL_") == 0 || StringFind(name, "VLine_Buy_TP_") == 0 ||
           StringFind(name, "VLine_Sell_SL_") == 0 || StringFind(name, "VLine_Sell_TP_") == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| Helper: Draw modern label with background                        |
//+------------------------------------------------------------------+
void DrawLabel(string name, string text, datetime t, double price, color bg, color fg)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, t, price);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Helper: Delete all modern SL/TP/Entry objects                    |
//+------------------------------------------------------------------+
void DeleteModernDivObjects()
{
    string names[] = {"Modern_SL", "Modern_TP", "Modern_Label_Entry", "Modern_Label_SL", "Modern_Label_TP"};
    for(int i=0; i<ArraySize(names); i++)
        ObjectDelete(0, names[i]);
}

//+------------------------------------------------------------------+
//| End of Divergence RSI Indicator                                  |
//+------------------------------------------------------------------+ 