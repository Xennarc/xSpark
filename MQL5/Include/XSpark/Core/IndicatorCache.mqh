#ifndef XSPARK_CORE_INDICATOR_CACHE_MQH
#define XSPARK_CORE_INDICATOR_CACHE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

#define XSPARK_SCOREBOT_CLOSED_M15_BARS 50

class CXSparkIndicatorCache
{
private:
   string m_symbol;
   int    m_ema21_m15_handle;
   int    m_ema50_m15_handle;
   int    m_rsi14_m15_handle;
   int    m_atr14_m15_handle;
   int    m_atr50_m15_handle;
   int    m_ema50_h1_handle;
   int    m_rsi14_h1_handle;

   MqlRates m_m15_rates[];
   double   m_ema21_m15[];
   double   m_ema50_m15[];
   double   m_rsi14_m15[];
   double   m_atr14_m15[];
   double   m_atr50_m15[];
   double   m_ema50_h1[];
   double   m_rsi14_h1[];

   bool     m_initialized;
   bool     m_valid;
   string   m_last_reason;

   bool HandleIsReady(const int handle, const int required_bars)
   {
      if(handle == INVALID_HANDLE)
         return false;

      return BarsCalculated(handle) >= required_bars;
   }

   bool IndicatorValueIsReady(const double value)
   {
      // MathIsValidNumber rejects NaN and +/-INF; the previous value==value idiom
      // only caught NaN and let an infinity through into the scoring maths.
      return MathIsValidNumber(value) && value != EMPTY_VALUE;
   }

public:
   CXSparkIndicatorCache()
   {
      m_symbol = "";
      m_ema21_m15_handle = INVALID_HANDLE;
      m_ema50_m15_handle = INVALID_HANDLE;
      m_rsi14_m15_handle = INVALID_HANDLE;
      m_atr14_m15_handle = INVALID_HANDLE;
      m_atr50_m15_handle = INVALID_HANDLE;
      m_ema50_h1_handle = INVALID_HANDLE;
      m_rsi14_h1_handle = INVALID_HANDLE;
      m_initialized = false;
      m_valid = false;
      m_last_reason = "Indicator cache is not initialized.";
   }

