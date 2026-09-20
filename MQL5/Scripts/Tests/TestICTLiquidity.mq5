#property script_show_inputs
#include <XSpark/Strategy/ICTLiquidity.mqh>

// Deterministic checks for the mechanized ICT liquidity model.
//
// These cover pure shape detection only: swing points, the sweep, the fair
// value gap, displacement, the kill-zone clock, premium/discount, and the four
// conditions assembled in both directions. Every fixture is a hand-built bar
// array whose answer is known by construction.
//
// Broker behaviour, sizing, execution and spread are not exercised here and
// must be validated in the Strategy Tester and on a demo account.
//
// NOTHING HERE MEASURES AN EDGE. A rule that fires exactly where it was
// designed to fire is a correct rule, not a profitable one. These tests say the
// model is faithfully implemented; only out-of-sample testing can say whether
// what it implements is worth trading.

int g_ict_passed = 0, g_ict_failed = 0;

void IctCheck(const string name, const bool ok)
{
   if(ok) { g_ict_passed++; Print("PASS: ",name); }
   else { g_ict_failed++; Print("FAIL: ",name); }
}

bool IctNear(const double a, const double b, const double tolerance = 0.0000001)
{
   return MathAbs(a - b) < tolerance;
}

// ---------------------------------------------------------------------------
// Swing points.
// ---------------------------------------------------------------------------

void RunIctSwingTests()
{
   // Series order: index 0 is newest. This array has its peak at index 3.
   //   idx:      0     1     2     3     4     5     6
   double highs[];
   ArrayResize(highs, 7);
   highs[0] = 10.0;
   highs[1] = 11.0;
   highs[2] = 12.0;
   highs[3] = 15.0;
   highs[4] = 12.5;
   highs[5] = 11.5;
   highs[6] = 10.5;
   double lows[];
   ArrayResize(lows, 7);
   lows[0] = 9.0;
   lows[1] = 8.0;
   lows[2] = 7.0;
   lows[3] = 4.0;
   lows[4] = 7.5;
   lows[5] = 8.5;
   lows[6] = 9.5;

   IctCheck("a peak with two lower bars either side is a swing high",
            XSparkIctIsSwingHigh(highs, 3, 2));
   IctCheck("a bar on the way up is not a swing high",
            !XSparkIctIsSwingHigh(highs, 2, 2));
   IctCheck("a trough with two higher bars either side is a swing low",
            XSparkIctIsSwingLow(lows, 3, 2));
   IctCheck("a bar on the way down is not a swing low",
            !XSparkIctIsSwingLow(lows, 2, 2));

   // Too close to either end: there is not enough room for the strength.
   IctCheck("an index without room on the newer side is refused",
            !XSparkIctIsSwingHigh(highs, 1, 2));
   IctCheck("an index without room on the older side is refused",
            !XSparkIctIsSwingHigh(highs, 5, 2));
   IctCheck("a zero strength is refused",
            !XSparkIctIsSwingHigh(highs, 3, 0));

   // A flat top must resolve to one swing, not two. Ties are allowed on the
   // older side and refused on the newer side, so the NEWEST bar of the flat
   // run wins - the most recent time the market was offered at that level, and
   // so the one the resting stops actually sit above.
   double flat[];
   ArrayResize(flat, 7);
   flat[0] = 10.0;
   flat[1] = 11.0;
   flat[2] = 15.0;
   flat[3] = 15.0;
   flat[4] = 12.0;
   flat[5] = 11.0;
   flat[6] = 10.0;
   IctCheck("a flat top resolves to the newest bar of the run only",
            XSparkIctIsSwingHigh(flat, 2, 2) && !XSparkIctIsSwingHigh(flat, 3, 2));

   // Searching backwards finds the nearest qualifying swing, not the highest.
   IctCheck("the search finds the nearest older swing high",
            XSparkIctFindSwingHigh(highs, 0, 60, 2) == 3);
   IctCheck("the search refuses a lookback of zero",
            XSparkIctFindSwingHigh(highs, 0, 0, 2) == -1);
   IctCheck("the search returns -1 when no swing exists",
            XSparkIctFindSwingHigh(flat, 4, 60, 2) == -1);
   IctCheck("the low search finds the nearest older swing low",
            XSparkIctFindSwingLow(lows, 0, 60, 2) == 3);
}

