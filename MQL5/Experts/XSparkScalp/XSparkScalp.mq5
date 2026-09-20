#property version     "1.00"
#property description "XSparkScalp Expert Advisor with the TrendScalp session-gated pullback strategy."

#include <XSpark/Core/AutoTune.mqh>
#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/MarketState.mqh>
#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Core/StateStore.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Execution/ExecutionEngine.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Risk/RiskManager.mqh>
#include <XSpark/Risk/AccountExposure.mqh>
#include <XSpark/Strategy/TrendScalp.mqh>
#include <XSpark/Trade/PositionManager.mqh>
#include <XSpark/UI/Dashboard.mqh>

// XSparkScalp runs the TrendScalp strategy through the SAME safety, risk,
// execution, position-management and dashboard components as XSpark and
// XSparkFlow. It is a separate .mq5 with its own Magic Number so all three
// bots can run side by side on one account without ever managing each
// other's positions.
//
// The rule: in an uptrend (the fast average at least a quarter of a typical
// candle above the slow one, and the close above the higher period's slow
// average), buy when a candle dips to the fast average and closes back above
// it in its upper half without running more than one typical candle past it;
// the stop sits a little under that candle and the target is the same
// distance above the entry; shorts are the mirror. Change the chart period to
// change the timeframe the rule runs on - anything from M1 to H1.
//
// THE HONEST FRAMING, carried by every document and journal line: the exit
// geometry (target at or below the stop) sets the win rate a trade with NO
// edge would show - about 47% at a 1:1 target with a 6% cost share - and the
// trend-pullback entry is the only possible source of edge and it is
// unmeasured. Nothing here is a profitability claim. A scalper is a COST
// problem first, so the one journal line an operator must read before funding
// is the COST line printed after calibration, followed by the minimum-lot line.
//
// Setup guide and settings: docs/STRATEGY_TRENDSCALP.md.

// WHAT YOU ACTUALLY CHOOSE, and why there is so little of it.
//
// A setting earns its place here only if you know something the code does not.
// You know your account, your appetite for risk, what your broker charges per
// lot and how its clock is set, and which sessions you want to be in. You do
// not know - and could not reasonably work out - how far the stop should sit
// beyond the signal candle in multiples of the typical candle, or how large a
// share of the stop the spread may be. Those are not settings; they are fixed,
// with a sentence each in the strategy header saying why.
//
// Everything the bot needs to know about THIS market - how wide the spread may
// be, how much the price may drift while an order travels - it measures from
// the instrument's own recent range when it starts, and again every broker
// day. There is nothing to tune per symbol, and no way to get it wrong.
input group "01. Start here"
input bool   InpScalpEnableTrading = false;      // Place real trades (off = watch and log only)
input double InpScalpRiskPct = 1.0;              // Money risked on one trade (% of your balance)
input EXSparkScalpSessions InpScalpSessions = XSPARK_SCALP_SESSIONS_ALL; // Which trading sessions to trade
input int    InpScalpBrokerUtcOffset = 0;        // Broker clock offset from UTC in hours (Exness uses 0)

// THE COST THE BROKER CHARGES PER LOT. A scalp's stop is one typical candle,
// so the spread plus the commission is a large share of what the trade can
// win. The commission feeds the cost floor on the stop, and it is verified
// against what the broker actually charged on every closed trade: an
// understated figure blocks new entries until it is corrected.
input group "02. Your broker's costs"
input double InpScalpCommissionPerLot = 0.0;     // Commission per 1.0 lot, both ways, in account money (0 = none)

// HOW AN OPEN TRADE IS HANDLED. One question, asked once. Every trade sees the
// same exits: a broker-side stop and target sent with the order, a time stop,
// the session-end flatten, and the weekend close. No trailing, no partials.
input group "03. How an open trade is handled"
input EXSparkScalpExitStyle InpScalpExitStyle = XSPARK_SCALP_EXIT_EVEN; // Where the target sits

// SMALL ACCOUNTS. On a $100 balance the broker's smallest trade usually risks
// more than the risk percentage allows, so every signal would be refused. This
// cap lets the smallest trade through when the money it risks is at or below
// the cap. A cap at or below the risk percentage means "never raise".
input group "04. Small accounts"
input double InpScalpMinLotRiskCapPct = 3.0;     // Smallest trade may risk up to this % (0 = never exceed risk %)

// THE DAILY LOSS LIMIT. A percentage of your account balance. Reaching it
// pauses new entries for the rest of the broker day; open trades keep being
// managed, and the next broker day starts clean.
input group "05. Daily loss limit"
input double InpScalpMaxDailyDDPct = 6.0;        // Stop opening trades if the account falls this much today

// THE EMERGENCY STOP. A separate, harsher control: it closes every trade this
// bot owns and refuses to open another until you clear it deliberately.
//
// It is a switch rather than a level of zero because switching it off and
// setting it back on must not make you retype the level you had. Off stops
// it from firing; it does not undo one that has already fired.
input group "06. Emergency stop - off means the level below is ignored"
input bool   InpScalpUseTotalDDKillSwitch = true; // Emergency stop: close everything on a big account fall
input double InpScalpMaxTotalDDPct = 20.0;       // Account fall that sets off the emergency stop (%)

input group "07. Advanced - rarely touched"
input ulong  InpScalpMagicNumber = XSPARK_TRENDSCALP_MAGIC_DEFAULT; // This bot's ID tag - a different one per chart
input bool   InpScalpVerboseLog = false;         // Write detailed logs (for troubleshooting)
input bool   InpScalpClearKillswitchLatch = false; // Clear the emergency stop once, then set back to false

// The panel's placement and size. Presentation, not strategy: an operator who
// wants it elsewhere can drag the chart, and four inputs to move a box is four
// inputs that are not about trading.
#define XSPARK_SCALP_PANEL_CORNER CORNER_LEFT_UPPER
#define XSPARK_SCALP_PANEL_MARGIN_X 12
#define XSPARK_SCALP_PANEL_MARGIN_Y 18
#define XSPARK_SCALP_PANEL_SIZE_PCT 125

// How often the "state still inconsistent" line repeats while recovery is
// active: often enough to be seen, rarely enough not to bury the journal.
#define XSPARK_SCALP_STATE_RECOVERY_LOG_INTERVAL_SECONDS 30

// How often the live broker clock is compared with the configured UTC offset.
// Hourly catches a DST change on the broker's side within the hour it happens,
// and the comparison is two clock reads, so it costs nothing to repeat.
#define XSPARK_SCALP_OFFSET_CHECK_INTERVAL_SECONDS 3600

// The per-server-day funnel: one counter per terminal verdict a closed candle
// can reach, so a tester run shows where signals die. Fourteen stages: the six
// rule verdicts, the five gate statuses, SIGNAL, ENTERED, and OTHER for every
// remaining path so the counts always add up to the candles evaluated.
#define XSPARK_SCALP_FUNNEL_STAGES 14

CXSparkLogger          g_logger;
CXSparkMarketState     g_market_state;
CXSparkIndicatorCache  g_indicator_cache;
CXSparkSafetyManager   g_safety_manager;
CXSparkRiskManager     g_risk_manager;
CXSparkPositionSizer   g_position_sizer;
CXSparkExecutionEngine g_execution_engine;
CXSparkPositionManager g_position_manager;
CXSparkTrendScalp      g_strategy;
CXSparkDashboard       g_dashboard;

bool     g_state_purged = false;
ENUM_TIMEFRAMES g_base_timeframe = PERIOD_M5;
ENUM_TIMEFRAMES g_higher_timeframe = PERIOD_M30;

double g_score_point_size = XSPARK_XAUUSD_SCORE_POINT_SIZE;
bool   g_score_point_size_conforms = false;
string g_score_point_size_reason = "Strategy point size has not been resolved.";

bool   g_entry_drift_bound_usable = false;
string g_entry_drift_bound_reason = "Entry drift bound has not been evaluated.";

// The calibration and the broker day it was made on. It re-runs on the first
// closed candle of every new broker day, so the thresholds track the market
// the bot is actually in rather than the week it was attached.
bool   g_auto_tune_complete = false;
XSparkAutoTuneResult g_auto_tune;
int    g_calibration_day_id = 0;
int    g_calibration_warn_day_id = 0;
int    g_scalp_calibration_bars = XSPARK_AUTOTUNE_SAMPLE_BARS;

bool   g_config_valid = false;
string g_config_reason = "TrendScalp configuration has not been checked.";

int g_tester_sequence = 0;

datetime g_current_base_bar_time = 0;
datetime g_last_evaluated_signal_bar_time = 0;
double   g_latest_closed_atr14 = 0.0;
datetime g_bar_state_time = 0;

// The rule's geometry, held here as well as inside the strategy because the
// EA bounds the stop against the live quote and the cost floor at planning
// time, and that arithmetic reads the same numbers the rule was configured
// with.
XSparkTrendScalpConfig g_scalp_config;

// The stop floor the whole calibration is measured against. Seeded from the
// strategy's own constant so it is never zero, and re-read from the validated
// config in OnInit so the two can never disagree.
double g_scalp_min_stop_atr_mult = XSPARK_TRENDSCALP_MIN_STOP_ATR;

// The numbers the EA actually runs with. They are what the operator typed
// unless XSparkTrendScalpResolveLimits had to correct it, and every consumer
// below reads these rather than the raw inputs - so a corrected value is
// corrected everywhere, not just where someone remembered.
double g_scalp_risk_pct = XSPARK_TRENDSCALP_DEFAULT_RISK_PCT;
double g_scalp_min_lot_cap_pct = XSPARK_TRENDSCALP_DEFAULT_MIN_LOT_RISK_CAP_PCT;
double g_scalp_daily_dd_pct = XSPARK_TRENDSCALP_DEFAULT_DAILY_DD_PCT;
double g_scalp_total_dd_pct = XSPARK_TRENDSCALP_DEFAULT_TOTAL_DD_PCT;
bool   g_scalp_use_killswitch = true;
double g_scalp_commission_per_lot = XSPARK_TRENDSCALP_DEFAULT_COMMISSION_PER_LOT;
int    g_scalp_utc_offset = XSPARK_TRENDSCALP_DEFAULT_UTC_OFFSET;

// The target the exit style implies and the session window the choice
// implies, both resolved once in OnInit from their pure resolvers.
double g_scalp_target_r = XSPARK_TRENDSCALP_TARGET_R_EVEN;
int    g_scalp_session_start_seconds = 0;
int    g_scalp_session_end_seconds = 0;

// When this instrument's weekend starts, read from the instrument. Resolved
// once in OnInit and seeded with the fallback so a path that somehow reached
// OnTick first would still close early rather than carry the gap.
bool g_scalp_use_weekend_close = true;
int  g_scalp_weekend_close_hour = XSPARK_TRENDSCALP_WEEKEND_CLOSE_HOUR;
int  g_scalp_weekend_close_minute = XSPARK_TRENDSCALP_WEEKEND_CLOSE_MINUTE;

// The live clock check. The offset is an input because the tester cannot
// measure it; live it can be, so a mismatch blocks entries until the two
// agree. Starts as "agrees" because the first comparison happens on the first
// tick, and a bot that could not yet measure has no evidence of a mismatch.
bool     g_clock_offset_ok = true;
string   g_clock_offset_reason = "";
datetime g_last_offset_check_time = 0;

// The commission verification latch. Set when a closed trade's measured
// commission exceeds the declared one by more than the tolerance; only a
// restart with a corrected input clears it, because the declared number feeds
// the cost floor and every entry taken on an understated cost was admitted on
// arithmetic that was wrong.
bool   g_commission_understated = false;
string g_commission_reason = "";
long   g_last_commission_identifier = 0;

// Where the last closed candle's evaluation ended, for the funnel. Empty when
// the candle was not evaluated at all (already seen, or data unavailable).
string g_funnel_stage = "";
string g_funnel_names[XSPARK_SCALP_FUNNEL_STAGES];
int    g_funnel_counts[XSPARK_SCALP_FUNNEL_STAGES];
int    g_funnel_day_id = 0;

// Set by the plan when the refusal came from the cost floor rather than from
// the candle, so the status can say COST BLOCKED rather than SCANNING.
bool g_plan_cost_refusal = false;

