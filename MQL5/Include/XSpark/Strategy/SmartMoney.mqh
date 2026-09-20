#ifndef XSPARK_STRATEGY_SMART_MONEY_MQH
#define XSPARK_STRATEGY_SMART_MONEY_MQH

#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

// ---------------------------------------------------------------------------
// Smart Money Concepts, mechanized from the published Pine v5 indicator.
// ---------------------------------------------------------------------------
//
// WHAT THIS IS. The source is an INDICATOR: it draws market structure, order
// blocks, equal highs and lows, fair value gaps, strong/weak highs and lows and
// premium/discount zones, and it raises alerts. It contains no entry, no stop,
// no target and no position size, so "turn it into an Expert Advisor" cannot be
// a transcription - something has to supply the trade. This file supplies it,
// and every choice that the indicator did not make is marked DEPARTURE below so
// the line between what was transcribed and what was decided stays visible.
//
// TRANSCRIBED, shape for shape, from the Pine source:
//   - the leg/pivot detector, including its one-sided confirmation window
//   - internal structure (5 candles) and swing structure (50 candles) as two
//     separate structures, each with its own pivots, its own crossed flags and
//     its own BOS/CHoCH bias. Both lengths move together with the swing size
//     preset; the published pair is the NORMAL one
//   - the order block: the extreme bar of the leg that broke structure, chosen
//     over the volatility-parsed high/low, oldest bar winning a tie
//   - order block mitigation on the high/low source
//   - the trailing extremes and the strong/weak high and low they label
//   - equal highs and lows, at the published 0.1 threshold and 3-bar window
//   - fair value gaps, at the published auto threshold
//
// THE TRADE, which the indicator does not contain (all DEPARTURES):
//   1. structure breaks (internal, and by default only when the swing bias
//      agrees) - the indicator's own BOS/CHoCH event
//   2. the order block that break created, while it is still unmitigated
//   3. the entry is a LIMIT at the block's mean threshold, so the trade waits
//      for the retracement instead of chasing the break
//   4. the entry must sit in discount for a buy and premium for a sell, read
//      off the indicator's own premium/discount range
//   5. the stop sits beyond the block's far edge - the same level whose breach
//      makes the indicator delete the block, so stop and mitigation agree by
//      construction rather than by coincidence
//   6. the target is the draw on liquidity: the trailing extreme the indicator
//      labels Strong/Weak High or Low. The reward ratio is an OUTPUT of where
//      that level sits, never an input
//
// WHAT IS NOT CLAIMED. Nothing here says this is profitable. Smart Money
// Concepts is taught discretionarily and has no published, independently
// audited record; a popular indicator selects for attention, not for edge.
// What mechanizing it buys is the ability to find out: the rule is fixed, the
// journal says where every signal died, and OnTester reports an interval rather
// than an equity curve.
//
// THE HONEST PART. The exit geometry alone sets the win rate a trade with NO
// edge would show. The entry is the only possible source of edge, and it has to
// pay for the spread before it pays for anything else.
//
// ---------------------------------------------------------------------------
// STATE IS REBUILT, NEVER CARRIED.
// ---------------------------------------------------------------------------
//
// Pine keeps structure state from the first bar of the chart. An Expert Advisor
// cannot: it restarts, it reconnects, and RAM state that survives neither is
// state that silently differs between a tester pass and a live run.
//
// So every bar this model REPLAYS the indicator over a fixed window of closed
// bars, oldest to newest, in the indicator's own per-bar order, and reads the
// answer off the end. Two consequences, both deliberate:
//
//   - the same window always gives the same answer, on any terminal, after any
//     restart, in the tester and live. There is nothing to reconcile.
//   - structure older than the window does not exist. A swing pivot that has
//     scrolled off is gone, and the bias is whatever the window shows. This is
//     the price of determinism and it is paid knowingly.

// ---------------------------------------------------------------------------
// Tunables, fixed rather than exposed. An operator does not know better than
// the code what counts as a pivot (AGENTS.md rule 48). Where a number appears
// in the Pine source, that source's default is what appears here.
// ---------------------------------------------------------------------------

// Pine: swingsLengthInput = 50, and the internal structure is hard-coded to 5.
// This pair is the NORMAL size preset; the other two scale both together, so
// the internal structure stays roughly a tenth of the swing in all three.
#define XSPARK_SMC_SWING_LENGTH 50
#define XSPARK_SMC_INTERNAL_LENGTH 5
#define XSPARK_SMC_FAST_SWING_LENGTH 20
#define XSPARK_SMC_FAST_INTERNAL_LENGTH 3
#define XSPARK_SMC_SLOW_SWING_LENGTH 65
#define XSPARK_SMC_SLOW_INTERNAL_LENGTH 8

// Pine: equalHighsLowsLengthInput = 3, equalHighsLowsThresholdInput = 0.1.
#define XSPARK_SMC_EQUAL_LENGTH 3
#define XSPARK_SMC_EQUAL_THRESHOLD 0.1

// Pine: a bar whose range is at least twice the volatility measure has its high
// and low SWAPPED before the order block search reads them, which is what stops
// one violent candle from becoming every order block on the chart.
#define XSPARK_SMC_HIGH_VOLATILITY_MULT 2.0

// How many live order blocks and imbalances the model carries. Pine keeps 100
// and draws 5; nothing here reads past the newest few, and a smaller ring keeps
// the state a fixed-size value that can be rebuilt each bar without allocation.
#define XSPARK_SMC_MAX_BLOCKS 12
#define XSPARK_SMC_MAX_GAPS 12

// DEPARTURE. How long after the break the retracement may still be taken. The
// indicator draws a block until price mitigates it, however long that takes; a
// trade taken forty bars after the reason for it is a different trade.
#define XSPARK_SMC_MAX_BLOCK_AGE_BARS 60
#define XSPARK_SMC_FAST_BLOCK_AGE_BARS 30
#define XSPARK_SMC_SLOW_BLOCK_AGE_BARS 70

// DEPARTURE. Stop placement beyond the block's far edge, in instrument points.
// The far edge is the invalidation - price through it is exactly the condition
// on which the indicator deletes the block - so the buffer only has to clear
// the spread and the broker's stop level. Deliberately not an ATR multiple.
#define XSPARK_SMC_STOP_BUFFER_POINTS 20.0

// DEPARTURE. The reward the draw on liquidity must offer before the trade is
// worth taking, and the point past which it is a different trade. Not a target:
// the target is wherever the liquidity is.
#define XSPARK_SMC_MIN_TARGET_R 1.5
#define XSPARK_SMC_MAX_TARGET_R 20.0

// The risk layer's bounds on the stop it will send, and the share of that stop
// the round-trip cost may be. These never decide whether a setup exists, only
// whether one the model found can be traded at an acceptable cost.
#define XSPARK_SMC_MIN_STOP_ATR 0.50
#define XSPARK_SMC_MAX_STOP_ATR 3.50
#define XSPARK_SMC_MAX_COST_SHARE_PCT 6.0

// Premium and discount, from the indicator's own zones: buy only from the lower
// half of the dealing range, sell only from the upper half. ON, because the
// entry is a retracement and entering on the wrong half of the range is paying
// for the move that was supposed to be the profit.
#define XSPARK_SMC_USE_PREMIUM_DISCOUNT true

// Pine: orderBlockMitigationInput defaults to High/Low rather than Close.
#define XSPARK_SMC_MITIGATION_USES_CLOSE false

// Pine: fairValueGapsThresholdInput = true (the auto threshold).
#define XSPARK_SMC_GAP_AUTO_THRESHOLD true

// ---------------------------------------------------------------------------
// The four levers, and why they are the only four.
// ---------------------------------------------------------------------------
//
// The published indicator exposes about forty settings. Most of them are the
// indicator being an indicator: colours, label sizes, which boxes to draw, how
// far to extend them, Historical vs Present, Colored vs Monochrome. None of
// those can change what a trade does, because this EA draws nothing.
//
// Of the rest, four change which trades exist, and each is offered here as a
// NAMED CHOICE rather than as the numbers behind it: every value is a
// configuration that is internally consistent on its own, so there is no
// combination to get wrong (AGENTS.md rule 49).
//
//   which structure   <- the indicator's Internal vs Swing order blocks
//   which break       <- its Bullish/Bearish Structure = All / BOS / CHoCH
//   how big a swing   <- its Show Swings Points length
//   how selective     <- its Premium/Discount Zones and Fair Value Gaps
//
// What is NOT offered, and why, so an absence is not mistaken for an oversight:
//
//   Order Block Filter (Atr vs Cumulative Mean Range). The published note on it
//     recommends the cumulative mean range "when a low amount of data is
//     available", and a rebuilt window is exactly that case - 200 bars of ATR
//     cannot be read out of a 160-bar window. So there is one correct answer
//     here, not a choice, and it is a constant.
//   Order Block Mitigation (Close vs High/Low). In the indicator this decides
//     when a box stops being drawn. Here the same level is the STOP, and a zone
//     price has already traded through is not an entry at any price - so the
//     high/low reading, which is also the indicator's own default, is the only
//     one consistent with where the stop sits.
//   Bars Confirmation and Threshold for equal highs and lows. Both are numbers
//     that can only be copied from their defaults (AGENTS.md rule 48), and here
//     they affect one line of the journal rather than any entry.
//   Confluence Filter. Off in the source, and its published expression compares
//     a price to a distance; mechanizing it faithfully would mechanize a defect.
//   Everything under Highs & Lows MTF, and the Fair Value Gaps timeframe. Drawn
//     levels from other chart periods. This model reads one chart period.
//
// Ordinals are a wire format: append, never renumber (AGENTS.md rule 50).

enum EXSparkSmcStructure
{
   XSPARK_SMC_INTERNAL_WITH_SWING = 0, // Internal break, the swing trend must agree
   XSPARK_SMC_INTERNAL_ONLY       = 1, // Internal break alone (more trades)
   XSPARK_SMC_SWING_ONLY          = 2  // Swing break alone (far fewer trades)
};

// The indicator's All / BOS / CHoCH filter. There it decides which labels are
// drawn; here it decides which breaks are traded, which is the same distinction
// doing real work: a change of character is the FIRST break against the prior
// bias, and a break of structure is one that extends it.
enum EXSparkSmcBreakType
{
   XSPARK_SMC_BREAK_ANY          = 0, // Both reversals and continuations
   XSPARK_SMC_BREAK_REVERSAL     = 1, // Reversals only (the first break the other way)
   XSPARK_SMC_BREAK_CONTINUATION = 2  // Continuations only (breaks that extend a trend)
};

