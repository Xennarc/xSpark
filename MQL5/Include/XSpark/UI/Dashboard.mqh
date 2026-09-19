#ifndef XSPARK_UI_DASHBOARD_MQH
#define XSPARK_UI_DASHBOARD_MQH

#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/UI/DashboardLayout.mqh>
#include <XSpark/UI/DashboardText.mqh>

// Panel palette. The panel paints its own opaque background rather than
// inheriting the chart's, so it is legible on a light chart, a dark chart and
// the Strategy Tester's default alike. Nothing here reads a chart colour.
#define XSPARK_UI_BG          C'10,17,25'
#define XSPARK_UI_BG_HEADER   C'15,25,36'
#define XSPARK_UI_BG_BAND     C'18,30,42'
#define XSPARK_UI_BORDER      C'34,49,64'
#define XSPARK_UI_TRACK       C'28,42,55'
#define XSPARK_UI_TEXT        C'236,240,244'
#define XSPARK_UI_TEXT_DIM    C'137,155,171'
#define XSPARK_UI_BRAND       C'247,185,85'
#define XSPARK_UI_GREEN       C'61,206,131'
#define XSPARK_UI_CYAN        C'56,208,246'
#define XSPARK_UI_AMBER       C'240,185,56'
#define XSPARK_UI_ORANGE      C'240,140,52'
#define XSPARK_UI_RED         C'236,86,76'

#define XSPARK_UI_FONT_TEXT   "Segoe UI"
#define XSPARK_UI_FONT_BOLD   "Arial Bold"
#define XSPARK_UI_FONT_NUM    "Consolas"

class CXSparkDashboard
{
private:
   bool   m_initialized;
   string m_dashboard_prefix;
   string m_trade_prefix;
   int    m_corner;
   int    m_margin_x;
   int    m_margin_y;
   int    m_origin_x;
   int    m_origin_y;

   double m_scale;
   int m_dpi;
   bool m_compact, m_last_compact, m_animate, m_force_refresh;
   ulong m_last_render;
   long m_quote_stamp;
   double m_prices[24];
   int m_price_count;

   color SeverityColor(const int severity)
   {
      if(severity == XSPARK_UI_SEV_ACTIVE)
         return XSPARK_UI_GREEN;
      if(severity == XSPARK_UI_SEV_READY)
         return XSPARK_UI_CYAN;
      if(severity == XSPARK_UI_SEV_IDLE)
         return XSPARK_UI_AMBER;
      if(severity == XSPARK_UI_SEV_BLOCKED)
         return XSPARK_UI_ORANGE;

      return XSPARK_UI_RED;
   }

   string Name(const string suffix)
   {
      return m_dashboard_prefix + suffix;
   }

