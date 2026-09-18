#ifndef XSPARK_UI_DASHBOARD_MQH
#define XSPARK_UI_DASHBOARD_MQH

#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/UI/DashboardLayout.mqh>

// Panel palette. The panel paints its own opaque background rather than
// inheriting the chart's, so it is legible on a light chart, a dark chart and
// the Strategy Tester's default alike. Nothing here reads a chart colour.
#define XSPARK_UI_BG          C'16,18,24'
#define XSPARK_UI_BG_HEADER   C'23,26,34'
#define XSPARK_UI_BG_BAND     C'21,24,31'
#define XSPARK_UI_BORDER      C'38,43,56'
#define XSPARK_UI_TRACK       C'32,36,47'
#define XSPARK_UI_TEXT        C'226,231,241'
#define XSPARK_UI_TEXT_DIM    C'129,138,158'
#define XSPARK_UI_BRAND       C'56,208,246'
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

      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_origin_x + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_origin_y + y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width < 1 ? 1 : width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height < 1 ? 1 : height);
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
             const bool right_aligned = false)
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
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_origin_x + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_origin_y + y);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
      ObjectSetString(0, name, OBJPROP_TEXT, content);
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

   void SectionLabel(const string suffix, const int y, const string title)
   {
      Text(suffix, XSPARK_UI_PAD, y, title, XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_BOLD);
      Rect(suffix + "_rule", XSPARK_UI_PAD, y + 12,
           XSPARK_UI_PANEL_WIDTH - XSPARK_UI_PAD * 2, 1,
           XSPARK_UI_BORDER, XSPARK_UI_BORDER);
   }

   void Dot(const string suffix, const int x, const int y, const bool latched)
   {
      Rect(suffix, x, y, 6, 6,
           latched ? XSPARK_UI_RED : XSPARK_UI_GREEN,
           latched ? XSPARK_UI_RED : XSPARK_UI_GREEN);
   }

   color DirectionColor(const EXSparkSignalDirection direction)
   {
      if(direction == XSPARK_SIGNAL_BUY)
         return XSPARK_UI_GREEN;
      if(direction == XSPARK_SIGNAL_SELL)
         return XSPARK_UI_RED;

      return XSPARK_UI_TEXT_DIM;
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
   }

   void Configure(const int corner, const int margin_x, const int margin_y)
   {
      m_corner = corner;
      m_margin_x = margin_x;
      m_margin_y = margin_y;
   }

   void Initialize()
   {
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
               const string block_reason)
   {
      if(!m_initialized)
         Initialize();

      // Recomputed every refresh so the panel stays put when the chart window is
      // resized or the terminal is restored from a different geometry.
      XSparkDashboardPanelOrigin(m_corner,
                                 (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS),
                                 (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS),
                                 m_margin_x,
                                 m_margin_y,
                                 m_origin_x,
                                 m_origin_y);

      const int severity = XSparkDashboardSeverity(status);
      const color severity_color = SeverityColor(severity);
      const int inner = XSPARK_UI_PANEL_WIDTH - XSPARK_UI_PAD * 2;
      const int right_edge = XSPARK_UI_PANEL_WIDTH - XSPARK_UI_PAD;

      Rect("bg", 0, 0, XSPARK_UI_PANEL_WIDTH, XSPARK_UI_PANEL_HEIGHT,
           XSPARK_UI_BG, XSPARK_UI_BORDER);

      // ---- header -------------------------------------------------------
      Rect("hdr", 1, 1, XSPARK_UI_PANEL_WIDTH - 2, 33, XSPARK_UI_BG_HEADER, XSPARK_UI_BG_HEADER);
      Text("hdr_mark", XSPARK_UI_PAD, 9, "XSPARK", XSPARK_UI_BRAND, 13, XSPARK_UI_FONT_BOLD);
      Text("hdr_sub", XSPARK_UI_PAD + 86, 14, "SCOREBOT V3", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Text("hdr_mode", right_edge, 13, mode, XSPARK_UI_TEXT_DIM, 8, XSPARK_UI_FONT_TEXT, true);

      // ---- status band --------------------------------------------------
      Rect("band", 1, 34, XSPARK_UI_PANEL_WIDTH - 2, 26, XSPARK_UI_BG_BAND, XSPARK_UI_BG_BAND);
      Rect("band_accent", 1, 34, 3, 26, severity_color, severity_color);
      Text("band_text", XSPARK_UI_PAD, 41, status, severity_color, 10, XSPARK_UI_FONT_BOLD);
      Text("band_bar", right_edge, 43,
           StringFormat("%s  %s", XSparkDirectionName(report.direction),
                        report.signal_bar_time > 0
                           ? TimeToString(report.signal_bar_time, TIME_MINUTES)
                           : "--:--"),
           XSPARK_UI_TEXT_DIM, 8, XSPARK_UI_FONT_NUM, true);

      // ---- signal -------------------------------------------------------
      SectionLabel("s_signal", 70, "SIGNAL");

      Text("sig_pattern", XSPARK_UI_PAD, 88,
           report.has_pattern ? report.pattern_name : "no pattern",
           report.has_pattern ? DirectionColor(report.direction) : XSPARK_UI_TEXT_DIM,
           9, XSPARK_UI_FONT_TEXT);
      Text("sig_score", right_edge, 87,
           StringFormat("%.2f", report.components.final_score),
           report.threshold_passed ? XSPARK_UI_GREEN : XSPARK_UI_TEXT,
           11, XSPARK_UI_FONT_NUM, true);

      // Score track, fill, and a tick marking the threshold. The tick is what
      // makes the bar readable at a glance: fill past the tick is a qualifying
      // setup, fill short of it is not, with no arithmetic required.
      Bar("sig", XSPARK_UI_PAD, 108, inner, 8,
          report.components.final_score, XSPARK_SCOREBOT_MAX_SCORE,
          report.threshold_passed ? XSPARK_UI_GREEN : XSPARK_UI_TEXT_DIM);

      const int tick_x = XSPARK_UI_PAD + XSparkDashboardBarPixels(report.effective_threshold,
                                                                 XSPARK_SCOREBOT_MAX_SCORE,
                                                                 inner);
      Rect("sig_tick", tick_x - 1, 105, 2, 14, XSPARK_UI_TEXT, XSPARK_UI_TEXT);

      Text("sig_meta", XSPARK_UI_PAD, 122,
           StringFormat("threshold %.2f   ceiling %.1f   RR %.2f",
                        report.effective_threshold,
                        XSPARK_SCOREBOT_MAX_SCORE,
                        report.dynamic_rr),
           XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_NUM);

      // Component bars. Each is drawn against ITS OWN maximum, which the plain
      // numeric readout could not convey: MTF tops out at 0.5 and PAT at 2.0, so
      // a raw "MTF 0.50" read as a low value when it was in fact the maximum.
      string component_names[7];
      double component_values[7];
      double component_maxima[7];

      component_names[0] = "PAT";  component_values[0] = report.components.pattern; component_maxima[0] = 2.0;
      component_names[1] = "ATR";  component_values[1] = report.components.atr;     component_maxima[1] = 1.0;
      component_names[2] = "TRD";  component_values[2] = report.components.trend;   component_maxima[2] = 1.0;
      component_names[3] = "RSI";  component_values[3] = report.components.rsi;     component_maxima[3] = 1.0;
      component_names[4] = "S/R";  component_values[4] = report.components.sr;      component_maxima[4] = 1.0;
      component_names[5] = "VOL";  component_values[5] = report.components.volume;  component_maxima[5] = 1.0;
      component_names[6] = "MTF";  component_values[6] = report.components.mtf;     component_maxima[6] = 0.5;

      const int column_width = 34;
      const int column_gap = 6;
      const int columns_x = XSPARK_UI_PAD + 2;

      for(int c = 0; c < 7; c++)
      {
         const int column_x = columns_x + c * (column_width + column_gap);
         const double ratio = component_maxima[c] > 0.0 ? component_values[c] / component_maxima[c] : 0.0;

         Text(StringFormat("cmp%d_l", c), column_x, 140, component_names[c],
              ratio >= 0.999 ? XSPARK_UI_TEXT : XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
         Bar(StringFormat("cmp%d", c), column_x, 154, column_width, 5,
             component_values[c], component_maxima[c],
             ratio >= 0.999 ? XSPARK_UI_GREEN : XSPARK_UI_CYAN);
      }

      // ---- market -------------------------------------------------------
      SectionLabel("s_market", 172, "MARKET");

      Text("mkt_atr", XSPARK_UI_PAD, 190,
           StringFormat("ATR14 %.1f   ATR50 %.1f", report.atr_points, report.atr50_points),
           XSPARK_UI_TEXT, 8, XSPARK_UI_FONT_NUM);
      Text("mkt_session", right_edge, 190,
           XSparkDashboardSessionTag(report.components.session_weight),
           report.components.session_weight > 0.0 ? XSPARK_UI_TEXT : XSPARK_UI_ORANGE,
           8, XSPARK_UI_FONT_NUM, true);

      Text("mkt_rsi", XSPARK_UI_PAD, 206,
           StringFormat("RSI %.1f / %.1f", report.rsi_base, report.rsi_higher),
           XSPARK_UI_TEXT, 8, XSPARK_UI_FONT_NUM);
      Text("mkt_spread", right_edge, 206,
           StringFormat("spread %.1f", spread_score_points),
           XSPARK_UI_TEXT_DIM, 8, XSPARK_UI_FONT_NUM, true);

      Text("mkt_structure", XSPARK_UI_PAD, 218,
           "HTF " + report.structure_status + " / " + report.joint_verdict,
           XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);

      // ---- risk and performance -----------------------------------------
      SectionLabel("s_risk", 228, "RISK & PERFORMANCE");

      Text("rsk_equity", XSPARK_UI_PAD, 245,
           StringFormat("%.2f", equity), XSPARK_UI_TEXT, 13, XSPARK_UI_FONT_NUM);

      const double total_dd = safety.TotalDDPct();
      const bool at_high = total_dd <= 0.0000001;
      Text("rsk_fromhigh", right_edge, 250,
           at_high ? "AT HIGH" : StringFormat("-%.2f%% from high", total_dd),
           at_high ? XSPARK_UI_GREEN : DrawdownColor(total_dd, safety.MaxTotalDDPct()),
           9, XSPARK_UI_FONT_NUM, true);

      const double daily_dd = safety.DailyDDPct();
      const double daily_limit = safety.MaxDailyDDPct();
      const double total_limit = safety.MaxTotalDDPct();

      Text("rsk_dd_l", XSPARK_UI_PAD, 272, "Daily drawdown", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Text("rsk_dd_v", right_edge, 272,
           StringFormat("%.2f%% / %.2f%%", daily_dd, daily_limit),
           DrawdownColor(daily_dd, daily_limit), 7, XSPARK_UI_FONT_NUM, true);
      Bar("rsk_dd", XSPARK_UI_PAD, 285, inner, 6, daily_dd, daily_limit,
          DrawdownColor(daily_dd, daily_limit));

      Text("rsk_td_l", XSPARK_UI_PAD, 297, "Total drawdown", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Text("rsk_td_v", right_edge, 297,
           StringFormat("%.2f%% / %.2f%%", total_dd, total_limit),
           DrawdownColor(total_dd, total_limit), 7, XSPARK_UI_FONT_NUM, true);
      Bar("rsk_td", XSPARK_UI_PAD, 310, inner, 6, total_dd, total_limit,
          DrawdownColor(total_dd, total_limit));

      // The distance to the ruin stop, in words. This is the number that decides
      // whether the account keeps trading, so it is stated rather than left for
      // the reader to subtract.
      const double remaining = total_limit - total_dd;
      Text("rsk_kill", XSPARK_UI_PAD, 322,
           safety.TotalDDKillSwitchEnabled()
              ? (safety.TotalDDKillSwitchLatched()
                    ? "killswitch LATCHED - no new entries until cleared"
                    : StringFormat("killswitch at %.2f%%  -  %.2f%% away", total_limit, remaining))
              : "killswitch DISABLED - no ruin stop is armed",
           safety.TotalDDKillSwitchEnabled()
              ? (safety.TotalDDKillSwitchLatched() ? XSPARK_UI_RED : XSPARK_UI_TEXT_DIM)
              : XSPARK_UI_RED,
           7, XSPARK_UI_FONT_NUM);

      Text("rsk_pos", XSPARK_UI_PAD, 340,
           StringFormat("positions %d/%d", open_positions, max_open_positions),
           open_positions >= max_open_positions ? XSPARK_UI_AMBER : XSPARK_UI_TEXT,
           8, XSPARK_UI_FONT_NUM);
      Text("rsk_trades", right_edge, 340,
           StringFormat("today %d  24h %d  risk %.2f%%",
                        trades_today, trades_last_24h, report.selected_risk_pct),
           XSPARK_UI_TEXT, 8, XSPARK_UI_FONT_NUM, true);

      // ---- guards -------------------------------------------------------
      Rect("g_rule", XSPARK_UI_PAD, 358, inner, 1, XSPARK_UI_BORDER, XSPARK_UI_BORDER);

      const bool quote_stale = safety.LastQuoteAgeSeconds() > (long)safety.MaxQuoteAgeSeconds();

      Dot("g_d1", XSPARK_UI_PAD, 369, safety.DailyHaltLatched());
      Text("g_t1", XSPARK_UI_PAD + 11, 366, "DAILY", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Dot("g_d2", XSPARK_UI_PAD + 62, 369, safety.TotalDDKillSwitchLatched());
      Text("g_t2", XSPARK_UI_PAD + 73, 366, "KILL", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Dot("g_d3", XSPARK_UI_PAD + 118, 369, safety.StateRecoveryLatched());
      Text("g_t3", XSPARK_UI_PAD + 129, 366, "STATE", XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);
      Dot("g_d4", XSPARK_UI_PAD + 180, 369, quote_stale);
      Text("g_t4", XSPARK_UI_PAD + 191, 366,
           StringFormat("QUOTE %I64ds", safety.LastQuoteAgeSeconds()),
           XSPARK_UI_TEXT_DIM, 7, XSPARK_UI_FONT_TEXT);

      // ---- footer -------------------------------------------------------
      Text("foot", XSPARK_UI_PAD, 385,
           XSparkDashboardTrim(block_reason, 58),
           severity >= XSPARK_UI_SEV_BLOCKED ? severity_color : XSPARK_UI_TEXT_DIM,
           7, XSPARK_UI_FONT_TEXT);

      // Object property changes are queued; without this the timer-driven refresh is
      // not repainted on a chart that is receiving no ticks.
      ChartRedraw(0);
   }

   // Latest recognized boundary only. Detection is never labelled as a trade.
   void AnnotatePattern(const XSparkScoreBotReport &report)
   {
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
