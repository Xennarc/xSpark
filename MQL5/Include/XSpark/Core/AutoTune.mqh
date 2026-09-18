#ifndef XSPARK_CORE_AUTO_TUNE_MQH
#define XSPARK_CORE_AUTO_TUNE_MQH

#include <XSpark/Core/ExecutionMath.mqh>

// Derives the instrument-scaled thresholds from the instrument itself.
//
// Four of XSpark's numbers are expressed in ScoreBot points, which means they
// are only meaningful for one instrument at a time: the ATR floor and ceiling,
// the absolute spread cap, and the two slippage tolerances. The shipped values
// are gold values. On EURUSD a ScoreBot point is a pip, so an ATR floor of 80
// asks for 80 pips of range on a timeframe whose ATR is nearer 10 - and the ATR
// gate then refuses every bar for as long as the EA is attached. That is not a
// hypothetical; it is what a EURUSD M15 run produced.
//
// Documenting the conversion was not enough. The fix is for the numbers to be
// DERIVED from what the instrument actually does, so an operator never has to
// know the pip value of a gold threshold.
//
// Everything here is pure - no symbol, no terminal, no indicator handle - so
// the whole derivation is exercisable from a test script.

// A reference ATR needs enough observations to be a description of the market
// rather than of one week in it. Below this the derivation refuses and the
// caller retries on the next bar; it never proceeds on a thin sample.
#define XSPARK_AUTOTUNE_MIN_SAMPLES 120
#define XSPARK_AUTOTUNE_SAMPLE_BARS 500

struct XSparkAutoTuneResult
{
   double reference_atr_points;   // median ATR14 over the sample, in ScoreBot points
   double atr_min_points;         // volatility floor for the ATR gate
   double atr_max_points;         // volatility ceiling for the ATR gate
   double min_stop_points;        // smallest stop this configuration can produce
   double entry_deviation_points; // permitted entry slippage
   double exit_deviation_points;  // permitted exit slippage
   double spread_cap_points;      // absolute spread cap
};

void XSparkResetAutoTuneResult(XSparkAutoTuneResult &result)
{
   result.reference_atr_points = 0.0;
   result.atr_min_points = 0.0;
   result.atr_max_points = 0.0;
   result.min_stop_points = 0.0;
   result.entry_deviation_points = 0.0;
   result.exit_deviation_points = 0.0;
   result.spread_cap_points = 0.0;
}

// Median, not mean. One volatility spike must not be able to drag the floor up
// and mute the strategy for the rest of the run, which is precisely the failure
// this whole module exists to prevent.
//
// Invalid and non-positive samples are discarded rather than counted as zero:
// CopyBuffer can return unset values at the edge of the available history, and
// averaging those in would bias the reference downward.
bool XSparkSampleMedian(const double &samples[],
                        const int count,
                        const int min_valid,
                        double &median,
                        int &valid_count,
                        string &reason)
{
   median = 0.0;
   valid_count = 0;
   reason = "";

   if(count <= 0)
   {
      reason = "No ATR samples were supplied.";
      return false;
   }

   if(ArraySize(samples) < count)
   {
      reason = "Fewer ATR samples are present than were claimed.";
      return false;
   }

   double sorted[];
   if(ArrayResize(sorted, count) != count)
   {
      reason = "Unable to allocate the ATR sample buffer.";
      return false;
   }

   for(int index = 0; index < count; index++)
   {
      if(!MathIsValidNumber(samples[index]) || samples[index] <= 0.0)
         continue;

      sorted[valid_count] = samples[index];
      valid_count++;
   }

   if(valid_count < min_valid)
   {
      reason = StringFormat("Only %d usable ATR samples of the %d required; the market history is too short to describe this instrument yet.",
                            valid_count,
                            min_valid);
      return false;
   }

   if(ArrayResize(sorted, valid_count) != valid_count)
   {
      reason = "Unable to trim the ATR sample buffer.";
      return false;
   }

   ArraySort(sorted);

   if(valid_count % 2 == 1)
      median = sorted[valid_count / 2];
   else
      median = (sorted[valid_count / 2 - 1] + sorted[valid_count / 2]) / 2.0;

   if(!MathIsValidNumber(median) || median <= 0.0)
   {
      reason = "The median ATR is not a usable positive number.";
      return false;
   }

   return true;
}

