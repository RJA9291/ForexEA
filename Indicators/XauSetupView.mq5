//+------------------------------------------------------------------+
//| XauSetupView.mq5                                                 |
//| Shows XauScalper's entry logic on an M5 chart: EMA20 (M5),       |
//| EMA50/EMA200 from M15, Heikin Ashi candles, and an arrow on      |
//| every closed bar where the scalper's setup was complete.         |
//| Arrows ignore what the EA also checks at run time: open          |
//| position, daily limits, clearance and the broker's live spread.  |
//+------------------------------------------------------------------+
#property copyright "ForexEA"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   6

#property indicator_label1  "EMA20 M5 (pullback)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumPurple
#property indicator_width1  2

#property indicator_label2  "EMA50 M15 (bias)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1

#property indicator_label3  "EMA200 M15 (bias)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1

#property indicator_label4  "Setup BUY"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2

#property indicator_label5  "Setup SELL"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  2

#property indicator_label6  "Heikin Ashi"
#property indicator_type6   DRAW_COLOR_CANDLES
#property indicator_color6  clrSeaGreen, clrTomato

// Defaults match the demo forward-test inputs of XauScalper (docs/scalper.md).
input int    InpBars            = 3000;  // Bars to evaluate
input int    InpBiasFastEMA     = 50;
input int    InpBiasSlowEMA     = 200;
input int    InpPullbackEMA     = 20;
input int    InpATRPeriod       = 14;
input double InpTouchATR        = 0.3;
input int    InpSwingBars       = 5;
input double InpSLBufferATR     = 0.1;
input double InpMinSLPips       = 20;
input double InpMaxSLPips       = 60;
input double InpAssumedSpread   = 0.80;  // Price units; InstaForex gold is about 80 points
input double InpMaxSpreadToSL   = 0.25;
input double InpATRSpikeMult    = 2.5;
input int    InpATRBaseline     = 100;
input bool   InpShowHA          = true;  // Draw Heikin Ashi and hide the normal candles

double emaM5[], ema50[], ema200[], buyArr[], sellArr[];
double haO[], haH[], haL[], haC[], haClr[];
int    hEMA, hATR, hFast, hSlow;
datetime lastBar = 0;
bool     drawn = false;
bool     pending = true;
long   prevMode, prevBull, prevBear, prevUp, prevDown, prevLine;

int OnInit()
  {
   if(_Period != PERIOD_M5)
      Print("XauSetupView: the scalper's logic is M5; attach to an M5 chart.");
   SetIndexBuffer(0, emaM5, INDICATOR_DATA);
   SetIndexBuffer(1, ema50, INDICATOR_DATA);
   SetIndexBuffer(2, ema200, INDICATOR_DATA);
   SetIndexBuffer(3, buyArr, INDICATOR_DATA);
   SetIndexBuffer(4, sellArr, INDICATOR_DATA);
   SetIndexBuffer(5, haO, INDICATOR_DATA);
   SetIndexBuffer(6, haH, INDICATOR_DATA);
   SetIndexBuffer(7, haL, INDICATOR_DATA);
   SetIndexBuffer(8, haC, INDICATOR_DATA);
   SetIndexBuffer(9, haClr, INDICATOR_COLOR_INDEX);
   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);
   for(int p = 0; p < 6; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, InpShowHA ? DRAW_COLOR_CANDLES : DRAW_NONE);

   hEMA  = iMA(_Symbol, PERIOD_M5, InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   hFast = iMA(_Symbol, PERIOD_M15, InpBiasFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, PERIOD_M15, InpBiasSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE || hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE)
      return INIT_FAILED;

   prevMode = ChartGetInteger(0, CHART_MODE);
   prevBull = ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   prevBear = ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   prevUp   = ChartGetInteger(0, CHART_COLOR_CHART_UP);
   prevDown = ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
   prevLine = ChartGetInteger(0, CHART_COLOR_CHART_LINE);
   EventSetTimer(1);
   IndicatorSetString(INDICATOR_SHORTNAME, "XauSetupView");
   return INIT_SUCCEEDED;
  }

void HideCandles()
  {
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrNONE);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(!InpShowHA || !drawn) return;
   ChartSetInteger(0, CHART_MODE, prevMode);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, prevBull);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, prevBear);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, prevUp);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, prevDown);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, prevLine);
  }

double M15Value(const int handle, const int shift)
  {
   double v[1];
   return CopyBuffer(handle, 0, shift, 1, v) == 1 ? v[0] : EMPTY_VALUE;
  }

