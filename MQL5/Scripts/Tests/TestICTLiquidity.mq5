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
// Displacement, and the absence of any threshold on it.
// ---------------------------------------------------------------------------

void RunIctDisplacementTests()
{
   // All that is read from the bar is which way its body points. There is no
   // magnitude test, because in this method the evidence a leg displaced is the
   // imbalance it left, not its size against an indicator.
   IctCheck("a down body points at a raided high",
            XSparkIctBodyDirection(15.0, 14.0) == XSPARK_SIGNAL_SELL);
   IctCheck("an up body points at a raided low",
            XSparkIctBodyDirection(14.0, 15.0) == XSPARK_SIGNAL_BUY);

   // THE CORRECTION THIS PINS. A tiny body is still a direction: an earlier
   // draft refused it for being under 0.65 x ATR, which is a test this method
   // does not contain. If that body leaves an imbalance and breaks structure,
   // it displaced.
   IctCheck("a small body is still a direction, with no size test applied",
            XSparkIctBodyDirection(15.0, 14.99) == XSPARK_SIGNAL_SELL &&
            XSparkIctBodyDirection(14.99, 15.0) == XSPARK_SIGNAL_BUY);

   IctCheck("a bar that closed where it opened points nowhere",
            XSparkIctBodyDirection(15.0, 15.0) == XSPARK_SIGNAL_NONE);
   IctCheck("an unusable bar points nowhere",
            XSparkIctBodyDirection(0.0 / 1.0, 15.0) == XSPARK_SIGNAL_BUY);
}

// ---------------------------------------------------------------------------
// Consequent encroachment.
// ---------------------------------------------------------------------------

void RunIctEncroachmentTests()
{
   double ce = 0.0;

   // The method's entry reference is the gap's 50% midpoint, not either edge.
   IctCheck("the encroachment is the midpoint of the gap",
            XSparkIctConsequentEncroachment(103.0, 106.0, ce) && IctNear(ce, 104.5));
   IctCheck("a one-sided gap has no midpoint",
            !XSparkIctConsequentEncroachment(106.0, 103.0, ce) && ce == 0.0);
   IctCheck("a zero-width gap has no midpoint",
            !XSparkIctConsequentEncroachment(103.0, 103.0, ce));
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
   config.max_target_r = config.min_target_r;
   IctCheck("an inverted reward band on the draw is refused",
            !XSparkIctConfigUsable(config, reason));

   XSparkDefaultIctConfig(config);
   config.stop_buffer_points = -1.0;
   IctCheck("a negative stop buffer is refused",
            !XSparkIctConfigUsable(config, reason));

   XSparkDefaultIctConfig(config);
   config.min_gap_price = -0.1;
   IctCheck("a negative minimum imbalance is refused",
            !XSparkIctConfigUsable(config, reason));

   // The shipped swing definition is the method's own three-candle formation.
   IctCheck("the shipped swing is a three-candle formation",
            XSPARK_ICT_SWING_STRENGTH == 1);
   IctCheck("the shipped configuration keeps the premium filter on",
            XSPARK_ICT_USE_PREMIUM_DISCOUNT);

   XSparkDefaultIctConfig(config);
   config.max_cost_share_pct = 100.0;
   IctCheck("a cost share of one hundred percent is refused",
            !XSparkIctConfigUsable(config, reason));

   IctCheck("the break-even win rate at a 1:1 target is one half",
            IctNear(XSparkIctBreakEvenWinRate(1.0), 0.5));
   IctCheck("the break-even win rate at a 2:1 target is one third",
            IctNear(XSparkIctBreakEvenWinRate(2.0), 1.0 / 3.0));
   IctCheck("an unusable target has no break-even win rate",
            IctNear(XSparkIctBreakEvenWinRate(0.0), 0.0));

   // Costs only ever lower it, and by exactly the cost share.
   IctCheck("the no-edge win rate is the break-even rate less the cost share",
            IctNear(XSparkIctNoEdgeWinRate(2.0, 6.0), 0.94 / 3.0));
   IctCheck("a costless account's no-edge rate equals break-even",
            IctNear(XSparkIctNoEdgeWinRate(2.0, 0.0), 1.0 / 3.0));
   IctCheck("the no-edge rate is always at or below break-even",
            XSparkIctNoEdgeWinRate(2.0, 6.0) < XSparkIctBreakEvenWinRate(2.0));
   IctCheck("an unusable cost share has no no-edge win rate",
            IctNear(XSparkIctNoEdgeWinRate(2.0, 100.0), 0.0) &&
            IctNear(XSparkIctNoEdgeWinRate(2.0, -1.0), 0.0));

   // No target-style test: the target is not a style. It is wherever the draw
   // on liquidity sits, and the reward ratio is an output of that. An earlier
   // draft let an operator pick 2R or 3R, which this method does not do.
}

