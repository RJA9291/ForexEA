//+------------------------------------------------------------------+
//| XauTrendPullback.mq5                                             |
//| XAUUSD auto-trader: H4 trend -> H1 impulse leg + Fibonacci       |
//| pullback zone -> M15 rejection candle -> entry with risk-based   |
//| lot size, fixed R:R target, breakeven and ATR trailing.          |
//+------------------------------------------------------------------+
#property copyright "RJA9291"
#property link      "https://github.com/RJA9291/ForexEA"
#property version   "1.00"

#include <Trade/Trade.mqh>

input group "Risk"
input double InpRiskPercent     = 1.0;   // Risk per trade (% of equity)
input bool   InpAllowMinLot     = true;  // Use broker minimum lot when risk-based size is smaller
input double InpMaxRiskPercent  = 10.0;  // Hard cap on risk when forced to minimum lot (% of equity)
input int    InpMaxTradesPerDay = 2;     // Max new trades per day
input double InpMaxDailyLossPct = 3.0;   // Stop trading today after this loss (% of balance)
input int    InpMaxSpreadPoints = 60;    // Skip entries when spread is wider (points)

input group "Trend filter"
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;
input int    InpFastEMA         = 50;
input int    InpSlowEMA         = 200;

input group "Market structure"
input ENUM_TIMEFRAMES InpSetupTF = PERIOD_H1;
input int    InpSwingStrength   = 3;     // Bars each side to confirm a swing point
input int    InpSwingLookback   = 150;   // Bars searched for swings
input double InpMinImpulseATR   = 2.5;   // Impulse leg must be at least this many ATRs
input double InpFibShallow      = 0.382; // Pullback zone edge nearest the swing extreme
input double InpFibDeep         = 0.618; // Pullback zone edge furthest from the swing extreme
input int    InpATRPeriod       = 14;

input group "Entry trigger"
input ENUM_TIMEFRAMES InpTriggerTF = PERIOD_M15;
input double InpWickBodyRatio   = 1.0;   // Rejection wick must be >= body * ratio
input double InpSLBufferATR     = 0.2;   // Extra SL distance beyond the zone (ATR)
input double InpMinSLATR        = 0.3;   // Minimum SL distance (ATR)
input double InpMaxSLATR        = 2.0;   // Skip trade if SL would be wider (ATR)

input group "Checkpoint targets (one order, SL ratchets at each checkpoint)"
input double InpTP1R            = 1.0;   // TP1: SL moves to breakeven
input double InpTP2R            = 2.0;   // TP2: SL locks at TP1
input double InpTP3R            = 3.0;   // TP3: SL locks at TP2
input double InpFinalTPR        = 4.0;   // Final TP: the order's real take profit
input double InpTrailATR        = 0.0;   // Trail distance after TP3 (ATR, 0 = off)

input group "Session (broker server time)"
input int    InpStartHour       = 8;
input int    InpEndHour         = 20;

input group "General"
input ulong  InpMagic           = 920001;
input bool   InpGoldOnly        = true;  // Refuse to run on non-gold symbols
input bool   InpDrawMap         = true;  // Draw leg, zone and status on chart

#define OBJ_PREFIX "XTP_"

struct Leg
  {
   int      dir;       // 1 = bullish impulse (low -> high), -1 = bearish
   double   start;     // price where the impulse began
   double   end;       // swing extreme the pullback retraces from
   datetime tStart;
   datetime tEnd;
  };

CTrade   trade;
int      hFast = INVALID_HANDLE;
int      hSlow = INVALID_HANDLE;
int      hATR  = INVALID_HANDLE;
datetime lastTriggerBar = 0;
string   lastReason = "";      // why the most recent trade was taken
ulong    trackedTicket = 0;
double   peakPips = 0;
string   tallyNames[];         // outcome of each M15 evaluation, printed on deinit
int      tallyCounts[];

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpGoldOnly && StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
     {
      Print("XauTrendPullback: attach to XAUUSD/GOLD only (symbol is ", _Symbol, ")");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPercent <= 0 || InpFibShallow >= InpFibDeep || InpMaxRiskPercent < InpRiskPercent ||
      !(0 < InpTP1R && InpTP1R < InpTP2R && InpTP2R < InpTP3R && InpTP3R < InpFinalTPR))
      return INIT_PARAMETERS_INCORRECT;

   hFast = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, InpSetupTF, InpATRPeriod);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   PrintFormat("XTP spec: digits %d point %g contract %g minLot %g step %g tickValue %g spread %d stopsLevel %d",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS), SymbolInfoDouble(_Symbol, SYMBOL_POINT),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hATR  != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
   for(int i = 0; i < ArraySize(tallyNames); i++)
      PrintFormat("XTP outcome: %-45s %d", tallyNames[i], tallyCounts[i]);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   datetime barTime = iTime(_Symbol, InpTriggerTF, 0);
   if(barTime == 0 || barTime == lastTriggerBar)
      return;
   lastTriggerBar = barTime;

   Evaluate();
  }

