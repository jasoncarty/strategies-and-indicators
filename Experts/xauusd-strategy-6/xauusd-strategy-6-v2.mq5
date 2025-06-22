//+------------------------------------------------------------------+
//|                                         xauusd-strategy-6-v2.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD RSI Crossover Strategy V2                   |
//| Description:                                                       |
//|   An advanced trading strategy for XAUUSD (Gold) that uses RSI     |
//|   crossovers with its smoothed version for trade signals. This     |
//|   version includes trend filtering and news protection.            |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: RSI crosses above its smoothed version with upward        |
//|          momentum                                                  |
//|   - SELL: RSI crosses below its smoothed version with downward     |
//|          momentum                                                  |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Fixed take profit at 2:1 risk-reward ratio                    |
//|   - Trailing stop that moves when price moves in favor by 20%      |
//|     of initial stop distance                                       |
//|                                                                    |
//| Risk Management:                                                   |
//|   - ATR-based stop loss, capped at 1% account risk                |
//|   - Position sizing automatically adjusted to maintain risk        |
//|   - Trailing stop to protect profits                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input group "RSI Settings"
input int    RSI_Period = 14;         // RSI Period
input int    RSI_SmoothPeriod = 14;    // Period for smoothing RSI
input double MinRsiSpread = 2.0;        // Minimum spread between RSI and its SMA for entry

input group "Trend Filter"
input bool   UseTrendFilter = true;         // Use MA trend filter
input int    FastMA = 20;                   // Fast Moving Average Period
input int    SlowMA = 50;                   // Slow Moving Average Period

input group "RSI Zone Filter"
input bool   UseRsiZoneFilter = true;       // Use RSI zone filter for crossovers
input double BuyZoneThreshold = 50.0;       // RSI threshold for buy signals
input double SellZoneThreshold = 50.0;      // RSI threshold for sell signals

input group "RSI Trend Filter"
input bool   UseRsiTrendFilter = true;      // Use RSI trend filter
input bool   AllowCounterTrendOB = true;    // Allow counter-trend trades in overbought/oversold
input double OversoldLevel = 30.0;          // RSI oversold level
input double OverboughtLevel = 70.0;        // RSI overbought level

input group "Risk Management"
input double RiskPercent = 1.0;       // Risk percentage per trade
input int    ATR_Period = 14;         // ATR Period for Stop Loss calculation
input double ATR_Multiplier = 2.0;    // ATR Multiplier for Stop Loss
input double RR_Ratio = 2.0;          // Risk:Reward ratio for take profit
input bool   UseTrailingStop = true;  // Use trailing stop
input double Trail_SL_Percent = 20.0;  // Trail SL percent of initial SL distance

input group "News Filter"
input bool   UseNewsFilter = true;    // Use news filter
input int    NewsMinutesBefore = 60;  // Minutes before news to stop trading
input int    NewsMinutesAfter = 60;   // Minutes after news to resume trading

input group "RSI Momentum Settings"
input int    WaitBarsAfterCross = 3;        // Bars to wait after crossover
input int    MomentumCheckBars = 2;         // Bars to check for momentum continuation
input int    PreCrossoverBars = 2;          // Bars to check before crossover
input double MinSmaSlope = 0.1;             // Minimum SMA slope for trend confirmation

input group "RSI Exit Settings"
input int    ExitConfirmationBars = 2;      // Bars to confirm exit signal
input double ExitMinSpreadPercent = 0.3;    // Minimum spread for exit signal

// Global variables
int rsiHandle;
int atrHandle;
int smaHandle;
int fastMAHandle;
int slowMAHandle;
double rsiBuffer[];
double atrBuffer[];
double smoothRsiBuffer[];
double fastMABuffer[];
double slowMABuffer[];
datetime lastBarTime = 0;
bool isInTrade = false;
ENUM_POSITION_TYPE currentPositionType = (ENUM_POSITION_TYPE)-1;  // -1 represents no position
double initialStopLoss = 0;           // Store initial stop loss for trailing calculation
double rsiValues[];
double smoothRsiValues[];
double tempBuffer[];  // Temporary buffer for single value copies

