#property script_show_inputs

// Deterministic tests for the execution / position-state hardening helpers.
// These exercise pure functions only. Broker behaviour (order sends, deal
// history, live position binding) is NOT simulated here and must be validated
// in the MT5 Strategy Tester and on a demo account.

#include <XSpark/Core/ExecutionMath.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>

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

void TestDuplicateSignalProtection()
{
   const datetime bar = StringToTime("2026.09.03 12:00:00");
   string reason = "";

   Check("first submission of a signal bar is allowed",
         XSparkSignalBarIsSubmittable(0, bar, reason));
   Check("repeat submission of the same signal bar is blocked",
         !XSparkSignalBarIsSubmittable(bar, bar, reason));
   Check("duplicate block states its reason", reason == "Duplicate signal-bar submission blocked.");
   Check("a different signal bar is allowed after an earlier submission",
         XSparkSignalBarIsSubmittable(bar, (datetime)(bar + 900), reason));
   Check("invalid signal bar time is rejected",
         !XSparkSignalBarIsSubmittable(0, 0, reason));
}

void TestEntryDriftTolerance()
{
   const double max_drift = XSparkCanonicalPointsToPrice(30.0);
   double drift = 0.0;

   Check("max drift equals 30 canonical points", NearlyEqual(max_drift, 0.30));
   Check("small adverse drift is inside tolerance",
         XSparkEntryDriftIsWithinTolerance(2000.00, 2000.20, max_drift, drift));
   Check("drift value is reported", NearlyEqual(drift, 0.20));
   Check("drift exactly at tolerance is accepted",
         XSparkEntryDriftIsWithinTolerance(2000.00, 2000.30, max_drift, drift));
   Check("drift beyond tolerance aborts the entry",
         !XSparkEntryDriftIsWithinTolerance(2000.00, 2000.35, max_drift, drift));
   Check("favourable drift beyond tolerance also aborts the entry",
         !XSparkEntryDriftIsWithinTolerance(2000.00, 1999.60, max_drift, drift));
   Check("invalid reference price is rejected",
         !XSparkEntryDriftIsWithinTolerance(0.0, 2000.00, max_drift, drift));
}

void TestStopAndTargetGeometry()
{
   Check("buy stop below entry is protective",
         XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_BUY, 2000.00, 1997.00));
   Check("buy stop above entry is not protective",
         !XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_BUY, 2000.00, 2001.00));
   Check("buy stop at entry is not protective",
         !XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_BUY, 2000.00, 2000.00));
   Check("sell stop above entry is protective",
         XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_SELL, 2000.00, 2003.00));
   Check("sell stop below entry is not protective",
         !XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_SELL, 2000.00, 1999.00));
   Check("none direction is never protective",
         !XSparkStopIsOnProtectiveSide(XSPARK_SIGNAL_NONE, 2000.00, 1997.00));

   Check("buy risk distance uses the execution price",
         NearlyEqual(XSparkRiskDistance(XSPARK_SIGNAL_BUY, 2000.25, 1997.00), 3.25));
   Check("sell risk distance uses the execution price",
         NearlyEqual(XSparkRiskDistance(XSPARK_SIGNAL_SELL, 1999.75, 2003.00), 3.25));
   Check("risk distance is zero when price moved through the stop",
         NearlyEqual(XSparkRiskDistance(XSPARK_SIGNAL_BUY, 1996.00, 1997.00), 0.0));

   Check("buy target is derived from actual risk distance and locked RR",
         NearlyEqual(XSparkTargetFromRiskDistance(XSPARK_SIGNAL_BUY, 2000.25, 3.25, 2.0), 2006.75));
   Check("sell target is derived from actual risk distance and locked RR",
         NearlyEqual(XSparkTargetFromRiskDistance(XSPARK_SIGNAL_SELL, 1999.75, 3.25, 2.0), 1993.25));
   Check("target is invalid without a reward ratio",
         NearlyEqual(XSparkTargetFromRiskDistance(XSPARK_SIGNAL_BUY, 2000.25, 3.25, 0.0), 0.0));

   Check("realized RR matches the locked RR",
         NearlyEqual(XSparkRealizedRR(2000.25, 2006.75, 3.25), 2.0));
   Check("realized RR is zero without a risk distance",
         NearlyEqual(XSparkRealizedRR(2000.25, 2006.75, 0.0), 0.0));

   Check("RR inside configured bounds is accepted", XSparkRRIsWithinBounds(2.0, 1.5, 3.0));
   Check("RR at the lower bound is accepted", XSparkRRIsWithinBounds(1.5, 1.5, 3.0));
   Check("RR at the upper bound is accepted", XSparkRRIsWithinBounds(3.0, 1.5, 3.0));
   Check("RR below the lower bound is rejected", !XSparkRRIsWithinBounds(1.4, 1.5, 3.0));
   Check("RR above the upper bound is rejected", !XSparkRRIsWithinBounds(3.1, 1.5, 3.0));
}

