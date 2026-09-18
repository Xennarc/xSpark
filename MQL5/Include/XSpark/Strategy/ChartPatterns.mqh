#ifndef XSPARK_CHART_PATTERNS_MQH
#define XSPARK_CHART_PATTERNS_MQH
#include <XSpark/Strategy/MarketStructure.mqh>
#include <XSpark/Strategy/PatternDetector.mqh>

// Research definitions, not fitted parameters or profitability claims.
#define XSPARK_ENGULF_PREV_BODY_ATR 0.15
#define XSPARK_ENGULF_BODY_ATR 0.50
#define XSPARK_BREAK_BUFFER_ATR 0.05

struct XSparkPatternConfig
{
   bool enabled, flags, head_shoulders, cups, pin_bars;
   double max_chase_atr;
};
void XSparkDefaultPatternConfig(XSparkPatternConfig &c)
{
   c.enabled = false; // Scan and log, but retain the existing execution path.
   c.flags = true; c.head_shoulders = true; c.cups = true; c.pin_bars = false;
   c.max_chase_atr = 0.50;
}

bool XSparkValidatePatternConfig(const XSparkPatternConfig &c, const bool htf,
                                  const bool pullback, const bool continuation, string &reason)
{
   reason = "";
   if(!MathIsValidNumber(c.max_chase_atr) || c.max_chase_atr <= XSPARK_BREAK_BUFFER_ATR || c.max_chase_atr > 1.0)
   { reason = "Pattern chase must be >0.05 and <=1 ATR."; return false; }
   if(c.enabled && (!htf || !pullback || !continuation))
   { reason = "Pattern profile requires HTF, pullback and continuation switches."; return false; }
   return true;
}

// Use directional prices so all geometric rules have a single mirrored form.
double XSparkPatternHigh(const XSparkCandle &b, const EXSparkSignalDirection d)
{ return d == XSPARK_SIGNAL_BUY ? b.high : -b.low; }
double XSparkPatternLow(const XSparkCandle &b, const EXSparkSignalDirection d)
{ return d == XSPARK_SIGNAL_BUY ? b.low : -b.high; }
double XSparkPatternClose(const XSparkCandle &b, const EXSparkSignalDirection d)
{ return (double)d * b.close; }

bool XSparkStrongEngulfing(const XSparkCandle &b1, const XSparkCandle &b2,
                           const double atr, XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   if(!MathIsValidNumber(atr) || atr <= 0.0) return false;
   const double body1 = MathAbs(b1.close - b1.open), body2 = MathAbs(b2.close - b2.open);
   const double range = b1.high - b1.low;
   if(body2 < XSPARK_ENGULF_PREV_BODY_ATR * atr || body1 < XSPARK_ENGULF_BODY_ATR * atr ||
      body1 <= body2 || range <= 0.0 || range > 3.0 * atr) return false;
   // Equal adjacent open/close is valid: FX candles need not gap to engulf.
   const bool buy = b2.close < b2.open && b1.close > b1.open &&
                    b1.open <= b2.close && b1.close >= b2.open &&
                    (b1.close - b1.low) / range >= 0.65;
   const bool sell = b2.close > b2.open && b1.close < b1.open &&
                     b1.open >= b2.close && b1.close <= b2.open &&
                     (b1.high - b1.close) / range >= 0.65;
   if(!buy && !sell) return false;
   out.found = true; out.direction = buy ? XSPARK_SIGNAL_BUY : XSPARK_SIGNAL_SELL;
   out.pattern_id = buy ? XSPARK_PATTERN_BULLISH_ENGULFING : XSPARK_PATTERN_BEARISH_ENGULFING;
   out.pattern_name = XSparkPatternNameFromId(out.pattern_id);
   out.score = 2.0; out.engulfing_confirmed = true; out.instance_time = b1.time;
   return true;
}

bool XSparkPatternBreak(const XSparkCandle &b1, const XSparkCandle &b2,
                        const EXSparkSignalDirection dir, const double level,
                        const double previous_level, const double atr, const double max_chase)
{
   const double close = XSparkPatternClose(b1, dir);
   return MathIsValidNumber(level) && MathIsValidNumber(previous_level) && atr > 0.0 &&
          close > level + XSPARK_BREAK_BUFFER_ATR * atr &&
          close - level <= max_chase * atr &&
          XSparkPatternClose(b2, dir) <= previous_level &&
          close > (double)dir * b1.open;
}
void XSparkSetChartPattern(const XSparkCandle &b1, const XSparkCandle &b2,
                           const EXSparkSignalDirection dir, const EXSparkScoreBotPatternId id,
                           const datetime instance, const double oriented_level, const double atr,
                           XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   out.found = true; out.chart_pattern = true; out.direction = dir; out.pattern_id = id;
   out.pattern_name = XSparkPatternNameFromId(id); out.instance_time = instance;
   out.breakout_level = (double)dir * oriented_level;
   XSparkPatternResult engulf;
   out.engulfing_confirmed = XSparkStrongEngulfing(b1, b2, atr, engulf) && engulf.direction == dir;
   out.score = out.engulfing_confirmed ? 2.0 : 1.5;
}

