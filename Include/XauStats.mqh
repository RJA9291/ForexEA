//+------------------------------------------------------------------+
//| XauStats.mqh                                                     |
//| End-of-test statistics shared by the strategy backtest EAs:      |
//| per year, total with max closed-equity drawdown, and per regime  |
//| split 2024-2025 vs 2026+. The regime is read from the last word  |
//| of each entry deal's comment.                                    |
//+------------------------------------------------------------------+
#property strict

struct XauRegStat
  {
   string            name;
   int               n[2], w[2];
   double            gp[2], gl[2];
  };

double XauDealPL(const ulong d)
  {
   return HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
  }

void XauPrintStats(const ulong magic, const string tag)
  {
   if(!HistorySelect(0, TimeCurrent() + 60))
      return;
   int total = HistoryDealsTotal();
   double all = 0;
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != magic || HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;
      all += XauDealPL(d);
     }

   int years[], trades[], wins[];
   double gross[], loss[];
   long posIds[];
   string posReg[];
   XauRegStat st[];
   double equity = AccountInfoDouble(ACCOUNT_BALANCE) - all, peak = equity, maxDD = 0;

   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != magic) continue;
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
      double p = XauDealPL(d);
      MqlDateTime dt;
      TimeToStruct((datetime)HistoryDealGetInteger(d, DEAL_TIME), dt);

      int y = -1;
      for(int j = 0; j < ArraySize(years); j++) if(years[j] == dt.year) y = j;
      if(y < 0)
        {
         y = ArraySize(years);
         ArrayResize(years, y + 1); ArrayResize(trades, y + 1); ArrayResize(wins, y + 1);
         ArrayResize(gross, y + 1); ArrayResize(loss, y + 1);
         years[y] = dt.year; trades[y] = 0; wins[y] = 0; gross[y] = 0; loss[y] = 0;
        }
      trades[y]++;
      if(p > 0) { wins[y]++; gross[y] += p; } else loss[y] -= p;
      equity += p;
      peak = MathMax(peak, equity);
      maxDD = MathMax(maxDD, (peak - equity) / peak);

      string reg = "UNKNOWN";
      for(int k = 0; k < ArraySize(posIds); k++) if(posIds[k] == pos) { reg = posReg[k]; break; }
      int r = -1;
      for(int k = 0; k < ArraySize(st); k++) if(st[k].name == reg) { r = k; break; }
      if(r < 0)
        {
         r = ArraySize(st);
         ArrayResize(st, r + 1);
         st[r].name = reg;
         for(int q = 0; q < 2; q++) { st[r].n[q] = 0; st[r].w[q] = 0; st[r].gp[q] = 0; st[r].gl[q] = 0; }
        }
      int per = dt.year <= 2025 ? 0 : 1;
      st[r].n[per]++;
      if(p > 0) { st[r].w[per]++; st[r].gp[per] += p; } else st[r].gl[per] -= p;
     }

   for(int j = 0; j < ArraySize(years); j++)
      PrintFormat("%s year %d: trades %d, win %.1f%%, net %.2f, PF %.2f", tag, years[j], trades[j],
                  100.0 * wins[j] / MathMax(1, trades[j]), gross[j] - loss[j], loss[j] > 0 ? gross[j] / loss[j] : 0.0);
   PrintFormat("%s total: net %.2f, max closed-equity drawdown %.1f%%", tag, all, 100.0 * maxDD);
   for(int r = 0; r < ArraySize(st); r++)
     {
      int n = st[r].n[0] + st[r].n[1], w = st[r].w[0] + st[r].w[1];
      double gp = st[r].gp[0] + st[r].gp[1], gl = st[r].gl[0] + st[r].gl[1];
      PrintFormat("%s regime %-10s all: %3d trades win %5.1f%% net %9.2f PF %.2f | 2024-25: %3d win %5.1f%% PF %.2f | 2026: %3d win %5.1f%% PF %.2f",
                  tag, st[r].name, n, 100.0 * w / MathMax(1, n), gp - gl, gl > 0 ? gp / gl : 0.0,
                  st[r].n[0], 100.0 * st[r].w[0] / MathMax(1, st[r].n[0]), st[r].gl[0] > 0 ? st[r].gp[0] / st[r].gl[0] : 0.0,
                  st[r].n[1], 100.0 * st[r].w[1] / MathMax(1, st[r].n[1]), st[r].gl[1] > 0 ? st[r].gp[1] / st[r].gl[1] : 0.0);
     }
  }
//+------------------------------------------------------------------+
