#property script_show_inputs
#include <XSpark/Strategy/SmartMoney.mqh>

// Deterministic checks for the mechanized Smart Money Concepts model.
//
// These cover pure shape detection only: the leg detector, the volatility
// parse, the order block search, mitigation, fair value gaps, equal highs and
// lows, the replay that rebuilds all of it, and the rule assembled on top of
// it. Every fixture is a hand-built bar array whose answer is known by
// construction.
//
// Broker behaviour, sizing, execution and spread are not exercised here and
// must be validated in the Strategy Tester and on a demo account.
//
// NOTHING HERE MEASURES AN EDGE. A rule that fires exactly where it was
// designed to fire is a correct rule, not a profitable one. These tests say the
// indicator is faithfully transcribed and the trade built on it behaves as
// described; only out-of-sample testing can say whether it is worth trading.

int g_smc_passed = 0, g_smc_failed = 0;

void SmcCheck(const string name, const bool ok)
{
   if(ok) { g_smc_passed++; Print("PASS: ",name); }
   else { g_smc_failed++; Print("FAIL: ",name); }
}

bool SmcNear(const double a, const double b, const double tolerance = 0.0000001)
{
   return MathAbs(a - b) < tolerance;
}

// The configuration the fixtures run on: the same model with a shorter swing,
// so a readable number of bars can still produce one. The published lengths are
// exercised by XSparkSmcDefaultConfig in the configuration tests below.
void SmcTestConfig(XSparkSmcConfig &config)
{
   XSparkSmcDefaultConfig(config);
   config.swing_length = 10;
   config.internal_length = 3;
   config.equal_length = 2;
   config.max_block_age_bars = 20;
   config.min_block_price = 0.0;
}

// ---------------------------------------------------------------------------
// The leg detector.
// ---------------------------------------------------------------------------

void RunSmcLegTests()
{
   // Series order: index 0 is newest. The peak sits at index 3, and the three
   // bars NEWER than it are all lower - which is what the detector asks.
   double highs[];
   ArrayResize(highs, 8);
   highs[0] = 11.0; highs[1] = 12.0; highs[2] = 13.0; highs[3] = 15.0;
   highs[4] = 14.0; highs[5] = 13.5; highs[6] = 13.0; highs[7] = 12.0;

   double lows[];
   ArrayResize(lows, 8);
   lows[0] = 9.0; lows[1] = 8.0; lows[2] = 7.0; lows[3] = 4.0;
   lows[4] = 5.0; lows[5] = 6.0; lows[6] = 7.0; lows[7] = 8.0;

   SmcCheck("a bar higher than the three after it starts a new leg high",
            XSparkSmcNewLegHigh(highs, 0, 3));
   SmcCheck("a bar lower than the three after it starts a new leg low",
            XSparkSmcNewLegLow(lows, 0, 3));

   // The detector is ONE-SIDED. Nothing to the left of the pivot is consulted,
   // which is the source's behaviour and not an oversight in this transcription.
   SmcCheck("nothing older than the pivot is consulted",
            XSparkSmcNewLegHigh(highs, 1, 2));

   // A tie on the newer side is not a break: the comparison is strict.
   double flat[];
   ArrayResize(flat, 5);
   flat[0] = 10.0; flat[1] = 10.0; flat[2] = 10.0; flat[3] = 10.0; flat[4] = 10.0;
   SmcCheck("a flat run starts no leg at all",
            !XSparkSmcNewLegHigh(flat, 0, 3) && !XSparkSmcNewLegLow(flat, 0, 3));

   SmcCheck("a window that runs past the array is refused",
            !XSparkSmcNewLegHigh(highs, 6, 3) && !XSparkSmcNewLegLow(lows, 6, 3));
   SmcCheck("a zero-length leg is refused",
            !XSparkSmcNewLegHigh(highs, 0, 0) && !XSparkSmcNewLegLow(lows, 0, 0));
}

// ---------------------------------------------------------------------------
// The volatility measure and the body scale.
// ---------------------------------------------------------------------------

void RunSmcMeasureTests()
{
   double highs[]; ArrayResize(highs, 3);
   double lows[];  ArrayResize(lows, 3);
   double closes[];ArrayResize(closes, 3);
   double opens[]; ArrayResize(opens, 3);

   // Two comparable bars, each with a one-point range and no gap between them.
   highs[0] = 11.0; lows[0] = 10.0; closes[0] = 10.5; opens[0] = 10.0;
   highs[1] = 11.0; lows[1] = 10.0; closes[1] = 10.5; opens[1] = 10.0;
   highs[2] = 11.0; lows[2] = 10.0; closes[2] = 10.5; opens[2] = 10.0;

   SmcCheck("the mean range of equal one-point bars is one point",
            SmcNear(XSparkSmcMeanRange(highs, lows, closes, 3), 1.0));
   SmcCheck("a single bar has no measurable range",
            SmcNear(XSparkSmcMeanRange(highs, lows, closes, 1), 0.0));

   // The body scale is the source's own expression, a hundredth of the
   // fractional body. Half a point on a ten-point open is 0.0005.
   SmcCheck("the body scale is the source's hundredth-of-a-fraction",
            SmcNear(XSparkSmcMeanBodyDelta(opens, closes, 3), 0.0005, 0.0000001));
}

// ---------------------------------------------------------------------------
// The rings.
// ---------------------------------------------------------------------------

void SmcMakeBlock(XSparkSmcBlock &block, const double low, const double high, const int bias, const int index)
{
   XSparkSmcResetBlock(block);
   block.low = low;
   block.high = high;
   block.bias = bias;
   block.index = index;
   block.break_index = index - 1;
   block.pivot_index = index + 5;
   block.internal = true;
}

