//+------------------------------------------------------------------+
//| XauScalper.mq5                                                   |
//| XAUUSD scalper: M15 EMA bias -> M5 pullback to EMA20 ->          |
//| Heikin Ashi flip trigger -> one order with checkpoint TPs.       |
//| v2: ADX trend-strength filter, strong-HA trigger, London-NY      |
//| overlap session, tighter SL.                                     |
//| Escape rules: daily loss, losing streak, equity kill switch,     |
//| time stop, spread/ATR-spike filters.                             |
//+------------------------------------------------------------------+
#property copyright "RJA9291"
#property link      "https://github.com/RJA9291/ForexEA"
#property version   "2.10"

#include <Trade/Trade.mqh>
#include <AurumRest.mqh>

input group "Risk"
input double InpRiskPercent     = 1.0;   // Risk per trade (% of equity)
input bool   InpAllowMinLot     = true;  // Use broker minimum lot when risk-based size is smaller
input double InpMaxRiskPercent  = 10.0;  // Hard cap on risk when forced to minimum lot (% of equity)
input int    InpMaxTradesPerDay = 6;
input double InpMaxDailyLossPct = 3.0;   // Stop for the day after this loss (% of balance)
input int    InpMaxConsecLosses = 3;     // Stop for the day after this many losses in a row
input double InpKillSwitchDDPct = 20.0;  // Halt until reset when equity falls this far below its peak

input group "Costs"
input int    InpMaxSpreadPoints = 100;   // Absolute spread cap (points)
input double InpMaxSpreadToSL   = 0.25;  // Skip if spread is more than this fraction of the SL distance

input group "Bias"
input ENUM_TIMEFRAMES InpBiasTF  = PERIOD_M15;
input int    InpBiasFastEMA     = 50;
input int    InpBiasSlowEMA     = 200;
input bool   InpUseADX          = true;  // Require a trending market on the bias timeframe
input int    InpADXPeriod       = 14;
input double InpMinADX          = 22;

input group "Entry"
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M5;
input int    InpPullbackEMA     = 20;
input int    InpATRPeriod       = 14;
input double InpTouchATR        = 0.3;   // Pullback must come within this many ATR of the EMA
input bool   InpRequireStrongHA = true;  // Trigger HA candle must have no wick against the trade
input int    InpSwingBars       = 3;     // SL goes beyond the extreme of this many bars
input double InpSLBufferATR     = 0.1;
input double InpMinSLPips       = 20;    // 1 pip = 0.10 on gold
input double InpMaxSLPips       = 45;
input double InpATRSpikeMult    = 2.5;   // Skip when ATR exceeds its baseline by this multiple (news spikes)
input int    InpATRBaseline     = 100;   // Bars used for the ATR baseline

input group "Checkpoint targets (one order, SL ratchets at each checkpoint)"
input double InpTP1R            = 1.0;   // TP1: SL moves to breakeven
input double InpTP2R            = 2.0;   // TP2: SL locks at TP1
input double InpTP3R            = 3.0;   // TP3: SL locks at TP2
input double InpFinalTPR        = 4.0;   // Final TP: the order's real take profit
input int    InpTimeStopBars    = 12;    // Close if TP1 not reached within this many entry bars (0 = off)

input group "Session (broker server time)"
input int    InpStartHour       = 15;    // 15-19 = London-NY overlap on a GMT+2 server (InstaForex winter time)
input int    InpEndHour         = 19;

input group "Clearance and signal app (live/demo only, ignored by the Strategy Tester)"
input bool   InpUseClearance    = true;  // Skip entries the clearance gate marks NOT_CLEARED (needs XauSignalEngine running)
input bool   InpPublish         = true;  // Send every trade to the signal app (Supabase)
input string InpSupabaseUrl     = "https://ukzbdszndqvgycsnjeof.supabase.co";
input int    InpContextMaxAgeSec = 300;  // Engine context older than this counts as missing

input group "General"
input ulong  InpMagic           = 920101;
input bool   InpGoldOnly        = true;
input bool   InpShowStatus      = true;

