#property version     "1.00"
#property description "XSpark Expert Advisor with ScoreBot_v3 MAX_SHARPE strategy."

#include <XSpark/Core/IndicatorCache.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/MarketState.mqh>
#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Execution/ExecutionEngine.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Risk/RiskManager.mqh>
#include <XSpark/Strategy/ScoreBotV3.mqh>
#include <XSpark/Trade/PositionManager.mqh>
#include <XSpark/UI/Dashboard.mqh>

input group "General"
input bool   InpEnableTrading = false;
input ulong  InpMagicNumber = XSPARK_SCOREBOT_MAGIC_DEFAULT;
input string InpOrderComment = XSPARK_SCOREBOT_COMMENT_DEFAULT;
input int    InpMaxOpenTrades = 1;
input bool   InpVerboseLog = false;

input group "Strategy"
input double InpMinScore = 2.0;
input bool   InpDropIBR = false;
input double InpLongScoreExtra = 0.0;

input group "RSI"
input int InpRSILongMin = 40;
input int InpRSILongMax = 70;
input int InpRSIShortMin = 30;
input int InpRSIShortMax = 60;

input group "ATR / exits"
input double InpATRMinPoints = 80.0;
input double InpATRMaxPoints = 800.0;
input double InpATRMultSL = 1.5;
input double InpMinRR = 1.5;
input double InpMaxRR = 3.0;
input double InpATRRatioBoost = 1.3;
input double InpPartialTPRatio = 2.5;
input double InpPartialClosePct = 50.0;
input double InpATRMultTrail = 2.0;

input group "Risk"
// Defaults are the growth-optimal region for the edge measured in
// docs/IMPROVEMENT_PLAN.md (36% win rate, 1.974 payoff, +0.0706 R per trade),
// which puts the Kelly fraction at 3.58%. Growth per trade PEAKS there and
// falls away above it: 10% risk turns a genuinely positive edge into a
// decaying account, because compounding is multiplicative. See ADR-022.
//
// The tiers are flat by default. Tier selection reads the session-weighted
// score, so identical evidence would otherwise size differently purely by the
// hour of day, and at a larger risk figure that distortion is amplified. The
// inputs remain separate so tiering can be reinstated deliberately.
input double InpRiskPctTier1 = 3.0;
input double InpRiskPctTier2 = 3.0;
input double InpRiskPctTier3 = 3.0;
input double InpMaxRiskPct = 3.5;
input double InpMaxDailyDDPct = 15.0;

input group "Sessions"
input bool InpAllowAsianReduced = true;

input group "Production controls"
input bool   InpUseSpreadFilter = true;
input double InpMaxSpreadPoints = 50.0;
input double InpMaxSpreadATRPct = 10.0;
input bool   InpUseTotalDDKillSwitch = true;
// Sized to survive an ordinary losing streak at the configured risk rather than
// to feel small. At 3% risk, eight consecutive full-stop losses - the streak
// the baseline run already produced - cost 21.6%. An 8% limit would latch on
// the third loss and stop the account permanently on routine variance. The
// startup log prints the exact tolerance for whatever values are set.
input double InpMaxTotalDDPct = 25.0;
// Clears a PERSISTED killswitch latch. The latch now survives restarts, so
// this is the only way to resume after one. Set it true, attach, confirm the
// CRITICAL line, then set it back to false.
input bool   InpClearKillswitchLatch = false;
input bool   InpUseStopLevelValidation = true;
input bool   InpUseMarginCheck = true;
input double InpMarginBufferPct = 20.0;
input int    InpMaxQuoteAgeSeconds = 15;

// Slippage tolerances, in ScoreBot points (the pip of the instrument: 0.01 on
// gold, 0.0001 on a 5-digit FX major, 0.01 on a 3-digit JPY cross). These were
// compile-time constants tuned for gold, which made them silently wrong on
// every other instrument - 30 points against a gold stop of at least 120 is a
// bound, the same 30 pips against a 15-pip FX stop is not. See ADR-024.
//
// Entry: how far the fill may drift from the price the order was SIZED
// against. Because the stop is placed relative to that same price, this is
// also the amount by which a permitted fill can push realised risk past
// selected risk. Smaller is tighter risk control at the cost of more rejected
// entries. The startup drift-bound line reports what the current value is
// worth as a percentage, and a value that no longer bounds anything is a
// DRIFT GATE FAULT.
input double InpEntryDeviationPoints = XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS;

// Exit: deliberately NOT subject to the same check, and deliberately larger.
// A tolerance that is too small on an exit gets the close REJECTED, which
// leaves live exposure that XSpark intended to be flat - the opposite of a
// risk control. Generosity here is protective, so only a non-positive value is
// refused.
input double InpExitDeviationPoints = XSPARK_CLOSE_DEVIATION_SCORE_POINTS;

input bool   InpUseWeekendClose = false;
input int    InpWeekendCloseHour = 20;
input int    InpWeekendCloseMinute = 0;

CXSparkLogger          g_logger;
CXSparkMarketState     g_market_state;
CXSparkIndicatorCache  g_indicator_cache;
CXSparkSafetyManager   g_safety_manager;
CXSparkRiskManager     g_risk_manager;
CXSparkPositionSizer   g_position_sizer;
CXSparkExecutionEngine g_execution_engine;
CXSparkPositionManager g_position_manager;
CXSparkScoreBotV3      g_strategy;
CXSparkDashboard       g_dashboard;

bool     g_state_purged = false;
// Resolved once in OnInit and never re-read from the terminal. A conversion on
// the killswitch flatten path runs while the quote feed is unusable, so the
// size must already be held rather than fetched at the moment it is needed.
ENUM_TIMEFRAMES g_base_timeframe = XSPARK_SCOREBOT_TESTED_BASE_TIMEFRAME;
ENUM_TIMEFRAMES g_higher_timeframe = XSPARK_SCOREBOT_TESTED_HIGHER_TIMEFRAME;

