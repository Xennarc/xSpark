#property version     "1.00"
#property description "XSparkFlow Expert Advisor with the CandleFlow single-factor strategy."

#include <XSpark/Core/AutoTune.mqh>
#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/MarketState.mqh>
#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Execution/ExecutionEngine.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Risk/RiskManager.mqh>
#include <XSpark/Risk/AccountExposure.mqh>
#include <XSpark/Strategy/CandleFlow.mqh>
#include <XSpark/Trade/PositionManager.mqh>
#include <XSpark/UI/Dashboard.mqh>

// XSparkFlow runs the CandleFlow strategy through the SAME safety, risk,
// execution, position-management and dashboard components as XSpark. Only the
// entry rule and the trailing rule differ. It is a separate .mq5 with its own
// Magic Number so both bots can run side by side on one account without ever
// managing each other's positions.
//
// The rule: a closed base-timeframe candle that finished above its open opens a
// long, below its open opens a short. No take-profit. The stop is placed beyond
// that candle's far wick by a buffer, and is re-anchored to the far wick of
// every later closed candle, tightening only. Change the chart period to change
// the timeframe the rule runs on - nothing else needs tuning.
//
// Setup guide and settings: docs/STRATEGY_CANDLEFLOW.md.

input group "01. Start here"
input bool   InpFlowEnableTrading = false; // Allow new trades (false = watch only)
input bool   InpFlowAutoTuneForSymbol = true; // Automatically adapt to this market
input int    InpFlowMaxOpenTrades = 1; // Maximum open trades for this bot (1-10)

input group "02. The candle rule"
input double InpFlowBufferATRMult = 0.10; // Stop buffer beyond the wick (x average range)
input double InpFlowBufferRangePct = 0.0; // Extra buffer (% of the signal candle's range)
input double InpFlowBufferPoints = 0.0; // Extra buffer (strategy points)
input double InpFlowMinStopATRMult = 0.25; // Smallest allowed stop (x average range)
input double InpFlowMaxStopATRMult = 0.0; // Largest allowed stop (x average range; 0 = no limit)
input double InpFlowMinBodyATRMult = 0.0; // Ignore candles smaller than (x average range; 0 = off)

// Every setting below is read only by the trailing stop. The candle anchor is
// always active; the chandelier, the maturity tiering and the breakeven lock are
// additional layers that ship OFF, and the most protective of whichever layers
// are enabled wins. Load presets/xauusd-m30-candleflow-advanced.set for a
// configuration with all of them turned on.
input group "03. Trailing stop"
input double InpFlowMinTrailATRMult = 0.25; // Trail never closer to price than (x average range)
input double InpFlowTrailATRMult = 0.0; // Trail from the peak by (x average range; 0 = off)
input double InpFlowTrailTightATRMult = 0.0; // Tightened trail distance (x average range)
input double InpFlowTrailTightenStartR = 0.0; // Start tightening at this profit (x initial risk; 0 = off)
input double InpFlowTrailTightenFullR = 0.0; // Fully tightened at this profit (x initial risk)
input double InpFlowBreakevenAtR = 0.0; // Lock in breakeven at this profit (x initial risk; 0 = off)
input double InpFlowBreakevenOffsetR = 0.0; // Where the locked stop sits (x initial risk from entry)

input group "04. Risk and account limits"
input double InpFlowRiskPct = 1.0; // Risk per trade (% of balance)
input double InpFlowMaxRiskPct = 3.5; // Maximum risk per trade (%)
input double InpFlowMaxAccountRiskPct = 6.0; // Maximum combined risk across the account (%)
input double InpFlowMaxDailyDDPct = 15.0; // Daily equity drop to pause new trades (%)
input bool   InpFlowUseTotalDDKillSwitch = true; // Use account drawdown emergency stop
input double InpFlowMaxTotalDDPct = 25.0; // Equity drop to trigger emergency stop (%)

input group "05. Trading hours"
input bool   InpFlowUseWeekendClose = false; // Close this bot's trades before the weekend
input int    InpFlowWeekendCloseHour = 20; // Friday closing hour (broker time, 0-23)
input int    InpFlowWeekendCloseMinute = 0; // Friday closing minute (0-59)

input group "06. Chart panel and logs"
input ENUM_BASE_CORNER InpFlowDashboardCorner = CORNER_LEFT_UPPER; // Chart panel corner
input int    InpFlowDashboardMarginX = 12; // Panel distance from left/right edge (pixels)
input int    InpFlowDashboardMarginY = 18; // Panel distance from top/bottom edge (pixels)
input bool   InpFlowVerboseLog = false; // Show detailed diagnostic logs
input bool   InpFlowDashboardCompact = false; // Start with a compact chart panel
input bool   InpFlowDashboardAnimate = true; // Animate live dashboard activity
input int    InpFlowDashboardSizePct = 125; // Dashboard size (125-200%; larger is easier to read)

// The band below is read ONLY by the filter above it. Grouped together so an
// operator can see that turning the filter off makes both numbers inert, rather
// than finding them under a heading that implies they always apply.
input group "07. Optional market-movement filter"
input bool   InpFlowUseVolatilityGate = false; // Only trade inside the movement band
input double InpFlowATRMinPoints = 80.0; // Filter: minimum movement (strategy points)
input double InpFlowATRMaxPoints = 800.0; // Filter: maximum movement (strategy points)

input group "08. Advanced - market calibration and costs"
input double InpFlowQuietMarketPct = 60.0; // Minimum market movement (% of normal)
input double InpFlowWildMarketPct = 600.0; // Maximum market movement (% of normal)
input double InpFlowEntrySlipPct = 25.0; // Entry price tolerance (% of smallest stop)
input double InpFlowExitSlipPct = 85.0; // Exit price tolerance (% of smallest stop)
input double InpFlowSpreadCapPct = 40.0; // Maximum spread (% of smallest stop)
input double InpFlowMaxSpreadATRPct = 10.0; // Maximum spread (% of average range)

