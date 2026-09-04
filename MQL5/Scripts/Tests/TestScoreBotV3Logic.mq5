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

   Check("canonical points price conversion", NearlyEqual(XSparkCanonicalPointsToPrice(80.0), 0.80));
   Check("2-digit broker point conversion", NearlyEqual(XSparkCanonicalPointsToBrokerPointsForPointSize(80.0, 0.01), 80.0));
   Check("3-digit broker point conversion", NearlyEqual(XSparkCanonicalPointsToBrokerPointsForPointSize(80.0, 0.001), 800.0));
   Check("slippage canonical conversion", NearlyEqual(XSparkCanonicalPointsToPrice(30.0), 0.30));
}

void OnStart()
{
   Print("Starting ScoreBot_v3 deterministic logic tests");
   TestPatterns();
   TestPureCalculations();
   PrintFormat("ScoreBot_v3 logic tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