//+------------------------------------------------------------------+
double BufferValue(const int handle, const int shift)
  {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1)
      return EMPTY_VALUE;
   return buf[0];
  }

//+------------------------------------------------------------------+
int TrendBias()
  {
   double fast  = BufferValue(hFast, 1);
   double slow  = BufferValue(hSlow, 1);
   double close = iClose(_Symbol, InpTrendTF, 1);
   if(fast == EMPTY_VALUE || slow == EMPTY_VALUE || close == 0)
      return 0;
   if(fast > slow && close > slow) return 1;
   if(fast < slow && close < slow) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
bool IsSwingHigh(const double &hi[], const int i, const int s)
  {
   for(int k = 1; k <= s; k++)
      if(hi[i] <= hi[i - k] || hi[i] < hi[i + k])
         return false;
   return true;
  }

bool IsSwingLow(const double &lo[], const int i, const int s)
  {
   for(int k = 1; k <= s; k++)
      if(lo[i] >= lo[i - k] || lo[i] > lo[i + k])
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Latest completed impulse leg in the trend direction whose        |
//| extreme has not been exceeded and whose origin is unbroken.      |
//+------------------------------------------------------------------+
bool FindLeg(const int dir, const double atr, Leg &leg)
  {
   int n = InpSwingLookback;
   int s = InpSwingStrength;
   double hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tm, true);
   if(CopyHigh(_Symbol, InpSetupTF, 0, n, hi) != n ||
      CopyLow(_Symbol, InpSetupTF, 0, n, lo) != n ||
      CopyTime(_Symbol, InpSetupTF, 0, n, tm) != n)
      return false;

   int iExt = -1, iOrg = -1;
   for(int i = s + 1; i < n - s; i++)
     {
      bool isExt = (dir > 0) ? IsSwingHigh(hi, i, s) : IsSwingLow(lo, i, s);
      if(isExt) { iExt = i; break; }
     }
   if(iExt < 0) return false;

   for(int i = iExt + 1; i < n - s; i++)
     {
      bool isOrg = (dir > 0) ? IsSwingLow(lo, i, s) : IsSwingHigh(hi, i, s);
      if(isOrg) { iOrg = i; break; }
     }
   if(iOrg < 0) return false;

   double extPrice = (dir > 0) ? hi[iExt] : lo[iExt];
   double orgPrice = (dir > 0) ? lo[iOrg] : hi[iOrg];

   // Price since the extreme must not have made a new extreme or broken the origin.
   for(int i = 0; i < iExt; i++)
     {
      if(dir > 0 && (hi[i] > extPrice || lo[i] <= orgPrice)) return false;
      if(dir < 0 && (lo[i] < extPrice || hi[i] >= orgPrice)) return false;
     }

   if(MathAbs(extPrice - orgPrice) < InpMinImpulseATR * atr)
      return false;

   leg.dir    = dir;
   leg.start  = orgPrice;
   leg.end    = extPrice;
   leg.tStart = tm[iOrg];
   leg.tEnd   = tm[iExt];
   return true;
  }

//+------------------------------------------------------------------+
bool SessionOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour <= InpEndHour)
      return dt.hour >= InpStartHour && dt.hour < InpEndHour;
   return dt.hour >= InpStartHour || dt.hour < InpEndHour;
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void DailyStats(int &entries, double &closedPnl)
  {
   entries = 0;
   closedPnl = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(dayStart, TimeCurrent() + 60))
      return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
         entries++;
      else
         closedPnl += HistoryDealGetDouble(deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(deal, DEAL_SWAP) +
                      HistoryDealGetDouble(deal, DEAL_COMMISSION);
     }
  }

