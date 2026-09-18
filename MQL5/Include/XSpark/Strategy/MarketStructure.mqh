#ifndef XSPARK_MARKET_STRUCTURE_MQH
#define XSPARK_MARKET_STRUCTURE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

#define XSPARK_STRUCTURE_FRACTAL_WING 2
#define XSPARK_STRUCTURE_MAX_PIVOTS 56
#define XSPARK_STRUCTURE_TR_PERIOD 14

enum EXSparkPivotType { XSPARK_PIVOT_NONE = 0, XSPARK_PIVOT_HIGH = 1, XSPARK_PIVOT_LOW = -1 };
enum EXSparkStructureState { XSPARK_STRUCT_UNKNOWN = 0, XSPARK_STRUCT_UP = 1,
                            XSPARK_STRUCT_DOWN = -1, XSPARK_STRUCT_RANGE = 2 };
struct XSparkPivot
{
   EXSparkPivotType type;
   double price;
   int shift;
   datetime time;
   bool broken;
};
struct XSparkStructure
{
   bool valid;
   string reason;
   int bars_scanned, pivot_count, legs_in_state;
   XSparkPivot pivots[XSPARK_STRUCTURE_MAX_PIVOTS]; // newest first after construction
   EXSparkStructureState state;
   double last_high, prev_high, last_low, prev_low, scale;
   int last_high_shift, last_low_shift;
   double leg_origin, leg_extreme, leg_range, retracement;
   int leg_origin_shift, leg_extreme_shift;
};

void XSparkResetStructure(XSparkStructure &s)
{
   s.valid = false; s.reason = "structure unavailable";
   s.bars_scanned = 0; s.pivot_count = 0; s.legs_in_state = 0;
   s.state = XSPARK_STRUCT_UNKNOWN;
   s.last_high = 0.0; s.prev_high = 0.0; s.last_low = 0.0; s.prev_low = 0.0;
   s.scale = 0.0; s.last_high_shift = 0; s.last_low_shift = 0;
   s.leg_origin = 0.0; s.leg_extreme = 0.0; s.leg_range = 0.0; s.retracement = 0.0;
   s.leg_origin_shift = 0; s.leg_extreme_shift = 0;
}

string XSparkStructureName(const EXSparkStructureState state)
{
   if(state == XSPARK_STRUCT_UP) return "UP";
   if(state == XSPARK_STRUCT_DOWN) return "DOWN";
   if(state == XSPARK_STRUCT_RANGE) return "RANGE";
   return "UNKNOWN";
}

// Arithmetic mean TR, deliberately not Wilder ATR. Index zero is closed bar 1.
double XSparkMeanTrueRange(const XSparkCandle &bars[], const int count, const int period)
{
   if(period < 1 || count <= period || count > ArraySize(bars)) return 0.0;
   double total = 0.0;
   for(int i = 0; i < period; i++)
   {
      const double value = MathMax(bars[i].high - bars[i].low,
                          MathMax(MathAbs(bars[i].high - bars[i + 1].close),
                                  MathAbs(bars[i].low - bars[i + 1].close)));
      if(!MathIsValidNumber(value) || value < 0.0) return 0.0;
      total += value;
   }
   return total / period;
}

