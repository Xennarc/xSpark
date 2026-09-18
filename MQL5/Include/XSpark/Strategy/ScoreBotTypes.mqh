#ifndef XSPARK_STRATEGY_SCOREBOT_TYPES_MQH
#define XSPARK_STRATEGY_SCOREBOT_TYPES_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

#define XSPARK_SCOREBOT_MAGIC_DEFAULT 770331
#define XSPARK_SCOREBOT_COMMENT_DEFAULT "ScoreBot_v3"
// The timeframe pair the strategy was tested on. The EA now runs on any
// supported base timeframe, but this pair remains the reference configuration.
#define XSPARK_SCOREBOT_TESTED_BASE_TIMEFRAME PERIOD_M15
#define XSPARK_SCOREBOT_TESTED_HIGHER_TIMEFRAME PERIOD_H1

// Multi-timeframe partner for a base timeframe.
//
// An explicit table rather than arithmetic. PeriodSeconds(base) * 4 followed by
// a nearest-greater-or-equal search is elegant and gives the right answer in the
// middle of the range, but it degenerates at the edges: H8 has no 4x partner so
// it lands on W1 (a 21x jump), H12 lands on W1 (14x), and MN1 has nothing above
// it at all. A table states what is supported, is auditable against the tested
// M15 -> H1 relationship, and makes an unsupported chart period a refusal rather
// than a silently absurd ratio.
bool XSparkHigherTimeframeFor(const ENUM_TIMEFRAMES base,
                              ENUM_TIMEFRAMES &higher,
                              string &reason)
{
   higher = PERIOD_CURRENT;
   reason = "";

   switch(base)
   {
      case PERIOD_M1:  higher = PERIOD_M5;  return true;
      case PERIOD_M5:  higher = PERIOD_M30; return true;
      case PERIOD_M15: higher = PERIOD_H1;  return true;   // the tested pair
      case PERIOD_M30: higher = PERIOD_H2;  return true;
      case PERIOD_H1:  higher = PERIOD_H4;  return true;
      case PERIOD_H2:  higher = PERIOD_H8;  return true;
      case PERIOD_H4:  higher = PERIOD_D1;  return true;
      default:         break;
   }

   reason = "Chart period is not a supported XSpark base timeframe. Supported: M1, M5, M15, M30, H1, H2, H4.";
   return false;
}
#define XSPARK_SCOREBOT_MAX_SCORE 9.0
#define XSPARK_SCOREBOT_TIER3_THRESHOLD 5.5
#define XSPARK_SCOREBOT_TIER2_THRESHOLD 4.5
// DEFAULT for InpEntryDeviationPoints, not a fixed constant. It is the gold
// value that shipped through Phase 1, kept here so the default is bit-for-bit
// what it was; on any other instrument it must be set for that instrument.
// The startup drift-bound check reports whether it still bounds anything.
#define XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS 30.0

// Hard ceiling on risk per trade. Not a preference: with the edge measured in
// docs/IMPROVEMENT_PLAN.md the growth-optimal (Kelly) fraction is 3.58% and
// expected log-growth crosses zero at about 7.2%. Above that a genuinely
// positive edge still shrinks the account, because compounding is
// multiplicative and a large loss needs a larger gain to undo. 10% leaves room
// to size well past the optimum deliberately while refusing the fat-finger
// entries that would otherwise be accepted in silence.
#define XSPARK_MAX_ALLOWED_RISK_PCT 10.0

// Below this many consecutive full-stop losses to the killswitch, the limit is
// tight enough that ordinary variance will latch it. The reference run already
// contained an 8-loss streak.
#define XSPARK_MIN_LOSS_STREAK_TOLERANCE 6

// Optimisation fitness parameters. k is how many standard errors of penalty the
// mean carries, so a pass must show evidence rather than a lucky mean. The
// minimum trade count exists because a mean over a handful of trades is noise
// with a number attached; below it the pass returns the sentinel.
#define XSPARK_FITNESS_PENALTY_K 1.0
#define XSPARK_FITNESS_MIN_TRADES 30

enum EXSparkScoreBotPatternId
{
   XSPARK_PATTERN_NONE = 0,
   XSPARK_PATTERN_BULLISH_PIN = 1,
   XSPARK_PATTERN_BEARISH_PIN = 2,
   XSPARK_PATTERN_BULLISH_ENGULFING = 3,
   XSPARK_PATTERN_BEARISH_ENGULFING = 4,
   XSPARK_PATTERN_BULLISH_IBR = 5,
   XSPARK_PATTERN_BEARISH_IBR = 6,
   XSPARK_PATTERN_PULLBACK_BREAK = 7,
   XSPARK_PATTERN_MOMENTUM_TURN = 8,
   XSPARK_PATTERN_BULL_FLAG = 9,
   XSPARK_PATTERN_BEAR_FLAG = 10,
   XSPARK_PATTERN_INVERSE_HS = 11,
   XSPARK_PATTERN_HEAD_SHOULDERS = 12,
   XSPARK_PATTERN_CUP_HANDLE = 13,
   XSPARK_PATTERN_INVERSE_CUP_HANDLE = 14
};

