//+------------------------------------------------------------------+
//|                                                 Example_EA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Include the WebServerAPI
#include "WebServerAPI.mqh"

// Input parameters
input double LotSize = 0.1;
input int StopLoss = 50;
input int TakeProfit = 100;

// Global variables
int magic_number = 12345;
datetime test_start_time;
datetime test_end_time;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    test_start_time = TimeCurrent();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    test_end_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Simple example strategy logic
    if(!PositionSelect(_Symbol))
    {
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Simple buy signal (for demonstration)
        if(ask > bid)
        {
            double sl = ask - StopLoss * _Point;
            double tp = ask + TakeProfit * _Point;

            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = LotSize;
            request.type = ORDER_TYPE_BUY;
            request.price = ask;
            request.sl = sl;
            request.tp = tp;
            request.deviation = 10;
            request.magic = magic_number;
            request.comment = "Example EA";

            OrderSend(request, result);
        }
    }
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
{
    // Extract test results from the strategy tester
    StrategyTestResult result;
    result.strategy_name = "Example EA";
    result.symbol = _Symbol;
    result.timeframe = EnumToString(_Period);
    result.start_date = test_start_time;
    result.end_date = test_end_time;

    // Get test results from the strategy tester
    result.initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
    result.final_balance = TesterStatistics(STAT_BALANCE);
    result.profit = TesterStatistics(STAT_PROFIT);
    result.profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
    result.max_drawdown = TesterStatistics(STAT_BALANCEDD);
    result.total_trades = (int)TesterStatistics(STAT_TRADES);
    result.winning_trades = (int)TesterStatistics(STAT_PROFIT_TRADES);
    result.losing_trades = (int)TesterStatistics(STAT_DEALS);
    result.win_rate = TesterStatistics(STAT_PROFIT_TRADES) / TesterStatistics(STAT_TRADES) * 100;
    result.sharpe_ratio = TesterStatistics(STAT_SHARPE_RATIO);

    // Create parameters JSON
    string parameters = "{";
    parameters += "\"lot_size\":" + DoubleToString(LotSize, 2) + ",";
    parameters += "\"stop_loss\":" + IntegerToString(StopLoss) + ",";
    parameters += "\"take_profit\":" + IntegerToString(TakeProfit);
    parameters += "}";
    result.parameters = parameters;

    // Extract trade history
    TradeData trades[];
    ExtractTradeHistory(trades);

    // Send results to web server
    bool success = SendTestResultsToServer(result, trades);

    if(success)
    {
        Print("Test results sent successfully to web server");
    }
    else
    {
        Print("Failed to send test results to web server");
    }

    return 0;
}

//+------------------------------------------------------------------+
//| Extract trade history from the strategy tester                   |
//+------------------------------------------------------------------+
void ExtractTradeHistory(TradeData &trades[])
{
    int total_deals = (int)TesterStatistics(STAT_DEALS);
    ArrayResize(trades, total_deals);

    for(int i = 0; i < total_deals; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if(deal_ticket > 0)
        {
            trades[i].ticket = (int)deal_ticket;
            trades[i].symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);

            ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
            if(deal_type == DEAL_TYPE_BUY)
                trades[i].type = "BUY";
            else if(deal_type == DEAL_TYPE_SELL)
                trades[i].type = "SELL";
            else
                trades[i].type = "UNKNOWN";

            trades[i].volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
            trades[i].open_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
            trades[i].close_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
            trades[i].open_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
            trades[i].close_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
            trades[i].profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            trades[i].swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
            trades[i].commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            trades[i].net_profit = trades[i].profit + trades[i].swap + trades[i].commission;
        }
    }
}
