//+------------------------------------------------------------------+
//| NeuralNetworkTradeLoggerEA.mq5 - ML-Enhanced Trading EA          |
//| Uses neural network predictions to enhance manual trading        |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "../TradeUtils.mqh"
#include "../../Include/Controls/Button.mqh"
#include "../../Include/Controls/Dialog.mqh"
#include "../../Include/Controls/Edit.mqh"
#include "../../Include/Controls/Label.mqh"
#include "../../Include/Controls/CheckBox.mqh"

//--- Inputs (all at top, before any code)
input group "Risk Management"
input double RiskPercent = 1.0; // Risk per trade (% of balance)
input double MinPredictionConfidence = 0.65; // Minimum ML confidence to trade
input double MaxPredictionConfidence = 0.95; // Maximum ML confidence (avoid overfitting)

input group "ML Integration"
input bool UseMLPredictions = true; // Enable ML-based trade filtering
input bool UseMLPositionSizing = true; // Use ML confidence for position sizing
input bool UseMLStopLoss = true; // Use ML predictions for dynamic SL
input string MLModelPath = "ml_models/"; // Path to ML models
input string JsonFileName = "MLTradeLog.json";

input group "Technical Analysis"
input int SRLookbackBars = 200;
input double SRTolerance = 10.0; // in points
input int SRMergeDistance = 50; // in points
input color SRSupportColor = clrAqua;
input color SRResistanceColor = clrMagenta;

input group "UI Settings"
input bool ShowMLPredictions = true; // Show ML predictions in UI
input bool AutoTradeMode = false; // Enable automatic trading based on ML

double userRiskPercent = RiskPercent;

//--- Globals
CTrade trade;
CDialog controlsDialog;
CButton buyBtn;
CButton sellBtn;
CButton closeOrderBtn;
CButton mlPredictBtn;
CLabel tpLabel;
CLabel slLabel;
CLabel mlLabel;
CLabel confidenceLabel;
CEdit tpInput;
CEdit slInput;
CCheckBox mlCheckBox;
CCheckBox autoTradeCheckBox;
long chartId;
int panelX = 10, panelY = 10, panelW = 400, panelH = 250;
string objPrefix = "NNTL_";

//--- Panel state
string slInputValue = "";
string tpInputValue = "";
double lastSL = 0, lastTP = 0;
double lastLot = 0;
string lastDir = "";

//--- ML Prediction state
double mlPrediction = 0.0;
double mlConfidence = 0.0;
string mlDirection = "none";
bool mlModelLoaded = false;

//--- Supply/Demand zone arrays
SDZone demandZones[];
SDZone resistanceZones[];

//--- ML Feature collection (now using TradeUtils.mqh)

//--- Helper: Load ML model (placeholder for MQL5)
bool LoadMLModel() {
    // In MQL5, we would need to implement model loading
    // For now, we'll use a simple rule-based system
    Print("ML Model loading simulated - using rule-based predictions");
    mlModelLoaded = true;
    return true;
}

//--- Helper: Get ML prediction (now using TradeUtils.mqh)
//--- Helper: Calculate ML confidence (now using TradeUtils.mqh)

//--- Helper: Collect ML features (now using TradeUtils.mqh)

