//+------------------------------------------------------------------+
//|                                           xauusd-strategy-4.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Moving Average Crossover Strategy           |
//| Description:                                                       |
//|   A trading strategy for XAUUSD (Gold) that uses multiple moving   |
//|   averages for trend identification and trade signals. It combines |
//|   fast and slow MAs with volume confirmation.                      |
//|                                                                    |
//| Entry Conditions:                                                  |
//|   - BUY: Fast MA crosses above slow MA with volume confirmation    |
//|   - SELL: Fast MA crosses below slow MA with volume confirmation   |
//|   - Additional trend filter using longer-term MA                   |
//|                                                                    |
//| Exit Conditions:                                                   |
//|   - Opposite MA crossover                                         |
//|   - Fixed take profit and stop loss                               |
//|   - Trailing stop option                                          |
//|                                                                    |
//| Risk Management:                                                   |
//|   - Fixed position sizing                                         |
//|   - Maximum risk per trade                                        |
//|   - Multiple timeframe analysis                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"

// Include trade functions
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>

// Create trade object
CTrade trade;

// Input Parameters for Risk Management
input group "Risk Management"
input bool     EnableDebugLogs = false;    // Enable debug logging
input double   RiskPercent = 1.0;          // Risk per trade (%)
input double   RR_Ratio = 2.5;             // Risk:Reward ratio
input double   MaxStopLossUSD = 500.0;     // Maximum Stop Loss in USD
input double   MinStopLossUSD = 20.0;      // Minimum Stop Loss in USD
input bool     UseFixedLotSize = false;    // Use fixed lot size
input double   FixedLotSize = 0.01;        // Fixed lot size if enabled
input bool     UsePartialClose = true;     // Use partial profit taking
input double   PartialClosePercent = 50.0; // Percentage of position to close at first target
input double   FirstTargetRR = 1.5;        // Risk:Reward ratio for first target

// Input Parameters for Trailing Stop
input group "Trailing Stop Settings"
input bool     UseTrailingStop = true;     // Use Trailing Stop
input double   TrailingStopPercent = 50.0; // Trailing Stop (% of TP distance)

// Input Parameters for Asian Session
input group "Asian Session Times (Server Time)"
input int      AsianSessionStartHour = 1;     // Asian Session Start Hour (0-23)
input int      AsianSessionStartMin = 0;      // Asian Session Start Minute
input int      AsianSessionEndHour = 10;      // Asian Session End Hour (0-23)
input int      AsianSessionEndMin = 0;        // Asian Session End Minute
input bool     OnlyTradeAsianSession = true;  // Only trade during Asian session

// Input Parameters for Filters
input group "Trading Filters"
input bool     UseVolatilityFilter = true;    // Use Volatility Filter
input int      VolatilityPeriod = 20;         // Volatility Period
input double   VolatilityThreshold = 2.0;     // Volatility Threshold
input bool     UseTrendFilter = true;         // Use Trend Filter
input int      TrendPeriod = 20;              // Trend Period
input bool     OnlyTradeLong = true;         // Only Take Long Trades
input int      MaxConsecutiveLosses = 4;      // Max Consecutive Losses

// Input Parameters for News Filter
input group "News Filter Settings"
input bool     UseNewsFilter = true;       // Use news filter
input int      NewsMinutesBefore = 30;     // Minutes before news to stop trading
input int      NewsMinutesAfter = 30;      // Minutes after news to resume trading

// Input Parameters for Volume Filter
input group "Volume Filter Settings"
input bool     UseVolumeFilter = true;     // Use volume filter
input int      VolumePeriod = 20;          // Period for volume MA
input double   MinVolumeThreshold = 1.2;   // Minimum volume ratio (current/average)

// Input Parameters for Correlation Filter
input group "Correlation Filter Settings"
input bool     UseCorrelationFilter = true; // Use correlation filter
input string   CorrelationPair = "EURUSD+";    // Correlation instrument
input int      CorrelationPeriod = 20;     // Correlation calculation period
input double   MinCorrelation = 0.5;      // Minimum correlation threshold (positive for EURUSD)

