#ifndef XSPARK_STRATEGY_ICT_LIQUIDITY_MQH
#define XSPARK_STRATEGY_ICT_LIQUIDITY_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

// ---------------------------------------------------------------------------
// ICT ("Inner Circle Trader") liquidity model, mechanized.
// ---------------------------------------------------------------------------
//
// WHAT THIS IS. The sequence most consistently taught across ICT material as
// the "2022 model": inside a session window, price runs a visible pool of stop
// orders, fails, breaks structure the other way with an impulsive leg, and the
// entry is a limit order back into the imbalance that leg left behind.
//
//   kill zone -> liquidity sweep -> market structure shift -> FVG entry
//
// Every one of those four is a shape in the bar array, so the whole sequence is
// decidable without judgement. That is the only reason this file can exist.
//
// WHAT IS NOT CLAIMED. ICT is taught discretionarily and has no published,
// independently audited track record. A large following is not evidence: it
// selects for survivors, and a discretionary method fits its own history in
// hindsight by construction. Nothing here says this model is profitable. What
// mechanizing it buys is the ability to find out - the same OnTester verdict
// TrendScalp carries, on a rule nobody can quietly rewrite after the fact.
//
// THE HONEST PART, carried the way every other strategy here carries it: the
// exit geometry sets the win rate a trade with NO edge would show, and the
// entry is the only possible source of edge. The difference from a moving
// average pullback is that this model claims a MECHANISM - stops really do rest
// above an obvious high, and taking them really does supply the other side -
// not merely a shape. A mechanism can still fail to pay for the spread.
//
// WHAT MECHANIZING FORCED US TO DECIDE. ICT leaves these open; a program cannot.
// Each is a named constant so a disagreement is a one-line change, not a
// rewrite, and so the funnel can show what each one costs:
//
//   - A swing needs a fixed number of bars either side (SWING_STRENGTH). ICT
//     reads swings by eye and at several degrees at once.
//   - A sweep must close back through the level on the SAME bar that pierced
//     it. ICT often allows the reversal to take several bars.
//   - Displacement is a body measured against the typical candle. ICT calls a
//     leg "impulsive" by appearance.
//   - The entry is the gap edge nearest the market, not its midpoint or far
//     edge. All three are taught; the near edge fills most often.
//   - Kill zones are UTC here. ICT defines them in New York local time, which
//     moves an hour twice a year against UTC - see the kill-zone section.
//
// ---------------------------------------------------------------------------
// Tunables, all fixed rather than exposed. An operator does not know better
// than the code what counts as a swing (AGENTS.md rule 48).
// ---------------------------------------------------------------------------

// Bars required either side of a swing point. Two is the smallest that rejects
// a single noisy bar while still finding the short-term highs an intraday stop
// pool actually sits above.
#define XSPARK_ICT_SWING_STRENGTH 2

// How far back the model looks for the swing being swept, and for the sweep
// itself once structure has shifted. Beyond this a "sweep" and the break that
// follows are no longer one event.
#define XSPARK_ICT_SWING_LOOKBACK 60
#define XSPARK_ICT_SWEEP_MAX_AGE_BARS 12

// The displacement leg's body, as a multiple of the typical candle. Below this
// the break of structure is drift, and drift does not leave the imbalance the
// entry depends on.
#define XSPARK_ICT_MIN_DISPLACEMENT_ATR 0.65

// The imbalance must be worth returning to. A gap thinner than this is inside
// the spread on most instruments and is not an entry, it is a rounding error.
#define XSPARK_ICT_MIN_FVG_ATR 0.10

// Stop placement beyond the swept extreme, as a multiple of the typical candle.
// The swept high is the model's invalidation: price going back through it says
// the pool was not taken, so the reason for the trade is gone.
#define XSPARK_ICT_STOP_BUFFER_ATR 0.20

// Stop bounds and the cost share, mirroring TrendScalp: the same instrument
// arithmetic applies to any strategy whose stop is measured in typical candles.
#define XSPARK_ICT_MIN_STOP_ATR 0.50
#define XSPARK_ICT_MAX_STOP_ATR 3.50
#define XSPARK_ICT_MAX_COST_SHARE_PCT 6.0