void TestVolumeRecalculation()
{
   // XAUUSD-shaped specification: 0.01 tick size, 1.0 loss per tick per lot.
   const double tick_size = 0.01;
   const double tick_value = 1.00;
   const double volume_min = 0.01;
   const double volume_max = 100.0;
   const double volume_step = 0.01;
   const double risk_cash = 100.0;

   double volume = 0.0;
   double loss_per_lot = 0.0;
   string reason = "";

   Check("planned distance sizes a valid volume",
         XSparkVolumeFromRiskInputs(risk_cash, 3.00, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    volume, loss_per_lot, reason));
   Check("planned loss per lot is correct", NearlyEqual(loss_per_lot, 300.0));
   Check("planned volume is normalized down", NearlyEqual(volume, 0.33));
   Check("planned monetary risk stays within the risk budget", volume * loss_per_lot <= risk_cash);

   double wider_volume = 0.0;
   Check("a wider execution-time distance still sizes",
         XSparkVolumeFromRiskInputs(risk_cash, 3.25, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    wider_volume, loss_per_lot, reason));
   Check("a wider distance reduces the volume", wider_volume < volume);
   Check("a wider distance keeps risk within budget", wider_volume * loss_per_lot <= risk_cash);

   double tighter_volume = 0.0;
   Check("a tighter execution-time distance still sizes",
         XSparkVolumeFromRiskInputs(risk_cash, 2.80, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    tighter_volume, loss_per_lot, reason));
   Check("a tighter distance increases the volume", tighter_volume > volume);
   Check("a tighter distance keeps risk within budget", tighter_volume * loss_per_lot <= risk_cash);

   double below_min_volume = 0.0;
   Check("below-minimum volume aborts instead of rounding up",
         !XSparkVolumeFromRiskInputs(1.0, 3.00, tick_size, tick_value,
                                     volume_min, volume_max, volume_step,
                                     below_min_volume, loss_per_lot, reason));
   Check("aborted sizing returns zero volume", NearlyEqual(below_min_volume, 0.0));

   double capped_volume = 0.0;
   Check("oversized risk is capped at the broker maximum",
         XSparkVolumeFromRiskInputs(10000000.0, 3.00, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    capped_volume, loss_per_lot, reason));
   Check("capped volume equals the broker maximum", NearlyEqual(capped_volume, volume_max));

   double reason_volume = 0.0;
   XSparkVolumeFromRiskInputs(1.0, 3.00, tick_size, tick_value,
                              volume_min, volume_max, volume_step,
                              reason_volume, loss_per_lot, reason);
   Check("below-minimum abort keeps its reason wording",
         StringFind(reason, "below broker minimum") >= 0 &&
         StringFind(reason, "trade aborted") >= 0);

   XSparkVolumeFromRiskInputs(10000000.0, 3.00, tick_size, tick_value,
                              volume_min, volume_max, volume_step,
                              reason_volume, loss_per_lot, reason);
   Check("broker-maximum cap keeps its reason wording",
         StringFind(reason, "capped at broker maximum") >= 0);

   XSparkVolumeFromRiskInputs(risk_cash, 3.00, tick_size, tick_value,
                              volume_min, volume_max, volume_step,
                              reason_volume, loss_per_lot, reason);
   Check("successful sizing keeps its reason wording",
         StringFind(reason, "Position size calculated") >= 0);

   double invalid_volume = 0.0;
   Check("zero risk cash is rejected",
         !XSparkVolumeFromRiskInputs(0.0, 3.00, tick_size, tick_value,
                                     volume_min, volume_max, volume_step,
                                     invalid_volume, loss_per_lot, reason));
   Check("zero stop distance is rejected",
         !XSparkVolumeFromRiskInputs(risk_cash, 0.0, tick_size, tick_value,
                                     volume_min, volume_max, volume_step,
                                     invalid_volume, loss_per_lot, reason));
   Check("missing broker volume constraints are rejected",
         !XSparkVolumeFromRiskInputs(risk_cash, 3.00, tick_size, tick_value,
                                     0.0, volume_max, volume_step,
                                     invalid_volume, loss_per_lot, reason));
}