struct XSparkCandle
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;
};

struct XSparkPatternResult
{
   datetime                instance_time;
   double                  breakout_level;
   bool                    chart_pattern;
   bool                    engulfing_confirmed;
   bool                    found;
   EXSparkSignalDirection  direction;
   EXSparkScoreBotPatternId pattern_id;
   string                  pattern_name;
   double                  score;
};

struct XSparkScoreComponents
{
   double pattern;
   double atr;
   double trend;
   double rsi;
   double sr;
   double volume;
   double mtf;
   double raw;
   double session_weight;
   double final_score;
};

struct XSparkScoreBotReport
{
   string pattern_mode, detected_patterns, pattern_runner_up, entry_location;
   double detected_level, pattern_runner_up_score;
   datetime detected_instance;
   string base_structure, higher_structure, structure_status;
   string htf_verdict, pullback_verdict, rsi_verdict, joint_verdict;
   bool gate_candidate;
   EXSparkSignalDirection candidate_direction;
   string candidate_pattern;
   datetime candidate_instance;
   XSparkSignalContext    context;
   datetime               signal_bar_time;
   EXSparkSignalDirection direction;
   EXSparkScoreBotPatternId pattern_id;
   string                 pattern_name;
   string                 status;
   string                 block_reason;
   bool                   has_pattern;
   bool                   scored;
   bool                   threshold_passed;
   double                 effective_threshold;
   double                 dynamic_rr;
   double                 atr14;
   double                 atr50;
   double                 atr_points;
   double                 atr50_points;
   double                 rsi_base;
   double                 rsi_higher;
   double                 ema21_base;
   double                 ema50_base;
   double                 ema50_higher;
   double                 selected_risk_pct;
   XSparkScoreComponents  components;
};

struct XSparkTradePlan
{
   XSparkSignalContext    context;
   string                 symbol;
   EXSparkSignalDirection direction;
   datetime               signal_bar_time;
   double                 entry_breakout_level;
   double                 entry_limit; // quote chase bound; zero on legacy plans
   double                 planned_risk_distance; // preserved when execution refreshes the plan
   double                 entry_reference;
   double                 theoretical_sl;
   double                 final_sl;
   double                 final_tp;
   double                 risk_distance;
   double                 dynamic_rr;
   double                 score;
   double                 effective_threshold;
   double                 risk_pct;
   double                 volume;
   double                 pattern_score;
   double                 atr_score;
   double                 trend_score;
   double                 rsi_score;
   double                 sr_score;
   double                 volume_score;
   double                 mtf_score;
   double                 session_weight;
   EXSparkScoreBotPatternId pattern_id;
   string                 pattern_name;
};

// Broker-derived execution facts. Everything MT5 exposes about a confirmed
// entry is captured here so downstream state registration never has to guess
// which position was created.
struct XSparkExecutionResult
{
   bool     confirmed;
   ulong    order_ticket;
   ulong    deal_ticket;
   ulong    position_ticket;             // live broker position ticket bound to the entry deal
   long     position_id;                 // DEAL_POSITION_ID of the entry deal
   bool     position_id_exact;           // true when position_id came from the broker deal record
   long     retcode;
   string   retcode_description;
   double   price;                       // trade-server result price
   double   volume;                      // trade-server result volume
   double   fill_price;                  // DEAL_PRICE of the entry deal when available
   double   fill_volume;                 // DEAL_VOLUME of the entry deal when available
   datetime fill_time;                   // DEAL_TIME of the entry deal when available
   datetime submit_time;                 // server time captured immediately before the order send
   double   submitted_entry_reference;   // execution-time entry reference used for sizing
   double   submitted_sl;
   double   submitted_tp;
   double   submitted_volume;
   double   actual_risk_distance;        // execution-time stop distance the volume was sized from
   double   actual_rr;                   // execution-time reward ratio the target was derived from
};

string XSparkDirectionName(const EXSparkSignalDirection direction)
{
   if(direction == XSPARK_SIGNAL_BUY)
      return "BUY";

   if(direction == XSPARK_SIGNAL_SELL)
      return "SELL";

   return "NONE";
}

string XSparkPatternNameFromId(const EXSparkScoreBotPatternId pattern_id)
{
   switch(pattern_id)
   {
      case XSPARK_PATTERN_BULLISH_PIN:
         return "Bullish Pin";
      case XSPARK_PATTERN_BEARISH_PIN:
         return "Bearish Pin";
      case XSPARK_PATTERN_BULLISH_ENGULFING:
         return "Bullish Engulfing";
      case XSPARK_PATTERN_BEARISH_ENGULFING:
         return "Bearish Engulfing";
      case XSPARK_PATTERN_BULLISH_IBR:
         return "Bullish IBR";
      case XSPARK_PATTERN_BEARISH_IBR:
         return "Bearish IBR";
      case XSPARK_PATTERN_BULL_FLAG: return "Bull Flag";
      case XSPARK_PATTERN_BEAR_FLAG: return "Bear Flag";
      case XSPARK_PATTERN_INVERSE_HS: return "Inverse H&S";
      case XSPARK_PATTERN_HEAD_SHOULDERS: return "Head & Shoulders";
      case XSPARK_PATTERN_CUP_HANDLE: return "Cup & Handle";
      case XSPARK_PATTERN_INVERSE_CUP_HANDLE: return "Inverse Cup & Handle";
      case XSPARK_PATTERN_PULLBACK_BREAK: return "Pullback Break";
      case XSPARK_PATTERN_MOMENTUM_TURN: return "Momentum Turn";
      default:
         return "NO PATTERN";
   }
}