input group "09. Advanced - broker and price checks"
input bool   InpFlowUseSpreadFilter = true; // Block entries when the spread is too wide
input bool   InpFlowUseStopLevelValidation = true; // Check broker minimum stop distance
input bool   InpFlowUseMarginCheck = true; // Check available margin before entering
input double InpFlowMarginBufferPct = 20.0; // Extra margin required (% of order margin)
input int    InpFlowMaxQuoteAgeSeconds = 15; // Maximum price age before refusing (seconds)

input group "10. Manual limits - only when auto-adapt is off"
input double InpFlowMaxSpreadPoints = 50.0; // Maximum spread (strategy points)
input double InpFlowEntryDeviationPoints = XSPARK_CANDLEFLOW_ENTRY_DEVIATION_POINTS; // Entry price tolerance (strategy points)
input double InpFlowExitDeviationPoints = XSPARK_CANDLEFLOW_EXIT_DEVIATION_POINTS; // Exit price tolerance (strategy points)

input group "11. Advanced - bot identity"
input ulong  InpFlowMagicNumber = XSPARK_CANDLEFLOW_MAGIC_DEFAULT; // Unique bot ID (use a different ID per chart)
input string InpFlowOrderComment = XSPARK_CANDLEFLOW_COMMENT_DEFAULT; // Trade label shown in account history

input group "12. Recovery - deliberate reset only"
input bool   InpFlowClearKillswitchLatch = false; // Reset emergency stop once (then set false)

// CandleFlow sends no take-profit, so the execution engine's reward-ratio
// bounds never apply to any plan it produces. The engine still validates its
// configuration at startup, so it is handed a trivially valid pair rather than
// a disabled one - a value it can never consume cannot mislead a reader.
#define XSPARK_FLOW_UNUSED_RR 1.0

CXSparkLogger          g_logger;
CXSparkMarketState     g_market_state;
CXSparkIndicatorCache  g_indicator_cache;
CXSparkSafetyManager   g_safety_manager;
CXSparkRiskManager     g_risk_manager;
CXSparkPositionSizer   g_position_sizer;
CXSparkExecutionEngine g_execution_engine;
CXSparkPositionManager g_position_manager;
CXSparkCandleFlow      g_strategy;
CXSparkDashboard       g_dashboard;

bool     g_state_purged = false;
ENUM_TIMEFRAMES g_base_timeframe = PERIOD_M30;
ENUM_TIMEFRAMES g_higher_timeframe = PERIOD_H2;

double g_score_point_size = XSPARK_XAUUSD_SCORE_POINT_SIZE;
bool   g_score_point_size_conforms = false;
string g_score_point_size_reason = "Strategy point size has not been resolved.";

bool   g_entry_drift_bound_usable = false;
string g_entry_drift_bound_reason = "Entry drift bound has not been evaluated.";

bool   g_auto_tune_complete = false;
XSparkAutoTuneResult g_auto_tune;

bool   g_config_valid = false;
string g_config_reason = "CandleFlow configuration has not been checked.";

int g_tester_sequence = 0;

datetime g_current_base_bar_time = 0;
datetime g_last_evaluated_signal_bar_time = 0;
double   g_latest_closed_atr14 = 0.0;

// The trailing anchors the whole exit rule rests on. Recomputed once per closed
// candle and held between bars, so a bar whose data could not be refreshed
// leaves the last known anchor in place rather than dropping the trail.
datetime g_bar_state_time = 0;
double   g_anchor_long = 0.0;
double   g_anchor_short = 0.0;
// The closed candle the anchors came from. PositionManager advances each
// position's chandelier peak from these, once per candle.
bool     g_closed_candle_ready = false;
double   g_closed_high = 0.0;
double   g_closed_low = 0.0;
datetime g_closed_time = 0;
XSparkTrailTuning g_trail_tuning;

string g_ui_decision_status = "", g_ui_decision_reason = "";
string g_ui_entry_style = "Single-factor candle";
string   g_status = "SCANNING";
string   g_last_block_reason = "Waiting for the next closed candle.";
long     g_state_recovery_position_id = 0;
datetime g_state_recovery_signal_bar_time = 0;
datetime g_state_recovery_last_log_time = 0;
XSparkScoreBotReport g_last_report;

#define XSPARK_FLOW_STATE_RECOVERY_LOG_INTERVAL_SECONDS 30

string XSparkFlowBoolToString(const bool value)
{
   return value ? "true" : "false";
}

string XSparkFlowDeinitReasonToString(const int reason)
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

bool XSparkFlowValidateInputs()
{
   string timeframe_reason = "";
   if(!XSparkHigherTimeframeFor((ENUM_TIMEFRAMES)Period(), g_higher_timeframe, timeframe_reason))
   {
      g_logger.Critical("EA", timeframe_reason);
      return false;
   }

   g_base_timeframe = (ENUM_TIMEFRAMES)Period();

   // Zero and another shipped strategy's number are both refused: an EA that
   // adopts a Magic Number already claimed by a different bot manages that
   // bot's positions, which defeats every separation XSpark relies on.
   string magic_reason = "";
   if(!XSparkMagicIsAvailable(InpFlowMagicNumber, XSPARK_CANDLEFLOW_MAGIC_DEFAULT, magic_reason))
   {
      g_logger.Critical("EA", magic_reason);
      return false;
   }

   // Same reason as XSpark: per-position stops, a per-position state store and
   // independent trailing all assume one broker position per entry. Netting
   // merges them and defeats every one of those.
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_logger.Critical("EA", "XSparkFlow requires a hedging account; netting merges positions and defeats per-position management.");
      return false;
   }

   if(!XSparkTradeSlotsValid(InpFlowMaxOpenTrades))
   {
      g_logger.Critical("EA", "Maximum open trades must be between 1 and 10.");
      return false;
   }

   if(!MathIsValidNumber(InpFlowRiskPct) || InpFlowRiskPct <= 0.0 ||
      !MathIsValidNumber(InpFlowMaxRiskPct) || InpFlowMaxRiskPct <= 0.0 ||
      InpFlowRiskPct > InpFlowMaxRiskPct)
   {
      g_logger.Critical("EA", "Risk per trade must be positive and no greater than the maximum risk per trade.");
      return false;
   }

   if(InpFlowMaxRiskPct > XSPARK_MAX_ALLOWED_RISK_PCT)
   {
      g_logger.Critical("EA",
                        StringFormat("Maximum risk per trade %.2f%% exceeds the hard ceiling of %.2f%%.",
                                     InpFlowMaxRiskPct,
                                     XSPARK_MAX_ALLOWED_RISK_PCT));
      return false;
   }

   if(!MathIsValidNumber(InpFlowMaxAccountRiskPct) || InpFlowMaxAccountRiskPct <= 0.0)
   {
      g_logger.Critical("EA", "The account risk cap must be a positive percentage.");
      return false;
   }

   if(InpFlowWeekendCloseHour < 0 || InpFlowWeekendCloseHour > 23 ||
      InpFlowWeekendCloseMinute < 0 || InpFlowWeekendCloseMinute > 59)
   {
      g_logger.Critical("EA", "Weekend close time must be a valid hour and minute.");
      return false;
   }

   if(InpFlowEntryDeviationPoints <= 0.0 || InpFlowExitDeviationPoints <= 0.0)
   {
      g_logger.Critical("EA", "Entry and exit price tolerances must be positive.");
      return false;
   }

   return true;
}