// Global Variables
bool isFirstCandle = true;
bool hasPosition = false;
datetime lastTradeTime = 0;
int consecutiveLosses = 0;
double lastTradeProfit = 0;
ulong lastTicket = 0;  // Store the last trade ticket

// Indicator handles
int volumeMAHandle = INVALID_HANDLE;
int correlationHandle = INVALID_HANDLE;
datetime lastNewsTime = 0;
bool inNewsWindow = false;

// Structure for partial close tracking
struct PartialCloseInfo {
   ulong ticket;
   bool firstTargetClosed;
   double originalLots;
};
PartialCloseInfo partialCloseTracker[];

//+------------------------------------------------------------------+
//| Calculate Average True Range (ATR)                                 |
//+------------------------------------------------------------------+
double GetATR(int period)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(_Symbol, PERIOD_CURRENT, period);
   CopyBuffer(atrHandle, 0, 0, 1, atr);
   return atr[0];
}

//+------------------------------------------------------------------+
//| Check if volatility is suitable for trading                        |
//+------------------------------------------------------------------+
bool IsVolatilityGood()
{
   if(!UseVolatilityFilter) return true;

   double atr = GetATR(VolatilityPeriod);
   double averagePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate ATR as percentage of price
   double atrPercent = (atr / averagePrice) * 100;

   return atrPercent >= VolatilityThreshold;
}