// ---------------------------------------------------------------------------
// Liquidity sweep.
// ---------------------------------------------------------------------------

void RunIctSweepTests()
{
   // Pierced the level and closed back below it: the stops were taken and the
   // breakout failed. This is the event.
   IctCheck("a wick through a high that closes back below is a sweep",
            XSparkIctSweptHigh(15.5, 14.8, 15.0));

   // Closed BEYOND the level: this is a breakout, the opposite trade.
   IctCheck("a close beyond the high is a breakout, not a sweep",
            !XSparkIctSweptHigh(15.5, 15.2, 15.0));

   // Never reached the level: nothing was swept.
   IctCheck("a bar that never reached the high is not a sweep",
            !XSparkIctSweptHigh(14.9, 14.5, 15.0));

   // Exactly touching is not piercing; resting stops sit above the level.
   IctCheck("touching the level exactly is not a sweep",
            !XSparkIctSweptHigh(15.0, 14.8, 15.0));

   IctCheck("a wick under a low that closes back above is a sweep",
            XSparkIctSweptLow(9.5, 10.2, 10.0));
   IctCheck("a close beyond the low is a breakdown, not a sweep",
            !XSparkIctSweptLow(9.5, 9.8, 10.0));
   IctCheck("a bar that never reached the low is not a sweep",
            !XSparkIctSweptLow(10.1, 10.5, 10.0));

   IctCheck("an unusable level is refused by both sweeps",
            !XSparkIctSweptHigh(15.5, 14.8, 0.0) && !XSparkIctSweptLow(9.5, 10.2, -1.0));
}

// ---------------------------------------------------------------------------
// Fair value gap.
// ---------------------------------------------------------------------------

void RunIctFvgTests()
{
   double gap_low = 0.0, gap_high = 0.0;

   // Bullish: newest low (index 0) sits above oldest high (index 2). The market
   // jumped and left [12.0, 13.0] untraded.
   //   idx:       0      1      2
   double bh[];
   ArrayResize(bh, 3);
   bh[0] = 14.0;
   bh[1] = 13.5;
   bh[2] = 12.0;
   double bl[];
   ArrayResize(bl, 3);
   bl[0] = 13.0;
   bl[1] = 12.2;
   bl[2] = 11.0;

   IctCheck("a bullish imbalance is found and measured",
            XSparkIctBullishFvg(bh, bl, 0, 0.0, gap_low, gap_high) &&
            IctNear(gap_low, 12.0) && IctNear(gap_high, 13.0));

   // The same three bars are not a bearish gap.
   IctCheck("a bullish imbalance is not also a bearish one",
            !XSparkIctBearishFvg(bh, bl, 0, 0.0, gap_low, gap_high));

   // A gap of 1.00 must fail a floor of 1.50 and pass a floor of 0.50.
   IctCheck("an imbalance under the floor is refused",
            !XSparkIctBullishFvg(bh, bl, 0, 1.5, gap_low, gap_high));
   IctCheck("an imbalance over the floor is accepted",
            XSparkIctBullishFvg(bh, bl, 0, 0.5, gap_low, gap_high));

   // Bearish: newest high below oldest low, leaving [11.0, 12.0] untraded.
   double sh[];
   ArrayResize(sh, 3);
   sh[0] = 11.0;
   sh[1] = 12.5;
   sh[2] = 14.0;
   double sl[];
   ArrayResize(sl, 3);
   sl[0] = 10.0;
   sl[1] = 11.5;
   sl[2] = 12.0;
   IctCheck("a bearish imbalance is found and measured",
            XSparkIctBearishFvg(sh, sl, 0, 0.0, gap_low, gap_high) &&
            IctNear(gap_low, 11.0) && IctNear(gap_high, 12.0));

   // Overlapping bars: every trade in the middle bar's range happened, so
   // there is no imbalance in either direction.
   double oh[];
   ArrayResize(oh, 3);
   oh[0] = 13.0;
   oh[1] = 13.0;
   oh[2] = 13.0;
   double ol[];
   ArrayResize(ol, 3);
   ol[0] = 11.0;
   ol[1] = 11.0;
   ol[2] = 11.0;
   IctCheck("overlapping bars leave no imbalance",
            !XSparkIctBullishFvg(oh, ol, 0, 0.0, gap_low, gap_high) &&
            !XSparkIctBearishFvg(oh, ol, 0, 0.0, gap_low, gap_high));

   // Touching exactly is not a gap: the ranges met, nothing was skipped.
   double th[];
   ArrayResize(th, 3);
   th[0] = 14.0;
   th[1] = 13.5;
   th[2] = 13.0;
   double tl[];
   ArrayResize(tl, 3);
   tl[0] = 13.0;
   tl[1] = 12.2;
   tl[2] = 11.0;
   IctCheck("ranges that touch exactly leave no imbalance",
            !XSparkIctBullishFvg(th, tl, 0, 0.0, gap_low, gap_high));

   IctCheck("an imbalance without three bars of room is refused",
            !XSparkIctBullishFvg(bh, bl, 1, 0.0, gap_low, gap_high));
   IctCheck("a refused imbalance reports a zeroed gap",
            !XSparkIctBullishFvg(oh, ol, 0, 0.0, gap_low, gap_high) &&
            gap_low == 0.0 && gap_high == 0.0);
}

