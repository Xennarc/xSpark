#ifndef XSPARK_STRATEGY_CANDLE_FLOW_MQH
#define XSPARK_STRATEGY_CANDLE_FLOW_MQH

#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/StrategyIdentity.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

// CandleFlow: one factor, one candle.
//
// A closed base-timeframe candle that finished above its open is a long; below
// its open is a short. The stop is anchored to that same candle's far wick with
// a buffer, and is re-anchored to the far wick of every later closed candle,
// tightening only. That is the entire ENTRY rule, and it has not changed.
//
// The exit has two optional additions, both off as far as this module is
// concerned and both configured by the EA: a hard take-profit for the whole
// position, published here as the signal's reward ratio, and a ladder of
// partial take-profits, which belongs entirely to PositionManager because it
// operates on an open position rather than on an entry. See
// Trade/ProfitLadder.mqh. With both left at zero this is the original
// no-target strategy, unchanged price for price.
//
// Everything here is pure arithmetic over closed bars: no symbol lookups, no
// terminal calls, no broker state. The live quote, the broker stop level, the
// volume and every risk decision belong to the shared XSpark components, which
// this module never touches. That is what makes the rules testable from a
// script and what keeps the strategy inside the boundary AGENTS.md draws:
// strategies produce signals only.

// XSPARK_CANDLEFLOW_MAGIC_DEFAULT is declared in StrategyIdentity.mqh, which
// owns every strategy's Magic Number so collisions between them are detectable.
#define XSPARK_CANDLEFLOW_COMMENT_DEFAULT "CandleFlow_v1"

// CandleFlow's own price tolerances, in strategy points.
//
// Numerically these are what ScoreBot_v3 ships, because both were derived from
// the same XAUUSD reference range - but they are declared here rather than
// borrowed from XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS. A default that reads
// through another strategy's constant is a default that changes when that
// strategy is retuned, silently and for reasons that have nothing to do with
// this one. On any instrument other than gold both are replaced by the
// auto-calibration anyway.
#define XSPARK_CANDLEFLOW_ENTRY_DEVIATION_POINTS 30.0
#define XSPARK_CANDLEFLOW_EXIT_DEVIATION_POINTS 100.0

// CandleFlow has no score. RiskManager grades exposure by score, so every
// CandleFlow signal presents the same one and the EA sets all three risk tiers
// to the same percentage - the tier lookup then cannot change the answer. The
// value is inside the 0-9 band RiskManager validates and sits in the top tier,
// so a misconfigured EA that left the tiers apart fails loudly on the risk
// ceiling rather than silently sizing at a tier nobody chose.
#define XSPARK_CANDLEFLOW_SIGNAL_SCORE 5.5

// A no-target plan is signalled by a non-positive reward ratio, which the
// execution engine reads as "send no take-profit". It is what a signal carries
// whenever the operator has not configured a hard target.
#define XSPARK_CANDLEFLOW_NO_TARGET_RR 0.0

// The single entry factor: which way the closed candle finished.
//
// A candle that closed exactly at its open has no direction and is not a
// signal. The optional body filter is the one concession to noise - a candle
// whose body is a rounding error on the instrument's own range is a coin
// flip wearing a direction - and it is off by default so the shipped rule
// stays literally single-factor.
EXSparkSignalDirection XSparkCandleFlowBarDirection(const XSparkCandle &bar,
                                                    const double atr14,
                                                    const double min_body_atr_mult,
                                                    string &reason)
{
   reason = "";

   if(!MathIsValidNumber(bar.open) || !MathIsValidNumber(bar.close) ||
      !MathIsValidNumber(bar.high) || !MathIsValidNumber(bar.low) ||
      bar.open <= 0.0 || bar.close <= 0.0 || bar.high <= 0.0 || bar.low <= 0.0)
   {
      reason = "Closed candle prices are not usable.";
      return XSPARK_SIGNAL_NONE;
   }

   if(bar.high < bar.low)
   {
      reason = "Closed candle high is below its low.";
      return XSPARK_SIGNAL_NONE;
   }

   const double body = MathAbs(bar.close - bar.open);

   if(body <= 0.0)
   {
      reason = "Candle closed at its open; it has no direction.";
      return XSPARK_SIGNAL_NONE;
   }

   if(min_body_atr_mult > 0.0)
   {
      if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
      {
         reason = "Body filter is enabled but the average range is unavailable.";
         return XSPARK_SIGNAL_NONE;
      }

      if(body < min_body_atr_mult * atr14)
      {
         reason = StringFormat("Candle body is %.2f%% of the average range; the filter requires %.2f%%.",
                               body / atr14 * 100.0,
                               min_body_atr_mult * 100.0);
         return XSPARK_SIGNAL_NONE;
      }
   }

   return bar.close > bar.open ? XSPARK_SIGNAL_BUY : XSPARK_SIGNAL_SELL;
}

