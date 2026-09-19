#include <map>
#include <sstream>
template<class... T> void PrintFormat(const char* f,T... v) {Print(StringFormat(f,v...));}
double MathPow(double a,double b){return std::pow(a,b);}
#include <iomanip>
#include <cctype>
using color = long;
const int CORNER_LEFT_UPPER=0,CORNER_LEFT_LOWER=1,CORNER_RIGHT_LOWER=2,CORNER_RIGHT_UPPER=3;
enum {OBJ_RECTANGLE_LABEL=10,OBJ_LABEL,OBJ_BUTTON,OBJ_TEXT,OBJ_HLINE,OBJ_ARROW,
 OBJPROP_CORNER,OBJPROP_BACK,OBJPROP_SELECTABLE,OBJPROP_SELECTED,OBJPROP_HIDDEN,OBJPROP_BORDER_TYPE,
 OBJPROP_XDISTANCE,OBJPROP_YDISTANCE,OBJPROP_XSIZE,OBJPROP_YSIZE,OBJPROP_BGCOLOR,OBJPROP_COLOR,
 OBJPROP_ANCHOR,OBJPROP_FONTSIZE,OBJPROP_TEXT,OBJPROP_FONT,OBJPROP_TOOLTIP,OBJPROP_TIMEFRAMES,
 OBJPROP_STATE,OBJPROP_BORDER_COLOR,OBJPROP_ZORDER,OBJPROP_PRICE,OBJPROP_STYLE,OBJPROP_ARROWCODE,OBJPROP_WIDTH,
 BORDER_FLAT,ANCHOR_RIGHT_UPPER,ANCHOR_LEFT_UPPER,OBJ_ALL_PERIODS,OBJ_NO_PERIODS,
 CHARTEVENT_OBJECT_CLICK,CHARTEVENT_CHART_CHANGE,CHART_WIDTH_IN_PIXELS,CHART_HEIGHT_IN_PIXELS,
 MQL_TESTER,MQL_VISUAL_MODE,SYMBOL_DIGITS,STYLE_DOT,TIME_MINUTES};
int StringLen(const string& s) {return int(s.size());}
int StringFind(const string& s,const string& q) {auto p=s.find(q);return p==string::npos?-1:int(p);}
string StringSubstr(const string& s,int p,int n=-1) {return p>=int(s.size())?"":s.substr(p,n<0?string::npos:size_t(n));}
void StringToLower(string& s) {for(auto& c:s)c=char(std::tolower(static_cast<unsigned char>(c)));}
void StringReplace(string& s,const string& a,const string& b) {size_t p=0;while((p=s.find(a,p))!=string::npos){s.replace(p,a.size(),b);p+=b.size();}}
double MathRound(double v){return std::round(v);}
string DoubleToString(double v,int d){return StringFormat("%.*f",d,v);}
string TimeToString(datetime,int){return "14:30";}
struct Object {int type;string name;std::map<int,long> integers;std::map<int,string> strings;};
std::vector<Object> objects;
int ObjectFind(int,const string& n){for(int i=0;i<int(objects.size());i++)if(objects[i].name==n)return i;return -1;}
bool ObjectCreate(int,const string& n,int type,int,long,double){if(ObjectFind(0,n)<0)objects.push_back({type,n,{},{}});return true;}
void ObjectSetInteger(int,const string& n,int p,long v){int i=ObjectFind(0,n);if(i>=0)objects[i].integers[p]=v;}
void ObjectSetString(int,const string& n,int p,const string& v){int i=ObjectFind(0,n);if(i>=0)objects[i].strings[p]=v;}
void ObjectSetDouble(int,const string&,int,double){}
void ObjectMove(int,const string&,int,datetime,double){}
int ObjectsTotal(int){return int(objects.size());}
string ObjectName(int,int i){return objects.at(i).name;}
void ObjectDelete(int,const string& n){int i=ObjectFind(0,n);if(i>=0)objects.erase(objects.begin()+i);}
void ChartRedraw(int){}
int chart_width=1200,chart_height=800;
long ChartGetInteger(int,int p){return p==CHART_WIDTH_IN_PIXELS?chart_width:chart_height;}
long SymbolInfoInteger(const string&,int){return 2;}
bool tester=false,visual=true;
long MQLInfoInteger(int p){return p==MQL_TESTER?tester:visual;}
ulong clock_ms=1000;
ulong GetTickCount64(){return clock_ms;}
class CXSparkSafetyManager {public:
 double TotalDDPct(){return 2.4;} double MaxTotalDDPct(){return 25;}
 double DailyDDPct(){return 0.8;} double MaxDailyDDPct(){return 15;}
 int MaxQuoteAgeSeconds(){return 15;}
};
// Machine-readable scene produced by the actual Dashboard.Update draw calls.
void DumpScene(const string& scene){
 std::cout<<"SCENE "<<scene<<"\n";
 for(auto& o:objects){
  if(o.integers.count(OBJPROP_TIMEFRAMES)&&o.integers[OBJPROP_TIMEFRAMES]==OBJ_NO_PERIODS)continue;
  std::cout<<"OBJECT "<<o.type<<" "<<o.integers[OBJPROP_XDISTANCE]<<" "<<o.integers[OBJPROP_YDISTANCE]<<" "
   <<o.integers[OBJPROP_XSIZE]<<" "<<o.integers[OBJPROP_YSIZE]<<" "<<o.integers[OBJPROP_BGCOLOR]<<" "
   <<o.integers[OBJPROP_COLOR]<<" "<<o.integers[OBJPROP_FONTSIZE]<<" "
   <<(o.integers[OBJPROP_ANCHOR]==ANCHOR_RIGHT_UPPER)<<" "<<std::quoted(o.strings[OBJPROP_FONT])<<" "
   <<std::quoted(o.strings[OBJPROP_TEXT])<<" "<<std::quoted(o.name)<<"\n";
 }
}