// Impulse -> compact counter-drift -> first closed breakout. No pivot dependency.
bool XSparkDetectFlag(const XSparkCandle &bars[], const int count,
                       const EXSparkSignalDirection dir, const double atr,
                       const double max_chase, XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   if(count > ArraySize(bars) || count < 10 || atr <= 0.0) return false;
   for(int flag = 3; flag <= 10; flag++)
   {
      if(flag + 9 >= count) break;
      const int peak = flag + 1;
      double high = XSparkPatternHigh(bars[1], dir), low = XSparkPatternLow(bars[1], dir);
      for(int i = 2; i <= flag; i++)
      { high = MathMax(high, XSparkPatternHigh(bars[i], dir)); low = MathMin(low, XSparkPatternLow(bars[i], dir)); }
      if(!XSparkPatternBreak(bars[0], bars[1], dir, high, high, atr, max_chase)) continue;
      if(XSparkPatternClose(bars[1], dir) > XSparkPatternClose(bars[flag], dir) + 0.15 * atr) continue;
      const double tip = XSparkPatternHigh(bars[peak], dir);
      if(high > tip + 0.15 * atr) continue;
      for(int pole = 3; pole <= 8; pole++)
      {
         const int start = peak + pole;
         if(start >= count) break;
         const double impulse = XSparkPatternClose(bars[peak], dir) - XSparkPatternClose(bars[start], dir);
         double bodies = 0.0, ranges = 0.0;
         bool tip_is_extreme = true;
         for(int i = peak; i < start; i++)
         {
            bodies += MathAbs(bars[i].close - bars[i].open); ranges += bars[i].high - bars[i].low;
            if(XSparkPatternHigh(bars[i], dir) > tip) tip_is_extreme = false;
         }
         const double retrace = tip - low;
         if(!tip_is_extreme || impulse < 1.5 * atr || ranges <= 0.0 || bodies / ranges < 0.50 ||
            high - low > 0.50 * impulse || retrace < 0.10 * impulse || retrace > 0.50 * impulse) continue;
         XSparkSetChartPattern(bars[0], bars[1], dir,
                               dir == XSPARK_SIGNAL_BUY ? XSPARK_PATTERN_BULL_FLAG : XSPARK_PATTERN_BEAR_FLAG,
                               bars[peak].time, high, atr, out);
         return true;
      }
   }
   return false;
}

double XSparkNeckline(const XSparkPivot &older, const XSparkPivot &newer,
                      const int shift, const EXSparkSignalDirection dir)
{
   if(older.shift <= newer.shift) return EMPTY_VALUE;
   const double weight = (double)(older.shift - shift) / (older.shift - newer.shift);
   return (double)dir * (older.price + weight * (newer.price - older.price));
}

