#!/usr/bin/env python3
"""Run actual pure MQL logic/fixtures through a small C++ compatibility adapter.

This does NOT compile the EA as MQL5, emulate MT5, or validate broker behaviour.
Only array declaration syntax and platform math/string/time helpers are adapted.
Requires Python 3 and g++; all build output is temporary.
"""
from pathlib import Path
import re
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    "MQL5/Include/XSpark/Strategy/StrategyInterface.mqh",
    "MQL5/Include/XSpark/Strategy/ScoreBotTypes.mqh",
    "MQL5/Include/XSpark/Strategy/PatternDetector.mqh",
    "MQL5/Include/XSpark/Strategy/MarketStructure.mqh",
    "MQL5/Include/XSpark/Strategy/EntryGates.mqh",
    "MQL5/Include/XSpark/Strategy/ChartPatterns.mqh",
    "MQL5/Scripts/Tests/TestMarketStructure.mq5",
    "MQL5/Scripts/Tests/TestChartPatterns.mq5",
]
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
double MathCeil(double a) {return std::ceil(a);}
double MathAbs(double a) {return std::abs(a);}
bool MathIsValidNumber(double a) {return std::isfinite(a);}
template<class T> int ArraySize(const std::vector<T>& a) {return int(a.size());}
template<class T, size_t N> int ArraySize(const T (&)[N]) {return int(N);}
template<class T> void ArrayResize(std::vector<T>& a,int n) {a.resize(n);}
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
    text = re.sub(r'\b(\w+) (\w+)\[\];', r'std::vector<\1> \2;', text)
    return text

with tempfile.TemporaryDirectory(prefix="xspark-logic-") as tmp:
    source = Path(tmp) / 'logic.cpp'
    body = PREAMBLE + '\n'.join(adapt((ROOT / f).read_text()) for f in FILES)
    body += (ROOT / 'tools/portable_mql_stubs.hpp').read_text()
    for file in ['Strategy/ScoringEngine.mqh', 'Core/StateStore.mqh', 'Risk/RiskManager.mqh', 'Strategy/ScoreBotV3.mqh']:
        body += adapt((ROOT / 'MQL5/Include/XSpark' / file).read_text())
    body += (ROOT / 'tools/portable_boundary_tests.hpp').read_text()
    source.write_text(body + '\nint main() { OnStart(); TestBoundaries(); RunChartPatternTests(); Print("TOTAL passed=",g_passed+g_pattern_passed," failed=",g_failed+g_pattern_failed); return g_failed+g_pattern_failed ? 1 : 0; }\n')
    exe = Path(tmp) / 'logic'
    subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic',
                    '-fsanitize=address,undefined', '-g', str(source), '-o', str(exe)], check=True)
    env = dict(os.environ)
    # LeakSanitizer cannot run under the managed runtime's ptrace supervisor.
    env['ASAN_OPTIONS'] = 'detect_leaks=0'
    subprocess.run([str(exe)], check=True, env=env)