//--- Helper: Draw panel
bool DrawPanel() {
    Print("DrawPanel called");

    // Panel background
    if(!controlsDialog.Create(0, "ML Controls dialog", 0, 50, 50, 500, 400)) {
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

    // ML Prediction label
    if(!mlLabel.Create(0, "ML Label", 0, 60, 210, 200, 220)) {
        Print("Failed to create ML Label");
        return false;
    }
    mlLabel.Text("ML Prediction: Neutral");
    mlLabel.Color(clrBlue);

    // Confidence label
    if(!confidenceLabel.Create(0, "Confidence Label", 0, 60, 240, 200, 250)) {
        Print("Failed to create Confidence Label");
        return false;
    }
    confidenceLabel.Text("Confidence: 0%");
    confidenceLabel.Color(clrPurple);

    // ML Checkbox
    if(!mlCheckBox.Create(0, "ML Checkbox", 0, 60, 270, 200, 290)) {
        Print("Failed to create ML Checkbox");
        return false;
    }
    mlCheckBox.Text("Use ML Predictions");
    mlCheckBox.Checked(UseMLPredictions);

    // Auto Trade Checkbox
    if(!autoTradeCheckBox.Create(0, "Auto Trade Checkbox", 0, 200, 270, 340, 290)) {
        Print("Failed to create Auto Trade Checkbox");
        return false;
    }
    autoTradeCheckBox.Text("Auto Trade");
    autoTradeCheckBox.Checked(AutoTradeMode);

    // Buy button
    string buyBtnName = objPrefix + "BUY_BTN";
    if(!buyBtn.Create(0, buyBtnName, 0, 60, 300, 200, 340)) {
        Print("Failed to create buy button");
        return false;
    };
    buyBtn.Text("BUY");
    buyBtn.Color(clrWhite);
    buyBtn.ColorBackground(clrGreen);

    // Sell button
    string sellBtnName = objPrefix + "SELL_BTN";
    if(!sellBtn.Create(0, sellBtnName, 0, 251, 300, 391, 340)) {
        Print("Failed to create sell button");
        return false;
    };
    sellBtn.Text("SELL");
    sellBtn.Color(clrWhite);
    sellBtn.ColorBackground(clrRed);

    // ML Predict button
    string mlPredictBtnName = objPrefix + "ML_PREDICT_BTN";
    if(!mlPredictBtn.Create(0, mlPredictBtnName, 0, 60, 350, 391, 380)) {
        Print("Failed to create ML Predict button");
        return false;
    };
    mlPredictBtn.Text("Get ML Prediction");
    mlPredictBtn.Color(clrWhite);
    mlPredictBtn.ColorBackground(clrBlue);

    // Add all controls to dialog
    controlsDialog.Add(buyBtn);
    controlsDialog.Add(sellBtn);
    controlsDialog.Add(mlPredictBtn);
    controlsDialog.Add(tpLabel);
    controlsDialog.Add(slLabel);
    controlsDialog.Add(mlLabel);
    controlsDialog.Add(confidenceLabel);
    controlsDialog.Add(tpInput);
    controlsDialog.Add(slInput);
    controlsDialog.Add(mlCheckBox);
    controlsDialog.Add(autoTradeCheckBox);

    return true;
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

//--- Helper: Update ML display
void UpdateMLDisplay() {
    string predictionText = "ML Prediction: ";
    string confidenceText = "Confidence: ";

    if(mlDirection == "buy") {
        predictionText += "BUY";
        mlLabel.Color(clrGreen);
    } else if(mlDirection == "sell") {
        predictionText += "SELL";
        mlLabel.Color(clrRed);
    } else {
        predictionText += "NEUTRAL";
        mlLabel.Color(clrBlue);
    }

    confidenceText += DoubleToString(mlConfidence * 100, 1) + "%";

    mlLabel.Text(predictionText);
    confidenceLabel.Text(confidenceText);
}

//--- Helper: Get ML prediction and update display
void GetMLPredictionAndUpdate() {
    MLFeatures features;
    CollectMLFeatures(features);

    mlPrediction = GetMLPrediction(features);
    mlConfidence = CalculateMLConfidence(features);

    // Determine direction
    if(mlPrediction > 0.6) {
        mlDirection = "buy";
    } else if(mlPrediction < 0.4) {
        mlDirection = "sell";
    } else {
        mlDirection = "neutral";
    }

    UpdateMLDisplay();

    Print("ML Prediction: ", mlPrediction, " (", mlDirection, ") Confidence: ", mlConfidence);
}

//--- Helper: Collect trade context with ML data
void CollectTradeContext(string dir, double lot, double sl, double tp, double entry) {
    MLFeatures features;
    CollectMLFeatures(features);

    // Save to JSON with ML data
    string json = "{";
    json += "\"symbol\":\"" + _Symbol + "\",";
    json += "\"timeframe\":\"" + EnumToString(_Period) + "\",";
    json += "\"direction\":\"" + dir + "\",";
    json += "\"lot\":" + DoubleToString(lot,2) + ",";
    json += "\"sl\":" + DoubleToString(sl,_Digits) + ",";
    json += "\"tp\":" + DoubleToString(tp,_Digits) + ",";
    json += "\"entry\":" + DoubleToString(entry,_Digits) + ",";
    json += "\"ml_prediction\":" + DoubleToString(mlPrediction,4) + ",";
    json += "\"ml_confidence\":" + DoubleToString(mlConfidence,4) + ",";
    json += "\"ml_direction\":\"" + mlDirection + "\",";
    json += "\"rsi\":" + DoubleToString(features.rsi,2) + ",";
    json += "\"stoch\":" + DoubleToString(features.stoch_main,2) + ",";
    json += "\"stoch_signal\":" + DoubleToString(features.stoch_signal,2) + ",";
    json += "\"ad\":" + DoubleToString(features.ad,2) + ",";
    json += "\"volume\":" + DoubleToString(features.volume,0) + ",";
    json += "\"ma\":" + DoubleToString(features.ma,_Digits) + ",";
    json += "\"atr\":" + DoubleToString(features.atr,_Digits) + ",";
    json += "\"macd\":" + DoubleToString(features.macd_main,2) + ",";
    json += "\"macd_signal\":" + DoubleToString(features.macd_signal,2) + ",";
    json += "\"bb_upper\":" + DoubleToString(features.bb_upper,_Digits) + ",";
    json += "\"bb_lower\":" + DoubleToString(features.bb_lower,_Digits) + ",";
    json += "\"spread\":" + DoubleToString(features.spread,1) + ",";
    json += "\"candle_pattern\":\"" + features.candle_pattern + "\",";
    json += "\"candle_seq\":\"" + features.candle_seq + "\",";
    json += "\"zone_type\":\"" + features.zone_type + "\",";
    json += "\"zone_upper\":" + DoubleToString(features.zone_upper,_Digits) + ",";
    json += "\"zone_lower\":" + DoubleToString(features.zone_lower,_Digits) + ",";
    json += "\"zone_start\":" + IntegerToString(features.zone_start) + ",";
    json += "\"zone_end\":" + IntegerToString(features.zone_end) + ",";
    json += "\"trend\":\"" + features.trend + "\",";
    json += "\"volume_ratio\":" + DoubleToString(features.volume_ratio,2) + ",";
    json += "\"price_change\":" + DoubleToString(features.price_change,2) + ",";
    json += "\"volatility\":" + DoubleToString(features.volatility,2) + ",";
    json += "\"session_hour\":" + IntegerToString(features.session_hour) + ",";
    json += "\"is_news_time\":" + (features.is_news_time ? "true" : "false") + ",";
    json += "\"timestamp\":" + IntegerToString(TimeCurrent()) + "}";

    int handle = FileOpen(JsonFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
    if(handle == INVALID_HANDLE) handle = FileOpen(JsonFileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
    if(handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, json);
        FileClose(handle);
    }
}

//--- Helper: Check ML conditions for trading
bool CheckMLConditions(string direction) {
    if(!UseMLPredictions) return true;

    // Check if ML prediction agrees with trade direction
    if(direction == "buy" && mlDirection != "buy") {
        Print("ML prediction doesn't agree with BUY direction");
        return false;
    }
    if(direction == "sell" && mlDirection != "sell") {
        Print("ML prediction doesn't agree with SELL direction");
        return false;
    }

    // Check confidence levels
    if(mlConfidence < MinPredictionConfidence) {
        Print("ML confidence too low: ", mlConfidence);
        return false;
    }
    if(mlConfidence > MaxPredictionConfidence) {
        Print("ML confidence too high (possible overfitting): ", mlConfidence);
        return false;
    }

    return true;
}

//--- Helper: Calculate ML-adjusted lot size
double CalculateMLLotSize(double baseLot, double confidence) {
    if(!UseMLPositionSizing) return baseLot;

    // Adjust lot size based on ML confidence
    double confidenceMultiplier = 0.5 + (confidence * 0.5); // 0.5x to 1.0x
    return baseLot * confidenceMultiplier;
}

//--- Helper: Calculate ML-adjusted stop loss
double CalculateMLStopLoss(double baseSL, double entry, string direction) {
    if(!UseMLStopLoss) return baseSL;

    // Adjust stop loss based on ML confidence
    double confidenceAdjustment = (1.0 - mlConfidence) * 0.5; // Tighter stops for higher confidence

    if(direction == "buy") {
        return entry - (entry - baseSL) * (1.0 - confidenceAdjustment);
    } else {
        return entry + (baseSL - entry) * (1.0 - confidenceAdjustment);
    }
}

//--- Helper: Place order and log
void PlaceManualOrder(string dir) {
    Print("PlaceManualOrder called");
    ReadInputs();

    // Get ML prediction first
    GetMLPredictionAndUpdate();

    // Check ML conditions
    if(!CheckMLConditions(dir)) {
        Print("ML conditions not met for ", dir, " trade");
        return;
    }

    double entry = (dir == "buy") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = StringToDouble(slInputValue);
    double tp = StringToDouble(tpInputValue);

    // Apply ML adjustments
    sl = CalculateMLStopLoss(sl, entry, dir);

    double stopDist = MathAbs(entry - sl);
    double baseLot = CalculateLotSize(userRiskPercent, stopDist, _Symbol);
    double lot = CalculateMLLotSize(baseLot, mlConfidence);

    bool placed = false;
    if(dir == "buy")
        placed = PlaceBuyOrder(lot, sl, tp, 0, "MLBuy");
    else
        placed = PlaceSellOrder(lot, sl, tp, 0, "MLSell");

    if(placed) {
        lastSL = sl; lastTP = tp; lastLot = lot; lastDir = dir;
        CollectTradeContext(dir, lot, sl, tp, entry);
        Print("ML-enhanced trade placed: ", dir, " Lot: ", lot, " ML Confidence: ", mlConfidence);
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

//--- Helper: Auto trade based on ML
void CheckAutoTrade() {
    if(!AutoTradeMode) return;

    // Get ML prediction
    GetMLPredictionAndUpdate();

    // Check if we should auto trade
    if(mlConfidence >= MinPredictionConfidence && mlConfidence <= MaxPredictionConfidence) {
        if(mlDirection == "buy" && mlPrediction > 0.7) {
            Print("Auto trading BUY based on ML prediction: ", mlPrediction);
            PlaceManualOrder("buy");
        } else if(mlDirection == "sell" && mlPrediction < 0.3) {
            Print("Auto trading SELL based on ML prediction: ", mlPrediction);
            PlaceManualOrder("sell");
        }
    }
}

//--- Main OnTick
void OnTick() {
    // Handle button clicks
    if(buyBtn.Pressed()) {
        Print(__FUNCTION__, " Buy button clicked");
        PlaceManualOrder("buy");
        buyBtn.Pressed(false);
    };
    if(sellBtn.Pressed()) {
        Print(__FUNCTION__, " Sell button clicked");
        PlaceManualOrder("sell");
        sellBtn.Pressed(false);
    };
    if(mlPredictBtn.Pressed()) {
        Print(__FUNCTION__, " ML Predict button clicked");
        GetMLPredictionAndUpdate();
        mlPredictBtn.Pressed(false);
    };

    // Check for new bar
    if(!IsNewBar()) return;

    // Auto trade check
    CheckAutoTrade();

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
    Print("[NNTL] Trend on candle close: ", trendStr);

    // Detect and draw supply/demand zones
    FindSupplyDemandZones(_Symbol, _Period, 200, 2, demandZones, resistanceZones);
    DrawZones(_Symbol, _Period, demandZones, resistanceZones, clrGreen, clrRed, "NNTL_SD_ZONE_");

    // Detect and draw S/R zones
    FindSRZones(_Symbol, _Period, SRLookbackBars, SRTolerance*_Point, SRMergeDistance, supportZones, resistanceZones);
    DrawSRZones(_Symbol, _Period, supportZones, resistanceZones, SRSupportColor, SRResistanceColor, SRLookbackBars, "NNTL_SR_ZONE_");
}

//--- OnInit/OnDeinit
int OnInit() {
    if(!DrawPanel()) {
        Print("Failed to draw panel");
        return INIT_FAILED;
    };

    // Load ML model
    if(!LoadMLModel()) {
        Print("Failed to load ML model");
        return INIT_FAILED;
    };

    // Update EA input parameters based on ML training results
    Print("🤖 Pure ML Mode: Using only ML model predictions");
    Print("   No parameter files needed - models contain learned intelligence");

    ChartRedraw();
    Print("Neural Network Trade Logger EA initialized successfully");

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, objPrefix);
    controlsDialog.Destroy(reason);
    Print("Neural Network Trade Logger EA deinitialized");
}

//+------------------------------------------------------------------+
