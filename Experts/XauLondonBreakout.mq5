//+------------------------------------------------------------------+
//| XauLondonBreakout.mq5                                            |
//| XAUUSD London range breakout: Asian range (03:00-08:00 server),  |
//| OCO buy/sell stops at 08:00, SL at the opposite side (capped),   |
//| TP 2.5R, breakeven at 1.5R, flat by 21:00, one trade per day.    |
//| Based on rules published at mql5.com/en/blogs/post/777540.       |
//+------------------------------------------------------------------+
#property copyright "RJA9291"
#property link      "https://github.com/RJA9291/ForexEA"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <XauRegime.mqh>

input group "Risk"
input double InpRiskPercent     = 1.0;   // Risk per trade (% of equity)
input bool   InpAllowMinLot     = true;  // Use broker minimum lot when risk-based size is smaller
input double InpMaxRiskPercent  = 10.0;  // Hard cap on risk when forced to minimum lot (% of equity)
input double InpKillSwitchDDPct = 20.0;  // Halt until reset when equity falls this far below its peak

input group "Range (broker server time)"
input int    InpRangeStartHour  = 3;
input int    InpRangeEndHour    = 8;     // Orders are placed when this hour starts
input int    InpCloseHour       = 21;    // Pending orders deleted and positions closed
input double InpMinRangePct     = 0.30;  // Skip the day if the range is narrower (% of price)
input double InpMaxRangePct     = 1.60;  // Skip the day if the range is wider (% of price)
input double InpBufferPips      = 5;     // Entry distance beyond the range (1 pip = 0.10)

input group "Exits"
input double InpMaxSLPct        = 0.60;  // SL distance cap (% of price)
input double InpTPR             = 2.5;   // Take profit in R
input double InpBreakevenR      = 1.5;   // Move SL to breakeven at this R (0 = off)
input int    InpMaxSpreadPoints = 150;   // Skip the day if spread at placement is wider

enum EscapeMode
  {
   ESC_NONE    = 0,   // No escape: SL / TP / breakeven / 21:00 only
   ESC_FAILED  = 1,   // A: exit when an M15 bar closes back inside the Asian range before breakeven
   ESC_TIME    = 2,   // B: exit if not at least InpTimeStopMinR in profit after InpTimeStopHours
   ESC_REVERSE = 3    // C: like A, then open the opposite side once (same risk, same exits)
  };
input group "Escape rules (under test)"
input EscapeMode InpEscapeMode  = ESC_NONE;
input int    InpTimeStopHours   = 3;
input double InpTimeStopMinR    = 0.5;

input group "General"
input ulong  InpMagic           = 920201;
input bool   InpGoldOnly        = true;
input bool   InpShowStatus      = true;

CTrade   trade;
CXauRegime regime;
datetime setupDay = 0;      // day for which orders were already handled
string   peakVar;
bool     killSwitchLogged = false;
string   tallyNames[];
int      tallyCounts[];
string   dayNote = "";
double   dayRangeHi = 0, dayRangeLo = 0;   // today's Asian range, for escape rule A/C
bool     reversedToday = false;
datetime lastEscapeBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpGoldOnly && StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
     {
      Print("XauLondonBreakout: attach to XAUUSD/GOLD only (symbol is ", _Symbol, ")");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPercent <= 0 || InpMaxRiskPercent < InpRiskPercent || InpTPR <= 0 ||
      InpRangeStartHour >= InpRangeEndHour || InpRangeEndHour >= InpCloseHour || InpMinRangePct >= InpMaxRangePct)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   if(!regime.Init(_Symbol))
      return INIT_FAILED;

   // Equity peak survives restarts; delete this global variable (F3) to reset the kill switch.
   peakVar = StringFormat("XLB_peak_%I64u", InpMagic);
   if(!GlobalVariableCheck(peakVar))
      GlobalVariableSet(peakVar, AccountInfoDouble(ACCOUNT_EQUITY));

   PrintFormat("XauLondonBreakout spec: digits %d contract %g minLot %g tickValue %g spread %d stopsLevel %d",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Per-year results from this EA's closed deals (for tester logs).  |
//+------------------------------------------------------------------+
void PrintStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 60))
      return;
   int total = HistoryDealsTotal();
   double net[], gross[], loss[];
   int years[], trades[], wins[];
   double all = 0;
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;
      all += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
             HistoryDealGetDouble(d, DEAL_COMMISSION);
     }

   double equity = AccountInfoDouble(ACCOUNT_BALANCE) - all;
   double peak = equity, maxDD = 0;
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;
      double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                 HistoryDealGetDouble(d, DEAL_COMMISSION);
      MqlDateTime dt;
      TimeToStruct((datetime)HistoryDealGetInteger(d, DEAL_TIME), dt);
      int k = -1;
      for(int j = 0; j < ArraySize(years); j++) if(years[j] == dt.year) k = j;
      if(k < 0)
        {
         k = ArraySize(years);
         ArrayResize(years, k + 1); ArrayResize(trades, k + 1); ArrayResize(wins, k + 1);
         ArrayResize(net, k + 1); ArrayResize(gross, k + 1); ArrayResize(loss, k + 1);
         years[k] = dt.year; trades[k] = 0; wins[k] = 0; net[k] = 0; gross[k] = 0; loss[k] = 0;
        }
      trades[k]++;
      net[k] += p;
      if(p > 0) { wins[k]++; gross[k] += p; } else loss[k] -= p;
      equity += p;
      peak = MathMax(peak, equity);
      maxDD = MathMax(maxDD, (peak - equity) / peak);
     }
   for(int j = 0; j < ArraySize(years); j++)
      PrintFormat("XLB year %d: trades %d, win %.1f%%, net %.2f, PF %.2f",
                  years[j], trades[j], 100.0 * wins[j] / MathMax(1, trades[j]), net[j],
                  loss[j] > 0 ? gross[j] / loss[j] : 0.0);
   PrintFormat("XLB total: net %.2f, max closed-equity drawdown %.1f%%", all, 100.0 * maxDD);
  }

