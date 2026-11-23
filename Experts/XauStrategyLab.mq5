//+------------------------------------------------------------------+
//| XauStrategyLab.mq5                                               |
//| Backtest harness for candidate XAUUSD strategies. One strategy   |
//| per run (InpStrategy); all share the same risk, exits, regime    |
//| tagging and statistics, so results are directly comparable.     |
//|                                                                  |
//| BBMA (Oma Ally style, community rules - there is no official     |
//| written spec): Bollinger Bands 20/2, LWMA 5/10 of highs and      |
//| lows, EMA50, on H1.                                              |
//|   Reentry: after a CSA (close outside the band in the trend      |
//|   direction) within the last 20 bars, price pulls back into the  |
//|   MA5/MA10 band and the bar closes back in the trend direction   |
//|   on the correct side of the middle band -> trade with trend.    |
//|   Extreme: MA5 pokes outside the band, then a bar closes back    |
//|   inside against the move -> counter-trend trade.                |
//| S/R bounce (M15): previous-day high/low and $50 round numbers;   |
//| a rejection candle that touches a level and closes back on the  |
//| near side -> trade away from the level.                          |
//| Tokmat Shadow Entry (user's course notes, 2026-11-23): SnR zones |
//| are the shadows (wicks) of D1/H4 swing candles. When price       |
//| reaches a support zone, drop to M5: price must break two         |
//| resistances (close above the two latest M5 swing highs), then    |
//| buy on the pullback to the broken level. Mirror for sell. SL     |
//| beyond the lowest point since the zone touch, 20-80 pips (notes: |
//| SL 30-50 pips, RR 1:2-1:3). No martingale, no full margin.       |
//+------------------------------------------------------------------+
#property copyright "RJA9291"
#property link      "https://github.com/RJA9291/ForexEA"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <XauRegime.mqh>
#include <XauStats.mqh>

enum LabStrategy
  {
   LAB_BBMA_REENTRY = 1,   // BBMA Reentry (H1, with trend)
   LAB_BBMA_EXTREME = 2,   // BBMA Extreme (H1, counter-trend)
   LAB_SR_BOUNCE    = 3,   // Support/Resistance bounce (M15)
   LAB_TOKMAT       = 4    // Tokmat Shadow Entry (D1/H4 shadow zones, M5 break-2 + pullback)
  };

input LabStrategy InpStrategy   = LAB_BBMA_REENTRY;
input double InpRiskPercent     = 1.0;
input double InpTPR             = 2.0;   // take profit in R
input double InpBreakevenR      = 1.0;   // SL to entry at this R (0 = off)
input double InpSLBufferATR     = 0.2;   // extra SL distance beyond the structure (H1 ATR)
input double InpMinSLATR        = 0.3;
input double InpMaxSLATR        = 2.0;
input int    InpMaxTradesPerDay = 2;
input int    InpStartHour       = 8;     // server time; no new entries outside these hours
input int    InpEndHour         = 21;
input int    InpMaxSpreadPoints = 150;
input double InpSRTouchATR      = 0.15;  // how close a candle must come to a level (H1 ATR)
input double InpTkMinSLPips     = 20;    // Tokmat: SL distance floor (1 pip = 0.10)
input double InpTkMaxSLPips     = 80;    // Tokmat: skip the setup if the SL would be wider
input int    InpTkTouchHours    = 12;    // Tokmat: how long a zone touch stays valid
input ENUM_TIMEFRAMES InpTkTF  = PERIOD_M5; // Tokmat: entry timeframe (notes allow M1 or M5)
input ulong  InpMagic           = 920300;

CTrade     trade;
CXauRegime regime;
int hBB, hMa5H, hMa5L, hMa10H, hMa10L, hEma50, hAtrH1;
datetime lastBar = 0;
string   tallyNames[];
int      tallyCounts[];

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES SignalTF()
  {
   if(InpStrategy == LAB_TOKMAT) return InpTkTF;
   return InpStrategy == LAB_SR_BOUNCE ? PERIOD_M15 : PERIOD_H1;
  }