double g_score_point_size = XSPARK_XAUUSD_SCORE_POINT_SIZE;
bool   g_score_point_size_conforms = false;
string g_score_point_size_reason = "ScoreBot point size has not been resolved.";

// Whether the entry deviation still bounds realised risk at the configured ATR
// floor and stop multiple. Decidable from configuration alone, so it is settled
// once at initialisation rather than re-derived per signal.
bool   g_entry_drift_bound_usable = false;
string g_entry_drift_bound_reason = "Entry drift bound has not been evaluated.";

datetime g_current_base_bar_time = 0;
datetime g_last_evaluated_signal_bar_time = 0;
double   g_latest_closed_atr14 = 0.0;
string   g_status = "SCANNING";
string   g_last_block_reason = "Waiting for the next closed base timeframe bar.";
long     g_state_recovery_position_id = 0;
datetime g_state_recovery_signal_bar_time = 0;
datetime g_state_recovery_last_log_time = 0;
XSparkScoreBotReport g_last_report;

#define XSPARK_STATE_RECOVERY_LOG_INTERVAL_SECONDS 30

string XSparkBoolToString(const bool value)
{
   return value ? "true" : "false";
}

string XSparkDeinitReasonToString(const int reason)
{
   switch(reason)
   {
      case REASON_PROGRAM:
         return "program requested removal";
      case REASON_REMOVE:
         return "removed from chart";
      case REASON_RECOMPILE:
         return "recompiled";
      case REASON_CHARTCHANGE:
         return "chart symbol or period changed";
      case REASON_CHARTCLOSE:
         return "chart closed";
      case REASON_PARAMETERS:
         return "input parameters changed";
      case REASON_ACCOUNT:
         return "account changed";
      case REASON_TEMPLATE:
         return "template applied";
      case REASON_INITFAILED:
         return "initialization failed";
      case REASON_CLOSE:
         return "terminal closed";
      default:
         return "unknown";
   }
}

