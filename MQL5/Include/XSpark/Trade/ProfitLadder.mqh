#ifndef XSPARK_TRADE_PROFIT_LADDER_MQH
#define XSPARK_TRADE_PROFIT_LADDER_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

// Scaled profit taking, as pure functions over prices.
//
// This sits beside TrailingStop.mqh and for the same reason: taking profit in
// steps is a property of an OPEN POSITION, not of an entry rule, so it lives
// where PositionManager can reach it without the strategy layer being involved
// at all. Nothing here reads the terminal, the broker or an indicator handle.
// Every input is a number the caller already holds, which is what makes the
// decision reproducible from a script rather than only observable in a backtest.
//
// What it is for. A trailing stop alone gives every open profit back to the
// market once, on the way out: the trade has to retrace by the whole trail
// distance before the stop can act. On a strategy whose only exit is that stop,
// a trade that runs 6R and returns 2R is banked at 2R. A ladder banks a share
// of the position at fixed distances while the trade is moving IN ITS FAVOUR -
// upward on a long, downward on a short - so the retrace only costs the part
// still running.
//
// Each step is expressed as a BUDGET rather than as a share to close: "leave
// this much of the opening volume open", not "close 30% now". That is what
// makes a step idempotent, which is what makes it safe to have a confirmed
// broker close and no record of it. See XSparkProfitLadderTargetRemaining.
//
// What it is NOT. It never adds to a position, never re-enters, never sizes
// from a previous outcome and never moves a stop. It only ever removes exposure
// the position already has, which is why it cannot increase the risk the entry
// was sized for. See AGENTS.md rule 26.

// How many steps one position may have. Three is a deliberate ceiling rather
// than a technical one: MQL5 has no array inputs, so each level costs the
// operator two settings in the Inputs tab, and a fourth step subdivides the
// remainder past the point where the difference is visible in a result.
#define XSPARK_PROFIT_LADDER_MAX_LEVELS 3

// Two steps closer together than this are one step with extra paperwork, and on
// a fast move both fire against the same quote anyway.
#define XSPARK_PROFIT_LADDER_MIN_SPACING_R 0.25

// The ladder may never close the whole position. A residual is what keeps the
// trailing stop, the break-even lock and the weekend close in charge of the
// trade, and it is what makes "partial close" the only broker operation this
// module can ever cause. A configuration that would close everything is refused
// rather than silently clamped.
#define XSPARK_PROFIT_LADDER_MAX_TOTAL_PCT 90.0

// A fat-fingered target is caught rather than sent. Nothing sensible asks for a
// hundred times the amount risked. It doubles as the sentinel a progress value
// that cannot be trusted is read as: no step can ever exceed it, so an unusable
// record makes the ladder inert for that position rather than replaying it.
#define XSPARK_PROFIT_LADDER_MAX_R 100.0

// How long the ladder waits after the broker rejects a close before trying the
// same step again. A crossed trigger stays crossed, so without this a broker
// that keeps refusing gets one order per tick for the rest of the trade.
#define XSPARK_PROFIT_LADDER_RETRY_SECONDS 30

// After this many consecutive rejections the ladder stops trying for that
// position until the EA restarts. Something is wrong that retrying will not
// fix, and the trailing stop is still in charge of the trade either way.
#define XSPARK_PROFIT_LADDER_MAX_REJECTS 5

// Progress is compared in R multiples, which are a ratio of two prices. The
// tolerance only has to separate two configured levels, and validation already
// keeps those XSPARK_PROFIT_LADDER_MIN_SPACING_R apart.
#define XSPARK_PROFIT_LADDER_R_EPSILON 0.000000001

