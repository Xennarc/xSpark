// Test-only fixtures. Production Dashboard.Update issues every captured draw call.
Object& UIObject(const string& suffix){return objects.at(ObjectFind(0,"ScoreBotV3_Dashboard_"+suffix));}
bool IsVisible(Object& o){return !o.integers.count(OBJPROP_TIMEFRAMES)||o.integers[OBJPROP_TIMEFRAMES]!=OBJ_NO_PERIODS;}
struct Bounds {double left,top,right,bottom;string name;};
bool TextFitsPanel(){
 std::vector<Bounds> labels;auto& bg=UIObject("bg");
 const double bx=bg.integers[OBJPROP_XDISTANCE],by=bg.integers[OBJPROP_YDISTANCE];
 const double bw=bg.integers[OBJPROP_XSIZE],bh=bg.integers[OBJPROP_YSIZE];
 for(auto& o:objects){
  if(o.type!=OBJ_LABEL||!IsVisible(o))continue;
  const string value=o.strings[OBJPROP_TEXT];if(value==" "||value.empty())return false;
  uint w=0,h=0;TextSetFont(o.strings[OBJPROP_FONT],-10*int(o.integers[OBJPROP_FONTSIZE]),0);TextGetSize(value,w,h);
  double x=o.integers[OBJPROP_XDISTANCE],y=o.integers[OBJPROP_YDISTANCE];
  if(o.integers[OBJPROP_ANCHOR]==ANCHOR_RIGHT_UPPER)x-=w;
  Bounds b{x,y,x+w,y+h,o.name};
  if(b.left<bx||b.top<by||b.right>bx+bw||b.bottom>by+bh){Print("OUTSIDE: ",o.name);return false;}
  for(auto& a:labels)if(b.left<a.right && b.right>a.left && b.top<a.bottom && b.bottom>a.top){Print("OVERLAP: ",a.name," / ",b.name);return false;}
  labels.push_back(b);
 }
 auto& button=UIObject("toggle");uint w=0,h=0;
 TextSetFont(button.strings[OBJPROP_FONT],-10*int(button.integers[OBJPROP_FONTSIZE]),0);TextGetSize(button.strings[OBJPROP_TEXT],w,h);
 return w<=button.integers[OBJPROP_XSIZE]&&h<=button.integers[OBJPROP_YSIZE];
}
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
 string mode="TRADING";
 auto update=[&](const string& status,const string& reason){panel.Update(report,safety,10248.60,4,7,2,3,2,mode,status,reason,live);};
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
 // Reproduce the supplied Mac/Wine chart: stale price, no setup, no positions.
 XSparkResetScoreBotReport(report);mode="ANALYSIS ONLY";live.position_count=0;
 for(int i=0;i<3;i++){live.positions[i]="";live.position_profit[i]=0;}
 live.symbol="XAUUSDm";live.timeframe="M5";live.bar_seconds=300;live.digits=3;live.bid=4378.062;live.quote_age=10879;
 live.entry_style="Original entries";live.seconds_to_close=0;
 for(int dpi: {96,120,144,192,288}){
  reported_dpi=dpi;actual_dpi=dpi;
  for(int width: {1200,340}){
   chart_width=width;chart_height=800;panel.HandleEvent(CHARTEVENT_CHART_CHANGE,"");update("STALE QUOTE","");
   UICheck(StringFormat("screenshot labels fit without overlap at DPI %d width %d",dpi,width),TextFitsPanel());
   UICheck(StringFormat("unused fields hidden at DPI %d width %d",dpi,width),!IsVisible(UIObject("detail_pnl0"))&&!IsVisible(UIObject("detail_trade1"))&&UIObject("detail_trade1").strings[OBJPROP_TEXT]==" ");
  }
 }
 chart_width=1200;chart_height=800;reported_dpi=96;actual_dpi=192;glyph_scale=1.35;missing_font=true;
 panel.HandleEvent(CHARTEVENT_CHART_CHANGE,"");update("STALE QUOTE","");
 UICheck("measured fonts cope with incorrect DPI and wider fallback glyphs",TextFitsPanel());
 UICheck("missing platform font falls back to Arial",UIObject("brand").strings[OBJPROP_FONT]=="Arial");
 UICheck("wrapped notice retains the complete explanation in tooltip",UIObject("notice_body0").strings[OBJPROP_TOOLTIP].find("The price feed is missing or too old for a new entry.")!=string::npos);
 live.position_count=3;live.positions[0]="#18446744073709551615  BUY  0.001 lots";live.position_profit[0]=-9999999.12;
 live.positions[1]="#18446744073709551614  SELL  1000.00 lots";live.position_profit[1]=10000000.10;
 live.positions[2]="#18446744073709551613  BUY  0.010 lots";live.position_profit[2]=0.0;
 report.gate_candidate=true;report.candidate_pattern="Inverse head and shoulders + Engulfing";
 clock_ms+=1000;update("SCANNING","A very long unrecognized problem WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW");
 UICheck("long patterns, tickets and profits stay in separate columns",TextFitsPanel());
 UICheck("returning values unhide an empty position row",IsVisible(UIObject("detail_trade1"))&&IsVisible(UIObject("detail_pnl0")));
 UICheck("long ticket retains full value in tooltip",UIObject("detail_trade0").strings[OBJPROP_TOOLTIP]==live.positions[0]);
 panel.HandleEvent(CHARTEVENT_OBJECT_CLICK,"ScoreBotV3_Dashboard_toggle");update("STALE QUOTE","");
 panel.HandleEvent(CHARTEVENT_OBJECT_CLICK,"ScoreBotV3_Dashboard_toggle");update("STALE QUOTE","");
 UICheck("collapse and expand preserve text bounds",TextFitsPanel());
 metrics_fail=true;clock_ms+=1000;update("STALE QUOTE","");
 UICheck("unavailable font metrics cannot draw unbounded labels",!IsVisible(UIObject("notice_title")));
 metrics_fail=false;missing_font=false;glyph_scale=1;reported_dpi=192;actual_dpi=192;
 live.position_count=0;live.open_profit=0;XSparkResetScoreBotReport(report);
 clock_ms+=1000;update("STALE QUOTE","");DumpScene("screenshot_fixed_192");
 UICheck("zero positions hide stale snapshot rows",!IsVisible(UIObject("detail_trade1"))&&!IsVisible(UIObject("detail_trade2")));
 UICheck("font measurement recovers on the next refresh",IsVisible(UIObject("notice_title"))&&TextFitsPanel());
 ObjectCreate(0,"ScoreBotV3_Dashboard_obsolete",OBJ_LABEL,0,0,0);
 ObjectCreate(0,"ScoreBotV3_Trade_preserve",OBJ_HLINE,0,0,0);
 ObjectCreate(0,"OtherIndicator_preserve",OBJ_LABEL,0,0,0);
 ObjectCreate(0,"ScoreBotV3_Dashboard_pattern_boundary",OBJ_HLINE,0,0,0);
 panel.Initialize();
 UICheck("initialization removes stale panel objects only",ObjectFind(0,"ScoreBotV3_Dashboard_obsolete")<0&&ObjectFind(0,"ScoreBotV3_Trade_preserve")>=0&&ObjectFind(0,"OtherIndicator_preserve")>=0&&ObjectFind(0,"ScoreBotV3_Dashboard_pattern_boundary")>=0);
 ObjectDelete(0,"ScoreBotV3_Trade_preserve");ObjectDelete(0,"OtherIndicator_preserve");
 tester=true;visual=false;clock_ms+=1000;
 UICheck("nonvisual tester skips UI work",!panel.NeedsRefresh());
 panel.Deinitialize(false);UICheck("deinitialization removes panel objects",objects.empty());
 Print("UI TOTAL passed=",g_passed+g_ui_passed," failed=",g_failed+g_ui_failed);
 return g_failed+g_ui_failed?1:0;
}