// Resolves the strategy point size for the chart symbol. Identical policy to
// XSpark: an untrusted size blocks new entries but never stops OnTick, because
// stopping OnTick would abandon the trailing stop of a live position.
void XSparkFlowResolveSessionScorePointSize()
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

string XSparkFlowStatusFromSafety()
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

void XSparkFlowUpdateDashboard()
{
   if(!g_dashboard.NeedsRefresh()) return;
   const string mode = InpFlowEnableTrading ? "TRADING" : "ANALYSIS ONLY";
   XSparkDashboardLive live;
   live.symbol = _Symbol; live.timeframe = EnumToString(g_base_timeframe);
   StringReplace(live.timeframe, "PERIOD_", "");
   live.currency = AccountInfoString(ACCOUNT_CURRENCY); live.entry_style = g_ui_entry_style;
   live.digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   live.connected = TerminalInfoInteger(TERMINAL_CONNECTED) != 0;
   live.animate = InpFlowDashboardAnimate; live.bid = 0; live.ask = 0; live.quote_age = -1; live.quote_stamp = 0;
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
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpFlowMagicNumber) continue;
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
      dashboard_reason = StringFormat("%d of %d XSparkFlow position(s) have no trustworthy entry risk; trailing is disabled for them.",
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
   else if(!g_safety_manager.ScorePointSizeConforms())
   { dashboard_status = "POINT SIZE FAULT"; dashboard_reason = "Instrument price units are not trusted."; }
   else if(!g_safety_manager.EntryDriftBoundUsable() && (!InpFlowAutoTuneForSymbol || g_auto_tune_complete))
   { dashboard_status = "DRIFT GATE FAULT"; dashboard_reason = "Entry price tolerance cannot safely bound risk."; }
   else if(g_safety_manager.DailyHaltLatched())
   { dashboard_status = "DD HALT"; dashboard_reason = "Daily DD halt is latched for the broker day."; }
   else if(!live.connected)
   { dashboard_status = "DISCONNECTED"; dashboard_reason = "Terminal is not connected."; }
   else if(!live.quote_valid || live.quote_age < 0 || live.quote_age > InpFlowMaxQuoteAgeSeconds)
   { dashboard_status = "STALE QUOTE"; dashboard_reason = "Waiting for fresh broker prices."; }
   else if(!live.positions_valid)
   { dashboard_status = "STATE RECOVERY"; dashboard_reason = "Cannot read the broker position snapshot."; }
   else if(InpFlowEnableTrading && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
   { dashboard_status = "TRADING PERMISSION"; dashboard_reason = "Terminal trading is not allowed."; }
   else if(!InpFlowEnableTrading)
   { dashboard_status = "TRADING DISABLED"; dashboard_reason = "Trading disabled by input."; }

   g_dashboard.Update(g_last_report,
                      g_safety_manager,
                      AccountInfoDouble(ACCOUNT_EQUITY),
                      g_position_manager.TradesToday(),
                      g_position_manager.TradesLast24Hours(),
                      g_position_manager.ManagedPositionCount(),
                      InpFlowMaxOpenTrades,
                      XSparkPriceToScorePoints(g_market_state.SpreadPrice(), g_score_point_size),
                      mode,
                      dashboard_status,
                      dashboard_reason, live);
}

// Machine-greppable record of a candle that did NOT become a trade. Emitted at
// most once per closed bar, so it cannot flood.
void XSparkFlowLogSignalRejection(const string stage,
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

void XSparkFlowVerboseBlock(const string component, const string reason)
{
   if(InpFlowVerboseLog)
      g_logger.Debug(component, reason);
}

// Turns a CandleFlow signal into a fundable, broker-valid plan.
//
// The strategy hands over the RAW candle anchor. The stop that decides the
// volume is bounded here, against the live quote, because that is the price the
// position is opened at - and because the floor that stops a thin candle from
// producing an oversized position is only meaningful measured from the fill.
bool XSparkFlowPrepareTradePlan(XSparkSignal &signal,
                                const double risk_pct,
                                XSparkTradePlan &plan)
{
   XSparkResetTradePlan(plan);

   if(signal.direction == XSPARK_SIGNAL_NONE)
   {
      g_last_block_reason = "Cannot prepare a trade plan for a NONE signal.";
      return false;
   }

   const double entry_reference = signal.direction == XSPARK_SIGNAL_BUY ?
                                  g_market_state.Ask() :
                                  g_market_state.Bid();

   if(entry_reference <= 0.0 || signal.desired_stop <= 0.0)
   {
      g_last_block_reason = "Entry reference or candle anchor is invalid.";
      return false;
   }

   double bounded_stop = 0.0;
   double bounded_distance = 0.0;
   string bound_reason = "";
   if(!XSparkCandleFlowStop(signal.direction,
                            entry_reference,
                            signal.desired_stop,
                            signal.atr14,
                            InpFlowMinStopATRMult,
                            InpFlowMaxStopATRMult,
                            bounded_stop,
                            bounded_distance,
                            bound_reason))
   {
      g_last_block_reason = bound_reason;
      return false;
   }

   double adjusted_sl = 0.0;
   double ignored_tp = 0.0;
   string adjust_reason = "";

   if(!XSparkAdjustProtectionLevels(signal.symbol,
                                    signal.direction,
                                    entry_reference,
                                    bounded_stop,
                                    0.0,
                                    InpFlowUseStopLevelValidation,
                                    adjusted_sl,
                                    ignored_tp,
                                    adjust_reason))
   {
      g_last_block_reason = adjust_reason;
      return false;
   }

   if(adjust_reason != "")
      XSparkFlowVerboseBlock("ExecutionEngine", adjust_reason);

   double risk_distance = MathAbs(entry_reference - adjusted_sl);
   if(risk_distance <= 0.0)
   {
      g_last_block_reason = "Adjusted stop distance is invalid.";
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
   plan.final_tp = 0.0; // no target, by design
   plan.risk_distance = risk_distance;
   plan.dynamic_rr = XSPARK_CANDLEFLOW_NO_TARGET_RR;
   plan.score = signal.score;
   plan.effective_threshold = signal.effective_threshold;
   plan.risk_pct = risk_pct;
   plan.volume = volume;
   plan.pattern_score = signal.pattern_score;
   plan.session_weight = signal.session_weight;
   plan.pattern_id = (EXSparkScoreBotPatternId)signal.pattern_id;
   plan.pattern_name = signal.pattern_name;

   double final_sl = 0.0;
   double final_tp = 0.0;
   string final_adjust_reason = "";

   if(!g_execution_engine.ValidateInitialProtection(plan,
                                                    InpFlowUseStopLevelValidation,
                                                    final_sl,
                                                    final_tp,
                                                    final_adjust_reason))
   {
      g_last_block_reason = final_adjust_reason;
      return false;
   }

   // Broker stop-level validation can move the stop once, which changes the
   // real stop distance and therefore the volume. One bounded recalculation,
   // then the result must be stable or the entry is refused.
   if(MathAbs(final_sl - plan.final_sl) > 0.0)
   {
      plan.final_sl = final_sl;
      plan.risk_distance = MathAbs(plan.entry_reference - plan.final_sl);

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

      if(!g_execution_engine.ValidateInitialProtection(plan,
                                                       InpFlowUseStopLevelValidation,
                                                       final_sl,
                                                       final_tp,
                                                       final_adjust_reason))
      {
         g_last_block_reason = final_adjust_reason;
         return false;
      }

      if(MathAbs(final_sl - plan.final_sl) > 0.0)
      {
         g_last_block_reason = "Stop-level validation remained unstable after risk recalculation.";
         return false;
      }
   }

   if(final_tp != 0.0)
   {
      g_last_block_reason = "Protection validation produced a take-profit for a no-target plan.";
      return false;
   }

   return true;
}

void XSparkFlowLogEntry(XSparkTradePlan &plan,
                        XSparkExecutionResult &result,
                        const bool registered_exactly)
{
   g_logger.Info("EA",
                 StringFormat("Entry confirmed direction=%s entry=%s SL=%s TP=none lots=%s risk=%.2f%% candle=%s anchor_stop=%s order=%I64u deal=%I64u position_id=%I64d exact=%s",
                              XSparkDirectionName(plan.direction),
                              DoubleToString(plan.entry_reference, g_market_state.Digits()),
                              DoubleToString(plan.final_sl, g_market_state.Digits()),
                              DoubleToString(plan.volume, 2),
                              plan.risk_pct,
                              TimeToString(plan.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              DoubleToString(plan.theoretical_sl, g_market_state.Digits()),
                              result.order_ticket,
                              result.deal_ticket,
                              result.position_id,
                              XSparkFlowBoolToString(registered_exactly)));
}

bool XSparkFlowAttemptStateRecovery()
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
      since_last_recovery_log >= XSPARK_FLOW_STATE_RECOVERY_LOG_INTERVAL_SECONDS)
   {
      g_logger.Critical("EA",
                        StringFormat("XSparkFlow state is still inconsistent with broker state; new entries remain blocked. coverage=%s recovered_position_id=%I64d tracked=%s",
                                     coverage_reason,
                                     g_state_recovery_position_id,
                                     XSparkFlowBoolToString(recovered_position_tracked)));
      g_state_recovery_last_log_time = now;
   }

   g_last_block_reason = "XSparkFlow state is inconsistent with broker state; new entries are blocked.";
   return false;
}

void XSparkFlowEnterStateRecovery(XSparkTradePlan &plan, XSparkExecutionResult &result)
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

   XSparkFlowAttemptStateRecovery();

   if(g_safety_manager.StateRecoveryLatched())
      return;

   g_last_block_reason = g_position_manager.LastRegistrationBoundState() ?
                         "Entry confirmed; state bound without exact broker identification, then verified by reconciliation." :
                         "Entry confirmed; state for the new position was rebuilt from broker values by reconciliation.";
}

// Derives the instrument-scaled thresholds from the instrument's own range.
// The stop multiple handed to the derivation is the CandleFlow stop FLOOR,
// because that is genuinely the smallest stop this configuration can produce -
// which is what every derived tolerance is measured against.
bool XSparkFlowCalibrateForSymbol()
{
   if(!InpFlowAutoTuneForSymbol || g_auto_tune_complete)
      return true;

   double samples[];
   const int copied = g_indicator_cache.CopyATR14BaseHistory(XSPARK_AUTOTUNE_SAMPLE_BARS, samples);

   if(copied <= 0)
   {
      g_last_block_reason = "No ATR history is available yet to calibrate this market.";
      return false;
   }

   double reference_price = 0.0;
   int valid_samples = 0;
   string median_reason = "";
   if(!XSparkSampleMedian(samples, copied, XSPARK_AUTOTUNE_MIN_SAMPLES,
                          reference_price, valid_samples, median_reason))
   {
      g_last_block_reason = "Market calibration is waiting: " + median_reason;
      return false;
   }

   const double reference_points = XSparkPriceToScorePoints(reference_price, g_score_point_size);

   string derive_reason = "";
   if(!XSparkDeriveAutoTune(reference_points,
                            InpFlowQuietMarketPct,
                            InpFlowWildMarketPct,
                            InpFlowMinStopATRMult,
                            InpFlowEntrySlipPct,
                            InpFlowExitSlipPct,
                            InpFlowSpreadCapPct,
                            g_auto_tune,
                            derive_reason))
   {
      g_last_block_reason = "Market calibration failed: " + derive_reason;
      g_logger.Critical("AutoTune", g_last_block_reason);
      return false;
   }

   if(!g_strategy.SetVolatilityBand(g_auto_tune.atr_min_points, g_auto_tune.atr_max_points) ||
      !g_safety_manager.SetMaxSpreadScorePoints(g_auto_tune.spread_cap_points) ||
      !g_execution_engine.SetEntryDeviationScorePoints(g_auto_tune.entry_deviation_points) ||
      !g_position_manager.SetExitDeviationScorePoints(g_auto_tune.exit_deviation_points))
   {
      g_last_block_reason = "A derived threshold was refused by the component that uses it; new entries stay blocked.";
      g_logger.Critical("AutoTune", g_last_block_reason);
      return false;
   }

   double bound_min_stop = 0.0;
   double bound_ratio = 0.0;
   string bound_reason = "";
   const int bound = XSparkEntryDriftBound(g_auto_tune.entry_deviation_points,
                                           InpFlowMinStopATRMult,
                                           g_auto_tune.atr_min_points,
                                           bound_min_stop,
                                           bound_ratio,
                                           bound_reason);

   g_entry_drift_bound_usable = bound != XSPARK_DRIFT_BOUND_FAULT;
   g_entry_drift_bound_reason = bound_reason;
   g_safety_manager.SetEntryDriftBound(g_entry_drift_bound_usable, g_entry_drift_bound_reason);

   if(bound == XSPARK_DRIFT_BOUND_FAULT)
   {
      g_logger.Critical("AutoTune", "Derived entry slippage does not bound realised risk: " + bound_reason);
      return false;
   }

   if(bound == XSPARK_DRIFT_BOUND_WARN)
      g_logger.Warn("AutoTune", bound_reason);

   g_auto_tune_complete = true;

   g_logger.Info("AutoTune",
                 StringFormat("Calibrated %s %s from %d of %d ATR samples: %s",
                              _Symbol,
                              EnumToString(g_base_timeframe),
                              valid_samples,
                              copied,
                              derive_reason));
   return true;
}

// Refreshes everything that changes once per closed candle: the indicator
// cache, the ATR used for the stop bounds, and the two trailing anchors.
//
// Runs BEFORE position management on the first tick of a new candle, so a live
// position is re-anchored on the same tick the candle closed on rather than the
// next one. A failed refresh keeps the previous anchors: a stop that cannot be
// tightened must stay where it is, never disappear.
bool XSparkFlowRefreshBarState(const datetime current_bar_time)
{
   if(current_bar_time != 0 && g_bar_state_time == current_bar_time)
      return true;

   if(!g_indicator_cache.RefreshClosedData())
   {
      g_last_block_reason = g_indicator_cache.LastReason();
      XSparkFlowVerboseBlock("IndicatorCache", g_last_block_reason);
      return false;
   }

   g_latest_closed_atr14 = g_indicator_cache.ATR14Base();

   double anchor_long = 0.0;
   double anchor_short = 0.0;
   string anchor_reason = "";

   if(g_strategy.TrailAnchors(g_indicator_cache, anchor_long, anchor_short, anchor_reason))
   {
      g_anchor_long = anchor_long;
      g_anchor_short = anchor_short;
      XSparkFlowVerboseBlock("CandleFlow", anchor_reason);

      XSparkCandle closed;
      if(g_indicator_cache.BaseBar(1, closed) && closed.high > 0.0 && closed.low > 0.0 && closed.time > 0)
      {
         g_closed_high = closed.high;
         g_closed_low = closed.low;
         g_closed_time = closed.time;
         g_closed_candle_ready = true;
      }
   }
   else
   {
      g_logger.Warn("CandleFlow",
                    "Trailing anchors could not be recomputed for this candle; the previous anchors stay in force: " + anchor_reason);
   }

   g_bar_state_time = current_bar_time;
   return true;
}

void XSparkFlowEvaluateNewBarCore()
{
   if(!XSparkFlowRefreshBarState(g_current_base_bar_time))
   {
      g_status = "SCANNING";
      return;
   }

   if(!XSparkFlowCalibrateForSymbol())
   {
      g_status = "SCANNING";
      XSparkFlowVerboseBlock("AutoTune", g_last_block_reason);
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
      XSparkFlowVerboseBlock("CandleFlow", g_last_block_reason);
      return;
   }

   g_last_evaluated_signal_bar_time = signal_bar.time;

   XSparkSignal signal;
   XSparkScoreBotReport report;
   const bool eligible_signal = g_strategy.Evaluate(g_indicator_cache, signal, report);
   g_last_report = report;
   g_last_report.selected_risk_pct = InpFlowRiskPct;

   g_logger.Info("CandleFlow",
                 StringFormat("bar=%s dir=%s O=%.8f H=%.8f L=%.8f C=%.8f atr=%.8f anchor=%.8f status=%s",
                              TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              XSparkDirectionName(report.direction),
                              report.context.bar1_open,
                              report.context.bar1_high,
                              report.context.bar1_low,
                              report.context.bar1_close,
                              report.atr14,
                              report.detected_level,
                              report.status));

   if(!eligible_signal)
   {
      g_status = report.status;
      g_last_block_reason = report.block_reason;
      XSparkFlowVerboseBlock("CandleFlow", g_last_block_reason);
      return;
   }

   if(!g_config_valid)
   {
      g_status = "CONFIG BLOCKED"; g_last_block_reason = g_config_reason;
      XSparkFlowLogSignalRejection("configuration", g_last_block_reason, report);
      return;
   }

   if(InpFlowUseWeekendClose &&
      g_position_manager.ShouldWeekendClose(g_market_state.ServerTime(),
                                            InpFlowWeekendCloseHour,
                                            InpFlowWeekendCloseMinute))
   {
      g_status = "WEEKEND CLOSE";
      g_last_block_reason = "Weekend close window is active; new entries are blocked.";
      XSparkFlowVerboseBlock("PositionManager", g_last_block_reason);
      return;
   }

   // Every candle produces a direction, so an opposite-direction candle arrives
   // constantly while a position is open. XSparkFlow does not reverse: the open
   // trade exits on its trailing stop and nothing else, so an opposing signal is
   // refused here rather than hedged into a second position.
   string exposure_reason = "";
   if(!XSparkDirectionIsUnopposed(_Symbol, InpFlowMagicNumber, signal.direction, exposure_reason))
   {
      g_status = "OPPOSING EXPOSURE"; g_last_block_reason = exposure_reason;
      XSparkFlowLogSignalRejection("exposure", exposure_reason, report);
      return;
   }

   if(!g_safety_manager.CanOpenNewTrades(g_position_manager.ManagedPositionCount(),
                                         g_market_state.SpreadPrice(),
                                         report.atr14))
   {
      g_status = XSparkFlowStatusFromSafety();
      g_last_block_reason = g_safety_manager.LastReason();
      XSparkFlowLogSignalRejection("safety", g_last_block_reason, report);

      if(g_status == "STALE QUOTE")
         g_logger.Warn("SafetyManager", g_last_block_reason);
      else
         XSparkFlowVerboseBlock("SafetyManager", g_last_block_reason);

      return;
   }

   double risk_pct = 0.0;
   if(!g_risk_manager.IsSignalApproved(signal, risk_pct))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_risk_manager.LastReason();
      XSparkFlowLogSignalRejection("risk", g_last_block_reason, report);
      XSparkFlowVerboseBlock("RiskManager", g_last_block_reason);
      return;
   }

   g_last_report.selected_risk_pct = risk_pct;

   XSparkTradePlan plan;
   if(!XSparkFlowPrepareTradePlan(signal, risk_pct, plan))
   {
      g_status = "SCANNING";
      XSparkFlowLogSignalRejection("plan", g_last_block_reason, report);
      XSparkFlowVerboseBlock("TradePlan", g_last_block_reason);
      return;
   }

   plan.planned_risk_distance = plan.risk_distance;

   // Account-level risk cap. Checked once the plan has a volume and a
   // broker-valid stop, because a cap checked against an estimate is not a cap.
   {
      double open_risk_cash = 0.0, own_risk_cash = 0.0, foreign_risk_cash = 0.0;
      int own_positions = 0;
      string account_risk_reason = "";

      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

      double prospective_risk_cash = 0.0;
      string prospective_reason = "";
      const bool prospective_known = XSparkPositionRiskCash(plan.entry_reference,
                                                            plan.final_sl,
                                                            plan.volume,
                                                            SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                                                            tick_value,
                                                            prospective_risk_cash,
                                                            prospective_reason);

      double projected_pct = 0.0;
      string cap_reason = "";

      if(!prospective_known ||
         !XSparkReadAccountExposure(_Symbol, InpFlowMagicNumber, open_risk_cash, own_risk_cash, foreign_risk_cash, own_positions, account_risk_reason) ||
         !XSparkAccountRiskWithinCap(open_risk_cash,
                                     prospective_risk_cash,
                                     AccountInfoDouble(ACCOUNT_BALANCE),
                                     InpFlowMaxAccountRiskPct,
                                     projected_pct,
                                     cap_reason))
      {
         g_status = "ACCOUNT RISK";
         g_last_block_reason = !prospective_known ? prospective_reason
                               : (account_risk_reason != "" ? account_risk_reason : cap_reason);

         g_last_block_reason += StringFormat(" [own_symbol_magic=%.2f other_positions=%.2f account currency]",
                                              own_risk_cash, foreign_risk_cash);
         XSparkFlowLogSignalRejection("account_risk", g_last_block_reason, report);
         g_logger.Warn("RiskManager",
                       StringFormat("Entry refused by the account risk cap: %s", g_last_block_reason));
         return;
      }
   }

   if(InpFlowUseMarginCheck)
   {
      double required_margin = 0.0;
      double free_margin = 0.0;
      string margin_reason = "";

      if(!g_execution_engine.HasSufficientMargin(plan.symbol,
                                                 plan.direction,
                                                 plan.volume,
                                                 plan.entry_reference,
                                                 InpFlowMarginBufferPct,
                                                 required_margin,
                                                 free_margin,
                                                 margin_reason))
      {
         g_status = "SCANNING";
         g_last_block_reason = margin_reason;
         XSparkFlowVerboseBlock("ExecutionEngine", g_last_block_reason);
         return;
      }
   }

   if(!g_execution_engine.CanSubmitSignal(plan.signal_bar_time))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkFlowVerboseBlock("ExecutionEngine", g_last_block_reason);
      return;
   }

   XSparkExecutionResult execution_result;
   if(!g_execution_engine.ExecuteApprovedPlan(plan, g_position_sizer, execution_result, g_logger))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      return;
   }

   const bool registered_exactly = g_position_manager.RegisterNewTrade(plan, execution_result, g_logger);

   g_dashboard.AnnotateEntry(plan, execution_result);
   XSparkFlowLogEntry(plan, execution_result, registered_exactly);

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

   XSparkFlowEnterStateRecovery(plan, execution_result);
}

