#ifndef XSPARK_CORE_SYMBOL_MATH_MQH
#define XSPARK_CORE_SYMBOL_MATH_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

#define XSPARK_XAU_CANONICAL_POINT_SIZE 0.01

double XSparkCanonicalPointsToPrice(const double canonical_points)
{
   return canonical_points * XSPARK_XAU_CANONICAL_POINT_SIZE;
}

double XSparkPriceToCanonicalPoints(const double price_distance)
{
   return price_distance / XSPARK_XAU_CANONICAL_POINT_SIZE;
}

double XSparkPriceDistanceToBrokerPoints(const double price_distance, const double broker_point_size)
{
   if(broker_point_size <= 0.0)
      return 0.0;

   return price_distance / broker_point_size;
}

double XSparkCanonicalPointsToBrokerPointsForPointSize(const double canonical_points,
                                                       const double broker_point_size)
{
   return XSparkPriceDistanceToBrokerPoints(XSparkCanonicalPointsToPrice(canonical_points),
                                            broker_point_size);
}

double XSparkCanonicalPointsToBrokerPoints(const string symbol, const double canonical_points)
{
   const double broker_point_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return XSparkCanonicalPointsToBrokerPointsForPointSize(canonical_points, broker_point_size);
}

double XSparkBrokerPointsToPrice(const string symbol, const double broker_points)
{
   const double broker_point_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(broker_point_size <= 0.0)
      return 0.0;

   return broker_points * broker_point_size;
}

double XSparkNormalizePrice(const string symbol, const double price)
{
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

int XSparkVolumeDigitsFromStep(const double volume_step)
{
   if(volume_step <= 0.0)
      return 2;

   for(int digits = 0; digits <= 8; digits++)
   {
      const double scaled = volume_step * MathPow(10.0, digits);
      if(MathAbs(scaled - MathRound(scaled)) < 0.0000001)
         return digits;
   }

   return 8;
}

double XSparkNormalizeVolumeDown(const double volume, const double volume_step)
{
   if(volume <= 0.0 || volume_step <= 0.0)
      return 0.0;

   const double normalized = MathFloor((volume / volume_step) + 0.000000001) * volume_step;
   return NormalizeDouble(normalized, XSparkVolumeDigitsFromStep(volume_step));
}

double XSparkMinimumStopDistance(const string symbol)
{
   const long stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(stops_level <= 0 || point <= 0.0)
      return 0.0;

   return (double)stops_level * point;
}

bool XSparkIsXauUsdSymbol(const string symbol)
{
   string upper = symbol;
   StringToUpper(upper);
   return StringFind(upper, "XAUUSD") >= 0;
}

bool XSparkAdjustProtectionLevels(const string symbol,
                                  const EXSparkSignalDirection direction,
                                  const double reference_price,
                                  const double requested_sl,
                                  const double requested_tp,
                                  const bool use_stop_level_validation,
                                  double &adjusted_sl,
                                  double &adjusted_tp,
                                  string &reason)
{
   adjusted_sl = requested_sl;
   adjusted_tp = requested_tp;
   reason = "";

   if(symbol == "" || reference_price <= 0.0)
   {
      reason = "Invalid symbol or reference price for stop-level validation.";
      return false;
   }

   adjusted_sl = requested_sl > 0.0 ? XSparkNormalizePrice(symbol, requested_sl) : 0.0;
   adjusted_tp = requested_tp > 0.0 ? XSparkNormalizePrice(symbol, requested_tp) : 0.0;

   if(!use_stop_level_validation)
      return true;

   const double min_distance = XSparkMinimumStopDistance(symbol);
   const double broker_point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(broker_point <= 0.0)
   {
      reason = "Broker point size is unavailable for stop-level validation.";
      return false;
   }

   bool changed = false;

   if(direction == XSPARK_SIGNAL_BUY)
   {
      if(adjusted_sl > 0.0 && (reference_price - adjusted_sl) < min_distance)
      {
         adjusted_sl = XSparkNormalizePrice(symbol, reference_price - min_distance);
         while(adjusted_sl > 0.0 && (reference_price - adjusted_sl) < min_distance)
            adjusted_sl = XSparkNormalizePrice(symbol, adjusted_sl - broker_point);
         changed = true;
      }

      if(adjusted_tp > 0.0 && (adjusted_tp - reference_price) < min_distance)
      {
         adjusted_tp = XSparkNormalizePrice(symbol, reference_price + min_distance);
         while(adjusted_tp > 0.0 && (adjusted_tp - reference_price) < min_distance)
            adjusted_tp = XSparkNormalizePrice(symbol, adjusted_tp + broker_point);
         changed = true;
      }
   }
   else if(direction == XSPARK_SIGNAL_SELL)
   {
      if(adjusted_sl > 0.0 && (adjusted_sl - reference_price) < min_distance)
      {
         adjusted_sl = XSparkNormalizePrice(symbol, reference_price + min_distance);
         while(adjusted_sl > 0.0 && (adjusted_sl - reference_price) < min_distance)
            adjusted_sl = XSparkNormalizePrice(symbol, adjusted_sl + broker_point);
         changed = true;
      }

      if(adjusted_tp > 0.0 && (reference_price - adjusted_tp) < min_distance)
      {
         adjusted_tp = XSparkNormalizePrice(symbol, reference_price - min_distance);
         while(adjusted_tp > 0.0 && (reference_price - adjusted_tp) < min_distance)
            adjusted_tp = XSparkNormalizePrice(symbol, adjusted_tp - broker_point);
         changed = true;
      }
   }
   else
   {
      reason = "Protection levels cannot be adjusted for a NONE signal.";
      return false;
   }

   if(changed)
      reason = "Protection levels were moved outward to satisfy broker stop-level rules.";

   return true;
}

#endif