bool XSparkValidateInputs()
{
   // The instrument guard is lifted: the ScoreBot point size is now derived from
   // the broker specification for any symbol (see ADR-021). The chart period is
   // still validated, because an unsupported period has no multi-timeframe
   // partner and the strategy cannot be evaluated at all without one. Refusing a
   // chart the EA cannot analyse is the same posture the M15 guard had; it is not
   // the runtime-fault case ADR-020 keeps out of OnInit.
   string timeframe_reason = "";
   if(!XSparkHigherTimeframeFor((ENUM_TIMEFRAMES)Period(), g_higher_timeframe, timeframe_reason))
   {
      g_logger.Critical("EA", timeframe_reason);
      return false;
   }

   g_base_timeframe = (ENUM_TIMEFRAMES)Period();

   if(InpMagicNumber == 0)
   {
      g_logger.Critical("EA", "Magic Number must be explicit and non-zero.");
      return false;
   }

   // The whole position model is per-trade: independent tickets, per-position stops,
   // partial closes and a per-position state store keyed on POSITION_IDENTIFIER. A
   // netting account merges same-symbol trades into one position with a blended
   // entry, which silently defeats every one of those. Refuse rather than mis-manage.
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_logger.Critical("EA", "XSpark requires a hedging account; netting merges positions and defeats per-position management.");
      return false;
   }

   if(InpMaxOpenTrades != 1 && InpMaxOpenTrades != 2)
   {
      g_logger.Critical("EA", "InpMaxOpenTrades must be 1 or 2.");
      return false;
   }

   if(InpMinScore < 0.0 || InpLongScoreExtra < 0.0)
   {
      g_logger.Critical("EA", "Strategy score thresholds must be non-negative.");
      return false;
   }

   // InpLongScoreExtra raises the BUY threshold only, so only InpMinScore on its own
   // can put both directions out of reach. Raising the long threshold past the
   // ceiling is a legitimate short-only configuration, not an error.
   if(InpMinScore > XSPARK_SCOREBOT_MAX_SCORE)
   {
      g_logger.Critical("EA",
                        StringFormat("InpMinScore %.2f exceeds the maximum reachable score %.2f; no trade could ever qualify.",
                                     InpMinScore,
                                     XSPARK_SCOREBOT_MAX_SCORE));
      return false;
   }

   if(InpMinScore + InpLongScoreExtra > XSPARK_SCOREBOT_MAX_SCORE)
   {
      g_logger.Warn("EA",
                    StringFormat("InpMinScore + InpLongScoreExtra (%.2f) exceeds the maximum reachable score %.2f; long entries can never qualify and XSpark will trade short only.",
                                 InpMinScore + InpLongScoreExtra,
                                 XSPARK_SCOREBOT_MAX_SCORE));
   }

   if(InpRSILongMin < 0 || InpRSILongMax > 100 || InpRSILongMin > InpRSILongMax ||
      InpRSIShortMin < 0 || InpRSIShortMax > 100 || InpRSIShortMin > InpRSIShortMax)
   {
      g_logger.Critical("EA", "RSI input ranges are invalid.");
      return false;
   }

   if(InpATRMinPoints <= 0.0 || InpATRMaxPoints <= InpATRMinPoints ||
      InpATRMultSL <= 0.0 || InpMinRR <= 0.0 || InpMaxRR < InpMinRR ||
      InpATRRatioBoost <= 0.7 || InpPartialTPRatio <= 0.0 ||
      InpPartialClosePct <= 0.0 || InpPartialClosePct >= 100.0 ||
      InpATRMultTrail <= 0.0)
   {
      g_logger.Critical("EA", "ATR/exit inputs are invalid.");
      return false;
   }

   // Risk inputs were previously checked only for positivity, so a fat-fingered
   // 30.0 was accepted in silence. Every one now carries an upper bound.
   if(InpRiskPctTier1 <= 0.0 || InpRiskPctTier2 <= 0.0 ||
      InpRiskPctTier3 <= 0.0 || InpMaxRiskPct <= 0.0 ||
      InpMaxDailyDDPct <= 0.0)
   {
      g_logger.Critical("EA", "Risk inputs are invalid.");
      return false;
   }

   if(InpRiskPctTier1 > XSPARK_MAX_ALLOWED_RISK_PCT ||
      InpRiskPctTier2 > XSPARK_MAX_ALLOWED_RISK_PCT ||
      InpRiskPctTier3 > XSPARK_MAX_ALLOWED_RISK_PCT ||
      InpMaxRiskPct > XSPARK_MAX_ALLOWED_RISK_PCT)
   {
      g_logger.Critical("EA",
                        StringFormat("Risk per trade above %.1f%% is refused. Growth per trade peaks near the Kelly "
                                     "fraction and turns negative well below this ceiling, so a larger figure trades "
                                     "faster toward ruin, not toward profit. See ADR-022.",
                                     XSPARK_MAX_ALLOWED_RISK_PCT));
      return false;
   }

   if(InpMaxSpreadPoints <= 0.0 || InpMaxSpreadATRPct <= 0.0 ||
      InpMaxTotalDDPct <= 0.0 || InpMarginBufferPct < 0.0)
   {
      g_logger.Critical("EA", "Production-control inputs are invalid.");
      return false;
   }

   // A daily limit at or above the total limit can never bind, which would
   // silently remove the shorter-horizon brake entirely.
   if(InpMaxTotalDDPct >= 100.0 || InpMaxDailyDDPct >= 100.0 ||
      InpMaxDailyDDPct >= InpMaxTotalDDPct)
   {
      g_logger.Critical("EA",
                        "Drawdown limits are invalid: both must be below 100% and the daily limit must be "
                        "strictly below the total limit, or the daily halt can never fire.");
      return false;
   }

   // The killswitch must survive an ordinary losing streak at the configured
   // risk, or it converts routine variance into a permanent stop. Refusing is
   // wrong here - the operator may want a tight limit deliberately - but it
   // must never be a surprise, so it is stated loudly at startup.
   const int losses_to_killswitch = XSparkConsecutiveLossesToDrawdown(InpMaxRiskPct, InpMaxTotalDDPct);
   const int losses_to_daily_halt = XSparkConsecutiveLossesToDrawdown(InpMaxRiskPct, InpMaxDailyDDPct);

   g_logger.Info("EA",
                 StringFormat("Risk tolerance at max %.2f%% per trade: %d consecutive full-stop losses latch the "
                              "%.1f%% killswitch, %d latch the %.1f%% daily halt.",
                              InpMaxRiskPct,
                              losses_to_killswitch,
                              InpMaxTotalDDPct,
                              losses_to_daily_halt,
                              InpMaxDailyDDPct));

   if(losses_to_killswitch > 0 && losses_to_killswitch < XSPARK_MIN_LOSS_STREAK_TOLERANCE)
   {
      g_logger.Warn("EA",
                    StringFormat("The killswitch latches after only %d consecutive losses. The reference run in "
                                 "docs/IMPROVEMENT_PLAN.md contained an 8-loss streak, which at a 64%% loss rate is "
                                 "roughly the MEDIAN longest run over 50 trades rather than a tail event. Expect the "
                                 "killswitch to fire on ordinary variance at these settings.",
                                 losses_to_killswitch));
   }

   if(InpMaxQuoteAgeSeconds <= 0)
   {
      g_logger.Critical("EA", "InpMaxQuoteAgeSeconds must be at least 1 second.");
      return false;
   }

   // The entry deviation is a risk control, and until Phase 2 it was a
   // compile-time constant tuned for gold. Whether it still bounds anything is
   // a property of the WHOLE configuration - deviation, ATR floor and stop
   // multiple together - so it is checked here rather than trusted. ADR-024.
   double min_stop_points = 0.0;
   double overshoot_ratio = 0.0;
   string drift_reason = "";
   const int drift_bound = XSparkEntryDriftBound(InpEntryDeviationPoints,
                                                 InpATRMultSL,
                                                 InpATRMinPoints,
                                                 min_stop_points,
                                                 overshoot_ratio,
                                                 drift_reason);

   g_entry_drift_bound_usable = drift_bound != XSPARK_DRIFT_BOUND_FAULT;
   g_entry_drift_bound_reason = drift_reason;

   if(drift_bound == XSPARK_DRIFT_BOUND_FAULT)
   {
      // Deliberately NOT INIT_FAILED. Refusing to initialise would abandon any
      // live position to the broker with no XSpark management at all, which is
      // worse than the misconfiguration. The SafetyManager veto stops NEW
      // exposure while protective management of existing positions continues,
      // exactly as the point-size fault does. AGENTS.md rules 9 and 23.
      g_logger.Critical("EA", "Entry drift gate is inert: " + drift_reason +
                              " New entries are blocked until the entry deviation, the ATR floor or the stop multiple is corrected for this instrument.");
   }
   else if(drift_bound == XSPARK_DRIFT_BOUND_WARN)
   {
      g_logger.Warn("EA", drift_reason);
   }
   else
   {
      g_logger.Info("EA", drift_reason);
   }

   if(!MathIsValidNumber(InpExitDeviationPoints) || InpExitDeviationPoints <= 0.0)
   {
      g_logger.Critical("EA", "InpExitDeviationPoints must be a finite positive number of ScoreBot points.");
      return false;
   }

   if(InpWeekendCloseHour < 0 || InpWeekendCloseHour > 23 ||
      InpWeekendCloseMinute < 0 || InpWeekendCloseMinute > 59)
   {
      g_logger.Critical("EA", "Weekend close time is invalid.");
      return false;
   }

   return true;
}