void TestPriceMovementRiskRevalidation()
{
   // The ATR-derived stop stays where the strategy put it. Only the volume and
   // the target move when the execution price differs from the planned price.
   const double planned_entry = 2000.00;
   const double locked_atr_stop = 1997.00;
   const double locked_rr = 2.0;
   const double risk_cash = 100.0;
   const double tick_size = 0.01;
   const double tick_value = 1.00;
   const double volume_min = 0.01;
   const double volume_max = 100.0;
   const double volume_step = 0.01;
   const double max_drift = XSparkCanonicalPointsToPrice(30.0);

   double drift = 0.0;
   double loss_per_lot = 0.0;
   string reason = "";

   double planned_volume = 0.0;
   const double planned_distance = XSparkRiskDistance(XSPARK_SIGNAL_BUY, planned_entry, locked_atr_stop);
   Check("planning-time sizing succeeds",
         XSparkVolumeFromRiskInputs(risk_cash, planned_distance, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    planned_volume, loss_per_lot, reason));
   Check("planning-time volume is non-zero", planned_volume > 0.0);

   // Price ran away from us but is still inside the permitted deviation.
   const double moved_up_entry = 2000.25;
   Check("adverse move within deviation is still executable",
         XSparkEntryDriftIsWithinTolerance(planned_entry, moved_up_entry, max_drift, drift));

   const double moved_up_distance = XSparkRiskDistance(XSPARK_SIGNAL_BUY, moved_up_entry, locked_atr_stop);
   Check("stop distance grows by exactly the entry move, proving the stop did not move",
         NearlyEqual(moved_up_distance - planned_distance, moved_up_entry - planned_entry));

   double moved_up_volume = 0.0;
   Check("volume is recomputed from the actual distance",
         XSparkVolumeFromRiskInputs(risk_cash, moved_up_distance, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    moved_up_volume, loss_per_lot, reason));
   Check("volume shrinks when the actual stop distance grows", moved_up_volume < planned_volume);
   Check("monetary risk never exceeds the selected risk percentage",
         moved_up_volume * loss_per_lot <= risk_cash);

   const double moved_up_target = XSparkTargetFromRiskDistance(XSPARK_SIGNAL_BUY,
                                                               moved_up_entry,
                                                               moved_up_distance,
                                                               locked_rr);
   Check("target is rebuilt from the actual distance and locked RR",
         NearlyEqual(moved_up_target, 2006.75));
   Check("rebuilt target preserves the locked RR",
         XSparkRRIsWithinBounds(XSparkRealizedRR(moved_up_entry, moved_up_target, moved_up_distance), 1.5, 3.0));

   // Price moved toward the stop: the distance shrinks and the volume grows,
   // but the monetary risk stays capped by the risk budget.
   const double moved_down_entry = 1999.80;
   const double moved_down_distance = XSparkRiskDistance(XSPARK_SIGNAL_BUY, moved_down_entry, locked_atr_stop);
   double moved_down_volume = 0.0;
   Check("favourable move within deviation is still executable",
         XSparkEntryDriftIsWithinTolerance(planned_entry, moved_down_entry, max_drift, drift));
   Check("stop distance shrinks by exactly the entry move, proving the stop did not move",
         NearlyEqual(planned_distance - moved_down_distance, planned_entry - moved_down_entry));
   Check("volume is recomputed for the tighter distance",
         XSparkVolumeFromRiskInputs(risk_cash, moved_down_distance, tick_size, tick_value,
                                    volume_min, volume_max, volume_step,
                                    moved_down_volume, loss_per_lot, reason));
   Check("volume grows when the actual stop distance shrinks", moved_down_volume > planned_volume);
   Check("tighter distance still respects the risk budget",
         moved_down_volume * loss_per_lot <= risk_cash);

   // Beyond the deviation tolerance the entry is abandoned, not chased.
   Check("movement beyond the deviation tolerance aborts the entry",
         !XSparkEntryDriftIsWithinTolerance(planned_entry, 2000.60, max_drift, drift));
   Check("price through the locked stop aborts the entry",
         NearlyEqual(XSparkRiskDistance(XSPARK_SIGNAL_BUY, 1996.50, locked_atr_stop), 0.0));
}

