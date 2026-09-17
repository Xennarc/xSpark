#ifndef XSPARK_CORE_INDICATOR_CACHE_MQH
#define XSPARK_CORE_INDICATOR_CACHE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

#define XSPARK_SCOREBOT_CLOSED_BASE_BARS 50

class CXSparkIndicatorCache
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_base_timeframe;
   ENUM_TIMEFRAMES m_higher_timeframe;
   int    m_ema21_base_handle;
   int    m_ema50_base_handle;
   int    m_rsi14_base_handle;
   int    m_atr14_base_handle;
   int    m_atr50_base_handle;
   int    m_ema50_higher_handle;
   int    m_rsi14_higher_handle;

   MqlRates m_base_rates[];
   double   m_ema21_base[];
   double   m_ema50_base[];
   double   m_rsi14_base[];
   double   m_atr14_base[];
   double   m_atr50_base[];
   double   m_ema50_higher[];
   double   m_rsi14_higher[];

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
      m_base_timeframe = XSPARK_SCOREBOT_TESTED_BASE_TIMEFRAME;
      m_higher_timeframe = XSPARK_SCOREBOT_TESTED_HIGHER_TIMEFRAME;
      m_ema21_base_handle = INVALID_HANDLE;
      m_ema50_base_handle = INVALID_HANDLE;
      m_rsi14_base_handle = INVALID_HANDLE;
      m_atr14_base_handle = INVALID_HANDLE;
      m_atr50_base_handle = INVALID_HANDLE;
      m_ema50_higher_handle = INVALID_HANDLE;
      m_rsi14_higher_handle = INVALID_HANDLE;
      m_initialized = false;
      m_valid = false;
      m_last_reason = "Indicator cache is not initialized.";
   }

   bool Initialize(const string symbol,
                   const ENUM_TIMEFRAMES base_timeframe,
                   const ENUM_TIMEFRAMES higher_timeframe)
   {
      if(symbol == "")
      {
         m_last_reason = "Indicator symbol is empty.";
         return false;
      }

      if(base_timeframe == PERIOD_CURRENT || higher_timeframe == PERIOD_CURRENT ||
         PeriodSeconds(higher_timeframe) <= PeriodSeconds(base_timeframe))
      {
         m_last_reason = "Indicator timeframes are invalid; the higher timeframe must be longer than the base.";
         return false;
      }

      m_symbol = symbol;
      m_base_timeframe = base_timeframe;
      m_higher_timeframe = higher_timeframe;

      m_ema21_base_handle = iMA(m_symbol, m_base_timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_ema50_base_handle = iMA(m_symbol, m_base_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_rsi14_base_handle = iRSI(m_symbol, m_base_timeframe, 14, PRICE_CLOSE);
      m_atr14_base_handle = iATR(m_symbol, m_base_timeframe, 14);
      m_atr50_base_handle = iATR(m_symbol, m_base_timeframe, 50);
      m_ema50_higher_handle = iMA(m_symbol, m_higher_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_rsi14_higher_handle = iRSI(m_symbol, m_higher_timeframe, 14, PRICE_CLOSE);

      if(m_ema21_base_handle == INVALID_HANDLE ||
         m_ema50_base_handle == INVALID_HANDLE ||
         m_rsi14_base_handle == INVALID_HANDLE ||
         m_atr14_base_handle == INVALID_HANDLE ||
         m_atr50_base_handle == INVALID_HANDLE ||
         m_ema50_higher_handle == INVALID_HANDLE ||
         m_rsi14_higher_handle == INVALID_HANDLE)
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
      if(m_ema21_base_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema21_base_handle);
      if(m_ema50_base_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema50_base_handle);
      if(m_rsi14_base_handle != INVALID_HANDLE)
         IndicatorRelease(m_rsi14_base_handle);
      if(m_atr14_base_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr14_base_handle);
      if(m_atr50_base_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr50_base_handle);
      if(m_ema50_higher_handle != INVALID_HANDLE)
         IndicatorRelease(m_ema50_higher_handle);
      if(m_rsi14_higher_handle != INVALID_HANDLE)
         IndicatorRelease(m_rsi14_higher_handle);

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

      if(Bars(m_symbol, m_base_timeframe) < XSPARK_SCOREBOT_CLOSED_BASE_BARS + 60 ||
         Bars(m_symbol, m_higher_timeframe) < 60)
      {
         m_last_reason = "Insufficient base or higher timeframe bars for ScoreBot_v3 indicators.";
         return false;
      }

      // Copying starts at shift 1, so N closed values need N+1 calculated bars.
      if(!HandleIsReady(m_ema21_base_handle, XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1) ||
         !HandleIsReady(m_ema50_base_handle, XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1) ||
         !HandleIsReady(m_rsi14_base_handle, XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1) ||
         !HandleIsReady(m_atr14_base_handle, XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1) ||
         !HandleIsReady(m_atr50_base_handle, XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1) ||
         !HandleIsReady(m_ema50_higher_handle, 2) ||
         !HandleIsReady(m_rsi14_higher_handle, 2))
      {
         m_last_reason = "Indicator bars are not fully calculated.";
         return false;
      }

      // Logical index 0 must map to closed shift 1 after copying from start_pos=1.
      ArraySetAsSeries(m_base_rates, true);
      ArraySetAsSeries(m_ema21_base, true);
      ArraySetAsSeries(m_ema50_base, true);
      ArraySetAsSeries(m_rsi14_base, true);
      ArraySetAsSeries(m_atr14_base, true);
      ArraySetAsSeries(m_atr50_base, true);
      ArraySetAsSeries(m_ema50_higher, true);
      ArraySetAsSeries(m_rsi14_higher, true);

      if(CopyRates(m_symbol, m_base_timeframe, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_base_rates) != XSPARK_SCOREBOT_CLOSED_BASE_BARS)
      {
         m_last_reason = "Unable to copy closed base timeframe OHLCV bars.";
         return false;
      }

      if(CopyBuffer(m_ema21_base_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_ema21_base) != XSPARK_SCOREBOT_CLOSED_BASE_BARS ||
         CopyBuffer(m_ema50_base_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_ema50_base) != XSPARK_SCOREBOT_CLOSED_BASE_BARS ||
         CopyBuffer(m_rsi14_base_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_rsi14_base) != XSPARK_SCOREBOT_CLOSED_BASE_BARS ||
         CopyBuffer(m_atr14_base_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_atr14_base) != XSPARK_SCOREBOT_CLOSED_BASE_BARS ||
         CopyBuffer(m_atr50_base_handle, 0, 1, XSPARK_SCOREBOT_CLOSED_BASE_BARS, m_atr50_base) != XSPARK_SCOREBOT_CLOSED_BASE_BARS)
      {
         m_last_reason = "Unable to copy closed base timeframe indicator buffers.";
         return false;
      }

      if(CopyBuffer(m_ema50_higher_handle, 0, 1, 1, m_ema50_higher) != 1 ||
         CopyBuffer(m_rsi14_higher_handle, 0, 1, 1, m_rsi14_higher) != 1)
      {
         m_last_reason = "Unable to copy closed higher timeframe indicator buffers.";
         return false;
      }

      if(!IndicatorValueIsReady(m_ema21_base[0]) ||
         !IndicatorValueIsReady(m_ema50_base[0]) ||
         !IndicatorValueIsReady(m_rsi14_base[0]) ||
         !IndicatorValueIsReady(m_atr14_base[0]) ||
         !IndicatorValueIsReady(m_atr50_base[0]) ||
         !IndicatorValueIsReady(m_ema50_higher[0]) ||
         !IndicatorValueIsReady(m_rsi14_higher[0]))
      {
         m_last_reason = "One or more closed-bar indicator values are unavailable.";
         return false;
      }

      m_valid = true;
      m_last_reason = "Indicator cache is valid.";
      return true;
   }

   datetime CurrentBaseBarTime()
   {
      return iTime(m_symbol, m_base_timeframe, 0);
   }

   bool BaseBar(const int closed_shift, XSparkCandle &bar)
   {
      if(!m_valid || closed_shift < 1 || closed_shift > XSPARK_SCOREBOT_CLOSED_BASE_BARS)
         return false;

      const int index = closed_shift - 1;
      bar.time = m_base_rates[index].time;
      bar.open = m_base_rates[index].open;
      bar.high = m_base_rates[index].high;
      bar.low = m_base_rates[index].low;
      bar.close = m_base_rates[index].close;
      bar.tick_volume = m_base_rates[index].tick_volume;
      return true;
   }

   double EMA21Base()
   {
      return m_valid ? m_ema21_base[0] : 0.0;
   }

   double EMA50Base()
   {
      return m_valid ? m_ema50_base[0] : 0.0;
   }

   double RSI14Base()
   {
      return m_valid ? m_rsi14_base[0] : 0.0;
   }

   double ATR14Base()
   {
      return m_valid ? m_atr14_base[0] : 0.0;
   }

   // Copies a history window of the SAME ATR14 the gate compares against, for
   // the market calibration. It reads this cache's own handle rather than
   // opening another: a second handle would carry a second definition to keep
   // in step, and - because a freshly created handle has not calculated yet -
   // one created and released per attempt could never warm up between retries.
   //
   // Returns the number of values copied, or -1. Bar 0 is still forming, so the
   // window starts at the first CLOSED bar.
   int CopyATR14BaseHistory(const int count, double &destination[])
   {
      if(!m_valid || m_atr14_base_handle == INVALID_HANDLE || count <= 0)
         return -1;

      return CopyBuffer(m_atr14_base_handle, 0, 1, count, destination);
   }

   double ATR50Base()
   {
      return m_valid ? m_atr50_base[0] : 0.0;
   }

   double EMA50Higher()
   {
      return m_valid ? m_ema50_higher[0] : 0.0;
   }

   double RSI14Higher()
   {
      return m_valid ? m_rsi14_higher[0] : 0.0;
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