CTrade   trade;
int      hFast = INVALID_HANDLE;
int      hSlow = INVALID_HANDLE;
int      hEMA  = INVALID_HANDLE;
int      hATR  = INVALID_HANDLE;
int      hADX  = INVALID_HANDLE;
datetime lastEntryBar = 0;
string   lastReason = "";
ulong    trackedTicket = 0;
double   peakPips = 0;
bool     killSwitchLogged = false;
string   tallyNames[];
int      tallyCounts[];
string   peakVar;
bool     live = false;               // false in the Strategy Tester: no clearance, no publishing
CAurumRest rest;
string   pubStage = "";
datetime pubTime = 0;
datetime lastSync = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpGoldOnly && StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
     {
      Print("XauScalper: attach to XAUUSD/GOLD only (symbol is ", _Symbol, ")");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPercent <= 0 || InpMaxRiskPercent < InpRiskPercent || InpMinSLPips >= InpMaxSLPips ||
      !(0 < InpTP1R && InpTP1R < InpTP2R && InpTP2R < InpTP3R && InpTP3R < InpFinalTPR))
      return INIT_PARAMETERS_INCORRECT;

   hFast = iMA(_Symbol, InpBiasTF, InpBiasFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpBiasTF, InpBiasSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEMA  = iMA(_Symbol, InpEntryTF, InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   hADX  = iADX(_Symbol, InpBiasTF, InpADXPeriod);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hEMA == INVALID_HANDLE ||
      hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);

   // Equity peak survives restarts; delete this global variable (F3) to reset the kill switch.
   peakVar = StringFormat("XSC_peak_%I64u", InpMagic);
   if(!GlobalVariableCheck(peakVar))
      GlobalVariableSet(peakVar, AccountInfoDouble(ACCOUNT_EQUITY));

   live = !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION);
   if(live && InpPublish && !rest.Init(InpSupabaseUrl, "XauScalper"))
      Print("XauScalper: no SUPABASE_SERVICE_KEY in MQL5\\Files\\aurum.env - trades will not appear in the app.");

   PrintFormat("XauScalper spec: digits %d contract %g minLot %g tickValue %g spread %d stopsLevel %d",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hEMA  != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATR  != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX  != INVALID_HANDLE) IndicatorRelease(hADX);
   Comment("");
   for(int i = 0; i < ArraySize(tallyNames); i++)
      PrintFormat("XSC outcome: %-40s %d", tallyNames[i], tallyCounts[i]);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateEquityPeak();
   ManagePositions();
   if(live && rest.Ready() && TimeCurrent() - lastSync >= 10)
     {
      lastSync = TimeCurrent();
      SyncClosed();
     }

   datetime barTime = iTime(_Symbol, InpEntryTF, 0);
   if(barTime == 0 || barTime == lastEntryBar)
      return;
   lastEntryBar = barTime;
   Evaluate();
  }

//+------------------------------------------------------------------+
double Buf(const int handle, const int shift)
  {
   double b[1];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1)
      return EMPTY_VALUE;
   return b[0];
  }

double PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (digits >= 3 ? 100 : 10);
  }

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

void Status(const string header, const string outcome)
  {
   Tally(outcome);
   if(InpShowStatus) Comment(header + "\n" + outcome);
  }

//+------------------------------------------------------------------+
void UpdateEquityPeak()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > GlobalVariableGet(peakVar))
      GlobalVariableSet(peakVar, eq);
  }

bool KillSwitchActive()
  {
   double peak = GlobalVariableGet(peakVar);
   bool hit = peak > 0 && AccountInfoDouble(ACCOUNT_EQUITY) <= peak * (1.0 - InpKillSwitchDDPct / 100.0);
   if(hit && !killSwitchLogged)
     {
      PrintFormat("XauScalper KILL SWITCH: equity %.2f is %.1f%% below peak %.2f. Trading halted; delete global variable %s to reset.",
                  AccountInfoDouble(ACCOUNT_EQUITY), InpKillSwitchDDPct, peak, peakVar);
      killSwitchLogged = true;
     }
   return hit;
  }

