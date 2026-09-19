#ifndef XSPARK_UI_DASHBOARD_LAYOUT_MQH
#define XSPARK_UI_DASHBOARD_LAYOUT_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Core/UserMessages.mqh>

// Pure layout and presentation decisions for the chart panel. Nothing in this
// file touches the chart API, so every rule below is exercisable from a test
// script with no terminal, no symbol and no open position.
//
// The panel itself lives in Dashboard.mqh and only draws what these functions
// decide.

// Severity drives the colour of the status band and nothing else. It is an
// ORDERING, worst last, so a caller can compare severities rather than compare
// strings.
#define XSPARK_UI_SEV_READY   0   // healthy, waiting
#define XSPARK_UI_SEV_ACTIVE  1   // healthy, working
#define XSPARK_UI_SEV_IDLE    2   // deliberately not trading
#define XSPARK_UI_SEV_BLOCKED 3   // a gate is holding entries, transiently
#define XSPARK_UI_SEV_FAULT   4   // something is wrong and stays wrong

// Panel geometry. Widths are in screen pixels.
#define XSPARK_UI_PANEL_WIDTH 400
#define XSPARK_UI_PANEL_HEIGHT 660
#define XSPARK_UI_PAD 12

// Maps a status string to its severity.
//
// The mapping is deliberately INVERTED relative to what shipped. The original
// coloured a known list of bad statuses and let everything else fall through to
// green, so a status added anywhere in the EA without a matching edit here
// rendered as healthy. That was not hypothetical: `ACCOUNT RISK` and
// `DRIFT GATE FAULT` are both faults introduced on open branches, and both
// would have rendered green on merge. Green is now an explicit, closed set and
// ANYTHING unrecognised is a FAULT - if a status reaches this function that
// nobody mapped, the honest reading is that the panel does not know what the EA
// is doing, which is not a green condition.
int XSparkDashboardSeverity(const string status)
{
   if(status == "MANAGING")
      return XSPARK_UI_SEV_ACTIVE;

   if(status == "SCANNING")
      return XSPARK_UI_SEV_READY;

   if(status == "ANALYSIS ONLY" || status == "TRADING DISABLED")
      return XSPARK_UI_SEV_IDLE;

   if(status == "SPREAD BLOCKED" || status == "ATR BLOCKED" ||
      status == "SESSION BLOCKED" || status == "STALE QUOTE" ||
      status == "WEEKEND CLOSE")
   {
      return XSPARK_UI_SEV_BLOCKED;
   }

   // Every hard fault, including the two that exist only on open branches at the
   // time of writing. Listing them early is harmless if those branches never
   // merge, and means the panel cannot render either one green whichever order
   // the merges happen in.
   if(status == "KILLSWITCH" || status == "DD HALT" ||
      status == "STATE RECOVERY" || status == "UNMANAGED EXPOSURE" ||
      status == "POINT SIZE FAULT" || status == "ACCOUNT RISK" ||
      status == "DRIFT GATE FAULT")
   {
      return XSPARK_UI_SEV_FAULT;
   }

   return XSPARK_UI_SEV_FAULT;
}

// Width in pixels of a bar fill. Clamped to the track, and fails to EMPTY
// rather than to full: a bar that cannot be computed must not read as a
// maximum reading.
int XSparkDashboardBarPixels(const double value, const double max_value, const int track_pixels)
{
   if(track_pixels <= 0)
      return 0;

   if(!MathIsValidNumber(value) || !MathIsValidNumber(max_value) || max_value <= 0.0)
      return 0;

   if(value <= 0.0)
      return 0;

   const double ratio = value / max_value;
   if(!MathIsValidNumber(ratio))
      return 0;

   if(ratio >= 1.0)
      return track_pixels;

   const int pixels = (int)MathRound(ratio * (double)track_pixels);
   if(pixels < 0)
      return 0;
   if(pixels > track_pixels)
      return track_pixels;

   return pixels;
}

