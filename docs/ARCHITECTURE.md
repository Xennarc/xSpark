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

Determines whether new trading is allowed at all. Safety rules override strategy rules. Unknown or ambiguous safety state prevents new entries. ScoreBot_v3 safety gates include disabled-trading mode, terminal/account/EA trade permission checks, spread filtering, stale/invalid quote rejection, max XSpark position count, persisted daily drawdown halt, runtime total drawdown killswitch state, and a state-recovery latch raised when a confirmed entry could not be registered in managed state.

### RiskManager

Evaluates approved signals against account-level risk rules. ScoreBot_v3 risk tiers are owned here and capped by `InpMaxRiskPct`. No strategy may bypass it.

### PositionSizer

Converts accepted risk, actual stop distance, account balance, and symbol specifications into valid broker volume. It uses symbol-specific MT5 data for volume step, minimum volume, maximum volume, tick size, and tick value. It aborts rather than increasing a below-minimum size to broker minimum. The sizing arithmetic lives in the pure helper `XSparkVolumeFromRiskInputs`, so execution-time re-sizing can be tested deterministically.

### ExecutionEngine

The only component that submits new broker entry orders. It validates margin, applies duplicate signal-bar protection, uses broker-aware filling, and inspects/logs trade-server return codes and results.

Immediately before every order send it revalidates the whole risk chain against the current broker quote: entry-drift tolerance, the locked ATR stop, broker stop-level rules, actual stop distance, volume, target from the locked dynamic RR, RR bounds, and margin. The theoretical ATR stop is never moved to keep the planned lot size; the volume adapts so monetary risk stays at the selected risk percentage. An entry that cannot be executed inside the configured deviation, or whose configured RR cannot be preserved, is aborted rather than chased.

After a confirmed entry it resolves the exact broker position from `CTrade::ResultDeal()` and `DEAL_POSITION_ID`, and records order ticket, deal ticket, position id, live position ticket, fill price, fill volume, fill time, submitted values, actual risk distance, actual RR, retcode, and retcode description in `XSparkExecutionResult`.

### PositionManager

Reconciles XSpark-managed broker positions using chart symbol plus configured Magic Number. Existing broker-side positions are the source of truth after restart or crash. It owns partial close, breakeven stop movement, trailing stop movement, weekend close, and killswitch flattening for XSpark-owned exposure only.

New trade state is bound to the exact broker position id supplied by the execution result. A same-direction match exists only as a documented fail-safe fallback for the case where the broker deal exposes no position id; it does not use newest-open-time, and it refuses any candidate that is already tracked, has the wrong direction, opened before the send, or whose executed volume does not match. A position that already existed before the send is refused outright, so a netting-mode merge can never overwrite the state of a trade that is already being managed. Anything other than an exact bind is reported as a registration failure so the EA can recover deliberately.

A confirmed retcode proves the order was accepted, not that the broker applied the protection sent with it. Registration reads the live `POSITION_SL`, applies the submitted stop immediately when the broker left the position unprotected, and reports a registration failure while any stop is still missing. Every management pass re-attempts protection repair for XSpark positions found without a broker stop.

Exit operations use a wider deviation than entries: closing a position at a slightly worse price is always better than failing to close it.

Flattening keeps retrying until no XSpark exposure remains and never touches another symbol or Magic Number. The campaign is keyed on the exposure rather than on the caller, so an overlapping killswitch and weekend close cannot restart each other. Broker retries and log output are paced so a latched killswitch surfaces remaining exposure without emitting identical CRITICAL lines on every tick.

### ExecutionMath

`Core/ExecutionMath.mqh` holds the pure, broker-independent predicates shared by the execution boundary, the position-identity boundary, and the stale-quote gate: duplicate signal-bar protection, entry-drift tolerance, protective-stop side checks, risk distance, target from risk distance, realized RR, RR bounds, position identity matching, fail-safe fallback acceptance, and quote-age evaluation. Keeping them pure is what makes them testable without a trade server.

## State Recovery

Broker execution is authoritative. When an entry is confirmed but XSpark cannot bind the resulting position exactly, the EA logs CRITICAL, latches SafetyManager, reconciles against MT5, and verifies that managed state represents every live XSpark position.

```text
Confirmed execution
       |
RegisterNewTrade (exact broker position id)
       |
   bound? -- yes --> MANAGING
       |
       no
       |
CRITICAL + SafetyManager state-recovery latch
       |
PositionManager.Reconcile
       |
Managed state covers live positions,
with matching direction, a broker stop,
and ownership of this entry's signal bar?
       |
   yes --> latch cleared, entries allowed again
   no  --> STATE RECOVERY: new entries blocked, protection continues
```

## Current Behavior

The EA implements ScoreBot_v3 MAX_SHARPE analysis and production gates. `InpEnableTrading` defaults to false, so the strategy analyzes closed M15 bars and updates the dashboard without sending entries unless trading is deliberately enabled.
