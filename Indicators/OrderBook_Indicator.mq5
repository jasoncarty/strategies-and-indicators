//+------------------------------------------------------------------+
//| Order Book (Depth of Market) Visualizer Indicator for MT5        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0

// Input parameters
input int MaxLevels = 10; // Number of bid/ask levels to display
color BidColor = clrBlue;
color AskColor = clrRed;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!MarketBookAdd(_Symbol))
    {
        MessageBox("Order book (DOM) not available for this symbol.", "Order Book Indicator", MB_ICONERROR);
        return(INIT_FAILED);
    }
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    MarketBookRelease(_Symbol);
    DeleteAllOrderBookObjects();
}

//+------------------------------------------------------------------+
//| Helper: Delete all order book objects                            |
//+------------------------------------------------------------------+
void DeleteAllOrderBookObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "OB_Bid_") == 0 || StringFind(name, "OB_Ask_") == 0)
            ObjectDelete(0, name);
    }
    Comment("");
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
    DeleteAllOrderBookObjects();
    MqlBookInfo book[];
    if(!MarketBookGet(_Symbol, book))
    {
        Comment("Order book (DOM) not available for this symbol.");
        return(rates_total);
    }
    int bidCount = 0, askCount = 0;
    double bestBid = 0, bestAsk = 0, bestBidVol = 0, bestAskVol = 0;
    for(int i=0; i<ArraySize(book); i++)
    {
        if(book[i].type == BOOK_TYPE_BUY && bidCount < MaxLevels)
        {
            string name = "OB_Bid_" + IntegerToString(bidCount);
            ObjectCreate(0, name, OBJ_HLINE, 0, 0, (double)book[i].price);
            ObjectSetInteger(0, name, OBJPROP_COLOR, BidColor);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
            if(bidCount == 0) { bestBid = book[i].price; bestBidVol = book[i].volume; }
            bidCount++;
        }
        else if(book[i].type == BOOK_TYPE_SELL && askCount < MaxLevels)
        {
            string name = "OB_Ask_" + IntegerToString(askCount);
            ObjectCreate(0, name, OBJ_HLINE, 0, 0, (double)book[i].price);
            ObjectSetInteger(0, name, OBJPROP_COLOR, AskColor);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
            if(askCount == 0) { bestAsk = book[i].price; bestAskVol = book[i].volume; }
            askCount++;
        }
    }
    Comment("Order Book (Top Level):\nBest Bid: ", DoubleToString(bestBid, _Digits), " (Vol: ", bestBidVol, ")\nBest Ask: ", DoubleToString(bestAsk, _Digits), " (Vol: ", bestAskVol, ")");
    return(rates_total);
}
//+------------------------------------------------------------------+
//| End of Order Book Indicator                                      |
//+------------------------------------------------------------------+ 