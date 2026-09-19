#property script_show_inputs
#include <XSpark/UI/DashboardLayout.mqh>
int g_ui_passed=0,g_ui_failed=0;
void UICheck(const string name,const bool ok)
{if(ok){g_ui_passed++;Print("PASS: ",name);}else{g_ui_failed++;Print("FAIL: ",name);}}
void RunDashboardExperienceTests()
{
 XSparkNotice n;
 XSparkExplain("V2 CONFIG BLOCKED","invalid switch combination",n);
 UICheck("config error explains next step",n.severity==4 && StringFind(n.action,"Entry style")>=0);
 XSparkExplain("KILLSWITCH","",n);
 UICheck("emergency stop is a fault",n.severity==4 && n.title=="Emergency stop is active");
 XSparkExplain("","The killswitch latches after only 4 consecutive losses",n);
 UICheck("risk warning does not claim stop already triggered",n.title!="Emergency stop is active");
 XSparkExplain("SCANNING","Computed volume is below broker minimum",n);
 UICheck("minimum-lot error explains budget",n.title=="Budget is below the smallest trade" && StringFind(n.action,"raise risk")<0);
 XSparkExplain("STALE QUOTE","",n);UICheck("stale quote never shows healthy",n.severity==3);
 XSparkExplain("HTF RANGE","",n);UICheck("sideways market is a wait not system failure",n.severity==2);
 XSparkExplain("SCANNING","NO PATTERN",n);UICheck("no pattern is normal scanning",n.severity==0);
 XSparkExplain("MANAGING","Managing existing XSpark positions.",n);UICheck("management is active",n.severity==1);
 XSparkExplain("UNRECOGNIZED","new failure",n);UICheck("unknown error fails visibly",n.severity==4 && n.detail=="new failure");
 XSparkExplain("SCANNING","Free margin 20 is below required buffered margin 50",n);UICheck("margin error has practical guidance",StringFind(n.action,"margin buffer")>=0);
 XSparkExplain("TRADING DISABLED","",n);UICheck("watch mode distinguishes analysis from orders",StringFind(n.detail,"New orders are disabled")>=0);
 UICheck("raw input names translate only for display",StringFind(XSparkReadableInputs("InpMaxOpenTrades must be 1-10"),"InpMaxOpenTrades")<0);
 UICheck("countdown uses actual candle elapsed time",XSparkDashboardSecondsLeft(1060,1000,900)==840);
 UICheck("expired candle does not restart countdown",XSparkDashboardSecondsLeft(2000,1000,900)==0);
 UICheck("missing candle is not fabricated",XSparkDashboardSecondsLeft(1000,0,900)==-1);
 UICheck("future candle rejected",XSparkDashboardSecondsLeft(999,1000,900)==-1);
 UICheck("wrap preserves word boundaries",XSparkDashboardLine("First second third",0,12)=="First second" && XSparkDashboardLine("First second third",1,12)=="third");
 UICheck("missing wrap rows are empty",XSparkDashboardLine("short",4,12)=="");
 UICheck("gate labels are readable",XSparkDashboardGate("PASS")=="Ready" && XSparkDashboardGate("OFF")=="Off" && XSparkDashboardGate("HTF RANGE")=="Waiting");
 XSparkExplain("", "XSpark requires a hedging account; netting merges positions", n);
 UICheck("hedging requirement is clear", n.title=="Use a hedging account" && n.severity==4);
 XSparkExplain("", "Weekend close time is invalid.", n);
 UICheck("invalid weekend setting is not normal outside-hours wait", n.severity==4);
 XSparkExplain("", "State recovery resolved; managed state matches broker state.", n);
 UICheck("resolved recovery does not remain an alarm", n.severity==0);
 XSparkExplain("SCANNING", "Entry confirmed but the broker position closed before state registration.", n);
 UICheck("already closed position is not reported as managing", n.title=="The filled trade has already closed");
 UICheck("long explanations visibly mark truncation", XSparkDashboardLine("First second third fourth fifth",1,12,true)=="third fou...");
 XSparkExplain("", "RSI input ranges are invalid.", n);
 UICheck("momentum range error explains its bounds", StringFind(n.detail,"0 and 100")>=0 && n.severity==4);
 XSparkExplain("", "Production-control inputs are invalid.", n);
 UICheck("invalid controls identify the settings", n.title=="Check spread and account limits");
 Print("DASHBOARD RESULT passed=",g_ui_passed," failed=",g_ui_failed);
}
#ifndef XSPARK_PORTABLE_TEST
void OnStart(){RunDashboardExperienceTests();}
#endif
