"""Minimal syntax adapter for portable source tests; not an MQL5 compiler."""
import re

PREAMBLE = r'''
#define XSPARK_PORTABLE_TEST
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>
#include <limits>
using string = std::string;
using datetime = long;
enum ENUM_TIMEFRAMES {PERIOD_CURRENT, PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
                     PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_H8, PERIOD_D1};
const double EMPTY_VALUE = std::numeric_limits<double>::max();
template<class A, class B> auto MathMin(A a,B b) {return std::min<double>(a,b);}
template<class A, class B> auto MathMax(A a,B b) {return std::max<double>(a,b);}
double MathSqrt(double a) {return std::sqrt(a);}
double MathCeil(double a) {return std::ceil(a);}
double MathAbs(double a) {return std::abs(a);}
bool MathIsValidNumber(double a) {return std::isfinite(a);}
template<class T> int ArraySize(const std::vector<T>& a) {return int(a.size());}
template<class T, size_t N> int ArraySize(const T (&)[N]) {return int(N);}
template<class T> int ArrayResize(std::vector<T>& a,int n) {a.resize(n); return n;}
inline const char* FmtArg(const string& s) {return s.c_str();}
template<class T> T FmtArg(T x) {return x;}
template<class... T> string StringFormat(const char* f,T... v) {
 int n=std::snprintf(nullptr,0,f,FmtArg(v)...);
 std::vector<char> b(n+1); std::snprintf(b.data(),b.size(),f,FmtArg(v)...); return string(b.data());
}
template<class... T> void Print(T... v) { (std::cout << ... << v) << '\n'; }
'''

def adapt(text):
    text = text.replace('%I64d', '%ld').replace('%I64u', '%lu')
    text = re.sub(r'^\s*#(?:include|property).*$', '', text, flags=re.M)
    text = re.sub(r'\bconst (\w+) &(\w+)\[\]', r'const std::vector<\1> &\2', text)
    text = re.sub(r'\b(\w+) &(\w+)\[\]', r'std::vector<\1> &\2', text)
    text = re.sub(r'\b(\w+)\s+(\w+)\[\];', r'std::vector<\1> \2;', text)
    return text