//+------------------------------------------------------------------+
//| Results per regime, split 2024-2025 (in-sample) vs 2026+.        |
//+------------------------------------------------------------------+
struct RegStat
  {
   string            name;
   int               n[2], w[2];
   double            gp[2], gl[2];
  };

void PrintRegimeStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 60))
      return;
   int total = HistoryDealsTotal();
   long posIds[];
   string posReg[];
   RegStat st[];
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long pos = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         string c = HistoryDealGetString(d, DEAL_COMMENT);
         int sp = StringLen(c) - 1;
         while(sp >= 0 && StringGetCharacter(c, sp) != ' ') sp--;
         int k = ArraySize(posIds);
         ArrayResize(posIds, k + 1); ArrayResize(posReg, k + 1);
         posIds[k] = pos;
         posReg[k] = sp >= 0 ? StringSubstr(c, sp + 1) : "UNKNOWN";
         continue;
        }
      string reg = "UNKNOWN";
      for(int k = 0; k < ArraySize(posIds); k++) if(posIds[k] == pos) { reg = posReg[k]; break; }
      int r = -1;
      for(int k = 0; k < ArraySize(st); k++) if(st[k].name == reg) { r = k; break; }
      if(r < 0)
        {
         r = ArraySize(st);
         ArrayResize(st, r + 1);
         st[r].name = reg;
         for(int p = 0; p < 2; p++) { st[r].n[p] = 0; st[r].w[p] = 0; st[r].gp[p] = 0; st[r].gl[p] = 0; }
        }
      MqlDateTime dt;
      TimeToStruct((datetime)HistoryDealGetInteger(d, DEAL_TIME), dt);
      int p = dt.year <= 2025 ? 0 : 1;
      double pl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                  HistoryDealGetDouble(d, DEAL_COMMISSION);
      st[r].n[p]++;
      if(pl > 0) { st[r].w[p]++; st[r].gp[p] += pl; } else st[r].gl[p] -= pl;
     }
   for(int r = 0; r < ArraySize(st); r++)
     {
      int n = st[r].n[0] + st[r].n[1], w = st[r].w[0] + st[r].w[1];
      double gp = st[r].gp[0] + st[r].gp[1], gl = st[r].gl[0] + st[r].gl[1];
      PrintFormat("XLB regime %-10s all: %3d trades win %5.1f%% net %9.2f PF %.2f | 2024-25: %3d win %5.1f%% PF %.2f | 2026: %3d win %5.1f%% PF %.2f",
                  st[r].name, n, 100.0 * w / MathMax(1, n), gp - gl, gl > 0 ? gp / gl : 0.0,
                  st[r].n[0], 100.0 * st[r].w[0] / MathMax(1, st[r].n[0]), st[r].gl[0] > 0 ? st[r].gp[0] / st[r].gl[0] : 0.0,
                  st[r].n[1], 100.0 * st[r].w[1] / MathMax(1, st[r].n[1]), st[r].gl[1] > 0 ? st[r].gp[1] / st[r].gl[1] : 0.0);
     }
  }

