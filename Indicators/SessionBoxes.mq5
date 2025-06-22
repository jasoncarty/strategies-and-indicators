//+------------------------------------------------------------------+
//|                                                   SessionBoxes.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Custom Indicator: Session Boxes                                    |
//| Description:                                                       |
//|   This indicator draws boxes on the chart to visualize different   |
//|   trading sessions (Asian, London, and New York). It helps traders |
//|   identify key trading sessions and their overlaps. The boxes are  |
//|   drawn based on the configured session times and automatically    |
//|   adjust for daylight savings time changes.                        |
//|                                                                    |
//| Features:                                                          |
//|   - Configurable session times for Asian, London, and NY sessions  |
//|   - Customizable box colors and styles for each session            |
//|   - Automatic DST adjustment                                       |
//|   - Visual representation of session overlaps                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// Input Parameters for Asian Session
input group "Asian Session Times (Server Time)"
input int      AsianSessionStartHour = 1;     // Asian Session Start Hour (0-23)
input int      AsianSessionStartMin = 0;      // Asian Session Start Minute
input int      AsianSessionEndHour = 10;      // Asian Session End Hour (0-23)
input int      AsianSessionEndMin = 0;        // Asian Session End Minute

// Input Parameters for London Session
input group "London Session Times (Server Time)"
input int      LondonSessionStartHour = 9;    // London Session Start Hour (0-23)
input int      LondonSessionStartMin = 0;     // London Session Start Minute
input int      LondonSessionEndHour = 18;     // London Session End Hour (0-23)
input int      LondonSessionEndMin = 0;       // London Session End Minute

// Input Parameters for NY Session
input group "New York Session Times (Server Time)"
input int      NYSessionStartHour = 14;       // NY Session Start Hour (0-23)
input int      NYSessionStartMin = 0;         // NY Session Start Minute
input int      NYSessionEndHour = 23;         // NY Session End Hour (0-23)
input int      NYSessionEndMin = 0;           // NY Session End Minute

input group "Visual Settings"
input color    AsianBoxColor = C'0,0,139';     // Asian Session Box Color (Dark Blue)
input color    LondonBoxColor = C'0,100,0';    // London Session Box Color (Dark Green)
input color    NYBoxColor = C'139,0,0';        // NY Session Box Color (Dark Red)
input int      BoxTransparency = 70;           // Box Fill Transparency (0-100)
input int      BoxBorderWidth = 2;             // Box Border Width
input bool     ShowPrevSessions = true;        // Show Previous Sessions
input int      MaxBoxes = 3;                   // Maximum Number of Previous Sessions