// ---------------------------------------------------------------------------
// Displacement.
// ---------------------------------------------------------------------------

void RunIctDisplacementTests()
{
   // Body of 1.0 against a typical candle of 1.0 clears a 0.65 floor.
   IctCheck("a down body over the floor is a bearish displacement",
            XSparkIctIsDisplacement(15.0, 14.0, 1.0, 0.65, XSPARK_SIGNAL_SELL));
   IctCheck("an up body over the floor is a bullish displacement",
            XSparkIctIsDisplacement(14.0, 15.0, 1.0, 0.65, XSPARK_SIGNAL_BUY));

   // Direction must match the body's sign.
   IctCheck("a down body is not a bullish displacement",
            !XSparkIctIsDisplacement(15.0, 14.0, 1.0, 0.65, XSPARK_SIGNAL_BUY));
   IctCheck("an up body is not a bearish displacement",
            !XSparkIctIsDisplacement(14.0, 15.0, 1.0, 0.65, XSPARK_SIGNAL_SELL));

   // Body of 0.5 against a typical candle of 1.0 misses the 0.65 floor: this is
   // the drift case that leaves no imbalance worth returning to.
   IctCheck("a body under the floor is not a displacement",
            !XSparkIctIsDisplacement(15.0, 14.5, 1.0, 0.65, XSPARK_SIGNAL_SELL));

   IctCheck("a doji is not a displacement in either direction",
            !XSparkIctIsDisplacement(15.0, 15.0, 1.0, 0.65, XSPARK_SIGNAL_SELL) &&
            !XSparkIctIsDisplacement(15.0, 15.0, 1.0, 0.65, XSPARK_SIGNAL_BUY));

   IctCheck("an unusable typical candle refuses the displacement",
            !XSparkIctIsDisplacement(15.0, 14.0, 0.0, 0.65, XSPARK_SIGNAL_SELL));
   IctCheck("no direction is not a displacement",
            !XSparkIctIsDisplacement(15.0, 14.0, 1.0, 0.65, XSPARK_SIGNAL_NONE));
}

// ---------------------------------------------------------------------------
// Premium and discount.
// ---------------------------------------------------------------------------