// Signal tracking variables
bool pendingBuySignal = false;
bool pendingSellSignal = false;
datetime signalBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI
    rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE)
    {
        Print("Error creating RSI indicator");
        return INIT_FAILED;
    }

    // Initialize ATR
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Error creating ATR indicator");
        return INIT_FAILED;
    }

    // Initialize RSI SMA
    smaHandle = iMA(_Symbol, PERIOD_CURRENT, RSI_SmoothPeriod, 0, MODE_SMA, rsiHandle);
    if(smaHandle == INVALID_HANDLE)
    {
        Print("Error creating SMA indicator");
        return INIT_FAILED;
    }

    // Initialize Fast MA
    fastMAHandle = iMA(_Symbol, PERIOD_CURRENT, FastMA, 0, MODE_SMA, PRICE_CLOSE);
    if(fastMAHandle == INVALID_HANDLE)
    {
        Print("Error creating Fast MA indicator");
        return INIT_FAILED;
    }

    // Initialize Slow MA
    slowMAHandle = iMA(_Symbol, PERIOD_CURRENT, SlowMA, 0, MODE_SMA, PRICE_CLOSE);
    if(slowMAHandle == INVALID_HANDLE)
    {
        Print("Error creating Slow MA indicator");
        return INIT_FAILED;
    }

    // Initialize arrays
    ArraySetAsSeries(rsiBuffer, true);
    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(smoothRsiBuffer, true);
    ArraySetAsSeries(fastMABuffer, true);
    ArraySetAsSeries(slowMABuffer, true);
    ArraySetAsSeries(rsiValues, true);
    ArraySetAsSeries(smoothRsiValues, true);
    ArraySetAsSeries(tempBuffer, true);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    if(smaHandle != INVALID_HANDLE)
        IndicatorRelease(smaHandle);
    if(fastMAHandle != INVALID_HANDLE)
        IndicatorRelease(fastMAHandle);
    if(slowMAHandle != INVALID_HANDLE)
        IndicatorRelease(slowMAHandle);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPoints)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);

    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / tickSize;

    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    // Calculate lot size based on risk
    double lotSize = NormalizeDouble(riskAmount / (stopLossPoints * pointValue), 2);

    // Adjust lot size to conform to broker's requirements
    lotSize = MathFloor(lotSize / lotStep) * lotStep;

    // Ensure lot size is within allowed range
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate stop loss based on ATR and account balance limit         |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1)
    {
        Print("Error copying ATR buffer!");
        return 0;
    }

    double atrValue = atrBuffer[0];
    double atrStopDistance = atrValue * ATR_Multiplier;

    // Calculate maximum stop loss based on 1% of account balance
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double maxRiskAmount = accountBalance * (RiskPercent / 100.0);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / tickSize;

    // Calculate maximum stop loss points based on risk limit
    double maxStopPoints = maxRiskAmount / (SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) * pointValue);

    // Use the smaller of ATR-based stop or maximum allowed stop
    double stopDistance = MathMin(atrStopDistance, maxStopPoints);

    if(orderType == ORDER_TYPE_BUY)
        return entryPrice - stopDistance;
    else
        return entryPrice + stopDistance;
}

