#!/usr/bin/env python3
"""Run MQL logic and selected position methods through a C++ compatibility adapter.

This does NOT compile the EA as MQL5, emulate MT5, or validate broker behaviour.
Array syntax is adapted; platform/broker calls use explicit test doubles.
Requires Python 3 and g++; all build output is temporary.
"""
from pathlib import Path
import re
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    "MQL5/Include/XSpark/Core/StrategyIdentity.mqh",
    "MQL5/Include/XSpark/Strategy/StrategyInterface.mqh",
    "MQL5/Include/XSpark/Trade/TrailingStop.mqh",
    "MQL5/Include/XSpark/Strategy/ScoreBotTypes.mqh",
    "MQL5/Include/XSpark/Strategy/PatternDetector.mqh",
    "MQL5/Include/XSpark/Strategy/MarketStructure.mqh",
    "MQL5/Include/XSpark/Strategy/EntryGates.mqh",
    "MQL5/Include/XSpark/Strategy/ChartPatterns.mqh",
    "MQL5/Include/XSpark/Strategy/EntrySettings.mqh",
    "MQL5/Scripts/Tests/TestMarketStructure.mq5",
    "MQL5/Scripts/Tests/TestChartPatterns.mq5",
    "MQL5/Scripts/Tests/TestEntrySettings.mq5",
]
from mql_adapter import PREAMBLE, adapt

with tempfile.TemporaryDirectory(prefix="xspark-logic-") as tmp:
    source = Path(tmp) / 'logic.cpp'
    body = PREAMBLE + '\n'.join(adapt((ROOT / f).read_text()) for f in FILES)
    body += (ROOT / 'tools/portable_mql_stubs.hpp').read_text()
    for file in ['Strategy/ScoringEngine.mqh', 'Core/StateStore.mqh', 'Risk/RiskManager.mqh', 'Strategy/ScoreBotV3.mqh',
                 'Strategy/CandleFlow.mqh']:
        body += adapt((ROOT / 'MQL5/Include/XSpark' / file).read_text())
    body += adapt((ROOT / 'MQL5/Scripts/Tests/TestConcurrentRisk.mq5').read_text())
    body += adapt((ROOT / 'MQL5/Scripts/Tests/TestCandleFlow.mq5').read_text())
    body += adapt((ROOT / 'MQL5/Scripts/Tests/TestStrategyIdentity.mq5').read_text())
    body += adapt((ROOT / 'MQL5/Scripts/Tests/TestTrailingStop.mq5').read_text())
    body += (ROOT / 'tools/portable_boundary_tests.hpp').read_text()
    # Compile actual reconciliation/management methods with isolated broker doubles.
    manager = (ROOT / 'MQL5/Include/XSpark/Trade/PositionManager.mqh').read_text()
    methods = []
    for name in ['FindStateByTicket', 'FindStateByIdentifier', 'PositionMatchesInstance',
                 'PositionDirection', 'AddOrUpdateSelectedPosition', 'CountUnmanagedStates',
                 'CountMatchingLivePositions', 'FindLiveTicketByIdentifier', 'Reconcile', 'ManagePositions',
                 'SetTrailPlan']:
        match = re.search(r'^   (?:int|bool|void|EXSparkSignalDirection) ' + name + r'\(', manager, re.M)
        if not match:
            raise RuntimeError('Missing production method: ' + name)
        end = manager.index('\n   }', match.start()) + len('\n   }')
        methods.append(adapt(manager[match.start():end]))
    position_tests = (ROOT / 'tools/portable_position_tests.hpp').read_text()
    execution_math = (ROOT / 'MQL5/Include/XSpark/Core/ExecutionMath.mqh').read_text()
    identity_start = execution_math.index('bool XSparkPositionIdentityMatches(')
    identity_end = execution_math.index('\n}', identity_start) + 2
    position_tests = position_tests.replace('// IDENTITY_SOURCE', adapt(execution_math[identity_start:identity_end]))
    safety = (ROOT / 'MQL5/Include/XSpark/Core/SafetyManager.mqh').read_text()
    unopposed_start = safety.index('bool XSparkDirectionIsUnopposed(')
    unopposed_end = safety.index('\n}', unopposed_start) + 2
    position_tests = position_tests.replace('// UNOPPOSED_SOURCE', adapt(safety[unopposed_start:unopposed_end]))
    for marker, value in [('// PRODUCTION_METHODS', '\n'.join(methods)),
                          ('// TRADE_STATE_SOURCE', adapt((ROOT / 'MQL5/Include/XSpark/Trade/TradeState.mqh').read_text())),
                          ('// ACCOUNT_EXPOSURE_SOURCE', adapt((ROOT / 'MQL5/Include/XSpark/Risk/AccountExposure.mqh').read_text()))]:
        position_tests = position_tests.replace(marker, value)
    body += position_tests
    source.write_text(body + '\nint main() { OnStart(); TestBoundaries(); RunChartPatternTests(); RunEntrySettingsTests(); MultiPositionTests::Run(); RunConcurrentRiskTests(); RunCandleFlowTests(); RunStrategyIdentityTests(); RunTrailingStopTests(); Print("TOTAL passed=",g_passed+g_pattern_passed+g_settings_passed+g_concurrent_passed+g_flow_passed+g_identity_passed+g_trail_passed," failed=",g_failed+g_pattern_failed+g_settings_failed+g_concurrent_failed+g_flow_failed+g_identity_failed+g_trail_failed); return g_failed+g_pattern_failed+g_settings_failed+g_concurrent_failed+g_flow_failed+g_identity_failed+g_trail_failed ? 1 : 0; }\n')
    exe = Path(tmp) / 'logic'
    subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic',
                    '-fsanitize=address,undefined', '-g', str(source), '-o', str(exe)], check=True)
    env = dict(os.environ)
    # LeakSanitizer cannot run under the managed runtime's ptrace supervisor.
    env['ASAN_OPTIONS'] = 'detect_leaks=0'
    subprocess.run([str(exe)], check=True, env=env)
