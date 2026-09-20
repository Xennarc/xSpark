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

// The numbers that used to be inputs.
//
// Each of these failed the only test a setting has to pass: does the operator
// know something the code does not? Nobody can choose "entry slippage as 25% of
// the smallest stop this configuration can produce" from anything they know
// about their own trading, and a number that can only be copied from a default
// is not a choice - it is a way to get it wrong. They are fixed here instead,
// where the test suite covers them and one edit changes every chart.
//
// They are declared by CandleFlow rather than borrowed, because a default that
// reads through another strategy's constant changes silently when that strategy
// is retuned (AGENTS.md rule 43).

// How the per-instrument calibration is shaped. These are percentages fed to
// the shared derivation, which measures the instrument's own median range and
// turns them into absolute tolerances - so the same five numbers are correct on
// gold, on an FX pair and on an index without anyone editing anything.
// The stop floor: the smallest stop this configuration can produce, as a
// multiple of the typical candle. It is a safety control rather than a
// preference - a doji-thin candle otherwise yields a stop a few points wide and
// therefore a position many times the intended size - and it is the distance
// every derived tolerance below is measured against.
#define XSPARK_CANDLEFLOW_MIN_STOP_ATR_MULT 0.25

#define XSPARK_CANDLEFLOW_QUIET_MARKET_PCT 60.0
#define XSPARK_CANDLEFLOW_WILD_MARKET_PCT 600.0
// 20 rather than 25, and the difference matters. The derivation makes the
// permitted entry drift exactly this percentage of the smallest stop, and
// XSparkEntryDriftBound warns above 20% because a fill that drifts that far has
// spent a fifth of its own stop before it starts. At 25 that warning fired on
// every calibrated start, which is how a warning stops being read. Freezing the
// number is what forced the question; the answer is to tighten it.
#define XSPARK_CANDLEFLOW_ENTRY_SLIP_PCT 20.0
#define XSPARK_CANDLEFLOW_EXIT_SLIP_PCT 85.0
#define XSPARK_CANDLEFLOW_SPREAD_CAP_PCT 40.0

// The widest buy/sell gap worth trading through, as a share of the typical
// candle. A second, independent ceiling beside the derived absolute one.
#define XSPARK_CANDLEFLOW_MAX_SPREAD_ATR_PCT 10.0

// The absolute spread cap used only until the calibration replaces it, which it
// does on the first bar with enough history. It is a gold-shaped number and it
// is safe to be one precisely because no entry can consume it: SafetyManager
// vetoes new trades until the drift bound is established, which only the
// calibration can do. Named as a seed so it is never mistaken for a tuned
// value, and never reused as one.
#define XSPARK_CANDLEFLOW_SEED_SPREAD_CAP_POINTS 50.0

// One trade at a time. CandleFlow signals on nearly every candle and never
// reverses or hedges, so a second concurrent position is not a bigger bet on a
// better signal - it is the same bet twice, on a rule that has no way to prefer
// one candle over another.
#define XSPARK_CANDLEFLOW_MAX_OPEN_TRADES 1

// Ceilings, not preferences. The risk percentage an operator sets is checked
// against the first; the second bounds everything this bot and any other bot
// has open at once. Both are limits the strategy imposes on itself.
#define XSPARK_CANDLEFLOW_MAX_RISK_PCT 3.5
#define XSPARK_CANDLEFLOW_MAX_ACCOUNT_RISK_PCT 6.0

// The shipped values for the three numbers an operator sets. They are named
// because they are also the fallback when a setting cannot be used: a number
// that has to be replaced should be replaced with the recommended one, not with
// whatever happens to be nearby.
#define XSPARK_CANDLEFLOW_DEFAULT_RISK_PCT 1.0
#define XSPARK_CANDLEFLOW_DEFAULT_DAILY_DD_PCT 15.0
#define XSPARK_CANDLEFLOW_DEFAULT_TOTAL_DD_PCT 25.0