void RunSmcRingTests()
{
   XSparkSmcBlockRing ring;
   XSparkSmcResetBlockRing(ring);

   for(int i = 0; i < XSPARK_SMC_MAX_BLOCKS + 3; i++)
   {
      XSparkSmcBlock block;
      SmcMakeBlock(block, 100.0 + i, 101.0 + i, XSPARK_SIGNAL_BUY, i + 2);
      XSparkSmcPushBlock(ring, block);
   }

   SmcCheck("the block ring never grows past its capacity",
            ring.count == XSPARK_SMC_MAX_BLOCKS);
   SmcCheck("the newest block is at the front and the oldest was evicted",
            SmcNear(ring.items[0].low, 100.0 + XSPARK_SMC_MAX_BLOCKS + 2) &&
            SmcNear(ring.items[XSPARK_SMC_MAX_BLOCKS - 1].low, 100.0 + 3));

   // Mitigation, on the high/low source: a bullish block dies when price trades
   // below its low and a bearish one when price trades above its high.
   XSparkSmcResetBlockRing(ring);
   XSparkSmcBlock bullish, bearish, survivor;
   SmcMakeBlock(bullish, 100.0, 101.0, XSPARK_SIGNAL_BUY, 5);
   SmcMakeBlock(bearish, 120.0, 121.0, XSPARK_SIGNAL_SELL, 6);
   SmcMakeBlock(survivor, 90.0, 91.0, XSPARK_SIGNAL_BUY, 7);
   XSparkSmcPushBlock(ring, survivor);
   XSparkSmcPushBlock(ring, bearish);
   XSparkSmcPushBlock(ring, bullish);

   XSparkSmcMitigateBlocks(ring, 125.0, 99.0);
   SmcCheck("one bar mitigating two blocks removes both of them",
            ring.count == 1 && SmcNear(ring.items[0].low, 90.0));

   // Gaps: a bullish gap survives until price trades below its bottom.
   XSparkSmcGapRing gaps;
   XSparkSmcResetGapRing(gaps);
   XSparkSmcGap gap;
   XSparkSmcResetGap(gap);
   gap.bias = XSPARK_SIGNAL_BUY; gap.bottom = 100.0; gap.top = 102.0; gap.index = 4;
   XSparkSmcPushGap(gaps, gap);
   XSparkSmcMitigateGaps(gaps, 103.0, 100.5);
   SmcCheck("a bullish gap survives price inside it",
            gaps.count == 1);
   XSparkSmcMitigateGaps(gaps, 103.0, 99.5);
   SmcCheck("a bullish gap dies when price trades through its bottom",
            gaps.count == 0);

   // And the bearish side is read the SAME way, which the source does not do.
   XSparkSmcResetGapRing(gaps);
   XSparkSmcResetGap(gap);
   gap.bias = XSPARK_SIGNAL_SELL; gap.bottom = 100.0; gap.top = 102.0; gap.index = 4;
   XSparkSmcPushGap(gaps, gap);
   XSparkSmcMitigateGaps(gaps, 101.5, 99.0);
   SmcCheck("a bearish gap survives price inside it, unlike the source",
            gaps.count == 1);
   XSparkSmcMitigateGaps(gaps, 102.5, 99.0);
   SmcCheck("a bearish gap dies when price trades through its top",
            gaps.count == 0);
}

// ---------------------------------------------------------------------------
// Fair value gaps.
// ---------------------------------------------------------------------------

void RunSmcGapTests()
{
   double opens[];  ArrayResize(opens, 4);
   double highs[];  ArrayResize(highs, 4);
   double lows[];   ArrayResize(lows, 4);
   double closes[]; ArrayResize(closes, 4);
   datetime times[];ArrayResize(times, 4);

   for(int i = 0; i < 4; i++)
      times[i] = (datetime)((4 - i) * 3600);

   // Series order: index 0 newest. A bullish gap needs lows[0] > highs[2] and a
   // middle bar that closed above highs[2].
   opens[2] = 100.0; highs[2] = 101.0; lows[2] = 99.0;  closes[2] = 100.5;
   opens[1] = 100.5; highs[1] = 105.0; lows[1] = 100.4; closes[1] = 104.5;
   opens[0] = 104.5; highs[0] = 106.0; lows[0] = 103.0; closes[0] = 105.0;
   opens[3] = 99.0;  highs[3] = 100.0; lows[3] = 98.0;  closes[3] = 99.5;

   XSparkSmcState state;
   XSparkSmcResetState(state);
   XSparkSmcStepGap(opens, highs, lows, closes, times, 0, 0.0, state);

   SmcCheck("three bars whose outer two do not overlap leave a bullish gap",
            state.gaps.count == 1 && state.gaps.items[0].bias == XSPARK_SIGNAL_BUY &&
            SmcNear(state.gaps.items[0].bottom, 101.0) && SmcNear(state.gaps.items[0].top, 103.0));

   // A threshold above the middle bar's body refuses it: a gap left by a bar
   // that barely moved is not displacement.
   XSparkSmcResetState(state);
   XSparkSmcStepGap(opens, highs, lows, closes, times, 0, 1.0, state);
   SmcCheck("a body below the displacement threshold leaves no gap",
            state.gaps.count == 0);

   // The bearish mirror.
   opens[2] = 105.0; highs[2] = 106.0; lows[2] = 104.0; closes[2] = 104.5;
   opens[1] = 104.5; highs[1] = 104.6; lows[1] = 100.0; closes[1] = 100.5;
   opens[0] = 100.5; highs[0] = 102.0; lows[0] = 99.0;  closes[0] = 101.0;

   XSparkSmcResetState(state);
   XSparkSmcStepGap(opens, highs, lows, closes, times, 0, 0.0, state);
   SmcCheck("the bearish mirror leaves a bearish gap",
            state.gaps.count == 1 && state.gaps.items[0].bias == XSPARK_SIGNAL_SELL &&
            SmcNear(state.gaps.items[0].bottom, 102.0) && SmcNear(state.gaps.items[0].top, 104.0));

   // Overlapping outer bars are not a gap at all.
   opens[0] = 100.5; highs[0] = 105.0; lows[0] = 99.0; closes[0] = 101.0;
   XSparkSmcResetState(state);
   XSparkSmcStepGap(opens, highs, lows, closes, times, 0, 0.0, state);
   SmcCheck("outer bars that overlap leave no gap",
            state.gaps.count == 0);
}

// ---------------------------------------------------------------------------
// The order block search.
// ---------------------------------------------------------------------------

