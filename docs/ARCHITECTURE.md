# Architecture

XSpark is a native MQL5 Expert Advisor with explicit boundaries between market data, strategy signals, safety, risk, sizing, execution, and position management.

```text
MT5 Market Data
       |
MarketState
       |
Strategy
       |
Signal
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
```

## Core Principles

- Strategies cannot execute trades.
- Strategies produce signal data only.
- SafetyManager can veto any new exposure.
- RiskManager can veto any new exposure.
- ExecutionEngine is the future broker execution boundary.
- MT5/broker state is authoritative for live positions and orders.
- Safety-critical behavior fails closed.

## Module Responsibilities

### MarketState

Reads current MT5 symbol data such as bid, ask, spread, server time, digits, and point size. It must use MT5 symbol APIs and must not assume instrument characteristics.

### Strategy

Future strategies will convert market state into a signal: none, buy, or sell. Strategy modules must not include broker execution APIs or submit orders.

### SafetyManager

Determines whether new trading is allowed at all. Safety rules override strategy rules. Unknown or ambiguous safety state prevents new entries.

### RiskManager

Evaluates approved signals against account-level and exposure-level risk rules. No strategy may bypass it.

### PositionSizer

Converts accepted risk, stop distance, and symbol specifications into valid broker volume. It must use symbol-specific MT5 data for volume step, minimum volume, maximum volume, tick value, and related constraints.

### ExecutionEngine

The only component that may eventually submit broker orders. Future execution must inspect and log trade-server return codes and results.

### PositionManager

Reconciles XSpark-managed broker positions using the configured Magic Number. Existing broker-side positions are the source of truth after restart or crash.

## Phase 0 Behavior

Phase 0 initializes the EA shell, logging, market state, and module skeletons. It accepts ticks and performs no trading.
