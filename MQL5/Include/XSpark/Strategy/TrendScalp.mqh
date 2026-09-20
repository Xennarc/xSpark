#ifndef XSPARK_STRATEGY_TREND_SCALP_MQH
#define XSPARK_STRATEGY_TREND_SCALP_MQH

#include <XSpark/Core/AutoTune.mqh>
#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/StrategyIdentity.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

// TrendScalp: a session-gated, trend-aligned pullback scalper.
//
// The rule in one sentence: in an uptrend (the fast average at least a quarter
// of a typical candle above the slow one, and the close above the higher
// period's slow average), buy when a candle dips to the fast average and
// closes back above it in its upper half without running more than one
// typical candle past it; the stop sits a little under that candle and the
// target is the same distance above the entry; shorts are the mirror.
//
// THE HONEST FRAMING, which every document and journal line must carry. The
// exit geometry (a target at or below the stop) sets the win rate a trade
// with NO edge would show; the trend-pullback entry is the only possible
// source of edge and it is unmeasured. Under a driftless walk a long enters
// at the ask and both barriers trigger on the bid, so with stop distance D,
// target rD and total round-trip cost s (spread plus commission, in price):
//
//    P(win) = (D - s) / ((1 + r) D)     and the expectancy is -s/D in R,
//
// whatever r is. At the 6% cost share this design permits a trade with no
// edge wins 47.0% at a 1:1 target and 52.2% at 0.8:1. The break-even win
// rate before any edge is 1/(1+r): 50.0% and 55.6%. Nothing here is a
// profitability claim; no backtest, forward test or live result exists.
//
// A scalper is therefore a COST problem first. Every control below that is
// not shared with the other strategies exists to keep the round-trip cost a
// small share of the stop: the cost floor on the stop distance, the
// commission input and its live verification, the session windows that skip
// the rollover spread, and the deferral of a time-stop close while the
// spread is wide.
//
// Everything in this header is pure arithmetic over closed bars and numbers
// the EA hands in: no symbol lookups, no terminal calls, no broker state. The
// live quote, the broker stop level, the volume and every risk decision
// belong to the shared XSpark components, which this module never touches.
// That is what makes every rule testable from a script and what keeps the
// strategy inside the boundary AGENTS.md draws: strategies produce signals
// only.

// XSPARK_TRENDSCALP_MAGIC_DEFAULT is declared in StrategyIdentity.mqh, which
// owns every strategy's Magic Number so collisions between them are detectable.
#define XSPARK_TRENDSCALP_COMMENT_DEFAULT "TrendScalp_v1"

// ---------------------------------------------------------------------------
// The entry rule's numbers. Each is a multiple of the typical candle (ATR14 on
// the chart period), so the same rule transfers between periods and
// instruments without anyone editing anything.
// ---------------------------------------------------------------------------

// The fast average must sit at least this far above (below) the slow one for
// the chart to count as trending. Without a gap "trend" would mean "not
// crossing right now", which is true of every flat market between crosses.
#define XSPARK_TRENDSCALP_MIN_EMA_GAP_ATR 0.25

// The pullback candle must reach within this of the fast average. A tenth of
// a typical candle is close enough that the average was tested, and far
// enough that the test does not have to print exactly on the line.
#define XSPARK_TRENDSCALP_TOUCH_ATR 0.10

// The close must land in the upper (long) or lower (short) half of the
// candle's range. Half is the point where buyers demonstrably won the candle
// rather than merely surviving it.
#define XSPARK_TRENDSCALP_MIN_CLOSE_POSITION 0.50

// The close may not run further than this beyond the fast average. A candle
// that has already travelled a whole typical range past the line is a chase,
// and a chase puts the stop a whole candle further away for the same target.
#define XSPARK_TRENDSCALP_MAX_EXTENSION_ATR 1.00

// The stop sits this far beyond the signal candle's far wick, so ordinary
// noise around the wick does not remove it.
#define XSPARK_TRENDSCALP_BUFFER_ATR 0.15

// The stop floor from the entry reference. A stop narrower than one typical
// candle is hit by noise rather than by being wrong, and it is also the
// "smallest stop" every calibrated tolerance below is measured against.
#define XSPARK_TRENDSCALP_MIN_STOP_ATR 1.00

// The stop ceiling. A deeper pullback is not a scalp any more: two and a half
// typical candles of risk against a one-candle target is a different trade
// and it is refused rather than sized down.
#define XSPARK_TRENDSCALP_MAX_STOP_ATR 2.50

// The round-trip cost (spread plus commission) may be at most this share of
// the stop distance. At this share a trade with no edge wins 47% at a 1:1
// target, which is the arithmetic in the header comment; above it the exit
// geometry alone starts to bury whatever edge the entry has.
#define XSPARK_TRENDSCALP_MAX_COST_SHARE_PCT 6.0

// SafetyManager's coarse cost-versus-typical-candle backstop. Deliberately
// ABOVE MAX_COST_SHARE_PCT * MAX_STOP_ATR (= 15), so the strategy's own cost
// floor is always the operative refusal and its message, with its two
// numbers, is what the operator reads. TestTrendScalp asserts the inequality
// so a retune cannot re-shadow it.
#define XSPARK_TRENDSCALP_MAX_SPREAD_ATR_PCT 25.0

// ---------------------------------------------------------------------------
// How long a trade may live.
// ---------------------------------------------------------------------------

// A stuck scalp blocks the single slot. Twelve bars catches the stale trade
// that has neither reached its target nor its stop, where 24 bars caught one
// in two hundred; and whatever the chart period a scalp is never held longer
// than six hours.
#define XSPARK_TRENDSCALP_MAX_HOLD_BARS 12
#define XSPARK_TRENDSCALP_MAX_HOLD_SECONDS 21600

// No entry in the last fifteen minutes of the trading window: a trade opened
// then is flattened at the session end before it has had a fair chance.
#define XSPARK_TRENDSCALP_SESSION_CLOSE_LEAD_SECONDS 900

// A commission-cost rail, not a risk rail (the daily stop is the risk rail):
// forty trades at a 6% cost share is 2.4R of cost paid in one day.
#define XSPARK_TRENDSCALP_MAX_TRADES_PER_DAY 40

// One trade at a time. A second position on the same rule is the same bet
// twice, on a rule that has no way to prefer one pullback over another.
#define XSPARK_TRENDSCALP_MAX_OPEN_TRADES 1

// ---------------------------------------------------------------------------
// Risk ceilings, not preferences.
// ---------------------------------------------------------------------------

// The most an operator may risk on one trade. Lower than CandleFlow's because
// a scalper takes many more trades a day, so the same per-trade risk is a
// larger daily exposure.
#define XSPARK_TRENDSCALP_MAX_RISK_PCT 2.0

// The most the small-account cap may let the broker's minimum lot risk. It
// equals the shipped default so the shipped default passes its own ceiling
// (rule 47).
#define XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT 3.0

// Bounds everything this bot and any other bot has open at once. At or above
// the small-account ceiling so a permitted minimum-lot trade cannot be
// refused by the account cap.
#define XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT 6.0

// Spare margin wanted beyond the trade's own, so a fill does not leave the
// account one adverse tick from a margin call.
#define XSPARK_TRENDSCALP_MARGIN_BUFFER_PCT 20.0

// The age past which a quote is too stale to act on. The same as CandleFlow
// but declared here (rule 43); it detects VPS clock skew and is not exercised
// in the tester.
#define XSPARK_TRENDSCALP_MAX_QUOTE_AGE_SECONDS 15

// ---------------------------------------------------------------------------
// Calibration shape: percentages fed to the shared derivation, which measures
// the instrument's own median range and turns them into absolute tolerances.
// ---------------------------------------------------------------------------

// The volatility band, as a share of the reference typical candle. Below the
// quiet edge the stop floor is a few points and the cost share explodes;
// above the wild edge a one-candle stop is a news spike.
#define XSPARK_TRENDSCALP_QUIET_MARKET_PCT 60.0
#define XSPARK_TRENDSCALP_WILD_MARKET_PCT 600.0