//+------------------------------------------------------------------+
int Bias()
  {
   double fast = Buf(hFast, 1), slow = Buf(hSlow, 1);
   double close = iClose(_Symbol, InpBiasTF, 1);
   if(fast == EMPTY_VALUE || slow == EMPTY_VALUE || close == 0) return 0;
   if(fast > slow && close > fast) return 1;
   if(fast < slow && close < fast) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Heikin Ashi open/close for the last two closed entry bars.       |
//+------------------------------------------------------------------+
bool HeikinAshi(double &o1, double &c1, double &o2, double &c2, double &h1, double &l1)
  {
   const int n = 60;
   MqlRates r[];
   ArraySetAsSeries(r, false);   // oldest first; the last element is the forming bar
   if(CopyRates(_Symbol, InpEntryTF, 0, n, r) != n)
      return false;
   double haO = (r[0].open + r[0].close) / 2.0;
   double haC = (r[0].open + r[0].high + r[0].low + r[0].close) / 4.0;
   for(int i = 1; i < n; i++)
     {
      double nextO = (haO + haC) / 2.0;
      double nextC = (r[i].open + r[i].high + r[i].low + r[i].close) / 4.0;
      if(i == n - 3) { o2 = nextO; c2 = nextC; }
      if(i == n - 2)
        {
         o1 = nextO; c1 = nextC;
         h1 = MathMax(r[i].high, MathMax(nextO, nextC));
         l1 = MathMin(r[i].low, MathMin(nextO, nextC));
        }
      haO = nextO;
      haC = nextC;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void DailyStats(int &entries, double &closedPnl, int &lossStreak)
  {
   entries = 0; closedPnl = 0; lossStreak = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(dayStart, TimeCurrent() + 60))
      return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)   // chronological, so the streak ends on the latest deal
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) { entries++; continue; }
      double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                 HistoryDealGetDouble(d, DEAL_COMMISSION);
      closedPnl += p;
      lossStreak = (p < 0) ? lossStreak + 1 : 0;
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
bool SessionOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour <= InpEndHour)
      return dt.hour >= InpStartHour && dt.hour < InpEndHour;
   return dt.hour >= InpStartHour || dt.hour < InpEndHour;
  }

