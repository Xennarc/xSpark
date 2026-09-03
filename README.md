# XSpark

XSpark is a safety-first automated trading engine for MetaTrader 5. It is designed to run as a native MQL5 Expert Advisor on an Exness MT5 account, with a strong bias toward reliability, capital protection, deterministic behavior, simple operations, and maintainable code.

This project is under development and is not yet intended for live trading.

## Current Phase

XSpark has implemented its first strategy, ScoreBot_v3 MAX_SHARPE, behind safety-first architecture boundaries.

The EA is still under development and not production-approved. Trading is disabled by default with `InpEnableTrading = false`.

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
ScoreBotV3
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
|   |   `-- XSpark/
|   |       `-- XSpark.mq5
|   |-- Include/
|   |   `-- XSpark/
|   |       |-- Core/
|   |       |   |-- IndicatorCache.mqh
|   |       |   |-- MarketState.mqh
|   |       |   |-- SafetyManager.mqh
|   |       |   |-- StateStore.mqh
|   |       |   |-- SymbolMath.mqh
|   |       |   `-- Logger.mqh
|   |       |-- Strategy/
|   |       |   |-- StrategyInterface.mqh
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
|           `-- TestScoreBotV3Logic.mq5
|-- docs/
|   |-- ARCHITECTURE.md
|   |-- STRATEGY_SCOREBOT_V3.md
|   |-- ROADMAP.md
|   |-- TESTING.md
|   |-- DEPLOYMENT.md
|   `-- DECISIONS.md
`-- .github/
    `-- pull_request_template.md
```

## Development Workflow

1. Make small, reviewable changes.
2. Keep production code in native MQL5 unless a future requirement justifies otherwise.
3. Compile in MetaEditor before considering code complete.
4. Use MT5 Strategy Tester for behavior validation when executable behavior exists.
5. Keep documentation synchronized with architectural changes.

## Testing Philosophy

Compile success proves only that code builds. Functional validation, execution validation, strategy validation, and profitability testing are separate concerns. A profitable backtest does not prove that a strategy is safe or production-ready.

The included MQL5 script `MQL5/Scripts/Tests/TestScoreBotV3Logic.mq5` is intended for deterministic logic validation inside MetaTrader.

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