// Permitted entry drift as a share of the smallest stop. CandleFlow's 20 sits
// on a 0.25-typical-candle floor; on a 1.0 floor it would allow a fill that
// turns 1:1 into 0.88:1.12 before the trade starts, so it is halved.
#define XSPARK_TRENDSCALP_ENTRY_SLIP_PCT 10.0

// Permitted exit drift as a share of the smallest stop: a close is a close,
// so it may pay most of a stop to get done.
#define XSPARK_TRENDSCALP_EXIT_SLIP_PCT 85.0

// The absolute spread cap as a share of the smallest stop. It exists because
// the shared derivation requires a value; it is a backstop behind the cost
// floor, which measures the same thing more exactly.
#define XSPARK_TRENDSCALP_SPREAD_CAP_PCT 40.0

// The absolute spread cap used only until the calibration replaces it. A
// gold-shaped placeholder, and safe to be one because no entry can consume
// it: SafetyManager vetoes new trades until the drift bound is established,
// which only the calibration can do.
#define XSPARK_TRENDSCALP_SEED_SPREAD_CAP_POINTS 50.0

// The calibration sample spans this many days of the chart period, capped so
// an M1 chart does not ask for a month of bars. Five days is one trading
// week: the shortest sample that has seen every session once.
#define XSPARK_TRENDSCALP_CALIBRATION_DAYS 5
#define XSPARK_TRENDSCALP_CALIBRATION_MAX_BARS 10080

// TrendScalp has no score. RiskManager grades exposure by score, so every
// signal presents the same one and the EA sets all three risk tiers to the
// same percentage; the value sits in the top tier so a misconfigured EA fails
// loudly on the risk ceiling rather than sizing at a tier nobody chose.
#define XSPARK_TRENDSCALP_SIGNAL_SCORE 5.5

// ---------------------------------------------------------------------------
// Friday close. A scalp is never meant to be open at the weekend, so the lead
// is one hour rather than CandleFlow's two: nothing this bot holds needs
// hours to unwind.
// ---------------------------------------------------------------------------
#define XSPARK_TRENDSCALP_WEEKEND_CLOSE_LEAD_MINUTES 60

// Used only when the broker reports no usable Friday session. Closing early
// is the safe direction to be wrong in.
#define XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR 20
#define XSPARK_TRENDSCALP_WEEKEND_CLOSE_MINUTE 0

// Gold-shaped seeds for the slippage tolerances, replaced by the calibration
// on the first bar with enough history; declared here rather than borrowed
// (rule 43).
#define XSPARK_TRENDSCALP_ENTRY_DEVIATION_POINTS 30.0
#define XSPARK_TRENDSCALP_EXIT_DEVIATION_POINTS 100.0

// The shipped values for the numbers an operator sets. They are named because
// they are also the fallback the resolver uses: a number that has to be
// replaced is replaced with the recommended one, not with whatever is nearby.
#define XSPARK_TRENDSCALP_DEFAULT_RISK_PCT 1.0
#define XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT 3.0
#define XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT 6.0
#define XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT 20.0
#define XSPARK_TRENDSCALP_DEFAULT_COMMISSION_PER_LOT 0.0
#define XSPARK_TRENDSCALP_DEFAULT_UTC_OFFSET 0

// A measured commission above the declared one by more than this blocks
// entries: the declared number feeds the cost floor, so an understated one
// silently admits trades the floor should have refused. A quarter absorbs
// rounding on part-lot fills without absorbing a wrong account type.
#define XSPARK_TRENDSCALP_COMMISSION_TOLERANCE_PCT 25.0

// Below this many recorded outcomes the OnTester verdict says the win rate
// cannot be distinguished from 50%. At 300 trades the 95% Wilson interval on
// an observed 55% is about four points wide, which is the first sample size
// where "above 50%" can be said at all.
#define XSPARK_TRENDSCALP_MIN_TRADES_FOR_VERDICT 300

// The z for a one-sided 95% lower confidence bound on the win rate.
#define XSPARK_TRENDSCALP_WILSON_Z 1.96

// The two exit styles' targets, as multiples of the stop. EVEN's 50%
// break-even line is the one objective an operator can read directly; QUICK
// trades a higher no-edge win rate for a lower break-even margin.
#define XSPARK_TRENDSCALP_TARGET_R_EVEN 1.0
#define XSPARK_TRENDSCALP_TARGET_R_QUICK 0.8

// The band the EA hands the execution engine around the target. XSparkFlow's
// 1.25 upper edge was for a 2-3R target; on a scalp 25% is the whole
// difference between the two exit styles, so a broker-adjusted target more
// than 5% either side of the plan is refused at planning time.
#define XSPARK_TRENDSCALP_TARGET_BAND_LOW_MULT 0.95
#define XSPARK_TRENDSCALP_TARGET_BAND_HIGH_MULT 1.05

// ---------------------------------------------------------------------------
// Sessions, in seconds of the UTC day. 00:00-01:00 UTC is excluded (rollover
// spread and swap) and 21:00-24:00 UTC is excluded in every choice, because
// after the New York close the spread widens and the typical candle shrinks,
// which is the worst combination a cost-bounded rule can meet.
// ---------------------------------------------------------------------------
#define XSPARK_TRENDSCALP_SESSION_ASIA_OPEN_UTC_SECONDS 3600
#define XSPARK_TRENDSCALP_SESSION_LONDON_OPEN_UTC_SECONDS 25200
#define XSPARK_TRENDSCALP_SESSION_CLOSE_UTC_SECONDS 75600
#define XSPARK_TRENDSCALP_SECONDS_PER_DAY 86400

// The broker clock offset an operator may declare, in whole hours. The real
// world's time zones run from UTC-12 to UTC+14; anything outside is a typo.
#define XSPARK_TRENDSCALP_MIN_UTC_OFFSET_HOURS -12
#define XSPARK_TRENDSCALP_MAX_UTC_OFFSET_HOURS 14

// ---------------------------------------------------------------------------
// Timeframes.
// ---------------------------------------------------------------------------

// The higher-period partner for each supported chart period. TrendScalp's own
// table rather than the shared XSparkHigherTimeframeFor, which XSpark.mq5 and
// its tests depend on and which pairs H1 with H4: an H4 EMA50 spans 200 hours
// and is a swing filter, not a bias for a trade that lasts hours, so H1 pairs
// with H2 here. The indicator cache requires higher > base and every pair
// satisfies it.
bool XSparkTrendScalpHigherTimeframeFor(const ENUM_TIMEFRAMES base,
                                        ENUM_TIMEFRAMES &higher,
                                        string &reason)
{
   higher = PERIOD_CURRENT;
   reason = "";

   switch(base)
   {
      case PERIOD_M1:  higher = PERIOD_M15; return true;
      case PERIOD_M2:  higher = PERIOD_M15; return true;
      case PERIOD_M3:  higher = PERIOD_M15; return true;
      case PERIOD_M4:  higher = PERIOD_M30; return true;
      case PERIOD_M5:  higher = PERIOD_M30; return true;
      case PERIOD_M6:  higher = PERIOD_M30; return true;
      case PERIOD_M10: higher = PERIOD_H1;  return true;
      case PERIOD_M12: higher = PERIOD_H1;  return true;
      case PERIOD_M15: higher = PERIOD_H1;  return true;
      case PERIOD_M20: higher = PERIOD_H2;  return true;
      case PERIOD_M30: higher = PERIOD_H2;  return true;
      case PERIOD_H1:  higher = PERIOD_H2;  return true;
      default:         break;
   }

   reason = "Chart period is not supported by TrendScalp. Use M1 to H1.";
   return false;
}

// The time stop for a chart period, in seconds: twelve bars, but never more
// than six hours. Zero for a period that cannot be used, which the EA has
// already refused at start-up; the pure function still fails closed.
int XSparkTrendScalpMaxHoldSeconds(const int period_seconds)
{
   if(period_seconds <= 0)
      return 0;

   const long by_bars = (long)XSPARK_TRENDSCALP_MAX_HOLD_BARS * (long)period_seconds;

   if(by_bars > (long)XSPARK_TRENDSCALP_MAX_HOLD_SECONDS)
      return XSPARK_TRENDSCALP_MAX_HOLD_SECONDS;

   return (int)by_bars;
}

