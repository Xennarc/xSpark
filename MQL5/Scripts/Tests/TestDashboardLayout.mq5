#property script_show_inputs

// Deterministic tests for the chart panel's pure presentation rules.
// These exercise layout and mapping functions only. Rendering itself - object
// creation, fonts, colours, z-order - is NOT simulated here and must be checked
// visually on a chart.

#include <XSpark/UI/DashboardLayout.mqh>

int g_passed = 0;
int g_failed = 0;

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

// The panel must never render a status it does not understand as healthy. The
// version that shipped coloured a known list of bad statuses and defaulted
// everything else to green, so a status added anywhere in the EA without a
// matching edit here read as healthy.
void TestSeverityMapping()
{
   Check("MANAGING is active", XSparkDashboardSeverity("MANAGING") == XSPARK_UI_SEV_ACTIVE);
   Check("SCANNING is ready", XSparkDashboardSeverity("SCANNING") == XSPARK_UI_SEV_READY);

   Check("ANALYSIS ONLY is idle", XSparkDashboardSeverity("ANALYSIS ONLY") == XSPARK_UI_SEV_IDLE);
   Check("TRADING DISABLED is idle", XSparkDashboardSeverity("TRADING DISABLED") == XSPARK_UI_SEV_IDLE);

   Check("SPREAD BLOCKED is blocked", XSparkDashboardSeverity("SPREAD BLOCKED") == XSPARK_UI_SEV_BLOCKED);
   Check("ATR BLOCKED is blocked", XSparkDashboardSeverity("ATR BLOCKED") == XSPARK_UI_SEV_BLOCKED);
   Check("SESSION BLOCKED is blocked", XSparkDashboardSeverity("SESSION BLOCKED") == XSPARK_UI_SEV_BLOCKED);
   Check("STALE QUOTE is blocked", XSparkDashboardSeverity("STALE QUOTE") == XSPARK_UI_SEV_BLOCKED);
   Check("WEEKEND CLOSE is blocked", XSparkDashboardSeverity("WEEKEND CLOSE") == XSPARK_UI_SEV_BLOCKED);
   // TrendScalp's two gates, and OPPOSING EXPOSURE, which XSparkFlow already
   // raised as a status nothing had mapped - so it rendered as a fault.
   Check("COST BLOCKED is blocked", XSparkDashboardSeverity("COST BLOCKED") == XSPARK_UI_SEV_BLOCKED);
   Check("DAILY CAP is blocked", XSparkDashboardSeverity("DAILY CAP") == XSPARK_UI_SEV_BLOCKED);
   Check("OPPOSING EXPOSURE is blocked", XSparkDashboardSeverity("OPPOSING EXPOSURE") == XSPARK_UI_SEV_BLOCKED);

   Check("KILLSWITCH is a fault", XSparkDashboardSeverity("KILLSWITCH") == XSPARK_UI_SEV_FAULT);
   Check("DD HALT is a fault", XSparkDashboardSeverity("DD HALT") == XSPARK_UI_SEV_FAULT);
   Check("STATE RECOVERY is a fault", XSparkDashboardSeverity("STATE RECOVERY") == XSPARK_UI_SEV_FAULT);
   Check("UNMANAGED EXPOSURE is a fault", XSparkDashboardSeverity("UNMANAGED EXPOSURE") == XSPARK_UI_SEV_FAULT);
   Check("POINT SIZE FAULT is a fault", XSparkDashboardSeverity("POINT SIZE FAULT") == XSPARK_UI_SEV_FAULT);

   // Pre-mapped from open branches so neither can render green on merge,
   // whichever order the merges happen in.
   Check("ACCOUNT RISK is a fault", XSparkDashboardSeverity("ACCOUNT RISK") == XSPARK_UI_SEV_FAULT);
   Check("DRIFT GATE FAULT is a fault", XSparkDashboardSeverity("DRIFT GATE FAULT") == XSPARK_UI_SEV_FAULT);

   // The point of the inversion.
   Check("an unmapped status is a fault, not healthy",
         XSparkDashboardSeverity("SOME NEW STATUS") == XSPARK_UI_SEV_FAULT);
   Check("an empty status is a fault", XSparkDashboardSeverity("") == XSPARK_UI_SEV_FAULT);
   Check("a lowercase near-miss is a fault", XSparkDashboardSeverity("scanning") == XSPARK_UI_SEV_FAULT);

   Check("fault outranks blocked", XSPARK_UI_SEV_FAULT > XSPARK_UI_SEV_BLOCKED);
   Check("blocked outranks idle", XSPARK_UI_SEV_BLOCKED > XSPARK_UI_SEV_IDLE);
}

