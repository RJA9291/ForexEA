//+------------------------------------------------------------------+
//| AurumRest.mqh - minimal Supabase REST client for EAs other than  |
//| the Signal Engine. Key comes from MQL5\Files\aurum.env           |
//| (SUPABASE_SERVICE_KEY=...), never from inputs or the repo.       |
//| WebRequest needs the Supabase URL in Tools > Options > Expert    |
//| Advisors > Allow WebRequest (already set for the Signal Engine). |
//+------------------------------------------------------------------+

class CAurumRest
  {
private:
   string            m_url;
   string            m_key;
   string            m_tag;

public:
   bool Init(const string url, const string tag)
     {
      m_url = url; m_tag = tag; m_key = "";
      int fh = FileOpen("aurum.env", FILE_READ | FILE_TXT | FILE_ANSI);
      if(fh != INVALID_HANDLE)
        {
         while(!FileIsEnding(fh))
           {
            string line = FileReadString(fh);
            if(StringFind(line, "SUPABASE_SERVICE_KEY=") == 0)
              {
               m_key = StringSubstr(line, 21);
               StringTrimLeft(m_key); StringTrimRight(m_key);
              }
           }
         FileClose(fh);
        }
      return Ready();
     }

   bool Ready() const { return m_url != "" && m_key != ""; }

   int Send(const string method, const string path, const string body, const string prefer, string &response)
     {
      response = "";
      if(!Ready()) return -1;
      string headers = "apikey: " + m_key + "\r\nAuthorization: Bearer " + m_key + "\r\nContent-Type: application/json\r\n";
      if(prefer != "") headers += "Prefer: " + prefer + "\r\n";
      char data[], result[];
      string resultHeaders;
      if(body != "")
        {
         StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
         ArrayResize(data, ArraySize(data) - 1);
        }
      ResetLastError();
      int code = WebRequest(method, m_url + path, headers, 5000, data, result, resultHeaders);
      if(code == -1)
         PrintFormat("%s: WebRequest failed (%d). Add %s to Allow WebRequest list.", m_tag, GetLastError(), m_url);
      else
         response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      if(code >= 300)
         PrintFormat("%s: %s %s -> %d %s", m_tag, method, path, code, response);
      return code;
     }
  };

string AurumJStr(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "");
   return "\"" + s + "\"";
  }

string AurumIso(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.mon, d.day, d.hour, d.min, d.sec);
  }

//+------------------------------------------------------------------+
//| Clearance context shared by XauSignalEngine through terminal     |
//| global variables, so other EAs need no news/fundamental fetches. |
//+------------------------------------------------------------------+
#define AURUM_GV_TIME    "AURUM_ctx_time"      // TimeLocal() of the engine's last write
#define AURUM_GV_NEWS    "AURUM_ctx_news"      // 1 = inside a HIGH-impact news window
#define AURUM_GV_REGIME  "AURUM_ctx_regime"    // see AurumRegimeName
#define AURUM_GV_FUND    "AURUM_ctx_fund"      // 1 BULLISH, 0 NEUTRAL, -1 BEARISH, -9 no brief today
#define AURUM_GV_FUNDHI  "AURUM_ctx_fund_high" // 1 = fundamental confidence HIGH

int AurumRegimeCode(const string name)
  {
   if(name == "RANGING")    return 1;
   if(name == "MIXED")      return 2;
   if(name == "TREND_UP")   return 3;
   if(name == "TREND_DOWN") return 4;
   if(name == "HIGH_VOL")   return 5;
   return 0;
  }

string AurumRegimeName(const int code)
  {
   switch(code)
     {
      case 1: return "RANGING";
      case 2: return "MIXED";
      case 3: return "TREND_UP";
      case 4: return "TREND_DOWN";
      case 5: return "HIGH_VOL";
     }
   return "";
  }
//+------------------------------------------------------------------+
