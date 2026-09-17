#ifndef XSPARK_CORE_EXECUTION_MATH_MQH
#define XSPARK_CORE_EXECUTION_MATH_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

// Deterministic, broker-independent helpers used by the execution boundary,
// the position-identity boundary, and the stale-quote safety gate.
// Everything in this file must stay pure so it can be exercised by the
// MQL5 test scripts without a live trade server.

#define XSPARK_PRICE_EPSILON 0.0000001
#define XSPARK_RR_EPSILON 0.0000001
#define XSPARK_FALLBACK_OPEN_TIME_TOLERANCE_SECONDS 2
#define XSPARK_MAX_FUTURE_QUOTE_SKEW_SECONDS 5

// The entry drift gate rejects a fill whose price has moved more than the
// entry deviation away from the price the order was sized against. Because the
// stop is placed relative to that same reference, the deviation is also the
// amount by which a permitted fill can push realised risk past selected risk:
//
//    realised_risk / selected_risk  <=  1 + deviation / risk_distance
//
// The SMALLEST risk distance the strategy can ever produce is fixed by the ATR
// gate, which refuses to trade below the configured ATR floor:
//
//    min_risk_distance = atr_mult_sl * atr_min_score_points
//
// so deviation / min_risk_distance is the worst-case fractional overshoot at
// the current configuration. That ratio, not the raw deviation, is the number
// that has to be sane - and it is instrument-dependent, which is exactly why a
// single compile-time constant was wrong.
//
// FAULT at 1.0 is not a preference. At that ratio the permitted slip equals the
// whole stop distance, so a fill may land at or beyond the position's own stop:
// the gate no longer bounds anything and realised risk is untethered from
// selected risk. WARN at 0.20 is a judgement, set against the headroom the EA
// already declares between selected risk and the per-trade risk cap.
#define XSPARK_DRIFT_RATIO_WARN 0.20
#define XSPARK_DRIFT_RATIO_FAULT 1.0

#define XSPARK_DRIFT_BOUND_OK 0
#define XSPARK_DRIFT_BOUND_WARN 1
#define XSPARK_DRIFT_BOUND_FAULT 2


bool XSparkSignalBarIsSubmittable(const datetime last_submitted_signal_bar_time,
                                  const datetime candidate_signal_bar_time,
                                  string &reason)
{
   reason = "";

   if(candidate_signal_bar_time <= 0)
   {
      reason = "Signal bar time is invalid.";
      return false;
   }

   if(last_submitted_signal_bar_time == candidate_signal_bar_time)
   {
      reason = "Duplicate signal-bar submission blocked.";
      return false;
   }

   return true;
}

double XSparkEntryDrift(const double planned_entry_reference, const double current_entry_reference)
{
   if(planned_entry_reference <= 0.0 || current_entry_reference <= 0.0)
      return 0.0;

   return MathAbs(current_entry_reference - planned_entry_reference);
}

// The configured deviation/slippage is the maximum execution tolerance. Beyond
// it the entry is abandoned instead of chasing the market.
bool XSparkEntryDriftIsWithinTolerance(const double planned_entry_reference,
                                       const double current_entry_reference,
                                       const double max_drift_price,
                                       double &drift)
{
   drift = 0.0;

   if(planned_entry_reference <= 0.0 || current_entry_reference <= 0.0 || max_drift_price <= 0.0)
      return false;

   drift = XSparkEntryDrift(planned_entry_reference, current_entry_reference);
   return drift <= max_drift_price + XSPARK_PRICE_EPSILON;
}

bool XSparkStopIsOnProtectiveSide(const EXSparkSignalDirection direction,
                                  const double entry_reference,
                                  const double stop_price)
{
   if(entry_reference <= 0.0 || stop_price <= 0.0)
      return false;

   if(direction == XSPARK_SIGNAL_BUY)
      return stop_price < entry_reference - XSPARK_PRICE_EPSILON;

   if(direction == XSPARK_SIGNAL_SELL)
      return stop_price > entry_reference + XSPARK_PRICE_EPSILON;

   return false;
}

