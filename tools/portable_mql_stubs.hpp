// Test-only MT5 boundary doubles. Never included in production MQL5.
#include <map>
const double XSPARK_XAUUSD_SCORE_POINT_SIZE = 0.01;
#define XSPARK_SCOREBOT_STRUCTURE_BASE_BARS 160
#define XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS 80
struct MqlDateTime { int year=2026, mon=9, day=18, hour=13, min=0, sec=0; };
void TimeToStruct(datetime time, MqlDateTime& p) {p.hour = int(time / 3600) % 24;}
datetime StructToTime(const MqlDateTime& p) {return p.hour*3600+p.min*60+p.sec;}
datetime TimeTradeServer() {return 47000;}
datetime TimeCurrent() {return 47000;}
double XSparkPriceToScorePoints(double price, double point) {return price/point;}
// Trade-server return codes, with the values MetaTrader documents at
// https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes
// Only the portable build reads these numbers: in MQL5 the names come from the
// terminal. They exist so XSparkCloseRetcodeClass compiles into the fixtures
// and can be driven with the codes a broker actually returns.
const long TRADE_RETCODE_REQUOTE = 10004;
const long TRADE_RETCODE_REJECT = 10006;
const long TRADE_RETCODE_PLACED = 10008;
const long TRADE_RETCODE_DONE = 10009;
const long TRADE_RETCODE_DONE_PARTIAL = 10010;
const long TRADE_RETCODE_ERROR = 10011;
const long TRADE_RETCODE_TIMEOUT = 10012;
const long TRADE_RETCODE_INVALID_STOPS = 10016;
const long TRADE_RETCODE_TRADE_DISABLED = 10017;
const long TRADE_RETCODE_MARKET_CLOSED = 10018;
const long TRADE_RETCODE_NO_MONEY = 10019;
const long TRADE_RETCODE_PRICE_CHANGED = 10020;
const long TRADE_RETCODE_PRICE_OFF = 10021;
const long TRADE_RETCODE_TOO_MANY_REQUESTS = 10024;
const long TRADE_RETCODE_SERVER_DISABLES_AT = 10026;
const long TRADE_RETCODE_CLIENT_DISABLES_AT = 10027;
const long TRADE_RETCODE_LOCKED = 10028;
const long TRADE_RETCODE_FROZEN = 10029;
const long TRADE_RETCODE_CONNECTION = 10031;
const long TRADE_RETCODE_ONLY_REAL = 10032;
const long TRADE_RETCODE_LIMIT_ORDERS = 10033;
const long TRADE_RETCODE_LIMIT_VOLUME = 10034;
const long TRADE_RETCODE_POSITION_CLOSED = 10036;
enum {TIME_DATE=1, TIME_MINUTES=2};
string TimeToString(datetime t, int=0) {return std::to_string(t);}
double MathLog(double x) {return std::log(x);}
int StringLen(const string& s) {return int(s.size());}
int StringFind(const string& s, const string& sub) {auto p=s.find(sub); return p==string::npos?-1:int(p);}
int StringGetCharacter(const string& s,int i) {return s.at(i);}
std::map<string,double> gv;
bool fail_write = false, fail_read = false, fail_cas = false;
bool GlobalVariableCheck(const string& k) {return gv.count(k);}
datetime GlobalVariableSet(const string& k,double v) {if(fail_write) return 0; gv[k]=v; return 1;}
double GlobalVariableGet(const string& k) {return gv.at(k);}
bool GlobalVariableGet(const string& k,double& v) {if(fail_read || !gv.count(k)) return false; v=gv.at(k); return true;}
bool GlobalVariableDel(const string& k) {return gv.erase(k);}
bool GlobalVariableSetOnCondition(const string& k,double value,double previous) {
 if(fail_cas || fail_write || !gv.count(k) || gv.at(k)!=previous) return false;
 gv[k]=value; return true;
}
void GlobalVariablesFlush() {}
class CXSparkMarketState {public: double Ask() {return 100.3;} double Bid() {return 100.2;} };
// Mirrors IndicatorCache.mqh. The real header is not in the portable FILES
// list because it calls CopyRates and indicator handles, so the one constant
// strategies read from it is restated here.
// Minimal symbol-info double for strategies that read the instrument directly.
// Only the properties a strategy may legitimately need are answered.
#ifndef XSPARK_PORTABLE_SYMBOL_INFO
#define XSPARK_PORTABLE_SYMBOL_INFO
enum ENUM_SYMBOL_INFO_DOUBLE_PORTABLE { SYMBOL_POINT = 1 };
inline double SymbolInfoDouble(const string&, int property) {
 if(property == SYMBOL_POINT) return 0.01;
 return 0.0;
}
#endif

#ifndef XSPARK_SCOREBOT_CLOSED_BASE_BARS
#define XSPARK_SCOREBOT_CLOSED_BASE_BARS 50
#endif
class CXSparkIndicatorCache {
public:
 std::vector<XSparkCandle> base, structure_base, structure_higher;
 double rsi=45, previous=44;
 bool valid=true, structure_ready=false;
 bool IsValid() {return valid;}
 string LastReason() {return "mock cache invalid";}
 bool BaseBar(int shift, XSparkCandle& bar) {
  if(shift<1 || shift>int(base.size())) return false;
  bar=base[shift-1]; return true;
 }
 bool StructureIsValid() {return structure_ready;}
 bool StructureBaseBar(int shift, XSparkCandle& bar) {
  if(shift<1 || shift>int(structure_base.size())) return false;
  bar=structure_base[shift-1]; return true;
 }
 bool StructureHigherBar(int shift, XSparkCandle& bar) {
  if(shift<1 || shift>int(structure_higher.size())) return false;
  bar=structure_higher[shift-1]; return true;
 }
 double RSI14Base() {return rsi;}
 double RSI14BaseAt(int) {return previous;}
 double RSI14Higher() {return 42;}
 double ATR14Base() {return 1;}
 double ATR50Base() {return 1;}
 double EMA21Base() {return 100;}
 double EMA50Base() {return 99;}
 double EMA50Higher() {return 99;}
};
