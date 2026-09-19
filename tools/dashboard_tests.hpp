// Test-only fixtures. Production Dashboard.Update issues every captured draw call.
Object& UIObject(const string& suffix){return objects.at(ObjectFind(0,"ScoreBotV3_Dashboard_"+suffix));}
int main(){
 OnStart(); RunDashboardExperienceTests();
 CXSparkLogger logger;
 std::ostringstream log; auto* original=std::cout.rdbuf(log.rdbuf());
 logger.Error("RiskManager","Computed volume is below broker minimum: InpMaxRiskPct=1");
 logger.Warn("RiskManager","The killswitch latches after only 4 consecutive losses");
 logger.Info("EA","MACHINE_RECORD field=42");
 std::cout.rdbuf(original);
 UICheck("logger adds understandable error title",log.str().find("Budget is below the smallest trade")!=string::npos);
 UICheck("logger retains exact technical details",log.str().find("Technical details: Computed volume is below broker minimum: InpMaxRiskPct=1")!=string::npos);
 UICheck("forecast warning does not say emergency stop is active",log.str().find("Emergency stop is active")==string::npos);
 UICheck("informational records remain intact",log.str().find("XSpark [INFO] [EA] MACHINE_RECORD field=42")!=string::npos);
 CXSparkDashboard panel; CXSparkSafetyManager safety;
 XSparkScoreBotReport report{}; XSparkDashboardLive live{};
 live.symbol="XAUUSD";live.timeframe="M15";live.currency="USD";live.entry_style="Chart-pattern entries";
 live.bid=2634.82;live.ask=2635.02;live.digits=2;live.seconds_to_close=512;live.bar_seconds=900;
 live.quote_age=0;live.quote_valid=true;live.positions_valid=true;live.connected=true;live.animate=true;
 live.position_count=2;live.open_profit=38.72;
 live.positions[0]="#192847310  BUY  0.02 lots";live.position_profit[0]=24.50;
 live.positions[1]="#192847526  BUY  0.01 lots";live.position_profit[1]=14.22;
 report.gate_candidate=true;report.candidate_pattern="Bullish engulfing";report.signal_bar_time=1000;
 report.scored=true;report.components.final_score=6.3;report.effective_threshold=4;report.selected_risk_pct=1;
 report.htf_verdict="PASS";report.pullback_verdict="PASS";report.rsi_verdict="OFF";
 auto update=[&](const string& status,const string& reason){panel.Update(report,safety,10248.60,4,7,2,3,2,"TRADING",status,reason,live);};
 for(int i=0;i<24;i++){clock_ms+=1000;live.quote_stamp++;live.bid=2634.05+0.04*i+0.1*std::sin(i);update("MANAGING","Managing existing XSpark positions.");}
 const size_t count=objects.size();
 UICheck("fresh feed is explicitly live",UIObject("feed").strings[OBJPROP_TEXT]=="LIVE PRICES");
 UICheck("all open positions counted",UIObject("detail_positions").strings[OBJPROP_TEXT]=="2/3");
 UICheck("second position has independent profit",UIObject("detail_pnl1").strings[OBJPROP_TEXT]=="+14.22");
 UICheck("tick redraw is throttled",!panel.NeedsRefresh());
 DumpScene("live");
 clock_ms+=1000;update("MANAGING","");
 UICheck("refresh reuses the existing objects",objects.size()==count);
 live.quote_age=99;clock_ms+=1000;update("STALE QUOTE","");
 UICheck("stale feed cannot show live",UIObject("feed").strings[OBJPROP_TEXT]=="FEED PAUSED");
 UICheck("stale feed explains next step",UIObject("notice_title").strings[OBJPROP_TEXT]=="Waiting for fresh prices");
 DumpScene("stale");
 UICheck("unrelated chart clicks ignored",!panel.HandleEvent(CHARTEVENT_OBJECT_CLICK,"another-object"));
 UICheck("collapse requests immediate refresh",panel.HandleEvent(CHARTEVENT_OBJECT_CLICK,"ScoreBotV3_Dashboard_toggle")&&panel.NeedsRefresh());
 update("STALE QUOTE","");
 UICheck("compact hides all detail objects",UIObject("detail_account").integers[OBJPROP_TIMEFRAMES]==OBJ_NO_PERIODS);
 UICheck("compact reduces panel height",UIObject("bg").integers[OBJPROP_YSIZE]==286);
 DumpScene("compact");
 panel.HandleEvent(CHARTEVENT_OBJECT_CLICK,"ScoreBotV3_Dashboard_toggle");update("STALE QUOTE","");
 UICheck("expand restores details without object growth",UIObject("detail_account").integers[OBJPROP_TIMEFRAMES]==OBJ_ALL_PERIODS&&objects.size()==count);
 chart_width=340;chart_height=450;panel.HandleEvent(CHARTEVENT_CHART_CHANGE,"");update("STALE QUOTE","");
 UICheck("small chart automatically compacts",UIObject("bg").integers[OBJPROP_YSIZE]<286);
 DumpScene("small");
 tester=true;visual=false;clock_ms+=1000;
 UICheck("nonvisual tester skips UI work",!panel.NeedsRefresh());
 panel.Deinitialize(false);UICheck("deinitialization removes panel objects",objects.empty());
 Print("UI TOTAL passed=",g_passed+g_ui_passed," failed=",g_failed+g_ui_failed);
 return g_failed+g_ui_failed?1:0;
}