void RunIctRangeTests()
{
   double position = 0.0;

   IctCheck("the range midpoint reads as one half",
            XSparkIctRangePosition(15.0, 10.0, 20.0, position) && IctNear(position, 0.5));
   IctCheck("the range low reads as zero",
            XSparkIctRangePosition(10.0, 10.0, 20.0, position) && IctNear(position, 0.0));
   IctCheck("the range high reads as one",
            XSparkIctRangePosition(20.0, 10.0, 20.0, position) && IctNear(position, 1.0));
   IctCheck("a quarter up the range reads as 0.25",
            XSparkIctRangePosition(12.5, 10.0, 20.0, position) && IctNear(position, 0.25));
   IctCheck("an inverted range is refused",
            !XSparkIctRangePosition(15.0, 20.0, 10.0, position));
   IctCheck("a zero-width range is refused",
            !XSparkIctRangePosition(15.0, 15.0, 15.0, position));
}

// ---------------------------------------------------------------------------
// Kill zones.
// ---------------------------------------------------------------------------

void RunIctKillZoneTests()
{
   // London 07:00-10:00 UTC, New York 12:00-15:00 UTC.
   IctCheck("08:00 UTC is inside the London kill zone",
            XSparkIctInKillZone(480, XSPARK_ICT_KZ_LONDON));
   IctCheck("13:00 UTC is inside the New York kill zone",
            XSparkIctInKillZone(780, XSPARK_ICT_KZ_NEW_YORK));
   IctCheck("13:00 UTC is outside the London kill zone",
            !XSparkIctInKillZone(780, XSPARK_ICT_KZ_LONDON));
   IctCheck("both zones accept either window",
            XSparkIctInKillZone(480, XSPARK_ICT_KZ_LONDON_NY) &&
            XSparkIctInKillZone(780, XSPARK_ICT_KZ_LONDON_NY));

   // 11:00 sits between the two windows and belongs to neither.
   IctCheck("the gap between the windows is outside both",
            !XSparkIctInKillZone(660, XSPARK_ICT_KZ_LONDON_NY));

   // Start is inclusive, end is exclusive, so no minute is in two windows.
   IctCheck("the start minute is inside",
            XSparkIctInKillZone(420, XSPARK_ICT_KZ_LONDON));
   IctCheck("the end minute is outside",
            !XSparkIctInKillZone(600, XSPARK_ICT_KZ_LONDON));

   IctCheck("midnight is outside every window",
            !XSparkIctInKillZone(0, XSPARK_ICT_KZ_LONDON_NY));
   IctCheck("an out-of-range clock is refused",
            !XSparkIctInKillZone(-1, XSPARK_ICT_KZ_LONDON_NY) &&
            !XSparkIctInKillZone(1440, XSPARK_ICT_KZ_LONDON_NY));
}

// ---------------------------------------------------------------------------
// Configuration.
// ---------------------------------------------------------------------------

void RunIctConfigTests()
{
   XSparkIctConfig config;
   XSparkDefaultIctConfig(config);
   string reason = "";

   IctCheck("the shipped configuration is usable",
            XSparkIctConfigUsable(config, reason));

   config.swing_strength = 0;
   IctCheck("a zero swing strength is refused",
            !XSparkIctConfigUsable(config, reason) && reason != "");

   XSparkDefaultIctConfig(config);
   config.swing_lookback = 1;
   IctCheck("a lookback shorter than the swing is refused",
            !XSparkIctConfigUsable(config, reason));

   XSparkDefaultIctConfig(config);
   config.max_stop_atr = config.min_stop_atr;
   IctCheck("an inverted stop band is refused",
            !XSparkIctConfigUsable(config, reason));

   XSparkDefaultIctConfig(config);
   config.max_cost_share_pct = 100.0;
   IctCheck("a cost share of one hundred percent is refused",
            !XSparkIctConfigUsable(config, reason));

   XSparkDefaultIctConfig(config);
   config.target_r = 0.0;
   IctCheck("a zero target is refused",
            !XSparkIctConfigUsable(config, reason));

   IctCheck("the no-edge win rate at a 1:1 target is one half",
            IctNear(XSparkIctNoEdgeWinRate(1.0), 0.5));
   IctCheck("the no-edge win rate at a 2:1 target is one third",
            IctNear(XSparkIctNoEdgeWinRate(2.0), 1.0 / 3.0));
   IctCheck("an unusable target has no no-edge win rate",
            IctNear(XSparkIctNoEdgeWinRate(0.0), 0.0));
}