// Turns what the operator typed into what the EA will actually run with, and
// reports every difference.
//
// WHY THIS IS NOT A VALIDATOR THAT REFUSES. An out-of-range number used to
// return false from XSparkFlowValidateInputs, which returns INIT_FAILED, which
// means OnTick never runs at all - so the trailing stop, the break-even lock,
// the profit ladder, the weekend close and the killswitch flatten all stop
// while live positions sit open at the broker. ADR-020 settled that question
// already, for the point-size fault, and settled it the other way: fall back,
// log CRITICAL, keep managing. A configuration problem must never be a reason
// to abandon open exposure.
//
// It is also invisible where it is most likely to be met. In the Strategy
// Tester a failed OnInit produces a finished run with zero trades and one line
// in the Journal, which reads exactly like a strategy that found no setups.
//
// Every correction below moves toward MORE safety, except one: a total-drawdown
// level of zero is honoured as "switched off", because that is what a shipped
// build's own label told the operator it meant. Read on.
//
// Pure: no terminal calls, so every branch is testable.
bool XSparkCandleFlowResolveLimits(const double raw_risk_pct,
                                   const double raw_daily_dd_pct,
                                   const double raw_total_dd_pct,
                                   const bool raw_use_killswitch,
                                   double &risk_pct,
                                   double &daily_dd_pct,
                                   double &total_dd_pct,
                                   bool &use_killswitch,
                                   string &corrections)
{
   risk_pct = raw_risk_pct;
   daily_dd_pct = raw_daily_dd_pct;
   total_dd_pct = raw_total_dd_pct;
   use_killswitch = raw_use_killswitch;
   corrections = "";

   bool corrected = false;

   if(!MathIsValidNumber(risk_pct) || risk_pct <= 0.0)
   {
      corrections += StringFormat("Money risked on one trade was %.4f, which cannot size a trade; using %.2f%%. ",
                                  raw_risk_pct,
                                  XSPARK_CANDLEFLOW_DEFAULT_RISK_PCT);
      risk_pct = XSPARK_CANDLEFLOW_DEFAULT_RISK_PCT;
      corrected = true;
   }
   else if(risk_pct > XSPARK_CANDLEFLOW_MAX_RISK_PCT)
   {
      // Clamped DOWN, never refused. The operator asked for more risk than this
      // strategy allows itself; running at the ceiling is what they would have
      // got by typing the ceiling, and it is strictly safer than what they
      // asked for. Refusing to start protects nothing.
      corrections += StringFormat("Money risked on one trade was %.2f%%, above this bot's %.2f%% ceiling; using the ceiling. ",
                                  raw_risk_pct,
                                  XSPARK_CANDLEFLOW_MAX_RISK_PCT);
      risk_pct = XSPARK_CANDLEFLOW_MAX_RISK_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(daily_dd_pct) || daily_dd_pct <= 0.0 || daily_dd_pct >= 100.0)
   {
      // A daily limit of zero halts trading at zero drawdown, permanently. The
      // recommended value is the only sane replacement.
      corrections += StringFormat("The daily loss limit was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  raw_daily_dd_pct,
                                  XSPARK_CANDLEFLOW_DEFAULT_DAILY_DD_PCT);
      daily_dd_pct = XSPARK_CANDLEFLOW_DEFAULT_DAILY_DD_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(total_dd_pct) || total_dd_pct >= 100.0)
   {
      corrections += StringFormat("The emergency stop level was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  raw_total_dd_pct,
                                  XSPARK_CANDLEFLOW_DEFAULT_TOTAL_DD_PCT);
      total_dd_pct = XSPARK_CANDLEFLOW_DEFAULT_TOTAL_DD_PCT;
      corrected = true;
   }
   else if(total_dd_pct <= 0.0)
   {
      // THE ONE CORRECTION THAT REDUCES PROTECTION, and it is deliberate. A
      // shipped build labelled this setting "(0 = off)", so an operator who
      // typed 0 was following the instructions in front of them. MetaTrader
      // keeps a value across a recompile while the identifier survives, and
      // this one did - so that 0 outlives the build that meant it. Reading it
      // as "off" is honouring what they were told, not guessing; the
      // alternative silently re-arms a control they deliberately disabled.
      // It is stated at CRITICAL and names the switch that replaced it.
      corrections += StringFormat("The emergency stop level was 0, which an earlier build read as OFF, so the emergency stop is OFF. "
                                  "Use the emergency-stop switch instead, and set the level back to %.2f%%. ",
                                  XSPARK_CANDLEFLOW_DEFAULT_TOTAL_DD_PCT);
      total_dd_pct = XSPARK_CANDLEFLOW_DEFAULT_TOTAL_DD_PCT;
      use_killswitch = false;
      corrected = true;
   }

   // A daily limit at or above the emergency stop simply never fires, because
   // the emergency stop closes everything first. That is harmless - the
   // stricter control still acts - so it is reported and left alone rather than
   // corrected into something the operator did not ask for.
   if(use_killswitch && daily_dd_pct >= total_dd_pct)
   {
      corrections += StringFormat("The daily loss limit (%.2f%%) is at or above the emergency stop (%.2f%%), so it can never act; the emergency stop applies first. ",
                                  daily_dd_pct,
                                  total_dd_pct);
      corrected = true;
   }

   return !corrected;
}

