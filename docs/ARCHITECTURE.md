# Architecture

XSpark is a native MQL5 Expert Advisor with explicit boundaries between market data, strategy signals, safety, risk, sizing, execution, and position management.

```text
M15/H1 Market Data
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
Trade-state reconciliation
       |
Partial / BE / trailing management
```

## Core Principles

- Strategies cannot execute trades.
- Strategies produce signal data only.
- SafetyManager can veto any new exposure.
- RiskManager can veto any new exposure.
- ExecutionEngine is the new-entry broker execution boundary.
- PositionManager is the XSpark-owned exit/protection-management boundary.
- MT5/broker state is authoritative for live positions and orders.
- Safety-critical behavior fails closed.

## Module Responsibilities

### MarketState

Reads current MT5 symbol data such as bid, ask, spread, server time, digits, and point size. It must use MT5 symbol APIs and must not assume instrument characteristics.

### StrategyInterface / ScoreBotV3

Strategies convert market state into signal data. `ScoreBotV3.mqh` implements the XAUUSD M15 ScoreBot_v3 MAX_SHARPE logic and produces signals plus analysis reports. Strategy modules must not include broker execution APIs or submit orders.

### SafetyManager

Determines whether new trading is allowed at all. Safety rules override strategy rules. Unknown or ambiguous safety state prevents new entries. ScoreBot_v3 safety gates include disabled-trading mode, terminal/account/EA trade permission checks, spread filtering, max XSpark position count, persisted daily drawdown halt, and runtime total drawdown killswitch state.

### RiskManager

Evaluates approved signals against account-level risk rules. ScoreBot_v3 risk tiers are owned here and capped by `InpMaxRiskPct`. No strategy may bypass it.

### PositionSizer

Converts accepted risk, actual stop distance, account balance, and symbol specifications into valid broker volume. It uses symbol-specific MT5 data for volume step, minimum volume, maximum volume, tick size, and tick value. It aborts rather than increasing a below-minimum size to broker minimum.

### ExecutionEngine

The only component that submits new broker entry orders. It validates margin, applies duplicate signal-bar protection, uses broker-aware filling, and inspects/logs trade-server return codes and results.

### PositionManager

Reconciles XSpark-managed broker positions using chart symbol plus configured Magic Number. Existing broker-side positions are the source of truth after restart or crash. It owns partial close, breakeven stop movement, trailing stop movement, weekend close, and killswitch flattening for XSpark-owned exposure only.

## Current Behavior

The EA implements ScoreBot_v3 MAX_SHARPE analysis and production gates. `InpEnableTrading` defaults to false, so the strategy analyzes closed M15 bars and updates the dashboard without sending entries unless trading is deliberately enabled.
