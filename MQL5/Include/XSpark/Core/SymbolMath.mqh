#ifndef XSPARK_CORE_SYMBOL_MATH_MQH
#define XSPARK_CORE_SYMBOL_MATH_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

// ---------------------------------------------------------------------------
// ScoreBot point size
// ---------------------------------------------------------------------------
// ScoreBot thresholds - the ATR gate, the spread cap, the entry deviation and
// the exit deviation - are denominated in "ScoreBot points". A ScoreBot point
// is a PRICE quantity, not a quote-precision artefact: the tested strategy
// specified its thresholds in US cents of gold, so for XAUUSD one ScoreBot
// point is 0.01 price units.
//
// The size is now resolved from the instrument specification rather than
// hardcoded, and asserted against the declared XAUUSD baseline below while the
// EA remains XAUUSD-only. On XAUUSD the resolved and declared values are
// bitwise identical at both quote conventions a broker may use for gold
// (2 digits: point 0.01; 3 digits: 0.001 * 10, an exact binary64 product), so
// the change is behaviour-neutral on gold by construction rather than by
// approximation.
//
// Resolution happens ONCE at initialisation and the size is passed to the
// modules that need it. A conversion never reads the terminal: the exit
// deviation is converted on the killswitch flatten path, which deliberately
// runs while the quote feed is unusable, and a SymbolInfoDouble call there
// could fail at exactly the moment the conversion matters most.

#define XSPARK_XAUUSD_SCORE_POINT_SIZE 0.01

// Broker-reported digits above this are not a quote convention this EA models.
#define XSPARK_SPEC_MAX_DIGITS 8

// Relative agreement required between SYMBOL_POINT and 10^-SYMBOL_DIGITS.
#define XSPARK_SPEC_RELATIVE_TOLERANCE 0.000001

// Upper bound on the outward stop/target walk so a pathological point size or
// stop level can never spin OnTick forever.
#define XSPARK_MAX_STOP_ADJUST_STEPS 1000

// Conventional pip size for an instrument specification. Takes the spec as data
// rather than a symbol so it stays deterministic in a script with no chart,
// no Market Watch entry and no terminal connection.
bool XSparkPipSizeForSpec(const int digits, const double point, double &pip, string &reason)
{
   pip = 0.0;
   reason = "";

   if(!MathIsValidNumber(point) || point <= 0.0)
   {
      reason = "Instrument point size is not a valid positive number.";
      return false;
   }

   if(digits < 0 || digits > XSPARK_SPEC_MAX_DIGITS)
   {
      reason = StringFormat("Instrument digits %d is outside the supported range 0-%d.",
                            digits,
                            XSPARK_SPEC_MAX_DIGITS);
      return false;
   }

   // SYMBOL_POINT and SYMBOL_DIGITS are independent broker-reported fields.
   // Deriving the threshold size from one while XSparkNormalizePrice rounds
   // prices with the other is only sound while the two agree, so disagreement
   // fails closed instead of silently skewing every threshold.
   const double expected_point = MathPow(10.0, -digits);
   if(expected_point <= 0.0 || MathAbs(point / expected_point - 1.0) > XSPARK_SPEC_RELATIVE_TOLERANCE)
   {
      reason = StringFormat("Instrument point %s disagrees with digits %d (expected %s).",
                            DoubleToString(point, 10),
                            digits,
                            DoubleToString(expected_point, 10));
      return false;
   }

   // A 3- or 5-digit quote carries a fractional sub-unit below the conventional
   // pip; every other digit count quotes the pip directly.
   pip = (digits == 3 || digits == 5) ? point * 10.0 : point;

   if(!MathIsValidNumber(pip) || pip <= 0.0)
   {
      reason = "Derived pip size is not a valid positive number.";
      return false;
   }

   return true;
}

// Reads the live instrument specification and derives the ScoreBot point size
// from it. Call once at initialisation, never inside a conversion.
bool XSparkResolveScorePointSize(const string symbol, double &score_point_size, string &reason)
{
   score_point_size = 0.0;
   reason = "";

   if(symbol == "")
   {
      reason = "Cannot resolve a ScoreBot point size without a symbol.";
      return false;
   }

   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(!XSparkPipSizeForSpec(digits, point, score_point_size, reason))
   {
      score_point_size = 0.0;
      return false;
   }

   return true;
}

double XSparkScorePointsToPrice(const double score_points, const double score_point_size)
{
   if(!MathIsValidNumber(score_points) ||
      !MathIsValidNumber(score_point_size) ||
      score_point_size <= 0.0)
   {
      return 0.0;
   }

   return score_points * score_point_size;
}

