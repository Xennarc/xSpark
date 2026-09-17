#property script_show_inputs

// Deterministic tests for the execution / position-state hardening helpers.
// These exercise pure functions only. Broker behaviour (order sends, deal
// history, live position binding) is NOT simulated here and must be validated
// in the MT5 Strategy Tester and on a demo account.

#include <XSpark/Core/ExecutionMath.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Trade/TradeState.mqh>

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
   const double max_drift = XSparkScorePointsToPrice(30.0, XSPARK_XAUUSD_SCORE_POINT_SIZE);
   double drift = 0.0;

   Check("max drift equals 30 ScoreBot points", NearlyEqual(max_drift, 0.30));
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
   const double max_drift = XSparkScorePointsToPrice(30.0, XSPARK_XAUUSD_SCORE_POINT_SIZE);

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

// The shared closure accumulator. Both defects it replaces are asserted against
// directly, so a regression to either is a test failure rather than a silently
// wrong number in a log line.
void TestClosureAccumulation()
{
   XSparkClosureTotals totals;
   XSparkResetClosureTotals(totals);

   Check("reset clears net profit", NearlyEqual(totals.net_profit, 0.0));
   Check("reset clears exit price", NearlyEqual(totals.exit_price, 0.0));
   Check("reset clears deal count", totals.deal_count == 0);

   // A position closed in two deals, which is what every partial close produces.
   XSparkAccumulateClosureDeal(totals, 10.00, -0.70, -0.20, 0.02, 2650.00, 1000);
   XSparkAccumulateClosureDeal(totals,  8.00, -0.35,  0.00, 0.01, 2680.00, 2000);

   Check("gross profit sums DEAL_PROFIT", NearlyEqual(totals.gross_profit, 18.00));
   Check("commission is accumulated", NearlyEqual(totals.commission, -1.05));
   Check("swap is accumulated", NearlyEqual(totals.swap, -0.20));

   // DEFECT 1: the old code summed DEAL_PROFIT alone and called it profit, so a
   // commission-charging account reported a figure that never reached the
   // balance. Net must differ from gross by exactly the costs.
   Check("net profit includes commission and swap", NearlyEqual(totals.net_profit, 16.75));
   Check("net profit differs from gross by the costs",
         NearlyEqual(totals.gross_profit - totals.net_profit, 1.25));

   // DEFECT 2: the old code ASSIGNED the exit price per deal, so it reported
   // whichever deal the loop saw last. The volume-weighted average is 2660.00
   // while the last deal's price is 2680.00, so a regression is unambiguous.
   Check("exit price is volume weighted", NearlyEqual(totals.exit_price, 2660.00));
   Check("exit price is NOT the last deal's price", !NearlyEqual(totals.exit_price, 2680.00));

   Check("volume is accumulated", NearlyEqual(totals.volume, 0.03));
   Check("deal count is accumulated", totals.deal_count == 2);
   Check("exit time is the latest deal", totals.exit_time == 2000);

   // Order must not matter to any accumulated quantity.
   XSparkClosureTotals reversed;
   XSparkResetClosureTotals(reversed);
   XSparkAccumulateClosureDeal(reversed,  8.00, -0.35,  0.00, 0.01, 2680.00, 2000);
   XSparkAccumulateClosureDeal(reversed, 10.00, -0.70, -0.20, 0.02, 2650.00, 1000);
   Check("accumulation is order independent for price", NearlyEqual(reversed.exit_price, 2660.00));
   Check("accumulation is order independent for net", NearlyEqual(reversed.net_profit, 16.75));
   Check("exit time takes the latest regardless of order", reversed.exit_time == 2000);

   // A single deal weights to its own price.
   XSparkClosureTotals single;
   XSparkResetClosureTotals(single);
   XSparkAccumulateClosureDeal(single, -5.00, -0.35, 0.0, 0.01, 2600.00, 500);
   Check("single deal exit price is its own", NearlyEqual(single.exit_price, 2600.00));
   Check("single losing deal nets the costs", NearlyEqual(single.net_profit, -5.35));

   // A deal with no usable volume still moved money, so its cash must count even
   // though it cannot carry a price weight.
   XSparkClosureTotals zero_volume;
   XSparkResetClosureTotals(zero_volume);
   XSparkAccumulateClosureDeal(zero_volume, 3.00, -0.10, 0.0, 0.0, 2700.00, 100);
   Check("zero-volume deal still counts its cash", NearlyEqual(zero_volume.net_profit, 2.90));
   Check("zero-volume deal keeps a fallback price", NearlyEqual(zero_volume.exit_price, 2700.00));
   Check("zero-volume deal adds no volume", NearlyEqual(zero_volume.volume, 0.0));

   // A weighted deal must win over a previously stored fallback price.
   XSparkAccumulateClosureDeal(zero_volume, 1.00, 0.0, 0.0, 0.02, 2500.00, 200);
   Check("a weighted deal overrides the fallback price", NearlyEqual(zero_volume.exit_price, 2500.00));

   // Non-finite inputs must not poison the totals.
   const double closure_infinity = MathPow(10.0, 400.0);
   const double closure_nan = closure_infinity - closure_infinity;

   XSparkClosureTotals guarded;
   XSparkResetClosureTotals(guarded);
   XSparkAccumulateClosureDeal(guarded, 5.00, -0.20, 0.0, 0.01, 2600.00, 100);
   XSparkAccumulateClosureDeal(guarded, closure_nan, closure_infinity, closure_nan,
                               closure_infinity, closure_nan, 200);
   Check("non-finite cash is ignored", NearlyEqual(guarded.net_profit, 4.80));
   Check("non-finite volume does not corrupt the weighting", NearlyEqual(guarded.exit_price, 2600.00));
   Check("non-finite volume adds no volume", NearlyEqual(guarded.volume, 0.01));
   Check("totals remain finite after a poisoned deal", MathIsValidNumber(guarded.exit_price));
}

