#ifndef XSPARK_TRADE_TRAILING_STOP_MQH
#define XSPARK_TRADE_TRAILING_STOP_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

// Trailing-stop arithmetic, as pure functions over prices.
//
// This is deliberately NOT in the Strategy layer. A trailing stop is a property
// of an open position, not of an entry rule, and PositionManager is what owns
// open positions - so the maths lives where both a strategy and the manager can
// reach it without either depending on the other.
//
// Nothing here reads the terminal, the broker or an indicator handle. Every
// input is a number the caller already holds, which is what makes the whole
// decision reproducible in a script rather than only observable in a backtest.
//
// The layers compose. Each produces a candidate stop; the most protective one
// wins; the floor then pushes the winner away from the market if it landed too
// close to be survivable. The one-way ratchet is applied by the caller, because
// only the caller knows where the live broker stop currently is.

// Below this the tiering arithmetic is not meaningfully different from a fixed
// multiple, and an interpolation across a near-zero R span amplifies noise.
#define XSPARK_TRAIL_MIN_TIER_SPAN_R 0.10

// The shipped configuration. These are the numbers the EA's inputs default to,
// declared here so the test that proves they form a VALID configuration is
// testing what actually ships rather than a copy of it.
//
// They are chosen for plausibility, not measured: a wide trail early so a young
// trade can breathe, tightening as it matures, and the entry protected once the
// trade has earned more than it risked. Nothing here is a profitability claim.
#define XSPARK_TRAIL_DEFAULT_FLOOR_ATR 0.35
#define XSPARK_TRAIL_DEFAULT_ATR 3.0
#define XSPARK_TRAIL_DEFAULT_TIGHT_ATR 1.5
#define XSPARK_TRAIL_DEFAULT_TIGHTEN_START_R 1.0
#define XSPARK_TRAIL_DEFAULT_TIGHTEN_FULL_R 4.0
#define XSPARK_TRAIL_DEFAULT_BREAKEVEN_R 1.2
#define XSPARK_TRAIL_DEFAULT_BREAKEVEN_OFFSET_R 0.1

struct XSparkTrailTuning
{
   // The trail may never sit closer to the market than this many ATRs. A stop
   // inside the spread plus ordinary noise is not protection, it is a delayed
   // market order.
   double min_trail_atr_mult;

   // Chandelier: trail from the best price the position has seen, measured on
   // closed candles. Zero disables the layer.
   double chandelier_atr_mult;
   double chandelier_tight_atr_mult;

   // Maturity tiering. Between these two R values the multiple moves linearly
   // from the wide one to the tight one, so there is no cliff at which a small
   // price change jumps the stop. Zero start disables tiering.
   double tighten_start_r;
   double tighten_full_r;

   // Breakeven lock. Once the position has been this far in front, its stop may
   // never again be worse than entry plus the offset. Zero disables the layer.
   double breakeven_at_r;
   double breakeven_offset_r;
};

void XSparkResetTrailTuning(XSparkTrailTuning &tuning)
{
   tuning.min_trail_atr_mult = 0.0;
   tuning.chandelier_atr_mult = 0.0;
   tuning.chandelier_tight_atr_mult = 0.0;
   tuning.tighten_start_r = 0.0;
   tuning.tighten_full_r = 0.0;
   tuning.breakeven_at_r = 0.0;
   tuning.breakeven_offset_r = 0.0;
}

void XSparkDefaultTrailTuning(XSparkTrailTuning &tuning)
{
   tuning.min_trail_atr_mult = XSPARK_TRAIL_DEFAULT_FLOOR_ATR;
   tuning.chandelier_atr_mult = XSPARK_TRAIL_DEFAULT_ATR;
   tuning.chandelier_tight_atr_mult = XSPARK_TRAIL_DEFAULT_TIGHT_ATR;
   tuning.tighten_start_r = XSPARK_TRAIL_DEFAULT_TIGHTEN_START_R;
   tuning.tighten_full_r = XSPARK_TRAIL_DEFAULT_TIGHTEN_FULL_R;
   tuning.breakeven_at_r = XSPARK_TRAIL_DEFAULT_BREAKEVEN_R;
   tuning.breakeven_offset_r = XSPARK_TRAIL_DEFAULT_BREAKEVEN_OFFSET_R;
}

