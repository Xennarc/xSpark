#ifndef XSPARK_STRATEGY_PATTERN_DETECTOR_MQH
#define XSPARK_STRATEGY_PATTERN_DETECTOR_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

bool XSparkDetectPinBar(XSparkCandle &bar, XSparkPatternResult &result)
{
   XSparkResetPatternResult(result);

   const double range = bar.high - bar.low;
   if(range <= 0.0)
      return false;

   const double body = MathAbs(bar.close - bar.open);
   const double upper = bar.high - MathMax(bar.open, bar.close);
   const double lower = MathMin(bar.open, bar.close) - bar.low;

   if(lower >= 2.0 * body &&
      body <= 0.35 * range &&
      lower >= 0.55 * range)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_BUY;
      result.pattern_id = XSPARK_PATTERN_BULLISH_PIN;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = MathMin(2.0, 1.0 + lower / range);
      return true;
   }

   if(upper >= 2.0 * body &&
      body <= 0.35 * range &&
      upper >= 0.55 * range)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_SELL;
      result.pattern_id = XSPARK_PATTERN_BEARISH_PIN;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = MathMin(2.0, 1.0 + upper / range);
      return true;
   }

   return false;
}

bool XSparkDetectEngulfing(XSparkCandle &bar1, XSparkCandle &bar2, XSparkPatternResult &result)
{
   XSparkResetPatternResult(result);

   const double body1 = MathAbs(bar1.close - bar1.open);
   const double body2 = MathAbs(bar2.close - bar2.open);

   if(body2 <= 0.0)
      return false;

   if(bar2.close < bar2.open &&
      bar1.close > bar1.open &&
      bar1.close > bar2.open &&
      bar1.open < bar2.close &&
      body1 > body2)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_BUY;
      result.pattern_id = XSPARK_PATTERN_BULLISH_ENGULFING;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = MathMin(2.0, 1.0 + ((body1 / body2) - 1.0) * 0.5);
      return true;
   }

   if(bar2.close > bar2.open &&
      bar1.close < bar1.open &&
      bar1.close < bar2.open &&
      bar1.open > bar2.close &&
      body1 > body2)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_SELL;
      result.pattern_id = XSPARK_PATTERN_BEARISH_ENGULFING;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = MathMin(2.0, 1.0 + ((body1 / body2) - 1.0) * 0.5);
      return true;
   }

   return false;
}

bool XSparkDetectInsideBarBreakout(XSparkCandle &bar1,
                                   XSparkCandle &bar2,
                                   XSparkCandle &bar3,
                                   XSparkPatternResult &result)
{
   XSparkResetPatternResult(result);

   const bool inside = bar2.high < bar3.high && bar2.low > bar3.low;
   if(!inside)
      return false;

   if(bar1.close > bar2.high)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_BUY;
      result.pattern_id = XSPARK_PATTERN_BULLISH_IBR;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = 1.5;
      return true;
   }

   if(bar1.close < bar2.low)
   {
      result.found = true;
      result.direction = XSPARK_SIGNAL_SELL;
      result.pattern_id = XSPARK_PATTERN_BEARISH_IBR;
      result.pattern_name = XSparkPatternNameFromId(result.pattern_id);
      result.score = 1.5;
      return true;
   }

   return false;
}

bool XSparkDetectScoreBotPattern(XSparkCandle &bar1,
                                 XSparkCandle &bar2,
                                 XSparkCandle &bar3,
                                 const bool drop_inside_bar_breakout,
                                 XSparkPatternResult &result)
{
   if(XSparkDetectPinBar(bar1, result))
      return true;

   if(XSparkDetectEngulfing(bar1, bar2, result))
      return true;

   if(!drop_inside_bar_breakout && XSparkDetectInsideBarBreakout(bar1, bar2, bar3, result))
      return true;

   XSparkResetPatternResult(result);
   return false;
}

#endif