// Premium/discount: longs only in the lower half of the swept range, shorts
// only in the upper half.
//
// OFF, and this is a finding rather than a preference. A displacement strong
// enough to break structure leaves its imbalance BELOW the level it broke, by
// construction - so an entry at that imbalance is always in the discount half
// of the range the sweep defined, and a premium filter applied there refuses
// every sell the model can generate. ICT applies premium/discount to a higher
// timeframe dealing range, which is a different measurement than this file
// makes. The test suite pins this behaviour so it cannot be switched on by
// accident; the function stays available for a variant whose entry is a higher
// timeframe imbalance rather than the displacement's own.
#define XSPARK_ICT_USE_PREMIUM_DISCOUNT false

// ---------------------------------------------------------------------------
// Swing points.
// ---------------------------------------------------------------------------
//
// Series indexing throughout this file: index 0 is the forming bar, 1 is the
// last closed bar, and a LARGER index is OLDER. So index-1 is newer than index
// and index+1 is older, which is the reverse of the way the eye reads a chart
// left to right. Every loop below is written in that convention.

// A swing high needs `strength` bars either side that did not trade higher.
//
// Ties are allowed on the older side and refused on the newer side, so a flat
// top resolves to exactly one swing rather than to several - and specifically
// to the NEWEST bar of the flat run, which is the most recent time the market
// was offered there and so the level the resting stops actually sit above.
bool XSparkIctIsSwingHigh(const double &highs[], const int index, const int strength)
{
   const int size = ArraySize(highs);
   if(strength <= 0 || index < strength || index + strength >= size)
      return false;

   const double pivot = highs[index];
   if(!MathIsValidNumber(pivot))
      return false;

   for(int step = 1; step <= strength; step++)
   {
      const double newer = highs[index - step];
      const double older = highs[index + step];
      if(!MathIsValidNumber(newer) || !MathIsValidNumber(older))
         return false;
      if(newer >= pivot)
         return false;
      if(older > pivot)
         return false;
   }

   return true;
}

bool XSparkIctIsSwingLow(const double &lows[], const int index, const int strength)
{
   const int size = ArraySize(lows);
   if(strength <= 0 || index < strength || index + strength >= size)
      return false;

   const double pivot = lows[index];
   if(!MathIsValidNumber(pivot))
      return false;

   for(int step = 1; step <= strength; step++)
   {
      const double newer = lows[index - step];
      const double older = lows[index + step];
      if(!MathIsValidNumber(newer) || !MathIsValidNumber(older))
         return false;
      if(newer <= pivot)
         return false;
      if(older < pivot)
         return false;
   }

   return true;
}

// The newest swing high strictly older than `from_index`, searched back at most
// `lookback` bars. Returns its index, or -1. This is the level whose stop pool
// the model expects price to run.
int XSparkIctFindSwingHigh(const double &highs[], const int from_index, const int lookback, const int strength)
{
   const int size = ArraySize(highs);
   if(from_index < 0 || lookback <= 0)
      return -1;

   const int last = MathMin(from_index + lookback, size - strength - 1);
   for(int i = from_index + 1; i <= last; i++)
   {
      if(XSparkIctIsSwingHigh(highs, i, strength))
         return i;
   }

   return -1;
}

int XSparkIctFindSwingLow(const double &lows[], const int from_index, const int lookback, const int strength)
{
   const int size = ArraySize(lows);
   if(from_index < 0 || lookback <= 0)
      return -1;

   const int last = MathMin(from_index + lookback, size - strength - 1);
   for(int i = from_index + 1; i <= last; i++)
   {
      if(XSparkIctIsSwingLow(lows, i, strength))
         return i;
   }

   return -1;
}

// ---------------------------------------------------------------------------
// Liquidity sweep.
// ---------------------------------------------------------------------------
//
// The event: the bar trades through a prior swing extreme and closes back on
// the original side. Traded through, because that is what reaches the resting
// stops; closed back, because a bar that closes beyond the level has not failed
// there, it has broken out, and a breakout is the opposite trade.
//
// Requiring both on ONE bar is the strictest reading and the one chosen here.
// It is also the reading that cannot be fitted after the fact: a sweep that is
// allowed to resolve "within a few bars" is a sweep whose definition depends on
// what price did next.

