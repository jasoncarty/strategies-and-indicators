//+------------------------------------------------------------------+
//| BreakoutStrategy_Base.mqh                                         |
//| Base functions for breakout strategy                              |
//| Can be included by both pure and ML versions                     |
//| Uses exact same state machine as original SimpleBreakoutML_EA    |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//--- State machine variables (extern to allow access from main EA)
extern double previousDayHigh;
extern double previousDayLow;
extern double newDayLow; // New day low established after bearish breakout
extern double newDayHigh; // New day high established after bullish breakout
extern bool hasOpenPosition;
extern datetime lastDayCheck;

//--- State machine enum
enum BREAKOUT_STATE {
    WAITING_FOR_BREAKOUT = 0,
    BULLISH_BREAKOUT_DETECTED = 1,
    BEARISH_BREAKOUT_DETECTED = 2,
    WAITING_FOR_BULLISH_RETEST = 3,
    WAITING_FOR_BEARISH_RETEST = 4,
    WAITING_FOR_BULLISH_CLOSE = 5,
    WAITING_FOR_BEARISH_CLOSE = 6,
    // New states for enhanced trading opportunities
    PRICE_NEAR_HIGH_LEVEL = 7,        // Price approaching prev day high
    PRICE_NEAR_LOW_LEVEL = 8,         // Price approaching prev day low
    BOUNCE_FROM_HIGH_DETECTED = 9,    // Bounce down from prev day high
    BOUNCE_FROM_LOW_DETECTED = 10     // Bounce up from prev day low
};
extern BREAKOUT_STATE currentState;
extern datetime lastStateChange;
extern double breakoutLevel;
extern string breakoutDirection;
extern string bounceDirection; // Direction for bounce trades (separate from breakouts)
extern double swingPoint; // The swing high/low that created the retest

//--- Retest tracking variables
extern bool bullishRetestDetected;
extern double bullishRetestLow;
extern bool bearishRetestDetected;
extern double bearishRetestHigh;

//--- Breakout tracking variables
extern double lastBreakoutLevel;
extern string lastBreakoutDirection;
extern int retestBar;
extern int breakoutBar;
extern int barsSinceBreakout;

//--- Bounce tracking variables (new)
extern bool bounceFromHighDetected;
extern bool bounceFromLowDetected;
extern double bounceHighPoint;
extern double bounceLowPoint;
extern int proximityThreshold; // Points threshold for "near" level detection
extern bool wasNearHighLevel;
extern bool wasNearLowLevel;

//+------------------------------------------------------------------+
//| Update previous day high and low                                 |
//+------------------------------------------------------------------+
void UpdatePreviousDayLevels() {
    previousDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
    previousDayLow = iLow(_Symbol, PERIOD_D1, 1);

        Print("📊 Previous Day Levels Updated:");
    Print("   High: ", DoubleToString(previousDayHigh, _Digits));
    Print("   Low: ", DoubleToString(previousDayLow, _Digits));

    // Reset bounce extremes for new day
    ResetBounceExtremes();

    // Initialize proximity threshold (can be adjusted)
    if(proximityThreshold == 0) {
        proximityThreshold = 50; // 50 points default - can be made configurable
        Print("📏 Proximity threshold set to: ", proximityThreshold, " points");
    }
}

