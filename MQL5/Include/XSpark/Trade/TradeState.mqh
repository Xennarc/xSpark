#ifndef XSPARK_TRADE_TRADE_STATE_MQH
#define XSPARK_TRADE_TRADE_STATE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

struct XSparkTradeState
{
   ulong                  ticket;
   long                   identifier;
   EXSparkSignalDirection direction;
   double                 entry;
   double                 initial_sl;
   double                 initial_tp;
   double                 initial_lots;
   bool                   partial_done;
   double                 current_trail_sl;
   datetime               open_time;
   double                 entry_score;
   datetime               signal_bar_time;
   EXSparkScoreBotPatternId pattern_id;
   string                 pattern_name;
   double                 initial_risk_distance;
};

void XSparkResetTradeState(XSparkTradeState &state)
{
   state.ticket = 0;
   state.identifier = 0;
   state.direction = XSPARK_SIGNAL_NONE;
   state.entry = 0.0;
   state.initial_sl = 0.0;
   state.initial_tp = 0.0;
   state.initial_lots = 0.0;
   state.partial_done = false;
   state.current_trail_sl = 0.0;
   state.open_time = 0;
   state.entry_score = 0.0;
   state.signal_bar_time = 0;
   state.pattern_id = XSPARK_PATTERN_NONE;
   state.pattern_name = "NO PATTERN";
   state.initial_risk_distance = 0.0;
}

#endif
