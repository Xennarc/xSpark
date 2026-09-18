#ifndef XSPARK_CORE_INDICATOR_CACHE_MQH
#define XSPARK_CORE_INDICATOR_CACHE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

#define XSPARK_SCOREBOT_CLOSED_BASE_BARS 50
#define XSPARK_SCOREBOT_STRUCTURE_BASE_BARS 160
#define XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS 80

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
   MqlRates m_structure_base_rates[];
   MqlRates m_structure_higher_rates[];
   bool m_structure_valid;
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
      m_structure_valid = false;
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
      m_structure_valid = false;
   }

   bool RefreshClosedData()
   {
      m_valid = false;
      m_structure_valid = false;

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
         !HandleIsReady(m_ema50_higher_handle, 51) ||
         !HandleIsReady(m_rsi14_higher_handle, 15))
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
         !IndicatorValueIsReady(m_ema50_higher[0]) || m_ema50_higher[0] <= 0.0 ||
         !IndicatorValueIsReady(m_rsi14_higher[0]))
      {
         m_last_reason = "One or more closed-bar indicator values are unavailable.";
         return false;
      }

      // Structure has an independent readiness contract; a short window must
      // not delay the legacy strategy's first tradeable bar.
      ArraySetAsSeries(m_structure_base_rates, true);
      ArraySetAsSeries(m_structure_higher_rates, true);
      const int base_count = CopyRates(m_symbol, m_base_timeframe, 1,
                                      XSPARK_SCOREBOT_STRUCTURE_BASE_BARS, m_structure_base_rates);
      const int higher_count = CopyRates(m_symbol, m_higher_timeframe, 1,
                                        XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS, m_structure_higher_rates);
      m_structure_valid = base_count == XSPARK_SCOREBOT_STRUCTURE_BASE_BARS &&
                          higher_count == XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS;
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

   bool StructureIsValid() { return m_structure_valid; }

   bool StructureBar(const bool higher, const int closed_shift, XSparkCandle &bar)
   {
      const int count = higher ? XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS : XSPARK_SCOREBOT_STRUCTURE_BASE_BARS;
      if(!m_structure_valid || closed_shift < 1 || closed_shift > count) return false;
      MqlRates rate;
      if(higher) rate = m_structure_higher_rates[closed_shift - 1];
      else rate = m_structure_base_rates[closed_shift - 1];
      bar.time = rate.time; bar.open = rate.open; bar.high = rate.high;
      bar.low = rate.low; bar.close = rate.close; bar.tick_volume = rate.tick_volume;
      return true;
   }

   bool StructureBaseBar(const int closed_shift, XSparkCandle &bar)
   { return StructureBar(false, closed_shift, bar); }
   bool StructureHigherBar(const int closed_shift, XSparkCandle &bar)
   { return StructureBar(true, closed_shift, bar); }

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

   double RSI14BaseAt(const int closed_shift)
   {
      if(!m_valid || closed_shift < 1 || closed_shift > ArraySize(m_rsi14_base))
         return EMPTY_VALUE;
      const double value = m_rsi14_base[closed_shift - 1];
      return IndicatorValueIsReady(value) ? value : EMPTY_VALUE;
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
