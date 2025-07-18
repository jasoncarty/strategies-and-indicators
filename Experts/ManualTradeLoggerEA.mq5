//+------------------------------------------------------------------+
//| ManualTradeLoggerEA.mq5 - Manual Trading Data Collector         |
//| Allows manual trading in Strategy Tester, logs trade context    |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"
#include "../../Include/Controls/Button.mqh"
#include "../../Include/Controls/Dialog.mqh"
#include "../../Include/Controls/Edit.mqh"
#include "../../Include/Controls/Label.mqh"

//--- Inputs (all at top, before any code)
input double RiskPercent = 1.0; // Risk per trade (% of balance)
input string JsonFileName = "ManualTradeLog.json";
input int SRLookbackBars = 200;
input double SRTolerance = 10.0; // in points
input int SRMergeDistance = 50; // in points
input color SRSupportColor = clrAqua;
input color SRResistanceColor = clrMagenta;

double userRiskPercent = RiskPercent;
//--- Globals
CTrade trade;
CDialog controlsDialog;
CButton buyBtn;
CButton sellBtn;
CButton closeOrderBtn;
CLabel tpLabel;
CLabel slLabel;
CEdit tpInput;
CEdit slInput;
long chartId;
int panelX = 10, panelY = 10, panelW = 350, panelH = 180;
string objPrefix = "MTL_";

//--- Panel state
string slInputValue = "";
string tpInputValue = "";
double lastSL = 0, lastTP = 0;
double lastLot = 0;
string lastDir = "";

//--- Supply/Demand zone arrays
SDZone demandZones[];
SDZone supplyZones[];
//--- S/R zone arrays
SRZone supportZones[];
SRZone resistanceZones[];

//--- Helper: Draw panel
bool DrawPanel() {
    Print("DrawPanel called");
    // Panel background
    if(!controlsDialog.Create(0, "Controls dialog", 0, 50, 50, 500, 400)) {
        Print("Failed to create controls dialog");
        return false;
    };
    
    // TP label
    if(!tpLabel.Create(0, "TP Label", 0, 60, 30, 200, 50)) {
        Print("Failed to create TP Label");
        return false;
    }
    tpLabel.Text("Take profit price");
    tpLabel.Color(clrBlack);
    
    
    // TP Input
    if(!tpInput.Create(0, "TP input", 0, 60, 70, 391, 110)) {
        Print("Failed to create TP input");
        return false;
    }
    tpInput.Text("0.0");
    tpInput.Color(clrBlack);
    tpInput.ReadOnly(false);
    
    // SL label
    if(!slLabel.Create(0, "SL Label", 0, 60, 120, 200, 130)) {
        Print("Failed to create SL Label");
        return false;
    }
    slLabel.Text("Stop loss price");
    slLabel.Color(clrBlack);
    
    // SL input
    if(!slInput.Create(0, "SL input", 0, 60, 160, 391, 200)) {
        Print("Failed to create SL input");
        return false;
    }
    slInput.Text("0.0");
    slInput.Color(clrBlack);
    slInput.ReadOnly(false);
    
    // Buy button
    string buyBtnName = objPrefix + "BUY_BTN";
    if(!buyBtn.Create(0, buyBtnName, 0, 60, 220, 200, 260)) {
        Print("Failed to create buy button");
        return false;
    };
    buyBtn.Text("BUY");
    buyBtn.Color(clrWhite);
    buyBtn.ColorBackground(clrGreen);
    
    // Sell button
    string sellBtnName = objPrefix + "SELL_BTN";
    if(!sellBtn.Create(0, sellBtnName, 0, 251, 220, 391, 260)) {
        Print("Failed to create sell button");
        return false;
    };
    sellBtn.Text("SELL");
    sellBtn.Color(clrWhite);
    sellBtn.ColorBackground(clrRed);

    if(!controlsDialog.Add(buyBtn)) {
        Print("Failed to add buy button to dialog");
        return false;
    };
    if(!controlsDialog.Add(sellBtn)) {
        Print("Failed to add sell button to dialog");
        return false;
    };
    controlsDialog.Add(tpLabel);
    controlsDialog.Add(slLabel);
    controlsDialog.Add(tpInput);
    controlsDialog.Add(slInput);

    return true;
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
  Print("OnChartEvent called");
  Print("id: ", id);
  Print("lparam: ", lparam);
  Print("dparam: ", dparam);
  Print("sparam: ", sparam);
}

