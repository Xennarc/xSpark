#property script_show_inputs
#include <XSpark/Risk/RiskManager.mqh>
int g_concurrent_passed=0, g_concurrent_failed=0;
void ConcurrentCheck(const string name,const bool ok)
{
   if(ok) {g_concurrent_passed++;Print("PASS: ",name);}
   else {g_concurrent_failed++;Print("FAIL: ",name);}
}
void RunConcurrentRiskTests()
{
   ConcurrentCheck("single slot keeps configured ceiling",XSparkConcurrentRiskCap(1,3.5,6)==3.5);
   ConcurrentCheck("two slots share account budget",MathAbs(XSparkConcurrentRiskCap(2,3.5,6)-2.7)<0.000001);
   ConcurrentCheck("three slots share account budget",MathAbs(XSparkConcurrentRiskCap(3,3.5,6)-1.8)<0.000001);
   ConcurrentCheck("ten slots remain bounded",MathAbs(XSparkConcurrentRiskCap(10,3.5,6)-0.54)<0.000001);
   ConcurrentCheck("invalid slot count refuses",XSparkConcurrentRiskCap(0,3.5,6)==0 && XSparkConcurrentRiskCap(11,3.5,6)==0);
   ConcurrentCheck("invalid account budget refuses",XSparkConcurrentRiskCap(2,3.5,0)==0);
   ConcurrentCheck("unused second slot admits another trade",XSparkPositionSlotAvailable(1,2));
   ConcurrentCheck("third trade refused at two-slot limit",!XSparkPositionSlotAvailable(2,2));
   ConcurrentCheck("unknown position count refuses",!XSparkPositionSlotAvailable(-1,2));
   CXSparkRiskManager risk;
   ConcurrentCheck("two slots initialize with shipped risk values",risk.Initialize(3,3,3,3.5,2,6));
   XSparkSignal signal;XSparkResetSignal(signal);signal.direction=XSPARK_SIGNAL_BUY;signal.score=5.5;signal.effective_threshold=2;
   double pct=0;
   ConcurrentCheck("approved signal uses reduced risk",risk.IsSignalApproved(signal,pct) && MathAbs(pct-2.7)<0.000001);
   ConcurrentCheck("dashboard reports actual reduced risk",risk.SelectedRiskPercentForScore(5.5)==pct);
   risk.Initialize(1,2,3,3.5,2,6);
   ConcurrentCheck("lower selected tier is never raised",risk.SelectedRiskPercentForScore(2)==1 && risk.SelectedRiskPercentForScore(4.5)==2);
   double projected=0;string reason;
   ConcurrentCheck("two budgeted positions fit below account cap",XSparkAccountRiskWithinCap(270,270,10000,6,projected,reason) && MathAbs(projected-5.4)<0.000001);
   ConcurrentCheck("other exposure can still block another position",!XSparkAccountRiskWithinCap(400,270,10000,6,projected,reason));
   ConcurrentCheck("failed reinitialization cannot retain approval",!risk.Initialize(3,3,3,3.5,11,6) && !risk.IsSignalApproved(signal,pct));
   Print("CONCURRENT RESULT passed=",g_concurrent_passed," failed=",g_concurrent_failed);
}
#ifndef XSPARK_PORTABLE_TEST
void OnStart() {RunConcurrentRiskTests();}
#endif