// The indicator's swing length, which it defaults to 50. One choice moves the
// swing length, the internal length and how long a block stays enterable
// together, because a 20-candle swing with a 60-candle memory is not a faster
// version of the same rule, it is a different rule.
enum EXSparkSmcSwingSize
{
   XSPARK_SMC_SWING_NORMAL = 0, // Normal: 50-candle swings (the published setting)
   XSPARK_SMC_SWING_FAST   = 1, // Fast: 20-candle swings, more trades
   XSPARK_SMC_SWING_SLOW   = 2  // Slow: 65-candle swings, fewest trades
};

// The indicator's Premium/Discount Zones and Fair Value Gaps switches, folded
// into one dial because they are the same question asked twice: how much has to
// line up before this is an entry.
enum EXSparkSmcSelectivity
{
   XSPARK_SMC_BALANCED   = 0, // Balanced: only enter from the right half of the range
   XSPARK_SMC_STRICT     = 1, // Strict: also require the move to leave a price gap
   XSPARK_SMC_PERMISSIVE = 2  // Permissive: enter the zone wherever it sits
};

string XSparkSmcStructureName(const int mode)
{
   if(mode == XSPARK_SMC_INTERNAL_ONLY)
      return "internal structure alone";
   if(mode == XSPARK_SMC_SWING_ONLY)
      return "swing structure alone";
   return "internal structure with the swing bias agreeing";
}

string XSparkSmcBreakTypeName(const int break_type)
{
   if(break_type == XSPARK_SMC_BREAK_REVERSAL)
      return "changes of character only (the first break against the bias)";
   if(break_type == XSPARK_SMC_BREAK_CONTINUATION)
      return "breaks of structure only (breaks that extend the bias)";
   return "both changes of character and breaks of structure";
}

string XSparkSmcSwingSizeName(const int size)
{
   if(size == XSPARK_SMC_SWING_FAST)
      return "fast";
   if(size == XSPARK_SMC_SWING_SLOW)
      return "slow";
   return "normal";
}

string XSparkSmcSelectivityName(const int selectivity)
{
   if(selectivity == XSPARK_SMC_STRICT)
      return "strict: the right half of the dealing range AND an unfilled price gap";
   if(selectivity == XSPARK_SMC_PERMISSIVE)
      return "permissive: the order block wherever it sits in the dealing range";
   return "balanced: the right half of the dealing range, no gap required";
}

// ---------------------------------------------------------------------------
// Series indexing.
// ---------------------------------------------------------------------------
//
// Index 0 is the newest CLOSED bar and a LARGER index is OLDER, which is the
// reverse of the way the eye reads a chart. Every loop below is written in that
// convention, and Pine's `high[size]` is therefore `highs[index + size]`.

// ---------------------------------------------------------------------------
// The indicator's leg detector.
// ---------------------------------------------------------------------------
//
// Pine:   newLegHigh = high[size] > ta.highest(size)
//
// ta.highest(size) is the highest of the `size` bars ENDING at the current bar,
// so the test is: the bar `size` back is strictly higher than every bar since.
// Note what is NOT tested - anything to the left of that bar. This is a
// one-sided confirmation window, not a symmetric pivot, and transcribing it
// faithfully means transcribing that asymmetry.

bool XSparkSmcNewLegHigh(const double &highs[], const int index, const int size)
{
   const int count = ArraySize(highs);
   if(size <= 0 || index < 0 || index + size >= count)
      return false;

   const double pivot = highs[index + size];
   if(!MathIsValidNumber(pivot))
      return false;

   for(int i = index; i < index + size; i++)
   {
      if(!MathIsValidNumber(highs[i]))
         return false;
      if(highs[i] >= pivot)
         return false;
   }

   return true;
}

bool XSparkSmcNewLegLow(const double &lows[], const int index, const int size)
{
   const int count = ArraySize(lows);
   if(size <= 0 || index < 0 || index + size >= count)
      return false;

   const double pivot = lows[index + size];
   if(!MathIsValidNumber(pivot))
      return false;

   for(int i = index; i < index + size; i++)
   {
      if(!MathIsValidNumber(lows[i]))
         return false;
      if(lows[i] <= pivot)
         return false;
   }

   return true;
}

// ---------------------------------------------------------------------------
// The volatility measure.
// ---------------------------------------------------------------------------
//
// Pine offers ATR(200) or the cumulative mean true range and recommends the
// latter "when a low amount of data is available". A rebuilt window is exactly
// that case - 200 bars of ATR cannot be read from a 160-bar window - so the
// mean true range OVER THE WINDOW is what this model uses, for the order block
// volatility parse and for the equal-high threshold alike.
//
// It also keeps the model free of an indicator handle: the whole structure
// reading is a function of the bars and nothing else.
double XSparkSmcMeanRange(const double &highs[], const double &lows[], const double &closes[], const int count)
{
   if(count < 2)
      return 0.0;

   const int size = ArraySize(highs);
   if(size != ArraySize(lows) || size != ArraySize(closes) || count > size)
      return 0.0;

   double total = 0.0;
   int used = 0;

   for(int i = 0; i < count - 1; i++)
   {
      const double high = highs[i];
      const double low = lows[i];
      const double previous_close = closes[i + 1];
      if(!MathIsValidNumber(high) || !MathIsValidNumber(low) || !MathIsValidNumber(previous_close))
         continue;

      const double range = MathMax(high - low, MathMax(MathAbs(high - previous_close), MathAbs(low - previous_close)));
      if(!MathIsValidNumber(range) || range < 0.0)
         continue;

      total += range;
      used++;
   }

   return used > 0 ? total / (double)used : 0.0;
}

// The indicator's own body-delta scale, mean of its absolute value across the
// window. Pine measures it as (close - open) / (open * 100), which is a hundredth
// of the fractional body size rather than a percentage; the gap test compares it
// against a threshold built from the same expression, so the scale cancels and
// the shape is what matters. Transcribed as written rather than "corrected",
// because correcting one side of a comparison and not the other would change
// which gaps qualify.
double XSparkSmcMeanBodyDelta(const double &opens[], const double &closes[], const int count)
{
   const int size = ArraySize(opens);
   if(count < 1 || count > size || size != ArraySize(closes))
      return 0.0;

   double total = 0.0;
   int used = 0;

   for(int i = 0; i < count; i++)
   {
      const double open = opens[i];
      const double close = closes[i];
      if(!MathIsValidNumber(open) || !MathIsValidNumber(close) || open <= 0.0)
         continue;

      total += MathAbs((close - open) / (open * 100.0));
      used++;
   }

   return used > 0 ? total / (double)used : 0.0;
}

// ---------------------------------------------------------------------------
// The pieces of indicator state.
// ---------------------------------------------------------------------------

struct XSparkSmcPivot
{
   double   level;       // the pivot price
   double   last_level;  // the one before it, which is what HH/LL compares against
   bool     crossed;     // true once a close has broken it; reset by a new pivot
   bool     valid;
   int      index;       // series index of the pivot bar inside the window
   datetime time;
};

void XSparkSmcResetPivot(XSparkSmcPivot &pivot)
{
   pivot.level = 0.0;
   pivot.last_level = 0.0;
   pivot.crossed = false;
   pivot.valid = false;
   pivot.index = -1;
   pivot.time = 0;
}

// An order block, plus the structure break that created it. Pine stores only
// the block, because a drawing does not need to remember why it exists; a trade
// does - the break is the reason, and it is what decides whether the block may
// still be entered.
struct XSparkSmcBlock
{
   double   high;              // the parsed high of the block bar
   double   low;               // the parsed low
   datetime time;              // the block bar
   int      index;             // series index of the block bar
   int      bias;              // XSPARK_SIGNAL_BUY or XSPARK_SIGNAL_SELL
   bool     internal;          // created by the internal structure, not the swing
   bool     choch;             // the break was a change of character, not a continuation
   int      break_index;       // series index of the bar that broke structure
   datetime break_time;
   int      pivot_index;       // series index of the pivot the break crossed
   double   broken_level;      // the price that was crossed
   int      swing_trend_at_break;
};

void XSparkSmcResetBlock(XSparkSmcBlock &block)
{
   block.high = 0.0;
   block.low = 0.0;
   block.time = 0;
   block.index = -1;
   block.bias = XSPARK_SIGNAL_NONE;
   block.internal = false;
   block.choch = false;
   block.break_index = -1;
   block.break_time = 0;
   block.pivot_index = -1;
   block.broken_level = 0.0;
   block.swing_trend_at_break = XSPARK_SIGNAL_NONE;
}

struct XSparkSmcGap
{
   double   top;
   double   bottom;
   int      bias;
   int      index;   // series index of the newest of the three bars
   datetime time;
};

void XSparkSmcResetGap(XSparkSmcGap &gap)
{
   gap.top = 0.0;
   gap.bottom = 0.0;
   gap.bias = XSPARK_SIGNAL_NONE;
   gap.index = -1;
   gap.time = 0;
}

// ---------------------------------------------------------------------------
// The rings the replay fills.
// ---------------------------------------------------------------------------
//
// Fixed-capacity, newest first, oldest evicted. Wrapped in a struct rather than
// left as two loose members so one function can serve both the internal and the
// swing set: a mirrored pair of bodies is a pair that drifts.

struct XSparkSmcBlockRing
{
   XSparkSmcBlock items[XSPARK_SMC_MAX_BLOCKS];
   int            count;
};

struct XSparkSmcGapRing
{
   XSparkSmcGap items[XSPARK_SMC_MAX_GAPS];
   int          count;
};

void XSparkSmcResetBlockRing(XSparkSmcBlockRing &ring)
{
   for(int i = 0; i < XSPARK_SMC_MAX_BLOCKS; i++)
      XSparkSmcResetBlock(ring.items[i]);
   ring.count = 0;
}

void XSparkSmcResetGapRing(XSparkSmcGapRing &ring)
{
   for(int i = 0; i < XSPARK_SMC_MAX_GAPS; i++)
      XSparkSmcResetGap(ring.items[i]);
   ring.count = 0;
}

// Everything the replay produces. A fixed-size value with no strings and no
// dynamic arrays, so it can be rebuilt from scratch on every bar without
// allocating and without anything surviving between bars.
struct XSparkSmcState
{
   XSparkSmcPivot swing_high, swing_low;
   XSparkSmcPivot internal_high, internal_low;
   XSparkSmcPivot equal_high, equal_low;

