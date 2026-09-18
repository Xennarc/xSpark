#property script_show_inputs
#include <XSpark/Strategy/EntrySettings.mqh>
int g_settings_passed = 0, g_settings_failed = 0;
void SettingsCheck(const string name, const bool ok)
{
   if(ok) { g_settings_passed++; Print("PASS: ",name); }
   else { g_settings_failed++; Print("FAIL: ",name); }
}
void RunEntrySettingsTests()
{
   XSparkGateConfig g; XSparkDefaultGateConfig(g);
   XSparkPatternConfig p; XSparkDefaultPatternConfig(p);
   string reason;
   SettingsCheck("saved mode preserves shipped routing",XSparkApplyEntryStyle(XSPARK_ENTRY_SAVED,g,p,reason) &&
                 g.observe_only && !g.use_htf && !g.use_pullback && !g.use_continuation && !p.enabled);
   g.use_htf=true; g.use_pullback=true; g.use_continuation=true; g.observe_only=false; p.enabled=true;
   SettingsCheck("saved mode preserves old active preset",XSparkApplyEntryStyle(XSPARK_ENTRY_SAVED,g,p,reason) &&
                 !g.observe_only && g.use_htf && g.use_pullback && g.use_continuation && p.enabled);
   // Deliberately mixed saved switches are resolved as one coherent profile.
   g.use_htf=false; g.use_pullback=true; g.use_continuation=false; g.observe_only=true; p.enabled=false;
   g.use_rsi=true; g.require_rsi_turn=true; g.pullback_min=0.4; g.min_leg_atr=2.0;
   p.flags=false; p.cups=false; p.pin_bars=true; p.max_chase_atr=0.3;
   SettingsCheck("chart style resolves all coupled switches",XSparkApplyEntryStyle(XSPARK_ENTRY_PATTERNS,g,p,reason) &&
                 !g.observe_only && g.use_htf && g.use_pullback && g.use_continuation && p.enabled);
   SettingsCheck("chart style passes dependency validation",XSparkValidateGateConfig(g,reason) &&
                 XSparkValidatePatternConfig(p,g.use_htf,g.use_pullback,g.use_continuation,reason));
   SettingsCheck("style preserves optional filters and tuning",g.use_rsi && g.require_rsi_turn && g.pullback_min==0.4 &&
                 g.min_leg_atr==2.0 && !p.flags && !p.cups && p.pin_bars && p.max_chase_atr==0.3);
   SettingsCheck("preview uses original entries with pattern telemetry",XSparkApplyEntryStyle(XSPARK_ENTRY_PREVIEW,g,p,reason) &&
                 g.observe_only && p.enabled && g.use_htf && g.use_pullback && g.use_continuation);
   SettingsCheck("original style turns off experimental routing",XSparkApplyEntryStyle(XSPARK_ENTRY_ORIGINAL,g,p,reason) &&
                 g.observe_only && !p.enabled && !g.use_htf && !g.use_pullback && !g.use_continuation);
   SettingsCheck("unknown style rejected without changing routing",!XSparkApplyEntryStyle((EXSparkEntryStyle)99,g,p,reason) &&
                 reason!="" && g.observe_only && !p.enabled && !g.use_htf && !g.use_pullback && !g.use_continuation);
   g.require_rsi_turn=true; g.use_rsi=false;
   XSparkApplyEntryStyle(XSPARK_ENTRY_PATTERNS,g,p,reason);
   SettingsCheck("quick style does not hide invalid optional filter",!XSparkValidateGateConfig(g,reason));
   Print("SETTINGS RESULT passed=",g_settings_passed," failed=",g_settings_failed);
}
#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunEntrySettingsTests(); }
#endif