// How many closed bars the calibration samples on a chart period: five days'
// worth, never fewer than the shared derivation's own sample size and never
// more than the cap. Integer arithmetic throughout - (a + b - 1) / b is the
// ceiling - so no rounding function is needed. Zero for an unusable period.
int XSparkTrendScalpCalibrationBars(const int period_seconds)
{
   if(period_seconds <= 0)
      return 0;

   const int wanted_seconds = XSPARK_TRENDSCALP_CALIBRATION_DAYS * XSPARK_TRENDSCALP_SECONDS_PER_DAY;
   int bars = (wanted_seconds + period_seconds - 1) / period_seconds;

   if(bars < XSPARK_AUTOTUNE_SAMPLE_BARS)
      bars = XSPARK_AUTOTUNE_SAMPLE_BARS;

   if(bars > XSPARK_TRENDSCALP_CALIBRATION_MAX_BARS)
      bars = XSPARK_TRENDSCALP_CALIBRATION_MAX_BARS;

   return bars;
}

// ---------------------------------------------------------------------------
// Configuration.
// ---------------------------------------------------------------------------

struct XSparkTrendScalpConfig
{
   double buffer_atr_mult;     // stop buffer beyond the far wick, as a multiple of ATR14
   double min_stop_atr_mult;   // stop floor as a multiple of ATR14
   double max_stop_atr_mult;   // stop ceiling as a multiple of ATR14; a wider stop is refused
   double max_cost_share_pct;  // round-trip cost may be at most this share of the stop
   double min_ema_gap_atr;     // fast-slow average gap that counts as a trend
   double touch_atr;           // how close to the fast average the pullback must reach
   double min_close_position;  // close position in the candle's range, (0, 1]
   double max_extension_atr;   // how far past the fast average the close may run
   // Target as a multiple of the stop. Supplied by the EA from the exit style;
   // the rule reports it on the signal so the panel and the plan agree.
   double target_r;
   bool   use_volatility_gate;
   double atr_min_points;
   double atr_max_points;
   double score_point_size;
};

void XSparkDefaultTrendScalpConfig(XSparkTrendScalpConfig &config)
{
   config.buffer_atr_mult = XSPARK_TRENDSCALP_BUFFER_ATR;
   config.min_stop_atr_mult = XSPARK_TRENDSCALP_MIN_STOP_ATR;
   config.max_stop_atr_mult = XSPARK_TRENDSCALP_MAX_STOP_ATR;
   config.max_cost_share_pct = XSPARK_TRENDSCALP_MAX_COST_SHARE_PCT;
   config.min_ema_gap_atr = XSPARK_TRENDSCALP_MIN_EMA_GAP_ATR;
   config.touch_atr = XSPARK_TRENDSCALP_TOUCH_ATR;
   config.min_close_position = XSPARK_TRENDSCALP_MIN_CLOSE_POSITION;
   config.max_extension_atr = XSPARK_TRENDSCALP_MAX_EXTENSION_ATR;
   config.target_r = XSPARK_TRENDSCALP_TARGET_R_EVEN;
   // On by default, unlike CandleFlow: a scalp's stop is one typical candle,
   // so a market whose typical candle is a few points is a market where the
   // cost share cannot be met, and one whose typical candle is a news spike
   // is not a market for a one-candle stop.
   config.use_volatility_gate = true;
   config.atr_min_points = 0.0;
   config.atr_max_points = 0.0;
   config.score_point_size = 0.0;
}

bool XSparkValidateTrendScalpConfig(const XSparkTrendScalpConfig &config, string &reason)
{
   reason = "";

   if(!MathIsValidNumber(config.buffer_atr_mult) || config.buffer_atr_mult <= 0.0)
   {
      reason = "The wick buffer must be a finite positive multiple of the typical candle; a stop exactly on the wick has no buffer.";
      return false;
   }

   if(!MathIsValidNumber(config.min_stop_atr_mult) || config.min_stop_atr_mult <= 0.0)
   {
      reason = "The stop floor must be a finite positive multiple of the typical candle.";
      return false;
   }

   if(!MathIsValidNumber(config.max_stop_atr_mult) || config.max_stop_atr_mult <= config.min_stop_atr_mult)
   {
      reason = "The stop ceiling must be finite and above the stop floor.";
      return false;
   }

   // A share of 100 or more would let the whole stop be cost; a share of zero
   // would refuse every trade on any instrument with a spread.
   if(!MathIsValidNumber(config.max_cost_share_pct) || config.max_cost_share_pct <= 0.0 || config.max_cost_share_pct >= 100.0)
   {
      reason = "The permitted cost share must be a percentage above 0 and below 100.";
      return false;
   }

   if(!MathIsValidNumber(config.min_ema_gap_atr) || config.min_ema_gap_atr < 0.0 ||
      !MathIsValidNumber(config.touch_atr) || config.touch_atr < 0.0 ||
      !MathIsValidNumber(config.max_extension_atr) || config.max_extension_atr < 0.0)
   {
      reason = "The trend gap, touch distance and extension limit must be finite and non-negative.";
      return false;
   }

   if(!MathIsValidNumber(config.min_close_position) || config.min_close_position <= 0.0 || config.min_close_position > 1.0)
   {
      reason = "The close position must be above 0 and at most 1: it is a share of the candle's range.";
      return false;
   }

   // A scalp without a target has no exit but the stop and the time stop,
   // which is a different strategy; zero is refused rather than read as "no
   // take-profit".
   if(!MathIsValidNumber(config.target_r) || config.target_r <= 0.0)
   {
      reason = "The target must be a finite positive multiple of the stop.";
      return false;
   }

   if(!MathIsValidNumber(config.atr_min_points) || config.atr_min_points < 0.0 ||
      !MathIsValidNumber(config.atr_max_points) || config.atr_max_points < 0.0 ||
      !MathIsValidNumber(config.score_point_size) || config.score_point_size < 0.0)
   {
      reason = "The volatility band and point size must be finite and non-negative.";
      return false;
   }

   return true;
}

// What the panel shows for the two halves of the rule.
struct XSparkTrendScalpVerdicts
{
   string trend;    // "UPTREND", "DOWNTREND", "NO TREND", "BIAS CONFLICT", "NO DATA"
   string pullback; // "TOUCH+RECLAIM", "NO TOUCH", "NOT RECLAIMED", "WEAK CLOSE", "OVEREXTENDED", "OFF"
};

// ---------------------------------------------------------------------------
// The entry rule.
// ---------------------------------------------------------------------------

