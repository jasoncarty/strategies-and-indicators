//+------------------------------------------------------------------+
//|                                         xauusd-strategy-6-v1.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD RSI Level Strategy V1                       |
//| Description:                                                       |
//|   A trading strategy for XAUUSD (Gold) that uses RSI levels and    |
//|   ATR for trade signals. This version focuses on oversold and      |
//|   overbought conditions with ATR-based volatility filtering.       |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: RSI must go below 30 first, then cross back above        |
//|   - SELL: RSI must go above 70 first, then cross back below       |
//|   - ATR must be above 6.0 for any trade entry                     |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Position must be in profit                                     |
//|   - RSI change must exceed configured percentage                   |
//|   - Trailing stop moves when price moves by 20% of initial stop    |
//|                                                                    |
//| Risk Management:                                                   |
//|   - ATR-based stop loss                                           |
//|   - Dynamic position sizing (1% risk per trade)                    |
//|   - Trailing stop to protect profits                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input int    RSI_Period = 14;         // RSI Period
input int    RSI_Oversold = 30;       // RSI Oversold Level
input int    RSI_Overbought = 70;     // RSI Overbought Level
input double RiskPercent = 1.0;       // Risk percentage per trade
input int    ATR_Period = 14;         // ATR Period
input double ATR_Multiplier = 2.0;    // ATR Multiplier for Stop Loss
input int    SMA_Period = 14;         // SMA Period for RSI smoothing
input double RSI_Change = 1.0;        // RSI Change percentage for closing position
input double Min_ATR = 6.0;           // Minimum ATR for placing orders
input double Trail_SL_Percent = 20.0; // Percentage of SL points to move to trailing stop

// Global variables
int rsiHandle;
int atrHandle;
int smaHandle;
double rsiBuffer[];
double atrBuffer[];
double smoothRsiBuffer[];
datetime lastBarTime = 0;
bool isInTrade = false;
ENUM_POSITION_TYPE currentPositionType = (ENUM_POSITION_TYPE)-1;  // -1 represents no position
double initialStopLoss = 0;           // Store initial stop loss for trailing calculation

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicator
    rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE)
    {
        Print("Error creating RSI indicator!");
        return INIT_FAILED;
    }

    // Initialize ATR indicator
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Error creating ATR indicator!");
        return INIT_FAILED;
    }

    // Initialize SMA on RSI
    smaHandle = iMA(_Symbol, PERIOD_CURRENT, SMA_Period, 0, MODE_SMA, rsiHandle);
    if(smaHandle == INVALID_HANDLE)
    {
        Print("Error creating SMA indicator!");
        return INIT_FAILED;
    }

    // Allocate memory for indicator buffers
    ArraySetAsSeries(rsiBuffer, true);
    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(smoothRsiBuffer, true);

    return(INIT_SUCCEEDED);
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
}

//+------------------------------------------------------------------+
//| Find the highest high in the last N bars                          |
//+------------------------------------------------------------------+
double FindSwingHigh(int bars)
{
    double high = 0;
    double highs[];
    ArraySetAsSeries(highs, true);

    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, bars, highs) == bars)
    {
        high = highs[ArrayMaximum(highs, 0, bars)];
    }

    return high;
}

//+------------------------------------------------------------------+
//| Find the lowest low in the last N bars                            |
//+------------------------------------------------------------------+
double FindSwingLow(int bars)
{
    double low = 0;
    double lows[];
    ArraySetAsSeries(lows, true);

    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, bars, lows) == bars)
    {
        low = lows[ArrayMinimum(lows, 0, bars)];
    }

    return low;
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
//| Calculate stop loss based on ATR                                   |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1)
    {
        Print("Error copying ATR buffer!");
        return 0;
    }

    double atrValue = atrBuffer[0];
    double stopDistance = atrValue * ATR_Multiplier;

    if(orderType == ORDER_TYPE_BUY)
        return entryPrice - stopDistance;
    else
        return entryPrice + stopDistance;
}

//+------------------------------------------------------------------+
//| Check if position is in profit                                    |
//+------------------------------------------------------------------+
bool IsPositionInProfit()
{
    if(!PositionSelect(_Symbol)) return false;

    double positionProfit = PositionGetDouble(POSITION_PROFIT);
    return (positionProfit > 0);
}