string XSparkStatusFromSafety()
{
   if(g_safety_manager.TotalDDKillSwitchLatched())
      return "KILLSWITCH";

   if(g_safety_manager.StateRecoveryLatched())
      return "STATE RECOVERY";

   // A non-conforming point size blocks every new entry for the life of the
   // session. Without its own status the panel would render that as a healthy
   // green SCANNING, which is the one reading an operator must never get.
   if(!g_safety_manager.ScorePointSizeConforms())
      return "POINT SIZE FAULT";

   // Same reasoning as the point-size fault: a configuration in which the
   // entry deviation no longer bounds realised risk blocks every new entry,
   // and must not render as a healthy green SCANNING.
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

void XSparkUpdateDashboard()
{
   const string mode = InpEnableTrading ? "TRADING" : "ANALYSIS ONLY";

   // The unmanaged-exposure alarm is DERIVED here rather than stored in g_status.
   // Stored, it latches (nothing clears it once the position closes) and every
   // OnTick early return bypasses it. Derived, it does neither: it is recomputed
   // from the live count on every render and clears with the condition.
   string dashboard_status = g_status;
   string dashboard_reason = g_last_block_reason;

   const int unmanaged = g_position_manager.UnmanagedPositionCount();
   if(unmanaged > 0 && !g_safety_manager.TotalDDKillSwitchLatched())
   {
      dashboard_status = "UNMANAGED EXPOSURE";
      dashboard_reason = StringFormat("%d of %d XSpark position(s) have no trustworthy entry risk; partial, break-even and trailing are disabled for them.",
                                      unmanaged,
                                      g_position_manager.ManagedPositionCount());
   }
   g_dashboard.Update(g_last_report,
                      g_safety_manager,
                      AccountInfoDouble(ACCOUNT_EQUITY),
                      g_position_manager.TradesToday(),
                      g_position_manager.TradesLast24Hours(),
                      g_position_manager.ManagedPositionCount(),
                      InpMaxOpenTrades,
                      mode,
                      dashboard_status,
                      dashboard_reason);
}

// Machine-greppable record of a signal that did NOT become a trade.
//
// Without this, the journal cannot distinguish a strategy that found no setups
// from one that found them and could not fund them - which is the difference
// between "the market was quiet" and "the account is too small for the ATR band
// this gate admits". Both look like silence. It carries the score components so
// a rejected population can be compared against the taken one offline, and the
// balance so that comparison survives across account sizes.
//
// Emitted at most once per evaluated bar, so it cannot flood.
void XSparkLogSignalRejection(const string stage,
                              const string reason,
                              XSparkScoreBotReport &report)
{
   g_logger.Info("Rejected",
                 StringFormat("stage=%s bar=%s pattern=%s dir=%s raw=%.4f final=%.4f threshold=%.4f "
                              "session_w=%.2f pat=%.2f atr=%.2f trend=%.2f rsi=%.2f sr=%.2f vol=%.2f mtf=%.2f "
                              "atr14_pts=%.2f atr50_pts=%.2f rr=%.4f balance=%s reason=%s",
                              stage,
                              TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES),
                              report.pattern_name,
                              XSparkDirectionName(report.direction),
                              report.components.raw,
                              report.components.final_score,
                              report.effective_threshold,
                              report.components.session_weight,
                              report.components.pattern,
                              report.components.atr,
                              report.components.trend,
                              report.components.rsi,
                              report.components.sr,
                              report.components.volume,
                              report.components.mtf,
                              report.atr_points,
                              report.atr50_points,
                              report.dynamic_rr,
                              DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
                              reason));
}

void XSparkVerboseBlock(const string component, const string reason)
{
   if(InpVerboseLog)
      g_logger.Info(component, reason);
}

bool XSparkPrepareTradePlan(XSparkSignal &signal,
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
      g_last_block_reason = "Entry reference or theoretical stop is invalid.";
      return false;
   }

   double adjusted_sl = 0.0;
   double ignored_tp = 0.0;
   string adjust_reason = "";

   if(!XSparkAdjustProtectionLevels(signal.symbol,
                                    signal.direction,
                                    entry_reference,
                                    signal.desired_stop,
                                    0.0,
                                    InpUseStopLevelValidation,
                                    adjusted_sl,
                                    ignored_tp,
                                    adjust_reason))
   {
      g_last_block_reason = adjust_reason;
      return false;
   }

   if(adjust_reason != "")
      XSparkVerboseBlock("ExecutionEngine", adjust_reason);

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

   double initial_tp = 0.0;
   if(signal.direction == XSPARK_SIGNAL_BUY)
      initial_tp = entry_reference + risk_distance * signal.dynamic_rr;
   else
      initial_tp = entry_reference - risk_distance * signal.dynamic_rr;

   plan.symbol = signal.symbol;
   plan.direction = signal.direction;
   plan.signal_bar_time = signal.signal_bar_time;
   plan.entry_reference = XSparkNormalizePrice(signal.symbol, entry_reference);
   plan.theoretical_sl = XSparkNormalizePrice(signal.symbol, signal.desired_stop);
   plan.final_sl = XSparkNormalizePrice(signal.symbol, adjusted_sl);
   plan.final_tp = XSparkNormalizePrice(signal.symbol, initial_tp);
   plan.risk_distance = risk_distance;
   plan.dynamic_rr = signal.dynamic_rr;
   plan.score = signal.score;
   plan.effective_threshold = signal.effective_threshold;
   plan.risk_pct = risk_pct;
   plan.volume = volume;
   plan.pattern_score = signal.pattern_score;
   plan.atr_score = signal.atr_score;
   plan.trend_score = signal.trend_score;
   plan.rsi_score = signal.rsi_score;
   plan.sr_score = signal.sr_score;
   plan.volume_score = signal.volume_score;
   plan.mtf_score = signal.mtf_score;
   plan.session_weight = signal.session_weight;
   plan.pattern_id = (EXSparkScoreBotPatternId)signal.pattern_id;
   plan.pattern_name = signal.pattern_name;

   double final_sl = 0.0;
   double final_tp = 0.0;
   string final_adjust_reason = "";

   if(!g_execution_engine.ValidateInitialProtection(plan,
                                                    InpUseStopLevelValidation,
                                                    final_sl,
                                                    final_tp,
                                                    final_adjust_reason))
   {
      g_last_block_reason = final_adjust_reason;
      return false;
   }

   if(MathAbs(final_sl - plan.final_sl) > 0.0)
   {
      plan.final_sl = final_sl;
      plan.risk_distance = MathAbs(plan.entry_reference - plan.final_sl);

      if(plan.direction == XSPARK_SIGNAL_BUY)
         plan.final_tp = XSparkNormalizePrice(signal.symbol,
                                              plan.entry_reference + plan.risk_distance * plan.dynamic_rr);
      else
         plan.final_tp = XSparkNormalizePrice(signal.symbol,
                                              plan.entry_reference - plan.risk_distance * plan.dynamic_rr);

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
                                                       InpUseStopLevelValidation,
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

   plan.final_tp = final_tp;

   const double actual_rr = plan.risk_distance > 0.0 ?
                            MathAbs(plan.final_tp - plan.entry_reference) / plan.risk_distance :
                            0.0;

   if(actual_rr < InpMinRR - 0.0000001 || actual_rr > InpMaxRR + 0.0000001)
   {
      g_last_block_reason = StringFormat("Final broker-valid RR %.4f is outside configured %.2f-%.2f.",
                                         actual_rr,
                                         InpMinRR,
                                         InpMaxRR);
      return false;
   }

   return true;
}