// The whole entry decision on one closed candle, in six steps; each failure
// sets the verdict and the reason and returns NONE. There is no RSI step: it
// restated the trend and extension steps with four numbers nobody can choose.
EXSparkSignalDirection XSparkTrendScalpBarDirection(const XSparkCandle &bar1,
                                                    const double ema21,
                                                    const double ema50,
                                                    const double ema50_higher,
                                                    const double atr14,
                                                    const XSparkTrendScalpConfig &config,
                                                    XSparkTrendScalpVerdicts &verdicts,
                                                    string &reason)
{
   verdicts.trend = "NO DATA";
   verdicts.pullback = "OFF";
   reason = "";

   // Step 1: every input usable. A rule that reads a zero average as a price
   // would find a "trend" in the indicator's warm-up.
   if(!MathIsValidNumber(bar1.open) || !MathIsValidNumber(bar1.high) ||
      !MathIsValidNumber(bar1.low) || !MathIsValidNumber(bar1.close) ||
      bar1.open <= 0.0 || bar1.high <= 0.0 || bar1.low <= 0.0 || bar1.close <= 0.0)
   {
      reason = "Closed candle prices are not usable.";
      return XSPARK_SIGNAL_NONE;
   }

   if(bar1.high < bar1.low)
   {
      reason = "Closed candle high is below its low.";
      return XSPARK_SIGNAL_NONE;
   }

   const double range = bar1.high - bar1.low;

   if(range <= 0.0)
   {
      reason = "Closed candle has no range, so the close has no position inside it.";
      return XSPARK_SIGNAL_NONE;
   }

   if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
   {
      reason = "The typical candle size is unavailable.";
      return XSPARK_SIGNAL_NONE;
   }

   if(!MathIsValidNumber(ema21) || ema21 <= 0.0 ||
      !MathIsValidNumber(ema50) || ema50 <= 0.0 ||
      !MathIsValidNumber(ema50_higher) || ema50_higher <= 0.0)
   {
      reason = "The moving averages are unavailable.";
      return XSPARK_SIGNAL_NONE;
   }

   // Step 2: a trend on the chart period, agreed by the higher one.
   const double gap = config.min_ema_gap_atr * atr14;
   const bool base_up = ema21 - ema50 >= gap;
   const bool base_down = !base_up && ema50 - ema21 >= gap;

   if(!base_up && !base_down)
   {
      verdicts.trend = "NO TREND";
      reason = StringFormat("The fast average is %.2f typical candles from the slow one; a trend needs at least %.2f.",
                            MathAbs(ema21 - ema50) / atr14,
                            config.min_ema_gap_atr);
      return XSPARK_SIGNAL_NONE;
   }

   if(base_up && bar1.close <= ema50_higher)
   {
      verdicts.trend = "BIAS CONFLICT";
      reason = "The chart period trends up but the close is not above the higher period's slow average.";
      return XSPARK_SIGNAL_NONE;
   }

   if(base_down && bar1.close >= ema50_higher)
   {
      verdicts.trend = "BIAS CONFLICT";
      reason = "The chart period trends down but the close is not below the higher period's slow average.";
      return XSPARK_SIGNAL_NONE;
   }

   verdicts.trend = base_up ? "UPTREND" : "DOWNTREND";

   // Step 3: the candle reached the fast average.
   const double touch = config.touch_atr * atr14;
   const bool touched = base_up ? bar1.low <= ema21 + touch
                                : bar1.high >= ema21 - touch;

   if(!touched)
   {
      verdicts.pullback = "NO TOUCH";
      reason = StringFormat("The candle did not reach the fast average at %.8f within %.2f typical candles.",
                            ema21,
                            config.touch_atr);
      return XSPARK_SIGNAL_NONE;
   }

   // Step 4: and closed back on the trend's side of it, in the trend's
   // direction. A candle that touched and closed below the average is the
   // trend failing, not pulling back.
   const bool reclaimed = base_up ? (bar1.close > ema21 && bar1.close > bar1.open)
                                  : (bar1.close < ema21 && bar1.close < bar1.open);

   if(!reclaimed)
   {
      verdicts.pullback = "NOT RECLAIMED";
      reason = base_up ? "The candle touched the fast average but did not close above both it and its own open."
                       : "The candle touched the fast average but did not close below both it and its own open.";
      return XSPARK_SIGNAL_NONE;
   }

   // Step 5: the close is in the trend's half of the candle.
   const double close_position = base_up ? (bar1.close - bar1.low) / range
                                         : (bar1.high - bar1.close) / range;

   if(close_position < config.min_close_position)
   {
      verdicts.pullback = "WEAK CLOSE";
      reason = StringFormat("The close sits at %.0f%% of the candle's range; at least %.0f%% is required.",
                            close_position * 100.0,
                            config.min_close_position * 100.0);
      return XSPARK_SIGNAL_NONE;
   }

   // Step 6: no chasing.
   const double extension = base_up ? bar1.close - ema21 : ema21 - bar1.close;

   if(extension > config.max_extension_atr * atr14)
   {
      verdicts.pullback = "OVEREXTENDED";
      reason = StringFormat("The close is %.2f typical candles past the fast average; at most %.2f is allowed.",
                            extension / atr14,
                            config.max_extension_atr);
      return XSPARK_SIGNAL_NONE;
   }

   verdicts.pullback = "TOUCH+RECLAIM";
   reason = StringFormat("%s: the candle touched the fast average at %.8f and closed at %.8f, %.0f%% up its range.",
                         verdicts.trend,
                         ema21,
                         bar1.close,
                         close_position * 100.0);
   return base_up ? XSPARK_SIGNAL_BUY : XSPARK_SIGNAL_SELL;
}

// How far beyond the wick the stop sits: a share of the typical candle, so
// it rescales with the chart period.
bool XSparkTrendScalpBuffer(const double atr14,
                            const double atr_mult,
                            double &buffer,
                            string &reason)
{
   buffer = 0.0;
   reason = "";

   if(!MathIsValidNumber(atr_mult) || atr_mult <= 0.0)
   {
      reason = "The wick buffer must be a finite positive multiple of the typical candle.";
      return false;
   }

   if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
   {
      reason = "The wick buffer needs the typical candle size and it is unavailable.";
      return false;
   }

   buffer = atr_mult * atr14;

   if(!MathIsValidNumber(buffer) || buffer <= 0.0)
   {
      buffer = 0.0;
      reason = "Derived wick buffer is not a usable distance.";
      return false;
   }

   return true;
}

// The protective anchor the signal candle implies: its far wick, pushed out
// by the buffer.
bool XSparkTrendScalpAnchor(const EXSparkSignalDirection direction,
                            const XSparkCandle &bar1,
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

   if(!MathIsValidNumber(bar1.high) || !MathIsValidNumber(bar1.low) ||
      bar1.high <= 0.0 || bar1.low <= 0.0 || bar1.high < bar1.low)
   {
      reason = "Closed candle range is not usable for an anchor.";
      return false;
   }

   if(!MathIsValidNumber(buffer) || buffer < 0.0)
   {
      reason = "Wick buffer is not a usable distance.";
      return false;
   }

   anchor = direction == XSPARK_SIGNAL_BUY ? bar1.low - buffer : bar1.high + buffer;

   if(!MathIsValidNumber(anchor) || anchor <= 0.0)
   {
      anchor = 0.0;
      reason = "Derived anchor price is not positive.";
      return false;
   }

   return true;
}

// ---------------------------------------------------------------------------
// Cost.
// ---------------------------------------------------------------------------

// What a round trip costs, in price: the spread (paid on entry, because the
// exit triggers on the other side of it) plus the commission converted from
// account money per lot into price. One tick of one lot is worth tick_value,
// so commission_per_lot / tick_value ticks, times tick_size, is the
// commission in price. Gold: 7 x 0.01 / 1 = 0.07 per unit of price; EURUSD:
// 7 x 0.00001 / 1 = 0.7 pip. Refuses negative or non-finite inputs; a
// commission of 0 is valid.
bool XSparkTrendScalpRoundTripCost(const double spread,
                                   const double commission_per_lot,
                                   const double tick_size,
                                   const double tick_value,
                                   double &cost,
                                   double &commission_price,
                                   string &reason)
{
   cost = 0.0;
   commission_price = 0.0;
   reason = "";

   if(!MathIsValidNumber(spread) || spread < 0.0)
   {
      reason = "The buy/sell gap is not a usable distance.";
      return false;
   }

   if(!MathIsValidNumber(commission_per_lot) || commission_per_lot < 0.0)
   {
      reason = "The commission per lot must be finite and non-negative.";
      return false;
   }

   if(!MathIsValidNumber(tick_size) || tick_size <= 0.0 ||
      !MathIsValidNumber(tick_value) || tick_value <= 0.0)
   {
      reason = "The instrument's tick size and tick value are not usable, so the commission cannot be converted to price.";
      return false;
   }

   commission_price = commission_per_lot * tick_size / tick_value;
   cost = spread + commission_price;

   if(!MathIsValidNumber(cost) || cost < 0.0)
   {
      cost = 0.0;
      commission_price = 0.0;
      reason = "Derived round-trip cost is not a usable distance.";
      return false;
   }

   return true;
}

