#property script_show_inputs
#include <XSpark/Strategy/ChartPatterns.mqh>
int g_pattern_passed = 0, g_pattern_failed = 0;
void PatternCheck(const string name, const bool ok)
{
   if(ok) { g_pattern_passed++; Print("PASS: ",name); }
   else { g_pattern_failed++; Print("FAIL: ",name); }
}
void CPBar(XSparkCandle &b, const int i, const double o, const double h, const double l, const double c)
{ b.time = (datetime)(3000000-i*60); b.open=o; b.high=h; b.low=l; b.close=c; b.tick_volume=100; }
void CPFlat(XSparkCandle &b[], const int n, const double p)
{ ArrayResize(b,n); for(int i=0;i<n;i++) CPBar(b[i],i,p,p+0.1,p-0.1,p); }
void CPMirror(XSparkCandle &b[])
{
   for(int i=0;i<ArraySize(b);i++)
   { double high=b[i].high; b[i].high=220-b[i].low; b[i].low=220-high; b[i].open=220-b[i].open; b[i].close=220-b[i].close; }
}
void CPFlag(XSparkCandle &b[])
{
   CPFlat(b,32,101);
   for(int i=5;i<=8;i++) { double c=110-i; CPBar(b[i],i,c-1,c+0.2,c-1.1,c); }
   CPBar(b[4],4,104.8,105,104.2,104.5);
   CPBar(b[3],3,104.5,104.8,104,104.3);
   CPBar(b[2],2,104.3,104.6,103.9,104.0);
   CPBar(b[1],1,104.5,104.6,103.9,104.2);
   CPBar(b[0],0,104.2,105.3,104.1,105.15);
}
void CPCup(XSparkCandle &b[], const bool sharp_v)
{
   CPFlat(b,90,108);
   for(int i=5;i<=45;i++)
   {
      double x=(double)(i-25)/20.0;
      double c=106+4*(sharp_v ? MathAbs(x) : x*x);
      CPBar(b[i],i,c-0.03,c+0.05,c-0.05,c);
   }
   CPBar(b[4],4,109.8,109.9,109.3,109.6);
   CPBar(b[3],3,109.6,109.7,108.9,109.1);
   CPBar(b[2],2,109.1,109.3,108.8,109.0);
   CPBar(b[1],1,109.1,109.3,108.8,108.9);
   CPBar(b[0],0,108.9,110.35,108.8,110.25);
}
void CPHeadShoulders(XSparkCandle &b[], XSparkStructure &s)
{
   CPFlat(b,50,102);
   XSparkResetStructure(s); s.valid=true; s.pivot_count=5;
   int shifts[5]={5,11,17,23,29};
   double prices[5]={100.2,104,98,104,100};
   for(int i=0;i<5;i++)
   {
      s.pivots[i].type = i%2==0 ? XSPARK_PIVOT_LOW : XSPARK_PIVOT_HIGH;
      s.pivots[i].shift=shifts[i]; s.pivots[i].price=prices[i];
      s.pivots[i].time=b[shifts[i]-1].time; s.pivots[i].broken=false;
   }
   CPBar(b[1],1,103.7,103.9,103.3,103.5);
   CPBar(b[0],0,103.5,104.3,103.4,104.2);
}
void RunChartPatternTests()
{
   XSparkCandle bars[]; XSparkPatternResult p;
   CPFlat(bars,3,100);
   CPBar(bars[1],1,101,101.1,100.1,100.2);
   CPBar(bars[0],0,100.2,101.4,100.1,101.3);
   PatternCheck("equal-open bullish engulfing qualifies",XSparkStrongEngulfing(bars[0],bars[1],1,p) && p.direction==XSPARK_SIGNAL_BUY);
   CPMirror(bars);
   PatternCheck("equal-open bearish engulfing qualifies",XSparkStrongEngulfing(bars[0],bars[1],1,p) && p.direction==XSPARK_SIGNAL_SELL);
   CPBar(bars[1],1,101,101.1,100.9,100.95);
   CPBar(bars[0],0,100.95,102,100.9,101.9);
   PatternCheck("doji engulf rejected",!XSparkStrongEngulfing(bars[0],bars[1],1,p));
   CPFlag(bars);
   PatternCheck("bull flag detected",XSparkDetectFlag(bars,32,XSPARK_SIGNAL_BUY,1,0.5,p));
   PatternCheck("flag engulfing confluence retained",p.chart_pattern && p.engulfing_confirmed && p.score==2 && p.instance_time==bars[5].time);
   CPMirror(bars);
   PatternCheck("bear flag mirrored",XSparkDetectFlag(bars,32,XSPARK_SIGNAL_SELL,1,0.5,p));
   CPFlag(bars); bars[0].close=104.9;
   PatternCheck("unbroken flag refused",!XSparkDetectFlag(bars,32,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPFlag(bars); bars[0].close=106.2; bars[0].high=106.3;
   PatternCheck("extended flag refused",!XSparkDetectFlag(bars,32,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPFlat(bars,32,101);
   PatternCheck("flat noise is not flag",!XSparkDetectFlag(bars,32,XSPARK_SIGNAL_BUY,1,0.5,p));

   XSparkStructure s;
   CPHeadShoulders(bars,s);
   PatternCheck("inverse HS neckline break",XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_BUY,1,0.5,p));
   PatternCheck("HS uses completing shoulder instance",p.instance_time==s.pivots[0].time && p.breakout_level==104);
   CPMirror(bars);
   for(int i=0;i<s.pivot_count;i++)
   { s.pivots[i].price=220-s.pivots[i].price; s.pivots[i].type=i%2==0 ? XSPARK_PIVOT_HIGH : XSPARK_PIVOT_LOW; }
   PatternCheck("ordinary HS mirrored",XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_SELL,1,0.5,p));
   CPHeadShoulders(bars,s); s.pivots[0].price=101.5;
   PatternCheck("unequal shoulders refused",!XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPHeadShoulders(bars,s); s.pivots[2].price=100.1;
   PatternCheck("head without prominence refused",!XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPHeadShoulders(bars,s); bars[2].close=104.2; bars[2].high=104.3;
   PatternCheck("old neckline break refused",!XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_BUY,1,0.5,p));

   CPCup(bars,false);
   PatternCheck("rounded cup handle breakout",XSparkDetectCupHandle(bars,90,XSPARK_SIGNAL_BUY,1,0.5,p));
   PatternCheck("cup keeps breakout boundary",p.breakout_level>110 && p.chart_pattern);
   CPMirror(bars);
   PatternCheck("inverse cup mirrored",XSparkDetectCupHandle(bars,90,XSPARK_SIGNAL_SELL,1,0.5,p));
   CPCup(bars,true);
   PatternCheck("sharp V rejected as cup",!XSparkDetectCupHandle(bars,90,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPCup(bars,false); bars[1].low=106.5;
   PatternCheck("deep handle rejected",!XSparkDetectCupHandle(bars,90,XSPARK_SIGNAL_BUY,1,0.5,p));
   CPCup(bars,false); bars[0].close=110;
   PatternCheck("cup without breakout rejected",!XSparkDetectCupHandle(bars,90,XSPARK_SIGNAL_BUY,1,0.5,p));

   XSparkPatternResult items[]; ArrayResize(items,2);
   XSparkResetPatternResult(items[0]); XSparkResetPatternResult(items[1]);
   items[0].found=true; items[0].direction=XSPARK_SIGNAL_BUY; items[0].score=1;
   items[0].pattern_id=XSPARK_PATTERN_BULLISH_PIN;
   items[1].found=true; items[1].direction=XSPARK_SIGNAL_BUY; items[1].score=2; items[1].engulfing_confirmed=true;
   items[1].pattern_id=XSPARK_PATTERN_BULLISH_ENGULFING;
   XSparkPatternResult runner; string reason;
   PatternCheck("engulfing outranks pin",XSparkSelectPattern(items,XSPARK_SIGNAL_BUY,p,runner,reason) && p.pattern_id==XSPARK_PATTERN_BULLISH_ENGULFING);
   items[0].score=2; items[0].direction=XSPARK_SIGNAL_SELL;
   PatternCheck("unresolved conflict blocks",!XSparkSelectPattern(items,XSPARK_SIGNAL_NONE,p,runner,reason) && reason=="PATTERN CONFLICT");
   PatternCheck("HTF removes opposite candidate",XSparkSelectPattern(items,XSPARK_SIGNAL_BUY,p,runner,reason) && p.direction==XSPARK_SIGNAL_BUY);
   PatternCheck("buy entry chase bounded",!XSparkEntryLimitAllows(XSPARK_SIGNAL_BUY,110.6,110.5));
   PatternCheck("sell entry chase bounded",!XSparkEntryLimitAllows(XSPARK_SIGNAL_SELL,99.4,99.5));
   PatternCheck("legacy zero limit unchanged",XSparkEntryLimitAllows(XSPARK_SIGNAL_BUY,110.6,0));
   PatternCheck("failed buy breakout refuses quote",!XSparkEntryLimitAllows(XSPARK_SIGNAL_BUY,104.9,105.5,105.0));
   PatternCheck("failed sell breakout refuses quote",!XSparkEntryLimitAllows(XSPARK_SIGNAL_SELL,105.1,104.5,105.0));
   PatternCheck("intact breakout within band passes",XSparkEntryLimitAllows(XSPARK_SIGNAL_BUY,105.2,105.5,105.0));
   XSparkPatternConfig cfg; XSparkDefaultPatternConfig(cfg);
   PatternCheck("pattern defaults valid",XSparkValidatePatternConfig(cfg,false,false,false,reason));
   cfg.enabled=true;
   PatternCheck("pattern dependencies required",!XSparkValidatePatternConfig(cfg,true,false,true,reason));
   PatternCheck("pattern dependencies accepted",XSparkValidatePatternConfig(cfg,true,true,true,reason));
   cfg.max_chase_atr=0.05;
   PatternCheck("empty breakout band rejected",!XSparkValidatePatternConfig(cfg,true,true,true,reason));
   XSparkDefaultPatternConfig(cfg);
   CPFlat(bars,32,100); CPBar(bars[0],0,100,100.3,98.5,100.2);
   XSparkBuildStructure(bars,32,0.5,s);
   PatternCheck("pin absent by default",XSparkScanPatterns(bars,32,s,1,cfg,items)==0);
   cfg.pin_bars=true;
   PatternCheck("optional pin has reduced weight",XSparkScanPatterns(bars,32,s,1,cfg,items)==1 && items[0].score==1);
   CPFlag(bars); XSparkBuildStructure(bars,32,0.5,s);
   cfg.flags=false; cfg.pin_bars=false;
   PatternCheck("flag switch retains standalone engulfing",XSparkScanPatterns(bars,32,s,1,cfg,items)==1 && !items[0].chart_pattern && items[0].engulfing_confirmed);
   // Construct raw candles and let production pivot detection discover the shape.
   CPFlat(bars,50,105);
   int knots[7]={0,4,10,16,22,28,34};
   double mids[7]={104.2,100.3,103.9,98.1,103.9,100.1,105};
   for(int segment=0;segment<6;segment++)
      for(int k=knots[segment];k<=knots[segment+1];k++)
      {
         double mid=mids[segment]+(mids[segment+1]-mids[segment])*(k-knots[segment])/(knots[segment+1]-knots[segment]);
         CPBar(bars[k],k,mid,mid+0.1,mid-0.1,mid);
      }
   CPBar(bars[1],1,103.7,103.9,103.3,103.5);
   CPBar(bars[0],0,103.5,104.3,103.4,104.2);
   XSparkBuildStructure(bars,50,0.5,s);
   PatternCheck("HS discovered from raw confirmed pivots",XSparkDetectHeadShoulders(bars,50,s,XSPARK_SIGNAL_BUY,1,0.5,p));
   Print("CHART RESULT passed=",g_pattern_passed," failed=",g_pattern_failed);
}
#ifndef XSPARK_PORTABLE_TEST
void OnStart() { RunChartPatternTests(); }
#endif