//+------------------------------------------------------------------+
//| Calculate RSI percentage change                                    |
//+------------------------------------------------------------------+
double CalculateRsiChange(double currentRsi, double previousRsi)
{
    if(previousRsi == 0) return 0;
    return ((currentRsi - previousRsi) / previousRsi) * 100;
}

//+------------------------------------------------------------------+
//| Check if we have a valid RSI crossover                           |
//+------------------------------------------------------------------+
bool IsValidCrossover(const double &rsiValues[], bool isBuy)
{
    // For buy signals
    if(isBuy)
    {
        // Force debug print for every call
        Print("FORCE DEBUG - RSI Values: Current=", DoubleToString(rsiValues[0], 2),
              " Prev=", DoubleToString(rsiValues[1], 2),
              " Prev2=", DoubleToString(rsiValues[2], 2));

        // Case 1: Previous bar was below 30, current bar crossed above
        bool case1 = rsiValues[1] <= RSI_Oversold && rsiValues[0] > RSI_Oversold;

        // Case 2: Two bars ago was below 30, previous and current bars confirm cross
        bool case2 = rsiValues[2] <= RSI_Oversold &&
                    rsiValues[1] > RSI_Oversold &&
                    rsiValues[0] > RSI_Oversold;

        // Force print conditions
        Print("FORCE DEBUG - Conditions: Case1=", case1, " Case2=", case2,
              " TwoBarsAgoBelow30=", (rsiValues[2] <= RSI_Oversold),
              " PrevAbove30=", (rsiValues[1] > RSI_Oversold),
              " CurrentAbove30=", (rsiValues[0] > RSI_Oversold));

        if(case1 || case2)
        {
            Print("SIGNAL DETECTED - Type: ", case1 ? "Case1" : "Case2",
                  " RSI Values: Current=", DoubleToString(rsiValues[0], 2),
                  " Prev=", DoubleToString(rsiValues[1], 2),
                  " Prev2=", DoubleToString(rsiValues[2], 2));
            return true;
        }
    }
    // For sell signals
    else
    {
        // First, check if we were recently above overbought
        bool wasAboveOverbought = false;
        int lastAboveIndex = -1;

        // Find the most recent bar that was above overbought
        for(int i = 1; i < 3; i++)
        {
            if(rsiValues[i] >= RSI_Overbought)
            {
                wasAboveOverbought = true;
                lastAboveIndex = i;
                break;
            }
        }

        if(wasAboveOverbought)
        {
            // If we found a bar above overbought, check if we've crossed below
            // We consider it a valid crossover if:
            // 1. Current value is below overbought AND
            // 2. Either:
            //    a. Previous value was above overbought OR
            //    b. Previous value was first cross below overbought (current < prev < overbought)
            if(rsiValues[0] < RSI_Overbought &&
               (rsiValues[1] >= RSI_Overbought ||
                (lastAboveIndex == 2 && rsiValues[1] < RSI_Overbought && rsiValues[1] < rsiValues[2])))
            {
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check if we should update trailing stop                           |
//+------------------------------------------------------------------+
void CheckTrailingStop()
{
    if(!isInTrade) return;

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

        // For buy positions
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            // Calculate the minimum price move needed before trailing (20% of SL distance)
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
            // Calculate the minimum price move needed before trailing (20% of SL distance)
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
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Only process at the close of a new candle
    if(currentBarTime == lastBarTime)
        return;

    // Update the last bar time
    lastBarTime = currentBarTime;

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
        Print("Resetting isInTrade flag - No open positions found");
        isInTrade = false;
        currentPositionType = (ENUM_POSITION_TYPE)-1;
    }

    // Copy indicator values
    double rsiValues[];
    double smoothRsiValues[];
    double atrValues[];  // Add ATR array
    ArraySetAsSeries(rsiValues, true);
    ArraySetAsSeries(smoothRsiValues, true);
    ArraySetAsSeries(atrValues, true);  // Set ATR array as series

    // Get last 5 bars of RSI values
    if(CopyBuffer(rsiHandle, 0, 0, 5, rsiValues) != 5)
    {
        Print("Error copying RSI buffer: ", GetLastError());
        return;
    }

    if(CopyBuffer(smaHandle, 0, 0, 5, smoothRsiValues) != 5)
    {
        Print("Error copying SMA buffer: ", GetLastError());
        return;
    }

    // Get ATR values
    if(CopyBuffer(atrHandle, 0, 0, 5, atrValues) != 5)
    {
        Print("Error copying ATR buffer: ", GetLastError());
        return;
    }

    string currentTime = TimeToString(currentBarTime);

    // Debug print actual RSI values and trade state
    Print(currentTime, " - DEBUG - Raw RSI Values - Current:", DoubleToString(rsiValues[0], 2),
          " Prev:", DoubleToString(rsiValues[1], 2),
          " Prev2:", DoubleToString(rsiValues[2], 2),
          " IsInTrade:", isInTrade,
          " HasOpenPosition:", hasOpenPosition,
          " ATR:", DoubleToString(atrValues[0], 2));

    // Always print RSI values for monitoring
    if(rsiValues[0] <= RSI_Oversold + 5 || rsiValues[0] >= RSI_Overbought - 5 ||
       rsiValues[1] <= RSI_Oversold + 5 || rsiValues[1] >= RSI_Overbought - 5)
    {
        Print(currentTime, " - RSI Monitor - Raw RSI: Current=", DoubleToString(rsiValues[0], 2),
              " Prev=", DoubleToString(rsiValues[1], 2),
              " Prev2=", DoubleToString(rsiValues[2], 2),
              " Smooth RSI: Current=", DoubleToString(smoothRsiValues[0], 2),
              " Prev=", DoubleToString(smoothRsiValues[1], 2),
              " Prev2=", DoubleToString(smoothRsiValues[2], 2),
              " ATR=", DoubleToString(atrValues[0], 2));
    }

    // Check for trade conditions
    if(!isInTrade)
    {
        Print("PRE-SIGNAL CHECK - Time:", currentTime,
              " RSI Values - Current:", DoubleToString(rsiValues[0], 2),
              " Prev:", DoubleToString(rsiValues[1], 2),
              " Prev2:", DoubleToString(rsiValues[2], 2),
              " ATR:", DoubleToString(atrValues[0], 2));

        // Check buy conditions
        bool rawRsiBuySignal = IsValidCrossover(rsiValues, true);
        bool smoothRsiBuySignal = IsValidCrossover(smoothRsiValues, true);

        // Check sell conditions
        bool rawRsiSellSignal = IsValidCrossover(rsiValues, false);
        bool smoothRsiSellSignal = IsValidCrossover(smoothRsiValues, false);

        Print("POST-SIGNAL CHECK - Time:", currentTime,
              " Raw Buy:", rawRsiBuySignal,
              " Smooth Buy:", smoothRsiBuySignal,
              " Raw Sell:", rawRsiSellSignal,
              " Smooth Sell:", smoothRsiSellSignal,
              " ATR:", DoubleToString(atrValues[0], 2));

        // First check if ATR is sufficient for any trade
        if(atrValues[0] < Min_ATR)
        {
            if(rawRsiBuySignal || smoothRsiBuySignal || rawRsiSellSignal || smoothRsiSellSignal)
            {
                Print(currentTime, " - Signal ignored due to low ATR: ", DoubleToString(atrValues[0], 2),
                      " (Minimum required: ", Min_ATR, ")");
            }
            return;
        }

        // Process buy signals
        if(rawRsiBuySignal || smoothRsiBuySignal)
        {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double stopLoss = CalculateStopLoss(ORDER_TYPE_BUY, ask);

            if(stopLoss == 0) return;  // Error in calculating stop loss

            double stopLossPoints = MathAbs(ask - stopLoss);
            double lotSize = CalculateLotSize(stopLossPoints);

            Print(currentTime, " - Buy Signal Detected - Raw RSI: ", DoubleToString(rsiValues[0], 2),
                  " Previous: ", DoubleToString(rsiValues[1], 2),
                  " Prev2: ", DoubleToString(rsiValues[2], 2),
                  " ATR: ", DoubleToString(atrValues[0], 2),
                  " Signal from: ", rawRsiBuySignal ? "Raw RSI" : "Smooth RSI");

            if(OrderOpen(ORDER_TYPE_BUY, ask, lotSize, stopLoss))
            {
                isInTrade = true;
                currentPositionType = POSITION_TYPE_BUY;
                initialStopLoss = stopLoss;
                Print(currentTime, " - Buy order opened at ", ask, " SL: ", stopLoss,
                      " ATR: ", atrValues[0], " Lots: ", lotSize,
                      " Raw RSI: ", rsiValues[0], " Smooth RSI: ", smoothRsiValues[0]);
            }
        }
        // Process sell signals
        else if(rawRsiSellSignal || smoothRsiSellSignal)
        {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double stopLoss = CalculateStopLoss(ORDER_TYPE_SELL, bid);

            if(stopLoss == 0) return;  // Error in calculating stop loss

            double stopLossPoints = MathAbs(stopLoss - bid);
            double lotSize = CalculateLotSize(stopLossPoints);

            Print(currentTime, " - Sell Signal Detected - Raw RSI: ", DoubleToString(rsiValues[0], 2),
                  " Previous: ", DoubleToString(rsiValues[1], 2),
                  " Prev2: ", DoubleToString(rsiValues[2], 2),
                  " ATR: ", DoubleToString(atrValues[0], 2),
                  " Signal from: ", rawRsiSellSignal ? "Raw RSI" : "Smooth RSI");

            if(OrderOpen(ORDER_TYPE_SELL, bid, lotSize, stopLoss))
            {
                isInTrade = true;
                currentPositionType = POSITION_TYPE_SELL;
                initialStopLoss = stopLoss;
                Print(currentTime, " - Sell order opened at ", bid, " SL: ", stopLoss,
                      " ATR: ", atrValues[0], " Lots: ", lotSize,
                      " Raw RSI: ", rsiValues[0], " Smooth RSI: ", smoothRsiValues[0]);
            }
        }
    }
    else
    {
        // Check if we should update trailing stop
        CheckTrailingStop();
    }

    // Check for close conditions at candle close using smoothed RSI
    if(isInTrade && IsPositionInProfit())  // Only check exit if position is profitable
    {
        bool shouldClose = false;
        double rsiChange = CalculateRsiChange(smoothRsiValues[1], smoothRsiValues[2]);

        // Close buy position when smoothed RSI starts decreasing by more than RSI_Change%
        if(currentPositionType == POSITION_TYPE_BUY &&
           smoothRsiValues[1] > RSI_Oversold &&
           rsiChange < -RSI_Change)  // Requires RSI_Change% decrease
        {
            shouldClose = true;
        }
        // Close sell position when smoothed RSI starts increasing by more than RSI_Change%
        else if(currentPositionType == POSITION_TYPE_SELL &&
                smoothRsiValues[1] < RSI_Overbought &&
                rsiChange > RSI_Change)  // Requires RSI_Change% increase
        {
            shouldClose = true;
        }

        if(shouldClose)
        {
            double closePrice = (currentPositionType == POSITION_TYPE_BUY) ?
                              SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            double positionProfit = PositionGetDouble(POSITION_PROFIT);

            if(CloseAllPositions())
            {
                isInTrade = false;
                currentPositionType = (ENUM_POSITION_TYPE)-1;  // Reset to no position
                Print("Position closed at ", closePrice, " Profit: ", positionProfit,
                      " Smooth RSI: ", smoothRsiValues[1],
                      " RSI Change: ", DoubleToString(rsiChange, 2), "%",
                      " (Threshold: ±", DoubleToString(RSI_Change, 2), "%)",
                      " Time: ", TimeToString(currentBarTime));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open a new order                                                  |
//+------------------------------------------------------------------+
bool OrderOpen(ENUM_ORDER_TYPE orderType, double price, double lots, double stopLoss)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = orderType;
    request.price = price;
    request.sl = stopLoss;
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
              " Filling: ", request.type_filling);
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
