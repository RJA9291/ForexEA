//+------------------------------------------------------------------+
//| XauRegime.mqh                                                    |
//| Market regime classifier shared by the backtest EA and the       |
//| signal engine, so live labels match the backtested statistics.   |
//| Uses only closed bars.                                           |
//+------------------------------------------------------------------+
#property strict

// Regimes, checked in this order:
//   HIGH_VOL   : daily ATR(14) > 1.5 x its 100-day average
//   TREND_UP   : H4 ADX(14) >= 25, EMA50 > EMA200, close above EMA50
//   TREND_DOWN : H4 ADX(14) >= 25, EMA50 < EMA200, close below EMA50
//   RANGING    : H4 ADX(14) < 20
//   MIXED      : everything else
class CXauRegime
  {
private:
   string            m_symbol;
   int               m_adx, m_fast, m_slow, m_atrD1;
   double            Buf(const int handle, const int buffer, const int shift)
     {
      double b[1];
      if(CopyBuffer(handle, buffer, shift, 1, b) != 1) return EMPTY_VALUE;
      return b[0];
     }

public:
   double            adx, emaFast, emaSlow, close, atrRatio;

                     CXauRegime() : m_adx(INVALID_HANDLE), m_fast(INVALID_HANDLE), m_slow(INVALID_HANDLE), m_atrD1(INVALID_HANDLE) {}

   bool              Init(const string symbol)
     {
      m_symbol = symbol;
      m_adx   = iADX(symbol, PERIOD_H4, 14);
      m_fast  = iMA(symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_slow  = iMA(symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_atrD1 = iATR(symbol, PERIOD_D1, 14);
      return m_adx != INVALID_HANDLE && m_fast != INVALID_HANDLE && m_slow != INVALID_HANDLE && m_atrD1 != INVALID_HANDLE;
     }

   void              Release()
     {
      if(m_adx != INVALID_HANDLE)   IndicatorRelease(m_adx);
      if(m_fast != INVALID_HANDLE)  IndicatorRelease(m_fast);
      if(m_slow != INVALID_HANDLE)  IndicatorRelease(m_slow);
      if(m_atrD1 != INVALID_HANDLE) IndicatorRelease(m_atrD1);
     }

   string            Classify()
     {
      adx     = Buf(m_adx, 0, 1);
      emaFast = Buf(m_fast, 0, 1);
      emaSlow = Buf(m_slow, 0, 1);
      close   = iClose(m_symbol, PERIOD_H4, 1);
      atrRatio = 0;
      double atr[];
      if(CopyBuffer(m_atrD1, 0, 1, 100, atr) == 100)
        {
         double sum = 0;
         for(int i = 0; i < 100; i++) sum += atr[i];
         if(sum > 0) atrRatio = atr[99] / (sum / 100.0);   // atr[99] is the most recent closed day
        }
      if(adx == EMPTY_VALUE || emaFast == EMPTY_VALUE || emaSlow == EMPTY_VALUE || close == 0)
         return "UNKNOWN";
      if(atrRatio > 1.5) return "HIGH_VOL";
      if(adx >= 25 && emaFast > emaSlow && close > emaFast) return "TREND_UP";
      if(adx >= 25 && emaFast < emaSlow && close < emaFast) return "TREND_DOWN";
      if(adx < 20) return "RANGING";
      return "MIXED";
     }

   string            DetailJson()
     {
      return StringFormat("{\"adx_h4\":%.1f,\"ema50_h4\":%.2f,\"ema200_h4\":%.2f,\"close_h4\":%.2f,\"atr_d1_ratio\":%.2f}",
                          adx, emaFast, emaSlow, close, atrRatio);
     }
  };
//+------------------------------------------------------------------+