// Turns the candle anchor into the stop the entry will be sized from, bounded
// against the LIVE entry reference: the EA calls this at planning time.
//
// Three candidates and the widest wins: the candle anchor, the floor of one
// typical candle, and the COST FLOOR - the distance at which the round-trip
// cost is exactly the permitted share of the stop. Widening to a floor only
// ever reduces the volume, so no floor can raise realised risk. Above the
// ceiling the entry is refused, and the reason says WHICH term put it there,
// because the two have different fixes: a deep candle is this bar's problem,
// a binding cost floor is the chart period's or the account's.
bool XSparkTrendScalpStop(const EXSparkSignalDirection direction,
                          const double reference,
                          const double anchor,
                          const double atr14,
                          const double round_trip_cost,
                          const XSparkTrendScalpConfig &config,
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

   if(!MathIsValidNumber(atr14) || atr14 <= 0.0)
   {
      reason = "The stop bounds need the typical candle size and it is unavailable.";
      return false;
   }

   if(!MathIsValidNumber(round_trip_cost) || round_trip_cost < 0.0)
   {
      reason = "The round-trip cost is not a usable distance.";
      return false;
   }

   if(!MathIsValidNumber(config.min_stop_atr_mult) || config.min_stop_atr_mult <= 0.0 ||
      !MathIsValidNumber(config.max_stop_atr_mult) || config.max_stop_atr_mult <= config.min_stop_atr_mult ||
      !MathIsValidNumber(config.max_cost_share_pct) || config.max_cost_share_pct <= 0.0 || config.max_cost_share_pct >= 100.0)
   {
      reason = "The stop bounds and cost share are not a usable configuration.";
      return false;
   }

   const double anchor_distance = direction == XSPARK_SIGNAL_BUY ? reference - anchor
                                                                 : anchor - reference;
   const double atr_floor = config.min_stop_atr_mult * atr14;
   const double cost_floor = round_trip_cost * 100.0 / config.max_cost_share_pct;
   const double ceiling = config.max_stop_atr_mult * atr14;

   double used = anchor_distance;
   if(atr_floor > used)
      used = atr_floor;

   const bool cost_binding = cost_floor > used;
   if(cost_binding)
      used = cost_floor;

   if(!MathIsValidNumber(used) || used <= 0.0)
   {
      reason = "No usable stop distance could be derived.";
      return false;
   }

   if(used > ceiling)
   {
      if(cost_binding)
      {
         reason = StringFormat("COST: the round-trip cost %.8f is %.1f%% of the widest stop this chart period allows (%.8f); "
                               "at most %.1f%% is permitted. A longer chart period, a tighter-spread account, or a lower commission fixes this.",
                               round_trip_cost,
                               round_trip_cost / ceiling * 100.0,
                               ceiling,
                               config.max_cost_share_pct);
      }
      else
      {
         reason = StringFormat("The pullback candle is too deep for a scalp: stop %.2f x the typical candle, ceiling %.2f.",
                               used / atr14,
                               config.max_stop_atr_mult);
      }

      return false;
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

// ---------------------------------------------------------------------------
// Exit styles. The enum is a wire format: MetaTrader stores the integer, so
// members are added at the end and never renumbered.
// ---------------------------------------------------------------------------

enum EXSparkScalpExitStyle
{
   XSPARK_SCALP_EXIT_EVEN  = 0, // Target equal to the stop (no edge wins 47%; break-even 50%)
   XSPARK_SCALP_EXIT_QUICK = 1  // Target 0.8x the stop (no edge wins 52%; break-even 55.6%)
};

bool XSparkTrendScalpTargetForStyle(const EXSparkScalpExitStyle style,
                                    double &target_r,
                                    string &reason)
{
   target_r = 0.0;
   reason = "";

   switch(style)
   {
      case XSPARK_SCALP_EXIT_EVEN:
         target_r = XSPARK_TRENDSCALP_TARGET_R_EVEN;
         return true;
      case XSPARK_SCALP_EXIT_QUICK:
         target_r = XSPARK_TRENDSCALP_TARGET_R_QUICK;
         return true;
      default:
         break;
   }

   reason = "The exit style is not one this build knows.";
   return false;
}

// The win rate a trade with NO edge shows at this target and cost share, as a
// fraction: (1 - share/100) / (1 + r). It is the number every journal line
// compares the observed win rate against, and it is zero for an unusable
// input so a wrong call prints something obviously wrong rather than 50%.
double XSparkTrendScalpNoEdgeWinRate(const double target_r, const double cost_share_pct)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0 ||
      !MathIsValidNumber(cost_share_pct) || cost_share_pct < 0.0 || cost_share_pct >= 100.0)
      return 0.0;

   return (1.0 - cost_share_pct / 100.0) / (1.0 + target_r);
}

// The win rate at which this target breaks even before any cost, as a
// fraction: 1 / (1 + r). Zero for an unusable target, as above.
double XSparkTrendScalpBreakEvenWinRate(const double target_r)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0)
      return 0.0;

   return 1.0 / (1.0 + target_r);
}

// ---------------------------------------------------------------------------
// Sessions.
//
// Fixed UTC windows. DST shifts London and New York by one hour against them
// twice a year, and that is accepted: an hour at either edge of a fourteen-
// hour window is not what decides a scalp, and a DST-aware window would need
// a calendar the tester does not have. The ALL choice is expected to trade
// sparsely in Asian hours on gold and FX, because the cost gate and the
// volatility floor bite hardest there; it is a comparison, not a
// recommendation. London-only, New York-only and Asia-only are not shipped;
// they go at the END of the enum if the first A/B warrants them.
// ---------------------------------------------------------------------------

enum EXSparkScalpSessions
{
   XSPARK_SCALP_SESSIONS_ALL    = 0, // Asian, London and New York (01:00-21:00 UTC)
   XSPARK_SCALP_SESSIONS_LDN_NY = 1  // London and New York only (07:00-21:00 UTC)
};

bool XSparkTrendScalpSessionWindow(const EXSparkScalpSessions sessions,
                                   int &start_utc_seconds,
                                   int &end_utc_seconds,
                                   string &reason)
{
   start_utc_seconds = 0;
   end_utc_seconds = 0;
   reason = "";

   switch(sessions)
   {
      case XSPARK_SCALP_SESSIONS_ALL:
         start_utc_seconds = XSPARK_TRENDSCALP_SESSION_ASIA_OPEN_UTC_SECONDS;
         end_utc_seconds = XSPARK_TRENDSCALP_SESSION_CLOSE_UTC_SECONDS;
         return true;
      case XSPARK_SCALP_SESSIONS_LDN_NY:
         start_utc_seconds = XSPARK_TRENDSCALP_SESSION_LONDON_OPEN_UTC_SECONDS;
         end_utc_seconds = XSPARK_TRENDSCALP_SESSION_CLOSE_UTC_SECONDS;
         return true;
      default:
         break;
   }

   reason = "The session choice is not one this build knows.";
   return false;
}

// Seconds since midnight UTC for a broker-clock instant. Long arithmetic
// throughout, never MqlDateTime: the offset can push the instant across
// midnight in either direction, and the double modulo folds a negative
// remainder back into the day.
bool XSparkTrendScalpUtcSecondsOfDay(const datetime server_time,
                                     const int broker_utc_offset_hours,
                                     long &utc_seconds_of_day,
                                     string &reason)
{
   utc_seconds_of_day = 0;
   reason = "";

   if(broker_utc_offset_hours < XSPARK_TRENDSCALP_MIN_UTC_OFFSET_HOURS ||
      broker_utc_offset_hours > XSPARK_TRENDSCALP_MAX_UTC_OFFSET_HOURS)
   {
      reason = StringFormat("The broker clock offset %d is outside %d..%d hours.",
                            broker_utc_offset_hours,
                            XSPARK_TRENDSCALP_MIN_UTC_OFFSET_HOURS,
                            XSPARK_TRENDSCALP_MAX_UTC_OFFSET_HOURS);
      return false;
   }

   if((long)server_time <= 0)
   {
      reason = "The broker time is not usable.";
      return false;
   }

   const long day = (long)XSPARK_TRENDSCALP_SECONDS_PER_DAY;
   const long utc = (long)server_time - (long)broker_utc_offset_hours * 3600;
   utc_seconds_of_day = ((utc % day) + day) % day;
   return true;
}

