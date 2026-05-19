//+------------------------------------------------------------------+
//|   TONO_CONFLUENCE_MASTER_XAU_v6_10_4_VISUAL_CLUTTER_CONTROL.mq5 |
//|        Clean rebuild: Confluence Panel + Supply Demand Zones      |
//|        Designed for XAUUSD / XAUUSD.m M5 visual monitoring        |
//+------------------------------------------------------------------+
#property copyright "TONO / ChatGPT"
#property version   "6.104"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_TONO_MODE
{
   MODE_SAFE = 0,
   MODE_BALANCED = 1,
   MODE_AGGRESSIVE = 2
};

enum ENUM_SD_ZONE_TYPE
{
   ZONE_SUPPLY = 0,
   ZONE_DEMAND = 1
};

//====================================================================
// INPUTS
//====================================================================
input group "=== GENERAL ==="
input ENUM_TONO_MODE Inp_Mode                 = MODE_BALANCED;
input bool           Inp_Enable_AutoTrade     = false;
input bool           Inp_Use_Closed_Candle    = false;      // false = faster panel status
input ulong          Inp_Magic                = 6102026;
input double         Inp_LotSize              = 0.01;
input int            Inp_MaxSpreadPoints      = 55;
input int            Inp_MinBarsBetweenTrades = 5;

input group "=== FIXED SL/TP ==="
input int            Inp_StopLoss_Points      = 100;
input int            Inp_TakeProfit_Points    = 100;
input bool           Inp_Use_Breakeven        = true;
input int            Inp_BE_Start_Points      = 60;
input int            Inp_BE_Lock_Points       = 10;
input bool           Inp_Use_Trailing         = true;
input int            Inp_Trail_Start_Points   = 80;
input int            Inp_Trail_DistancePoints = 45;

input group "=== CONFLUENCE INDICATORS ==="
input int            Inp_EMA_Period           = 34;
input int            Inp_RSI_Period           = 9;
input int            Inp_MACD_Fast            = 8;
input int            Inp_MACD_Slow            = 21;
input int            Inp_MACD_Signal          = 9;
input int            Inp_Stoch_K              = 5;
input int            Inp_Stoch_D              = 3;
input int            Inp_Stoch_Slowing        = 3;
input int            Inp_ADX_Period           = 10;
input int            Inp_CustomScoreThreshold = 0;          // 0 = auto by mode
input int            Inp_CustomADXMin         = 0;          // 0 = auto by mode

input group "=== SUPPLY DEMAND VISUAL ==="
input bool           Inp_Draw_SupplyDemand    = true;
input bool           Inp_SD_Show_Zone_Boxes   = true;       // show colored supply/demand rectangles
input bool           Inp_SD_Show_Boundary_Lines = true;     // show top/bottom horizontal segments
input bool           Inp_SD_Show_Backup_HLines  = false;    // false = cleaner chart, true = full-width price lines
input bool           Inp_SD_Show_Only_Nearest = true;       // true = only S1 + D1, less crowded
input int            Inp_SD_Lookback_Bars     = 160;
input int            Inp_SD_Pivot_LR          = 2;          // lower = faster zones
input int            Inp_SD_Max_Zones_Each    = 2;          // 1 or 2 recommended
input int            Inp_SD_Extend_Bars_Right = 48;
input double         Inp_SD_Impulse_ATR_Mult  = 0.80;       // lower = more zones
input double         Inp_SD_Min_Zone_ATR_Mult = 0.15;
input bool           Inp_SD_Show_Labels       = true;
input bool           Inp_SD_Show_Midline      = false;      // default off to avoid crowded chart
input bool           Inp_SD_Filter_Entries    = false;      // false = visual only
input bool           Inp_SD_Block_Buy_Near_Supply  = true;
input bool           Inp_SD_Block_Sell_Near_Demand = true;
input double         Inp_SD_Near_ATR_Mult     = 0.25;

input group "=== PANEL VISUAL ==="
input bool           Inp_Show_Panel           = true;
input int            Inp_Panel_X              = 15;
input int            Inp_Panel_Y              = 135;
input int            Inp_Panel_Width          = 460;
input int            Inp_Panel_Height         = 520;
input int            Inp_Timer_Seconds        = 1;
input bool           Inp_Show_Debug_Detail    = true;       // expanded multi-line debug
input bool           Inp_Chart_Auto_Clean     = true;

//====================================================================
// COLORS
//====================================================================
color C_BG       = C'16,18,22';
color C_BOX      = C'28,31,38';
color C_BORDER   = C'58,64,78';
color C_TEXT     = clrWhite;
color C_MUTED    = C'155,160,170';
color C_BUY      = C'0,210,210';
color C_SELL     = C'255,65,95';
color C_WARN     = C'255,190,65';
color C_OK       = C'70,220,120';
color C_SUPPLY   = C'255,75,75';
color C_DEMAND   = C'90,190,255';
color C_MID      = C'120,150,255';

//====================================================================
// GLOBALS
//====================================================================
string   G_PREFIX;
int      hEMA = INVALID_HANDLE, hRSI = INVALID_HANDLE, hMACD = INVALID_HANDLE;
int      hStoch = INVALID_HANDLE, hADX = INVALID_HANDLE, hATR = INVALID_HANDLE;

double   bEMA[], bRSI[], bMACDMain[], bMACDSignal[], bStochMain[], bStochSignal[], bADX[], bATR[];
datetime G_lastBarTime = 0;
datetime G_lastTradeBarTime = 0;

