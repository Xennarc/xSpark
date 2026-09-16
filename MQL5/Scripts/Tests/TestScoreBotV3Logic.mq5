#property script_show_inputs

#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Risk/RiskManager.mqh>
#include <XSpark/Strategy/PatternDetector.mqh>
#include <XSpark/Strategy/ScoringEngine.mqh>

int g_passed = 0;
int g_failed = 0;

void MakeCandle(XSparkCandle &bar,
                const double open,
                const double high,
                const double low,
                const double close,
                const long tick_volume = 100)
{
   bar.time = 0;
   bar.open = open;
   bar.high = high;
   bar.low = low;
   bar.close = close;
   bar.tick_volume = tick_volume;
}

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

void TestPatterns()
{
   XSparkCandle bar1;
   XSparkCandle bar2;
   XSparkCandle bar3;
   XSparkPatternResult result;

   MakeCandle(bar1, 100.00, 101.00, 98.70, 100.20);
   Check("bullish pin detected", XSparkDetectPinBar(bar1, result));
   Check("bullish pin direction", result.direction == XSPARK_SIGNAL_BUY);
   Check("bullish pin score", NearlyEqual(result.score, MathMin(2.0, 1.0 + 1.30 / 2.30)));

   MakeCandle(bar1, 100.00, 101.30, 99.00, 99.80);
   Check("bearish pin detected", XSparkDetectPinBar(bar1, result));
   Check("bearish pin direction", result.direction == XSPARK_SIGNAL_SELL);

   MakeCandle(bar2, 100.00, 100.20, 98.80, 99.00);
   MakeCandle(bar1, 98.80, 100.40, 98.60, 100.20);
   Check("bullish engulfing detected", XSparkDetectEngulfing(bar1, bar2, result));
   Check("bullish engulfing direction", result.direction == XSPARK_SIGNAL_BUY);

   MakeCandle(bar2, 100.00, 101.20, 99.80, 101.00);
   MakeCandle(bar1, 101.20, 101.40, 99.60, 99.80);
   Check("bearish engulfing detected", XSparkDetectEngulfing(bar1, bar2, result));
   Check("bearish engulfing direction", result.direction == XSPARK_SIGNAL_SELL);

   MakeCandle(bar3, 100.00, 101.00, 99.00, 100.20);
   MakeCandle(bar2, 100.10, 100.50, 99.50, 100.00);
   MakeCandle(bar1, 100.00, 100.80, 99.80, 100.60);
   Check("bullish inside-bar breakout detected", XSparkDetectInsideBarBreakout(bar1, bar2, bar3, result));
   Check("bullish inside-bar breakout direction", result.direction == XSPARK_SIGNAL_BUY);

   MakeCandle(bar1, 100.00, 100.20, 99.20, 99.40);
   Check("bearish inside-bar breakout detected", XSparkDetectInsideBarBreakout(bar1, bar2, bar3, result));
   Check("bearish inside-bar breakout direction", result.direction == XSPARK_SIGNAL_SELL);

   MakeCandle(bar1, 100.00, 101.00, 98.70, 100.20);
   MakeCandle(bar2, 100.40, 100.60, 99.00, 99.20);
   MakeCandle(bar3, 100.00, 101.20, 98.80, 100.50);
   Check("pattern priority chooses pin first", XSparkDetectScoreBotPattern(bar1, bar2, bar3, false, result));
   Check("pattern priority result is bullish pin", result.pattern_id == XSPARK_PATTERN_BULLISH_PIN);

   MakeCandle(bar1, 100.00, 100.40, 99.80, 100.10);
   MakeCandle(bar2, 100.10, 100.50, 99.90, 100.20);
   MakeCandle(bar3, 100.20, 100.60, 99.80, 100.30);
   Check("no pattern", !XSparkDetectScoreBotPattern(bar1, bar2, bar3, false, result));

   MakeCandle(bar1, 100.00, 100.00, 100.00, 100.00);
   Check("zero-range pin safety", !XSparkDetectPinBar(bar1, result));

   MakeCandle(bar2, 100.00, 100.50, 99.50, 100.00);
   MakeCandle(bar1, 99.80, 100.60, 99.70, 100.30);
   Check("zero-body engulfing denominator safety", !XSparkDetectEngulfing(bar1, bar2, result));
}

