#ifndef XSPARK_STRATEGY_SCOREBOT_V3_MQH
#define XSPARK_STRATEGY_SCOREBOT_V3_MQH

#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/MarketState.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/PatternDetector.mqh>
#include <XSpark/Strategy/ScoringEngine.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

class CXSparkScoreBotV3 : public IXSparkStrategy
{
private:
   string m_symbol;
   bool   m_initialized;
   string m_last_reason;

   double m_min_score;
   bool   m_drop_ibr;
   double m_long_score_extra;

   int m_rsi_long_min;
   int m_rsi_long_max;
   int m_rsi_short_min;
   int m_rsi_short_max;

   double m_atr_min_points;
   double m_atr_max_points;
   double m_atr_mult_sl;
   double m_min_rr;
   double m_max_rr;
   double m_atr_ratio_boost;
   bool   m_allow_asian_reduced;

   double MeanTickVolumeBars2To10(CXSparkIndicatorCache &cache)
   {
      long total = 0;

      for(int shift = 2; shift <= 10; shift++)
      {
         XSparkCandle bar;
         if(!cache.M15Bar(shift, bar))
            return 0.0;

         total += bar.tick_volume;
      }

      return (double)total / 9.0;
   }

   bool HasSupportResistance(CXSparkIndicatorCache &cache,
                             const EXSparkSignalDirection direction,
                             const double close1,
                             const double atr14)
   {
      for(int shift = 3; shift <= 48; shift++)
      {
         XSparkCandle candidate;
         XSparkCandle newer1;
         XSparkCandle newer2;
         XSparkCandle older1;
         XSparkCandle older2;

         if(!cache.M15Bar(shift, candidate) ||
            !cache.M15Bar(shift - 1, newer1) ||
            !cache.M15Bar(shift - 2, newer2) ||
            !cache.M15Bar(shift + 1, older1) ||
            !cache.M15Bar(shift + 2, older2))
         {
            return false;
         }

         if(direction == XSPARK_SIGNAL_BUY)
         {
            const bool swing_low = candidate.low < newer1.low &&
                                   candidate.low < newer2.low &&
                                   candidate.low < older1.low &&
                                   candidate.low < older2.low;

            if(swing_low && MathAbs(close1 - candidate.low) <= 0.5 * atr14)
               return true;
         }
         else if(direction == XSPARK_SIGNAL_SELL)
         {
            const bool swing_high = candidate.high > newer1.high &&
                                    candidate.high > newer2.high &&
                                    candidate.high > older1.high &&
                                    candidate.high > older2.high;

            if(swing_high && MathAbs(close1 - candidate.high) <= 0.5 * atr14)
               return true;
         }
      }

      return false;
   }

public:
   CXSparkScoreBotV3()
   {
      m_symbol = "";
      m_initialized = false;
      m_last_reason = "ScoreBot_v3 is not initialized.";
      Configure(2.0, false, 0.0, 40, 70, 30, 60, 80.0, 800.0, 1.5, 1.5, 3.0, 1.3, true);
   }

   void Configure(const double min_score,
                  const bool drop_ibr,
                  const double long_score_extra,
                  const int rsi_long_min,
                  const int rsi_long_max,
                  const int rsi_short_min,
                  const int rsi_short_max,
                  const double atr_min_points,
                  const double atr_max_points,
                  const double atr_mult_sl,
                  const double min_rr,
                  const double max_rr,
                  const double atr_ratio_boost,
                  const bool allow_asian_reduced)
   {
      m_min_score = min_score;
      m_drop_ibr = drop_ibr;
      m_long_score_extra = long_score_extra;
      m_rsi_long_min = rsi_long_min;
      m_rsi_long_max = rsi_long_max;
      m_rsi_short_min = rsi_short_min;
      m_rsi_short_max = rsi_short_max;
      m_atr_min_points = atr_min_points;
      m_atr_max_points = atr_max_points;
      m_atr_mult_sl = atr_mult_sl;
      m_min_rr = min_rr;
      m_max_rr = max_rr;
      m_atr_ratio_boost = atr_ratio_boost;
      m_allow_asian_reduced = allow_asian_reduced;
   }

   bool Initialize(const string symbol)
   {
      if(symbol == "")
      {
         m_last_reason = "ScoreBot_v3 symbol is empty.";
         return false;
      }

      m_symbol = symbol;
      m_initialized = true;
      m_last_reason = "ScoreBot_v3 initialized.";
      return true;
   }

   void Deinitialize()
   {
      m_initialized = false;
   }