void RunSmcStoreBlockTests()
{
   double highs[];  ArrayResize(highs, 8);
   double lows[];   ArrayResize(lows, 8);
   datetime times[];ArrayResize(times, 8);

   for(int i = 0; i < 8; i++)
   {
      highs[i] = 110.0;
      lows[i] = 109.0;
      times[i] = (datetime)((8 - i) * 3600);
   }

   // The lowest bar of the leg sits at index 4; a bullish break should pick it.
   lows[4] = 100.0; highs[4] = 101.0;

   XSparkSmcConfig config;
   SmcTestConfig(config);

   XSparkSmcState state;
   XSparkSmcResetState(state);
   state.measure = 5.0;   // a swap threshold of 10, far above any bar's range

   XSparkSmcStoreBlock(highs, lows, times, 1, 6, XSPARK_SIGNAL_BUY, true, true, 111.0, config, state);
   SmcCheck("a bullish break takes the lowest bar of the leg as its block",
            state.internal_blocks.count == 1 &&
            SmcNear(state.internal_blocks.items[0].low, 100.0) &&
            SmcNear(state.internal_blocks.items[0].high, 101.0) &&
            state.internal_blocks.items[0].index == 4 &&
            state.internal_blocks.items[0].bias == XSPARK_SIGNAL_BUY &&
            state.internal_blocks.items[0].choch);

   // A tie must resolve to the OLDEST bar, which is the largest series index.
   XSparkSmcResetState(state);
   state.measure = 5.0;
   lows[2] = 100.0; highs[2] = 101.0;
   XSparkSmcStoreBlock(highs, lows, times, 1, 6, XSPARK_SIGNAL_BUY, true, false, 111.0, config, state);
   SmcCheck("a tie between two equal extremes goes to the older bar",
            state.internal_blocks.count == 1 && state.internal_blocks.items[0].index == 4);

   // The volatility parse: a bar at least twice the measure has its high and
   // low swapped, which deflates it out of the contest entirely.
   XSparkSmcResetState(state);
   state.measure = 0.5;   // a swap threshold of 1.0
   lows[2] = 110.0; highs[2] = 110.5;
   lows[3] = 95.0;  highs[3] = 112.0;   // a 17-point bar: swapped, so it cannot win
   XSparkSmcStoreBlock(highs, lows, times, 1, 6, XSPARK_SIGNAL_BUY, true, false, 111.0, config, state);
   SmcCheck("a violent bar is parsed out of the order block contest",
            state.internal_blocks.count == 1 && state.internal_blocks.items[0].index == 4);

   // An empty leg stores nothing at all.
   XSparkSmcResetState(state);
   state.measure = 5.0;
   XSparkSmcStoreBlock(highs, lows, times, 5, 5, XSPARK_SIGNAL_BUY, true, false, 111.0, config, state);
   SmcCheck("a break with no leg behind it stores no block",
            state.internal_blocks.count == 0);

   // A bearish break takes the highest bar instead, into the swing ring.
   XSparkSmcResetState(state);
   state.measure = 5.0;
   for(int i = 0; i < 8; i++) { highs[i] = 110.0; lows[i] = 109.0; }
   highs[3] = 120.0; lows[3] = 119.0;
   XSparkSmcStoreBlock(highs, lows, times, 1, 6, XSPARK_SIGNAL_SELL, false, false, 108.0, config, state);
   SmcCheck("a bearish break takes the highest bar of the leg, into the swing ring",
            state.swing_blocks.count == 1 && state.internal_blocks.count == 0 &&
            SmcNear(state.swing_blocks.items[0].high, 120.0) &&
            state.swing_blocks.items[0].bias == XSPARK_SIGNAL_SELL);
}

// ---------------------------------------------------------------------------
// The replay.
// ---------------------------------------------------------------------------
//
// A 160-bar path whose structure is known by construction:
//
//   k 0-89    flat at 100     - no strict inequality, so no pivot at all
//   k 90-109  up to 120       - swing high pivot at k=109
//   k 110-124 down to 105     - swing low pivot at k=124
//   k 125-139 up to 126       - closes through 120.5: swing break, bullish
//   k 140-147 down to 110     - the pullback; swing high pivot at k=139
//   k 148-151 up to 118       - internal high pivot at k=151
//   k 152-154 down to 115     - the shallow dip that becomes the order block
//   k 155-159 up to 122       - closes through 118.5: internal break
//
// The final leg deliberately stops SHORT of the 126.5 swing high, so the
// internal break is a break of a level the swing structure does not share -
// which is the source's own condition for an internal break existing at all.
// The order block it leaves is the lowest bar of that leg, the dip at k=154.

#define SMC_FIXTURE_BARS 160

double SmcFixtureLevel(const int k)
{
   if(k <= 89) return 100.0;
   if(k <= 109) return 100.0 + (double)(k - 89);
   if(k <= 124) return 120.0 - (double)(k - 109);
   if(k <= 139) return 105.0 + (double)(k - 124) * 1.4;
   if(k <= 147) return 126.0 - (double)(k - 139) * 2.0;
   if(k <= 151) return 110.0 + (double)(k - 147) * 2.0;
   if(k <= 154) return 118.0 - (double)(k - 151);
   return 115.0 + (double)(k - 154) * 1.4;
}

void SmcBuildFixture(double &opens[], double &highs[], double &lows[], double &closes[], datetime &times[])
{
   ArrayResize(opens, SMC_FIXTURE_BARS);
   ArrayResize(highs, SMC_FIXTURE_BARS);
   ArrayResize(lows, SMC_FIXTURE_BARS);
   ArrayResize(closes, SMC_FIXTURE_BARS);
   ArrayResize(times, SMC_FIXTURE_BARS);

   for(int k = 0; k < SMC_FIXTURE_BARS; k++)
   {
      const double level = SmcFixtureLevel(k);
      const bool up = k == 0 ? true : level >= SmcFixtureLevel(k - 1);
      // Series order: the newest bar is index 0, so bar k lands at the far end.
      const int i = SMC_FIXTURE_BARS - 1 - k;
      opens[i] = up ? level - 0.3 : level + 0.3;
      closes[i] = up ? level + 0.3 : level - 0.3;
      highs[i] = level + 0.5;
      lows[i] = level - 0.5;
      times[i] = (datetime)((k + 1) * 3600);
   }
}

void RunSmcReplayTests()
{
   double opens[];
   double highs[];
   double lows[];
   double closes[];
   datetime times[];
   SmcBuildFixture(opens, highs, lows, closes, times);

   XSparkSmcConfig config;
   SmcTestConfig(config);

   XSparkSmcState state;
   string reason = "";

   SmcCheck("the replay walks the fixture without refusing it",
            XSparkSmcReplay(opens, highs, lows, closes, times, SMC_FIXTURE_BARS, config, state, reason));
   SmcCheck("the replay walks every bar the swing length leaves room for",
            state.bars_used == SMC_FIXTURE_BARS - config.swing_length);
   SmcCheck("the window's typical candle size is measurable",
            state.measure > 0.0);

   // Structure: both biases point up, and the swing high that was broken is
   // marked crossed so it cannot be broken twice.
   SmcCheck("the swing bias is bullish after the close through the swing high",
            state.swing_trend == XSPARK_SIGNAL_BUY);
   SmcCheck("the internal bias is bullish after the close through the internal high",
            state.internal_trend == XSPARK_SIGNAL_BUY);
   SmcCheck("the newest swing high is the leg's peak and has not been broken",
            state.swing_high.valid && SmcNear(state.swing_high.level, 126.5, 0.000001) &&
            !state.swing_high.crossed);
   SmcCheck("the newest swing low is the pullback trough",
            state.swing_low.valid && SmcNear(state.swing_low.level, 109.5, 0.000001));

   // The dealing range: the top ran with price to the fixture's high, the
   // bottom was re-anchored by the newest swing low.
   SmcCheck("the dealing range runs between the two newest swing pivots",
            state.trailing_valid && SmcNear(state.trailing_top, 126.5, 0.000001) &&
            SmcNear(state.trailing_bottom, 109.5, 0.000001));

   // The order block: the lowest bar of the leg that broke internal structure.
   SmcCheck("the internal break left an order block at the dip it rose from",
            state.internal_blocks.count > 0 &&
            state.internal_blocks.items[0].bias == XSPARK_SIGNAL_BUY &&
            SmcNear(state.internal_blocks.items[0].low, 114.5, 0.000001) &&
            SmcNear(state.internal_blocks.items[0].high, 115.5, 0.000001));
   SmcCheck("the block remembers the break that created it, two bars back",
            state.internal_blocks.items[0].break_index == 2 &&
            SmcNear(state.internal_blocks.items[0].broken_level, 118.5, 0.000001));
   // Not a change of character, and the reason is worth recording: every
   // earlier internal break in this fixture sat at exactly the swing pivot's
   // level, and the source refuses to count those as internal structure at all.
   // So the internal bias had never been set when this break arrived.
   SmcCheck("a first break with no prior bias is a continuation, not a reversal",
            !state.internal_blocks.items[0].choch && state.internal_blocks.items[0].internal);
   SmcCheck("the swing break left its own block, at the swing trough",
            state.swing_blocks.count > 0 &&
            state.swing_blocks.items[0].bias == XSPARK_SIGNAL_BUY &&
            SmcNear(state.swing_blocks.items[0].low, 104.5, 0.000001));

   // Determinism: the same window replayed twice is the same answer. This is
   // the whole reason the model rebuilds instead of remembering.
   XSparkSmcState again;
   string again_reason = "";
   XSparkSmcReplay(opens, highs, lows, closes, times, SMC_FIXTURE_BARS, config, again, again_reason);
   SmcCheck("replaying the same window twice gives the same structure",
            again.swing_trend == state.swing_trend &&
            again.internal_trend == state.internal_trend &&
            SmcNear(again.trailing_top, state.trailing_top) &&
            again.internal_blocks.count == state.internal_blocks.count);

   // Refusals.
   XSparkSmcConfig deep;
   SmcTestConfig(deep);
   deep.swing_length = SMC_FIXTURE_BARS;
   SmcCheck("a swing longer than the window is refused rather than silently empty",
            !XSparkSmcReplay(opens, highs, lows, closes, times, SMC_FIXTURE_BARS, deep, state, reason) &&
            reason != "");

   SmcCheck("a window of one bar is refused",
            !XSparkSmcReplay(opens, highs, lows, closes, times, 1, config, state, reason));
}