void OnDeinit(const int reason)
  {
   PrintStats();
   PrintRegimeStats();
   regime.Release();
   Comment("");
   for(int i = 0; i < ArraySize(tallyNames); i++)
      PrintFormat("XLB outcome: %-40s %d", tallyNames[i], tallyCounts[i]);
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

double PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (digits >= 3 ? 100 : 10);
  }

int ServerHour()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
  }

//+------------------------------------------------------------------+
bool KillSwitchActive()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GlobalVariableGet(peakVar);
   if(eq > peak) { GlobalVariableSet(peakVar, eq); peak = eq; }
   bool hit = peak > 0 && eq <= peak * (1.0 - InpKillSwitchDDPct / 100.0);
   if(hit && !killSwitchLogged)
     {
      PrintFormat("XauLondonBreakout KILL SWITCH: equity %.2f is %.1f%% below peak %.2f. Halted; delete global variable %s to reset.",
                  eq, InpKillSwitchDDPct, peak, peakVar);
      killSwitchLogged = true;
     }
   return hit;
  }

//+------------------------------------------------------------------+
int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

void DeletePendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         trade.OrderDelete(t);
     }
  }

int CountPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(t);
     }
  }

//+------------------------------------------------------------------+
double LotsForRisk(const double riskDistance, const ENUM_ORDER_TYPE type, const double price)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0 || riskDistance <= 0)
      return 0;

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPerLot = riskDistance / tickSize * tickValue;
   double lots = MathFloor(equity * InpRiskPercent / 100.0 / lossPerLot / step) * step;
   if(lots < minLot)
     {
      if(!InpAllowMinLot || minLot * lossPerLot > equity * InpMaxRiskPercent / 100.0)
         return 0;
      lots = minLot;
     }
   lots = MathMin(lots, maxLot);

   double margin;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      return 0;
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Asian range from today's M5 bars between start and end hour.     |
//+------------------------------------------------------------------+
bool AsianRange(double &hi, double &lo)
  {
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   datetime from = day + InpRangeStartHour * 3600;
   datetime to   = day + InpRangeEndHour * 3600 - 1;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, from, to, r);
   if(n < 12)   // fewer than one hour of bars: data gap or holiday
      return false;
   hi = r[0].high;
   lo = r[0].low;
   for(int i = 1; i < n; i++)
     {
      hi = MathMax(hi, r[i].high);
      lo = MathMin(lo, r[i].low);
     }
   return true;
  }

//+------------------------------------------------------------------+
void PlaceDayOrders()
  {
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   setupDay = day;

   double hi, lo;
   if(!AsianRange(hi, lo))       { dayNote = "No range data"; Tally(dayNote); return; }
   dayRangeHi = hi;
   dayRangeLo = lo;
   reversedToday = false;

   double mid = (hi + lo) / 2.0;
   double rangePct = (hi - lo) / mid * 100.0;
   if(rangePct < InpMinRangePct) { dayNote = "Range too narrow"; Tally(dayNote); return; }
   if(rangePct > InpMaxRangePct) { dayNote = "Range too wide"; Tally(dayNote); return; }

   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
                                 { dayNote = "Spread too wide at placement"; Tally(dayNote); return; }

   double pip = PipSize();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpBufferPips * pip;
   double buyAt  = NormalizeDouble(hi + buffer, digits);
   double sellAt = NormalizeDouble(lo - buffer, digits);
   double cap    = mid * InpMaxSLPct / 100.0;
   double risk   = MathMin(buyAt - sellAt, cap);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask >= buyAt || bid <= sellAt)
                                 { dayNote = "Price already outside range at 08:00"; Tally(dayNote); return; }
   // Stop orders closer than the broker's stops level are rejected as invalid price.
   double minGap = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(buyAt - ask <= minGap || bid - sellAt <= minGap)
                                 { dayNote = "Price too close to range edge"; Tally(dayNote); return; }

   double lots = LotsForRisk(risk, ORDER_TYPE_BUY, buyAt);
   if(lots <= 0)                 { dayNote = "Minimum lot exceeds risk cap"; Tally(dayNote); return; }

   double buySL  = NormalizeDouble(buyAt - risk, digits);
   double buyTP  = NormalizeDouble(buyAt + risk * InpTPR, digits);
   double sellSL = NormalizeDouble(sellAt + risk, digits);
   double sellTP = NormalizeDouble(sellAt - risk * InpTPR, digits);

   // The regime travels in the order comment so PrintStats can group results by it.
   string reg = regime.Classify();
   bool okBuy  = trade.BuyStop(lots, buyAt, _Symbol, buySL, buyTP, ORDER_TIME_GTC, 0, "XLB buy " + reg);
   bool okSell = trade.SellStop(lots, sellAt, _Symbol, sellSL, sellTP, ORDER_TIME_GTC, 0, "XLB sell " + reg);
   Tally("Regime " + reg);
   dayNote = StringFormat("Range %.2f-%.2f (%.2f%%) | BUY STOP %.2f / SELL STOP %.2f | %.2f lots, risk %.0f pip",
                          lo, hi, rangePct, buyAt, sellAt, lots, risk / pip);
   PrintFormat("XauLondonBreakout %s | buy %s sell %s", dayNote, okBuy ? "ok" : "failed", okSell ? "ok" : "failed");
   Tally(okBuy && okSell ? "Orders placed" : "Order placement failed");
   if(!(okBuy && okSell))
      DeletePendings();
  }