// ---------------------------------------------------------------------------
// The assembled sequence.
// ---------------------------------------------------------------------------
//
// One fixture in which every condition of the 2022 model holds, then mutated
// one condition at a time. A passing signal proves the whole chain; each
// failure names exactly the link that was cut.
//
// Series order, index 0 newest. Reading it as a chart means reading RIGHT to
// left. The roles:
//
//   idx 13  swing low at 98.5           the draw on liquidity, the trade's target
//   idx 10  swing high at 110.0         the stop pool
//   idx  8  wick 112.0, close 108.6     THE RAID - ran 110.0 and failed
//   idx  6  106.4 -> 103.4              displacement early in the leg
//   idx  6  gap [106.6, 108.0]          the imbalance it left, in PREMIUM
//   idx  5  swing low at 102.0          the structure the break must take
//   idx  1  101.0 -> 100.0              THE BREAK - closes below 102.0
//   idx  0                              confirms
//
// The entry is the gap's consequent encroachment, 107.3, which sits at 69% of
// the dealing range (98.5 leg low to 112.0 raided high) and so is in premium.
//
// THE POINT OF THE SHAPE. The imbalance that gets entered is at bar 6, not at
// bars 0-2. An earlier draft of this model looked only at the newest three
// bars, which sit at the BOTTOM of a down-leg and are therefore always in
// discount - so its premium filter refused every sell it could generate, and
// the draft wrongly concluded the filter did not apply to this method. This
// fixture only passes because the search covers the whole leg.
//
// Every bar is a legal candle (high >= max(open, close), low <= min(open,
// close)); an impossible bar would make the fixture prove nothing.

void IctBearishFixture(double &opens[], double &highs[], double &lows[], double &closes[])
{
   ArrayResize(opens, 16); ArrayResize(highs, 16); ArrayResize(lows, 16); ArrayResize(closes, 16);

   double o[16] = { 98.0, 101.0, 103.4, 103.8, 104.0, 103.4, 106.4, 108.6, 108.2, 109.6, 106.8, 104.8, 102.8, 100.0,  99.2, 100.0};
   double h[16] = { 98.4, 101.2, 103.6, 104.0, 104.6, 104.4, 106.6, 108.8, 112.0, 109.8, 110.0, 107.0, 105.0, 100.4, 100.2, 100.6};
   double l[16] = { 96.8,  97.5, 103.0, 102.8, 102.5, 102.0, 103.0, 106.0, 108.0, 107.8, 106.6, 104.6, 102.6,  98.5,  99.0,  99.4};
   double c[16] = { 97.2, 100.0, 103.2, 103.4, 102.8, 104.0, 103.4, 106.4, 108.6, 108.2, 109.6, 106.8, 104.8, 100.2,  99.4, 100.4};

   for(int i = 0; i < 16; i++)
   {
      opens[i] = o[i]; highs[i] = h[i]; lows[i] = l[i]; closes[i] = c[i];
   }
}

void IctTestConfig(XSparkIctConfig &config)
{
   XSparkDefaultIctConfig(config);
   config.swing_strength = 1;
   config.swing_lookback = 30;
   config.sweep_max_age_bars = 12;
   config.min_gap_price = 0.05;
   config.stop_buffer_points = 20.0;
   config.use_premium_discount = true;
   config.min_target_r = 1.5;
   config.max_target_r = 20.0;
}

