#property script_show_inputs
#include <XSpark/Strategy/TrendScalp.mqh>

// Deterministic checks for the TrendScalp rules.
//
// These cover pure arithmetic only: the timeframe table, the six-step entry
// rule in both directions, the wick buffer and anchor, the round-trip cost,
// the stop with its three floors and its two refusal wordings, the exit-style
// arithmetic, the session windows, the daily cap, the input resolver, the
// Wilson bound, the Friday close and the minimum-lot risk. Broker behaviour,
// sizing and execution are not exercised here and must be validated in the
// Strategy Tester and on a demo account. Nothing here measures an edge.

int g_scalp_passed = 0, g_scalp_failed = 0;

void ScalpCheck(const string name, const bool ok)
{
   if(ok) { g_scalp_passed++; Print("PASS: ",name); }
   else { g_scalp_failed++; Print("FAIL: ",name); }
}

void ScalpBar(XSparkCandle &bar,
              const double open,
              const double high,
              const double low,
              const double close)
{
   bar.time = (datetime)3000000;
   bar.open = open;
   bar.high = high;
   bar.low = low;
   bar.close = close;
   bar.tick_volume = 100;
}

bool ScalpNear(const double a, const double b, const double tolerance = 0.0000001)
{
   return MathAbs(a - b) < tolerance;
}

// One supported period maps to a strictly longer partner. Period enums are
// ordered by duration in MQL5 and in the portable adapter, so the comparison
// needs no PeriodSeconds.
bool ScalpMapsUp(const ENUM_TIMEFRAMES base, const ENUM_TIMEFRAMES expected)
{
   ENUM_TIMEFRAMES higher = PERIOD_CURRENT;
   string reason = "";
   return XSparkTrendScalpHigherTimeframeFor(base, higher, reason) && higher == expected && higher > base;
}

void RunTrendScalpTimeframeTests()
{
   ScalpCheck("M1 pairs with M15", ScalpMapsUp(PERIOD_M1, PERIOD_M15));
   ScalpCheck("M2 pairs with M15", ScalpMapsUp(PERIOD_M2, PERIOD_M15));
   ScalpCheck("M3 pairs with M15", ScalpMapsUp(PERIOD_M3, PERIOD_M15));
   ScalpCheck("M4 pairs with M30", ScalpMapsUp(PERIOD_M4, PERIOD_M30));
   ScalpCheck("M5 pairs with M30", ScalpMapsUp(PERIOD_M5, PERIOD_M30));
   ScalpCheck("M6 pairs with M30", ScalpMapsUp(PERIOD_M6, PERIOD_M30));
   ScalpCheck("M10 pairs with H1", ScalpMapsUp(PERIOD_M10, PERIOD_H1));
   ScalpCheck("M12 pairs with H1", ScalpMapsUp(PERIOD_M12, PERIOD_H1));
   ScalpCheck("M15 pairs with H1", ScalpMapsUp(PERIOD_M15, PERIOD_H1));
   ScalpCheck("M20 pairs with H2", ScalpMapsUp(PERIOD_M20, PERIOD_H2));
   ScalpCheck("M30 pairs with H2", ScalpMapsUp(PERIOD_M30, PERIOD_H2));
   ScalpCheck("H1 pairs with H2, not H4", ScalpMapsUp(PERIOD_H1, PERIOD_H2));

   ENUM_TIMEFRAMES higher = PERIOD_H4;
   string reason = "";
   ScalpCheck("H2 is refused", !XSparkTrendScalpHigherTimeframeFor(PERIOD_H2, higher, reason));
   ScalpCheck("a refusal clears the partner", higher == PERIOD_CURRENT && StringLen(reason) > 0);
   ScalpCheck("H4 is refused", !XSparkTrendScalpHigherTimeframeFor(PERIOD_H4, higher, reason));
   ScalpCheck("D1 is refused", !XSparkTrendScalpHigherTimeframeFor(PERIOD_D1, higher, reason));

   ScalpCheck("M1 holds at most twelve minutes", XSparkTrendScalpMaxHoldSeconds(60) == 720);
   ScalpCheck("M15 holds at most three hours", XSparkTrendScalpMaxHoldSeconds(900) == 10800);
   ScalpCheck("H1 is capped at six hours, not twelve", XSparkTrendScalpMaxHoldSeconds(3600) == 21600);
   ScalpCheck("an unusable period has no hold limit to report", XSparkTrendScalpMaxHoldSeconds(0) == 0 &&
                                                                XSparkTrendScalpMaxHoldSeconds(-60) == 0);

   ScalpCheck("M1 calibrates on five days of bars", XSparkTrendScalpCalibrationBars(60) == 7200);
   ScalpCheck("M5 calibrates on five days of bars", XSparkTrendScalpCalibrationBars(300) == 1440);
   ScalpCheck("M15 calibrates on the shared floor", XSparkTrendScalpCalibrationBars(900) == 500);
   ScalpCheck("H1 calibrates on the shared floor", XSparkTrendScalpCalibrationBars(3600) == 500);
   ScalpCheck("the sample never exceeds the cap", XSparkTrendScalpCalibrationBars(1) == 10080);
   ScalpCheck("an unusable period has no sample", XSparkTrendScalpCalibrationBars(0) == 0);
}

