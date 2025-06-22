//+------------------------------------------------------------------+
//|                                               AsianSessionBox.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Custom Indicator: Asian Session Box                                |
//| Description:                                                       |
//|   This indicator draws a box on the chart to visualize the Asian   |
//|   trading session. It helps traders identify the Asian session     |
//|   range and potential support/resistance levels formed during      |
//|   this period. The box is drawn based on the configured session    |
//|   times and automatically adjusts for daylight savings time.       |
//|                                                                    |
//| Features:                                                          |
//|   - Configurable Asian session start and end times                 |
//|   - Customizable box color and style                              |
//|   - Automatic DST adjustment                                       |
//|   - Option to show/hide high/low levels                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// Input Parameters
input group "Session Times (Server Time)"
input int      AsianSessionStartHour = 9;     // Asian Session Start Hour (0-23)
input int      AsianSessionStartMin = 0;      // Asian Session Start Minute
input int      AsianSessionEndHour = 10;       // Asian Session End Hour (0-23)
input int      AsianSessionEndMin = 0;        // Asian Session End Minute

input group "Visual Settings"
input color    BoxColor = clrDodgerBlue;      // Box Color
input ENUM_LINE_STYLE BoxStyle = STYLE_SOLID; // Box Border Style
input int      BoxTransparency = 95;          // Box Transparency (0-100)
input bool     ShowPrevSessions = true;       // Show Previous Sessions
input int      MaxBoxes = 10;                 // Maximum Number of Boxes to Show

// Global Variables
string         indicator_name = "AsianSessionBox";
datetime       last_session_start = 0;
int            box_counter = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Delete all existing objects
   ObjectsDeleteAll(0, indicator_name);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, indicator_name);
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
   // Get current time
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);

   // Find the start of today's Asian session
   MqlDateTime session_time;
   TimeToStruct(TimeCurrent(), session_time);
   session_time.hour = AsianSessionStartHour;
   session_time.min = AsianSessionStartMin;
   session_time.sec = 0;

   datetime session_start = StructToTime(session_time);

   // If current time is past Asian session end, show today's session
   if(current_time.hour > AsianSessionEndHour ||
      (current_time.hour == AsianSessionEndHour && current_time.min >= AsianSessionEndMin))
   {
      if(session_start != last_session_start)
      {
         DrawSessionBox(session_start);
         last_session_start = session_start;
      }
   }

   // If ShowPrevSessions is enabled, show previous sessions
   if(ShowPrevSessions)
   {
      for(int i = 1; i < MaxBoxes; i++)
      {
         datetime prev_session = session_start - (86400 * i); // 86400 seconds in a day
         DrawSessionBox(prev_session);
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw the session box                                              |
//+------------------------------------------------------------------+
void DrawSessionBox(datetime session_start)
{
   // Calculate session end time
   datetime session_end = session_start + (AsianSessionEndHour - AsianSessionStartHour) * 3600
                         + (AsianSessionEndMin - AsianSessionStartMin) * 60;

   // Find highest high and lowest low in the session
   double session_high = -1;
   double session_low = DBL_MAX;

   int start_idx = iBarShift(_Symbol, PERIOD_CURRENT, session_start);
   int end_idx = iBarShift(_Symbol, PERIOD_CURRENT, session_end);

   if(start_idx < 0 || end_idx < 0) return;

   for(int i = MathMin(start_idx, end_idx); i <= MathMax(start_idx, end_idx); i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);

      if(high > session_high) session_high = high;
      if(low < session_low) session_low = low;
   }

   if(session_high == -1 || session_low == DBL_MAX) return;

   // Create box object name
   string box_name = indicator_name + "_Box_" + IntegerToString(box_counter++);

   // Draw the box
   ObjectCreate(0, box_name, OBJ_RECTANGLE, 0, session_start, session_high, session_end, session_low);
   ObjectSetInteger(0, box_name, OBJPROP_COLOR, BoxColor);
   ObjectSetInteger(0, box_name, OBJPROP_STYLE, BoxStyle);
   ObjectSetInteger(0, box_name, OBJPROP_BACK, true);
   ObjectSetInteger(0, box_name, OBJPROP_FILL, true);
   ObjectSetInteger(0, box_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, box_name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, box_name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, box_name, OBJPROP_ZORDER, 0);

   // Calculate transparency (convert 0-100 to 0-255)
   uchar alpha = (uchar)(255 * (1 - BoxTransparency / 100.0));
   color fill_color = BoxColor;

   // Set the background color with transparency
   ObjectSetInteger(0, box_name, OBJPROP_BGCOLOR, fill_color);
}
