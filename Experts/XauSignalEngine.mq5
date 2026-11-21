//+------------------------------------------------------------------+
//| XauSignalEngine.mq5                                              |
//| Signal-only engine for the ForexEA app. Computes the London      |
//| range breakout setup for XAUUSD, tracks it like a trade, and     |
//| publishes price + signal state to Supabase and MT5 push.         |
//| It NEVER places orders: the user decides and trades manually.    |
//+------------------------------------------------------------------+
#property copyright "RJA9291"
#property link      "https://github.com/RJA9291/ForexEA"
#property version   "1.00"

#include <XauRegime.mqh>

input group "Supabase (keep the service key out of the repo)"
input string InpSupabaseUrl     = "https://ukzbdszndqvgycsnjeof.supabase.co";   // also add under Tools > Options > Expert Advisors > Allow WebRequest
input string InpServiceKey      = "";    // service key; leave empty to read MQL5\Files\aurum.env instead
input int    InpPriceSeconds    = 5;     // how often the live price is pushed

input group "Position sizing shown in the signal"
input double InpAccountSize     = 100;   // your real trading account balance (USD)
input double InpRiskPercent     = 0.5;   // risk per trade (% of account)

input group "London breakout rules (same as the backtested EA)"
input int    InpRangeStartHour  = 3;
input int    InpRangeEndHour    = 8;
input int    InpCloseHour       = 21;
input double InpMinRangePct     = 0.30;
input double InpMaxRangePct     = 1.60;
input double InpBufferPips      = 5;
input double InpMaxSLPct        = 0.60;
input double InpBreakevenR      = 1.5;
input double InpTPR             = 2.5;

input group "News window (HIGH impact events from the daily brief)"
input int    InpNewsBeforeMin   = 30;    // avoid-trading window starts this many minutes before the event
input int    InpNewsAfterMin    = 30;    // and ends this many minutes after it

input group "Alerts"
input bool   InpPushNotify      = true;  // MT5 mobile push (Tools > Options > Notifications, MetaQuotes ID)

enum SigState { ST_NONE, ST_PENDING, ST_ACTIVE, ST_DONE };

string   serviceKey = "";          // InpServiceKey, or SUPABASE_SERVICE_KEY from MQL5\Files\aurum.env

SigState state = ST_NONE;
datetime sigDay = 0;
long     sigId = 0;
double   rangeHi = 0, rangeLo = 0;
double   buyAt = 0, sellAt = 0, risk = 0;
int      side = 0;                 // 1 buy, -1 sell
double   entry = 0, sl = 0, tp1 = 0, tp2 = 0;
double   peak = 0;
bool     beSet = false;
bool     escapeFlagged = false;
datetime lastM15 = 0;
datetime lastPush = 0;
string   newsRisk = "UNKNOWN";
datetime newsAt[];                 // HIGH impact event times (GMT)
string   newsTitle[];
bool     newsWarned[];
int      newsFetchHour = -1;
bool     inNewsWindow = false;
CXauRegime regime;
string   regimeNow = "";
string   fundBias = "";            // BULLISH / NEUTRAL / BEARISH from the fundamental agent
string   fundConf = "";
string   newsWindowText = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      return INIT_PARAMETERS_INCORRECT;
   serviceKey = InpServiceKey;
   if(serviceKey == "")
     {
      // The key file survives chart/profile resets, unlike EA inputs.
      int fh = FileOpen("aurum.env", FILE_READ | FILE_TXT | FILE_ANSI);
      if(fh != INVALID_HANDLE)
        {
         while(!FileIsEnding(fh))
           {
            string line = FileReadString(fh);
            if(StringFind(line, "SUPABASE_SERVICE_KEY=") == 0)
              {
               serviceKey = StringSubstr(line, 21);
               StringTrimLeft(serviceKey); StringTrimRight(serviceKey);
              }
           }
         FileClose(fh);
        }
     }
   if(InpSupabaseUrl == "" || serviceKey == "")
      Print("XauSignalEngine: Supabase URL/key empty - running with chart + push alerts only.");
   if(!regime.Init(_Symbol))
      return INIT_FAILED;
   EventSetTimer(MathMax(1, InpPriceSeconds));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   regime.Release();
   Comment("");
  }