// Every bar of the fixture must be a candle the market could actually print.
void RunIctFixtureSanityTests()
{
   double opens[];
   double highs[];
   double lows[];
   double closes[];
   IctBearishFixture(opens, highs, lows, closes);

   bool legal = true;
   for(int i = 0; i < ArraySize(opens); i++)
   {
      const double body_high = MathMax(opens[i], closes[i]);
      const double body_low = MathMin(opens[i], closes[i]);
      if(highs[i] < body_high || lows[i] > body_low)
         legal = false;
   }
   IctCheck("every fixture bar is a candle the market could print", legal);
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

   const int london = 480;      // 08:00 UTC
   const double point = 0.01;

   XSparkIctSetup setup;
   XSparkIctVerdicts verdicts;

   const bool fired = XSparkIctEvaluate(opens, highs, lows, closes, 0, london, point, config, setup, verdicts);

   IctCheck("the complete 2022-model sequence produces a sell",
            fired && setup.direction == XSPARK_SIGNAL_SELL);
   IctCheck("every verdict in the chain is met",
            verdicts.zone == "IN ZONE" && verdicts.sweep == "SWEPT HIGH" &&
            verdicts.structure == "SHIFTED" && verdicts.imbalance == "FVG" &&
            verdicts.location == "PREMIUM" && verdicts.liquidity == "DRAW FOUND");
   IctCheck("the raid is found at the bar that ran the stops",
            setup.sweep_index == 8 && IctNear(setup.swept_level, 112.0));
   IctCheck("the break of structure is the bar before the one evaluated",
            setup.shift_index == 1);

   // THE CORRECTION. The gap entered is at bar 6, in the middle of the leg -
   // not at bar 0, where the newest three bars sit.
   IctCheck("the imbalance entered comes from inside the leg, not its end",
            setup.gap_index == 6 &&
            IctNear(setup.gap_low, 106.6) && IctNear(setup.gap_high, 108.0));
   IctCheck("the entry is the imbalance's consequent encroachment, not an edge",
            IctNear(setup.entry_limit, 107.3));
   IctCheck("the entry sits in premium of the dealing range",
            setup.range_position > 0.5 && setup.range_position < 1.0);

   IctCheck("the stop sits beyond the raided extreme by the point buffer",
            IctNear(setup.stop, 112.0 + 20.0 * point));
   IctCheck("the target is the draw on liquidity, an older swing low",
            IctNear(setup.target, 98.5));
   IctCheck("the reward ratio is derived from that draw, not chosen",
            IctNear(setup.target_r, (107.3 - 98.5) / (112.2 - 107.3)));
   IctCheck("the sell's stop is above its entry and its target below",
            setup.stop > setup.entry_limit && setup.target < setup.entry_limit);

   // --- now cut one link at a time ---

   IctCheck("the same sequence outside the kill zone is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, 0, point, config, setup, verdicts) &&
            verdicts.zone == "OUTSIDE ZONE");

   // The raid bar never reaches the 110.0 pool.
   double a_o[];
   double a_h[];
   double a_l[];
   double a_c[];
   IctBearishFixture(a_o, a_h, a_l, a_c);
   a_h[8] = 109.0;
   IctCheck("a sequence whose stop pool was never run is refused",
            !XSparkIctEvaluate(a_o, a_h, a_l, a_c, 0, london, point, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // The raid bar closes ABOVE the pool: a breakout, which is the other trade.
   double b_o[];
   double b_h[];
   double b_l[];
   double b_c[];
   IctBearishFixture(b_o, b_h, b_l, b_c);
   b_c[8] = 111.0;
   IctCheck("a breakout through the stop pool is not a raid",
            !XSparkIctEvaluate(b_o, b_h, b_l, b_c, 0, london, point, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // A bar that closed where it opened points nowhere.
   double d_o[];
   double d_h[];
   double d_l[];
   double d_c[];
   IctBearishFixture(d_o, d_h, d_l, d_c);
   d_c[1] = d_o[1];
   IctCheck("a bar that closed where it opened cannot be a displacement",
            !XSparkIctEvaluate(d_o, d_h, d_l, d_c, 0, london, point, config, setup, verdicts) &&
            verdicts.sweep == "NO SWEEP");

   // A bearish body that does NOT close through the opposing swing low at
   // 102.0: impulsive-looking, but structure never shifted.
   double e_o[];
   double e_h[];
   double e_l[];
   double e_c[];
   IctBearishFixture(e_o, e_h, e_l, e_c);
   e_o[1] = 104.0; e_h[1] = 104.2; e_c[1] = 103.0;
   IctCheck("a down bar that did not break structure is refused",
            !XSparkIctEvaluate(e_o, e_h, e_l, e_c, 0, london, point, config, setup, verdicts) &&
            verdicts.structure == "NOT SHIFTED");

   // Flatten every high in the leg so no imbalance survives anywhere in it.
   double f_o[];
   double f_h[];
   double f_l[];
   double f_c[];
   IctBearishFixture(f_o, f_h, f_l, f_c);
   f_h[0] = 103.2; f_h[1] = 103.2; f_h[2] = 104.0; f_h[3] = 104.8;
   f_h[4] = 106.2; f_h[5] = 106.6; f_h[6] = 108.2; f_h[7] = 110.0;
   IctCheck("a leg that left no imbalance anywhere is refused",
            !XSparkIctEvaluate(f_o, f_h, f_l, f_c, 0, london, point, config, setup, verdicts) &&
            verdicts.imbalance == "NO FVG");

   // Raising the old swing low creates a NEARER pool at 102.6, which is under
   // the reward floor. The refusal names the draw, not the setup.
   double g_o[];
   double g_h[];
   double g_l[];
   double g_c[];
   IctBearishFixture(g_o, g_h, g_l, g_c);
   g_l[13] = 108.0; g_o[13] = 108.4; g_c[13] = 108.6; g_h[13] = 108.8;
   IctCheck("a draw on liquidity too close to pay for the stop is refused",
            !XSparkIctEvaluate(g_o, g_h, g_l, g_c, 0, london, point, config, setup, verdicts) &&
            verdicts.liquidity == "DRAW TOO CLOSE");

   // Guards.
   IctCheck("an unusable point size is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, 0.0, config, setup, verdicts));
   IctCheck("an index without history behind it is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, 14, london, point, config, setup, verdicts));
   IctCheck("a negative index is refused",
            !XSparkIctEvaluate(opens, highs, lows, closes, -1, london, point, config, setup, verdicts));

   XSparkIctConfig broken;
   IctTestConfig(broken);
   broken.swing_strength = 0;
   IctCheck("a broken configuration is refused before any bar is read",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, london, point, broken, setup, verdicts) &&
            setup.reason != "");

   IctCheck("a refusal leaves no half-built setup behind",
            !XSparkIctEvaluate(opens, highs, lows, closes, 0, 0, point, config, setup, verdicts) &&
            setup.direction == XSPARK_SIGNAL_NONE && setup.entry_limit == 0.0 &&
            setup.stop == 0.0 && setup.target == 0.0 && setup.target_r == 0.0);
}

// The bullish mirror, so the two directions cannot drift apart. Built by
// reflecting the bearish fixture about 210.0: every high becomes a low, the
// raid runs a low instead of a high, and the draw on liquidity is a swing high.
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
   ArrayResize(opens, 16); ArrayResize(highs, 16); ArrayResize(lows, 16); ArrayResize(closes, 16);

   for(int i = 0; i < 16; i++)
   {
      opens[i]  = 210.0 - bo[i];
      highs[i]  = 210.0 - bl[i];   // reflecting swaps the roles of high and low
      lows[i]   = 210.0 - bh[i];
      closes[i] = 210.0 - bc[i];
   }

   XSparkIctSetup setup;
   XSparkIctVerdicts verdicts;
   const bool fired = XSparkIctEvaluate(opens, highs, lows, closes, 0, 480, 0.01, config, setup, verdicts);

   IctCheck("the mirrored sequence produces a buy",
            fired && setup.direction == XSPARK_SIGNAL_BUY);
   IctCheck("the mirrored verdicts match the bearish ones",
            verdicts.sweep == "SWEPT LOW" && verdicts.structure == "SHIFTED" &&
            verdicts.imbalance == "FVG" && verdicts.location == "DISCOUNT" &&
            verdicts.liquidity == "DRAW FOUND");
   IctCheck("the mirrored raid and imbalance are the same bars",
            setup.sweep_index == 8 && setup.shift_index == 1 && setup.gap_index == 6);
   IctCheck("the mirrored entry reflects the bearish one",
            IctNear(setup.entry_limit, 210.0 - 107.3));
   IctCheck("the mirrored draw on liquidity reflects the bearish one",
            IctNear(setup.target, 210.0 - 98.5));
   IctCheck("the buy's stop is below its entry and its target above",
            setup.stop < setup.entry_limit && setup.target > setup.entry_limit);
   IctCheck("the mirrored reward ratio equals the bearish one",
            IctNear(setup.target_r, (107.3 - 98.5) / (112.2 - 107.3)));
}

void RunIctCostAndStopTests()
{
   double cost = 0.0, commission_price = 0.0;
   string reason = "";

   IctCheck("a spread-only account's round-trip cost is the spread",
            XSparkIctRoundTripCost(0.30, 0.0, 0.01, 1.0, cost, commission_price, reason) &&
            IctNear(cost, 0.30) && IctNear(commission_price, 0.0));
   IctCheck("commission is converted to a price distance and added",
            XSparkIctRoundTripCost(0.30, 7.0, 0.01, 1.0, cost, commission_price, reason) &&
            IctNear(commission_price, 0.07) && IctNear(cost, 0.37));
   IctCheck("a negative spread is refused",
            !XSparkIctRoundTripCost(-0.1, 0.0, 0.01, 1.0, cost, commission_price, reason));
   IctCheck("a negative commission is refused",
            !XSparkIctRoundTripCost(0.30, -1.0, 0.01, 1.0, cost, commission_price, reason));
   IctCheck("an unusable tick size is refused",
            !XSparkIctRoundTripCost(0.30, 7.0, 0.0, 1.0, cost, commission_price, reason));

   XSparkIctConfig config;
   IctTestConfig(config);
   config.min_stop_atr = 0.50;
   config.max_stop_atr = 3.50;
   config.max_cost_share_pct = 6.0;

   double stop = 0.0, distance = 0.0;
   const double atr = 2.0;

   // The model's stop is 3.0 away and clears both floors, so it is used as is.
   IctCheck("a model stop inside the bounds is used unchanged",
            XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 103.0, atr, 0.05, config, stop, distance, reason) &&
            IctNear(distance, 3.0) && IctNear(stop, 103.0));
   IctCheck("the buy side mirrors the sell side",
            XSparkIctStop(XSPARK_SIGNAL_BUY, 100.0, 97.0, atr, 0.05, config, stop, distance, reason) &&
            IctNear(distance, 3.0) && IctNear(stop, 97.0));

   // Model stop 0.4 away, under the 0.50 x 2.0 = 1.0 floor: widened to 1.0.
   IctCheck("a stop under the typical-candle floor is widened, never tightened",
            XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 100.4, atr, 0.0, config, stop, distance, reason) &&
            IctNear(distance, 1.0) && IctNear(stop, 101.0));

   // Cost floor: 0.30 round trip at a 6% share needs a stop of at least 5.0.
   IctCheck("the cost floor widens a stop that would pay too much spread",
            XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 103.0, atr, 0.30, config, stop, distance, reason) &&
            IctNear(distance, 5.0) && IctNear(stop, 105.0));

   // Cost of 0.50 needs 8.333, over the 3.50 x 2.0 = 7.0 ceiling: refused, and
   // the refusal must name the cost rather than the distance.
   IctCheck("a cost floor over the ceiling is refused as a COST problem",
            !XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 103.0, atr, 0.50, config, stop, distance, reason) &&
            StringFind(reason, "COST:") == 0);

   // A swept level 10.0 away is over the ceiling with no cost pressure, and
   // that refusal must NOT blame the cost.
   IctCheck("a swept level past the ceiling is refused as a distance problem",
            !XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 110.0, atr, 0.0, config, stop, distance, reason) &&
            StringFind(reason, "COST:") != 0 && reason != "");

   // The market has already traded past where the stop would go.
   IctCheck("a market past the model's stop is refused",
            !XSparkIctStop(XSPARK_SIGNAL_SELL, 104.0, 103.0, atr, 0.0, config, stop, distance, reason));

   IctCheck("an unusable typical candle is refused",
            !XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 103.0, 0.0, 0.0, config, stop, distance, reason));
   IctCheck("no direction is refused",
            !XSparkIctStop(XSPARK_SIGNAL_NONE, 100.0, 103.0, atr, 0.0, config, stop, distance, reason));
   IctCheck("a refused stop reports nothing usable",
            !XSparkIctStop(XSPARK_SIGNAL_SELL, 100.0, 0.0, atr, 0.0, config, stop, distance, reason) &&
            stop == 0.0 && distance == 0.0);
}