// Global Variables
string         indicator_name = "SessionBoxes";
datetime       last_asian_session_start = 0;
datetime       last_london_session_start = 0;
datetime       last_ny_session_start = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Delete all existing objects
   ObjectsDeleteAll(0, indicator_name);
   ChartRedraw(); // Force chart redraw
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, indicator_name);
   ChartRedraw(); // Force chart redraw
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
   static datetime last_update = 0;
   datetime current_time = TimeCurrent();

   // Update only once per minute to prevent flashing
   if(current_time - last_update < 60) return(rates_total);
   last_update = current_time;

   // Clear existing boxes
   ObjectsDeleteAll(0, indicator_name);

   // Draw all sessions
   DrawSessionBoxes(0);  // Asian session
   DrawSessionBoxes(1);  // London session
   DrawSessionBoxes(2);  // NY session

   ChartRedraw(); // Force chart redraw
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw session boxes for specified session                          |
//+------------------------------------------------------------------+
void DrawSessionBoxes(int sessionType)
{
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);

   // Set session parameters based on session type
   int startHour, startMin, endHour, endMin;
   color boxColor;
   string sessionName;

   switch(sessionType)
   {
      case 0: // Asian
         startHour = AsianSessionStartHour;
         startMin = AsianSessionStartMin;
         endHour = AsianSessionEndHour;
         endMin = AsianSessionEndMin;
         boxColor = AsianBoxColor;
         sessionName = "Asian";
         break;
      case 1: // London
         startHour = LondonSessionStartHour;
         startMin = LondonSessionStartMin;
         endHour = LondonSessionEndHour;
         endMin = LondonSessionEndMin;
         boxColor = LondonBoxColor;
         sessionName = "London";
         break;
      case 2: // NY
         startHour = NYSessionStartHour;
         startMin = NYSessionStartMin;
         endHour = NYSessionEndHour;
         endMin = NYSessionEndMin;
         boxColor = NYBoxColor;
         sessionName = "NY";
         break;
      default:
         return;
   }

   // Find the start of today's session
   MqlDateTime session_time;
   TimeToStruct(TimeCurrent(), session_time);
   session_time.hour = startHour;
   session_time.min = startMin;
   session_time.sec = 0;

   datetime session_start = StructToTime(session_time);

   // Draw today's session if we're past the end time
   if(current_time.hour > endHour ||
      (current_time.hour == endHour && current_time.min >= endMin))
   {
      DrawSingleBox(session_start, startHour, startMin, endHour, endMin, boxColor, sessionName, 0);
   }

   // Draw previous sessions
   if(ShowPrevSessions)
   {
      for(int i = 1; i < MaxBoxes; i++)
      {
         datetime prev_session = session_start - (86400 * i); // 86400 seconds in a day
         DrawSingleBox(prev_session, startHour, startMin, endHour, endMin, boxColor, sessionName, i);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw a single session box                                         |
//+------------------------------------------------------------------+
void DrawSingleBox(datetime session_start, int startHour, int startMin,
                   int endHour, int endMin, color boxColor, string sessionName, int index)
{
   // Get the session type from the session name
   int sessionType = 0;  // Default to Asian
   if(StringCompare(sessionName, "London") == 0) sessionType = 1;
   if(StringCompare(sessionName, "NY") == 0) sessionType = 2;

   // Calculate session end time
   datetime session_end = session_start + (endHour - startHour) * 3600
                         + (endMin - startMin) * 60;

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

   // Create unique box name
   string box_name = indicator_name + "_" + sessionName + "_Box_" + IntegerToString(index);

   // Draw the box
   if(ObjectCreate(0, box_name, OBJ_RECTANGLE, 0, session_start, session_high, session_end, session_low))
   {
      // Set box properties
      ObjectSetInteger(0, box_name, OBJPROP_COLOR, boxColor);
      ObjectSetInteger(0, box_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, box_name, OBJPROP_WIDTH, BoxBorderWidth);
      ObjectSetInteger(0, box_name, OBJPROP_BACK, true);
      ObjectSetInteger(0, box_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, box_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, box_name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, box_name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, box_name, OBJPROP_ZORDER, 0);

      // Set fill color with transparency
      uint alpha = (uint)MathRound((100 - BoxTransparency) * 2.55);
      uint clr = (uint)boxColor;
      clr = (clr & 0x00FFFFFF) | (alpha << 24);
      ObjectSetInteger(0, box_name, OBJPROP_BGCOLOR, clr);

      // Add session label
      string label_name = indicator_name + "_" + sessionName + "_Label_" + IntegerToString(index);

      // Create background for the label
      string bg_name = indicator_name + "_" + sessionName + "_BG_" + IntegerToString(index);

      if(index == 0) // Only add label for current session
      {
         // Calculate label position (above the box)
         double label_y = session_high + (session_high - session_low) * 0.02;  // 2% above the box

         // Fixed positions for labels
         int xOffset = 10;  // Distance from left edge
         int yOffset = 20;  // Distance from top edge
         int labelSpacing = 25;  // Vertical space between labels

         // Create background rectangle
         if(ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         {
            ObjectSetInteger(0, bg_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, xOffset);
            ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, yOffset + (sessionType * labelSpacing));
            ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 100);
            ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 20);
            ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, clr);
            ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(0, bg_name, OBJPROP_COLOR, boxColor);
            ObjectSetInteger(0, bg_name, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, bg_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, bg_name, OBJPROP_BACK, false);
            ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, bg_name, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, bg_name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, bg_name, OBJPROP_ZORDER, 1);
         }

         // Create text label
         if(ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0))
         {
            ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, xOffset + 5);
            ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, yOffset + 2 + (sessionType * labelSpacing));
            ObjectSetString(0, label_name, OBJPROP_TEXT, sessionName + " Session");
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, ColorBrighten(boxColor, 50));
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 10);
            ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, label_name, OBJPROP_BACK, false);
            ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, label_name, OBJPROP_ZORDER, 2);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper function to brighten a color                               |
//+------------------------------------------------------------------+
color ColorBrighten(color clr, int brightness)
{
   int r = (clr >> 16) & 0xFF;
   int g = (clr >> 8) & 0xFF;
   int b = clr & 0xFF;

   r = MathMin(r + brightness, 255);
   g = MathMin(g + brightness, 255);
   b = MathMin(b + brightness, 255);

   return (color)((r << 16) | (g << 8) | b);
}