//+------------------------------------------------------------------+
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

string Num(const double v)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return DoubleToString(v, digits);
  }

string JStr(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return "\"" + s + "\"";
  }

//+------------------------------------------------------------------+
//| Supabase REST                                                    |
//+------------------------------------------------------------------+
int Rest(const string method, const string path, const string body, const string prefer, string &response)
  {
   response = "";
   if(InpSupabaseUrl == "" || serviceKey == "")
      return -1;
   string headers = "apikey: " + serviceKey + "\r\n" +
                    "Authorization: Bearer " + serviceKey + "\r\n" +
                    "Content-Type: application/json\r\n";
   if(prefer != "") headers += "Prefer: " + prefer + "\r\n";
   char data[], result[];
   string resultHeaders;
   if(body != "")
     {
      StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
      ArrayResize(data, ArraySize(data) - 1);   // drop the terminating zero
     }
   ResetLastError();
   int code = WebRequest(method, InpSupabaseUrl + path, headers, 5000, data, result, resultHeaders);
   if(code == -1)
      PrintFormat("XauSignalEngine: WebRequest failed (%d). Add %s to Allow WebRequest list.", GetLastError(), InpSupabaseUrl);
   else
      response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(code >= 300)
      PrintFormat("XauSignalEngine: %s %s -> %d %s", method, path, code, response);
   return code;
  }

void PushPrice()
  {
   string resp;
   string body = StringFormat("{\"symbol\":%s,\"bid\":%s,\"ask\":%s,\"updated_at\":%s}",
                              JStr(_Symbol), Num(SymbolInfoDouble(_Symbol, SYMBOL_BID)),
                              Num(SymbolInfoDouble(_Symbol, SYMBOL_ASK)), JStr(TimeToIso(TimeGMT())));
   Rest("POST", "/rest/v1/market?on_conflict=symbol", body, "resolution=merge-duplicates", resp);
  }

//| Today's brief is written by the daily news task, keyed by the Malaysian date.
string JsonField(const string s, const string key, const int from, const int limit)
  {
   int p = StringFind(s, "\"" + key + "\":\"", from);
   if(p < 0 || (limit >= 0 && p > limit)) return "";
   int start = p + StringLen(key) + 4;
   int end = StringFind(s, "\"", start);
   return end > start ? StringSubstr(s, start, end - start) : "";
  }

void FetchNewsRisk()
  {
   MqlDateTime d;
   TimeToStruct(TimeGMT() + 8 * 3600, d);
   string resp;
   string path = StringFormat("/rest/v1/news_briefs?select=risk_level,events&brief_date=eq.%04d-%02d-%02d", d.year, d.mon, d.day);
   if(Rest("GET", path, "", "", resp) != 200) return;
   string level = JsonField(resp, "risk_level", 0, -1);
   newsRisk = level == "" ? "UNKNOWN" : level;

   // Postgres jsonb orders keys by length: at, time, title, impact - so each event's
   // fields sit between its "at" and the next one.
   datetime oldAt[]; bool oldWarned[];
   ArrayCopy(oldAt, newsAt); ArrayCopy(oldWarned, newsWarned);
   ArrayResize(newsAt, 0); ArrayResize(newsTitle, 0); ArrayResize(newsWarned, 0);
   int pos = StringFind(resp, "\"at\":\"");
   while(pos >= 0)
     {
      int next = StringFind(resp, "\"at\":\"", pos + 6);
      string at = JsonField(resp, "at", pos, pos);
      if(JsonField(resp, "impact", pos, next) == "HIGH" && StringLen(at) >= 19)
        {
         string t = StringSubstr(at, 0, 19);
         StringReplace(t, "-", ".");
         StringReplace(t, "T", " ");
         datetime when = StringToTime(t);
         int n = ArraySize(newsAt);
         ArrayResize(newsAt, n + 1); ArrayResize(newsTitle, n + 1); ArrayResize(newsWarned, n + 1);
         newsAt[n] = when;
         newsTitle[n] = JsonField(resp, "title", pos, next);
         newsWarned[n] = false;
         for(int k = 0; k < ArraySize(oldAt); k++) if(oldAt[k] == when) newsWarned[n] = oldWarned[k];
        }
      pos = next;
     }
  }