//+------------------------------------------------------------------+
void Evaluate()
  {
   if(HasOpenPosition())
      return;   // ManagePositions owns the status display while a trade runs

   int bias = Bias();
   double atr = Buf(hATR, 1);
   double ema = Buf(hEMA, 1);
   if(atr == EMPTY_VALUE || ema == EMPTY_VALUE || atr <= 0)
      return;

   string head = StringFormat("XauScalper | Bias %s | ATR(%s) %.2f",
                              bias > 0 ? "BUY" : (bias < 0 ? "SELL" : "NONE"),
                              EnumToString(InpEntryTF), atr);

   if(KillSwitchActive())        { Status(head, "KILL SWITCH - trading halted"); return; }
   if(!SessionOpen())            { Status(head, "Outside session"); return; }

   int entries, streak; double closedPnl;
   DailyStats(entries, closedPnl, streak);
   if(entries >= InpMaxTradesPerDay) { Status(head, "Daily trade limit reached"); return; }
   if(closedPnl <= -AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0)
                                 { Status(head, "Daily loss limit reached"); return; }
   if(streak >= InpMaxConsecLosses) { Status(head, "Losing streak - done for today"); return; }
   if(bias == 0)                 { Status(head, "No bias - standing aside"); return; }
   if(InpUseADX)
     {
      double adx = Buf(hADX, 1);
      if(adx == EMPTY_VALUE || adx < InpMinADX) { Status(head, "Weak trend (ADX) - standing aside"); return; }
     }

   double atrBuf[];
   if(CopyBuffer(hATR, 0, 1, InpATRBaseline, atrBuf) == InpATRBaseline)
     {
      double base = 0;
      for(int i = 0; i < InpATRBaseline; i++) base += atrBuf[i];
      base /= InpATRBaseline;
      if(atr > base * InpATRSpikeMult) { Status(head, "ATR spike - news/volatility filter"); return; }
     }

   double hao1 = 0, hac1 = 0, hao2 = 0, hac2 = 0, hah1 = 0, hal1 = 0;
   if(!HeikinAshi(hao1, hac1, hao2, hac2, hah1, hal1)) return;
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double c1 = iClose(_Symbol, InpEntryTF, 1);
   int lo3 = iLowest(_Symbol, InpEntryTF, MODE_LOW, 3, 1);
   int hi3 = iHighest(_Symbol, InpEntryTF, MODE_HIGH, 3, 1);
   double recentLow  = iLow(_Symbol, InpEntryTF, lo3);
   double recentHigh = iHigh(_Symbol, InpEntryTF, hi3);
   double pip = PipSize();

   bool trigger = false;
   double entry = 0, sl = 0;
   string pattern = "";
   if(bias > 0)
     {
      bool pulledBack = recentLow <= ema + InpTouchATR * atr;
      bool haFlip = hac2 < hao2 && hac1 > hao1;
      bool strong = !InpRequireStrongHA || hal1 >= hao1 - tol;
      trigger = pulledBack && haFlip && strong && c1 > ema;
      pattern = "HA bull candle after pullback to EMA" + IntegerToString(InpPullbackEMA);
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = iLow(_Symbol, InpEntryTF, iLowest(_Symbol, InpEntryTF, MODE_LOW, InpSwingBars, 1)) - InpSLBufferATR * atr;
     }
   else
     {
      bool pulledBack = recentHigh >= ema - InpTouchATR * atr;
      bool haFlip = hac2 > hao2 && hac1 < hao1;
      bool strong = !InpRequireStrongHA || hah1 <= hao1 + tol;
      trigger = pulledBack && haFlip && strong && c1 < ema;
      pattern = "HA bear candle after pullback to EMA" + IntegerToString(InpPullbackEMA);
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = iHigh(_Symbol, InpEntryTF, iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpSwingBars, 1)) + InpSLBufferATR * atr;
     }
   if(!trigger)                  { Status(head, "Waiting for HA flip at EMA"); return; }

   double risk = MathAbs(entry - sl);
   if(risk < InpMinSLPips * pip)
     {
      risk = InpMinSLPips * pip;
      sl = entry - bias * risk;
     }
   if(risk > InpMaxSLPips * pip) { Status(head, "SL too wide - skipped"); return; }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
   if(spread > InpMaxSpreadPoints * point || spread > risk * InpMaxSpreadToSL)
                                 { Status(head, "Spread too wide for this SL"); return; }
   if(risk <= SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point)
                                 { Status(head, "SL inside broker stop level"); return; }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tp = NormalizeDouble(entry + bias * risk * InpFinalTPR, digits);
   sl = NormalizeDouble(sl, digits);

   ENUM_ORDER_TYPE type = bias > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lots = LotsForRisk(risk, type, entry);
   if(lots <= 0)                 { Status(head, "Minimum lot exceeds risk cap - skipped"); return; }

   string clearStatus = "", clearChecks = "", regimeName = "";
   if(live)
     {
      clearStatus = Clearance(bias, clearChecks, regimeName);
      if(InpUseClearance && clearStatus == "NOT_CLEARED")
                                 { Status(head, "Clearance NOT_CLEARED - skipped"); return; }
     }

   bool ok = bias > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, "XSC buy")
                      : trade.Sell(lots, _Symbol, 0, sl, tp, "XSC sell");
   if(ok)
     {
      lastReason = StringFormat("- %s bias (EMA%d/%d)\n- %s\n- SL %.0f pip beyond %d-bar swing",
                                EnumToString(InpBiasTF), InpBiasFastEMA, InpBiasSlowEMA, pattern,
                                risk / pip, InpSwingBars);
      Tally("Trade opened");
      if(live && rest.Ready())
         PublishOpen(trade.ResultOrder(), bias, trade.ResultPrice() > 0 ? trade.ResultPrice() : entry, sl, lots,
                     pattern, spread, clearStatus, clearChecks, regimeName);
     }
   else
      Status(head, "Order failed - see Experts log");
   PrintFormat("XauScalper %s %.2f lots @%.2f SL %.2f TP %.2f -> %s (%d) | %s",
               bias > 0 ? "BUY" : "SELL", lots, entry, sl, tp, ok ? "sent" : "failed",
               trade.ResultRetcode(), pattern);
  }