double XSparkPriceToScorePoints(const double price_distance, const double score_point_size)
{
   if(!MathIsValidNumber(price_distance) ||
      !MathIsValidNumber(score_point_size) ||
      score_point_size <= 0.0)
   {
      return 0.0;
   }

   return price_distance / score_point_size;
}

double XSparkPriceDistanceToBrokerPoints(const double price_distance, const double broker_point_size)
{
   if(!MathIsValidNumber(price_distance) ||
      !MathIsValidNumber(broker_point_size) ||
      broker_point_size <= 0.0)
   {
      return 0.0;
   }

   const double broker_points = price_distance / broker_point_size;

   // A non-finite result must never reach a ulong cast: MQL5 leaves that
   // conversion undefined, and the consumer is SetDeviationInPoints.
   if(!MathIsValidNumber(broker_points))
      return 0.0;

   return broker_points;
}

double XSparkScorePointsToBrokerPoints(const double score_points,
                                       const double score_point_size,
                                       const double broker_point_size)
{
   return XSparkPriceDistanceToBrokerPoints(XSparkScorePointsToPrice(score_points, score_point_size),
                                            broker_point_size);
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

   // Relative tolerance: an absolute epsilon would report 0 decimals for a very
   // small step (e.g. 1e-8) because the un-scaled value is already below it.
   for(int digits = 0; digits <= 8; digits++)
   {
      const double scaled = volume_step * MathPow(10.0, digits);
      if(MathAbs(scaled - MathRound(scaled)) < 0.0000001 * MathMax(1.0, scaled))
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
         for(int step = 0;
             step < XSPARK_MAX_STOP_ADJUST_STEPS && adjusted_sl > 0.0 && (reference_price - adjusted_sl) < min_distance;
             step++)
            adjusted_sl = XSparkNormalizePrice(symbol, adjusted_sl - broker_point);
         changed = true;
      }

      if(adjusted_tp > 0.0 && (adjusted_tp - reference_price) < min_distance)
      {
         adjusted_tp = XSparkNormalizePrice(symbol, reference_price + min_distance);
         for(int step = 0;
             step < XSPARK_MAX_STOP_ADJUST_STEPS && adjusted_tp > 0.0 && (adjusted_tp - reference_price) < min_distance;
             step++)
            adjusted_tp = XSparkNormalizePrice(symbol, adjusted_tp + broker_point);
         changed = true;
      }
   }
   else if(direction == XSPARK_SIGNAL_SELL)
   {
      if(adjusted_sl > 0.0 && (adjusted_sl - reference_price) < min_distance)
      {
         adjusted_sl = XSparkNormalizePrice(symbol, reference_price + min_distance);
         for(int step = 0;
             step < XSPARK_MAX_STOP_ADJUST_STEPS && adjusted_sl > 0.0 && (adjusted_sl - reference_price) < min_distance;
             step++)
            adjusted_sl = XSparkNormalizePrice(symbol, adjusted_sl + broker_point);
         changed = true;
      }

      if(adjusted_tp > 0.0 && (reference_price - adjusted_tp) < min_distance)
      {
         adjusted_tp = XSparkNormalizePrice(symbol, reference_price - min_distance);
         for(int step = 0;
             step < XSPARK_MAX_STOP_ADJUST_STEPS && adjusted_tp > 0.0 && (reference_price - adjusted_tp) < min_distance;
             step++)
            adjusted_tp = XSparkNormalizePrice(symbol, adjusted_tp - broker_point);
         changed = true;
      }
   }
   else
   {
      reason = "Protection levels cannot be adjusted for a NONE signal.";
      return false;
   }

   // Fail closed: a bounded walk can run out of steps or cross zero, which would
   // otherwise hand the caller a non-positive or still-invalid protection price.
   if((requested_sl > 0.0 && adjusted_sl <= 0.0) || (requested_tp > 0.0 && adjusted_tp <= 0.0))
   {
      reason = "Stop-level adjustment produced a non-positive protection price.";
      return false;
   }

   const bool buy_ok = direction != XSPARK_SIGNAL_BUY ||
                       ((adjusted_sl <= 0.0 || (reference_price - adjusted_sl) >= min_distance) &&
                        (adjusted_tp <= 0.0 || (adjusted_tp - reference_price) >= min_distance));
   const bool sell_ok = direction != XSPARK_SIGNAL_SELL ||
                        ((adjusted_sl <= 0.0 || (adjusted_sl - reference_price) >= min_distance) &&
                         (adjusted_tp <= 0.0 || (reference_price - adjusted_tp) >= min_distance));

   if(!buy_ok || !sell_ok)
   {
      reason = "Protection levels could not be moved far enough to satisfy broker stop-level rules.";
      return false;
   }

   if(changed)
      reason = "Protection levels were moved outward to satisfy broker stop-level rules.";

   return true;
}

#endif