void TestPositionIdentityMatching()
{
   Check("matching broker position id binds", XSparkPositionIdentityMatches(123456, 123456));
   Check("different broker position id does not bind", !XSparkPositionIdentityMatches(123456, 654321));
   Check("zero candidate id never binds", XSparkPositionIdentityMatches(0, 123456) == false);
   Check("zero expected id never binds", XSparkPositionIdentityMatches(123456, 0) == false);

   const datetime submit_time = StringToTime("2026.09.03 12:00:00");

   Check("fallback accepts a single untracked new same-direction position",
         XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                            submit_time, submit_time, 0.10, 0.10, 0.005));
   Check("fallback accepts an open time inside the clock tolerance",
         XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                            (datetime)(submit_time - 1), submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects a position that is already tracked",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, true,
                                             submit_time, submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects the opposite direction",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_SELL, false,
                                             submit_time, submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects a position opened before the send",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                             (datetime)(submit_time - 600), submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects a volume that does not match the submission",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                             submit_time, submit_time, 0.20, 0.10, 0.005));
   Check("fallback accepts an open time exactly at the clock tolerance",
         XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                            (datetime)(submit_time - XSPARK_FALLBACK_OPEN_TIME_TOLERANCE_SECONDS),
                                            submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects an open time one second beyond the clock tolerance",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                             (datetime)(submit_time - XSPARK_FALLBACK_OPEN_TIME_TOLERANCE_SECONDS - 1),
                                             submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects a missing open time",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_BUY, XSPARK_SIGNAL_BUY, false,
                                             0, submit_time, 0.10, 0.10, 0.005));
   Check("fallback rejects a NONE plan direction",
         !XSparkFallbackPositionIsAcceptable(XSPARK_SIGNAL_NONE, XSPARK_SIGNAL_NONE, false,
                                             submit_time, submit_time, 0.10, 0.10, 0.005));
}