string g_ui_decision_status = "", g_ui_decision_reason = "";
string g_ui_entry_style = "Trend pullback scalp";
string   g_status = "SCANNING";
string   g_last_block_reason = "Waiting for the next closed candle.";
long     g_state_recovery_position_id = 0;
datetime g_state_recovery_signal_bar_time = 0;
datetime g_state_recovery_last_log_time = 0;
XSparkScoreBotReport g_last_report;

string XSparkScalpBoolToString(const bool value)
{
   return value ? "true" : "false";
}

string XSparkScalpDeinitReasonToString(const int reason)
{
   switch(reason)
   {
      case REASON_PROGRAM:     return "program requested removal";
      case REASON_REMOVE:      return "removed from chart";
      case REASON_RECOMPILE:   return "recompiled";
      case REASON_CHARTCHANGE: return "chart symbol or period changed";
      case REASON_CHARTCLOSE:  return "chart closed";
      case REASON_PARAMETERS:  return "input parameters changed";
      case REASON_ACCOUNT:     return "account changed";
      case REASON_TEMPLATE:    return "template applied";
      case REASON_INITFAILED:  return "initialization failed";
      case REASON_CLOSE:       return "terminal closed";
      default:                 return "unknown";
   }
}

// The tick value a loss is settled at, with the plain tick value as the
// fallback the sizer and the account cap both use, so every cost figure in
// the journal is measured in the same units the sizer measures risk in.
double XSparkScalpTickValue()
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   return tick_value;
}

// ---------------------------------------------------------------------------
// The per-server-day funnel.
// ---------------------------------------------------------------------------

void XSparkScalpResetFunnel()
{
   g_funnel_names[0] = "NO TREND";
   g_funnel_names[1] = "BIAS CONFLICT";
   g_funnel_names[2] = "NO TOUCH";
   g_funnel_names[3] = "NOT RECLAIMED";
   g_funnel_names[4] = "WEAK CLOSE";
   g_funnel_names[5] = "OVEREXTENDED";
   g_funnel_names[6] = "ATR BLOCKED";
   g_funnel_names[7] = "SESSION BLOCKED";
   g_funnel_names[8] = "SPREAD BLOCKED";
   g_funnel_names[9] = "COST BLOCKED";
   g_funnel_names[10] = "DAILY CAP";
   g_funnel_names[11] = "SIGNAL";
   g_funnel_names[12] = "ENTERED";
   g_funnel_names[13] = "OTHER";

   for(int index = 0; index < XSPARK_SCALP_FUNNEL_STAGES; index++)
      g_funnel_counts[index] = 0;
}

// A stage that is not one of the named ones lands in OTHER, so a new refusal
// path can never make a candle disappear from the day's total.
void XSparkScalpCountFunnelStage(const string stage)
{
   if(stage == "")
      return;

   for(int index = 0; index < XSPARK_SCALP_FUNNEL_STAGES; index++)
   {
      if(g_funnel_names[index] == stage)
      {
         g_funnel_counts[index]++;
         return;
      }
   }

   g_funnel_counts[XSPARK_SCALP_FUNNEL_STAGES - 1]++;
}

void XSparkScalpLogFunnel(const int day_id, const string occasion)
{
   string line = StringFormat("Funnel for broker day %d (%s):", day_id, occasion);

   for(int index = 0; index < XSPARK_SCALP_FUNNEL_STAGES; index++)
      line += StringFormat(" %s=%d", g_funnel_names[index], g_funnel_counts[index]);

   g_logger.Info("Funnel", line);
}

// ---------------------------------------------------------------------------
// Inputs.
// ---------------------------------------------------------------------------

bool XSparkScalpValidateInputs()
{
   string timeframe_reason = "";
   if(!XSparkTrendScalpHigherTimeframeFor((ENUM_TIMEFRAMES)Period(), g_higher_timeframe, timeframe_reason))
   {
      g_logger.Critical("EA", timeframe_reason);
      return false;
   }

   g_base_timeframe = (ENUM_TIMEFRAMES)Period();

   // The calibration sample and the time stop both scale with the chart
   // period; a period whose length cannot be read is one the table above
   // should already have refused, and it is refused here too rather than run
   // on a zero sample.
   g_scalp_calibration_bars = XSparkTrendScalpCalibrationBars(PeriodSeconds(g_base_timeframe));
   if(g_scalp_calibration_bars <= 0 || XSparkTrendScalpMaxHoldSeconds(PeriodSeconds(g_base_timeframe)) <= 0)
   {
      g_logger.Critical("EA", "The chart period's length could not be read, so neither the calibration sample nor the time stop can be sized.");
      return false;
   }

   // Zero and another shipped strategy's number are both refused: an EA that
   // adopts a Magic Number already claimed by a different bot manages that
   // bot's positions, which defeats every separation XSpark relies on.
   string magic_reason = "";
   if(!XSparkMagicIsAvailable(InpScalpMagicNumber, XSPARK_TRENDSCALP_MAGIC_DEFAULT, magic_reason))
   {
      g_logger.Critical("EA", magic_reason);
      return false;
   }

   // Same reason as XSpark: per-position stops, a per-position state store and
   // a per-ticket time stop all assume one broker position per entry. Netting
   // merges them and defeats every one of those.
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_logger.Critical("EA", "XSparkScalp requires a hedging account; netting merges positions and defeats per-position management.");
      return false;
   }

   // A NUMBER THE OPERATOR TYPED IS NEVER A REASON TO REFUSE TO START.
   //
   // Everything above this line is a fact about the account or the chart that
   // no fallback can repair. A percentage outside its range is not. Returning
   // false here returns INIT_FAILED, and OnTick then never runs - so the time
   // stop, the session flatten, the weekend close and the killswitch flatten
   // all stop while live positions sit open at the broker. ADR-020 decided
   // that trade-off once already. The resolver corrects, says what it
   // corrected at CRITICAL, and lets the EA run.
   g_scalp_risk_pct = InpScalpRiskPct;
   g_scalp_min_lot_cap_pct = InpScalpMinLotRiskCapPct;
   g_scalp_daily_dd_pct = InpScalpMaxDailyDDPct;
   g_scalp_total_dd_pct = InpScalpMaxTotalDDPct;
   g_scalp_use_killswitch = InpScalpUseTotalDDKillSwitch;
   g_scalp_commission_per_lot = InpScalpCommissionPerLot;
   g_scalp_utc_offset = InpScalpBrokerUtcOffset;

   string limit_corrections = "";
   if(!XSparkTrendScalpResolveLimits(InpScalpRiskPct,
                                     InpScalpMinLotRiskCapPct,
                                     InpScalpMaxDailyDDPct,
                                     InpScalpMaxTotalDDPct,
                                     InpScalpUseTotalDDKillSwitch,
                                     InpScalpCommissionPerLot,
                                     InpScalpBrokerUtcOffset,
                                     g_scalp_risk_pct,
                                     g_scalp_min_lot_cap_pct,
                                     g_scalp_daily_dd_pct,
                                     g_scalp_total_dd_pct,
                                     g_scalp_use_killswitch,
                                     g_scalp_commission_per_lot,
                                     g_scalp_utc_offset,
                                     limit_corrections))
      g_logger.Critical("EA",
                        "Settings were corrected so the bot could start. " + limit_corrections +
                        "Fix them in Inputs so this does not repeat.");

   return true;
}

// Reads this symbol's own trading sessions and resolves when to flatten.
//
// The terminal call lives here and the decision lives in TrendScalp.mqh,
// which is what lets every branch of the decision be tested without a trade
// server. The RAW session end in seconds is handed over, so a session ending
// at 24:00 (reported as 86400) flattens at 23:00 with the one-hour lead
// rather than at 00:00 Friday. Session data that cannot be read is not an
// error: the pure function falls back to closing early, which is the safe
// direction.
void XSparkScalpResolveWeekendClose()
{
   datetime session_from = 0;
   datetime session_to = 0;

   // The last Friday session is the one that matters; a symbol may report
   // several with a break between them.
   bool friday_known = false;
   int friday_end_seconds = 0;

   for(uint index = 0; index < 8; index++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, FRIDAY, index, session_from, session_to))
         break;

      friday_known = true;
      friday_end_seconds = (int)session_to;
   }

   // A symbol that trades on either weekend day has no weekend gap to protect
   // against, so flattening for it would close a position for no reason.
   const bool trades_at_weekend =
      SymbolInfoSessionTrade(_Symbol, SATURDAY, 0, session_from, session_to) ||
      SymbolInfoSessionTrade(_Symbol, SUNDAY, 0, session_from, session_to);

   string weekend_reason = "";
   XSparkTrendScalpWeekendClose(trades_at_weekend,
                                friday_known,
                                friday_end_seconds,
                                g_scalp_use_weekend_close,
                                g_scalp_weekend_close_hour,
                                g_scalp_weekend_close_minute,
                                weekend_reason);

   g_logger.Info("TrendScalp", weekend_reason);
}

// Resolves the strategy point size for the chart symbol. Identical policy to
// XSpark: an untrusted size blocks new entries but never stops OnTick, because
// stopping OnTick would abandon the time stop of a live position.
void XSparkScalpResolveSessionScorePointSize()
{
   double resolved = 0.0;
   string resolve_reason = "";
   const bool resolve_ok = XSparkResolveScorePointSize(_Symbol, resolved, resolve_reason);
   const bool is_xauusd = XSparkIsXauUsdSymbol(_Symbol);

   string select_reason = "";
   const bool trusted = XSparkSelectOperatingPointSize(is_xauusd,
                                                       resolve_ok,
                                                       resolved,
                                                       SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                                       g_score_point_size,
                                                       g_score_point_size_conforms,
                                                       select_reason);

   g_score_point_size_reason = select_reason;

   if(trusted)
   {
      g_logger.Info("EA",
                    StringFormat("Strategy point size for %s resolved to %s. %s",
                                 _Symbol,
                                 DoubleToString(g_score_point_size, 10),
                                 select_reason));
      return;
   }

   g_logger.Critical("EA",
                     StringFormat("Strategy point size is not trusted for %s: %s New entries are blocked; "
                                  "protective management of existing positions continues.",
                                  _Symbol,
                                  select_reason));
}

string XSparkScalpStatusFromSafety()
{
   if(g_safety_manager.TotalDDKillSwitchLatched())
      return "KILLSWITCH";

   if(g_safety_manager.StateRecoveryLatched())
      return "STATE RECOVERY";

   if(!g_safety_manager.ScorePointSizeConforms())
      return "POINT SIZE FAULT";

   if(!g_safety_manager.EntryDriftBoundUsable())
      return "DRIFT GATE FAULT";

   if(g_safety_manager.DailyHaltLatched())
      return "DD HALT";

   const string reason = g_safety_manager.LastReason();

   if(StringFind(reason, "Trading disabled") >= 0)
      return "TRADING DISABLED";

   if(StringFind(reason, "Spread") >= 0)
      return "SPREAD BLOCKED";

   if(StringFind(reason, "Stale quote") >= 0)
      return "STALE QUOTE";

   return "SCANNING";
}