struct SDZone
{
   bool     valid;
   int      type;
   datetime t_left;
   datetime t_right;
   double   top;
   double   bottom;
   double   mid;
   int      bar_index;
};

SDZone G_supply[4];
SDZone G_demand[4];
string G_status = "INIT";
string G_debug  = "Loading...";
string G_zoneStatus = "INIT";
bool   G_buffersReady = false;
double G_buyScore = 0.0;
double G_sellScore = 0.0;
double G_nearestSupplyTop = 0.0;
double G_nearestSupplyBottom = 0.0;
double G_nearestDemandTop = 0.0;
double G_nearestDemandBottom = 0.0;

//====================================================================
// UTILS
//====================================================================
int ModeThreshold()
{
   if(Inp_CustomScoreThreshold > 0) return Inp_CustomScoreThreshold;
   if(Inp_Mode == MODE_SAFE) return 74;
   if(Inp_Mode == MODE_AGGRESSIVE) return 58;
   return 66;
}

int ModeADXMin()
{
   if(Inp_CustomADXMin > 0) return Inp_CustomADXMin;
   if(Inp_Mode == MODE_SAFE) return 22;
   if(Inp_Mode == MODE_AGGRESSIVE) return 14;
   return 18;
}

string ModeText()
{
   if(Inp_Mode == MODE_SAFE) return "SAFE";
   if(Inp_Mode == MODE_AGGRESSIVE) return "AGGRESSIVE";
   return "BALANCED";
}

int SigShift()
{
   return Inp_Use_Closed_Candle ? 1 : 0;
}

int SpreadPoints()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

void ResetZones()
{
   for(int i=0; i<4; i++)
   {
      G_supply[i].valid=false;
      G_demand[i].valid=false;
   }
   G_nearestSupplyTop = 0; G_nearestSupplyBottom = 0;
   G_nearestDemandTop = 0; G_nearestDemandBottom = 0;
}

void DeleteByPrefix(string pfx)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, pfx) == 0)
         ObjectDelete(0, name);
   }
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != G_lastBarTime)
   {
      G_lastBarTime = t;
      return true;
   }
   return false;
}

