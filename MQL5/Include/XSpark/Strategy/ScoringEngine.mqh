#ifndef XSPARK_STRATEGY_SCORING_ENGINE_MQH
#define XSPARK_STRATEGY_SCORING_ENGINE_MQH

#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>

double XSparkClampDouble(const double value, const double minimum, const double maximum)
{
   if(value < minimum)
      return minimum;

   if(value > maximum)
      return maximum;

   return value;
}

double XSparkScoreBotSessionWeight(const datetime signal_bar_time, const bool allow_asian_reduced)
{
   MqlDateTime parts;
   TimeToStruct(signal_bar_time, parts);

   const bool london = parts.hour >= 7 && parts.hour < 16;
   const bool new_york = parts.hour >= 12 && parts.hour < 21;

   if(london && new_york)
      return 1.2;

   if(london || new_york)
      return 1.0;

   if(allow_asian_reduced)
      return 0.6;

   return 0.0;
}

double XSparkScoreBotDynamicRR(const double atr14,
                               const double atr50,
                               const double min_rr,
                               const double max_rr,
                               const double atr_ratio_boost)
{
   if(atr14 <= 0.0 || atr50 <= 0.0 || atr_ratio_boost <= 0.7)
      return min_rr;

   const double ratio = atr14 / atr50;
   const double t = XSparkClampDouble((ratio - 0.7) / (atr_ratio_boost - 0.7), 0.0, 1.0);
   return min_rr + t * (max_rr - min_rr);
}

double XSparkScoreBotVolumeScore(const long tick_volume_bar1, const double mean_tick_volume_bars2_to_10)
{
   if(tick_volume_bar1 <= 0 || mean_tick_volume_bars2_to_10 <= 0.0)
      return 0.0;

   const double ratio = (double)tick_volume_bar1 / mean_tick_volume_bars2_to_10;
   if(ratio < 1.5)
      return 0.0;

   return MathMin(1.0, (ratio - 1.0) * 0.5);
}

double XSparkScoreBotEffectiveThreshold(const double min_score,
                                        const double long_score_extra,
                                        const EXSparkSignalDirection direction)
{
   if(direction == XSPARK_SIGNAL_BUY)
      return min_score + long_score_extra;

   return min_score;
}

bool XSparkScoreBotScoreIsValid(const double final_score)
{
   return final_score >= -0.0000001 && final_score <= XSPARK_SCOREBOT_MAX_SCORE + 0.0000001;
}

#endif