void RunIctHoldAndFlattenTests()
{
   // 24 bars of M5 is 7200 seconds, inside the 21600 ceiling.
   IctCheck("the hold time is the bar count on a low chart period",
            XSparkIctMaxHoldSeconds(300) == 24 * 300);
   // 24 bars of H1 would be 86400, so the wall-clock ceiling binds.
   IctCheck("the wall-clock ceiling binds on a high chart period",
            XSparkIctMaxHoldSeconds(3600) == XSPARK_ICT_MAX_HOLD_SECONDS);
   IctCheck("an unusable chart period has no hold time",
            XSparkIctMaxHoldSeconds(0) == 0 && XSparkIctMaxHoldSeconds(-1) == 0);

   datetime flatten = 0;
   string reason = "";

   // 08:00 UTC on day 34: London ends at 10:00, two hours away.
   const datetime in_london = (datetime)(34 * 86400 + 8 * 3600);
   IctCheck("a position in the London window flattens at its end",
            XSparkIctKillZoneEnd(in_london, 0, XSPARK_ICT_KZ_LONDON_NY, flatten, reason) &&
            flatten == (datetime)(34 * 86400 + 10 * 3600));

   // 13:00 UTC: New York ends at 15:00.
   const datetime in_newyork = (datetime)(34 * 86400 + 13 * 3600);
   IctCheck("a position in the New York window flattens at its end",
            XSparkIctKillZoneEnd(in_newyork, 0, XSPARK_ICT_KZ_LONDON_NY, flatten, reason) &&
            flatten == (datetime)(34 * 86400 + 15 * 3600));

   // 11:00 UTC sits between the windows: nothing to flatten at.
   const datetime between = (datetime)(34 * 86400 + 11 * 3600);
   IctCheck("outside every window there is no flatten time",
            !XSparkIctKillZoneEnd(between, 0, XSPARK_ICT_KZ_LONDON_NY, flatten, reason) &&
            flatten == 0 && reason != "");

   // A broker three hours ahead of UTC: its 11:00 is 08:00 UTC, still London.
   const datetime broker_ahead = (datetime)(34 * 86400 + 11 * 3600);
   IctCheck("the clock offset moves the window with the broker",
            XSparkIctKillZoneEnd(broker_ahead, 3, XSPARK_ICT_KZ_LONDON_NY, flatten, reason) &&
            flatten == (datetime)(34 * 86400 + 13 * 3600));

   // Selecting one zone must not flatten inside the other.
   IctCheck("a zone selection that excludes the window reports no end",
            !XSparkIctKillZoneEnd(in_newyork, 0, XSPARK_ICT_KZ_LONDON, flatten, reason));
}