// Actual monetary risk is driven by the distance between the price we are about
// to trade at and the broker-valid stop, not by the distance planned earlier.
double XSparkRiskDistance(const EXSparkSignalDirection direction,
                          const double entry_reference,
                          const double stop_price)
{
   if(!XSparkStopIsOnProtectiveSide(direction, entry_reference, stop_price))
      return 0.0;

   return MathAbs(entry_reference - stop_price);
}

double XSparkTargetFromRiskDistance(const EXSparkSignalDirection direction,
                                    const double entry_reference,
                                    const double risk_distance,
                                    const double reward_ratio)
{
   if(entry_reference <= 0.0 || risk_distance <= 0.0 || reward_ratio <= 0.0)
      return 0.0;

   if(direction == XSPARK_SIGNAL_BUY)
      return entry_reference + risk_distance * reward_ratio;

   if(direction == XSPARK_SIGNAL_SELL)
      return entry_reference - risk_distance * reward_ratio;

   return 0.0;
}

double XSparkRealizedRR(const double entry_reference,
                        const double target_price,
                        const double risk_distance)
{
   if(entry_reference <= 0.0 || target_price <= 0.0 || risk_distance <= 0.0)
      return 0.0;

   return MathAbs(target_price - entry_reference) / risk_distance;
}

bool XSparkRRIsWithinBounds(const double reward_ratio,
                            const double min_reward_ratio,
                            const double max_reward_ratio)
{
   if(reward_ratio <= 0.0 || min_reward_ratio <= 0.0 || max_reward_ratio < min_reward_ratio)
      return false;

   return reward_ratio >= min_reward_ratio - XSPARK_RR_EPSILON &&
          reward_ratio <= max_reward_ratio + XSPARK_RR_EPSILON;
}

bool XSparkPositionIdentityMatches(const long candidate_position_identifier,
                                   const long expected_position_id)
{
   if(candidate_position_identifier == 0 || expected_position_id == 0)
      return false;

   return candidate_position_identifier == expected_position_id;
}

// Documented fail-safe fallback only. It is used when the broker deal did not
// yield a DEAL_POSITION_ID, and it deliberately refuses anything that could
// belong to a different XSpark position.
bool XSparkFallbackPositionIsAcceptable(const EXSparkSignalDirection plan_direction,
                                        const EXSparkSignalDirection candidate_direction,
                                        const bool candidate_already_tracked,
                                        const datetime candidate_open_time,
                                        const datetime submit_time,
                                        const double candidate_volume,
                                        const double submitted_volume,
                                        const double volume_tolerance)
{
   if(plan_direction == XSPARK_SIGNAL_NONE || candidate_direction != plan_direction)
      return false;

   if(candidate_already_tracked)
      return false;

   if(candidate_open_time <= 0)
      return false;

   if(submit_time > 0 &&
      (long)candidate_open_time + XSPARK_FALLBACK_OPEN_TIME_TOLERANCE_SECONDS < (long)submit_time)
   {
      return false;
   }

   if(submitted_volume > 0.0 && volume_tolerance > 0.0 &&
      MathAbs(candidate_volume - submitted_volume) > volume_tolerance)
   {
      return false;
   }

   return true;
}

long XSparkQuoteAgeSeconds(const datetime quote_time, const datetime reference_time)
{
   return (long)reference_time - (long)quote_time;
}