// Whether a new entry is permitted now. The window is half-open,
// [start, end - lead): the lead keeps a trade from being opened and then
// flattened minutes later at the session end.
bool XSparkTrendScalpSessionAllows(const datetime server_time,
                                   const int broker_utc_offset_hours,
                                   const EXSparkScalpSessions sessions,
                                   const int lead_seconds,
                                   string &reason)
{
   reason = "";

   int start = 0;
   int end = 0;
   if(!XSparkTrendScalpSessionWindow(sessions, start, end, reason))
      return false;

   if(lead_seconds < 0 || lead_seconds >= end - start)
   {
      reason = "The session-close lead must be non-negative and shorter than the window.";
      return false;
   }

   long utc = 0;
   if(!XSparkTrendScalpUtcSecondsOfDay(server_time, broker_utc_offset_hours, utc, reason))
      return false;

   const long last_entry = (long)end - (long)lead_seconds;

   if(utc < (long)start || utc >= last_entry)
   {
      reason = StringFormat("%02d:%02d UTC is outside the entry window %02d:%02d-%02d:%02d UTC.",
                            (int)(utc / 3600),
                            (int)((utc % 3600) / 60),
                            start / 3600,
                            (start % 3600) / 60,
                            (int)(last_entry / 3600),
                            (int)((last_entry % 3600) / 60));
      return false;
   }

   return true;
}

// The broker-clock instant after which every open position is flattened:
// today's window end when inside the window, and "now" when outside it, so a
// position still open outside the window - after a restart, say - is
// flattened at once rather than at the next day's end.
bool XSparkTrendScalpSessionEnd(const datetime server_time,
                                const int broker_utc_offset_hours,
                                const EXSparkScalpSessions sessions,
                                datetime &flatten_after_server_time,
                                string &reason)
{
   flatten_after_server_time = 0;
   reason = "";

   int start = 0;
   int end = 0;
   if(!XSparkTrendScalpSessionWindow(sessions, start, end, reason))
      return false;

   long utc = 0;
   if(!XSparkTrendScalpUtcSecondsOfDay(server_time, broker_utc_offset_hours, utc, reason))
      return false;

   if(utc >= (long)start && utc < (long)end)
   {
      flatten_after_server_time = (datetime)((long)server_time + ((long)end - utc));
      reason = StringFormat("Inside the trading window; open positions are flattened at %s on the broker's clock.",
                            TimeToString(flatten_after_server_time, TIME_DATE | TIME_MINUTES));
      return true;
   }

   flatten_after_server_time = server_time;
   reason = "Outside the trading window; any open position is flattened now.";
   return true;
}

// The offset is an input because the tester emulates TimeGMT() equal to the
// server time, so a measured offset would make a backtest disagree with live.
// Live it IS measurable, and the EA measures it hourly and compares here: a
// mismatch means every session window is shifted by the difference, so
// entries are blocked until they agree.
bool XSparkTrendScalpOffsetMatches(const int observed_hours,
                                   const int configured_hours,
                                   string &reason)
{
   reason = "";

   if(observed_hours == configured_hours)
      return true;

   reason = StringFormat("The broker's clock is %d hours from UTC but the offset setting says %d. "
                         "Set the offset to %d and restart; entries are blocked until they agree.",
                         observed_hours,
                         configured_hours,
                         observed_hours);
   return false;
}

// ---------------------------------------------------------------------------
// Daily cap. Constant and fail-closed: a negative count means the trade
// history could not be read, and a cap that cannot be checked is a cap that
// refuses. There is no loss-streak pause: at a 50% win rate three losses in a
// row happen in one three-trade window in eight, so it would throttle without
// evidence; the daily stop bounds a bad day.
// ---------------------------------------------------------------------------
bool XSparkTrendScalpDailyCapAllows(const int trades_today,
                                    const int max_per_day,
                                    string &reason)
{
   reason = "";

   if(trades_today < 0)
   {
      reason = "Trade history is unavailable; the daily cap cannot be checked.";
      return false;
   }

   if(max_per_day <= 0)
   {
      reason = "The daily cap is not a usable count.";
      return false;
   }

   if(trades_today >= max_per_day)
   {
      reason = StringFormat("%d trades were opened today; the daily cap is %d.",
                            trades_today,
                            max_per_day);
      return false;
   }

   return true;
}

// ---------------------------------------------------------------------------
// Resolution, never refusal.
// ---------------------------------------------------------------------------

// Turns what the operator typed into what the EA will actually run with, and
// reports every difference. Mirrors XSparkCandleFlowResolveLimits, including
// its convention that a total-drawdown level of 0 reads as OFF, so the two
// bots read a .set the same way. The reasoning is that function's: an
// out-of-range number must not return INIT_FAILED, because then OnTick never
// runs and the time stop, the session flatten, the weekend close and the
// killswitch all stop while live positions sit open at the broker.
//
// Every correction moves toward MORE safety except the level-0 convention;
// two of them - the commission and the offset - are reported at CRITICAL
// wording because the corrected value silently changes what the cost floor
// and the session windows measure.
//
// Pure: no terminal calls, so every branch is testable.
bool XSparkTrendScalpResolveLimits(const double raw_risk_pct,
                                   const double raw_min_lot_cap_pct,
                                   const double raw_daily_dd_pct,
                                   const double raw_total_dd_pct,
                                   const bool raw_use_killswitch,
                                   const double raw_commission_per_lot,
                                   const int raw_utc_offset_hours,
                                   double &risk_pct,
                                   double &min_lot_cap_pct,
                                   double &daily_dd_pct,
                                   double &total_dd_pct,
                                   bool &use_killswitch,
                                   double &commission_per_lot,
                                   int &utc_offset_hours,
                                   string &corrections)
{
   risk_pct = raw_risk_pct;
   min_lot_cap_pct = raw_min_lot_cap_pct;
   daily_dd_pct = raw_daily_dd_pct;
   total_dd_pct = raw_total_dd_pct;
   use_killswitch = raw_use_killswitch;
   commission_per_lot = raw_commission_per_lot;
   utc_offset_hours = raw_utc_offset_hours;
   corrections = "";

   bool corrected = false;

   if(!MathIsValidNumber(risk_pct) || risk_pct <= 0.0)
   {
      corrections += StringFormat("Money risked on one trade was %.4f, which cannot size a trade; using %.2f%%. ",
                                  raw_risk_pct,
                                  XSPARK_TRENDSCALP_DEFAULT_RISK_PCT);
      risk_pct = XSPARK_TRENDSCALP_DEFAULT_RISK_PCT;
      corrected = true;
   }
   else if(risk_pct > XSPARK_TRENDSCALP_MAX_RISK_PCT)
   {
      // Clamped DOWN, never refused: running at the ceiling is what they
      // would have got by typing the ceiling, and it is strictly safer than
      // what they asked for.
      corrections += StringFormat("Money risked on one trade was %.2f%%, above this bot's %.2f%% ceiling; using the ceiling. ",
                                  raw_risk_pct,
                                  XSPARK_TRENDSCALP_MAX_RISK_PCT);
      risk_pct = XSPARK_TRENDSCALP_MAX_RISK_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(min_lot_cap_pct) || min_lot_cap_pct < 0.0)
   {
      corrections += StringFormat("The small-account cap was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  raw_min_lot_cap_pct,
                                  XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT);
      min_lot_cap_pct = XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT;
      corrected = true;
   }
   else if(min_lot_cap_pct > XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT)
   {
      corrections += StringFormat("The small-account cap was %.2f%%, above this bot's %.2f%% ceiling; using the ceiling. ",
                                  raw_min_lot_cap_pct,
                                  XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT);
      min_lot_cap_pct = XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(daily_dd_pct) || daily_dd_pct <= 0.0 || daily_dd_pct >= 100.0)
   {
      // A daily limit of zero halts trading at zero drawdown, permanently.
      corrections += StringFormat("The daily loss limit was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  raw_daily_dd_pct,
                                  XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT);
      daily_dd_pct = XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(total_dd_pct) || total_dd_pct >= 100.0)
   {
      corrections += StringFormat("The emergency stop level was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  raw_total_dd_pct,
                                  XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT);
      total_dd_pct = XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT;
      corrected = true;
   }
   else if(total_dd_pct <= 0.0)
   {
      // The one correction that reduces protection, kept for consistency
      // with CandleFlow: an earlier build labelled the level "(0 = off)", and
      // a .set carrying that 0 must mean the same thing in every bot. Stated
      // at CRITICAL and names the switch that replaced it.
      corrections += StringFormat("The emergency stop level was 0, which an earlier build read as OFF, so the emergency stop is OFF. "
                                  "Use the emergency-stop switch instead, and set the level back to %.2f%%. ",
                                  XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT);
      total_dd_pct = XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT;
      use_killswitch = false;
      corrected = true;
   }

   // A daily limit at or above the emergency stop never fires, because the
   // emergency stop closes everything first. Harmless, so reported and left.
   if(use_killswitch && daily_dd_pct >= total_dd_pct)
   {
      corrections += StringFormat("The daily loss limit (%.2f%%) is at or above the emergency stop (%.2f%%), so it can never act; the emergency stop applies first. ",
                                  daily_dd_pct,
                                  total_dd_pct);
      corrected = true;
   }

   if(!MathIsValidNumber(commission_per_lot) || commission_per_lot < 0.0)
   {
      // Zero is the only replacement that does not invent a cost, but it
      // UNDER-counts on a commission account: the cost floor will admit
      // trades it should refuse until the live verification catches the
      // first closure. Said as loudly as the resolver can.
      corrections += StringFormat("CRITICAL: the commission per lot was %.4f, which is not a usable amount; using %.2f. "
                                  "Round-trip costs are now UNDER-COUNTED on a commission account until this is set. ",
                                  raw_commission_per_lot,
                                  XSPARK_TRENDSCALP_DEFAULT_COMMISSION_PER_LOT);
      commission_per_lot = XSPARK_TRENDSCALP_DEFAULT_COMMISSION_PER_LOT;
      corrected = true;
   }

   if(utc_offset_hours < XSPARK_TRENDSCALP_MIN_UTC_OFFSET_HOURS ||
      utc_offset_hours > XSPARK_TRENDSCALP_MAX_UTC_OFFSET_HOURS)
   {
      corrections += StringFormat("CRITICAL: the broker clock offset was %d, outside %d..%d hours; using %d. "
                                  "The session windows are wrong until this is set, and the live clock check will block entries. ",
                                  raw_utc_offset_hours,
                                  XSPARK_TRENDSCALP_MIN_UTC_OFFSET_HOURS,
                                  XSPARK_TRENDSCALP_MAX_UTC_OFFSET_HOURS,
                                  XSPARK_TRENDSCALP_DEFAULT_UTC_OFFSET);
      utc_offset_hours = XSPARK_TRENDSCALP_DEFAULT_UTC_OFFSET;
      corrected = true;
   }

   return !corrected;
}