void UpdateRegime()
  {
   regimeNow = regime.Classify();
   string resp;
   // PATCH, not upsert: an insert attempt would fail the NOT NULL bid/ask columns.
   Rest("PATCH", "/rest/v1/market?symbol=eq." + _Symbol,
        "{\"regime\":" + JStr(regimeNow) + ",\"regime_detail\":" + regime.DetailJson() + "}", "", resp);
  }

void FetchFundamental()
  {
   fundBias = ""; fundConf = "";
   MqlDateTime d;
   TimeToStruct(TimeGMT() + 8 * 3600, d);
   string resp;
   string path = StringFormat("/rest/v1/fundamental_briefs?select=bias,confidence&brief_date=eq.%04d-%02d-%02d", d.year, d.mon, d.day);
   if(Rest("GET", path, "", "", resp) != 200) return;
   fundBias = JsonField(resp, "bias", 0, -1);
   fundConf = JsonField(resp, "confidence", 0, -1);
  }

void CheckNewsWindow()
  {
   MqlDateTime h;
   TimeToStruct(TimeCurrent(), h);
   if(h.hour != newsFetchHour) { newsFetchHour = h.hour; FetchNewsRisk(); UpdateRegime(); }

   bool was = inNewsWindow;
   inNewsWindow = false;
   datetime now = TimeGMT();
   for(int i = 0; i < ArraySize(newsAt); i++)
     {
      long diff = (long)(newsAt[i] - now);
      if(diff > InpNewsBeforeMin * 60 || diff < -InpNewsAfterMin * 60) continue;
      inNewsWindow = true;
      newsWindowText = StringFormat("AVOID TRADING: %s at %s MYT (window -%d/+%d min)", newsTitle[i],
                                    TimeToString(newsAt[i] + 8 * 3600, TIME_MINUTES), InpNewsBeforeMin, InpNewsAfterMin);
      if(!newsWarned[i]) { newsWarned[i] = true; Notify(newsWindowText); }
     }
   if(inNewsWindow != was && (state == ST_PENDING || state == ST_ACTIVE))
      SaveSignal(state == ST_PENDING ? "PENDING" : StatusText(),
                 (state == ST_ACTIVE ? TradeFields() + "," : "") + NewsEscape());
  }

string NewsEscape()
  {
   if(!inNewsWindow) return "\"escape\":null";
   return "\"escape\":{\"rule\":\"NEWS_WINDOW\",\"tested\":false,\"advice\":" +
          JStr(newsWindowText + ". Do not enter new trades; consider protecting open ones.") + "}";
  }

string TimeToIso(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.mon, d.day, d.hour, d.min, d.sec);
  }

//+------------------------------------------------------------------+
//| Signal payload                                                   |
//+------------------------------------------------------------------+
string StatusText()
  {
   if(state == ST_PENDING) return "PENDING";
   if(state == ST_ACTIVE)  return beSet ? "TP1" : "ACTIVE";
   return "";
  }

string ReasonsJson()
  {
   double mid = (rangeHi + rangeLo) / 2.0;
   string r = "[";
   r += JStr(StringFormat("Asian range %s-%s (%.2f%% of price, within %.2f-%.2f%%)", Num(rangeLo), Num(rangeHi),
                          (rangeHi - rangeLo) / mid * 100.0, InpMinRangePct, InpMaxRangePct)) + ",";
   r += JStr("Breakout of the 03:00-08:00 server range at London open (08:00 server = 14:00 MYT)") + ",";
   r += JStr(RegimeReason()) + ",";
   r += JStr(StringFormat("Risk %.0f pip, BE at %.1fR, target %.1fR", risk / PipSize(), InpBreakevenR, InpTPR)) + ",";
   r += JStr("Backtest closes open trades at 21:00 server (03:00 MYT)");
   if(newsRisk == "HIGH")
      r += "," + JStr("News risk HIGH today: major release can whipsaw the breakout (news filter not yet backtested - see Berita tab)");
   else if(newsRisk == "UNKNOWN")
      r += "," + JStr("No news brief for today yet");
   if(fundBias != "")
     {
      string favours = fundBias == "BULLISH" ? " - favours the BUY STOP side" : (fundBias == "BEARISH" ? " - favours the SELL STOP side" : "");
      r += "," + JStr(StringFormat("Fundamental bias %s (%s confidence)%s; AI context, not backtested", fundBias, fundConf, favours));
     }
   return r + "]";
  }

