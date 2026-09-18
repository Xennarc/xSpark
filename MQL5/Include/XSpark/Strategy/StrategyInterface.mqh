#ifndef XSPARK_STRATEGY_INTERFACE_MQH
#define XSPARK_STRATEGY_INTERFACE_MQH

enum EXSparkSignalDirection
{
   XSPARK_SIGNAL_NONE = 0,
   XSPARK_SIGNAL_BUY = 1,
   XSPARK_SIGNAL_SELL = -1
};

// Raw closed-bar measurements, carried unchanged into entries and rejections.
struct XSparkSignalContext
{
   double bar1_open, bar1_high, bar1_low, bar1_close;
   double rsi_base, rsi_base_prev, rsi_higher, atr14;
};

void XSparkResetSignalContext(XSparkSignalContext &context)
{
   context.bar1_open = 0.0; context.bar1_high = 0.0;
   context.bar1_low = 0.0; context.bar1_close = 0.0;
   context.rsi_base = 0.0; context.rsi_base_prev = 0.0;
   context.rsi_higher = 0.0; context.atr14 = 0.0;
}

struct XSparkSignal
{
   datetime               instance_time;
   XSparkSignalContext    context;
   string                 symbol;
   EXSparkSignalDirection direction;
   double                 desired_stop;
   double                 desired_target;
   string                 reason;
   datetime               timestamp;
   datetime               signal_bar_time;
   double                 score;
   double                 effective_threshold;
   double                 dynamic_rr;
   double                 atr14;
   double                 atr50;
   double                 pattern_score;
   double                 atr_score;
   double                 trend_score;
   double                 rsi_score;
   double                 sr_score;
   double                 volume_score;
   double                 mtf_score;
   double                 session_weight;
   int                    pattern_id;
   string                 pattern_name;
};

void XSparkResetSignal(XSparkSignal &signal)
{
   signal.instance_time = 0;
   XSparkResetSignalContext(signal.context);
   signal.symbol = "";
   signal.direction = XSPARK_SIGNAL_NONE;
   signal.desired_stop = 0.0;
   signal.desired_target = 0.0;
   signal.reason = "";
   signal.timestamp = 0;
   signal.signal_bar_time = 0;
   signal.score = 0.0;
   signal.effective_threshold = 0.0;
   signal.dynamic_rr = 0.0;
   signal.atr14 = 0.0;
   signal.atr50 = 0.0;
   signal.pattern_score = 0.0;
   signal.atr_score = 0.0;
   signal.trend_score = 0.0;
   signal.rsi_score = 0.0;
   signal.sr_score = 0.0;
   signal.volume_score = 0.0;
   signal.mtf_score = 0.0;
   signal.session_weight = 0.0;
   signal.pattern_id = 0;
   signal.pattern_name = "";
}

class IXSparkStrategy
{
public:
   virtual bool Initialize(const string symbol) = 0;
   virtual void Deinitialize() = 0;
};

#endif