bool XSparkValidateTrailTuning(const XSparkTrailTuning &tuning, string &reason)
{
   reason = "";

   if(!MathIsValidNumber(tuning.min_trail_atr_mult) || tuning.min_trail_atr_mult < 0.0 ||
      !MathIsValidNumber(tuning.chandelier_atr_mult) || tuning.chandelier_atr_mult < 0.0 ||
      !MathIsValidNumber(tuning.chandelier_tight_atr_mult) || tuning.chandelier_tight_atr_mult < 0.0 ||
      !MathIsValidNumber(tuning.tighten_start_r) || tuning.tighten_start_r < 0.0 ||
      !MathIsValidNumber(tuning.tighten_full_r) || tuning.tighten_full_r < 0.0 ||
      !MathIsValidNumber(tuning.breakeven_at_r) || tuning.breakeven_at_r < 0.0 ||
      !MathIsValidNumber(tuning.breakeven_offset_r))
   {
      reason = "Trailing-stop settings must be finite and non-negative.";
      return false;
   }

   if(tuning.chandelier_atr_mult > 0.0 && tuning.chandelier_tight_atr_mult > tuning.chandelier_atr_mult)
   {
      reason = "The tightened trail multiple must not be wider than the base one; tiering only ever tightens.";
      return false;
   }

   if(tuning.tighten_start_r > 0.0)
   {
      if(tuning.chandelier_atr_mult <= 0.0)
      {
         reason = "Trail tiering is configured but the trail itself is disabled.";
         return false;
      }

      if(tuning.chandelier_tight_atr_mult <= 0.0)
      {
         reason = "Trail tiering needs a positive tightened multiple.";
         return false;
      }

      if(tuning.tighten_full_r < tuning.tighten_start_r + XSPARK_TRAIL_MIN_TIER_SPAN_R)
      {
         reason = StringFormat("Trail tiering needs at least %.2fR between where tightening starts and where it completes.",
                               XSPARK_TRAIL_MIN_TIER_SPAN_R);
         return false;
      }
   }

   // A breakeven lock placed beyond entry in the LOSING direction would be a
   // stop worse than the one the trade opened with, which the ratchet would
   // refuse anyway - so it is a configuration error rather than a no-op.
   if(tuning.breakeven_at_r > 0.0 && tuning.breakeven_offset_r < 0.0 &&
      tuning.breakeven_offset_r <= -tuning.breakeven_at_r)
   {
      reason = "The breakeven offset gives back more than the trigger earns; the lock would never engage.";
      return false;
   }

   return true;
}

// The best price a position has seen, taken from CLOSED candles only.
//
// Classic Chandelier uses the extreme high or low, wick included, because that
// is the price the market actually reached. Sampling on the close instead would
// systematically under-state the excursion and trail too tightly.
double XSparkTrailUpdatedPeak(const EXSparkSignalDirection direction,
                              const double current_peak,
                              const double bar_high,
                              const double bar_low)
{
   if(direction == XSPARK_SIGNAL_BUY)
   {
      if(!MathIsValidNumber(bar_high) || bar_high <= 0.0)
         return current_peak;

      return (!MathIsValidNumber(current_peak) || current_peak <= 0.0) ? bar_high
                                                                      : MathMax(current_peak, bar_high);
   }

   if(direction == XSPARK_SIGNAL_SELL)
   {
      if(!MathIsValidNumber(bar_low) || bar_low <= 0.0)
         return current_peak;

      return (!MathIsValidNumber(current_peak) || current_peak <= 0.0) ? bar_low
                                                                      : MathMin(current_peak, bar_low);
   }

   return current_peak;
}

