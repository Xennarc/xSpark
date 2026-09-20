# XSpark

XSpark is a safety-first automated trading engine for MetaTrader 5. It is designed to run as a native MQL5 Expert Advisor on an Exness MT5 account, with a strong bias toward reliability, capital protection, deterministic behavior, simple operations, and maintainable code.

This project is under development and is not yet intended for live trading.

## Current Phase

XSpark has implemented its first strategy, ScoreBot_v3 MAX_SHARPE, behind safety-first architecture boundaries.

A second strategy, [CandleFlow](docs/STRATEGY_CANDLEFLOW.md), ships as a separate
Expert Advisor (`XSparkFlow.mq5`) that reuses the same safety, risk, execution,
position-management and dashboard components. It is a single-factor rule: the
direction of the closed candle, a stop that re-anchors to each later candle's far
wick, and a configurable ladder of partial take-profits that banks part of the
trade at fixed distances while the rest runs on that stop. Both EAs can run on
one account under different Magic Numbers. CandleFlow is untested and unvalidated
for profitability.

Further strategies ship the same way - one Expert Advisor each, one Magic Number
each, shared components untouched: `XSparkScalp.mq5` (TrendScalp),
`XSparkICT.mq5` (a mechanized ICT liquidity model) and
[`XSparkSMC.mq5`](docs/STRATEGY_SMC.md) (Smart Money Concepts). XSparkSMC
rebuilds a published Pine indicator's market structure, order blocks, equal
highs and lows, fair value gaps and premium/discount range from a fixed window
of closed bars on every candle, then enters with a limit order at the midpoint
of the order block a structure break left behind - stopping beyond that block's
far edge, which is exactly where the indicator itself deletes the block, and
targeting the draw on liquidity. Every one of these is untested and unvalidated
for profitability, and all of them are off by default.

The EA is still under development and not production-approved. Trading is disabled by default with `InpEnableTrading = false`.

See the [live chart dashboard](docs/DASHBOARD.md) for the visual console, status
messages, display settings and validation limits.

## Purpose

The long-term goal is a production-grade MT5 Expert Advisor that can operate continuously during forex market hours while remaining simple enough for one retail trader to understand, test, deploy, and maintain.

## Architecture Summary

XSpark separates responsibilities so future strategy logic cannot bypass safety and risk controls:

```text
MT5 Market Data
       |
MarketState / IndicatorCache
       |
StrategyInterface
       |
ScoreBotV3 / CandleFlow / TrendScalp / ICTLiquidity / SmartMoney
       |
TradeSignal
       |
SafetyManager
       |
RiskManager
       |
PositionSizer
       |
ExecutionEngine
       |
MT5 / Exness

Existing positions
       |
PositionManager
       |
Partial / BE / trailing management
```

Strategies produce signals only. SafetyManager and RiskManager can veto execution. ExecutionEngine is the new-entry broker boundary, while PositionManager owns XSpark-only exits and protection changes. MT5 broker state is authoritative for live exposure.

## Repository Structure