// Turns one reference ATR into the whole set of instrument-scaled thresholds.
//
// The percentages are what an operator sets, and they mean the same thing on
// every instrument. The entry deviation is deliberately expressed against the
// MINIMUM STOP rather than against the ATR, because that ratio is exactly the
// worst-case realised-risk overshoot that ADR-024 defines - so a derived
// deviation satisfies the drift bound by construction instead of having to be
// checked and hoped for.
//
// Fails CLOSED on every unusable input. A caller that cannot derive thresholds
// must not trade on stale ones.
bool XSparkDeriveAutoTune(const double reference_atr_points,
                          const double floor_pct,
                          const double ceiling_pct,
                          const double atr_mult_sl,
                          const double entry_deviation_pct,
                          const double exit_deviation_pct,
                          const double spread_cap_pct,
                          XSparkAutoTuneResult &result,
                          string &reason)
{
   XSparkResetAutoTuneResult(result);
   reason = "";

   if(!MathIsValidNumber(reference_atr_points) || reference_atr_points <= 0.0)
   {
      reason = "Reference ATR is not a finite positive number of ScoreBot points.";
      return false;
   }

   if(!MathIsValidNumber(floor_pct) || floor_pct <= 0.0 ||
      !MathIsValidNumber(ceiling_pct) || ceiling_pct <= 0.0)
   {
      reason = "Volatility band percentages must be finite and positive.";
      return false;
   }

   if(ceiling_pct <= floor_pct)
   {
      reason = StringFormat("Volatility ceiling %.2f%% is not above the floor %.2f%%; no bar could ever pass the gate.",
                            ceiling_pct,
                            floor_pct);
      return false;
   }

   if(!MathIsValidNumber(atr_mult_sl) || atr_mult_sl <= 0.0)
   {
      reason = "Stop multiple must be a finite positive number.";
      return false;
   }

   if(!MathIsValidNumber(entry_deviation_pct) || entry_deviation_pct <= 0.0 ||
      !MathIsValidNumber(exit_deviation_pct) || exit_deviation_pct <= 0.0 ||
      !MathIsValidNumber(spread_cap_pct) || spread_cap_pct <= 0.0)
   {
      reason = "Deviation and spread percentages must be finite and positive.";
      return false;
   }

   // An entry deviation at or above the whole stop is the inert drift gate of
   // ADR-024. Refused here rather than derived and then faulted, so a bad
   // percentage is reported as the configuration error it is.
   if(entry_deviation_pct >= 100.0)
   {
      reason = StringFormat("Entry slippage allowance of %.2f%% is the entire stop distance or more; a permitted fill could land at or beyond its own stop.",
                            entry_deviation_pct);
      return false;
   }

   result.reference_atr_points = reference_atr_points;
   result.atr_min_points = reference_atr_points * (floor_pct / 100.0);
   result.atr_max_points = reference_atr_points * (ceiling_pct / 100.0);
   result.min_stop_points = result.atr_min_points * atr_mult_sl;
   result.entry_deviation_points = result.min_stop_points * (entry_deviation_pct / 100.0);
   result.exit_deviation_points = result.min_stop_points * (exit_deviation_pct / 100.0);
   result.spread_cap_points = result.min_stop_points * (spread_cap_pct / 100.0);

   if(!MathIsValidNumber(result.atr_min_points) || result.atr_min_points <= 0.0 ||
      !MathIsValidNumber(result.atr_max_points) || result.atr_max_points <= 0.0 ||
      !MathIsValidNumber(result.min_stop_points) || result.min_stop_points <= 0.0 ||
      !MathIsValidNumber(result.entry_deviation_points) || result.entry_deviation_points <= 0.0 ||
      !MathIsValidNumber(result.exit_deviation_points) || result.exit_deviation_points <= 0.0 ||
      !MathIsValidNumber(result.spread_cap_points) || result.spread_cap_points <= 0.0)
   {
      XSparkResetAutoTuneResult(result);
      reason = "A derived threshold overflowed or is not usable.";
      return false;
   }

   if(result.atr_max_points <= result.atr_min_points)
   {
      XSparkResetAutoTuneResult(result);
      reason = "The derived volatility ceiling is not above the derived floor.";
      return false;
   }

   reason = StringFormat("reference ATR %.2f, volatility band %.2f-%.2f, min stop %.2f, entry slip %.2f, exit slip %.2f, spread cap %.2f (all ScoreBot points)",
                         result.reference_atr_points,
                         result.atr_min_points,
                         result.atr_max_points,
                         result.min_stop_points,
                         result.entry_deviation_points,
                         result.exit_deviation_points,
                         result.spread_cap_points);
   return true;
}

#endif