   bool Initialize(const string symbol)
   {
      if(symbol == "")
      {
         m_last_reason = "Indicator symbol is empty.";
         return false;
      }

      m_symbol = symbol;

      m_ema21_m15_handle = iMA(m_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_ema50_m15_handle = iMA(m_symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_rsi14_m15_handle = iRSI(m_symbol, PERIOD_M15, 14, PRICE_CLOSE);
      m_atr14_m15_handle = iATR(m_symbol, PERIOD_M15, 14);
      m_atr50_m15_handle = iATR(m_symbol, PERIOD_M15, 50);
      m_ema50_h1_handle = iMA(m_symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_rsi14_h1_handle = iRSI(m_symbol, PERIOD_H1, 14, PRICE_CLOSE);

      if(m_ema21_m15_handle == INVALID_HANDLE ||
         m_ema50_m15_handle == INVALID_HANDLE ||
         m_rsi14_m15_handle == INVALID_HANDLE ||
         m_atr14_m15_handle == INVALID_HANDLE ||
         m_atr50_m15_handle == INVALID_HANDLE ||
         m_ema50_h1_handle == INVALID_HANDLE ||
         m_rsi14_h1_handle == INVALID_HANDLE)
      {
         m_last_reason = "One or more indicator handles are invalid.";
         return false;
      }

      m_initialized = true;
      RefreshClosedData();
      return true;
   }

   void Deinitialize()
   {
      if(m_ema21_m15_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema21_m15_handle);
      if(m_ema50_m15_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema50_m15_handle);
      if(m_rsi14_m15_handle != INVALID_HANDLE)
         IndicatorRelease(m_rsi14_m15_handle);
      if(m_atr14_m15_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr14_m15_handle);
      if(m_atr50_m15_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr50_m15_handle);
      if(m_ema50_h1_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema50_h1_handle);
      if(m_rsi14_h1_handle != INVALID_HANDLE)
         IndicatorRelease(m_rsi14_h1_handle);

      m_initialized = false;
      m_valid = false;
   }

   bool RefreshClosedData()
   {
      m_valid = false;

      if(!m_initialized)
      {
         m_last_reason = "Indicator cache is not initialized.";
         return false;
      }

      if(Bars(m_symbol, PERIOD_M15) < XSPARK_SCOREBOT_CLOSED_M15_BARS + 60 ||
         Bars(m_symbol, PERIOD_H1) < 60)
      {
         m_last_reason = "Insufficient M15 or H1 bars for ScoreBot_v3 indicators.";
         return false;
      }

      // Copying starts at shift 1, so N closed values need N+1 calculated bars.
      if(!HandleIsReady(m_ema21_m15_handle, XSPARK_SCOREBOT_CLOSED_M15_BARS + 1) ||
         !HandleIsReady(m_ema50_m15_handle, XSPARK_SCOREBOT_CLOSED_M15_BARS + 1) ||
         !HandleIsReady(m_rsi14_m15_handle, XSPARK_SCOREBOT_CLOSED_M15_BARS + 1) ||
         !HandleIsReady(m_atr14_m15_handle, XSPARK_SCOREBOT_CLOSED_M15_BARS + 1) ||
         !HandleIsReady(m_atr50_m15_handle, XSPARK_SCOREBOT_CLOSED_M15_BARS + 1) ||
         !HandleIsReady(m_ema50_h1_handle, 2) ||
         !HandleIsReady(m_rsi14_h1_handle, 2))
      {
         m_last_reason = "Indicator bars are not fully calculated.";
         return false;
      }

      // Logical index 0 must map to closed shift 1 after copying from start_pos=1.
      ArraySetAsSeries(m_m15_rates, true);
      ArraySetAsSeries(m_ema21_m15, true);
      ArraySetAsSeries(m_ema50_m15, true);
      ArraySetAsSeries(m_rsi14_m15, true);
      ArraySetAsSeries(m_atr14_m15, true);
      ArraySetAsSeries(m_atr50_m15, true);
      ArraySetAsSeries(m_ema50_h1, true);
      ArraySetAsSeries(m_rsi14_h1, true);

      if(CopyRates(m_symbol, PERIOD_M15, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_m15_rates) != XSPARK_SCOREBOT_CLOSED_M15_BARS)
      {
         m_last_reason = "Unable to copy closed M15 OHLCV bars.";
         return false;
      }

      if(CopyBuffer(m_ema21_m15_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_ema21_m15) != XSPARK_SCOREBOT_CLOSED_M15_BARS ||
         CopyBuffer(m_ema50_m15_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_ema50_m15) != XSPARK_SCOREBOT_CLOSED_M15_BARS ||
         CopyBuffer(m_rsi14_m15_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_rsi14_m15) != XSPARK_SCOREBOT_CLOSED_M15_BARS ||
         CopyBuffer(m_atr14_m15_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_atr14_m15) != XSPARK_SCOREBOT_CLOSED_M15_BARS ||
         CopyBuffer(m_atr50_m15_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_M15_BARS, m_atr50_m15) != XSPARK_SCOREBOT_CLOSED_M15_BARS)
      {
         m_last_reason = "Unable to copy closed M15 indicator buffers.";
         return false;
      }

      if(CopyBuffer(m_ema50_h1_handle, 0, 1, 1, m_ema50_h1) != 1 ||
         CopyBuffer(m_rsi14_h1_handle, 0, 1, 1, m_rsi14_h1) != 1)
      {
         m_last_reason = "Unable to copy closed H1 indicator buffers.";
         return false;
      }

      if(!IndicatorValueIsReady(m_ema21_m15[0]) ||
         !IndicatorValueIsReady(m_ema50_m15[0]) ||
         !IndicatorValueIsReady(m_rsi14_m15[0]) ||
         !IndicatorValueIsReady(m_atr14_m15[0]) ||
         !IndicatorValueIsReady(m_atr50_m15[0]) ||
         !IndicatorValueIsReady(m_ema50_h1[0]) ||
         !IndicatorValueIsReady(m_rsi14_h1[0]))
      {
         m_last_reason = "One or more closed-bar indicator values are unavailable.";
         return false;
      }

      m_valid = true;
      m_last_reason = "Indicator cache is valid.";
      return true;
   }

   datetime CurrentM15BarTime()
   {
      return iTime(m_symbol, PERIOD_M15, 0);
   }

   bool M15Bar(const int closed_shift, XSparkCandle &bar)
   {
      if(!m_valid || closed_shift < 1 || closed_shift > XSPARK_SCOREBOT_CLOSED_M15_BARS)
         return false;

      const int index = closed_shift - 1;
      bar.time = m_m15_rates[index].time;
      bar.open = m_m15_rates[index].open;
      bar.high = m_m15_rates[index].high;
      bar.low = m_m15_rates[index].low;
      bar.close = m_m15_rates[index].close;
      bar.tick_volume = m_m15_rates[index].tick_volume;
      return true;
   }

   double EMA21M15()
   {
      return m_valid ? m_ema21_m15[0] : 0.0;
   }

   double EMA50M15()
   {
      return m_valid ? m_ema50_m15[0] : 0.0;
   }

   double RSI14M15()
   {
      return m_valid ? m_rsi14_m15[0] : 0.0;
   }

   double ATR14M15()
   {
      return m_valid ? m_atr14_m15[0] : 0.0;
   }

   double ATR50M15()
   {
      return m_valid ? m_atr50_m15[0] : 0.0;
   }

   double EMA50H1()
   {
      return m_valid ? m_ema50_h1[0] : 0.0;
   }

   double RSI14H1()
   {
      return m_valid ? m_rsi14_h1[0] : 0.0;
   }

   bool IsValid()
   {
      return m_valid;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