//--- Helper: Get input values
void ReadInputs() {
    string slField = objPrefix + "SL_INP";
    string tpField = objPrefix + "TP_INP";
    string riskField = objPrefix + "RISK_INP";
    slInputValue = ObjectGetString(0, slField, OBJPROP_TEXT);
    tpInputValue = ObjectGetString(0, tpField, OBJPROP_TEXT);
    string riskStr = ObjectGetString(0, riskField, OBJPROP_TEXT);
    if(StringToDouble(riskStr) > 0) userRiskPercent = StringToDouble(riskStr);
}

//--- Helper: Collect indicator/context data
void CollectTradeContext(string dir, double lot, double sl, double tp, double entry) {
    // Indicator values
    double rsi = 0, stochMain = 0, stochSignal = 0, ad = 0, volume = 0, ma = 0, atr = 0, macdMain = 0, macdSignal = 0, bbUpper = 0, bbLower = 0, spread = 0;
    // RSI
    int rsiHandle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
    if(rsiHandle != INVALID_HANDLE) {
        double buf[1];
        if(CopyBuffer(rsiHandle, 0, 0, 1, buf) > 0) rsi = buf[0];
        IndicatorRelease(rsiHandle);
    }
    // Stochastic
    int stochHandle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    if(stochHandle != INVALID_HANDLE) {
        double bufMain[1], bufSignal[1];
        if(CopyBuffer(stochHandle, 0, 0, 1, bufMain) > 0) stochMain = bufMain[0];
        if(CopyBuffer(stochHandle, 1, 0, 1, bufSignal) > 0) stochSignal = bufSignal[0];
        IndicatorRelease(stochHandle);
    }
    // Accumulation/Distribution
    int adHandle = iAD(_Symbol, _Period, VOLUME_TICK);
    if(adHandle != INVALID_HANDLE) {
        double buf[1];
        if(CopyBuffer(adHandle, 0, 0, 1, buf) > 0) ad = buf[0];
        IndicatorRelease(adHandle);
    }
    // Volume
    volume = (double)iVolume(_Symbol, _Period, 0);
    // MA
    int maHandle = iMA(_Symbol, _Period, 50, 0, MODE_SMA, PRICE_CLOSE);
    if(maHandle != INVALID_HANDLE) {
        double buf[1];
        if(CopyBuffer(maHandle, 0, 0, 1, buf) > 0) ma = buf[0];
        IndicatorRelease(maHandle);
    }
    // ATR
    atr = GetATR(_Symbol, _Period, 14);
    // MACD
    int macdHandle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    if(macdHandle != INVALID_HANDLE) {
        double bufMain[1], bufSignal[1];
        if(CopyBuffer(macdHandle, 0, 0, 1, bufMain) > 0) macdMain = bufMain[0];
        if(CopyBuffer(macdHandle, 1, 0, 1, bufSignal) > 0) macdSignal = bufSignal[0];
        IndicatorRelease(macdHandle);
    }
    // Bollinger Bands
    int bbHandle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    if(bbHandle != INVALID_HANDLE) {
        double bufUpper[1], bufLower[1];
        if(CopyBuffer(bbHandle, 1, 0, 1, bufUpper) > 0) bbUpper = bufUpper[0];
        if(CopyBuffer(bbHandle, 2, 0, 1, bufLower) > 0) bbLower = bufLower[0];
        IndicatorRelease(bbHandle);
    }
    spread = GetSpread(_Symbol);
    // Trend direction (SMA 50 on daily)
    int smaHandle = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_SMA, PRICE_CLOSE);
    string trendStr = "none";
    if(smaHandle != INVALID_HANDLE) {
        double smaBuf[2];
        ArraySetAsSeries(smaBuf, true);
        if(CopyBuffer(smaHandle, 0, 0, 2, smaBuf) > 0) {
            double price = iClose(_Symbol, PERIOD_D1, 0);
            if(price > smaBuf[0]) trendStr = "bullish";
            else if(price < smaBuf[0]) trendStr = "bearish";
        }
        IndicatorRelease(smaHandle);
    }
    // Candle pattern
    double open[3], close[3], high[3], low[3];
    CopyOpen(_Symbol, _Period, 0, 3, open);
    CopyClose(_Symbol, _Period, 0, 3, close);
    CopyHigh(_Symbol, _Period, 0, 3, high);
    CopyLow(_Symbol, _Period, 0, 3, low);
    string candlePattern = "none";
    if(IsBullishEngulfing(open, close, 1)) candlePattern = "bullish_engulfing";
    else if(IsBearishEngulfing(open, close, 1)) candlePattern = "bearish_engulfing";
    else if(IsHammer(open, high, low, close, 0)) candlePattern = "hammer";
    else if(IsShootingStar(open, high, low, close, 0)) candlePattern = "shooting_star";
    // Sequence of last 3 candles
    string seq = "";
    for(int i=2; i>=0; i--) seq += (close[i]>open[i] ? "B" : "S");
    // S/D zone context
    string zoneType = "none";
    double zoneUpper = 0, zoneLower = 0;
    datetime zoneStart = 0, zoneEnd = 0;
    // Check demand zones (most recent first)
    for(int i = 0; i < ArraySize(demandZones); i++) {
        if(entry <= demandZones[i].upper && entry >= demandZones[i].lower) {
            zoneType = "demand";
            zoneUpper = demandZones[i].upper;
            zoneLower = demandZones[i].lower;
            zoneStart = demandZones[i].startTime;
            zoneEnd = demandZones[i].endTime;
            break;
        }
    }
    // If not in demand, check supply
    if(zoneType == "none") {
        for(int i = 0; i < ArraySize(supplyZones); i++) {
            if(entry <= supplyZones[i].upper && entry >= supplyZones[i].lower) {
                zoneType = "supply";
                zoneUpper = supplyZones[i].upper;
                zoneLower = supplyZones[i].lower;
                zoneStart = supplyZones[i].startTime;
                zoneEnd = supplyZones[i].endTime;
                break;
            }
        }
    }
    // Save to JSON
    string json = "{";
    json += "\"symbol\":\"" + _Symbol + "\",";
    json += "\"timeframe\":\"" + EnumToString(_Period) + "\",";
    json += "\"direction\":\"" + dir + "\",";
    json += "\"lot\":" + DoubleToString(lot,2) + ",";
    json += "\"sl\":" + DoubleToString(sl,_Digits) + ",";
    json += "\"tp\":" + DoubleToString(tp,_Digits) + ",";
    json += "\"entry\":" + DoubleToString(entry,_Digits) + ",";
    json += "\"rsi\":" + DoubleToString(rsi,2) + ",";
    json += "\"stoch\":" + DoubleToString(stochMain,2) + ","; // Changed to stochMain
    json += "\"stoch_signal\":" + DoubleToString(stochSignal,2) + ","; // Added stoch_signal
    json += "\"ad\":" + DoubleToString(ad,2) + ",";
    json += "\"volume\":" + DoubleToString(volume,0) + ",";
    json += "\"ma\":" + DoubleToString(ma,_Digits) + ",";
    json += "\"atr\":" + DoubleToString(atr,_Digits) + ",";
    json += "\"macd\":" + DoubleToString(macdMain,2) + ","; // Changed to macdMain
    json += "\"macd_signal\":" + DoubleToString(macdSignal,2) + ","; // Added macd_signal
    json += "\"bb_upper\":" + DoubleToString(bbUpper,_Digits) + ",";
    json += "\"bb_lower\":" + DoubleToString(bbLower,_Digits) + ",";
    json += "\"spread\":" + DoubleToString(spread,1) + ",";
    json += "\"candle_pattern\":\"" + candlePattern + "\",";
    json += "\"candle_seq\":\"" + seq + "\",";
    json += "\"zone_type\":\"" + zoneType + "\",";
    json += "\"zone_upper\":" + DoubleToString(zoneUpper,_Digits) + ",";
    json += "\"zone_lower\":" + DoubleToString(zoneLower,_Digits) + ",";
    json += "\"zone_start\":" + IntegerToString(zoneStart) + ",";
    json += "\"zone_end\":" + IntegerToString(zoneEnd) + ",";
    json += "\"trend\":\"" + trendStr + "\",";
    json += "\"timestamp\":" + IntegerToString(TimeCurrent()) + "}";
    int handle = FileOpen(JsonFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
    if(handle == INVALID_HANDLE) handle = FileOpen(JsonFileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
    if(handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, json);
        FileClose(handle);
    }
}

