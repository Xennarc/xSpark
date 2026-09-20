#property script_show_inputs
#include <XSpark/Core/StrategyIdentity.mqh>

// Checks for the Magic Number registry.
//
// Two Expert Advisors sharing a Magic Number manage each other's positions, so
// the refusal below is a safety control rather than a convenience. These are
// pure checks on the registry itself; that each EA actually calls it is covered
// by tools/check_ea_inputs.py and by reading OnInit.

int g_identity_passed = 0, g_identity_failed = 0;

void IdentityCheck(const string name, const bool ok)
{
   if(ok) { g_identity_passed++; Print("PASS: ",name); }
   else { g_identity_failed++; Print("FAIL: ",name); }
}

void RunStrategyIdentityTests()
{
   string reason = "";

   IdentityCheck("every shipped strategy has its own Magic Number",
                 XSPARK_SCOREBOT_MAGIC_DEFAULT != XSPARK_CANDLEFLOW_MAGIC_DEFAULT &&
                 XSPARK_SCOREBOT_MAGIC_DEFAULT != XSPARK_TRENDSCALP_MAGIC_DEFAULT &&
                 XSPARK_CANDLEFLOW_MAGIC_DEFAULT != XSPARK_TRENDSCALP_MAGIC_DEFAULT);

   IdentityCheck("a strategy may use its own shipped default",
                 XSparkMagicIsAvailable(XSPARK_SCOREBOT_MAGIC_DEFAULT, XSPARK_SCOREBOT_MAGIC_DEFAULT, reason) &&
                 XSparkMagicIsAvailable(XSPARK_CANDLEFLOW_MAGIC_DEFAULT, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, reason) &&
                 XSparkMagicIsAvailable(XSPARK_TRENDSCALP_MAGIC_DEFAULT, XSPARK_TRENDSCALP_MAGIC_DEFAULT, reason));

   // The third strategy refuses both earlier numbers, and both earlier
   // strategies refuse its number. A registry that only checked the first two
   // would let the newest bot collide with either of them.
   IdentityCheck("TrendScalp refuses ScoreBot's and CandleFlow's Magic Numbers",
                 !XSparkMagicIsAvailable(XSPARK_SCOREBOT_MAGIC_DEFAULT, XSPARK_TRENDSCALP_MAGIC_DEFAULT, reason) &&
                 !XSparkMagicIsAvailable(XSPARK_CANDLEFLOW_MAGIC_DEFAULT, XSPARK_TRENDSCALP_MAGIC_DEFAULT, reason));

   IdentityCheck("the refusal names CandleFlow when its number is taken",
                 StringFind(reason, "CandleFlow") >= 0);

   IdentityCheck("ScoreBot and CandleFlow both refuse TrendScalp's Magic Number",
                 !XSparkMagicIsAvailable(XSPARK_TRENDSCALP_MAGIC_DEFAULT, XSPARK_SCOREBOT_MAGIC_DEFAULT, reason) &&
                 !XSparkMagicIsAvailable(XSPARK_TRENDSCALP_MAGIC_DEFAULT, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, reason));

   IdentityCheck("the refusal names TrendScalp when its number is taken",
                 StringFind(reason, "TrendScalp") >= 0);

   IdentityCheck("CandleFlow refuses ScoreBot's Magic Number",
                 !XSparkMagicIsAvailable(XSPARK_SCOREBOT_MAGIC_DEFAULT, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, reason));

   IdentityCheck("the refusal names the strategy already holding the number",
                 StringFind(reason, "ScoreBot_v3") >= 0);

   IdentityCheck("ScoreBot refuses CandleFlow's Magic Number",
                 !XSparkMagicIsAvailable(XSPARK_CANDLEFLOW_MAGIC_DEFAULT, XSPARK_SCOREBOT_MAGIC_DEFAULT, reason));

   IdentityCheck("zero is refused whichever strategy asks",
                 !XSparkMagicIsAvailable(0, XSPARK_SCOREBOT_MAGIC_DEFAULT, reason) &&
                 !XSparkMagicIsAvailable(0, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, reason) &&
                 !XSparkMagicIsAvailable(0, XSPARK_TRENDSCALP_MAGIC_DEFAULT, reason));

   // An operator running several instances of one strategy on different charts
   // picks their own numbers. Those belong to nobody and must stay usable.
   IdentityCheck("an operator's own number is available to any strategy",
                 XSparkMagicIsAvailable(990001, XSPARK_SCOREBOT_MAGIC_DEFAULT, reason) &&
                 XSparkMagicIsAvailable(990001, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, reason) &&
                 XSparkMagicIsAvailable(990001, XSPARK_TRENDSCALP_MAGIC_DEFAULT, reason));

   IdentityCheck("an unclaimed number has no claimant",
                 XSparkStrategyClaimingMagic(990001) == "");

   Print("IDENTITY RESULT passed=", g_identity_passed, " failed=", g_identity_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunStrategyIdentityTests(); }
#endif