// Runs from the timer only: inside OnCalculate the M15 averages are not yet updated for the
// current pass, and the timer also draws while the market is closed and no ticks arrive.
bool Calc(const int rates_total, const int prev_calculated, const datetime &time[],
          const double &open[], const double &high[], const double &low[], const double &close[])
  {
   if(rates_total < InpATRBaseline + 10) return false;
   double atr[];
   if(CopyBuffer(hEMA, 0, 0, rates_total, emaM5) != rates_total) return false;
   if(CopyBuffer(hATR, 0, 0, rates_total, atr) != rates_total) return false;
   if(BarsCalculated(hFast) <= 0 || BarsCalculated(hSlow) <= 0) return false;

   int start = MathMax(InpATRBaseline + 5, rates_total - InpBars);
   bool full = time[rates_total - 1] != lastBar || prev_calculated == 0;
   int from = full ? start : rates_total - 1;
   if(full)
     {
      for(int j = 0; j < start; j++)
        {
         emaM5[j] = EMPTY_VALUE; ema50[j] = EMPTY_VALUE; ema200[j] = EMPTY_VALUE;
         buyArr[j] = EMPTY_VALUE; sellArr[j] = EMPTY_VALUE;
         haO[j] = EMPTY_VALUE; haH[j] = EMPTY_VALUE; haL[j] = EMPTY_VALUE; haC[j] = EMPTY_VALUE; haClr[j] = 0;
        }
      lastBar = time[rates_total - 1];
     }

   double pip = 0.10;
   for(int j = from; j < rates_total; j++)
     {
      double o = j == start ? (open[j] + close[j]) / 2.0 : (haO[j - 1] + haC[j - 1]) / 2.0;
      haC[j] = (open[j] + high[j] + low[j] + close[j]) / 4.0;
      haO[j] = o;
      haH[j] = MathMax(high[j], MathMax(haO[j], haC[j]));
      haL[j] = MathMin(low[j], MathMin(haO[j], haC[j]));
      haClr[j] = haC[j] >= haO[j] ? 0 : 1;

      int cur = iBarShift(_Symbol, PERIOD_M15, time[j], false);
      ema50[j]  = M15Value(hFast, cur);
      ema200[j] = M15Value(hSlow, cur);
      buyArr[j] = EMPTY_VALUE; sellArr[j] = EMPTY_VALUE;
      if(j == rates_total - 1 || j < start + 3) continue;   // forming bar, or HA not settled

      // The EA decides at the open of bar j+1, using bar j as "shift 1".
      int m15 = iBarShift(_Symbol, PERIOD_M15, time[j] + PeriodSeconds(PERIOD_M5), false) + 1;
      double f = M15Value(hFast, m15), s = M15Value(hSlow, m15), c15 = iClose(_Symbol, PERIOD_M15, m15);
      if(f == EMPTY_VALUE || s == EMPTY_VALUE || c15 == 0) continue;
      int bias = (f > s && c15 > f) ? 1 : ((f < s && c15 < f) ? -1 : 0);
      if(bias == 0) continue;

      double base = 0;
      for(int k = 0; k < InpATRBaseline; k++) base += atr[j - k];
      base /= InpATRBaseline;
      if(atr[j] > base * InpATRSpikeMult) continue;

      double ema = emaM5[j];
      double lo3 = MathMin(low[j], MathMin(low[j - 1], low[j - 2]));
      double hi3 = MathMax(high[j], MathMax(high[j - 1], high[j - 2]));
      bool trig;
      double entry, sl;
      if(bias > 0)
        {
         trig  = lo3 <= ema + InpTouchATR * atr[j] && haC[j - 1] < haO[j - 1] && haC[j] > haO[j] && close[j] > ema;
         entry = close[j] + InpAssumedSpread;
         sl    = low[ArrayMinimum(low, j - InpSwingBars + 1, InpSwingBars)] - InpSLBufferATR * atr[j];
        }
      else
        {
         trig  = hi3 >= ema - InpTouchATR * atr[j] && haC[j - 1] > haO[j - 1] && haC[j] < haO[j] && close[j] < ema;
         entry = close[j];
         sl    = high[ArrayMaximum(high, j - InpSwingBars + 1, InpSwingBars)] + InpSLBufferATR * atr[j];
        }
      if(!trig) continue;
      double risk = MathMax(MathAbs(entry - sl), InpMinSLPips * pip);
      if(risk > InpMaxSLPips * pip) continue;
      if(InpAssumedSpread > risk * InpMaxSpreadToSL) continue;
      if(bias > 0) buyArr[j] = low[j] - 0.4 * atr[j];
      else         sellArr[j] = high[j] + 0.4 * atr[j];
     }
   if(InpShowHA) HideCandles();
   drawn = true;
   ChartRedraw();
   return true;
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total > 0 && time[rates_total - 1] != lastBar) pending = true;
   return rates_total;
  }

void OnTimer()
  {
   if(!pending) return;
   int n = ArraySize(haO);
   MqlRates r[];
   if(n == 0 || CopyRates(_Symbol, _Period, 0, n, r) != n) return;
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++) { t[i] = r[i].time; o[i] = r[i].open; h[i] = r[i].high; l[i] = r[i].low; c[i] = r[i].close; }
   lastBar = 0;
   if(Calc(n, 0, t, o, h, l, c)) pending = false;
  }
//+------------------------------------------------------------------+
