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
}