//====================================================================
// INIT / DEINIT
//====================================================================
int OnInit()
{
   G_PREFIX = "TONO_CM6104_" + IntegerToString((int)ChartID()) + "_";

   trade.SetExpertMagicNumber(Inp_Magic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(Inp_Chart_Auto_Clean)
   {
      ChartSetInteger(0, CHART_FOREGROUND, false);
      ChartSetInteger(0, CHART_SHIFT, true);
      ChartSetInteger(0, CHART_SHOW_GRID, false);
   }

   hEMA   = iMA(_Symbol, _Period, Inp_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, Inp_RSI_Period, PRICE_CLOSE);
   hMACD  = iMACD(_Symbol, _Period, Inp_MACD_Fast, Inp_MACD_Slow, Inp_MACD_Signal, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, _Period, Inp_Stoch_K, Inp_Stoch_D, Inp_Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   hADX   = iADX(_Symbol, _Period, Inp_ADX_Period);
   hATR   = iATR(_Symbol, _Period, 14);

   if(hEMA==INVALID_HANDLE || hRSI==INVALID_HANDLE || hMACD==INVALID_HANDLE || hStoch==INVALID_HANDLE || hADX==INVALID_HANDLE || hATR==INVALID_HANDLE)
   {
      Print("INIT FAILED: one or more indicator handles invalid.");
      return INIT_FAILED;
   }

   ArraySetAsSeries(bEMA,true); ArraySetAsSeries(bRSI,true);
   ArraySetAsSeries(bMACDMain,true); ArraySetAsSeries(bMACDSignal,true);
   ArraySetAsSeries(bStochMain,true); ArraySetAsSeries(bStochSignal,true);
   ArraySetAsSeries(bADX,true); ArraySetAsSeries(bATR,true);

   if(Inp_Show_Panel) CreatePanel();

   EventSetTimer(MathMax(1, Inp_Timer_Seconds));
   G_status = "LOADING";
   G_debug = "Indicator buffers loading...";
   UpdateAll();
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteByPrefix(G_PREFIX);
   if(hEMA!=INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

void OnTick()
{
   ManageOpenPosition();
   bool nb = IsNewBar();
   UpdateAll();
   if(nb && Inp_Enable_AutoTrade)
      TryAutoTrade();
}

void OnTimer()
{
   UpdateAll();
}

//====================================================================
// DATA UPDATE
//====================================================================
bool UpdateBuffers()
{
   int need = 5;
   if(CopyBuffer(hEMA,0,0,need,bEMA) < need) return false;
   if(CopyBuffer(hRSI,0,0,need,bRSI) < need) return false;
   if(CopyBuffer(hMACD,0,0,need,bMACDMain) < need) return false;
   if(CopyBuffer(hMACD,1,0,need,bMACDSignal) < need) return false;
   if(CopyBuffer(hStoch,0,0,need,bStochMain) < need) return false;
   if(CopyBuffer(hStoch,1,0,need,bStochSignal) < need) return false;
   if(CopyBuffer(hADX,0,0,need,bADX) < need) return false;
   if(CopyBuffer(hATR,0,0,need,bATR) < need) return false;
   return true;
}

void UpdateAll()
{
   G_buffersReady = UpdateBuffers();

   // Visual layer must still appear even while indicators are loading.
   // Previous build called UpdatePanel() while arrays were empty, causing panel/zone updates to silently fail.
   if(!G_buffersReady)
   {
      G_status = "LOADING";
      G_debug  = "WAIT: indicator buffer loading | visual fallback active";
      G_buyScore = 0;
      G_sellScore = 0;

      if(Inp_Draw_SupplyDemand)
      {
         FindFallbackZonesOnly();
         DrawSupplyDemandZones();
      }

      if(Inp_Show_Panel) UpdatePanel();
      ChartRedraw();
      return;
   }

   CalculateScores();
   if(Inp_Draw_SupplyDemand)
   {
      FindSupplyDemandZones();
      DrawSupplyDemandZones();
   }
   EvaluateStatus();
   if(Inp_Show_Panel) UpdatePanel();
   ChartRedraw();
}

//====================================================================
// CONFLUENCE SCORE
//====================================================================
void CalculateScores()
{
   int s = SigShift();
   double close = iClose(_Symbol, _Period, s);
   G_buyScore = 0; G_sellScore = 0;

   bool emaBull   = close > bEMA[s];
   bool macdBull  = bMACDMain[s] > bMACDSignal[s];
   bool rsiBull   = bRSI[s] > 50.0;
   bool stochBull = bStochMain[s] > bStochSignal[s];
   bool adxOK     = bADX[s] >= ModeADXMin();

   if(emaBull) G_buyScore += 28; else G_sellScore += 28;
   if(macdBull) G_buyScore += 24; else G_sellScore += 24;
   if(rsiBull) G_buyScore += 18; else G_sellScore += 18;
   if(stochBull) G_buyScore += 16; else G_sellScore += 16;

   if(adxOK)
   {
      if(G_buyScore >= G_sellScore) G_buyScore += 14;
      else G_sellScore += 14;
   }
}

//====================================================================
// SUPPLY DEMAND ZONE DETECTION
//====================================================================
bool IsPivotHigh(int bar, int lr)
{
   double h = iHigh(_Symbol,_Period,bar);
   for(int k=1; k<=lr; k++)
   {
      if(iHigh(_Symbol,_Period,bar-k) > h) return false;
      if(iHigh(_Symbol,_Period,bar+k) >= h) return false;
   }
   return true;
}

bool IsPivotLow(int bar, int lr)
{
   double l = iLow(_Symbol,_Period,bar);
   for(int k=1; k<=lr; k++)
   {
      if(iLow(_Symbol,_Period,bar-k) < l) return false;
      if(iLow(_Symbol,_Period,bar+k) <= l) return false;
   }
   return true;
}

bool HasBearishImpulseAfter(int bar, double atr)
{
   double pivotLow = iLow(_Symbol,_Period,bar);
   int maxLook = MathMin(8, bar-1);
   for(int j=1; j<=maxLook; j++)
   {
      double newerLow = iLow(_Symbol,_Period,bar-j);
      if((pivotLow - newerLow) >= atr * Inp_SD_Impulse_ATR_Mult)
         return true;
   }
   return false;
}

bool HasBullishImpulseAfter(int bar, double atr)
{
   double pivotHigh = iHigh(_Symbol,_Period,bar);
   int maxLook = MathMin(8, bar-1);
   for(int j=1; j<=maxLook; j++)
   {
      double newerHigh = iHigh(_Symbol,_Period,bar-j);
      if((newerHigh - pivotHigh) >= atr * Inp_SD_Impulse_ATR_Mult)
         return true;
   }
   return false;
}

void AddZone(SDZone &arr[], int idx, int type, int bar, double top, double bottom)
{
   if(top < bottom)
   {
      double tmp = top; top = bottom; bottom = tmp;
   }
   double atr = MathMax(SafeATR(), _Point * 100.0);
   double minH = atr * Inp_SD_Min_Zone_ATR_Mult;
   if((top-bottom) < minH)
   {
      if(type == ZONE_SUPPLY) bottom = top - minH;
      else top = bottom + minH;
   }

   arr[idx].valid     = true;
   arr[idx].type      = type;
   arr[idx].bar_index = bar;
   arr[idx].t_left    = iTime(_Symbol,_Period,bar);
   arr[idx].t_right   = iTime(_Symbol,_Period,0) + (datetime)(PeriodSeconds(_Period) * Inp_SD_Extend_Bars_Right);
   arr[idx].top       = NormalizePrice(top);
   arr[idx].bottom    = NormalizePrice(bottom);
   arr[idx].mid       = NormalizePrice((top+bottom)/2.0);
}

double SafeATR()
{
   if(G_buffersReady && ArraySize(bATR) > 0 && bATR[0] > 0)
      return bATR[0];
   return MathMax(_Point * 300.0, SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 300.0);
}

void AddZoneSafe(SDZone &arr[], int idx, int type, int bar, double top, double bottom)
{
   if(bar < 0) return;
   if(top < bottom)
   {
      double tmp = top; top = bottom; bottom = tmp;
   }

   double atr = SafeATR();
   double minH = MathMax(atr * Inp_SD_Min_Zone_ATR_Mult, _Point * 60.0);
   if((top-bottom) < minH)
   {
      if(type == ZONE_SUPPLY) bottom = top - minH;
      else top = bottom + minH;
   }

   arr[idx].valid     = true;
   arr[idx].type      = type;
   arr[idx].bar_index = bar;
   arr[idx].t_left    = iTime(_Symbol,_Period,bar);
   arr[idx].t_right   = iTime(_Symbol,_Period,0) + (datetime)(PeriodSeconds(_Period) * Inp_SD_Extend_Bars_Right);
   arr[idx].top       = NormalizePrice(top);
   arr[idx].bottom    = NormalizePrice(bottom);
   arr[idx].mid       = NormalizePrice((top+bottom)/2.0);
}

void FindFallbackZonesOnly()
{
   ResetZones();
   int bars = Bars(_Symbol,_Period);
   int lookback = MathMin(Inp_SD_Lookback_Bars, bars-5);
   if(lookback < 20)
   {
      G_zoneStatus = "WAIT DATA";
      return;
   }

   int hi = iHighest(_Symbol,_Period,MODE_HIGH,lookback,1);
   int lo = iLowest(_Symbol,_Period,MODE_LOW,lookback,1);

   if(hi >= 0)
   {
      double top = iHigh(_Symbol,_Period,hi);
      double bottom = MathMax(iOpen(_Symbol,_Period,hi), iClose(_Symbol,_Period,hi));
      AddZoneSafe(G_supply, 0, ZONE_SUPPLY, hi, top, bottom);
   }
   if(lo >= 0)
   {
      double bottom = iLow(_Symbol,_Period,lo);
      double top = MathMin(iOpen(_Symbol,_Period,lo), iClose(_Symbol,_Period,lo));
      AddZoneSafe(G_demand, 0, ZONE_DEMAND, lo, top, bottom);
   }

   G_nearestSupplyTop = G_supply[0].top;
   G_nearestSupplyBottom = G_supply[0].bottom;
   G_nearestDemandTop = G_demand[0].top;
   G_nearestDemandBottom = G_demand[0].bottom;
   G_zoneStatus = "FALLBACK";
}

void FindSupplyDemandZones()
{
   ResetZones();
   int bars = Bars(_Symbol,_Period);
   if(bars < Inp_SD_Lookback_Bars + Inp_SD_Pivot_LR + 10)
   {
      G_zoneStatus = "WAIT DATA";
      return;
   }

   int maxEach = MathMax(1, MathMin(2, Inp_SD_Max_Zones_Each));
   int supCount = 0, demCount = 0;
   int startBar = MathMax(Inp_SD_Pivot_LR + 2, 4);
   int endBar = MathMin(Inp_SD_Lookback_Bars, bars - Inp_SD_Pivot_LR - 2);

   for(int bar=startBar; bar<=endBar && (supCount<maxEach || demCount<maxEach); bar++)
   {
      double atrAt = MathMax(SafeATR(), _Point*100.0);

      if(supCount < maxEach && IsPivotHigh(bar, Inp_SD_Pivot_LR) && HasBearishImpulseAfter(bar, atrAt))
      {
         double top = iHigh(_Symbol,_Period,bar);
         double bodyLow = MathMax(iOpen(_Symbol,_Period,bar), iClose(_Symbol,_Period,bar));
         double bottom = bodyLow;
         AddZone(G_supply, supCount, ZONE_SUPPLY, bar, top, bottom);
         supCount++;
      }

      if(demCount < maxEach && IsPivotLow(bar, Inp_SD_Pivot_LR) && HasBullishImpulseAfter(bar, atrAt))
      {
         double bottom = iLow(_Symbol,_Period,bar);
         double bodyHigh = MathMin(iOpen(_Symbol,_Period,bar), iClose(_Symbol,_Period,bar));
         double top = bodyHigh;
         AddZone(G_demand, demCount, ZONE_DEMAND, bar, top, bottom);
         demCount++;
      }
   }

   // Fallback: guaranteed zone from highest/lowest if pivot logic finds nothing
   if(supCount == 0)
   {
      int hi = iHighest(_Symbol,_Period,MODE_HIGH,Inp_SD_Lookback_Bars,1);
      double top = iHigh(_Symbol,_Period,hi);
      double bottom = MathMax(iOpen(_Symbol,_Period,hi), iClose(_Symbol,_Period,hi));
      AddZone(G_supply, 0, ZONE_SUPPLY, hi, top, bottom);
      supCount = 1;
   }
   if(demCount == 0)
   {
      int lo = iLowest(_Symbol,_Period,MODE_LOW,Inp_SD_Lookback_Bars,1);
      double bottom = iLow(_Symbol,_Period,lo);
      double top = MathMin(iOpen(_Symbol,_Period,lo), iClose(_Symbol,_Period,lo));
      AddZone(G_demand, 0, ZONE_DEMAND, lo, top, bottom);
      demCount = 1;
   }

   G_nearestSupplyTop = G_supply[0].top;
   G_nearestSupplyBottom = G_supply[0].bottom;
   G_nearestDemandTop = G_demand[0].top;
   G_nearestDemandBottom = G_demand[0].bottom;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double near = MathMax(SafeATR() * Inp_SD_Near_ATR_Mult, _Point * 50);
   bool nearSupply = (G_nearestSupplyBottom > 0 && price >= G_nearestSupplyBottom - near && price <= G_nearestSupplyTop + near);
   bool nearDemand = (G_nearestDemandTop > 0 && price <= G_nearestDemandTop + near && price >= G_nearestDemandBottom - near);

   if(nearSupply) G_zoneStatus = "NEAR SUPPLY";
   else if(nearDemand) G_zoneStatus = "NEAR DEMAND";
   else G_zoneStatus = "MID";
}

//====================================================================
// DRAWING SUPPLY DEMAND
//====================================================================
void DrawSupplyDemandZones()
{
   DeleteByPrefix(G_PREFIX + "SD_");

   int maxDraw = Inp_SD_Show_Only_Nearest ? 1 : 4;
   for(int i=0; i<maxDraw; i++)
   {
      if(G_supply[i].valid) DrawZone(G_supply[i], i);
      if(G_demand[i].valid) DrawZone(G_demand[i], i);
   }
}

void DrawZone(SDZone &z, int index)
{
   string kind = (z.type == ZONE_SUPPLY ? "SUP" : "DEM");
   color zcol = (z.type == ZONE_SUPPLY ? C_SUPPLY : C_DEMAND);
   int alpha  = (z.type == ZONE_SUPPLY ? 45 : 65);
   string base = G_PREFIX + "SD_" + kind + "_" + IntegerToString(index) + "_";

   // Rectangle zone. Can be disabled if you only want the debug panel without chart zones.
   if(Inp_SD_Show_Zone_Boxes)
   {
      string rect = base + "BOX";
      if(ObjectCreate(0, rect, OBJ_RECTANGLE, 0, z.t_left, z.top, z.t_right, z.bottom))
      {
         ObjectSetInteger(0, rect, OBJPROP_COLOR, ColorToARGB(zcol, alpha));
         ObjectSetInteger(0, rect, OBJPROP_FILL, true);
         ObjectSetInteger(0, rect, OBJPROP_BACK, true);
         ObjectSetInteger(0, rect, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rect, OBJPROP_HIDDEN, false);
      }
   }

   // Short top/bottom segments. Turn this off when the chart becomes too busy.
   if(Inp_SD_Show_Boundary_Lines)
   {
      DrawPriceLine(base + "TOP", z.t_left, z.t_right, z.top, zcol, index==0 ? STYLE_SOLID : STYLE_DOT, 2);
      DrawPriceLine(base + "BOT", z.t_left, z.t_right, z.bottom, zcol, index==0 ? STYLE_SOLID : STYLE_DOT, 2);
   }

   // Full-width HLINE backup. Default OFF because it can make the chart crowded.
   if(Inp_SD_Show_Backup_HLines)
   {
      DrawHLine(base + "H_TOP", z.top, zcol, index==0 ? STYLE_SOLID : STYLE_DOT, 1);
      DrawHLine(base + "H_BOT", z.bottom, zcol, index==0 ? STYLE_SOLID : STYLE_DOT, 1);
   }

   if(Inp_SD_Show_Midline)
   {
      if(Inp_SD_Show_Boundary_Lines)
         DrawPriceLine(base + "MID", z.t_left, z.t_right, z.mid, C_MID, STYLE_DASH, 1);
      if(Inp_SD_Show_Backup_HLines)
         DrawHLine(base + "H_MID", z.mid, C_MID, STYLE_DASH, 1);
   }

   if(Inp_SD_Show_Labels)
   {
      string labelTop = kind + ": " + DoubleToString(z.top, _Digits);
      string labelBot = kind + ": " + DoubleToString(z.bottom, _Digits);
      DrawPriceText(base + "TXT_TOP", z.t_right, z.top, labelTop, zcol);
      DrawPriceText(base + "TXT_BOT", z.t_right, z.bottom, labelBot, zcol);
   }
}

void DrawPriceLine(string name, datetime t1, datetime t2, double price, color col, ENUM_LINE_STYLE style, int width)
{
   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 30);
   }
}

void DrawHLine(string name, double price, color col, ENUM_LINE_STYLE style, int width)
{
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 35);
   }
}