bool XSparkIctSweptHigh(const double high, const double close, const double swing_high)
{
   if(!MathIsValidNumber(high) || !MathIsValidNumber(close) || !MathIsValidNumber(swing_high))
      return false;
   if(swing_high <= 0.0)
      return false;

   return high > swing_high && close < swing_high;
}

bool XSparkIctSweptLow(const double low, const double close, const double swing_low)
{
   if(!MathIsValidNumber(low) || !MathIsValidNumber(close) || !MathIsValidNumber(swing_low))
      return false;
   if(swing_low <= 0.0)
      return false;

   return low < swing_low && close > swing_low;
}

// ---------------------------------------------------------------------------
// Fair value gap (imbalance).
// ---------------------------------------------------------------------------
//
// Three consecutive bars whose outer two do not overlap. The middle bar moved
// far enough fast enough that no trade happened across part of its range, and
// the model's claim is that price tends to return there.
//
// With series indexing the three bars are newest = index, middle = index + 1,
// oldest = index + 2.
//
//   bullish: lows[index] > highs[index + 2]   gap [highs[index + 2], lows[index]]
//   bearish: highs[index] < lows[index + 2]   gap [highs[index], lows[index + 2]]
//
// `min_size` refuses a gap too thin to be an entry once the spread is paid.

bool XSparkIctBullishFvg(const double &highs[], const double &lows[], const int index,
                         const double min_size, double &gap_low, double &gap_high)
{
   gap_low = 0.0;
   gap_high = 0.0;

   const int size = ArraySize(highs);
   if(index < 0 || index + 2 >= size || ArraySize(lows) != size)
      return false;
   if(!MathIsValidNumber(min_size) || min_size < 0.0)
      return false;

   const double newest_low = lows[index];
   const double oldest_high = highs[index + 2];
   if(!MathIsValidNumber(newest_low) || !MathIsValidNumber(oldest_high))
      return false;

   if(newest_low - oldest_high < min_size || newest_low <= oldest_high)
      return false;

   gap_low = oldest_high;
   gap_high = newest_low;
   return true;
}

bool XSparkIctBearishFvg(const double &highs[], const double &lows[], const int index,
                         const double min_size, double &gap_low, double &gap_high)
{
   gap_low = 0.0;
   gap_high = 0.0;

   const int size = ArraySize(highs);
   if(index < 0 || index + 2 >= size || ArraySize(lows) != size)
      return false;
   if(!MathIsValidNumber(min_size) || min_size < 0.0)
      return false;

   const double newest_high = highs[index];
   const double oldest_low = lows[index + 2];
   if(!MathIsValidNumber(newest_high) || !MathIsValidNumber(oldest_low))
      return false;

   if(oldest_low - newest_high < min_size || oldest_low <= newest_high)
      return false;

   gap_low = newest_high;
   gap_high = oldest_low;
   return true;
}

// ---------------------------------------------------------------------------
// Displacement.
// ---------------------------------------------------------------------------
//
// Measured on the BODY, not the range. A long wick is indecision that happened
// to travel; a body is where the market actually settled, and it is the body
// that leaves the imbalance behind.

bool XSparkIctIsDisplacement(const double open, const double close, const double atr,
                             const double min_atr_mult, const EXSparkSignalDirection direction)
{
   if(!MathIsValidNumber(open) || !MathIsValidNumber(close) ||
      !MathIsValidNumber(atr) || atr <= 0.0 ||
      !MathIsValidNumber(min_atr_mult) || min_atr_mult <= 0.0)
      return false;

   const double body = close - open;

   if(direction == XSPARK_SIGNAL_BUY)
      return body > 0.0 && body >= min_atr_mult * atr;

   if(direction == XSPARK_SIGNAL_SELL)
      return -body >= min_atr_mult * atr;

   return false;
}