```text
xspark-mt5/
|-- AGENTS.md
|-- README.md
|-- .gitignore
|-- MQL5/
|   |-- Experts/
|   |   |-- XSpark/
|   |   |   `-- XSpark.mq5
|   |   |-- XSparkFlow/
|   |   |   `-- XSparkFlow.mq5
|   |   |-- XSparkScalp/
|   |   |   `-- XSparkScalp.mq5
|   |   |-- XSparkICT/
|   |   |   `-- XSparkICT.mq5
|   |   `-- XSparkSMC/
|   |       `-- XSparkSMC.mq5
|   |-- Include/
|   |   `-- XSpark/
|   |       |-- Core/
|   |       |   |-- ExecutionMath.mqh
|   |       |   |-- IndicatorCache.mqh
|   |       |   |-- MarketState.mqh
|   |       |   |-- SafetyManager.mqh
|   |       |   |-- StateStore.mqh
|   |       |   |-- SymbolMath.mqh
|   |       |   `-- Logger.mqh
|   |       |-- Strategy/
|   |       |   |-- StrategyInterface.mqh
|   |       |   |-- CandleFlow.mqh
|   |       |   |-- ICTLiquidity.mqh
|   |       |   |-- SmartMoney.mqh
|   |       |   |-- TrendScalp.mqh
|   |       |   |-- ScoreBotV3.mqh
|   |       |   |-- PatternDetector.mqh
|   |       |   |-- ScoringEngine.mqh
|   |       |   `-- ScoreBotTypes.mqh
|   |       |-- Risk/
|   |       |   |-- RiskManager.mqh
|   |       |   `-- PositionSizer.mqh
|   |       |-- Execution/
|   |       |   `-- ExecutionEngine.mqh
|   |       |-- Trade/
|   |       |   |-- PositionManager.mqh
|   |       |   `-- TradeState.mqh
|   |       `-- UI/
|   |           `-- Dashboard.mqh
|   `-- Scripts/
|       `-- Tests/
|           |-- TestExecutionHardening.mq5
|           |-- TestSmartMoney.mq5
|           `-- TestScoreBotV3Logic.mq5
|-- docs/
|   |-- ARCHITECTURE.md
|   |-- STRATEGY_SCOREBOT_V3.md
|   |-- STRATEGY_CANDLEFLOW.md
|   |-- STRATEGY_SMC.md
|   |-- ROADMAP.md
|   |-- TESTING.md
|   |-- DEPLOYMENT.md
|   `-- DECISIONS.md
`-- .github/
    `-- pull_request_template.md
```

## V2 experimental entry work

The structure/pullback/continuation entry path is implemented behind default-off
switches, with observe-only mode enabled by default. It has not been compiled
in MetaEditor or tested for profitability. See
[implementation status and terminal validation](docs/V2_IMPLEMENTATION.md).
Run `python3 tools/test_portable_logic.py` for portable logic checks; this is not
an MQL5 compiler. `tools/compile_mt5.ps1` verifies native builds on Windows using
an installed MetaEditor without deploying them.

The new [chart-pattern and engulfing-first profile](docs/CHART_PATTERNS.md) recognizes
flags, head and shoulders, and cup/handle formations in both directions. Pin bars
are off in that profile. Use its explicit Strategy Tester presets to activate it;
shipped defaults still execute the legacy logic. Profitability remains unverified.

For the simplified Inputs layout and one-dropdown entry selection, see
[the settings guide](docs/INPUT_SETTINGS.md). Existing `.set` identifiers and
defaults are preserved.

The [multiple-trade guide](docs/MULTIPLE_TRADES.md) explains the 1–10 slot limit,
automatic risk allocation and independent position management.

## Development Workflow

1. Make small, reviewable changes.
2. Keep production code in native MQL5 unless a future requirement justifies otherwise.
3. Compile in MetaEditor before considering code complete.
4. Use MT5 Strategy Tester for behavior validation when executable behavior exists.
5. Keep documentation synchronized with architectural changes.

## Testing Philosophy

Compile success proves only that code builds. Functional validation, execution validation, strategy validation, and profitability testing are separate concerns. A profitable backtest does not prove that a strategy is safe or production-ready.

The included MQL5 scripts under `MQL5/Scripts/Tests/` - among them `TestScoreBotV3Logic.mq5`, `TestExecutionHardening.mq5` and `TestSmartMoney.mq5` - are intended for deterministic logic validation inside MetaTrader. They cover pure calculations only; broker behaviour must be validated in the Strategy Tester and on a demo account.

## Deployment Target

The intended production target is:

```text
Exness VPS
|
Windows
|
MetaTrader 5
|
XSpark.ex5
|
Exness trading server
```

The VPS is production infrastructure, not the primary development environment. Passwords, account numbers, API keys, and other secrets must never be committed.