void RunIctWilsonTests()
{
   double lower = 0.0;

   // A small sample cannot clear even a low bar: 20 of 40 is a coin flip.
   IctCheck("a small even sample's lower bound sits well under one half",
            XSparkIctWilsonLowerBound(20, 40, lower) && lower < 0.40 && lower > 0.30);

   // The same proportion with ten times the sample is much tighter.
   IctCheck("a large sample tightens the bound toward the proportion",
            XSparkIctWilsonLowerBound(200, 400, lower) && lower > 0.45 && lower < 0.50);

   // The bound is always below the proportion it came from.
   double small = 0.0, large = 0.0;
   XSparkIctWilsonLowerBound(20, 40, small);
   XSparkIctWilsonLowerBound(200, 400, large);
   IctCheck("more evidence at the same proportion raises the bound",
            large > small);

   IctCheck("a perfect record still reports a bound below one",
            XSparkIctWilsonLowerBound(30, 30, lower) && lower < 1.0 && lower > 0.85);
   IctCheck("no wins reports a bound of zero",
            XSparkIctWilsonLowerBound(0, 30, lower) && IctNear(lower, 0.0));

   IctCheck("an empty sample is refused",
            !XSparkIctWilsonLowerBound(0, 0, lower) && lower == 0.0);
   IctCheck("more wins than outcomes is refused",
            !XSparkIctWilsonLowerBound(31, 30, lower));
   IctCheck("a negative win count is refused",
            !XSparkIctWilsonLowerBound(-1, 30, lower));

   // The verdict this drives: at a 2R target break-even is 33.3%, so a 40%
   // win rate over 30 trades must NOT read as an edge, and the same rate over
   // 400 must.
   const double break_even = XSparkIctBreakEvenWinRate(2.0);
   XSparkIctWilsonLowerBound(12, 30, lower);
   IctCheck("40% over thirty trades does not clear the 2R break-even",
            lower <= break_even);
   XSparkIctWilsonLowerBound(160, 400, lower);
   IctCheck("40% over four hundred trades does clear it",
            lower > break_even);
}