string StrategyName()
  {
   if(InpStrategy == LAB_BBMA_REENTRY) return "BBMA_REENTRY";
   if(InpStrategy == LAB_BBMA_EXTREME) return "BBMA_EXTREME";
   if(InpStrategy == LAB_TOKMAT) return "TOKMAT_SHADOW";
   return "SR_BOUNCE";
  }

int OnInit()
  {
   hBB    = iBands(_Symbol, PERIOD_H1, 20, 0, 2.0, PRICE_CLOSE);
   hMa5H  = iMA(_Symbol, PERIOD_H1, 5, 0, MODE_LWMA, PRICE_HIGH);
   hMa5L  = iMA(_Symbol, PERIOD_H1, 5, 0, MODE_LWMA, PRICE_LOW);
   hMa10H = iMA(_Symbol, PERIOD_H1, 10, 0, MODE_LWMA, PRICE_HIGH);
   hMa10L = iMA(_Symbol, PERIOD_H1, 10, 0, MODE_LWMA, PRICE_LOW);
   hEma50 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hAtrH1 = iATR(_Symbol, PERIOD_H1, 14);
   if(hBB == INVALID_HANDLE || hMa5H == INVALID_HANDLE || hMa5L == INVALID_HANDLE || hMa10H == INVALID_HANDLE ||
      hMa10L == INVALID_HANDLE || hEma50 == INVALID_HANDLE || hAtrH1 == INVALID_HANDLE || !regime.Init(_Symbol))
      return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   PrintFormat("XauStrategyLab spec: strategy %s, digits %d, contract %g", StrategyName(),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   XauPrintStats(InpMagic, "LAB " + StrategyName());
   for(int i = 0; i < ArraySize(tallyNames); i++)
      PrintFormat("LAB outcome: %-40s %d", tallyNames[i], tallyCounts[i]);
   regime.Release();
  }

void Tally(const string reason)
  {
   int n = ArraySize(tallyNames);
   for(int i = 0; i < n; i++) if(tallyNames[i] == reason) { tallyCounts[i]++; return; }
   ArrayResize(tallyNames, n + 1); ArrayResize(tallyCounts, n + 1);
   tallyNames[n] = reason; tallyCounts[n] = 1;
  }

double Buf(const int h, const int buffer, const int shift)
  {
   double b[1];
   if(CopyBuffer(h, buffer, shift, 1, b) != 1) return EMPTY_VALUE;
   return b[0];
  }

//+------------------------------------------------------------------+
bool HasPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic) return true;
     }
   return false;
  }

int TradesToday()
  {
   if(!HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent() + 60)) return 0;
   int n = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d != 0 && (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) == InpMagic && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) n++;
     }
   return n;
  }

double LotsForRisk(const double riskDistance)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0 || riskDistance <= 0) return 0;
   double lots = MathFloor(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 / (riskDistance / tickSize * tickValue) / step) * step;
   if(lots < minLot) return 0;
   return NormalizeDouble(MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), 2);
  }

// Market entry with the SL placed beyond `structure`; R is the entry-to-SL distance.
// minRisk/maxRisk override the ATR-based bounds when positive (price units).
void Enter(const int dir, const double structure, const string setup, const double minRisk = 0, const double maxRisk = 0)
  {
   double atr = Buf(hAtrH1, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0) return;
   double lo = minRisk > 0 ? minRisk : InpMinSLATR * atr, hi = maxRisk > 0 ? maxRisk : InpMaxSLATR * atr;
   double entry = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = structure - dir * InpSLBufferATR * atr * (minRisk > 0 ? 0.25 : 1.0);
   double risk = (entry - sl) * dir;
   if(risk < lo) { risk = lo; sl = entry - dir * risk; }
   if(risk > hi) { Tally(setup + ": SL too wide"); return; }
   double lots = LotsForRisk(risk);
   if(lots <= 0) { Tally(setup + ": lot below minimum"); return; }
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tp = NormalizeDouble(entry + dir * risk * InpTPR, digits);
   sl = NormalizeDouble(sl, digits);
   string comment = StringFormat("LAB %s %s", setup, regime.Classify());
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, comment) : trade.Sell(lots, _Symbol, 0, sl, tp, comment);
   Tally(ok ? setup + ": entered" : setup + ": order failed");
  }