void TestPureCalculations()
{
   Check("session both London and New York", NearlyEqual(XSparkScoreBotSessionWeight(StringToTime("2026.09.03 13:00"), true), 1.2));
   Check("session London only", NearlyEqual(XSparkScoreBotSessionWeight(StringToTime("2026.09.03 08:00"), true), 1.0));
   Check("session New York only", NearlyEqual(XSparkScoreBotSessionWeight(StringToTime("2026.09.03 18:00"), true), 1.0));
   Check("session Asian reduced", NearlyEqual(XSparkScoreBotSessionWeight(StringToTime("2026.09.03 23:00"), true), 0.6));
   Check("session blocked when Asian reduced disabled", NearlyEqual(XSparkScoreBotSessionWeight(StringToTime("2026.09.03 23:00"), false), 0.0));

   Check("dynamic RR floor", NearlyEqual(XSparkScoreBotDynamicRR(0.70, 1.00, 1.5, 3.0, 1.3), 1.5));
   Check("dynamic RR ceiling", NearlyEqual(XSparkScoreBotDynamicRR(1.30, 1.00, 1.5, 3.0, 1.3), 3.0));
   Check("dynamic RR mid-range", NearlyEqual(XSparkScoreBotDynamicRR(1.00, 1.00, 1.5, 3.0, 1.3), 2.25));

   Check("risk tier 4.499 is tier 1", NearlyEqual(XSparkRiskPercentForScore(4.499, 1.0, 1.5, 2.0, 2.0), 1.0));
   Check("risk tier 4.5 is tier 2", NearlyEqual(XSparkRiskPercentForScore(4.5, 1.0, 1.5, 2.0, 2.0), 1.5));
   Check("risk tier 5.499 is tier 2", NearlyEqual(XSparkRiskPercentForScore(5.499, 1.0, 1.5, 2.0, 2.0), 1.5));
   Check("risk tier 5.5 is tier 3", NearlyEqual(XSparkRiskPercentForScore(5.5, 1.0, 1.5, 2.0, 2.0), 2.0));
   Check("risk cap prevents values above max", NearlyEqual(XSparkRiskPercentForScore(9.0, 1.0, 1.5, 3.0, 2.0), 2.0));

   const double max_raw = 7.5;
   const double max_final = max_raw * 1.2;
   Check("final score maximum <= 9.0", XSparkScoreBotScoreIsValid(max_final) && NearlyEqual(max_final, 9.0));

   Check("ScoreBot points price conversion",
         NearlyEqual(XSparkScorePointsToPrice(80.0, XSPARK_XAUUSD_SCORE_POINT_SIZE), 0.80));
   Check("2-digit broker point conversion",
         NearlyEqual(XSparkScorePointsToBrokerPoints(80.0, XSPARK_XAUUSD_SCORE_POINT_SIZE, 0.01), 80.0));
   Check("3-digit broker point conversion",
         NearlyEqual(XSparkScorePointsToBrokerPoints(80.0, XSPARK_XAUUSD_SCORE_POINT_SIZE, 0.001), 800.0));
   Check("slippage ScoreBot point conversion",
         NearlyEqual(XSparkScorePointsToPrice(30.0, XSPARK_XAUUSD_SCORE_POINT_SIZE), 0.30));
}