// How far beyond the wick the stop sits.
//
// Three additive components so the same configuration transfers between
// timeframes and instruments: a share of the average range, a share of the
// signal candle's own range, and a fixed pad already converted to price by the
// caller. Defaults use the ATR component alone, because it is the one that
// rescales automatically when the chart period changes.
bool XSparkCandleFlowBuffer(const double atr14,
                            const double candle_range,
                            const double atr_mult,
                            const double range_pct,
                            const double fixed_price,
                            double &buffer,
                            string &reason)
{
   buffer = 0.0;
   reason = "";

   if(!MathIsValidNumber(atr_mult) || atr_mult < 0.0 ||
      !MathIsValidNumber(range_pct) || range_pct < 0.0 ||
      !MathIsValidNumber(fixed_price) || fixed_price < 0.0)
   {
      reason = "Wick buffer configuration must be finite and non-negative.";
      return false;
   }

   double total = fixed_price;

   if(atr_mult > 0.0)
   {
      if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
      {
         reason = "Wick buffer needs the average range and it is unavailable.";
         return false;
      }

      total += atr_mult * atr14;
   }

   if(range_pct > 0.0)
   {
      if(!MathIsValidNumber(candle_range) || candle_range < 0.0)
      {
         reason = "Wick buffer needs the candle range and it is unavailable.";
         return false;
      }

      total += (range_pct / 100.0) * candle_range;
   }

   if(!MathIsValidNumber(total) || total < 0.0)
   {
      reason = "Derived wick buffer is not a usable distance.";
      return false;
   }

   buffer = total;
   return true;
}

// The protective anchor a candle implies: its far wick, pushed out by the
// buffer. Used unchanged for the entry stop and for every later re-anchor.
bool XSparkCandleFlowAnchor(const EXSparkSignalDirection direction,
                            const XSparkCandle &bar,
                            const double buffer,
                            double &anchor,
                            string &reason)
{
   anchor = 0.0;
   reason = "";

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
   {
      reason = "An anchor needs a BUY or SELL direction.";
      return false;
   }

   if(!MathIsValidNumber(bar.high) || !MathIsValidNumber(bar.low) ||
      bar.high <= 0.0 || bar.low <= 0.0 || bar.high < bar.low)
   {
      reason = "Closed candle range is not usable for an anchor.";
      return false;
   }

   if(!MathIsValidNumber(buffer) || buffer < 0.0)
   {
      reason = "Wick buffer is not a usable distance.";
      return false;
   }

   anchor = direction == XSPARK_SIGNAL_BUY ? bar.low - buffer : bar.high + buffer;

   if(!MathIsValidNumber(anchor) || anchor <= 0.0)
   {
      anchor = 0.0;
      reason = "Derived anchor price is not positive.";
      return false;
   }

   return true;
}