// ---------------------------------------------------------------------------
// Statistics for the OnTester verdict.
// ---------------------------------------------------------------------------

// The lower end of the 95% Wilson score interval on the win rate. Used rather
// than the plain proportion because the question the tester answers is not
// "was the win rate above 50%" but "is the sample large enough to say so":
// 55 of 100 is not, 220 of 400 barely is. Refuses an empty or impossible
// sample and leaves the bound at 0, which is the honest reading of "no
// evidence".
bool XSparkTrendScalpWilsonLowerBound(const int wins,
                                      const int outcomes,
                                      double &lower)
{
   lower = 0.0;

   if(outcomes <= 0 || wins < 0 || wins > outcomes)
      return false;

   const double n = (double)outcomes;
   const double p = (double)wins / n;
   const double z = XSPARK_TRENDSCALP_WILSON_Z;
   const double z2 = z * z;

   const double centre = p + z2 / (2.0 * n);
   const double margin = z * MathSqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n));
   const double bound = (centre - margin) / (1.0 + z2 / n);

   if(!MathIsValidNumber(bound))
      return false;

   lower = bound < 0.0 ? 0.0 : bound;
   return true;
}

// ---------------------------------------------------------------------------
// Friday close.
// ---------------------------------------------------------------------------

// Turns an instrument's own Friday session into the moment this bot flattens.
// Pure: the caller does the terminal lookup and hands over the RAW session
// end in seconds from the start of the day, exactly as SymbolInfoSessionTrade
// reports it. A session ending at 24:00 is reported as 86400, and that value
// is read as 1440 end-minutes so the flatten lands at 23:00 with the
// one-hour lead; folding it through "% 24" first would read it as 00:00 and
// flatten a whole day early. Anything above 86400 cannot come from the
// terminal and falls back.
//
// Three outcomes, each stated rather than inferred: the instrument trades at
// the weekend, so there is no gap to protect against; its Friday session is
// readable, so flatten the lead time before it ends; it is not readable, so
// fall back to the early hour and say so.
bool XSparkTrendScalpWeekendClose(const bool trades_at_weekend,
                                  const bool friday_session_known,
                                  const int friday_end_seconds,
                                  bool &use_weekend_close,
                                  int &close_hour,
                                  int &close_minute,
                                  string &reason)
{
   use_weekend_close = true;
   close_hour = XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR;
   close_minute = XSPARK_TRENDSCALP_WEEKEND_CLOSE_MINUTE;
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
                       friday_end_seconds >= 0 &&
                       friday_end_seconds <= XSPARK_TRENDSCALP_SECONDS_PER_DAY;

   if(!usable)
   {
      reason = StringFormat("The broker did not report a usable Friday session, so trades are closed at %02d:%02d on its clock.",
                            close_hour,
                            close_minute);
      return true;
   }

   const int end_minutes = friday_end_seconds >= XSPARK_TRENDSCALP_SECONDS_PER_DAY ? 1440
                                                                                   : friday_end_seconds / 60;
   int flatten_minutes = end_minutes - XSPARK_TRENDSCALP_WEEKEND_CLOSE_LEAD_MINUTES;

   // A session ending inside the lead time would push the flatten into the
   // previous day, which ShouldWeekendClose cannot express; closing as the
   // day opens is the honest reading and still the safe direction.
   if(flatten_minutes < 0)
      flatten_minutes = 0;

   close_hour = flatten_minutes / 60;
   close_minute = flatten_minutes % 60;

   reason = StringFormat("This market's Friday session ends at %02d:%02d, so trades are closed at %02d:%02d on the broker's clock.",
                         end_minutes / 60,
                         end_minutes % 60,
                         close_hour,
                         close_minute);
   return true;
}

// ---------------------------------------------------------------------------
// Small accounts.
// ---------------------------------------------------------------------------

// What the broker's minimum lot risks at the smallest stop this setup can
// produce, in cash and as a share of the balance. It is the number an operator
// must read before funding a $100 account: 0.01 lot of gold with a $1.50 stop
// risks $1.50, and at 1% of $100 the budget is $1.00, so the minimum lot -
// not the risk percentage - decides the trade. One tick of one lot is worth
// tick_value, so the stop is min_stop_price / tick_size ticks.
bool XSparkTrendScalpMinimumLotRisk(const double volume_min,
                                    const double min_stop_price,
                                    const double tick_size,
                                    const double tick_value,
                                    const double balance,
                                    double &risk_cash,
                                    double &risk_pct,
                                    string &reason)
{
   risk_cash = 0.0;
   risk_pct = 0.0;
   reason = "";

   if(!MathIsValidNumber(volume_min) || volume_min <= 0.0)
   {
      reason = "The broker's minimum volume is not usable.";
      return false;
   }

   if(!MathIsValidNumber(min_stop_price) || min_stop_price <= 0.0)
   {
      reason = "The smallest stop distance is not usable.";
      return false;
   }

   if(!MathIsValidNumber(tick_size) || tick_size <= 0.0 ||
      !MathIsValidNumber(tick_value) || tick_value <= 0.0)
   {
      reason = "The instrument's tick size and tick value are not usable.";
      return false;
   }

   if(!MathIsValidNumber(balance) || balance <= 0.0)
   {
      reason = "The account balance is not usable.";
      return false;
   }

   risk_cash = volume_min * (min_stop_price / tick_size) * tick_value;
   risk_pct = risk_cash / balance * 100.0;

   if(!MathIsValidNumber(risk_cash) || !MathIsValidNumber(risk_pct) || risk_cash <= 0.0)
   {
      risk_cash = 0.0;
      risk_pct = 0.0;
      reason = "The minimum-lot risk could not be derived.";
      return false;
   }

   return true;
}

