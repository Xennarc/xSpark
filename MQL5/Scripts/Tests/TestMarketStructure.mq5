#property script_show_inputs
#include <XSpark/Strategy/EntryGates.mqh>

int g_passed = 0, g_failed = 0;
void Check(const string name, const bool ok)
{
   if(ok) { g_passed++; Print("PASS: ", name); }
   else { g_failed++; Print("FAIL: ", name); }
}
void Bar(XSparkCandle &b, const int index, const double mid)
{
   b.time = (datetime)(100000 - index * 60);
   b.open = mid; b.close = mid; b.high = mid + 0.2; b.low = mid - 0.2; b.tick_volume = 100;
}
void Flat(XSparkCandle &bars[], const int count)
{
   ArrayResize(bars, count);
   for(int i = 0; i < count; i++) Bar(bars[i], i, 100.0);
}
void Staircase(XSparkCandle &bars[], const bool down)
{
   ArrayResize(bars, 40);
   // Oldest-to-newest turning points: rising highs AND rising lows.
   double values[8] = {101, 105, 102, 107, 104, 109, 106, 108};
   for(int old = 0; old < 40; old++)
   {
      const int segment = old / 5;
      const int next = (int)MathMin(7, segment + 1);
      double price = values[segment] + (values[next] - values[segment]) * (old % 5) / 5.0;
      if(down) price = 220 - price;
      Bar(bars[39 - old], 39 - old, price);
   }
}
void TestStructure()
{
   XSparkCandle bars[];
   XSparkStructure s;
   Staircase(bars, false);
   Check("HH/HL builds", XSparkBuildStructure(bars, ArraySize(bars), 0.1, s));
   Check("HH/HL is UP", s.valid && s.state == XSPARK_STRUCT_UP);
   Check("five legs", s.legs_in_state == 5);
   Check("buy leg exists", XSparkLocateLeg(bars, ArraySize(bars), XSPARK_SIGNAL_BUY, s));
   Check("newest first confirmed shifts", s.pivot_count >= 4 && s.pivots[0].shift >= 3 && s.pivots[0].time > s.pivots[1].time);
   XSparkInvalidateStructure(s.last_low - 0.01, s);
   Check("base close invalidates immediately", s.state == XSPARK_STRUCT_RANGE);
   Staircase(bars, true);
   XSparkBuildStructure(bars, ArraySize(bars), 0.1, s);
   Check("LH/LL is DOWN", s.state == XSPARK_STRUCT_DOWN);
   XSparkInvalidateStructure(s.last_high + 0.01, s);
   Check("sell structure invalidates", s.state == XSPARK_STRUCT_RANGE);

   Flat(bars, 20); bars[5].high = 105; bars[6].high = 105;
   XSparkBuildStructure(bars, 20, 0.1, s);
   Check("plateau newest only", s.pivot_count == 1 && s.pivots[0].shift == 6);
   Check("insufficient pivots UNKNOWN", s.valid && s.state == XSPARK_STRUCT_UNKNOWN && s.reason != "");
   Flat(bars, 20); bars[5].high = 105; bars[5].low = 95;
   XSparkBuildStructure(bars, 20, 0.1, s);
   Check("outside bar excluded", s.pivot_count == 0);
   Staircase(bars, false);
   XSparkBuildStructure(bars, ArraySize(bars), 100, s);
   Check("tiny swings absorbed", s.pivot_count <= 1);
   // Explicit classification fixture: equal newest highs, rising lows.
   Flat(bars, 30);
   bars[22].high = 105; bars[16].low = 95;
   bars[10].high = 105; bars[4].low = 97;
   XSparkBuildStructure(bars, 30, 0.1, s);
   Check("equal highs with rising lows is RANGE", s.state == XSPARK_STRUCT_RANGE);
   Flat(bars, 20); bars[3].time = bars[2].time;
   Check("unordered data fails closed", !XSparkBuildStructure(bars, 20, 0.5, s) && !s.valid);
   Flat(bars, 20); bars[0].low = bars[0].high + 1;
   Check("invalid geometry fails closed", !XSparkBuildStructure(bars, 20, 0.5, s));

   Flat(bars, 400);
   for(int i = 0; i < 400; i++)
   {
      const int phase = i % 6;
      Bar(bars[i], i, phase <= 3 ? 100 + phase : 106 - phase);
   }
   Check("overflow refuses", !XSparkBuildStructure(bars, 400, 0.1, s) && !s.valid && s.reason == "pivot overflow");
}
void TestGates()
{
   XSparkGateConfig c; XSparkDefaultGateConfig(c);
   string reason;
   Check("default config", XSparkValidateGateConfig(c, reason));
   c.use_htf = true;
   Check("HTF alone refused", !XSparkValidateGateConfig(c, reason));
   c.use_pullback = true; c.use_continuation = true;
   Check("coupled gates accepted", XSparkValidateGateConfig(c, reason));
   c.pullback_max = 1.0;
   Check("broken-leg window refused", !XSparkValidateGateConfig(c, reason));
   c.pullback_max = 0.8;
   Check("buy upper exhaustion", XSparkRSIVerdict(XSPARK_SIGNAL_BUY, 65, 62, 30, 60, 40, 70, false) == "RSI INNER HIGH");
   Check("sell lower exhaustion", XSparkRSIVerdict(XSPARK_SIGNAL_SELL, 35, 38, 30, 60, 40, 70, false) == "RSI INNER LOW");
   Check("outer separated", XSparkRSIVerdict(XSPARK_SIGNAL_BUY, 25, 24, 30, 60, 40, 70, false) == "RSI OUTER LOW");
   Check("RSI turn required", XSparkRSIVerdict(XSPARK_SIGNAL_BUY, 45, 46, 30, 60, 40, 70, true) == "RSI NOT TURNING");
   Check("RSI turn valid", XSparkRSIVerdict(XSPARK_SIGNAL_BUY, 45, 44, 30, 60, 40, 70, true) == "PASS");
   Check("RSI missing history", XSparkRSIVerdict(XSPARK_SIGNAL_BUY, 45, EMPTY_VALUE, 30, 60, 40, 70, true) == "RSI HISTORY UNAVAILABLE");
   XSparkStructure s; XSparkResetStructure(s);
   s.valid = true; s.leg_origin_shift = 10; s.leg_extreme_shift = 5;
   s.leg_range = 4; s.retracement = 0.5;
   Check("mid pullback passes", XSparkPullbackVerdict(s, 1, c) == "PASS");
   s.retracement = 0.1;
   Check("chase refused", XSparkPullbackVerdict(s, 1, c) == "NOT IN PULLBACK ZONE");
   s.retracement = 1.1;
   Check("broken leg refused", XSparkPullbackVerdict(s, 1, c) == "LEG BROKEN");
   s.retracement = 0.5;
   XSparkCandle bars[]; Flat(bars, 20);
   bars[2].low = 98; bars[0].close = 101; bars[0].high = 101.2;
   XSparkPatternResult aligned, out; XSparkResetPatternResult(aligned);
   Check("pullback break fires", XSparkDetectContinuation(bars, 20, s, XSPARK_SIGNAL_BUY, 45, 44, c, aligned, out) && out.pattern_id == XSPARK_PATTERN_PULLBACK_BREAK);
   c.use_t1 = false;
   Check("momentum turn fires", XSparkDetectContinuation(bars, 20, s, XSPARK_SIGNAL_BUY, 45, 44, c, aligned, out) && out.score == 1.0);
   Check("wrong RSI turn waits", !XSparkDetectContinuation(bars, 20, s, XSPARK_SIGNAL_BUY, 43, 44, c, aligned, out));
   c.use_t3 = false;
   Check("disabled triggers wait", !XSparkDetectContinuation(bars, 20, s, XSPARK_SIGNAL_BUY, 45, 44, c, aligned, out));
   s.leg_extreme_shift = 1;
   Check("impulse bar not pullback", !XSparkDetectContinuation(bars, 20, s, XSPARK_SIGNAL_BUY, 45, 44, c, aligned, out));
}
void OnStart()
{
   TestStructure(); TestGates();
   Print("RESULT passed=", g_passed, " failed=", g_failed);
}
