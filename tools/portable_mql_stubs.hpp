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
double MathLog(double x) {return std::log(x);}
double MathCeil(double x) {return std::ceil(x);}
int StringLen(const string& s) {return int(s.size());}
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