//+------------------------------------------------------------------+
double LotsForRisk(const double riskDistance, const ENUM_ORDER_TYPE type, const double price)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0 || riskDistance <= 0)
      return 0;

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney  = equity * InpRiskPercent / 100.0;
   double lossPerLot = riskDistance / tickSize * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   if(lots < minLot)
     {
      if(!InpAllowMinLot || minLot * lossPerLot > equity * InpMaxRiskPercent / 100.0)
         return 0;
      lots = minLot;
     }
   lots = MathMin(lots, maxLot);

   double margin;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      return 0;
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
void Evaluate()
  {
   string status;
   int bias = TrendBias();
   double atr = BufferValue(hATR, 1);
   if(atr == EMPTY_VALUE || atr <= 0)
      return;

   status = StringFormat("XauTrendPullback | Trend %s | ATR(H1) %.2f",
                         bias > 0 ? "BULL" : (bias < 0 ? "BEAR" : "NONE"), atr);

   if(bias == 0)                { Show(status + "\nNo clear trend - standing aside"); return; }

   Leg leg;
   if(!FindLeg(bias, atr, leg)) { Show(status + "\nNo valid impulse leg"); return; }

   double range   = MathAbs(leg.end - leg.start);
   double zoneNear = leg.end - bias * range * InpFibShallow;
   double zoneFar  = leg.end - bias * range * InpFibDeep;
   if(InpDrawMap) DrawMap(leg, zoneNear, zoneFar);

   status += StringFormat("\nLeg %.2f -> %.2f | Zone %.2f - %.2f",
                          leg.start, leg.end, MathMin(zoneNear, zoneFar), MathMax(zoneNear, zoneFar));

   if(!SessionOpen())           { Show(status + "\nOutside session"); return; }
   if(HasOpenPosition())        return;   // ManagePositions owns the chart status while a trade runs

   int entries; double closedPnl;
   DailyStats(entries, closedPnl);
   if(entries >= InpMaxTradesPerDay)
     { Show(status + "\nDaily trade limit reached"); return; }
   if(closedPnl <= -AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0)
     { Show(status + "\nDaily loss limit reached"); return; }

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
     { Show(status + StringFormat("\nSpread %d too wide", (int)spread) + "\nSpread too wide"); return; }

   double o  = iOpen(_Symbol, InpTriggerTF, 1);
   double h  = iHigh(_Symbol, InpTriggerTF, 1);
   double l  = iLow(_Symbol, InpTriggerTF, 1);
   double c  = iClose(_Symbol, InpTriggerTF, 1);
   double po = iOpen(_Symbol, InpTriggerTF, 2);
   double pc = iClose(_Symbol, InpTriggerTF, 2);
   double body = MathAbs(c - o);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   bool triggered = false;
   double entry = 0, sl = 0;
   string pattern = "";
   if(bias > 0)
     {
      double lowerWick = MathMin(o, c) - l;
      bool touched   = l <= zoneNear && c >= zoneFar;
      bool rejection = c > o && lowerWick >= body * InpWickBodyRatio;
      bool engulfing = c > o && pc < po && c > po && o <= pc;
      triggered = touched && (rejection || engulfing);
      pattern = engulfing ? "Bullish engulfing" : "Bullish rejection wick";
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = MathMin(l, zoneFar) - InpSLBufferATR * atr;
     }
   else
     {
      double upperWick = h - MathMax(o, c);
      bool touched   = h >= zoneNear && c <= zoneFar;
      bool rejection = c < o && upperWick >= body * InpWickBodyRatio;
      bool engulfing = c < o && pc > po && c < po && o >= pc;
      triggered = touched && (rejection || engulfing);
      pattern = engulfing ? "Bearish engulfing" : "Bearish rejection wick";
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = MathMax(h, zoneFar) + InpSLBufferATR * atr;
     }

   if(!triggered)               { Show(status + "\nWaiting for rejection in zone"); return; }

   double risk = MathAbs(entry - sl);
   if(risk < InpMinSLATR * atr)
     {
      risk = InpMinSLATR * atr;
      sl = entry - bias * risk;
     }
   if(risk > InpMaxSLATR * atr) { Show(status + "\nSL too wide - skipped"); return; }
   if(risk <= stopsLevel)       { Show(status + "\nSL inside broker stop level - skipped"); return; }

   double tp = entry + bias * risk * InpFinalTPR;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   ENUM_ORDER_TYPE type = bias > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lots = LotsForRisk(risk, type, entry);
   if(lots <= 0)                { Show(status + "\nMinimum lot exceeds risk cap - skipped"); return; }

   bool ok = bias > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, "XTP buy")
                      : trade.Sell(lots, _Symbol, 0, sl, tp, "XTP sell");
   if(ok)
      lastReason = StringFormat("- H4 trend %s (EMA%d/%d)\n- H1 impulse %.2f -> %.2f, pullback into Fib %.1f-%.1f%%\n- M15 %s",
                                bias > 0 ? "up" : "down", InpFastEMA, InpSlowEMA, leg.start, leg.end,
                                InpFibShallow * 100, InpFibDeep * 100, pattern);
   PrintFormat("XauTrendPullback %s %.2f lots @%.2f SL %.2f TP %.2f -> %s (%d) | %s",
               bias > 0 ? "BUY" : "SELL", lots, entry, sl, tp,
               ok ? "sent" : "failed", trade.ResultRetcode(), pattern);
   if(!ok) Show(status + "\nOrder failed - see Experts log");
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   // Gold quotes: 1 pip = 0.10, matching common signal apps.
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (digits >= 3 ? 100 : 10);
  }