string StatsJson()
  {
   // Backtest 2024-01-02 to 2026-11-20, InstaForex data, generated ticks, 1% risk (docs/backtests.md).
   return "{\"source\":\"backtest 2024-2026\",\"trades\":543,\"win_rate\":47.5,"
          "\"by_year\":[{\"year\":2024,\"win_rate\":48.2,\"pf\":1.12},"
          "{\"year\":2025,\"win_rate\":44.8,\"pf\":1.15},{\"year\":2026,\"win_rate\":49.7,\"pf\":1.46}],"
          "\"max_drawdown_pct\":23.7,\"regime\":" + RegimeStatsJson() + "}";
  }

// London breakout per regime, backtest 2024-01-02 to 2026-11-20 (docs/backtests.md).
// Only TREND_UP lost money in both halves (PF 0.79 in 2024-25, 0.91 in 2026).
string RegimeStatsJson()
  {
   string name = regimeNow, verdict = "INCONSISTENT";
   int trades = 0; double win = 0, pf = 0, pfA = 0, pfB = 0;
   if(name == "RANGING")    { trades = 78;  win = 53.8; pf = 1.90; pfA = 1.11; pfB = 3.64; verdict = "PROFITABLE_BOTH"; }
   if(name == "MIXED")      { trades = 178; win = 50.6; pf = 1.26; pfA = 1.07; pfB = 1.47; verdict = "PROFITABLE_BOTH"; }
   if(name == "TREND_UP")   { trades = 168; win = 37.5; pf = 0.82; pfA = 0.79; pfB = 0.91; verdict = "LOSING_BOTH"; }
   if(name == "HIGH_VOL")   { trades = 57;  win = 59.6; pf = 2.10; pfA = 3.69; pfB = 0.50; }
   if(name == "TREND_DOWN") { trades = 62;  win = 46.8; pf = 1.45; pfA = 0.68; pfB = 1.57; }
   if(trades == 0) return "null";
   return StringFormat("{\"name\":%s,\"trades\":%d,\"win_rate\":%.1f,\"pf\":%.2f,\"pf_2024_25\":%.2f,\"pf_2026\":%.2f,\"verdict\":%s}",
                       JStr(name), trades, win, pf, pfA, pfB, JStr(verdict));
  }

string RegimeReason()
  {
   if(regimeNow == "TREND_UP")
      return "Regime TREND_UP: London breakout lost in both 2024-25 (PF 0.79) and 2026 (PF 0.91) - historically better to skip";
   if(regimeNow == "RANGING" || regimeNow == "MIXED")
      return "Regime " + regimeNow + ": London breakout was profitable in both 2024-25 and 2026";
   if(regimeNow == "HIGH_VOL" || regimeNow == "TREND_DOWN")
      return "Regime " + regimeNow + ": backtest results differ between 2024-25 and 2026 - no reliable edge either way";
   return "Regime unknown (not enough data)";
  }

double SuggestedLots(double &riskUsd)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0 || risk <= 0) { riskUsd = 0; return 0; }
   double lossPerLot = risk / tickSize * tickValue;
   double lots = MathFloor(InpAccountSize * InpRiskPercent / 100.0 / lossPerLot / step) * step;
   lots = MathMax(lots, minLot);   // shown with its real dollar risk so the user can judge
   riskUsd = lots * lossPerLot;
   return NormalizeDouble(lots, 2);
  }