void XSparkResetPatternResult(XSparkPatternResult &result)
{
   result.instance_time = 0; result.breakout_level = 0.0;
   result.chart_pattern = false; result.engulfing_confirmed = false;
   result.found = false;
   result.direction = XSPARK_SIGNAL_NONE;
   result.pattern_id = XSPARK_PATTERN_NONE;
   result.pattern_name = "NO PATTERN";
   result.score = 0.0;
}

void XSparkResetScoreComponents(XSparkScoreComponents &components)
{
   components.pattern = 0.0;
   components.atr = 0.0;
   components.trend = 0.0;
   components.rsi = 0.0;
   components.sr = 0.0;
   components.volume = 0.0;
   components.mtf = 0.0;
   components.raw = 0.0;
   components.session_weight = 0.0;
   components.final_score = 0.0;
}

void XSparkResetScoreBotReport(XSparkScoreBotReport &report)
{
   report.pattern_mode = "LEGACY"; report.detected_patterns = "NONE";
   report.pattern_runner_up = "NONE"; report.pattern_runner_up_score = 0.0;
   report.detected_level = 0.0; report.detected_instance = 0;
   report.entry_location = "PIVOT PULLBACK";
   report.base_structure = "unavailable"; report.higher_structure = "unavailable";
   report.structure_status = "UNKNOWN";
   report.htf_verdict = "OFF"; report.pullback_verdict = "OFF"; report.rsi_verdict = "OFF";
   report.joint_verdict = "OFF"; report.gate_candidate = false;
   report.candidate_direction = XSPARK_SIGNAL_NONE; report.candidate_pattern = "NONE";
   report.candidate_instance = 0;
   XSparkResetSignalContext(report.context);
   report.signal_bar_time = 0;
   report.direction = XSPARK_SIGNAL_NONE;
   report.pattern_id = XSPARK_PATTERN_NONE;
   report.pattern_name = "NO PATTERN";
   report.status = "SCANNING";
   report.block_reason = "";
   report.has_pattern = false;
   report.scored = false;
   report.threshold_passed = false;
   report.effective_threshold = 0.0;
   report.dynamic_rr = 0.0;
   report.atr14 = 0.0;
   report.atr50 = 0.0;
   report.atr_points = 0.0;
   report.atr50_points = 0.0;
   report.rsi_base = 0.0;
   report.rsi_higher = 0.0;
   report.ema21_base = 0.0;
   report.ema50_base = 0.0;
   report.ema50_higher = 0.0;
   report.selected_risk_pct = 0.0;
   XSparkResetScoreComponents(report.components);
}

void XSparkResetTradePlan(XSparkTradePlan &plan)
{
   XSparkResetSignalContext(plan.context);
   plan.symbol = "";
   plan.direction = XSPARK_SIGNAL_NONE;
   plan.signal_bar_time = 0;
   plan.entry_limit = 0.0; plan.entry_breakout_level = 0.0;
   plan.planned_risk_distance = 0.0;
   plan.entry_reference = 0.0;
   plan.theoretical_sl = 0.0;
   plan.final_sl = 0.0;
   plan.final_tp = 0.0;
   plan.risk_distance = 0.0;
   plan.dynamic_rr = 0.0;
   plan.score = 0.0;
   plan.effective_threshold = 0.0;
   plan.risk_pct = 0.0;
   plan.volume = 0.0;
   plan.pattern_score = 0.0;
   plan.atr_score = 0.0;
   plan.trend_score = 0.0;
   plan.rsi_score = 0.0;
   plan.sr_score = 0.0;
   plan.volume_score = 0.0;
   plan.mtf_score = 0.0;
   plan.session_weight = 0.0;
   plan.pattern_id = XSPARK_PATTERN_NONE;
   plan.pattern_name = "NO PATTERN";
}

void XSparkResetExecutionResult(XSparkExecutionResult &result)
{
   result.confirmed = false;
   result.order_ticket = 0;
   result.deal_ticket = 0;
   result.position_ticket = 0;
   result.position_id = 0;
   result.position_id_exact = false;
   result.retcode = 0;
   result.retcode_description = "";
   result.price = 0.0;
   result.volume = 0.0;
   result.fill_price = 0.0;
   result.fill_volume = 0.0;
   result.fill_time = 0;
   result.submit_time = 0;
   result.submitted_entry_reference = 0.0;
   result.submitted_sl = 0.0;
   result.submitted_tp = 0.0;
   result.submitted_volume = 0.0;
   result.actual_risk_distance = 0.0;
   result.actual_rr = 0.0;
}

#endif