// The shipped configuration. Declared here so the test that proves the defaults
// form a VALID ladder is testing what actually ships rather than a copy of it.
//
// Two steps, both after the trade has earned more than it risked, closing 40%
// and then 30% and leaving 30% on the trailing stop. Weighted toward the first
// step because the failure being addressed is a trade that runs well and then
// hands it back: the earlier share is the one the retrace cannot reach. The
// remainder still carries the open-ended upside the strategy exists for.
//
// 40% first also survives a small position better, which is not a coincidence
// worth leaving unexplained. At a 0.01 minimum lot, 30% of 0.03 lots rounds to
// nothing and the first step is skipped entirely; 40% rounds to 0.01 and fires.
// Every share is normalised DOWN, so rounding always leaves more running than
// configured, never less.
//
// Plausible, not measured: nothing here is a profitability claim.
#define XSPARK_LADDER_DEFAULT_LEVEL1_R 1.5
#define XSPARK_LADDER_DEFAULT_LEVEL1_PCT 40.0
#define XSPARK_LADDER_DEFAULT_LEVEL2_R 3.0
#define XSPARK_LADDER_DEFAULT_LEVEL2_PCT 30.0
#define XSPARK_LADDER_DEFAULT_LEVEL3_R 0.0
#define XSPARK_LADDER_DEFAULT_LEVEL3_PCT 0.0

// The hard broker-side target ships OFF, and that is a recommendation rather
// than caution about an unproven feature. The remainder's exit is the trailing
// stop by design; a fixed cap on the one part of the trade that is meant to run
// is the opposite of what the ladder below it is for. It exists for an operator
// who wants an exit that fills while the terminal is closed, and it is theirs
// to switch on.
#define XSPARK_LADDER_DEFAULT_FINAL_TARGET_R 0.0

struct XSparkProfitLadder
{
   // Step i fires when the trade has earned level_r[i] times the distance from
   // its entry to its FIRST stop, and brings the position down to the share of
   // its OPENING volume that level_pct[i] and every share below it leave open.
   // In the ordinary case - nothing skipped, nothing already banked - that is
   // exactly "close level_pct[i] percent of the starting size", which is what
   // the Inputs tab says. Both zero means the step is unused.
   double level_r[XSPARK_PROFIT_LADDER_MAX_LEVELS];
   double level_pct[XSPARK_PROFIT_LADDER_MAX_LEVELS];

   // A broker-side take-profit for whatever is left, in the same units. Zero
   // means the remainder exits on its trailing stop alone, which is the
   // strategy's original behaviour.
   double final_target_r;
};

void XSparkResetProfitLadder(XSparkProfitLadder &ladder)
{
   for(int index = 0; index < XSPARK_PROFIT_LADDER_MAX_LEVELS; index++)
   {
      ladder.level_r[index] = 0.0;
      ladder.level_pct[index] = 0.0;
   }

   ladder.final_target_r = 0.0;
}

void XSparkDefaultProfitLadder(XSparkProfitLadder &ladder)
{
   XSparkResetProfitLadder(ladder);

   ladder.level_r[0] = XSPARK_LADDER_DEFAULT_LEVEL1_R;
   ladder.level_pct[0] = XSPARK_LADDER_DEFAULT_LEVEL1_PCT;
   ladder.level_r[1] = XSPARK_LADDER_DEFAULT_LEVEL2_R;
   ladder.level_pct[1] = XSPARK_LADDER_DEFAULT_LEVEL2_PCT;
   ladder.level_r[2] = XSPARK_LADDER_DEFAULT_LEVEL3_R;
   ladder.level_pct[2] = XSPARK_LADDER_DEFAULT_LEVEL3_PCT;
   ladder.final_target_r = XSPARK_LADDER_DEFAULT_FINAL_TARGET_R;
}

// Steps are filled from the first, so the count is the length of the leading
// run of configured ones. A hole is not counted past, and validation refuses
// the configuration that produced it rather than quietly skipping the step the
// operator thought they had set.
int XSparkProfitLadderActiveLevels(const XSparkProfitLadder &ladder)
{
   int count = 0;

   for(int index = 0; index < XSPARK_PROFIT_LADDER_MAX_LEVELS; index++)
   {
      if(!MathIsValidNumber(ladder.level_r[index]) || ladder.level_r[index] <= 0.0 ||
         !MathIsValidNumber(ladder.level_pct[index]) || ladder.level_pct[index] <= 0.0)
      {
         break;
      }

      count++;
   }

   return count;
}

double XSparkProfitLadderTotalPct(const XSparkProfitLadder &ladder)
{
   const int levels = XSparkProfitLadderActiveLevels(ladder);
   double total = 0.0;

   for(int index = 0; index < levels; index++)
      total += ladder.level_pct[index];

   return total;
}

bool XSparkProfitLadderIsEnabled(const XSparkProfitLadder &ladder)
{
   return XSparkProfitLadderActiveLevels(ladder) > 0;
}

