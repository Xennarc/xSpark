#property script_show_inputs

// Deterministic tests for deriving the instrument-scaled thresholds.
// Pure functions only. Reading real ATR history, and whether the derived
// numbers actually produce trades on a given symbol, are Strategy Tester
// questions and are NOT covered here.

#include <XSpark/Core/AutoTune.mqh>

int g_passed = 0;
int g_failed = 0;

bool NearlyEqual(const double actual, const double expected, const double tolerance = 0.000001)
{
   return MathAbs(actual - expected) <= tolerance;
}

void Check(const string name, const bool condition)
{
   if(condition)
   {
      g_passed++;
      Print("PASS: ", name);
   }
   else
   {
      g_failed++;
      Print("FAIL: ", name);
   }
}

void FillConstant(double &target[], const int count, const double value)
{
   ArrayResize(target, count);
   for(int index = 0; index < count; index++)
      target[index] = value;
}

// The median is what stops one volatility spike from raising the floor and
// muting the strategy for the rest of the run - the exact failure this module
// exists to prevent, arriving by a different route.
void TestSampleMedian()
{
   double median = 0.0;
   int valid = 0;
   string reason = "";

   double odd[];
   ArrayResize(odd, 5);
   odd[0] = 5.0; odd[1] = 1.0; odd[2] = 3.0; odd[3] = 2.0; odd[4] = 4.0;
   Check("odd sample takes the middle value",
         XSparkSampleMedian(odd, 5, 1, median, valid, reason) && NearlyEqual(median, 3.0));
   Check("odd sample counts every value", valid == 5);

   double even[];
   ArrayResize(even, 4);
   even[0] = 1.0; even[1] = 2.0; even[2] = 3.0; even[3] = 4.0;
   Check("even sample averages the two middle values",
         XSparkSampleMedian(even, 4, 1, median, valid, reason) && NearlyEqual(median, 2.5));

   // A single enormous outlier must not move the median. The mean of this set
   // is 201.6; the median is 2.
   double spiked[];
   ArrayResize(spiked, 5);
   spiked[0] = 1.0; spiked[1] = 2.0; spiked[2] = 3.0; spiked[3] = 2.0; spiked[4] = 1000.0;
   Check("a volatility spike does not move the median",
         XSparkSampleMedian(spiked, 5, 1, median, valid, reason) && NearlyEqual(median, 2.0));

   // CopyBuffer can return unset values at the edge of available history.
   // Counting those as zero would drag the reference down and loosen the floor.
   double padded[];
   ArrayResize(padded, 6);
   padded[0] = 0.0; padded[1] = 4.0; padded[2] = 0.0;
   padded[3] = 2.0; padded[4] = 6.0; padded[5] = -1.0;
   Check("unset and negative samples are discarded, not counted as zero",
         XSparkSampleMedian(padded, 6, 1, median, valid, reason) && NearlyEqual(median, 4.0));
   Check("only the usable samples are counted", valid == 3);

   const double sample_infinity = MathPow(10.0, 400.0);
   double hostile[];
   ArrayResize(hostile, 4);
   hostile[0] = 2.0; hostile[1] = sample_infinity;
   hostile[2] = sample_infinity - sample_infinity; hostile[3] = 4.0;
   Check("non-finite samples are discarded",
         XSparkSampleMedian(hostile, 4, 1, median, valid, reason) && NearlyEqual(median, 3.0));
   Check("non-finite samples are not counted", valid == 2);

   // Fails CLOSED on a thin sample. The caller retries on the next bar, so a
   // short history delays trading rather than calibrating on noise.
   double thin[];
   FillConstant(thin, 10, 5.0);
   Check("a sample below the minimum is refused",
         !XSparkSampleMedian(thin, 10, XSPARK_AUTOTUNE_MIN_SAMPLES, median, valid, reason));
   Check("the refusal says the history is too short",
         StringFind(reason, "too short") >= 0);
   Check("a refused median is left at zero", NearlyEqual(median, 0.0));

   double empty[];
   ArrayResize(empty, 1);
   empty[0] = 1.0;
   Check("a zero count is refused", !XSparkSampleMedian(empty, 0, 1, median, valid, reason));
   Check("a negative count is refused", !XSparkSampleMedian(empty, -3, 1, median, valid, reason));
   Check("claiming more samples than exist is refused",
         !XSparkSampleMedian(empty, 50, 1, median, valid, reason));

   double all_bad[];
   FillConstant(all_bad, 200, 0.0);
   Check("a sample with nothing usable is refused",
         !XSparkSampleMedian(all_bad, 200, 1, median, valid, reason));
}

