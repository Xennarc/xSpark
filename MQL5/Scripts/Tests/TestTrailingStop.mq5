#property script_show_inputs
#include <XSpark/Trade/TrailingStop.mqh>

// Checks for the composed trailing stop.
//
// CandleFlow's only exit is this stop, so its arithmetic carries the whole
// strategy. These are pure price calculations; that PositionManager applies
// them with a one-way ratchet is covered by the manager fixtures in
// tools/portable_position_tests.hpp.

int g_trail_passed = 0, g_trail_failed = 0;

void TrailCheck(const string name, const bool ok)
{
   if(ok) { g_trail_passed++; Print("PASS: ",name); }
   else { g_trail_failed++; Print("FAIL: ",name); }
}

bool TrailNear(const double a, const double b)
{
   return MathAbs(a - b) < 0.0000001;
}

void TrailTuning(XSparkTrailTuning &tuning,
                 const double floor_mult,
                 const double base_mult,
                 const double tight_mult,
                 const double start_r,
                 const double full_r,
                 const double be_r,
                 const double be_offset)
{
   XSparkResetTrailTuning(tuning);
   tuning.min_trail_atr_mult = floor_mult;
   tuning.chandelier_atr_mult = base_mult;
   tuning.chandelier_tight_atr_mult = tight_mult;
   tuning.tighten_start_r = start_r;
   tuning.tighten_full_r = full_r;
   tuning.breakeven_at_r = be_r;
   tuning.breakeven_offset_r = be_offset;
}