// When to bank profit, as one choice instead of seven numbers.
//
// The operator's real question is "do I take money off the table as this runs,
// or do I let it ride?" - which is a genuine preference with no right answer,
// because it depends on their own give-back distribution. What is NOT a genuine
// preference is "level two closes 30% of the opening size at 3.0 times the
// amount risked": nobody can choose those digits from first principles.
//
// So the question is asked once, and each answer is a table that is known to
// pass XSparkValidateProfitLadder. A hole in the levels, steps that run
// backwards, or shares that would close the whole position are no longer things
// an operator can type - they are unreachable.//
// THE ORDINALS ARE A WIRE FORMAT. MetaTrader stores an enum input in a .set file
// as its INTEGER, not its name, so renumbering these or inserting a level in the
// middle silently reinterprets every saved file - a stored 1 that meant one
// style becoming another, on a live chart, with nothing logged. Add new levels
// at the END and never renumber an existing one.
enum EXSparkProfitStyle
{
   XSPARK_PROFIT_STYLE_OFF      = 0, // Off - the trailing stop is the only exit
   XSPARK_PROFIT_STYLE_BALANCED = 1, // Bank some at 1.5x and 3x, let the rest run
   XSPARK_PROFIT_STYLE_EARLY    = 2  // Bank more, sooner - a smoother, smaller curve
};

// EARLY banks three quarters of the trade by 2x the amount risked. It suits an
// operator whose trades more often fade than extend; it costs the right tail,
// and the docs say so rather than leaving it to be discovered.
#define XSPARK_LADDER_EARLY_LEVEL1_R 1.0
#define XSPARK_LADDER_EARLY_LEVEL1_PCT 50.0
#define XSPARK_LADDER_EARLY_LEVEL2_R 2.0
#define XSPARK_LADDER_EARLY_LEVEL2_PCT 25.0

void XSparkEarlyProfitLadder(XSparkProfitLadder &ladder)
{
   XSparkResetProfitLadder(ladder);

   ladder.level_r[0] = XSPARK_LADDER_EARLY_LEVEL1_R;
   ladder.level_pct[0] = XSPARK_LADDER_EARLY_LEVEL1_PCT;
   ladder.level_r[1] = XSPARK_LADDER_EARLY_LEVEL2_R;
   ladder.level_pct[1] = XSPARK_LADDER_EARLY_LEVEL2_PCT;
}