// Newest five alternating confirmed pivots: shoulder, neck, head, neck, shoulder.
bool XSparkDetectHeadShoulders(const XSparkCandle &bars[], const int count,
                               const XSparkStructure &s, const EXSparkSignalDirection dir,
                               const double atr, const double max_chase, XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   if(!s.valid || s.pivot_count < 5 || count > ArraySize(bars) || count < 3 || atr <= 0.0) return false;
   const EXSparkPivotType shoulder = dir == XSPARK_SIGNAL_BUY ? XSPARK_PIVOT_LOW : XSPARK_PIVOT_HIGH;
   for(int i = 0; i < 5; i++)
      if(s.pivots[i].type != (i % 2 == 0 ? shoulder : (shoulder == XSPARK_PIVOT_LOW ? XSPARK_PIVOT_HIGH : XSPARK_PIVOT_LOW))) return false;
   const XSparkPivot right = s.pivots[0], head = s.pivots[2], left = s.pivots[4];
   const int span = left.shift - right.shift;
   if(span < 12 || span > 60 || right.shift < 3 || left.shift + 4 > count) return false;
   const double r = (double)dir * right.price, h = (double)dir * head.price, l = (double)dir * left.price;
   const double nr = (double)dir * s.pivots[1].price, nl = (double)dir * s.pivots[3].price;
   const double height = MathMin(nr, nl) - h;
   if(height < 1.0 * atr || MathMin(r,l) - h < 0.5 * atr || MathAbs(r-l) > 0.5 * atr ||
      MathAbs(nr-nl) > 0.30 * height || r >= nr || l >= nl) return false;
   const double width_ratio = (double)(left.shift - head.shift) / MathMax(1, head.shift - right.shift);
   if(width_ratio < 0.5 || width_ratio > 2.0) return false;
   // A reversal shape needs an incoming move, not five arbitrary sideways pivots.
   if(XSparkPatternClose(bars[left.shift + 3], dir) < l + 0.5 * atr) return false;
   const double level = XSparkNeckline(s.pivots[3], s.pivots[1], 1, dir);
   const double previous = XSparkNeckline(s.pivots[3], s.pivots[1], 2, dir);
   if(!XSparkPatternBreak(bars[0], bars[1], dir, level, previous, atr, max_chase)) return false;
   for(int i = 1; i < right.shift - 1; i++)
      if(XSparkPatternClose(bars[i], dir) > XSparkNeckline(s.pivots[3], s.pivots[1], i + 1, dir)) return false;
   XSparkSetChartPattern(bars[0], bars[1], dir,
                         dir == XSPARK_SIGNAL_BUY ? XSPARK_PATTERN_INVERSE_HS : XSPARK_PATTERN_HEAD_SHOULDERS,
                         right.time, level, atr, out);
   return true;
}

bool XSparkChartRim(const XSparkCandle &bars[], const int count, const int index,
                    const EXSparkSignalDirection dir)
{
   if(index < 2 || index + 2 >= count) return false;
   const double high = XSparkPatternHigh(bars[index], dir);
   for(int j = 1; j <= 2; j++)
      if(high <= XSparkPatternHigh(bars[index-j],dir) || high < XSparkPatternHigh(bars[index+j],dir)) return false;
   return true;
}

// A rounded cup must spend time near its bottom; a sharp V does not qualify.
bool XSparkDetectCupHandle(const XSparkCandle &bars[], const int count,
                           const EXSparkSignalDirection dir, const double atr,
                           const double max_chase, XSparkPatternResult &out)
{
   XSparkResetPatternResult(out);
   if(count > ArraySize(bars) || count < 30 || atr <= 0.0) return false;
   for(int handle = 3; handle <= 10; handle++)
   {
      const int right = handle + 1;
      if(right + 24 >= count) break;
      if(!XSparkChartRim(bars,count,right,dir)) continue;
      const double right_rim = XSparkPatternHigh(bars[right], dir);
      double handle_high = XSparkPatternHigh(bars[1], dir), handle_low = XSparkPatternLow(bars[1], dir);
      for(int i = 2; i <= handle; i++)
      { handle_high = MathMax(handle_high, XSparkPatternHigh(bars[i], dir)); handle_low = MathMin(handle_low, XSparkPatternLow(bars[i], dir)); }
      if(handle_high > right_rim + 0.15 * atr ||
         XSparkPatternClose(bars[1], dir) > XSparkPatternClose(bars[handle], dir) + 0.15 * atr) continue;
      for(int span = 20; span <= 80 && right + span + 4 < count; span++)
      {
         const int left = right + span;
         if(!XSparkChartRim(bars,count,left,dir)) continue;
         const double left_rim = XSparkPatternHigh(bars[left], dir);
         const double level = MathMax(handle_high, MathMax(left_rim, right_rim));
         if(MathAbs(left_rim - right_rim) > 0.5 * atr ||
            !XSparkPatternBreak(bars[0], bars[1], dir, level, level, atr, max_chase)) continue;
         double bottom = right_rim;
         int bottom_index = right;
         bool over_rim = false;
         for(int i = right + 1; i < left; i++)
         {
            if(XSparkPatternHigh(bars[i], dir) > level + 0.15 * atr) over_rim = true;
            if(XSparkPatternLow(bars[i], dir) < bottom) { bottom = XSparkPatternLow(bars[i], dir); bottom_index = i; }
         }
         const double depth = MathMin(left_rim,right_rim) - bottom;
         const double location = (double)(bottom_index-right) / span;
         const double handle_depth = right_rim - handle_low;
         if(over_rim || depth < 2.0 * atr || location < 0.30 || location > 0.70 ||
            handle_depth < 0.10 * depth || handle_depth > 0.40 * depth ||
            XSparkPatternClose(bars[left + 4], dir) > left_rim - atr) continue;
         int bottom_bars = 0;
         double center_sum = 0.0; int center_count = 0;
         for(int i = right + 1; i < left; i++)
         {
            const double close = XSparkPatternClose(bars[i], dir);
            if(close <= bottom + 0.25 * depth) bottom_bars++;
            const double fraction = (double)(i-right) / span;
            if(fraction >= 0.35 && fraction <= 0.65) { center_sum += close; center_count++; }
         }
         if(bottom_bars < (int)MathCeil(0.35 * span) || center_count == 0 ||
            center_sum / center_count > bottom + 0.35 * depth) continue;
         XSparkSetChartPattern(bars[0], bars[1], dir,
                               dir == XSPARK_SIGNAL_BUY ? XSPARK_PATTERN_CUP_HANDLE : XSPARK_PATTERN_INVERSE_CUP_HANDLE,
                               bars[right].time, level, atr, out);
         return true;
      }
   }
   return false;
}

