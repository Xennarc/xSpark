#property version     "1.00"
#property description "XSparkSMC Expert Advisor running the mechanized Smart Money Concepts model."

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
#include <XSpark/Strategy/SmartMoney.mqh>
#include <XSpark/Trade/PositionManager.mqh>

// XSparkSMC runs the mechanized Smart Money Concepts model through the SAME
// safety, risk, execution and position-management components as XSpark,
// XSparkFlow, XSparkScalp and XSparkICT. It is a separate .mq5 with its own
// Magic Number so every bot can run side by side on one account without ever
// managing another's positions.
//
// WHERE THE RULE CAME FROM. The source is a published Pine v5 INDICATOR. It
// draws structure, order blocks, equal highs and lows, fair value gaps,
// strong/weak highs and lows and premium/discount zones, and it raises alerts.
// It has no entry, no stop, no target and no size - so this EA is not a
// transcription of a strategy, it is a strategy built on a transcription.
// Strategy/SmartMoney.mqh marks every line of that division: what was copied
// shape for shape, and what had to be decided because the source was silent.
//
// THE RULE. Structure breaks. The leg that broke it leaves an order block. The
// entry is a LIMIT back at that block's midpoint while the block is still
// unmitigated and the structure still points its way, taken only from the
// discount half of the dealing range for a buy and the premium half for a sell.
// The stop sits beyond the block's far edge - the level whose breach makes the
// indicator delete the block, so the stop and the indicator's own invalidation
// are the same line. The target is the draw on liquidity: the trailing extreme
// the indicator labels Strong or Weak High and Low.
//
// THE HONEST FRAMING, carried the way every other strategy here carries it.
// Smart Money Concepts is taught discretionarily and has no published,
// independently audited record; a widely used indicator selects for attention,
// not for edge. Nothing in this EA claims the model is profitable. What it does
// is make the claim TESTABLE: the rule is fixed, the journal says where every
// signal died, and OnTester reports a 95% interval on expectancy - so a pass
// that cannot distinguish itself from a coin flip says so in those words rather
// than showing an equity curve.
//
// Read before funding: the COST line printed after the first bar and again
// every broker day, then the minimum-lot line under it.
//
// WHAT THIS EA DELIBERATELY DOES NOT DO, so its absence is not mistaken for an
// oversight:
//   - no chart drawing. The indicator's boxes and labels are its whole output
//     and none of them is an input to a decision here; a tester run has nobody
//     watching, and an EA that draws is an EA spending time on presentation.
//   - no multi-timeframe highs and lows, and no fair-value-gap timeframe. Both
//     are display features in the source; this model reads one chart period.
//   - no trailing stop and no partial close. The stop and target go to the
//     broker with the order.
//   - no separate "structure broke against me" exit. There is nothing for one
//     to do: the stop already sits at the block's far edge, which is where the
//     setup is invalidated, so a second invalidation would only be the first
//     one arriving late.

input group "01. Start here"
input bool   InpSmcEnableTrading = false;        // Place real trades (off = watch and log only)
input double InpSmcRiskPct = 1.0;                // Money risked on one trade (% of your balance)
input EXSparkSmcStructure InpSmcStructure = XSPARK_SMC_INTERNAL_WITH_SWING; // Which structure break to trade
input EXSparkSmcConfluence InpSmcConfluence = XSPARK_SMC_BLOCK_ONLY; // What the entry zone must show

// THE COST THE BROKER CHARGES PER LOT. This model's stop is the height of an
// order block plus a small buffer, so spread plus commission is a large share
// of what the trade can win. The commission feeds the cost floor on the stop
// and the minimum width an order block must have to be worth entering.
input group "02. Your broker's costs"
input double InpSmcCommissionPerLot = 0.0;       // Commission per 1.0 lot, both ways, in account money (0 = none)

// NO TARGET SETTING, deliberately. This model takes the trade to the draw on
// liquidity - the extreme the market is being pulled toward - so the target is
// a level the market supplies and the reward ratio is whatever that level
// implies against the stop. An input here would let an operator override the
// one thing the model says not to guess at (AGENTS.md rule 48).

// SMALL ACCOUNTS. On a small balance the broker's smallest trade usually risks
// more than the risk percentage allows, so every signal would be refused. This
// cap lets the smallest trade through when the money it risks is at or below
// the cap. A cap at or below the risk percentage means "never raise".
input group "04. Small accounts"
input double InpSmcMinLotRiskCapPct = 3.0;       // Smallest trade may risk up to this % (0 = never exceed risk %)

// THE DAILY LOSS LIMIT. A percentage of your account. Reaching it pauses new
// entries for the rest of the broker day; open trades keep being managed, and
// the next broker day starts clean.
input group "05. Daily loss limit"
input double InpSmcMaxDailyDDPct = 6.0;          // Stop opening trades if the account falls this much today

// THE EMERGENCY STOP. A separate, harsher control: it closes every trade this
// bot owns and refuses to open another until you clear it deliberately.
input group "06. Emergency stop - off means the level below is ignored"
input bool   InpSmcUseTotalDDKillSwitch = true;  // Emergency stop: close everything on a big account fall
input double InpSmcMaxTotalDDPct = 20.0;         // Account fall that sets off the emergency stop (%)

input group "07. Advanced - rarely touched"
input ulong  InpSmcMagicNumber = XSPARK_SMC_MAGIC_DEFAULT; // This bot's ID tag - a different one per chart
input bool   InpSmcVerboseLog = false;           // Write detailed logs (for troubleshooting)
input bool   InpSmcClearKillswitchLatch = false; // Clear the emergency stop once, then set back to false

// Bounds this EA enforces itself, none of them operator-facing. One position at
// a time: a structure break is one event, and stacking entries on one block
// would multiply the exposure without multiplying the reason for it.
#define XSPARK_SMC_MAX_OPEN_TRADES 1
#define XSPARK_SMC_MAX_RISK_PCT 2.0
#define XSPARK_SMC_MAX_MIN_LOT_RISK_PCT 3.0
#define XSPARK_SMC_MAX_ACCOUNT_RISK_PCT 6.0
#define XSPARK_SMC_DEFAULT_RISK_PCT 1.0
#define XSPARK_SMC_DEFAULT_MIN_LOT_RISK_CAP_PCT 3.0
#define XSPARK_SMC_DEFAULT_DAILY_DD_PCT 6.0
#define XSPARK_SMC_DEFAULT_TOTAL_DD_PCT 20.0
#define XSPARK_SMC_DEFAULT_COMMISSION_PER_LOT 0.0