//+------------------------------------------------------------------+
//| Check if trend aligns with trade direction                         |
//+------------------------------------------------------------------+
bool IsTrendAligned(bool isBullish)
{
   if(!UseTrendFilter) return true;

   double ma[];
   ArraySetAsSeries(ma, true);
   int maHandle = iMA(_Symbol, PERIOD_CURRENT, TrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   CopyBuffer(maHandle, 0, 0, 2, ma);

   bool isUptrend = ma[0] > ma[1];
   return isBullish ? isUptrend : !isUptrend;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade settings
   trade.SetExpertMagicNumber(444444);  // Unique identifier for this EA
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);

   // Verify symbol is XAUUSD
   if(_Symbol != "XAUUSD+")
   {
      Print("Error: This EA is designed for XAUUSD only!");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialize volume MA
   if(UseVolumeFilter)
   {
      volumeMAHandle = iMA(_Symbol, PERIOD_CURRENT, VolumePeriod, 0, MODE_SMA, VOLUME_TICK);
      if(volumeMAHandle == INVALID_HANDLE)
      {
         Print("Failed to create volume MA indicator!");
         return INIT_FAILED;
      }
   }

   // Initialize correlation indicator
   if(UseCorrelationFilter)
   {
      // Verify correlation pair exists
      if(!SymbolSelect(CorrelationPair, true))
      {
         Print("Error: Correlation pair ", CorrelationPair, " not found!");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   // Reset trade counters
   consecutiveLosses = 0;
   lastTradeProfit = 0;
   ArrayResize(partialCloseTracker, 0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check if we should take a trade                                    |
//+------------------------------------------------------------------+
bool ShouldTakeTrade(bool isBullish)
{
   // Check consecutive losses
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      if(EnableDebugLogs)
         Print("Max consecutive losses reached (", consecutiveLosses, "), skipping trade");
      return false;
   }

   // Check if we're only taking long trades
   if(OnlyTradeLong && !isBullish)
   {
      if(EnableDebugLogs)
         Print("Skipping short trade as OnlyTradeLong is enabled");
      return false;
   }

   // Check news filter
   if(IsNewsTime())
   {
      if(EnableDebugLogs)
         Print("Skipping trade due to news window");
      return false;
   }

   // Check volume filter
   if(!IsVolumeSufficient())
   {
      if(EnableDebugLogs)
         Print("Skipping trade due to insufficient volume");
      return false;
   }

   // Check correlation filter
   if(!IsCorrelationValid())
   {
      if(EnableDebugLogs)
         Print("Skipping trade due to invalid correlation");
      return false;
   }

   // Check volatility
   if(!IsVolatilityGood())
   {
      if(EnableDebugLogs)
         Print("Volatility filter prevented trade");
      return false;
   }

   // Check trend alignment
   if(!IsTrendAligned(isBullish))
   {
      if(EnableDebugLogs)
         Print("Trend filter prevented trade");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Track trade results                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Get all history for today
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   if(totalDeals <= 0) return;

   // Find the last closed position
   ulong lastPositionTicket = 0;
   double positionProfit = 0;
   bool foundClosedPosition = false;

   // Loop through deals backwards to find the last closed position
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;

      // Check if this deal belongs to our EA
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != trade.RequestMagic())
         continue;

      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

      // Skip partial closes by checking if the deal volume equals the position volume
      double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      // If this is a position close
      if(dealEntry == DEAL_ENTRY_OUT)
      {
         // Get all deals for this position to check if it's a partial close
         bool isPartialClose = false;
         double totalVolumeOut = 0;

         for(int j = i; j >= 0; j--)
         {
            ulong checkDealTicket = HistoryDealGetTicket(j);
            if(HistoryDealGetInteger(checkDealTicket, DEAL_POSITION_ID) == positionId)
            {
               if(HistoryDealGetInteger(checkDealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
               {
                  totalVolumeOut += HistoryDealGetDouble(checkDealTicket, DEAL_VOLUME);
               }
               else if(HistoryDealGetInteger(checkDealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
               {
                  if(totalVolumeOut < HistoryDealGetDouble(checkDealTicket, DEAL_VOLUME))
                  {
                     isPartialClose = true;
                     break;
                  }
               }
            }
         }

         if(!isPartialClose)
         {
            lastPositionTicket = positionId;
            positionProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            foundClosedPosition = true;
            break;
         }
      }
   }

   if(foundClosedPosition)
   {
      lastTradeProfit = positionProfit;

      if(positionProfit < 0)
      {
         consecutiveLosses++;
         if(EnableDebugLogs)
            Print("Loss trade detected. Consecutive losses: ", consecutiveLosses);
      }
      else
      {
         consecutiveLosses = 0;
         if(EnableDebugLogs)
            Print("Win trade detected. Consecutive losses reset to 0");
      }

      Print("Position ", lastPositionTicket, " closed with profit: ", positionProfit,
            ", Consecutive losses: ", consecutiveLosses);
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up indicators
   if(volumeMAHandle != INVALID_HANDLE)
      IndicatorRelease(volumeMAHandle);
   if(correlationHandle != INVALID_HANDLE)
      IndicatorRelease(correlationHandle);
}

//+------------------------------------------------------------------+
//| Check if current time is within Asian session                      |
//+------------------------------------------------------------------+
bool IsAsianSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Convert current time to minutes since midnight
   int currentTimeInMinutes = now.hour * 60 + now.min;
   int sessionStartInMinutes = AsianSessionStartHour * 60 + AsianSessionStartMin;
   int sessionEndInMinutes = AsianSessionEndHour * 60 + AsianSessionEndMin;

   // Handle session crossing midnight
   if(sessionStartInMinutes > sessionEndInMinutes)
   {
      return currentTimeInMinutes >= sessionStartInMinutes ||
             currentTimeInMinutes <= sessionEndInMinutes;
   }

   return currentTimeInMinutes >= sessionStartInMinutes &&
          currentTimeInMinutes <= sessionEndInMinutes;
}

//+------------------------------------------------------------------+
//| Calculate stop loss in points based on risk                        |
//+------------------------------------------------------------------+
double CalculateStopLoss(double riskPercent, double &lotSize)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmountUSD = accountBalance * (riskPercent / 100);

   // Ensure risk amount is within limits
   riskAmountUSD = MathMin(riskAmountUSD, MaxStopLossUSD);
   riskAmountUSD = MathMax(riskAmountUSD, MinStopLossUSD);

   // Get tick value and size
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue * (_Point / tickSize);

   // Get minimum lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Calculate initial lot size based on minimum stop loss
   lotSize = UseFixedLotSize ? FixedLotSize : minLot;

   // Calculate stop loss in points
   double stopLossPoints = riskAmountUSD / (lotSize * pointValue);

   // If using fixed lot size, return the stop loss points
   if(UseFixedLotSize)
      return stopLossPoints;

   // Otherwise, calculate optimal lot size
   lotSize = riskAmountUSD / (stopLossPoints * pointValue);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   // Recalculate final stop loss points based on actual lot size
   stopLossPoints = riskAmountUSD / (lotSize * pointValue);

   Print("Risk Amount: $", riskAmountUSD,
         ", Lot Size: ", lotSize,
         ", Stop Loss Points: ", stopLossPoints,
         ", Stop Loss USD: $", stopLossPoints * lotSize * pointValue);

   return stopLossPoints;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if market is open
   if(!MarketInfo.IsMarketOpen())
   {
      return;
   }

   // First, handle any open position's trailing stop
   if(PositionsTotal() > 0 && UseTrailingStop)
   {
      ManageTrailingStop();
      return;
   }

   // Check if we should only trade during Asian session
   if(OnlyTradeAsianSession && !IsAsianSession())
   {
      // If we're outside Asian session, reset first candle flag
      // so we can trade the first candle of next session
      isFirstCandle = true;
      return;
   }

   // Check if we already have a position
   if(PositionsTotal() > 0)
   {
      hasPosition = true;
      return;
   }

   hasPosition = false;

   // Get current candle data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, rates) != 3)  // Get 3 candles
      return;

   // Only trade on the first completed candle of a new session
   if(!isFirstCandle || hasPosition)
      return;

   // For the first candle of the session, we want to wait until we have a completed candle
   // rates[0] is current forming candle
   // rates[1] is the last completed candle
   // rates[2] is the candle before that

   // Check if we're still in the first candle of the session
   datetime periodStart = rates[1].time;  // Start time of the last completed candle
   if(!IsAsianSessionStart(periodStart))
   {
      return;  // Not the start of Asian session
   }

   // Determine if first completed candle is bullish or bearish
   bool isBullish = rates[1].close > rates[1].open;

   // Check if we should take this trade
   if(!ShouldTakeTrade(isBullish))
   {
      if(EnableDebugLogs)
         Print("Trade conditions not met, skipping trade");
      return;
   }

   // Calculate lot size and stop loss
   double lotSize;
   double stopLossPoints = CalculateStopLoss(RiskPercent, lotSize);

   // Add extra check for market open before placing trades
   if(!MarketInfo.IsMarketOpen())
   {
      Print("Market is closed, cannot place trade");
      return;
   }

   // Log the candle we're basing our decision on
   Print("Trading based on candle: Open=", rates[1].open,
         ", Close=", rates[1].close,
         ", Time=", TimeToString(rates[1].time));

   // Place trade based on candle direction
   if(isBullish)
   {
      double entry = rates[0].close;
      double sl = entry - (stopLossPoints * _Point);
      double tp = entry + (stopLossPoints * RR_Ratio * _Point);

      if(PlaceTrade(isBullish, entry, sl, tp, lotSize))
      {
         lastTradeTime = TimeCurrent();
         Print("Buy order placed during Asian session at ", TimeToString(lastTradeTime),
               ", Stop Loss: $", MathAbs(entry - sl) * lotSize / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      }
   }
   else if(!OnlyTradeLong)  // Only place sell trades if OnlyTradeLong is false
   {
      double entry = rates[0].close;
      double sl = entry + (stopLossPoints * _Point);
      double tp = entry - (stopLossPoints * RR_Ratio * _Point);

      if(PlaceTrade(isBullish, entry, sl, tp, lotSize))
      {
         lastTradeTime = TimeCurrent();
         Print("Sell order placed during Asian session at ", TimeToString(lastTradeTime),
               ", Stop Loss: $", MathAbs(entry - sl) * lotSize / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      }
   }

   isFirstCandle = false;  // Prevent further trades until next session
}

//+------------------------------------------------------------------+
//| Custom function to reset first candle flag                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long& lparam,
                  const double& dparam,
                  const string& sparam)
{
   // Reset first candle flag when timeframe changes
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      isFirstCandle = true;
      Print("Timeframe changed - Reset first candle flag");
   }
}

//+------------------------------------------------------------------+
//| Market Information Helper Class                                    |
//+------------------------------------------------------------------+
class CMarketInfo
{
public:
   static bool IsMarketOpen()
   {
      // Get trading mode
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

      // Check if trading is allowed
      return tradeMode == SYMBOL_TRADE_MODE_FULL;
   }
};

// Create market info instance
CMarketInfo MarketInfo;

//+------------------------------------------------------------------+
//| Check if the given time is the start of Asian session             |
//+------------------------------------------------------------------+
bool IsAsianSessionStart(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);

   // Convert to minutes since midnight
   int timeMinutes = dt.hour * 60 + dt.min;
   int sessionStartMinutes = AsianSessionStartHour * 60 + AsianSessionStartMin;

   // Check if this candle starts exactly at session start
   return timeMinutes == sessionStartMinutes;
}

//+------------------------------------------------------------------+
//| Manage trailing stop for open position                            |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionSelectByTicket(ticket))
      {
         double positionType = PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

         // Calculate the total distance to TP
         double totalDistance = MathAbs(currentTP - openPrice);
         // Calculate trailing stop distance (50% of total distance)
         double trailDistance = totalDistance * (TrailingStopPercent / 100.0);

         double newSL = 0;
         bool modifyNeeded = false;

         if(positionType == POSITION_TYPE_BUY)
         {
            // For buy positions, trail above the current price
            newSL = currentPrice - trailDistance;
            // Only modify if new SL is higher than current SL
            if(newSL > currentSL + _Point)
            {
               modifyNeeded = true;
            }
         }
         else if(positionType == POSITION_TYPE_SELL)
         {
            // For sell positions, trail below the current price
            newSL = currentPrice + trailDistance;
            // Only modify if new SL is lower than current SL
            if(newSL < currentSL - _Point || currentSL == 0)
            {
               modifyNeeded = true;
            }
         }

         // If modification is needed and new SL is valid
         if(modifyNeeded && newSL > 0)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            if(GetLastError() == 0)
            {
               Print("Trailing stop updated for ticket #", ticket,
                     " New SL: ", newSL,
                     " Current Price: ", currentPrice);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Place a trade with proper stops                                   |
//+------------------------------------------------------------------+
bool PlaceTrade(bool isBullish, double entry, double stopLoss, double takeProfit, double lotSize)
{
   bool result = false;

   if(isBullish)
   {
      // If using partial close, set first target at FirstTargetRR and final target at RR_Ratio
      double firstTP = UsePartialClose ? entry + ((entry - stopLoss) * FirstTargetRR) : takeProfit;

      result = trade.Buy(lotSize, _Symbol, entry, stopLoss, firstTP, "XAUUSD-Strat4");
      if(result)
      {
         lastTicket = trade.ResultOrder();
         lastTradeTime = TimeCurrent();

         // Add to partial close tracker if using partial close
         if(UsePartialClose)
         {
            int size = ArraySize(partialCloseTracker);
            ArrayResize(partialCloseTracker, size + 1);
            partialCloseTracker[size].ticket = lastTicket;
            partialCloseTracker[size].firstTargetClosed = false;
            partialCloseTracker[size].originalLots = lotSize;
         }

         Print("Buy order placed during Asian session at ", TimeToString(lastTradeTime),
               ", Stop Loss: $", MathAbs(entry - stopLoss) * lotSize / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      }
      else
      {
         HandleTradeError();
      }
   }
   else
   {
      // If using partial close, set first target at FirstTargetRR and final target at RR_Ratio
      double firstTP = UsePartialClose ? entry - ((stopLoss - entry) * FirstTargetRR) : takeProfit;

      result = trade.Sell(lotSize, _Symbol, entry, stopLoss, firstTP, "XAUUSD-Strat4");
      if(result)
      {
         lastTicket = trade.ResultOrder();
         lastTradeTime = TimeCurrent();

         // Add to partial close tracker if using partial close
         if(UsePartialClose)
         {
            int size = ArraySize(partialCloseTracker);
            ArrayResize(partialCloseTracker, size + 1);
            partialCloseTracker[size].ticket = lastTicket;
            partialCloseTracker[size].firstTargetClosed = false;
            partialCloseTracker[size].originalLots = lotSize;
         }

         Print("Sell order placed during Asian session at ", TimeToString(lastTradeTime),
               ", Stop Loss: $", MathAbs(entry - stopLoss) * lotSize / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      }
      else
      {
         HandleTradeError();
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| Handle trade error                                               |
//+------------------------------------------------------------------+
void HandleTradeError()
{
   int lastError = GetLastError();
   string errorText = "Unknown error";
   switch(lastError)
   {
      case TRADE_RETCODE_INVALID:
         errorText = "Invalid request";
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         errorText = "Invalid volume";
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         errorText = "Invalid price";
         break;
      case TRADE_RETCODE_INVALID_STOPS:
         errorText = "Invalid stops";
         break;
      case TRADE_RETCODE_TRADE_DISABLED:
         errorText = "Trade not allowed";
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         errorText = "Market closed";
         break;
      case TRADE_RETCODE_NO_MONEY:
         errorText = "Not enough money";
         break;
      case TRADE_RETCODE_PRICE_CHANGED:
         errorText = "Price changed";
         break;
      default:
         errorText = "Error #" + IntegerToString(lastError);
         break;
   }
   Print("Failed to place trade. Error: ", errorText);
}

//+------------------------------------------------------------------+
//| Check if we're in a news window                                    |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;

   // This is a simplified news check. In a real implementation,
   // you would need to connect to a news feed service
   datetime currentTime = TimeCurrent();

   // If we're already in a news window, check if we should exit
   if(inNewsWindow)
   {
      if(currentTime >= lastNewsTime + NewsMinutesAfter * 60)
      {
         inNewsWindow = false;
         return false;
      }
      return true;
   }

   // Simulate news events at the start of each hour
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   if(dt.min == 0)  // News at the start of each hour
   {
      lastNewsTime = currentTime;
      inNewsWindow = true;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if volume is sufficient for trading                          |
//+------------------------------------------------------------------+
bool IsVolumeSufficient()
{
   if(!UseVolumeFilter) return true;

   long volume[];
   double volumeMA[];
   ArraySetAsSeries(volume, true);
   ArraySetAsSeries(volumeMA, true);

   // Get current volume and MA
   if(CopyRealVolume(_Symbol, PERIOD_CURRENT, 0, 2, volume) <= 0 ||
      CopyBuffer(volumeMAHandle, 0, 0, 2, volumeMA) <= 0)
   {
      Print("Failed to copy volume data");
      return false;
   }

   // Convert volume to double for calculation
   double currentVolume = (double)volume[0];
   double volumeRatio = currentVolume / volumeMA[0];

   if(EnableDebugLogs)
      Print("Volume ratio: ", volumeRatio, " (threshold: ", MinVolumeThreshold, ")");

   return volumeRatio >= MinVolumeThreshold;
}

//+------------------------------------------------------------------+
//| Calculate correlation with specified pair                          |
//+------------------------------------------------------------------+
bool IsCorrelationValid()
{
   if(!UseCorrelationFilter) return true;

   double correlation = CalculateCorrelation();

   if(EnableDebugLogs)
      Print("Correlation with ", CorrelationPair, ": ", correlation);

   return correlation >= MinCorrelation;  // Positive correlation with EURUSD is good for gold
}

//+------------------------------------------------------------------+
//| Calculate correlation between XAUUSD and correlation pair          |
//+------------------------------------------------------------------+
double CalculateCorrelation()
{
   double price1[], price2[];
   ArrayResize(price1, CorrelationPeriod);
   ArrayResize(price2, CorrelationPeriod);

   // Get price data for both instruments
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, CorrelationPeriod, price1) <= 0 ||
      CopyClose(CorrelationPair, PERIOD_CURRENT, 0, CorrelationPeriod, price2) <= 0)
   {
      Print("Failed to copy price data for correlation calculation");
      return 0;
   }

   return MathCorrelation(price1, price2, CorrelationPeriod);
}

//+------------------------------------------------------------------+
//| Calculate correlation between two arrays                           |
//+------------------------------------------------------------------+
double MathCorrelation(double &array1[], double &array2[], int size)
{
   if(size < 2) return 0;

   double sum_x = 0, sum_y = 0, sum_xy = 0;
   double sum_x2 = 0, sum_y2 = 0;

   for(int i = 0; i < size; i++)
   {
      sum_x += array1[i];
      sum_y += array2[i];
      sum_xy += array1[i] * array2[i];
      sum_x2 += array1[i] * array1[i];
      sum_y2 += array2[i] * array2[i];
   }

   double n = (double)size;
   double numerator = (n * sum_xy) - (sum_x * sum_y);
   double denominator = MathSqrt(((n * sum_x2) - (sum_x * sum_x)) * ((n * sum_y2) - (sum_y * sum_y)));

   if(denominator == 0) return 0;

   return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Manage partial close and trailing stop                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!UsePartialClose && !UseTrailingStop) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionSelectByTicket(ticket))
      {
         double positionType = PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double positionLots = PositionGetDouble(POSITION_VOLUME);

         // Handle partial close
         if(UsePartialClose)
         {
            // Find position in tracker
            for(int j = ArraySize(partialCloseTracker) - 1; j >= 0; j--)
            {
               if(partialCloseTracker[j].ticket == ticket && !partialCloseTracker[j].firstTargetClosed)
               {
                  // Calculate if first target is reached
                  bool targetReached = false;
                  if(positionType == POSITION_TYPE_BUY)
                     targetReached = currentPrice >= currentTP;
                  else
                     targetReached = currentPrice <= currentTP;

                  if(targetReached)
                  {
                     // Calculate lots to close
                     double lotsToClose = positionLots * (PartialClosePercent / 100.0);

                     // Close partial position
                     if(trade.PositionClosePartial(ticket, lotsToClose))
                     {
                        // Update stop loss to break even
                        trade.PositionModify(ticket, openPrice,
                           positionType == POSITION_TYPE_BUY ?
                           openPrice + ((openPrice - currentSL) * RR_Ratio) :
                           openPrice - ((currentSL - openPrice) * RR_Ratio));

                        partialCloseTracker[j].firstTargetClosed = true;
                        Print("Partial close executed for ticket #", ticket);
                     }
                  }
               }
            }
         }

         // Handle trailing stop
         if(UseTrailingStop)
         {
            // Calculate the total distance to TP
            double totalDistance = MathAbs(currentTP - openPrice);
            // Calculate trailing stop distance
            double trailDistance = totalDistance * (TrailingStopPercent / 100.0);

            double newSL = 0;
            bool modifyNeeded = false;

            if(positionType == POSITION_TYPE_BUY)
            {
               newSL = currentPrice - trailDistance;
               if(newSL > currentSL + _Point)
                  modifyNeeded = true;
            }
            else if(positionType == POSITION_TYPE_SELL)
            {
               newSL = currentPrice + trailDistance;
               if(newSL < currentSL - _Point || currentSL == 0)
                  modifyNeeded = true;
            }

            if(modifyNeeded && newSL > 0)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               if(GetLastError() == 0)
               {
                  Print("Trailing stop updated for ticket #", ticket,
                        " New SL: ", newSL,
                        " Current Price: ", currentPrice);
               }
            }
         }
      }
   }
}