void DrawPriceText(string name, datetime t, double price, string text, color col)
{
   if(ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 40);
   }
}

//====================================================================
// STATUS / ENTRY FILTER
//====================================================================
void EvaluateStatus()
{
   int s = SigShift();
   int threshold = ModeThreshold();
   int adxMin = ModeADXMin();
   int spread = SpreadPoints();
   bool spreadOK = spread <= Inp_MaxSpreadPoints;
   bool adxOK = bADX[s] >= adxMin;
   bool buyOK = (G_buyScore >= threshold && G_buyScore > G_sellScore);
   bool sellOK = (G_sellScore >= threshold && G_sellScore > G_buyScore);

   if(!spreadOK)
   {
      G_status = "BLOCKED";
      G_debug = "WAIT: spread high " + IntegerToString(spread) + " > " + IntegerToString(Inp_MaxSpreadPoints);
      return;
   }
   if(!adxOK)
   {
      G_status = "WAIT";
      G_debug = "WAIT: ADX low " + DoubleToString(bADX[s],1) + " < " + IntegerToString(adxMin);
      return;
   }

   if(Inp_SD_Filter_Entries)
   {
      if(buyOK && Inp_SD_Block_Buy_Near_Supply && G_zoneStatus == "NEAR SUPPLY")
      {
         G_status = "WAIT";
         G_debug = "WAIT: BUY blocked near supply";
         return;
      }
      if(sellOK && Inp_SD_Block_Sell_Near_Demand && G_zoneStatus == "NEAR DEMAND")
      {
         G_status = "WAIT";
         G_debug = "WAIT: SELL blocked near demand";
         return;
      }
   }

   if(buyOK)
   {
      G_status = "READY BUY";
      G_debug = "BUY score " + DoubleToString(G_buyScore,0) + " >= " + IntegerToString(threshold) + " | " + G_zoneStatus;
   }
   else if(sellOK)
   {
      G_status = "READY SELL";
      G_debug = "SELL score " + DoubleToString(G_sellScore,0) + " >= " + IntegerToString(threshold) + " | " + G_zoneStatus;
   }
   else
   {
      G_status = "WAIT";
      G_debug = "Score low B" + DoubleToString(G_buyScore,0) + "/S" + DoubleToString(G_sellScore,0) + " < " + IntegerToString(threshold);
   }
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == Inp_Magic)
            return true;
      }
   }
   return false;
}

