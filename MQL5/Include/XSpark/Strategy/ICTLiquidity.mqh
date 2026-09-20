#ifndef XSPARK_STRATEGY_ICT_LIQUIDITY_MQH
#define XSPARK_STRATEGY_ICT_LIQUIDITY_MQH

#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
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
// WHERE THIS DEPARTS FROM THE SOURCE, stated because the first version of this
// file hid four departures behind the phrase "ICT leaves these open". It does
// not leave these open; the first version simply chose differently.
//
// Corrected since:
//   - NO INDICATOR ANYWHERE IN THE ENTRY RULE. The method rejects them, and an
//     earlier draft gated displacement on an ATR multiple, which is foreign to
//     it. The evidence of displacement IS the imbalance the leg leaves: if no
//     gap was left, the leg did not displace. Nothing else is measured.
//   - A swing is a THREE-CANDLE formation - one lower high either side of a
//     high. An earlier draft required two bars either side, which is an
//     indicator-package convention, not this method's definition.
//   - The entry is CONSEQUENT ENCROACHMENT, the gap's 50% midpoint, which is
//     the method's own term and its own entry reference.
//   - The target is a DRAW ON LIQUIDITY - the opposing pool of stops the market
//     is being pulled toward - not a fixed multiple of the stop. The reward
//     ratio is therefore an OUTPUT of where liquidity sits, never an input.
//     An earlier draft used a fixed 2R, which changes the whole payoff.
//
// Still departing, deliberately and visibly:
//   - The sweep must close back through the level on the SAME bar that pierced
//     it. The method allows the raid to resolve over several bars; requiring
//     one bar is the only reading that cannot be fitted after the fact, since
//     "resolves within a few bars" is defined by what price did next.
//   - Kill zones are held in UTC. The method names them in New York local time,
//     which moves an hour against UTC twice a year - see the kill-zone section.
//   - A minimum gap width is required, sized by the round-trip cost rather than
//     by any indicator. A gap narrower than the spread is not an entry.
//
// The ATR that remains in this file is used ONLY by the EA's risk layer to
// bound a stop it would otherwise send at any width. It takes no part in
// deciding whether a setup exists.

// ---------------------------------------------------------------------------
// Tunables, all fixed rather than exposed. An operator does not know better
// than the code what counts as a swing (AGENTS.md rule 48).
// ---------------------------------------------------------------------------

// Bars either side of a swing point. ONE, because a short-term swing high in
// this method is a candle with a lower high on each side - three candles, no
// more. Raising it finds fewer, larger swings and is a different method.
#define XSPARK_ICT_SWING_STRENGTH 1

// How far back the model looks for the swing being swept, and how old the
// sweep may be when structure finally shifts. Beyond this the raid and the
// break are no longer one event.
//
// The lookback is bounded by the shared indicator cache, which holds
// XSPARK_SCOREBOT_CLOSED_BASE_BARS closed bars. The deepest read is sweep age
// + lookback + strength, so these must leave room inside that window or the
// oldest swing silently cannot be found - which reads as "no sweep" rather
// than as a missing bar.
#define XSPARK_ICT_SWING_LOOKBACK 30
#define XSPARK_ICT_SWEEP_MAX_AGE_BARS 12

// Stop placement beyond the swept extreme, in instrument points. The raided
// high is the invalidation: price back through it says the pool was not taken,
// so the reason for the trade is gone. The buffer only clears the spread and
// the broker's stop level, and is deliberately not an ATR multiple.
#define XSPARK_ICT_STOP_BUFFER_POINTS 20.0

// The reward the draw on liquidity must offer before the trade is worth
// taking. Not a target - the target is wherever liquidity sits - but a floor
// below which that target is too close to pay for the stop.
#define XSPARK_ICT_MIN_TARGET_R 1.5
#define XSPARK_ICT_MAX_TARGET_R 20.0

// The EA's risk bounds on the stop it will send, and the share of that stop
// the round-trip cost may be. These belong to the risk layer, not to the
// entry rule: they never decide whether a setup exists, only whether one the
// model found can be traded at an acceptable cost.
#define XSPARK_ICT_MIN_STOP_ATR 0.50
#define XSPARK_ICT_MAX_STOP_ATR 3.50
#define XSPARK_ICT_MAX_COST_SHARE_PCT 6.0

// Premium and discount: sell only from the upper half of the dealing range,
// buy only from the lower half.
//
// ON, which reverses an earlier draft. That draft measured the range wrongly
// and then concluded from its own error that the concept did not apply. The
// dealing range runs from the swept extreme to the far end of the leg the
// displacement made, and the entry is sought among ALL the imbalances that
// leg left - not only the newest three bars, which sit at the end of the leg
// and so are always in discount. Read that way the filter is exactly what the
// method says it is, and the funnel reports what it costs.
#define XSPARK_ICT_USE_PREMIUM_DISCOUNT true

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
// NOT MEASURED AGAINST ANYTHING. A leg displaced if it left an imbalance; if
// every price in its range traded, it did not. That is the whole test, and it
// is why no indicator appears in it.
//
// All that is read from the bar itself is which way its body points, so the
// model knows whether to look for a raided high or a raided low. A bar that
// closed where it opened points nowhere and is not a displacement.