void TestDeriveAutoTune()
{
   XSparkAutoTuneResult result;
   string reason = "";

   // THE CASE THAT MATTERS. The gold defaults are an ATR floor of 80 with a
   // stop multiple of 1.5, giving a 120 point minimum stop and the shipped 30
   // point entry deviation. Deriving the deviation as 25% of the minimum stop
   // reproduces that 30 EXACTLY, which is why 25 is the default: the number an
   // operator never has to think about again is the number that already shipped.
   Check("derivation succeeds on a gold-shaped market",
         XSparkDeriveAutoTune(133.3333333333, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("gold-shaped floor is 60% of the reference", NearlyEqual(result.atr_min_points, 80.0, 0.0001));
   Check("gold-shaped ceiling reproduces the shipped 800",
         NearlyEqual(result.atr_max_points, 800.0, 0.0001));
   Check("gold-shaped minimum stop is 120 points", NearlyEqual(result.min_stop_points, 120.0, 0.0001));
   Check("gold-shaped entry slippage reproduces the shipped 30",
         NearlyEqual(result.entry_deviation_points, 30.0, 0.0001));
   Check("gold-shaped exit slippage is 102, slightly more generous than the shipped 100",
         NearlyEqual(result.exit_deviation_points, 102.0, 0.0001));

   // THE BUG THIS FIXES. EURUSD M15 with a reference ATR near 10 pips. Under
   // the gold floor of 80 the volatility gate refused every bar; derived, the
   // floor lands at 6 pips and the market is tradeable.
   Check("derivation succeeds on an FX-shaped market",
         XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("FX floor is 6 pips, not 80", NearlyEqual(result.atr_min_points, 6.0));
   Check("FX ceiling is 60 pips", NearlyEqual(result.atr_max_points, 60.0));
   Check("FX minimum stop is 9 pips", NearlyEqual(result.min_stop_points, 9.0));
   Check("FX entry slippage is 2.25 pips, not 30", NearlyEqual(result.entry_deviation_points, 2.25));
   Check("FX exit slippage is 7.65 pips", NearlyEqual(result.exit_deviation_points, 7.65));
   Check("FX spread cap is 3.6 pips, not 50", NearlyEqual(result.spread_cap_points, 3.6));
   Check("the reference is carried through", NearlyEqual(result.reference_atr_points, 10.0));

   // The derived entry deviation satisfies the ADR-024 drift bound by
   // construction, on BOTH instruments, because it is a percentage of the same
   // minimum stop the bound measures against. That is the property that makes
   // the manual version's whole failure mode unreachable.
   double bound_stop = 0.0;
   double bound_ratio = 0.0;
   string bound_reason = "";
   Check("the derived FX deviation is not an inert drift gate",
         XSparkEntryDriftBound(result.entry_deviation_points, 1.5, result.atr_min_points,
                               bound_stop, bound_ratio, bound_reason) != XSPARK_DRIFT_BOUND_FAULT);
   Check("the derived overshoot ratio equals the configured percentage",
         NearlyEqual(bound_ratio, 0.25));

   // Scale invariance: the whole point. A market a thousand times larger gets
   // thresholds a thousand times larger and an identical overshoot ratio.
   XSparkAutoTuneResult big;
   Check("derivation succeeds on a very large-scale market",
         XSparkDeriveAutoTune(10000.0, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, big, reason));
   Check("thresholds scale linearly with the market",
         NearlyEqual(big.atr_min_points / result.atr_min_points, 1000.0) &&
         NearlyEqual(big.entry_deviation_points / result.entry_deviation_points, 1000.0));

   // Fails CLOSED on every unusable input.
   Check("a zero reference is refused",
         !XSparkDeriveAutoTune(0.0, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("a negative reference is refused",
         !XSparkDeriveAutoTune(-10.0, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("a ceiling below the floor is refused",
         !XSparkDeriveAutoTune(10.0, 600.0, 60.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("a ceiling equal to the floor is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 60.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("the band refusal explains that no bar could pass",
         StringFind(reason, "no bar could ever pass") >= 0);
   Check("a zero floor percentage is refused",
         !XSparkDeriveAutoTune(10.0, 0.0, 400.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("a zero stop multiple is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 600.0, 0.0, 25.0, 85.0, 40.0, result, reason));
   Check("a zero entry slippage is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 0.0, 85.0, 40.0, result, reason));
   Check("a zero spread cap is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 25.0, 85.0, 0.0, result, reason));

   // An entry slippage of a whole stop is the inert gate of ADR-024, refused
   // here as the configuration error it is rather than derived and then faulted.
   Check("entry slippage of a whole stop is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 100.0, 85.0, 40.0, result, reason));
   Check("entry slippage above a whole stop is refused",
         !XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 150.0, 85.0, 40.0, result, reason));
   Check("the slippage refusal names the stop distance",
         StringFind(reason, "entire stop distance") >= 0);
   Check("entry slippage just below a whole stop is allowed",
         XSparkDeriveAutoTune(10.0, 60.0, 600.0, 1.5, 99.0, 85.0, 40.0, result, reason));

   const double derive_infinity = MathPow(10.0, 400.0);
   Check("a non-finite reference is refused",
         !XSparkDeriveAutoTune(derive_infinity - derive_infinity, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("an infinite reference is refused",
         !XSparkDeriveAutoTune(derive_infinity, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, result, reason));
   Check("a non-finite band percentage is refused",
         !XSparkDeriveAutoTune(10.0, derive_infinity - derive_infinity, 400.0, 1.5, 25.0, 85.0, 40.0, result, reason));

   // A refused derivation must leave nothing usable behind, so a caller that
   // ignores the return value cannot trade on half-built thresholds.
   XSparkAutoTuneResult wiped;
   XSparkDeriveAutoTune(-1.0, 60.0, 600.0, 1.5, 25.0, 85.0, 40.0, wiped, reason);
   Check("a refused derivation leaves the floor at zero", NearlyEqual(wiped.atr_min_points, 0.0));
   Check("a refused derivation leaves the entry slippage at zero",
         NearlyEqual(wiped.entry_deviation_points, 0.0));
   Check("a refused derivation leaves the spread cap at zero",
         NearlyEqual(wiped.spread_cap_points, 0.0));
}

void OnStart()
{
   Print("Starting XSpark auto-tune tests");
   TestSampleMedian();
   TestDeriveAutoTune();
   PrintFormat("XSpark auto-tune tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
