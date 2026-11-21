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

input group "General"
input ulong  InpMagic           = 920201;
input bool   InpGoldOnly        = true;
input bool   InpShowStatus      = true;

CTrade   trade;
datetime setupDay = 0;      // day for which orders were already handled
string   peakVar;
bool     killSwitchLogged = false;
string   tallyNames[];
int      tallyCounts[];
string   dayNote = "";

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

void OnDeinit(const int reason)
  {
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

   double lots = LotsForRisk(risk, ORDER_TYPE_BUY, buyAt);
   if(lots <= 0)                 { dayNote = "Minimum lot exceeds risk cap"; Tally(dayNote); return; }

   double buySL  = NormalizeDouble(buyAt - risk, digits);
   double buyTP  = NormalizeDouble(buyAt + risk * InpTPR, digits);
   double sellSL = NormalizeDouble(sellAt + risk, digits);
   double sellTP = NormalizeDouble(sellAt - risk * InpTPR, digits);

   bool okBuy  = trade.BuyStop(lots, buyAt, _Symbol, buySL, buyTP, ORDER_TIME_GTC, 0, "XLB buy");
   bool okSell = trade.SellStop(lots, sellAt, _Symbol, sellSL, sellTP, ORDER_TIME_GTC, 0, "XLB sell");
   dayNote = StringFormat("Range %.2f-%.2f (%.2f%%) | BUY STOP %.2f / SELL STOP %.2f | %.2f lots, risk %.0f pip",
                          lo, hi, rangePct, buyAt, sellAt, lots, risk / pip);
   PrintFormat("XauLondonBreakout %s | buy %s sell %s", dayNote, okBuy ? "ok" : "failed", okSell ? "ok" : "failed");
   Tally(okBuy && okSell ? "Orders placed" : "Order placement failed");
   if(!(okBuy && okSell))
      DeletePendings();
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