// ---------------------------------------------------------------------------
// Premium and discount.
// ---------------------------------------------------------------------------
//
// Position within the range the sweep defined, 0 at the low and 1 at the high.
// Selling is only permitted in the upper half and buying in the lower half:
// the model is a reversion to the other side of the range, so entering on the
// wrong half of it is paying the move that was supposed to be the profit.

bool XSparkIctRangePosition(const double price, const double range_low, const double range_high, double &position)
{
   position = 0.0;

   if(!MathIsValidNumber(price) || !MathIsValidNumber(range_low) || !MathIsValidNumber(range_high))
      return false;
   if(range_high <= range_low)
      return false;

   position = (price - range_low) / (range_high - range_low);
   return true;
}

// ---------------------------------------------------------------------------
// Kill zones.
// ---------------------------------------------------------------------------
//
// ICT names these in New York local time. New York observes daylight saving and
// UTC does not, so a window fixed in UTC is the ICT window for part of the year
// and an hour off for the rest. The choice here is UTC, because the alternative
// is a DST table that is wrong the year a government moves a date - and because
// the boundary of a three-hour window is not where the model's claim lives.
//
// An operator who wants the windows to track New York exactly uses the broker
// clock offset input to shift them by an hour when the US changes over.
//
//   London  07:00-10:00 UTC  (02:00-05:00 New York, winter)
//   New York 12:00-15:00 UTC (07:00-10:00 New York, winter)
//
// Both windows are where the day's volume and the day's stop pools actually
// are. Outside them the model is switched off rather than merely unlikely.

enum EXSparkIctKillZones
{
   XSPARK_ICT_KZ_LONDON_NY = 0, // London and New York kill zones
   XSPARK_ICT_KZ_LONDON    = 1, // London kill zone only
   XSPARK_ICT_KZ_NEW_YORK  = 2  // New York kill zone only
};

#define XSPARK_ICT_LONDON_START_MIN 420   // 07:00 UTC
#define XSPARK_ICT_LONDON_END_MIN   600   // 10:00 UTC
#define XSPARK_ICT_NEWYORK_START_MIN 720  // 12:00 UTC
#define XSPARK_ICT_NEWYORK_END_MIN   900  // 15:00 UTC

// Whether `minutes_utc` (minutes since midnight UTC) falls inside the selected
// kill zones. The end minute is exclusive so the two windows never both own a
// boundary minute.
bool XSparkIctInKillZone(const int minutes_utc, const EXSparkIctKillZones zones)
{
   if(minutes_utc < 0 || minutes_utc >= 1440)
      return false;

   const bool london = minutes_utc >= XSPARK_ICT_LONDON_START_MIN && minutes_utc < XSPARK_ICT_LONDON_END_MIN;
   const bool newyork = minutes_utc >= XSPARK_ICT_NEWYORK_START_MIN && minutes_utc < XSPARK_ICT_NEWYORK_END_MIN;

   if(zones == XSPARK_ICT_KZ_LONDON)
      return london;
   if(zones == XSPARK_ICT_KZ_NEW_YORK)
      return newyork;

   return london || newyork;
}

string XSparkIctKillZoneName(const EXSparkIctKillZones zones)
{
   if(zones == XSPARK_ICT_KZ_LONDON)
      return "London 07:00-10:00 UTC";
   if(zones == XSPARK_ICT_KZ_NEW_YORK)
      return "New York 12:00-15:00 UTC";
   return "London 07:00-10:00 and New York 12:00-15:00 UTC";
}

// ---------------------------------------------------------------------------
// The assembled model.
// ---------------------------------------------------------------------------

struct XSparkIctConfig
{
   int    swing_strength;
   int    swing_lookback;
   int    sweep_max_age_bars;
   double min_displacement_atr;
   double min_fvg_atr;
   double stop_buffer_atr;
   double min_stop_atr;
   double max_stop_atr;
   double max_cost_share_pct;
   bool   use_premium_discount;
   double target_r;
   EXSparkIctKillZones kill_zones;
};