int XSparkPatternPriority(const XSparkPatternResult &p)
{
   if(p.chart_pattern && p.engulfing_confirmed) return 4;
   if(p.engulfing_confirmed) return 3;
   if(p.chart_pattern) return 2;
   return 1;
}
bool XSparkPatternBetter(const XSparkPatternResult &a, const XSparkPatternResult &b)
{
   if(!b.found) return a.found;
   if(a.score != b.score) return a.score > b.score;
   if(XSparkPatternPriority(a) != XSparkPatternPriority(b)) return XSparkPatternPriority(a) > XSparkPatternPriority(b);
   return (int)a.pattern_id < (int)b.pattern_id; // Stable named-id tie order.
}

int XSparkScanPatterns(const XSparkCandle &bars[], const int count, const XSparkStructure &base,
                       const double atr, const XSparkPatternConfig &cfg, XSparkPatternResult &items[])
{
   ArrayResize(items, 0);
   if(!base.valid || count < 3 || count > ArraySize(bars) || !MathIsValidNumber(atr) || atr <= 0.0) return 0;
   XSparkPatternResult p;
   int n = 0;
   if(XSparkStrongEngulfing(bars[0], bars[1], atr, p)) { ArrayResize(items, ++n); items[n-1] = p; }
   if(cfg.pin_bars)
   {
      XSparkCandle bar = bars[0];
      if(XSparkDetectPinBar(bar, p))
      {
         const double upper = bar.high - MathMax(bar.open,bar.close), lower = MathMin(bar.open,bar.close) - bar.low;
         if((p.direction == XSPARK_SIGNAL_BUY && upper <= 0.65 * lower) ||
            (p.direction == XSPARK_SIGNAL_SELL && lower <= 0.65 * upper))
         { p.score = 1.0; p.instance_time = bar.time; ArrayResize(items, ++n); items[n-1] = p; }
      }
   }
   for(int side = 0; side < 2; side++)
   {
      const EXSparkSignalDirection dir = side == 0 ? XSPARK_SIGNAL_BUY : XSPARK_SIGNAL_SELL;
      if(cfg.flags && XSparkDetectFlag(bars,count,dir,atr,cfg.max_chase_atr,p)) { ArrayResize(items, ++n); items[n-1] = p; }
      if(cfg.head_shoulders && XSparkDetectHeadShoulders(bars,count,base,dir,atr,cfg.max_chase_atr,p)) { ArrayResize(items, ++n); items[n-1] = p; }
      if(cfg.cups && XSparkDetectCupHandle(bars,count,dir,atr,cfg.max_chase_atr,p)) { ArrayResize(items, ++n); items[n-1] = p; }
   }
   return n;
}

// Direction/context first, then rank. Conflicting directions without an HTF
// resolution refuse; no detector changes a candle's direction to fill a quota.
bool XSparkSelectPattern(const XSparkPatternResult &items[], const EXSparkSignalDirection dir,
                          XSparkPatternResult &best, XSparkPatternResult &runner, string &reason)
{
   XSparkResetPatternResult(best); XSparkResetPatternResult(runner); reason = "NO QUALIFIED PATTERN";
   for(int i = 0; i < ArraySize(items); i++)
   {
      if(!items[i].found || (dir != XSPARK_SIGNAL_NONE && items[i].direction != dir)) continue;
      if(XSparkPatternBetter(items[i],best)) { runner = best; best = items[i]; }
      else if(XSparkPatternBetter(items[i],runner)) runner = items[i];
   }
   if(!best.found) return false;
   if(runner.found && best.direction != runner.direction && best.score - runner.score <= 0.15)
   { reason = "PATTERN CONFLICT"; return false; }
   reason = "PASS"; return true;
}
#endif