// min_swing_atr is a multiple of the window's mean TR. No terminal/cache state.
bool XSparkBuildStructure(const XSparkCandle &bars[], const int count,
                          const double min_swing_atr, XSparkStructure &out)
{
   XSparkResetStructure(out);
   if(count <= XSPARK_STRUCTURE_TR_PERIOD || count > ArraySize(bars) ||
      !MathIsValidNumber(min_swing_atr) || min_swing_atr <= 0.0)
   {
      out.reason = "invalid structure window or swing multiplier"; return false;
   }
   for(int i = 0; i < count; i++)
   {
      if(!MathIsValidNumber(bars[i].open) || !MathIsValidNumber(bars[i].high) ||
         !MathIsValidNumber(bars[i].low) || !MathIsValidNumber(bars[i].close) ||
         bars[i].low <= 0.0 || bars[i].high < MathMax(bars[i].open, bars[i].close) ||
         bars[i].low > MathMin(bars[i].open, bars[i].close) ||
         bars[i].time <= 0 || (i > 0 && bars[i].time >= bars[i - 1].time))
      {
         out.reason = "invalid closed-bar geometry or order"; return false;
      }
   }
   out.scale = XSparkMeanTrueRange(bars, count, XSPARK_STRUCTURE_TR_PERIOD);
   if(!MathIsValidNumber(out.scale) || out.scale <= 0.0)
   {
      out.reason = "mean true range unavailable"; return false;
   }
   const double minimum = min_swing_atr * out.scale;
   if(!MathIsValidNumber(minimum) || minimum <= 0.0) return false;
   const int wing = XSPARK_STRUCTURE_FRACTAL_WING;
   // Oldest to newest: alternation and magnitude filtering are a single pass.
   for(int i = count - wing - 1; i >= wing; i--)
   {
      out.bars_scanned++;
      bool high = true, low = true;
      for(int j = 1; j <= wing; j++)
      {
         high = high && bars[i].high > bars[i - j].high && bars[i].high >= bars[i + j].high;
         low = low && bars[i].low < bars[i - j].low && bars[i].low <= bars[i + j].low;
      }
      if(high == low) continue; // Includes outside bars: never guess a direction.
      XSparkPivot p;
      p.type = high ? XSPARK_PIVOT_HIGH : XSPARK_PIVOT_LOW;
      p.price = high ? bars[i].high : bars[i].low;
      p.shift = i + 1; p.time = bars[i].time; p.broken = false;
      for(int newer = i - 1; newer >= 0; newer--)
         if((high && bars[newer].high > p.price) || (!high && bars[newer].low < p.price))
         { p.broken = true; break; }
      const int top = out.pivot_count - 1;
      if(top >= 0)
      {
         if(out.pivots[top].type == p.type)
         {
            if((high && p.price >= out.pivots[top].price) || (!high && p.price <= out.pivots[top].price))
               out.pivots[top] = p;
            continue;
         }
         if(MathAbs(p.price - out.pivots[top].price) < minimum) continue;
      }
      if(out.pivot_count >= XSPARK_STRUCTURE_MAX_PIVOTS)
      {
         out.reason = "pivot overflow"; return false;
      }
      out.pivots[out.pivot_count++] = p;
   }
   for(int i = 0; i < out.pivot_count / 2; i++)
   {
      XSparkPivot temp = out.pivots[i];
      out.pivots[i] = out.pivots[out.pivot_count - 1 - i];
      out.pivots[out.pivot_count - 1 - i] = temp;
   }
   int highs = 0, lows = 0;
   for(int i = 0; i < out.pivot_count; i++)
   {
      if(out.pivots[i].type == XSPARK_PIVOT_HIGH)
      {
         if(highs == 0) { out.last_high = out.pivots[i].price; out.last_high_shift = out.pivots[i].shift; }
         if(highs == 1) out.prev_high = out.pivots[i].price;
         highs++;
      }
      else
      {
         if(lows == 0) { out.last_low = out.pivots[i].price; out.last_low_shift = out.pivots[i].shift; }
         if(lows == 1) out.prev_low = out.pivots[i].price;
         lows++;
      }
   }
   out.valid = true;
   if(highs < 2 || lows < 2) { out.reason = "fewer than two highs and two lows"; return true; }
   out.state = XSPARK_STRUCT_RANGE;
   if(out.last_high > out.prev_high && out.last_low > out.prev_low) out.state = XSPARK_STRUCT_UP;
   if(out.last_high < out.prev_high && out.last_low < out.prev_low) out.state = XSPARK_STRUCT_DOWN;
   out.reason = "confirmed closed-bar structure";
   if(out.state == XSPARK_STRUCT_UP || out.state == XSPARK_STRUCT_DOWN)
   {
      out.legs_in_state = 1;
      for(int i = 0; i + 2 < out.pivot_count; i++)
      {
         const double change = out.pivots[i].price - out.pivots[i + 2].price;
         if((out.state == XSPARK_STRUCT_UP && change <= 0.0) ||
            (out.state == XSPARK_STRUCT_DOWN && change >= 0.0)) break;
         out.legs_in_state++;
      }
   }
   return true;
}