void TestStaleQuoteCalculations()
{
   const datetime quote_time = StringToTime("2026.09.03 12:00:00");
   long age = 0;
   string reason = "";

   Check("quote age is server time minus quote time",
         XSparkQuoteAgeSeconds(quote_time, (datetime)(quote_time + 7)) == 7);

   Check("fresh quote is accepted",
         XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time + 5), 15, age, reason));
   Check("accepted quote reports its age", age == 5);
   Check("quote age exactly at the limit is accepted",
         XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time + 15), 15, age, reason));
   Check("stale quote is rejected",
         !XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time + 16), 15, age, reason));
   Check("invalid quote timestamp is rejected",
         !XSparkQuoteAgeIsAcceptable(0, (datetime)(quote_time + 5), 15, age, reason));
   Check("invalid server reference time is rejected",
         !XSparkQuoteAgeIsAcceptable(quote_time, 0, 15, age, reason));
   Check("unconfigured maximum quote age is rejected",
         !XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time + 5), 0, age, reason));
   Check("small clock skew ahead of server time is tolerated",
         XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time - 3), 15, age, reason));
   Check("clock skew exactly at the future-skew limit is tolerated",
         XSparkQuoteAgeIsAcceptable(quote_time,
                                    (datetime)(quote_time - XSPARK_MAX_FUTURE_QUOTE_SKEW_SECONDS),
                                    15, age, reason));
   Check("clock skew one second beyond the future-skew limit is rejected",
         !XSparkQuoteAgeIsAcceptable(quote_time,
                                     (datetime)(quote_time - XSPARK_MAX_FUTURE_QUOTE_SKEW_SECONDS - 1),
                                     15, age, reason));
   Check("large future-dated quote timestamp is rejected",
         !XSparkQuoteAgeIsAcceptable(quote_time, (datetime)(quote_time - 30), 15, age, reason));
}

void TestExecutionResultState()
{
   XSparkExecutionResult result;

   result.confirmed = true;
   result.order_ticket = 11;
   result.deal_ticket = 22;
   result.position_ticket = 33;
   result.position_id = 44;
   result.position_id_exact = true;
   result.retcode = 10009;
   result.retcode_description = "done";
   result.price = 2000.0;
   result.volume = 0.10;
   result.fill_price = 2000.1;
   result.fill_volume = 0.10;
   result.fill_time = StringToTime("2026.09.03 12:00:00");
   result.submit_time = StringToTime("2026.09.03 12:00:00");
   result.submitted_entry_reference = 2000.2;
   result.submitted_sl = 1997.0;
   result.submitted_tp = 2006.0;
   result.submitted_volume = 0.10;
   result.actual_risk_distance = 3.2;
   result.actual_rr = 2.0;

   XSparkResetExecutionResult(result);

   Check("reset clears confirmation", !result.confirmed);
   Check("reset clears order ticket", result.order_ticket == 0);
   Check("reset clears deal ticket", result.deal_ticket == 0);
   Check("reset clears position ticket", result.position_ticket == 0);
   Check("reset clears position id", result.position_id == 0);
   Check("reset clears exact-id flag", !result.position_id_exact);
   Check("reset clears retcode", result.retcode == 0);
   Check("reset clears retcode description", result.retcode_description == "");
   Check("reset clears result price", NearlyEqual(result.price, 0.0));
   Check("reset clears result volume", NearlyEqual(result.volume, 0.0));
   Check("reset clears fill price", NearlyEqual(result.fill_price, 0.0));
   Check("reset clears fill volume", NearlyEqual(result.fill_volume, 0.0));
   Check("reset clears fill time", result.fill_time == 0);
   Check("reset clears submit time", result.submit_time == 0);
   Check("reset clears submitted entry reference", NearlyEqual(result.submitted_entry_reference, 0.0));
   Check("reset clears submitted stop", NearlyEqual(result.submitted_sl, 0.0));
   Check("reset clears submitted target", NearlyEqual(result.submitted_tp, 0.0));
   Check("reset clears submitted volume", NearlyEqual(result.submitted_volume, 0.0));
   Check("reset clears actual risk distance", NearlyEqual(result.actual_risk_distance, 0.0));
   Check("reset clears actual RR", NearlyEqual(result.actual_rr, 0.0));
}

void OnStart()
{
   Print("Starting XSpark execution/state hardening tests");
   TestDuplicateSignalProtection();
   TestEntryDriftTolerance();
   TestStopAndTargetGeometry();
   TestVolumeRecalculation();
   TestPriceMovementRiskRevalidation();
   TestPositionIdentityMatching();
   TestStaleQuoteCalculations();
   TestExecutionResultState();
   PrintFormat("XSpark execution/state hardening tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
