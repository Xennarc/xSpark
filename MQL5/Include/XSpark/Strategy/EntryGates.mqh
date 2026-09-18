#ifndef XSPARK_ENTRY_GATES_MQH
#define XSPARK_ENTRY_GATES_MQH
#include <XSpark/Strategy/MarketStructure.mqh>
#include <XSpark/Strategy/PatternDetector.mqh>

struct XSparkGateConfig
{
   bool observe_only, use_htf, use_pullback, use_rsi, require_rsi_turn;
   bool use_continuation, use_t1, use_t3;
   double min_swing_atr, min_leg_atr, pullback_min, pullback_max;
};
void XSparkDefaultGateConfig(XSparkGateConfig &c)
{
   c.observe_only = true; c.use_htf = false; c.use_pullback = false;
   c.use_rsi = false; c.require_rsi_turn = false; c.use_continuation = false;
   c.use_t1 = true; c.use_t3 = true;
   c.min_swing_atr = 0.5; c.min_leg_atr = 1.5; c.pullback_min = 0.30; c.pullback_max = 0.80;
}
bool XSparkValidateGateConfig(const XSparkGateConfig &c, string &reason)
{
   reason = "";
   if(!MathIsValidNumber(c.min_swing_atr) || c.min_swing_atr <= 0.0 ||
      !MathIsValidNumber(c.min_leg_atr) || c.min_leg_atr <= 0.0 ||
      !MathIsValidNumber(c.pullback_min) || !MathIsValidNumber(c.pullback_max) ||
      c.pullback_min <= 0.0 || c.pullback_max >= 1.0 || c.pullback_min >= c.pullback_max)
      reason = "Invalid swing/leg size or pullback interval (require 0 < min < max < 1).";
   else if(c.use_htf && (!c.use_pullback || !c.use_continuation))
      reason = "HTF structure requires pullback gate and continuation triggers (V2 3.3).";
   else if(c.use_continuation && (!c.use_htf || !c.use_pullback))
      reason = "Continuation triggers require HTF structure and pullback gates.";
   else if(c.require_rsi_turn && !c.use_rsi)
      reason = "RSI turn requires the RSI gate.";
   return reason == "";
}

string XSparkPullbackVerdict(const XSparkStructure &s, const double atr14, const XSparkGateConfig &c)
{
   if(!s.valid || s.leg_origin_shift < 2 || !MathIsValidNumber(atr14) || atr14 <= 0.0 ||
      !MathIsValidNumber(s.leg_range) || s.leg_range < c.min_leg_atr * atr14)
      return "NO QUALIFYING LEG";
   if(!MathIsValidNumber(s.retracement)) return "INVALID RETRACEMENT";
   if(s.retracement > 1.0) return "LEG BROKEN";
   if(s.retracement < c.pullback_min || s.retracement > c.pullback_max) return "NOT IN PULLBACK ZONE";
   return "PASS";
}
string XSparkRSIVerdict(const EXSparkSignalDirection direction, const double current, const double previous,
                        const int long_min, const int long_max, const int short_min, const int short_max,
                        const bool require_turn)
{
   if(!MathIsValidNumber(current) || current < 0.0 || current > 100.0 ||
      (direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)) return "RSI UNAVAILABLE";
   const bool buy = direction == XSPARK_SIGNAL_BUY;
   if(current < (buy ? long_min : short_min)) return buy ? "RSI OUTER LOW" : "RSI INNER LOW";
   if(current > (buy ? long_max : short_max)) return buy ? "RSI INNER HIGH" : "RSI OUTER HIGH";
   if(require_turn)
   {
      if(!MathIsValidNumber(previous) || previous < 0.0 || previous > 100.0) return "RSI HISTORY UNAVAILABLE";
      if((buy && current <= previous) || (!buy && current >= previous)) return "RSI NOT TURNING";
   }
   return "PASS";
}

// Select an aligned legacy candle independently of legacy first-match priority.
// This avoids hiding a valid aligned engulfing behind an opposite pin.
void XSparkAlignedLegacy(XSparkCandle &bar1, XSparkCandle &bar2, XSparkCandle &bar3,
                         const bool drop_ibr, const EXSparkSignalDirection dir, XSparkPatternResult &best)
{
   XSparkResetPatternResult(best);
   XSparkPatternResult p;
   if(XSparkDetectPinBar(bar1, p) && p.direction == dir) best = p;
   if(XSparkDetectEngulfing(bar1, bar2, p) && p.direction == dir && (!best.found || p.score > best.score)) best = p;
   if(!drop_ibr && XSparkDetectInsideBarBreakout(bar1, bar2, bar3, p) && p.direction == dir && (!best.found || p.score > best.score)) best = p;
}

// No armed RAM state: reconstruct timing from the same closed-bar window after
// restart. All three triggers share the leg-origin instance, never a bar key.
bool XSparkDetectContinuation(const XSparkCandle &bars[], const int count,
                              const XSparkStructure &leg, const EXSparkSignalDirection dir,
                              const double rsi_now, const double rsi_prev,
                              const XSparkGateConfig &cfg, const XSparkPatternResult &aligned,
                              XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   if(!leg.valid || count < 3 || count > ArraySize(bars) || leg.leg_origin_shift < 2 ||
      leg.leg_origin_shift > count || leg.leg_extreme_shift < 2 ||
      leg.leg_extreme_shift >= leg.leg_origin_shift ||
      (dir != XSPARK_SIGNAL_BUY && dir != XSPARK_SIGNAL_SELL)) return false;
   const bool buy = dir == XSPARK_SIGNAL_BUY;
   // A pullback extreme must follow the impulse extreme, not precede it.
   int extreme = 0;
   for(int i = 1; i < leg.leg_extreme_shift - 1; i++)
      if((buy && bars[i].low < bars[extreme].low) || (!buy && bars[i].high > bars[extreme].high)) extreme = i;
   if(cfg.use_t1 && extreme >= 1)
   {
      double level = buy ? bars[1].high : bars[1].low;
      for(int i = 2; i <= extreme; i++)
         level = buy ? MathMax(level, bars[i].high) : MathMin(level, bars[i].low);
      if((buy && bars[0].close > level) || (!buy && bars[0].close < level))
      {
         out.found = true; out.direction = dir; out.score = 1.5;
         out.pattern_id = XSPARK_PATTERN_PULLBACK_BREAK; out.pattern_name = "Pullback Break";
      }
   }
   if(aligned.found && (!out.found || aligned.score > out.score)) out = aligned;
   if(!out.found && cfg.use_t3 && rsi_now >= 0.0 && rsi_now <= 100.0 && rsi_prev >= 0.0 && rsi_prev <= 100.0 &&
      leg.retracement >= cfg.pullback_min &&
      ((buy && rsi_now > rsi_prev && bars[0].close > bars[0].open) ||
       (!buy && rsi_now < rsi_prev && bars[0].close < bars[0].open)))
   {
      out.found = true; out.direction = dir; out.score = 1.0;
      out.pattern_id = XSPARK_PATTERN_MOMENTUM_TURN; out.pattern_name = "Momentum Turn";
   }
   return out.found;
}
#endif