   int    swing_trend;      // XSPARK_SIGNAL_BUY / SELL / NONE
   int    internal_trend;

   // Each extreme becomes usable as soon as its own side has produced a swing
   // pivot, which is how the indicator behaves: the top extends from the first
   // swing high whether or not a swing low has printed yet. The dealing range
   // needs both, and trailing_valid says so.
   bool     trailing_top_valid, trailing_bottom_valid, trailing_valid;
   double   trailing_top, trailing_bottom;
   datetime trailing_top_time, trailing_bottom_time;

   bool     equal_high_found, equal_low_found;
   double   equal_high_level, equal_low_level;
   datetime equal_high_time, equal_low_time;

   XSparkSmcBlockRing internal_blocks;
   XSparkSmcBlockRing swing_blocks;
   XSparkSmcGapRing   gaps;

   double measure;    // the mean true range the parse and the threshold both use
   int    bars_used;  // how many bars the replay actually walked
};

void XSparkSmcResetState(XSparkSmcState &state)
{
   XSparkSmcResetPivot(state.swing_high);
   XSparkSmcResetPivot(state.swing_low);
   XSparkSmcResetPivot(state.internal_high);
   XSparkSmcResetPivot(state.internal_low);
   XSparkSmcResetPivot(state.equal_high);
   XSparkSmcResetPivot(state.equal_low);

   state.swing_trend = XSPARK_SIGNAL_NONE;
   state.internal_trend = XSPARK_SIGNAL_NONE;

   state.trailing_top_valid = false;
   state.trailing_bottom_valid = false;
   state.trailing_valid = false;
   state.trailing_top = 0.0;
   state.trailing_bottom = 0.0;
   state.trailing_top_time = 0;
   state.trailing_bottom_time = 0;

   state.equal_high_found = false;
   state.equal_low_found = false;
   state.equal_high_level = 0.0;
   state.equal_low_level = 0.0;
   state.equal_high_time = 0;
   state.equal_low_time = 0;

   XSparkSmcResetBlockRing(state.internal_blocks);
   XSparkSmcResetBlockRing(state.swing_blocks);
   XSparkSmcResetGapRing(state.gaps);

   state.measure = 0.0;
   state.bars_used = 0;
}

// ---------------------------------------------------------------------------
// Configuration.
// ---------------------------------------------------------------------------

struct XSparkSmcConfig
{
   int    swing_length;
   int    internal_length;
   int    equal_length;
   double equal_threshold;
   double high_volatility_mult;
   bool   mitigation_uses_close;
   bool   gap_auto_threshold;

   int    structure_mode;     // EXSparkSmcStructure
   int    break_type;         // EXSparkSmcBreakType
   bool   require_gap;        // set by EXSparkSmcSelectivity
   bool   use_premium_discount;  // set by EXSparkSmcSelectivity
   int    max_block_age_bars;    // set by EXSparkSmcSwingSize

   // The thinnest order block worth entering, as a price distance. Supplied by
   // the EA from the round-trip cost, because only the EA knows the spread. A
   // block narrower than the spread is not a zone, it is noise.
   double min_block_price;

   double stop_buffer_points;
   double min_stop_atr;
   double max_stop_atr;
   double max_cost_share_pct;
   double min_target_r;
   double max_target_r;
};

void XSparkSmcDefaultConfig(XSparkSmcConfig &config)
{
   config.swing_length = XSPARK_SMC_SWING_LENGTH;
   config.internal_length = XSPARK_SMC_INTERNAL_LENGTH;
   config.equal_length = XSPARK_SMC_EQUAL_LENGTH;
   config.equal_threshold = XSPARK_SMC_EQUAL_THRESHOLD;
   config.high_volatility_mult = XSPARK_SMC_HIGH_VOLATILITY_MULT;
   config.mitigation_uses_close = XSPARK_SMC_MITIGATION_USES_CLOSE;
   config.gap_auto_threshold = XSPARK_SMC_GAP_AUTO_THRESHOLD;

   config.structure_mode = XSPARK_SMC_INTERNAL_WITH_SWING;
   config.break_type = XSPARK_SMC_BREAK_ANY;
   config.require_gap = false;
   config.use_premium_discount = XSPARK_SMC_USE_PREMIUM_DISCOUNT;
   config.max_block_age_bars = XSPARK_SMC_MAX_BLOCK_AGE_BARS;

   config.min_block_price = 0.0;

   config.stop_buffer_points = XSPARK_SMC_STOP_BUFFER_POINTS;
   config.min_stop_atr = XSPARK_SMC_MIN_STOP_ATR;
   config.max_stop_atr = XSPARK_SMC_MAX_STOP_ATR;
   config.max_cost_share_pct = XSPARK_SMC_MAX_COST_SHARE_PCT;
   config.min_target_r = XSPARK_SMC_MIN_TARGET_R;
   config.max_target_r = XSPARK_SMC_MAX_TARGET_R;
}