// How far in front the position has been, in units of its own initial risk.
//
// Measured from the PEAK rather than the current price on purpose: it is what
// the trade earned, not what it is holding right now. That makes it monotonic,
// so a tier once reached is never given back and the trail can never loosen
// because price retraced.
bool XSparkTrailPeakR(const EXSparkSignalDirection direction,
                      const double entry,
                      const double peak,
                      const double risk_distance,
                      double &peak_r)
{
   peak_r = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(entry) || entry <= 0.0 ||
      !MathIsValidNumber(peak) || peak <= 0.0 ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0)
   {
      return false;
   }

   const double advance = direction == XSPARK_SIGNAL_BUY ? peak - entry : entry - peak;

   if(!MathIsValidNumber(advance))
      return false;

   peak_r = advance / risk_distance;

   if(!MathIsValidNumber(peak_r))
   {
      peak_r = 0.0;
      return false;
   }

   // A position that has never traded in its favour has earned nothing. Its
   // excursion is reported as zero rather than negative, because every consumer
   // is asking "how mature is this trade", and the answer is "not at all".
   if(peak_r < 0.0)
      peak_r = 0.0;

   return true;
}

// The ATR multiple this maturity earns. Linear between the two R marks so the
// stop never jumps on a tier boundary.
bool XSparkTrailChandelierMultiple(const double peak_r,
                                   const XSparkTrailTuning &tuning,
                                   double &multiple)
{
   multiple = 0.0;

   if(!MathIsValidNumber(peak_r) || peak_r < 0.0 || tuning.chandelier_atr_mult <= 0.0)
      return false;

   multiple = tuning.chandelier_atr_mult;

   if(tuning.tighten_start_r <= 0.0 ||
      tuning.tighten_full_r < tuning.tighten_start_r + XSPARK_TRAIL_MIN_TIER_SPAN_R ||
      tuning.chandelier_tight_atr_mult <= 0.0)
   {
      return true;
   }

   if(peak_r <= tuning.tighten_start_r)
      return true;

   if(peak_r >= tuning.tighten_full_r)
   {
      multiple = tuning.chandelier_tight_atr_mult;
      return true;
   }

   const double span = tuning.tighten_full_r - tuning.tighten_start_r;
   const double progress = (peak_r - tuning.tighten_start_r) / span;
   multiple = tuning.chandelier_atr_mult +
              (tuning.chandelier_tight_atr_mult - tuning.chandelier_atr_mult) * progress;

   if(!MathIsValidNumber(multiple) || multiple <= 0.0)
   {
      multiple = tuning.chandelier_atr_mult;
      return true;
   }

   return true;
}

bool XSparkTrailChandelierStop(const EXSparkSignalDirection direction,
                               const double peak,
                               const double atr,
                               const double multiple,
                               double &stop)
{
   stop = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(peak) || peak <= 0.0 ||
      !MathIsValidNumber(atr) || atr <= 0.0 ||
      !MathIsValidNumber(multiple) || multiple <= 0.0)
   {
      return false;
   }

   const double candidate = direction == XSPARK_SIGNAL_BUY ? peak - multiple * atr
                                                           : peak + multiple * atr;

   if(!MathIsValidNumber(candidate) || candidate <= 0.0)
      return false;

   stop = candidate;
   return true;
}

bool XSparkTrailBreakevenStop(const EXSparkSignalDirection direction,
                              const double entry,
                              const double risk_distance,
                              const double offset_r,
                              double &stop)
{
   stop = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(entry) || entry <= 0.0 ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0 ||
      !MathIsValidNumber(offset_r))
   {
      return false;
   }

   const double candidate = direction == XSPARK_SIGNAL_BUY ? entry + offset_r * risk_distance
                                                           : entry - offset_r * risk_distance;

   if(!MathIsValidNumber(candidate) || candidate <= 0.0)
      return false;

   stop = candidate;
   return true;
}

// The more protective of two candidates. Zero means "this layer produced
// nothing", so it never wins.
double XSparkTrailMoreProtective(const EXSparkSignalDirection direction,
                                 const double first,
                                 const double second)
{
   const bool first_usable = MathIsValidNumber(first) && first > 0.0;
   const bool second_usable = MathIsValidNumber(second) && second > 0.0;

   if(!first_usable)
      return second_usable ? second : 0.0;

   if(!second_usable)
      return first;

   return direction == XSPARK_SIGNAL_BUY ? MathMax(first, second) : MathMin(first, second);
}