// The strategy object end to end: the same fixture, loaded into the shared
// indicator cache, through Evaluate and into an XSparkSignal. This is the only
// test that proves the class reads the cache in the order the model expects -
// a reversed copy would still pass every pure-function test above.
#ifdef XSPARK_PORTABLE_TEST
void IctCacheBar(XSparkCandle &bar, const double open, const double high,
                 const double low, const double close)
{
   // 34 whole days plus 28800 seconds, so the clock reads 08:00 UTC - inside
   // the London kill zone. A timestamp chosen for tidiness rather than for the
   // window is the quiet way to make every one of these tests vacuous.
   bar.time = (datetime)(34 * 86400 + 28800);
   bar.open = open; bar.high = high; bar.low = low; bar.close = close;
   bar.tick_volume = 100;
}

void RunIctStrategyTests()
{
   double opens[];
   double highs[];
   double lows[];
   double closes[];
   IctBearishFixture(opens, highs, lows, closes);

   CXSparkIndicatorCache cache;
   cache.base.resize(XSPARK_SCOREBOT_CLOSED_BASE_BARS);
   for(int i = 0; i < XSPARK_SCOREBOT_CLOSED_BASE_BARS; i++)
   {
      // Past the fixture, repeat its oldest bar. The sequence never reads that
      // far, and an exactly flat tail cannot create a swing, because a swing
      // needs a STRICT inequality on its newer side.
      const int f = i < 16 ? i : 15;
      IctCacheBar(cache.base[i], opens[f], highs[f], lows[f], closes[f]);
   }

   CXSparkIctLiquidity strategy;
   XSparkIctConfig config;
   IctTestConfig(config);
   strategy.Configure(config);

   XSparkSignal signal;
   XSparkScoreBotReport report;

   IctCheck("an uninitialized ICT strategy never signals",
            !strategy.Evaluate(cache, signal, report) &&
            report.status == "SCANNING" && report.joint_verdict == "BLOCKED");

   IctCheck("the strategy refuses a symbol it was not given",
            !strategy.Initialize(""));

   IctCheck("the strategy initializes on the test configuration",
            strategy.Initialize("TEST"));

   // A configuration whose deepest read runs past the cache is refused at
   // initialization rather than silently reading a truncated rule.
   CXSparkIctLiquidity deep;
   XSparkIctConfig too_deep;
   IctTestConfig(too_deep);
   too_deep.swing_lookback = XSPARK_SCOREBOT_CLOSED_BASE_BARS;
   deep.Configure(too_deep);
   IctCheck("a configuration that would read past the cache is refused",
            !deep.Initialize("TEST"));

   strategy.SetClockOffset(0);
   strategy.SetMinimumGap(0.05);

   IctCheck("the strategy produces the sell the model found",
            strategy.Evaluate(cache, signal, report) &&
            signal.direction == XSPARK_SIGNAL_SELL &&
            report.status == "SIGNAL" && report.joint_verdict == "PASS");
   IctCheck("the signal carries the consequent encroachment as its entry limit",
            IctNear(signal.entry_limit, 107.3));
   IctCheck("the signal carries the stop beyond the raided extreme",
            IctNear(signal.desired_stop, 112.2));
   IctCheck("the signal's reward ratio is the one the draw implies",
            IctNear(signal.dynamic_rr, (107.3 - 98.5) / (112.2 - 107.3)));
   IctCheck("the signal leaves the target price to execution",
            signal.desired_target == 0.0);
   IctCheck("the report names the ICT pattern and the raided level",
            report.pattern_mode == "ICT LIQUIDITY" &&
            report.pattern_name == "SWEEP + MSS + FVG SHORT" &&
            IctNear(report.detected_level, 112.0));
   IctCheck("the signal carries the symbol and the fixed score",
            signal.symbol == "TEST" && signal.score == XSPARK_ICT_SIGNAL_SCORE);

   // A minimum gap wider than the imbalance refuses it, which is how the EA
   // hands the spread down into the entry rule.
   strategy.SetMinimumGap(5.0);
   IctCheck("an imbalance narrower than the round-trip cost is refused",
            !strategy.Evaluate(cache, signal, report));
   strategy.SetMinimumGap(0.05);

   // Outside the kill zone the same cache must refuse, which also proves the
   // clock offset reaches the model.
   strategy.SetClockOffset(8);   // shifts 08:00 UTC out of the London window
   IctCheck("a clock offset that moves the bar out of the zone refuses",
            !strategy.Evaluate(cache, signal, report) && report.htf_verdict == "OUTSIDE ZONE");

   strategy.SetClockOffset(0);
   strategy.Deinitialize();
   IctCheck("a deinitialized strategy never signals",
            !strategy.Evaluate(cache, signal, report));
}
#endif

