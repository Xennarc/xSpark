// Test-only terminal/broker doubles. Methods inserted below are production source.
// This verifies state isolation and loop behaviour, not actual broker execution.
namespace MultiPositionTests {
// TRADE_STATE_SOURCE
struct FakePosition {
 ulong ticket; long id; double entry=100, stop=98, volume=1, tp=110;
 string symbol="TEST"; long magic=999; long type=0;
 datetime open_time=0; // what the broker reports as POSITION_TIME
};
std::vector<FakePosition> live;
std::map<long,XSparkTradeState> saved;
int selected=-1, unreadable=-1;
bool connected=true;
enum {POSITION_IDENTIFIER, POSITION_TIME, POSITION_MAGIC, POSITION_TYPE,
 POSITION_PRICE_OPEN, POSITION_SL, POSITION_VOLUME, POSITION_TP, POSITION_SYMBOL,
 SYMBOL_DIGITS, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_VALUE_LOSS,
 SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_STEP,
 TERMINAL_CONNECTED, POSITION_TYPE_BUY=100, POSITION_TYPE_SELL=101};
// The broker's lot bounds, shared by the fake and by the production
// LegalLadderCloseVolume compiled in below. Gold minimums on a retail account.
double broker_volume_min = 0.01, broker_volume_step = 0.01;
using ENUM_POSITION_TYPE = long;
int PositionsTotal() {return int(live.size());}
ulong PositionGetTicket(int i) {selected=i; return i==unreadable ? 0 : live.at(i).ticket;}
bool PositionSelectByTicket(ulong t) {
 for(int i=0;i<PositionsTotal();i++) if(live[i].ticket==t) {selected=i; return i!=unreadable;}
 selected=-1; return false;
}
long PositionGetInteger(int p) {
 const auto& b=live.at(selected);
 if(p==POSITION_IDENTIFIER) return b.id;
 if(p==POSITION_MAGIC) return b.magic;
 if(p==POSITION_TYPE) return b.type;
 if(p==POSITION_TIME) return b.open_time;
 return 100;
}
double PositionGetDouble(int p) {
 const auto& b=live.at(selected);
 if(p==POSITION_PRICE_OPEN) return b.entry;
 if(p==POSITION_SL) return b.stop;
 if(p==POSITION_VOLUME) return b.volume;
 if(p==POSITION_TP) return b.tp;
 return 0;
}
string PositionGetString(int) {return live.at(selected).symbol;}
long SymbolInfoInteger(const string&,int) {return 2;}
double SymbolInfoDouble(const string&,int p) {
 if(p==SYMBOL_VOLUME_MIN) return broker_volume_min;
 if(p==SYMBOL_VOLUME_STEP) return broker_volume_step;
 return 1;
}
// Only the lot ROUNDING is a double; the legality RULE above it is production
// source. SymbolMath's version additionally normalises to the step's precision,
// which cannot change which side of a bound a value falls on.
double XSparkNormalizeVolumeDown(double v,double step) {
 if(v<=0||step<=0) return 0;
 return std::floor(v/step+0.000000001)*step;
}
long TerminalInfoInteger(int) {return connected;}
string DoubleToString(double v,int) {return std::to_string(v);}
// IDENTITY_SOURCE
// SIZER_SOURCE
// UNOPPOSED_SOURCE
// KILLSWITCH_RESTORE_SOURCE
// RESOLVE_LIMITS_SOURCE
bool XSparkAdjustProtectionLevels(const string&,EXSparkSignalDirection,double,double sl,double tp,bool,
                                  double& out_sl,double& out_tp,string&) {out_sl=sl;out_tp=tp;return true;}
class CXSparkLogger {public:
 void Info(const string&,const string&) {} void Warn(const string&,const string&) {} void Error(const string&,const string&) {} void Critical(const string&,const string&) {}
};
// ACCOUNT_EXPOSURE_SOURCE
XSparkTrailPlan MakeTrailPlan(int mode = XSPARK_TRAIL_ATR_AFTER_PARTIAL) {
 XSparkTrailPlan plan; XSparkResetTrailPlan(plan); plan.mode = mode; return plan;
}
class Manager {
public:
 bool m_initialized=true, m_use_stop_level_validation=true;
 string m_symbol="TEST",m_last_reason,m_flatten_campaign_reason;
 ulong m_magic_number=999;
 int m_managed_position_count=0,m_unmanaged_position_count=0,m_flatten_attempts=0;
 bool m_profit_step_unrecorded=false;
 string m_profit_step_unrecorded_reason;
 std::vector<XSparkTradeState> m_states;
 std::vector<ulong> partial_calls, modify_calls;
 std::vector<double> partial_volumes;
 XSparkTrailPlan m_trail_plan = MakeTrailPlan();
 bool close_first_fully=false;
 bool reject_partials=false;
 // The per-ticket full close the time stop uses. Records every call, answers
 // with a configurable result class, and on DONE removes the position - or
 // halves it when partial_time_closes is set, modelling a partial fill.
 std::vector<ulong> close_calls;
 int close_result=XSPARK_CLOSE_RESULT_DONE;
 bool partial_time_closes=false;
 int ClosePosition(ulong ticket,const string&,CXSparkLogger&) {
  if(!PositionSelectByTicket(ticket)) return XSPARK_CLOSE_RESULT_REJECT;
  close_calls.push_back(ticket);
  if(close_result!=XSPARK_CLOSE_RESULT_DONE) return close_result;
  if(partial_time_closes) live[selected].volume/=2;
  else {live.erase(live.begin()+selected);selected=-1;}
  return XSPARK_CLOSE_RESULT_DONE;
 }
 // Mirrors production: only the persisted fields come back from storage. The
 // ticket and the open time are broker truth and stay as the live position
 // reported them, and every RAM-only field starts fresh. A whole-struct copy
 // here once hid a real defect (ADR-031), and would hide the restart re-arm
 // of the time stop the same way.
 bool LoadPersistedState(XSparkTradeState& s) {
  if(!saved.count(s.identifier)) return false;
  auto ticket=s.ticket; auto open=s.open_time; s=saved.at(s.identifier);
  s.ticket=ticket; s.open_time=open;
  s.time_exit_retry_after=0; s.time_exit_reject_count=0;
  s.profit_retry_after=0; s.profit_reject_count=0;
  s.partial_block_logged=false; s.profit_block_logged=false;
  return true;
 }
 bool PersistStateChecked(XSparkTradeState& s,CXSparkLogger&) {saved[s.identifier]=s;return true;}
 void ClearPersistedState(XSparkTradeState& s) {saved.erase(s.identifier);}
 void RemoveStateAt(int i) {m_states.erase(m_states.begin()+i);}
 void LogClosureIfPossible(XSparkTradeState&,CXSparkLogger&) {}
 int CountMatchingPendingOrders() {return 0;}
 void ResetFlattenCampaign() {m_flatten_campaign_reason="";}
 bool ShouldWeekendClose(datetime,int,int) {return false;}
 void FlattenManagedExposure(const string&,CXSparkLogger&,bool) {}
 void RepairMissingProtection(datetime,CXSparkLogger&) {}
 int VolumeDigits() {return 2;}
 int SymbolDigits() {return 2;}
 // ScoreBot_v3's partial path only. The ladder's own volume rule is production
 // source, spliced in at PRODUCTION_METHODS below.
 double LegalPartialCloseVolume(double initial,double current,double pct) {
  if(initial<=0||current<=0||pct<=0) return 0;
  const double close=std::floor(initial*pct/100/broker_volume_step+1e-9)*broker_volume_step;
  if(close<broker_volume_min-1e-9||close>=current) return 0;
  if(current-close<broker_volume_min-1e-9) return 0;
  return close;
 }
 bool ClosePartial(ulong ticket,double volume,CXSparkLogger&) {
  if(!PositionSelectByTicket(ticket)) return false;
  partial_calls.push_back(ticket);
  partial_volumes.push_back(volume);
  // The broker refusing the close. Recorded as an attempt, but nothing moves.
  if(reject_partials) return false;
  if(close_first_fully && ticket==11) {live.erase(live.begin()+selected);selected=-1;}
  else live[selected].volume-=volume;
  return true;
 }
 bool ModifyPositionStops(ulong ticket,double sl,double tp,const string&,CXSparkLogger&) {
  if(!PositionSelectByTicket(ticket)) return false;
  modify_calls.push_back(ticket);live[selected].stop=sl;live[selected].tp=tp;return true;
 }
// PRODUCTION_METHODS
};
void Seed() {
 live={{11,101},{22,202}}; saved.clear(); selected=-1;unreadable=-1;connected=true;
 for(auto& b:live) {
  b.type=POSITION_TYPE_BUY;
  XSparkTradeState s;XSparkResetTradeState(s);
  s.ticket=b.ticket;s.identifier=b.id;s.direction=XSPARK_SIGNAL_BUY;s.entry=b.entry;
  s.initial_sl=b.stop;s.initial_tp=b.tp;s.initial_lots=1;s.initial_risk_distance=2;
  saved[b.id]=s;
 }
}
// Same two positions on the short side, so the anchor ratchet is proven in both
// directions rather than only the one the long fixture happens to exercise.
void SeedShort() {
 live={{11,101},{22,202}}; saved.clear(); selected=-1;unreadable=-1;connected=true;
 for(auto& b:live) {
  b.type=POSITION_TYPE_SELL; b.stop=102;
  XSparkTradeState s;XSparkResetTradeState(s);
  s.ticket=b.ticket;s.identifier=b.id;s.direction=XSPARK_SIGNAL_SELL;s.entry=b.entry;
  s.initial_sl=b.stop;s.initial_tp=90;s.initial_lots=1;s.initial_risk_distance=2;
  saved[b.id]=s;
 }
}
// The two long positions, opened this many seconds before the stub's server
// clock (47000), for the time stop.
void SeedAged(long age_seconds) {
 Seed();
 for(auto& b:live) b.open_time=TimeTradeServer()-age_seconds;
}
void TimeOnce(Manager& m, double bid, double ask, int max_hold_seconds, datetime flatten_after, double exit_max_spread, CXSparkLogger& logger) {
 XSparkTrailPlan plan = MakeTrailPlan(XSPARK_TRAIL_CANDLE_ANCHOR);
 plan.max_hold_seconds = max_hold_seconds; plan.flatten_after = flatten_after; plan.exit_max_spread = exit_max_spread;
 m.SetTrailPlan(plan);
 m.ManagePositions(bid,ask,1,0,0,0,false,20,0,logger);
}
void TrailOnce(Manager& m, double bid, double ask, double anchor_long, double anchor_short, CXSparkLogger& logger) {
 XSparkTrailPlan plan = MakeTrailPlan(XSPARK_TRAIL_CANDLE_ANCHOR);
 plan.anchor_long = anchor_long; plan.anchor_short = anchor_short;
 m.SetTrailPlan(plan);
 m.ManagePositions(bid,ask,1,0,0,0,false,20,0,logger);
}
void TrailPlanned(Manager& m, double bid, double ask, CXSparkLogger& logger,
                  double anchor_long, double anchor_short,
                  double closed_high, double closed_low, datetime closed_time, double atr,
                  double floor_mult, double trail_mult, double tight_mult,
                  double start_r, double full_r, double be_r, double be_offset) {
 XSparkTrailPlan plan = MakeTrailPlan(XSPARK_TRAIL_CANDLE_ANCHOR);
 plan.anchor_long = anchor_long; plan.anchor_short = anchor_short;
 plan.closed_candle_ready = closed_time > 0;
 plan.closed_high = closed_high; plan.closed_low = closed_low; plan.closed_time = closed_time;
 plan.atr = atr;
 plan.tuning.min_trail_atr_mult = floor_mult;
 plan.tuning.chandelier_atr_mult = trail_mult;
 plan.tuning.chandelier_tight_atr_mult = tight_mult;
 plan.tuning.tighten_start_r = start_r;
 plan.tuning.tighten_full_r = full_r;
 plan.tuning.breakeven_at_r = be_r;
 plan.tuning.breakeven_offset_r = be_offset;
 m.SetTrailPlan(plan);
 m.ManagePositions(bid,ask,1,0,0,0,false,20,0,logger);
}
// Lot arithmetic is a chain of divisions and multiplications by the lot step,
// so an exact comparison here would be testing binary representation rather
// than the rule. A tolerance far below the smallest lot step is the real check.
bool VolumeIs(double actual, double expected) {return std::abs(actual-expected) < 0.000000001;}
bool LadderOnce(Manager& m, double bid, double ask, CXSparkLogger& logger,
                double r1, double pct1, double r2, double pct2,
                double anchor_long = 0, double anchor_short = 0) {
 XSparkTrailPlan plan = MakeTrailPlan(XSPARK_TRAIL_CANDLE_ANCHOR);
 plan.anchor_long = anchor_long; plan.anchor_short = anchor_short;
 plan.ladder.level_r[0] = r1; plan.ladder.level_pct[0] = pct1;
 plan.ladder.level_r[1] = r2; plan.ladder.level_pct[1] = pct2;
 // Returned, never ignored: SetTrailPlan validates the trail and the ladder as
 // ONE object and leaves the PREVIOUS plan in force on refusal, so a fixture
 // that dropped this would silently be exercising an empty ladder and passing.
 const bool accepted = m.SetTrailPlan(plan);
 m.ManagePositions(bid,ask,1,0,0,0,false,20,0,logger);
 return accepted;
}
void Run() {
 CXSparkLogger logger;
 Seed();Manager m;
 Check("two same-price positions reconcile independently",m.Reconcile(logger) && m.m_states.size()==2);
 live.erase(live.begin());
 Check("closed trade cannot rebind to same-price survivor",m.Reconcile(logger) && m.m_states.size()==1 && m.m_states[0].identifier==202 && m.m_states[0].ticket==22 && !saved.count(101));
 live[0].ticket=222;m.m_states[0].partial_done=true;
 Check("ticket change preserves exact identity and partial state",m.Reconcile(logger) && m.m_states.size()==1 && m.m_states[0].ticket==222 && m.m_states[0].partial_done);
 unreadable=0;
 Check("unreadable snapshot preserves all records",!m.Reconcile(logger) && m.m_states.size()==1 && saved.count(202));
 unreadable=-1;connected=false;live.clear();
 Check("disconnect does not prune positions",m.Reconcile(logger) && m.m_states.size()==1);
 Seed();Manager partial;
 partial.ManagePositions(106,106.1,1,2.5,50,2,false,20,0,logger);
 Check("both positions receive their own partial close",partial.partial_calls.size()==2 && live[0].volume==0.5 && live[1].volume==0.5);
 Check("both positions retain independent break-even state",partial.m_states[0].partial_done && partial.m_states[1].partial_done && live[0].stop==100 && live[1].stop==100);
 partial.ManagePositions(107,107.1,1,2.5,50,2,false,20,0,logger);
 Check("trailing manages both without duplicate partials",live[0].stop==105 && live[1].stop==105 && partial.partial_calls.size()==2);
 Manager restarted;restarted.ManagePositions(108,108.1,1,2.5,50,2,false,20,0,logger);
 Check("restart restores both partial flags and trailing",restarted.m_states.size()==2 && restarted.partial_calls.empty() && live[0].stop==106 && live[1].stop==106);
 Seed();Manager compact;compact.close_first_fully=true;
 compact.ManagePositions(106,106.1,1,2.5,50,2,false,20,0,logger);
 Check("closing first position does not skip second during compaction",live.size()==1 && live[0].id==202 && live[0].volume==0.5 && compact.partial_calls.size()==2);
 Seed();Manager collision;collision.Reconcile(logger);live[0].id=303;
 Check("ticket identity mismatch cannot overwrite recorded state",!collision.Reconcile(logger) && collision.m_states[0].identifier==101);
 collision.ManagePositions(106,106.1,1,2.5,50,2,false,20,0,logger);
 Check("mismatched ticket is never managed as the old trade",collision.partial_calls.size()==1 && collision.partial_calls[0]==22);
 // Opposite-direction exposure. Both strategies refuse to hold a position and
 // open its opposite: XSparkFlow because the open trade must exit on its own
 // trailing stop rather than be hedged, ScoreBot for the same reason. The EA
 // checks this when it plans, and ExecutionEngine re-checks it before every
 // send attempt, so a position that appears in between still blocks the entry.
 Seed();string opposed;
 Check("a held long admits another long",XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed));
 Check("a held long refuses a short",!XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_SELL,opposed) && opposed.find("OPPOSING EXPOSURE")!=string::npos);
 live[0].type=POSITION_TYPE_SELL;live[1].type=POSITION_TYPE_SELL;
 Check("a held short refuses a long",!XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed));
 Check("a held short admits another short",XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_SELL,opposed));
 live.clear();
 Check("a flat bot may open either direction",XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed) && XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_SELL,opposed));
 Seed();live.push_back({33,303});live.back().magic=770331;live.back().type=POSITION_TYPE_SELL;
 Check("another bot's opposite position is not this bot's exposure",XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed));
 Check("this bot's own long still refuses a short beside it",!XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_SELL,opposed));
 Seed();live.push_back({44,404});live.back().symbol="OTHER";live.back().type=POSITION_TYPE_SELL;
 Check("an opposite position on another symbol does not block",XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed));
 Seed();unreadable=0;
 Check("an unreadable position refuses rather than assumes flat",!XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_BUY,opposed));
 unreadable=-1;
 Check("a NONE direction is never unopposed",!XSparkDirectionIsUnopposed("TEST",999,XSPARK_SIGNAL_NONE,opposed));

 // The clear-the-emergency-stop input is a ONE-SHOT. MT5 reruns OnInit on an
 // input change, a recompile, a chart-period change, a reattach and a terminal
 // restart. A clear that also re-anchored the persisted peak when nothing was
 // latched therefore re-anchored it on every one of those, and the input left
 // true after a reset - which the log asks the operator to undo, and is
 // therefore exactly what gets forgotten - reset the ruin stop's measurement to
 // whatever hole the account was in, repeatedly. These drive the production
 // decision itself, not a copy of it.
 {
  bool clear_a_latch=false,adopt=false,inert=false;
  XSparkResolveKillswitchRestore(true,true,10000.0,clear_a_latch,adopt,inert);
  Check("clearing a real latch re-anchors the peak",clear_a_latch && !adopt && !inert);
  XSparkResolveKillswitchRestore(true,false,10000.0,clear_a_latch,adopt,inert);
  Check("a clear with nothing latched keeps the persisted peak",!clear_a_latch && adopt && inert);
  XSparkResolveKillswitchRestore(false,false,10000.0,clear_a_latch,adopt,inert);
  Check("an ordinary restart adopts the persisted peak",!clear_a_latch && adopt && !inert);
  XSparkResolveKillswitchRestore(false,true,10000.0,clear_a_latch,adopt,inert);
  Check("a restart carrying a latch adopts the peak and the latch",!clear_a_latch && adopt && !inert);
  XSparkResolveKillswitchRestore(false,false,0.0,clear_a_latch,adopt,inert);
  Check("a first run with no persisted peak seeds from live equity",!clear_a_latch && !adopt && !inert);
  XSparkResolveKillswitchRestore(true,false,0.0,clear_a_latch,adopt,inert);
  Check("an armed clear on a fresh install seeds, and reports itself inert",!clear_a_latch && !adopt && inert);

  // The regression, as an operator reaches it: clear a real latch, forget to
  // set the input back, then keep reattaching while the account keeps falling.
  double peak=10000.0,equity=7500.0;bool latched=true;int warned=0;
  XSparkResolveKillswitchRestore(true,latched,peak,clear_a_latch,adopt,inert);
  if(clear_a_latch){peak=equity;latched=false;}
  Check("the deliberate first clear re-anchors to live equity",peak==7500.0 && !latched);
  for(int i=0;i<4;i++){
   equity-=500.0;
   XSparkResolveKillswitchRestore(true,latched,peak,clear_a_latch,adopt,inert);
   if(clear_a_latch){peak=equity;latched=false;}
   else if(!adopt){peak=equity;}
   if(inert) warned++;
  }
  Check("later OnInits with the input still true never chase equity down",peak==7500.0 && equity==5500.0);
  Check("and every one of them warns that the input is still armed",warned==4);
 }

 // A NUMBER THE OPERATOR TYPED IS NEVER A REASON TO REFUSE TO START. These used
 // to return false from XSparkFlowValidateInputs, which returns INIT_FAILED,
 // which means OnTick never runs - and in the Strategy Tester that looks exactly
 // like a strategy that found no setups: a finished run, zero trades, one line
 // in the Journal. On a live chart it is worse, because open positions stop
 // being managed. Each case below must now RESOLVE and report.
 {
  double risk=0,daily=0,total=0; bool ks=false; string note;

  Check("the shipped defaults need no correction at all",
        XSparkCandleFlowResolveLimits(1.0,15.0,25.0,true,risk,daily,total,ks,note)
        && risk==1.0 && daily==15.0 && total==25.0 && ks && note=="");

  // The regression itself. A build shipped this setting labelled "(0 = off)";
  // MetaTrader keeps the value across a recompile because the identifier
  // survived, so that 0 outlives the build that meant it.
  Check("a zero emergency-stop level is honoured as OFF, not refused",
        !XSparkCandleFlowResolveLimits(1.0,15.0,0.0,true,risk,daily,total,ks,note)
        && !ks && total==25.0 && note.find("OFF")!=string::npos);
  Check("and the operator still keeps the trade risk they set",risk==1.0);

  // Risk above the ceiling clamps DOWN. Refusing to start protects nothing;
  // running at the ceiling is strictly safer than what was asked for.
  Check("risk above the ceiling clamps to the ceiling rather than refusing",
        !XSparkCandleFlowResolveLimits(5.0,15.0,25.0,true,risk,daily,total,ks,note)
        && risk==3.5 && ks && total==25.0);
  Check("risk at the ceiling exactly is not a correction",
        XSparkCandleFlowResolveLimits(3.5,15.0,25.0,true,risk,daily,total,ks,note) && risk==3.5);

  Check("a zero risk cannot size a trade and falls back to the recommended one",
        !XSparkCandleFlowResolveLimits(0.0,15.0,25.0,true,risk,daily,total,ks,note) && risk==1.0);

  // A daily limit of zero halts trading at zero drawdown, permanently.
  Check("a zero daily limit falls back rather than halting at once",
        !XSparkCandleFlowResolveLimits(1.0,0.0,25.0,true,risk,daily,total,ks,note) && daily==15.0);
  Check("a daily limit of 100 or more falls back",
        !XSparkCandleFlowResolveLimits(1.0,100.0,25.0,true,risk,daily,total,ks,note) && daily==15.0);

  Check("an emergency stop of 100 or more falls back and stays armed",
        !XSparkCandleFlowResolveLimits(1.0,15.0,100.0,true,risk,daily,total,ks,note)
        && total==25.0 && ks);

  // Harmless, so reported and left alone rather than corrected into something
  // nobody asked for: the stricter control still acts first.
  Check("a daily limit above the emergency stop is reported, not rewritten",
        !XSparkCandleFlowResolveLimits(1.0,30.0,25.0,true,risk,daily,total,ks,note)
        && daily==30.0 && total==25.0 && note.find("never act")!=string::npos);
  Check("and it is not even reported when the emergency stop is switched off",
        XSparkCandleFlowResolveLimits(1.0,30.0,25.0,false,risk,daily,total,ks,note)
        && daily==30.0 && !ks && note=="");

  // Switching off by the switch must survive untouched - that is the operator's
  // documented way to run a full-year backtest.
  Check("the switch alone turns the emergency stop off with no correction",
        XSparkCandleFlowResolveLimits(1.0,15.0,25.0,false,risk,daily,total,ks,note)
        && !ks && total==25.0 && note=="");

  // Several at once must all be corrected, not just the first.
  Check("several bad settings are all corrected in one pass",
        !XSparkCandleFlowResolveLimits(9.0,0.0,0.0,true,risk,daily,total,ks,note)
        && risk==3.5 && daily==15.0 && total==25.0 && !ks);
 }

 // Candle-anchor trailing, exercising the manager loop itself.
 Seed();Manager anchor;
 TrailOnce(anchor,106,106.1,99,0,logger);
 Check("candle anchor trails every position without a partial close",anchor.partial_calls.empty() && live[0].stop==99 && live[1].stop==99);
 TrailOnce(anchor,106,106.1,97,0,logger);
 Check("a looser candle anchor never widens a live stop",live[0].stop==99 && live[1].stop==99);
 TrailOnce(anchor,106,106.1,101,0,logger);
 Check("a tighter candle anchor moves the stop up",live[0].stop==101 && live[1].stop==101);
 TrailOnce(anchor,106,106.1,0,0,logger);
 Check("a missing candle anchor leaves the broker stop alone",live[0].stop==101 && live[1].stop==101);
 Check("candle anchor mode records the trail it applied",anchor.m_states[0].current_trail_sl==101 && saved.at(101).current_trail_sl==101);
 SeedShort();Manager anchor_short;
 TrailOnce(anchor_short,94,94.1,0,101,logger);
 Check("candle anchor trails a short down",live[0].stop==101 && live[1].stop==101);
 TrailOnce(anchor_short,94,94.1,0,103,logger);
 Check("a looser candle anchor never widens a short stop",live[0].stop==101 && live[1].stop==101);

 // The composed trail: peak tracking, the chandelier, the breakeven lock and
 // the floor, applied through the same one-way ratchet. Seeded positions are
 // long from 100 with 2.0 of initial risk and a stop at 98.
 Seed();Manager chandelier;
 TrailPlanned(chandelier,106,106.1,logger,0,0,/*peak candle*/110,105,1,/*atr*/2,/*floor*/0.25,/*trail*/3,0,0,0,0,0);
 Check("the chandelier trails from the closed candle's peak",live[0].stop==104 && live[1].stop==104);
 TrailPlanned(chandelier,106,106.1,logger,0,0,110,105,1,2,0.25,3,0,0,0,0,0);
 Check("the same candle cannot advance the peak twice",live[0].stop==104 && chandelier.m_states[0].trail_peak==110);
 TrailPlanned(chandelier,106,106.1,logger,0,0,108,104,2,2,0.25,3,0,0,0,0,0);
 Check("a lower high never lowers the peak",live[0].stop==104 && chandelier.m_states[0].trail_peak==110);
 TrailPlanned(chandelier,112,112.1,logger,0,0,114,109,3,2,0.25,3,0,0,0,0,0);
 Check("a higher high raises the peak and the stop with it",live[0].stop==108 && chandelier.m_states[0].trail_peak==114);
 Check("the advanced peak is persisted for a restart",saved.at(101).trail_peak==114);

 // Tiering: 5R of maturity with tightening complete at 3R uses the tight
 // multiple, so the stop sits one ATR under the peak rather than three.
 // Quoted at 109 rather than 106: a 1 x ATR trail under a peak of 110 sits at
 // 108, which is only a legal stop while the market is above it. At 106 the
 // floor would rescue it instead, which the case below that one proves.
 Seed();Manager tiered;
 TrailPlanned(tiered,109,109.1,logger,0,0,110,105,1,2,0.25,3,1,1,3,0,0);
 Check("a mature trade trails at the tightened multiple",live[0].stop==108);
 Seed();Manager tiered_through;
 TrailPlanned(tiered_through,106,106.1,logger,0,0,110,105,1,2,0.25,3,1,1,3,0,0);
 Check("a tightened trail that lands through the market is rescued by the floor",live[0].stop==105.5);

 // Breakeven: the candle high reaches exactly 1R and the lock engages, even
 // with the chandelier disabled.
 Seed();Manager be;
 TrailPlanned(be,101,101.1,logger,0,0,102,100.5,1,2,0.25,0,0,0,0,1,0);
 Check("the breakeven lock moves the stop to entry",live[0].stop==100);
 Seed();Manager be_early;
 TrailPlanned(be_early,101,101.1,logger,0,0,101.5,100.5,1,2,0.25,0,0,0,0,1,0);
 Check("below the trigger the breakeven lock leaves the stop alone",live[0].stop==98);

 // The floor is what stops a tight candle from parking the stop inside the
 // spread. The anchor at 105.99 is 0.01 from the bid; the floor is 0.5.
 Seed();Manager floored;
 TrailPlanned(floored,106,106.1,logger,105.99,0,0,0,0,2,0.25,0,0,0,0,0,0);
 Check("an anchor inside the floor is widened away from the market",live[0].stop==105.5);
 Seed();Manager unfloored;
 TrailPlanned(unfloored,106,106.1,logger,105.99,0,0,0,0,2,0,0,0,0,0,0,0);
 Check("with the floor off the same anchor is used as given",live[0].stop==105.99);
 Seed();double all=0,own=0,other=0;int count=0;string reason;
 live.push_back({33,303});live.back().symbol="OTHER";
 Check("exposure includes foreign trades but counts own slots",XSparkReadAccountExposure("TEST",999,all,own,other,count,reason) && all==6 && own==4 && other==2 && count==2);
 live[2].stop=0;
 Check("foreign position without stop blocks account admission",!XSparkReadAccountExposure("TEST",999,all,own,other,count,reason));

 // Scaled profit taking, exercising the manager loop itself. The seeded
 // positions are long from 100 with 2.0 of initial risk and 1.00 lots, so a
 // step at 1.0R triggers at 102 and one at 2.0R at 104.
 Seed();Manager ladder;
 Check("the ladder plan is accepted",LadderOnce(ladder,101.9,102.0,logger,1.0,30,2.0,30));
 Check("no step fires before its price is reached",ladder.partial_calls.empty() && VolumeIs(live[0].volume,1));
 LadderOnce(ladder,102,102.1,logger,1.0,30,2.0,30);
 Check("the first step closes its share of the starting size",ladder.partial_calls.size()==2 && VolumeIs(live[0].volume,0.7) && VolumeIs(live[1].volume,0.7));
 Check("progress is recorded and persisted",ladder.m_states[0].profit_high_water_r==1.0 && saved.at(101).profit_high_water_r==1.0);
 LadderOnce(ladder,102,102.1,logger,1.0,30,2.0,30);
 Check("a banked step never fires twice at the same price",ladder.partial_calls.size()==2 && VolumeIs(live[0].volume,0.7));
 LadderOnce(ladder,104,104.1,logger,1.0,30,2.0,30);
 Check("the second step banks a share of the starting size, not of the remainder",ladder.partial_calls.size()==4 && VolumeIs(live[0].volume,0.4));
 // 30% of the 1.00 lots the position OPENED with, both times. 30% of the 0.70
 // remainder would have been 0.21, which is what a ladder sized from the live
 // volume would have sent on the second step.
 Check("every step is sized from the opening volume",VolumeIs(ladder.partial_volumes[0],0.3) && VolumeIs(ladder.partial_volumes[3],0.3));
 Check("progress advances to the second step",ladder.m_states[0].profit_high_water_r==2.0);
 LadderOnce(ladder,106,106.1,logger,1.0,30,2.0,30);
 Check("an exhausted ladder stops closing",ladder.partial_calls.size()==4 && VolumeIs(live[0].volume,0.4));

 // A restart mid-ladder must not re-bank what the trade already banked.
 Manager reopened;
 LadderOnce(reopened,104,104.1,logger,1.0,30,2.0,30);
 Check("a restart mid-ladder repeats no step",reopened.partial_calls.empty() && VolumeIs(live[0].volume,0.4));
 Check("a restart mid-ladder restores the progress",reopened.m_states[0].profit_high_water_r==2.0);

 // THE CRASH WINDOW. The broker confirmed the close and the terminal died
 // before the progress was written, so the volume is already reduced while the
 // record still says nothing was banked. A ladder that closed a fixed share
 // would bank a second 30% here; a budget has nothing left to do.
 Seed();for(auto& b:live) b.volume=0.7;
 Manager crashed;
 LadderOnce(crashed,102,102.1,logger,1.0,30,2.0,30);
 Check("a confirmed close that was never recorded is not replayed",crashed.partial_calls.empty() && VolumeIs(live[0].volume,0.7));

 // A candle that gaps through both steps banks both shares in ONE order, at
 // the price the market is actually at, rather than leaving the upper step to
 // a later pass at a price that may have retraced.
 Seed();Manager gapped;
 LadderOnce(gapped,106,106.1,logger,1.0,30,2.0,30);
 Check("a gap through both steps banks them in one order",gapped.partial_calls.size()==2 && VolumeIs(gapped.partial_volumes[0],0.6) && VolumeIs(live[0].volume,0.4));
 Check("a gap through both steps records the furthest one",gapped.m_states[0].profit_high_water_r==2.0);

 // Profit first, then protection, on the SAME pass: the tick that banked a
 // step is the tick the stop most wants ratcheting on, and the state array it
 // was banked through has been re-resolved by then.
 Seed();Manager ordered;
 LadderOnce(ordered,102,102.1,logger,1.0,30,2.0,30,/*anchor_long*/101);
 Check("the pass that banks a step also trails the remainder",ordered.partial_calls.size()==2 && live[0].stop==101);
 Check("banking and trailing on one pass keeps the position's own target",VolumeIs(live[0].tp,110));
 LadderOnce(ordered,102,102.1,logger,1.0,30,2.0,30,103);
 Check("the next pass trails normally with nothing left to bank",live[0].stop==103 && ordered.partial_calls.size()==2);

 // A broker take-profit belongs to the position, and neither the ladder nor the
 // trail may remove it. The seeded positions carry one at 110.
 Seed();Manager keeps_target;
 LadderOnce(keeps_target,102,102.1,logger,1.0,30,2.0,30,101);
 Check("trailing never erases a live broker take-profit",VolumeIs(live[0].tp,110) && VolumeIs(live[1].tp,110));

 // A ladder is only ever consulted by the candle-anchor exit; ScoreBot's mode
 // must behave exactly as it always has.
 Seed();Manager other_mode;
 XSparkTrailPlan atr_plan = MakeTrailPlan(XSPARK_TRAIL_ATR_AFTER_PARTIAL);
 atr_plan.ladder.level_r[0]=1.0; atr_plan.ladder.level_pct[0]=30;
 other_mode.SetTrailPlan(atr_plan);
 other_mode.ManagePositions(102,102.1,1,2.5,50,2,false,20,0,logger);
 Check("the ladder never runs in the partial-then-trail mode",other_mode.partial_calls.empty() && VolumeIs(live[0].volume,1));

 // A small position. 30% of 0.02 lots rounds to 0.00, so the first step cannot
 // fire - but the SECOND step's budget is 40% of 0.02, which needs 0.01 closed,
 // and that is legal. A per-step percentage would have banked nothing at all.
 Seed();Manager tiny;
 for(auto& b:live) {b.volume=0.02; saved[b.id].initial_lots=0.02;}
 LadderOnce(tiny,102,102.1,logger,1.0,30,2.0,30);
 Check("a step with no legal volume closes nothing",tiny.partial_calls.empty() && VolumeIs(live[0].volume,0.02));
 Check("a skipped step is not recorded as banked",tiny.m_states[0].profit_high_water_r==0.0);
 LadderOnce(tiny,104,104.1,logger,1.0,30,2.0,30);
 Check("a later step makes good what a skipped one could not take",tiny.partial_calls.size()==2 && VolumeIs(live[0].volume,0.01));

 // The SHIPPED split on the smallest position it is meant to serve. 40% of
 // 0.03 lots is 0.012, which rounds down to 0.01 and fires; a 30% first step
 // would be 0.009 and would be skipped. This is why the shipped first share is
 // the larger one, and the case pins that reasoning to an assertion.
 Seed();Manager shipped;
 for(auto& b:live) {b.volume=0.03; saved[b.id].initial_lots=0.03;}
 LadderOnce(shipped,103,103.1,logger,
            XSPARK_LADDER_DEFAULT_LEVEL1_R,XSPARK_LADDER_DEFAULT_LEVEL1_PCT,
            XSPARK_LADDER_DEFAULT_LEVEL2_R,XSPARK_LADDER_DEFAULT_LEVEL2_PCT);
 Check("the shipped first step fires on the smallest position it serves",
       shipped.partial_calls.size()==2 && VolumeIs(shipped.partial_volumes[0],0.01) && VolumeIs(live[0].volume,0.02));
 LadderOnce(shipped,106,106.1,logger,
            XSPARK_LADDER_DEFAULT_LEVEL1_R,XSPARK_LADDER_DEFAULT_LEVEL1_PCT,
            XSPARK_LADDER_DEFAULT_LEVEL2_R,XSPARK_LADDER_DEFAULT_LEVEL2_PCT);
 Check("the shipped second step fires there too, leaving a residual",
       shipped.partial_calls.size()==4 && VolumeIs(live[0].volume,0.01));

 // A rejected close backs off instead of re-sending on every tick, and latches
 // off after enough consecutive rejections. The trail keeps running throughout.
 Seed();Manager rejected;rejected.reject_partials=true;
 LadderOnce(rejected,102,102.1,logger,1.0,30,2.0,30,101);
 Check("a rejected close is attempted once",rejected.partial_calls.size()==2 && VolumeIs(live[0].volume,1));
 Check("a rejected close still lets the stop trail",live[0].stop==101);
 Check("a rejection does not record progress",rejected.m_states[0].profit_high_water_r==0.0);
 LadderOnce(rejected,102,102.1,logger,1.0,30,2.0,30,101);
 Check("a rejected close is not retried inside the cooldown",rejected.partial_calls.size()==2);
 for(int attempt=0;attempt<XSPARK_PROFIT_LADDER_MAX_REJECTS+2;attempt++) {
  for(auto& s:rejected.m_states) s.profit_retry_after=0;
  LadderOnce(rejected,102,102.1,logger,1.0,30,2.0,30,101);
 }
 Check("repeated rejections latch the ladder off for the position",
       rejected.partial_calls.size()==size_t(2*XSPARK_PROFIT_LADDER_MAX_REJECTS) && VolumeIs(live[0].volume,1));

 // The EARLY style on the smallest position it is meant to serve. Its second
 // step asks for a quarter of the OPENING volume to be left, and the budget is
 // measured against what is live - so it fires where a per-step percentage of
 // 25% (0.0075 lots) would have rounded to nothing.
 Seed();Manager early;
 for(auto& b:live) {b.volume=0.03; saved[b.id].initial_lots=0.03;}
 LadderOnce(early,102,102.1,logger,1.0,50,2.0,25);
 Check("the early style's first step fires on 0.03 lots",early.partial_calls.size()==2 && VolumeIs(live[0].volume,0.02));
 LadderOnce(early,104,104.1,logger,1.0,50,2.0,25);
 Check("the early style's second step fires there too",early.partial_calls.size()==4 && VolumeIs(live[0].volume,0.01));

 // Shorts bank on the way down.
 SeedShort();Manager ladder_short;
 LadderOnce(ladder_short,98.1,98.2,logger,1.0,30,2.0,30);
 Check("a short's step is not due while price is above it",ladder_short.partial_calls.empty() && VolumeIs(live[0].volume,1));
 LadderOnce(ladder_short,97.9,98.0,logger,1.0,30,2.0,30);
 Check("a short banks its first step at its own price",ladder_short.partial_calls.size()==2 && VolumeIs(live[0].volume,0.7));

 // An invalid ladder is refused as a whole plan, and the previously accepted
 // plan stays in force rather than the trade being managed on nothing.
 Seed();Manager refused;
 XSparkTrailPlan bad = MakeTrailPlan(XSPARK_TRAIL_CANDLE_ANCHOR);
 bad.ladder.level_r[0]=1.0; bad.ladder.level_pct[0]=60;
 bad.ladder.level_r[1]=2.0; bad.ladder.level_pct[1]=60;
 Check("a ladder that would close the whole position is refused by the manager",!refused.SetTrailPlan(bad));
 refused.ManagePositions(102,102.1,1,0,0,0,false,20,0,logger);
 Check("a refused ladder banks nothing",refused.partial_calls.empty() && VolumeIs(live[0].volume,1));

 // A position adopted with no persisted record has no trustworthy original
 // risk, and every trigger is measured against it. It must never be laddered.
 Seed();saved.clear();Manager adopted;
 LadderOnce(adopted,200,200.1,logger,1.0,30,2.0,30);
 Check("a position adopted without a record is never laddered",adopted.partial_calls.empty() && VolumeIs(live[0].volume,1));

 // The realised-R ledger's win count, which is the number a scalper is judged
 // on. A scratch is neither a win nor a loss and still counts against the rate.
 XSparkRLedger ledger; XSparkResetRLedger(ledger);
 Check("an empty ledger has no win rate", XSparkRLedgerWinRate(ledger)==0.0);
 XSparkRLedgerRecordOutcome(ledger,12.5); XSparkRLedgerRecordOutcome(ledger,-0.07); XSparkRLedgerRecordOutcome(ledger,0.0); XSparkRLedgerRecordOutcome(ledger,0.05);
 Check("wins and losses are counted in cash and a scratch is neither", ledger.outcomes==4 && ledger.wins==2 && ledger.losses==1);
 Check("the win rate is wins over every recorded outcome", XSparkRLedgerWinRate(ledger)==0.5);
 XSparkRLedgerRecordOutcome(ledger, std::numeric_limits<double>::quiet_NaN());
 Check("an unusable outcome is not recorded at all", ledger.outcomes==4 && ledger.wins==2);
 XSparkRLedgerAdd(ledger, 1.0);
 Check("the R moments never record an outcome by themselves", ledger.count==1 && ledger.outcomes==4);

 // The small-account floor in the production sizing function: a budget too
 // small for the broker minimum is raised to it only inside an explicit cap,
 // and every existing caller (cap zero) keeps the refusal it always had.
 {
  double volume=0, loss_per_lot=0; string why;
  Check("sizer: a zero cap refuses a below-minimum volume",
        !XSparkVolumeFromRiskInputs(1.0,3.0,0.01,1.0,0.01,100.0,0.01,volume,loss_per_lot,why) && volume==0.0);
  Check("sizer: a cap below the minimum-lot risk refuses and names the cap",
        !XSparkVolumeFromRiskInputs(1.0,3.0,0.01,1.0,0.01,100.0,0.01,volume,loss_per_lot,why,2.0) && why.find("above the 2.00 cap")!=string::npos);
  Check("sizer: a cap at the minimum-lot risk raises exactly to the minimum",
        XSparkVolumeFromRiskInputs(1.0,3.0,0.01,1.0,0.01,100.0,0.01,volume,loss_per_lot,why,3.0) && VolumeIs(volume,0.01) && why.find("raised to the broker minimum")!=string::npos);
  Check("sizer: a volume that meets the minimum is never changed by the cap",
        XSparkVolumeFromRiskInputs(100.0,3.0,0.01,1.0,0.01,100.0,0.01,volume,loss_per_lot,why,3.0) && VolumeIs(volume,0.33));
 }

 // The time stop and the session-end flatten, exercising the manager loop
 // itself. Ages are seeded against the stub's server clock; the positions are
 // long from 100 with a stop at 98 and 1.00 lots, and the bid/ask passed to
 // ManagePositions is the spread the exit check sees.
 {
  const datetime now = TimeTradeServer();
  const datetime cooldown = now + XSPARK_TIME_EXIT_RETRY_SECONDS;

  SeedAged(100);Manager young;
  TimeOnce(young,100,100.02,3600,0,0,logger);
  Check("time stop: a position younger than the limit is untouched",young.close_calls.empty() && live.size()==2 && young.m_states.size()==2 && live[0].stop==98);

  SeedAged(100);live[0].open_time=now-3600;Manager at_limit;
  TimeOnce(at_limit,100,100.02,3600,0,0,logger);
  Check("time stop: a position held exactly the limit is closed and its state pruned",at_limit.close_calls.size()==1 && at_limit.close_calls[0]==11 && live.size()==1 && live[0].id==202 && at_limit.m_states.size()==1 && at_limit.m_states[0].identifier==202 && !saved.count(101) && saved.count(202));
  Check("time stop: the younger position beside it is untouched",VolumeIs(live[0].volume,1) && live[0].stop==98);
  SeedAged(5000);Manager over_limit;
  TimeOnce(over_limit,100,100.02,3600,0,0,logger);
  Check("time stop: every position over the limit is closed",over_limit.close_calls.size()==2 && live.empty() && over_limit.m_states.empty());

  SeedAged(100);Manager session_past;
  TimeOnce(session_past,100,100.02,0,now-1,0,logger);
  Check("session close: a flatten time in the past closes every position",session_past.close_calls.size()==2 && live.empty());
  SeedAged(100);Manager session_now;
  TimeOnce(session_now,100,100.02,0,now,0,logger);
  Check("session close: the flatten instant itself closes",session_now.close_calls.size()==2 && live.empty());
  SeedAged(100);Manager session_future;
  TimeOnce(session_future,100,100.02,0,now+1,0,logger);
  Check("session close: a flatten time in the future closes nothing",session_future.close_calls.empty() && live.size()==2);

  // A rejected close backs off instead of re-sending on every tick, and latches
  // off after enough consecutive rejections. The broker stop is never touched.
  SeedAged(5000);Manager refused_close;refused_close.close_result=XSPARK_CLOSE_RESULT_REJECT;
  TimeOnce(refused_close,100,100.02,3600,0,0,logger);
  Check("a rejected time stop is attempted once per position and backs off",refused_close.close_calls.size()==2 && live.size()==2 && refused_close.m_states[0].time_exit_reject_count==1 && refused_close.m_states[0].time_exit_retry_after==cooldown);
  TimeOnce(refused_close,100,100.02,3600,0,0,logger);
  Check("a rejected time stop is not retried inside the cooldown",refused_close.close_calls.size()==2);
  Check("a rejected time stop leaves the broker stop where it was",live[0].stop==98 && live[1].stop==98);
  for(int attempt=0;attempt<XSPARK_TIME_EXIT_MAX_REJECTS+2;attempt++) {
   for(auto& s:refused_close.m_states) s.time_exit_retry_after=0;
   TimeOnce(refused_close,100,100.02,3600,0,0,logger);
  }
  Check("five rejections latch the time stop off for the position",refused_close.close_calls.size()==size_t(2*XSPARK_TIME_EXIT_MAX_REJECTS) && refused_close.m_states[0].time_exit_reject_count==XSPARK_TIME_EXIT_MAX_REJECTS && live.size()==2);
  Check("a latched time stop still leaves the stop and the size alone",live[0].stop==98 && VolumeIs(live[0].volume,1) && VolumeIs(live[1].volume,1));

  // A restart re-arms. The backoff is RAM-only in production; the whole-struct
  // storage double would have carried a persisted count straight back, so it
  // is planted in storage here and must NOT come back.
  for(auto& b:live) {saved.at(b.id).time_exit_reject_count=XSPARK_TIME_EXIT_MAX_REJECTS; saved.at(b.id).time_exit_retry_after=now+99999;}
  Manager rearmed;rearmed.close_result=XSPARK_CLOSE_RESULT_REJECT;
  TimeOnce(rearmed,100,100.02,3600,0,0,logger);
  Check("a restart re-arms the time stop with exactly one attempt per position",rearmed.close_calls.size()==2 && rearmed.close_calls[0]==11 && rearmed.close_calls[1]==22 && rearmed.m_states[0].time_exit_reject_count==1);
  TimeOnce(rearmed,100,100.02,3600,0,0,logger);
  Check("and the re-armed attempt backs off like any other",rearmed.close_calls.size()==2);

  // An outage is nobody's fault: attempted, deferred, never counted, and it
  // clears whatever count the position had.
  SeedAged(5000);Manager outage;outage.close_result=XSPARK_CLOSE_RESULT_DEFER;
  outage.Reconcile(logger);
  for(auto& s:outage.m_states) s.time_exit_reject_count=3;
  TimeOnce(outage,100,100.02,3600,0,0,logger);
  Check("a deferred close is attempted, not counted, and resets a prior count",outage.close_calls.size()==2 && live.size()==2 && outage.m_states[0].time_exit_reject_count==0 && outage.m_states[1].time_exit_reject_count==0 && outage.m_states[0].time_exit_retry_after==cooldown);
  TimeOnce(outage,100,100.02,3600,0,0,logger);
  Check("a deferred close waits out its cooldown",outage.close_calls.size()==2);

  // A wide spread defers WITHOUT a close call, and the close goes through once
  // the spread is back inside the limit and the cooldown has passed.
  SeedAged(5000);Manager wide;
  TimeOnce(wide,100,100.2,3600,0,0.05,logger);
  Check("a wide spread defers the time stop without a close call",wide.close_calls.empty() && live.size()==2 && wide.m_states[0].time_exit_retry_after==cooldown && wide.m_states[0].time_exit_reject_count==0);
  TimeOnce(wide,100,100.02,3600,0,0.05,logger);
  Check("a narrowed spread still waits out the deferral",wide.close_calls.empty());
  for(auto& s:wide.m_states) s.time_exit_retry_after=0;
  TimeOnce(wide,100,100.02,3600,0,0.05,logger);
  Check("once the spread is inside the limit the time stop closes",wide.close_calls.size()==2 && live.empty());
  SeedAged(5000);Manager unchecked_spread;
  TimeOnce(unchecked_spread,100,100.2,3600,0,0,logger);
  Check("a zero spread limit means no spread check",unchecked_spread.close_calls.size()==2 && live.empty());

  SeedAged(1000000);Manager limits_off;
  TimeOnce(limits_off,100,100.02,0,0,0,logger);
  Check("with both limits off a position is never time-closed",limits_off.close_calls.empty() && live.size()==2 && live[0].stop==98);

  // ADR-018: a position adopted without a record has no original risk, and
  // that PROPERTY - not a separate guard - is what keeps it out of the time
  // stop. Its broker stop and target are the whole of its management.
  SeedAged(1000000);saved.clear();Manager adopted_old;
  TimeOnce(adopted_old,100,100.02,60,now-1,0,logger);
  Check("a position adopted without a record is never time-closed",adopted_old.close_calls.empty() && live.size()==2 && adopted_old.m_states.size()==2);
  Check("and it is unmanaged because its original risk is unknown",adopted_old.m_states[0].initial_risk_distance==0.0 && adopted_old.m_states[1].initial_risk_distance==0.0);

  // ScoreBot's mode never reaches the time stop, whatever the plan says.
  SeedAged(1000000);Manager atr_mode;
  XSparkTrailPlan timed_atr = MakeTrailPlan(XSPARK_TRAIL_ATR_AFTER_PARTIAL);
  timed_atr.max_hold_seconds=60; timed_atr.flatten_after=now-1;
  atr_mode.SetTrailPlan(timed_atr);
  atr_mode.ManagePositions(99,99.1,1,2.5,50,2,false,20,0,logger);
  Check("the partial-then-trail mode never time-closes",atr_mode.close_calls.empty() && atr_mode.partial_calls.empty() && live.size()==2);

  // Another bot's position and another symbol's position, both far over the
  // limit, are not this instance's to close.
  SeedAged(5000);
  live.push_back({33,303});live.back().magic=770331;live.back().open_time=now-1000000;
  live.push_back({44,404});live.back().symbol="OTHER";live.back().open_time=now-1000000;
  Manager foreign;
  TimeOnce(foreign,100,100.02,3600,0,0,logger);
  Check("the time stop closes this bot's positions and nobody else's",foreign.close_calls.size()==2 && foreign.close_calls[0]==11 && foreign.close_calls[1]==22 && live.size()==2 && live[0].id==303 && live[1].id==404);
  Check("the foreign positions keep their size and stop",VolumeIs(live[0].volume,1) && VolumeIs(live[1].volume,1) && live[0].stop==98 && live[1].stop==98);

  // A partial fill is DONE: the remainder keeps its ticket and its open time,
  // the row stays, and the next pass closes the rest.
  SeedAged(5000);Manager partial_fill;partial_fill.partial_time_closes=true;
  TimeOnce(partial_fill,100,100.02,3600,0,0,logger);
  Check("a partially filled time stop closes once per position and keeps the rows",partial_fill.close_calls.size()==2 && live.size()==2 && VolumeIs(live[0].volume,0.5) && VolumeIs(live[1].volume,0.5) && partial_fill.m_states.size()==2);
  Check("a partial fill sets no backoff, so the remainder is retried at once",partial_fill.m_states[0].time_exit_retry_after==0 && partial_fill.m_states[0].time_exit_reject_count==0);
  partial_fill.partial_time_closes=false;
  TimeOnce(partial_fill,100,100.02,3600,0,0,logger);
  Check("the next pass closes the remainder and prunes",partial_fill.close_calls.size()==4 && live.empty() && partial_fill.m_states.empty());

  // A flatten campaign already owns every close under this Magic Number.
  SeedAged(5000);Manager campaign;campaign.m_flatten_campaign_reason="Killswitch flatten";
  TimeOnce(campaign,100,100.02,3600,now-1,0,logger);
  Check("an open flatten campaign suppresses the time stop",campaign.close_calls.empty() && live.size()==2 && campaign.m_flatten_campaign_reason=="Killswitch flatten");

  // The retcode classifier itself, one code of each class and the boundary
  // ones a broker actually returns.
  Check("retcode class: done, partial and placed are DONE",
        XSparkCloseRetcodeClass(TRADE_RETCODE_DONE)==XSPARK_CLOSE_RESULT_DONE &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_DONE_PARTIAL)==XSPARK_CLOSE_RESULT_DONE &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_PLACED)==XSPARK_CLOSE_RESULT_DONE &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_POSITION_CLOSED)==XSPARK_CLOSE_RESULT_DONE);
  Check("retcode class: a moved price is RETRY",
        XSparkCloseRetcodeClass(TRADE_RETCODE_REQUOTE)==XSPARK_CLOSE_RESULT_RETRY &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_PRICE_CHANGED)==XSPARK_CLOSE_RESULT_RETRY &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_PRICE_OFF)==XSPARK_CLOSE_RESULT_RETRY);
  Check("retcode class: an outage or a closed market is DEFER",
        XSparkCloseRetcodeClass(TRADE_RETCODE_MARKET_CLOSED)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_TRADE_DISABLED)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_FROZEN)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_CONNECTION)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_TIMEOUT)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_TOO_MANY_REQUESTS)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_ONLY_REAL)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_LIMIT_ORDERS)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_LIMIT_VOLUME)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_SERVER_DISABLES_AT)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_CLIENT_DISABLES_AT)==XSPARK_CLOSE_RESULT_DEFER &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_LOCKED)==XSPARK_CLOSE_RESULT_DEFER);
  Check("retcode class: a refusal of this request is REJECT, and so is anything unknown",
        XSparkCloseRetcodeClass(TRADE_RETCODE_REJECT)==XSPARK_CLOSE_RESULT_REJECT &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_INVALID_STOPS)==XSPARK_CLOSE_RESULT_REJECT &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_NO_MONEY)==XSPARK_CLOSE_RESULT_REJECT &&
        XSparkCloseRetcodeClass(TRADE_RETCODE_ERROR)==XSPARK_CLOSE_RESULT_REJECT &&
        XSparkCloseRetcodeClass(0)==XSPARK_CLOSE_RESULT_REJECT);

  // The plan's reset switches every time exit off, so a caller that never
  // sets them - every caller before TrendScalp - is unchanged.
  XSparkTrailPlan fresh; XSparkResetTrailPlan(fresh);
  Check("a reset plan carries no time exit",fresh.max_hold_seconds==0 && fresh.flatten_after==0 && fresh.exit_max_spread==0.0);
  XSparkTradeState blank; XSparkResetTradeState(blank);
  Check("a reset state carries no time-exit backoff",blank.time_exit_retry_after==0 && blank.time_exit_reject_count==0);
 }
}
} // namespace