//+------------------------------------------------------------------+
//| BBMA on closed H1 bars                                           |
//+------------------------------------------------------------------+
void BbmaReentry()
  {
   double mid = Buf(hBB, 0, 1), up = Buf(hBB, 1, 1), lo = Buf(hBB, 2, 1);
   double m5h = Buf(hMa5H, 0, 1), m5l = Buf(hMa5L, 0, 1), m10h = Buf(hMa10H, 0, 1), m10l = Buf(hMa10L, 0, 1);
   double ema = Buf(hEma50, 0, 1);
   if(mid == EMPTY_VALUE || ema == EMPTY_VALUE) return;
   double o = iOpen(_Symbol, PERIOD_H1, 1), h = iHigh(_Symbol, PERIOD_H1, 1), l = iLow(_Symbol, PERIOD_H1, 1), c = iClose(_Symbol, PERIOD_H1, 1);

   // CSA: a close outside the band in the trend direction within the last 20 closed bars (excluding bar 1).
   bool csaUp = false, csaDn = false;
   for(int i = 2; i <= 21; i++)
     {
      double ci = iClose(_Symbol, PERIOD_H1, i);
      if(ci > Buf(hBB, 1, i)) csaUp = true;
      if(ci < Buf(hBB, 2, i)) csaDn = true;
     }
   if(csaUp && !csaDn && c > ema && c > mid && c > o && l <= MathMax(m5l, m10l) && c > MathMax(m5l, m10l))
      Enter(1, MathMin(l, m10l), "BBMA reentry");
   else if(csaDn && !csaUp && c < ema && c < mid && c < o && h >= MathMin(m5h, m10h) && c < MathMin(m5h, m10h))
      Enter(-1, MathMax(h, m10h), "BBMA reentry");
  }

void BbmaExtreme()
  {
   double up2 = Buf(hBB, 1, 2), lo2 = Buf(hBB, 2, 2), up1 = Buf(hBB, 1, 1), lo1 = Buf(hBB, 2, 1);
   double m5h2 = Buf(hMa5H, 0, 2), m5l2 = Buf(hMa5L, 0, 2);
   if(up2 == EMPTY_VALUE || m5h2 == EMPTY_VALUE) return;
   double o = iOpen(_Symbol, PERIOD_H1, 1), c = iClose(_Symbol, PERIOD_H1, 1);
   double h2 = iHigh(_Symbol, PERIOD_H1, 2), l2 = iLow(_Symbol, PERIOD_H1, 2);
   if(m5h2 > up2 && c < up1 && c < o)
      Enter(-1, MathMax(h2, iHigh(_Symbol, PERIOD_H1, 1)), "BBMA extreme");
   else if(m5l2 < lo2 && c > lo1 && c > o)
      Enter(1, MathMin(l2, iLow(_Symbol, PERIOD_H1, 1)), "BBMA extreme");
  }

