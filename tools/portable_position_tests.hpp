// Test-only terminal/broker doubles. Methods inserted below are production source.
// This verifies state isolation and loop behaviour, not actual broker execution.
namespace MultiPositionTests {
// TRADE_STATE_SOURCE
struct FakePosition {
 ulong ticket; long id; double entry=100, stop=98, volume=1, tp=110;
 string symbol="TEST"; long magic=999; long type=0;
};
std::vector<FakePosition> live;
std::map<long,XSparkTradeState> saved;
int selected=-1, unreadable=-1;
bool connected=true;
enum {POSITION_IDENTIFIER, POSITION_TIME, POSITION_MAGIC, POSITION_TYPE,
 POSITION_PRICE_OPEN, POSITION_SL, POSITION_VOLUME, POSITION_TP, POSITION_SYMBOL,
 SYMBOL_DIGITS, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_VALUE_LOSS,
 TERMINAL_CONNECTED, POSITION_TYPE_BUY=100, POSITION_TYPE_SELL=101};
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
double SymbolInfoDouble(const string&,int) {return 1;}
long TerminalInfoInteger(int) {return connected;}
string DoubleToString(double v,int) {return std::to_string(v);}
// IDENTITY_SOURCE
// UNOPPOSED_SOURCE
bool XSparkAdjustProtectionLevels(const string&,EXSparkSignalDirection,double,double sl,double tp,bool,
                                  double& out_sl,double& out_tp,string&) {out_sl=sl;out_tp=tp;return true;}
class CXSparkLogger {public:
 void Info(const string&,const string&) {} void Warn(const string&,const string&) {} void Error(const string&,const string&) {}
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
 std::vector<XSparkTradeState> m_states;
 std::vector<ulong> partial_calls, modify_calls;
 XSparkTrailPlan m_trail_plan = MakeTrailPlan();
 bool close_first_fully=false;
 bool LoadPersistedState(XSparkTradeState& s) {
  if(!saved.count(s.identifier)) return false;
  auto ticket=s.ticket; s=saved.at(s.identifier); s.ticket=ticket; return true;
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
 double LegalPartialCloseVolume(double initial,double current,double pct) {return std::min(current,initial*pct/100);}
 bool ClosePartial(ulong ticket,double volume,CXSparkLogger&) {
  if(!PositionSelectByTicket(ticket)) return false;
  partial_calls.push_back(ticket);
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
}
} // namespace