void XSparkLogEntry(XSparkTradePlan &plan,
                    XSparkExecutionResult &result,
                    const bool registered_exactly)
{
   g_logger.Info("EA",
                 StringFormat("Entry confirmed direction=%s entry=%s SL=%s TP=%s lots=%s risk=%.2f%% score=%.2f threshold=%.2f pattern=%s session=%.2f RR=%.2f components(pattern=%.2f atr=%.2f trend=%.2f rsi=%.2f sr=%.2f volume=%.2f mtf=%.2f) order=%I64u deal=%I64u",
                              XSparkDirectionName(plan.direction),
                              DoubleToString(result.price, g_market_state.Digits()),
                              DoubleToString(plan.final_sl, g_market_state.Digits()),
                              DoubleToString(plan.final_tp, g_market_state.Digits()),
                              DoubleToString(plan.volume, 2),
                              plan.risk_pct,
                              plan.score,
                              plan.effective_threshold,
                              plan.pattern_name,
                              plan.session_weight,
                              plan.dynamic_rr,
                              plan.pattern_score,
                              plan.atr_score,
                              plan.trend_score,
                              plan.rsi_score,
                              plan.sr_score,
                              plan.volume_score,
                              plan.mtf_score,
                              result.order_ticket,
                              result.deal_ticket));

   // The configured deviation is accepted execution tolerance, so a fill inside
   // it can still make the realised entry-to-stop distance wider than the one
   // the volume was sized from. Surface it rather than hide it.
   const double realised_entry = result.fill_price > 0.0 ? result.fill_price : result.price;
   const double realised_distance = plan.final_sl > 0.0 && realised_entry > 0.0 ?
                                    MathAbs(realised_entry - plan.final_sl) :
                                    0.0;

   if(realised_distance > 0.0 && result.actual_risk_distance > 0.0 &&
      realised_distance > result.actual_risk_distance)
   {
      const double overshoot_pct = ((realised_distance / result.actual_risk_distance) - 1.0) * 100.0;
      g_logger.Warn("EA",
                    StringFormat("Fill slipped inside the permitted deviation: sized stop distance %.2f ScoreBot points, realised %.2f, so realised risk is %.2f%% above the %.2f%% budget.",
                                 XSparkPriceToScorePoints(result.actual_risk_distance, g_score_point_size),
                                 XSparkPriceToScorePoints(realised_distance, g_score_point_size),
                                 overshoot_pct,
                                 plan.risk_pct));
   }

   g_logger.Info("EA",
                 StringFormat("Execution facts position_id=%I64d position_ticket=%I64u exact_id=%s state_registered_exactly=%s fill_price=%s fill_volume=%s submitted_entry=%s submitted_lots=%s risk_distance=%.2f ScoreBot points actual_RR=%.4f retcode=%I64d %s",
                              result.position_id,
                              result.position_ticket,
                              XSparkBoolToString(result.position_id_exact),
                              XSparkBoolToString(registered_exactly),
                              DoubleToString(result.fill_price, g_market_state.Digits()),
                              DoubleToString(result.fill_volume, 2),
                              DoubleToString(result.submitted_entry_reference, g_market_state.Digits()),
                              DoubleToString(result.submitted_volume, 2),
                              XSparkPriceToScorePoints(result.actual_risk_distance, g_score_point_size),
                              result.actual_rr,
                              result.retcode,
                              result.retcode_description));
}