void RunTrailingStopTests()
{
   string reason = "";
   XSparkTrailTuning tuning;

   // --- the peak advances only in the trade's favour -----------------------
   TrailCheck("a long peak rises with a higher high",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_BUY, 105.0, 107.0, 104.0), 107.0));
   TrailCheck("a long peak ignores a lower high",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_BUY, 105.0, 103.0, 102.0), 105.0));
   TrailCheck("a short peak falls with a lower low",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_SELL, 95.0, 96.0, 93.0), 93.0));
   TrailCheck("a short peak ignores a higher low",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_SELL, 95.0, 99.0, 97.0), 95.0));
   TrailCheck("an unset peak takes the first candle's extreme",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_BUY, 0.0, 107.0, 104.0), 107.0));
   TrailCheck("an unusable candle leaves the peak alone",
              TrailNear(XSparkTrailUpdatedPeak(XSPARK_SIGNAL_BUY, 105.0, 0.0, 0.0), 105.0));

   // --- maturity, measured from the peak -----------------------------------
   double peak_r = 0.0;
   TrailCheck("a long that ran two risk units reports 2R",
              XSparkTrailPeakR(XSPARK_SIGNAL_BUY, 100.0, 104.0, 2.0, peak_r) && TrailNear(peak_r, 2.0));
   TrailCheck("a short that ran two risk units reports 2R",
              XSparkTrailPeakR(XSPARK_SIGNAL_SELL, 100.0, 96.0, 2.0, peak_r) && TrailNear(peak_r, 2.0));
   TrailCheck("a trade that never went in front reports zero, not a negative",
              XSparkTrailPeakR(XSPARK_SIGNAL_BUY, 100.0, 99.0, 2.0, peak_r) && TrailNear(peak_r, 0.0));
   TrailCheck("an unknown initial risk cannot produce an R",
              !XSparkTrailPeakR(XSPARK_SIGNAL_BUY, 100.0, 104.0, 0.0, peak_r));

   // --- the tier multiple interpolates, it does not jump --------------------
   double multiple = 0.0;
   TrailTuning(tuning, 0.25, 3.0, 1.0, 1.0, 3.0, 0.0, 0.0);
   TrailCheck("below the start the trail stays at its base width",
              XSparkTrailChandelierMultiple(0.5, tuning, multiple) && TrailNear(multiple, 3.0));
   TrailCheck("at the start the trail is still at its base width",
              XSparkTrailChandelierMultiple(1.0, tuning, multiple) && TrailNear(multiple, 3.0));
   TrailCheck("halfway through the tightening the multiple is halfway",
              XSparkTrailChandelierMultiple(2.0, tuning, multiple) && TrailNear(multiple, 2.0));
   TrailCheck("at full tightening the multiple is the tight one",
              XSparkTrailChandelierMultiple(3.0, tuning, multiple) && TrailNear(multiple, 1.0));
   TrailCheck("beyond full tightening it does not keep shrinking",
              XSparkTrailChandelierMultiple(9.0, tuning, multiple) && TrailNear(multiple, 1.0));

   TrailTuning(tuning, 0.25, 3.0, 1.0, 0.0, 0.0, 0.0, 0.0);
   TrailCheck("with tiering off the multiple never changes",
              XSparkTrailChandelierMultiple(9.0, tuning, multiple) && TrailNear(multiple, 3.0));

   TrailTuning(tuning, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   TrailCheck("with the trail off there is no multiple",
              !XSparkTrailChandelierMultiple(2.0, tuning, multiple));

   // --- the chandelier price itself ----------------------------------------
   double stop = 0.0;
   TrailCheck("a long trails below its peak",
              XSparkTrailChandelierStop(XSPARK_SIGNAL_BUY, 110.0, 2.0, 3.0, stop) && TrailNear(stop, 104.0));
   TrailCheck("a short trails above its peak",
              XSparkTrailChandelierStop(XSPARK_SIGNAL_SELL, 90.0, 2.0, 3.0, stop) && TrailNear(stop, 96.0));
   TrailCheck("no average range means no chandelier",
              !XSparkTrailChandelierStop(XSPARK_SIGNAL_BUY, 110.0, 0.0, 3.0, stop));

   // --- the breakeven lock --------------------------------------------------
   TrailCheck("a long locks at entry plus the offset",
              XSparkTrailBreakevenStop(XSPARK_SIGNAL_BUY, 100.0, 2.0, 0.1, stop) && TrailNear(stop, 100.2));
   TrailCheck("a short locks at entry minus the offset",
              XSparkTrailBreakevenStop(XSPARK_SIGNAL_SELL, 100.0, 2.0, 0.1, stop) && TrailNear(stop, 99.8));
   TrailCheck("a zero offset locks exactly at entry",
              XSparkTrailBreakevenStop(XSPARK_SIGNAL_BUY, 100.0, 2.0, 0.0, stop) && TrailNear(stop, 100.0));

   // --- the most protective layer wins -------------------------------------
   TrailCheck("a long prefers the higher stop",
              TrailNear(XSparkTrailMoreProtective(XSPARK_SIGNAL_BUY, 99.0, 101.0), 101.0));
   TrailCheck("a short prefers the lower stop",
              TrailNear(XSparkTrailMoreProtective(XSPARK_SIGNAL_SELL, 99.0, 101.0), 99.0));
   TrailCheck("an absent layer never wins",
              TrailNear(XSparkTrailMoreProtective(XSPARK_SIGNAL_BUY, 0.0, 101.0), 101.0) &&
              TrailNear(XSparkTrailMoreProtective(XSPARK_SIGNAL_BUY, 99.0, 0.0), 99.0));
   TrailCheck("two absent layers produce nothing",
              TrailNear(XSparkTrailMoreProtective(XSPARK_SIGNAL_BUY, 0.0, 0.0), 0.0));

   // --- the floor, which is what stops a noise exit -------------------------
   double floored = 0.0;
   TrailCheck("a stop outside the floor is left alone",
              XSparkTrailApplyFloor(XSPARK_SIGNAL_BUY, 110.0, 104.0, 2.0, 0.5, floored, reason) &&
              TrailNear(floored, 104.0));
   TrailCheck("a long stop inside the floor is widened away from price",
              XSparkTrailApplyFloor(XSPARK_SIGNAL_BUY, 110.0, 109.9, 2.0, 0.5, floored, reason) &&
              TrailNear(floored, 109.0));
   TrailCheck("a short stop inside the floor is widened away from price",
              XSparkTrailApplyFloor(XSPARK_SIGNAL_SELL, 90.0, 90.1, 2.0, 0.5, floored, reason) &&
              TrailNear(floored, 91.0));
   TrailCheck("a stop already through the market is pushed back behind the floor",
              XSparkTrailApplyFloor(XSPARK_SIGNAL_BUY, 110.0, 111.0, 2.0, 0.5, floored, reason) &&
              TrailNear(floored, 109.0));
   TrailCheck("with the floor off nothing is widened",
              XSparkTrailApplyFloor(XSPARK_SIGNAL_BUY, 110.0, 109.9, 2.0, 0.0, floored, reason) &&
              TrailNear(floored, 109.9));
   TrailCheck("a configured floor without an average range refuses",
              !XSparkTrailApplyFloor(XSPARK_SIGNAL_BUY, 110.0, 109.9, 0.0, 0.5, floored, reason));

   // --- the composed decision ----------------------------------------------
   // Entry 100, risk 2.0, ATR 2.0. Peak 110 is therefore 5R.
   TrailTuning(tuning, 0.25, 3.0, 1.0, 1.0, 3.0, 1.0, 0.0);
   TrailCheck("a mature long trails from its peak at the tightened multiple",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 110.0, 2.0, 0.0, 110.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(peak_r, 5.0) && TrailNear(stop, 108.0));

   TrailCheck("the candle anchor wins when it is the more protective one",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 110.0, 2.0, 109.0, 110.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(stop, 109.0));

   TrailCheck("the chandelier wins when the candle anchor is looser",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 110.0, 2.0, 101.0, 110.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(stop, 108.0));

   // Peak 102 is 1R, so the breakeven lock engages and the chandelier at the
   // base multiple would still be below entry. The lock must win.
   TrailCheck("the breakeven lock beats a chandelier that is still under water",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 102.0, 2.0, 0.0, 102.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(peak_r, 1.0) && TrailNear(stop, 100.0));

   // The same trade one tick short of the trigger must NOT be locked.
   TrailCheck("below the trigger the breakeven lock does not engage",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 101.0, 2.0, 0.0, 101.0,
                                   tuning, stop, peak_r, reason) &&
              stop < 100.0);

   TrailTuning(tuning, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   TrailCheck("a candle anchor sitting on the market is widened to the floor",
              XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 110.0, 2.0, 109.95, 110.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(stop, 109.0));

   TrailCheck("with every layer off there is nothing to do",
              !XSparkTrailCandidate(XSPARK_SIGNAL_BUY, 100.0, 2.0, 110.0, 2.0, 0.0, 110.0,
                                    tuning, stop, peak_r, reason));

   // A short mirror of the composed case, because a sign error here would
   // silently put every short's stop on the wrong side of the market.
   TrailTuning(tuning, 0.25, 3.0, 1.0, 1.0, 3.0, 1.0, 0.0);
   TrailCheck("a mature short trails above its peak at the tightened multiple",
              XSparkTrailCandidate(XSPARK_SIGNAL_SELL, 100.0, 2.0, 90.0, 2.0, 0.0, 90.0,
                                   tuning, stop, peak_r, reason) &&
              TrailNear(peak_r, 5.0) && TrailNear(stop, 92.0));

   // --- configuration validation -------------------------------------------
   TrailTuning(tuning, 0.25, 3.0, 1.0, 1.0, 3.0, 1.0, 0.0);
   TrailCheck("a complete configuration is accepted", XSparkValidateTrailTuning(tuning, reason));

   // The numbers the EA's inputs actually default to. A default that failed
   // validation would block every entry on a fresh chart, silently.
   XSparkDefaultTrailTuning(tuning);
   TrailCheck("the shipped defaults are a valid configuration",
              XSparkValidateTrailTuning(tuning, reason));
   TrailCheck("the shipped defaults turn the trail and both refinements on",
              tuning.min_trail_atr_mult > 0.0 && tuning.chandelier_atr_mult > 0.0 &&
              tuning.tighten_start_r > 0.0 && tuning.breakeven_at_r > 0.0);

   TrailTuning(tuning, 0.25, 1.0, 3.0, 1.0, 3.0, 0.0, 0.0);
   TrailCheck("a tightened trail wider than the base one is refused",
              !XSparkValidateTrailTuning(tuning, reason));

   TrailTuning(tuning, 0.25, 0.0, 0.0, 1.0, 3.0, 0.0, 0.0);
   TrailCheck("tiering without a trail to tier is refused",
              !XSparkValidateTrailTuning(tuning, reason));

   TrailTuning(tuning, 0.25, 3.0, 1.0, 2.0, 2.05, 0.0, 0.0);
   TrailCheck("a tiering span too narrow to interpolate is refused",
              !XSparkValidateTrailTuning(tuning, reason));

   TrailTuning(tuning, 0.25, 3.0, 1.0, 0.0, 0.0, 1.0, -1.5);
   TrailCheck("a breakeven lock that gives back more than it earns is refused",
              !XSparkValidateTrailTuning(tuning, reason));

   TrailTuning(tuning, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   TrailCheck("a negative floor is refused", !XSparkValidateTrailTuning(tuning, reason));

   Print("TRAILING RESULT passed=", g_trail_passed, " failed=", g_trail_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunTrailingStopTests(); }
#endif