// Turns the candle anchor into the stop the entry will actually be sized from.
//
// Two bounds, both measured against the live reference price rather than the
// candle, because the stop distance that decides the volume is the one from
// the fill:
//
//   - a floor, so a doji-thin candle cannot produce a stop a few points wide
//     and therefore a position many times the intended size;
//   - an optional ceiling, so an outsized candle is refused rather than sized
//     down into a position too small to be worth its own spread.
//
// Widening to the floor always REDUCES the volume, so the floor can never
// increase realised risk. Fails closed: an unusable bound refuses the entry.
bool XSparkCandleFlowStop(const EXSparkSignalDirection direction,
                          const double reference,
                          const double anchor,
                          const double atr14,
                          const double min_stop_atr_mult,
                          const double max_stop_atr_mult,
                          double &stop,
                          double &distance,
                          string &reason)
{
   stop = 0.0;
   distance = 0.0;
   reason = "";

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
   {
      reason = "A stop needs a BUY or SELL direction.";
      return false;
   }

   if(!MathIsValidNumber(reference) || reference <= 0.0 ||
      !MathIsValidNumber(anchor) || anchor <= 0.0)
   {
      reason = "Reference price or candle anchor is not usable.";
      return false;
   }

   if(!MathIsValidNumber(min_stop_atr_mult) || min_stop_atr_mult < 0.0 ||
      !MathIsValidNumber(max_stop_atr_mult) || max_stop_atr_mult < 0.0)
   {
      reason = "Stop bounds must be finite and non-negative.";
      return false;
   }

   double floor_distance = 0.0;
   if(min_stop_atr_mult > 0.0)
   {
      if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
      {
         reason = "A stop floor is configured but the average range is unavailable.";
         return false;
      }

      floor_distance = min_stop_atr_mult * atr14;
   }

   const double anchor_distance = direction == XSPARK_SIGNAL_BUY ?
                                  reference - anchor :
                                  anchor - reference;

   const double used = MathMax(anchor_distance, floor_distance);

   if(!MathIsValidNumber(used) || used <= 0.0)
   {
      reason = "Price already moved through the candle anchor and no stop floor is configured.";
      return false;
   }

   if(max_stop_atr_mult > 0.0)
   {
      if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
      {
         reason = "A stop ceiling is configured but the average range is unavailable.";
         return false;
      }

      if(used > max_stop_atr_mult * atr14)
      {
         reason = StringFormat("Candle stop is %.2f times the average range; the ceiling is %.2f.",
                               used / atr14,
                               max_stop_atr_mult);
         return false;
      }
   }

   stop = direction == XSPARK_SIGNAL_BUY ? reference - used : reference + used;

   if(!MathIsValidNumber(stop) || stop <= 0.0)
   {
      stop = 0.0;
      reason = "Derived stop price is not positive.";
      return false;
   }

   distance = used;
   return true;
}

struct XSparkCandleFlowConfig
{
   double buffer_atr_mult;    // buffer as a multiple of ATR14
   double buffer_range_pct;   // buffer as a percentage of the signal candle's range
   double buffer_fixed_price; // fixed pad, already converted to price by the caller
   double min_stop_atr_mult;  // stop floor as a multiple of ATR14
   double max_stop_atr_mult;  // stop ceiling as a multiple of ATR14; 0 disables
   double min_body_atr_mult;  // body filter as a multiple of ATR14; 0 disables
   // Hard take-profit for the whole position, as a multiple of the entry risk.
   // Zero is the strategy's original no-target behaviour, where the trailing
   // stop is the only exit. Supplied by the EA from the profit ladder, which
   // owns this setting and its bounds; the rule only reports it on the signal
   // so the panel and the plan agree about what the trade is aiming at.
   double final_target_r;
   bool   use_volatility_gate;
   double atr_min_points;
   double atr_max_points;
   double score_point_size;
};

void XSparkDefaultCandleFlowConfig(XSparkCandleFlowConfig &config)
{
   config.buffer_atr_mult = 0.10;
   config.buffer_range_pct = 0.0;
   config.buffer_fixed_price = 0.0;
   config.min_stop_atr_mult = 0.25;
   config.max_stop_atr_mult = 0.0;
   config.min_body_atr_mult = 0.0;
   config.final_target_r = 0.0;
   config.use_volatility_gate = false;
   config.atr_min_points = 0.0;
   config.atr_max_points = 0.0;
   config.score_point_size = 0.0;
}