// Production safety addition (not part of tested ScoreBot_v3 strategy logic):
// a frozen or invalid feed must never be used to open new exposure.
bool XSparkQuoteAgeIsAcceptable(const datetime quote_time,
                                const datetime reference_time,
                                const int max_quote_age_seconds,
                                long &age_seconds,
                                string &reason)
{
   age_seconds = 0;
   reason = "";

   if(max_quote_age_seconds <= 0)
   {
      reason = "Maximum quote age is not configured.";
      return false;
   }

   if(quote_time <= 0)
   {
      reason = "Quote timestamp is invalid.";
      return false;
   }

   if(reference_time <= 0)
   {
      reason = "Server reference time is invalid.";
      return false;
   }

   age_seconds = XSparkQuoteAgeSeconds(quote_time, reference_time);

   if(age_seconds < -(long)XSPARK_MAX_FUTURE_QUOTE_SKEW_SECONDS)
   {
      reason = StringFormat("Quote timestamp is %I64d seconds ahead of server time.", -age_seconds);
      return false;
   }

   if(age_seconds > (long)max_quote_age_seconds)
   {
      reason = StringFormat("Quote is %I64d seconds old; maximum allowed is %d.",
                            age_seconds,
                            max_quote_age_seconds);
      return false;
   }

   return true;
}

// Reports whether the entry deviation still bounds realised risk at the
// configured ATR floor and stop multiple. Pure: every input is a configuration
// number, so this is decidable at initialisation, before any trade exists.
//
// Fails CLOSED. A non-finite or non-positive input is a fault, not a pass,
// because an unusable ratio is exactly the state in which the caller must not
// assume the gate is working.
int XSparkEntryDriftBound(const double deviation_score_points,
                          const double atr_mult_sl,
                          const double atr_min_score_points,
                          double &min_risk_distance_score_points,
                          double &overshoot_ratio,
                          string &reason)
{
   min_risk_distance_score_points = 0.0;
   overshoot_ratio = 0.0;
   reason = "";

   if(!MathIsValidNumber(deviation_score_points) || deviation_score_points <= 0.0)
   {
      reason = "Entry deviation is not a finite positive number of ScoreBot points.";
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   if(!MathIsValidNumber(atr_mult_sl) || atr_mult_sl <= 0.0)
   {
      reason = "ATR stop multiple is not a finite positive number.";
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   if(!MathIsValidNumber(atr_min_score_points) || atr_min_score_points <= 0.0)
   {
      reason = "Minimum ATR is not a finite positive number of ScoreBot points.";
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   min_risk_distance_score_points = atr_mult_sl * atr_min_score_points;

   if(!MathIsValidNumber(min_risk_distance_score_points) || min_risk_distance_score_points <= 0.0)
   {
      reason = "Minimum stop distance implied by the ATR floor is not usable.";
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   overshoot_ratio = deviation_score_points / min_risk_distance_score_points;

   if(!MathIsValidNumber(overshoot_ratio))
   {
      reason = "Worst-case realised-risk overshoot ratio is not a finite number.";
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   if(overshoot_ratio >= XSPARK_DRIFT_RATIO_FAULT)
   {
      reason = StringFormat("Entry deviation %.2f ScoreBot points is %.0f%% of the smallest stop this configuration can produce (%.2f points = %.2f x %.2f ATR floor). A permitted fill can land at or beyond its own stop, so the drift gate bounds nothing and realised risk is untethered from selected risk.",
                            deviation_score_points,
                            overshoot_ratio * 100.0,
                            min_risk_distance_score_points,
                            atr_mult_sl,
                            atr_min_score_points);
      return XSPARK_DRIFT_BOUND_FAULT;
   }

   if(overshoot_ratio > XSPARK_DRIFT_RATIO_WARN)
   {
      reason = StringFormat("Entry deviation %.2f ScoreBot points is %.0f%% of the smallest stop this configuration can produce (%.2f points). A permitted fill can realise up to %.0f%% of selected risk.",
                            deviation_score_points,
                            overshoot_ratio * 100.0,
                            min_risk_distance_score_points,
                            (1.0 + overshoot_ratio) * 100.0);
      return XSPARK_DRIFT_BOUND_WARN;
   }

   reason = StringFormat("Entry deviation %.2f ScoreBot points is %.0f%% of the smallest stop this configuration can produce (%.2f points).",
                         deviation_score_points,
                         overshoot_ratio * 100.0,
                         min_risk_distance_score_points);
   return XSPARK_DRIFT_BOUND_OK;
}

#endif