void XSparkDefaultIctConfig(XSparkIctConfig &config)
{
   config.swing_strength = XSPARK_ICT_SWING_STRENGTH;
   config.swing_lookback = XSPARK_ICT_SWING_LOOKBACK;
   config.sweep_max_age_bars = XSPARK_ICT_SWEEP_MAX_AGE_BARS;
   config.min_displacement_atr = XSPARK_ICT_MIN_DISPLACEMENT_ATR;
   config.min_fvg_atr = XSPARK_ICT_MIN_FVG_ATR;
   config.stop_buffer_atr = XSPARK_ICT_STOP_BUFFER_ATR;
   config.min_stop_atr = XSPARK_ICT_MIN_STOP_ATR;
   config.max_stop_atr = XSPARK_ICT_MAX_STOP_ATR;
   config.max_cost_share_pct = XSPARK_ICT_MAX_COST_SHARE_PCT;
   config.use_premium_discount = XSPARK_ICT_USE_PREMIUM_DISCOUNT;
   config.target_r = 2.0;
   config.kill_zones = XSPARK_ICT_KZ_LONDON_NY;
}

bool XSparkIctConfigUsable(const XSparkIctConfig &config, string &reason)
{
   reason = "";

   if(config.swing_strength <= 0)
   {
      reason = "A swing needs at least one bar either side.";
      return false;
   }

   if(config.swing_lookback <= config.swing_strength)
   {
      reason = "The swing lookback must be longer than the swing itself.";
      return false;
   }

   if(config.sweep_max_age_bars <= 0)
   {
      reason = "The sweep must be allowed to be at least one bar old.";
      return false;
   }

   if(!MathIsValidNumber(config.min_displacement_atr) || config.min_displacement_atr <= 0.0)
   {
      reason = "The displacement threshold is not a usable multiple.";
      return false;
   }

   if(!MathIsValidNumber(config.min_fvg_atr) || config.min_fvg_atr < 0.0)
   {
      reason = "The imbalance floor is not a usable multiple.";
      return false;
   }

   if(!MathIsValidNumber(config.stop_buffer_atr) || config.stop_buffer_atr < 0.0)
   {
      reason = "The stop buffer is not a usable multiple.";
      return false;
   }

   if(!MathIsValidNumber(config.min_stop_atr) || config.min_stop_atr <= 0.0 ||
      !MathIsValidNumber(config.max_stop_atr) || config.max_stop_atr <= config.min_stop_atr)
   {
      reason = "The stop bounds are not a usable range.";
      return false;
   }

   if(!MathIsValidNumber(config.max_cost_share_pct) || config.max_cost_share_pct <= 0.0 ||
      config.max_cost_share_pct >= 100.0)
   {
      reason = "The cost share is not a usable percentage.";
      return false;
   }

   if(!MathIsValidNumber(config.target_r) || config.target_r <= 0.0)
   {
      reason = "The target must be a positive multiple of the stop.";
      return false;
   }

   return true;
}

// Every place the sequence can stop, in the order it is checked. The EA prints
// these as a daily funnel, so a run that takes no trades says which of the four
// ICT conditions the market never produced rather than going silent.
struct XSparkIctVerdicts
{
   string zone;       // "IN ZONE", "OUTSIDE ZONE"
   string sweep;      // "SWEPT HIGH", "SWEPT LOW", "NO SWEEP"
   string structure;  // "SHIFTED", "NOT SHIFTED"
   string imbalance;  // "FVG", "NO FVG", "FVG TOO THIN"
   string location;   // "DISCOUNT", "PREMIUM", "WRONG HALF", "OFF"
};

void XSparkResetIctVerdicts(XSparkIctVerdicts &verdicts)
{
   verdicts.zone = "";
   verdicts.sweep = "";
   verdicts.structure = "";
   verdicts.imbalance = "";
   verdicts.location = "";
}

// The result of one bar's evaluation, before risk and cost have a say.
struct XSparkIctSetup
{
   EXSparkSignalDirection direction;
   double swept_level;     // the extreme the sweep ran; the model's invalidation
   double entry_limit;     // the near edge of the imbalance
   double gap_low;
   double gap_high;
   double stop;
   double target;
   int    sweep_index;
   int    shift_index;
   string reason;
};