bool XSparkValidateCandleFlowConfig(const XSparkCandleFlowConfig &config, string &reason)
{
   reason = "";

   if(!MathIsValidNumber(config.buffer_atr_mult) || config.buffer_atr_mult < 0.0 ||
      !MathIsValidNumber(config.buffer_range_pct) || config.buffer_range_pct < 0.0 ||
      !MathIsValidNumber(config.buffer_fixed_price) || config.buffer_fixed_price < 0.0)
   {
      reason = "Wick buffer settings must be finite and non-negative.";
      return false;
   }

   // Without at least one buffer component the stop sits exactly on the wick,
   // where ordinary noise removes it. Refused as the configuration error it is.
   if(config.buffer_atr_mult <= 0.0 && config.buffer_range_pct <= 0.0 && config.buffer_fixed_price <= 0.0)
   {
      reason = "At least one wick buffer component must be positive; a stop exactly on the wick has no buffer at all.";
      return false;
   }

   if(!MathIsValidNumber(config.min_stop_atr_mult) || config.min_stop_atr_mult <= 0.0)
   {
      reason = "The stop floor must be a finite positive multiple of the average range.";
      return false;
   }

   if(!MathIsValidNumber(config.max_stop_atr_mult) || config.max_stop_atr_mult < 0.0)
   {
      reason = "The stop ceiling must be finite and non-negative.";
      return false;
   }

   if(config.max_stop_atr_mult > 0.0 && config.max_stop_atr_mult <= config.min_stop_atr_mult)
   {
      reason = "The stop ceiling must be above the stop floor, or zero to disable it.";
      return false;
   }

   if(!MathIsValidNumber(config.min_body_atr_mult) || config.min_body_atr_mult < 0.0)
   {
      reason = "The candle body filter must be finite and non-negative.";
      return false;
   }

   if(!MathIsValidNumber(config.final_target_r) || config.final_target_r < 0.0)
   {
      reason = "The final take-profit target must be finite and non-negative.";
      return false;
   }

   return true;
}

class CXSparkCandleFlow : public IXSparkStrategy
{
private:
   XSparkCandleFlowConfig m_config;
   string m_symbol;
   bool   m_initialized;
   string m_last_reason;

public:
   CXSparkCandleFlow()
   {
      XSparkDefaultCandleFlowConfig(m_config);
      m_symbol = "";
      m_initialized = false;
      m_last_reason = "CandleFlow is not initialized.";
   }

   void Configure(const XSparkCandleFlowConfig &config)
   {
      m_config = config;
   }

   // The reward ratio every signal carries. Non-positive means "send no
   // take-profit", which is what the execution engine reads it as.
   double TargetRewardRatio()
   {
      if(!MathIsValidNumber(m_config.final_target_r) || m_config.final_target_r <= 0.0)
         return XSPARK_CANDLEFLOW_NO_TARGET_RR;

      return m_config.final_target_r;
   }

   bool Initialize(const string symbol)
   {
      m_initialized = false;

      if(symbol == "")
      {
         m_last_reason = "CandleFlow requires a symbol.";
         return false;
      }

      string config_reason = "";
      if(!XSparkValidateCandleFlowConfig(m_config, config_reason))
      {
         m_last_reason = config_reason;
         return false;
      }

      m_symbol = symbol;
      m_initialized = true;
      m_last_reason = "CandleFlow initialized.";
      return true;
   }

   void Deinitialize()
   {
      m_initialized = false;
      m_last_reason = "CandleFlow is not initialized.";
   }

   // Auto-tune feeds the instrument-scaled volatility band through the same
   // setter ScoreBot_v3 uses, so the EA's calibration path is unchanged. The
   // band is stored whether or not the gate consumes it: the derived numbers
   // also drive the spread cap and the slippage tolerances.
   bool SetVolatilityBand(const double atr_min_points, const double atr_max_points)
   {
      if(!MathIsValidNumber(atr_min_points) || !MathIsValidNumber(atr_max_points) ||
         atr_min_points <= 0.0 || atr_max_points <= atr_min_points)
      {
         m_last_reason = "Volatility band is not usable.";
         return false;
      }

      m_config.atr_min_points = atr_min_points;
      m_config.atr_max_points = atr_max_points;
      return true;
   }