//+------------------------------------------------------------------+
//| Calculate stop loss for bullish trade (based on new day low)     |
//+------------------------------------------------------------------+
double CalculateBullishStopLoss(int stopLossBuffer = 20, double customLevel = 0.0) {
    // Use custom level if provided, otherwise use NEW day low
    double referenceLevel = (customLevel > 0) ? customLevel : newDayLow;
    double baseStopLoss = referenceLevel - (stopLossBuffer * _Point); // Add small buffer below reference level
    Print("🎯 Bullish Stop Loss Calculation:");
    Print("   Reference level: ", DoubleToString(referenceLevel, _Digits), (customLevel > 0) ? " (custom)" : " (NEW day low)");
    Print("   Buffer: ", stopLossBuffer, " points");
    Print("   Base Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
    return baseStopLoss;
}

//+------------------------------------------------------------------+
//| Calculate stop loss for bearish trade (based on new day high)    |
//+------------------------------------------------------------------+
double CalculateBearishStopLoss(int stopLossBuffer = 20, double customLevel = 0.0) {
    // Use custom level if provided, otherwise use NEW day high
    double referenceLevel = (customLevel > 0) ? customLevel : newDayHigh;
    double baseStopLoss = referenceLevel + (stopLossBuffer * _Point); // Add small buffer above reference level
    Print("🎯 Bearish Stop Loss Calculation:");
    Print("   Reference level: ", DoubleToString(referenceLevel, _Digits), (customLevel > 0) ? " (custom)" : " (NEW day high)");
    Print("   Buffer: ", stopLossBuffer, " points");
    Print("   Base Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
    return baseStopLoss;
}

//+------------------------------------------------------------------+
//| Calculate stop loss for bounce trades - SELL from high bounce   |
//+------------------------------------------------------------------+
double CalculateBounceFromHighStopLoss(int stopLossBuffer = 20) {
    // For bounce SELL trades: Stop loss above the bounce high point
    double baseStopLoss = bounceHighPoint + (stopLossBuffer * _Point);
    Print("🎯 Bounce From High Stop Loss Calculation:");
    Print("   Bounce high point: ", DoubleToString(bounceHighPoint, _Digits));
    Print("   Buffer: ", stopLossBuffer, " points");
    Print("   Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
    return baseStopLoss;
}

//+------------------------------------------------------------------+
//| Calculate stop loss for bounce trades - BUY from low bounce     |
//+------------------------------------------------------------------+
double CalculateBounceFromLowStopLoss(int stopLossBuffer = 20) {
    // For bounce BUY trades: Stop loss below the bounce low point
    double baseStopLoss = bounceLowPoint - (stopLossBuffer * _Point);
    Print("🎯 Bounce From Low Stop Loss Calculation:");
    Print("   Bounce low point: ", DoubleToString(bounceLowPoint, _Digits));
    Print("   Buffer: ", stopLossBuffer, " points");
    Print("   Stop Loss: ", DoubleToString(baseStopLoss, _Digits));
    return baseStopLoss;
}

//+------------------------------------------------------------------+
//| Calculate take profit based on risk:reward ratio                 |
//+------------------------------------------------------------------+
double CalculateTakeProfit(double entryPrice, double stopLoss, double riskRewardRatio, string direction) {
    double stopDistance;
    double takeProfit;

    if(direction == "buy") {
        stopDistance = entryPrice - stopLoss;
        takeProfit = entryPrice + (stopDistance * riskRewardRatio);
    } else {
        stopDistance = stopLoss - entryPrice;
        takeProfit = entryPrice - (stopDistance * riskRewardRatio);
    }

    Print("🎯 Take Profit Calculation:");
    Print("   Entry: ", DoubleToString(entryPrice, _Digits));
    Print("   Stop Loss: ", DoubleToString(stopLoss, _Digits));
    Print("   Stop Distance: ", DoubleToString(stopDistance, _Digits));
    Print("   Risk:Reward Ratio: ", DoubleToString(riskRewardRatio, 2), ":1");
    Print("   Take Profit: ", DoubleToString(takeProfit, _Digits));

    return takeProfit;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPercent, double stopDistance, double accountBalance = 0) {
    if(accountBalance == 0) {
        accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }

    double riskAmount = accountBalance * (riskPercent / 100.0);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if(tickSize == 0) tickSize = _Point;
    if(tickValue == 0) tickValue = _Point * 10; // Fallback

    double lotSize = riskAmount / (stopDistance * tickValue / tickSize);

    // Ensure lot size is within broker limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathRound(lotSize / lotStep) * lotStep;

    Print("🎯 Lot Size Calculation:");
    Print("   Risk Percent: ", DoubleToString(riskPercent, 2), "%");
    Print("   Account Balance: $", DoubleToString(accountBalance, 2));
    Print("   Risk Amount: $", DoubleToString(riskAmount, 2));
    Print("   Stop Distance: ", DoubleToString(stopDistance, _Digits));
    Print("   Calculated Lot Size: ", DoubleToString(lotSize, 2));

    return lotSize;
}

//+------------------------------------------------------------------+
//| Check if price is near a key level                              |
//+------------------------------------------------------------------+
bool IsPriceNearLevel(double currentPrice, double level, int threshold) {
    double distance = MathAbs(currentPrice - level);
    double thresholdPrice = threshold * _Point;
    return (distance <= thresholdPrice);
}

//+------------------------------------------------------------------+
//| Detect bounce from previous day high                            |
//+------------------------------------------------------------------+
bool DetectBounceFromHigh(double currentHigh, double currentLow, double currentClose) {
    // Price must have reached near previous day high and then moved away
    bool reachedHigh = IsPriceNearLevel(currentHigh, previousDayHigh, proximityThreshold);
    bool movedAway = currentClose < (previousDayHigh - (proximityThreshold * _Point));

    if(reachedHigh && movedAway) {
        bounceHighPoint = currentHigh;
        Print("🔄 Bounce from high detected - High: ", DoubleToString(currentHigh, _Digits),
              " Close: ", DoubleToString(currentClose, _Digits),
              " Prev Day High: ", DoubleToString(previousDayHigh, _Digits));
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Detect bounce from previous day low                             |
//+------------------------------------------------------------------+
bool DetectBounceFromLow(double currentHigh, double currentLow, double currentClose) {
    // Price must have reached near previous day low and then moved away
    bool reachedLow = IsPriceNearLevel(currentLow, previousDayLow, proximityThreshold);
    bool movedAway = currentClose > (previousDayLow + (proximityThreshold * _Point));

    if(reachedLow && movedAway) {
        bounceLowPoint = currentLow;
        Print("🔄 Bounce from low detected - Low: ", DoubleToString(currentLow, _Digits),
              " Close: ", DoubleToString(currentClose, _Digits),
              " Prev Day Low: ", DoubleToString(previousDayLow, _Digits));
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Reset bounce detection variables                                 |
//+------------------------------------------------------------------+
void ResetBounceVariables() {
    bounceFromHighDetected = false;
    bounceFromLowDetected = false;
    // Don't reset bounceHighPoint and bounceLowPoint here - they should track session extremes
    // Only reset them at new day or when explicitly needed
    wasNearHighLevel = false;
    wasNearLowLevel = false;
    bounceDirection = "";
    Print("🔄 Reset bounce detection variables (preserving bounce extremes)");
    Print("   Current bounce high point: ", DoubleToString(bounceHighPoint, _Digits));
    Print("   Current bounce low point: ", DoubleToString(bounceLowPoint, _Digits));
}

//+------------------------------------------------------------------+
//| Reset bounce extremes for new session                           |
//+------------------------------------------------------------------+
void ResetBounceExtremes() {
    bounceHighPoint = 0;
    bounceLowPoint = 0;
    Print("🔄 Reset bounce extremes for new session");
}

//+------------------------------------------------------------------+
//| Main state machine logic (exact copy from original)             |
//+------------------------------------------------------------------+
void ProcessBreakoutStateMachine() {
    double currentHigh = iHigh(_Symbol, _Period, 0);
    double currentLow = iLow(_Symbol, _Period, 0);
    double currentClose = iClose(_Symbol, _Period, 0);
    double previousHigh = iHigh(_Symbol, _Period, 1);
    double previousLow = iLow(_Symbol, _Period, 1);
    double previousClose = iClose(_Symbol, _Period, 1);
    double previousBarClose = iClose(_Symbol, _Period, 1);

    // Check for bounce opportunities in all non-bounce states
    if(currentState != BOUNCE_FROM_HIGH_DETECTED && currentState != BOUNCE_FROM_LOW_DETECTED) {
                        // Update bounce extremes continuously (like newDayHigh/newDayLow tracking)
        if(bounceHighPoint == 0 || currentHigh > bounceHighPoint) {
            bounceHighPoint = currentHigh;
        }
        if(bounceLowPoint == 0 || currentLow < bounceLowPoint) {
            bounceLowPoint = currentLow;
        }

        // Check for bounces from key levels (independent of any previous breakouts)
        if(DetectBounceFromHigh(currentHigh, currentLow, currentClose)) {
            currentState = BOUNCE_FROM_HIGH_DETECTED;
            bounceFromHighDetected = true;
            bounceDirection = "sell"; // Bounce from high = sell signal
            Print("🎯 State changed to BOUNCE_FROM_HIGH_DETECTED - Ready for SELL ML prediction (BOUNCE, not breakout)");
            Print("🎯 Bounce high point: ", DoubleToString(bounceHighPoint, _Digits), " (for stop loss calculation)");
            return;
        }

        if(DetectBounceFromLow(currentHigh, currentLow, currentClose)) {
            currentState = BOUNCE_FROM_LOW_DETECTED;
            bounceFromLowDetected = true;
            bounceDirection = "buy"; // Bounce from low = buy signal
            Print("🎯 State changed to BOUNCE_FROM_LOW_DETECTED - Ready for BUY ML prediction (BOUNCE, not breakout)");
            Print("🎯 Bounce low point: ", DoubleToString(bounceLowPoint, _Digits), " (for stop loss calculation)");
            return;
        }

        // Check for price proximity to levels (for retest scenarios)
        bool nearHigh = IsPriceNearLevel(currentClose, previousDayHigh, proximityThreshold);
        bool nearLow = IsPriceNearLevel(currentClose, previousDayLow, proximityThreshold);

                // Detect retests ONLY after confirmed previous breakouts
        if(nearHigh && lastBreakoutDirection == "bullish" && currentState == WAITING_FOR_BREAKOUT) {
            currentState = PRICE_NEAR_HIGH_LEVEL;
            bounceDirection = "sell"; // Retest from above = sell signal (this is a bounce off a previously broken level)
            Print("🎯 State changed to PRICE_NEAR_HIGH_LEVEL - Potential RETEST bounce sell opportunity");
        }

        if(nearLow && lastBreakoutDirection == "bearish" && currentState == WAITING_FOR_BREAKOUT) {
            currentState = PRICE_NEAR_LOW_LEVEL;
            bounceDirection = "buy"; // Retest from below = buy signal (this is a bounce off a previously broken level)
            Print("🎯 State changed to PRICE_NEAR_LOW_LEVEL - Potential RETEST bounce buy opportunity");
        }
    }

    switch((int)currentState) {
        case WAITING_FOR_BREAKOUT:
            // IMPORTANT: Continue updating new day low/high even when waiting for breakout
            // This ensures we use the most recent levels for risk management
            if(newDayLow == 0 || previousLow < newDayLow) {
                double oldNewDayLow = newDayLow;
                newDayLow = previousLow;
                if(oldNewDayLow != 0) {
                    Print("📉 New day low updated while waiting for breakout: ", DoubleToString(oldNewDayLow, _Digits), " -> ", DoubleToString(newDayLow, _Digits));
                }
            }

            if(previousHigh > newDayHigh || newDayHigh == 0) {
                double oldNewDayHigh = newDayHigh;
                newDayHigh = previousHigh;
                if(oldNewDayHigh != 0) {
                    Print("📈 New day high updated while waiting for breakout: ", DoubleToString(oldNewDayHigh, _Digits), " -> ", DoubleToString(newDayHigh, _Digits));
                }
            }

            // Look for bullish breakout
            for(int i = 1; i <= 10; i++) {
                double barClose = iClose(_Symbol, _Period, i);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    Print("🔔 Bullish breakout detected at bar ", i, " - High: ", DoubleToString(barClose, _Digits));
                    break;
                }
            }
            // Look for bearish breakout
            for(int j = 1; j <= 10; j++) {
                double barClose = iClose(_Symbol, _Period, j);
                if(barClose < previousDayLow - (5 * _Point)) {
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = j;
                    barsSinceBreakout = 0;
                    Print("🔔 Bearish breakout detected at bar ", j, " - Low: ", DoubleToString(barClose, _Digits));
                    break;
                }
            }
            break;

        case BULLISH_BREAKOUT_DETECTED:
            // Wait for price to move above previous day high and establish new day high
            if(previousClose > previousDayHigh + (5 * _Point)) {
                // Always update new day high to the highest high since breakout
                if(newDayHigh == 0 || previousHigh > newDayHigh) {
                    newDayHigh = previousHigh;
                    Print("📈 New day high established at: ", DoubleToString(newDayHigh, _Digits));
                }
                currentState = WAITING_FOR_BULLISH_RETEST;
                Print("➡️ Waiting for bullish retest at level: ", DoubleToString(previousDayHigh, _Digits));
            }
            break;

        case BEARISH_BREAKOUT_DETECTED:
            // Wait for price to move below previous day low and establish new day low
            if(previousClose < previousDayLow - (5 * _Point)) {
                // Always update new day low to the lowest low since breakout
                if(newDayLow == 0 || previousLow < newDayLow) {
                    newDayLow = previousLow;
                    Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
                }
                currentState = WAITING_FOR_BEARISH_RETEST;
                Print("➡️ Waiting for bearish retest at level: ", DoubleToString(previousDayLow, _Digits));
            }
            break;

        case WAITING_FOR_BULLISH_RETEST:
            // Always update new day low to the lowest low since breakout (this will be our retest low)
            if(newDayLow == 0 || previousLow < newDayLow) {
                newDayLow = previousLow;
                Print("📉 New day low (retest low) established at: ", DoubleToString(newDayLow, _Digits));
            }

            if(previousClose <= previousDayHigh) {
                Print("🔍 DEBUG: Retest completed - Price bounced back down from previous day high. Current low: ", DoubleToString(currentLow, _Digits), " Previous day high: ", DoubleToString(previousDayHigh, _Digits));

                // Immediately go to WAITING_FOR_BULLISH_CLOSE state
                swingPoint = newDayLow; // Use new day low as the stop loss level
                currentState = WAITING_FOR_BULLISH_CLOSE;
                breakoutDirection = "bullish";
                bullishRetestDetected = true;
                Print("🎯 Bullish retest completed - Moving to WAITING_FOR_BULLISH_CLOSE");
                Print("🎯 Previous day high: ", DoubleToString(previousDayHigh, _Digits));
                Print("🎯 NEW day high(confirmation level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 NEW day low(stop loss level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 Waiting for close above new day high with momentum");
            }
            // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;

        case WAITING_FOR_BEARISH_RETEST:
            Print("🔍 DEBUG: In WAITING_FOR_BEARISH_RETEST - Retest detected: ", bearishRetestDetected, " Retest high: ", DoubleToString(bearishRetestHigh, _Digits));

            if(newDayLow == 0 || previousClose < newDayLow) {
                newDayLow = previousClose;
                Print("📉 New day low established at: ", DoubleToString(newDayLow, _Digits));
            }
            // Always update new day high to the highest high since breakout (this will be our retest high)
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                newDayHigh = previousHigh;
                Print("📈 New day high updated to: ", DoubleToString(newDayHigh, _Digits));
            }

            if(previousHigh >= previousDayLow) {
                Print("🔍 DEBUG: Retest completed - Price bounced back up from previous day low. Current high: ", DoubleToString(previousHigh, _Digits), " Previous day low: ", DoubleToString(previousDayLow, _Digits));

                // Immediately go to WAITING_FOR_BEARISH_CLOSE state
                swingPoint = newDayHigh; // Use new day high as the stop loss level
                currentState = WAITING_FOR_BEARISH_CLOSE;
                breakoutDirection = "bearish";
                bearishRetestDetected = true;
                Print("🎯 Bearish retest completed - Moving to WAITING_FOR_BEARISH_CLOSE");
                Print("🎯 Previous day low: ", DoubleToString(previousDayLow, _Digits));
                Print("🎯 NEW day low(confirmation level): ", DoubleToString(newDayLow, _Digits));
                Print("🎯 NEW day high(stop loss level): ", DoubleToString(newDayHigh, _Digits));
                Print("🎯 Waiting for close below new day low with momentum");
            }
            // Do NOT reset to WAITING_FOR_BREAKOUT if price moves away from the level; just keep waiting for confirmation
            break;

        case WAITING_FOR_BULLISH_CLOSE:
            // Check for opposite breakout (bearish) while waiting for bullish close
            for(int k = 1; k <= 10; k++) {
                double barClose = iClose(_Symbol, _Period, k);
                if(barClose < previousDayLow - (5 * _Point)) {
                    // Reset state variables and transition to bearish breakout state
                    ResetBreakoutStateVariables();
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = k;
                    barsSinceBreakout = 0;
                    Print("🔄 Opposite breakout detected while waiting for bullish close!");
                    Print("🔔 Bearish breakout detected at bar ", k, " - Low: ", DoubleToString(barClose, _Digits));
                    return; // Exit early to avoid processing bullish logic
                }
            }

            // Update new day low if price goes lower (better risk management)
            if(newDayLow == 0 || previousLow < newDayLow) {
                double oldNewDayLow = newDayLow;
                newDayLow = previousLow;
                Print("📉 New day low updated during close phase: ", DoubleToString(oldNewDayLow, _Digits), " -> ", DoubleToString(newDayLow, _Digits));
                Print("   This improves stop loss placement for better risk management");
            }

            Print("🔍 DEBUG: In WAITING_FOR_BULLISH_CLOSE - Previous bar close: ", DoubleToString(previousBarClose, _Digits), " New day high: ", DoubleToString(newDayHigh, _Digits));
            Print("🔍 DEBUG: Need previous bar close above: ", DoubleToString(newDayHigh, _Digits));

            if(newDayHigh > 0 && previousBarClose > newDayHigh) {
                Print("✅ Bullish confirmation - Previous bar closed above NEW day high with momentum, placing buy order.");
                // This will be handled by the main EA
                currentState = WAITING_FOR_BREAKOUT;
            } else {
                Print("⏳ Waiting for previous bar to close above NEW day high: ", DoubleToString(newDayHigh, _Digits));
            }
            break;

        case WAITING_FOR_BEARISH_CLOSE:
            // Check for opposite breakout (bullish) while waiting for bearish close
            for(int k = 1; k <= 10; k++) {
                double barClose = iClose(_Symbol, _Period, k);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    // Reset state variables and transition to bullish breakout state
                    ResetBreakoutStateVariables();
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = k;
                    barsSinceBreakout = 0;
                    Print("🔄 Opposite breakout detected while waiting for bearish close!");
                    Print("🔔 Bullish breakout detected at bar ", k, " - High: ", DoubleToString(barClose, _Digits));
                    return; // Exit early to avoid processing bearish logic
                }
            }

            // Update new day high if price goes higher (better risk management)
            if(previousHigh > newDayHigh || newDayHigh == 0) {
                double oldNewDayHigh = newDayHigh;
                newDayHigh = previousHigh;
                Print("📈 New day high updated during close phase: ", DoubleToString(oldNewDayHigh, _Digits), " -> ", DoubleToString(newDayHigh, _Digits));
                Print("   This improves stop loss placement for better risk management");
            }

            Print("🔍 DEBUG: In WAITING_FOR_BEARISH_CLOSE - Previous bar close: ", DoubleToString(previousBarClose, _Digits), " New day low: ", DoubleToString(newDayLow, _Digits));
            Print("🔍 DEBUG: Need previous bar close below: ", DoubleToString(newDayLow, _Digits));

            if(newDayLow > 0 && previousBarClose < newDayLow) {
                Print("✅ Bearish confirmation - Previous bar closed below NEW day low with momentum, placing sell order.");
                // This will be handled by the main EA
                currentState = WAITING_FOR_BREAKOUT;
            } else {
                Print("⏳ Waiting for previous bar to close below NEW day low: ", DoubleToString(newDayLow, _Digits));
            }
            break;

        case PRICE_NEAR_HIGH_LEVEL:
            // Check for breakouts first (price might break out instead of bouncing)
            for(int i = 1; i <= 10; i++) {
                double barClose = iClose(_Symbol, _Period, i);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    ResetBounceVariables(); // Clear bounce state
                    Print("🔔 Bullish breakout detected while near high level at bar ", i, " - High: ", DoubleToString(barClose, _Digits));
                    return;
                }
                if(barClose < previousDayLow - (5 * _Point)) {
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    ResetBounceVariables(); // Clear bounce state
                    Print("🔔 Bearish breakout detected while near high level at bar ", i, " - Low: ", DoubleToString(barClose, _Digits));
                    return;
                }
            }

            // If no breakout, check for retest bounce opportunity
            if(DetectBounceFromHigh(currentHigh, currentLow, currentClose)) {
                currentState = BOUNCE_FROM_HIGH_DETECTED;
                bounceFromHighDetected = true;
                bounceDirection = "sell";
                Print("🎯 Retest bounce detected at high level - Ready for SELL ML prediction");
            }
            break;

        case PRICE_NEAR_LOW_LEVEL:
            // Check for breakouts first (price might break out instead of bouncing)
            for(int i = 1; i <= 10; i++) {
                double barClose = iClose(_Symbol, _Period, i);
                if(barClose > previousDayHigh + (5 * _Point)) {
                    currentState = BULLISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayHigh;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bullish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    ResetBounceVariables(); // Clear bounce state
                    Print("🔔 Bullish breakout detected while near low level at bar ", i, " - High: ", DoubleToString(barClose, _Digits));
                    return;
                }
                if(barClose < previousDayLow - (5 * _Point)) {
                    currentState = BEARISH_BREAKOUT_DETECTED;
                    breakoutLevel = previousDayLow;
                    lastBreakoutLevel = barClose;
                    lastBreakoutDirection = "bearish";
                    breakoutBar = i;
                    barsSinceBreakout = 0;
                    ResetBounceVariables(); // Clear bounce state
                    Print("🔔 Bearish breakout detected while near low level at bar ", i, " - Low: ", DoubleToString(barClose, _Digits));
                    return;
                }
            }

            // If no breakout, check for retest bounce opportunity
            if(DetectBounceFromLow(currentHigh, currentLow, currentClose)) {
                currentState = BOUNCE_FROM_LOW_DETECTED;
                bounceFromLowDetected = true;
                bounceDirection = "buy";
                Print("🎯 Retest bounce detected at low level - Ready for BUY ML prediction");
            }
            break;

        case BOUNCE_FROM_HIGH_DETECTED:
            // ML prediction should be requested for SELL in the main EA
            // This state indicates a trading opportunity is ready
            Print("💡 BOUNCE_FROM_HIGH_DETECTED state - Main EA should request SELL ML prediction");
            // State will be reset by main EA after trade execution or timeout
            break;

        case BOUNCE_FROM_LOW_DETECTED:
            // ML prediction should be requested for BUY in the main EA
            // This state indicates a trading opportunity is ready
            Print("💡 BOUNCE_FROM_LOW_DETECTED state - Main EA should request BUY ML prediction");
            // State will be reset by main EA after trade execution or timeout
            break;
    }
}

//+------------------------------------------------------------------+
//| Reset state variables when transitioning between breakout states  |
//+------------------------------------------------------------------+
void ResetBreakoutStateVariables() {
    // IMPORTANT: Do NOT reset newDayHigh and newDayLow - preserve them for better risk management
    // Only reset the retest detection flags and levels
    bullishRetestDetected = false;
    bearishRetestDetected = false;
    bearishRetestHigh = 0;
    bullishRetestLow = 0;

    // Reset bounce detection variables
    ResetBounceVariables();

    Print("🔄 Reset breakout state variables (preserving new day high/low levels)");
    Print("   Current new day high: ", DoubleToString(newDayHigh, _Digits));
    Print("   Current new day low: ", DoubleToString(newDayLow, _Digits));
}

//+------------------------------------------------------------------+
//| Log current state and levels for debugging                        |
//+------------------------------------------------------------------+
void LogCurrentState() {
    Print("📊 Current State: ", EnumToString(currentState));
    Print("   Previous Day High: ", DoubleToString(previousDayHigh, _Digits));
    Print("   Previous Day Low: ", DoubleToString(previousDayLow, _Digits));
    Print("   NEW Day High: ", DoubleToString(newDayHigh, _Digits));
    Print("   NEW Day Low: ", DoubleToString(newDayLow, _Digits));
    Print("   Breakout Direction: ", breakoutDirection);
    Print("   Bullish Retest Detected: ", bullishRetestDetected ? "true" : "false");
    Print("   Bearish Retest Detected: ", bearishRetestDetected ? "true" : "false");
    Print("   Bounce From High Detected: ", bounceFromHighDetected ? "true" : "false");
    Print("   Bounce From Low Detected: ", bounceFromLowDetected ? "true" : "false");
    Print("   Proximity Threshold: ", proximityThreshold, " points");
    Print("   Bounce High Point: ", DoubleToString(bounceHighPoint, _Digits), " (for stop loss)");
    Print("   Bounce Low Point: ", DoubleToString(bounceLowPoint, _Digits), " (for stop loss)");
}

//+------------------------------------------------------------------+
//| Get current market features (for ML integration)                |
//+------------------------------------------------------------------+
void GetMarketFeatures(double &features[]) {
    // This function can be used by ML-enhanced versions
    // to collect market features for ML predictions

    // Technical indicators
    int rsi_handle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
    double rsi_buffer[];
    ArraySetAsSeries(rsi_buffer, true);
    CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer);
    features[0] = rsi_buffer[0];

    int stoch_handle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    double stoch_main_buffer[], stoch_signal_buffer[];
    ArraySetAsSeries(stoch_main_buffer, true);
    ArraySetAsSeries(stoch_signal_buffer, true);
    CopyBuffer(stoch_handle, 0, 0, 1, stoch_main_buffer);
    CopyBuffer(stoch_handle, 1, 0, 1, stoch_signal_buffer);
    features[1] = stoch_main_buffer[0];
    features[2] = stoch_signal_buffer[0];

    int macd_handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
    double macd_main_buffer[], macd_signal_buffer[];
    ArraySetAsSeries(macd_main_buffer, true);
    ArraySetAsSeries(macd_signal_buffer, true);
    CopyBuffer(macd_handle, 0, 0, 1, macd_main_buffer);
    CopyBuffer(macd_handle, 1, 0, 1, macd_signal_buffer);
    features[3] = macd_main_buffer[0];
    features[4] = macd_signal_buffer[0];

    // Bollinger Bands
    int bb_handle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
    double bb_upper_buffer[], bb_lower_buffer[];
    ArraySetAsSeries(bb_upper_buffer, true);
    ArraySetAsSeries(bb_lower_buffer, true);
    CopyBuffer(bb_handle, 1, 0, 1, bb_upper_buffer);
    CopyBuffer(bb_handle, 2, 0, 1, bb_lower_buffer);
    features[5] = bb_upper_buffer[0];
    features[6] = bb_lower_buffer[0];

    // Additional indicators
    int adx_handle = iADX(_Symbol, _Period, 14);
    double adx_buffer[];
    ArraySetAsSeries(adx_buffer, true);
    CopyBuffer(adx_handle, 0, 0, 1, adx_buffer);
    features[7] = adx_buffer[0];

    // Williams %R (not available in MQL5, using RSI as substitute)
    features[8] = features[0]; // Using RSI as substitute

    int cci_handle = iCCI(_Symbol, _Period, 14, PRICE_TYPICAL);
    double cci_buffer[];
    ArraySetAsSeries(cci_buffer, true);
    CopyBuffer(cci_handle, 0, 0, 1, cci_buffer);
    features[9] = cci_buffer[0];

    int momentum_handle = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);
    double momentum_buffer[];
    ArraySetAsSeries(momentum_buffer, true);
    CopyBuffer(momentum_handle, 0, 0, 1, momentum_buffer);
    features[10] = momentum_buffer[0];

    int atr_handle = iATR(_Symbol, _Period, 14);
    double atr_buffer[];
    ArraySetAsSeries(atr_buffer, true);
    CopyBuffer(atr_handle, 0, 0, 1, atr_buffer);
    features[11] = atr_buffer[0];

    // Market conditions
    long volume_array[];
    ArraySetAsSeries(volume_array, true);
    CopyTickVolume(_Symbol, _Period, 0, 2, volume_array);
    features[12] = (volume_array[0] > 0) ? (double)volume_array[0] / volume_array[1] : 1.0;

    double close_array[];
    ArraySetAsSeries(close_array, true);
    CopyClose(_Symbol, _Period, 0, 2, close_array);
    features[13] = (close_array[0] - close_array[1]) / close_array[1];
    features[14] = atr_buffer[0] / close_array[0];
    features[15] = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Time-based features
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    features[16] = dt.hour;
    features[17] = (dt.hour >= 8 && dt.hour < 16) ? 1.0 : 0.0; // London session
    features[18] = dt.day_of_week;
    features[19] = dt.mon;

    // Strategy-specific features
    features[20] = previousDayHigh;
    features[21] = previousDayLow;
    features[22] = (previousDayHigh + previousDayLow) / 2;
    features[23] = (breakoutDirection == "buy") ? 1.0 : ((breakoutDirection == "sell") ? -1.0 : 0.0);
}