//+------------------------------------------------------------------+
//| Escape rules A/B/C. Only act before breakeven: once SL is at     |
//| entry the trade can no longer lose, so there is nothing to save. |
//+------------------------------------------------------------------+
void CheckEscape()
  {
   if(InpEscapeMode == ESC_NONE)
      return;
   datetime m15 = iTime(_Symbol, PERIOD_M15, 0);
   bool newBar = m15 != lastEscapeBar;
   lastEscapeBar = m15;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      string comment = PositionGetString(POSITION_COMMENT);
      if(sl == 0 || tp == 0 || (sl - open) * dir >= 0) continue;

      double risk = MathAbs(tp - open) / InpTPR;
      double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(InpEscapeMode == ESC_TIME)
        {
         if(TimeCurrent() - opened >= InpTimeStopHours * 3600 && (price - open) * dir < InpTimeStopMinR * risk)
            if(trade.PositionClose(t)) Tally("Escape B: time stop");
         continue;
        }

      if(!newBar || StringFind(comment, "XLB rev") == 0) continue;   // reversal trades keep plain exits
      if(iTime(_Symbol, PERIOD_M15, 1) + 15 * 60 <= opened) continue;  // that bar closed before the entry
      double c = iClose(_Symbol, PERIOD_M15, 1);
      bool backInside = dir > 0 ? c < dayRangeHi : c > dayRangeLo;
      if(!backInside) continue;

      int sp = StringLen(comment) - 1;
      while(sp >= 0 && StringGetCharacter(comment, sp) != ' ') sp--;
      string reg = sp >= 0 ? StringSubstr(comment, sp + 1) : "UNKNOWN";

      if(!trade.PositionClose(t)) continue;
      Tally("Escape A: failed breakout exit");
      if(InpEscapeMode != ESC_REVERSE || reversedToday) continue;
      reversedToday = true;
      bool ok;
      if(dir > 0)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ok = trade.Sell(vol, _Symbol, 0, NormalizeDouble(bid + risk, digits), NormalizeDouble(bid - risk * InpTPR, digits), "XLB rev " + reg);
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         ok = trade.Buy(vol, _Symbol, 0, NormalizeDouble(ask - risk, digits), NormalizeDouble(ask + risk * InpTPR, digits), "XLB rev " + reg);
        }
      Tally(ok ? "Escape C: reversal opened" : "Escape C: reversal failed");
     }
  }

//+------------------------------------------------------------------+
void ManagePosition()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl == 0 || tp == 0 || InpBreakevenR <= 0) continue;
      if((sl - open) * dir >= 0) continue;   // already at or beyond breakeven

      // TP is never modified, so the original risk is recoverable from it.
      double risk = MathAbs(tp - open) / InpTPR;
      double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if((price - open) * dir >= risk * InpBreakevenR)
         trade.PositionModify(t, NormalizeDouble(open + dir * 10 * point, digits), tp);
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   int hour = ServerHour();
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   int positions = CountPositions();

   // OCO: once one side fills, the other side is cancelled.
   if(positions > 0 && CountPendings() > 0)
      DeletePendings();

   if(hour >= InpCloseHour)
     {
      if(CountPendings() > 0) DeletePendings();
      if(positions > 0) { CloseAll(); Tally("Closed at session end"); }
     }

   if(hour < InpCloseHour)
      CheckEscape();
   ManagePosition();

   if(day != setupDay && hour >= InpRangeEndHour && hour < InpCloseHour)
     {
      if(KillSwitchActive()) { setupDay = day; dayNote = "KILL SWITCH - halted"; Tally(dayNote); }
      else if(hour == InpRangeEndHour) PlaceDayOrders();
      else setupDay = day;   // EA started after the placement hour: wait for tomorrow
     }

   if(InpShowStatus)
      Comment(StringFormat("XauLondonBreakout | server %02d:00 | positions %d pending %d\n%s",
                           hour, positions, CountPendings(), dayNote));
  }
//+------------------------------------------------------------------+