// The session weight is a MULTIPLIER on the raw score, not a component of it,
// and its values are a small fixed set. Rendering it as a bar would invite the
// reader to compare it against components it does not share a scale with, so it
// is rendered as a tag instead.
string XSparkDashboardSessionTag(const double session_weight)
{
   if(!MathIsValidNumber(session_weight))
      return "SESSION ?";

   if(session_weight >= 1.2)
      return "LDN+NY x1.2";

   if(session_weight >= 1.0)
      return "LDN|NY x1.0";

   if(session_weight >= 0.6)
      return "ASIA x0.6";

   if(session_weight > 0.0)
      return StringFormat("SESSION x%.1f", session_weight);

   return "CLOSED x0.0";
}

// Places the panel origin in CORNER_LEFT_UPPER space for any requested corner.
//
// Every object is then anchored LEFT_UPPER, so right-aligned text inside the
// panel is a simple offset from the panel origin and never has to reason about
// which direction the chart corner measures in. Clamped to the chart so a
// window smaller than the panel still shows its top-left rather than scrolling
// the whole panel out of view.
void XSparkDashboardPanelOrigin(const int corner,
                                const int chart_width,
                                const int chart_height,
                                const int margin_x,
                                const int margin_y,
                                int &x,
                                int &y,
                                const int panel_width = XSPARK_UI_PANEL_WIDTH,
                                const int panel_height = XSPARK_UI_PANEL_HEIGHT)
{
   const bool right = (corner == CORNER_RIGHT_UPPER || corner == CORNER_RIGHT_LOWER);
   const bool lower = (corner == CORNER_LEFT_LOWER || corner == CORNER_RIGHT_LOWER);

   x = right ? chart_width - panel_width - margin_x : margin_x;
   y = lower ? chart_height - panel_height - margin_y : margin_y;

   x = (int)MathMax(0, MathMin(x, chart_width - panel_width));
   y = (int)MathMax(0, MathMin(y, chart_height - panel_height));
}

// Trims a reason string to what fits on the footer line, with an ellipsis so a
// truncated message is never mistaken for a complete one. The full text always
// remains in the journal.
string XSparkDashboardTrim(const string text, const int max_chars)
{
   if(max_chars <= 0)
      return "";

   if(StringLen(text) <= max_chars)
      return text;

   if(max_chars <= 3)
      return StringSubstr(text, 0, max_chars);

   return StringSubstr(text, 0, max_chars - 3) + "...";
}

// UI snapshot only. Reading it must not run a strategy or send an order.
struct XSparkDashboardLive
{
   string symbol, timeframe, currency, entry_style;
   double bid, ask, open_profit;
   int digits, seconds_to_close, bar_seconds, position_count;
   long quote_age, quote_stamp;
   bool connected, quote_valid, positions_valid, animate;
   string positions[3];
   double position_profit[3];
};

int XSparkDashboardSecondsLeft(const datetime now, const datetime opened, const int seconds)
{
   if(now <= 0 || opened <= 0 || seconds <= 0 || now < opened) return -1;
   const long elapsed = now - opened;
   if(elapsed >= seconds) return 0; // Never start a fake next candle without a tick.
   return seconds - (int)elapsed;
}

// Word wrapping for the explanation card; tooltip/journal retain the full text.
string XSparkDashboardLine(const string text, const int line, const int columns, const bool final_line = false)
{
   if(columns < 1 || line < 0) return "";
   int start = 0;
   for(int row = 0; row <= line; row++)
   {
      const int remaining = StringLen(text) - start;
      if(remaining <= 0) return "";
      int length = (int)MathMin(columns, remaining);
      if(remaining > columns)
         for(int k = length; k > 0; k--)
            if(StringSubstr(text, start + k, 1) == " ") { length = k; break; }
      if(row == line)
      {
         if(final_line && remaining > length)
            return XSparkDashboardTrim(StringSubstr(text, start), columns);
         return StringSubstr(text, start, length);
      }
      start += length;
      while(StringSubstr(text, start, 1) == " ") start++;
   }
   return "";
}

string XSparkDashboardGate(const string verdict)
{
   if(verdict == "PASS") return "Ready";
   if(verdict == "OFF") return "Off";
   return "Waiting";
}
#endif