void RunTrendScalpConstantTests()
{
   // A retune that lowered the coarse backstop below the strategy's own cost
   // floor would make SafetyManager's message the one an operator reads,
   // without the two numbers that say what to change.
   ScalpCheck("the coarse spread backstop sits above the cost floor at the widest stop",
              XSPARK_TRENDSCALP_MAX_SPREAD_ATR_PCT > XSPARK_TRENDSCALP_MAX_COST_SHARE_PCT * XSPARK_TRENDSCALP_MAX_STOP_ATR);
   ScalpCheck("the shipped small-account cap passes its own ceiling",
              XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT <= XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT);
   ScalpCheck("the account cap cannot refuse a permitted minimum-lot trade",
              XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT >= XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT);
   ScalpCheck("the shipped risk passes its own ceiling",
              XSPARK_TRENDSCALP_DEFAULT_RISK_PCT <= XSPARK_TRENDSCALP_MAX_RISK_PCT);
   ScalpCheck("the shipped daily stop sits below the shipped emergency stop",
              XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT < XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT);
   ScalpCheck("the time stop never exceeds six hours on any supported period",
              XSPARK_TRENDSCALP_MAX_HOLD_BARS * 3600 > XSPARK_TRENDSCALP_MAX_HOLD_SECONDS);
}