   // The stop anchor implied by the most recently closed candle, in both
   // directions. Called once per closed bar; the caller hands the result to
   // PositionManager, which ratchets live stops toward it.
   bool TrailAnchors(CXSparkIndicatorCache &cache,
                     double &anchor_long,
                     double &anchor_short,
                     string &reason)
   {
      anchor_long = 0.0;
      anchor_short = 0.0;
      reason = "";

      if(!m_initialized)
      {
         reason = "CandleFlow is not initialized.";
         return false;
      }

      XSparkCandle bar;
      if(!cache.IsValid() || !cache.BaseBar(1, bar))
      {
         reason = "No closed candle is available to re-anchor the trailing stop.";
         return false;
      }

      const double atr14 = cache.ATR14Base();

      double buffer = 0.0;
      if(!XSparkCandleFlowBuffer(atr14, bar.high - bar.low,
                                 m_config.buffer_atr_mult,
                                 m_config.buffer_range_pct,
                                 m_config.buffer_fixed_price,
                                 buffer,
                                 reason))
      {
         return false;
      }

      string long_reason = "";
      string short_reason = "";
      const bool long_ok = XSparkCandleFlowAnchor(XSPARK_SIGNAL_BUY, bar, buffer, anchor_long, long_reason);
      const bool short_ok = XSparkCandleFlowAnchor(XSPARK_SIGNAL_SELL, bar, buffer, anchor_short, short_reason);

      if(!long_ok || !short_ok)
      {
         anchor_long = 0.0;
         anchor_short = 0.0;
         reason = long_ok ? short_reason : long_reason;
         return false;
      }

      reason = StringFormat("Anchors from %s candle: long %.8f, short %.8f, buffer %.8f.",
                            TimeToString(bar.time, TIME_DATE | TIME_MINUTES),
                            anchor_long,
                            anchor_short,
                            buffer);
      return true;
   }