bool XSparkSmcConfigUsable(const XSparkSmcConfig &config, string &reason)
{
   reason = "";

   if(config.internal_length <= 0 || config.swing_length <= config.internal_length)
   {
      reason = "The swing structure must be longer than the internal structure, and both must be positive.";
      return false;
   }

   if(config.equal_length <= 0)
   {
      reason = "Equal highs and lows need at least one bar of confirmation.";
      return false;
   }

   if(!MathIsValidNumber(config.equal_threshold) || config.equal_threshold <= 0.0 || config.equal_threshold > 0.5)
   {
      reason = "The equal high/low threshold must sit between zero and half a typical candle.";
      return false;
   }

   if(!MathIsValidNumber(config.high_volatility_mult) || config.high_volatility_mult <= 0.0)
   {
      reason = "The high-volatility multiple is not a usable number.";
      return false;
   }

   if(config.structure_mode != XSPARK_SMC_INTERNAL_WITH_SWING &&
      config.structure_mode != XSPARK_SMC_INTERNAL_ONLY &&
      config.structure_mode != XSPARK_SMC_SWING_ONLY)
   {
      reason = "The structure selection is not one this model knows.";
      return false;
   }

   if(config.break_type != XSPARK_SMC_BREAK_ANY &&
      config.break_type != XSPARK_SMC_BREAK_REVERSAL &&
      config.break_type != XSPARK_SMC_BREAK_CONTINUATION)
   {
      reason = "The break selection is not one this model knows.";
      return false;
   }

   if(config.max_block_age_bars <= 0)
   {
      reason = "An order block must be allowed to be at least one bar old.";
      return false;
   }

   if(!MathIsValidNumber(config.min_block_price) || config.min_block_price < 0.0)
   {
      reason = "The thinnest tradeable order block is not a usable distance.";
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

// The deepest bar the replay reads, so a window too short to hold the structure
// is refused once at startup rather than silently producing no swing at all.
int XSparkSmcRequiredBars(const XSparkSmcConfig &config)
{
   return config.swing_length + config.max_block_age_bars + config.equal_length + 3;
}

// How many candles of the window the replay actually walks. A swing pivot is
// only confirmed once `swing_length` newer candles have printed below it, so the
// window spends that many candles before it can produce its first one - and the
// dealing range needs a swing high AND a swing low before any entry is possible.
//
// This is the ceiling the 160-candle structure window imposes on the slow
// preset, and the reason there is no slower one. The EA prints it at startup so
// a configuration that will mostly report RANGE UNKNOWN says so on the first
// bar rather than after a quiet week.
int XSparkSmcReplayBars(const XSparkSmcConfig &config, const int window_bars)
{
   const int bars = window_bars - 1 - config.swing_length;
   return bars > 0 ? bars : 0;
}

// Whether the window leaves enough room for the chosen swing size to produce
// the two pivots a dealing range needs. Three swing lengths of replay is the
// floor: fewer, and one zigzag has to land exactly right for the model to see a
// range at all.
bool XSparkSmcWindowIsComfortable(const XSparkSmcConfig &config, const int window_bars)
{
   if(config.swing_length <= 0)
      return false;

   return XSparkSmcReplayBars(config, window_bars) >= 3 * config.swing_length;
}

// The swing size preset. Moves the swing length, the internal length and the
// block's shelf life together: each value is a whole configuration, and none of
// the three numbers is separately settable, because a fast swing with a slow
// memory is not a faster version of this rule (AGENTS.md rule 49).
bool XSparkSmcApplySwingSize(XSparkSmcConfig &config, const int size, string &reason)
{
   reason = "";

   if(size == XSPARK_SMC_SWING_FAST)
   {
      config.swing_length = XSPARK_SMC_FAST_SWING_LENGTH;
      config.internal_length = XSPARK_SMC_FAST_INTERNAL_LENGTH;
      config.max_block_age_bars = XSPARK_SMC_FAST_BLOCK_AGE_BARS;
      return true;
   }

   if(size == XSPARK_SMC_SWING_SLOW)
   {
      config.swing_length = XSPARK_SMC_SLOW_SWING_LENGTH;
      config.internal_length = XSPARK_SMC_SLOW_INTERNAL_LENGTH;
      config.max_block_age_bars = XSPARK_SMC_SLOW_BLOCK_AGE_BARS;
      return true;
   }

   if(size == XSPARK_SMC_SWING_NORMAL)
   {
      config.swing_length = XSPARK_SMC_SWING_LENGTH;
      config.internal_length = XSPARK_SMC_INTERNAL_LENGTH;
      config.max_block_age_bars = XSPARK_SMC_MAX_BLOCK_AGE_BARS;
      return true;
   }

   reason = "The swing size is not one this model knows.";
   return false;
}

// The selectivity preset. Both switches are the same question - how much has to
// line up - so they move together and cannot be set to a pair nobody tested.
bool XSparkSmcApplySelectivity(XSparkSmcConfig &config, const int selectivity, string &reason)
{
   reason = "";

   if(selectivity == XSPARK_SMC_STRICT)
   {
      config.use_premium_discount = true;
      config.require_gap = true;
      return true;
   }

   if(selectivity == XSPARK_SMC_PERMISSIVE)
   {
      config.use_premium_discount = false;
      config.require_gap = false;
      return true;
   }

   if(selectivity == XSPARK_SMC_BALANCED)
   {
      config.use_premium_discount = true;
      config.require_gap = false;
      return true;
   }

   reason = "The selectivity is not one this model knows.";
   return false;
}

void XSparkSmcPushBlock(XSparkSmcBlockRing &ring, const XSparkSmcBlock &block)
{
   const int last = ring.count < XSPARK_SMC_MAX_BLOCKS ? ring.count : XSPARK_SMC_MAX_BLOCKS - 1;
   for(int i = last; i > 0; i--)
      ring.items[i] = ring.items[i - 1];

   ring.items[0] = block;
   if(ring.count < XSPARK_SMC_MAX_BLOCKS)
      ring.count++;
}

void XSparkSmcPushGap(XSparkSmcGapRing &ring, const XSparkSmcGap &gap)
{
   const int last = ring.count < XSPARK_SMC_MAX_GAPS ? ring.count : XSPARK_SMC_MAX_GAPS - 1;
   for(int i = last; i > 0; i--)
      ring.items[i] = ring.items[i - 1];

   ring.items[0] = gap;
   if(ring.count < XSPARK_SMC_MAX_GAPS)
      ring.count++;
}

// ---------------------------------------------------------------------------
// Mitigation.
// ---------------------------------------------------------------------------
//
// Pine: a bearish block dies when the source trades above its high, a bullish
// block when the source trades below its low. The source is the bar's high/low
// by default and its close when the operator asks for it.
//
// DEPARTURE, in the mechanics rather than the rule: the published loop removes
// elements while iterating over the same array, which skips the element after
// every removal. Two blocks mitigated by one bar therefore leave one of them on
// the chart. This compacts instead, so "mitigated" means mitigated.
void XSparkSmcMitigateBlocks(XSparkSmcBlockRing &ring, const double bearish_source, const double bullish_source)
{
   int kept = 0;

   for(int i = 0; i < ring.count; i++)
   {
      const bool mitigated = (ring.items[i].bias == XSPARK_SIGNAL_SELL && bearish_source > ring.items[i].high) ||
                             (ring.items[i].bias == XSPARK_SIGNAL_BUY && bullish_source < ring.items[i].low);
      if(mitigated)
         continue;

      if(kept != i)
         ring.items[kept] = ring.items[i];
      kept++;
   }

   for(int i = kept; i < ring.count; i++)
      XSparkSmcResetBlock(ring.items[i]);

   ring.count = kept;
}

// DEPARTURE, deliberate and visible. The published deletion is asymmetric: a
// bullish gap survives until price passes its FAR edge, while a bearish gap
// dies the moment price touches its NEAR one - a consequence of the bearish
// record storing its two edges the other way round. For a drawing that is a
// cosmetic inconsistency. For a rule that asks "does this imbalance still
// exist" it is two different questions wearing one name, so both sides are
// read here as the same question: the gap lives until price trades through it.
void XSparkSmcMitigateGaps(XSparkSmcGapRing &ring, const double high, const double low)
{
   int kept = 0;

   for(int i = 0; i < ring.count; i++)
   {
      const bool mitigated = (ring.items[i].bias == XSPARK_SIGNAL_BUY && low < ring.items[i].bottom) ||
                             (ring.items[i].bias == XSPARK_SIGNAL_SELL && high > ring.items[i].top);
      if(mitigated)
         continue;

      if(kept != i)
         ring.items[kept] = ring.items[i];
      kept++;
   }

   for(int i = kept; i < ring.count; i++)
      XSparkSmcResetGap(ring.items[i]);

   ring.count = kept;
}

// ---------------------------------------------------------------------------
// One step of the leg detector.
// ---------------------------------------------------------------------------
//
// Each of the three structures the indicator runs - swing, internal and the
// equal-high/low detector - carries its OWN leg value, because in Pine each
// call site of leg() gets its own instance. Sharing one would make the internal
// structure's pivots depend on the swing structure's, which is not the source.

struct XSparkSmcLegEvent
{
   bool new_pivot;
   bool pivot_high;
   double level;
   int index;
};

void XSparkSmcStepLeg(const double &highs[], const double &lows[], const int index, const int size,
                      const bool first_bar, int &leg, XSparkSmcLegEvent &event)
{
   event.new_pivot = false;
   event.pivot_high = false;
   event.level = 0.0;
   event.index = -1;

   const int previous = leg;

   // Pine's BEARISH_LEG is 0 and BULLISH_LEG is 1. A new leg HIGH starts a
   // bearish leg; a new leg LOW starts a bullish one.
   if(XSparkSmcNewLegHigh(highs, index, size))
      leg = 0;
   else if(XSparkSmcNewLegLow(lows, index, size))
      leg = 1;

   // ta.change() is undefined on the first bar, so nothing starts there.
   if(first_bar || leg == previous)
      return;

   event.new_pivot = true;
   event.pivot_high = leg == 0;
   event.index = index + size;
   event.level = event.pivot_high ? highs[event.index] : lows[event.index];
}

// The pivot levels as they stood on the PREVIOUS bar. Pine's ta.crossover reads
// both of its arguments one bar back as well as now, so a break has to be
// measured against the level that existed when the earlier close was printed -
// not against a level set by the pivot that formed on this very bar.
struct XSparkSmcSnapshot
{
   double close;
   double internal_high, internal_low, swing_high, swing_low;
   bool   internal_high_valid, internal_low_valid, swing_high_valid, swing_low_valid;
};

// ---------------------------------------------------------------------------
// The order block.
// ---------------------------------------------------------------------------
//
// Pine, on the bar that breaks structure: take every bar from the broken pivot
// up to (but not including) this one, and pick the extreme one - the highest
// parsed high for a bearish break, the lowest parsed low for a bullish one.
// Its parsed high and low become the block.
//
// The PARSE is the volatility filter: a bar whose range is at least twice the
// volatility measure has its high and low swapped before the comparison, which
// deflates it out of the contest. That is the entire mechanism by which one
// violent candle does not become every order block on the chart.
//
// Ties go to the OLDEST bar, because Pine's array is ordered oldest first and
// indexof() returns the first match. Oldest is the LARGEST series index here.
void XSparkSmcStoreBlock(const double &highs[], const double &lows[], const datetime &times[],
                         const int break_index, const int pivot_index, const int bias,
                         const bool internal, const bool choch, const double broken_level,
                         const XSparkSmcConfig &config, XSparkSmcState &state)
{
   // An empty range stores nothing: Pine's slice(pivot, current) is empty when
   // the pivot is the bar before this one.
   if(pivot_index <= break_index || break_index < 0)
      return;

   const int size = ArraySize(highs);
   if(pivot_index >= size)
      return;

   const double swap_at = config.high_volatility_mult * state.measure;

   int chosen = -1;
   double best = 0.0;

   for(int i = pivot_index; i >= break_index + 1; i--)
   {
      if(!MathIsValidNumber(highs[i]) || !MathIsValidNumber(lows[i]))
         continue;

      const bool volatile_bar = swap_at > 0.0 && (highs[i] - lows[i]) >= swap_at;
      const double parsed_high = volatile_bar ? lows[i] : highs[i];
      const double parsed_low = volatile_bar ? highs[i] : lows[i];
      const double candidate = bias == XSPARK_SIGNAL_SELL ? parsed_high : parsed_low;

      const bool better = chosen < 0 ||
                          (bias == XSPARK_SIGNAL_SELL ? candidate > best : candidate < best);
      if(better)
      {
         chosen = i;
         best = candidate;
      }
   }

   if(chosen < 0)
      return;

   const bool volatile_chosen = swap_at > 0.0 && (highs[chosen] - lows[chosen]) >= swap_at;
   const double parsed_high = volatile_chosen ? lows[chosen] : highs[chosen];
   const double parsed_low = volatile_chosen ? highs[chosen] : lows[chosen];

   XSparkSmcBlock block;
   XSparkSmcResetBlock(block);
   // DEPARTURE. A swapped pair leaves the published box drawn upside down, which
   // is harmless on a chart and meaningless as a zone. The ordered pair is taken
   // so a block always has a top above its bottom.
   block.high = MathMax(parsed_high, parsed_low);
   block.low = MathMin(parsed_high, parsed_low);
   block.time = times[chosen];
   block.index = chosen;
   block.bias = bias;
   block.internal = internal;
   block.choch = choch;
   block.break_index = break_index;
   block.break_time = times[break_index];
   block.pivot_index = pivot_index;
   block.broken_level = broken_level;
   block.swing_trend_at_break = state.swing_trend;

   if(internal)
      XSparkSmcPushBlock(state.internal_blocks, block);
   else
      XSparkSmcPushBlock(state.swing_blocks, block);
}

// ---------------------------------------------------------------------------
// One bar of structure breaking.
// ---------------------------------------------------------------------------
//
// Pine's displayStructure(), for one of the two structures. A close through the
// pivot that has not already been broken flips that structure's bias, marks the
// pivot crossed, and stores the order block the leg left behind. Whether it is
// called a break of structure or a change of character is only a question of
// which way the bias pointed beforehand.
void XSparkSmcStepBreak(const double &highs[], const double &lows[], const double &closes[],
                        const datetime &times[], const int index,
                        const XSparkSmcSnapshot &previous, const bool internal,
                        const XSparkSmcConfig &config, XSparkSmcState &state)
{
   // Pine's internal extraCondition: an internal pivot sitting at exactly the
   // swing pivot's level is the same event seen twice, and only one of them is
   // internal structure.
   const bool distinct_high = !internal || !state.swing_high.valid ||
                              state.internal_high.level != state.swing_high.level;
   const bool distinct_low = !internal || !state.swing_low.valid ||
                             state.internal_low.level != state.swing_low.level;

   const double high_level = internal ? state.internal_high.level : state.swing_high.level;
   const bool high_valid = internal ? state.internal_high.valid : state.swing_high.valid;
   const bool high_crossed = internal ? state.internal_high.crossed : state.swing_high.crossed;
   const int high_pivot_index = internal ? state.internal_high.index : state.swing_high.index;
   const double previous_high = internal ? previous.internal_high : previous.swing_high;
   const bool previous_high_valid = internal ? previous.internal_high_valid : previous.swing_high_valid;

   if(high_valid && previous_high_valid && !high_crossed && distinct_high &&
      previous.close <= previous_high && closes[index] > high_level)
   {
      const int bias_before = internal ? state.internal_trend : state.swing_trend;
      const bool choch = bias_before == XSPARK_SIGNAL_SELL;

      if(internal)
      {
         state.internal_high.crossed = true;
         state.internal_trend = XSPARK_SIGNAL_BUY;
      }
      else
      {
         state.swing_high.crossed = true;
         state.swing_trend = XSPARK_SIGNAL_BUY;
      }

      XSparkSmcStoreBlock(highs, lows, times, index, high_pivot_index, XSPARK_SIGNAL_BUY,
                          internal, choch, high_level, config, state);
   }

   const double low_level = internal ? state.internal_low.level : state.swing_low.level;
   const bool low_valid = internal ? state.internal_low.valid : state.swing_low.valid;
   const bool low_crossed = internal ? state.internal_low.crossed : state.swing_low.crossed;
   const int low_pivot_index = internal ? state.internal_low.index : state.swing_low.index;
   const double previous_low = internal ? previous.internal_low : previous.swing_low;
   const bool previous_low_valid = internal ? previous.internal_low_valid : previous.swing_low_valid;

   if(low_valid && previous_low_valid && !low_crossed && distinct_low &&
      previous.close >= previous_low && closes[index] < low_level)
   {
      const int bias_before = internal ? state.internal_trend : state.swing_trend;
      const bool choch = bias_before == XSPARK_SIGNAL_BUY;

      if(internal)
      {
         state.internal_low.crossed = true;
         state.internal_trend = XSPARK_SIGNAL_SELL;
      }
      else
      {
         state.swing_low.crossed = true;
         state.swing_trend = XSPARK_SIGNAL_SELL;
      }

      XSparkSmcStoreBlock(highs, lows, times, index, low_pivot_index, XSPARK_SIGNAL_SELL,
                          internal, choch, low_level, config, state);
   }
}

// ---------------------------------------------------------------------------
// Fair value gaps.
// ---------------------------------------------------------------------------
//
// Three bars whose outer two do not overlap: the middle bar moved far enough
// fast enough that part of its range never traded. Pine additionally requires
// the middle bar's body to be larger than a threshold, which on the automatic
// setting is twice the mean absolute body size - so a gap left by a bar that
// barely moved does not count as displacement.
void XSparkSmcStepGap(const double &opens[], const double &highs[], const double &lows[], const double &closes[],
                      const datetime &times[], const int index, const double threshold, XSparkSmcState &state)
{
   const int size = ArraySize(highs);
   if(index < 0 || index + 2 >= size)
      return;

   const double middle_open = opens[index + 1];
   const double middle_close = closes[index + 1];
   if(!MathIsValidNumber(middle_open) || !MathIsValidNumber(middle_close) || middle_open <= 0.0)
      return;

   const double delta = (middle_close - middle_open) / (middle_open * 100.0);
   const double oldest_high = highs[index + 2];
   const double oldest_low = lows[index + 2];

   XSparkSmcGap gap;
   XSparkSmcResetGap(gap);

   if(lows[index] > oldest_high && middle_close > oldest_high && delta > threshold)
   {
      gap.top = lows[index];
      gap.bottom = oldest_high;
      gap.bias = XSPARK_SIGNAL_BUY;
      gap.index = index;
      gap.time = times[index];
      XSparkSmcPushGap(state.gaps, gap);
      return;
   }

   if(highs[index] < oldest_low && middle_close < oldest_low && -delta > threshold)
   {
      gap.top = oldest_low;
      gap.bottom = highs[index];
      gap.bias = XSPARK_SIGNAL_SELL;
      gap.index = index;
      gap.time = times[index];
      XSparkSmcPushGap(state.gaps, gap);
   }
}

// ---------------------------------------------------------------------------
// The replay.
// ---------------------------------------------------------------------------
//
// Walks the window oldest to newest in the indicator's own per-bar order, which
// is load-bearing: the trailing extremes are extended BEFORE a new pivot can
// re-anchor them, structures are read BEFORE breaks are tested against them,
// and blocks are mitigated AFTER the bar that created them - so a block the
// market immediately traded through never survives its own bar.
bool XSparkSmcReplay(const double &opens[], const double &highs[], const double &lows[], const double &closes[],
                     const datetime &times[], const int count,
                     const XSparkSmcConfig &config, XSparkSmcState &state, string &reason)
{
   XSparkSmcResetState(state);
   reason = "";

   string config_reason = "";
   if(!XSparkSmcConfigUsable(config, config_reason))
   {
      reason = config_reason;
      return false;
   }

   const int size = ArraySize(highs);
   if(size != ArraySize(lows) || size != ArraySize(opens) || size != ArraySize(closes) ||
      size != ArraySize(times))
   {
      reason = "The bar arrays are not the same length.";
      return false;
   }

   if(count < 2 || count > size)
   {
      reason = "The replay window is not a usable number of bars.";
      return false;
   }

   const int start = count - 1 - config.swing_length;
   if(start < 2)
   {
      reason = StringFormat("A %d-bar swing structure needs more than %d closed bars to replay.",
                            config.swing_length, count);
      return false;
   }

   state.measure = XSparkSmcMeanRange(highs, lows, closes, count);
   if(!MathIsValidNumber(state.measure) || state.measure <= 0.0)
   {
      reason = "The window's typical candle size is not usable, so the structure cannot be parsed.";
      return false;
   }

   const double gap_threshold = config.gap_auto_threshold
                                ? XSparkSmcMeanBodyDelta(opens, closes, count) * 2.0
                                : 0.0;
   const double equal_tolerance = config.equal_threshold * state.measure;

   int swing_leg = 0;
   int internal_leg = 0;
   int equal_leg = 0;
   bool first_bar = true;

   for(int i = start; i >= 0; i--)
   {
      XSparkSmcSnapshot previous;
      previous.close = closes[i + 1];
      previous.internal_high = state.internal_high.level;
      previous.internal_low = state.internal_low.level;
      previous.swing_high = state.swing_high.level;
      previous.swing_low = state.swing_low.level;
      previous.internal_high_valid = state.internal_high.valid;
      previous.internal_low_valid = state.internal_low.valid;
      previous.swing_high_valid = state.swing_high.valid;
      previous.swing_low_valid = state.swing_low.valid;

      // 1. The trailing extremes run first, so this bar extends the range the
      //    premium/discount reading is taken against before any new pivot can
      //    reset it.
      if(state.trailing_top_valid && highs[i] >= state.trailing_top)
      {
         state.trailing_top = highs[i];
         state.trailing_top_time = times[i];
      }
      if(state.trailing_bottom_valid && lows[i] <= state.trailing_bottom)
      {
         state.trailing_bottom = lows[i];
         state.trailing_bottom_time = times[i];
      }

      // 2. Imbalances this bar traded through are gone before it can leave one.
      XSparkSmcMitigateGaps(state.gaps, highs[i], lows[i]);

      // 3. Swing structure.
      XSparkSmcLegEvent swing_event;
      XSparkSmcStepLeg(highs, lows, i, config.swing_length, first_bar, swing_leg, swing_event);
      if(swing_event.new_pivot)
      {
         if(swing_event.pivot_high)
         {
            state.swing_high.last_level = state.swing_high.level;
            state.swing_high.level = swing_event.level;
            state.swing_high.crossed = false;
            state.swing_high.valid = true;
            state.swing_high.index = swing_event.index;
            state.swing_high.time = times[swing_event.index];
            state.trailing_top = swing_event.level;
            state.trailing_top_time = times[swing_event.index];
            state.trailing_top_valid = true;
         }
         else
         {
            state.swing_low.last_level = state.swing_low.level;
            state.swing_low.level = swing_event.level;
            state.swing_low.crossed = false;
            state.swing_low.valid = true;
            state.swing_low.index = swing_event.index;
            state.swing_low.time = times[swing_event.index];
            state.trailing_bottom = swing_event.level;
            state.trailing_bottom_time = times[swing_event.index];
            state.trailing_bottom_valid = true;
         }

         state.trailing_valid = state.trailing_top_valid && state.trailing_bottom_valid;
      }

      // 4. Internal structure.
      XSparkSmcLegEvent internal_event;
      XSparkSmcStepLeg(highs, lows, i, config.internal_length, first_bar, internal_leg, internal_event);
      if(internal_event.new_pivot)
      {
         if(internal_event.pivot_high)
         {
            state.internal_high.last_level = state.internal_high.level;
            state.internal_high.level = internal_event.level;
            state.internal_high.crossed = false;
            state.internal_high.valid = true;
            state.internal_high.index = internal_event.index;
            state.internal_high.time = times[internal_event.index];
         }
         else
         {
            state.internal_low.last_level = state.internal_low.level;
            state.internal_low.level = internal_event.level;
            state.internal_low.crossed = false;
            state.internal_low.valid = true;
            state.internal_low.index = internal_event.index;
            state.internal_low.time = times[internal_event.index];
         }
      }

      // 5. Equal highs and lows, on their own short structure. The comparison
      //    is made against the PREVIOUS equal pivot, before it is replaced.
      XSparkSmcLegEvent equal_event;
      XSparkSmcStepLeg(highs, lows, i, config.equal_length, first_bar, equal_leg, equal_event);
      if(equal_event.new_pivot)
      {
         if(equal_event.pivot_high)
         {
            if(state.equal_high.valid &&
               MathAbs(state.equal_high.level - equal_event.level) < equal_tolerance)
            {
               state.equal_high_found = true;
               state.equal_high_level = equal_event.level;
               state.equal_high_time = times[equal_event.index];
            }

            state.equal_high.last_level = state.equal_high.level;
            state.equal_high.level = equal_event.level;
            state.equal_high.crossed = false;
            state.equal_high.valid = true;
            state.equal_high.index = equal_event.index;
            state.equal_high.time = times[equal_event.index];
         }
         else
         {
            if(state.equal_low.valid &&
               MathAbs(state.equal_low.level - equal_event.level) < equal_tolerance)
            {
               state.equal_low_found = true;
               state.equal_low_level = equal_event.level;
               state.equal_low_time = times[equal_event.index];
            }

            state.equal_low.last_level = state.equal_low.level;
            state.equal_low.level = equal_event.level;
            state.equal_low.crossed = false;
            state.equal_low.valid = true;
            state.equal_low.index = equal_event.index;
            state.equal_low.time = times[equal_event.index];
         }
      }

      // 6. Breaks, internal before swing, exactly as the indicator orders them.
      XSparkSmcStepBreak(highs, lows, closes, times, i, previous, true, config, state);
      XSparkSmcStepBreak(highs, lows, closes, times, i, previous, false, config, state);

      // 7. Mitigation runs after the break, so a block this bar created and
      //    this bar traded through does not survive to be entered.
      const double bearish_source = config.mitigation_uses_close ? closes[i] : highs[i];
      const double bullish_source = config.mitigation_uses_close ? closes[i] : lows[i];
      XSparkSmcMitigateBlocks(state.internal_blocks, bearish_source, bullish_source);
      XSparkSmcMitigateBlocks(state.swing_blocks, bearish_source, bullish_source);

      // 8. And the bar's own imbalance, which needs its two predecessors.
      XSparkSmcStepGap(opens, highs, lows, closes, times, i, gap_threshold, state);

      state.bars_used++;
      first_bar = false;
   }

   return true;
}

// ---------------------------------------------------------------------------
// The trade the indicator does not contain.
// ---------------------------------------------------------------------------
//
// Everything below this line is a DEPARTURE by definition: the source draws and
// alerts, it does not trade. What it supplies is the vocabulary - a break, a
// block, a range, a draw - and the rule here is assembled out of that and
// nothing else. No moving average, no oscillator, no session filter.

// Every place the sequence can stop, in the order it is checked. The EA counts
// these per broker day, so a run that takes no trades says WHICH condition the
// market never produced instead of going silent.
struct XSparkSmcVerdicts
{
   string structure;  // "NO STRUCTURE", "BLOCK EXPIRED", "STRUCTURE FLIPPED",
                      // "AGAINST SWING", "WRONG BREAK TYPE", "BOS", "CHOCH"
   string block;      // "ORDER BLOCK", "BLOCK TOO THIN"
   string imbalance;  // "IMBALANCE", "NO IMBALANCE", "OFF"
   string location;   // "DISCOUNT", "PREMIUM", "WRONG HALF", "RANGE UNKNOWN", "OFF"
   string liquidity;  // "DRAW FOUND", "NO DRAW", "DRAW TOO CLOSE", "DRAW TOO FAR"
};

void XSparkSmcResetVerdicts(XSparkSmcVerdicts &verdicts)
{
   verdicts.structure = "";
   verdicts.block = "";
   verdicts.imbalance = "";
   verdicts.location = "";
   verdicts.liquidity = "";
}

// One bar's answer, before risk and cost have a say.
struct XSparkSmcSetup
{
   EXSparkSignalDirection direction;
   double   entry_limit;     // the block's mean threshold; the worst price accepted
   double   block_high;
   double   block_low;
   datetime block_time;
   datetime break_time;      // the structure break; this setup's identity
   double   broken_level;
   double   stop;
   double   target;          // the draw on liquidity, as a price
   double   target_r;        // what that draw implies against the stop; an output
   double   range_position;  // where the entry sits in the dealing range, 0 to 1
   int      block_age_bars;
   bool     choch;
   bool     internal;
   bool     equal_draw;      // the draw sits on a pool of equal highs or lows
   string   reason;
};

void XSparkSmcResetSetup(XSparkSmcSetup &setup)
{
   setup.direction = XSPARK_SIGNAL_NONE;
   setup.entry_limit = 0.0;
   setup.block_high = 0.0;
   setup.block_low = 0.0;
   setup.block_time = 0;
   setup.break_time = 0;
   setup.broken_level = 0.0;
   setup.stop = 0.0;
   setup.target = 0.0;
   setup.target_r = 0.0;
   setup.range_position = 0.0;
   setup.block_age_bars = 0;
   setup.choch = false;
   setup.internal = false;
   setup.equal_draw = false;
   setup.reason = "";
}

// Reads one block out of whichever ring the structure selection points at.
// A copy rather than a reference because MQL5 has neither references to array
// elements nor a conditional that yields one.
bool XSparkSmcBlockAt(const XSparkSmcState &state, const bool internal, const int index, XSparkSmcBlock &block)
{
   XSparkSmcResetBlock(block);

   if(index < 0)
      return false;

   if(internal)
   {
      if(index >= state.internal_blocks.count)
         return false;
      block = state.internal_blocks.items[index];
      return true;
   }

   if(index >= state.swing_blocks.count)
      return false;

   block = state.swing_blocks.items[index];
   return true;
}

// Where a price sits in the dealing range, 0 at the low and 1 at the high.
bool XSparkSmcRangePosition(const double price, const double range_low, const double range_high, double &position)
{
   position = 0.0;

   if(!MathIsValidNumber(price) || !MathIsValidNumber(range_low) || !MathIsValidNumber(range_high))
      return false;
   if(range_high <= range_low)
      return false;

   position = (price - range_low) / (range_high - range_low);
   return true;
}

// The block's mean threshold: the midpoint of the zone, and the price this
// model waits for. Not the near edge, which fills more often at a worse price,
// and not the far edge, which is a better price that frequently never trades.
bool XSparkSmcMeanThreshold(const double block_low, const double block_high, double &mean)
{
   mean = 0.0;

   if(!MathIsValidNumber(block_low) || !MathIsValidNumber(block_high) || block_high <= block_low)
      return false;

   mean = block_low + (block_high - block_low) / 2.0;
   return true;
}

// Whether the leg that broke structure also left an imbalance that price has
// not yet traded back through. The gap must be no older than the leg's origin -
// an imbalance from some earlier move is not evidence about this one.
bool XSparkSmcLegLeftGap(const XSparkSmcState &state, const XSparkSmcBlock &block)
{
   for(int i = 0; i < state.gaps.count; i++)
   {
      if(state.gaps.items[i].bias != block.bias)
         continue;
      if(state.gaps.items[i].index < 0 || state.gaps.items[i].index > block.pivot_index)
         continue;
      return true;
   }

   return false;
}

// The whole rule, on the close of the newest bar in the replayed window.
//
// THE SEQUENCE:
//   1. a structure break the selected structure still agrees with
//   2. the order block that break left, unmitigated and thicker than the cost
//   3. optionally, an imbalance the same leg left
//   4. the entry is the block's mean threshold, as a LIMIT, in discount for a
//      buy and premium for a sell
//   5. the stop sits beyond the block's far edge - the level whose breach
//      deletes the block
//   6. the target is the draw on liquidity: the trailing extreme the indicator
//      labels Strong or Weak
//
// The setup is not required to have appeared on this bar. A block stays
// enterable while it is unmitigated, in date, and the structure still points
// its way, which is what lets a LIMIT entry be reached at all - the retracement
// almost never happens on the bar that broke structure. Because the whole state
// is replayed from the window every bar, that patience costs no stored state.
bool XSparkSmcEvaluate(const XSparkSmcState &state, const XSparkSmcConfig &config,
                       const double point_size, XSparkSmcSetup &setup, XSparkSmcVerdicts &verdicts)
{
   XSparkSmcResetSetup(setup);
   XSparkSmcResetVerdicts(verdicts);

   string config_reason = "";
   if(!XSparkSmcConfigUsable(config, config_reason))
   {
      setup.reason = config_reason;
      return false;
   }

   if(state.bars_used <= 0)
   {
      setup.reason = "The structure has not been replayed, so there is nothing to read.";
      return false;
   }

   if(!MathIsValidNumber(point_size) || point_size <= 0.0)
   {
      setup.reason = "The instrument's point size is unavailable.";
      return false;
   }

   // 1 and 2. The newest block whose break the structure still agrees with.
   const bool use_internal = config.structure_mode != XSPARK_SMC_SWING_ONLY;

   bool saw_block = false;
   bool saw_fresh = false;
   bool saw_live = false;
   bool saw_aligned = false;
   bool saw_break_type = false;
   bool found = false;
   XSparkSmcBlock chosen;
   XSparkSmcResetBlock(chosen);
   // Kept so a block refused for its width still reports which break left it.
   XSparkSmcBlock thin;
   XSparkSmcResetBlock(thin);

   for(int i = 0; i < XSPARK_SMC_MAX_BLOCKS; i++)
   {
      XSparkSmcBlock block;
      if(!XSparkSmcBlockAt(state, use_internal, i, block))
         break;

      saw_block = true;

      // break_index is a series index, so it IS the block's age in bars.
      if(block.break_index > config.max_block_age_bars)
         continue;
      saw_fresh = true;

      const int live_trend = block.internal ? state.internal_trend : state.swing_trend;
      if(live_trend != block.bias)
         continue;
      saw_live = true;

      if(config.structure_mode == XSPARK_SMC_INTERNAL_WITH_SWING && state.swing_trend != block.bias)
         continue;
      saw_aligned = true;

      // The indicator's All / BOS / CHoCH filter, doing real work: a change of
      // character is the first break against the prior bias and a break of
      // structure is one that extends it, so this is the difference between
      // trading reversals and trading continuations.
      if((config.break_type == XSPARK_SMC_BREAK_REVERSAL && !block.choch) ||
         (config.break_type == XSPARK_SMC_BREAK_CONTINUATION && block.choch))
         continue;
      saw_break_type = true;

      if(block.high - block.low < config.min_block_price)
      {
         if(thin.bias == XSPARK_SIGNAL_NONE)
            thin = block;
         continue;
      }

      chosen = block;
      found = true;
      break;
   }

   if(!found)
   {
      if(!saw_block)
      {
         verdicts.structure = "NO STRUCTURE";
         setup.reason = "No structure break in the window left an order block.";
      }
      else if(!saw_fresh)
      {
         verdicts.structure = "BLOCK EXPIRED";
         setup.reason = StringFormat("Every order block is older than the %d bars this model will still enter.",
                                     config.max_block_age_bars);
      }
      else if(!saw_live)
      {
         verdicts.structure = "STRUCTURE FLIPPED";
         setup.reason = "Structure has since broken the other way, so the reason for the block is gone.";
      }
      else if(!saw_aligned)
      {
         verdicts.structure = "AGAINST SWING";
         setup.reason = "The internal break points against the swing bias.";
      }
      else if(!saw_break_type)
      {
         verdicts.structure = "WRONG BREAK TYPE";
         setup.reason = StringFormat("A block is live but this bot is taking %s.",
                                     XSparkSmcBreakTypeName(config.break_type));
      }
      else
      {
         verdicts.structure = thin.choch ? "CHOCH" : "BOS";
         verdicts.block = "BLOCK TOO THIN";
         setup.reason = "The order block is thinner than a round trip costs, so its midpoint is inside the spread.";
      }
      return false;
   }

   verdicts.structure = chosen.choch ? "CHOCH" : "BOS";
   verdicts.block = "ORDER BLOCK";

   const EXSparkSignalDirection direction = chosen.bias == XSPARK_SIGNAL_SELL ? XSPARK_SIGNAL_SELL
                                                                              : XSPARK_SIGNAL_BUY;

   // 3. The imbalance, when the stricter confluence is selected.
   if(config.require_gap)
   {
      if(!XSparkSmcLegLeftGap(state, chosen))
      {
         verdicts.imbalance = "NO IMBALANCE";
         setup.reason = "The leg that broke structure left no price gap, so it did not displace.";
         return false;
      }
      verdicts.imbalance = "IMBALANCE";
   }
   else
   {
      verdicts.imbalance = "OFF";
   }

   // 4. The entry, and where it sits in the dealing range.
   double entry = 0.0;
   if(!XSparkSmcMeanThreshold(chosen.low, chosen.high, entry))
   {
      setup.reason = "The order block has no usable midpoint.";
      return false;
   }

   if(!state.trailing_valid)
   {
      verdicts.location = "RANGE UNKNOWN";
      setup.reason = "The window has not produced both a swing high and a swing low, so there is no dealing range to read.";
      return false;
   }

   double position = 0.0;
   if(!XSparkSmcRangePosition(entry, state.trailing_bottom, state.trailing_top, position))
   {
      verdicts.location = "RANGE UNKNOWN";
      setup.reason = "The dealing range is not a usable interval.";
      return false;
   }

   if(config.use_premium_discount)
   {
      const bool correct_half = direction == XSPARK_SIGNAL_SELL ? position >= 0.5 : position <= 0.5;
      if(!correct_half)
      {
         verdicts.location = "WRONG HALF";
         setup.reason = StringFormat("The entry at %.5f sits at %.0f%% of the dealing range, the wrong half for a %s.",
                                     entry, position * 100.0,
                                     direction == XSPARK_SIGNAL_SELL ? "sell" : "buy");
         return false;
      }
      verdicts.location = direction == XSPARK_SIGNAL_SELL ? "PREMIUM" : "DISCOUNT";
   }
   else
   {
      verdicts.location = "OFF";
   }

   // 5. The stop, beyond the far edge of the block.
   const double buffer = config.stop_buffer_points * point_size;
   const double stop = direction == XSPARK_SIGNAL_SELL ? chosen.high + buffer : chosen.low - buffer;
   const double stop_distance = direction == XSPARK_SIGNAL_SELL ? stop - entry : entry - stop;

   if(stop_distance <= 0.0 || stop <= 0.0)
   {
      setup.reason = "The stop is on the wrong side of the entry; the block is not usable.";
      return false;
   }

   // 6. The draw on liquidity: the trailing extreme on the other side of the
   //    trade. The indicator labels it Strong when the swing bias says it has
   //    held and Weak when the bias says it is likely to be taken - and under
   //    the default structure selection a buy is only ever taken toward a Weak
   //    High, which is the one the market is being pulled to.
   const double target = direction == XSPARK_SIGNAL_SELL ? state.trailing_bottom : state.trailing_top;
   const double reward = direction == XSPARK_SIGNAL_SELL ? entry - target : target - entry;

   if(!MathIsValidNumber(target) || target <= 0.0 || reward <= 0.0)
   {
      verdicts.liquidity = "NO DRAW";
      setup.reason = "The opposing extreme is not beyond the entry, so the trade has nowhere to go.";
      return false;
   }

   const double implied_r = reward / stop_distance;

   if(implied_r < config.min_target_r)
   {
      verdicts.liquidity = "DRAW TOO CLOSE";
      setup.reason = StringFormat("The draw at %.5f is only %.2f times the stop away; at least %.2f is required.",
                                  target, implied_r, config.min_target_r);
      return false;
   }

   if(implied_r > config.max_target_r)
   {
      verdicts.liquidity = "DRAW TOO FAR";
      setup.reason = StringFormat("The draw at %.5f is %.2f times the stop away, beyond the %.2f bound; that is a different trade.",
                                  target, implied_r, config.max_target_r);
      return false;
   }
   verdicts.liquidity = "DRAW FOUND";

   const double equal_tolerance = config.equal_threshold * state.measure;
   const bool equal_draw = direction == XSPARK_SIGNAL_SELL
                           ? (state.equal_low_found && MathAbs(state.equal_low_level - target) <= equal_tolerance)
                           : (state.equal_high_found && MathAbs(state.equal_high_level - target) <= equal_tolerance);

   setup.direction = direction;
   setup.entry_limit = entry;
   setup.block_high = chosen.high;
   setup.block_low = chosen.low;
   setup.block_time = chosen.time;
   setup.break_time = chosen.break_time;
   setup.broken_level = chosen.broken_level;
   setup.stop = stop;
   setup.target = target;
   setup.target_r = implied_r;
   setup.range_position = position;
   setup.block_age_bars = chosen.break_index;
   setup.choch = chosen.choch;
   setup.internal = chosen.internal;
   setup.equal_draw = equal_draw;

   setup.reason = StringFormat("%s: %s %s at %.5f %d bars ago, %s order block %.5f-%.5f, entry at its midpoint %.5f (%.0f%% of the dealing range), stop %.5f, draw %.5f%s at %.2fR.",
                               direction == XSPARK_SIGNAL_SELL ? "SELL" : "BUY",
                               chosen.internal ? "internal" : "swing",
                               chosen.choch ? "CHoCH" : "BOS",
                               chosen.broken_level,
                               chosen.break_index,
                               direction == XSPARK_SIGNAL_SELL ? "bearish" : "bullish",
                               chosen.low, chosen.high,
                               entry, position * 100.0, stop, target,
                               equal_draw ? " on equal highs/lows" : "",
                               implied_r);
   return true;
}

// ---------------------------------------------------------------------------
// Cost, and the stop the EA actually sends.
// ---------------------------------------------------------------------------
//
// Declared here rather than reused from another strategy: a cost rule that
// reads through another strategy's constant changes silently when that strategy
// is retuned (AGENTS.md rule 43). The arithmetic is the same arithmetic because
// the instrument is the same instrument.

// Spread plus commission, both ways, expressed as a price distance.
bool XSparkSmcRoundTripCost(const double spread,
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

// The stop the EA sends, measured from the live quote rather than from the
// price the model measured.
//
// The model already put the stop beyond the block's far edge, which is the
// invalidation. This applies the three things only the EA knows: how far the
// market has moved since the signal bar closed, the floor the round-trip cost
// implies, and the ceiling past which the trade is too wide to be this model's.
//
// A stop is only ever WIDENED, never tightened: tightening it would move the
// stop inside the zone whose breach says the setup failed.
bool XSparkSmcStop(const EXSparkSignalDirection direction,
                   const double entry_reference,
                   const double model_stop,
                   const double atr,
                   const double round_trip_cost,
                   const XSparkSmcConfig &config,
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
   if(!XSparkSmcConfigUsable(config, config_reason))
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
      // wide is a different problem from one refused because the block is far
      // away, and only the operator can fix the first.
      reason = cost_binding
               ? StringFormat("COST: the round-trip cost %.8f is %.1f%% of the widest stop this chart period allows (%.8f); at most %.1f%% is permitted. A longer chart period, a tighter-spread account, or a lower commission fixes this.",
                              round_trip_cost, round_trip_cost / ceiling * 100.0, ceiling, config.max_cost_share_pct)
               : StringFormat("The stop would sit %.2f typical candles from the entry, over the %.2f ceiling; the order block is too far to trade from here.",
                              used / atr, config.max_stop_atr);
      return false;
   }

   distance = used;
   stop = direction == XSPARK_SIGNAL_BUY ? entry_reference - used : entry_reference + used;
   return true;
}

// The two win rates every target implies. Break-even is what the geometry alone
// demands; no-edge is what a trade with no predictive content actually shows
// once the round-trip cost is paid. The gap between them is what the entry has
// to be worth before any of this is a strategy rather than a lottery.
double XSparkSmcBreakEvenWinRate(const double target_r)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0)
      return 0.0;
   return 1.0 / (1.0 + target_r);
}