void RunIctWeekendCloseTests()
{
   bool use_close = false;
   int hour = 0, minute = 0;
   string reason = "";

   // Friday session ending 21:00 (75600s) flattens fifteen minutes earlier.
   IctCheck("the flatten sits a lead time before the Friday session end",
            XSparkIctWeekendClose(false, true, 75600, use_close, hour, minute, reason) &&
            use_close && hour == 20 && minute == 45);

   // A market that trades through the weekend has nothing to protect against.
   IctCheck("a weekend-trading market is not flattened",
            XSparkIctWeekendClose(true, true, 75600, use_close, hour, minute, reason) &&
            !use_close && hour == 0 && minute == 0 && reason != "");

   // No usable Friday session: fall back to the shipped time, still closing.
   IctCheck("an unreported Friday session falls back to the shipped time",
            XSparkIctWeekendClose(false, false, 0, use_close, hour, minute, reason) &&
            use_close && hour == XSPARK_ICT_WEEKEND_CLOSE_HOUR &&
            minute == XSPARK_ICT_WEEKEND_CLOSE_MINUTE);
   IctCheck("an out-of-range Friday session falls back too",
            XSparkIctWeekendClose(false, true, 999999, use_close, hour, minute, reason) &&
            use_close && hour == XSPARK_ICT_WEEKEND_CLOSE_HOUR);

   // A session ending inside the lead time cannot push the flatten into the
   // previous day; it clamps to the start of the day instead.
   IctCheck("a session ending inside the lead time clamps to midnight",
            XSparkIctWeekendClose(false, true, 300, use_close, hour, minute, reason) &&
            use_close && hour == 0 && minute == 0);

   // A full-day session reads as 24:00 and flattens at 23:45.
   IctCheck("a full-day Friday session flattens before midnight",
            XSparkIctWeekendClose(false, true, XSPARK_ICT_SECONDS_PER_DAY, use_close, hour, minute, reason) &&
            use_close && hour == 23 && minute == 45);

   // The backstop must sit AFTER every kill zone, or it would be doing the
   // kill-zone flatten's job and closing trades the model still wants open.
   IctCheck("the weekend backstop sits after the last kill zone ends",
            XSPARK_ICT_WEEKEND_CLOSE_HOUR * 60 + XSPARK_ICT_WEEKEND_CLOSE_MINUTE > XSPARK_ICT_NEWYORK_END_MIN);
}

void RunIctTests()
{
   RunIctSwingTests();
   RunIctSweepTests();
   RunIctFvgTests();
   RunIctDisplacementTests();
   RunIctEncroachmentTests();
   RunIctRangeTests();
   RunIctKillZoneTests();
   RunIctConfigTests();
   RunIctFixtureSanityTests();
   RunIctEvaluateTests();
   RunIctBullishMirrorTests();
   RunIctCostAndStopTests();
   RunIctHoldAndFlattenTests();
   RunIctWeekendCloseTests();
   RunIctWilsonTests();
#ifdef XSPARK_PORTABLE_TEST
   RunIctStrategyTests();
#endif

   Print("ICT RESULT passed=", g_ict_passed, " failed=", g_ict_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunIctTests(); }
#endif