#define XSPARK_SMC_ENTRY_DEVIATION_POINTS 20
#define XSPARK_SMC_EXIT_DEVIATION_POINTS 20
#define XSPARK_SMC_MARGIN_BUFFER_PCT 20.0
#define XSPARK_SMC_MAX_QUOTE_AGE_SECONDS 15
#define XSPARK_SMC_SEED_SPREAD_CAP_POINTS 50.0
#define XSPARK_SMC_MAX_SPREAD_ATR_PCT 25.0
#define XSPARK_SMC_TARGET_BAND_LOW_MULT 0.80
#define XSPARK_SMC_TARGET_BAND_HIGH_MULT 1.25
#define XSPARK_SMC_COMMENT_DEFAULT "XSparkSMC"
#define XSPARK_SMC_MIN_TRADES_FOR_VERDICT 30

// The per-server-day funnel. One counter per terminal verdict a closed candle
// can reach, so a run that takes no trades says WHICH condition the market
// never produced rather than going silent.
#define XSPARK_SMC_FUNNEL_STAGES 17

CXSparkLogger          g_logger;
CXSparkMarketState     g_market_state;
CXSparkIndicatorCache  g_indicator_cache;
CXSparkSafetyManager   g_safety_manager;
CXSparkRiskManager     g_risk_manager;
CXSparkPositionSizer   g_position_sizer;
CXSparkExecutionEngine g_execution_engine;
CXSparkPositionManager g_position_manager;
CXSparkSmartMoney      g_strategy;

ENUM_TIMEFRAMES g_base_timeframe = PERIOD_M15;
ENUM_TIMEFRAMES g_higher_timeframe = PERIOD_H1;

double g_score_point_size = 0.01;
bool   g_score_point_size_conforms = false;
string g_score_point_size_reason = "The strategy point size has not been resolved.";

bool   g_entry_drift_bound_usable = false;
string g_entry_drift_bound_reason = "The entry drift bound has not been evaluated.";

bool   g_smc_use_weekend_close = true;
int    g_smc_weekend_close_hour = XSPARK_SMC_WEEKEND_CLOSE_HOUR;
int    g_smc_weekend_close_minute = XSPARK_SMC_WEEKEND_CLOSE_MINUTE;

bool   g_config_valid = false;
string g_config_reason = "The Smart Money configuration has not been checked.";

XSparkSmcConfig g_smc_config;
double g_smc_risk_pct = XSPARK_SMC_DEFAULT_RISK_PCT;
double g_smc_min_lot_cap_pct = XSPARK_SMC_DEFAULT_MIN_LOT_RISK_CAP_PCT;
double g_smc_daily_dd_pct = XSPARK_SMC_DEFAULT_DAILY_DD_PCT;
double g_smc_total_dd_pct = XSPARK_SMC_DEFAULT_TOTAL_DD_PCT;
bool   g_smc_use_killswitch = true;
double g_smc_commission_per_lot = XSPARK_SMC_DEFAULT_COMMISSION_PER_LOT;

int      g_tester_sequence = 0;
datetime g_current_base_bar_time = 0;
datetime g_last_evaluated_signal_bar_time = 0;
double   g_latest_closed_atr14 = 0.0;

string g_status = "SCANNING";
string g_last_block_reason = "";
string g_funnel_stage = "";
int    g_funnel_day_id = 0;
bool   g_plan_cost_refusal = false;

XSparkScoreBotReport g_last_report;

string g_funnel_names[XSPARK_SMC_FUNNEL_STAGES];
int    g_funnel_counts[XSPARK_SMC_FUNNEL_STAGES];

// ---------------------------------------------------------------------------
// The funnel.
// ---------------------------------------------------------------------------

void XSparkSmcResetFunnel()
{
   g_funnel_names[0] = "NO STRUCTURE";
   g_funnel_names[1] = "BLOCK EXPIRED";
   g_funnel_names[2] = "STRUCTURE FLIPPED";
   g_funnel_names[3] = "AGAINST SWING";
   g_funnel_names[4] = "BLOCK TOO THIN";
   g_funnel_names[5] = "NO IMBALANCE";
   g_funnel_names[6] = "RANGE UNKNOWN";
   g_funnel_names[7] = "WRONG HALF";
   g_funnel_names[8] = "NO DRAW";
   g_funnel_names[9] = "DRAW TOO CLOSE";
   g_funnel_names[10] = "DRAW TOO FAR";
   g_funnel_names[11] = "COST BLOCKED";
   g_funnel_names[12] = "SPREAD BLOCKED";
   g_funnel_names[13] = "SIZE BLOCKED";
   g_funnel_names[14] = "SIGNAL";
   g_funnel_names[15] = "ENTERED";
   g_funnel_names[16] = "OTHER";

   for(int i = 0; i < XSPARK_SMC_FUNNEL_STAGES; i++)
      g_funnel_counts[i] = 0;
}

void XSparkSmcCountFunnelStage(const string stage)
{
   if(stage == "")
      return;

   for(int i = 0; i < XSPARK_SMC_FUNNEL_STAGES; i++)
   {
      if(g_funnel_names[i] == stage)
      {
         g_funnel_counts[i]++;
         return;
      }
   }

   g_funnel_counts[XSPARK_SMC_FUNNEL_STAGES - 1]++;
}

void XSparkSmcLogFunnel(const int day_id, const string occasion)
{
   string line = StringFormat("Funnel for broker day %d (%s):", day_id, occasion);
   for(int i = 0; i < XSPARK_SMC_FUNNEL_STAGES; i++)
      line += StringFormat(" %s=%d", g_funnel_names[i], g_funnel_counts[i]);

   g_logger.Info("Funnel", line);
}

void XSparkSmcVerboseBlock(const string component, const string reason)
{
   if(InpSmcVerboseLog && reason != "")
      g_logger.Debug(component, reason);
}