string BasePayload()
  {
   double riskUsd;
   double lots = SuggestedLots(riskUsd);
   return StringFormat("\"regime\":%s,", JStr(regimeNow)) +
          StringFormat("\"symbol\":%s,\"strategy\":\"LONDON_BREAKOUT\",\"buy_entry\":%s,\"sell_entry\":%s,"
                       "\"risk_pips\":%.1f,\"lots\":%.2f,\"risk_usd\":%.2f,\"reasons\":%s,\"stats\":%s,\"news_risk\":%s",
                       JStr(_Symbol), Num(buyAt), Num(sellAt), risk / PipSize(), lots, riskUsd,
                       ReasonsJson(), StatsJson(), JStr(newsRisk));
  }

void SaveSignal(const string status, const string extra)
  {
   string resp;
   string body = "{\"status\":" + JStr(status) + "," + BasePayload() + (extra != "" ? "," + extra : "") +
                 ",\"updated_at\":" + JStr(TimeToIso(TimeGMT())) + "}";
   if(sigId == 0)
     {
      if(Rest("POST", "/rest/v1/signals", body, "return=representation", resp) < 300)
        {
         int p = StringFind(resp, "\"id\":");
         if(p >= 0) sigId = StringToInteger(StringSubstr(resp, p + 5, 20));
        }
     }
   else
      Rest("PATCH", "/rest/v1/signals?id=eq." + IntegerToString(sigId), body, "", resp);
   lastPush = TimeCurrent();
  }

string TradeFields()
  {
   double pip = PipSize();
   double price = side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return StringFormat("\"side\":%s,\"entry\":%s,\"sl\":%s,\"tp1\":%s,\"tp2\":%s,\"running_pips\":%.1f,\"peak_pips\":%.1f",
                       JStr(side > 0 ? "BUY" : "SELL"), Num(entry), Num(sl), Num(tp1), Num(tp2),
                       (price - entry) * side / pip, peak);
  }

void Notify(const string text)
  {
   Print("XauSignalEngine: ", text);
   if(InpPushNotify) SendNotification("XAUUSD " + text);
  }

//+------------------------------------------------------------------+
//| Setup and tracking                                               |
//+------------------------------------------------------------------+
void ResetDay(const datetime day)
  {
   state = ST_NONE; sigDay = day; sigId = 0; side = 0; peak = 0;
   beSet = false; escapeFlagged = false;
  }

bool BuildRange()
  {
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, day + InpRangeStartHour * 3600, day + InpRangeEndHour * 3600 - 1, r);
   if(n < 12) return false;
   rangeHi = r[0].high; rangeLo = r[0].low;
   for(int i = 1; i < n; i++) { rangeHi = MathMax(rangeHi, r[i].high); rangeLo = MathMin(rangeLo, r[i].low); }
   return true;
  }

void CreateSetup()
  {
   if(!BuildRange()) { Comment("XauSignalEngine: no range data today"); state = ST_DONE; return; }
   FetchNewsRisk();
   FetchFundamental();
   UpdateRegime();
   double mid = (rangeHi + rangeLo) / 2.0;
   double pct = (rangeHi - rangeLo) / mid * 100.0;
   double pip = PipSize();
   buyAt  = rangeHi + InpBufferPips * pip;
   sellAt = rangeLo - InpBufferPips * pip;
   risk   = MathMin(buyAt - sellAt, mid * InpMaxSLPct / 100.0);

   if(pct < InpMinRangePct || pct > InpMaxRangePct)
     {
      string why = pct < InpMinRangePct ? "Range too narrow" : "Range too wide";
      SaveSignal("NO_TRADE", "\"escape\":{\"note\":" + JStr(why) + "}");
      Notify(StringFormat("NO TRADE today: %s (%.2f%%)", why, pct));
      state = ST_DONE;
      return;
     }
   state = ST_PENDING;
   SaveSignal("PENDING", inNewsWindow ? NewsEscape() : "");
   Notify(StringFormat("London setup: BUY STOP %s / SELL STOP %s, risk %.0f pip", Num(buyAt), Num(sellAt), risk / pip));
  }