void XSparkResetIctSetup(XSparkIctSetup &setup)
{
   setup.direction = XSPARK_SIGNAL_NONE;
   setup.swept_level = 0.0;
   setup.entry_limit = 0.0;
   setup.gap_low = 0.0;
   setup.gap_high = 0.0;
   setup.stop = 0.0;
   setup.target = 0.0;
   setup.sweep_index = -1;
   setup.shift_index = -1;
   setup.reason = "";
}

// The swept swing high behind a displacement bar: searched from the bar just
// older than `displacement_index` back at most `sweep_max_age_bars`.
//
// Returns the sweep's index, or -1. Split out from the full evaluation so the
// mirrored bullish case cannot drift from it.
int XSparkIctFindBearishSweep(const double &highs[], const double &closes[],
                              const int displacement_index, const XSparkIctConfig &config, double &swept_level)
{
   swept_level = 0.0;

   const int size = ArraySize(highs);
   if(displacement_index < 0 || displacement_index >= size)
      return -1;

   // Walk back from the bar before the displacement. The sweep must be strictly
   // older: one bar cannot both take the stops and break structure the other way.
   for(int age = 1; age <= config.sweep_max_age_bars; age++)
   {
      const int candidate = displacement_index + age;
      if(candidate >= size)
         break;

      const int swing = XSparkIctFindSwingHigh(highs, candidate, config.swing_lookback, config.swing_strength);
      if(swing < 0)
         continue;

      if(XSparkIctSweptHigh(highs[candidate], closes[candidate], highs[swing]))
      {
         swept_level = highs[candidate];
         return candidate;
      }
   }

   return -1;
}

int XSparkIctFindBullishSweep(const double &lows[], const double &closes[],
                              const int displacement_index, const XSparkIctConfig &config, double &swept_level)
{
   swept_level = 0.0;

   const int size = ArraySize(lows);
   if(displacement_index < 0 || displacement_index >= size)
      return -1;

   for(int age = 1; age <= config.sweep_max_age_bars; age++)
   {
      const int candidate = displacement_index + age;
      if(candidate >= size)
         break;

      const int swing = XSparkIctFindSwingLow(lows, candidate, config.swing_lookback, config.swing_strength);
      if(swing < 0)
         continue;

      if(XSparkIctSweptLow(lows[candidate], closes[candidate], lows[swing]))
      {
         swept_level = lows[candidate];
         return candidate;
      }
   }

   return -1;
}