//+------------------------------------------------------------------+
void ManagePositions()
  {
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

      int    dir   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
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
         peakPips = 0;
         int bars = Bars(_Symbol, PERIOD_M1, opened, TimeCurrent());
         if(bars > 0)
           {
            double ext = dir > 0 ? iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, bars, 0))
                                 : iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, bars, 0));
            peakPips = MathMax(0, (ext - open) * dir / pip);
           }
        }
      peakPips = MathMax(peakPips, runPips);
      double best = open + dir * peakPips * pip;

      bool hit1 = (best - tp1) * dir >= 0, hit2 = (best - tp2) * dir >= 0, hit3 = (best - tp3) * dir >= 0;

      if(!hit1 && InpTimeStopBars > 0 && iBarShift(_Symbol, InpEntryTF, opened) >= InpTimeStopBars)
        {
         if(trade.PositionClose(ticket))
            PrintFormat("XauScalper time stop: TP1 not reached in %d bars, closed at %+.1f pip", InpTimeStopBars, runPips);
         continue;
        }

      double lock = sl;
      string stage = "Running";
      if(hit3)      { lock = tp2;                     stage = "TP3 HIT - SL locked at TP2"; }
      else if(hit2) { lock = tp1;                     stage = "TP2 HIT - SL locked at TP1"; }
      else if(hit1) { lock = open + dir * 10 * point; stage = "TP1 HIT - BREAK EVEN SET"; }

      lock = NormalizeDouble(lock, digits);
      if((lock - sl) * dir > point && (price - lock) * dir > 0)
         if(trade.PositionModify(ticket, lock, tp))
            sl = lock;

      if(live && rest.Ready())
        {
         string code = hit3 ? "TP3" : (hit2 ? "TP2" : (hit1 ? "TP1" : "ACTIVE"));
         if(code != pubStage || TimeCurrent() - pubTime >= 60)
           {
            pubStage = code; pubTime = TimeCurrent();
            PublishUpdate(ticket, StringFormat("\"status\":%s,\"sl\":%s,\"running_pips\":%.1f,\"peak_pips\":%.1f",
                                               AurumJStr(code), DoubleToString(sl, digits), runPips, peakPips));
           }
        }

      if(InpShowStatus)
         Comment(StringFormat("XAUUSD %s  |  %s\nRUNNING %+.1f pip   (peak %+.1f)\nENTRY %.2f   SL %.2f\n"
                              "TP1 %.2f %s   TP2 %.2f %s   TP3 %.2f %s   FINAL %.2f\nSIGNAL REASON\n%s",
                              dir > 0 ? "BUY" : "SELL", stage, runPips, peakPips, open, sl,
                              tp1, hit1 ? "[hit]" : "", tp2, hit2 ? "[hit]" : "", tp3, hit3 ? "[hit]" : "", tp,
                              lastReason == "" ? "(EA restarted - reason not kept)" : lastReason));
     }
   if(!found)
      trackedTicket = 0;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Clearance gate for scalper entries. Context comes from the       |
//| Signal Engine (global variables). News window is the hard stop;  |
//| fundamental bias against the trade with HIGH confidence, or      |
//| missing engine context, are soft failures (1 = CAUTION, 2 =      |
//| NOT_CLEARED). Regime is recorded only: no scalper regime data.   |
//| None of these checks is backtested for the scalper; the demo     |
//| records them so CLEARED vs CAUTION results can be compared.      |
//+------------------------------------------------------------------+
string CheckJson(const int id, const string name, const bool pass, const string detail)
  {
   return StringFormat("{\"id\":%d,\"name\":%s,\"pass\":%s,\"detail\":%s}", id, AurumJStr(name), pass ? "true" : "false", AurumJStr(detail));
  }

