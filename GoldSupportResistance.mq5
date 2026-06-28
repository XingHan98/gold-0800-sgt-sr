//+------------------------------------------------------------------+
//|                                     GoldSupportResistance.mq5     |
//|  Draws daily support & resistance lines for XAU/USD at 08:00 SGT  |
//|                                                                  |
//|  Logic (5-min timeframe by default, Mon-Fri):                    |
//|   * 08:00 SGT == 00:00 UTC (Singapore has no DST).               |
//|   * Bar A starts as the 07:55 SGT candle (closes 00:00 UTC),     |
//|     Bar B as the 07:50 SGT candle (the one before it).           |
//|   * RESISTANCE: if Close(A) > High(B) -> resistance = High(B).   |
//|     Otherwise step back one interval (A:=B, B:=older)            |
//|     and compare again, until the condition is met.               |
//|   * SUPPORT: if Close(A) < Low(B) -> support = Low(B).           |
//|     Otherwise step back the same way until met.                  |
//|   The two searches are independent, both starting from the       |
//|   07:55 / 07:50 pair and walking backward one interval at a time.|
//|   Interval = InpTimeframe (default M5); change it to finetune.   |
//+------------------------------------------------------------------+
#property copyright "Gold S/R EA"
#property version   "1.00"
#property strict

//--- Inputs
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5; // Bar A/B interval (default 5-min)
input int    InpManualOffsetHours = 9999;   // Server->UTC offset in hours (9999 = auto-detect)
input int    InpLookbackBars      = 300;    // Max bars to walk back when searching
input color  InpResColor          = clrTomato;     // Resistance line color
input color  InpSupColor          = clrDodgerBlue; // Support line color
input int    InpLineWidth         = 2;      // Line width
input bool   InpDrawWeekends      = false;  // Draw on Sat/Sun (gold normally closed)

//--- State
datetime g_lastDrawnDay = 0;   // UTC midnight of the day we last drew for

//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(30);          // check twice a minute; cheap and reliable
   TryDrawForToday();          // attempt immediately on load
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   TryDrawForToday();
  }
//+------------------------------------------------------------------+
//| Returns seconds the trade server is ahead of UTC                 |
//+------------------------------------------------------------------+
int ServerToUTCOffsetSec()
  {
   if(InpManualOffsetHours != 9999)
      return(InpManualOffsetHours * 3600);

   // Auto: difference between server time and GMT, rounded to the hour
   long diff = (long)TimeCurrent() - (long)TimeGMT();
   long hours = (long)MathRound((double)diff / 3600.0);
   return((int)(hours * 3600));
  }
//+------------------------------------------------------------------+
//| Main entry: draw today's lines once, if due                      |
//+------------------------------------------------------------------+
void TryDrawForToday()
  {
   datetime utcNow      = TimeGMT();
   datetime utcMidnight = utcNow - (utcNow % 86400);   // today's 00:00 UTC = 08:00 SGT

   if(utcMidnight == g_lastDrawnDay)
      return;                                          // already handled today

   // Weekday in SGT == weekday of this UTC midnight (00:00 UTC = 08:00 SGT same date)
   MqlDateTime dt;
   TimeToStruct(utcMidnight, dt);
   bool isWeekend = (dt.day_of_week == 0 || dt.day_of_week == 6);
   if(isWeekend && !InpDrawWeekends)
     {
      g_lastDrawnDay = utcMidnight;                    // mark so we don't re-check all day
      return;
     }

   DrawLevels(utcMidnight);
   g_lastDrawnDay = utcMidnight;
  }