void RunTrendScalpRuleTests()
{
   XSparkTrendScalpConfig config;
   XSparkDefaultTrendScalpConfig(config);
   XSparkTrendScalpVerdicts verdicts;
   string reason = "";

   // Uptrend geometry: fast 100, slow 99 (one typical candle apart), higher
   // slow average 98, typical candle 1.0.
   XSparkCandle bar;

   ScalpBar(bar, 99.8, 100.6, 99.9, 100.5);
   ScalpCheck("a pullback that touched and reclaimed the fast average in an uptrend is a long",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_BUY &&
              verdicts.trend == "UPTREND" && verdicts.pullback == "TOUCH+RECLAIM");

   // Downtrend mirror: fast 100, slow 101, higher slow 102.
   ScalpBar(bar, 100.1, 100.2, 99.4, 99.5);
   ScalpCheck("the mirror pullback in a downtrend is a short",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 102.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_SELL &&
              verdicts.trend == "DOWNTREND" && verdicts.pullback == "TOUCH+RECLAIM");

   ScalpBar(bar, 99.8, 100.6, 99.9, 100.5);
   ScalpCheck("averages closer than the gap are no trend",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.9, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "NO TREND");
   ScalpCheck("an uptrend under the higher period's slow average is a bias conflict",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 101.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "BIAS CONFLICT");
   ScalpBar(bar, 100.1, 100.2, 99.4, 99.5);
   ScalpCheck("a downtrend above the higher period's slow average is a bias conflict",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 99.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "BIAS CONFLICT");

   ScalpBar(bar, 100.3, 100.9, 100.2, 100.8);
   ScalpCheck("a long candle that never reached the fast average is no touch",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "UPTREND" && verdicts.pullback == "NO TOUCH");
   ScalpBar(bar, 99.7, 99.8, 99.1, 99.2);
   ScalpCheck("a short candle that never reached the fast average is no touch",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 102.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "DOWNTREND" && verdicts.pullback == "NO TOUCH");

   ScalpBar(bar, 100.2, 100.4, 99.6, 99.8);
   ScalpCheck("a long candle that closed below the fast average is not reclaimed",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "NOT RECLAIMED");
   ScalpBar(bar, 100.6, 100.7, 99.9, 100.3);
   ScalpCheck("a long candle above the average but below its own open is not reclaimed",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "NOT RECLAIMED");
   ScalpBar(bar, 99.8, 100.4, 99.6, 100.2);
   ScalpCheck("a short candle that closed above the fast average is not reclaimed",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 102.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "NOT RECLAIMED");

   ScalpBar(bar, 100.05, 101.0, 99.9, 100.2);
   ScalpCheck("a long close in the lower half of its range is a weak close",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "WEAK CLOSE");
   ScalpBar(bar, 99.95, 100.1, 99.0, 99.8);
   ScalpCheck("a short close in the upper half of its range is a weak close",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 102.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "WEAK CLOSE");

   ScalpBar(bar, 99.9, 101.6, 99.9, 101.5);
   ScalpCheck("a long close more than a typical candle past the average is overextended",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "OVEREXTENDED");
   ScalpBar(bar, 100.1, 100.1, 98.4, 98.5);
   ScalpCheck("a short close more than a typical candle past the average is overextended",
              XSparkTrendScalpBarDirection(bar, 100.0, 101.0, 102.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.pullback == "OVEREXTENDED");

   ScalpBar(bar, 99.8, 100.6, 99.9, 100.5);
   ScalpCheck("a missing typical candle size refuses rather than passes",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 98.0, 0.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "NO DATA");
   ScalpCheck("a zero average is a warm-up, not a price",
              XSparkTrendScalpBarDirection(bar, 100.0, 99.0, 0.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE &&
              verdicts.trend == "NO DATA");
   XSparkCandle inverted; ScalpBar(inverted, 100.0, 99.0, 101.0, 100.5);
   ScalpCheck("an impossible candle range is refused",
              XSparkTrendScalpBarDirection(inverted, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE);
   XSparkCandle flat; ScalpBar(flat, 100.2, 100.2, 100.2, 100.2);
   ScalpCheck("a candle with no range has no close position and is refused",
              XSparkTrendScalpBarDirection(flat, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE);
   XSparkCandle unpriced; ScalpBar(unpriced, 0.0, 100.6, 99.9, 100.5);
   ScalpCheck("an unusable price is refused",
              XSparkTrendScalpBarDirection(unpriced, 100.0, 99.0, 98.0, 1.0, config, verdicts, reason) == XSPARK_SIGNAL_NONE);
   ScalpCheck("every refusal says why", StringLen(reason) > 0);
}

void RunTrendScalpAnchorTests()
{
   string reason = "";
   double buffer = 0.0;
   ScalpCheck("the buffer is a share of the typical candle",
              XSparkTrendScalpBuffer(2.0, 0.15, buffer, reason) && ScalpNear(buffer, 0.3));
   ScalpCheck("a buffer without a typical candle size refuses",
              !XSparkTrendScalpBuffer(0.0, 0.15, buffer, reason));
   ScalpCheck("a zero or negative buffer multiple refuses",
              !XSparkTrendScalpBuffer(2.0, 0.0, buffer, reason) && !XSparkTrendScalpBuffer(2.0, -0.1, buffer, reason));

   XSparkCandle bar; ScalpBar(bar, 99.8, 100.6, 99.9, 100.5);
   double anchor = 0.0;
   ScalpCheck("a long anchors below the candle low",
              XSparkTrendScalpAnchor(XSPARK_SIGNAL_BUY, bar, 0.15, anchor, reason) && ScalpNear(anchor, 99.75));
   ScalpCheck("a short anchors above the candle high",
              XSparkTrendScalpAnchor(XSPARK_SIGNAL_SELL, bar, 0.15, anchor, reason) && ScalpNear(anchor, 100.75));
   ScalpCheck("an anchor needs a direction",
              !XSparkTrendScalpAnchor(XSPARK_SIGNAL_NONE, bar, 0.15, anchor, reason));
   ScalpCheck("a buffer that drives the anchor below zero refuses",
              !XSparkTrendScalpAnchor(XSPARK_SIGNAL_BUY, bar, 200.0, anchor, reason));
}

void RunTrendScalpCostTests()
{
   string reason = "";
   double cost = 0.0, commission_price = 0.0;

   ScalpCheck("gold: 7 per lot at a 0.01 tick worth 1 is 0.07 of price on top of the spread",
              XSparkTrendScalpRoundTripCost(0.20, 7.0, 0.01, 1.0, cost, commission_price, reason) &&
              ScalpNear(commission_price, 0.07) && ScalpNear(cost, 0.27));
   ScalpCheck("EURUSD: 7 per lot at a 0.00001 tick worth 1 is 0.7 pip on top of the spread",
              XSparkTrendScalpRoundTripCost(0.00010, 7.0, 0.00001, 1.0, cost, commission_price, reason) &&
              ScalpNear(commission_price, 0.00007, 0.0000000001) && ScalpNear(cost, 0.00017, 0.0000000001));
   ScalpCheck("a commission of zero is valid and the cost is the spread alone",
              XSparkTrendScalpRoundTripCost(0.20, 0.0, 0.01, 1.0, cost, commission_price, reason) &&
              ScalpNear(commission_price, 0.0) && ScalpNear(cost, 0.20));
   ScalpCheck("a negative spread is refused",
              !XSparkTrendScalpRoundTripCost(-0.01, 7.0, 0.01, 1.0, cost, commission_price, reason));
   ScalpCheck("a negative commission is refused",
              !XSparkTrendScalpRoundTripCost(0.20, -7.0, 0.01, 1.0, cost, commission_price, reason));
   ScalpCheck("an unusable tick value refuses rather than dividing by it",
              !XSparkTrendScalpRoundTripCost(0.20, 7.0, 0.01, 0.0, cost, commission_price, reason) && cost == 0.0);
}

void RunTrendScalpStopTests()
{
   XSparkTrendScalpConfig config;
   XSparkDefaultTrendScalpConfig(config);
   string reason = "";
   double stop = 0.0, distance = 0.0;

   // Reference 100, typical candle 1.0: floor 1.0, ceiling 2.5, and a cost
   // of 0.03 makes a 0.5 cost floor at the 6% share.
   ScalpCheck("the candle stop is used when it is the widest term",
              XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 98.5, 1.0, 0.03, config, stop, distance, reason) &&
              ScalpNear(distance, 1.5) && ScalpNear(stop, 98.5));
   ScalpCheck("a stop tighter than one typical candle is widened to the floor",
              XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 99.7, 1.0, 0.03, config, stop, distance, reason) &&
              ScalpNear(distance, 1.0) && ScalpNear(stop, 99.0));
   ScalpCheck("widening to the floor never crosses the reference price", stop < 100.0);
   ScalpCheck("the cost floor widens the stop so the cost stays at the permitted share",
              XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 99.7, 1.0, 0.09, config, stop, distance, reason) &&
              ScalpNear(distance, 1.5) && ScalpNear(stop, 98.5));
   ScalpCheck("a pullback deeper than the ceiling is refused as too deep",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 97.0, 1.0, 0.03, config, stop, distance, reason) &&
              StringFind(reason, "too deep") >= 0 && StringFind(reason, "COST") < 0);
   ScalpCheck("a cost floor above the ceiling is refused with the COST wording and its two numbers",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 99.7, 1.0, 0.18, config, stop, distance, reason) &&
              StringFind(reason, "COST") == 0 && StringFind(reason, "7.2%") >= 0 && StringFind(reason, "6.0%") >= 0);
   ScalpCheck("a refused stop leaves nothing to size from", stop == 0.0 && distance == 0.0);
   ScalpCheck("a short widens to the floor above the reference",
              XSparkTrendScalpStop(XSPARK_SIGNAL_SELL, 100.0, 100.3, 1.0, 0.03, config, stop, distance, reason) &&
              ScalpNear(distance, 1.0) && ScalpNear(stop, 101.0));
   ScalpCheck("a short candle stop is used when it is the widest term",
              XSparkTrendScalpStop(XSPARK_SIGNAL_SELL, 100.0, 102.0, 1.0, 0.03, config, stop, distance, reason) &&
              ScalpNear(distance, 2.0) && ScalpNear(stop, 102.0));
   ScalpCheck("an anchor already crossed by price is rescued by the floor",
              XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 100.4, 1.0, 0.03, config, stop, distance, reason) &&
              ScalpNear(stop, 99.0));
   ScalpCheck("a negative cost is refused",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 98.5, 1.0, -0.01, config, stop, distance, reason));
   ScalpCheck("an unusable reference is refused",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 0.0, 98.5, 1.0, 0.03, config, stop, distance, reason));
   ScalpCheck("a missing typical candle size refuses the bounds",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_BUY, 100.0, 98.5, 0.0, 0.03, config, stop, distance, reason));
   ScalpCheck("a stop needs a direction",
              !XSparkTrendScalpStop(XSPARK_SIGNAL_NONE, 100.0, 98.5, 1.0, 0.03, config, stop, distance, reason));
}