void XSparkInvalidateStructure(const double base_close, XSparkStructure &s)
{
   if(!s.valid) return;
   if(!MathIsValidNumber(base_close) || base_close <= 0.0)
   { s.valid = false; s.state = XSPARK_STRUCT_UNKNOWN; s.reason = "invalid base close"; return; }
   if((s.state == XSPARK_STRUCT_UP && base_close < s.last_low) ||
      (s.state == XSPARK_STRUCT_DOWN && base_close > s.last_high))
   { s.state = XSPARK_STRUCT_RANGE; s.legs_in_state = 0; s.reason = "invalidated by base close"; }
}

bool XSparkLocateLeg(const XSparkCandle &bars[], const int count,
                     const EXSparkSignalDirection direction, XSparkStructure &s)
{
   s.leg_origin_shift = 0; s.leg_extreme_shift = 0;
   s.leg_origin = 0.0; s.leg_extreme = 0.0; s.leg_range = 0.0; s.retracement = 0.0;
   if(!s.valid || count > ArraySize(bars) || count < 1 ||
      (direction != XSPARK_SIGNAL_BUY && direction != XSPARK_SIGNAL_SELL)) return false;
   const bool buy = direction == XSPARK_SIGNAL_BUY;
   const int origin = buy ? s.last_low_shift : s.last_high_shift;
   if(origin < 2 || origin > count) return false;
   s.leg_origin_shift = origin;
   s.leg_origin = buy ? s.last_low : s.last_high;
   s.leg_extreme = buy ? bars[0].high : bars[0].low;
   s.leg_extreme_shift = 1;
   for(int i = 1; i < origin - 1; i++)
      if((buy && bars[i].high > s.leg_extreme) || (!buy && bars[i].low < s.leg_extreme))
      { s.leg_extreme = buy ? bars[i].high : bars[i].low; s.leg_extreme_shift = i + 1; }
   s.leg_range = buy ? s.leg_extreme - s.leg_origin : s.leg_origin - s.leg_extreme;
   if(s.leg_range <= 0.0) return false;
   s.retracement = (buy ? s.leg_extreme - bars[0].close : bars[0].close - s.leg_extreme) / s.leg_range;
   return MathIsValidNumber(s.retracement);
}

bool XSparkNearestOpposingPivot(const XSparkStructure &s, const EXSparkSignalDirection dir,
                                const double beyond_price, XSparkPivot &out)
{
   bool found = false;
   if(!s.valid || (dir != XSPARK_SIGNAL_BUY && dir != XSPARK_SIGNAL_SELL)) return false;
   for(int i = 0; i < s.pivot_count; i++)
   {
      if(s.pivots[i].broken) continue;
      const bool buy = dir == XSPARK_SIGNAL_BUY;
      if((buy && s.pivots[i].type == XSPARK_PIVOT_HIGH && s.pivots[i].price > beyond_price) ||
         (!buy && s.pivots[i].type == XSPARK_PIVOT_LOW && s.pivots[i].price < beyond_price))
      {
         if(!found || (buy && s.pivots[i].price < out.price) || (!buy && s.pivots[i].price > out.price))
         { out = s.pivots[i]; found = true; }
      }
   }
   return found;
}

string XSparkStructureJournal(const XSparkStructure &s)
{
   return StringFormat("valid=%s state=%s pivots=%d legs=%d HH=%.8f/%.8f LL=%.8f/%.8f scale=%.8f origin=%.8f extreme=%.8f range=%.8f retrace=%.6f origin_shift=%d reason=%s",
                       s.valid ? "true" : "false", XSparkStructureName(s.state), s.pivot_count, s.legs_in_state,
                       s.last_high, s.prev_high, s.last_low, s.prev_low, s.scale,
                       s.leg_origin, s.leg_extreme, s.leg_range, s.retracement, s.leg_origin_shift, s.reason);
}
#endif
