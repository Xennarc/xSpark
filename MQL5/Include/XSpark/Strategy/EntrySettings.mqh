#ifndef XSPARK_ENTRY_SETTINGS_MQH
#define XSPARK_ENTRY_SETTINGS_MQH
#include <XSpark/Strategy/EntryGates.mqh>
#include <XSpark/Strategy/ChartPatterns.mqh>

// Explicit values are persisted in .set files. Comments label the MT5 dropdown.
enum EXSparkEntryStyle
{
   XSPARK_ENTRY_SAVED = 0,    // Use saved / custom entry switches
   XSPARK_ENTRY_ORIGINAL = 1, // Original candle entries
   XSPARK_ENTRY_PREVIEW = 2,  // Preview chart patterns (original entries)
   XSPARK_ENTRY_PATTERNS = 3  // Chart patterns and engulfing entries
};

string XSparkEntryStyleName(const EXSparkEntryStyle style)
{
   switch(style)
   {
      case XSPARK_ENTRY_SAVED: return "Use saved / custom entry switches";
      case XSPARK_ENTRY_ORIGINAL: return "Original candle entries";
      case XSPARK_ENTRY_PREVIEW: return "Preview chart patterns (original entries)";
      case XSPARK_ENTRY_PATTERNS: return "Chart patterns and engulfing entries";
      default: return "Invalid entry style";
   }
}

// Resolve only the five interdependent routing switches. Risk, entry permission,
// optional filters and tuning remain the user's settings. Saved mode is identity.
bool XSparkApplyEntryStyle(const EXSparkEntryStyle style, XSparkGateConfig &gates,
                           XSparkPatternConfig &patterns, string &reason)
{
   reason = "";
   if(style == XSPARK_ENTRY_SAVED) return true;
   if(style != XSPARK_ENTRY_ORIGINAL && style != XSPARK_ENTRY_PREVIEW && style != XSPARK_ENTRY_PATTERNS)
   { reason = "Choose a valid Entry style from the dropdown."; return false; }
   const bool use_patterns = style != XSPARK_ENTRY_ORIGINAL;
   patterns.enabled = use_patterns;
   gates.use_htf = use_patterns;
   gates.use_pullback = use_patterns;
   gates.use_continuation = use_patterns;
   gates.observe_only = style != XSPARK_ENTRY_PATTERNS;
   return true;
}
#endif