//+------------------------------------------------------------------+
//| Support/Resistance bounce on closed M15 bars                     |
//+------------------------------------------------------------------+
void SrBounce()
  {
   double atr = Buf(hAtrH1, 0, 1);
   if(atr == EMPTY_VALUE) return;
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);
   double o = iOpen(_Symbol, PERIOD_M15, 1), h = iHigh(_Symbol, PERIOD_M15, 1), l = iLow(_Symbol, PERIOD_M15, 1), c = iClose(_Symbol, PERIOD_M15, 1);
   double body = MathAbs(c - o), tol = InpSRTouchATR * atr;
   double round50Below = MathFloor(c / 50.0) * 50.0, round50Above = round50Below + 50.0;

   double supports[3], resistances[3];
   supports[0] = pdl; supports[1] = round50Below; supports[2] = pdh;      // yesterday's high acts as support once broken
   resistances[0] = pdh; resistances[1] = round50Above; resistances[2] = pdl;

   for(int i = 0; i < 3; i++)
     {
      double s = supports[i];
      if(s < c && l <= s + tol && c > s && c > o && (MathMin(o, c) - l) >= body)
        { Enter(1, MathMin(l, s), "SR bounce"); return; }
     }
   for(int i = 0; i < 3; i++)
     {
      double r = resistances[i];
      if(r > c && h >= r - tol && c < r && c < o && (h - MathMax(o, c)) >= body)
        { Enter(-1, MathMax(h, r), "SR bounce"); return; }
     }
  }

//+------------------------------------------------------------------+
//| Tokmat Shadow Entry                                              |
//+------------------------------------------------------------------+
// Per direction (0 = buy, 1 = sell): 0 idle, 1 zone touched, 2 two structure levels broken.
int      tkState[2] = {0, 0};
double   tkZoneLo[2], tkZoneHi[2], tkExtreme[2], tkBreak[2];
datetime tkSince[2];

bool IsFractalHigh(const ENUM_TIMEFRAMES tf, const int i, const int s)
  {
   double h = iHigh(_Symbol, tf, i);
   for(int k = 1; k <= s; k++) if(h <= iHigh(_Symbol, tf, i - k) || h < iHigh(_Symbol, tf, i + k)) return false;
   return true;
  }
bool IsFractalLow(const ENUM_TIMEFRAMES tf, const int i, const int s)
  {
   double l = iLow(_Symbol, tf, i);
   for(int k = 1; k <= s; k++) if(l >= iLow(_Symbol, tf, i - k) || l > iLow(_Symbol, tf, i + k)) return false;
   return true;
  }

// Shadow zone of a D1/H4 swing candle that the last closed M5 bar is touching.
// Buy: swing low, zone = lower wick [low, body low]. Sell: swing high, zone = upper wick [body high, high].
bool TouchedShadowZone(const int dir, double &zlo, double &zhi)
  {
   double l1 = iLow(_Symbol, InpTkTF, 1), h1 = iHigh(_Symbol, InpTkTF, 1), c1 = iClose(_Symbol, InpTkTF, 1);
   ENUM_TIMEFRAMES tfs[2] = {PERIOD_D1, PERIOD_H4};
   int depth[2] = {60, 120};
   for(int t = 0; t < 2; t++)
      for(int i = 3; i < depth[t]; i++)
        {
         double o = iOpen(_Symbol, tfs[t], i), c = iClose(_Symbol, tfs[t], i);
         if(dir > 0 && IsFractalLow(tfs[t], i, 2))
           {
            zlo = iLow(_Symbol, tfs[t], i); zhi = MathMax(MathMin(o, c), zlo + 0.5);
            if(l1 <= zhi && c1 >= zlo) return true;
           }
         if(dir < 0 && IsFractalHigh(tfs[t], i, 2))
           {
            zhi = iHigh(_Symbol, tfs[t], i); zlo = MathMin(MathMax(o, c), zhi - 0.5);
            if(h1 >= zlo && c1 <= zhi) return true;
           }
        }
   return false;
  }

// The two most recent M5 swing highs (dir>0) or lows (dir<0) formed since `since`; returns the outer one.
bool TwoStructureLevels(const int dir, const datetime since, double &level)
  {
   int found = 0;
   level = 0;
   for(int i = 3; i < 150; i++)
     {
      if(iTime(_Symbol, InpTkTF, i) < since) break;
      bool sw = dir > 0 ? IsFractalHigh(InpTkTF, i, 2) : IsFractalLow(InpTkTF, i, 2);
      if(!sw) continue;
      double v = dir > 0 ? iHigh(_Symbol, InpTkTF, i) : iLow(_Symbol, InpTkTF, i);
      level = found == 0 ? v : (dir > 0 ? MathMax(level, v) : MathMin(level, v));
      if(++found == 2) return true;
     }
   return false;
  }