// Maximum favourable and adverse excursion. The invariant that matters is
// mfe_r >= mae_r for any consistent pair, in both directions.
void TestExcursionTracking()
{
   // LONG: favourable is a higher Bid, adverse is a lower Bid.
   double mfe = 0.0;
   double mae = 0.0;

   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 2600.00, mfe, mae);
   Check("first long sample seeds both extremes", NearlyEqual(mfe, 2600.00) && NearlyEqual(mae, 2600.00));

   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 2612.00, mfe, mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 2594.00, mfe, mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 2605.00, mfe, mae);
   Check("long MFE keeps the highest exit-side price", NearlyEqual(mfe, 2612.00));
   Check("long MAE keeps the lowest exit-side price", NearlyEqual(mae, 2594.00));

   // Entry 2600, risk 6.00 -> MFE +2R, MAE -1R.
   Check("long MFE in R", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, mfe, 6.00), 2.0));
   Check("long MAE in R", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, mae, 6.00), -1.0));

   // SHORT: favourable is a LOWER Ask, adverse is a higher Ask. The direction
   // inversion is the easiest thing to get backwards here.
   double s_mfe = 0.0;
   double s_mae = 0.0;

   XSparkUpdateExcursion(XSPARK_SIGNAL_SELL, 2600.00, s_mfe, s_mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_SELL, 2588.00, s_mfe, s_mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_SELL, 2606.00, s_mfe, s_mae);
   Check("short MFE keeps the LOWEST exit-side price", NearlyEqual(s_mfe, 2588.00));
   Check("short MAE keeps the HIGHEST exit-side price", NearlyEqual(s_mae, 2606.00));
   Check("short MFE in R", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_SELL, 2600.00, s_mfe, 6.00), 2.0));
   Check("short MAE in R", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_SELL, 2600.00, s_mae, 6.00), -1.0));

   // The Stage 2 gate, asserted for both directions.
   Check("long invariant MFE_R >= MAE_R",
         XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, mfe, 6.00) >=
         XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, mae, 6.00));
   Check("short invariant MFE_R >= MAE_R",
         XSparkExcursionR(XSPARK_SIGNAL_SELL, 2600.00, s_mfe, 6.00) >=
         XSparkExcursionR(XSPARK_SIGNAL_SELL, 2600.00, s_mae, 6.00));

   // A position that never moves reports zero both ways, not an unset sentinel.
   double f_mfe = 2600.00;
   double f_mae = 2600.00;
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 2600.00, f_mfe, f_mae);
   Check("a flat position reports zero MFE", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, f_mfe, 6.00), 0.0));
   Check("a flat position reports zero MAE", NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, f_mae, 6.00), 0.0));

   // Unusable samples must not move the extremes.
   const double excursion_infinity = MathPow(10.0, 400.0);
   double g_mfe = 2600.00;
   double g_mae = 2600.00;
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, 0.0, g_mfe, g_mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, -1.0, g_mfe, g_mae);
   XSparkUpdateExcursion(XSPARK_SIGNAL_BUY, excursion_infinity - excursion_infinity, g_mfe, g_mae);
   Check("invalid samples leave MFE untouched", NearlyEqual(g_mfe, 2600.00));
   Check("invalid samples leave MAE untouched", NearlyEqual(g_mae, 2600.00));
   XSparkUpdateExcursion(XSPARK_SIGNAL_NONE, 2700.00, g_mfe, g_mae);
   Check("a NONE direction does not move MFE", NearlyEqual(g_mfe, 2600.00));
   Check("a NONE direction does not move MAE", NearlyEqual(g_mae, 2600.00));

   // No original risk distance means no fabricated R. An adopted position has none.
   Check("no risk distance yields no R",
         NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, 2612.00, 0.0), 0.0));
   Check("negative risk distance yields no R",
         NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, 2612.00, -6.00), 0.0));
   Check("non-finite excursion yields no R",
         NearlyEqual(XSparkExcursionR(XSPARK_SIGNAL_BUY, 2600.00, excursion_infinity, 6.00), 0.0));
}