// The equal-high detector, on a zigzag whose second peak sits two hundredths
// above the first - well inside the published threshold.
void RunSmcEqualTests()
{
   const int count = 40;
   double opens[];
   double highs[];
   double lows[];
   double closes[];
   datetime times[];
   ArrayResize(opens, count); ArrayResize(highs, count);
   ArrayResize(lows, count); ArrayResize(closes, count);
   ArrayResize(times, count);

   // Three zigzag cycles whose peaks sit two hundredths apart - inside the
   // threshold - and whose troughs are identical, then a walk away from both.
   // The replay cannot start at bar zero, so the first cycle is warm-up and the
   // equal pair the test is about is the second against the third.
   double levels[];
   ArrayResize(levels, count);
   const int pattern = 8;
   for(int k = 0; k < count; k++)
   {
      if(k >= 3 * pattern)
      {
         levels[k] = 99.0 - (double)(k - 3 * pattern) * 0.5;
         continue;
      }

      const int step = k % pattern;
      if(step == 3)
         levels[k] = 103.0 + 0.02 * (double)(k / pattern);
      else
         levels[k] = step < 3 ? 100.0 + (double)step : 103.0 - (double)(step - 3);
   }

   for(int k = 0; k < count; k++)
   {
      const int i = count - 1 - k;
      const bool up = k == 0 ? true : levels[k] >= levels[k - 1];
      opens[i] = up ? levels[k] - 0.3 : levels[k] + 0.3;
      closes[i] = up ? levels[k] + 0.3 : levels[k] - 0.3;
      highs[i] = levels[k] + 0.5;
      lows[i] = levels[k] - 0.5;
      times[i] = (datetime)((k + 1) * 3600);
   }

   XSparkSmcConfig config;
   SmcTestConfig(config);
   config.swing_length = 5;

   XSparkSmcState state;
   string reason = "";
   SmcCheck("the equal-high zigzag replays",
            XSparkSmcReplay(opens, highs, lows, closes, times, count, config, state, reason));
   SmcCheck("two peaks within the threshold are recorded as equal highs",
            state.equal_high_found && SmcNear(state.equal_high_level, 103.54, 0.000001));
   SmcCheck("two identical troughs are recorded as equal lows",
            state.equal_low_found && SmcNear(state.equal_low_level, 98.5, 0.000001));
}

// ---------------------------------------------------------------------------
// The rule.
// ---------------------------------------------------------------------------
//
// Hand-built states rather than bar fixtures: each refusal is one condition, so
// each test changes exactly one number and the reason it fails is not in doubt.

void SmcBuildState(XSparkSmcState &state, const int bias)
{
   XSparkSmcResetState(state);
   state.measure = 1.0;
   state.bars_used = 100;
   state.internal_trend = bias;
   state.swing_trend = bias;
   state.trailing_top_valid = true;
   state.trailing_bottom_valid = true;
   state.trailing_valid = true;
   state.trailing_top = 130.0;
   state.trailing_bottom = 100.0;

   XSparkSmcBlock block;
   XSparkSmcResetBlock(block);
   block.bias = bias;
   block.internal = true;
   block.choch = true;
   block.break_index = 4;
   block.break_time = (datetime)7200;
   block.pivot_index = 20;
   block.index = 12;
   block.time = (datetime)3600;
   block.broken_level = bias == XSPARK_SIGNAL_BUY ? 125.0 : 105.0;
   // A buy enters low in the range and a sell enters high in it.
   block.low = bias == XSPARK_SIGNAL_BUY ? 108.0 : 120.0;
   block.high = bias == XSPARK_SIGNAL_BUY ? 110.0 : 122.0;
   XSparkSmcPushBlock(state.internal_blocks, block);
}