//+------------------------------------------------------------------+
//| Check for RSI/SMA crossover                                        |
//+------------------------------------------------------------------+
bool HasCrossover(bool lookingForBullish)
{
    // Check for crossover within last 3 bars
    for(int i = 2; i > 0; i--)
    {
        if(lookingForBullish)
        {
            // Looking for RSI crossing above SMA (bullish)
            if(rsiValues[i] < smoothRsiValues[i] && rsiValues[i-1] > smoothRsiValues[i-1])
                return true;
        }
        else
        {
            // Looking for RSI crossing below SMA (bearish)
            if(rsiValues[i] > smoothRsiValues[i] && rsiValues[i-1] < smoothRsiValues[i-1])
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if we should update trailing stop                           |
//+------------------------------------------------------------------+
void CheckTrailingStop()
{
    if(!isInTrade || !UseTrailingStop || Trail_SL_Percent <= 0)
        return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        double currentSL = PositionGetDouble(POSITION_SL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Calculate points from open to initial SL
        double totalSLPoints = MathAbs(openPrice - initialStopLoss);
        double trailPoint = totalSLPoints * (Trail_SL_Percent / 100.0);

        // Skip if trail point is too small
        if(trailPoint < SymbolInfoDouble(_Symbol, SYMBOL_POINT))
            return;

        // For buy positions
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            // Calculate the minimum price move needed before trailing
            double minPriceMove = openPrice + trailPoint;

            // Only start trailing if price has moved enough
            if(currentPrice >= minPriceMove)
            {
                // New SL will be the current price minus the trail distance
                double newSL = currentPrice - trailPoint;

                // Only modify if new SL is higher than current SL
                if(newSL > currentSL)
                {
                    ModifyPosition(newSL);
                    Print("Updated Buy Stop Loss: ", newSL,
                          " Current Price: ", currentPrice,
                          " Trail Distance: ", trailPoint);
                }
            }
        }
        // For sell positions
        else
        {
            // Calculate the minimum price move needed before trailing
            double minPriceMove = openPrice - trailPoint;

            // Only start trailing if price has moved enough
            if(currentPrice <= minPriceMove)
            {
                // New SL will be the current price plus the trail distance
                double newSL = currentPrice + trailPoint;

                // Only modify if new SL is lower than current SL
                if(newSL < currentSL)
                {
                    ModifyPosition(newSL);
                    Print("Updated Sell Stop Loss: ", newSL,
                          " Current Price: ", currentPrice,
                          " Trail Distance: ", trailPoint);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify position's stop loss                                       |
//+------------------------------------------------------------------+
bool ModifyPosition(double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP);
    request.position = PositionGetTicket(0);

    return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
    // Copy indicator values
    if(CopyBuffer(rsiHandle, 0, 0, 3, rsiValues) != 3)
    {
        Print("Error copying RSI values");
        return;
    }

    if(CopyBuffer(smaHandle, 0, 0, 3, smoothRsiValues) != 3)
    {
        Print("Error copying SMA values");
        return;
    }

    if(CopyBuffer(fastMAHandle, 0, 0, 3, fastMABuffer) != 3)
    {
        Print("Error copying Fast MA values");
        return;
    }

    if(CopyBuffer(slowMAHandle, 0, 0, 3, slowMABuffer) != 3)
    {
        Print("Error copying Slow MA values");
        return;
    }
}

void OnTick()
{
    // Only process on new candle
    if(!IsNewBar())
        return;

    Print("=============== NEW BAR CHECK ===============");
    Print("DEBUG: Current Time:", TimeToString(TimeCurrent()));

    // Check if we actually have an open position
    bool hasOpenPosition = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            hasOpenPosition = true;
            break;
        }
    }

    // Reset isInTrade if we don't actually have a position
    if(isInTrade && !hasOpenPosition)
    {
        Print("DEBUG: Resetting isInTrade flag - No open positions found");
        isInTrade = false;
        currentPositionType = (ENUM_POSITION_TYPE)-1;
    }

    Print("DEBUG: isInTrade:", isInTrade);

    // Update indicators
    UpdateIndicators();

    // Print current values
    Print("Current Values - ",
          "RSI[0]:", DoubleToString(rsiValues[0], 5), " ",
          "RSI[1]:", DoubleToString(rsiValues[1], 5), " ",
          "RSI[2]:", DoubleToString(rsiValues[2], 5), " ",
          "SMA[0]:", DoubleToString(smoothRsiValues[0], 5), " ",
          "SMA[1]:", DoubleToString(smoothRsiValues[1], 5), " ",
          "SMA[2]:", DoubleToString(smoothRsiValues[2], 5), " ",
          "FastMA:", DoubleToString(fastMABuffer[0], 5), " ",
          "SlowMA:", DoubleToString(slowMABuffer[0], 5));

    // Check if we're in a trade
    if(isInTrade)
    {
        Print("DEBUG: In trade - checking exit conditions");
        CheckExitConditions();
        Print("=============== END BAR CHECK ===============");
        return;
    }

    // Check for news events
    if(IsNewsTime())
    {
        Print("DEBUG: No trading - Within news event window");
        Print("=============== END BAR CHECK ===============");
        return;
    }

    Print("DEBUG: Not in trade - checking entry conditions");

    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Check for initial signals
    if(!pendingBuySignal && !pendingSellSignal)
    {
        // Check for buy entry
        if(IsValidBuyEntry())
        {
            Print("DEBUG: Valid buy signal detected - waiting for next candle close for confirmation");
            pendingBuySignal = true;
            signalBarTime = currentBarTime;
            return;
        }
        // Check for sell entry
        else if(IsValidSellEntry())
        {
            Print("DEBUG: Valid sell signal detected - waiting for next candle close for confirmation");
            pendingSellSignal = true;
            signalBarTime = currentBarTime;
            return;
        }
    }
    // Handle pending signals - only check on candle close
    else
    {
        // Make sure we're on the next candle after the signal
        if(currentBarTime > signalBarTime)
        {
            // Get the previous (closed) candle's values
            double closedCandleRSI = rsiValues[1];  // [1] is the previous closed candle
            double closedCandleSMA = smoothRsiValues[1];
            double priorCandleRSI = rsiValues[2];   // [2] is the candle before that

            // Calculate spread using closed candle values
            double currentSpread = MathAbs(closedCandleRSI - closedCandleSMA);
            bool hasEnoughSpread = currentSpread >= MinRsiSpread;

            if(pendingBuySignal)
            {
                // Check RSI momentum using closed candle values
                bool hasUpwardMomentum = closedCandleRSI > priorCandleRSI;

                if(hasEnoughSpread && closedCandleRSI > closedCandleSMA && hasUpwardMomentum)
                {
                    Print("DEBUG: Buy signal confirmed on candle close - executing trade");
                    Print("DEBUG: Confirmation details - Spread:", DoubleToString(currentSpread, 5),
                          " RSI above SMA:", (closedCandleRSI > closedCandleSMA),
                          " RSI Momentum:", DoubleToString(closedCandleRSI - priorCandleRSI, 5));

                    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double stopLoss = CalculateStopLoss(ORDER_TYPE_BUY, ask);

                    if(stopLoss == 0)
                    {
                        Print("DEBUG: Error calculating stop loss");
                    }
                    else
                    {
                        double stopLossPoints = MathAbs(ask - stopLoss);
                        double lotSize = CalculateLotSize(stopLossPoints);

                        if(OrderOpen(ORDER_TYPE_BUY, ask, lotSize, stopLoss))
                        {
                            isInTrade = true;
                            currentPositionType = POSITION_TYPE_BUY;
                            initialStopLoss = stopLoss;
                            Print("DEBUG: Successfully opened buy position");
                        }
                        else
                        {
                            Print("DEBUG: Failed to open buy position");
                        }
                    }
                }
                else
                {
                    Print("DEBUG: Buy signal not confirmed on candle close - spread:", DoubleToString(currentSpread, 5),
                          " RSI above SMA:", (closedCandleRSI > closedCandleSMA),
                          " RSI Momentum:", DoubleToString(closedCandleRSI - priorCandleRSI, 5));
                }
                pendingBuySignal = false;
            }
            else if(pendingSellSignal)
            {
                // Check RSI momentum using closed candle values
                bool hasDownwardMomentum = closedCandleRSI < priorCandleRSI;

                if(hasEnoughSpread && closedCandleRSI < closedCandleSMA && hasDownwardMomentum)
                {
                    Print("DEBUG: Sell signal confirmed on candle close - executing trade");
                    Print("DEBUG: Confirmation details - Spread:", DoubleToString(currentSpread, 5),
                          " RSI below SMA:", (closedCandleRSI < closedCandleSMA),
                          " RSI Momentum:", DoubleToString(priorCandleRSI - closedCandleRSI, 5));

                    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    double stopLoss = CalculateStopLoss(ORDER_TYPE_SELL, bid);

                    if(stopLoss == 0)
                    {
                        Print("DEBUG: Error calculating stop loss");
                    }
                    else
                    {
                        double stopLossPoints = MathAbs(stopLoss - bid);
                        double lotSize = CalculateLotSize(stopLossPoints);

                        if(OrderOpen(ORDER_TYPE_SELL, bid, lotSize, stopLoss))
                        {
                            isInTrade = true;
                            currentPositionType = POSITION_TYPE_SELL;
                            initialStopLoss = stopLoss;
                            Print("DEBUG: Successfully opened sell position");
                        }
                        else
                        {
                            Print("DEBUG: Failed to open sell position");
                        }
                    }
                }
                else
                {
                    Print("DEBUG: Sell signal not confirmed on candle close - spread:", DoubleToString(currentSpread, 5),
                          " RSI below SMA:", (closedCandleRSI < closedCandleSMA),
                          " RSI Momentum:", DoubleToString(priorCandleRSI - closedCandleRSI, 5));
                }
                pendingSellSignal = false;
            }
        }
    }

    Print("=============== END BAR CHECK ===============");
}

//+------------------------------------------------------------------+
//| Open a new order                                                  |
//+------------------------------------------------------------------+
bool OrderOpen(ENUM_ORDER_TYPE orderType, double price, double lots, double stopLoss)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    // Calculate take profit based on stop loss distance
    double takeProfit = CalculateTakeProfit(orderType, price, stopLoss);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = orderType;
    request.price = price;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 10;
    request.magic = 123456;

    // Get the filling mode of the symbol
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

    // If FOK is supported
    if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
    {
        request.type_filling = ORDER_FILLING_FOK;
    }
    // If IOC is supported
    else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
    {
        request.type_filling = ORDER_FILLING_IOC;
    }
    // If neither is supported, try return filling
    else
    {
        request.type_filling = ORDER_FILLING_RETURN;
    }

    bool success = OrderSend(request, result);

    if(!success)
    {
        Print("OrderSend failed with error: ", GetLastError());
        Print("Attempted to open ", orderType == ORDER_TYPE_BUY ? "Buy" : "Sell",
              " Price: ", price,
              " Lots: ", lots,
              " StopLoss: ", stopLoss,
              " TakeProfit: ", takeProfit,
              " Filling: ", request.type_filling);
    }
    else
    {
        Print("Order opened successfully - ", orderType == ORDER_TYPE_BUY ? "Buy" : "Sell",
              " Price: ", price,
              " Lots: ", lots,
              " StopLoss: ", stopLoss,
              " TakeProfit: ", takeProfit,
              " Risk/Reward: 1:", RR_Ratio);
    }

    return success;
}

//+------------------------------------------------------------------+
//| Close all open positions                                          |
//+------------------------------------------------------------------+
bool CloseAllPositions()
{
    int total = PositionsTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;

        if(!PositionSelectByTicket(ticket)) continue;

        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        MqlTradeRequest request = {};
        MqlTradeResult result = {};

        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.volume = PositionGetDouble(POSITION_VOLUME);
        request.deviation = 10;
        request.magic = 123456;

        // Get the filling mode of the symbol
        uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

        // If FOK is supported
        if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
        {
            request.type_filling = ORDER_FILLING_FOK;
        }
        // If IOC is supported
        else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
        {
            request.type_filling = ORDER_FILLING_IOC;
        }
        // If neither is supported, try return filling
        else
        {
            request.type_filling = ORDER_FILLING_RETURN;
        }

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            request.type = ORDER_TYPE_SELL;
        }
        else
        {
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.type = ORDER_TYPE_BUY;
        }

        bool success = OrderSend(request, result);

        if(!success)
        {
            Print("Close position failed with error: ", GetLastError());
            Print("Attempted to close position ", ticket,
                  " Price: ", request.price,
                  " Lots: ", request.volume,
                  " Filling: ", request.type_filling);
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculate take profit based on stop loss distance and RR ratio    |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss)
{
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double tpDistance = stopDistance * RR_Ratio;

    if(orderType == ORDER_TYPE_BUY)
        return entryPrice + tpDistance;
    else
        return entryPrice - tpDistance;
}

//+------------------------------------------------------------------+
//| Check if we're in a high-impact news window                        |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
    if(!UseNewsFilter) return false;

    MqlCalendarValue values[];
    datetime from = TimeCurrent() - NewsMinutesBefore * 60;
    datetime to = TimeCurrent() + NewsMinutesAfter * 60;

    if(CalendarValueHistory(values, from, to, "USD"))
    {
        for(int i = 0; i < ArraySize(values); i++)
        {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
                // Check if it's a high-impact event
                if(event.importance == CALENDAR_IMPORTANCE_HIGH)
                {
                    Print("High impact news event found: ", event.name,
                          " Time: ", TimeToString(values[i].time));
                    return true;
                }
            }
        }
    }

    return false;
}


//+------------------------------------------------------------------+
//| Check if RSI momentum continues after crossover                  |
//+------------------------------------------------------------------+
bool IsValidMomentumContinuation(bool isBuySignal)
{
    int requiredBars = MomentumCheckBars;

    if(ArraySize(rsiValues) < requiredBars || ArraySize(smoothRsiValues) < requiredBars)
        return false;

    if(isBuySignal)
    {
        // For buy signals, check if RSI is consistently above SMA
        for(int i = 0; i < requiredBars; i++)
        {
            if(rsiValues[i] <= smoothRsiValues[i])
                return false;
        }
    }
    else
    {
        // For sell signals, check if RSI is consistently below SMA
        for(int i = 0; i < requiredBars; i++)
        {
            if(rsiValues[i] >= smoothRsiValues[i])
                return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Check if we have enough bars after crossover                      |
//+------------------------------------------------------------------+
bool HasEnoughBarsAfterCross(bool isBuySignal, int waitBars)
{
    for(int i = 1; i < waitBars + 1 && i < ArraySize(rsiValues); i++)
    {
        if(isBuySignal)
        {
            // For buy signals, check if RSI crossed below SMA recently
            if(rsiValues[i] < smoothRsiValues[i] && rsiValues[i-1] >= smoothRsiValues[i-1])
                return false;
        }
        else
        {
            // For sell signals, check if RSI crossed above SMA recently
            if(rsiValues[i] > smoothRsiValues[i] && rsiValues[i-1] <= smoothRsiValues[i-1])
                return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check if we have a valid exit signal                              |
//+------------------------------------------------------------------+
bool IsValidExitSignal(const double &rsiValues[], const double &smoothRsiValues[], bool isLongPosition)
{
    // For long positions, we're looking for a valid sell signal
    if(isLongPosition)
    {
        // First check if RSI is below SMA
        if(rsiValues[0] >= smoothRsiValues[0])
            return false;

        // Calculate spread
        double currentSpread = smoothRsiValues[0] - rsiValues[0];

        // Check minimum spread
        if(currentSpread < ExitMinSpreadPercent)
            return false;

        // Check if RSI is moving down consistently
        bool isMovingDown = true;
        for(int i = 0; i < ExitConfirmationBars-1; i++)
        {
            if(rsiValues[i] >= rsiValues[i+1])
            {
                isMovingDown = false;
                break;
            }
        }

        // Check if spread is widening
        bool isSpreadWidening = (smoothRsiValues[0] - rsiValues[0]) >
                              (smoothRsiValues[1] - rsiValues[1]);

        return isMovingDown && isSpreadWidening;
    }
    // For short positions, we're looking for a valid buy signal
    else
    {
        // First check if RSI is above SMA
        if(rsiValues[0] <= smoothRsiValues[0])
            return false;

        // Calculate spread
        double currentSpread = rsiValues[0] - smoothRsiValues[0];

        // Check minimum spread
        if(currentSpread < ExitMinSpreadPercent)
            return false;

        // Check if RSI is moving up consistently
        bool isMovingUp = true;
        for(int i = 0; i < ExitConfirmationBars-1; i++)
        {
            if(rsiValues[i] <= rsiValues[i+1])
            {
                isMovingUp = false;
                break;
            }
        }

        // Check if spread is widening
        bool isSpreadWidening = (rsiValues[0] - smoothRsiValues[0]) >
                              (rsiValues[1] - smoothRsiValues[1]);

        return isMovingUp && isSpreadWidening;
    }
}

//+------------------------------------------------------------------+
//| Add this new function to check pre-crossover momentum              |
//+------------------------------------------------------------------+
bool HasValidPreCrossoverMomentum(const double &rsiValues[], const double &smoothRsiValues[], bool isBuy, int lookback)
{
    int consistentBars = 0;

    // For buy signals
    if(isBuy)
    {
        // Check if RSI was predominantly moving up before crossover
        for(int i = 1; i < lookback; i++)
        {
            if(rsiValues[i] < rsiValues[i+1])
                consistentBars++;
        }
    }
    // For sell signals
    else
    {
        // Check if RSI was predominantly moving down before crossover
        for(int i = 1; i < lookback; i++)
        {
            if(rsiValues[i] > rsiValues[i+1])
                consistentBars++;
        }
    }

    // Return true if at least half of the bars show momentum in the right direction
    return consistentBars >= (lookback - 1) / 2;
}

//+------------------------------------------------------------------+
//| Add function to check SMA slope                                 |
//+------------------------------------------------------------------+
bool HasValidSmaSlope(const double &smoothRsiValues[], bool isBuy)
{
    // Calculate the slope over the last 3 bars
    double slope = (smoothRsiValues[0] - smoothRsiValues[3]) / 3.0;

    if(isBuy)
        return slope >= -MinSmaSlope;  // SMA should be flat or rising for buys
    else
        return slope <= MinSmaSlope;   // SMA should be flat or falling for sells
}

//+------------------------------------------------------------------+
//| Returns true if current bar is new                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

// Function to check if RSI SMA is trending up
bool IsRsiSmaTrendingUp()
{
    // Check if current SMA is higher than previous
    return smoothRsiValues[0] > smoothRsiValues[1];
}

// Function to check if RSI SMA is trending down
bool IsRsiSmaTrendingDown()
{
    // Check if current SMA is lower than previous
    return smoothRsiValues[0] < smoothRsiValues[1];
}

bool IsValidBuyEntry()
{
    Print("=================== CHECKING BUY ENTRY ===================");

    // Check if we have enough data
    if(ArraySize(rsiValues) < 3 || ArraySize(smoothRsiValues) < 3 ||
       (UseTrendFilter && (ArraySize(fastMABuffer) < 3 || ArraySize(slowMABuffer) < 3)))
    {
        Print("ERROR: Not enough data for entry check");
        return false;
    }

    // Get current and previous values
    double rsi_0 = rsiValues[0];
    double rsi_1 = rsiValues[1];
    double rsi_2 = rsiValues[2];
    double sma_0 = smoothRsiValues[0];
    double sma_1 = smoothRsiValues[1];
    double sma_2 = smoothRsiValues[2];

    string debugValues = StringFormat(
        "RSI[0]:%s RSI[1]:%s RSI[2]:%s SMA[0]:%s SMA[1]:%s SMA[2]:%s",
        DoubleToString(rsi_0, 5),
        DoubleToString(rsi_1, 5),
        DoubleToString(rsi_2, 5),
        DoubleToString(sma_0, 5),
        DoubleToString(sma_1, 5),
        DoubleToString(sma_2, 5)
    );

    // Add MA values to debug if trend filter is enabled
    if(UseTrendFilter)
    {
        double fastMA = fastMABuffer[0];
        double slowMA = slowMABuffer[0];
        debugValues += StringFormat(
            " FastMA:%s SlowMA:%s",
            DoubleToString(fastMA, 5),
            DoubleToString(slowMA, 5)
        );
    }

    Print("DEBUG: Values loaded - ", debugValues);

    // Check if RSI has crossed above SMA
    bool hasCrossedAbove = (rsi_2 <= sma_2) && (rsi_1 > sma_1);
    bool isAboveSMA = rsi_0 > sma_0;

    // Check if crossover occurred in favorable zone
    bool crossoverInFavorableZone = true;  // Default to true if zone filter is disabled
    if(UseRsiZoneFilter && hasCrossedAbove)
    {
        // We use sma_1 as that's the smooth RSI value at crossover time
        crossoverInFavorableZone = sma_1 < BuyZoneThreshold;
        Print("DEBUG: Buy crossover zone check - Smooth RSI at crossover:", sma_1,
              " In favorable zone (<", BuyZoneThreshold, "):", crossoverInFavorableZone);
    }

    // Check RSI trend direction if enabled
    bool validRsiTrend = true;  // Default to true if RSI trend filter is disabled
    bool isOversold = rsi_0 < OversoldLevel;
    if(UseRsiTrendFilter)
    {
        bool isTrendingDown = IsRsiSmaTrendingDown();
        validRsiTrend = !isTrendingDown || (AllowCounterTrendOB && isOversold);
        Print("DEBUG: RSI Trend Check - Trending Down:", isTrendingDown,
              " Oversold:", isOversold,
              " Allow Counter-Trend:", AllowCounterTrendOB,
              " Valid RSI Trend:", validRsiTrend);
    }

    // Check MA trend if enabled
    bool validMATrend = true;  // Default to true if trend filter is disabled
    if(UseTrendFilter)
    {
        validMATrend = fastMABuffer[0] > slowMABuffer[0];
        Print("DEBUG: MA Trend Check - FastMA:", fastMABuffer[0], " SlowMA:", slowMABuffer[0], " Valid for Buy:", validMATrend);
    }

    Print("DEBUG: Buy Signal Analysis - ",
          "Crossed Above:", hasCrossedAbove, " ",
          "Above SMA:", isAboveSMA, " ",
          "Zone Filter Enabled:", UseRsiZoneFilter, " ",
          "Crossover In Favorable Zone:", crossoverInFavorableZone, " ",
          "RSI Trend Filter Enabled:", UseRsiTrendFilter, " ",
          "Valid RSI Trend:", validRsiTrend, " ",
          "Oversold:", isOversold, " ",
          "Valid MA Trend:", validMATrend);

    return hasCrossedAbove && isAboveSMA && crossoverInFavorableZone && validRsiTrend && validMATrend;
}

bool IsValidSellEntry()
{
    Print("=================== CHECKING SELL ENTRY ===================");

    // Check if we have enough data
    if(ArraySize(rsiValues) < 3 || ArraySize(smoothRsiValues) < 3 ||
       (UseTrendFilter && (ArraySize(fastMABuffer) < 3 || ArraySize(slowMABuffer) < 3)))
    {
        Print("ERROR: Not enough data for entry check");
        return false;
    }

    // Get current and previous values
    double rsi_0 = rsiValues[0];
    double rsi_1 = rsiValues[1];
    double rsi_2 = rsiValues[2];
    double sma_0 = smoothRsiValues[0];
    double sma_1 = smoothRsiValues[1];
    double sma_2 = smoothRsiValues[2];

    string debugValues = StringFormat(
        "RSI[0]:%s RSI[1]:%s RSI[2]:%s SMA[0]:%s SMA[1]:%s SMA[2]:%s",
        DoubleToString(rsi_0, 5),
        DoubleToString(rsi_1, 5),
        DoubleToString(rsi_2, 5),
        DoubleToString(sma_0, 5),
        DoubleToString(sma_1, 5),
        DoubleToString(sma_2, 5)
    );

    // Add MA values to debug if trend filter is enabled
    if(UseTrendFilter)
    {
        double fastMA = fastMABuffer[0];
        double slowMA = slowMABuffer[0];
        debugValues += StringFormat(
            " FastMA:%s SlowMA:%s",
            DoubleToString(fastMA, 5),
            DoubleToString(slowMA, 5)
        );
    }

    Print("DEBUG: Values loaded - ", debugValues);

    // Check if RSI has crossed below SMA
    bool hasCrossedBelow = (rsi_2 >= sma_2) && (rsi_1 < sma_1);
    bool isBelowSMA = rsi_0 < sma_0;

    // Check if crossover occurred in favorable zone
    bool crossoverInFavorableZone = true;  // Default to true if zone filter is disabled
    if(UseRsiZoneFilter && hasCrossedBelow)
    {
        // We use sma_1 as that's the smooth RSI value at crossover time
        crossoverInFavorableZone = sma_1 > SellZoneThreshold;
        Print("DEBUG: Sell crossover zone check - Smooth RSI at crossover:", sma_1,
              " In favorable zone (>", SellZoneThreshold, "):", crossoverInFavorableZone);
    }

    // Check RSI trend direction if enabled
    bool validRsiTrend = true;  // Default to true if RSI trend filter is disabled
    bool isOverbought = rsi_0 > OverboughtLevel;
    if(UseRsiTrendFilter)
    {
        bool isTrendingUp = IsRsiSmaTrendingUp();
        validRsiTrend = !isTrendingUp || (AllowCounterTrendOB && isOverbought);
        Print("DEBUG: RSI Trend Check - Trending Up:", isTrendingUp,
              " Overbought:", isOverbought,
              " Allow Counter-Trend:", AllowCounterTrendOB,
              " Valid RSI Trend:", validRsiTrend);
    }

    // Check MA trend if enabled
    bool validMATrend = true;  // Default to true if trend filter is disabled
    if(UseTrendFilter)
    {
        validMATrend = fastMABuffer[0] < slowMABuffer[0];
        Print("DEBUG: MA Trend Check - FastMA:", fastMABuffer[0], " SlowMA:", slowMABuffer[0], " Valid for Sell:", validMATrend);
    }

    Print("DEBUG: Sell Signal Analysis - ",
          "Crossed Below:", hasCrossedBelow, " ",
          "Below SMA:", isBelowSMA, " ",
          "Zone Filter Enabled:", UseRsiZoneFilter, " ",
          "Crossover In Favorable Zone:", crossoverInFavorableZone, " ",
          "RSI Trend Filter Enabled:", UseRsiTrendFilter, " ",
          "Valid RSI Trend:", validRsiTrend, " ",
          "Overbought:", isOverbought, " ",
          "Valid MA Trend:", validMATrend);

    return hasCrossedBelow && isBelowSMA && crossoverInFavorableZone && validRsiTrend && validMATrend;
}

void CheckExitConditions()
{
    // Check trailing stop first
    CheckTrailingStop();

    // Get current and previous values
    double rsi_0 = rsiValues[0];
    double rsi_1 = rsiValues[1];
    double rsi_2 = rsiValues[2];
    double sma_0 = smoothRsiValues[0];
    double sma_1 = smoothRsiValues[1];
    double sma_2 = smoothRsiValues[2];

    Print("=== EXIT CHECK ===");
    Print("Position:", (currentPositionType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
    Print("Current Bar - RSI:", rsi_0, " SMA:", sma_0);
    Print("Previous Bar - RSI:", rsi_1, " SMA:", sma_1);

    // For buy positions, look for bearish crossover (false)
    // For sell positions, look for bullish crossover (true)
    bool shouldExit = HasCrossover(currentPositionType == POSITION_TYPE_SELL);

    Print("Exit Signal detected:", shouldExit);

    if(shouldExit)
    {
        Print("Attempting to close position");
        if(CloseAllPositions())
        {
            Print("Position closed successfully");
            isInTrade = false;
            currentPositionType = (ENUM_POSITION_TYPE)-1;
        }
        else
        {
            Print("Failed to close position");
        }
    }
}