// ---------------------------------------------------------------------------
// The assembled sequence.
// ---------------------------------------------------------------------------
//
// One fixture in which every ICT condition holds, then mutated one condition at
// a time. A passing signal proves the whole chain; each failure names exactly
// the link that was cut.
//
// Series order, index 0 newest. The four bar roles the model depends on:
//
//   idx 10  swing high at 110.0          the stop pool
//   idx  7  wick to 112.0, close 108.0   THE SWEEP - ran 110.0 and failed
//   idx  5  swing low at 105.0           the structure the break must take
//   idx  1  106.5 -> 102.0               THE DISPLACEMENT - closes below 105.0
//   idx  0  high 103.0                   confirms the imbalance [103.0, 106.2]
//
// The imbalance spans bars 2, 1, 0: low[2] = 106.2 sits above high[0] = 103.0,
// so the displacement skipped that range entirely. Every bar is a legal candle
// (high >= max(open, close), low <= min(open, close)); an impossible bar would
// make the fixture prove nothing.

void IctBearishFixture(double &opens[], double &highs[], double &lows[], double &closes[])
{
   ArrayResize(opens, 14); ArrayResize(highs, 14); ArrayResize(lows, 14); ArrayResize(closes, 14);

   double o[14] = {102.0, 106.5, 107.5, 107.0, 106.0, 106.5, 108.0, 107.0, 107.5, 109.0, 105.5, 104.5, 103.5, 103.0};
   double h[14] = {103.0, 106.8, 108.0, 108.0, 107.5, 107.0, 108.2, 112.0, 108.5, 109.5, 110.0, 106.0, 105.0, 104.0};
   double l[14] = {100.5, 101.5, 106.2, 106.5, 106.0, 105.0, 106.0, 106.5, 106.5, 107.0, 105.0, 104.0, 103.0, 102.5};
   double c[14] = {101.0, 102.0, 106.8, 107.5, 107.0, 106.0, 106.5, 108.0, 107.0, 107.5, 109.0, 105.5, 104.5, 103.5};

   for(int i = 0; i < 14; i++)
   {
      opens[i] = o[i]; highs[i] = h[i]; lows[i] = l[i]; closes[i] = c[i];
   }
}

void IctTestConfig(XSparkIctConfig &config)
{
   XSparkDefaultIctConfig(config);
   config.swing_strength = 2;
   config.swing_lookback = 8;
   config.sweep_max_age_bars = 10;
   config.min_displacement_atr = 0.65;
   config.min_fvg_atr = 0.10;
   config.use_premium_discount = false;
   config.target_r = 2.0;
}