void RunSmcEvaluateTests()
{
   XSparkSmcConfig config;
   SmcTestConfig(config);

   XSparkSmcState state;
   XSparkSmcSetup setup;
   XSparkSmcVerdicts verdicts;

   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("a bullish block in discount with a draw above it is a signal",
            XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            setup.direction == XSPARK_SIGNAL_BUY &&
            SmcNear(setup.entry_limit, 109.0) &&
            verdicts.structure == "CHOCH" && verdicts.location == "DISCOUNT" &&
            verdicts.liquidity == "DRAW FOUND");
   SmcCheck("the entry is the block's midpoint and the stop sits beyond its low",
            SmcNear(setup.stop, 108.0 - 20.0 * 0.01) && setup.stop < setup.block_low);
   SmcCheck("the reward ratio is an output of where the draw sits",
            SmcNear(setup.target, 130.0) &&
            SmcNear(setup.target_r, (130.0 - 109.0) / (109.0 - (108.0 - 0.2)), 0.000001));
   SmcCheck("the setup is identified by the break, not by the bar evaluated",
            setup.break_time == (datetime)7200);

   // The bearish mirror.
   SmcBuildState(state, XSPARK_SIGNAL_SELL);
   SmcCheck("the bearish mirror signals out of premium",
            XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            setup.direction == XSPARK_SIGNAL_SELL &&
            SmcNear(setup.entry_limit, 121.0) &&
            verdicts.location == "PREMIUM" && SmcNear(setup.target, 100.0));

   // An empty window has no structure to read.
   XSparkSmcResetState(state);
   state.bars_used = 100;
   state.measure = 1.0;
   SmcCheck("a window with no order block says so",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.structure == "NO STRUCTURE");

   // Too old to enter.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.internal_blocks.items[0].break_index = config.max_block_age_bars + 1;
   SmcCheck("a block older than the age bound is refused",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.structure == "BLOCK EXPIRED");

   // Structure has since broken the other way.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.internal_trend = XSPARK_SIGNAL_SELL;
   SmcCheck("a block whose own structure has flipped is refused",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.structure == "STRUCTURE FLIPPED");

   // The swing bias disagrees: refused by default, allowed when the structure
   // selection says internal alone.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.swing_trend = XSPARK_SIGNAL_SELL;
   SmcCheck("an internal break against the swing bias is refused by default",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.structure == "AGAINST SWING");

   XSparkSmcConfig internal_only;
   SmcTestConfig(internal_only);
   internal_only.structure_mode = XSPARK_SMC_INTERNAL_ONLY;
   SmcCheck("the same setup passes when internal structure is traded alone",
            XSparkSmcEvaluate(state, internal_only, 0.01, setup, verdicts));

   // Swing-only ignores the internal ring entirely.
   XSparkSmcConfig swing_only;
   SmcTestConfig(swing_only);
   swing_only.structure_mode = XSPARK_SMC_SWING_ONLY;
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("swing-only does not enter an internal block",
            !XSparkSmcEvaluate(state, swing_only, 0.01, setup, verdicts) &&
            verdicts.structure == "NO STRUCTURE");

   // Too thin to be a zone.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   XSparkSmcConfig thick;
   SmcTestConfig(thick);
   thick.min_block_price = 5.0;
   SmcCheck("a block thinner than a round trip costs is refused",
            !XSparkSmcEvaluate(state, thick, 0.01, setup, verdicts) &&
            verdicts.block == "BLOCK TOO THIN");

   // The wrong half of the dealing range.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.internal_blocks.items[0].low = 124.0;
   state.internal_blocks.items[0].high = 126.0;
   SmcCheck("a buy from the premium half is refused",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.location == "WRONG HALF");

   XSparkSmcConfig no_zones;
   SmcTestConfig(no_zones);
   no_zones.use_premium_discount = false;
   SmcCheck("switching the zones off lets the same entry through and says OFF",
            XSparkSmcEvaluate(state, no_zones, 0.01, setup, verdicts) &&
            verdicts.location == "OFF");

   // No dealing range at all.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.trailing_valid = false;
   SmcCheck("a window with no dealing range is refused",
            !XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) &&
            verdicts.location == "RANGE UNKNOWN");

   // The draw. With the zones on, an entry in discount is by definition below
   // the top of the range, so "no draw at all" is only reachable with them off -
   // which is worth stating, because it means the discount filter and the draw
   // check are not two independent conditions.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.trailing_top = 108.5;   // behind the entry
   SmcCheck("with the zones off, a draw behind the entry leaves nowhere to go",
            !XSparkSmcEvaluate(state, no_zones, 0.01, setup, verdicts) &&
            verdicts.liquidity == "NO DRAW");

   XSparkSmcConfig far_floor;
   SmcTestConfig(far_floor);
   far_floor.min_target_r = 30.0;
   far_floor.max_target_r = 60.0;
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("a draw too close to pay for the stop is refused",
            !XSparkSmcEvaluate(state, far_floor, 0.01, setup, verdicts) &&
            verdicts.liquidity == "DRAW TOO CLOSE");

   XSparkSmcConfig near_ceiling;
   SmcTestConfig(near_ceiling);
   near_ceiling.max_target_r = 5.0;
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("a draw beyond the upper bound is a different trade",
            !XSparkSmcEvaluate(state, near_ceiling, 0.01, setup, verdicts) &&
            verdicts.liquidity == "DRAW TOO FAR");

   // Equal highs sitting on the draw are reported as the stronger pool.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.equal_high_found = true;
   state.equal_high_level = 130.0;
   SmcCheck("a draw resting on equal highs is marked as such",
            XSparkSmcEvaluate(state, config, 0.01, setup, verdicts) && setup.equal_draw);

   // The imbalance requirement.
   XSparkSmcConfig with_gap;
   SmcTestConfig(with_gap);
   with_gap.require_gap = true;
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("the stricter confluence refuses a leg that left no gap",
            !XSparkSmcEvaluate(state, with_gap, 0.01, setup, verdicts) &&
            verdicts.imbalance == "NO IMBALANCE");

   XSparkSmcGap gap;
   XSparkSmcResetGap(gap);
   gap.bias = XSPARK_SIGNAL_BUY;
   gap.bottom = 112.0; gap.top = 114.0; gap.index = 6;
   XSparkSmcPushGap(state.gaps, gap);
   SmcCheck("a gap inside the leg satisfies the stricter confluence",
            XSparkSmcEvaluate(state, with_gap, 0.01, setup, verdicts) &&
            verdicts.imbalance == "IMBALANCE");

   // A gap older than the leg's origin is evidence about some earlier move.
   state.gaps.items[0].index = state.internal_blocks.items[0].pivot_index + 1;
   SmcCheck("a gap older than the leg does not count as its displacement",
            !XSparkSmcEvaluate(state, with_gap, 0.01, setup, verdicts) &&
            verdicts.imbalance == "NO IMBALANCE");

   // An unusable point size refuses rather than placing a stop at the entry.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("an unusable point size is refused",
            !XSparkSmcEvaluate(state, config, 0.0, setup, verdicts));
}

// ---------------------------------------------------------------------------
// Which break is traded.
// ---------------------------------------------------------------------------
//
// The indicator's All / BOS / CHoCH filter, which there decides which labels
// are drawn and here decides which breaks are traded.

