#property script_show_inputs
#include <XSpark/Trade/ProfitLadder.mqh>

// Checks for the scaled take-profit ladder.
//
// These are pure price and share calculations. That PositionManager turns a due
// step into exactly one partial close, records it so a restart cannot repeat it,
// and never lets it disturb the trailing stop, is covered by the manager
// fixtures in tools/portable_position_tests.hpp.

int g_ladder_passed = 0, g_ladder_failed = 0;

void LadderCheck(const string name, const bool ok)
{
   if(ok) { g_ladder_passed++; Print("PASS: ",name); }
   else { g_ladder_failed++; Print("FAIL: ",name); }
}

bool LadderNear(const double a, const double b)
{
   return MathAbs(a - b) < 0.0000001;
}

void LadderLevels(XSparkProfitLadder &ladder,
                  const double r1, const double pct1,
                  const double r2, const double pct2,
                  const double r3, const double pct3,
                  const double final_r)
{
   XSparkResetProfitLadder(ladder);
   ladder.level_r[0] = r1;
   ladder.level_pct[0] = pct1;
   ladder.level_r[1] = r2;
   ladder.level_pct[1] = pct2;
   ladder.level_r[2] = r3;
   ladder.level_pct[2] = pct3;
   ladder.final_target_r = final_r;
}