// Reconciles against the broker and clears the state-recovery latch only when
// managed state provably represents every live XSpark position again.
bool XSparkAttemptStateRecovery()
{
   if(!g_safety_manager.StateRecoveryLatched())
      return true;

   if(!g_position_manager.Reconcile(g_logger))
   {
      g_logger.Critical("EA", "Reconciliation failed while XSpark state recovery is active; new entries stay blocked.");
      return false;
   }

   string coverage_reason = "";
   const bool covered = g_position_manager.ManagedStateCoversLivePositions(coverage_reason);

   // The new position counts as represented only when the state that claims it
   // belongs to this entry, or was rebuilt from broker values. A state owned by
   // a different signal bar means the entry merged into another XSpark trade.
   const bool recovered_position_tracked =
      g_state_recovery_position_id == 0 ||
      !g_position_manager.PositionIsLive(g_state_recovery_position_id) ||
      g_position_manager.StateForIdentifierOwnsSignalBar(g_state_recovery_position_id,
                                                         g_state_recovery_signal_bar_time);

   if(covered && recovered_position_tracked)
   {
      g_logger.Warn("EA",
                    StringFormat("XSpark state recovery resolved by reconciliation. %s Strategy metadata of a recovered position may have been rebuilt from broker values.",
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
      since_last_recovery_log >= XSPARK_STATE_RECOVERY_LOG_INTERVAL_SECONDS)
   {
      g_logger.Critical("EA",
                        StringFormat("XSpark state is still inconsistent with broker state; new entries remain blocked. coverage=%s recovered_position_id=%I64d tracked=%s",
                                     coverage_reason,
                                     g_state_recovery_position_id,
                                     XSparkBoolToString(recovered_position_tracked)));
      g_state_recovery_last_log_time = now;
   }

   g_last_block_reason = "XSpark state is inconsistent with broker state; new entries are blocked.";
   return false;
}

// Broker execution succeeded but XSpark could not bind the resulting position
// exactly. Broker state stays authoritative: latch, reconcile, verify, and keep
// protecting whatever exposure actually exists.
void XSparkEnterStateRecovery(XSparkTradePlan &plan, XSparkExecutionResult &result)
{
   const string registration_reason = g_position_manager.LastReason();

   g_logger.Critical("EA",
                     StringFormat("Broker execution confirmed (order=%I64u deal=%I64u position_id=%I64d) but XSpark state registration did not bind exactly: %s",
                                  result.order_ticket,
                                  result.deal_ticket,
                                  result.position_id,
                                  registration_reason));

   g_state_recovery_position_id = result.position_id;
   g_state_recovery_signal_bar_time = plan.signal_bar_time;
   g_state_recovery_last_log_time = 0;
   g_safety_manager.LatchStateRecovery(registration_reason, g_logger);

   g_status = "STATE RECOVERY";
   g_last_block_reason = "Broker execution confirmed but XSpark state registration failed; reconciling before any further entry.";

   XSparkAttemptStateRecovery();

   if(g_safety_manager.StateRecoveryLatched())
      return;

   g_last_block_reason = g_position_manager.LastRegistrationBoundState() ?
                         "Entry confirmed; state bound without exact broker identification, then verified by reconciliation." :
                         "Entry confirmed; state for the new position was rebuilt from broker values by reconciliation.";
}

void XSparkEvaluateNewBar()
{
   if(!g_indicator_cache.RefreshClosedData())
   {
      g_status = "SCANNING";
      g_last_block_reason = g_indicator_cache.LastReason();
      XSparkVerboseBlock("IndicatorCache", g_last_block_reason);
      return;
   }

   g_latest_closed_atr14 = g_indicator_cache.ATR14Base();

   XSparkCandle signal_bar;
   if(!g_indicator_cache.BaseBar(1, signal_bar))
   {
      g_status = "SCANNING";
      g_last_block_reason = "Closed signal bar is unavailable.";
      return;
   }

   if(signal_bar.time == g_last_evaluated_signal_bar_time)
   {
      g_status = "SCANNING";
      g_last_block_reason = "Closed signal bar was already evaluated.";
      XSparkVerboseBlock("ScoreBotV3", g_last_block_reason);
      return;
   }

   g_last_evaluated_signal_bar_time = signal_bar.time;

   XSparkSignal signal;
   XSparkScoreBotReport report;
   const bool eligible_signal = g_strategy.Evaluate(g_indicator_cache,
                                                    g_market_state,
                                                    signal,
                                                    report);
   g_last_report = report;

   if(report.scored)
      g_last_report.selected_risk_pct = g_risk_manager.SelectedRiskPercentForScore(report.components.final_score);

   if(!report.has_pattern || !report.scored || !eligible_signal)
   {
      g_status = report.status;
      g_last_block_reason = report.block_reason;

      // Only bars where a pattern actually formed are recorded. A bar with no
      // pattern is not a rejected signal, it is the absence of one, and logging
      // every quiet bar would bury the population that matters.
      if(report.has_pattern)
         XSparkLogSignalRejection("strategy", g_last_block_reason, report);

      if(StringFind(g_last_block_reason, "Unexpected ScoreBot score") >= 0)
         g_logger.Error("ScoreBotV3", g_last_block_reason);
      else
         XSparkVerboseBlock("ScoreBotV3", g_last_block_reason);
      return;
   }

   // Opening inside the weekend-close window would be flattened immediately by
   // PositionManager, so the entry is refused rather than paid for.
   if(InpUseWeekendClose &&
      g_position_manager.ShouldWeekendClose(g_market_state.ServerTime(),
                                            InpWeekendCloseHour,
                                            InpWeekendCloseMinute))
   {
      g_status = "WEEKEND CLOSE";
      g_last_block_reason = "Weekend close window is active; new entries are blocked.";
      XSparkVerboseBlock("PositionManager", g_last_block_reason);
      return;
   }

   if(!g_safety_manager.CanOpenNewTrades(g_position_manager.ManagedPositionCount(),
                                         g_market_state.SpreadPrice(),
                                         report.atr14))
   {
      g_status = XSparkStatusFromSafety();
      g_last_block_reason = g_safety_manager.LastReason();

      // A blocked entry is normal; a blocked entry because the feed looks
      // frozen is worth seeing in the journal without verbose logging, and a
      // skewed host clock shows up here first. Evaluations are once per base
      // bar, so this cannot flood.
      XSparkLogSignalRejection("safety", g_last_block_reason, report);

      if(g_status == "STALE QUOTE")
         g_logger.Warn("SafetyManager", g_last_block_reason);
      else
         XSparkVerboseBlock("SafetyManager", g_last_block_reason);

      return;
   }

   double risk_pct = 0.0;
   if(!g_risk_manager.IsSignalApproved(signal, risk_pct))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_risk_manager.LastReason();
      XSparkLogSignalRejection("risk", g_last_block_reason, report);
      XSparkVerboseBlock("RiskManager", g_last_block_reason);
      return;
   }

   g_last_report.selected_risk_pct = risk_pct;

   XSparkTradePlan plan;
   if(!XSparkPrepareTradePlan(signal, risk_pct, plan))
   {
      g_status = "SCANNING";

      // The most consequential rejection class on a small account: the signal
      // passed every gate and then could not be funded, because normalising the
      // volume down landed below the broker minimum and the sizer aborts rather
      // than round up past the risk budget. In the journal this is otherwise
      // indistinguishable from the market being quiet.
      XSparkLogSignalRejection("plan", g_last_block_reason, report);
      XSparkVerboseBlock("TradePlan", g_last_block_reason);
      return;
   }

   if(InpUseMarginCheck)
   {
      double required_margin = 0.0;
      double free_margin = 0.0;
      string margin_reason = "";

      if(!g_execution_engine.HasSufficientMargin(plan.symbol,
                                                 plan.direction,
                                                 plan.volume,
                                                 plan.entry_reference,
                                                 InpMarginBufferPct,
                                                 required_margin,
                                                 free_margin,
                                                 margin_reason))
      {
         g_status = "SCANNING";
         g_last_block_reason = margin_reason;
         XSparkVerboseBlock("ExecutionEngine", g_last_block_reason);
         return;
      }
   }

   if(!g_execution_engine.CanSubmitSignal(plan.signal_bar_time))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkVerboseBlock("ExecutionEngine", g_last_block_reason);
      return;
   }

   XSparkExecutionResult execution_result;
   if(!g_execution_engine.ExecuteApprovedPlan(plan, g_position_sizer, execution_result, g_logger))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      return;
   }

   // Broker execution is confirmed from here on. State registration failure is
   // a critical condition, never a silent one.
   const bool registered_exactly = g_position_manager.RegisterNewTrade(plan, execution_result, g_logger);

   g_dashboard.AnnotateEntry(plan, execution_result);
   XSparkLogEntry(plan, execution_result, registered_exactly);

   if(registered_exactly)
   {
      g_status = "MANAGING";
      g_last_block_reason = "Entry confirmed and registered against the exact broker position id.";
      return;
   }

   // The broker confirmed and then closed the position before XSpark could
   // register it. Nothing is left to manage and nothing is inconsistent.
   if(g_position_manager.LastRegistrationPositionAlreadyClosed())
   {
      g_logger.Warn("EA", g_position_manager.LastReason());
      g_status = "SCANNING";
      g_last_block_reason = "Entry confirmed but the broker position closed before state registration.";
      return;
   }

   XSparkEnterStateRecovery(plan, execution_result);
}