   bool Evaluate(CXSparkIndicatorCache &cache,
                 CXSparkMarketState &market_state,
                 XSparkSignal &signal,
                 XSparkScoreBotReport &report)
   {
      XSparkResetSignal(signal);
      XSparkResetScoreBotReport(report);

      if(!m_initialized)
      {
         report.status = "SCANNING";
         report.block_reason = "ScoreBot_v3 is not initialized.";
         m_last_reason = report.block_reason;
         return false;
      }

      if(!cache.IsValid())
      {
         report.status = "SCANNING";
         report.block_reason = cache.LastReason();
         m_last_reason = report.block_reason;
         return false;
      }

      XSparkCandle bar1;
      XSparkCandle bar2;
      XSparkCandle bar3;

      if(!cache.M15Bar(1, bar1) || !cache.M15Bar(2, bar2) || !cache.M15Bar(3, bar3))
      {
         report.status = "SCANNING";
         report.block_reason = "Closed M15 bars are unavailable.";
         m_last_reason = report.block_reason;
         return false;
      }

      report.signal_bar_time = bar1.time;
      report.atr14 = cache.ATR14M15();
      report.atr50 = cache.ATR50M15();
      report.atr_points = XSparkPriceToCanonicalPoints(report.atr14);
      report.rsi_m15 = cache.RSI14M15();
      report.rsi_h1 = cache.RSI14H1();
      report.ema21_m15 = cache.EMA21M15();
      report.ema50_m15 = cache.EMA50M15();
      report.ema50_h1 = cache.EMA50H1();

      XSparkPatternResult pattern;
      if(!XSparkDetectScoreBotPattern(bar1, bar2, bar3, m_drop_ibr, pattern))
      {
         report.status = "SCANNING";
         report.block_reason = "NO PATTERN";
         m_last_reason = report.block_reason;
         return false;
      }

      report.has_pattern = true;
      report.direction = pattern.direction;
      report.pattern_id = pattern.pattern_id;
      report.pattern_name = pattern.pattern_name;

      report.components.session_weight = XSparkScoreBotSessionWeight(bar1.time, m_allow_asian_reduced);
      if(report.components.session_weight <= 0.0)
      {
         report.status = "SESSION BLOCKED";
         report.block_reason = "Session weight is zero.";
         m_last_reason = report.block_reason;
         return false;
      }

      if(report.atr_points < m_atr_min_points || report.atr_points > m_atr_max_points)
      {
         report.status = "ATR BLOCKED";
         report.block_reason = StringFormat("ATR14 %.2f canonical points is outside %.2f-%.2f.",
                                            report.atr_points,
                                            m_atr_min_points,
                                            m_atr_max_points);
         m_last_reason = report.block_reason;
         return false;
      }

      report.components.pattern = pattern.score;
      report.components.atr = 1.0;

      if(pattern.direction == XSPARK_SIGNAL_BUY)
      {
         if(report.ema21_m15 > report.ema50_m15 && bar1.close > report.ema50_h1)
            report.components.trend = 1.0;

         if(report.rsi_m15 >= (double)m_rsi_long_min && report.rsi_m15 <= (double)m_rsi_long_max)
            report.components.rsi = 1.0;

         if(HasSupportResistance(cache, pattern.direction, bar1.close, report.atr14))
            report.components.sr = 1.0;

         if(report.rsi_h1 > 50.0 && report.rsi_m15 > report.rsi_h1)
            report.components.mtf = 0.5;
      }
      else if(pattern.direction == XSPARK_SIGNAL_SELL)
      {
         if(report.ema21_m15 < report.ema50_m15 && bar1.close < report.ema50_h1)
            report.components.trend = 1.0;

         if(report.rsi_m15 >= (double)m_rsi_short_min && report.rsi_m15 <= (double)m_rsi_short_max)
            report.components.rsi = 1.0;

         if(HasSupportResistance(cache, pattern.direction, bar1.close, report.atr14))
            report.components.sr = 1.0;

         if(report.rsi_h1 < 50.0 && report.rsi_m15 < report.rsi_h1)
            report.components.mtf = 0.5;
      }

      report.components.volume = XSparkScoreBotVolumeScore(bar1.tick_volume, MeanTickVolumeBars2To10(cache));
      report.components.raw = report.components.pattern +
                              report.components.atr +
                              report.components.trend +
                              report.components.rsi +
                              report.components.sr +
                              report.components.volume +
                              report.components.mtf;
      report.components.final_score = report.components.raw * report.components.session_weight;

      if(!XSparkScoreBotScoreIsValid(report.components.final_score))
      {
         report.status = "SCANNING";
         report.block_reason = StringFormat("Unexpected ScoreBot score %.4f is outside 0-9.", report.components.final_score);
         m_last_reason = report.block_reason;
         return false;
      }

      report.scored = true;
      report.dynamic_rr = XSparkScoreBotDynamicRR(report.atr14,
                                                 report.atr50,
                                                 m_min_rr,
                                                 m_max_rr,
                                                 m_atr_ratio_boost);
      report.effective_threshold = XSparkScoreBotEffectiveThreshold(m_min_score,
                                                                    m_long_score_extra,
                                                                    pattern.direction);
      report.threshold_passed = report.components.final_score >= report.effective_threshold;

      signal.symbol = m_symbol;
      signal.direction = pattern.direction;
      signal.timestamp = TimeTradeServer();
      if(signal.timestamp == 0)
         signal.timestamp = TimeCurrent();
      signal.signal_bar_time = bar1.time;
      signal.score = report.components.final_score;
      signal.effective_threshold = report.effective_threshold;
      signal.dynamic_rr = report.dynamic_rr;
      signal.atr14 = report.atr14;
      signal.atr50 = report.atr50;
      signal.pattern_score = report.components.pattern;
      signal.atr_score = report.components.atr;
      signal.trend_score = report.components.trend;
      signal.rsi_score = report.components.rsi;
      signal.sr_score = report.components.sr;
      signal.volume_score = report.components.volume;
      signal.mtf_score = report.components.mtf;
      signal.session_weight = report.components.session_weight;
      signal.pattern_id = (int)pattern.pattern_id;
      signal.pattern_name = pattern.pattern_name;

      const double entry_reference = pattern.direction == XSPARK_SIGNAL_BUY ? market_state.Ask() : market_state.Bid();
      const double theoretical_distance = m_atr_mult_sl * report.atr14;
      if(pattern.direction == XSPARK_SIGNAL_BUY)
         signal.desired_stop = entry_reference - theoretical_distance;
      else
         signal.desired_stop = entry_reference + theoretical_distance;

      signal.desired_target = 0.0;
      signal.reason = report.threshold_passed ? "ScoreBot_v3 signal eligible." : "Score below effective threshold.";

      report.status = report.threshold_passed ? "ANALYSIS ONLY" : "SCANNING";
      report.block_reason = signal.reason;
      m_last_reason = report.block_reason;
      return report.threshold_passed;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