//+------------------------------------------------------------------+
//| Compute & draw support and resistance for the given UTC day      |
//+------------------------------------------------------------------+
void DrawLevels(datetime utcMidnight)
  {
   int    offset      = ServerToUTCOffsetSec();
   datetime srvAnchor = utcMidnight + offset;          // 08:00 SGT expressed in server time

   // Pull the bars just before the anchor (index 0 = newest = last bar before 08:00 SGT)
   int barSecs = PeriodSeconds(InpTimeframe);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   datetime fromTime = srvAnchor - (datetime)((InpLookbackBars + 5) * barSecs);
   int copied = CopyRates(_Symbol, InpTimeframe, fromTime, srvAnchor - 1, rates);
   if(copied < 2)
     {
      PrintFormat("S/R: not enough bars before %s (got %d)",
                  TimeToString(srvAnchor), copied);
      return;
     }

   int maxStep = MathMin(InpLookbackBars, copied - 2);

   //--- Resistance: walk back until Close(A) > High(B)
   double   resistance  = 0.0;
   bool     resFound    = false;
   datetime resBarTime  = 0;             // server time of Bar B that set the level
   for(int k = 0; k <= maxStep; k++)
     {
      double closeA = rates[k].close;       // Bar A
      double highB  = rates[k + 1].high;    // Bar B (older neighbour)
      if(closeA > highB)
        {
         resistance = highB;
         resBarTime = rates[k + 1].time;
         resFound   = true;
         break;
        }
     }

   //--- Support: walk back until Close(A) < Low(B)
   double   support    = 0.0;
   bool     supFound   = false;
   datetime supBarTime = 0;             // server time of Bar B that set the level
   for(int k = 0; k <= maxStep; k++)
     {
      double closeA = rates[k].close;       // Bar A
      double lowB   = rates[k + 1].low;     // Bar B (older neighbour)
      if(closeA < lowB)
        {
         support    = lowB;
         supBarTime = rates[k + 1].time;
         supFound   = true;
         break;
        }
     }

   string dayTag = TimeToString(utcMidnight, TIME_DATE);
   // The lines represent the 08:00 SGT level for this day:
   string drawTimeStr = TimeToString(srvAnchor, TIME_DATE | TIME_MINUTES) + " (08:00 SGT)";

   if(resFound)
      DrawLine("SR_RES_" + dayTag, "R", resistance, srvAnchor, InpResColor, drawTimeStr);
   else
      PrintFormat("S/R %s: resistance not found within %d bars", dayTag, maxStep);

   if(supFound)
      DrawLine("SR_SUP_" + dayTag, "S", support, srvAnchor, InpSupColor, drawTimeStr);
   else
      PrintFormat("S/R %s: support not found within %d bars", dayTag, maxStep);

   // Log: price, the 08:00 SGT anchor the line marks, the source bar, and wall-clock draw time
   PrintFormat("S/R for %s | resistance=%s (from bar %s) | support=%s (from bar %s) | line time=%s | computed at %s server (offset=%dh)",
               dayTag,
               resFound ? DoubleToString(resistance, _Digits) : "n/a",
               resFound ? TimeToString(resBarTime, TIME_DATE | TIME_MINUTES) : "n/a",
               supFound ? DoubleToString(support, _Digits)    : "n/a",
               supFound ? TimeToString(supBarTime, TIME_DATE | TIME_MINUTES) : "n/a",
               drawTimeStr,
               TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
               offset / 3600);
  }
//+------------------------------------------------------------------+
//| Draw a horizontal segment + a price/time label on the chart      |
//|   prefix:  "R" or "S"                                            |
//|   timeStr: the 08:00 SGT time the line represents                |
//+------------------------------------------------------------------+
void DrawLine(string name, string prefix, double price, datetime fromT, color clr, string timeStr)
  {
   string priceStr = DoubleToString(price, _Digits);
   string caption  = prefix + " " + priceStr + "  @ " + timeStr;

   //--- the line itself
   datetime toT = fromT + 86400;           // span ~24h forward from 08:00 SGT
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, fromT, price, toT, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT, caption);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, caption);

   //--- a text label anchored at the left end of the line showing price + time
   string lblName = name + "_lbl";
   ObjectDelete(0, lblName);
   ObjectCreate(0, lblName, OBJ_TEXT, 0, fromT, price);
   ObjectSetString (0, lblName, OBJPROP_TEXT, caption);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
  }
//+------------------------------------------------------------------+