void RunIctEvaluateTests()
{
   XSparkIctConfig config;
   IctTestConfig(config);

   double opens[];
   double highs[];
   double lows[];
   double closes[];
   IctBearishFixture(opens, highs, lows, closes);

   const double atr = 3.0;   // the displacement's 4.5 body is 1.5 x ATR
   const int london = 480;   // 08:00 UTC

   XSparkIctSetup setup;
   XSparkIctVerdicts verdicts;

   const bool fired = XSparkIctEvaluate(opens, highs, lows, closes, 0, london, atr, config, setup, verdicts);

   IctCheck("the complete bearish sequence produces a sell",
            fired && setup.direction == XSPARK_SIGNAL_SELL);
   IctCheck("the sequence reports all four verdicts as met",
            verdicts.zone == "IN ZONE" && verdicts.sweep == "SWEPT HIGH" &&
            verdicts.structure == "SHIFTED" && verdicts.imbalance == "FVG");
   IctCheck("the sweep is found at the bar that ran the stops",
            setup.sweep_index == 7);
   IctCheck("the displacement is the bar before the one evaluated",
            setup.shift_index == 1);
   IctCheck("the swept level is the sweep bar's extreme, not the swing it ran",
            IctNear(setup.swept_level, 112.0));
   IctCheck("the imbalance is measured across the displacement",
            IctNear(setup.gap_low, 103.0) && IctNear(setup.gap_high, 106.2));
   IctCheck("the entry is the gap edge the market reaches first",
            IctNear(setup.entry_limit, 103.0));
   IctCheck("the stop sits beyond the swept extreme by the buffer",
            IctNear(setup.stop, 112.0 + config.stop_buffer_atr * atr));
   IctCheck("the target is the configured multiple of the stop distance",
            IctNear(setup.target, 103.0 - config.target_r * (112.6 - 103.0)));
   IctCheck("the sell's stop is above its entry and its target below",
            setup.stop > setup.entry_limit && setup.target < setup.entry_limit);

   // --- now cut one link at a time ---

   IctCheck("the same sequence outside the kill zone is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, 0, atr, config, setup, verdicts) &&
            verdicts.zone == "OUTSIDE ZONE");

   // Displacement body shrunk to 1.0 = 0.33 x ATR, under the 0.65 floor.
   double flat_open[];
   double flat_high[];
   double flat_low[];
   double flat_close[];
   IctBearishFixture(flat_open, flat_high, flat_low, flat_close);
   flat_close[1] = 105.5;
   IctCheck("a shift bar without displacement is refused",
            !XSparkIctEvaluate(flat_open, flat_high, flat_low, flat_close, 0, london, atr, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // The sweep bar never reaches the 110.0 stop pool.
   double nosweep_open[];
   double nosweep_high[];
   double nosweep_low[];
   double nosweep_close[];
   IctBearishFixture(nosweep_open, nosweep_high, nosweep_low, nosweep_close);
   nosweep_high[7] = 109.0;
   IctCheck("a sequence whose stop pool was never run is refused",
            !XSparkIctEvaluate(nosweep_open, nosweep_high, nosweep_low, nosweep_close, 0, london, atr, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // The sweep bar closes ABOVE the pool: a breakout, which is the other trade.
   double breakout_open[];
   double breakout_high[];
   double breakout_low[];
   double breakout_close[];
   IctBearishFixture(breakout_open, breakout_high, breakout_low, breakout_close);
   breakout_close[7] = 111.0;
   IctCheck("a breakout through the stop pool is not a sweep",
            !XSparkIctEvaluate(breakout_open, breakout_high, breakout_low, breakout_close, 0, london, atr, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // The confirming bar's high overlaps bar 2, so nothing was skipped.
   double nogap_open[];
   double nogap_high[];
   double nogap_low[];
   double nogap_close[];
   IctBearishFixture(nogap_open, nogap_high, nogap_low, nogap_close);
   nogap_high[0] = 106.5;
   IctCheck("a displacement that left no imbalance is refused",
            !XSparkIctEvaluate(nogap_open, nogap_high, nogap_low, nogap_close, 0, london, atr, config, setup, verdicts) &&
            verdicts.imbalance == "NO FVG");

   // The displacement closes 102.0, which does not break the 105.0 swing low,
   // so the body is impulsive but structure never shifted.
   double noshift_open[];
   double noshift_high[];
   double noshift_low[];
   double noshift_close[];
   IctBearishFixture(noshift_open, noshift_high, noshift_low, noshift_close);
   noshift_low[5] = 100.0;   // move the swing low below the displacement's close
   noshift_close[5] = 101.0;
   noshift_open[5] = 101.5;
   IctCheck("a displacement that did not break structure is refused",
            !XSparkIctEvaluate(noshift_open, noshift_high, noshift_low, noshift_close, 0, london, atr, config, setup, verdicts) &&
            verdicts.structure == "NOT SHIFTED");

   // PINS THE PREMIUM/DISCOUNT FINDING. The entry at 103.0 sits BELOW the range
   // the sweep and the break defined (105.0 to 112.0), because a displacement
   // strong enough to break structure always leaves its imbalance beyond the
   // level it broke. Switching this filter on therefore refuses the very setup
   // the model just produced - which is why it ships off.
   XSparkIctConfig pd;
   IctTestConfig(pd);
   pd.use_premium_discount = true;
   IctCheck("the premium filter refuses the model's own entry, so it ships off",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, atr, pd, setup, verdicts) &&
            verdicts.location == "WRONG HALF");
   IctCheck("the shipped configuration leaves the premium filter off",
            !XSPARK_ICT_USE_PREMIUM_DISCOUNT);

   // Guards.
   IctCheck("an unusable typical candle is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, 0.0, config, setup, verdicts));
   IctCheck("an index without history behind it is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 12, london, atr, config, setup, verdicts));
   IctCheck("a negative index is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, -1, london, atr, config, setup, verdicts));

   XSparkIctConfig broken;
   IctTestConfig(broken);
   broken.swing_strength = 0;
   IctCheck("a broken configuration is refused before any bar is read",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, atr, broken, setup, verdicts) &&
            setup.reason != "");

   IctCheck("a refusal leaves no half-built setup behind",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, 0, atr, config, setup, verdicts) &&
            setup.direction == XSPARK_SIGNAL_NONE && setup.entry_limit == 0.0 && setup.stop == 0.0);

   // The stop runs 9.6 from the entry, which is 3.2 typical candles; a ceiling
   // of 0.5 refuses it.
   XSparkIctConfig tight;
   IctTestConfig(tight);
   tight.max_stop_atr = 0.5;
   IctCheck("a stop wider than the ceiling is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, atr, tight, setup, verdicts) &&
            setup.direction == XSPARK_SIGNAL_NONE);
}

// The bullish mirror, so the two directions cannot drift apart. Built by
// reflecting the bearish fixture about 210.0: every high becomes a low, and the
// sequence runs a low, shifts up, and leaves a bullish imbalance.
void RunIctBullishMirrorTests()
{
   XSparkIctConfig config;
   IctTestConfig(config);

   double bo[];
   double bh[];
   double bl[];
   double bc[];
   IctBearishFixture(bo, bh, bl, bc);

   double opens[];
   double highs[];
   double lows[];
   double closes[];
   ArrayResize(opens, 14); ArrayResize(highs, 14); ArrayResize(lows, 14); ArrayResize(closes, 14);

   for(int i = 0; i < 14; i++)
   {
      opens[i]  = 210.0 - bo[i];
      highs[i]  = 210.0 - bl[i];   // reflecting swaps the roles of high and low
      lows[i]   = 210.0 - bh[i];
      closes[i] = 210.0 - bc[i];
   }

   XSparkIctSetup setup;
   XSparkIctVerdicts verdicts;
   const bool fired = XSparkIctEvaluate(opens, highs, lows, closes, 0, 480, 3.0, config, setup, verdicts);

   IctCheck("the mirrored sequence produces a buy",
            fired && setup.direction == XSPARK_SIGNAL_BUY);
   IctCheck("the mirrored verdicts match the bearish ones",
            verdicts.sweep == "SWEPT LOW" && verdicts.structure == "SHIFTED" &&
            verdicts.imbalance == "FVG");
   IctCheck("the mirrored sweep is the same bar",
            setup.sweep_index == 7 && setup.shift_index == 1);
   IctCheck("the mirrored swept level reflects the bearish one",
            IctNear(setup.swept_level, 210.0 - 112.0));
   IctCheck("the mirrored entry reflects the bearish one",
            IctNear(setup.entry_limit, 210.0 - 103.0));
   IctCheck("the buy's stop is below its entry and its target above",
            setup.stop < setup.entry_limit && setup.target > setup.entry_limit);
   IctCheck("the mirrored stop distance equals the bearish one",
            IctNear(setup.entry_limit - setup.stop, 112.6 - 103.0));
}

void RunIctTests()
{
   RunIctSwingTests();
   RunIctSweepTests();
   RunIctFvgTests();
   RunIctDisplacementTests();
   RunIctRangeTests();
   RunIctKillZoneTests();
   RunIctConfigTests();
   RunIctEvaluateTests();
   RunIctBullishMirrorTests();

   Print("ICT RESULT passed=", g_ict_passed, " failed=", g_ict_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunIctTests(); }
#endif
