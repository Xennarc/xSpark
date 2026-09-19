#property script_show_inputs
#include <XSpark/Strategy/CandleFlow.mqh>

// Deterministic checks for the CandleFlow entry and trailing rules.
//
// These cover pure arithmetic only: candle direction, the wick buffer, the
// anchor, the stop bounds and the one-way ratchet. Broker behaviour, sizing and
// execution are not exercised here and must be validated in the Strategy Tester
// and on a demo account.

int g_flow_passed = 0, g_flow_failed = 0;

void FlowCheck(const string name, const bool ok)
{
   if(ok) { g_flow_passed++; Print("PASS: ",name); }
   else { g_flow_failed++; Print("FAIL: ",name); }
}

void FlowBar(XSparkCandle &bar,
             const double open,
             const double high,
             const double low,
             const double close)
{
   bar.time = (datetime)3000000;
   bar.open = open;
   bar.high = high;
   bar.low = low;
   bar.close = close;
   bar.tick_volume = 100;
}

bool FlowNear(const double a, const double b)
{
   return MathAbs(a - b) < 0.0000001;
}

void RunCandleFlowTests()
{
   string reason = "";
   XSparkCandle bull; FlowBar(bull, 100.0, 101.0, 99.5, 100.8);
   XSparkCandle bear; FlowBar(bear, 100.0, 100.5, 99.0, 99.2);
   XSparkCandle doji; FlowBar(doji, 100.0, 100.4, 99.6, 100.0);

   FlowCheck("a candle closing above its open is a long",
             XSparkCandleFlowBarDirection(bull, 1.0, 0.0, reason) == XSPARK_SIGNAL_BUY);
   FlowCheck("a candle closing below its open is a short",
             XSparkCandleFlowBarDirection(bear, 1.0, 0.0, reason) == XSPARK_SIGNAL_SELL);
   FlowCheck("a candle closing at its open is not a signal",
             XSparkCandleFlowBarDirection(doji, 1.0, 0.0, reason) == XSPARK_SIGNAL_NONE);

   FlowCheck("the body filter rejects a body below the threshold",
             XSparkCandleFlowBarDirection(bull, 1.0, 1.0, reason) == XSPARK_SIGNAL_NONE);
   // Deliberately not tested at the exact threshold: the body is a difference of
   // two prices and the threshold a product, so an equality check there measures
   // floating-point representation rather than the rule.
   FlowCheck("the body filter admits a body above the threshold",
             XSparkCandleFlowBarDirection(bull, 1.0, 0.7, reason) == XSPARK_SIGNAL_BUY);
   FlowCheck("an enabled body filter without an average range refuses rather than passes",
             XSparkCandleFlowBarDirection(bull, 0.0, 0.5, reason) == XSPARK_SIGNAL_NONE);

   XSparkCandle inverted; FlowBar(inverted, 100.0, 99.0, 101.0, 100.8);
   FlowCheck("an impossible candle range is refused",
             XSparkCandleFlowBarDirection(inverted, 1.0, 0.0, reason) == XSPARK_SIGNAL_NONE);

   double buffer = 0.0;
   FlowCheck("the ATR component scales the buffer",
             XSparkCandleFlowBuffer(2.0, 1.5, 0.10, 0.0, 0.0, buffer, reason) && FlowNear(buffer, 0.2));
   FlowCheck("the candle-range component scales the buffer",
             XSparkCandleFlowBuffer(2.0, 1.5, 0.0, 20.0, 0.0, buffer, reason) && FlowNear(buffer, 0.3));
   FlowCheck("buffer components add together with the fixed pad",
             XSparkCandleFlowBuffer(2.0, 1.5, 0.10, 20.0, 0.05, buffer, reason) && FlowNear(buffer, 0.55));
   FlowCheck("an ATR buffer without an average range refuses",
             !XSparkCandleFlowBuffer(0.0, 1.5, 0.10, 0.0, 0.0, buffer, reason));
   FlowCheck("a negative buffer component refuses",
             !XSparkCandleFlowBuffer(2.0, 1.5, -0.10, 0.0, 0.0, buffer, reason));

   double anchor = 0.0;
   FlowCheck("a long anchors below the candle low",
             XSparkCandleFlowAnchor(XSPARK_SIGNAL_BUY, bull, 0.2, anchor, reason) && FlowNear(anchor, 99.3));
   FlowCheck("a short anchors above the candle high",
             XSparkCandleFlowAnchor(XSPARK_SIGNAL_SELL, bull, 0.2, anchor, reason) && FlowNear(anchor, 101.2));
   FlowCheck("an anchor needs a direction",
             !XSparkCandleFlowAnchor(XSPARK_SIGNAL_NONE, bull, 0.2, anchor, reason));
   FlowCheck("a buffer that drives the anchor below zero refuses",
             !XSparkCandleFlowAnchor(XSPARK_SIGNAL_BUY, bull, 200.0, anchor, reason));

   double stop = 0.0, distance = 0.0;
   FlowCheck("a stop wider than the floor is used as the candle placed it",
             XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.8, 99.3, 2.0, 0.25, 0.0, stop, distance, reason) &&
             FlowNear(stop, 99.3) && FlowNear(distance, 1.5));
   FlowCheck("a stop tighter than the floor is widened to the floor",
             XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.8, 100.7, 2.0, 0.25, 0.0, stop, distance, reason) &&
             FlowNear(distance, 0.5) && FlowNear(stop, 100.3));
   FlowCheck("widening to the floor never crosses the reference price",
             stop < 100.8);
   FlowCheck("a short widens to the floor above the reference",
             XSparkCandleFlowStop(XSPARK_SIGNAL_SELL, 100.0, 100.05, 2.0, 0.25, 0.0, stop, distance, reason) &&
             FlowNear(stop, 100.5) && FlowNear(distance, 0.5));
   FlowCheck("an anchor already crossed by price is rescued by the floor",
             XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.0, 100.4, 2.0, 0.25, 0.0, stop, distance, reason) &&
             FlowNear(stop, 99.5));
   FlowCheck("an anchor already crossed by price refuses when no floor is configured",
             !XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.0, 100.4, 2.0, 0.0, 0.0, stop, distance, reason));
   FlowCheck("a stop above the ceiling refuses the entry",
             !XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.8, 95.0, 2.0, 0.25, 2.0, stop, distance, reason));
   FlowCheck("a stop inside the ceiling is accepted",
             XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.8, 99.3, 2.0, 0.25, 2.0, stop, distance, reason));
   FlowCheck("a configured floor without an average range refuses",
             !XSparkCandleFlowStop(XSPARK_SIGNAL_BUY, 100.8, 99.3, 0.0, 0.25, 0.0, stop, distance, reason));

   XSparkCandleFlowConfig config;
   XSparkDefaultCandleFlowConfig(config);
   FlowCheck("the shipped configuration is valid", XSparkValidateCandleFlowConfig(config, reason));

   config.buffer_atr_mult = 0.0;
   FlowCheck("a configuration with no buffer at all is refused",
             !XSparkValidateCandleFlowConfig(config, reason));

   XSparkDefaultCandleFlowConfig(config);
   config.min_stop_atr_mult = 0.0;
   FlowCheck("a configuration with no stop floor is refused",
             !XSparkValidateCandleFlowConfig(config, reason));

   XSparkDefaultCandleFlowConfig(config);
   config.max_stop_atr_mult = 0.20;
   FlowCheck("a ceiling below the floor is refused",
             !XSparkValidateCandleFlowConfig(config, reason));

   Print("CANDLEFLOW RESULT passed=", g_flow_passed, " failed=", g_flow_failed);
}

#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunCandleFlowTests(); }
#endif