void TokmatStep(const bool mayEnter)
  {
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double o1 = iOpen(_Symbol, InpTkTF, 1), h1 = iHigh(_Symbol, InpTkTF, 1), l1 = iLow(_Symbol, InpTkTF, 1), c1 = iClose(_Symbol, InpTkTF, 1);
   datetime t1 = iTime(_Symbol, InpTkTF, 1);
   for(int k = 0; k < 2; k++)
     {
      int dir = k == 0 ? 1 : -1;
      if(tkState[k] > 0 && t1 - tkSince[k] > InpTkTouchHours * 3600) tkState[k] = 0;   // stale

      if(tkState[k] == 0)
        {
         double zlo, zhi;
         if(TouchedShadowZone(dir, zlo, zhi))
           { tkState[k] = 1; tkZoneLo[k] = zlo; tkZoneHi[k] = zhi; tkSince[k] = t1; tkExtreme[k] = dir > 0 ? l1 : h1; }
         continue;
        }
      tkExtreme[k] = dir > 0 ? MathMin(tkExtreme[k], l1) : MathMax(tkExtreme[k], h1);
      // A body close through the far side of the zone breaks it.
      if((dir > 0 && c1 < tkZoneLo[k] - 2 * pip) || (dir < 0 && c1 > tkZoneHi[k] + 2 * pip)) { tkState[k] = 0; continue; }

      if(tkState[k] == 1)
        {
         double lvl;
         // Swing levels counted from one hour before the touch, so the structure leading into the zone counts.
         if(TwoStructureLevels(dir, tkSince[k] - 3600, lvl) && (c1 - lvl) * dir > 0)
           { tkState[k] = 2; tkBreak[k] = lvl; Tally("Tokmat: broke 2 levels"); }
         continue;
        }

      // State 2: pullback to the broken level that holds -> entry.
      bool touched = dir > 0 ? l1 <= tkBreak[k] + 3 * pip : h1 >= tkBreak[k] - 3 * pip;
      bool holds = dir > 0 ? (c1 > tkBreak[k] && c1 > o1) : (c1 < tkBreak[k] && c1 < o1);
      if(touched && holds)
        {
         if(mayEnter) Enter(dir, tkExtreme[k], "Tokmat shadow", InpTkMinSLPips * pip, InpTkMaxSLPips * pip);
         else Tally("Tokmat: setup outside session/limits");
         tkState[k] = 0;
        }
      else if((dir > 0 && c1 < tkExtreme[k]) || (dir < 0 && c1 > tkExtreme[k]))
         tkState[k] = 0;
     }
  }

//+------------------------------------------------------------------+
void ManageBreakeven()
  {
   if(InpBreakevenR <= 0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(sl == 0 || tp == 0 || (sl - open) * dir >= 0) continue;
      double risk = MathAbs(tp - open) / InpTPR;
      double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if((price - open) * dir >= risk * InpBreakevenR)
         trade.PositionModify(t, NormalizeDouble(open + dir * 10 * point, digits), tp);
     }
  }

void OnTick()
  {
   ManageBreakeven();
   datetime bar = iTime(_Symbol, SignalTF(), 0);
   if(bar == 0 || bar == lastBar) return;
   lastBar = bar;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool mayEnter = dt.hour >= InpStartHour && dt.hour < InpEndHour && !HasPosition() &&
                   TradesToday() < InpMaxTradesPerDay && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
   if(InpStrategy == LAB_TOKMAT) { TokmatStep(mayEnter); return; }   // zone/structure tracking runs on every bar
   if(!mayEnter) return;

   if(InpStrategy == LAB_BBMA_REENTRY) BbmaReentry();
   else if(InpStrategy == LAB_BBMA_EXTREME) BbmaExtreme();
   else SrBounce();
  }
//+------------------------------------------------------------------+