void XSparkSmcLogSignalRejection(const string stage, const string reason, const XSparkScoreBotReport &report)
{
   g_logger.Info("Rejected",
                 StringFormat("bar=%s stage=%s dir=%s O=%.8f H=%.8f L=%.8f C=%.8f atr=%.8f broke=%.8f balance=%.2f reason=%s",
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

// ---------------------------------------------------------------------------
// Instrument helpers.
// ---------------------------------------------------------------------------

double XSparkSmcTickValue()
{
   const double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(MathIsValidNumber(tick_value) && tick_value > 0.0)
      return tick_value;

   // The same fallback the sizer and the account cap both use, so every cost
   // figure in the journal is derived the same way the trade will be.
   const double profit_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   return MathIsValidNumber(profit_value) && profit_value > 0.0 ? profit_value : 0.0;
}

// ---------------------------------------------------------------------------
// Input resolution.
// ---------------------------------------------------------------------------
//
// Corrected rather than refused wherever a correction is strictly safer than
// what was typed, and every correction is stated. An EA that refuses to start
// on a typo is an EA that is not running when the operator thinks it is.

bool XSparkSmcResolveInputs()
{
   string corrections = "";
   bool corrected = false;

   g_smc_risk_pct = InpSmcRiskPct;
   g_smc_min_lot_cap_pct = InpSmcMinLotRiskCapPct;
   g_smc_daily_dd_pct = InpSmcMaxDailyDDPct;
   g_smc_total_dd_pct = InpSmcMaxTotalDDPct;
   g_smc_use_killswitch = InpSmcUseTotalDDKillSwitch;
   g_smc_commission_per_lot = InpSmcCommissionPerLot;

   if(!MathIsValidNumber(g_smc_risk_pct) || g_smc_risk_pct <= 0.0)
   {
      corrections += StringFormat("Money risked on one trade was %.4f, which cannot size a trade; using %.2f%%. ",
                                  InpSmcRiskPct, XSPARK_SMC_DEFAULT_RISK_PCT);
      g_smc_risk_pct = XSPARK_SMC_DEFAULT_RISK_PCT;
      corrected = true;
   }
   else if(g_smc_risk_pct > XSPARK_SMC_MAX_RISK_PCT)
   {
      corrections += StringFormat("Money risked on one trade was %.2f%%, above this bot's %.2f%% ceiling; using the ceiling. ",
                                  InpSmcRiskPct, XSPARK_SMC_MAX_RISK_PCT);
      g_smc_risk_pct = XSPARK_SMC_MAX_RISK_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(g_smc_min_lot_cap_pct) || g_smc_min_lot_cap_pct < 0.0)
   {
      corrections += StringFormat("The small-account cap was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  InpSmcMinLotRiskCapPct, XSPARK_SMC_DEFAULT_MIN_LOT_RISK_CAP_PCT);
      g_smc_min_lot_cap_pct = XSPARK_SMC_DEFAULT_MIN_LOT_RISK_CAP_PCT;
      corrected = true;
   }
   else if(g_smc_min_lot_cap_pct > XSPARK_SMC_MAX_MIN_LOT_RISK_PCT)
   {
      corrections += StringFormat("The small-account cap was %.2f%%, above this bot's %.2f%% ceiling; using the ceiling. ",
                                  InpSmcMinLotRiskCapPct, XSPARK_SMC_MAX_MIN_LOT_RISK_PCT);
      g_smc_min_lot_cap_pct = XSPARK_SMC_MAX_MIN_LOT_RISK_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(g_smc_daily_dd_pct) || g_smc_daily_dd_pct <= 0.0 || g_smc_daily_dd_pct >= 100.0)
   {
      corrections += StringFormat("The daily loss limit was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  InpSmcMaxDailyDDPct, XSPARK_SMC_DEFAULT_DAILY_DD_PCT);
      g_smc_daily_dd_pct = XSPARK_SMC_DEFAULT_DAILY_DD_PCT;
      corrected = true;
   }

   if(!MathIsValidNumber(g_smc_total_dd_pct) || g_smc_total_dd_pct >= 100.0 || g_smc_total_dd_pct <= 0.0)
   {
      corrections += StringFormat("The emergency stop level was %.4f, which is not a usable percentage; using %.2f%%. ",
                                  InpSmcMaxTotalDDPct, XSPARK_SMC_DEFAULT_TOTAL_DD_PCT);
      g_smc_total_dd_pct = XSPARK_SMC_DEFAULT_TOTAL_DD_PCT;
      corrected = true;
   }

   if(g_smc_use_killswitch && g_smc_daily_dd_pct >= g_smc_total_dd_pct)
   {
      corrections += StringFormat("The daily loss limit (%.2f%%) is at or above the emergency stop (%.2f%%), so it can never act; the emergency stop applies first. ",
                                  g_smc_daily_dd_pct, g_smc_total_dd_pct);
      corrected = true;
   }

   if(!MathIsValidNumber(g_smc_commission_per_lot) || g_smc_commission_per_lot < 0.0)
   {
      corrections += StringFormat("CRITICAL: the commission per lot was %.4f, which is not a usable amount; using %.2f. "
                                  "Round-trip costs are now UNDER-COUNTED on a commission account until this is set. ",
                                  InpSmcCommissionPerLot, XSPARK_SMC_DEFAULT_COMMISSION_PER_LOT);
      g_smc_commission_per_lot = XSPARK_SMC_DEFAULT_COMMISSION_PER_LOT;
      corrected = true;
   }

   if(corrected)
      g_logger.Critical("EA",
                        "Settings were corrected so the bot could start. " + corrections +
                        "Fix them in Inputs so this does not repeat.");

   return !corrected;
}

// ---------------------------------------------------------------------------
// The two journal lines an operator must read before funding.
// ---------------------------------------------------------------------------

void XSparkSmcLogCostLine()
{
   const double spread = g_market_state.SpreadPrice();
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tick_value = XSparkSmcTickValue();

   double cost = 0.0;
   double commission_price = 0.0;
   string cost_reason = "";
   if(!XSparkSmcRoundTripCost(spread, g_smc_commission_per_lot, tick_size, tick_value, cost, commission_price, cost_reason))
   {
      g_logger.Warn("Cost", "The round-trip cost could not be measured on this bar: " + cost_reason);
      return;
   }

   const double atr = g_latest_closed_atr14;
   if(atr <= 0.0)
   {
      g_logger.Warn("Cost", "The typical candle size is not yet known, so the cost share cannot be stated.");
      return;
   }

   const double widest_stop = g_smc_config.max_stop_atr * atr;
   const double share_pct = widest_stop > 0.0 ? cost / widest_stop * 100.0 : 0.0;
   const bool feasible = cost <= g_smc_config.max_cost_share_pct / 100.0 * widest_stop;

   const string line = StringFormat("Round-trip cost now: spread %s + commission %s = %s, which is %.1f%% of the widest stop this chart period allows (%.2f x the typical candle = %s; at most %.1f%%). "
                                    "It is also the thinnest order block this bot will enter. At the NEAREST draw it will take (%.2f x the stop) a trade with no edge wins about %.1f%% after that cost, and breaks even at %.1f%%; "
                                    "every trade whose draw is further needs less. This chart period is %s at the current cost.",
                                    DoubleToString(spread, g_market_state.Digits()),
                                    DoubleToString(commission_price, g_market_state.Digits()),
                                    DoubleToString(cost, g_market_state.Digits()),
                                    share_pct,
                                    g_smc_config.max_stop_atr,
                                    DoubleToString(widest_stop, g_market_state.Digits()),
                                    g_smc_config.max_cost_share_pct,
                                    g_smc_config.min_target_r,
                                    XSparkSmcNoEdgeWinRate(g_smc_config.min_target_r, g_smc_config.max_cost_share_pct) * 100.0,
                                    XSparkSmcBreakEvenWinRate(g_smc_config.min_target_r) * 100.0,
                                    feasible ? "FEASIBLE" : "INFEASIBLE");

   if(feasible)
      g_logger.Info("Cost", line);
   else
      g_logger.Warn("Cost", line);
}

// What the broker's smallest trade risks at the WIDEST stop this chart period
// allows, not the narrowest. The narrowest is the most favourable case and says
// nothing about whether entries will actually open; the widest is what the
// small-account cap will be asked to permit.
void XSparkSmcLogMinimumLotLine()
{
   const double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tick_value = XSparkSmcTickValue();
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   const double atr = g_latest_closed_atr14;

   if(volume_min <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0 || balance <= 0.0 || atr <= 0.0)
   {
      g_logger.Warn("PositionSizer", "The smallest trade's risk could not be stated on this bar.");
      return;
   }

   const double widest_stop = g_smc_config.max_stop_atr * atr;
   const double risk_cash = volume_min * (widest_stop / tick_size) * tick_value;
   const double risk_pct = risk_cash / balance * 100.0;
   const int volume_digits = XSparkVolumeDigitsFromStep(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));

   g_logger.Info("PositionSizer",
                 StringFormat("Smallest trade on %s: %s lots. At the widest stop this chart period allows (%s) it risks %.2f = %.2f%% of the balance; "
                              "your risk setting is %.2f%% and the small-account cap is %.2f%%.",
                              _Symbol,
                              DoubleToString(volume_min, volume_digits),
                              DoubleToString(widest_stop, g_market_state.Digits()),
                              risk_cash, risk_pct, g_smc_risk_pct, g_smc_min_lot_cap_pct));

   if(risk_pct > g_smc_min_lot_cap_pct)
      g_logger.Warn("PositionSizer",
                    StringFormat("Entries will be refused whenever the stop runs wide: the smallest trade risks %.2f%% at the widest stop, above the %.2f%% small-account cap. "
                                 "Raise the balance, use a cent account, or lift the cap above %.2f%%.",
                                 risk_pct, g_smc_min_lot_cap_pct, risk_pct));
}

// The weekend backstop, read from the symbol's own Friday session rather than
// assumed. A broker may report several Friday sessions with a break between
// them; the last one is the one that matters.
void XSparkSmcResolveWeekendClose()
{
   datetime session_from = 0;
   datetime session_to = 0;

   bool friday_known = false;
   int friday_end_seconds = 0;

   for(uint index = 0; index < 8; index++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, FRIDAY, index, session_from, session_to))
         break;

      friday_known = true;
      friday_end_seconds = (int)session_to;
   }

   const bool trades_at_weekend =
      SymbolInfoSessionTrade(_Symbol, SATURDAY, 0, session_from, session_to) ||
      SymbolInfoSessionTrade(_Symbol, SUNDAY, 0, session_from, session_to);

   string weekend_reason = "";
   XSparkSmcWeekendClose(trades_at_weekend,
                         friday_known,
                         friday_end_seconds,
                         g_smc_use_weekend_close,
                         g_smc_weekend_close_hour,
                         g_smc_weekend_close_minute,
                         weekend_reason);

   g_logger.Info("SMC", weekend_reason);
}

// ---------------------------------------------------------------------------
// The trade plan.
// ---------------------------------------------------------------------------

bool XSparkSmcPrepareTradePlan(XSparkSignal &signal,
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

   const double entry_reference = signal.direction == XSPARK_SIGNAL_BUY ? g_market_state.Ask()
                                                                       : g_market_state.Bid();
   const double close_side_reference = signal.direction == XSPARK_SIGNAL_BUY ? g_market_state.Bid()
                                                                             : g_market_state.Ask();

   if(entry_reference <= 0.0 || close_side_reference <= 0.0 || signal.desired_stop <= 0.0)
   {
      g_last_block_reason = "Entry reference, close-side reference or the model's stop is invalid.";
      return false;
   }

   if(!MathIsValidNumber(signal.dynamic_rr) || signal.dynamic_rr <= 0.0)
   {
      g_last_block_reason = "This model needs a target and the signal carries none.";
      return false;
   }

   // THE LIMIT. The model entered at an order block, which price has to retrace
   // into; it does not chase the break it just measured. Checked here and again
   // at every execution retry. A setup refused here is not lost: the block
   // stays live, so the next closed bar re-derives the same signal from the
   // same window and asks again.
   if(!XSparkEntryLimitAllows(signal.direction, entry_reference, signal.entry_limit))
   {
      g_last_block_reason = StringFormat("The market at %.8f has not retraced to the order block midpoint at %.8f; the entry waits rather than chasing.",
                                         entry_reference, signal.entry_limit);
      return false;
   }

   double bounded_stop = 0.0;
   double bounded_distance = 0.0;
   string bound_reason = "";
   if(!XSparkSmcStop(signal.direction,
                     entry_reference,
                     signal.desired_stop,
                     signal.atr14,
                     round_trip_cost,
                     g_smc_config,
                     bounded_stop,
                     bounded_distance,
                     bound_reason))
   {
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
      XSparkSmcVerboseBlock("ExecutionEngine", adjust_reason);

   const double risk_distance = XSparkRiskDistance(signal.direction, entry_reference, adjusted_sl);
   if(risk_distance <= 0.0)
   {
      g_last_block_reason = "The adjusted stop is not on the protective side of the entry reference.";
      return false;
   }

   double volume = 0.0;
   if(!g_position_sizer.CalculateVolume(signal.symbol, risk_pct, entry_reference, adjusted_sl, volume))
   {
      g_last_block_reason = g_position_sizer.LastReason();
      return false;
   }

   plan.context = signal.context;
   plan.symbol = signal.symbol;
   plan.direction = signal.direction;
   plan.signal_bar_time = signal.signal_bar_time;
   plan.entry_reference = XSparkNormalizePrice(signal.symbol, entry_reference);
   plan.theoretical_sl = XSparkNormalizePrice(signal.symbol, bounded_stop);
   plan.final_sl = XSparkNormalizePrice(signal.symbol, adjusted_sl);
   plan.risk_distance = risk_distance;
   plan.dynamic_rr = signal.dynamic_rr;
   plan.score = signal.score;
   plan.effective_threshold = signal.effective_threshold;
   plan.risk_pct = risk_pct;
   plan.volume = volume;
   plan.pattern_score = signal.pattern_score;
   plan.session_weight = signal.session_weight;
   plan.pattern_name = signal.pattern_name;
   plan.entry_limit = signal.entry_limit;

   return true;
}

// ---------------------------------------------------------------------------
// The closed-candle evaluation.
// ---------------------------------------------------------------------------

void XSparkSmcEvaluateNewBarCore()
{
   g_funnel_stage = "";

   if(!g_indicator_cache.RefreshClosedData())
   {
      g_status = "SCANNING";
      g_last_block_reason = g_indicator_cache.LastReason();
      return;
   }

   XSparkCandle signal_bar;
   if(!g_indicator_cache.BaseBar(1, signal_bar))
   {
      g_status = "SCANNING";
      g_last_block_reason = "The closed signal candle is unavailable.";
      return;
   }

   g_latest_closed_atr14 = g_indicator_cache.ATR14Base();

   if(signal_bar.time == g_last_evaluated_signal_bar_time)
   {
      g_status = "SCANNING";
      g_last_block_reason = "The closed signal candle was already evaluated.";
      return;
   }

   g_last_evaluated_signal_bar_time = signal_bar.time;
   g_funnel_stage = "OTHER";

   // The thinnest order block worth entering, measured from what a round trip
   // actually costs right now. This is the ONLY number the EA hands down into
   // the entry rule, and it is a cost, not an indicator: a zone narrower than
   // the spread has a midpoint inside the spread.
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double round_trip_cost = 0.0;
   double commission_price = 0.0;
   string cost_reason = "";
   if(!XSparkSmcRoundTripCost(g_market_state.SpreadPrice(),
                              g_smc_commission_per_lot,
                              tick_size,
                              XSparkSmcTickValue(),
                              round_trip_cost,
                              commission_price,
                              cost_reason))
   {
      g_status = "COST BLOCKED";
      g_funnel_stage = "COST BLOCKED";
      g_last_block_reason = cost_reason;
      return;
   }

   g_strategy.SetMinimumBlock(round_trip_cost);

   XSparkSignal signal;
   XSparkScoreBotReport report;
   const bool eligible_signal = g_strategy.Evaluate(g_indicator_cache, signal, report);
   g_last_report = report;
   g_last_report.selected_risk_pct = g_smc_risk_pct;

   if(!eligible_signal)
   {
      g_status = report.status;
      g_last_block_reason = report.block_reason;

      // The model's own verdicts name the stage. Read newest-first: the last
      // condition to fail is the one that actually stopped the sequence.
      if(report.rsi_verdict == "NO DRAW" || report.rsi_verdict == "DRAW TOO CLOSE" ||
         report.rsi_verdict == "DRAW TOO FAR")
         g_funnel_stage = report.rsi_verdict;
      else if(report.entry_location == "WRONG HALF" || report.entry_location == "RANGE UNKNOWN")
         g_funnel_stage = report.entry_location;
      else if(report.joint_verdict == "NO IMBALANCE")
         g_funnel_stage = "NO IMBALANCE";
      else if(report.pullback_verdict == "BLOCK TOO THIN")
         g_funnel_stage = "BLOCK TOO THIN";
      else if(report.htf_verdict == "NO STRUCTURE" || report.htf_verdict == "BLOCK EXPIRED" ||
              report.htf_verdict == "STRUCTURE FLIPPED" || report.htf_verdict == "AGAINST SWING")
         g_funnel_stage = report.htf_verdict;

      XSparkSmcVerboseBlock("SMC", g_last_block_reason);
      return;
   }

   XSparkSmcCountFunnelStage("SIGNAL");
   g_funnel_stage = "OTHER";

   g_logger.Info("SMC",
                 StringFormat("bar=%s %s", TimeToString(report.signal_bar_time, TIME_DATE | TIME_MINUTES), signal.reason));

   if(!g_config_valid)
   {
      g_status = "CONFIG BLOCKED";
      g_last_block_reason = g_config_reason;
      XSparkSmcLogSignalRejection("configuration", g_last_block_reason, report);
      return;
   }

   if(!g_safety_manager.CanOpenNewTrades(g_position_manager.ManagedPositionCount(),
                                         round_trip_cost,
                                         report.atr14))
   {
      g_status = "BLOCKED";
      g_last_block_reason = g_safety_manager.LastReason();
      g_funnel_stage = "SPREAD BLOCKED";
      XSparkSmcLogSignalRejection("safety", g_last_block_reason, report);
      XSparkSmcVerboseBlock("SafetyManager", g_last_block_reason);
      return;
   }

   XSparkTradePlan plan;
   if(!XSparkSmcPrepareTradePlan(signal, g_smc_risk_pct, round_trip_cost, plan))
   {
      g_status = g_plan_cost_refusal ? "COST BLOCKED" : "SCANNING";
      g_funnel_stage = g_plan_cost_refusal ? "COST BLOCKED" : "SIZE BLOCKED";
      XSparkSmcLogSignalRejection("plan", g_last_block_reason, report);
      return;
   }

   // The account-level exposure cap. Always checked: no configuration makes
   // opening a trade the account cannot carry the behaviour someone wanted.
   double open_risk_cash = 0.0, own_risk_cash = 0.0, foreign_risk_cash = 0.0;
   int own_positions = 0;
   string account_risk_reason = "";
   double prospective_risk_cash = 0.0;
   string prospective_reason = "";
   double projected_pct = 0.0;
   string cap_check_reason = "";

   if(!XSparkPositionRiskCash(plan.entry_reference, plan.final_sl, plan.volume,
                              SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                              XSparkSmcTickValue(), prospective_risk_cash, prospective_reason) ||
      !XSparkReadAccountExposure(_Symbol, InpSmcMagicNumber, open_risk_cash, own_risk_cash,
                                 foreign_risk_cash, own_positions, account_risk_reason) ||
      !XSparkAccountRiskWithinCap(open_risk_cash, prospective_risk_cash,
                                  AccountInfoDouble(ACCOUNT_BALANCE),
                                  XSPARK_SMC_MAX_ACCOUNT_RISK_PCT, projected_pct, cap_check_reason))
   {
      g_status = "ACCOUNT RISK";
      g_last_block_reason = account_risk_reason != "" ? account_risk_reason
                            : (prospective_reason != "" ? prospective_reason : cap_check_reason);
      XSparkSmcLogSignalRejection("account_risk", g_last_block_reason, report);
      return;
   }

   double required_margin = 0.0, free_margin = 0.0;
   string margin_reason = "";
   if(!g_execution_engine.HasSufficientMargin(plan.symbol, plan.direction, plan.volume,
                                              plan.entry_reference, XSPARK_SMC_MARGIN_BUFFER_PCT,
                                              required_margin, free_margin, margin_reason))
   {
      g_status = "SCANNING";
      g_last_block_reason = margin_reason;
      XSparkSmcLogSignalRejection("margin", g_last_block_reason, report);
      return;
   }

   // Keyed on the structure break rather than on this bar, so one break opens
   // one trade however many bars the retracement takes to arrive.
   if(!g_execution_engine.CanSubmitSignal(plan.signal_bar_time))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkSmcLogSignalRejection("submit", g_last_block_reason, report);
      return;
   }

   XSparkExecutionResult execution_result;
   if(!g_execution_engine.ExecuteApprovedPlan(plan, g_position_sizer, execution_result, g_logger))
   {
      g_status = "SCANNING";
      g_last_block_reason = g_execution_engine.LastReason();
      XSparkSmcLogSignalRejection("execute", g_last_block_reason, report);
      return;
   }

   g_funnel_stage = "ENTERED";

   const bool registered_exactly = g_position_manager.RegisterNewTrade(plan, execution_result, g_logger);

   g_logger.Info("Entry",
                 StringFormat("%s %.8f lots at %.8f, stop %.8f, target ratio %.2f; %s",
                              XSparkDirectionName(plan.direction), execution_result.fill_volume,
                              execution_result.fill_price, plan.final_sl, plan.dynamic_rr,
                              registered_exactly ? "registered against the broker position id"
                                                 : "NOT registered exactly; state recovery applies"));

   g_status = registered_exactly ? "MANAGING" : "SCANNING";
}

void XSparkSmcEvaluateNewBar()
{
   XSparkSmcEvaluateNewBarCore();
   XSparkSmcCountFunnelStage(g_funnel_stage);
}

// ---------------------------------------------------------------------------
// Lifecycle.
// ---------------------------------------------------------------------------

int OnInit()
{
   XSparkResetScoreBotReport(g_last_report);
   g_last_report.pattern_mode = "SMART MONEY";
   XSparkSmcResetFunnel();
   g_logger.Initialize("XSparkSMC", InpSmcVerboseLog);
   g_logger.Info("EA", "Starting XSparkSMC Smart Money Concepts model");

   // The Magic Number check comes first and fails closed: an EA that cannot
   // prove its exposure is its own must not open any.
   string magic_reason = "";
   if(!XSparkMagicIsAvailable(InpSmcMagicNumber, XSPARK_SMC_MAGIC_DEFAULT, magic_reason))
   {
      g_logger.Critical("EA", magic_reason);
      return INIT_PARAMETERS_INCORRECT;
   }

   XSparkSmcResolveInputs();

   if(!g_market_state.Initialize(_Symbol))
   {
      g_logger.Critical("MarketState", "Failed to initialize market state for the chart symbol");
      return INIT_FAILED;
   }

   g_base_timeframe = (ENUM_TIMEFRAMES)Period();

   // The shared cache refuses a higher timeframe that is not longer than the
   // base, so the supported-period table supplies the partner rather than this
   // EA assuming one. Nothing in the Smart Money rule reads the higher
   // timeframe - the model is single-period - but the cache is shared and its
   // contract is the cache's, not this strategy's.
   string timeframe_reason = "";
   if(!XSparkHigherTimeframeFor(g_base_timeframe, g_higher_timeframe, timeframe_reason))
   {
      g_logger.Critical("EA", timeframe_reason);
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!g_indicator_cache.Initialize(_Symbol, g_base_timeframe, g_higher_timeframe))
   {
      g_logger.Critical("IndicatorCache", g_indicator_cache.LastReason());
      return INIT_FAILED;
   }

   g_score_point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(!MathIsValidNumber(g_score_point_size) || g_score_point_size <= 0.0)
   {
      g_logger.Critical("EA", "The instrument's point size is not usable.");
      return INIT_FAILED;
   }
   g_score_point_size_conforms = true;
   g_score_point_size_reason = "";
   g_entry_drift_bound_usable = true;
   g_entry_drift_bound_reason = "";

   XSparkSmcResolveWeekendClose();

   g_config_valid = true;
   g_config_reason = "";

   XSparkSmcDefaultConfig(g_smc_config);
   g_smc_config.structure_mode = (int)InpSmcStructure;
   g_smc_config.require_gap = InpSmcConfluence == XSPARK_SMC_BLOCK_WITH_GAP;

   string config_reason = "";
   if(!XSparkSmcConfigUsable(g_smc_config, config_reason))
   {
      g_config_valid = false;
      g_config_reason += config_reason + " ";
   }

   if(!g_config_valid)
      g_logger.Critical("SMC", g_config_reason + "New entries blocked; existing positions remain managed.");

   g_strategy.Configure(g_smc_config);

   if(!g_strategy.Initialize(_Symbol))
   {
      g_logger.Critical("SMC", g_strategy.LastReason());
      return INIT_FAILED;
   }

   if(!g_safety_manager.Initialize(_Symbol,
                                   InpSmcMagicNumber,
                                   InpSmcEnableTrading,
                                   XSPARK_SMC_MAX_OPEN_TRADES,
                                   true,
                                   XSPARK_SMC_SEED_SPREAD_CAP_POINTS,
                                   XSPARK_SMC_MAX_SPREAD_ATR_PCT,
                                   g_smc_use_killswitch,
                                   g_smc_total_dd_pct,
                                   g_smc_daily_dd_pct,
                                   XSPARK_SMC_MAX_QUOTE_AGE_SECONDS,
                                   InpSmcClearKillswitchLatch,
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
   // This model has no score to grade exposure by, so the tier lookup must not
   // be able to change the answer.
   if(!g_risk_manager.Initialize(g_smc_risk_pct,
                                 g_smc_risk_pct,
                                 g_smc_risk_pct,
                                 XSPARK_SMC_MAX_RISK_PCT,
                                 XSPARK_SMC_MAX_OPEN_TRADES,
                                 XSPARK_SMC_MAX_ACCOUNT_RISK_PCT))
   {
      g_logger.Critical("RiskManager", g_risk_manager.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_sizer.Initialize(g_smc_min_lot_cap_pct))
   {
      g_logger.Critical("PositionSizer", "Failed to initialize position sizer");
      return INIT_FAILED;
   }

   // The band the execution engine will accept a derived target inside. It is
   // the model's own reward bounds rather than a multiple of a chosen target,
   // because there is no chosen target: each signal carries the ratio its own
   // draw on liquidity implied.
   const double smc_min_rr = g_smc_config.min_target_r * XSPARK_SMC_TARGET_BAND_LOW_MULT;
   const double smc_max_rr = g_smc_config.max_target_r * XSPARK_SMC_TARGET_BAND_HIGH_MULT;

   if(!g_execution_engine.Initialize(InpSmcMagicNumber,
                                     XSPARK_SMC_COMMENT_DEFAULT,
                                     XSPARK_SMC_ENTRY_DEVIATION_POINTS,
                                     g_score_point_size,
                                     true,   // validate against the broker's stop level
                                     true,   // check margin before sending
                                     XSPARK_SMC_MARGIN_BUFFER_PCT,
                                     smc_min_rr,
                                     smc_max_rr,
                                     XSPARK_SMC_MAX_QUOTE_AGE_SECONDS,
                                     XSPARK_SMC_MAX_OPEN_TRADES,
                                     XSPARK_SMC_MAX_ACCOUNT_RISK_PCT))
   {
      g_logger.Critical("ExecutionEngine", g_execution_engine.LastReason());
      return INIT_FAILED;
   }

   if(!g_position_manager.Initialize(_Symbol,
                                     InpSmcMagicNumber,
                                     g_score_point_size,
                                     XSPARK_SMC_EXIT_DEVIATION_POINTS,
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

   g_logger.Info("RiskManager",
                 StringFormat("Trade slots=%d; per-entry risk %.2f%%; account cap %.2f%%; small-account cap %.2f%%.",
                              XSPARK_SMC_MAX_OPEN_TRADES, g_smc_risk_pct,
                              XSPARK_SMC_MAX_ACCOUNT_RISK_PCT, g_smc_min_lot_cap_pct));

   g_logger.Info("SMC",
                 StringFormat("Rule on %s, with NO indicator anywhere in it: structure is rebuilt from the last %d closed candles every bar - a %d-bar internal structure and a %d-bar swing structure, each with its own break of structure and change of character. "
                              "A break leaves an ORDER BLOCK at the extreme candle of the leg that made it; the entry is a LIMIT at that block's midpoint while it is unmitigated and no more than %d bars old, and the stop sits %.0f points beyond its far edge.",
                              EnumToString(g_base_timeframe),
                              XSPARK_SCOREBOT_STRUCTURE_BASE_BARS,
                              g_smc_config.internal_length,
                              g_smc_config.swing_length,
                              g_smc_config.max_block_age_bars,
                              g_smc_config.stop_buffer_points));

   g_logger.Info("SMC",
                 StringFormat("Structure [%s]: %s. Entry zone [%s]: %s. Premium/discount is %s, so a buy is taken only from the lower half of the dealing range and a sell only from the upper half.",
                              EnumToString(InpSmcStructure),
                              XSparkSmcStructureName(g_smc_config.structure_mode),
                              EnumToString(InpSmcConfluence),
                              g_smc_config.require_gap ? "the order block, and the leg must also have left an unfilled price gap"
                                                       : "the order block on its own",
                              g_smc_config.use_premium_discount ? "ON" : "OFF"));

   g_logger.Info("SMC",
                 StringFormat("Exit: the target is the DRAW ON LIQUIDITY - the extreme the indicator labels Strong or Weak - so the reward ratio is an output, not a setting. Draws nearer than %.2f x the stop are refused and further than %.2f x are treated as a different trade; "
                              "the engine accepts a derived target inside %.2f-%.2f. At the %.2f x floor a trade with NO edge wins about %.1f%% at the %.1f%% cost share and breaks even at %.1f%%. "
                              "Stop and target are sent with the order; there is no trailing and no partial close. Hold time %d seconds, and the weekend backstop above.",
                              g_smc_config.min_target_r, g_smc_config.max_target_r,
                              smc_min_rr, smc_max_rr,
                              g_smc_config.min_target_r,
                              XSparkSmcNoEdgeWinRate(g_smc_config.min_target_r, g_smc_config.max_cost_share_pct) * 100.0,
                              g_smc_config.max_cost_share_pct,
                              XSparkSmcBreakEvenWinRate(g_smc_config.min_target_r) * 100.0,
                              XSparkSmcMaxHoldSeconds(PeriodSeconds(g_base_timeframe))));

   g_logger.Info("SMC",
                 "NOT A PROFITABILITY CLAIM. This is a mechanized reading of a drawing tool, and the trade built on it was decided here rather than transcribed - the source contains no entry, stop, target or size. "
                 "Read the OnTester verdict, not the equity curve: it reports a 95% interval on expectancy and says NOT DISTINGUISHABLE when the sample cannot support a conclusion.");

   XSparkSmcLogCostLine();
   XSparkSmcLogMinimumLotLine();

   return INIT_SUCCEEDED;
}

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
   const double fitness = g_position_manager.RecordedFitness(XSPARK_FITNESS_PENALTY_K, XSPARK_FITNESS_MIN_TRADES);

   double wilson_low = 0.0;
   XSparkSmcWilsonLowerBound(wins, outcomes, wilson_low);

   // EXPECTANCY IS THE VERDICT HERE, not the win rate, and that follows from
   // the model rather than from taste. The target is the draw on liquidity, so
   // every trade carries its own reward ratio and there is no single break-even
   // win rate to test a proportion against: 40% wins is losing at 1.5R and
   // winning at 4R. Mean R against zero is the only question the sample can
   // actually answer.
   //
   // The win rate and its Wilson bound are still printed, as description. They
   // are deliberately NOT turned into a verdict, because a win-rate verdict
   // here would be arithmetic applied to a number it does not fit.
   const bool enough_trades = outcomes >= XSPARK_SMC_MIN_TRADES_FOR_VERDICT;
   const string win_verdict = StringFormat("win rate %.1f%% (95%% lower bound %.1f%%) is DESCRIPTIVE ONLY: each trade carries its own reward ratio",
                                           win_rate * 100.0, wilson_low * 100.0);
   const string expectancy_verdict = !enough_trades
                                     ? StringFormat("EXPECTANCY NOT TESTABLE: %d outcomes, %d required", outcomes, XSPARK_SMC_MIN_TRADES_FOR_VERDICT)
                                     : (mean_r - XSPARK_SMC_WILSON_Z_SCORE * se_r <= 0.0
                                        ? "EXPECTANCY NOT DISTINGUISHABLE FROM ZERO"
                                        : "EXPECTANCY ABOVE ZERO AT 95%");

   g_logger.Info("Tester",
                 StringFormat("Pass result: recorded_trades=%d outcomes=%d wins=%d losses=%d win_rate=%.4f wilson95_low=%.4f mean_R=%.4f se_R=%.4f stdev_R=%.4f min_R=%.4f max_R=%.4f fitness=%.6f live_at_end=%d verdict=%s; %s",
                              trades, outcomes, wins, losses, win_rate, wilson_low,
                              mean_r, se_r, stdev_r,
                              g_position_manager.RecordedMinR(),
                              g_position_manager.RecordedMaxR(),
                              fitness, live_at_end, win_verdict, expectancy_verdict));

   XSparkSmcLogFunnel(g_funnel_day_id, "tester pass ended");

   return fitness;
}

void OnDeinit(const int reason)
{
   XSparkSmcLogFunnel(g_funnel_day_id, "shutting down");
   g_strategy.Deinitialize();
   g_indicator_cache.Deinitialize();
   g_logger.Info("EA", StringFormat("XSparkSMC stopped (reason %d)", reason));
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
         XSparkSmcLogFunnel(g_funnel_day_id, "server day ended");
         XSparkSmcResetFunnel();
         g_funnel_day_id = day_id;
         XSparkSmcLogCostLine();
         XSparkSmcLogMinimumLotLine();
      }
   }

   g_safety_manager.RefreshDrawdownState(AccountInfoDouble(ACCOUNT_EQUITY), server_time, g_logger);

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
      return;
   }

   // Management settings, rebuilt every tick. Mode CANDLE_ANCHOR with anchors
   // of zero and an empty ladder: the manager never proposes a trail and never
   // touches the stop, which is the tested "missing anchor leaves the stop
   // alone" behaviour. The only exits here are the hold time and the weekend
   // backstop; the broker-side stop and target went out with the order.
   XSparkTrailPlan trail_plan;
   XSparkResetTrailPlan(trail_plan);
   trail_plan.mode = XSPARK_TRAIL_CANDLE_ANCHOR;
   trail_plan.atr = g_latest_closed_atr14;
   trail_plan.max_hold_seconds = XSparkSmcMaxHoldSeconds(PeriodSeconds(g_base_timeframe));

   // While the spread is wider than this share of the typical candle a due
   // close is deferred, so a hold time that comes due across the rollover waits
   // for the rollover spread to pass instead of paying it.
   trail_plan.exit_max_spread = g_latest_closed_atr14 > 0.0
                                ? XSPARK_SMC_MAX_SPREAD_ATR_PCT / 100.0 * g_latest_closed_atr14
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
                                      g_smc_use_weekend_close,
                                      g_smc_weekend_close_hour,
                                      g_smc_weekend_close_minute,
                                      g_logger);

   const datetime current_bar_time = iTime(_Symbol, g_base_timeframe, 0);
   if(current_bar_time == 0)
      return;

   if(current_bar_time != g_current_base_bar_time)
   {
      g_current_base_bar_time = current_bar_time;
      XSparkSmcEvaluateNewBar();
   }
}