// Fails closed. Every refusal names the setting the operator has to change,
// because the caller turns this into a message on the panel and in the journal
// and there is nothing else to tell them what went wrong.
bool XSparkValidateProfitLadder(const XSparkProfitLadder &ladder, string &reason)
{
   reason = "";

   for(int index = 0; index < XSPARK_PROFIT_LADDER_MAX_LEVELS; index++)
   {
      if(!MathIsValidNumber(ladder.level_r[index]) || ladder.level_r[index] < 0.0 ||
         !MathIsValidNumber(ladder.level_pct[index]) || ladder.level_pct[index] < 0.0)
      {
         reason = StringFormat("Take-profit level %d must be finite and non-negative.", index + 1);
         return false;
      }
   }

   if(!MathIsValidNumber(ladder.final_target_r) || ladder.final_target_r < 0.0)
   {
      reason = "The final take-profit target must be finite and non-negative.";
      return false;
   }

   if(ladder.final_target_r > XSPARK_PROFIT_LADDER_MAX_R)
   {
      reason = StringFormat("The final take-profit target is %.2f times the amount risked; the ceiling is %.0f.",
                            ladder.final_target_r,
                            XSPARK_PROFIT_LADDER_MAX_R);
      return false;
   }

   const int levels = XSparkProfitLadderActiveLevels(ladder);

   // A half-configured step is the failure this catches: a distance with no
   // share to close at it, or a share with no distance, is a setting that does
   // nothing and reads as if it does something.
   for(int index = 0; index < XSPARK_PROFIT_LADDER_MAX_LEVELS; index++)
   {
      const bool has_r = ladder.level_r[index] > 0.0;
      const bool has_pct = ladder.level_pct[index] > 0.0;

      if(has_r != has_pct)
      {
         reason = StringFormat("Take-profit level %d needs both a distance and a share to close; one of them is zero.",
                               index + 1);
         return false;
      }

      if(index >= levels && has_r)
      {
         reason = StringFormat("Take-profit level %d is set but level %d is not; the levels are filled from the first.",
                               index + 1,
                               levels + 1);
         return false;
      }
   }

   if(levels == 0)
   {
      // No ladder at all is a legitimate configuration - it is the behaviour the
      // strategy shipped with - and a final target alone is equally legitimate.
      return true;
   }

   for(int index = 0; index < levels; index++)
   {
      if(ladder.level_r[index] > XSPARK_PROFIT_LADDER_MAX_R)
      {
         reason = StringFormat("Take-profit level %d is %.2f times the amount risked; the ceiling is %.0f.",
                               index + 1,
                               ladder.level_r[index],
                               XSPARK_PROFIT_LADDER_MAX_R);
         return false;
      }

      if(ladder.level_pct[index] > 100.0)
      {
         reason = StringFormat("Take-profit level %d closes %.2f%% of the trade; a share above 100%% is impossible.",
                               index + 1,
                               ladder.level_pct[index]);
         return false;
      }

      if(index > 0 && ladder.level_r[index] < ladder.level_r[index - 1] + XSPARK_PROFIT_LADDER_MIN_SPACING_R)
      {
         reason = StringFormat("Take-profit levels %d and %d are less than %.2f times the amount risked apart; they would fire against the same price.",
                               index,
                               index + 1,
                               XSPARK_PROFIT_LADDER_MIN_SPACING_R);
         return false;
      }
   }

   const double total = XSparkProfitLadderTotalPct(ladder);

   if(total > XSPARK_PROFIT_LADDER_MAX_TOTAL_PCT)
   {
      reason = StringFormat("The take-profit levels close %.2f%% of the trade between them; at most %.0f%% may be closed so a part always remains on the trailing stop.",
                            total,
                            XSPARK_PROFIT_LADDER_MAX_TOTAL_PCT);
      return false;
   }

   // A hard target at or inside the last step would close the whole trade before
   // that step could bank anything, which makes every setting below it inert.
   if(ladder.final_target_r > 0.0 &&
      ladder.final_target_r < ladder.level_r[levels - 1] + XSPARK_PROFIT_LADDER_MIN_SPACING_R)
   {
      reason = StringFormat("The final take-profit target must be at least %.2f beyond the last take-profit level, or zero to leave the rest on the trailing stop.",
                            XSPARK_PROFIT_LADDER_MIN_SPACING_R);
      return false;
   }

   return true;
}

// The price a given maturity corresponds to, measured from the entry in units
// of the position's own initial risk. Used for the ladder's triggers and,
// through the execution engine's reward ratio, for the hard target.
bool XSparkProfitLadderTargetPrice(const EXSparkSignalDirection direction,
                                   const double entry,
                                   const double risk_distance,
                                   const double r_multiple,
                                   double &price)
{
   price = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(entry) || entry <= 0.0 ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0 ||
      !MathIsValidNumber(r_multiple) || r_multiple <= 0.0)
   {
      return false;
   }

   const double candidate = direction == XSPARK_SIGNAL_BUY ? entry + r_multiple * risk_distance
                                                           : entry - r_multiple * risk_distance;

   if(!MathIsValidNumber(candidate) || candidate <= 0.0)
      return false;

   price = candidate;
   return true;
}

// The share of the opening volume that is closed by the time a given step has
// been taken - that step's own share plus every share below it.
double XSparkProfitLadderCumulativePct(const XSparkProfitLadder &ladder, const int level_index)
{
   const int levels = XSparkProfitLadderActiveLevels(ladder);

   if(level_index < 0 || level_index >= levels)
      return 0.0;

   double total = 0.0;

   for(int index = 0; index <= level_index; index++)
      total += ladder.level_pct[index];

   return total;
}

// How much of the position should still be open once a given step is complete.
//
// This is what makes a step IDEMPOTENT, and that is the whole reason the ladder
// is expressed as a budget rather than as a share to close. A step asks "how far
// above its target is the position still", not "close 30% of it" - so a close
// the broker confirmed but which the terminal died before recording is simply a
// step that now has nothing left to do, rather than one that closes another 30%
// on the next start. It also lets a step that had to be skipped be made good by
// the next one, instead of being lost for the rest of the trade.
//
// The ceiling on the total share guarantees the result is a positive fraction of
// the opening volume, so a residual always exists.
double XSparkProfitLadderTargetRemaining(const XSparkProfitLadder &ladder,
                                         const double initial_volume,
                                         const int level_index)
{
   if(!MathIsValidNumber(initial_volume) || initial_volume <= 0.0)
      return 0.0;

   return initial_volume * (100.0 - XSparkProfitLadderCumulativePct(ladder, level_index)) / 100.0;
}