void RunSmcBreakTypeTests()
{
   XSparkSmcConfig any_break;
   SmcTestConfig(any_break);

   XSparkSmcConfig reversals;
   SmcTestConfig(reversals);
   reversals.break_type = XSPARK_SMC_BREAK_REVERSAL;

   XSparkSmcConfig continuations;
   SmcTestConfig(continuations);
   continuations.break_type = XSPARK_SMC_BREAK_CONTINUATION;

   XSparkSmcState state;
   XSparkSmcSetup setup;
   XSparkSmcVerdicts verdicts;

   // SmcBuildState leaves the block marked as a change of character.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   SmcCheck("a change of character is taken when both kinds are traded",
            XSparkSmcEvaluate(state, any_break, 0.01, setup, verdicts) &&
            verdicts.structure == "CHOCH");

   SmcCheck("a change of character is taken when only reversals are traded",
            XSparkSmcEvaluate(state, reversals, 0.01, setup, verdicts) &&
            verdicts.structure == "CHOCH");

   SmcCheck("a change of character is refused when only continuations are traded",
            !XSparkSmcEvaluate(state, continuations, 0.01, setup, verdicts) &&
            verdicts.structure == "WRONG BREAK TYPE");

   // The mirror: the same block as a break of structure.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.internal_blocks.items[0].choch = false;

   SmcCheck("a break of structure is taken when both kinds are traded",
            XSparkSmcEvaluate(state, any_break, 0.01, setup, verdicts) &&
            verdicts.structure == "BOS");

   SmcCheck("a break of structure is taken when only continuations are traded",
            XSparkSmcEvaluate(state, continuations, 0.01, setup, verdicts) &&
            verdicts.structure == "BOS");

   SmcCheck("a break of structure is refused when only reversals are traded",
            !XSparkSmcEvaluate(state, reversals, 0.01, setup, verdicts) &&
            verdicts.structure == "WRONG BREAK TYPE");

   // The refusal must name what the bot is actually taking, or the operator
   // cannot tell it from a market that simply produced nothing.
   SmcCheck("the refusal says which kind of break this bot takes",
            StringFind(setup.reason, "change") >= 0 || StringFind(setup.reason, "structure") >= 0);

   // Ordering: the swing-alignment refusal is reported before this one, because
   // a break pointing the wrong way is the more fundamental miss.
   SmcBuildState(state, XSPARK_SIGNAL_BUY);
   state.swing_trend = XSPARK_SIGNAL_SELL;
   state.internal_blocks.items[0].choch = false;
   SmcCheck("a block against the swing reports that before the break type",
            !XSparkSmcEvaluate(state, reversals, 0.01, setup, verdicts) &&
            verdicts.structure == "AGAINST SWING");

   string reason = "";
   XSparkSmcConfig broken;
   XSparkSmcDefaultConfig(broken);
   broken.break_type = 99;
   SmcCheck("an unknown break selection is refused",
            !XSparkSmcConfigUsable(broken, reason) && reason != "");
}

// ---------------------------------------------------------------------------
// The presets behind the dropdowns.
// ---------------------------------------------------------------------------
//
// Each dropdown applies a whole configuration. What these check is that every
// value is one the model accepts and the window can actually hold - a choice
// that can never produce a trade is a broken choice, not a conservative one.

void RunSmcPresetTests()
{
   string reason = "";

   XSparkSmcConfig normal;
   XSparkSmcDefaultConfig(normal);
   XSparkSmcConfig applied;
   XSparkSmcDefaultConfig(applied);

   SmcCheck("the normal swing size is what the shipped defaults already are",
            XSparkSmcApplySwingSize(applied, XSPARK_SMC_SWING_NORMAL, reason) &&
            applied.swing_length == normal.swing_length &&
            applied.internal_length == normal.internal_length &&
            applied.max_block_age_bars == normal.max_block_age_bars);
   SmcCheck("the normal swing size is the indicator's published pair",
            applied.swing_length == 50 && applied.internal_length == 5);

   XSparkSmcConfig fast;
   XSparkSmcDefaultConfig(fast);
   XSparkSmcConfig slow;
   XSparkSmcDefaultConfig(slow);

   SmcCheck("every swing size applies and validates",
            XSparkSmcApplySwingSize(fast, XSPARK_SMC_SWING_FAST, reason) &&
            XSparkSmcConfigUsable(fast, reason) &&
            XSparkSmcApplySwingSize(slow, XSPARK_SMC_SWING_SLOW, reason) &&
            XSparkSmcConfigUsable(slow, reason));

   SmcCheck("the three sizes are ordered, and each moves all three numbers",
            fast.swing_length < normal.swing_length && normal.swing_length < slow.swing_length &&
            fast.internal_length < normal.internal_length && normal.internal_length < slow.internal_length &&
            fast.max_block_age_bars < normal.max_block_age_bars &&
            normal.max_block_age_bars < slow.max_block_age_bars);

   // Every size must fit the structure window, or the strategy object refuses
   // to initialize on it and the dropdown ships a value that cannot run.
   SmcCheck("every swing size fits the cached structure window",
            XSparkSmcRequiredBars(fast) < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS &&
            XSparkSmcRequiredBars(normal) < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS &&
            XSparkSmcRequiredBars(slow) < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);

   // And every size must leave enough replay to produce a swing pivot at all.
   SmcCheck("every swing size leaves more replay than one swing needs",
            XSparkSmcReplayBars(fast, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) > fast.swing_length &&
            XSparkSmcReplayBars(normal, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) > normal.swing_length &&
            XSparkSmcReplayBars(slow, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) > slow.swing_length);

   // The window is comfortable for the fast size and tight for the slow one.
   // That is the honest state of a 160-candle window, and the EA warns on it
   // rather than letting the funnel discover it a week later.
   SmcCheck("the fast size has room to spare and the slow one does not",
            XSparkSmcWindowIsComfortable(fast, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) &&
            !XSparkSmcWindowIsComfortable(slow, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS));

   SmcCheck("replay bars shrink as the swing grows, and never go negative",
            XSparkSmcReplayBars(fast, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) >
            XSparkSmcReplayBars(slow, XSPARK_SCOREBOT_STRUCTURE_BASE_BARS) &&
            XSparkSmcReplayBars(normal, 10) == 0);

   SmcCheck("an unknown swing size is refused rather than silently normal",
            !XSparkSmcApplySwingSize(applied, 99, reason) && reason != "");

   // Selectivity.
   XSparkSmcConfig balanced;
   XSparkSmcDefaultConfig(balanced);
   XSparkSmcConfig strict;
   XSparkSmcDefaultConfig(strict);
   XSparkSmcConfig permissive;
   XSparkSmcDefaultConfig(permissive);

   SmcCheck("balanced keeps the range filter and asks for no gap",
            XSparkSmcApplySelectivity(balanced, XSPARK_SMC_BALANCED, reason) &&
            balanced.use_premium_discount && !balanced.require_gap);
   SmcCheck("strict keeps the range filter and adds the gap",
            XSparkSmcApplySelectivity(strict, XSPARK_SMC_STRICT, reason) &&
            strict.use_premium_discount && strict.require_gap);
   SmcCheck("permissive drops both",
            XSparkSmcApplySelectivity(permissive, XSPARK_SMC_PERMISSIVE, reason) &&
            !permissive.use_premium_discount && !permissive.require_gap);
   SmcCheck("balanced is what the shipped defaults already are",
            balanced.use_premium_discount == normal.use_premium_discount &&
            balanced.require_gap == normal.require_gap);
   SmcCheck("an unknown selectivity is refused",
            !XSparkSmcApplySelectivity(balanced, 99, reason) && reason != "");

   // Each preset must still describe itself: the EA prints these at startup and
   // an empty string there is an operator with no idea what the bot is doing.
   SmcCheck("every dropdown value names itself for the journal",
            XSparkSmcStructureName(XSPARK_SMC_INTERNAL_WITH_SWING) != "" &&
            XSparkSmcStructureName(XSPARK_SMC_SWING_ONLY) != "" &&
            XSparkSmcBreakTypeName(XSPARK_SMC_BREAK_ANY) != "" &&
            XSparkSmcBreakTypeName(XSPARK_SMC_BREAK_REVERSAL) != "" &&
            XSparkSmcBreakTypeName(XSPARK_SMC_BREAK_CONTINUATION) != "" &&
            XSparkSmcSwingSizeName(XSPARK_SMC_SWING_FAST) != "" &&
            XSparkSmcSwingSizeName(XSPARK_SMC_SWING_SLOW) != "" &&
            XSparkSmcSelectivityName(XSPARK_SMC_STRICT) != "" &&
            XSparkSmcSelectivityName(XSPARK_SMC_PERMISSIVE) != "");
}

