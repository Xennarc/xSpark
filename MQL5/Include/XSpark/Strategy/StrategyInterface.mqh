#ifndef XSPARK_STRATEGY_INTERFACE_MQH
#define XSPARK_STRATEGY_INTERFACE_MQH

enum EXSparkSignalDirection
{
   XSPARK_SIGNAL_NONE = 0,
   XSPARK_SIGNAL_BUY = 1,
   XSPARK_SIGNAL_SELL = -1
};

struct XSparkSignal
{
   string                 symbol;
   EXSparkSignalDirection direction;
   double                 desired_stop;
   double                 desired_target;
   string                 reason;
   datetime               timestamp;
};

void XSparkResetSignal(XSparkSignal &signal)
{
   signal.symbol = "";
   signal.direction = XSPARK_SIGNAL_NONE;
   signal.desired_stop = 0.0;
   signal.desired_target = 0.0;
   signal.reason = "";
   signal.timestamp = 0;
}

class IXSparkStrategy
{
public:
   virtual bool Initialize(const string symbol) = 0;
   virtual void Deinitialize() = 0;
   virtual bool Evaluate(XSparkSignal &signal) = 0;
};

#endif