// The whole model, evaluated on the close of `eval_index`.
//
// THE BAR ROLES, because getting these one apart is the easiest way to build a
// model that looks right and tests nothing:
//
//   eval_index      the bar that just closed. Newest bar of the imbalance, and
//                   the bar that CONFIRMS it - a three-bar gap does not exist
//                   until its third bar has closed.
//   eval_index + 1  the DISPLACEMENT. The impulsive body that broke structure
//                   and left the gap. It is the MIDDLE bar of the imbalance.
//   eval_index + 2  the oldest bar of the imbalance.
//   older still     the sweep, then the swing it ran.
//
// So the displacement is never the bar being evaluated. Checking displacement
// and imbalance on the same index would ask the gap to exist one bar before it
// can, and the sequence would never complete.
//
// Returns true only when all four conditions held and the geometry is usable.
// `verdicts` is filled either way, so a refusal is as informative as a signal.
bool XSparkIctEvaluate(const double &opens[], const double &highs[], const double &lows[], const double &closes[],
                       const int eval_index, const int minutes_utc, const double atr,
                       const XSparkIctConfig &config, XSparkIctSetup &setup, XSparkIctVerdicts &verdicts)
{
   XSparkResetIctSetup(setup);
   XSparkResetIctVerdicts(verdicts);

   string config_reason = "";
   if(!XSparkIctConfigUsable(config, config_reason))
   {
      setup.reason = config_reason;
      return false;
   }

   const int size = ArraySize(highs);
   if(size != ArraySize(lows) || size != ArraySize(opens) || size != ArraySize(closes))
   {
      setup.reason = "The bar arrays are not the same length.";
      return false;
   }

   if(eval_index < 0 || eval_index + 2 >= size)
   {
      setup.reason = "Not enough history to read the sequence.";
      return false;
   }

   if(!MathIsValidNumber(atr) || atr <= 0.0)
   {
      setup.reason = "The typical candle size is unavailable.";
      return false;
   }

   const int displacement_index = eval_index + 1;

   // 1. Kill zone. Checked first because it is the cheapest and because a
   //    sequence outside the window is not a setup the model missed, it is one
   //    the model declines.
   if(!XSparkIctInKillZone(minutes_utc, config.kill_zones))
   {
      verdicts.zone = "OUTSIDE ZONE";
      setup.reason = StringFormat("%02d:%02d UTC is outside the %s kill zone.",
                                  minutes_utc / 60, minutes_utc % 60,
                                  XSparkIctKillZoneName(config.kill_zones));
      return false;
   }
   verdicts.zone = "IN ZONE";

   // 2. The displacement, and 3. the sweep it must have reversed. The two are
   //    found together because a sweep is only meaningful as the thing the
   //    displacement broke away from.
   const bool bearish_body = XSparkIctIsDisplacement(opens[displacement_index], closes[displacement_index],
                                                     atr, config.min_displacement_atr, XSPARK_SIGNAL_SELL);
   const bool bullish_body = XSparkIctIsDisplacement(opens[displacement_index], closes[displacement_index],
                                                     atr, config.min_displacement_atr, XSPARK_SIGNAL_BUY);

   double swept_level = 0.0;
   EXSparkSignalDirection direction = XSPARK_SIGNAL_NONE;
   int sweep_index = -1;

   if(bearish_body)
   {
      sweep_index = XSparkIctFindBearishSweep(highs, closes, displacement_index, config, swept_level);
      if(sweep_index >= 0)
         direction = XSPARK_SIGNAL_SELL;
   }

   if(direction == XSPARK_SIGNAL_NONE && bullish_body)
   {
      sweep_index = XSparkIctFindBullishSweep(lows, closes, displacement_index, config, swept_level);
      if(sweep_index >= 0)
         direction = XSPARK_SIGNAL_BUY;
   }

   if(direction == XSPARK_SIGNAL_NONE)
   {
      verdicts.sweep = "NO SWEEP";
      setup.reason = bearish_body || bullish_body
                     ? "A displacement closed but no stop pool was run in the bars before it."
                     : "No displacement: the bar's body is under the impulse floor, so nothing broke structure.";
      return false;
   }

   verdicts.sweep = direction == XSPARK_SIGNAL_SELL ? "SWEPT HIGH" : "SWEPT LOW";

   // 4. The break of structure itself: the displacement must close through the
   //    opposing swing that formed between the sweep and it. Without this the
   //    bar is a large candle inside the range, not a shift.
   const int opposing = direction == XSPARK_SIGNAL_SELL
                        ? XSparkIctFindSwingLow(lows, displacement_index, config.swing_lookback, config.swing_strength)
                        : XSparkIctFindSwingHigh(highs, displacement_index, config.swing_lookback, config.swing_strength);

   if(opposing < 0)
   {
      verdicts.structure = "NOT SHIFTED";
      setup.reason = "No opposing swing exists for the displacement to break.";
      return false;
   }

   const bool shifted = direction == XSPARK_SIGNAL_SELL ? closes[displacement_index] < lows[opposing]
                                                        : closes[displacement_index] > highs[opposing];
   if(!shifted)
   {
      verdicts.structure = "NOT SHIFTED";
      setup.reason = StringFormat("The displacement did not close through the opposing swing at %.5f.",
                                  direction == XSPARK_SIGNAL_SELL ? lows[opposing] : highs[opposing]);
      return false;
   }
   verdicts.structure = "SHIFTED";

   // 5. The imbalance the displacement left, newest bar at eval_index.
   double gap_low = 0.0;
   double gap_high = 0.0;
   const double min_gap = config.min_fvg_atr * atr;
   const bool has_gap = direction == XSPARK_SIGNAL_SELL
                        ? XSparkIctBearishFvg(highs, lows, eval_index, min_gap, gap_low, gap_high)
                        : XSparkIctBullishFvg(highs, lows, eval_index, min_gap, gap_low, gap_high);

   if(!has_gap)
   {
      verdicts.imbalance = "NO FVG";
      setup.reason = "The displacement left no imbalance wide enough to return to.";
      return false;
   }
   verdicts.imbalance = "FVG";

   // Geometry. The entry is the gap edge the market reaches FIRST on its way
   // back: for a sell price retraces upward, so that is the gap's low edge.
   const double entry = direction == XSPARK_SIGNAL_SELL ? gap_low : gap_high;

   // Premium/discount, measured across the range the sweep and the break
   // defined. Off by default - see the constant for why this refuses every
   // setup when the entry is the displacement's own imbalance.
   if(config.use_premium_discount)
   {
      const double range_high = direction == XSPARK_SIGNAL_SELL ? swept_level : highs[opposing];
      const double range_low = direction == XSPARK_SIGNAL_SELL ? lows[opposing] : swept_level;

      double position = 0.0;
      if(!XSparkIctRangePosition(entry, range_low, range_high, position))
      {
         verdicts.location = "WRONG HALF";
         setup.reason = "The swept range is not usable, so premium and discount cannot be read.";
         return false;
      }

      const bool correct_half = direction == XSPARK_SIGNAL_SELL ? position >= 0.5 : position <= 0.5;
      if(!correct_half)
      {
         verdicts.location = "WRONG HALF";
         setup.reason = StringFormat("The entry sits at %.0f%% of the swept range, the wrong half for a %s.",
                                     position * 100.0,
                                     direction == XSPARK_SIGNAL_SELL ? "sell" : "buy");
         return false;
      }
      verdicts.location = direction == XSPARK_SIGNAL_SELL ? "PREMIUM" : "DISCOUNT";
   }
   else
   {
      verdicts.location = "OFF";
   }

   const double buffer = config.stop_buffer_atr * atr;
   const double stop = direction == XSPARK_SIGNAL_SELL ? swept_level + buffer : swept_level - buffer;
   const double stop_distance = direction == XSPARK_SIGNAL_SELL ? stop - entry : entry - stop;

   if(stop_distance <= 0.0)
   {
      setup.reason = "The stop is on the wrong side of the entry; the sequence is not usable.";
      return false;
   }

   if(stop_distance < config.min_stop_atr * atr)
   {
      setup.reason = StringFormat("The stop is %.2f typical candles from the entry, under the %.2f floor.",
                                  stop_distance / atr, config.min_stop_atr);
      return false;
   }

   if(stop_distance > config.max_stop_atr * atr)
   {
      setup.reason = StringFormat("The stop is %.2f typical candles from the entry, over the %.2f ceiling.",
                                  stop_distance / atr, config.max_stop_atr);
      return false;
   }

   setup.direction = direction;
   setup.swept_level = swept_level;
   setup.gap_low = gap_low;
   setup.gap_high = gap_high;
   setup.entry_limit = entry;
   setup.sweep_index = sweep_index;
   setup.shift_index = displacement_index;
   setup.stop = stop;
   setup.target = direction == XSPARK_SIGNAL_SELL ? entry - config.target_r * stop_distance
                                                  : entry + config.target_r * stop_distance;

   setup.reason = StringFormat("%s: %s at %.5f, structure shifted, entry at the imbalance %.5f-%.5f.",
                               direction == XSPARK_SIGNAL_SELL ? "SELL" : "BUY",
                               direction == XSPARK_SIGNAL_SELL ? "high swept" : "low swept",
                               swept_level, gap_low, gap_high);
   return true;
}

// The win rate a trade with NO edge shows at this target, before costs. Same
// arithmetic TrendScalp uses, repeated here so the ICT EA does not depend on
// another strategy's constant (AGENTS.md rule 43).
double XSparkIctNoEdgeWinRate(const double target_r)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0)
      return 0.0;
   return 1.0 / (1.0 + target_r);
}

#endif