bool CooldownOK()
{
   if(G_lastTradeBarTime == 0) return true;
   int shift = iBarShift(_Symbol, _Period, G_lastTradeBarTime, true);
   if(shift < 0) return true;
   return shift >= Inp_MinBarsBetweenTrades;
}

void TryAutoTrade()
{
   if(HasOpenPosition()) return;
   if(!CooldownOK()) return;

   if(G_status == "READY BUY")
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizePrice(ask - Inp_StopLoss_Points * _Point);
      double tp = NormalizePrice(ask + Inp_TakeProfit_Points * _Point);
      if(trade.Buy(Inp_LotSize, _Symbol, 0.0, sl, tp, "CM610 BUY"))
         G_lastTradeBarTime = iTime(_Symbol, _Period, 0);
   }
   else if(G_status == "READY SELL")
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizePrice(bid + Inp_StopLoss_Points * _Point);
      double tp = NormalizePrice(bid - Inp_TakeProfit_Points * _Point);
      if(trade.Sell(Inp_LotSize, _Symbol, 0.0, sl, tp, "CM610 SELL"))
         G_lastTradeBarTime = iTime(_Symbol, _Period, 0);
   }
}

void ManageOpenPosition()
{
   if(!Inp_Use_Breakeven && !Inp_Use_Trailing) return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != Inp_Magic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         double profitPts = (bid - open) / _Point;
         double newSL = sl;
         if(Inp_Use_Breakeven && profitPts >= Inp_BE_Start_Points)
            newSL = MathMax(newSL, NormalizePrice(open + Inp_BE_Lock_Points * _Point));
         if(Inp_Use_Trailing && profitPts >= Inp_Trail_Start_Points)
            newSL = MathMax(newSL, NormalizePrice(bid - Inp_Trail_DistancePoints * _Point));
         if(newSL > sl + _Point)
            trade.PositionModify(ticket, newSL, tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitPts = (open - ask) / _Point;
         double newSL = sl;
         if(sl == 0) newSL = 999999999;
         if(Inp_Use_Breakeven && profitPts >= Inp_BE_Start_Points)
            newSL = MathMin(newSL, NormalizePrice(open - Inp_BE_Lock_Points * _Point));
         if(Inp_Use_Trailing && profitPts >= Inp_Trail_Start_Points)
            newSL = MathMin(newSL, NormalizePrice(ask + Inp_Trail_DistancePoints * _Point));
         if(sl == 0 || newSL < sl - _Point)
            trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//====================================================================
// PANEL
//====================================================================
void CreatePanel()
{
   int x=Inp_Panel_X, y=Inp_Panel_Y, w=Inp_Panel_Width, h=Inp_Panel_Height;
   Rect("P_BG", x, y, w, h, C_BG, C_BORDER);

   // Header: separated title/mode/version so it will not overlap on common chart zooms.
   Rect("P_HEAD", x+8, y+8, w-16, 54, C_BOX, C_BORDER);
   Label("P_TITLE", "TONO CONFLUENCE XAU", x+18, y+15, C_TEXT, 10, true);
   Label("P_MODE", "MODE: BALANCED", x+w-150, y+16, C_WARN, 8, true);
   Label("P_VER", "v6.10.4 VISUAL CLUTTER CONTROL", x+18, y+36, C_MUTED, 7, false);

   // Main status band
   Rect("P_STATUS_BG", x+8, y+70, w-16, 38, C_BOX, C_BORDER);
   Label("P_STATUS", "LOADING", x+18, y+78, C_TEXT, 15, true);
   Label("P_AUTO", "AUTO: OFF", x+w-105, y+83, C_MUTED, 8, true);

   // Score section
   int by = y+126;
   Label("P_BUY_L", "LONG SCORE", x+18, by, C_BUY, 8, true);
   Label("P_BUY_V", "0", x+w-58, by, C_BUY, 8, true);
   Rect("P_BUY_BAR_BG", x+18, by+18, w-36, 8, C_BOX, C_BORDER);
   Rect("P_BUY_BAR", x+18, by+18, 1, 8, C_BUY, C_BUY);

   int sy = by+44;
   Label("P_SELL_L", "SHORT SCORE", x+18, sy, C_SELL, 8, true);
   Label("P_SELL_V", "0", x+w-58, sy, C_SELL, 8, true);
   Rect("P_SELL_BAR_BG", x+18, sy+18, w-36, 8, C_BOX, C_BORDER);
   Rect("P_SELL_BAR", x+18, sy+18, 1, 8, C_SELL, C_SELL);

   // Indicator grid: two clear columns with wider spacing.
   int gy = sy+54;
   int c1=x+18, v1=x+88, c2=x+230, v2=x+310;
   Label("P_ADX_L",  "ADX",    c1, gy,    C_MUTED, 8, false);
   Label("P_ADX_V",  "...",    v1, gy,    C_TEXT,  8, false);
   Label("P_SPR_L",  "SPREAD", c2, gy,    C_MUTED, 8, false);
   Label("P_SPR_V",  "...",    v2, gy,    C_TEXT,  8, false);

   Label("P_MACD_L", "MACD",   c1, gy+22, C_MUTED, 8, false);
   Label("P_MACD_V", "...",    v1, gy+22, C_TEXT,  8, false);
   Label("P_RSI_L",  "RSI",    c2, gy+22, C_MUTED, 8, false);
   Label("P_RSI_V",  "...",    v2, gy+22, C_TEXT,  8, false);

   Label("P_STO_L",  "STOCH",  c1, gy+44, C_MUTED, 8, false);
   Label("P_STO_V",  "...",    v1, gy+44, C_TEXT,  8, false);
   Label("P_EMA_L",  "EMA",    c2, gy+44, C_MUTED, 8, false);
   Label("P_EMA_V",  "...",    v2, gy+44, C_TEXT,  8, false);

   Label("P_ZONE_L", "ZONE",   c1, gy+70, C_MUTED, 8, false);
   Label("P_ZONE_V", "INIT",   v1, gy+70, C_WARN,  8, true);
   Label("P_SD_L",   "S/D",    c2, gy+70, C_MUTED, 8, false);
   Label("P_SD_V",   "...",    v2, gy+70, C_TEXT,  8, false);

   // Debug block: larger, more rows, fixed line spacing. This is the main v6.10.3 fix.
   int dy = y + h - 214;
   Rect("P_DEBUG_BG", x+8, dy, w-16, 204, C_BOX, C_BORDER);
   Label("P_DEBUG_T", "DETAILED DEBUG", x+18, dy+8, C_WARN, 8, true);
   Label("P_DBG1", "Loading...", x+18, dy+28,  C_TEXT, 7, false);
   Label("P_DBG2", "",          x+18, dy+46,  C_TEXT, 7, false);
   Label("P_DBG3", "",          x+18, dy+64,  C_TEXT, 7, false);
   Label("P_DBG4", "",          x+18, dy+82,  C_TEXT, 7, false);
   Label("P_DBG5", "",          x+18, dy+100, C_TEXT, 7, false);
   Label("P_DBG6", "",          x+18, dy+118, C_TEXT, 7, false);
   Label("P_DBG7", "",          x+18, dy+136, C_TEXT, 7, false);
   Label("P_DBG8", "",          x+18, dy+154, C_TEXT, 7, false);
   Label("P_DBG9", "",          x+18, dy+172, C_TEXT, 7, false);
}

void UpdatePanel()
{
   int s = SigShift();
   int w = Inp_Panel_Width;
   SetText("P_MODE", "MODE: " + ModeText(), C_WARN);
   SetText("P_STATUS", G_status, StatusColor());
   SetText("P_AUTO", Inp_Enable_AutoTrade ? "AUTO: ON" : "AUTO: OFF", Inp_Enable_AutoTrade ? C_OK : C_MUTED);
   SetText("P_BUY_V", DoubleToString(G_buyScore,0), C_BUY);
   SetText("P_SELL_V", DoubleToString(G_sellScore,0), C_SELL);
   SetWidth("P_BUY_BAR", (int)MathMax(1, MathMin(w-36, (G_buyScore/100.0)*(w-36))));
   SetWidth("P_SELL_BAR", (int)MathMax(1, MathMin(w-36, (G_sellScore/100.0)*(w-36))));

   string sd0 = "SUP# " + IntegerToString(CountValidSupply()) + " | DEM# " + IntegerToString(CountValidDemand());
   SetText("P_ZONE_V", G_zoneStatus, ZoneColor());
   SetText("P_SD_V", sd0, C_TEXT);

   // Safe loading state: never read indicator arrays until CopyBuffer has succeeded.
   if(!G_buffersReady || ArraySize(bADX) <= s || ArraySize(bEMA) <= s || ArraySize(bRSI) <= s || ArraySize(bMACDMain) <= s || ArraySize(bStochMain) <= s)
   {
      SetText("P_ADX_V", "...", C_MUTED);
      SetText("P_SPR_V", IntegerToString(SpreadPoints()), SpreadPoints() <= Inp_MaxSpreadPoints ? C_OK : C_SELL);
      SetText("P_MACD_V", "...", C_MUTED);
      SetText("P_RSI_V", "...", C_MUTED);
      SetText("P_STO_V", "...", C_MUTED);
      SetText("P_EMA_V", "...", C_MUTED);
      UpdateDetailedDebug(true);
      return;
   }

   SetText("P_ADX_V", DoubleToString(bADX[s],1), bADX[s] >= ModeADXMin() ? C_OK : C_WARN);
   SetText("P_SPR_V", IntegerToString(SpreadPoints()), SpreadPoints() <= Inp_MaxSpreadPoints ? C_OK : C_SELL);

   bool macdBull = bMACDMain[s] > bMACDSignal[s];
   bool rsiBull = bRSI[s] > 50;
   bool stoBull = bStochMain[s] > bStochSignal[s];
   bool emaBull = iClose(_Symbol,_Period,s) > bEMA[s];

   SetText("P_MACD_V", macdBull ? "BULL" : "BEAR", macdBull ? C_BUY : C_SELL);
   SetText("P_RSI_V", rsiBull ? "BULL" : "BEAR", rsiBull ? C_BUY : C_SELL);
   SetText("P_STO_V", stoBull ? "BULL" : "BEAR", stoBull ? C_BUY : C_SELL);
   SetText("P_EMA_V", emaBull ? "BULL" : "BEAR", emaBull ? C_BUY : C_SELL);

   SetText("P_ZONE_V", G_zoneStatus, ZoneColor());
   SetText("P_SD_V", sd0, C_TEXT);
   UpdateDetailedDebug(false);
}


int CountValidSupply()
{
   int c=0;
   for(int i=0; i<4; i++) if(G_supply[i].valid) c++;
   return c;
}

int CountValidDemand()
{
   int c=0;
   for(int i=0; i<4; i++) if(G_demand[i].valid) c++;
   return c;
}

string BullBearText(bool v)
{
   return v ? "BULL" : "BEAR";
}

void ClearExtraDebugLines()
{
   SetText("P_DBG2", "", C_TEXT);
   SetText("P_DBG3", "", C_TEXT);
   SetText("P_DBG4", "", C_TEXT);
   SetText("P_DBG5", "", C_TEXT);
   SetText("P_DBG6", "", C_TEXT);
   SetText("P_DBG7", "", C_TEXT);
   SetText("P_DBG8", "", C_TEXT);
   SetText("P_DBG9", "", C_TEXT);
}

void UpdateDetailedDebug(bool loading)
{
   if(!Inp_Show_Debug_Detail)
   {
      SetText("P_DBG1", G_debug, C_TEXT);
      ClearExtraDebugLines();
      return;
   }

   int bars = Bars(_Symbol,_Period);
   int spread = SpreadPoints();
   int threshold = ModeThreshold();
   int adxMin = ModeADXMin();
   int s = SigShift();
   double atrPts = SafeATR() / _Point;

   // v6.10.4: one topic per line, plus visual clutter flags.
   SetText("P_DBG1", "SIGNAL  Shift: " + IntegerToString(s) + " | TF: " + EnumToString(_Period) + " | Bars: " + IntegerToString(bars), C_MUTED);
   SetText("P_DBG2", "GATE    TH: " + IntegerToString(threshold) + " | ADX Min: " + IntegerToString(adxMin) + " | Spread Max: " + IntegerToString(Inp_MaxSpreadPoints), C_MUTED);
   SetText("P_DBG3", "SCORE   BUY: " + DoubleToString(G_buyScore,0) + " | SELL: " + DoubleToString(G_sellScore,0) + " | ATR: " + DoubleToString(atrPts,0) + " pts", C_TEXT);
   SetText("P_DBG4", "ZONE    " + G_zoneStatus + " | SUP#: " + IntegerToString(CountValidSupply()) + " | DEM#: " + IntegerToString(CountValidDemand()), ZoneColor());
   SetText("P_DBG5", "SUP     " + DoubleToString(G_nearestSupplyBottom,_Digits) + " - " + DoubleToString(G_nearestSupplyTop,_Digits), C_SUPPLY);
   SetText("P_DBG6", "DEM     " + DoubleToString(G_nearestDemandBottom,_Digits) + " - " + DoubleToString(G_nearestDemandTop,_Digits), C_DEMAND);

   if(loading || !G_buffersReady || ArraySize(bADX) <= s || ArraySize(bEMA) <= s || ArraySize(bRSI) <= s || ArraySize(bMACDMain) <= s || ArraySize(bStochMain) <= s)
   {
      SetText("P_DBG7", "INDI    Loading buffers | Spread: " + IntegerToString(spread), C_WARN);
      SetText("P_DBG8", "TRADE   Auto: " + string(Inp_Enable_AutoTrade ? "ON" : "OFF") + " | Pos: " + string(HasOpenPosition() ? "YES" : "NO"), C_TEXT);
      SetText("P_DBG9", "REASON  " + G_debug, C_WARN);
      return;
   }

   bool macdBull = bMACDMain[s] > bMACDSignal[s];
   bool rsiBull = bRSI[s] > 50;
   bool stoBull = bStochMain[s] > bStochSignal[s];
   bool emaBull = iClose(_Symbol,_Period,s) > bEMA[s];

   string indi = "INDI    EMA:" + BullBearText(emaBull) + " | MACD:" + BullBearText(macdBull) + " | RSI:" + DoubleToString(bRSI[s],1) + " | STO:" + BullBearText(stoBull);
   SetText("P_DBG7", indi, C_TEXT);

   string tradeState = "TRADE   Auto: " + string(Inp_Enable_AutoTrade ? "ON" : "OFF") + " | Pos: " + string(HasOpenPosition() ? "YES" : "NO") + " | Cooldown: " + string(CooldownOK() ? "OK" : "WAIT");
   SetText("P_DBG8", tradeState, C_TEXT);
   SetText("P_DBG9", "REASON  " + G_debug, StatusColor());
}

color StatusColor()
{
   if(G_status == "READY BUY") return C_BUY;
   if(G_status == "READY SELL") return C_SELL;
   if(G_status == "BLOCKED") return C_SELL;
   if(G_status == "WAIT") return C_WARN;
   return C_MUTED;
}

color ZoneColor()
{
   if(G_zoneStatus == "NEAR SUPPLY") return C_SUPPLY;
   if(G_zoneStatus == "NEAR DEMAND") return C_DEMAND;
   return C_WARN;
}

void Rect(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = G_PREFIX + name;
   if(ObjectFind(0,obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 100);
}

void Label(string name, string text, int x, int y, color col, int size, bool bold=false)
{
   string obj = G_PREFIX + name;
   if(ObjectFind(0,obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, col);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 110);
}

void SetText(string name, string text, color col)
{
   string obj = G_PREFIX + name;
   if(ObjectFind(0,obj) >= 0)
   {
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, col);
   }
}

void SetWidth(string name, int width)
{
   string obj = G_PREFIX + name;
   if(ObjectFind(0,obj) >= 0)
      ObjectSetInteger(0, obj, OBJPROP_XSIZE, width);
}
//+------------------------------------------------------------------+
