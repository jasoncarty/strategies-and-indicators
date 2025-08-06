//+------------------------------------------------------------------+
//| BreakoutStrategy.mq5                                              |
//| Pure breakout strategy without ML dependencies                    |
//| Can be used standalone or with ML integration                    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Include base strategy functions
#include "../../Include/BreakoutStrategy_Base.mqh"

//--- Input parameters
input double RiskPercent = 1.0;                // Risk per trade (% of balance)
input double RiskRewardRatio = 2.0;            // Risk:Reward ratio (2:1)
input int StopLossBuffer = 20;                 // Stop loss buffer in pips
input bool UseBreakoutFilter = true;           // Use breakout filter
input int BreakoutPeriod = 20;                 // Period for breakout detection
input double BreakoutThreshold = 0.001;        // Breakout threshold

//--- Global variables (matching original strategy)
double previousDayHigh = 0.0;
double previousDayLow = 0.0;
double newDayLow = 0; // New day low established after bearish breakout
double newDayHigh = 0; // New day high established after bullish breakout
bool hasOpenPosition = false;
datetime lastDayCheck = 0;

//--- State machine variables
BREAKOUT_STATE currentState = WAITING_FOR_BREAKOUT;
datetime lastStateChange = 0;
double breakoutLevel = 0.0;
string breakoutDirection = "";
double swingPoint = 0.0; // The swing high/low that created the retest

//--- Retest tracking variables
bool bullishRetestDetected = false;
double bullishRetestLow = 999999.0;
bool bearishRetestDetected = false;
double bearishRetestHigh = 0.0;

//--- Breakout tracking variables
double lastBreakoutLevel = 0.0;
string lastBreakoutDirection = "";
int retestBar = -1;
int breakoutBar = -1;
int barsSinceBreakout = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("🚀 BreakoutStrategy initialized");
    Print("   Risk per trade: ", RiskPercent, "%");
    Print("   Risk:Reward ratio: ", RiskRewardRatio, ":1");
    Print("   Stop Loss Buffer: ", StopLossBuffer, " pips");

    // Update previous day levels
    UpdatePreviousDayLevels();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("🛑 BreakoutStrategy deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for new day
    if(TimeCurrent() - lastDayCheck > 3600) { // Check every hour
        UpdatePreviousDayLevels();
        lastDayCheck = TimeCurrent();
    }

    // Process the state machine
    ProcessBreakoutStateMachine();

    // Check for trade signals
    CheckForTradeSignals();
}

//+------------------------------------------------------------------+
//| Check for trade signals from state machine                       |
//+------------------------------------------------------------------+
void CheckForTradeSignals() {
    if(hasOpenPosition) return; // Don't open new positions if we have one

    // Check if we just completed a bullish confirmation
    if(currentState == WAITING_FOR_BREAKOUT && breakoutDirection == "bullish" && bullishRetestDetected) {
        Print("🔄 Bullish trade signal detected - placing buy order");
        PlaceBuyOrder();
        ResetBreakoutStateVariables();
        bullishRetestDetected = false;
    }

    // Check if we just completed a bearish confirmation
    if(currentState == WAITING_FOR_BREAKOUT && breakoutDirection == "bearish" && bearishRetestDetected) {
        Print("🔄 Bearish trade signal detected - placing sell order");
        PlaceSellOrder();
        ResetBreakoutStateVariables();
        bearishRetestDetected = false;
    }
}

//+------------------------------------------------------------------+
//| Place buy order with proper SL/TP calculation                   |
//+------------------------------------------------------------------+
void PlaceBuyOrder() {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calculate stop loss based on new day low (original strategy logic)
    double stopLoss = CalculateBullishStopLoss(StopLossBuffer);

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "buy");

    // Calculate lot size based on risk percentage
    double stopDistance = entry - stopLoss;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = entry;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 3;
    request.comment = "BreakoutStrategy";

    bool success = OrderSend(request, result);

    if(success && result.retcode == TRADE_RETCODE_DONE) {
        Print("✅ Buy order placed successfully");
        Print("   Ticket: ", result.order);
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));
        hasOpenPosition = true;
    } else {
        Print("❌ Buy order failed: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| Place sell order with proper SL/TP calculation                  |
//+------------------------------------------------------------------+
void PlaceSellOrder() {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calculate stop loss based on new day high (original strategy logic)
    double stopLoss = CalculateBearishStopLoss(StopLossBuffer);

    // Calculate take profit based on risk:reward ratio
    double takeProfit = CalculateTakeProfit(entry, stopLoss, RiskRewardRatio, "sell");

    // Calculate lot size based on risk percentage
    double stopDistance = stopLoss - entry;
    double lotSize = CalculateLotSize(RiskPercent, stopDistance);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = entry;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 3;
    request.comment = "BreakoutStrategy";

    bool success = OrderSend(request, result);

    if(success && result.retcode == TRADE_RETCODE_DONE) {
        Print("✅ Sell order placed successfully");
        Print("   Ticket: ", result.order);
        Print("   Entry: ", DoubleToString(entry, _Digits));
        Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
        Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));
        Print("   Lot Size: ", DoubleToString(lotSize, 2));
        Print("   Risk: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0), 2));
        hasOpenPosition = true;
    } else {
        Print("❌ Sell order failed: ", result.retcode);
    }
}


