//+------------------------------------------------------------------+
//|                                                    RSI_With_SMA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot RSI
#property indicator_label1  "RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot RSI_SMA
#property indicator_label2  "RSI_SMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- input parameters
input int                 RSI_Period=14;          // RSI Period
input int                 SMA_Period=14;          // SMA Period
input ENUM_APPLIED_PRICE  RSI_Price=PRICE_CLOSE;  // RSI Price

//--- indicator buffers
double         RSIBuffer[];
double         RSI_SMABuffer[];

//--- handles
int    rsi_handle;
int    ma_handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0,RSIBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,RSI_SMABuffer,INDICATOR_DATA);

   //--- set accuracy
   IndicatorSetInteger(INDICATOR_DIGITS,2);

   //--- set levels
   IndicatorSetInteger(INDICATOR_LEVELS,3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE,0,70);
   IndicatorSetDouble(INDICATOR_LEVELVALUE,1,50);
   IndicatorSetDouble(INDICATOR_LEVELVALUE,2,30);

   IndicatorSetString(INDICATOR_SHORTNAME,"RSI("+string(RSI_Period)+") SMA("+string(SMA_Period)+")");

   //--- create handles
   rsi_handle=iRSI(_Symbol,PERIOD_CURRENT,RSI_Period,RSI_Price);
   ma_handle=iMA(_Symbol,PERIOD_CURRENT,SMA_Period,0,MODE_SMA,rsi_handle);

   //--- check handles
   if(rsi_handle==INVALID_HANDLE || ma_handle==INVALID_HANDLE)
   {
      Print("Failed to create handles of the indicators");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                                |
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
   if(rates_total<RSI_Period) return(0);

   int calculated=BarsCalculated(rsi_handle);
   if(calculated<rates_total)
   {
      Print("Not all data of RSI is calculated (",calculated," bars). Error ",GetLastError());
      return(0);
   }

   calculated=BarsCalculated(ma_handle);
   if(calculated<rates_total)
   {
      Print("Not all data of MA is calculated (",calculated," bars). Error ",GetLastError());
      return(0);
   }

   int to_copy;
   if(prev_calculated>rates_total || prev_calculated<0) to_copy=rates_total;
   else
   {
      to_copy=rates_total-prev_calculated;
      if(prev_calculated>0) to_copy++;
   }

   if(CopyBuffer(rsi_handle,0,0,to_copy,RSIBuffer)<=0)
   {
      Print("Failed to copy data from RSI indicator, error ",GetLastError());
      return(0);
   }

   if(CopyBuffer(ma_handle,0,0,to_copy,RSI_SMABuffer)<=0)
   {
      Print("Failed to copy data from MA indicator, error ",GetLastError());
      return(0);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsi_handle!=INVALID_HANDLE)
      IndicatorRelease(rsi_handle);
   if(ma_handle!=INVALID_HANDLE)
      IndicatorRelease(ma_handle);
}
