#ifndef XSPARK_STRATEGY_SCOREBOT_TYPES_MQH
#define XSPARK_STRATEGY_SCOREBOT_TYPES_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

#define XSPARK_SCOREBOT_MAGIC_DEFAULT 770331
#define XSPARK_SCOREBOT_COMMENT_DEFAULT "ScoreBot_v3"
#define XSPARK_SCOREBOT_PRIMARY_TIMEFRAME PERIOD_M15
#define XSPARK_SCOREBOT_MAX_SCORE 9.0
#define XSPARK_SCOREBOT_TIER3_THRESHOLD 5.5
#define XSPARK_SCOREBOT_TIER2_THRESHOLD 4.5
#define XSPARK_SCOREBOT_DEVIATION_CANONICAL_POINTS 30.0

enum EXSparkScoreBotPatternId
{
   XSPARK_PATTERN_NONE = 0,
   XSPARK_PATTERN_BULLISH_PIN = 1,
   XSPARK_PATTERN_BEARISH_PIN = 2,
   XSPARK_PATTERN_BULLISH_ENGULFING = 3,
   XSPARK_PATTERN_BEARISH_ENGULFING = 4,
   XSPARK_PATTERN_BULLISH_IBR = 5,
   XSPARK_PATTERN_BEARISH_IBR = 6
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
   double                 rsi_m15;
   double                 rsi_h1;
   double                 ema21_m15;
   double                 ema50_m15;
   double                 ema50_h1;
   double                 selected_risk_pct;
   XSparkScoreComponents  components;
};

struct XSparkTradePlan
{
   string                 symbol;
   EXSparkSignalDirection direction;
   datetime               signal_bar_time;
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

struct XSparkExecutionResult
{
   bool   confirmed;
   ulong  order_ticket;
   ulong  deal_ticket;
   ulong  position_ticket;
   long   retcode;
   string retcode_description;
   double price;
   double volume;
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
      default:
         return "NO PATTERN";
   }
}

void XSparkResetPatternResult(XSparkPatternResult &result)
{
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
   report.rsi_m15 = 0.0;
   report.rsi_h1 = 0.0;
   report.ema21_m15 = 0.0;
   report.ema50_m15 = 0.0;
   report.ema50_h1 = 0.0;
   report.selected_risk_pct = 0.0;
   XSparkResetScoreComponents(report.components);
}

void XSparkResetTradePlan(XSparkTradePlan &plan)
{
   plan.symbol = "";
   plan.direction = XSPARK_SIGNAL_NONE;
   plan.signal_bar_time = 0;
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
   result.retcode = 0;
   result.retcode_description = "";
   result.price = 0.0;
   result.volume = 0.0;
}

#endif