// ---------------------------------------------------------------------------
// The strategy object.
// ---------------------------------------------------------------------------

class CXSparkTrendScalp : public IXSparkStrategy
{
private:
   XSparkTrendScalpConfig m_config;
   string m_symbol;
   bool   m_initialized;
   string m_last_reason;

public:
   CXSparkTrendScalp()
   {
      XSparkDefaultTrendScalpConfig(m_config);
      m_symbol = "";
      m_initialized = false;
      m_last_reason = "TrendScalp is not initialized.";
   }

   void Configure(const XSparkTrendScalpConfig &config)
   {
      m_config = config;
   }

   // The reward ratio every signal carries. The execution engine derives the
   // take-profit price from it and the stop distance it actually gets. Zero
   // only for a configuration Initialize has already refused.
   double TargetRewardRatio()
   {
      if(!MathIsValidNumber(m_config.target_r) || m_config.target_r <= 0.0)
         return 0.0;

      return m_config.target_r;
   }

   bool Initialize(const string symbol)
   {
      m_initialized = false;

      if(symbol == "")
      {
         m_last_reason = "TrendScalp requires a symbol.";
         return false;
      }

      string config_reason = "";
      if(!XSparkValidateTrendScalpConfig(m_config, config_reason))
      {
         m_last_reason = config_reason;
         return false;
      }

      m_symbol = symbol;
      m_initialized = true;
      m_last_reason = "TrendScalp initialized.";
      return true;
   }

   void Deinitialize()
   {
      m_initialized = false;
      m_last_reason = "TrendScalp is not initialized.";
   }

   // The calibration feeds the instrument-scaled volatility band through the
   // same setter the other strategies use, so the EA's calibration path is
   // unchanged.
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

   // The whole entry decision. Produces a signal object; it never touches the
   // broker, the account, or the live quote. The report carries the two
   // verdicts for the panel, and joint_verdict is PASS only on a signal.
   bool Evaluate(CXSparkIndicatorCache &cache,
                 XSparkSignal &signal,
                 XSparkScoreBotReport &report)
   {
      XSparkResetSignal(signal);
      XSparkResetScoreBotReport(report);
      report.pattern_mode = "TREND PULLBACK";
      report.entry_location = "EMA PULLBACK";
      report.htf_verdict = "OFF";
      report.pullback_verdict = "OFF";
      report.rsi_verdict = "OFF";
      report.joint_verdict = "BLOCKED";

      if(!m_initialized)
      {
         report.status = "SCANNING";
         report.block_reason = "TrendScalp is not initialized.";
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
      const double ema21 = cache.EMA21Base();
      const double ema50 = cache.EMA50Base();
      const double ema50_higher = cache.EMA50Higher();

      report.signal_bar_time = bar1.time;
      report.atr14 = atr14;
      report.atr50 = atr50;
      report.atr_points = m_config.score_point_size > 0.0 ? atr14 / m_config.score_point_size : 0.0;
      report.atr50_points = m_config.score_point_size > 0.0 ? atr50 / m_config.score_point_size : 0.0;
      report.ema21_base = ema21;
      report.ema50_base = ema50;
      report.ema50_higher = ema50_higher;
      report.context.bar1_open = bar1.open;
      report.context.bar1_high = bar1.high;
      report.context.bar1_low = bar1.low;
      report.context.bar1_close = bar1.close;
      report.context.atr14 = atr14;
      report.effective_threshold = 0.0;
      // The engine derives the take-profit price from this at send time,
      // against the stop distance it actually gets.
      report.dynamic_rr = TargetRewardRatio();

      XSparkTrendScalpVerdicts verdicts;
      string direction_reason = "";
      const EXSparkSignalDirection direction = XSparkTrendScalpBarDirection(bar1,
                                                                            ema21,
                                                                            ema50,
                                                                            ema50_higher,
                                                                            atr14,
                                                                            m_config,
                                                                            verdicts,
                                                                            direction_reason);
      report.htf_verdict = verdicts.trend;
      report.pullback_verdict = verdicts.pullback;

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
      report.pattern_id = direction == XSPARK_SIGNAL_BUY ? XSPARK_PATTERN_SCALP_PULLBACK_LONG
                                                         : XSPARK_PATTERN_SCALP_PULLBACK_SHORT;
      report.pattern_name = XSparkPatternNameFromId(report.pattern_id);
      report.candidate_pattern = report.pattern_name;
      report.detected_patterns = report.pattern_name;

      // The gate is on by default here, so an uncalibrated band blocks as the
      // gate rather than as a scan: the status is what the funnel counts.
      if(m_config.use_volatility_gate)
      {
         if(m_config.score_point_size <= 0.0 || m_config.atr_min_points <= 0.0 || m_config.atr_max_points <= 0.0)
         {
            report.status = "ATR BLOCKED";
            report.block_reason = "The market-movement filter has no calibrated band yet, so entries wait for the calibration.";
            m_last_reason = report.block_reason;
            return false;
         }

         const double atr_points = atr14 / m_config.score_point_size;
         if(atr_points < m_config.atr_min_points || atr_points > m_config.atr_max_points)
         {
            report.status = "ATR BLOCKED";
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
      if(!XSparkTrendScalpBuffer(atr14, m_config.buffer_atr_mult, buffer, buffer_reason))
      {
         report.status = "SCANNING";
         report.block_reason = buffer_reason;
         m_last_reason = report.block_reason;
         return false;
      }

      double anchor = 0.0;
      string anchor_reason = "";
      if(!XSparkTrendScalpAnchor(direction, bar1, buffer, anchor, anchor_reason))
      {
         report.status = "SCANNING";
         report.block_reason = anchor_reason;
         m_last_reason = report.block_reason;
         return false;
      }

      report.detected_level = anchor;
      report.scored = true;
      report.threshold_passed = true;
      report.components.pattern = XSPARK_TRENDSCALP_SIGNAL_SCORE;
      report.components.raw = XSPARK_TRENDSCALP_SIGNAL_SCORE;
      report.components.final_score = XSPARK_TRENDSCALP_SIGNAL_SCORE;
      report.components.session_weight = 1.0;
      report.joint_verdict = "PASS";
      report.status = "SIGNAL";
      report.block_reason = "";

      signal.symbol = m_symbol;
      signal.direction = direction;
      signal.desired_stop = anchor;     // the raw candle anchor; the EA bounds it against the live quote and the cost floor
      // The price is deliberately not computed here: execution derives it
      // from the ratio and the stop distance it actually gets.
      signal.desired_target = 0.0;
      signal.dynamic_rr = TargetRewardRatio();
      signal.score = XSPARK_TRENDSCALP_SIGNAL_SCORE;
      signal.effective_threshold = 0.0;
      signal.pattern_score = XSPARK_TRENDSCALP_SIGNAL_SCORE;
      signal.session_weight = 1.0;
      signal.atr14 = atr14;
      signal.atr50 = atr50;
      signal.signal_bar_time = bar1.time;
      signal.instance_time = bar1.time;
      signal.pattern_id = (int)report.pattern_id;
      signal.pattern_name = report.pattern_name;
      signal.context = report.context;
      signal.reason = StringFormat("%s on the %s candle (%s); stop anchored at %.8f with a %.8f buffer, target %.2fx the stop.",
                                   report.pattern_name,
                                   TimeToString(bar1.time, TIME_DATE | TIME_MINUTES),
                                   direction_reason,
                                   anchor,
                                   buffer,
                                   TargetRewardRatio());

      m_last_reason = signal.reason;
      return true;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