string Clearance(const int dir, string &checks, string &regimeName)
  {
   bool fresh = GlobalVariableCheck(AURUM_GV_TIME) &&
                (double)TimeLocal() - GlobalVariableGet(AURUM_GV_TIME) <= InpContextMaxAgeSec;
   bool news  = fresh && GlobalVariableGet(AURUM_GV_NEWS) > 0.5;
   int  fund  = fresh ? (int)MathRound(GlobalVariableGet(AURUM_GV_FUND)) : -9;
   bool high  = fresh && GlobalVariableGet(AURUM_GV_FUNDHI) > 0.5;
   regimeName = fresh ? AurumRegimeName((int)MathRound(GlobalVariableGet(AURUM_GV_REGIME))) : "";

   bool opposite = (dir > 0 && fund == -1) || (dir < 0 && fund == 1);
   string fundText = fund == -9 ? "No fundamental brief today" :
                     StringFormat("Bias %s%s%s", fund > 0 ? "BULLISH" : (fund < 0 ? "BEARISH" : "NEUTRAL"),
                                  high ? " (HIGH)" : "", opposite ? " against this side" : "");
   bool cNews = !news, cFund = !(opposite && high), cCtx = fresh;
   checks = "[" +
      CheckJson(1, "Regime", true, regimeName == "" ? "Regime unknown" : "Regime " + regimeName + " (recorded only, no scalper data per regime)") + "," +
      CheckJson(2, "News", cNews, !fresh ? "Unknown: Signal Engine context missing" :
                                  (news ? "Inside a HIGH-impact news window" : "No HIGH-impact news window now")) + "," +
      CheckJson(3, "Fundamental", cFund, fundText) + "," +
      CheckJson(4, "Engine context", cCtx, cCtx ? "Signal Engine context is current" : "Signal Engine not running or stale") + "]";
   int soft = (cFund ? 0 : 1) + (cCtx ? 0 : 1);
   return (!cNews || soft >= 2) ? "NOT_CLEARED" : (soft == 1 ? "CAUTION" : "CLEARED");
  }

//+------------------------------------------------------------------+
//| Signal app publishing. Each position maps to one signals row;    |
//| the row id is kept in global variable XSC_sig_<ticket> so the    |
//| close is still recorded after a terminal restart.                |
//+------------------------------------------------------------------+
string SigVar(const ulong ticket) { return StringFormat("XSC_sig_%I64u", ticket); }

void PublishOpen(const ulong ticket, const int dir, const double open, const double sl, const double lots,
                 const string pattern, const double spread, const string clearStatus, const string checks, const string regimeName)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pip = PipSize();
   double risk = MathAbs(open - sl);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskUsd = tickSize > 0 ? lots * risk / tickSize * tickValue : 0;
   if(risk <= 0) return;

   string reasons = "[" +
      AurumJStr(StringFormat("%s bias %s: EMA%d %s EMA%d and close %s EMA%d", EnumToString(InpBiasTF), dir > 0 ? "BUY" : "SELL",
                             InpBiasFastEMA, dir > 0 ? "above" : "below", InpBiasSlowEMA, dir > 0 ? "above" : "below", InpBiasFastEMA)) + "," +
      AurumJStr(pattern + StringFormat(" (pullback within %.1f ATR in the last 3 bars)", InpTouchATR)) + "," +
      AurumJStr(StringFormat("SL %.0f pip beyond the %d-bar swing. Checkpoints: %.0fR break even, %.0fR lock TP1, %.0fR lock TP2, final %.0fR",
                             risk / pip, InpSwingBars, InpTP1R, InpTP2R, InpTP3R, InpFinalTPR)) + "," +
      AurumJStr(StringFormat("Time stop: closes if %.0fR is not reached within %d bars", InpTP1R, InpTimeStopBars)) + "," +
      AurumJStr(StringFormat("Risk %.1f%% of equity: %.2f lots, $%.2f at SL", InpRiskPercent, lots, riskUsd)) + "," +
      AurumJStr(StringFormat("Spread %.0f points = %.0f%% of the SL distance", spread / SymbolInfoDouble(_Symbol, SYMBOL_POINT), spread / risk * 100.0)) + "," +
      AurumJStr("Demo forward test: the EA places and manages this trade itself") + "]";

   // XauScalper with the demo inputs (no ADX, no strong-HA, swing 5, SL max 60) over Nov 2025 - Nov 2026,
   // session 09-21 server: docs/backtests.md variant E; win rate from tester/spread_sensitivity.py.
   string stats = "{\"source\":\"backtest Nov 2025 - Nov 2026, session 09-21 server\",\"trades\":357,\"win_rate\":41.2,"
                  "\"pf\":0.65,\"return_pct\":-47.4,\"verdict\":\"LOSING\"}";
   string clearance = clearStatus == "" ? "null" :
                      StringFormat("{\"status\":%s,\"stage\":\"AT_ENTRY\",\"checks\":%s,\"decided_at\":%s}",
                                   AurumJStr(clearStatus), checks, AurumJStr(AurumIso(TimeGMT())));
   string body = StringFormat("{\"strategy\":\"M5_SCALPER\",\"symbol\":%s,\"status\":\"ACTIVE\",\"side\":%s,"
                              "\"entry\":%s,\"sl\":%s,\"tp1\":%s,\"tp2\":%s,\"tp3\":%s,\"risk_pips\":%.1f,"
                              "\"lots\":%.2f,\"risk_usd\":%.2f,\"running_pips\":0,\"peak_pips\":0,\"regime\":%s,",
                              AurumJStr(_Symbol), AurumJStr(dir > 0 ? "BUY" : "SELL"),
                              DoubleToString(open, digits), DoubleToString(sl, digits),
                              DoubleToString(open + dir * risk * InpTP1R, digits), DoubleToString(open + dir * risk * InpTP2R, digits),
                              DoubleToString(open + dir * risk * InpFinalTPR, digits), risk / pip, lots, riskUsd,
                              regimeName == "" ? "null" : AurumJStr(regimeName)) +
                 "\"reasons\":" + reasons + ",\"stats\":" + stats + ",\"clearance\":" + clearance + "}";
   string resp;
   if(rest.Send("POST", "/rest/v1/signals", body, "return=representation", resp) < 300)
     {
      int p = StringFind(resp, "\"id\":");
      if(p >= 0) GlobalVariableSet(SigVar(ticket), (double)StringToInteger(StringSubstr(resp, p + 5, 20)));
     }
   pubStage = "ACTIVE"; pubTime = TimeCurrent();
  }