void RunTrendScalpExitStyleTests()
{
   string reason = "";
   double target = 0.0;
   ScalpCheck("the even style targets one stop",
              XSparkTrendScalpTargetForStyle(XSPARK_SCALP_EXIT_EVEN, target, reason) && ScalpNear(target, 1.0));
   ScalpCheck("the quick style targets 0.8 of the stop",
              XSparkTrendScalpTargetForStyle(XSPARK_SCALP_EXIT_QUICK, target, reason) && ScalpNear(target, 0.8));
   ScalpCheck("a style this build does not know is refused rather than guessed",
              !XSparkTrendScalpTargetForStyle((EXSparkScalpExitStyle)99, target, reason) && target == 0.0);

   // The arithmetic in the header comment, at the 6% cost share this design
   // permits. These are the numbers every journal line compares against.
   ScalpCheck("a no-edge trade at a 1:1 target and 6% cost wins 47.0%",
              ScalpNear(XSparkTrendScalpNoEdgeWinRate(1.0, 6.0), 0.470, 0.001));
   ScalpCheck("a no-edge trade at a 0.8:1 target and 6% cost wins 52.2%",
              ScalpNear(XSparkTrendScalpNoEdgeWinRate(0.8, 6.0), 0.522, 0.001));
   ScalpCheck("a 1:1 target breaks even at 50.0%",
              ScalpNear(XSparkTrendScalpBreakEvenWinRate(1.0), 0.500, 0.001));
   ScalpCheck("a 0.8:1 target breaks even at 55.6%",
              ScalpNear(XSparkTrendScalpBreakEvenWinRate(0.8), 0.556, 0.001));
   ScalpCheck("the no-edge rate is below the break-even rate whenever there is a cost",
              XSparkTrendScalpNoEdgeWinRate(1.0, 6.0) < XSparkTrendScalpBreakEvenWinRate(1.0));
   ScalpCheck("an unusable target yields no win rate rather than a plausible one",
              XSparkTrendScalpNoEdgeWinRate(0.0, 6.0) == 0.0 && XSparkTrendScalpBreakEvenWinRate(-1.0) == 0.0);
}

