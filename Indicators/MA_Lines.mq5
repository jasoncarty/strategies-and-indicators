#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot FastMA
#property indicator_label1  "FastMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot SlowMA
#property indicator_label2  "SlowMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- input parameters
input int FastMA_Period=20;   // Fast MA Period
input int SlowMA_Period=50;   // Slow MA Period

//--- indicator buffers
double FastMABuffer[];
double SlowMABuffer[];

//--- handles for our moving averages
int FastMAHandle;
int SlowMAHandle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0,FastMABuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SlowMABuffer,INDICATOR_DATA);

   //--- set accuracy
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   //--- set labels
   PlotIndexSetString(0,PLOT_LABEL,"Fast MA("+IntegerToString(FastMA_Period)+")");
   PlotIndexSetString(1,PLOT_LABEL,"Slow MA("+IntegerToString(SlowMA_Period)+")");

   //--- create MA handles
   FastMAHandle=iMA(_Symbol,PERIOD_CURRENT,FastMA_Period,0,MODE_SMA,PRICE_CLOSE);
   SlowMAHandle=iMA(_Symbol,PERIOD_CURRENT,SlowMA_Period,0,MODE_SMA,PRICE_CLOSE);

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
   //--- check for rates total
   if(rates_total<1) return(0);

   //--- copy MA values
   if(CopyBuffer(FastMAHandle,0,0,rates_total,FastMABuffer)<=0) return(0);
   if(CopyBuffer(SlowMAHandle,0,0,rates_total,SlowMABuffer)<=0) return(0);

   //--- return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(FastMAHandle!=INVALID_HANDLE) IndicatorRelease(FastMAHandle);
   if(SlowMAHandle!=INVALID_HANDLE) IndicatorRelease(SlowMAHandle);
}