void XSparkScalpUpdateDashboard()
{
   if(!g_dashboard.NeedsRefresh()) return;
   const string mode = InpScalpEnableTrading ? "TRADING" : "ANALYSIS ONLY";
   XSparkDashboardLive live;
   live.symbol = _Symbol; live.timeframe = EnumToString(g_base_timeframe);
   StringReplace(live.timeframe, "PERIOD_", "");
   live.currency = AccountInfoString(ACCOUNT_CURRENCY); live.entry_style = g_ui_entry_style;
   live.digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   live.connected = TerminalInfoInteger(TERMINAL_CONNECTED) != 0;
   live.animate = true; live.bid = 0; live.ask = 0; live.quote_age = -1; live.quote_stamp = 0;
   MqlTick tick;
   live.quote_valid = SymbolInfoTick(_Symbol, tick) && tick.time > 0 &&
                      MathIsValidNumber(tick.bid) && MathIsValidNumber(tick.ask) && tick.bid > 0 && tick.ask >= tick.bid;
   datetime now = TimeTradeServer(); if(now == 0) now = TimeCurrent();
   if(live.quote_valid)
   {
      live.bid = tick.bid; live.ask = tick.ask; live.quote_stamp = tick.time_msc;
      live.quote_age = now >= tick.time ? (long)(now - tick.time) : -1;
   }
   live.bar_seconds = PeriodSeconds(g_base_timeframe);
   live.seconds_to_close = XSparkDashboardSecondsLeft(now, iTime(_Symbol, g_base_timeframe, 0), live.bar_seconds);
   live.position_count = 0; live.open_profit = 0; live.positions_valid = true;
   for(int i = 0; i < 3; i++) { live.positions[i] = ""; live.position_profit[i] = 0; }
   for(int i = 0; i < PositionsTotal(); i++)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) { live.positions_valid = false; continue; }
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpScalpMagicNumber) continue;
      const double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      live.open_profit += profit;
      if(live.position_count < 3)
      {
         const string side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
         const int volume_digits = XSparkVolumeDigitsFromStep(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
         live.positions[live.position_count] = StringFormat("#%I64u  %s  %s lots", ticket, side,
                                                          DoubleToString(PositionGetDouble(POSITION_VOLUME), volume_digits));
         live.position_profit[live.position_count] = profit;
      }
      live.position_count++;
   }

   const bool show_entry_decision = g_status == "MANAGING" && g_ui_decision_status != "";
   string dashboard_status = show_entry_decision ? g_ui_decision_status : g_status;
   string dashboard_reason = show_entry_decision ? g_ui_decision_reason : g_last_block_reason;
   if(dashboard_status == "MANAGING" && live.positions_valid && live.position_count == 0)
   { dashboard_status = "SCANNING"; dashboard_reason = "Waiting for the next closed candle."; }

   const int unmanaged = g_position_manager.UnmanagedPositionCount();
   if(unmanaged > 0 && !g_safety_manager.TotalDDKillSwitchLatched())
   {
      dashboard_status = "UNMANAGED EXPOSURE";
      dashboard_reason = StringFormat("%d of %d XSparkScalp position(s) have no trustworthy entry risk; the time stop is off for them.",
                                      unmanaged,
                                      g_position_manager.ManagedPositionCount());
   }
   if(g_safety_manager.TotalDDKillSwitchLatched())
   { dashboard_status = "KILLSWITCH"; dashboard_reason = "Total DD killswitch is latched."; }
   else if(g_safety_manager.StateRecoveryLatched())
   { dashboard_status = "STATE RECOVERY"; dashboard_reason = g_safety_manager.StateRecoveryReason(); }
   else if(unmanaged > 0) { /* Keep the detailed unmanaged-position notice above. */ }
   else if(!g_config_valid)
   { dashboard_status = "CONFIG BLOCKED"; dashboard_reason = g_config_reason; }
   else if(g_commission_understated)
   { dashboard_status = "CONFIG BLOCKED"; dashboard_reason = g_commission_reason; }
   else if(!g_clock_offset_ok)
   { dashboard_status = "CLOCK OFFSET"; dashboard_reason = g_clock_offset_reason; }
   else if(!g_safety_manager.ScorePointSizeConforms())
   { dashboard_status = "POINT SIZE FAULT"; dashboard_reason = "Instrument price units are not trusted."; }
   else if(!g_safety_manager.EntryDriftBoundUsable() && g_auto_tune_complete)
   { dashboard_status = "DRIFT GATE FAULT"; dashboard_reason = "Entry price tolerance cannot safely bound risk."; }
   else if(g_safety_manager.DailyHaltLatched())
   { dashboard_status = "DD HALT"; dashboard_reason = "Daily DD halt is latched for the broker day."; }
   else if(!live.connected)
   { dashboard_status = "DISCONNECTED"; dashboard_reason = "Terminal is not connected."; }
   else if(!live.quote_valid || live.quote_age < 0 || live.quote_age > XSPARK_TRENDSCALP_MAX_QUOTE_AGE_SECONDS)
   { dashboard_status = "STALE QUOTE"; dashboard_reason = "Waiting for fresh broker prices."; }
   else if(!live.positions_valid)
   { dashboard_status = "STATE RECOVERY"; dashboard_reason = "Cannot read the broker position snapshot."; }
   else if(InpScalpEnableTrading && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
   { dashboard_status = "TRADING PERMISSION"; dashboard_reason = "Terminal trading is not allowed."; }
   else if(!InpScalpEnableTrading)
   { dashboard_status = "TRADING DISABLED"; dashboard_reason = "Trading disabled by input."; }

   g_dashboard.Update(g_last_report,
                      g_safety_manager,
                      AccountInfoDouble(ACCOUNT_EQUITY),
                      g_position_manager.TradesToday(),
                      g_position_manager.TradesLast24Hours(),
                      g_position_manager.ManagedPositionCount(),
                      XSPARK_TRENDSCALP_MAX_OPEN_TRADES,
                      XSparkPriceToScorePoints(g_market_state.SpreadPrice(), g_score_point_size),
                      mode,
                      dashboard_status,
                      dashboard_reason, live);
}

// Machine-greppable record of a candle that did NOT become a trade. Emitted at
// most once per closed bar, so it cannot flood.
void XSparkScalpLogSignalRejection(const string stage,
                                   const string reason,
                                   const XSparkScoreBotReport &report)
{
   g_logger.Info("Rejected",
                 StringFormat("bar=%s stage=%s dir=%s O=%.8f H=%.8f L=%.8f C=%.8f atr=%.8f anchor=%.8f balance=%.2f reason=%s",
                              TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              stage,
                              XSparkDirectionName(report.direction),
                              report.context.bar1_open,
                              report.context.bar1_high,
                              report.context.bar1_low,
                              report.context.bar1_close,
                              report.atr14,
                              report.detected_level,
                              AccountInfoDouble(ACCOUNT_BALANCE),
                              reason));
}

void XSparkScalpVerboseBlock(const string component, const string reason)
{
   if(InpScalpVerboseLog)
      g_logger.Debug(component, reason);
}

// ---------------------------------------------------------------------------
// Planning.
// ---------------------------------------------------------------------------

// The planning-time take-profit price, from the reward ratio the signal
// carries and the stop distance measured from the ENTRY reference - the price
// the position is actually opened at. The execution engine re-derives the
// target at send time from the same ratio and the stop distance it actually
// gets; this value exists to be checked against the broker's stop level before
// the order is built, and to be shown to the operator.
bool XSparkScalpApplyPlanTarget(XSparkTradePlan &plan)
{
   plan.final_tp = 0.0;

   const double target = XSparkTargetFromRiskDistance(plan.direction,
                                                      plan.entry_reference,
                                                      plan.risk_distance,
                                                      plan.dynamic_rr);
   if(target <= 0.0)
   {
      g_last_block_reason = "The take-profit target could not be derived from the stop distance.";
      return false;
   }

   plan.final_tp = XSparkNormalizePrice(plan.symbol, target);
   return true;
}

// Turns a TrendScalp signal into a fundable, broker-valid plan.
//
// The strategy hands over the RAW candle anchor. The stop that decides the
// volume is bounded here, against the live quote and the round-trip cost,
// because the entry reference is the price the position is opened at and the
// cost floor is only meaningful measured from the fill. Broker stop-level
// checks use the CLOSE-SIDE price (the bid for a long, the ask for a short),
// exactly as the engine's send-time revalidation does, so planning refuses
// what send would refuse; the risk distance and the target stay anchored on
// the entry reference.
bool XSparkScalpPrepareTradePlan(XSparkSignal &signal,
                                 const double risk_pct,
                                 const double round_trip_cost,
                                 XSparkTradePlan &plan)
{
   XSparkResetTradePlan(plan);
   g_plan_cost_refusal = false;

   if(signal.direction == XSPARK_SIGNAL_NONE)
   {
      g_last_block_reason = "Cannot prepare a trade plan for a NONE signal.";
      return false;
   }

   const double entry_reference = signal.direction == XSPARK_SIGNAL_BUY ?
                                  g_market_state.Ask() :
                                  g_market_state.Bid();
   const double close_side_reference = signal.direction == XSPARK_SIGNAL_BUY ?
                                       g_market_state.Bid() :
                                       g_market_state.Ask();

   if(entry_reference <= 0.0 || close_side_reference <= 0.0 || signal.desired_stop <= 0.0)
   {
      g_last_block_reason = "Entry reference, close-side reference or candle anchor is invalid.";
      return false;
   }

   if(!MathIsValidNumber(signal.dynamic_rr) || signal.dynamic_rr <= 0.0)
   {
      g_last_block_reason = "A scalp needs a target and the signal carries none.";
      return false;
   }

   double bounded_stop = 0.0;
   double bounded_distance = 0.0;
   string bound_reason = "";
   if(!XSparkTrendScalpStop(signal.direction,
                            entry_reference,
                            signal.desired_stop,
                            signal.atr14,
                            round_trip_cost,
                            g_scalp_config,
                            bounded_stop,
                            bounded_distance,
                            bound_reason))
   {
      // The pure function prefixes a cost-floor refusal so the status can
      // name the cost rather than the candle.
      g_plan_cost_refusal = StringFind(bound_reason, "COST:") == 0;
      g_last_block_reason = bound_reason;
      return false;
   }

   double adjusted_sl = 0.0;
   double ignored_tp = 0.0;
   string adjust_reason = "";

   if(!XSparkAdjustProtectionLevels(signal.symbol,
                                    signal.direction,
                                    close_side_reference,
                                    bounded_stop,
                                    0.0,
                                    true,
                                    adjusted_sl,
                                    ignored_tp,
                                    adjust_reason))
   {
      g_last_block_reason = adjust_reason;
      return false;
   }

   if(adjust_reason != "")
      XSparkScalpVerboseBlock("ExecutionEngine", adjust_reason);

   double risk_distance = XSparkRiskDistance(signal.direction, entry_reference, adjusted_sl);
   if(risk_distance <= 0.0)
   {
      g_last_block_reason = "Adjusted stop is not on the protective side of the entry reference.";
      return false;
   }

   double volume = 0.0;
   if(!g_position_sizer.CalculateVolume(signal.symbol,
                                        risk_pct,
                                        entry_reference,
                                        adjusted_sl,
                                        volume))
   {
      g_last_block_reason = g_position_sizer.LastReason();
      return false;
   }

   plan.context = signal.context;
   plan.symbol = signal.symbol;
   plan.direction = signal.direction;
   plan.signal_bar_time = signal.signal_bar_time;
   plan.entry_reference = XSparkNormalizePrice(signal.symbol, entry_reference);
   // Execution re-derives the stop from theoretical_sl at send time, so it holds
   // the BOUNDED stop rather than the raw candle anchor: a floor applied only at
   // planning time would be silently discarded on the send path.
   plan.theoretical_sl = XSparkNormalizePrice(signal.symbol, bounded_stop);
   plan.final_sl = XSparkNormalizePrice(signal.symbol, adjusted_sl);
   plan.risk_distance = risk_distance;
   // The ratio the engine re-derives the take-profit from at send time.
   plan.dynamic_rr = signal.dynamic_rr;
   plan.score = signal.score;
   plan.effective_threshold = signal.effective_threshold;
   plan.risk_pct = risk_pct;
   plan.volume = volume;
   plan.pattern_score = signal.pattern_score;
   plan.session_weight = signal.session_weight;
   plan.pattern_id = (EXSparkScoreBotPatternId)signal.pattern_id;
   plan.pattern_name = signal.pattern_name;

   if(!XSparkScalpApplyPlanTarget(plan))
      return false;

   double final_sl = 0.0;
   double final_tp = 0.0;
   string final_adjust_reason = "";

   if(!XSparkAdjustProtectionLevels(plan.symbol,
                                    plan.direction,
                                    close_side_reference,
                                    plan.final_sl,
                                    plan.final_tp,
                                    true,
                                    final_sl,
                                    final_tp,
                                    final_adjust_reason))
   {
      g_last_block_reason = final_adjust_reason;
      return false;
   }

   // Broker stop-level validation can move the stop once, which changes the
   // real stop distance and therefore the volume and the target. One bounded
   // recalculation, then the result must be stable or the entry is refused.
   if(MathAbs(final_sl - plan.final_sl) > XSPARK_PRICE_EPSILON)
   {
      plan.final_sl = final_sl;
      plan.risk_distance = XSparkRiskDistance(plan.direction, plan.entry_reference, plan.final_sl);

      if(plan.risk_distance <= 0.0)
      {
         g_last_block_reason = "Broker-adjusted stop is not on the protective side of the entry reference.";
         return false;
      }

      // The target is a multiple of the stop distance, so a stop the broker moved
      // is a target that moved with it. Re-derived rather than carried forward.
      if(!XSparkScalpApplyPlanTarget(plan))
         return false;

      if(!g_position_sizer.CalculateVolume(signal.symbol,
                                           risk_pct,
                                           plan.entry_reference,
                                           plan.final_sl,
                                           volume))
      {
         g_last_block_reason = g_position_sizer.LastReason();
         return false;
      }

      plan.volume = volume;

      if(!XSparkAdjustProtectionLevels(plan.symbol,
                                       plan.direction,
                                       close_side_reference,
                                       plan.final_sl,
                                       plan.final_tp,
                                       true,
                                       final_sl,
                                       final_tp,
                                       final_adjust_reason))
      {
         g_last_block_reason = final_adjust_reason;
         return false;
      }

      if(MathAbs(final_sl - plan.final_sl) > XSPARK_PRICE_EPSILON)
      {
         g_last_block_reason = "Stop-level validation remained unstable after risk recalculation.";
         return false;
      }
   }

   if(final_tp <= 0.0)
   {
      g_last_block_reason = "A take-profit target is required but protection validation produced none.";
      return false;
   }

   // The broker-valid target, which stop-level validation may have pushed
   // further out than the requested distance. The engine re-derives and
   // re-validates it against the refreshed quote before the order is sent; this
   // is what the panel and the journal report in the meantime.
   plan.final_tp = final_tp;

   // Judge the target HERE as well as at send time. The execution engine marks
   // the signal bar as consumed before its first send attempt, so a target the
   // engine would refuse discards that candle entirely; refusing it at planning
   // time costs the same trade and leaves a reason on the panel instead. The
   // band is narrow because on a scalp a quarter of the target is the whole
   // difference between the two exit styles.
   const double planned_rr = plan.risk_distance > 0.0
                             ? MathAbs(plan.final_tp - plan.entry_reference) / plan.risk_distance
                             : 0.0;

   if(planned_rr < plan.dynamic_rr * XSPARK_TRENDSCALP_TARGET_BAND_LOW_MULT - 0.0000001 ||
      planned_rr > plan.dynamic_rr * XSPARK_TRENDSCALP_TARGET_BAND_HIGH_MULT + 0.0000001)
   {
      g_last_block_reason = StringFormat("Broker-valid target is %.2f times the amount risked; the plan asks for %.2f and %.2f-%.2f is accepted.",
                                         planned_rr,
                                         plan.dynamic_rr,
                                         plan.dynamic_rr * XSPARK_TRENDSCALP_TARGET_BAND_LOW_MULT,
                                         plan.dynamic_rr * XSPARK_TRENDSCALP_TARGET_BAND_HIGH_MULT);
      return false;
   }

   return true;
}