// The entry deviation is the amount by which a permitted fill can push realised
// risk past selected risk. Whether that is a BOUND depends on the smallest stop
// the configuration can produce, which is set by the ATR floor and the stop
// multiple - so the same deviation is a control on one instrument and inert on
// another. These cases pin both ends of that.
void TestEntryDriftBound()
{
   double min_stop = 0.0;
   double ratio = 0.0;
   string reason = "";

   // The shipped gold configuration: 30 points against a stop that the ATR
   // floor guarantees is at least 1.5 x 80 = 120 points. A permitted fill can
   // realise up to 125% of selected risk. That is a real cost an operator
   // should see, so it WARNS rather than passing silently - the threshold is
   // NOT set to hide the shipped defaults.
   Check("gold defaults warn rather than fault",
         XSparkEntryDriftBound(XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS, 1.5, 80.0,
                               min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_WARN);
   Check("gold defaults imply a 120 point minimum stop", NearlyEqual(min_stop, 120.0));
   Check("gold defaults overshoot by a quarter", NearlyEqual(ratio, 0.25));
   Check("gold warning states the realised risk", StringFind(reason, "125%") >= 0);

   // The exact defect DEPLOYMENT.md recorded: the gold deviation left in place
   // on an FX pair, where a ScoreBot point is a pip and the stop is an order of
   // magnitude smaller. 30 pips of permitted slip against a 15 pip stop means a
   // fill can land at or past its own stop.
   Check("gold deviation on an FX pair faults",
         XSparkEntryDriftBound(30.0, 1.5, 10.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("FX misconfiguration overshoots by 200%", NearlyEqual(ratio, 2.0));
   Check("FX fault names the untethered risk", StringFind(reason, "untethered") >= 0);

   // The same instrument once the deviation is set FOR it.
   Check("FX deviation set for the instrument passes",
         XSparkEntryDriftBound(2.0, 1.5, 10.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_OK);
   Check("configured FX minimum stop is 15 pips", NearlyEqual(min_stop, 15.0));

   // Boundaries. 24/120 and 120/120 are both exact in binary64, so these pin
   // the comparison operators and not a rounding accident.
   Check("ratio exactly at the warn threshold does not warn",
         XSparkEntryDriftBound(24.0, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_OK);
   Check("warn threshold boundary ratio is exact", NearlyEqual(ratio, XSPARK_DRIFT_RATIO_WARN));
   Check("just above the warn threshold warns",
         XSparkEntryDriftBound(24.1, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_WARN);
   Check("deviation equal to the whole stop faults",
         XSparkEntryDriftBound(120.0, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("fault threshold boundary ratio is exact", NearlyEqual(ratio, XSPARK_DRIFT_RATIO_FAULT));
   Check("just below the whole stop still only warns",
         XSparkEntryDriftBound(119.0, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_WARN);

   // Fails CLOSED. An unusable configuration number is the state in which the
   // caller must NOT assume the gate is working, so every one of these is a
   // fault and none is a pass.
   Check("zero deviation faults",
         XSparkEntryDriftBound(0.0, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("negative deviation faults",
         XSparkEntryDriftBound(-30.0, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("zero stop multiple faults",
         XSparkEntryDriftBound(30.0, 0.0, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("negative stop multiple faults",
         XSparkEntryDriftBound(30.0, -1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("zero ATR floor faults",
         XSparkEntryDriftBound(30.0, 1.5, 0.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("negative ATR floor faults",
         XSparkEntryDriftBound(30.0, 1.5, -80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);

   const double drift_infinity = MathPow(10.0, 400.0);
   const double drift_nan = drift_infinity - drift_infinity;

   Check("non-finite deviation faults",
         XSparkEntryDriftBound(drift_nan, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("infinite deviation faults",
         XSparkEntryDriftBound(drift_infinity, 1.5, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("non-finite stop multiple faults",
         XSparkEntryDriftBound(30.0, drift_nan, 80.0, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("non-finite ATR floor faults",
         XSparkEntryDriftBound(30.0, 1.5, drift_nan, min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);

   // Both inputs here are FINITE and positive, so the earlier guards pass and
   // the product itself is what overflows. This is the branch that catches it;
   // using an infinite input instead would have been caught upstream and would
   // have tested nothing.
   Check("overflowing minimum stop faults",
         XSparkEntryDriftBound(30.0, 1.0e200, 1.0e200,
                               min_stop, ratio, reason) == XSPARK_DRIFT_BOUND_FAULT);
   Check("overflowing minimum stop names the stop distance",
         StringFind(reason, "Minimum stop distance") >= 0);

   // Every fault path must leave a reason; a silent fault is a fault an
   // operator cannot act on.
   Check("faults always carry a reason", StringLen(reason) > 0);
}

// The optimisation fitness. The property that matters most is the one the plan
// warns about: the fitness must NOT reward trading more at identical evidence.
void TestRLedgerFitness()
{
   XSparkRLedger ledger;
   XSparkResetRLedger(ledger);

   Check("empty ledger counts zero", ledger.count == 0);
   Check("empty ledger means zero", NearlyEqual(XSparkRLedgerMean(ledger), 0.0));
   Check("empty ledger has no dispersion", NearlyEqual(XSparkRLedgerStdDev(ledger), 0.0));
   Check("empty ledger returns the sentinel",
         NearlyEqual(XSparkRLedgerFitness(ledger, 1.0, 30), XSPARK_FITNESS_SENTINEL));

   // Four trades: +2, -1, -1, +2 -> mean 0.5.
   XSparkRLedgerAdd(ledger, 2.0);
   XSparkRLedgerAdd(ledger, -1.0);
   XSparkRLedgerAdd(ledger, -1.0);
   XSparkRLedgerAdd(ledger, 2.0);

   Check("count accumulates", ledger.count == 4);
   Check("mean R is correct", NearlyEqual(XSparkRLedgerMean(ledger), 0.5));
   Check("min R is tracked", NearlyEqual(ledger.min_r, -1.0));
   Check("max R is tracked", NearlyEqual(ledger.max_r, 2.0));

   // Sample stdev of {2,-1,-1,2}: deviations 1.5,-1.5,-1.5,1.5 -> sum sq 9 -> /3 = 3 -> sqrt = 1.7320508
   Check("sample stdev uses n-1", NearlyEqual(XSparkRLedgerStdDev(ledger), MathSqrt(3.0)));

   // Below the minimum trade count the pass must not compete with real results.
   Check("a short pass returns the sentinel",
         NearlyEqual(XSparkRLedgerFitness(ledger, 1.0, 30), XSPARK_FITNESS_SENTINEL));

   // At the minimum, fitness = mean - k * stdev / sqrt(n).
   const double expected = 0.5 - 1.0 * MathSqrt(3.0) / MathSqrt(4.0);
   Check("fitness is the mean penalised by its standard error",
         NearlyEqual(XSparkRLedgerFitness(ledger, 1.0, 4), expected));
   Check("k scales the penalty",
         NearlyEqual(XSparkRLedgerFitness(ledger, 2.0, 4), 0.5 - 2.0 * MathSqrt(3.0) / 2.0));
   Check("k of zero leaves the bare mean",
         NearlyEqual(XSparkRLedgerFitness(ledger, 0.0, 4), 0.5));

   // THE PROPERTY THAT MATTERS. Two passes with identical mean and dispersion,
   // one trading four times as often. The rejected form n*mean - k*stdev*sqrt(n)
   // factors as sd*sqrt(n)*(t-k) and RISES with n at fixed t, so it would prefer
   // the busier pass and push every sweep toward the loosest possible gate. The
   // form used here must prefer the pass with MORE EVIDENCE, not more activity -
   // so at an identical mean, more trades is better only because the standard
   // error shrinks, and never merely because the count is larger.
   XSparkRLedger small;
   XSparkRLedger large;
   XSparkResetRLedger(small);
   XSparkResetRLedger(large);

   for(int i = 0; i < 4; i++)
   {
      XSparkRLedgerAdd(small, 2.0);
      XSparkRLedgerAdd(small, -1.0);
   }
   for(int j = 0; j < 16; j++)
   {
      XSparkRLedgerAdd(large, 2.0);
      XSparkRLedgerAdd(large, -1.0);
   }

   Check("both passes share a mean", NearlyEqual(XSparkRLedgerMean(small), XSparkRLedgerMean(large)));
   // Not identical: the n-1 correction makes the smaller sample's dispersion
   // slightly larger (1.6036 vs 1.5240), converging as n grows. Close enough
   // that the fitness difference below is driven by the standard error, not by
   // a dispersion gap.
   Check("both passes share a dispersion to within the n-1 correction",
         NearlyEqual(XSparkRLedgerStdDev(small), XSparkRLedgerStdDev(large), 0.1));
   Check("the larger sample scores higher only via its smaller standard error",
         XSparkRLedgerFitness(large, 1.0, 4) > XSparkRLedgerFitness(small, 1.0, 4));

   // A losing pass must score below a winning one regardless of trade count, or
   // the fitness would reward activity over profitability.
   XSparkRLedger losing;
   XSparkResetRLedger(losing);
   for(int m = 0; m < 200; m++)
      XSparkRLedgerAdd(losing, -0.1);
   Check("a busy losing pass scores below a quiet winning one",
         XSparkRLedgerFitness(losing, 1.0, 4) < XSparkRLedgerFitness(small, 1.0, 4));

   // Degenerate and hostile inputs.
   XSparkRLedger single;
   XSparkResetRLedger(single);
   XSparkRLedgerAdd(single, 1.5);
   Check("one observation has no sample dispersion", NearlyEqual(XSparkRLedgerStdDev(single), 0.0));
   Check("one observation degrades to the bare mean",
         NearlyEqual(XSparkRLedgerFitness(single, 1.0, 1), 1.5));

   XSparkRLedger constant;
   XSparkResetRLedger(constant);
   for(int c = 0; c < 10; c++)
      XSparkRLedgerAdd(constant, 0.75);
   Check("zero dispersion leaves the mean unpenalised",
         NearlyEqual(XSparkRLedgerFitness(constant, 1.0, 4), 0.75));

   const double ledger_infinity = MathPow(10.0, 400.0);
   XSparkRLedger guarded;
   XSparkResetRLedger(guarded);
   XSparkRLedgerAdd(guarded, 1.0);
   XSparkRLedgerAdd(guarded, ledger_infinity);
   XSparkRLedgerAdd(guarded, ledger_infinity - ledger_infinity);
   Check("non-finite R multiples are rejected", guarded.count == 1);
   Check("the ledger stays finite after hostile input",
         MathIsValidNumber(XSparkRLedgerMean(guarded)));
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
   TestClosureAccumulation();
   TestExcursionTracking();
   TestEntryDriftBound();
   TestRLedgerFitness();
   PrintFormat("XSpark execution/state hardening tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