// ---------------------------------------------------------------------------
// Configuration.
// ---------------------------------------------------------------------------

void RunSmcConfigTests()
{
   XSparkSmcConfig config;
   XSparkSmcDefaultConfig(config);
   string reason = "";

   SmcCheck("the shipped configuration validates",
            XSparkSmcConfigUsable(config, reason) && reason == "");
   SmcCheck("the shipped lengths are the published ones",
            config.swing_length == 50 && config.internal_length == 5 &&
            config.equal_length == 3 && SmcNear(config.equal_threshold, 0.1));
   SmcCheck("the shipped default trades internal structure with the swing bias",
            config.structure_mode == XSPARK_SMC_INTERNAL_WITH_SWING &&
            config.break_type == XSPARK_SMC_BREAK_ANY &&
            !config.require_gap && config.use_premium_discount);
   SmcCheck("the shipped configuration fits the cached structure window",
            XSparkSmcRequiredBars(config) < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);

   XSparkSmcConfig broken;
   XSparkSmcDefaultConfig(broken);
   broken.internal_length = broken.swing_length;
   SmcCheck("an internal structure as long as the swing is refused",
            !XSparkSmcConfigUsable(broken, reason) && reason != "");

   XSparkSmcDefaultConfig(broken);
   broken.structure_mode = 99;
   SmcCheck("an unknown structure selection is refused",
            !XSparkSmcConfigUsable(broken, reason));

   XSparkSmcDefaultConfig(broken);
   broken.max_target_r = broken.min_target_r;
   SmcCheck("reward bounds that cannot hold a value are refused",
            !XSparkSmcConfigUsable(broken, reason));

   XSparkSmcDefaultConfig(broken);
   broken.max_stop_atr = broken.min_stop_atr;
   SmcCheck("stop bounds that cannot hold a value are refused",
            !XSparkSmcConfigUsable(broken, reason));

   XSparkSmcDefaultConfig(broken);
   broken.max_block_age_bars = 0;
   SmcCheck("a zero age bound is refused",
            !XSparkSmcConfigUsable(broken, reason));
}

// ---------------------------------------------------------------------------
// Cost and the live stop.
// ---------------------------------------------------------------------------

void RunSmcCostAndStopTests()
{
   double cost = 0.0, commission = 0.0;
   string reason = "";

   SmcCheck("the round-trip cost is the spread plus the commission in price",
            XSparkSmcRoundTripCost(0.20, 7.0, 0.01, 0.10, cost, commission, reason) &&
            SmcNear(commission, 0.70) && SmcNear(cost, 0.90));
   SmcCheck("a commission that cannot be converted to price is refused",
            !XSparkSmcRoundTripCost(0.20, 7.0, 0.0, 0.10, cost, commission, reason) && reason != "");
   SmcCheck("a negative spread is refused",
            !XSparkSmcRoundTripCost(-0.1, 0.0, 0.01, 0.10, cost, commission, reason));

   XSparkSmcConfig config;
   XSparkSmcDefaultConfig(config);

   double stop = 0.0, distance = 0.0;
   // The model's own stop is inside both bounds, so it is used unchanged.
   SmcCheck("a stop inside the bounds is sent as the model placed it",
            XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 109.0, 1.0, 0.0, config, stop, distance, reason) &&
            SmcNear(distance, 1.0) && SmcNear(stop, 109.0));

   // Too tight for the typical candle: widened to the floor, never tightened.
   SmcCheck("a stop tighter than the floor is widened to it",
            XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 109.9, 1.0, 0.0, config, stop, distance, reason) &&
            SmcNear(distance, config.min_stop_atr) && stop < 109.9);

   // Too wide for this model: refused rather than sent.
   SmcCheck("a stop past the ceiling is refused",
            !XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 100.0, 1.0, 0.0, config, stop, distance, reason));

   // When the cost is what pushes it past the ceiling, the reason says COST
   // first, because only the operator can fix that one.
   SmcCheck("a cost-driven refusal names the cost first",
            !XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 109.5, 1.0, 1.0, config, stop, distance, reason) &&
            StringFind(reason, "COST:") == 0);

   SmcCheck("a market already past the model's stop is refused",
            !XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 111.0, 1.0, 0.0, config, stop, distance, reason));
   SmcCheck("a stop with no typical candle size to bound it is refused",
            !XSparkSmcStop(XSPARK_SIGNAL_BUY, 110.0, 109.0, 0.0, 0.0, config, stop, distance, reason));
   SmcCheck("a stop with no direction is refused",
            !XSparkSmcStop(XSPARK_SIGNAL_NONE, 110.0, 109.0, 1.0, 0.0, config, stop, distance, reason));

   // The bearish mirror sits above the entry.
   SmcCheck("a sell stop sits above the entry reference",
            XSparkSmcStop(XSPARK_SIGNAL_SELL, 110.0, 111.0, 1.0, 0.0, config, stop, distance, reason) &&
            SmcNear(stop, 111.0));
}

// ---------------------------------------------------------------------------
// Win rates, hold time and the weekend backstop.
// ---------------------------------------------------------------------------

void RunSmcWinRateTests()
{
   SmcCheck("a one-to-one trade breaks even at half the trades",
            SmcNear(XSparkSmcBreakEvenWinRate(1.0), 0.5));
   SmcCheck("cost pushes the no-edge win rate below break-even",
            XSparkSmcNoEdgeWinRate(1.0, 6.0) < XSparkSmcBreakEvenWinRate(1.0));
   SmcCheck("an unusable reward ratio returns zero rather than a number",
            SmcNear(XSparkSmcBreakEvenWinRate(0.0), 0.0) &&
            SmcNear(XSparkSmcNoEdgeWinRate(1.0, 100.0), 0.0));

   double lower = 0.0;
   SmcCheck("twenty of forty cannot be distinguished from a coin flip",
            XSparkSmcWilsonLowerBound(20, 40, lower) && lower < 0.5);
   SmcCheck("two hundred of four hundred can be",
            XSparkSmcWilsonLowerBound(200, 400, lower) && lower > 0.45);
   SmcCheck("a sample with no outcomes has no bound",
            !XSparkSmcWilsonLowerBound(0, 0, lower));
   SmcCheck("more wins than outcomes is refused",
            !XSparkSmcWilsonLowerBound(5, 4, lower));
}