void XSparkFlowEvaluateNewBar()
{
   XSparkFlowEvaluateNewBarCore();
   g_ui_decision_status = g_status; g_ui_decision_reason = g_last_block_reason;
}

int OnInit()
{
   XSparkResetScoreBotReport(g_last_report);
   g_last_report.pattern_mode = "SINGLE FACTOR";
   g_logger.Initialize("XSparkFlow", InpFlowVerboseLog);
   g_logger.Info("EA", "Starting XSparkFlow CandleFlow");

   if(!XSparkFlowValidateInputs())
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

   XSparkFlowResolveSessionScorePointSize();

   XSparkCandleFlowConfig config;
   XSparkDefaultCandleFlowConfig(config);
   config.buffer_atr_mult = InpFlowBufferATRMult;
   config.buffer_range_pct = InpFlowBufferRangePct;
   config.buffer_fixed_price = XSparkScorePointsToPrice(InpFlowBufferPoints, g_score_point_size);
   config.min_stop_atr_mult = InpFlowMinStopATRMult;
   config.max_stop_atr_mult = InpFlowMaxStopATRMult;
   config.min_body_atr_mult = InpFlowMinBodyATRMult;
   config.use_volatility_gate = InpFlowUseVolatilityGate;
   config.atr_min_points = InpFlowATRMinPoints;
   config.atr_max_points = InpFlowATRMaxPoints;
   config.score_point_size = g_score_point_size;

   XSparkResetTrailTuning(g_trail_tuning);
   g_trail_tuning.min_trail_atr_mult = InpFlowMinTrailATRMult;
   g_trail_tuning.chandelier_atr_mult = InpFlowTrailATRMult;
   g_trail_tuning.chandelier_tight_atr_mult = InpFlowTrailTightATRMult;
   g_trail_tuning.tighten_start_r = InpFlowTrailTightenStartR;
   g_trail_tuning.tighten_full_r = InpFlowTrailTightenFullR;
   g_trail_tuning.breakeven_at_r = InpFlowBreakevenAtR;
   g_trail_tuning.breakeven_offset_r = InpFlowBreakevenOffsetR;

   g_config_valid = XSparkValidateCandleFlowConfig(config, g_config_reason);

   // The trailing stop is CandleFlow's only exit, so a configuration it cannot
   // honour blocks new entries rather than being quietly ignored. Positions
   // already open keep trailing on whatever the last accepted plan was.
   string trail_reason = "";
   if(!XSparkValidateTrailTuning(g_trail_tuning, trail_reason))
   {
      g_config_valid = false;
      g_config_reason += " " + trail_reason;
   }
   if(!g_config_valid)
      g_logger.Critical("CandleFlow", g_config_reason + " New entries blocked; existing positions remain managed.");

   g_strategy.Configure(config);

   if(!g_strategy.Initialize(_Symbol))
   {
      g_logger.Critical("CandleFlow", g_strategy.LastReason());
      return INIT_FAILED;
   }

   if(!g_safety_manager.Initialize(_Symbol,
                                   InpFlowMagicNumber,
                                   InpFlowEnableTrading,
                                   InpFlowMaxOpenTrades,
                                   InpFlowUseSpreadFilter,
                                   InpFlowMaxSpreadPoints,
                                   InpFlowMaxSpreadATRPct,
                                   InpFlowUseTotalDDKillSwitch,
                                   InpFlowMaxTotalDDPct,
                                   InpFlowMaxDailyDDPct,
                                   InpFlowMaxQuoteAgeSeconds,
                                   InpFlowClearKillswitchLatch,
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
   // CandleFlow has no score to grade exposure by, so the tier lookup must not
   // be able to change the answer.
   if(!g_risk_manager.Initialize(InpFlowRiskPct,
                                 InpFlowRiskPct,
                                 InpFlowRiskPct,
                                 InpFlowMaxRiskPct,
                                 InpFlowMaxOpenTrades,
                                 InpFlowMaxAccountRiskPct))
   {
      g_logger.Critical("RiskManager", g_risk_manager.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_sizer.Initialize())
   {
      g_logger.Critical("PositionSizer", "Failed to initialize position sizer");
      return INIT_FAILED;
   }

   if(!g_execution_engine.Initialize(InpFlowMagicNumber,
                                     InpFlowOrderComment,
                                     InpFlowEntryDeviationPoints,
                                     g_score_point_size,
                                     InpFlowUseStopLevelValidation,
                                     InpFlowUseMarginCheck,
                                     InpFlowMarginBufferPct,
                                     XSPARK_FLOW_UNUSED_RR,
                                     XSPARK_FLOW_UNUSED_RR,
                                     InpFlowMaxQuoteAgeSeconds,
                                     InpFlowMaxOpenTrades,
                                     InpFlowMaxAccountRiskPct))
   {
      g_logger.Critical("ExecutionEngine", g_execution_engine.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_manager.Initialize(_Symbol,
                                     InpFlowMagicNumber,
                                     g_score_point_size,
                                     InpFlowExitDeviationPoints,
                                     InpFlowUseStopLevelValidation))
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

   const double concurrent_cap = XSparkConcurrentRiskCap(InpFlowMaxOpenTrades, InpFlowMaxRiskPct, InpFlowMaxAccountRiskPct);
   g_logger.Info("RiskManager",
                 StringFormat("Trade slots=%d; per-entry risk %.2f%%; per-entry ceiling %.3f%%; account cap %.2f%%.",
                              InpFlowMaxOpenTrades, InpFlowRiskPct, concurrent_cap, InpFlowMaxAccountRiskPct));

   g_logger.Info("CandleFlow",
                 StringFormat("Trail: floor %.2f x range; peak trail %s; tightening %s; breakeven %s.",
                              InpFlowMinTrailATRMult,
                              InpFlowTrailATRMult > 0.0 ? DoubleToString(InpFlowTrailATRMult, 2) + " x range" : "off",
                              InpFlowTrailTightenStartR > 0.0
                                 ? StringFormat("%.2f x range from %.2fR to %.2fR",
                                                InpFlowTrailTightATRMult, InpFlowTrailTightenStartR, InpFlowTrailTightenFullR)
                                 : "off",
                              InpFlowBreakevenAtR > 0.0
                                 ? StringFormat("at %.2fR, stop %.2fR from entry", InpFlowBreakevenAtR, InpFlowBreakevenOffsetR)
                                 : "off"));

   g_logger.Info("CandleFlow",
                 StringFormat("Rule: closed %s candle direction; no take-profit; stop beyond the wick by %.2f x range + %.2f%% of the candle + %.2f points; "
                              "stop floor %.2f x range; ceiling %s; body filter %s; movement gate %s.",
                              EnumToString(g_base_timeframe),
                              InpFlowBufferATRMult,
                              InpFlowBufferRangePct,
                              InpFlowBufferPoints,
                              InpFlowMinStopATRMult,
                              InpFlowMaxStopATRMult > 0.0 ? DoubleToString(InpFlowMaxStopATRMult, 2) : "off",
                              InpFlowMinBodyATRMult > 0.0 ? DoubleToString(InpFlowMinBodyATRMult, 2) : "off",
                              XSparkFlowBoolToString(InpFlowUseVolatilityGate)));

   g_current_base_bar_time = iTime(_Symbol, g_base_timeframe, 0);
   EventSetTimer(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE) ? 5 : 1);
   g_dashboard.Configure(InpFlowDashboardCorner, InpFlowDashboardMarginX, InpFlowDashboardMarginY, InpFlowDashboardCompact, InpFlowDashboardAnimate, InpFlowDashboardSizePct);
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
                                    XSparkFlowBoolToString(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0)));

   g_logger.Info("EA", "Startup complete. Waiting for the next closed candle before the first evaluation.");
   XSparkFlowUpdateDashboard();

   return INIT_SUCCEEDED;
}

// Strategy Tester optimisation fitness, in R. OnTester() runs BEFORE OnDeinit(),
// so the flush of trades that closed but were not yet detected happens here.
double OnTester()
{
   g_position_manager.Reconcile(g_logger);

   g_tester_sequence++;
   g_logger.Info("Tester", StringFormat("OnTester ran at sequence position %d.", g_tester_sequence));

   const int trades = g_position_manager.RecordedTradeCount();
   const int live_at_end = g_position_manager.LiveManagedCount();
   const double fitness = g_position_manager.RecordedFitness(XSPARK_FITNESS_PENALTY_K,
                                                             XSPARK_FITNESS_MIN_TRADES);

   g_logger.Info("Tester",
                 StringFormat("Pass result: recorded_trades=%d live_at_end=%d mean_R=%.4f stdev_R=%.4f min_R=%.4f max_R=%.4f fitness=%.6f",
                              trades,
                              live_at_end,
                              g_position_manager.RecordedMeanR(),
                              g_position_manager.RecordedStdDevR(),
                              g_position_manager.RecordedMinR(),
                              g_position_manager.RecordedMaxR(),
                              fitness));

   return fitness;
}

void OnDeinit(const int reason)
{
   g_tester_sequence++;
   g_logger.Info("Tester", StringFormat("OnDeinit ran at sequence position %d.", g_tester_sequence));

   EventKillTimer();
   g_indicator_cache.Deinitialize();
   g_strategy.Deinitialize();
   const bool teardown = reason == REASON_REMOVE ||
                         reason == REASON_CHARTCLOSE ||
                         reason == REASON_PROGRAM;
   g_dashboard.Deinitialize(teardown);
   g_logger.Info("EA", StringFormat("Shutdown reason=%s (%d)",
                                    XSparkFlowDeinitReasonToString(reason),
                                    reason));
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(g_dashboard.HandleEvent(id, sparam)) XSparkFlowUpdateDashboard();
}

void OnTimer()
{
   XSparkFlowUpdateDashboard();
}

void OnTick()
{
   const bool market_state_valid = g_market_state.Refresh();

   datetime server_time = TimeTradeServer();
   if(server_time == 0)
      server_time = TimeCurrent();

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
         XSparkFlowAttemptStateRecovery();

      XSparkFlowUpdateDashboard();
      return;
   }

   const datetime current_bar_time = iTime(_Symbol, g_base_timeframe, 0);

   // Re-anchor BEFORE managing, so a candle that just closed tightens the stop
   // on this tick rather than the next one.
   if(current_bar_time != 0)
      XSparkFlowRefreshBarState(current_bar_time);

   // Rebuilt every tick rather than cached: the anchors and the closed-candle
   // extremes change together on a candle boundary, and a plan that carried one
   // without the other would trail against two different candles.
   XSparkTrailPlan trail_plan;
   XSparkResetTrailPlan(trail_plan);
   trail_plan.mode = XSPARK_TRAIL_CANDLE_ANCHOR;
   trail_plan.anchor_long = g_anchor_long;
   trail_plan.anchor_short = g_anchor_short;
   trail_plan.closed_candle_ready = g_closed_candle_ready;
   trail_plan.closed_high = g_closed_high;
   trail_plan.closed_low = g_closed_low;
   trail_plan.closed_time = g_closed_time;
   trail_plan.atr = g_latest_closed_atr14;
   trail_plan.tuning = g_trail_tuning;

   if(!g_position_manager.SetTrailPlan(trail_plan))
      g_logger.Critical("PositionManager",
                        "Trailing-stop settings were refused; open stops are left exactly where they are: " +
                        g_position_manager.LastReason());

   g_position_manager.ManagePositions(g_market_state.Bid(),
                                      g_market_state.Ask(),
                                      g_latest_closed_atr14,
                                      0.0,   // no partial close
                                      0.0,   // no partial close
                                      0.0,   // no ATR trail
                                      InpFlowUseWeekendClose,
                                      InpFlowWeekendCloseHour,
                                      InpFlowWeekendCloseMinute,
                                      g_logger);

   if(!g_state_purged && TerminalInfoInteger(TERMINAL_CONNECTED) != 0)
   {
      g_position_manager.PurgeOrphanedState(g_logger);
      g_state_purged = true;
   }

   if(g_safety_manager.StateRecoveryLatched())
      XSparkFlowAttemptStateRecovery();

   if(current_bar_time == 0)
   {
      g_status = "SCANNING";
      g_last_block_reason = "Current candle timestamp is unavailable.";
      XSparkFlowUpdateDashboard();
      return;
   }

   if(g_current_base_bar_time == 0)
   {
      g_current_base_bar_time = current_bar_time;
      g_status = "SCANNING";
      g_last_block_reason = "Initialized current candle timestamp; waiting for the next close.";
      XSparkFlowUpdateDashboard();
      return;
   }

   if(current_bar_time != g_current_base_bar_time)
   {
      g_current_base_bar_time = current_bar_time;
      XSparkFlowEvaluateNewBar();
   }
   else if(g_position_manager.ManagedPositionCount() > 0 &&
           !g_safety_manager.TotalDDKillSwitchLatched() &&
           !g_safety_manager.StateRecoveryLatched())
   {
      g_status = "MANAGING";
      g_last_block_reason = "Managing existing XSparkFlow positions.";
   }

   if(g_safety_manager.StateRecoveryLatched() && !g_safety_manager.TotalDDKillSwitchLatched())
   {
      g_status = "STATE RECOVERY";
      g_last_block_reason = "XSparkFlow state recovery is active: " + g_safety_manager.StateRecoveryReason();
   }

   XSparkFlowUpdateDashboard();
}