void Trigger(const int dir)
  {
   side = dir;
   entry = dir > 0 ? buyAt : sellAt;
   sl  = entry - dir * risk;
   tp1 = entry + dir * risk * InpBreakevenR;
   tp2 = entry + dir * risk * InpTPR;
   state = ST_ACTIVE;
   SaveSignal("ACTIVE", TradeFields() + (inNewsWindow ? "," + NewsEscape() : ""));
   Notify(StringFormat("%s triggered @%s SL %s TP %s%s", dir > 0 ? "BUY" : "SELL", Num(entry), Num(sl), Num(tp2),
                       inNewsWindow ? " - INSIDE NEWS WINDOW, avoid entry" : ""));
  }

void Close(const string status, const double exitPrice)
  {
   double pips = (exitPrice - entry) * side / PipSize();
   state = ST_DONE;
   SaveSignal(status, TradeFields() + StringFormat(",\"result_pips\":%.1f", pips));
   Notify(StringFormat("%s closed: %s (%+.1f pip)", side > 0 ? "BUY" : "SELL", status, pips));
  }

void CheckEscape()
  {
   datetime m15 = iTime(_Symbol, PERIOD_M15, 0);
   if(m15 == lastM15) return;
   lastM15 = m15;
   if(state != ST_ACTIVE || beSet || escapeFlagged) return;
   double c = iClose(_Symbol, PERIOD_M15, 1);
   bool backInside = side > 0 ? c < rangeHi : c > rangeLo;
   if(!backInside) return;
   escapeFlagged = true;
   string advice = "M15 closed back inside the Asian range: breakout may be failing. "
                   "Escape rule A suggests exiting early. NOT YET BACKTESTED - informational only.";
   SaveSignal("ACTIVE", TradeFields() + ",\"escape\":{\"rule\":\"A_FAILED_BREAKOUT\",\"tested\":false,\"advice\":" + JStr(advice) + "}");
   Notify("ESCAPE WARNING: M15 back inside range (rule A, untested)");
  }

void Track()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(state == ST_PENDING)
     {
      if(ask >= buyAt) Trigger(1);
      else if(bid <= sellAt) Trigger(-1);
      return;
     }
   if(state != ST_ACTIVE) return;

   double price = side > 0 ? bid : ask;
   double pip = PipSize();
   peak = MathMax(peak, (price - entry) * side / pip);

   if((price - tp2) * side >= 0) { Close("CLOSED_TP", tp2); return; }
   if((price - sl) * side <= 0)  { Close(beSet ? "CLOSED_BE" : "CLOSED_SL", sl); return; }
   if(!beSet && (price - tp1) * side >= 0)
     {
      beSet = true;
      sl = entry;
      SaveSignal("TP1", TradeFields());
      Notify(StringFormat("TP1 HIT - move SL to break even %s", Num(entry)));
      return;
     }
   CheckEscape();
   if(TimeCurrent() - lastPush >= 15)
      SaveSignal(StatusText(), TradeFields());
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day != sigDay) ResetDay(day);
   int hour = ServerHour();

   if(state == ST_NONE && hour == InpRangeEndHour)
      CreateSetup();
   else if(state == ST_NONE && hour > InpRangeEndHour)
      state = ST_DONE;   // started after today's placement hour

   if(hour >= InpCloseHour)
     {
      if(state == ST_PENDING) { state = ST_DONE; SaveSignal("CANCELLED", ""); Notify("Setup cancelled: no breakout by session end"); }
      else if(state == ST_ACTIVE) Close("CLOSED_TIME", side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
     }
   else
      Track();

   Comment(StringFormat("XauSignalEngine (signals only, no orders)\nState %s | range %s-%s\nBUY STOP %s  SELL STOP %s  risk %.0f pip%s",
                        EnumToString(state), Num(rangeLo), Num(rangeHi), Num(buyAt), Num(sellAt),
                        risk / PipSize(), side != 0 ? StringFormat("\n%s @%s SL %s TP %s peak %+.1f pip",
                        side > 0 ? "BUY" : "SELL", Num(entry), Num(sl), Num(tp2), peak) : ""));
  }

void OnTimer()
  {
   PushPrice();
   CheckNewsWindow();   // runs on the timer so warnings fire even when no ticks arrive
  }
//+------------------------------------------------------------------+