// Broker-facing safeguards. Spare margin wanted beyond the trade's own, and the
// age past which a quote is too stale to act on.
#define XSPARK_CANDLEFLOW_MARGIN_BUFFER_PCT 20.0
#define XSPARK_CANDLEFLOW_MAX_QUOTE_AGE_SECONDS 15

// Friday close. A position held on a trailing stop with no target carries the
// weekend gap in full and the stop cannot act across it, so flattening before
// the weekend is behaviour rather than taste.
//
// WHEN to flatten is a property of the instrument, not of the operator, so it
// is read from the instrument rather than fixed. A hard "Friday 20:00" is the
// gold answer applied to everything, which is exactly what rule 15 forbids: it
// is hours early on a market that trades until 22:00 and meaningless on one
// that never closes.
//
// How long before that instrument's own last Friday session ends. Two hours is
// enough for a partial close to fill in thinning liquidity without giving up a
// whole session.
#define XSPARK_CANDLEFLOW_WEEKEND_CLOSE_LEAD_MINUTES 120

// Used only when the broker reports no usable Friday session. Closing early is
// the safe direction to be wrong in, so an unreadable session is not a reason
// to carry the gap.
#define XSPARK_CANDLEFLOW_WEEKEND_CLOSE_HOUR 20
#define XSPARK_CANDLEFLOW_WEEKEND_CLOSE_MINUTE 0

// Turns an instrument's own session data into the moment this bot flattens.
//
// Pure: the caller does the terminal lookup and hands over the numbers, which
// is what lets every branch below be tested without a trade server.
//
// Three outcomes, and each one is stated rather than inferred:
//   - the instrument trades at the weekend, so there is no gap to protect
//     against and the weekend close is switched off for it;
//   - its Friday session is readable, so flatten the lead time before the end;
//   - it is not readable, so fall back and say so.
bool XSparkCandleFlowWeekendClose(const bool trades_at_weekend,
                                  const bool friday_session_known,
                                  const int friday_end_hour,
                                  const int friday_end_minute,
                                  bool &use_weekend_close,
                                  int &close_hour,
                                  int &close_minute,
                                  string &reason)
{
   use_weekend_close = true;
   close_hour = XSPARK_CANDLEFLOW_WEEKEND_CLOSE_HOUR;
   close_minute = XSPARK_CANDLEFLOW_WEEKEND_CLOSE_MINUTE;
   reason = "";

   if(trades_at_weekend)
   {
      use_weekend_close = false;
      close_hour = 0;
      close_minute = 0;
      reason = "This market trades at the weekend, so there is no weekend gap to close before.";
      return true;
   }

   const bool usable = friday_session_known &&
                       friday_end_hour >= 0 && friday_end_hour <= 23 &&
                       friday_end_minute >= 0 && friday_end_minute <= 59;

   if(!usable)
   {
      reason = StringFormat("The broker did not report a usable Friday session, so trades are closed at %02d:%02d on its clock.",
                            close_hour,
                            close_minute);
      return true;
   }

   const int end_minutes = friday_end_hour * 60 + friday_end_minute;
   int flatten_minutes = end_minutes - XSPARK_CANDLEFLOW_WEEKEND_CLOSE_LEAD_MINUTES;

   // A session ending inside the lead time would push the flatten into the
   // previous day, which ShouldWeekendClose cannot express. Opening the market
   // and immediately closing is the honest reading of that, and it is still the
   // safe direction.
   if(flatten_minutes < 0)
      flatten_minutes = 0;

   close_hour = flatten_minutes / 60;
   close_minute = flatten_minutes % 60;

   reason = StringFormat("This market's Friday session ends at %02d:%02d, so trades are closed at %02d:%02d on the broker's clock.",
                         friday_end_hour,
                         friday_end_minute,
                         close_hour,
                         close_minute);
   return true;
}

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
   config.min_stop_atr_mult = XSPARK_CANDLEFLOW_MIN_STOP_ATR_MULT;
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