// Pushes a stop away from the market when it landed inside the floor.
//
// This is the difference between a trailing stop and a slow market order. A
// candle anchor or a tightened chandelier can easily land a few points from the
// bid, where the spread alone removes the position while the move it was riding
// is still intact. Widening can only ever REDUCE the chance of being stopped,
// and the caller's ratchet still refuses anything looser than the live stop, so
// this cannot give back protection already banked.
bool XSparkTrailApplyFloor(const EXSparkSignalDirection direction,
                           const double reference_price,
                           const double candidate,
                           const double atr,
                           const double min_trail_atr_mult,
                           double &floored,
                           string &reason)
{
   floored = candidate;
   reason = "";

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
   {
      reason = "A trail floor needs a BUY or SELL direction.";
      return false;
   }

   if(!MathIsValidNumber(candidate) || candidate <= 0.0)
   {
      reason = "Trail candidate is not a usable price.";
      return false;
   }

   if(min_trail_atr_mult <= 0.0)
      return true;

   if(!MathIsValidNumber(reference_price) || reference_price <= 0.0 ||
      !MathIsValidNumber(atr) || atr <= 0.0)
   {
      reason = "A trail floor is configured but the reference price or average range is unavailable.";
      return false;
   }

   const double floor_distance = min_trail_atr_mult * atr;
   const double distance = direction == XSPARK_SIGNAL_BUY ? reference_price - candidate
                                                          : candidate - reference_price;

   if(MathIsValidNumber(distance) && distance >= floor_distance)
      return true;

   const double widened = direction == XSPARK_SIGNAL_BUY ? reference_price - floor_distance
                                                         : reference_price + floor_distance;

   if(!MathIsValidNumber(widened) || widened <= 0.0)
   {
      reason = "Applying the trail floor produced a price that is not positive.";
      return false;
   }

   floored = widened;
   reason = "Trail candidate was inside the floor and was widened to it.";
   return true;
}

// The whole trailing decision for one position on one closed candle.
//
// Returns false when no layer produced anything usable, which the caller must
// treat as "leave the broker stop exactly where it is" rather than as an error:
// a stop that cannot be improved must never be removed.
bool XSparkTrailCandidate(const EXSparkSignalDirection direction,
                          const double entry,
                          const double risk_distance,
                          const double reference_price,
                          const double atr,
                          const double candle_anchor,
                          const double peak,
                          const XSparkTrailTuning &tuning,
                          double &stop,
                          double &peak_r,
                          string &reason)
{
   stop = 0.0;
   peak_r = 0.0;
   reason = "";

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
   {
      reason = "A trailing stop needs a BUY or SELL direction.";
      return false;
   }

   double candidate = 0.0;

   if(MathIsValidNumber(candle_anchor) && candle_anchor > 0.0)
      candidate = candle_anchor;

   const bool have_r = XSparkTrailPeakR(direction, entry, peak, risk_distance, peak_r);

   if(tuning.chandelier_atr_mult > 0.0 && have_r)
   {
      double multiple = 0.0;
      double chandelier = 0.0;

      if(XSparkTrailChandelierMultiple(peak_r, tuning, multiple) &&
         XSparkTrailChandelierStop(direction, peak, atr, multiple, chandelier))
      {
         candidate = XSparkTrailMoreProtective(direction, candidate, chandelier);
      }
   }

   if(tuning.breakeven_at_r > 0.0 && have_r && peak_r >= tuning.breakeven_at_r)
   {
      double breakeven = 0.0;

      if(XSparkTrailBreakevenStop(direction, entry, risk_distance, tuning.breakeven_offset_r, breakeven))
         candidate = XSparkTrailMoreProtective(direction, candidate, breakeven);
   }

   if(candidate <= 0.0)
   {
      reason = "No trailing layer produced a usable stop.";
      return false;
   }

   double floored = 0.0;
   string floor_reason = "";

   if(!XSparkTrailApplyFloor(direction, reference_price, candidate, atr,
                             tuning.min_trail_atr_mult, floored, floor_reason))
   {
      reason = floor_reason;
      return false;
   }

   stop = floored;
   reason = floor_reason;
   return true;
}

#endif
