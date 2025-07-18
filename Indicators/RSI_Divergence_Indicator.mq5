//+------------------------------------------------------------------+
//| RSI Divergence Indicator for MT5                                 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0

#include <MovingAverages.mqh>

input int RSI_Period = 14;
input int Swing_Lookback = 5; // Number of bars to look back for swing highs/lows
input double Min_Div_Distance = 10; // Minimum bars between divergence points
color BullDivColor = clrGreen;
color BearDivColor = clrRed;

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
    if(rates_total < RSI_Period + Swing_Lookback + 2)
        return(rates_total);

    double rsi[];
    ArraySetAsSeries(rsi, true);
    if(!iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE, rsi))
        return(rates_total);

    // Loop through bars, skipping the most recent (incomplete) bar
    for(int i = rates_total - Swing_Lookback - 2; i >= Swing_Lookback; i--)
    {
        // Find swing low in price and RSI
        bool isSwingLowPrice = true, isSwingLowRSI = true;
        for(int j = 1; j <= Swing_Lookback; j++)
        {
            if(low[i] > low[i-j] || low[i] > low[i+j]) isSwingLowPrice = false;
            if(rsi[i] > rsi[i-j] || rsi[i] > rsi[i+j]) isSwingLowRSI = false;
        }
        // Find swing high in price and RSI
        bool isSwingHighPrice = true, isSwingHighRSI = true;
        for(int j = 1; j <= Swing_Lookback; j++)
        {
            if(high[i] < high[i-j] || high[i] < high[i+j]) isSwingHighPrice = false;
            if(rsi[i] < rsi[i-j] || rsi[i] < rsi[i+j]) isSwingHighRSI = false;
        }
        // Look for bullish divergence (regular)
        if(isSwingLowPrice && isSwingLowRSI)
        {
            // Search for previous swing low
            for(int k = i + Min_Div_Distance; k < rates_total - Swing_Lookback - 1; k++)
            {
                bool prevSwingLowPrice = true, prevSwingLowRSI = true;
                for(int j = 1; j <= Swing_Lookback; j++)
                {
                    if(low[k] > low[k-j] || low[k] > low[k+j]) prevSwingLowPrice = false;
                    if(rsi[k] > rsi[k-j] || rsi[k] > rsi[k+j]) prevSwingLowRSI = false;
                }
                if(prevSwingLowPrice && prevSwingLowRSI)
                {
                    if(low[i] < low[k] && rsi[i] > rsi[k])
                    {
                        // Bullish divergence found
                        string name = "RSI_BullDiv_" + IntegerToString(i);
                        ObjectCreate(0, name, OBJ_ARROW, 0, time[i], low[i]);
                        ObjectSetInteger(0, name, OBJPROP_COLOR, BullDivColor);
                        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233); // Up arrow
                        break;
                    }
                }
            }
        }
        // Look for bearish divergence (regular)
        if(isSwingHighPrice && isSwingHighRSI)
        {
            // Search for previous swing high
            for(int k = i + Min_Div_Distance; k < rates_total - Swing_Lookback - 1; k++)
            {
                bool prevSwingHighPrice = true, prevSwingHighRSI = true;
                for(int j = 1; j <= Swing_Lookback; j++)
                {
                    if(high[k] < high[k-j] || high[k] < high[k+j]) prevSwingHighPrice = false;
                    if(rsi[k] < rsi[k-j] || rsi[k] < rsi[k+j]) prevSwingHighRSI = false;
                }
                if(prevSwingHighPrice && prevSwingHighRSI)
                {
                    if(high[i] > high[k] && rsi[i] < rsi[k])
                    {
                        // Bearish divergence found
                        string name = "RSI_BearDiv_" + IntegerToString(i);
                        ObjectCreate(0, name, OBJ_ARROW, 0, time[i], high[i]);
                        ObjectSetInteger(0, name, OBJPROP_COLOR, BearDivColor);
                        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
                        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234); // Down arrow
                        break;
                    }
                }
            }
        }
    }
    return(rates_total);
}
//+------------------------------------------------------------------+
//| End of RSI Divergence Indicator                                  |
//+------------------------------------------------------------------+ 