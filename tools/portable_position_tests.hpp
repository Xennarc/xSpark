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
class Manager {
public:
 bool m_initialized=true, m_use_stop_level_validation=true;
 string m_symbol="TEST",m_last_reason,m_flatten_campaign_reason;
 ulong m_magic_number=999;
 int m_managed_position_count=0,m_unmanaged_position_count=0,m_flatten_attempts=0;
 std::vector<XSparkTradeState> m_states;
 std::vector<ulong> partial_calls, modify_calls;
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
 anchor.ManagePositions(106,106.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,99,0);
 Check("candle anchor trails every position without a partial close",anchor.partial_calls.empty() && live[0].stop==99 && live[1].stop==99);
 anchor.ManagePositions(106,106.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,97,0);
 Check("a looser candle anchor never widens a live stop",live[0].stop==99 && live[1].stop==99);
 anchor.ManagePositions(106,106.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,101,0);
 Check("a tighter candle anchor moves the stop up",live[0].stop==101 && live[1].stop==101);
 anchor.ManagePositions(106,106.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,0,0);
 Check("a missing candle anchor leaves the broker stop alone",live[0].stop==101 && live[1].stop==101);
 Check("candle anchor mode records the trail it applied",anchor.m_states[0].current_trail_sl==101 && saved.at(101).current_trail_sl==101);
 SeedShort();Manager anchor_short;
 anchor_short.ManagePositions(94,94.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,0,101);
 Check("candle anchor trails a short down",live[0].stop==101 && live[1].stop==101);
 anchor_short.ManagePositions(94,94.1,1,0,0,0,false,20,0,logger,XSPARK_TRAIL_CANDLE_ANCHOR,0,103);
 Check("a looser candle anchor never widens a short stop",live[0].stop==101 && live[1].stop==101);
 Seed();double all=0,own=0,other=0;int count=0;string reason;
 live.push_back({33,303});live.back().symbol="OTHER";
 Check("exposure includes foreign trades but counts own slots",XSparkReadAccountExposure("TEST",999,all,own,other,count,reason) && all==6 && own==4 && other==2 && count==2);
 live[2].stop=0;
 Check("foreign position without stop blocks account admission",!XSparkReadAccountExposure("TEST",999,all,own,other,count,reason));
}
} // namespace