void RunProfitLadderTests()
{
   string reason = "";
   XSparkProfitLadder ladder;

   // ---- the shipped configuration ----------------------------------------
   XSparkDefaultProfitLadder(ladder);
   LadderCheck("the shipped ladder is a valid configuration",
               XSparkValidateProfitLadder(ladder, reason));
   LadderCheck("the shipped ladder actually takes profit",
               XSparkProfitLadderIsEnabled(ladder) && XSparkProfitLadderActiveLevels(ladder) == 2);
   LadderCheck("the shipped ladder leaves a part running",
               XSparkProfitLadderTotalPct(ladder) < XSPARK_PROFIT_LADDER_MAX_TOTAL_PCT);
   LadderCheck("the shipped ladder ships the hard target off",
               ladder.final_target_r == 0.0);

   // An empty ladder is the strategy's original behaviour, and it is valid.
   XSparkResetProfitLadder(ladder);
   LadderCheck("no ladder at all is a valid configuration",
               XSparkValidateProfitLadder(ladder, reason));
   LadderCheck("no ladder at all takes no profit",
               !XSparkProfitLadderIsEnabled(ladder) && XSparkProfitLadderActiveLevels(ladder) == 0);

   // A hard target with no partial steps is equally legitimate.
   LadderLevels(ladder, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 4.0);
   LadderCheck("a hard target alone is a valid configuration",
               XSparkValidateProfitLadder(ladder, reason));

   // ---- counting and totals ----------------------------------------------
   LadderLevels(ladder, 1.0, 25.0, 2.0, 25.0, 3.0, 25.0, 0.0);
   LadderCheck("three configured steps are all counted",
               XSparkProfitLadderActiveLevels(ladder) == 3 &&
               LadderNear(XSparkProfitLadderTotalPct(ladder), 75.0));

   // ---- refusals ----------------------------------------------------------
   LadderLevels(ladder, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   LadderCheck("a distance with no share to close at it is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 0.0, 30.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   LadderCheck("a share with no distance to close it at is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 0.0, 0.0, 2.0, 30.0, 0.0, 0.0, 0.0);
   LadderCheck("a hole in the levels is refused rather than silently skipped",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 30.0, 1.1, 30.0, 0.0, 0.0, 0.0);
   LadderCheck("two steps too close together are refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 2.0, 30.0, 1.0, 30.0, 0.0, 0.0, 0.0);
   LadderCheck("steps that run backwards are refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 50.0, 2.0, 50.0, 0.0, 0.0, 0.0);
   LadderCheck("a ladder that would close the whole position is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 45.0, 2.0, 45.0, 0.0, 0.0, 0.0);
   LadderCheck("a ladder that closes exactly the ceiling is accepted",
               XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 130.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   LadderCheck("a share above 100% is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, -1.0, 30.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   LadderCheck("a negative distance is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 30.0, 3.0, 30.0, 0.0, 0.0, 3.1);
   LadderCheck("a hard target on top of the last step is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 30.0, 3.0, 30.0, 0.0, 0.0, 3.25);
   LadderCheck("a hard target clear of the last step is accepted",
               XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 1.0, 30.0, 0.0, 0.0, 0.0, 0.0, 500.0);
   LadderCheck("an absurd hard target is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   LadderLevels(ladder, 500.0, 30.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   LadderCheck("an absurd step distance is refused",
               !XSparkValidateProfitLadder(ladder, reason));

   // ---- target prices -----------------------------------------------------
   double price = 0.0;
   LadderCheck("a long's target sits above its entry",
               XSparkProfitLadderTargetPrice(XSPARK_SIGNAL_BUY, 100.0, 2.0, 1.5, price) &&
               LadderNear(price, 103.0));
   LadderCheck("a short's target sits below its entry",
               XSparkProfitLadderTargetPrice(XSPARK_SIGNAL_SELL, 100.0, 2.0, 1.5, price) &&
               LadderNear(price, 97.0));
   LadderCheck("a target needs a direction",
               !XSparkProfitLadderTargetPrice(XSPARK_SIGNAL_NONE, 100.0, 2.0, 1.5, price));
   LadderCheck("a target needs a risk distance",
               !XSparkProfitLadderTargetPrice(XSPARK_SIGNAL_BUY, 100.0, 0.0, 1.5, price));
   LadderCheck("a target that falls below zero is refused",
               !XSparkProfitLadderTargetPrice(XSPARK_SIGNAL_SELL, 100.0, 2.0, 60.0, price));

   // ---- the banked-step mask ---------------------------------------------
   int mask = 0;
   LadderCheck("a fresh position has banked nothing",
               !XSparkProfitLadderLevelTaken(mask, 0) && !XSparkProfitLadderLevelTaken(mask, 2));
   mask = XSparkProfitLadderMarkTaken(mask, 1);
   LadderCheck("marking one step leaves its neighbours alone",
               XSparkProfitLadderLevelTaken(mask, 1) &&
               !XSparkProfitLadderLevelTaken(mask, 0) &&
               !XSparkProfitLadderLevelTaken(mask, 2));
   LadderCheck("marking the same step twice changes nothing",
               XSparkProfitLadderMarkTaken(mask, 1) == mask);
   LadderCheck("a step outside the ladder is never marked",
               XSparkProfitLadderMarkTaken(mask, 9) == mask &&
               XSparkProfitLadderMarkTaken(mask, -1) == mask);
   LadderCheck("a step outside the ladder never reads as due",
               XSparkProfitLadderLevelTaken(mask, 9) && XSparkProfitLadderLevelTaken(mask, -1));
   LadderCheck("a stored mask naming a step this build lacks is read as empty",
               XSparkProfitLadderSanitizeMask(1 << XSPARK_PROFIT_LADDER_MAX_LEVELS) == 0 &&
               XSparkProfitLadderSanitizeMask(-4) == 0);
   LadderCheck("a representable stored mask survives unchanged",
               XSparkProfitLadderSanitizeMask(mask) == mask);

   // ---- which step is due -------------------------------------------------
   // A long from 100 risking 2.0: step one at 1.0R is 102, step two at 2.0R
   // is 104, step three at 3.5R is 107.
   LadderLevels(ladder, 1.0, 30.0, 2.0, 30.0, 3.5, 20.0, 0.0);
   int level = -1;
   double pct = 0.0, trigger = 0.0;

   LadderCheck("nothing is due before the first step is reached",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 101.9, ladder, 0,
                                           level, pct, trigger));
   LadderCheck("the first step is due exactly at its price",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 102.0, ladder, 0,
                                          level, pct, trigger) &&
               level == 0 && LadderNear(pct, 30.0) && LadderNear(trigger, 102.0));

   // A candle that jumps clean through two steps still banks the lower one
   // first: each step is its own broker operation, one per management pass.
   LadderCheck("a price beyond two steps still takes the lower one first",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 105.0, ladder, 0,
                                          level, pct, trigger) && level == 0);
   LadderCheck("with the first banked the same price takes the second",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 105.0, ladder, 1,
                                          level, pct, trigger) &&
               level == 1 && LadderNear(trigger, 104.0));
   LadderCheck("with both banked nothing is due until the third price",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 105.0, ladder, 3,
                                           level, pct, trigger));
   LadderCheck("the third step is due at its own price",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 107.0, ladder, 3,
                                          level, pct, trigger) &&
               level == 2 && LadderNear(pct, 20.0));
   LadderCheck("a fully banked ladder is never due again",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 200.0, ladder, 7,
                                           level, pct, trigger));

   // A step whose close was refused stays untaken while the steps above it are
   // banked, so the taken set is not necessarily a leading run.
   LadderCheck("a skipped lower step is still offered after a higher one banked",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 107.0, ladder, 2,
                                          level, pct, trigger) && level == 0);

   LadderCheck("a short's step is due when the price falls to it",
               XSparkProfitLadderDueLevel(XSPARK_SIGNAL_SELL, 100.0, 2.0, 98.0, ladder, 0,
                                          level, pct, trigger) &&
               level == 0 && LadderNear(trigger, 98.0));
   LadderCheck("a short's step is not due while the price is above it",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_SELL, 100.0, 2.0, 98.1, ladder, 0,
                                           level, pct, trigger));

   LadderCheck("a position with no recorded risk can never be due",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 0.0, 200.0, ladder, 0,
                                           level, pct, trigger));
   LadderCheck("an unusable price can never be due",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 0.0, ladder, 0,
                                           level, pct, trigger));
   LadderCheck("a directionless position can never be due",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_NONE, 100.0, 2.0, 200.0, ladder, 0,
                                           level, pct, trigger));

   XSparkResetProfitLadder(ladder);
   LadderCheck("an empty ladder is never due",
               !XSparkProfitLadderDueLevel(XSPARK_SIGNAL_BUY, 100.0, 2.0, 200.0, ladder, 0,
                                           level, pct, trigger));

   Print("PROFIT LADDER RESULT passed=", g_ladder_passed, " failed=", g_ladder_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunProfitLadderTests(); }
#endif