void ManagePositions()
  {
   double atr = BufferValue(hATR, 1);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip = PipSize();
   bool found = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      int    dir   = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(sl == 0 || tp == 0) continue;
      found = true;

      // TP is never modified, so the original risk is recoverable from it.
      double risk = MathAbs(tp - open) / InpFinalTPR;
      double tp1 = open + dir * risk * InpTP1R;
      double tp2 = open + dir * risk * InpTP2R;
      double tp3 = open + dir * risk * InpTP3R;

      double runPips = (price - open) * dir / pip;
      if(ticket != trackedTicket)
        {
         trackedTicket = ticket;
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         int bars = Bars(_Symbol, PERIOD_M1, opened, TimeCurrent());
         peakPips = 0;
         if(bars > 0)
           {
            double extreme = dir > 0 ? iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, bars, 0))
                                     : iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, bars, 0));
            peakPips = MathMax(0, (extreme - open) * dir / pip);
           }
        }
      peakPips = MathMax(peakPips, runPips);

      // Checkpoints are judged on the best price reached, so a pullback
      // after touching a checkpoint still keeps the locked stop.
      double best = open + dir * peakPips * pip;
      double lock = sl;
      string stage = "Running";
      if((best - tp3) * dir >= 0)      { lock = tp2;                     stage = "TP3 HIT - SL locked at TP2"; }
      else if((best - tp2) * dir >= 0) { lock = tp1;                     stage = "TP2 HIT - SL locked at TP1"; }
      else if((best - tp1) * dir >= 0) { lock = open + dir * 10 * point; stage = "TP1 HIT - BREAK EVEN SET"; }

      if(InpTrailATR > 0 && atr != EMPTY_VALUE && (best - tp3) * dir >= 0)
        {
         double trail = price - dir * InpTrailATR * atr;
         // Only step the stop in meaningful increments to avoid modify spam.
         if((trail - lock) * dir > 0.1 * atr)
            lock = trail;
        }

      lock = NormalizeDouble(lock, digits);
      if((lock - sl) * dir > point && (price - lock) * dir > 0)
         if(trade.PositionModify(ticket, lock, tp))
            sl = lock;

      if(InpDrawMap)
         Comment(StringFormat("XAUUSD %s  |  %s\nRUNNING %+.1f pip   (peak %+.1f)\n"
                              "ENTRY %.2f   SL %.2f\nTP1 %.2f %s   TP2 %.2f %s   TP3 %.2f %s   FINAL %.2f\n"
                              "SIGNAL REASON\n%s",
                              dir > 0 ? "BUY" : "SELL", stage, runPips, peakPips,
                              open, sl,
                              tp1, (best - tp1) * dir >= 0 ? "[hit]" : "",
                              tp2, (best - tp2) * dir >= 0 ? "[hit]" : "",
                              tp3, (best - tp3) * dir >= 0 ? "[hit]" : "", tp,
                              lastReason == "" ? "(EA restarted - reason not kept)" : lastReason));
     }

   if(!found)
      trackedTicket = 0;
  }

//+------------------------------------------------------------------+
void Tally(const string reason)
  {
   int n = ArraySize(tallyNames);
   for(int i = 0; i < n; i++)
      if(tallyNames[i] == reason) { tallyCounts[i]++; return; }
   ArrayResize(tallyNames, n + 1);
   ArrayResize(tallyCounts, n + 1);
   tallyNames[n] = reason;
   tallyCounts[n] = 1;
  }

void Show(const string text)
  {
   int cut = StringFind(text, "\n");
   string last = text;
   while(cut >= 0)
     {
      last = StringSubstr(last, cut + 1);
      cut = StringFind(last, "\n");
     }
   Tally(last);
   if(InpDrawMap) Comment(text);
  }

void UpsertObject(const string name, const ENUM_OBJECT kind,
                  const datetime t1, const double p1,
                  const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, kind, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DrawMap(const Leg &leg, const double zoneNear, const double zoneFar)
  {
   datetime future = TimeCurrent() + PeriodSeconds(InpSetupTF) * 24;
   color legClr  = leg.dir > 0 ? clrDodgerBlue : clrOrangeRed;
   color zoneClr = leg.dir > 0 ? clrDarkGreen : clrMaroon;

   string legName    = OBJ_PREFIX + "leg";
   string zoneName   = OBJ_PREFIX + "zone";
   string originName = OBJ_PREFIX + "origin";

   UpsertObject(legName, OBJ_TREND, leg.tStart, leg.start, leg.tEnd, leg.end, legClr);
   ObjectSetInteger(0, legName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, legName, OBJPROP_RAY_RIGHT, false);

   UpsertObject(zoneName, OBJ_RECTANGLE, leg.tEnd, zoneNear, future, zoneFar, zoneClr);
   ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);

   UpsertObject(originName, OBJ_TREND, leg.tStart, leg.start, future, leg.start, clrGray);
   ObjectSetInteger(0, originName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, originName, OBJPROP_RAY_RIGHT, false);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