   // The whole entry decision. Produces a signal object; it never touches the
   // broker, the account, or the live quote.
   bool Evaluate(CXSparkIndicatorCache &cache,
                 XSparkSignal &signal,
                 XSparkScoreBotReport &report)
   {
      XSparkResetSignal(signal);
      XSparkResetScoreBotReport(report);
      report.pattern_mode = "SINGLE FACTOR";
      report.entry_location = "CANDLE CLOSE";
      report.htf_verdict = "OFF";
      report.pullback_verdict = "OFF";
      report.rsi_verdict = "OFF";
      report.joint_verdict = "OFF";

      if(!m_initialized)
      {
         report.status = "SCANNING";
         report.block_reason = "CandleFlow is not initialized.";
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
      if(!cache.BaseBar(1, bar1))
      {
         report.status = "SCANNING";
         report.block_reason = "The closed signal candle is unavailable.";
         m_last_reason = report.block_reason;
         return false;
      }

      const double atr14 = cache.ATR14Base();
      const double atr50 = cache.ATR50Base();

      report.signal_bar_time = bar1.time;
      report.atr14 = atr14;
      report.atr50 = atr50;
      report.atr_points = m_config.score_point_size > 0.0 ? atr14 / m_config.score_point_size : 0.0;
      report.atr50_points = m_config.score_point_size > 0.0 ? atr50 / m_config.score_point_size : 0.0;
      report.context.bar1_open = bar1.open;
      report.context.bar1_high = bar1.high;
      report.context.bar1_low = bar1.low;
      report.context.bar1_close = bar1.close;
      report.context.atr14 = atr14;
      report.effective_threshold = 0.0;
      // Zero unless the operator configured a hard target, in which case the
      // execution engine derives the take-profit price from it at send time,
      // against the refreshed quote rather than against the planning one.
      report.dynamic_rr = TargetRewardRatio();

      string direction_reason = "";
      const EXSparkSignalDirection direction = XSparkCandleFlowBarDirection(bar1,
                                                                            atr14,
                                                                            m_config.min_body_atr_mult,
                                                                            direction_reason);

      if(direction == XSPARK_SIGNAL_NONE)
      {
         report.status = "SCANNING";
         report.block_reason = direction_reason;
         report.detected_patterns = "NONE";
         m_last_reason = report.block_reason;
         return false;
      }

      report.has_pattern = true;
      report.direction = direction;
      report.candidate_direction = direction;
      report.candidate_instance = bar1.time;
      report.detected_instance = bar1.time;
      report.pattern_name = XSparkPatternNameFromId(report.pattern_id);
      report.candidate_pattern = report.pattern_name;
      report.detected_patterns = report.pattern_name;
      report.pattern_id = direction == XSPARK_SIGNAL_BUY ? XSPARK_PATTERN_BULLISH_CANDLE
                                                         : XSPARK_PATTERN_BEARISH_CANDLE;

      // Optional and off by default. It is the only thing between the bare
      // single factor and the market, so when it blocks it says so plainly.
      if(m_config.use_volatility_gate)
      {
         if(m_config.score_point_size <= 0.0 || m_config.atr_min_points <= 0.0 || m_config.atr_max_points <= 0.0)
         {
            report.status = "SCANNING";
            report.block_reason = "The market-movement filter is on but its band has not been calibrated yet.";
            m_last_reason = report.block_reason;
            return false;
         }

         const double atr_points = atr14 / m_config.score_point_size;
         if(atr_points < m_config.atr_min_points || atr_points > m_config.atr_max_points)
         {
            report.status = "SCANNING";
            report.block_reason = StringFormat("Market movement %.2f points is outside the %.2f-%.2f band.",
                                               atr_points,
                                               m_config.atr_min_points,
                                               m_config.atr_max_points);
            m_last_reason = report.block_reason;
            return false;
         }
      }

      double buffer = 0.0;
      string buffer_reason = "";
      if(!XSparkCandleFlowBuffer(atr14, bar1.high - bar1.low,
                                 m_config.buffer_atr_mult,
                                 m_config.buffer_range_pct,
                                 m_config.buffer_fixed_price,
                                 buffer,
                                 buffer_reason))
      {
         report.status = "SCANNING";
         report.block_reason = buffer_reason;
         m_last_reason = report.block_reason;
         return false;
      }

      double anchor = 0.0;
      string anchor_reason = "";
      if(!XSparkCandleFlowAnchor(direction, bar1, buffer, anchor, anchor_reason))
      {
         report.status = "SCANNING";
         report.block_reason = anchor_reason;
         m_last_reason = report.block_reason;
         return false;
      }

      report.detected_level = anchor;
      report.scored = true;
      report.threshold_passed = true;
      report.components.pattern = XSPARK_CANDLEFLOW_SIGNAL_SCORE;
      report.components.raw = XSPARK_CANDLEFLOW_SIGNAL_SCORE;
      report.components.final_score = XSPARK_CANDLEFLOW_SIGNAL_SCORE;
      report.components.session_weight = 1.0;
      report.status = "SIGNAL";
      report.block_reason = "";

      signal.symbol = m_symbol;
      signal.direction = direction;
      signal.desired_stop = anchor;     // the raw candle anchor; the EA bounds it against the live quote
      // The price is deliberately not computed here: execution derives it from
      // the ratio below and the stop distance it actually gets, which is the
      // only distance the target is meaningful against.
      signal.desired_target = 0.0;
      signal.dynamic_rr = TargetRewardRatio();
      signal.score = XSPARK_CANDLEFLOW_SIGNAL_SCORE;
      signal.effective_threshold = 0.0;
      signal.pattern_score = XSPARK_CANDLEFLOW_SIGNAL_SCORE;
      signal.session_weight = 1.0;
      signal.atr14 = atr14;
      signal.atr50 = atr50;
      signal.signal_bar_time = bar1.time;
      signal.instance_time = bar1.time;
      signal.pattern_id = (int)report.pattern_id;
      signal.pattern_name = report.pattern_name;
      signal.context = report.context;
      signal.reason = StringFormat("%s on the %s candle; stop anchored at %.8f with a %.8f buffer.",
                                   report.pattern_name,
                                   TimeToString(bar1.time, TIME_DATE | TIME_MINUTES),
                                   anchor,
                                   buffer);

      m_last_reason = signal.reason;
      return true;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
