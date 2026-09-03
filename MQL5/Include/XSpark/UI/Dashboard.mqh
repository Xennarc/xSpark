#ifndef XSPARK_UI_DASHBOARD_MQH
#define XSPARK_UI_DASHBOARD_MQH

#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>

class CXSparkDashboard
{
private:
   bool   m_initialized;
   string m_dashboard_prefix;
   string m_trade_prefix;
   int    m_line_count;

   string LineName(const int index)
   {
      return StringFormat("%sLine_%02d", m_dashboard_prefix, index);
   }

   void EnsureLine(const int index)
   {
      const string name = LineName(index);
      if(ObjectFind(0, name) >= 0)
         return;

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18 + index * 16);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   }

   void SetLine(const int index, const string text, const color line_color = clrWhite)
   {
      EnsureLine(index);
      const string name = LineName(index);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
   }

   string ScoreBar(const double score)
   {
      int filled = (int)MathRound((score / XSPARK_SCOREBOT_MAX_SCORE) * 10.0);
      if(filled < 0)
         filled = 0;
      if(filled > 10)
         filled = 10;

      string bar = "";
      for(int index = 0; index < 10; index++)
         bar += index < filled ? "#" : ".";

      return bar;
   }

public:
   CXSparkDashboard()
   {
      m_initialized = false;
      m_dashboard_prefix = "ScoreBotV3_Dashboard_";
      m_trade_prefix = "ScoreBotV3_Trade_";
      m_line_count = 15;
   }

   void Initialize()
   {
      m_initialized = true;
      for(int index = 0; index < m_line_count; index++)
         EnsureLine(index);
   }

   void Deinitialize()
   {
      for(int index = ObjectsTotal(0) - 1; index >= 0; index--)
      {
         const string name = ObjectName(0, index);
         if(StringFind(name, m_dashboard_prefix) == 0)
            ObjectDelete(0, name);
      }

      m_initialized = false;
   }

   void Update(XSparkScoreBotReport &report,
               CXSparkSafetyManager &safety,
               const double equity,
               const int trades_today,
               const int trades_last_24h,
               const int open_positions,
               const int max_open_positions,
               const string mode,
               const string status,
               const string block_reason)
   {
      if(!m_initialized)
         Initialize();

      const color status_color = status == "KILLSWITCH" || status == "DD HALT" || status == "STATE RECOVERY" ? clrTomato :
                                 status == "ANALYSIS ONLY" || status == "TRADING DISABLED" ? clrGold :
                                 status == "SPREAD BLOCKED" || status == "ATR BLOCKED" ||
                                 status == "SESSION BLOCKED" || status == "STALE QUOTE" ? clrOrange :
                                 clrLimeGreen;

      SetLine(0, "XSpark ScoreBot_v3", clrAqua);
      SetLine(1, StringFormat("Mode: %s | Status: %s", mode, status), status_color);
      SetLine(2, StringFormat("Direction: %s | Pattern: %s",
                              XSparkDirectionName(report.direction),
                              report.pattern_name));
      SetLine(3, StringFormat("Score: %.2f / %.2f  [%s]",
                              report.components.final_score,
                              report.effective_threshold,
                              ScoreBar(report.components.final_score)));
      SetLine(4, StringFormat("TREND %.1f | RSI %.1f | ATR %.1f | S/R %.1f | VOL %.2f | MTF %.1f | SESSION %.1f",
                              report.components.trend,
                              report.components.rsi,
                              report.components.atr,
                              report.components.sr,
                              report.components.volume,
                              report.components.mtf,
                              report.components.session_weight));
      SetLine(5, StringFormat("Pattern %.2f | Raw %.2f | RR %.2f",
                              report.components.pattern,
                              report.components.raw,
                              report.dynamic_rr));
      SetLine(6, StringFormat("ATR14: %.2f pts | ATR50: %.2f pts",
                              report.atr_points,
                              XSparkPriceToCanonicalPoints(report.atr50)));
      SetLine(7, StringFormat("RSI M15 %.2f | RSI H1 %.2f",
                              report.rsi_m15,
                              report.rsi_h1));
      SetLine(8, StringFormat("Risk selected: %.2f%% | Threshold %.2f",
                              report.selected_risk_pct,
                              report.effective_threshold));
      SetLine(9, StringFormat("Equity: %.2f | Daily DD %.2f%% | Total DD %.2f%%",
                              equity,
                              safety.DailyDDPct(),
                              safety.TotalDDPct()));
      SetLine(10, StringFormat("Trades today: %d | Last 24h: %d",
                               trades_today,
                               trades_last_24h));
      SetLine(11, StringFormat("XSpark positions: %d / %d",
                               open_positions,
                               max_open_positions));
      SetLine(12, StringFormat("Signal bar: %s",
                               report.signal_bar_time > 0 ? TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES) : "waiting"));
      SetLine(13, "Last reason: " + block_reason, status_color);
      SetLine(14, StringFormat("Daily halt: %s | Killswitch: %s | State recovery: %s | Quote age: %I64ds/%ds",
                               safety.DailyHaltLatched() ? "ON" : "OFF",
                               safety.TotalDDKillSwitchLatched() ? "ON" : "OFF",
                               safety.StateRecoveryLatched() ? "ON" : "OFF",
                               safety.LastQuoteAgeSeconds(),
                               safety.MaxQuoteAgeSeconds()));
   }

   void AnnotateEntry(XSparkTradePlan &plan, XSparkExecutionResult &result)
   {
      const string base = StringFormat("%s%I64u_%I64d",
                                       m_trade_prefix,
                                       result.deal_ticket,
                                       plan.signal_bar_time);
      const int digits = (int)SymbolInfoInteger(plan.symbol, SYMBOL_DIGITS);
      const color entry_color = plan.direction == XSPARK_SIGNAL_BUY ? clrLimeGreen : clrTomato;
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
      ObjectSetInteger(0, base + "_SL", OBJPROP_COLOR, clrTomato);
      ObjectSetInteger(0, base + "_SL", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, base + "_SL", OBJPROP_TEXT, "Initial SL " + DoubleToString(plan.final_sl, digits));

      ObjectCreate(0, base + "_TP", OBJ_HLINE, 0, 0, plan.final_tp);
      ObjectSetInteger(0, base + "_TP", OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, base + "_TP", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, base + "_TP", OBJPROP_TEXT, "TP " + DoubleToString(plan.final_tp, digits));
   }
};

#endif