// Resolves the ScoreBot point size for the chart symbol and decides whether it
// can be trusted for new exposure. The decision itself lives in the pure
// XSparkSelectOperatingPointSize so it is testable from a script; this wrapper
// only supplies the broker facts and reports the outcome.
//
// XAUUSD keeps the Phase 0 regression assertion against the declared baseline.
// Every other instrument has no tested baseline to compare against, so the
// spec-validated derivation is the answer.
//
// An untrusted size is NOT an initialisation failure. Refusing to initialise
// would stop OnTick entirely, which would abandon trailing, break-even,
// protection repair and the total-drawdown killswitch while live positions stay
// open at the broker - strictly worse than the mis-scaled thresholds the check
// exists to catch. The EA falls back to a usable denominator and latches a
// SafetyManager veto so no NEW exposure is opened while the unit is untrusted.
void XSparkResolveSessionScorePointSize()
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
                    StringFormat("ScoreBot point size for %s resolved to %s. %s",
                                 _Symbol,
                                 DoubleToString(g_score_point_size, 10),
                                 select_reason));
      return;
   }

   g_logger.Critical("EA",
                     StringFormat("ScoreBot point size is not trusted for %s: %s "
                                  "Resolver said: %s Broker digits=%d point=%s. Operating size %s. "
                                  "New entries are blocked; protective management of existing positions continues.",
                                  _Symbol,
                                  select_reason,
                                  resolve_reason == "" ? "(resolved cleanly)" : resolve_reason,
                                  (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
                                  DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 10),
                                  DoubleToString(g_score_point_size, 10)));
}