// Guards a progress value restored from storage.
//
// Note the direction. Anything unusable is read as "every step is already
// behind us", which makes the ladder inert for that position rather than
// replaying it. A module that cannot trust its own record of what it has
// already done to a live position must not cause another broker operation on
// the strength of it; the position keeps its trailing stop either way.
double XSparkProfitLadderSanitizeHighWater(const double stored)
{
   if(!MathIsValidNumber(stored) || stored < 0.0 || stored > XSPARK_PROFIT_LADDER_MAX_R)
      return XSPARK_PROFIT_LADDER_MAX_R;

   return stored;
}

// The single step due on this pass, if any.
//
// Deliberately ONE step per call: each step is its own broker operation, and a
// pass that sent several would size the later ones from a volume the earlier
// ones have not been confirmed to have changed.
//
// The scan runs DOWNWARD, from the highest step to the lowest, and returns the
// FURTHEST one the price has reached. Validation keeps the steps strictly
// ascending, so the furthest reached step subsumes every step below it: its
// cumulative share already includes theirs. A candle that gaps through two
// steps therefore banks both shares in one order at the price the market is
// actually at, instead of banking the lower share now and leaving the upper one
// to a later pass at a price that may have retraced in the meantime.
//
// The comparison is against the EXIT-SIDE price - the Bid for a long, the Ask
// for a short - because that is the price the position could actually be closed
// at. Comparing against the entry side would report a step as reached while the
// fill would still be short of it, by one spread, on every trade.
bool XSparkProfitLadderDueLevel(const EXSparkSignalDirection direction,
                                const double entry,
                                const double risk_distance,
                                const double exit_side_price,
                                const XSparkProfitLadder &ladder,
                                const double high_water_r,
                                int &level_index,
                                double &cumulative_pct,
                                double &trigger_price)
{
   level_index = -1;
   cumulative_pct = 0.0;
   trigger_price = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(entry) || entry <= 0.0 ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0 ||
      !MathIsValidNumber(exit_side_price) || exit_side_price <= 0.0)
   {
      return false;
   }

   const double water = XSparkProfitLadderSanitizeHighWater(high_water_r);

   for(int index = XSparkProfitLadderActiveLevels(ladder) - 1; index >= 0; index--)
   {
      if(ladder.level_r[index] <= water + XSPARK_PROFIT_LADDER_R_EPSILON)
         continue;

      double target = 0.0;
      if(!XSparkProfitLadderTargetPrice(direction, entry, risk_distance, ladder.level_r[index], target))
         continue;

      const bool reached = direction == XSPARK_SIGNAL_BUY ? exit_side_price >= target
                                                          : exit_side_price <= target;

      if(!reached)
         continue;

      level_index = index;
      cumulative_pct = XSparkProfitLadderCumulativePct(ladder, index);
      trigger_price = target;
      return true;
   }

   return false;
}

// The ladder one style means, refused if it is not a configuration the manager
// can honour. The validator still runs for the same reason the trailing stop's
// does: a future edit to a table must not be able to reach a live chart.
bool XSparkProfitLadderForStyle(const EXSparkProfitStyle style,
                                XSparkProfitLadder &ladder,
                                string &reason)
{
   XSparkResetProfitLadder(ladder);
   reason = "";

   if(style == XSPARK_PROFIT_STYLE_OFF)
   {
      // Nothing to fill in. An empty ladder is a valid configuration and is the
      // strategy's original behaviour.
   }
   else if(style == XSPARK_PROFIT_STYLE_BALANCED)
      XSparkDefaultProfitLadder(ladder);
   else if(style == XSPARK_PROFIT_STYLE_EARLY)
      XSparkEarlyProfitLadder(ladder);
   else
   {
      reason = "The take-profit style is not one this build knows.";
      return false;
   }

   return XSparkValidateProfitLadder(ladder, reason);
}

#endif
