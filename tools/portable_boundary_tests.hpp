// Actual production strategy/StateStore with only MT5 APIs doubled.
void TestBoundaries()
{
 CXSparkStateStore store;
 store.Initialize(1,"TEST",999);
 string reason;
 Check("missing latch blocks historic setup", !store.ReserveNewer("leg",100,200,reason));
 Check("bootstrap timestamp persisted", store.Get("leg")==200);
 Check("new origin reserved", store.ReserveNewer("leg",250,300,reason));
 CXSparkStateStore restarted; restarted.Initialize(1,"TEST",999);
 Check("restart rejects same instance", !restarted.ReserveNewer("leg",250,310,reason));
 Check("restart rejects old instance", !restarted.ReserveNewer("leg",240,310,reason));
 fail_write=true;
 Check("failed bootstrap blocks", !store.ReserveNewer("new-key",100,200,reason));
 Check("failed reservation blocks", !store.ReserveNewer("leg",400,410,reason));
 Check("failed reservation preserves latch", store.Get("leg")==250);
 fail_write=false; fail_read=true;
 Check("unreadable latch blocks", !store.ReserveNewer("leg",400,410,reason));
 fail_read=false; fail_cas=true;
 Check("concurrent change blocks", !store.ReserveNewer("leg",400,410,reason));
 fail_cas=false;
 Check("future instance blocks", !store.ReserveNewer("leg",500,450,reason));
 Check("separate direction bootstraps independently", !store.ReserveNewer("sell",400,410,reason));
 Check("single risk tolerance unchanged", XSparkConsecutiveLossesToDrawdown(3.5,25)==9);
 Check("double risk tolerance reflects correlation", XSparkConsecutiveLossesToDrawdown(3.5,25,2)==4);
 Check("two default tiers have no headroom", !XSparkConcurrencyHasHeadroom(2,3,3,3,3.5,6));
 Check("two lower tiers have headroom", XSparkConcurrencyHasHeadroom(2,2,2,2,3.5,6));
 Check("single slot unaffected", XSparkConcurrencyHasHeadroom(1,3,3,3,3.5,6));

 CXSparkIndicatorCache cache; Flat(cache.base,50);
 cache.base[0].open=100; cache.base[0].high=101; cache.base[0].low=98.7; cache.base[0].close=100.2;
 CXSparkMarketState market;
 CXSparkScoreBotV3 strategy; strategy.Initialize("TEST");
 XSparkSignal baseline, observed, enforced; XSparkScoreBotReport br, ob, er;
 const bool baseline_eligible=strategy.Evaluate(cache,market,baseline,br);
 Check("legacy baseline eligible", baseline_eligible);
 XSparkGateConfig config; XSparkDefaultGateConfig(config);
 config.use_htf=true; config.use_pullback=true; config.use_continuation=true;
 config.use_rsi=true; strategy.ConfigureGates(config);
 const bool observed_eligible=strategy.Evaluate(cache,market,observed,ob);
 Check("observe eligibility identical", observed_eligible==baseline_eligible);
 Check("observe pattern direction score identical", observed.direction==baseline.direction && observed.pattern_id==baseline.pattern_id && observed.score==baseline.score);
 Check("observe protections and risk inputs identical", observed.desired_stop==baseline.desired_stop && observed.desired_target==baseline.desired_target && observed.dynamic_rr==baseline.dynamic_rr && observed.atr14==baseline.atr14);
 Check("observe never supplies reservation", observed.instance_time==0);
 Check("observe reports unavailable structure", ob.joint_verdict=="HTF STRUCTURE UNKNOWN");
 config.observe_only=false; strategy.ConfigureGates(config);
 Check("enforcement refuses missing structure", !strategy.Evaluate(cache,market,enforced,er));
 Check("rejected geometry retained", er.context.bar1_low==98.7 && er.has_pattern);
 XSparkDefaultGateConfig(config); config.use_rsi=true; config.observe_only=false;
 strategy.ConfigureGates(config); cache.rsi=90;
 Check("RSI gate can actually veto high score", !strategy.Evaluate(cache,market,enforced,er) && er.rsi_verdict=="RSI INNER HIGH");
 config.observe_only=true; strategy.ConfigureGates(config);
 Check("RSI observation leaves baseline trade eligible", strategy.Evaluate(cache,market,observed,ob));
 // Exercise the complete new-entry path on a bar with NO legacy pattern.
 Staircase(cache.structure_base,false);
 cache.structure_base.resize(160);
 for(int i=40;i<160;i++) Bar(cache.structure_base[i],i,100);
 Staircase(cache.structure_higher,false);
 cache.structure_higher.resize(80);
 for(int i=40;i<80;i++) Bar(cache.structure_higher[i],i,100);
 auto& b=cache.structure_base;
 b[0].open=107.0; b[0].close=107.4; b[0].high=107.6; b[0].low=106.9;
 b[1].open=107.1; b[1].close=107.0; b[1].high=107.4; b[1].low=106.8;
 b[2].open=107.5; b[2].close=107.1; b[2].high=107.7; b[2].low=106.9;
 b[3].open=108.0; b[3].close=107.5; b[3].high=108.2; b[3].low=107.3;
 b[4].open=108.0; b[4].close=108.0; b[4].high=108.2; b[4].low=107.8;
 cache.base.assign(b.begin(),b.begin()+50);
 cache.rsi=45; cache.previous=44; cache.structure_ready=true;
 XSparkDefaultGateConfig(config);
 config.use_htf=true; config.use_pullback=true; config.use_continuation=true;
 strategy.ConfigureGates(config);
 Check("observe does not execute additive candidate", !strategy.Evaluate(cache,market,observed,ob));
 Check("observe finds additive momentum turn", ob.gate_candidate && ob.joint_verdict=="PASS" && ob.candidate_pattern=="Momentum Turn");
 config.observe_only=false; strategy.ConfigureGates(config);
 Check("enforced path emits additive signal", strategy.Evaluate(cache,market,enforced,er));
 Check("continuation has origin identity", enforced.instance_time>0 && enforced.instance_time<enforced.signal_bar_time);
 Check("continuation stays inside score ceiling", enforced.score<=9 && enforced.pattern_score==1.0);
 cache.structure_base[0].time-=60;
 Check("inconsistent snapshot refuses", !strategy.Evaluate(cache,market,enforced,er) && er.joint_verdict=="HTF STRUCTURE UNKNOWN");

 // Full strategy path: chart consolidation replaces the pivot pullback location.
 CPFlag(cache.structure_base);
 cache.structure_base.resize(160);
 for(int i=32;i<160;i++) CPBar(cache.structure_base[i],i,101,101.1,100.9,101);
 cache.base.assign(cache.structure_base.begin(),cache.structure_base.begin()+50);
 Staircase(cache.structure_higher,false);
 cache.structure_higher.resize(80);
 for(int i=40;i<80;i++) Bar(cache.structure_higher[i],i,101);
 for(auto& h:cache.structure_higher) {h.open-=5; h.high-=5; h.low-=5; h.close-=5;}
 XSparkPatternConfig patterns; XSparkDefaultPatternConfig(patterns);
 patterns.enabled=true; strategy.ConfigurePatterns(patterns);
 Check("chart breakout reaches eligible strategy signal",strategy.Evaluate(cache,market,enforced,er));
 Check("chart candidate selected with own location",enforced.pattern_id==XSPARK_PATTERN_BULL_FLAG && er.entry_location=="CONFIRMED CHART BREAKOUT");
 Check("chart identity and quote bounds supplied",enforced.instance_family==XSPARK_PATTERN_BULL_FLAG && enforced.instance_time==cache.base[5].time && enforced.entry_breakout_level==105 && enforced.entry_limit==105.5);
 Check("pattern active mode visible",er.pattern_mode=="PATTERN ENTRIES ACTIVE");
 config.observe_only=true; strategy.ConfigureGates(config);
 const bool pattern_observed=strategy.Evaluate(cache,market,observed,ob);
 patterns.enabled=false; strategy.ConfigurePatterns(patterns);
 const bool pattern_baseline=strategy.Evaluate(cache,market,baseline,br);
 Check("pattern observation preserves legacy outcome",pattern_observed==pattern_baseline && observed.pattern_id==baseline.pattern_id && observed.score==baseline.score && observed.desired_stop==baseline.desired_stop);
 Check("pattern observation cannot reserve or bound legacy",observed.instance_time==0 && observed.instance_family==0 && observed.entry_limit==0 && observed.entry_breakout_level==0);
 patterns.enabled=true; strategy.ConfigurePatterns(patterns); config.observe_only=false; strategy.ConfigureGates(config);
 Flat(cache.structure_higher,80);
 Check("unresolved HTF blocks recognized chart",!strategy.Evaluate(cache,market,enforced,er) && er.detected_patterns.find("Bull Flag")!=string::npos && er.joint_verdict=="HTF STRUCTURE UNKNOWN");

}