void RunTrendScalpSessionTests()
{
   string reason = "";
   int start = 0, end = 0;
   ScalpCheck("ALL trades 01:00-21:00 UTC",
              XSparkTrendScalpSessionWindow(XSPARK_SCALP_SESSIONS_ALL, start, end, reason) && start == 3600 && end == 75600);
   ScalpCheck("LDN_NY trades 07:00-21:00 UTC",
              XSparkTrendScalpSessionWindow(XSPARK_SCALP_SESSIONS_LDN_NY, start, end, reason) && start == 25200 && end == 75600);
   ScalpCheck("a session choice this build does not know is refused",
              !XSparkTrendScalpSessionWindow((EXSparkScalpSessions)99, start, end, reason) && start == 0 && end == 0);

   const int lead = XSPARK_TRENDSCALP_SESSION_CLOSE_LEAD_SECONDS;
   // A broker on UTC: server seconds of the day are UTC seconds of the day.
   // Day 100 keeps the instants well away from zero.
   const datetime day = (datetime)(100 * 86400);

   ScalpCheck("the first permitted second of ALL is 01:00:00",
              XSparkTrendScalpSessionAllows(day + 3600, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 3599, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("the last permitted second is 15 minutes before the close",
              XSparkTrendScalpSessionAllows(day + 75600 - lead - 1, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 75600 - lead, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("00:00-01:00 UTC is refused in both choices",
              !XSparkTrendScalpSessionAllows(day + 1800, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 1800, 0, XSPARK_SCALP_SESSIONS_LDN_NY, lead, reason));
   ScalpCheck("21:00-24:00 UTC is refused in both choices",
              !XSparkTrendScalpSessionAllows(day + 75600, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 82800, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 86399, 0, XSPARK_SCALP_SESSIONS_LDN_NY, lead, reason));
   ScalpCheck("LDN_NY opens at 07:00 UTC and not a second before",
              XSparkTrendScalpSessionAllows(day + 25200, 0, XSPARK_SCALP_SESSIONS_LDN_NY, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 25199, 0, XSPARK_SCALP_SESSIONS_LDN_NY, lead, reason));
   ScalpCheck("Asian hours are permitted by ALL and refused by LDN_NY",
              XSparkTrendScalpSessionAllows(day + 10800, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 10800, 0, XSPARK_SCALP_SESSIONS_LDN_NY, lead, reason));

   // A broker three hours ahead of UTC: its 04:00 is 01:00 UTC.
   ScalpCheck("a +3 broker's 04:00 is the first permitted minute",
              XSparkTrendScalpSessionAllows(day + 4 * 3600, 3, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 4 * 3600 - 1, 3, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("a +3 broker's 23:59 is 20:59 UTC, inside the lead and refused",
              !XSparkTrendScalpSessionAllows(day + 86340, 3, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   // A broker five hours behind UTC: its 20:00 is 01:00 UTC, and its 23:00
   // is 04:00 UTC the next day - the midnight wrap.
   ScalpCheck("a -5 broker's 20:00 is the first permitted minute",
              XSparkTrendScalpSessionAllows(day + 20 * 3600, -5, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 20 * 3600 - 1, -5, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("a -5 broker's 23:00 wraps to 04:00 UTC and is permitted",
              XSparkTrendScalpSessionAllows(day + 23 * 3600, -5, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("a +3 broker's 01:00 wraps to 22:00 UTC the day before and is refused",
              !XSparkTrendScalpSessionAllows(day + 3600, 3, XSPARK_SCALP_SESSIONS_ALL, lead, reason));

   ScalpCheck("an offset outside -12..14 is refused",
              !XSparkTrendScalpSessionAllows(day + 36000, 15, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              !XSparkTrendScalpSessionAllows(day + 36000, -13, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   // +14: server 10:00 is 20:00 UTC the day before; -12: server 01:00 is
   // 13:00 UTC. Both inside the window, so both bounds must be accepted.
   ScalpCheck("the offset bounds themselves are permitted",
              XSparkTrendScalpSessionAllows(day + 36000, 14, XSPARK_SCALP_SESSIONS_ALL, lead, reason) &&
              XSparkTrendScalpSessionAllows(day + 3600, -12, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("an unknown session choice never permits an entry",
              !XSparkTrendScalpSessionAllows(day + 36000, 0, (EXSparkScalpSessions)99, lead, reason));
   ScalpCheck("a lead that swallows the window or runs backwards is refused",
              !XSparkTrendScalpSessionAllows(day + 36000, 0, XSPARK_SCALP_SESSIONS_ALL, 72000, reason) &&
              !XSparkTrendScalpSessionAllows(day + 36000, 0, XSPARK_SCALP_SESSIONS_ALL, -1, reason));
   ScalpCheck("an unusable broker time is refused",
              !XSparkTrendScalpSessionAllows((datetime)0, 0, XSPARK_SCALP_SESSIONS_ALL, lead, reason));
   ScalpCheck("a session refusal says why", StringLen(reason) > 0);

   datetime flatten = 0;
   ScalpCheck("inside the window the flatten instant is today's close",
              XSparkTrendScalpSessionEnd(day + 36000, 0, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) &&
              flatten == day + 75600);
   ScalpCheck("inside the window on a +3 broker the close is expressed on its clock",
              XSparkTrendScalpSessionEnd(day + 13 * 3600, 3, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) &&
              flatten == day + 24 * 3600);
   ScalpCheck("in the lead the flatten instant is still the close, not now",
              XSparkTrendScalpSessionEnd(day + 75600 - 60, 0, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) &&
              flatten == day + 75600);
   ScalpCheck("outside the window the flatten instant is now",
              XSparkTrendScalpSessionEnd(day + 80000, 0, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) &&
              flatten == day + 80000);
   ScalpCheck("before the window opens the flatten instant is now",
              XSparkTrendScalpSessionEnd(day + 1800, 0, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) &&
              flatten == day + 1800);
   ScalpCheck("Asian hours are outside LDN_NY and flatten now",
              XSparkTrendScalpSessionEnd(day + 10800, 0, XSPARK_SCALP_SESSIONS_LDN_NY, flatten, reason) &&
              flatten == day + 10800);
   ScalpCheck("an unknown session choice yields no flatten instant",
              !XSparkTrendScalpSessionEnd(day + 36000, 0, (EXSparkScalpSessions)99, flatten, reason) && flatten == 0);
   ScalpCheck("an invalid offset yields no flatten instant",
              !XSparkTrendScalpSessionEnd(day + 36000, 20, XSPARK_SCALP_SESSIONS_ALL, flatten, reason) && flatten == 0);

   ScalpCheck("a measured offset equal to the setting matches",
              XSparkTrendScalpOffsetMatches(3, 3, reason) && reason == "");
   ScalpCheck("a mismatch is refused and names both numbers",
              !XSparkTrendScalpOffsetMatches(2, 3, reason) &&
              StringFind(reason, "2 hours") >= 0 && StringFind(reason, "says 3") >= 0);
}

void RunTrendScalpDailyCapTests()
{
   string reason = "";
   ScalpCheck("a fresh day is allowed", XSparkTrendScalpDailyCapAllows(0, 40, reason));
   ScalpCheck("the last trade under the cap is allowed", XSparkTrendScalpDailyCapAllows(39, 40, reason));
   ScalpCheck("the cap itself refuses", !XSparkTrendScalpDailyCapAllows(40, 40, reason));
   ScalpCheck("past the cap refuses", !XSparkTrendScalpDailyCapAllows(41, 40, reason));
   ScalpCheck("an unreadable count (-1) refuses rather than guesses",
              !XSparkTrendScalpDailyCapAllows(-1, 40, reason) && StringFind(reason, "unavailable") >= 0);
   ScalpCheck("a cap of zero refuses", !XSparkTrendScalpDailyCapAllows(0, 0, reason));
   ScalpCheck("the shipped cap is a usable count", XSparkTrendScalpDailyCapAllows(0, XSPARK_TRENDSCALP_MAX_TRADES_PER_DAY, reason));
}

void RunTrendScalpWeekendTests()
{
   bool use_close = true;
   int close_hour = -1, close_minute = -1;
   string reason = "";

   ScalpCheck("a market that trades at the weekend is not closed before it",
              XSparkTrendScalpWeekendClose(true, true, 79200, use_close, close_hour, close_minute, reason) && !use_close);
   ScalpCheck("a Friday session ending at 22:00 closes at 21:00",
              XSparkTrendScalpWeekendClose(false, true, 79200, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == 21 && close_minute == 0);
   // 86400 is how the terminal reports a session ending at 24:00. Read
   // through "% 24" it would be 00:00 and the flatten would land a day early.
   ScalpCheck("a Friday session ending at 24:00 (86400) closes at 23:00, not at midnight Friday",
              XSparkTrendScalpWeekendClose(false, true, 86400, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == 23 && close_minute == 0);
   ScalpCheck("a Friday session ending at 23:59:59 (86399) closes at 22:59",
              XSparkTrendScalpWeekendClose(false, true, 86399, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == 22 && close_minute == 59);
   ScalpCheck("an earlier session end moves the close with it",
              XSparkTrendScalpWeekendClose(false, true, 63000, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == 16 && close_minute == 30);
   ScalpCheck("an unreadable session falls back rather than carrying the gap",
              XSparkTrendScalpWeekendClose(false, false, 0, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR &&
              close_minute == XSPARK_TRENDSCALP_WEEKEND_CLOSE_MINUTE);
   ScalpCheck("a negative session end falls back",
              XSparkTrendScalpWeekendClose(false, true, -1, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR);
   ScalpCheck("a session end past 24:00 cannot come from the terminal and falls back",
              XSparkTrendScalpWeekendClose(false, true, 90000, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR);
   ScalpCheck("a session ending inside the lead time closes at midnight, not the day before",
              XSparkTrendScalpWeekendClose(false, true, 1800, use_close, close_hour, close_minute, reason) &&
              use_close && close_hour == 0 && close_minute == 0);
   ScalpCheck("every derived close time is one ShouldWeekendClose can act on",
              close_hour >= 0 && close_hour <= 23 && close_minute >= 0 && close_minute <= 59);
   ScalpCheck("the reason always says which market it is talking about", StringLen(reason) > 0);
}

// The resolver has seven inputs and seven outputs; this keeps each branch's
// check to the one number that branch changes.
bool ScalpResolve(const double raw_risk,
                  const double raw_cap,
                  const double raw_daily,
                  const double raw_total,
                  const bool raw_killswitch,
                  const double raw_commission,
                  const int raw_offset,
                  double &risk,
                  double &cap,
                  double &daily,
                  double &total,
                  bool &killswitch,
                  double &commission,
                  int &offset,
                  string &corrections)
{
   return XSparkTrendScalpResolveLimits(raw_risk,
                                        raw_cap,
                                        raw_daily,
                                        raw_total,
                                        raw_killswitch,
                                        raw_commission,
                                        raw_offset,
                                        risk,
                                        cap,
                                        daily,
                                        total,
                                        killswitch,
                                        commission,
                                        offset,
                                        corrections);
}

void RunTrendScalpResolverTests()
{
   double risk = 0.0, cap = 0.0, daily = 0.0, total = 0.0, commission = 0.0;
   bool killswitch = false;
   int offset = 0;
   string corrections = "";

   ScalpCheck("the shipped defaults resolve with no corrections",
              ScalpResolve(XSPARK_TRENDSCALP_DEFAULT_RISK_PCT,
                           XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT,
                           XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT,
                           XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT,
                           true,
                           XSPARK_TRENDSCALP_DEFAULT_COMMISSION_PER_LOT,
                           XSPARK_TRENDSCALP_DEFAULT_UTC_OFFSET,
                           risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              corrections == "" && risk == XSPARK_TRENDSCALP_DEFAULT_RISK_PCT && killswitch &&
              cap == XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT && commission == 0.0 && offset == 0);

   ScalpCheck("a risk of zero becomes the recommended risk and is reported",
              !ScalpResolve(0.0, 3.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              risk == XSPARK_TRENDSCALP_DEFAULT_RISK_PCT && StringLen(corrections) > 0);
   ScalpCheck("a negative risk becomes the recommended risk",
              !ScalpResolve(-1.0, 3.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              risk == XSPARK_TRENDSCALP_DEFAULT_RISK_PCT);
   ScalpCheck("a risk above the ceiling is clamped to it, not refused",
              !ScalpResolve(5.0, 3.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              risk == XSPARK_TRENDSCALP_MAX_RISK_PCT && StringFind(corrections, "ceiling") >= 0);
   ScalpCheck("a risk exactly at the ceiling is left alone",
              ScalpResolve(XSPARK_TRENDSCALP_MAX_RISK_PCT, 3.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              risk == XSPARK_TRENDSCALP_MAX_RISK_PCT);

   ScalpCheck("a negative small-account cap becomes the recommended cap",
              !ScalpResolve(1.0, -1.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              cap == XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT);
   ScalpCheck("a small-account cap of zero means never raise and is left alone",
              ScalpResolve(1.0, 0.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              cap == 0.0);
   ScalpCheck("a small-account cap above its ceiling is clamped to it",
              !ScalpResolve(1.0, 10.0, 6.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              cap == XSPARK_TRENDSCALP_MAX_MIN_LOT_RISK_PCT);

   ScalpCheck("a daily limit of zero becomes the recommended limit",
              !ScalpResolve(1.0, 3.0, 0.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              daily == XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT);
   ScalpCheck("a daily limit of 100 or more becomes the recommended limit",
              !ScalpResolve(1.0, 3.0, 100.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              daily == XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT);
   ScalpCheck("an emergency level of 100 or more becomes the recommended level with the switch untouched",
              !ScalpResolve(1.0, 3.0, 6.0, 120.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              total == XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT && killswitch);
   ScalpCheck("an emergency level of zero reads as OFF, restores the level and says so at CRITICAL",
              !ScalpResolve(1.0, 3.0, 6.0, 0.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              !killswitch && total == XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT && StringFind(corrections, "OFF") >= 0);
   ScalpCheck("a daily limit at or above the emergency stop is reported and left alone",
              !ScalpResolve(1.0, 3.0, 25.0, 20.0, true, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              daily == 25.0 && total == 20.0 && StringFind(corrections, "never act") >= 0);
   ScalpCheck("with the emergency stop off the daily ordering is not a correction",
              ScalpResolve(1.0, 3.0, 25.0, 20.0, false, 0.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              !killswitch);

   ScalpCheck("a negative commission becomes zero and the under-counting is stated at CRITICAL",
              !ScalpResolve(1.0, 3.0, 6.0, 20.0, true, -7.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              commission == 0.0 && StringFind(corrections, "CRITICAL") >= 0 && StringFind(corrections, "UNDER-COUNTED") >= 0);
   ScalpCheck("a positive commission is carried through unchanged",
              ScalpResolve(1.0, 3.0, 6.0, 20.0, true, 7.0, 0, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              commission == 7.0);

   ScalpCheck("an offset above 14 becomes zero and is stated at CRITICAL",
              !ScalpResolve(1.0, 3.0, 6.0, 20.0, true, 0.0, 15, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              offset == 0 && StringFind(corrections, "CRITICAL") >= 0);
   ScalpCheck("an offset below -12 becomes zero",
              !ScalpResolve(1.0, 3.0, 6.0, 20.0, true, 0.0, -13, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              offset == 0);
   ScalpCheck("an offset inside the range is carried through unchanged",
              ScalpResolve(1.0, 3.0, 6.0, 20.0, true, 0.0, -5, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              offset == -5);

   ScalpCheck("several faults are all reported in one pass",
              !ScalpResolve(0.0, -1.0, 0.0, 0.0, true, -1.0, 99, risk, cap, daily, total, killswitch, commission, offset, corrections) &&
              risk == XSPARK_TRENDSCALP_DEFAULT_RISK_PCT && cap == XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT &&
              daily == XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT && total == XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT &&
              !killswitch && commission == 0.0 && offset == 0);
}

void RunTrendScalpStatisticsTests()
{
   double lower = 1.0;
   ScalpCheck("no outcomes yields no bound, and the bound reads 0",
              !XSparkTrendScalpWilsonLowerBound(0, 0, lower) && lower == 0.0);
   ScalpCheck("55 of 100 cannot be told from 50% at 95%",
              XSparkTrendScalpWilsonLowerBound(55, 100, lower) && lower < 0.5 && lower > 0.4);
   ScalpCheck("220 of 400 can, just",
              XSparkTrendScalpWilsonLowerBound(220, 400, lower) && lower > 0.5 && lower < 0.51);
   ScalpCheck("the bound is always below the observed rate",
              XSparkTrendScalpWilsonLowerBound(300, 400, lower) && lower < 0.75 && lower > 0.70);
   ScalpCheck("a perfect record still has a bound below 1",
              XSparkTrendScalpWilsonLowerBound(50, 50, lower) && lower < 1.0 && lower > 0.9);
   ScalpCheck("more wins than outcomes is refused",
              !XSparkTrendScalpWilsonLowerBound(5, 4, lower) && lower == 0.0);
   ScalpCheck("negative wins are refused",
              !XSparkTrendScalpWilsonLowerBound(-1, 4, lower));

   string reason = "";
   double risk_cash = 0.0, risk_pct = 0.0;
   // 0.01 lot of gold with a $1.50 stop: 150 ticks of $0.01 worth $1 per lot.
   ScalpCheck("0.01 lot of gold with a 1.50 stop risks 1.50, which is 1.5% of 100",
              XSparkTrendScalpMinimumLotRisk(0.01, 1.50, 0.01, 1.0, 100.0, risk_cash, risk_pct, reason) &&
              ScalpNear(risk_cash, 1.50) && ScalpNear(risk_pct, 1.5));
   ScalpCheck("the same trade on 10,000 is 0.015%",
              XSparkTrendScalpMinimumLotRisk(0.01, 1.50, 0.01, 1.0, 10000.0, risk_cash, risk_pct, reason) &&
              ScalpNear(risk_pct, 0.015));
   ScalpCheck("a zero balance is refused rather than divided by",
              !XSparkTrendScalpMinimumLotRisk(0.01, 1.50, 0.01, 1.0, 0.0, risk_cash, risk_pct, reason) && risk_pct == 0.0);
   ScalpCheck("an unusable minimum volume is refused",
              !XSparkTrendScalpMinimumLotRisk(0.0, 1.50, 0.01, 1.0, 100.0, risk_cash, risk_pct, reason));
   ScalpCheck("an unusable stop is refused",
              !XSparkTrendScalpMinimumLotRisk(0.01, 0.0, 0.01, 1.0, 100.0, risk_cash, risk_pct, reason));
}

void RunTrendScalpConfigTests()
{
   XSparkTrendScalpConfig config;
   string reason = "";

   XSparkDefaultTrendScalpConfig(config);
   ScalpCheck("the shipped configuration is valid", XSparkValidateTrendScalpConfig(config, reason));
   ScalpCheck("the shipped configuration gates on volatility and targets one stop",
              config.use_volatility_gate && config.target_r == XSPARK_TRENDSCALP_TARGET_R_EVEN);

   config.buffer_atr_mult = 0.0;
   ScalpCheck("a configuration with no buffer is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.min_stop_atr_mult = 0.0;
   ScalpCheck("a configuration with no stop floor is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.max_stop_atr_mult = config.min_stop_atr_mult;
   ScalpCheck("a ceiling at or below the floor is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.max_cost_share_pct = 0.0;
   ScalpCheck("a cost share of zero is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.max_cost_share_pct = 100.0;
   ScalpCheck("a cost share of 100 is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.target_r = 0.0;
   ScalpCheck("a scalp without a target is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.min_close_position = 0.0;
   ScalpCheck("a close position of zero is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.min_close_position = 1.01;
   ScalpCheck("a close position above the whole range is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.min_close_position = 1.0;
   ScalpCheck("a close position at the whole range is permitted", XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.min_ema_gap_atr = -0.1;
   ScalpCheck("a negative trend gap is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.touch_atr = -0.1;
   ScalpCheck("a negative touch distance is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.max_extension_atr = -0.1;
   ScalpCheck("a negative extension limit is refused", !XSparkValidateTrendScalpConfig(config, reason));

   XSparkDefaultTrendScalpConfig(config); config.atr_min_points = -1.0;
   ScalpCheck("a negative volatility band is refused", !XSparkValidateTrendScalpConfig(config, reason));

   ScalpCheck("every configuration refusal says why", StringLen(reason) > 0);

   CXSparkTrendScalp strategy;
   ScalpCheck("the strategy refuses to initialize without a symbol", !strategy.Initialize(""));
   ScalpCheck("the strategy initializes on the shipped configuration", strategy.Initialize("TEST"));
   ScalpCheck("the target the signal will carry is the configured one", ScalpNear(strategy.TargetRewardRatio(), 1.0));
   ScalpCheck("an inverted volatility band is refused", !strategy.SetVolatilityBand(10.0, 5.0));
   ScalpCheck("a usable volatility band is accepted", strategy.SetVolatilityBand(5.0, 10.0));
   XSparkTrendScalpConfig broken;
   XSparkDefaultTrendScalpConfig(broken);
   broken.target_r = 0.0;
   strategy.Configure(broken);
   ScalpCheck("a broken configuration is refused at initialization", !strategy.Initialize("TEST") &&
              StringLen(strategy.LastReason()) > 0);
}

#ifdef XSPARK_PORTABLE_TEST
// The whole Evaluate path, through the portable cache double, which reports a
// fast average of 100, a slow one of 99, a higher slow one of 99 and a
// typical candle of 1.0. Natively the cache reads the terminal and cannot be
// fed a bar from a script, so this block exists only in the portable build.
void RunTrendScalpEvaluateTests()
{
   CXSparkIndicatorCache cache;
   cache.base.resize(1);
   ScalpBar(cache.base[0], 99.8, 100.6, 99.9, 100.5);

   CXSparkTrendScalp strategy;
   XSparkTrendScalpConfig config;
   XSparkDefaultTrendScalpConfig(config);
   config.score_point_size = 0.01;
   strategy.Configure(config);

   XSparkSignal signal;
   XSparkScoreBotReport report;

   ScalpCheck("an uninitialized strategy never signals",
              !strategy.Evaluate(cache, signal, report) && report.status == "SCANNING" && report.joint_verdict == "BLOCKED");

   strategy.Initialize("TEST");
   ScalpCheck("before the calibration the gate blocks as ATR BLOCKED",
              !strategy.Evaluate(cache, signal, report) && report.status == "ATR BLOCKED" &&
              report.htf_verdict == "UPTREND" && report.pullback_verdict == "TOUCH+RECLAIM" && report.joint_verdict == "BLOCKED");

   strategy.SetVolatilityBand(200.0, 600.0);
   ScalpCheck("a typical candle outside the band blocks as ATR BLOCKED",
              !strategy.Evaluate(cache, signal, report) && report.status == "ATR BLOCKED");

   strategy.SetVolatilityBand(60.0, 600.0);
   ScalpCheck("a pullback long fills the signal and the report",
              strategy.Evaluate(cache, signal, report) &&
              signal.direction == XSPARK_SIGNAL_BUY && report.status == "SIGNAL" && report.joint_verdict == "PASS" &&
              report.htf_verdict == "UPTREND" && report.pullback_verdict == "TOUCH+RECLAIM" && report.rsi_verdict == "OFF");
   ScalpCheck("the signal carries the pullback-long pattern, the anchor, the target and the fixed score",
              report.pattern_id == XSPARK_PATTERN_SCALP_PULLBACK_LONG && signal.pattern_id == 17 &&
              report.pattern_name == "Pullback Long" && ScalpNear(report.detected_level, 99.75) &&
              ScalpNear(signal.desired_stop, 99.75) && signal.desired_target == 0.0 &&
              ScalpNear(signal.dynamic_rr, 1.0) && ScalpNear(report.dynamic_rr, 1.0) &&
              signal.score == XSPARK_TRENDSCALP_SIGNAL_SCORE && report.components.session_weight == 1.0 &&
              signal.session_weight == 1.0 && signal.symbol == "TEST");
   ScalpCheck("the panel texts are TrendScalp's own",
              report.pattern_mode == "TREND PULLBACK" && report.entry_location == "EMA PULLBACK" &&
              report.ema21_base == 100.0 && report.ema50_base == 99.0 && report.ema50_higher == 99.0);

   ScalpBar(cache.base[0], 100.3, 100.9, 100.2, 100.8);
   ScalpCheck("a candle that never touched the average reports the verdict and no signal",
              !strategy.Evaluate(cache, signal, report) && signal.direction == XSPARK_SIGNAL_NONE &&
              report.status == "SCANNING" && report.htf_verdict == "UPTREND" && report.pullback_verdict == "NO TOUCH" &&
              report.joint_verdict == "BLOCKED");

   cache.valid = false;
   ScalpCheck("an invalid cache never signals",
              !strategy.Evaluate(cache, signal, report) && report.status == "SCANNING");
}
#endif

void RunTrendScalpTests()
{
   RunTrendScalpTimeframeTests();
   RunTrendScalpConstantTests();
   RunTrendScalpRuleTests();
   RunTrendScalpAnchorTests();
   RunTrendScalpCostTests();
   RunTrendScalpStopTests();
   RunTrendScalpExitStyleTests();
   RunTrendScalpSessionTests();
   RunTrendScalpDailyCapTests();
   RunTrendScalpWeekendTests();
   RunTrendScalpResolverTests();
   RunTrendScalpStatisticsTests();
   RunTrendScalpConfigTests();
#ifdef XSPARK_PORTABLE_TEST
   RunTrendScalpEvaluateTests();
#endif

   Print("TRENDSCALP RESULT passed=", g_scalp_passed, " failed=", g_scalp_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunTrendScalpTests(); }
#endif