// The confirmed entry with the risk it ACTUALLY carries: the sizer's last
// figure is the send-time one, because the engine sizes through the same
// instance, and on a small account it can be above the budget when the
// broker's minimum lot was taken.
void XSparkScalpLogEntry(XSparkTradePlan &plan,
                         XSparkExecutionResult &result,
                         const bool registered_exactly)
{
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   const double actual_risk_cash = g_position_sizer.LastActualRiskCash();
   const double actual_risk_pct = balance > 0.0 ? actual_risk_cash / balance * 100.0 : 0.0;

   g_logger.Info("EA",
                 StringFormat("Entry confirmed direction=%s entry=%s SL=%s TP=%s lots=%s risk_setting=%.2f%% actual_risk=%.2f (%.2f%%) candle=%s anchor_stop=%s order=%I64u deal=%I64u position_id=%I64d exact=%s",
                              XSparkDirectionName(plan.direction),
                              DoubleToString(plan.entry_reference, g_market_state.Digits()),
                              DoubleToString(plan.final_sl, g_market_state.Digits()),
                              plan.final_tp > 0.0 ? DoubleToString(plan.final_tp, g_market_state.Digits()) : "none",
                              DoubleToString(plan.volume, 2),
                              plan.risk_pct,
                              actual_risk_cash,
                              actual_risk_pct,
                              TimeToString(plan.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              DoubleToString(plan.theoretical_sl, g_market_state.Digits()),
                              result.order_ticket,
                              result.deal_ticket,
                              result.position_id,
                              XSparkScalpBoolToString(registered_exactly)));

   if(g_position_sizer.LastRaisedToMinimum())
      g_logger.Warn("PositionSizer",
                    StringFormat("This entry was raised to the broker's smallest trade: it risks %.2f, which is %.2f%% of the balance against a %.2f%% setting. The balance, not the setting, is sizing this trade.",
                                 actual_risk_cash,
                                 actual_risk_pct,
                                 plan.risk_pct));
}

bool XSparkScalpAttemptStateRecovery()
{
   if(!g_safety_manager.StateRecoveryLatched())
      return true;

   if(!g_position_manager.Reconcile(g_logger))
   {
      g_logger.Critical("EA", "Reconciliation failed while state recovery is active; new entries stay blocked.");
      return false;
   }

   string coverage_reason = "";
   const bool covered = g_position_manager.ManagedStateCoversLivePositions(coverage_reason);

   const bool recovered_position_tracked =
      g_state_recovery_position_id == 0 ||
      !g_position_manager.PositionIsLive(g_state_recovery_position_id) ||
      g_position_manager.StateForIdentifierOwnsSignalBar(g_state_recovery_position_id,
                                                         g_state_recovery_signal_bar_time);

   if(covered && recovered_position_tracked)
   {
      g_logger.Warn("EA",
                    StringFormat("State recovery resolved by reconciliation. %s Strategy metadata of a recovered position may have been rebuilt from broker values.",
                                 coverage_reason));
      g_safety_manager.ClearStateRecovery(g_logger);
      g_state_recovery_position_id = 0;
      g_state_recovery_signal_bar_time = 0;
      g_state_recovery_last_log_time = 0;
      g_last_block_reason = "State recovery resolved; managed state matches broker state.";
      return true;
   }

   datetime now = TimeTradeServer();
   if(now == 0)
      now = TimeCurrent();

   const long since_last_recovery_log = (long)now - (long)g_state_recovery_last_log_time;

   if(g_state_recovery_last_log_time == 0 ||
      since_last_recovery_log < 0 ||
      since_last_recovery_log >= XSPARK_SCALP_STATE_RECOVERY_LOG_INTERVAL_SECONDS)
   {
      g_logger.Critical("EA",
                        StringFormat("XSparkScalp state is still inconsistent with broker state; new entries remain blocked. coverage=%s recovered_position_id=%I64d tracked=%s",
                                     coverage_reason,
                                     g_state_recovery_position_id,
                                     XSparkScalpBoolToString(recovered_position_tracked)));
      g_state_recovery_last_log_time = now;
   }

   g_last_block_reason = "XSparkScalp state is inconsistent with broker state; new entries are blocked.";
   return false;
}

void XSparkScalpEnterStateRecovery(XSparkTradePlan &plan, XSparkExecutionResult &result)
{
   const string registration_reason = g_position_manager.LastReason();

   g_logger.Critical("EA",
                     StringFormat("Broker execution confirmed (order=%I64u deal=%I64u position_id=%I64d) but state registration did not bind exactly: %s",
                                  result.order_ticket,
                                  result.deal_ticket,
                                  result.position_id,
                                  registration_reason));

   g_state_recovery_position_id = result.position_id;
   g_state_recovery_signal_bar_time = plan.signal_bar_time;
   g_state_recovery_last_log_time = 0;
   g_safety_manager.LatchStateRecovery(registration_reason, g_logger);

   g_status = "STATE RECOVERY";
   g_last_block_reason = "Broker execution confirmed but state registration failed; reconciling before any further entry.";

   XSparkScalpAttemptStateRecovery();

   if(g_safety_manager.StateRecoveryLatched())
      return;

   g_last_block_reason = g_position_manager.LastRegistrationBoundState() ?
                         "Entry confirmed; state bound without exact broker identification, then verified by reconciliation." :
                         "Entry confirmed; state for the new position was rebuilt from broker values by reconciliation.";
}

// ---------------------------------------------------------------------------
// Calibration.
// ---------------------------------------------------------------------------

// The COST line: the one line an operator must read before funding. Printed
// after every successful calibration, so it is in the journal on the first
// bar and again every broker day with that day's spread.
void XSparkScalpLogCostLine()
{
   const double spread = g_market_state.SpreadPrice();
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tick_value = XSparkScalpTickValue();

   double cost = 0.0;
   double commission_price = 0.0;
   string cost_reason = "";
   if(!XSparkTrendScalpRoundTripCost(spread, g_scalp_commission_per_lot, tick_size, tick_value, cost, commission_price, cost_reason))
   {
      g_logger.Warn("Cost", "The round-trip cost could not be measured on this bar: " + cost_reason);
      return;
   }

   const double min_stop_price = XSparkScorePointsToPrice(g_auto_tune.min_stop_points, g_score_point_size);
   const double typical_candle = XSparkScorePointsToPrice(g_auto_tune.reference_atr_points, g_score_point_size);
   const double widest_stop = g_scalp_config.max_stop_atr_mult * typical_candle;

   if(min_stop_price <= 0.0 || widest_stop <= 0.0)
   {
      g_logger.Warn("Cost", "The calibrated stop bounds are not usable, so the cost share cannot be stated.");
      return;
   }

   const double share_pct = cost / min_stop_price * 100.0;
   const double no_edge_pct = XSparkTrendScalpNoEdgeWinRate(g_scalp_target_r, share_pct) * 100.0;
   const double break_even_pct = XSparkTrendScalpBreakEvenWinRate(g_scalp_target_r) * 100.0;
   const bool feasible = cost <= g_scalp_config.max_cost_share_pct / 100.0 * widest_stop;

   const string line = StringFormat("Round-trip cost now: spread %s + commission %s = %s, which is %.1f%% of the smallest stop this setup can produce (%.2f points; at most %.1f%%). "
                                    "A trade with no edge at that cost wins about %.1f%% at the chosen target (break-even %.1f%%). "
                                    "This chart period is %s at the current cost: the widest stop allowed here (%.2f x the typical candle = %s) needs a cost at or below %.1f%% of it.",
                                    DoubleToString(spread, g_market_state.Digits()),
                                    DoubleToString(commission_price, g_market_state.Digits()),
                                    DoubleToString(cost, g_market_state.Digits()),
                                    share_pct,
                                    g_auto_tune.min_stop_points,
                                    g_scalp_config.max_cost_share_pct,
                                    no_edge_pct,
                                    break_even_pct,
                                    feasible ? "FEASIBLE" : "INFEASIBLE",
                                    g_scalp_config.max_stop_atr_mult,
                                    DoubleToString(widest_stop, g_market_state.Digits()),
                                    g_scalp_config.max_cost_share_pct);

   if(feasible)
      g_logger.Info("Cost", line);
   else
      g_logger.Warn("Cost", line);
}

// The minimum-lot line: what the broker's smallest trade risks at the
// smallest stop this setup can produce, and whether the risk setting or the
// minimum lot is sizing this account.
void XSparkScalpLogMinimumLotLine()
{
   const double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double min_stop_price = XSparkScorePointsToPrice(g_auto_tune.min_stop_points, g_score_point_size);
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double risk_cash = 0.0;
   double risk_pct = 0.0;
   string risk_reason = "";
   if(!XSparkTrendScalpMinimumLotRisk(volume_min,
                                      min_stop_price,
                                      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                                      XSparkScalpTickValue(),
                                      balance,
                                      risk_cash,
                                      risk_pct,
                                      risk_reason))
   {
      g_logger.Warn("PositionSizer", "The smallest trade's risk could not be stated: " + risk_reason);
      return;
   }

   const int volume_digits = XSparkVolumeDigitsFromStep(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   const bool exceeds_budget = risk_pct > g_scalp_risk_pct;
   const bool within_cap = risk_pct <= g_scalp_min_lot_cap_pct;
   const bool will_raise = exceeds_budget && within_cap;
   // What a losing trade actually costs: the budget when the minimum lot fits
   // inside it, the minimum lot's risk when it does not.
   const double effective_pct = exceeds_budget ? risk_pct : g_scalp_risk_pct;
   const int losses_allowed = effective_pct > 0.0 ? (int)MathFloor(g_scalp_daily_dd_pct / effective_pct) : 0;

   g_logger.Info("PositionSizer",
                 StringFormat("Smallest trade on %s: %s lots. At the smallest stop this setup can produce it risks %.2f = %.2f%% of the balance; your risk setting is %.2f%%, so the smallest trade %s be raised to the minimum. "
                              "The daily stop of %.2f%% allows about %d such losses; at a 50%% win rate expect it to fire on a fair share of days until the balance grows.",
                              _Symbol,
                              DoubleToString(volume_min, volume_digits),
                              risk_cash,
                              risk_pct,
                              g_scalp_risk_pct,
                              will_raise ? "WILL" : "WILL NOT",
                              g_scalp_daily_dd_pct,
                              losses_allowed));

   if(exceeds_budget && !within_cap)
      g_logger.Warn("PositionSizer",
                    StringFormat("No trade can open here at this balance: the smallest trade risks %.2f%%, above the %.2f%% small-account cap. A bigger balance, a cent account, or a longer chart period fixes this.",
                                 risk_pct,
                                 g_scalp_min_lot_cap_pct));
}

// Samples the instrument's own range and derives the thresholds from it,
// touching nothing: every mutation happens in the caller, after every pure
// check has passed. Returns false with waiting=true when there is simply not
// enough history yet, and with waiting=false when the derivation itself
// failed.
bool XSparkScalpDeriveCalibration(XSparkAutoTuneResult &derived,
                                  int &copied,
                                  int &valid_samples,
                                  string &derive_reason,
                                  bool &waiting,
                                  string &failure)
{
   XSparkResetAutoTuneResult(derived);
   copied = 0;
   valid_samples = 0;
   derive_reason = "";
   waiting = false;
   failure = "";

   double samples[];
   copied = g_indicator_cache.CopyATR14BaseHistory(g_scalp_calibration_bars, samples);

   if(copied <= 0)
   {
      waiting = true;
      failure = "No ATR history is available yet to calibrate this market.";
      return false;
   }

   double reference_price = 0.0;
   string median_reason = "";
   if(!XSparkSampleMedian(samples, copied, XSPARK_AUTOTUNE_MIN_SAMPLES,
                          reference_price, valid_samples, median_reason))
   {
      waiting = true;
      failure = "Market calibration is waiting: " + median_reason;
      return false;
   }

   const double reference_points = XSparkPriceToScorePoints(reference_price, g_score_point_size);

   if(!XSparkDeriveAutoTune(reference_points,
                            XSPARK_TRENDSCALP_QUIET_MARKET_PCT,
                            XSPARK_TRENDSCALP_WILD_MARKET_PCT,
                            g_scalp_min_stop_atr_mult,
                            XSPARK_TRENDSCALP_ENTRY_SLIP_PCT,
                            XSPARK_TRENDSCALP_EXIT_SLIP_PCT,
                            XSPARK_TRENDSCALP_SPREAD_CAP_PCT,
                            derived,
                            derive_reason))
   {
      failure = "Market calibration failed: " + derive_reason;
      return false;
   }

   return true;
}

// Derives the instrument-scaled thresholds from the instrument's own range.
// The stop multiple handed to the derivation is the TrendScalp stop FLOOR,
// because that is genuinely the smallest stop this configuration can produce -
// which is what every derived tolerance is measured against.
//
// Runs once on the first candle with enough history, and again on the first
// candle of every new broker day. The first calibration fails closed exactly
// as XSparkFlow's does; a re-run that fails keeps the previous thresholds and
// says so at WARN, because a set of thresholds that worked yesterday is a
// better guard than none.
bool XSparkScalpCalibrateForSymbol()
{
   const datetime server_time = g_market_state.ServerTime();
   const int day_id = server_time > 0 ? XSparkServerDayId(server_time) : g_calibration_day_id;
   const bool rerun = g_auto_tune_complete;

   if(rerun && day_id == g_calibration_day_id)
      return true;

   XSparkAutoTuneResult derived;
   int copied = 0;
   int valid_samples = 0;
   string derive_reason = "";
   bool waiting = false;
   string failure = "";

   if(!XSparkScalpDeriveCalibration(derived, copied, valid_samples, derive_reason, waiting, failure))
   {
      if(rerun)
      {
         if(g_calibration_warn_day_id != day_id)
         {
            g_logger.Warn("AutoTune", "The daily re-calibration did not complete; yesterday's thresholds stay in force: " + failure);
            g_calibration_warn_day_id = day_id;
         }

         return true;
      }

      g_last_block_reason = failure;

      if(!waiting)
         g_logger.Critical("AutoTune", failure);

      return false;
   }

   // The drift bound is pure, so it is judged BEFORE any component is touched:
   // a re-run whose tolerances would not bound risk leaves the old ones in
   // place instead of installing half a calibration.
   double bound_min_stop = 0.0;
   double bound_ratio = 0.0;
   string bound_reason = "";
   const int bound = XSparkEntryDriftBound(derived.entry_deviation_points,
                                           g_scalp_min_stop_atr_mult,
                                           derived.atr_min_points,
                                           bound_min_stop,
                                           bound_ratio,
                                           bound_reason);

   if(bound == XSPARK_DRIFT_BOUND_FAULT)
   {
      if(rerun)
      {
         if(g_calibration_warn_day_id != day_id)
         {
            g_logger.Warn("AutoTune", "The daily re-calibration derived an entry slippage that does not bound risk; yesterday's thresholds stay in force: " + bound_reason);
            g_calibration_warn_day_id = day_id;
         }

         return true;
      }

      g_entry_drift_bound_usable = false;
      g_entry_drift_bound_reason = bound_reason;
      g_safety_manager.SetEntryDriftBound(g_entry_drift_bound_usable, g_entry_drift_bound_reason);
      g_last_block_reason = "Derived entry slippage does not bound realised risk: " + bound_reason;
      g_logger.Critical("AutoTune", g_last_block_reason);
      return false;
   }

   if(!g_strategy.SetVolatilityBand(derived.atr_min_points, derived.atr_max_points) ||
      !g_safety_manager.SetMaxSpreadScorePoints(derived.spread_cap_points) ||
      !g_execution_engine.SetEntryDeviationScorePoints(derived.entry_deviation_points) ||
      !g_position_manager.SetExitDeviationScorePoints(derived.exit_deviation_points))
   {
      // A refusal here can leave the components on different calibrations,
      // which is the ambiguous state rule 24 exists for: entries stop until
      // a later calibration installs one consistent set.
      g_auto_tune_complete = false;
      g_entry_drift_bound_usable = false;
      g_entry_drift_bound_reason = "A derived threshold was refused by the component that uses it.";
      g_safety_manager.SetEntryDriftBound(g_entry_drift_bound_usable, g_entry_drift_bound_reason);
      g_last_block_reason = "A derived threshold was refused by the component that uses it; new entries stay blocked.";
      g_logger.Critical("AutoTune", g_last_block_reason);
      return false;
   }

   g_auto_tune = derived;
   g_auto_tune_complete = true;
   g_calibration_day_id = day_id;
   g_entry_drift_bound_usable = true;
   g_entry_drift_bound_reason = bound_reason;
   g_safety_manager.SetEntryDriftBound(g_entry_drift_bound_usable, g_entry_drift_bound_reason);

   if(bound == XSPARK_DRIFT_BOUND_WARN)
      g_logger.Warn("AutoTune", bound_reason);

   // The sample's span, so a reader can see that a five-day sample really was
   // five days rather than whatever history the terminal happened to hold.
   // Bar 0 is still forming, so the newest sampled bar is shift 1 and the
   // oldest is shift `copied`.
   const datetime first_sampled = iTime(_Symbol, g_base_timeframe, copied);
   const datetime last_sampled = iTime(_Symbol, g_base_timeframe, 1);
   const double span_hours = (first_sampled > 0 && last_sampled >= first_sampled)
                             ? ((double)((long)last_sampled - (long)first_sampled) + (double)PeriodSeconds(g_base_timeframe)) / 3600.0
                             : 0.0;

   g_logger.Info("AutoTune",
                 StringFormat("Calibrated %s %s from %d of %d ATR samples spanning %.1f hours (%s to %s)%s: %s",
                              _Symbol,
                              EnumToString(g_base_timeframe),
                              valid_samples,
                              copied,
                              span_hours,
                              TimeToString(first_sampled, TIME_DATE | TIME_MINUTES),
                              TimeToString(last_sampled, TIME_DATE | TIME_MINUTES),
                              rerun ? " on the new broker day" : "",
                              derive_reason));

   XSparkScalpLogCostLine();
   XSparkScalpLogMinimumLotLine();
   return true;
}

// Refreshes everything that changes once per closed candle: the indicator
// cache and the ATR the stop bounds and the time-stop spread check read.
// Runs BEFORE position management on the first tick of a new candle. A failed
// refresh keeps the previous ATR: a deferral threshold that cannot be updated
// must stay where it is, never disappear.
bool XSparkScalpRefreshBarState(const datetime current_bar_time)
{
   if(current_bar_time != 0 && g_bar_state_time == current_bar_time)
      return true;

   if(!g_indicator_cache.RefreshClosedData())
   {
      g_last_block_reason = g_indicator_cache.LastReason();
      XSparkScalpVerboseBlock("IndicatorCache", g_last_block_reason);
      return false;
   }

   g_latest_closed_atr14 = g_indicator_cache.ATR14Base();
   g_bar_state_time = current_bar_time;
   return true;
}

// ---------------------------------------------------------------------------
// Live verification of two inputs the tester cannot check.
// ---------------------------------------------------------------------------

// Compares the broker's clock with the configured UTC offset once an hour.
// Skipped in the tester, which emulates TimeGMT() equal to the server time
// and so would always report an offset of zero. A mismatch shifts every
// session window by the difference, so entries are blocked until they agree;
// the re-check every hour catches a DST change on the broker's side.
void XSparkScalpVerifyClockOffset(const datetime server_time)
{
   if(MQLInfoInteger(MQL_TESTER))
      return;

   const long since_last_check = (long)server_time - (long)g_last_offset_check_time;
   if(g_last_offset_check_time != 0 &&
      since_last_check >= 0 &&
      since_last_check < XSPARK_SCALP_OFFSET_CHECK_INTERVAL_SECONDS)
      return;

   const datetime trade_server = TimeTradeServer();
   const datetime gmt = TimeGMT();

   // Nothing to compare while disconnected; the previous verdict stands and
   // the comparison is retried on the next tick.
   if(trade_server == 0 || gmt == 0)
      return;

   g_last_offset_check_time = server_time;

   const double difference_hours = (double)((long)trade_server - (long)gmt) / 3600.0;
   const int observed = (int)MathRound(difference_hours);

   string offset_reason = "";
   if(!XSparkTrendScalpOffsetMatches(observed, g_scalp_utc_offset, offset_reason))
   {
      if(g_clock_offset_ok || offset_reason != g_clock_offset_reason)
         g_logger.Critical("Clock", offset_reason);

      g_clock_offset_ok = false;
      g_clock_offset_reason = offset_reason;
      return;
   }

   if(!g_clock_offset_ok)
      g_logger.Info("Clock",
                    StringFormat("The broker's clock now agrees with the configured offset of %d hours; entries are no longer blocked by it.",
                                 g_scalp_utc_offset));
   else
      XSparkScalpVerboseBlock("Clock",
                              StringFormat("Broker clock offset verified: observed %d hours, configured %d.",
                                           observed,
                                           g_scalp_utc_offset));

   g_clock_offset_ok = true;
   g_clock_offset_reason = "";
}

// Compares what the broker actually charged on the last closed trade with the
// declared commission. The declared figure feeds the cost floor, so an
// understated one silently admits trades the floor should have refused; the
// latch blocks entries until a restart with a corrected input.
void XSparkScalpVerifyCommission()
{
   const long identifier = g_position_manager.LastClosureIdentifier();
   if(identifier == 0 || identifier == g_last_commission_identifier)
      return;

   g_last_commission_identifier = identifier;

   const double measured = g_position_manager.LastClosureCommissionPerLot();
   const double tolerated = g_scalp_commission_per_lot * (1.0 + XSPARK_TRENDSCALP_COMMISSION_TOLERANCE_PCT / 100.0) + 0.000001;

   if(measured > tolerated)
   {
      g_commission_reason = StringFormat("Your broker charged %.2f per lot round trip; the commission setting says %.2f. Set it to %.2f and restart.",
                                         measured,
                                         g_scalp_commission_per_lot,
                                         measured);
      g_logger.Critical("Cost",
                        StringFormat("Commission understated on position %I64d: measured %.4f per lot, setting %.4f (tolerance %.0f%%). New entries are blocked until the setting is corrected and the EA restarted.",
                                     identifier,
                                     measured,
                                     g_scalp_commission_per_lot,
                                     XSPARK_TRENDSCALP_COMMISSION_TOLERANCE_PCT));
      g_commission_understated = true;
      return;
   }

   g_logger.Info("Cost",
                 StringFormat("Commission verified on position %I64d: measured %.4f per lot, setting %.4f.",
                              identifier,
                              measured,
                              g_scalp_commission_per_lot));
}

// ---------------------------------------------------------------------------
// The closed-candle evaluation.
// ---------------------------------------------------------------------------

void XSparkScalpEvaluateNewBarCore()
{
   g_funnel_stage = "";

   if(!XSparkScalpRefreshBarState(g_current_base_bar_time))
   {
      g_status = "SCANNING";
      return;
   }

   if(!XSparkScalpCalibrateForSymbol())
   {
      g_status = "SCANNING";
      XSparkScalpVerboseBlock("AutoTune", g_last_block_reason);
      return;
   }

   XSparkCandle signal_bar;
   if(!g_indicator_cache.BaseBar(1, signal_bar))
   {
      g_status = "SCANNING";
      g_last_block_reason = "Closed signal candle is unavailable.";
      return;
   }

   if(signal_bar.time == g_last_evaluated_signal_bar_time)
   {
      g_status = "SCANNING";
      g_last_block_reason = "Closed signal candle was already evaluated.";
      XSparkScalpVerboseBlock("TrendScalp", g_last_block_reason);
      return;
   }

   g_last_evaluated_signal_bar_time = signal_bar.time;
   g_funnel_stage = "OTHER";

   XSparkSignal signal;
   XSparkScoreBotReport report;
   const bool eligible_signal = g_strategy.Evaluate(g_indicator_cache, signal, report);
   g_last_report = report;
   g_last_report.selected_risk_pct = g_scalp_risk_pct;

   g_logger.Info("TrendScalp",
                 StringFormat("bar=%s dir=%s O=%.8f H=%.8f L=%.8f C=%.8f ema21=%.8f ema50=%.8f ema50_higher=%.8f atr=%.8f anchor=%.8f trend=%s pullback=%s status=%s",
                              TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              XSparkDirectionName(report.direction),
                              report.context.bar1_open,
                              report.context.bar1_high,
                              report.context.bar1_low,
                              report.context.bar1_close,
                              report.ema21_base,
                              report.ema50_base,
                              report.ema50_higher,
                              report.atr14,
                              report.detected_level,
                              report.htf_verdict,
                              report.pullback_verdict,
                              report.status));

   if(!eligible_signal)
   {
      g_status = report.status;
      g_last_block_reason = report.block_reason;

      // The rule's own verdicts name the stage; a gate inside the strategy
      // (the volatility band) names itself through the status.
      if(report.status == "ATR BLOCKED")
         g_funnel_stage = "ATR BLOCKED";
      else if(report.htf_verdict == "NO TREND" || report.htf_verdict == "BIAS CONFLICT")
         g_funnel_stage = report.htf_verdict;
      else if(report.pullback_verdict != "OFF" && report.pullback_verdict != "TOUCH+RECLAIM")
         g_funnel_stage = report.pullback_verdict;

      XSparkScalpVerboseBlock("TrendScalp", g_last_block_reason);
      return;
   }

   XSparkScalpCountFunnelStage("SIGNAL");

   if(!g_config_valid)
   {
      g_status = "CONFIG BLOCKED"; g_last_block_reason = g_config_reason;
      XSparkScalpLogSignalRejection("configuration", g_last_block_reason, report);
      return;
   }

   if(g_commission_understated)
   {
      g_status = "CONFIG BLOCKED"; g_last_block_reason = g_commission_reason;
      XSparkScalpLogSignalRejection("commission", g_last_block_reason, report);
      return;
   }

   if(!g_clock_offset_ok)
   {
      g_status = "CLOCK OFFSET"; g_last_block_reason = g_clock_offset_reason;
      XSparkScalpLogSignalRejection("clock", g_last_block_reason, report);
      return;
   }

   // The entry window, judged at the moment the entry would happen. The lead
   // keeps a trade from being opened and then flattened minutes later at the
   // session end. Session weight 0 tells the panel why.
   string session_reason = "";
   if(!XSparkTrendScalpSessionAllows(g_market_state.ServerTime(),
                                     g_scalp_utc_offset,
                                     InpScalpSessions,
                                     XSPARK_TRENDSCALP_SESSION_CLOSE_LEAD_SECONDS,
                                     session_reason))
   {
      g_status = "SESSION BLOCKED"; g_last_block_reason = session_reason;
      g_last_report.components.session_weight = 0.0;
      g_funnel_stage = "SESSION BLOCKED";
      XSparkScalpLogSignalRejection("session", g_last_block_reason, report);
      return;
   }

   // A scalp is never meant to be open at the weekend. Off only for an
   // instrument that trades through the weekend, where there is no gap.
   if(g_scalp_use_weekend_close &&
      g_position_manager.ShouldWeekendClose(g_market_state.ServerTime(),
                                            g_scalp_weekend_close_hour,
                                            g_scalp_weekend_close_minute))
   {
      g_status = "WEEKEND CLOSE";
      g_last_block_reason = "Weekend close window is active; new entries are blocked.";
      XSparkScalpLogSignalRejection("weekend", g_last_block_reason, report);
      return;
   }

   // The daily cap, fail-closed: a history that cannot be read is a cap that
   // refuses, because a count of zero would let a bot trade as if it had not.
   int trades_today = 0;
   const int counted_today = g_position_manager.EntryDealsToday(trades_today) ? trades_today : -1;
   string cap_reason = "";
   if(!XSparkTrendScalpDailyCapAllows(counted_today, XSPARK_TRENDSCALP_MAX_TRADES_PER_DAY, cap_reason))
   {
      g_status = "DAILY CAP"; g_last_block_reason = cap_reason;
      g_funnel_stage = "DAILY CAP";
      XSparkScalpLogSignalRejection("daily_cap", g_last_block_reason, report);
      return;
   }

   // XSparkScalp does not reverse: the open trade exits on its stop, its
   // target or its time stop and nothing else, so an opposing signal is
   // refused here rather than hedged into a second position.
   string exposure_reason = "";
   if(!XSparkDirectionIsUnopposed(_Symbol, InpScalpMagicNumber, signal.direction, exposure_reason))
   {
      g_status = "OPPOSING EXPOSURE"; g_last_block_reason = exposure_reason;
      XSparkScalpLogSignalRejection("exposure", exposure_reason, report);
      return;
   }

   // The COST the trade pays - spread plus commission in price - is what the
   // safety manager measures against its absolute cap and its share of the
   // typical candle, not the bare spread: on a commission account the spread
   // alone under-counts by exactly the commission.
   double round_trip_cost = 0.0;
   double commission_price = 0.0;
   string cost_reason = "";
   if(!XSparkTrendScalpRoundTripCost(g_market_state.SpreadPrice(),
                                     g_scalp_commission_per_lot,
                                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                                     XSparkScalpTickValue(),
                                     round_trip_cost,
                                     commission_price,
                                     cost_reason))
   {
      g_status = "COST BLOCKED"; g_last_block_reason = cost_reason;
      g_funnel_stage = "COST BLOCKED";
      XSparkScalpLogSignalRejection("cost", g_last_block_reason, report);
      return;
   }

   if(!g_safety_manager.CanOpenNewTrades(g_position_manager.ManagedPositionCount(),
                                         round_trip_cost,
                                         report.atr14))
   {
      g_status = XSparkScalpStatusFromSafety();
      g_last_block_reason = g_safety_manager.LastReason();

      if(g_status == "SPREAD BLOCKED")
         g_funnel_stage = "SPREAD BLOCKED";

      XSparkScalpLogSignalRejection("safety", g_last_block_reason, report);

      if(g_status == "STALE QUOTE")
         g_logger.Warn("SafetyManager", g_last_block_reason);
      else
         XSparkScalpVerboseBlock("SafetyManager", g_last_block_reason);

      return;
   }

   double risk_pct = 0.0;
   if(!g_risk_manager.IsSignalApproved(signal, risk_pct))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_risk_manager.LastReason();
      XSparkScalpLogSignalRejection("risk", g_last_block_reason, report);
      XSparkScalpVerboseBlock("RiskManager", g_last_block_reason);
      return;
   }

   g_last_report.selected_risk_pct = risk_pct;

   XSparkTradePlan plan;
   if(!XSparkScalpPrepareTradePlan(signal, risk_pct, round_trip_cost, plan))
   {
      g_status = g_plan_cost_refusal ? "COST BLOCKED" : "SCANNING";

      if(g_plan_cost_refusal)
         g_funnel_stage = "COST BLOCKED";

      XSparkScalpLogSignalRejection("plan", g_last_block_reason, report);
      XSparkScalpVerboseBlock("TradePlan", g_last_block_reason);
      return;
   }

   plan.planned_risk_distance = plan.risk_distance;

   // Account-level risk cap. Checked once the plan has a volume and a
   // broker-valid stop, because a cap checked against an estimate is not a cap.
   {
      double open_risk_cash = 0.0, own_risk_cash = 0.0, foreign_risk_cash = 0.0;
      int own_positions = 0;
      string account_risk_reason = "";

      double prospective_risk_cash = 0.0;
      string prospective_reason = "";
      const bool prospective_known = XSparkPositionRiskCash(plan.entry_reference,
                                                            plan.final_sl,
                                                            plan.volume,
                                                            SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                                                            XSparkScalpTickValue(),
                                                            prospective_risk_cash,
                                                            prospective_reason);

      double projected_pct = 0.0;
      string cap_check_reason = "";

      if(!prospective_known ||
         !XSparkReadAccountExposure(_Symbol, InpScalpMagicNumber, open_risk_cash, own_risk_cash, foreign_risk_cash, own_positions, account_risk_reason) ||
         !XSparkAccountRiskWithinCap(open_risk_cash,
                                     prospective_risk_cash,
                                     AccountInfoDouble(ACCOUNT_BALANCE),
                                     XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT,
                                     projected_pct,
                                     cap_check_reason))
      {
         g_status = "ACCOUNT RISK";
         g_last_block_reason = !prospective_known ? prospective_reason
                               : (account_risk_reason != "" ? account_risk_reason : cap_check_reason);

         g_last_block_reason += StringFormat(" [own_symbol_magic=%.2f other_positions=%.2f account currency]",
                                              own_risk_cash, foreign_risk_cash);
         XSparkScalpLogSignalRejection("account_risk", g_last_block_reason, report);
         g_logger.Warn("RiskManager",
                       StringFormat("Entry refused by the account risk cap: %s", g_last_block_reason));
         return;
      }
   }

   // Always checked. There is no configuration in which opening a trade the
   // account cannot margin is the behaviour someone wanted.
   double required_margin = 0.0;
   double free_margin = 0.0;
   string margin_reason = "";

   if(!g_execution_engine.HasSufficientMargin(plan.symbol,
                                              plan.direction,
                                              plan.volume,
                                              plan.entry_reference,
                                              XSPARK_TRENDSCALP_MARGIN_BUFFER_PCT,
                                              required_margin,
                                              free_margin,
                                              margin_reason))
   {
      g_status = "SCANNING";
      g_last_block_reason = margin_reason;
      XSparkScalpLogSignalRejection("margin", g_last_block_reason, report);
      XSparkScalpVerboseBlock("ExecutionEngine", g_last_block_reason);
      return;
   }

   if(!g_execution_engine.CanSubmitSignal(plan.signal_bar_time))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkScalpLogSignalRejection("submit", g_last_block_reason, report);
      XSparkScalpVerboseBlock("ExecutionEngine", g_last_block_reason);
      return;
   }

   XSparkExecutionResult execution_result;
   if(!g_execution_engine.ExecuteApprovedPlan(plan, g_position_sizer, execution_result, g_logger))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkScalpLogSignalRejection("execute", g_last_block_reason, report);
      return;
   }

   g_funnel_stage = "ENTERED";

   const bool registered_exactly = g_position_manager.RegisterNewTrade(plan, execution_result, g_logger);

   g_dashboard.AnnotateEntry(plan, execution_result);
   XSparkScalpLogEntry(plan, execution_result, registered_exactly);

   if(registered_exactly)
   {
      g_status = "MANAGING";
      g_last_block_reason = "Entry confirmed and registered against the exact broker position id.";
      return;
   }

   if(g_position_manager.LastRegistrationPositionAlreadyClosed())
   {
      g_logger.Warn("EA", g_position_manager.LastReason());
      g_status = "SCANNING";
      g_last_block_reason = "Entry confirmed but the broker position closed before state registration.";
      return;
   }

   XSparkScalpEnterStateRecovery(plan, execution_result);
}