double XSparkSmcNoEdgeWinRate(const double target_r, const double cost_share_pct)
{
   if(!MathIsValidNumber(target_r) || target_r <= 0.0 ||
      !MathIsValidNumber(cost_share_pct) || cost_share_pct < 0.0 || cost_share_pct >= 100.0)
      return 0.0;

   return (1.0 - cost_share_pct / 100.0) / (1.0 + target_r);
}

// The 95% Wilson lower bound on a win rate. Used rather than the plain
// proportion because the question a tester pass answers is not "was the win
// rate above break-even" but "is the sample large enough to say so".
#define XSPARK_SMC_WILSON_Z_SCORE 1.96

bool XSparkSmcWilsonLowerBound(const int wins, const int outcomes, double &lower)
{
   lower = 0.0;

   if(outcomes <= 0 || wins < 0 || wins > outcomes)
      return false;

   const double n = (double)outcomes;
   const double p = (double)wins / n;
   const double z = XSPARK_SMC_WILSON_Z_SCORE;
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
// This model's claim is about the leg that follows a structure break, so a
// position still open long after that leg should have resolved is no longer in
// the trade that was taken. Two bounds, whichever comes first: a count of bars,
// and a wall-clock ceiling so a high chart period cannot turn the bar count
// into a week.
//
// Wider than a kill-zone model's, deliberately: this entry is a LIMIT into a
// retracement and the move it is waiting for is measured in swings rather than
// in minutes.

#define XSPARK_SMC_MAX_HOLD_BARS 96
#define XSPARK_SMC_MAX_HOLD_SECONDS 172800

int XSparkSmcMaxHoldSeconds(const int period_seconds)
{
   if(period_seconds <= 0)
      return 0;

   const long by_bars = (long)XSPARK_SMC_MAX_HOLD_BARS * (long)period_seconds;

   if(by_bars > (long)XSPARK_SMC_MAX_HOLD_SECONDS)
      return XSPARK_SMC_MAX_HOLD_SECONDS;

   return (int)by_bars;
}

// ---------------------------------------------------------------------------
// The weekend close.
// ---------------------------------------------------------------------------
//
// A backstop, not part of the method. It exists because a position carried
// across a weekend gap is the one loss no stop can bound. Declared here rather
// than reused from another strategy so retuning that strategy cannot move this
// one's exits (AGENTS.md rule 43).

#define XSPARK_SMC_WEEKEND_CLOSE_HOUR 20
#define XSPARK_SMC_WEEKEND_CLOSE_MINUTE 45
#define XSPARK_SMC_WEEKEND_CLOSE_LEAD_MINUTES 15
#define XSPARK_SMC_SECONDS_PER_DAY 86400

bool XSparkSmcWeekendClose(const bool trades_at_weekend,
                           const bool friday_session_known,
                           const int friday_end_seconds,
                           bool &use_weekend_close,
                           int &close_hour,
                           int &close_minute,
                           string &reason)
{
   use_weekend_close = true;
   close_hour = XSPARK_SMC_WEEKEND_CLOSE_HOUR;
   close_minute = XSPARK_SMC_WEEKEND_CLOSE_MINUTE;
   reason = "";

   // A market that trades through the weekend has no gap to protect against, so
   // flattening for it would close a position for no reason at all.
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
                       friday_end_seconds <= XSPARK_SMC_SECONDS_PER_DAY;

   if(!usable)
   {
      reason = StringFormat("The broker did not report a usable Friday session, so trades are closed at %02d:%02d on its clock.",
                            close_hour, close_minute);
      return true;
   }

   const int end_minutes = friday_end_seconds >= XSPARK_SMC_SECONDS_PER_DAY ? 1440
                                                                            : friday_end_seconds / 60;
   int flatten_minutes = end_minutes - XSPARK_SMC_WEEKEND_CLOSE_LEAD_MINUTES;

   // A session ending inside the lead time would push the flatten into the
   // previous day, which the manager cannot express; closing as the day opens
   // is the honest reading and still the safe direction.
   if(flatten_minutes < 0)
      flatten_minutes = 0;

   close_hour = flatten_minutes / 60;
   close_minute = flatten_minutes % 60;

   reason = StringFormat("This market's Friday session ends at %02d:%02d, so trades are closed at %02d:%02d on the broker's clock.",
                         end_minutes / 60, end_minutes % 60, close_hour, close_minute);
   return true;
}

// ---------------------------------------------------------------------------
// The strategy object.
// ---------------------------------------------------------------------------
//
// Replays the indicator over the shared cache's structure window, runs the pure
// model above, and fills the same XSparkSignal every other strategy fills. It
// creates signals and nothing else: no order call, no broker state, no exposure
// decision (AGENTS.md rules 6-8). The EA bounds the stop against the live quote
// and the cost floor, and RiskManager and ExecutionEngine decide whether
// anything is sent.
//
// Like the ICT model and unlike the candle strategies, the signal carries an
// entry LIMIT: this model does not enter on the bar that broke structure, it
// waits for price to come back to the block, and execution refuses a fill
// beyond the midpoint rather than chasing.

// The score every SMC signal carries. The model is a sequence that either
// completed or did not, so there is nothing to grade: a fixed score keeps the
// shared report readable without inventing a confidence.
#define XSPARK_SMC_SIGNAL_SCORE 5.0

class CXSparkSmartMoney : public IXSparkStrategy
{
private:
   XSparkSmcConfig m_config;
   XSparkSmcState  m_state;
   string m_symbol;
   bool   m_initialized;
   string m_last_reason;

public:
   CXSparkSmartMoney()
   {
      XSparkSmcDefaultConfig(m_config);
      XSparkSmcResetState(m_state);
      m_symbol = "";
      m_initialized = false;
      m_last_reason = "The Smart Money strategy is not initialized.";
   }

   void Configure(const XSparkSmcConfig &config)
   {
      m_config = config;
   }

   // The thinnest order block worth entering, handed down by the EA from the
   // round-trip cost. A zone narrower than the spread is not a zone.
   void SetMinimumBlock(const double min_block_price)
   {
      m_config.min_block_price = min_block_price;
   }

   // No TargetRewardRatio(): the reward ratio is not a property of this
   // strategy, it is whatever the draw on liquidity implies on the setup that
   // was found. Each signal carries its own.

   bool Initialize(const string symbol)
   {
      m_initialized = false;
      m_symbol = "";
      XSparkSmcResetState(m_state);

      if(symbol == "")
      {
         m_last_reason = "The Smart Money strategy needs a symbol.";
         return false;
      }

      string reason = "";
      if(!XSparkSmcConfigUsable(m_config, reason))
      {
         m_last_reason = reason;
         return false;
      }

      // Refused here rather than at the first signal, because a window too
      // short for the swing structure does not fail loudly - it just never
      // produces a swing pivot, which reads as a quiet market.
      const int required = XSparkSmcRequiredBars(m_config);
      if(required >= XSPARK_SCOREBOT_STRUCTURE_BASE_BARS)
      {
         m_last_reason = StringFormat("The structure needs %d bars but only %d are cached.",
                                      required, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
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
      XSparkSmcResetState(m_state);
      m_last_reason = "The Smart Money strategy is not initialized.";
   }

   bool Evaluate(CXSparkIndicatorCache &cache,
                 XSparkSignal &signal,
                 XSparkScoreBotReport &report)
   {
      XSparkResetSignal(signal);
      XSparkResetScoreBotReport(report);
      report.pattern_mode = "SMART MONEY";
      report.entry_location = "ORDER BLOCK";
      report.htf_verdict = "OFF";
      report.pullback_verdict = "OFF";
      report.rsi_verdict = "OFF";
      report.joint_verdict = "BLOCKED";
      report.status = "SCANNING";

      if(!m_initialized)
      {
         report.block_reason = "The Smart Money strategy is not initialized.";
         m_last_reason = report.block_reason;
         return false;
      }

      if(!cache.IsValid())
      {
         report.block_reason = cache.LastReason();
         m_last_reason = report.block_reason;
         return false;
      }

      // The structure window, not the short indicator window: a 50-candle swing
      // cannot be read out of 50 candles.
      if(!cache.StructureIsValid())
      {
         report.block_reason = "The structure window is not fully loaded yet.";
         m_last_reason = report.block_reason;
         return false;
      }

      XSparkCandle bar1;
      if(!cache.BaseBar(1, bar1))
      {
         report.block_reason = "The closed signal candle is unavailable.";
         m_last_reason = report.block_reason;
         return false;
      }

      const double atr14 = cache.ATR14Base();
      const double atr50 = cache.ATR50Base();
      const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      double opens[];
      double highs[];
      double lows[];
      double closes[];
      datetime times[];
      ArrayResize(opens, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
      ArrayResize(highs, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
      ArrayResize(lows, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
      ArrayResize(closes, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
      ArrayResize(times, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);

      for(int i = 0; i < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS; i++)
      {
         XSparkCandle bar;
         if(!cache.StructureBaseBar(i + 1, bar))
         {
            report.block_reason = StringFormat("Only %d structure bars are available; the replay needs more.", i);
            m_last_reason = report.block_reason;
            return false;
         }
         opens[i] = bar.open;
         highs[i] = bar.high;
         lows[i] = bar.low;
         closes[i] = bar.close;
         times[i] = bar.time;
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

      string replay_reason = "";
      if(!XSparkSmcReplay(opens, highs, lows, closes, times, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS,
                          m_config, m_state, replay_reason))
      {
         report.block_reason = replay_reason;
         m_last_reason = replay_reason;
         return false;
      }

      XSparkSmcSetup setup;
      XSparkSmcVerdicts verdicts;

      if(!XSparkSmcEvaluate(m_state, m_config, point_size, setup, verdicts))
      {
         // The verdicts are the funnel: the EA counts them so a quiet run says
         // which condition the market never produced.
         report.htf_verdict = verdicts.structure != "" ? verdicts.structure : "NO STRUCTURE";
         report.pullback_verdict = verdicts.block != "" ? verdicts.block : "OFF";
         report.entry_location = verdicts.location != "" ? verdicts.location : "ORDER BLOCK";
         report.rsi_verdict = verdicts.liquidity != "" ? verdicts.liquidity : "OFF";
         report.joint_verdict = verdicts.imbalance != "" ? verdicts.imbalance : "BLOCKED";
         report.block_reason = setup.reason;
         m_last_reason = setup.reason;
         return false;
      }

      report.htf_verdict = verdicts.structure;
      report.pullback_verdict = verdicts.block;
      report.rsi_verdict = verdicts.liquidity;
      report.entry_location = verdicts.location;
      report.joint_verdict = verdicts.imbalance;
      report.detected_level = setup.broken_level;
      report.detected_instance = setup.break_time;
      report.dynamic_rr = setup.target_r;
      report.direction = setup.direction;
      report.scored = true;
      report.has_pattern = true;
      report.threshold_passed = true;
      report.components.pattern = XSPARK_SMC_SIGNAL_SCORE;
      report.components.raw = XSPARK_SMC_SIGNAL_SCORE;
      report.components.final_score = XSPARK_SMC_SIGNAL_SCORE;
      report.components.session_weight = 1.0;
      report.status = "SIGNAL";
      report.block_reason = "";
      report.pattern_name = StringFormat("%s %s + ORDER BLOCK %s",
                                         setup.internal ? "INTERNAL" : "SWING",
                                         setup.choch ? "CHOCH" : "BOS",
                                         setup.direction == XSPARK_SIGNAL_SELL ? "SHORT" : "LONG");

      signal.symbol = m_symbol;
      signal.direction = setup.direction;
      signal.desired_stop = setup.stop;
      // Execution derives the take-profit from the ratio and the stop distance
      // it actually gets, so the modelled target is not carried as a price.
      signal.desired_target = 0.0;
      signal.dynamic_rr = setup.target_r;
      signal.entry_limit = setup.entry_limit;
      signal.score = XSPARK_SMC_SIGNAL_SCORE;
      signal.effective_threshold = 0.0;
      signal.pattern_score = XSPARK_SMC_SIGNAL_SCORE;
      signal.session_weight = 1.0;
      signal.atr14 = atr14;
      signal.atr50 = atr50;
      // THE SETUP'S IDENTITY IS THE BREAK, not the bar being evaluated. The
      // block stays enterable for many bars, so keying the signal on the
      // current bar would let one structure break be submitted once per bar
      // until it filled; keying it on the break means one entry per break.
      signal.signal_bar_time = setup.break_time;
      signal.instance_time = setup.break_time;
      signal.pattern_name = report.pattern_name;
      signal.context = report.context;
      signal.reason = setup.reason;

      m_last_reason = signal.reason;
      return true;
   }

   // The replayed structure, for the EA's startup and journal lines.
   int SwingTrend() { return m_state.swing_trend; }
   int InternalTrend() { return m_state.internal_trend; }
   double TrailingTop() { return m_state.trailing_top; }
   double TrailingBottom() { return m_state.trailing_bottom; }
   bool TrailingValid() { return m_state.trailing_valid; }
   int LiveBlockCount() { return m_state.internal_blocks.count + m_state.swing_blocks.count; }
   int LiveGapCount() { return m_state.gaps.count; }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
