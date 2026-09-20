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
// of the position at fixed distances on the way UP, so the retrace only costs
// the part still running.
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
// hundred times the amount risked.
#define XSPARK_PROFIT_LADDER_MAX_R 100.0

// The shipped configuration. Declared here so the test that proves the defaults
// form a VALID ladder is testing what actually ships rather than a copy of it.
//
// Two steps, both after the trade has earned more than it risked, closing 30%
// each and leaving 40% on the trailing stop. Chosen so the common case the
// operator described - a trade that runs well and then hands it back - banks
// most of the move before the retrace can reach it, while the remainder still
// carries the open-ended upside the strategy exists for. Plausible, not
// measured: nothing here is a profitability claim.
#define XSPARK_LADDER_DEFAULT_LEVEL1_R 1.5
#define XSPARK_LADDER_DEFAULT_LEVEL1_PCT 30.0
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
   // its entry to its FIRST stop, and closes level_pct[i] percent of the volume
   // the position OPENED with. Both zero means the step is unused.
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

// Which steps a position has already banked, as a bit per step.
//
// A bitmask rather than a count because a step that could not be closed - the
// residual would have fallen below the broker's minimum volume - must not block
// the steps above it, so the taken set is not necessarily a prefix.
bool XSparkProfitLadderLevelTaken(const int taken_mask, const int level_index)
{
   if(level_index < 0 || level_index >= XSPARK_PROFIT_LADDER_MAX_LEVELS)
      return true; // out of range is "nothing to do here", never "fire it"

   return (taken_mask & (1 << level_index)) != 0;
}

int XSparkProfitLadderMarkTaken(const int taken_mask, const int level_index)
{
   if(level_index < 0 || level_index >= XSPARK_PROFIT_LADDER_MAX_LEVELS)
      return taken_mask;

   return taken_mask | (1 << level_index);
}

// Guards a mask restored from storage. Anything outside the representable set
// is treated as "no step has been banked", which is the cautious direction to
// be wrong in only because the trigger comparison below is re-evaluated against
// the live price: a step whose price has not been reached cannot fire.
int XSparkProfitLadderSanitizeMask(const int taken_mask)
{
   const int all = (1 << XSPARK_PROFIT_LADDER_MAX_LEVELS) - 1;

   if(taken_mask < 0 || (taken_mask & ~all) != 0)
      return 0;

   return taken_mask;
}

// The single step due on this pass, if any.
//
// Deliberately ONE step per call. Each step is a separate broker operation, and
// a pass that sent three of them would be three orders from one price sample,
// with the second and third sized from a volume the first has not been
// confirmed to have changed yet. A candle that jumps through every level
// therefore banks one step per management pass instead, at whatever the market
// is then - which is at or beyond the level either way, because the trigger is
// only reached from the profitable side.
//
// The comparison is against the EXIT-SIDE price - the Bid for a long, the Ask
// for a short - because that is the price the position could actually be closed
// at. Comparing against the entry side would report a level as reached while
// the fill would still be short of it, by one spread, on every trade.
bool XSparkProfitLadderDueLevel(const EXSparkSignalDirection direction,
                                const double entry,
                                const double risk_distance,
                                const double exit_side_price,
                                const XSparkProfitLadder &ladder,
                                const int taken_mask,
                                int &level_index,
                                double &close_pct,
                                double &trigger_price)
{
   level_index = -1;
   close_pct = 0.0;
   trigger_price = 0.0;

   if(direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)
      return false;

   if(!MathIsValidNumber(entry) || entry <= 0.0 ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0 ||
      !MathIsValidNumber(exit_side_price) || exit_side_price <= 0.0)
   {
      return false;
   }

   const int levels = XSparkProfitLadderActiveLevels(ladder);
   const int mask = XSparkProfitLadderSanitizeMask(taken_mask);

   for(int index = 0; index < levels; index++)
   {
      if(XSparkProfitLadderLevelTaken(mask, index))
         continue;

      double target = 0.0;
      if(!XSparkProfitLadderTargetPrice(direction, entry, risk_distance, ladder.level_r[index], target))
         continue;

      const bool reached = direction == XSPARK_SIGNAL_BUY ? exit_side_price >= target
                                                          : exit_side_price <= target;

      if(!reached)
         continue;

      level_index = index;
      close_pct = ladder.level_pct[index];
      trigger_price = target;
      return true;
   }

   return false;
}

#endif