void XSparkScalpEvaluateNewBar()
{
   XSparkScalpEvaluateNewBarCore();
   XSparkScalpCountFunnelStage(g_funnel_stage);
   g_ui_decision_status = g_status; g_ui_decision_reason = g_last_block_reason;
}

// ---------------------------------------------------------------------------
// Lifecycle.
// ---------------------------------------------------------------------------

int OnInit()
{
   XSparkResetScoreBotReport(g_last_report);
   g_last_report.pattern_mode = "TREND PULLBACK";
   XSparkScalpResetFunnel();
   g_logger.Initialize("XSparkScalp", InpScalpVerboseLog);
   g_logger.Info("EA", "Starting XSparkScalp TrendScalp");

   if(!XSparkScalpValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   if(!g_market_state.Initialize(_Symbol))
   {
      g_logger.Critical("MarketState", "Failed to initialize market state for the chart symbol");
      return INIT_FAILED;
   }

   if(!g_indicator_cache.Initialize(_Symbol, g_base_timeframe, g_higher_timeframe))
   {
      g_logger.Critical("IndicatorCache", g_indicator_cache.LastReason());
      return INIT_FAILED;
   }

   XSparkScalpResolveSessionScorePointSize();
   XSparkScalpResolveWeekendClose();

   // Both choices resolve to a tested value, and both resolvers refuse only a
   // member this build does not know. A refusal cannot come from anything an
   // operator typed - it could only come from an edit to the enum - so it is
   // a build fault, and it is reported as one: new entries are blocked while
   // OnTick keeps managing what is already open.
   g_config_valid = true;
   g_config_reason = "";

   string style_reason = "";
   if(!XSparkTrendScalpTargetForStyle(InpScalpExitStyle, g_scalp_target_r, style_reason))
   {
      g_config_valid = false;
      g_config_reason += style_reason + " ";
      g_scalp_target_r = XSPARK_TRENDSCALP_TARGET_R_EVEN;
   }

   string window_reason = "";
   if(!XSparkTrendScalpSessionWindow(InpScalpSessions, g_scalp_session_start_seconds, g_scalp_session_end_seconds, window_reason))
   {
      g_config_valid = false;
      g_config_reason += window_reason + " ";
   }

   // The rule's own geometry comes from the strategy's shipped defaults. Only
   // the two things the EA knows are set here: the instrument's point size,
   // and the target the chosen exit style implies.
   XSparkDefaultTrendScalpConfig(g_scalp_config);
   g_scalp_config.score_point_size = g_score_point_size;
   g_scalp_config.target_r = g_scalp_target_r;
   g_scalp_min_stop_atr_mult = g_scalp_config.min_stop_atr_mult;

   string config_reason = "";
   if(!XSparkValidateTrendScalpConfig(g_scalp_config, config_reason))
   {
      g_config_valid = false;
      g_config_reason += config_reason + " ";
   }

   if(!g_config_valid)
      g_logger.Critical("TrendScalp", g_config_reason + "New entries blocked; existing positions remain managed.");

   g_strategy.Configure(g_scalp_config);

   if(!g_strategy.Initialize(_Symbol))
   {
      g_logger.Critical("TrendScalp", g_strategy.LastReason());
      return INIT_FAILED;
   }

   if(!g_safety_manager.Initialize(_Symbol,
                                   InpScalpMagicNumber,
                                   InpScalpEnableTrading,
                                   XSPARK_TRENDSCALP_MAX_OPEN_TRADES,
                                   true,
                                   XSPARK_TRENDSCALP_SEED_SPREAD_CAP_POINTS,
                                   XSPARK_TRENDSCALP_MAX_SPREAD_ATR_PCT,
                                   g_scalp_use_killswitch,
                                   g_scalp_total_dd_pct,
                                   g_scalp_daily_dd_pct,
                                   XSPARK_TRENDSCALP_MAX_QUOTE_AGE_SECONDS,
                                   InpScalpClearKillswitchLatch,
                                   g_score_point_size,
                                   g_score_point_size_conforms,
                                   g_score_point_size_reason,
                                   g_entry_drift_bound_usable,
                                   g_entry_drift_bound_reason,
                                   g_logger))
   {
      g_logger.Critical("SafetyManager", g_safety_manager.LastReason());
      return INIT_FAILED;
   }

   // One risk percentage, presented to RiskManager as three identical tiers.
   // TrendScalp has no score to grade exposure by, so the tier lookup must not
   // be able to change the answer.
   if(!g_risk_manager.Initialize(g_scalp_risk_pct,
                                 g_scalp_risk_pct,
                                 g_scalp_risk_pct,
                                 XSPARK_TRENDSCALP_MAX_RISK_PCT,
                                 XSPARK_TRENDSCALP_MAX_OPEN_TRADES,
                                 XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT))
   {
      g_logger.Critical("RiskManager", g_risk_manager.LastReason());
      return INIT_FAILED;
   }

   // The small-account cap goes to the sizer as-is: zero keeps the sizer's
   // refusal of a below-minimum volume, and a positive cap lets the broker's
   // minimum lot through when the money it risks is inside the cap.
   if(!g_position_sizer.Initialize(g_scalp_min_lot_cap_pct))
   {
      g_logger.Critical("PositionSizer", "Failed to initialize position sizer");
      return INIT_FAILED;
   }

   const double scalp_min_rr = g_scalp_target_r * XSPARK_TRENDSCALP_TARGET_BAND_LOW_MULT;
   const double scalp_max_rr = g_scalp_target_r * XSPARK_TRENDSCALP_TARGET_BAND_HIGH_MULT;

   if(!g_execution_engine.Initialize(InpScalpMagicNumber,
                                     XSPARK_TRENDSCALP_COMMENT_DEFAULT,
                                     XSPARK_TRENDSCALP_ENTRY_DEVIATION_POINTS,
                                     g_score_point_size,
                                     true,
                                     true,
                                     XSPARK_TRENDSCALP_MARGIN_BUFFER_PCT,
                                     scalp_min_rr,
                                     scalp_max_rr,
                                     XSPARK_TRENDSCALP_MAX_QUOTE_AGE_SECONDS,
                                     XSPARK_TRENDSCALP_MAX_OPEN_TRADES,
                                     XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT))
   {
      g_logger.Critical("ExecutionEngine", g_execution_engine.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_manager.Initialize(_Symbol,
                                     InpScalpMagicNumber,
                                     g_score_point_size,
                                     XSPARK_TRENDSCALP_EXIT_DEVIATION_POINTS,
                                     true))
   {
      g_logger.Critical("PositionManager", g_position_manager.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_manager.Reconcile(g_logger))
   {
      g_logger.Critical("PositionManager", "Failed to reconcile existing MT5 positions");
      return INIT_FAILED;
   }

   if(g_indicator_cache.IsValid())
      g_latest_closed_atr14 = g_indicator_cache.ATR14Base();

   // The startup journal: everything the bot resolved, in the operator's
   // words, so the journal is the one place that confirms what actually loaded.
   const double concurrent_cap = XSparkConcurrentRiskCap(XSPARK_TRENDSCALP_MAX_OPEN_TRADES, XSPARK_TRENDSCALP_MAX_RISK_PCT, XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT);
   g_logger.Info("RiskManager",
                 StringFormat("Trade slots=%d; per-entry risk %.2f%%; per-entry ceiling %.3f%%; account cap %.2f%%; small-account cap %.2f%%.",
                              XSPARK_TRENDSCALP_MAX_OPEN_TRADES, g_scalp_risk_pct, concurrent_cap, XSPARK_TRENDSCALP_MAX_ACCOUNT_RISK_PCT, g_scalp_min_lot_cap_pct));

   g_logger.Info("TrendScalp",
                 StringFormat("Rule on %s with %s bias: in a trend (fast average %.2f x the typical candle from the slow one, close beyond the higher period's slow average), enter when a candle touches the fast average within %.2f x, closes back beyond it in its %.0f%% half, and no more than %.2f x past it; stop %.2f x beyond the far wick.",
                              EnumToString(g_base_timeframe),
                              EnumToString(g_higher_timeframe),
                              g_scalp_config.min_ema_gap_atr,
                              g_scalp_config.touch_atr,
                              g_scalp_config.min_close_position * 100.0,
                              g_scalp_config.max_extension_atr,
                              g_scalp_config.buffer_atr_mult));

   const int last_entry_seconds = g_scalp_session_end_seconds - XSPARK_TRENDSCALP_SESSION_CLOSE_LEAD_SECONDS;
   g_logger.Info("TrendScalp",
                 StringFormat("Sessions [%s]: entries %02d:%02d-%02d:%02d UTC (last entry %02d:%02d; open positions flattened at the window end); broker clock offset %d hours%s.",
                              EnumToString(InpScalpSessions),
                              g_scalp_session_start_seconds / 3600,
                              (g_scalp_session_start_seconds % 3600) / 60,
                              g_scalp_session_end_seconds / 3600,
                              (g_scalp_session_end_seconds % 3600) / 60,
                              last_entry_seconds / 3600,
                              (last_entry_seconds % 3600) / 60,
                              g_scalp_utc_offset,
                              MQLInfoInteger(MQL_TESTER) ? " (taken on trust in the tester)" : " (verified against the broker's clock every hour)"));

   g_logger.Info("TrendScalp",
                 StringFormat("Exit [%s]: target %.2f x the stop, accepted broker-valid band %.2f-%.2f; a trade with NO edge wins about %.1f%% at the %.1f%% cost share and breaks even at %.1f%%. Stop and target are sent with the order; there is no trailing.",
                              EnumToString(InpScalpExitStyle),
                              g_scalp_target_r,
                              scalp_min_rr,
                              scalp_max_rr,
                              XSparkTrendScalpNoEdgeWinRate(g_scalp_target_r, g_scalp_config.max_cost_share_pct) * 100.0,
                              g_scalp_config.max_cost_share_pct,
                              XSparkTrendScalpBreakEvenWinRate(g_scalp_target_r) * 100.0));

   g_logger.Info("TrendScalp",
                 StringFormat("Stop: floor %.2f x and ceiling %.2f x the typical candle; the round-trip cost (spread + commission %.2f per lot, verified on every closure within %.0f%%) may be at most %.1f%% of the stop, and widens it to that floor when it is not.",
                              g_scalp_config.min_stop_atr_mult,
                              g_scalp_config.max_stop_atr_mult,
                              g_scalp_commission_per_lot,
                              XSPARK_TRENDSCALP_COMMISSION_TOLERANCE_PCT,
                              g_scalp_config.max_cost_share_pct));

   g_logger.Info("TrendScalp",
                 StringFormat("Time stop: %d seconds (%d candles of %s, never more than %d seconds); a due close waits while the buy/sell gap exceeds %.0f%% of the typical candle. Daily cap: %d entries per broker day, refused when the history cannot be read.",
                              XSparkTrendScalpMaxHoldSeconds(PeriodSeconds(g_base_timeframe)),
                              XSPARK_TRENDSCALP_MAX_HOLD_BARS,
                              EnumToString(g_base_timeframe),
                              XSPARK_TRENDSCALP_MAX_HOLD_SECONDS,
                              XSPARK_TRENDSCALP_MAX_SPREAD_ATR_PCT,
                              XSPARK_TRENDSCALP_MAX_TRADES_PER_DAY));

   g_logger.Info("RiskManager",
                 StringFormat("At %.2f%% risk the daily stop of %.2f%% tolerates %d consecutive losses; the emergency stop of %.2f%% is %s and tolerates %d.",
                              g_scalp_risk_pct,
                              g_scalp_daily_dd_pct,
                              XSparkConsecutiveLossesToDrawdown(g_scalp_risk_pct, g_scalp_daily_dd_pct),
                              g_scalp_total_dd_pct,
                              g_scalp_use_killswitch ? "ON" : "OFF",
                              XSparkConsecutiveLossesToDrawdown(g_scalp_risk_pct, g_scalp_total_dd_pct)));

   g_current_base_bar_time = iTime(_Symbol, g_base_timeframe, 0);
   EventSetTimer(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE) ? 5 : 1);
   g_dashboard.Configure(XSPARK_SCALP_PANEL_CORNER, XSPARK_SCALP_PANEL_MARGIN_X, XSPARK_SCALP_PANEL_MARGIN_Y, false, true, XSPARK_SCALP_PANEL_SIZE_PCT);
   g_dashboard.Initialize();

   g_logger.Info("EA", StringFormat("Symbol=%s digits=%d point=%s strategy_point_size=%s",
                                    g_market_state.SymbolName(),
                                    g_market_state.Digits(),
                                    DoubleToString(g_market_state.PointSize(), g_market_state.Digits()),
                                    DoubleToString(g_score_point_size, 8)));

   g_logger.Info("EA", StringFormat("Account login=%s server=%s company=%s trade_allowed=%s",
                                    IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
                                    AccountInfoString(ACCOUNT_SERVER),
                                    AccountInfoString(ACCOUNT_COMPANY),
                                    XSparkScalpBoolToString(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0)));

   g_logger.Info("EA", "Startup complete. Waiting for the next closed candle before the first evaluation.");
   XSparkScalpUpdateDashboard();

   return INIT_SUCCEEDED;
}

// Strategy Tester optimisation fitness, in R. OnTester() runs BEFORE OnDeinit(),
// so the flush of trades that closed but were not yet detected happens here.
//
// The verdict words are the honest framing applied to the sample: a win rate
// is "above 50%" only when the 95% Wilson lower bound says so on enough
// trades, and an expectancy is "above zero" only when the mean is more than
// two standard errors from it. Below either bar the pass has shown nothing.
double OnTester()
{
   g_position_manager.Reconcile(g_logger);

   g_tester_sequence++;
   g_logger.Info("Tester", StringFormat("OnTester ran at sequence position %d.", g_tester_sequence));

   const int trades = g_position_manager.RecordedTradeCount();
   const int outcomes = g_position_manager.RecordedOutcomeCount();
   const int wins = g_position_manager.RecordedWins();
   const int losses = g_position_manager.RecordedLosses();
   const double win_rate = g_position_manager.RecordedWinRate();
   const int live_at_end = g_position_manager.LiveManagedCount();
   const double mean_r = g_position_manager.RecordedMeanR();
   const double stdev_r = g_position_manager.RecordedStdDevR();
   const double se_r = trades > 0 ? stdev_r / MathSqrt((double)trades) : 0.0;
   const double fitness = g_position_manager.RecordedFitness(XSPARK_FITNESS_PENALTY_K,
                                                             XSPARK_FITNESS_MIN_TRADES);

   double wilson_low = 0.0;
   XSparkTrendScalpWilsonLowerBound(wins, outcomes, wilson_low);

   const bool enough_trades = outcomes >= XSPARK_TRENDSCALP_MIN_TRADES_FOR_VERDICT;
   const string win_verdict = (!enough_trades || wilson_low <= 0.5)
                              ? "NOT DISTINGUISHABLE FROM 50%"
                              : "WIN RATE ABOVE 50% AT 95%";
   const string expectancy_verdict = (!enough_trades || mean_r - XSPARK_TRENDSCALP_WILSON_Z * se_r <= 0.0)
                                     ? "EXPECTANCY NOT DISTINGUISHABLE FROM ZERO"
                                     : "EXPECTANCY ABOVE ZERO AT 95%";

   g_logger.Info("Tester",
                 StringFormat("Pass result: recorded_trades=%d outcomes=%d wins=%d losses=%d win_rate=%.4f wilson95_low=%.4f mean_R=%.4f se_R=%.4f stdev_R=%.4f min_R=%.4f max_R=%.4f fitness=%.6f live_at_end=%d verdict=%s; %s",
                              trades,
                              outcomes,
                              wins,
                              losses,
                              win_rate,
                              wilson_low,
                              mean_r,
                              se_r,
                              stdev_r,
                              g_position_manager.RecordedMinR(),
                              g_position_manager.RecordedMaxR(),
                              fitness,
                              live_at_end,
                              win_verdict,
                              expectancy_verdict));

   return fitness;
}

void OnDeinit(const int reason)
{
   g_tester_sequence++;
   g_logger.Info("Tester", StringFormat("OnDeinit ran at sequence position %d.", g_tester_sequence));

   // The partial day's funnel would otherwise be lost, and in the tester the
   // last day is often the one being read.
   if(g_funnel_day_id != 0)
      XSparkScalpLogFunnel(g_funnel_day_id, "partial day at shutdown");

   EventKillTimer();
   g_indicator_cache.Deinitialize();
   g_strategy.Deinitialize();
   const bool teardown = reason == REASON_REMOVE ||
                         reason == REASON_CHARTCLOSE ||
                         reason == REASON_PROGRAM;
   g_dashboard.Deinitialize(teardown);
   g_logger.Info("EA", StringFormat("Shutdown reason=%s (%d)",
                                    XSparkScalpDeinitReasonToString(reason),
                                    reason));
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(g_dashboard.HandleEvent(id, sparam)) XSparkScalpUpdateDashboard();
}

void OnTimer()
{
   XSparkScalpUpdateDashboard();
}

void OnTick()
{
   const bool market_state_valid = g_market_state.Refresh();

   datetime server_time = TimeTradeServer();
   if(server_time == 0)
      server_time = TimeCurrent();

   // The funnel is per broker day: logged once when the day changes, so a
   // tester run shows where the signals of each day died.
   if(server_time > 0)
   {
      const int day_id = XSparkServerDayId(server_time);

      if(g_funnel_day_id == 0)
         g_funnel_day_id = day_id;
      else if(day_id != g_funnel_day_id)
      {
         XSparkScalpLogFunnel(g_funnel_day_id, "server day ended");
         XSparkScalpResetFunnel();
         g_funnel_day_id = day_id;
      }
   }

   g_safety_manager.RefreshDrawdownState(AccountInfoDouble(ACCOUNT_EQUITY),
                                         server_time,
                                         g_logger);

   if(g_safety_manager.TotalDDKillSwitchLatched())
   {
      g_status = "KILLSWITCH";
      g_last_block_reason = g_safety_manager.LastReason();
      g_position_manager.FlattenManagedExposure("Total DD killswitch", g_logger);
   }

   if(!market_state_valid)
   {
      if(!g_safety_manager.TotalDDKillSwitchLatched())
      {
         g_status = "SCANNING";
         g_last_block_reason = "Unable to refresh market state on tick.";
      }

      g_logger.Warn("MarketState", "Unable to refresh market state on tick; protective management is paused until quotes return.");

      if(g_safety_manager.StateRecoveryLatched())
         XSparkScalpAttemptStateRecovery();

      XSparkScalpUpdateDashboard();
      return;
   }

   XSparkScalpVerifyClockOffset(server_time);

   const datetime current_bar_time = iTime(_Symbol, g_base_timeframe, 0);

   // Refresh BEFORE managing, so the ATR the spread deferral reads is the
   // candle that just closed rather than the one before it.
   if(current_bar_time != 0)
      XSparkScalpRefreshBarState(current_bar_time);

   // Rebuilt every tick rather than cached, because the session end and the
   // spread deferral both move with the clock and the market. Mode
   // CANDLE_ANCHOR with anchors of zero, an all-zero tuning and an empty
   // ladder: the manager never proposes a trail and never touches the stop,
   // which is the tested "missing anchor leaves the stop alone" behaviour.
   // The only exits on the plan are the time stop and the session-end
   // flatten; the broker-side stop and target were sent with the order.
   XSparkTrailPlan trail_plan;
   XSparkResetTrailPlan(trail_plan);
   trail_plan.mode = XSPARK_TRAIL_CANDLE_ANCHOR;
   trail_plan.atr = g_latest_closed_atr14;
   trail_plan.max_hold_seconds = XSparkTrendScalpMaxHoldSeconds(PeriodSeconds(g_base_timeframe));

   // The session end can only be unresolvable on a session choice this build
   // does not know, which g_config_valid already reports; the time stop and
   // the weekend close still bound the position, so the flatten is left off
   // rather than closing on a reason nobody can read.
   datetime flatten_after = 0;
   string session_end_reason = "";
   if(XSparkTrendScalpSessionEnd(server_time, g_scalp_utc_offset, InpScalpSessions, flatten_after, session_end_reason))
      trail_plan.flatten_after = flatten_after;

   // While the spread is wider than this share of the typical candle a due
   // close is deferred, so a time stop that comes due across the rollover
   // waits for the rollover spread to pass instead of paying it. Zero (no
   // check) only while the typical candle is still unknown.
   trail_plan.exit_max_spread = g_latest_closed_atr14 > 0.0
                                ? XSPARK_TRENDSCALP_MAX_SPREAD_ATR_PCT / 100.0 * g_latest_closed_atr14
                                : 0.0;

   if(!g_position_manager.SetTrailPlan(trail_plan))
      g_logger.Critical("PositionManager",
                        "Position-management settings were refused; open stops are left exactly where they are: " +
                        g_position_manager.LastReason());

   g_position_manager.ManagePositions(g_market_state.Bid(),
                                      g_market_state.Ask(),
                                      g_latest_closed_atr14,
                                      0.0,   // no partial close
                                      0.0,   // no partial close
                                      0.0,   // no ATR trail
                                      g_scalp_use_weekend_close,
                                      g_scalp_weekend_close_hour,
                                      g_scalp_weekend_close_minute,
                                      g_logger);

   // A closure the manager just recorded carries the commission the broker
   // actually charged; compared with the declared one before anything else
   // can open on that declared figure.
   XSparkScalpVerifyCommission();

   // A take-profit close the broker confirmed and XSpark could not record
   // against a still-live position is the ambiguous state AGENTS.md rule 24
   // exists for. The latch blocks new entries and keeps managing what is
   // already open. LatchStateRecovery is idempotent.
   if(g_position_manager.UnrecordedProfitStep())
      g_safety_manager.LatchStateRecovery(g_position_manager.UnrecordedProfitStepReason(), g_logger);

   if(!g_state_purged && TerminalInfoInteger(TERMINAL_CONNECTED) != 0)
   {
      g_position_manager.PurgeOrphanedState(g_logger);
      g_state_purged = true;
   }

   if(g_safety_manager.StateRecoveryLatched())
      XSparkScalpAttemptStateRecovery();

   if(current_bar_time == 0)
   {
      g_status = "SCANNING";
      g_last_block_reason = "Current candle timestamp is unavailable.";
      XSparkScalpUpdateDashboard();
      return;
   }

   if(g_current_base_bar_time == 0)
   {
      g_current_base_bar_time = current_bar_time;
      g_status = "SCANNING";
      g_last_block_reason = "Initialized current candle timestamp; waiting for the next close.";
      XSparkScalpUpdateDashboard();
      return;
   }

   if(current_bar_time != g_current_base_bar_time)
   {
      g_current_base_bar_time = current_bar_time;
      XSparkScalpEvaluateNewBar();
   }
   else if(g_position_manager.ManagedPositionCount() > 0 &&
           !g_safety_manager.TotalDDKillSwitchLatched() &&
           !g_safety_manager.StateRecoveryLatched())
   {
      g_status = "MANAGING";
      g_last_block_reason = "Managing existing XSparkScalp positions.";
   }

   if(g_safety_manager.StateRecoveryLatched() && !g_safety_manager.TotalDDKillSwitchLatched())
   {
      g_status = "STATE RECOVERY";
      g_last_block_reason = "XSparkScalp state recovery is active: " + g_safety_manager.StateRecoveryReason();
   }

   XSparkScalpUpdateDashboard();
}