int OnInit()
{
   XSparkResetScoreBotReport(g_last_report);
   g_logger.Initialize("XSpark", InpVerboseLog);
   g_logger.Info("EA", "Starting XSpark ScoreBot_v3 MAX_SHARPE");

   if(!XSparkValidateInputs())
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

   XSparkResolveSessionScorePointSize();

   g_strategy.Configure(InpMinScore,
                        InpDropIBR,
                        InpLongScoreExtra,
                        InpRSILongMin,
                        InpRSILongMax,
                        InpRSIShortMin,
                        InpRSIShortMax,
                        InpATRMinPoints,
                        InpATRMaxPoints,
                        InpATRMultSL,
                        InpMinRR,
                        InpMaxRR,
                        InpATRRatioBoost,
                        InpAllowAsianReduced,
                        g_score_point_size);

   if(!g_strategy.Initialize(_Symbol))
   {
      g_logger.Critical("ScoreBotV3", g_strategy.LastReason());
      return INIT_FAILED;
   }

   if(!g_safety_manager.Initialize(_Symbol,
                                   InpMagicNumber,
                                   InpEnableTrading,
                                   InpMaxOpenTrades,
                                   InpUseSpreadFilter,
                                   InpMaxSpreadPoints,
                                   InpMaxSpreadATRPct,
                                   InpUseTotalDDKillSwitch,
                                   InpMaxTotalDDPct,
                                   InpMaxDailyDDPct,
                                   InpMaxQuoteAgeSeconds,
                                   InpClearKillswitchLatch,
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

   if(!g_risk_manager.Initialize(InpRiskPctTier1,
                                 InpRiskPctTier2,
                                 InpRiskPctTier3,
                                 InpMaxRiskPct))
   {
      g_logger.Critical("RiskManager", g_risk_manager.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_sizer.Initialize())
   {
      g_logger.Critical("PositionSizer", "Failed to initialize position sizer");
      return INIT_FAILED;
   }

   if(!g_execution_engine.Initialize(InpMagicNumber,
                                     InpOrderComment,
                                     InpEntryDeviationPoints,
                                     g_score_point_size,
                                     InpUseStopLevelValidation,
                                     InpUseMarginCheck,
                                     InpMarginBufferPct,
                                     InpMinRR,
                                     InpMaxRR,
                                     InpMaxQuoteAgeSeconds))
   {
      g_logger.Critical("ExecutionEngine", g_execution_engine.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_manager.Initialize(_Symbol,
                                     InpMagicNumber,
                                     g_score_point_size,
                                     InpExitDeviationPoints,
                                     InpUseStopLevelValidation))
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

   g_current_base_bar_time = iTime(_Symbol, g_base_timeframe, 0);
   EventSetTimer(5);
   g_dashboard.Initialize();

   g_logger.Info("EA", StringFormat("Symbol=%s digits=%d point=%s score_point_size=%s spread_score_points=%.2f",
                                    g_market_state.SymbolName(),
                                    g_market_state.Digits(),
                                    DoubleToString(g_market_state.PointSize(), g_market_state.Digits()),
                                    DoubleToString(g_score_point_size, 8),
                                    XSparkPriceToScorePoints(g_market_state.SpreadPrice(), g_score_point_size)));

   g_logger.Info("EA", StringFormat("Deviations entry=%.2f exit=%.2f ScoreBot points | entry drift bound %s",
                                    InpEntryDeviationPoints,
                                    InpExitDeviationPoints,
                                    g_entry_drift_bound_usable ? "usable" : "INERT"));

   g_logger.Info("EA", StringFormat("Account login=%s server=%s company=%s trade_allowed=%s",
                                    IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
                                    AccountInfoString(ACCOUNT_SERVER),
                                    AccountInfoString(ACCOUNT_COMPANY),
                                    XSparkBoolToString(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0)));

   g_logger.Info("EA", StringFormat("Terminal build=%s connected=%s terminal_trade_allowed=%s mql_trade_allowed=%s tester=%s optimization=%s",
                                    IntegerToString((long)TerminalInfoInteger(TERMINAL_BUILD)),
                                    XSparkBoolToString(TerminalInfoInteger(TERMINAL_CONNECTED) != 0),
                                    XSparkBoolToString(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_TRADE_ALLOWED) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_TESTER) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_OPTIMIZATION) != 0)));

   g_logger.Info("EA", "Startup complete. Waiting for the next genuine base timeframe bar before first strategy evaluation.");
   XSparkUpdateDashboard();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_indicator_cache.Deinitialize();
   g_strategy.Deinitialize();
   // REASON_CLOSE is a terminal shutdown, not a teardown: the EA comes back on the
   // same chart with the same positions still open, and AnnotateEntry only ever runs
   // at fill time, so erasing the markers here would lose them permanently.
   const bool teardown = reason == REASON_REMOVE ||
                         reason == REASON_CHARTCLOSE ||
                         reason == REASON_PROGRAM;
   g_dashboard.Deinitialize(teardown);
   g_logger.Info("EA", StringFormat("Shutdown reason=%s (%d)",
                                    XSparkDeinitReasonToString(reason),
                                    reason));
}

void OnTimer()
{
   XSparkUpdateDashboard();
}

void OnTick()
{
   const bool market_state_valid = g_market_state.Refresh();

   datetime server_time = TimeTradeServer();
   if(server_time == 0)
      server_time = TimeCurrent();

   // Drawdown tracking and killswitch flattening depend on account state and
   // broker positions, not on a usable quote, so they run even when the feed
   // is unusable. A dropout must never suspend the killswitch.
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
         XSparkAttemptStateRecovery();

      XSparkUpdateDashboard();
      return;
   }

   g_position_manager.ManagePositions(g_market_state.Bid(),
                                      g_market_state.Ask(),
                                      g_latest_closed_atr14,
                                      InpPartialTPRatio,
                                      InpPartialClosePct,
                                      InpATRMultTrail,
                                      InpUseWeekendClose,
                                      InpWeekendCloseHour,
                                      InpWeekendCloseMinute,
                                      g_logger);

   // First tick with a live quote and a reconciled position table: the trade context
   // is synchronised, so PositionsTotal() is now trustworthy enough to sweep on. This
   // deliberately does NOT run in OnInit, where an unsynchronised terminal reports
   // zero positions and every persisted key would look orphaned.
   if(!g_state_purged && TerminalInfoInteger(TERMINAL_CONNECTED) != 0)
   {
      g_position_manager.PurgeOrphanedState(g_logger);
      g_state_purged = true;
   }

   // Protective management above always runs; only new exposure is withheld
   // while managed state and broker state disagree.
   if(g_safety_manager.StateRecoveryLatched())
      XSparkAttemptStateRecovery();

   const datetime current_bar_time = iTime(_Symbol, g_base_timeframe, 0);
   if(current_bar_time == 0)
   {
      g_status = "SCANNING";
      g_last_block_reason = "Current bar timestamp is unavailable.";
      XSparkUpdateDashboard();
      return;
   }

   if(g_current_base_bar_time == 0)
   {
      g_current_base_bar_time = current_bar_time;
      g_status = "SCANNING";
      g_last_block_reason = "Initialized current bar timestamp; waiting for next bar.";
      XSparkUpdateDashboard();
      return;
   }

   if(current_bar_time != g_current_base_bar_time)
   {
      g_current_base_bar_time = current_bar_time;
      XSparkEvaluateNewBar();
   }
   else if(g_position_manager.ManagedPositionCount() > 0 &&
           !g_safety_manager.TotalDDKillSwitchLatched() &&
           !g_safety_manager.StateRecoveryLatched())
   {
      g_status = "MANAGING";
      g_last_block_reason = "Managing existing XSpark positions.";
   }

   if(g_safety_manager.StateRecoveryLatched() && !g_safety_manager.TotalDDKillSwitchLatched())
   {
      g_status = "STATE RECOVERY";
      g_last_block_reason = "XSpark state recovery is active: " + g_safety_manager.StateRecoveryReason();
   }

   XSparkUpdateDashboard();
}