//--- Helper: Place order and log
void PlaceManualOrder(string dir) {
    Print("PlaceManualOrder called");
    ReadInputs();
    double entry = (dir == "buy") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = StringToDouble(slInputValue);
    double tp = StringToDouble(tpInputValue);
    double stopDist = MathAbs(entry - sl);
    double lot = CalculateLotSize(userRiskPercent, stopDist, _Symbol);
    bool placed = false;
    if(dir == "buy")
        placed = PlaceBuyOrder(lot, sl, tp, 0, "ManualBuy");
    else
        placed = PlaceSellOrder(lot, sl, tp, 0, "ManualSell");
    if(placed) {
        lastSL = sl; lastTP = tp; lastLot = lot; lastDir = dir;
        CollectTradeContext(dir, lot, sl, tp, entry);
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

void CheckForManualTrade() {
    if(buyBtn.Pressed()) {
        PlaceManualOrder("buy");
        buyBtn.Pressed(false);
    };
    if(sellBtn.Pressed()) {
        PlaceManualOrder("sell");
        sellBtn.Pressed(false);
    };
}

//--- Main OnTick
void OnTick() {
    if(buyBtn.Pressed()) {
        Print(__FUNCTION__, " Buy button clicked");
        PlaceManualOrder("buy");
        buyBtn.Pressed(false);
    };
    if(sellBtn.Pressed()) {
        Print(__FUNCTION__, " Sell  button clicked");
        PlaceManualOrder("sell");
        sellBtn.Pressed(false);
    };
    if(!IsNewBar()) return;
    // Print trend log
    int smaHandle = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_SMA, PRICE_CLOSE);
    string trendStr = "none";
    if(smaHandle != INVALID_HANDLE) {
        double smaBuf[2];
        ArraySetAsSeries(smaBuf, true);
        if(CopyBuffer(smaHandle, 0, 0, 2, smaBuf) > 0) {
            double price = iClose(_Symbol, PERIOD_D1, 0);
            if(price > smaBuf[0]) trendStr = "bullish";
            else if(price < smaBuf[0]) trendStr = "bearish";
        }
        IndicatorRelease(smaHandle);
    }
    Print("[MTL] Trend on candle close: ", trendStr);
    // Detect and draw supply/demand zones
    FindSupplyDemandZones(_Symbol, _Period, 200, 2, demandZones, supplyZones);
    DrawZones(_Symbol, _Period, demandZones, supplyZones, clrGreen, clrRed, "MTL_SD_ZONE_");
    // Detect and draw S/R zones
    FindSRZones(_Symbol, _Period, SRLookbackBars, SRTolerance*_Point, SRMergeDistance, supportZones, resistanceZones);
    DrawSRZones(_Symbol, _Period, supportZones, resistanceZones, SRSupportColor, SRResistanceColor, SRLookbackBars, "MTL_SR_ZONE_");
}

//--- OnInit/OnDeinit
int OnInit() {
    if(!DrawPanel()) {
        Print("Failed to draw panel");
        return INIT_FAILED;
    };
    ChartRedraw();
    
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, objPrefix);
    controlsDialog.Destroy(reason);
}
//+------------------------------------------------------------------+ 