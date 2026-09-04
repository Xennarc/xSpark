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

#endif