   // Creates the object on first use and then only sets properties, so a
   // timer-driven refresh is property writes rather than object churn. Objects
   // are created in layout order, which is also the order MT5 paints them, so
   // backgrounds are created before the text that sits on them.
   void Rect(const string suffix,
             const int x,
             const int y,
             const int width,
             const int height,
             const color fill,
             const color border)
   {
      const string name = Name(suffix);

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      }

      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_origin_x + (int)(x * m_scale));
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_origin_y + (int)(y * m_scale));
      ObjectSetInteger(0, name, OBJPROP_XSIZE, (int)MathMax(1, width * m_scale));
      ObjectSetInteger(0, name, OBJPROP_YSIZE, (int)MathMax(1, height * m_scale));
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
      ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   }

   void Text(const string suffix,
             const int x,
             const int y,
             const string content,
             const color text_color,
             const int font_size,
             const string font,
             const bool right_aligned = false,
             const int box_width = 0,
             const int box_height = 0)
   {
      const string name = Name(suffix);

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }

      ObjectSetInteger(0, name, OBJPROP_ANCHOR, right_aligned ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_origin_x + (int)(x * m_scale));
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_origin_y + (int)(y * m_scale));
      // Every field has a pixel budget, including columns sharing a row.
      const int width = (int)((box_width > 0 ? box_width : (right_aligned ? x - 24 : 376 - x)) * m_scale);
      const int height = (int)((box_height > 0 ? box_height : font_size * 1.6) * m_scale);
      string actual_font = font;
      const int points = XSparkDashboardFont(actual_font, font_size, m_scale, m_dpi, height);
      const string fitted = points > 0 ? XSparkDashboardFitText(content, width) : "";
      ObjectSetString(0, name, OBJPROP_FONT, actual_font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, (int)MathMax(1, points));
      // MT5 can display the default "Label" for empty OBJ_LABEL text.
      // Set a space AND hide it; restore visibility when real content returns.
      ObjectSetString(0, name, OBJPROP_TEXT, fitted == "" ? " " : fitted);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, fitted == "" ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, content);
      ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   }

   // A bar is a dark track with a coloured fill laid over it. The fill is always
   // created, and collapses to one pixel at zero rather than being deleted, so
   // the object set is stable across refreshes.
   void Bar(const string suffix,
            const int x,
            const int y,
            const int width,
            const int height,
            const double value,
            const double max_value,
            const color fill_color)
   {
      Rect(suffix + "_t", x, y, width, height, XSPARK_UI_TRACK, XSPARK_UI_TRACK);

      const int filled = XSparkDashboardBarPixels(value, max_value, width);
      Rect(suffix + "_f", x, y, filled, height, fill_color, fill_color);

      // A zero reading must not show a one-pixel sliver that could be misread as
      // a small positive value.
      ObjectSetInteger(0, Name(suffix + "_f"), OBJPROP_TIMEFRAMES,
                       filled > 0 ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }

   string NoticeLine(const string text, const int row)
   {
      string font = XSPARK_UI_FONT_TEXT;
      if(XSparkDashboardFont(font, 8, m_scale, m_dpi, (int)(13 * m_scale)) == 0) return "";
      return XSparkDashboardPixelLine(text, row, (int)(352 * m_scale), row == 1);
   }

   // Drawdown is read against the budget it is spending, so the colour crosses
   // to amber at half the limit and to red at three quarters. Those are display
   // thresholds only; the limits that actually stop trading live in the
   // SafetyManager and are unaffected by anything in this file.
   color DrawdownColor(const double used_pct, const double limit_pct)
   {
      if(!MathIsValidNumber(used_pct) || !MathIsValidNumber(limit_pct) || limit_pct <= 0.0)
         return XSPARK_UI_TEXT_DIM;

      const double ratio = used_pct / limit_pct;
      if(ratio >= 0.75)
         return XSPARK_UI_RED;
      if(ratio >= 0.5)
         return XSPARK_UI_AMBER;

      return XSPARK_UI_GREEN;
   }

public:
   CXSparkDashboard()
   {
      m_initialized = false;
      m_dashboard_prefix = "ScoreBotV3_Dashboard_";
      m_trade_prefix = "ScoreBotV3_Trade_";
      m_corner = CORNER_LEFT_UPPER;
      m_margin_x = 12;
      m_margin_y = 18;
      m_origin_x = 12;
      m_origin_y = 18;
      m_dpi = 96;
      m_scale = 1.0; m_compact = false; m_last_compact = false; m_animate = true;
      m_force_refresh = true; m_last_render = 0; m_quote_stamp = 0; m_price_count = 0;
   }

   void Configure(const int corner, const int margin_x, const int margin_y, const bool compact = false, const bool animate = true)
   {
      m_compact = compact; m_animate = animate;
      m_corner = corner;
      m_margin_x = margin_x;
      m_margin_y = margin_y;
   }

   bool NeedsRefresh()
   {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return false;
      return m_force_refresh || GetTickCount64() - m_last_render >= 500;
   }

   bool HandleEvent(const int id, const string object_name)
   {
      if(id == CHARTEVENT_OBJECT_CLICK && object_name == Name("toggle"))
      {
         m_compact = !m_compact;
         ObjectSetInteger(0, object_name, OBJPROP_STATE, false);
         m_force_refresh = true; return true;
      }
      if(id == CHARTEVENT_CHART_CHANGE) { m_force_refresh = true; return true; }
      return false;
   }

   void Initialize()
   {
      // Rebuild only this panel's objects in paint order after upgrade/restart.
      // Reusing stale backgrounds can otherwise cover labels created earlier.
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         const string name = ObjectName(0, i);
         if(StringFind(name, m_dashboard_prefix) == 0 && name != Name("pattern_boundary") && name != Name("pattern_detection"))
            ObjectDelete(0, name);
      }
      m_last_compact = false; m_force_refresh = true;
      m_initialized = true;
   }

   // remove_trade_annotations must be false for a de-init that will be followed by a
   // re-init on the same chart (parameter change, recompile, template, terminal
   // restart). AnnotateEntry only ever runs at fill time, so deleting those objects
   // there would permanently erase the entry/SL/TP markers of positions that are
   // still open and still being managed.
   void Deinitialize(const bool remove_trade_annotations)
   {
      for(int index = ObjectsTotal(0) - 1; index >= 0; index--)
      {
         const string name = ObjectName(0, index);

         if(StringFind(name, m_dashboard_prefix) == 0)
         {
            ObjectDelete(0, name);
            continue;
         }

         if(remove_trade_annotations && StringFind(name, m_trade_prefix) == 0)
            ObjectDelete(0, name);
      }

      ChartRedraw(0);
      m_initialized = false;
   }

   void Update(XSparkScoreBotReport &report,
               CXSparkSafetyManager &safety,
               const double equity,
               const int trades_today,
               const int trades_last_24h,
               const int open_positions,
               const int max_open_positions,
               const double spread_score_points,
               const string mode,
               const string status,
               const string block_reason,
               XSparkDashboardLive &live)
   {
      if(!NeedsRefresh()) return;
      if(!m_initialized) Initialize();
      const ulong clock = GetTickCount64();
      m_dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      if(m_dpi <= 0) m_dpi = 96;
      const int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      const int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      m_scale = MathMin(1.0, MathMax(0.75, (double)(chart_width - 2 * m_margin_x) / 400.0));
      const bool compact = m_compact || chart_height < (int)(660 * m_scale) + 2 * m_margin_y;
      const int height = compact ? 286 : 660;
      XSparkDashboardPanelOrigin(m_corner, chart_width, chart_height, m_margin_x, m_margin_y,
                                 m_origin_x, m_origin_y, (int)(400 * m_scale), (int)(height * m_scale));
      if(compact != m_last_compact)
         for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
         {
            const string name = ObjectName(0, i);
            if(StringFind(name, Name("detail_")) == 0)
               ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, compact ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
         }
      m_last_compact = compact;
      const bool fresh = live.connected && live.quote_valid && live.quote_age >= 0 && live.quote_age <= safety.MaxQuoteAgeSeconds();
      if(fresh && live.quote_stamp != m_quote_stamp && live.bid > 0.0)
      {
         if(m_price_count == 24)
            for(int i = 0; i < 23; i++) m_prices[i] = m_prices[i + 1];
         else m_price_count++;
         m_prices[m_price_count - 1] = live.bid; m_quote_stamp = live.quote_stamp;
      }
      XSparkNotice notice; XSparkExplain(status, block_reason, notice);
      const color accent = SeverityColor(notice.severity);
      Rect("shadow", 4, 5, 400, height, C'5,10,16', C'5,10,16');
      Rect("bg", 0, 0, 400, height, XSPARK_UI_BG, XSPARK_UI_BORDER);
      Rect("topline", 1, 1, 398, 2, XSPARK_UI_BRAND, XSPARK_UI_BRAND);
      Rect("logo_a", 16, 18, 6, 17, XSPARK_UI_BRAND, XSPARK_UI_BRAND);
      Rect("logo_b", 25, 12, 6, 23, XSPARK_UI_BRAND, XSPARK_UI_BRAND);
      Text("brand", 41, 12, "xspark", XSPARK_UI_TEXT, 18, XSPARK_UI_FONT_BOLD, false, 155, 28);
      Text("feed", 220, 20, fresh ? "LIVE PRICES" : "FEED PAUSED", fresh ? XSPARK_UI_GREEN : XSPARK_UI_ORANGE, 8, XSPARK_UI_FONT_BOLD, false, 100, 14);
      const bool pulse = !m_animate || !live.animate || (clock / 1000) % 2 == 0;
      Rect("pulse", 206, 23, 5, 5, fresh ? (pulse ? XSPARK_UI_GREEN : XSPARK_UI_TRACK) : XSPARK_UI_ORANGE, XSPARK_UI_BG);
      const string button = Name("toggle");
      if(ObjectFind(0, button) < 0) ObjectCreate(0, button, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, button, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, button, OBJPROP_XDISTANCE, m_origin_x + (int)(330 * m_scale));
      ObjectSetInteger(0, button, OBJPROP_YDISTANCE, m_origin_y + (int)(14 * m_scale));
      ObjectSetInteger(0, button, OBJPROP_XSIZE, (int)(54 * m_scale));
      ObjectSetInteger(0, button, OBJPROP_YSIZE, (int)(24 * m_scale));
      ObjectSetInteger(0, button, OBJPROP_BGCOLOR, XSPARK_UI_BG_BAND);
      ObjectSetInteger(0, button, OBJPROP_COLOR, XSPARK_UI_TEXT_DIM);
      ObjectSetInteger(0, button, OBJPROP_BORDER_COLOR, XSPARK_UI_BORDER);
      string button_font = XSPARK_UI_FONT_TEXT;
      const int button_points = XSparkDashboardFont(button_font, 8, m_scale, m_dpi, (int)(16 * m_scale));
      const string button_text = button_points > 0 ? XSparkDashboardFitText(compact ? "Expand" : "Less", (int)(46 * m_scale)) : "";
      ObjectSetInteger(0, button, OBJPROP_FONTSIZE, (int)MathMax(1, button_points));
      ObjectSetInteger(0, button, OBJPROP_ZORDER, 10);
      ObjectSetInteger(0, button, OBJPROP_HIDDEN, true);
      ObjectSetString(0, button, OBJPROP_FONT, button_font);
      ObjectSetString(0, button, OBJPROP_TEXT, button_text == "" ? " " : button_text);
      ObjectSetString(0, button, OBJPROP_TOOLTIP, "Show or collapse details. Small chart windows use compact view.");
      Text("symbol", 16, 48, live.symbol + "  /  " + live.timeframe, XSPARK_UI_TEXT_DIM, 9, XSPARK_UI_FONT_BOLD);
      Text("price", 16, 68, live.quote_valid ? DoubleToString(live.bid, live.digits) : "--", fresh ? XSPARK_UI_TEXT : XSPARK_UI_TEXT_DIM, 25, XSPARK_UI_FONT_NUM, false, 218, 34);
      Text("mode", 16, 105, mode == "TRADING" ? "NEW TRADES ENABLED" : "WATCH ONLY", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 188, 12);
      // Real sampled bids; height is normalized to this sample window, not volume.
      double low = m_price_count > 0 ? m_prices[0] : live.bid, high = low;
      for(int i = 0; i < m_price_count; i++) { low = MathMin(low, m_prices[i]); high = MathMax(high, m_prices[i]); }
      for(int i = 0; i < 24; i++)
      {
         const int h = i < m_price_count ? (high > low ? 3 + (int)(30 * (m_prices[i] - low) / (high - low)) : 3) : 1;
         Rect(StringFormat("price_%d", i), 243 + i * 6, 97 - h, 4, h,
              i < m_price_count && fresh ? XSPARK_UI_BRAND : XSPARK_UI_TRACK, XSPARK_UI_BG);
      }
      ObjectSetString(0, Name("price_23"), OBJPROP_TOOLTIP, "Recent bid samples at dashboard refreshes; normalized price, not trade volume.");
      Text("quote_age", 384, 105, live.quote_age < 0 ? "No quote yet" : StringFormat("Last quote %I64ds ago", live.quote_age), XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, true, 170, 12);
      Rect("notice", 12, 128, 376, 124, XSPARK_UI_BG_HEADER, XSPARK_UI_BORDER);
      Rect("notice_edge", 12, 128, 3, 124, accent, accent);
      Text("notice_title", 24, 139, notice.title, accent, 12, XSPARK_UI_FONT_BOLD);
      for(int row = 0; row < 2; row++)
      {
         Text(StringFormat("notice_body%d", row), 24, 163 + row * 14,
              NoticeLine(notice.detail, row), XSPARK_UI_TEXT, 8, XSPARK_UI_FONT_TEXT, false, 352, 13);
         Text(StringFormat("notice_next%d", row), 24, 209 + row * 14,
              NoticeLine(notice.action, row), XSPARK_UI_TEXT_DIM, 8, XSPARK_UI_FONT_TEXT, false, 352, 13);
      }
      Text("next_label", 24, 195, "NEXT STEP", XSPARK_UI_BRAND, 7, XSPARK_UI_FONT_BOLD);
      const string notice_tooltip = notice.title + "\n" + notice.detail + "\n" + notice.action + "\nDetails: " + block_reason;
      ObjectSetString(0, Name("notice"), OBJPROP_TOOLTIP, notice_tooltip);
      ObjectSetString(0, Name("notice_title"), OBJPROP_TOOLTIP, notice_tooltip);
      for(int row = 0; row < 2; row++)
      {
         ObjectSetString(0, Name(StringFormat("notice_body%d", row)), OBJPROP_TOOLTIP, notice_tooltip);
         ObjectSetString(0, Name(StringFormat("notice_next%d", row)), OBJPROP_TOOLTIP, notice_tooltip);
      }
      if(!compact)
      {
         Rect("detail_setup", 12, 264, 376, 116, XSPARK_UI_BG_HEADER, XSPARK_UI_BORDER);
         Text("detail_setup_label", 24, 276, "LATEST CLOSED-CANDLE CHECK", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 290, 12);
         Text("detail_bar_time", 376, 276, report.signal_bar_time > 0 ? TimeToString(report.signal_bar_time, TIME_MINUTES) : "--:--", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_NUM, true, 52, 12);
         const string pattern = report.gate_candidate ? report.candidate_pattern : (report.has_pattern ? report.pattern_name : "Looking for a setup");
         Text("detail_pattern", 24, 296, pattern, XSPARK_UI_TEXT, 12, XSPARK_UI_FONT_BOLD, false, 260, 22);
         ObjectSetString(0, Name("detail_pattern"), OBJPROP_TOOLTIP,
                         "Entry candidate: " + pattern + "\nAll detections: " + report.detected_patterns + "\nRecognition mode: " + report.pattern_mode);
         Text("detail_score", 376, 299, report.scored ? StringFormat("%.1f / 9", report.components.final_score) : "-- / 9", XSPARK_UI_BRAND, 11, XSPARK_UI_FONT_NUM, true, 80, 19);
         Bar("detail_scorebar", 24, 323, 352, 5, report.scored ? report.components.final_score : 0, 9, XSPARK_UI_BRAND);
         const int threshold = XSparkDashboardBarPixels(report.effective_threshold, 9, 350);
         Rect("detail_threshold", 24 + threshold, 320, 2, 11, XSPARK_UI_TEXT_DIM, XSPARK_UI_TEXT_DIM);
         Text("detail_score_label", 24, 335, report.scored ? StringFormat("Entry threshold %.1f  |  Risk %.2f%%", report.effective_threshold, report.selected_risk_pct) : "Score available after a setup is evaluated", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
         string labels[3] = {"Trend", "Entry area", "Momentum"};
         string verdicts[3]; verdicts[0]=report.htf_verdict; verdicts[1]=report.pullback_verdict; verdicts[2]=report.rsi_verdict;
         for(int i = 0; i < 3; i++)
            Text(StringFormat("detail_gate%d", i), 24 + i * 120, 359, labels[i] + ": " + XSparkDashboardGate(verdicts[i]),
                 verdicts[i] == "PASS" ? XSPARK_UI_GREEN : XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, false, 112, 12);
         Rect("detail_account", 12, 392, 376, 108, XSPARK_UI_BG_HEADER, XSPARK_UI_BORDER);
         Text("detail_equity_l", 24, 404, "ACCOUNT EQUITY", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 136, 12);
         Text("detail_profit_l", 170, 404, "OPEN PROFIT", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 130, 12);
         Text("detail_positions_l", 310, 404, "TRADES", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 66, 12);
         Text("detail_equity", 24, 423, DoubleToString(equity, 2), XSPARK_UI_TEXT, StringLen(DoubleToString(equity, 2)) > 11 ? 10 : 15, XSPARK_UI_FONT_NUM, false, 136, 24);
         Text("detail_profit", 170, 423, live.positions_valid ? StringFormat("%+.2f", live.open_profit) : "--", live.open_profit >= 0 ? XSPARK_UI_GREEN : XSPARK_UI_RED, StringLen(DoubleToString(live.open_profit, 2)) > 10 ? 10 : 15, XSPARK_UI_FONT_NUM, false, 130, 24);
         Text("detail_positions", 310, 423, live.positions_valid ? StringFormat("%d/%d", live.position_count, max_open_positions) : "--", XSPARK_UI_TEXT, 15, XSPARK_UI_FONT_NUM, false, 66, 24);
         Text("detail_currency", 24, 449, live.currency, XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, false, 136, 12);
         Text("detail_today", 170, 449, StringFormat("%d today / %d in 24h", trades_today, trades_last_24h), XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
         Text("detail_daily_l", 24, 466, StringFormat("Daily loss %.1f / %.1f%%", safety.DailyDDPct(), safety.MaxDailyDDPct()), XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, false, 174, 12);
         Text("detail_total_l", 208, 466, StringFormat("Peak loss %.1f / %.1f%%", safety.TotalDDPct(), safety.MaxTotalDDPct()), XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, false, 168, 12);
         Bar("detail_daily", 24, 484, 166, 4, safety.DailyDDPct(), safety.MaxDailyDDPct(), DrawdownColor(safety.DailyDDPct(), safety.MaxDailyDDPct()));
         Bar("detail_total", 208, 484, 166, 4, safety.TotalDDPct(), safety.MaxTotalDDPct(), DrawdownColor(safety.TotalDDPct(), safety.MaxTotalDDPct()));
         Rect("detail_trades", 12, 512, 376, 100, XSPARK_UI_BG_HEADER, XSPARK_UI_BORDER);
         Text("detail_trades_l", 24, 524, "THIS BOT'S OPEN TRADES", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD, false, 222, 12);
         Text("detail_spread", 376, 524, StringFormat("Spread %.1f pts", spread_score_points), XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_NUM, true, 120, 12);
         for(int i = 0; i < 3; i++)
         {
            string line = live.positions_valid ? (i < live.position_count ? live.positions[i] : "") : (i == 0 ? "Position data is temporarily unavailable" : "");
            if(live.positions_valid && live.position_count == 0 && i == 0) line = "No open trades. Waiting for a new entry.";
            Text(StringFormat("detail_trade%d", i), 24, 546 + i * 19, line, XSPARK_UI_TEXT, 8, XSPARK_UI_FONT_TEXT, false, live.position_count > i ? 256 : 352, 15);
            Text(StringFormat("detail_pnl%d", i), 376, 546 + i * 19,
                 live.positions_valid && live.position_count > i ? StringFormat("%+.2f", live.position_profit[i]) : "",
                 live.position_profit[i] >= 0 ? XSPARK_UI_GREEN : XSPARK_UI_RED, 8, XSPARK_UI_FONT_NUM, true, 86, 15);
         }
         ObjectSetString(0, Name("detail_trades"), OBJPROP_TOOLTIP, StringFormat("Showing up to 3 of %d positions for this symbol and bot ID. Open profit includes swap, excludes commission. Managed records: %d.", live.position_count, open_positions));
      }
      const int footer = height - 28;
      string countdown = live.seconds_to_close < 0 ? "Waiting for candle data" :
                         (live.seconds_to_close == 0 ? "Awaiting next tick" : StringFormat("Next candle %02d:%02d", live.seconds_to_close / 60, live.seconds_to_close % 60));
      Text("footer_clock", 16, footer, countdown, XSPARK_UI_TEXT_DIM, 8, XSPARK_UI_FONT_NUM, false, 192, 13);
      Text("footer_style", 384, footer, live.entry_style, XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT, true, 166, 13);
      Bar("candle_progress", 16, height - 12, 368, 3,
          live.seconds_to_close >= 0 ? live.bar_seconds - live.seconds_to_close : 0, live.bar_seconds, fresh ? XSPARK_UI_BRAND : XSPARK_UI_TRACK);
      m_last_render = clock; m_force_refresh = false;
      ChartRedraw(0);
   }

   // Latest recognized boundary only. Detection is never labelled as a trade.
   void AnnotatePattern(const XSparkScoreBotReport &report)
   {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      const string line = Name("pattern_boundary"), label = Name("pattern_detection");
      if(report.detected_level <= 0.0)
      {
         ObjectDelete(0, line); ObjectDelete(0, label);
         return;
      }
      if(ObjectFind(0, line) < 0) ObjectCreate(0, line, OBJ_HLINE, 0, 0, report.detected_level);
      ObjectSetDouble(0, line, OBJPROP_PRICE, report.detected_level);
      ObjectSetInteger(0, line, OBJPROP_COLOR, XSPARK_UI_CYAN);
      ObjectSetInteger(0, line, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, line, OBJPROP_TOOLTIP, "Detected boundary: " + report.detected_patterns + " / " + report.pattern_mode);
      if(ObjectFind(0, label) < 0) ObjectCreate(0, label, OBJ_TEXT, 0, report.signal_bar_time, report.detected_level);
      ObjectMove(0, label, 0, report.signal_bar_time, report.detected_level);
      ObjectSetString(0, label, OBJPROP_TEXT, "DETECTED: " + report.detected_patterns);
      ObjectSetInteger(0, label, OBJPROP_COLOR, XSPARK_UI_CYAN);
      ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   }

   void AnnotateEntry(XSparkTradePlan &plan, XSparkExecutionResult &result)
   {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      const string base = StringFormat("%s%I64u_%I64d",
                                       m_trade_prefix,
                                       result.deal_ticket,
                                       (long)plan.signal_bar_time);
      const int digits = (int)SymbolInfoInteger(plan.symbol, SYMBOL_DIGITS);
      const color entry_color = plan.direction == XSPARK_SIGNAL_BUY ? XSPARK_UI_GREEN : XSPARK_UI_RED;
      const int arrow_code = plan.direction == XSPARK_SIGNAL_BUY ? 233 : 234;

      ObjectCreate(0, base + "_Arrow", OBJ_ARROW, 0, plan.signal_bar_time, result.price);
      ObjectSetInteger(0, base + "_Arrow", OBJPROP_ARROWCODE, arrow_code);
      ObjectSetInteger(0, base + "_Arrow", OBJPROP_COLOR, entry_color);
      ObjectSetInteger(0, base + "_Arrow", OBJPROP_WIDTH, 2);

      ObjectCreate(0, base + "_Label", OBJ_TEXT, 0, plan.signal_bar_time, result.price);
      ObjectSetString(0, base + "_Label", OBJPROP_TEXT,
                      StringFormat("%s %.2f %s",
                                   XSparkDirectionName(plan.direction),
                                   plan.score,
                                   plan.pattern_name));
      ObjectSetInteger(0, base + "_Label", OBJPROP_COLOR, entry_color);
      ObjectSetInteger(0, base + "_Label", OBJPROP_FONTSIZE, 8);

      ObjectCreate(0, base + "_Entry", OBJ_HLINE, 0, 0, result.price);
      ObjectSetInteger(0, base + "_Entry", OBJPROP_COLOR, entry_color);
      ObjectSetInteger(0, base + "_Entry", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, base + "_Entry", OBJPROP_TEXT, "Entry " + DoubleToString(result.price, digits));

      ObjectCreate(0, base + "_SL", OBJ_HLINE, 0, 0, plan.final_sl);
      ObjectSetInteger(0, base + "_SL", OBJPROP_COLOR, XSPARK_UI_RED);
      ObjectSetInteger(0, base + "_SL", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, base + "_SL", OBJPROP_TEXT, "Initial SL " + DoubleToString(plan.final_sl, digits));

      ObjectCreate(0, base + "_TP", OBJ_HLINE, 0, 0, plan.final_tp);
      ObjectSetInteger(0, base + "_TP", OBJPROP_COLOR, XSPARK_UI_GREEN);
      ObjectSetInteger(0, base + "_TP", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, base + "_TP", OBJPROP_TEXT, "TP " + DoubleToString(plan.final_tp, digits));

      ChartRedraw(0);
   }
};

#endif