// The Phase 0 behaviour-neutrality proof. These assertions use exact equality
// rather than a tolerance on purpose: the claim is that the resolved size is the
// SAME double as the constant it replaced, not merely close to it. A tolerance
// would pass for a size that silently rescales every ScoreBot threshold.
void TestScorePointSizeDerivation()
{
   double pip = 0.0;
   string reason = "";

   Check("XAUUSD 2-digit spec resolves", XSparkPipSizeForSpec(2, 0.01, pip, reason));
   Check("XAUUSD 2-digit size equals the declared baseline exactly",
         pip == XSPARK_XAUUSD_SCORE_POINT_SIZE);

   Check("XAUUSD 3-digit spec resolves", XSparkPipSizeForSpec(3, 0.001, pip, reason));
   Check("XAUUSD 3-digit size equals the declared baseline exactly",
         pip == XSPARK_XAUUSD_SCORE_POINT_SIZE);

   // Both return values are asserted before the sizes are compared. Comparing
   // them alone would pass vacuously if BOTH calls failed, because a rejected
   // spec leaves the out-parameter at 0.0 and 0.0 == 0.0. Equality against the
   // declared baseline is the claim; equality with each other is not enough.
   double pip_2_digit = 0.0;
   double pip_3_digit = 0.0;
   const bool resolved_2_digit = XSparkPipSizeForSpec(2, 0.01, pip_2_digit, reason);
   const bool resolved_3_digit = XSparkPipSizeForSpec(3, 0.001, pip_3_digit, reason);
   Check("both XAUUSD quote conventions resolve", resolved_2_digit && resolved_3_digit);
   Check("both XAUUSD quote conventions resolve to the same double",
         resolved_2_digit && resolved_3_digit && pip_2_digit == pip_3_digit);
   Check("the shared XAUUSD size is the declared baseline",
         resolved_2_digit && pip_2_digit == XSPARK_XAUUSD_SCORE_POINT_SIZE);

   Check("EURUSD 5-digit spec resolves", XSparkPipSizeForSpec(5, 0.00001, pip, reason));
   Check("EURUSD 5-digit size is a pip", NearlyEqual(pip, 0.0001));
   Check("EURUSD 4-digit spec resolves", XSparkPipSizeForSpec(4, 0.0001, pip, reason));
   Check("EURUSD 4-digit size is a pip", NearlyEqual(pip, 0.0001));

   Check("USDJPY 3-digit spec resolves", XSparkPipSizeForSpec(3, 0.001, pip, reason));
   Check("USDJPY 3-digit size is a pip", NearlyEqual(pip, 0.01));

   Check("1-digit spec resolves", XSparkPipSizeForSpec(1, 0.1, pip, reason));
   Check("1-digit size is the point", NearlyEqual(pip, 0.1));
   Check("0-digit spec resolves", XSparkPipSizeForSpec(0, 1.0, pip, reason));
   Check("0-digit size is the point", NearlyEqual(pip, 1.0));

   // Fail closed. Every rejection must also leave the out-parameter unusable so a
   // caller that ignores the bool cannot proceed on a plausible-looking size.
   Check("zero point is rejected", !XSparkPipSizeForSpec(2, 0.0, pip, reason));
   Check("zero point yields no size", NearlyEqual(pip, 0.0));
   Check("negative point is rejected", !XSparkPipSizeForSpec(2, -0.01, pip, reason));
   // The reason is asserted as well as the rejection. The digits-range guard runs
   // before the point/digits agreement guard, so a rejection alone would not say
   // which branch fired, and these would still pass if the order ever changed.
   Check("negative digits are rejected", !XSparkPipSizeForSpec(-1, 10.0, pip, reason));
   Check("negative digits are rejected for being out of range",
         StringFind(reason, "outside the supported range") >= 0);
   Check("digits above the supported range are rejected",
         !XSparkPipSizeForSpec(XSPARK_SPEC_MAX_DIGITS + 1, 0.000000001, pip, reason));
   Check("high digits are rejected for being out of range",
         StringFind(reason, "outside the supported range") >= 0);
   Check("point disagreeing with digits is rejected", !XSparkPipSizeForSpec(2, 0.001, pip, reason));
   Check("rejection states a reason", reason != "");

   // Non-finite guards. Built through MathPow overflow rather than a literal
   // expression or a division by zero, so the compiler cannot fold it and the
   // test does not depend on divide-by-zero semantics. Nothing downstream may
   // turn these into a usable distance: the consumer of the broker-point
   // conversion is the slippage tolerance an order is sent with, and MQL5
   // leaves a non-finite-to-ulong cast undefined.
   const double infinity = MathPow(10.0, 400.0);
   const double not_a_number = infinity - infinity;

   Check("infinity is not a valid number", !MathIsValidNumber(infinity));
   Check("nan is not a valid number", !MathIsValidNumber(not_a_number));

   Check("non-finite point is rejected", !XSparkPipSizeForSpec(2, infinity, pip, reason));
   Check("nan point is rejected", !XSparkPipSizeForSpec(2, not_a_number, pip, reason));
   Check("non-finite size yields no price distance",
         NearlyEqual(XSparkScorePointsToPrice(80.0, infinity), 0.0));
   Check("non-finite points yield no price distance",
         NearlyEqual(XSparkScorePointsToPrice(infinity, XSPARK_XAUUSD_SCORE_POINT_SIZE), 0.0));
   Check("non-finite size yields no ScoreBot points",
         NearlyEqual(XSparkPriceToScorePoints(0.80, infinity), 0.0));
   Check("non-finite distance yields no broker points",
         NearlyEqual(XSparkPriceDistanceToBrokerPoints(infinity, 0.01), 0.0));
   Check("non-finite broker point yields no broker points",
         NearlyEqual(XSparkPriceDistanceToBrokerPoints(0.30, infinity), 0.0));
   Check("a non-finite chain yields no broker points",
         NearlyEqual(XSparkScorePointsToBrokerPoints(100.0, infinity, 0.01), 0.0));

   // Conversion guards: an unresolved size must never produce a usable distance.
   Check("zero size yields no price distance", NearlyEqual(XSparkScorePointsToPrice(80.0, 0.0), 0.0));
   Check("negative size yields no price distance", NearlyEqual(XSparkScorePointsToPrice(80.0, -0.01), 0.0));
   Check("zero size yields no ScoreBot points", NearlyEqual(XSparkPriceToScorePoints(0.80, 0.0), 0.0));
   Check("zero broker point yields no broker points",
         NearlyEqual(XSparkPriceDistanceToBrokerPoints(0.30, 0.0), 0.0));

   // Exit deviation, the conversion ADR-014 depends on, at both gold conventions.
   Check("exit deviation on a 2-digit gold feed",
         NearlyEqual(XSparkScorePointsToBrokerPoints(100.0, XSPARK_XAUUSD_SCORE_POINT_SIZE, 0.01), 100.0));
   Check("exit deviation on a 3-digit gold feed",
         NearlyEqual(XSparkScorePointsToBrokerPoints(100.0, XSPARK_XAUUSD_SCORE_POINT_SIZE, 0.001), 1000.0));

   // Round trip: points -> price -> points must not drift at the ATR gate bounds.
   Check("ATR gate lower bound round-trips",
         NearlyEqual(XSparkPriceToScorePoints(
                        XSparkScorePointsToPrice(80.0, XSPARK_XAUUSD_SCORE_POINT_SIZE),
                        XSPARK_XAUUSD_SCORE_POINT_SIZE), 80.0));
   Check("ATR gate upper bound round-trips",
         NearlyEqual(XSparkPriceToScorePoints(
                        XSparkScorePointsToPrice(800.0, XSPARK_XAUUSD_SCORE_POINT_SIZE),
                        XSPARK_XAUUSD_SCORE_POINT_SIZE), 800.0));
}

void OnStart()
{
   Print("Starting ScoreBot_v3 deterministic logic tests");
   TestPatterns();
   TestPureCalculations();
   TestScorePointSizeDerivation();
   PrintFormat("ScoreBot_v3 logic tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