void PublishUpdate(const ulong ticket, const string fields)
  {
   if(!GlobalVariableCheck(SigVar(ticket))) return;
   long id = (long)GlobalVariableGet(SigVar(ticket));
   string resp;
   rest.Send("PATCH", "/rest/v1/signals?id=eq." + IntegerToString(id),
             "{" + fields + ",\"updated_at\":" + AurumJStr(AurumIso(TimeGMT())) + "}", "", resp);
  }

// Records the result of every published position that is no longer open.
void SyncClosed()
  {
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, "XSC_sig_") != 0) continue;
      ulong ticket = (ulong)StringToInteger(StringSubstr(name, 8));
      if(PositionSelectByTicket(ticket)) continue;
      if(!HistorySelectByPosition(ticket)) continue;

      double open = 0, exitPrice = 0, usd = 0;
      int dir = 0;
      long reason = -1;
      for(int k = 0; k < HistoryDealsTotal(); k++)
        {
         ulong d = HistoryDealGetTicket(k);
         if(d == 0) continue;
         usd += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            open = HistoryDealGetDouble(d, DEAL_PRICE);
            dir = HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_BUY ? 1 : -1;
           }
         else
           {
            exitPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            reason = HistoryDealGetInteger(d, DEAL_REASON);
           }
        }
      if(dir == 0 || exitPrice == 0) continue;   // history not synced yet; retry next pass

      double pips = (exitPrice - open) * dir / PipSize();
      string status = reason == DEAL_REASON_TP ? "CLOSED_TP" :
                      reason == DEAL_REASON_SL ? (pips < -2 ? "CLOSED_SL" : (pips <= 2 ? "CLOSED_BE" : "CLOSED_LOCK")) :
                      "CLOSED_TIME";
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      PublishUpdate(ticket, StringFormat("\"status\":%s,\"result_pips\":%.1f,\"running_pips\":%.1f,\"escape\":{\"note\":%s}",
                                         AurumJStr(status), pips, pips,
                                         AurumJStr(StringFormat("Closed at %s, demo P/L $%.2f", DoubleToString(exitPrice, digits), usd))));
      GlobalVariableDel(name);
      PrintFormat("XauScalper: published close of #%I64u: %s %+.1f pip ($%.2f)", ticket, status, pips, usd);
     }
  }
//+------------------------------------------------------------------+