void RunSmcHoldAndWeekendTests()
{
   SmcCheck("the hold time is a bar count until the wall clock binds",
            XSparkSmcMaxHoldSeconds(300) == XSPARK_SMC_MAX_HOLD_BARS * 300);
   SmcCheck("a long chart period is capped by the wall clock",
            XSparkSmcMaxHoldSeconds(14400) == XSPARK_SMC_MAX_HOLD_SECONDS);
   SmcCheck("an unusable chart period has no hold time",
            XSparkSmcMaxHoldSeconds(0) == 0);

   bool use_close = true;
   int hour = 0, minute = 0;
   string reason = "";

   SmcCheck("a market that trades at the weekend is not closed for one",
            XSparkSmcWeekendClose(true, true, 3600, use_close, hour, minute, reason) && !use_close);
   SmcCheck("an unknown Friday session falls back to the published time",
            XSparkSmcWeekendClose(false, false, 0, use_close, hour, minute, reason) &&
            use_close && hour == XSPARK_SMC_WEEKEND_CLOSE_HOUR &&
            minute == XSPARK_SMC_WEEKEND_CLOSE_MINUTE);
   SmcCheck("a known Friday session closes a quarter hour before it ends",
            XSparkSmcWeekendClose(false, true, 21 * 3600, use_close, hour, minute, reason) &&
            use_close && hour == 20 && minute == 45);
   SmcCheck("a session ending inside the lead time closes as the day opens",
            XSparkSmcWeekendClose(false, true, 600, use_close, hour, minute, reason) &&
            use_close && hour == 0 && minute == 0);
   SmcCheck("a full-day Friday session flattens before midnight",
            XSparkSmcWeekendClose(false, true, XSPARK_SMC_SECONDS_PER_DAY, use_close, hour, minute, reason) &&
            use_close && hour == 23 && minute == 45);
}

// ---------------------------------------------------------------------------
// The strategy object.
// ---------------------------------------------------------------------------

#ifdef XSPARK_PORTABLE_TEST
void RunSmcStrategyTests()
{
   double opens[];
   double highs[];
   double lows[];
   double closes[];
   datetime times[];
   SmcBuildFixture(opens, highs, lows, closes, times);

   CXSparkIndicatorCache cache;
   cache.structure_base.resize(XSPARK_SCOREBOT_STRUCTURE_BASE_BARS);
   cache.base.resize(XSPARK_SCOREBOT_CLOSED_BASE_BARS);
   for(int i = 0; i < XSPARK_SCOREBOT_STRUCTURE_BASE_BARS; i++)
   {
      cache.structure_base[i].time = times[i];
      cache.structure_base[i].open = opens[i];
      cache.structure_base[i].high = highs[i];
      cache.structure_base[i].low = lows[i];
      cache.structure_base[i].close = closes[i];
      cache.structure_base[i].tick_volume = 100;
      if(i < XSPARK_SCOREBOT_CLOSED_BASE_BARS)
         cache.base[i] = cache.structure_base[i];
   }

   CXSparkSmartMoney strategy;
   XSparkSmcConfig config;
   SmcTestConfig(config);
   strategy.Configure(config);

   XSparkSignal signal;
   XSparkScoreBotReport report;

   SmcCheck("an uninitialized strategy never signals",
            !strategy.Evaluate(cache, signal, report) &&
            report.status == "SCANNING" && report.pattern_mode == "SMART MONEY");

   SmcCheck("the strategy refuses a symbol it was not given",
            !strategy.Initialize(""));
   SmcCheck("the strategy initializes on the test configuration",
            strategy.Initialize("TEST"));

   // A configuration whose replay would not fit the cached window is refused at
   // initialization rather than quietly producing no structure at all.
   CXSparkSmartMoney deep;
   XSparkSmcConfig too_deep;
   SmcTestConfig(too_deep);
   too_deep.swing_length = XSPARK_SCOREBOT_STRUCTURE_BASE_BARS;
   deep.Configure(too_deep);
   SmcCheck("a configuration that would read past the cache is refused",
            !deep.Initialize("TEST"));

   // The structure window has not loaded yet: no signal, and it says why.
   cache.structure_ready = false;
   SmcCheck("a strategy with no structure window waits rather than guessing",
            !strategy.Evaluate(cache, signal, report) && report.block_reason != "");

   cache.structure_ready = true;
   const bool signalled = strategy.Evaluate(cache, signal, report);
   SmcCheck("the fixture produces a bullish signal through the strategy object",
            signalled && signal.direction == XSPARK_SIGNAL_BUY &&
            report.status == "SIGNAL" && report.htf_verdict == "BOS");
   SmcCheck("the signal carries a limit at the block midpoint and a stop below it",
            SmcNear(signal.entry_limit, 115.0, 0.000001) &&
            signal.desired_stop < signal.entry_limit &&
            signal.desired_target == 0.0);
   SmcCheck("the signal carries the ratio its own draw implied",
            signal.dynamic_rr > 0.0 && SmcNear(signal.dynamic_rr, report.dynamic_rr));
   SmcCheck("the signal is keyed on the structure break, not the bar evaluated",
            signal.signal_bar_time == report.detected_instance &&
            signal.signal_bar_time != report.signal_bar_time);
   SmcCheck("the replayed structure is readable for the journal",
            strategy.SwingTrend() == XSPARK_SIGNAL_BUY && strategy.TrailingValid() &&
            strategy.LiveBlockCount() > 0);

   // A minimum block wider than the fixture's block refuses it by name.
   strategy.SetMinimumBlock(50.0);
   SmcCheck("a minimum block wider than the zone refuses the entry",
            !strategy.Evaluate(cache, signal, report) &&
            report.pullback_verdict == "BLOCK TOO THIN");
   strategy.SetMinimumBlock(0.0);

   // An invalid cache is reported, never traded through.
   cache.valid = false;
   SmcCheck("an invalid cache blocks the strategy",
            !strategy.Evaluate(cache, signal, report) && report.block_reason != "");
   cache.valid = true;

   strategy.Deinitialize();
   SmcCheck("a deinitialized strategy never signals",
            !strategy.Evaluate(cache, signal, report));
}
#endif

void RunSmcTests()
{
   RunSmcLegTests();
   RunSmcMeasureTests();
   RunSmcRingTests();
   RunSmcGapTests();
   RunSmcStoreBlockTests();
   RunSmcReplayTests();
   RunSmcEqualTests();
   RunSmcEvaluateTests();
   RunSmcBreakTypeTests();
   RunSmcPresetTests();
   RunSmcConfigTests();
   RunSmcCostAndStopTests();
   RunSmcWinRateTests();
   RunSmcHoldAndWeekendTests();
#ifdef XSPARK_PORTABLE_TEST
   RunSmcStrategyTests();
#endif

   Print("SMC RESULT passed=", g_smc_passed, " failed=", g_smc_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunSmcTests(); }
#endif