void TestBarPixels()
{
   Check("half of a 200px track is 100px", XSparkDashboardBarPixels(0.5, 1.0, 200) == 100);
   Check("a full reading fills the track", XSparkDashboardBarPixels(1.0, 1.0, 200) == 200);
   Check("an over-range reading is clamped", XSparkDashboardBarPixels(5.0, 1.0, 200) == 200);
   Check("a zero reading is empty", XSparkDashboardBarPixels(0.0, 1.0, 200) == 0);

   // MTF tops out at 0.5, which the plain numeric readout could not convey.
   Check("MTF at its maximum reads full", XSparkDashboardBarPixels(0.5, 0.5, 100) == 100);
   // PAT tops out at 2.0, so the same 0.5 is a quarter there.
   Check("PAT at 0.5 reads a quarter", XSparkDashboardBarPixels(0.5, 2.0, 100) == 25);

   Check("the reference score fills proportionally",
         XSparkDashboardBarPixels(6.0, XSPARK_SCOREBOT_MAX_SCORE, 282) == 188);

   // Fails to EMPTY, never to full. A bar that cannot be computed must not read
   // as a maximum.
   Check("a negative reading is empty", XSparkDashboardBarPixels(-1.0, 1.0, 200) == 0);
   Check("a zero maximum is empty", XSparkDashboardBarPixels(1.0, 0.0, 200) == 0);
   Check("a negative maximum is empty", XSparkDashboardBarPixels(1.0, -1.0, 200) == 0);
   Check("a zero track is empty", XSparkDashboardBarPixels(1.0, 1.0, 0) == 0);
   Check("a negative track is empty", XSparkDashboardBarPixels(1.0, 1.0, -5) == 0);

   const double bar_infinity = MathPow(10.0, 400.0);
   const double bar_nan = bar_infinity - bar_infinity;

   Check("a non-finite reading is empty", XSparkDashboardBarPixels(bar_nan, 1.0, 200) == 0);
   // Infinity is rejected by the finiteness guard BEFORE the ratio is taken, so
   // it reads empty rather than full. That is the contract: a bar that cannot be
   // computed must never render as a maximum.
   Check("an infinite reading is empty, not full",
         XSparkDashboardBarPixels(bar_infinity, 1.0, 200) == 0);
   Check("a non-finite maximum is empty", XSparkDashboardBarPixels(1.0, bar_nan, 200) == 0);
   Check("an infinite maximum is empty", XSparkDashboardBarPixels(1.0, bar_infinity, 200) == 0);
}

void TestSessionTag()
{
   // The four values XSparkScoreBotSessionWeight can actually return.
   Check("overlap tag", XSparkDashboardSessionTag(1.2) == "LDN+NY x1.2");
   Check("single session tag", XSparkDashboardSessionTag(1.0) == "LDN|NY x1.0");
   Check("reduced asian tag", XSparkDashboardSessionTag(0.6) == "ASIA x0.6");
   Check("closed tag", XSparkDashboardSessionTag(0.0) == "CLOSED x0.0");

   // A weight of zero multiplies the whole score to zero, so it must never read
   // like an ordinary session.
   Check("a zero weight is reported as closed",
         StringFind(XSparkDashboardSessionTag(0.0), "CLOSED") >= 0);

   const double tag_infinity = MathPow(10.0, 400.0);
   Check("a non-finite weight is reported as unknown",
         XSparkDashboardSessionTag(tag_infinity - tag_infinity) == "SESSION ?");
}

void TestPanelOrigin()
{
   int x = 0;
   int y = 0;

   XSparkDashboardPanelOrigin(CORNER_LEFT_UPPER, 1200, 800, 12, 18, x, y);
   Check("left upper uses the margins directly", x == 12 && y == 18);

   XSparkDashboardPanelOrigin(CORNER_RIGHT_UPPER, 1200, 800, 12, 18, x, y);
   Check("right upper measures from the right edge",
         x == 1200 - XSPARK_UI_PANEL_WIDTH - 12 && y == 18);

   XSparkDashboardPanelOrigin(CORNER_LEFT_LOWER, 1200, 800, 12, 18, x, y);
   Check("left lower measures from the bottom edge",
         x == 12 && y == 800 - XSPARK_UI_PANEL_HEIGHT - 18);

   XSparkDashboardPanelOrigin(CORNER_RIGHT_LOWER, 1200, 800, 12, 18, x, y);
   Check("right lower measures from both far edges",
         x == 1200 - XSPARK_UI_PANEL_WIDTH - 12 &&
         y == 800 - XSPARK_UI_PANEL_HEIGHT - 18);

   // A window narrower or shorter than the panel must still show the panel's
   // top-left corner rather than scroll it out of view entirely.
   XSparkDashboardPanelOrigin(CORNER_RIGHT_LOWER, 100, 100, 12, 18, x, y);
   Check("a window smaller than the panel clamps to the origin", x == 0 && y == 0);

   XSparkDashboardPanelOrigin(CORNER_RIGHT_UPPER, 0, 0, 12, 18, x, y);
   Check("a zero-sized chart clamps rather than going negative", x == 0 && y == 0);
}

void TestReasonTrim()
{
   Check("a short reason is untouched", XSparkDashboardTrim("blocked", 58) == "blocked");

   const string long_reason = "Score below effective threshold and the spread filter is also holding entries right now";
   const string trimmed = XSparkDashboardTrim(long_reason, 58);

   Check("a long reason is trimmed to the limit", StringLen(trimmed) == 58);
   // A truncated message must never be mistakable for a complete one.
   Check("a trimmed reason is marked as trimmed",
         StringSubstr(trimmed, StringLen(trimmed) - 3, 3) == "...");
   Check("a reason at exactly the limit is untouched",
         XSparkDashboardTrim("0123456789", 10) == "0123456789");
   Check("one character over the limit is trimmed",
         XSparkDashboardTrim("01234567890", 10) == "0123456...");
   Check("a zero limit yields nothing", XSparkDashboardTrim("anything", 0) == "");
   Check("a negative limit yields nothing", XSparkDashboardTrim("anything", -1) == "");
   Check("a limit too small for an ellipsis still truncates",
         XSparkDashboardTrim("anything", 2) == "an");
   Check("an empty reason stays empty", XSparkDashboardTrim("", 58) == "");
}

void OnStart()
{
   Print("Starting XSpark dashboard layout tests");
   TestSeverityMapping();
   TestBarPixels();
   TestSessionTag();
   TestPanelOrigin();
   TestReasonTrim();
   PrintFormat("XSpark dashboard layout tests complete: PASS=%d FAIL=%d", g_passed, g_failed);
}