EXSparkSignalDirection XSparkIctBodyDirection(const double open, const double close)
{
   if(!MathIsValidNumber(open) || !MathIsValidNumber(close))
      return XSPARK_SIGNAL_NONE;

   if(close < open)
      return XSPARK_SIGNAL_SELL;
   if(close > open)
      return XSPARK_SIGNAL_BUY;

   return XSPARK_SIGNAL_NONE;
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
// Consequent encroachment.
// ---------------------------------------------------------------------------
//
// The imbalance's 50% midpoint, and this method's own entry reference. Not the
// near edge, which fills more often but is a worse price, and not the far edge,
// which is a better price that frequently never trades.

bool XSparkIctConsequentEncroachment(const double gap_low, const double gap_high, double &ce)
{
   ce = 0.0;

   if(!MathIsValidNumber(gap_low) || !MathIsValidNumber(gap_high) || gap_high <= gap_low)
      return false;

   ce = gap_low + (gap_high - gap_low) / 2.0;
   return true;
}

// ---------------------------------------------------------------------------
// The imbalance to enter at.
// ---------------------------------------------------------------------------
//
// Scans the WHOLE leg the displacement made, oldest bar to newest, rather than
// only the three most recent bars. This is the correction that matters most: a
// leg strong enough to break structure usually leaves several imbalances, and
// the newest of them sits at the end of the leg - which is the bottom of a
// down-leg, and therefore always in discount. Looking only there makes a
// premium filter refuse every sell the model can produce, which is what an
// earlier draft of this file concluded and wrongly blamed on the method.
//
// Among the candidates the one whose consequent encroachment sits DEEPEST into
// premium wins for a sell, and deepest into discount for a buy: that is the
// best price the leg is offering, and the one the method reaches for.
//
// `newest` and `oldest` bound the search, `min_gap` refuses a gap too narrow to
// pay the spread, and the dealing range decides which half counts.
bool XSparkIctSelectEntryGap(const double &highs[], const double &lows[],
                             const int newest, const int oldest,
                             const EXSparkSignalDirection direction,
                             const double min_gap,
                             const double range_low, const double range_high,
                             const bool use_premium_discount,
                             double &gap_low, double &gap_high, int &gap_index,
                             bool &saw_any_gap)
{
   gap_low = 0.0;
   gap_high = 0.0;
   gap_index = -1;
   saw_any_gap = false;

   const int size = ArraySize(highs);
   if(newest < 0 || oldest < newest || ArraySize(lows) != size)
      return false;
   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   double best_position = 0.0;
   bool found = false;

   for(int i = newest; i <= oldest; i++)
   {
      if(i + 2 >= size)
         break;

      double low = 0.0;
      double high = 0.0;
      const bool has_gap = direction == XSPARK_SIGNAL_SELL
                           ? XSparkIctBearishFvg(highs, lows, i, min_gap, low, high)
                           : XSparkIctBullishFvg(highs, lows, i, min_gap, low, high);
      if(!has_gap)
         continue;

      saw_any_gap = true;

      double ce = 0.0;
      if(!XSparkIctConsequentEncroachment(low, high, ce))
         continue;

      double position = 0.0;
      if(!XSparkIctRangePosition(ce, range_low, range_high, position))
         continue;

      if(use_premium_discount)
      {
         const bool correct_half = direction == XSPARK_SIGNAL_SELL ? position >= 0.5 : position <= 0.5;
         if(!correct_half)
            continue;
      }

      // Deepest into the correct half wins: highest for a sell, lowest for a buy.
      const double score = direction == XSPARK_SIGNAL_SELL ? position : 1.0 - position;
      if(!found || score > best_position)
      {
         found = true;
         best_position = score;
         gap_low = low;
         gap_high = high;
         gap_index = i;
      }
   }

   return found;
}

// ---------------------------------------------------------------------------
// The draw on liquidity.
// ---------------------------------------------------------------------------
//
// Where the trade is going: the opposing pool of stops the market is being
// pulled toward. For a sell that is the nearest swing LOW below the entry -
// resting sell stops that the move can reach and take.
//
// This is a price, not a ratio. The reward ratio a trade carries is whatever
// this level implies once the stop is known, which is why nothing in this file
// lets an operator choose a target: the market decides where the liquidity is.
bool XSparkIctDrawOnLiquidity(const double &highs[], const double &lows[],
                              const int from_index, const double entry,
                              const EXSparkSignalDirection direction,
                              const int lookback, const int strength,
                              double &target)
{
   target = 0.0;

   const int size = ArraySize(highs);
   if(from_index < 0 || lookback <= 0 || strength <= 0 || ArraySize(lows) != size)
      return false;
   if(!MathIsValidNumber(entry) || entry <= 0.0)
      return false;

   const int last = MathMin(from_index + lookback, size - strength - 1);

   for(int i = from_index + 1; i <= last; i++)
   {
      if(direction == XSPARK_SIGNAL_SELL)
      {
         if(!XSparkIctIsSwingLow(lows, i, strength))
            continue;
         // Only a pool the trade can actually travel to counts.
         if(lows[i] >= entry)
            continue;
         target = lows[i];
         return true;
      }
      else if(direction == XSPARK_SIGNAL_BUY)
      {
         if(!XSparkIctIsSwingHigh(highs, i, strength))
            continue;
         if(highs[i] <= entry)
            continue;
         target = highs[i];
         return true;
      }
   }

   return false;
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

// Minutes since midnight UTC for a broker timestamp, given the broker's offset
// from UTC in hours. Wraps, so an offset either side of midnight is still a
// clock reading rather than a negative number.
int XSparkIctMinutesUtc(const datetime broker_time, const int utc_offset_hours)
{
   const long seconds_per_day = 86400;
   long utc = (long)broker_time - (long)utc_offset_hours * 3600;
   long within_day = utc % seconds_per_day;
   if(within_day < 0)
      within_day += seconds_per_day;
   return (int)(within_day / 60);
}

// ---------------------------------------------------------------------------
// The assembled model.
// ---------------------------------------------------------------------------

struct XSparkIctConfig
{
   int    swing_strength;
   int    swing_lookback;
   int    sweep_max_age_bars;
   // The narrowest imbalance worth entering, as a price distance. Supplied by
   // the EA from the round-trip cost, because only the EA knows the spread.
   // Never an indicator multiple.
   double min_gap_price;
   double stop_buffer_points;
   double min_stop_atr;
   double max_stop_atr;
   double max_cost_share_pct;
   bool   use_premium_discount;
   // Bounds on the reward the draw on liquidity must offer. NOT a target:
   // the target is wherever the liquidity is. These only refuse a pool too
   // close to pay for the stop, or so far the trade is a different one.
   double min_target_r;
   double max_target_r;
   EXSparkIctKillZones kill_zones;
};

void XSparkDefaultIctConfig(XSparkIctConfig &config)
{
   config.swing_strength = XSPARK_ICT_SWING_STRENGTH;
   config.swing_lookback = XSPARK_ICT_SWING_LOOKBACK;
   config.sweep_max_age_bars = XSPARK_ICT_SWEEP_MAX_AGE_BARS;
   config.min_gap_price = 0.0;
   config.stop_buffer_points = XSPARK_ICT_STOP_BUFFER_POINTS;
   config.min_stop_atr = XSPARK_ICT_MIN_STOP_ATR;
   config.max_stop_atr = XSPARK_ICT_MAX_STOP_ATR;
   config.max_cost_share_pct = XSPARK_ICT_MAX_COST_SHARE_PCT;
   config.use_premium_discount = XSPARK_ICT_USE_PREMIUM_DISCOUNT;
   config.min_target_r = XSPARK_ICT_MIN_TARGET_R;
   config.max_target_r = XSPARK_ICT_MAX_TARGET_R;
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

   if(!MathIsValidNumber(config.min_gap_price) || config.min_gap_price < 0.0)
   {
      reason = "The narrowest tradeable imbalance is not a usable distance.";
      return false;
   }

   if(!MathIsValidNumber(config.stop_buffer_points) || config.stop_buffer_points < 0.0)
   {
      reason = "The stop buffer is not a usable number of points.";
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

   if(!MathIsValidNumber(config.min_target_r) || config.min_target_r <= 0.0 ||
      !MathIsValidNumber(config.max_target_r) || config.max_target_r <= config.min_target_r)
   {
      reason = "The reward bounds on the draw on liquidity are not a usable range.";
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
   string imbalance;  // "FVG", "NO FVG"
   string location;   // "DISCOUNT", "PREMIUM", "WRONG HALF", "OFF"
   string liquidity;  // "DRAW FOUND", "NO DRAW", "DRAW TOO CLOSE", "DRAW TOO FAR"
};

void XSparkResetIctVerdicts(XSparkIctVerdicts &verdicts)
{
   verdicts.zone = "";
   verdicts.sweep = "";
   verdicts.structure = "";
   verdicts.imbalance = "";
   verdicts.location = "";
   verdicts.liquidity = "";
}

// The result of one bar's evaluation, before risk and cost have a say.
struct XSparkIctSetup
{
   EXSparkSignalDirection direction;
   double swept_level;     // the extreme the raid ran; the model's invalidation
   double entry_limit;     // the imbalance's consequent encroachment
   double gap_low;
   double gap_high;
   double stop;
   double target;          // the draw on liquidity, as a price
   double target_r;        // what that draw implies against the stop; an output
   double range_position;  // where the entry sits in the dealing range, 0 to 1
   int    sweep_index;
   int    shift_index;
   int    gap_index;       // which bar of the leg carried the chosen imbalance
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
   setup.target_r = 0.0;
   setup.range_position = 0.0;
   setup.sweep_index = -1;
   setup.shift_index = -1;
   setup.gap_index = -1;
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
//   eval_index      the bar that just closed. Newest bar of the newest possible
//                   imbalance, and the bar that CONFIRMS it - a three-bar gap
//                   does not exist until its third bar has closed.
//   eval_index + 1  the DISPLACEMENT. The bar that broke structure. It is the
//                   MIDDLE bar of any imbalance it left.
//   older still     the rest of the leg, the sweep, then the swing it raided.
//
// THE SEQUENCE:
//   1. inside a kill zone
//   2. a swing high was raided and the raid failed on the same bar
//   3. a bar closed back through the opposing swing - structure shifted
//   4. that leg left an imbalance, sought across the WHOLE leg rather than
//      only its last three bars
//   5. the entry is that imbalance's consequent encroachment, in premium
//   6. the stop is beyond the raided extreme
//   7. the target is the draw on liquidity - the opposing pool of stops
//
// NO INDICATOR TAKES PART IN ANY OF THE SEVEN, and this function does not
// receive one. It takes the bars, the clock and the instrument's point size,
// and nothing else. An earlier draft accepted an ATR and used it to judge
// displacement; that the parameter can now be deleted outright is the clearest
// evidence the dependency is gone.
bool XSparkIctEvaluate(const double &opens[], const double &highs[], const double &lows[], const double &closes[],
                       const int eval_index, const int minutes_utc, const double point_size,
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

   if(!MathIsValidNumber(point_size) || point_size <= 0.0)
   {
      setup.reason = "The instrument's point size is unavailable.";
      return false;
   }

   const int displacement_index = eval_index + 1;

   // 1. Kill zone, checked first because it is the cheapest and because a
   //    sequence outside the window is not one the model missed.
   if(!XSparkIctInKillZone(minutes_utc, config.kill_zones))
   {
      verdicts.zone = "OUTSIDE ZONE";
      setup.reason = StringFormat("%02d:%02d UTC is outside the %s kill zone.",
                                  minutes_utc / 60, minutes_utc % 60,
                                  XSparkIctKillZoneName(config.kill_zones));
      return false;
   }
   verdicts.zone = "IN ZONE";

   // 2. The raid. Which side to look for comes from the displacement bar's
   //    body - the only thing read from it, and not a magnitude.
   const EXSparkSignalDirection body = XSparkIctBodyDirection(opens[displacement_index], closes[displacement_index]);

   double swept_level = 0.0;
   EXSparkSignalDirection direction = XSPARK_SIGNAL_NONE;
   int sweep_index = -1;

   if(body == XSPARK_SIGNAL_SELL)
   {
      sweep_index = XSparkIctFindBearishSweep(highs, closes, displacement_index, config, swept_level);
      if(sweep_index >= 0)
         direction = XSPARK_SIGNAL_SELL;
   }
   else if(body == XSPARK_SIGNAL_BUY)
   {
      sweep_index = XSparkIctFindBullishSweep(lows, closes, displacement_index, config, swept_level);
      if(sweep_index >= 0)
         direction = XSPARK_SIGNAL_BUY;
   }

   if(direction == XSPARK_SIGNAL_NONE)
   {
      verdicts.sweep = "NO SWEEP";
      setup.reason = body == XSPARK_SIGNAL_NONE
                     ? "The bar closed where it opened, so it points nowhere and cannot be a displacement."
                     : "No stop pool was raided in the bars before this one.";
      return false;
   }

   verdicts.sweep = direction == XSPARK_SIGNAL_SELL ? "SWEPT HIGH" : "SWEPT LOW";

   // 3. The break of structure: the displacement must close THROUGH the
   //    opposing swing formed between the raid and now. Without this the bar
   //    is just a candle inside the range.
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

   // The dealing range the premium/discount reading is taken against: from the
   // raided extreme to the far end of the leg the displacement made.
   double leg_extreme = direction == XSPARK_SIGNAL_SELL ? lows[eval_index] : highs[eval_index];
   for(int i = eval_index; i <= sweep_index && i < size; i++)
   {
      if(direction == XSPARK_SIGNAL_SELL)
      {
         if(lows[i] < leg_extreme) leg_extreme = lows[i];
      }
      else
      {
         if(highs[i] > leg_extreme) leg_extreme = highs[i];
      }
   }

   const double range_high = direction == XSPARK_SIGNAL_SELL ? swept_level : leg_extreme;
   const double range_low = direction == XSPARK_SIGNAL_SELL ? leg_extreme : swept_level;

   // 4 and 5. The imbalance, sought across the whole leg, and its consequent
   //          encroachment taken as the entry.
   double gap_low = 0.0;
   double gap_high = 0.0;
   int gap_index = -1;
   bool saw_any_gap = false;

   if(!XSparkIctSelectEntryGap(highs, lows, eval_index, sweep_index, direction,
                               config.min_gap_price, range_low, range_high,
                               config.use_premium_discount,
                               gap_low, gap_high, gap_index, saw_any_gap))
   {
      if(!saw_any_gap)
      {
         verdicts.imbalance = "NO FVG";
         setup.reason = "The leg left no imbalance wide enough to return to.";
      }
      else
      {
         verdicts.imbalance = "FVG";
         verdicts.location = "WRONG HALF";
         setup.reason = "Every imbalance in the leg sits in the wrong half of the dealing range.";
      }
      return false;
   }
   verdicts.imbalance = "FVG";

   double entry = 0.0;
   if(!XSparkIctConsequentEncroachment(gap_low, gap_high, entry))
   {
      setup.reason = "The imbalance has no usable midpoint.";
      return false;
   }

   double position = 0.0;
   XSparkIctRangePosition(entry, range_low, range_high, position);
   if(config.use_premium_discount)
      verdicts.location = direction == XSPARK_SIGNAL_SELL ? "PREMIUM" : "DISCOUNT";
   else
      verdicts.location = "OFF";

   // 6. The stop, beyond the raided extreme by a buffer that only clears the
   //    spread and the broker's stop level.
   const double buffer = config.stop_buffer_points * point_size;
   const double stop = direction == XSPARK_SIGNAL_SELL ? swept_level + buffer : swept_level - buffer;
   const double stop_distance = direction == XSPARK_SIGNAL_SELL ? stop - entry : entry - stop;

   if(stop_distance <= 0.0)
   {
      setup.reason = "The stop is on the wrong side of the entry; the sequence is not usable.";
      return false;
   }

   // 7. The draw on liquidity. The trade goes to the opposing pool of stops,
   //    and the reward ratio is whatever that implies - never chosen.
   double target = 0.0;
   if(!XSparkIctDrawOnLiquidity(highs, lows, sweep_index, entry, direction,
                                config.swing_lookback, config.swing_strength, target))
   {
      verdicts.liquidity = "NO DRAW";
      setup.reason = "No opposing pool of stops is within reach, so the trade has nowhere to go.";
      return false;
   }

   const double reward = direction == XSPARK_SIGNAL_SELL ? entry - target : target - entry;
   const double implied_r = reward / stop_distance;

   if(implied_r < config.min_target_r)
   {
      verdicts.liquidity = "DRAW TOO CLOSE";
      setup.reason = StringFormat("The draw on liquidity at %.5f is only %.2f times the stop away; at least %.2f is required.",
                                  target, implied_r, config.min_target_r);
      return false;
   }

   if(implied_r > config.max_target_r)
   {
      verdicts.liquidity = "DRAW TOO FAR";
      setup.reason = StringFormat("The draw on liquidity at %.5f is %.2f times the stop away, beyond the %.2f bound; that is a different trade.",
                                  target, implied_r, config.max_target_r);
      return false;
   }
   verdicts.liquidity = "DRAW FOUND";

   setup.direction = direction;
   setup.swept_level = swept_level;
   setup.gap_low = gap_low;
   setup.gap_high = gap_high;
   setup.entry_limit = entry;
   setup.sweep_index = sweep_index;
   setup.shift_index = displacement_index;
   setup.gap_index = gap_index;
   setup.stop = stop;
   setup.target = target;
   setup.target_r = implied_r;
   setup.range_position = position;

   setup.reason = StringFormat("%s: %s raided at %.5f, structure shifted, entry at the imbalance midpoint %.5f (%.0f%% of the dealing range), stop %.5f, draw on liquidity %.5f at %.2fR.",
                               direction == XSPARK_SIGNAL_SELL ? "SELL" : "BUY",
                               direction == XSPARK_SIGNAL_SELL ? "high" : "low",
                               swept_level, entry, position * 100.0, stop, target, implied_r);
   return true;
}

// The two win rates every target implies. Same arithmetic the other strategies
// use, declared here so this EA does not read through another strategy's
// constant (AGENTS.md rule 43).
//
// Break-even is what the geometry alone demands. No-edge is what a trade with
// no predictive content actually shows once the round-trip cost is paid, which
// is always the lower of the two - and the gap between them is what the entry
// has to be worth before any of this is a strategy rather than a lottery.
double XSparkIctBreakEvenWinRate(const double target_r)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0)
      return 0.0;
   return 1.0 / (1.0 + target_r);
}

double XSparkIctNoEdgeWinRate(const double target_r, const double cost_share_pct)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0 ||
      !MathIsValidNumber(cost_share_pct) || cost_share_pct < 0.0 || cost_share_pct >= 100.0)
      return 0.0;

   return (1.0 - cost_share_pct / 100.0) / (1.0 + target_r);
}

// The 95% Wilson lower bound on a win rate.
//
// Used rather than the plain proportion because the question a tester pass
// answers is not "was the win rate above break-even" but "is the sample large
// enough to say so": 20 of 40 is not, 200 of 400 is. This is what stops a
// lucky thirty trades from reading as an edge.
#define XSPARK_ICT_WILSON_Z_SCORE 1.96

bool XSparkIctWilsonLowerBound(const int wins, const int outcomes, double &lower)
{
   lower = 0.0;

   if(outcomes <= 0 || wins < 0 || wins > outcomes)
      return false;

   const double n = (double)outcomes;
   const double p = (double)wins / n;
   const double z = XSPARK_ICT_WILSON_Z_SCORE;
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
// How long a position may live.
// ---------------------------------------------------------------------------
//
// This model's claim is about what happens in the hours after a stop pool is
// run, so a position that is still open long after its kill zone closed is no
// longer in the trade that was taken. Two bounds, whichever comes first: a
// count of bars, and a wall-clock ceiling so a high chart period cannot turn
// the bar count into days.

#define XSPARK_ICT_MAX_HOLD_BARS 24
#define XSPARK_ICT_MAX_HOLD_SECONDS 21600

int XSparkIctMaxHoldSeconds(const int period_seconds)
{
   if(period_seconds <= 0)
      return 0;

   const long by_bars = (long)XSPARK_ICT_MAX_HOLD_BARS * (long)period_seconds;

   if(by_bars > (long)XSPARK_ICT_MAX_HOLD_SECONDS)
      return XSPARK_ICT_MAX_HOLD_SECONDS;

   return (int)by_bars;
}

// The server time at which the kill zone now in progress ends, so an open
// position is flattened rather than carried out of the window the model is
// about. Returns false outside every window, where the hold time above is the
// only bound and there is nothing to flatten at.
bool XSparkIctKillZoneEnd(const datetime server_time,
                          const int utc_offset_hours,
                          const EXSparkIctKillZones zones,
                          datetime &flatten_after,
                          string &reason)
{
   flatten_after = 0;
   reason = "";

   const int minutes_utc = XSparkIctMinutesUtc(server_time, utc_offset_hours);

   if(!XSparkIctInKillZone(minutes_utc, zones))
   {
      reason = "The clock is outside every kill zone, so there is no window end to flatten at.";
      return false;
   }

   const bool london = minutes_utc >= XSPARK_ICT_LONDON_START_MIN && minutes_utc < XSPARK_ICT_LONDON_END_MIN;
   const int end_minute = london ? XSPARK_ICT_LONDON_END_MIN : XSPARK_ICT_NEWYORK_END_MIN;

   // Measured as a delta from now rather than rebuilt from a date, so it stays
   // correct across the day boundary without a calendar.
   const long seconds_per_day = 86400;
   long utc = (long)server_time - (long)utc_offset_hours * 3600;
   long within_day = utc % seconds_per_day;
   if(within_day < 0)
      within_day += seconds_per_day;

   const long delta = (long)end_minute * 60 - within_day;
   if(delta <= 0)
   {
      reason = "The kill zone ends in the past, so the window end is not usable.";
      return false;
   }

   flatten_after = (datetime)((long)server_time + delta);
   return true;
}

// ---------------------------------------------------------------------------
// Cost and the live stop.
// ---------------------------------------------------------------------------
//
// Declared here rather than reused from another strategy: an input default or a
// cost rule that reads through another strategy's constant changes silently
// when that strategy is retuned (AGENTS.md rule 43). The arithmetic is the same
// arithmetic because the instrument is the same instrument.

// Spread plus commission, both ways, expressed as a price distance.
bool XSparkIctRoundTripCost(const double spread,
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

// The stop the EA actually sends, measured from the live quote rather than from
// the price the model measured.
//
// The model already placed the stop beyond the swept extreme, which is the
// invalidation. This applies the three things only the EA knows: how far the
// market has moved since the signal bar closed, the floor the round-trip cost
// implies, and the ceiling past which the trade is too wide to be this model's.
//
// A stop is only ever widened, never tightened: tightening it would move the
// stop inside the level whose breach says the setup failed.
bool XSparkIctStop(const EXSparkSignalDirection direction,
                   const double entry_reference,
                   const double model_stop,
                   const double atr,
                   const double round_trip_cost,
                   const XSparkIctConfig &config,
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

   if(!MathIsValidNumber(entry_reference) || entry_reference <= 0.0 ||
      !MathIsValidNumber(model_stop) || model_stop <= 0.0)
   {
      reason = "The entry reference or the model's stop is not usable.";
      return false;
   }

   if(!MathIsValidNumber(atr) || atr <= 0.0)
   {
      reason = "The stop bounds need the typical candle size and it is unavailable.";
      return false;
   }

   if(!MathIsValidNumber(round_trip_cost) || round_trip_cost < 0.0)
   {
      reason = "The round-trip cost is not a usable distance.";
      return false;
   }

   string config_reason = "";
   if(!XSparkIctConfigUsable(config, config_reason))
   {
      reason = config_reason;
      return false;
   }

   const double model_distance = direction == XSPARK_SIGNAL_BUY ? entry_reference - model_stop
                                                                : model_stop - entry_reference;

   if(model_distance <= 0.0)
   {
      reason = "The market has passed the model's stop, so the setup is already invalid.";
      return false;
   }

   const double atr_floor = config.min_stop_atr * atr;
   const double cost_floor = round_trip_cost * 100.0 / config.max_cost_share_pct;
   const double ceiling = config.max_stop_atr * atr;

   double used = model_distance;
   if(atr_floor > used)
      used = atr_floor;

   const bool cost_binding = cost_floor > used;
   if(cost_binding)
      used = cost_floor;

   if(used > ceiling)
   {
      // Naming the cost first matters: a trade refused because the spread is
      // wide is a different problem from one refused because the sweep was far
      // away, and only the operator can fix the first.
      reason = cost_binding
               ? StringFormat("COST: the round-trip cost %.8f is %.1f%% of the widest stop this chart period allows (%.8f); at most %.1f%% is permitted. A longer chart period, a tighter-spread account, or a lower commission fixes this.",
                              round_trip_cost, round_trip_cost / ceiling * 100.0, ceiling, config.max_cost_share_pct)
               : StringFormat("The stop would sit %.2f typical candles from the entry, over the %.2f ceiling; the swept level is too far to trade from here.",
                              used / atr, config.max_stop_atr);
      return false;
   }

   distance = used;
   stop = direction == XSPARK_SIGNAL_BUY ? entry_reference - used : entry_reference + used;
   return true;
}

// ---------------------------------------------------------------------------
// The strategy object.
// ---------------------------------------------------------------------------
//
// Reads the shared indicator cache, runs the pure model above, and fills the
// same XSparkSignal every other strategy fills. It creates signals and nothing
// else: no order call, no broker state, no exposure decision (AGENTS.md rules
// 6-8). The EA bounds the stop against the live quote and the cost floor, and
// RiskManager and ExecutionEngine decide whether anything is sent.
//
// The one thing carried here that TrendScalp does not carry is an entry LIMIT.
// This model does not enter at the market on the signal bar - it waits for
// price to retrace into the imbalance - so the signal names the worst price it
// will accept and execution refuses a fill beyond it.

// The score every ICT signal carries. The model is a sequence that either
// completed or did not, so there is nothing to grade: a fixed score keeps the
// shared report and panel readable without inventing a confidence.
#define XSPARK_ICT_SIGNAL_SCORE 5.0

class CXSparkIctLiquidity : public IXSparkStrategy
{
private:
   XSparkIctConfig m_config;
   string m_symbol;
   bool   m_initialized;
   string m_last_reason;
   int    m_utc_offset_hours;

public:
   CXSparkIctLiquidity()
   {
      XSparkDefaultIctConfig(m_config);
      m_symbol = "";
      m_initialized = false;
      m_last_reason = "The ICT strategy is not initialized.";
      m_utc_offset_hours = 0;
   }

   void Configure(const XSparkIctConfig &config)
   {
      m_config = config;
   }

   // The broker's clock offset from UTC. The kill zones are the only part of
   // this model that depends on wall-clock time, so a wrong offset moves the
   // windows rather than corrupting the shapes.
   void SetClockOffset(const int utc_offset_hours)
   {
      m_utc_offset_hours = utc_offset_hours;
   }

   // No TargetRewardRatio(): the reward ratio is not a property of this
   // strategy, it is whatever the draw on liquidity implies on the setup that
   // was found. Each signal carries its own.

   // The narrowest imbalance worth entering, handed down by the EA from the
   // round-trip cost. A gap narrower than the spread is not an entry.
   void SetMinimumGap(const double min_gap_price)
   {
      m_config.min_gap_price = min_gap_price;
   }

   bool Initialize(const string symbol)
   {
      m_initialized = false;
      m_symbol = "";

      if(symbol == "")
      {
         m_last_reason = "The ICT strategy needs a symbol.";
         return false;
      }

      string reason = "";
      if(!XSparkIctConfigUsable(m_config, reason))
      {
         m_last_reason = reason;
         return false;
      }

      // The deepest bar the sequence can read. Refused here rather than at the
      // first signal, because a lookback past the cache does not fail loudly -
      // it just never finds the oldest swing.
      const int deepest = m_config.sweep_max_age_bars + m_config.swing_lookback + m_config.swing_strength + 2;
      if(deepest >= XSPARK_SCOREBOT_CLOSED_BASE_BARS)
      {
         m_last_reason = StringFormat("The sequence would read %d bars back but only %d closed bars are cached.",
                                      deepest, XSPARK_SCOREBOT_CLOSED_BASE_BARS);
         return false;
      }

      m_symbol = symbol;
      m_initialized = true;
      m_last_reason = "";
      return true;
   }

   void Deinitialize()
   {
      m_initialized = false;
      m_symbol = "";
      m_last_reason = "The ICT strategy is not initialized.";
   }

   bool Evaluate(CXSparkIndicatorCache &cache,
                 XSparkSignal &signal,
                 XSparkScoreBotReport &report)
   {
      XSparkResetSignal(signal);
      XSparkResetScoreBotReport(report);
      report.pattern_mode = "ICT LIQUIDITY";
      report.entry_location = "FAIR VALUE GAP";
      report.htf_verdict = "OFF";
      report.pullback_verdict = "OFF";
      report.rsi_verdict = "OFF";
      report.joint_verdict = "BLOCKED";
      report.status = "SCANNING";

      if(!m_initialized)
      {
         report.block_reason = "The ICT strategy is not initialized.";
         m_last_reason = report.block_reason;
         return false;
      }

      if(!cache.IsValid())
      {
         report.block_reason = cache.LastReason();
         m_last_reason = report.block_reason;
         return false;
      }

      const double atr14 = cache.ATR14Base();
      const double atr50 = cache.ATR50Base();
      const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      // Copy the cached closed bars into series arrays: index 0 is the bar just
      // closed, which is what the model calls eval_index.
      double opens[];
      double highs[];
      double lows[];
      double closes[];
      ArrayResize(opens, XSPARK_SCOREBOT_CLOSED_BASE_BARS);
      ArrayResize(highs, XSPARK_SCOREBOT_CLOSED_BASE_BARS);
      ArrayResize(lows, XSPARK_SCOREBOT_CLOSED_BASE_BARS);
      ArrayResize(closes, XSPARK_SCOREBOT_CLOSED_BASE_BARS);

      XSparkCandle bar1;
      if(!cache.BaseBar(1, bar1))
      {
         report.block_reason = "The closed signal candle is unavailable.";
         m_last_reason = report.block_reason;
         return false;
      }

      for(int i = 0; i < XSPARK_SCOREBOT_CLOSED_BASE_BARS; i++)
      {
         XSparkCandle bar;
         if(!cache.BaseBar(i + 1, bar))
         {
            report.block_reason = StringFormat("Only %d closed bars are available; the sequence needs more.", i);
            m_last_reason = report.block_reason;
            return false;
         }
         opens[i] = bar.open;
         highs[i] = bar.high;
         lows[i] = bar.low;
         closes[i] = bar.close;
      }

      report.signal_bar_time = bar1.time;
      report.atr14 = atr14;
      report.atr50 = atr50;
      report.atr_points = 0.0;
      report.context.bar1_open = bar1.open;
      report.context.bar1_high = bar1.high;
      report.context.bar1_low = bar1.low;
      report.context.bar1_close = bar1.close;
      report.context.atr14 = atr14;

      const int minutes_utc = XSparkIctMinutesUtc(bar1.time, m_utc_offset_hours);

      XSparkIctSetup setup;
      XSparkIctVerdicts verdicts;

      if(!XSparkIctEvaluate(opens, highs, lows, closes, 0, minutes_utc, point_size, m_config, setup, verdicts))
      {
         // The verdicts are the funnel: the EA counts them so a run that takes
         // no trades says which ICT condition the market never produced.
         report.htf_verdict = verdicts.zone;
         report.pullback_verdict = verdicts.sweep;
         report.entry_location = verdicts.imbalance != "" ? verdicts.imbalance : "FAIR VALUE GAP";
         report.rsi_verdict = verdicts.liquidity != "" ? verdicts.liquidity : "OFF";
         report.joint_verdict = verdicts.location != "" ? verdicts.location : "BLOCKED";
         report.block_reason = setup.reason;
         m_last_reason = setup.reason;
         return false;
      }

      report.htf_verdict = verdicts.zone;
      report.pullback_verdict = verdicts.sweep;
      report.rsi_verdict = verdicts.liquidity;
      report.entry_location = verdicts.location;
      report.detected_level = setup.swept_level;
      report.dynamic_rr = setup.target_r;
      report.scored = true;
      report.threshold_passed = true;
      report.components.pattern = XSPARK_ICT_SIGNAL_SCORE;
      report.components.raw = XSPARK_ICT_SIGNAL_SCORE;
      report.components.final_score = XSPARK_ICT_SIGNAL_SCORE;
      report.components.session_weight = 1.0;
      report.joint_verdict = "PASS";
      report.status = "SIGNAL";
      report.block_reason = "";
      report.pattern_name = setup.direction == XSPARK_SIGNAL_SELL ? "SWEEP + MSS + FVG SHORT"
                                                                  : "SWEEP + MSS + FVG LONG";

      signal.symbol = m_symbol;
      signal.direction = setup.direction;
      signal.desired_stop = setup.stop;
      // Execution derives the take-profit from the ratio and the stop distance
      // it actually gets, so the modelled target is not carried as a price.
      signal.desired_target = 0.0;
      // The reward ratio the draw on liquidity implies, carried per signal.
      signal.dynamic_rr = setup.target_r;
      // The imbalance edge. Unlike a market entry this is the worst price the
      // model will accept: execution refuses a fill beyond it rather than
      // chasing the displacement it just measured.
      signal.entry_limit = setup.entry_limit;
      signal.score = XSPARK_ICT_SIGNAL_SCORE;
      signal.effective_threshold = 0.0;
      signal.pattern_score = XSPARK_ICT_SIGNAL_SCORE;
      signal.session_weight = 1.0;
      signal.atr14 = atr14;
      signal.atr50 = atr50;
      signal.signal_bar_time = bar1.time;
      signal.instance_time = bar1.time;
      signal.pattern_name = report.pattern_name;
      signal.context = report.context;
      signal.reason = setup.reason;

      m_last_reason = signal.reason;
      return true;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
