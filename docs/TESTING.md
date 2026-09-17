# Testing

XSpark uses a testing ladder that separates compile success, functional correctness, execution safety, strategy behavior, and profitability analysis.

```text
Static review
    |
MetaEditor compile
    |
MT5 Strategy Tester
    |
Historical testing
    |
Forward/out-of-sample testing
    |
Exness demo
    |
Small live account
    |
Normal deployment
```

## Validation Types

### Compile Validation

MetaEditor compilation confirms that MQL5 source code builds. It does not prove the system is safe, correct, or profitable.

### Functional Validation

Functional tests confirm that modules behave as intended: market state refresh, safety vetoes, risk checks, sizing calculations, execution result handling, and reconciliation.

### Strategy Validation

Strategy validation checks whether signal logic behaves consistently across instruments, time periods, market regimes, and out-of-sample data. Strategy validation must not bypass safety or risk modules.

### Execution Validation

Execution validation checks broker-facing behavior: request construction, filling modes, stop levels, volume normalization, slippage/deviation handling, duplicate protection, and trade-server return codes.

### Profitability Testing

Profitability testing is separate from safety testing. A profitable backtest does not prove a strategy is safe, robust, or suitable for live deployment.

## Final Strategy Testing Expectations

When strategies exist, testing should use realistic spread, commission, swap, execution conditions, and high-quality tick data where practical. Results must be reported honestly, including limitations, assumptions, and conditions that were not tested.

## Phase 0 Testing

Phase 0 has no strategy and no order execution. Validation is limited to repository review, static inspection, include path review, order-submission search, and MetaEditor compile if the compiler is available.

## ScoreBot_v3 Testing

ScoreBot_v3 adds deterministic logic and broker-facing behavior that must be validated separately.

### Deterministic Logic Script

Compile and run:

```text
MQL5/Scripts/Tests/TestScoreBotV3Logic.mq5
```

The script checks pattern detection, pattern priority, zero-range safety, zero-body engulfing denominator safety, session weights, dynamic RR, risk-tier boundaries, final score bounds, ScoreBot point conversion, ScoreBot point size derivation across broker quote conventions, the base/higher timeframe table including its refused periods, and the operating point size decision for gold and non-gold instruments.

The script must print explicit `PASS` and `FAIL` lines plus a final count.

### Execution / State Hardening Script

Compile and run:

```text
MQL5/Scripts/Tests/TestExecutionHardening.mq5
```

The script checks duplicate signal-bar protection, entry-drift tolerance against the configured deviation, protective-stop geometry, risk distance from the execution price, target derivation from the actual risk distance and locked RR, RR bounds, volume recalculation from risk inputs, the price-movement risk revalidation contract, position-identity matching, fail-safe fallback acceptance rules, stale-quote calculations, execution-result state reset, and the entry drift bound (that the gold defaults warn rather than fault, that the gold deviation on an FX pair faults, and that every unusable configuration number fails closed).

It exercises pure helpers only. It does not and cannot simulate broker behaviour: order sends, deal history lookup, live position binding, margin rejection, and flattening retries must be validated in the Strategy Tester and on a demo account.

### Compile Targets

Compile all three:

```text
MQL5/Experts/XSpark/XSpark.mq5
MQL5/Scripts/Tests/TestScoreBotV3Logic.mq5
MQL5/Scripts/Tests/TestExecutionHardening.mq5
```

Target result before merge:

```text
0 errors
0 warnings
```

### Strategy Tester Smoke

When MetaTrader Strategy Tester is available, run a smoke test without tuning:

```text
Symbol: XAUUSD
Timeframe: M15
Model: Every tick based on real ticks
Period: last 6 months
Preset: MAX_SHARPE defaults
```

The historical Python harness suggested approximately 1 to 1.5 trades/day, but this is only a smoke-test prior. It is not a target to optimize toward.

### Execution Hardening Checks That Need MetaTrader

The following cannot be proven outside MT5 and must be checked in the Strategy Tester or on a demo account:

- `DEAL_POSITION_ID` resolution after a confirmed entry, including the retry path when the deal is not yet in the history cache.
- Binding of the resulting live position by `POSITION_IDENTIFIER`, with `InpMaxOpenTrades = 2`.
- The state-recovery path: CRITICAL log, `STATE RECOVERY` status, blocked new entries, and continued protective management.
- Execution-time revalidation against real quote movement, requotes, and broker stop levels.
- Margin rejection at send time with the recomputed volume.
- Killswitch flattening retries, pacing, remaining-exposure reporting, and the single completion log line.
- Broker protection verification: a broker that accepts a market order but does not apply the stop, and the protection-repair retry loop.
- Exit deviation: that XSpark-owned closes and modifications fill at the wider tolerance.

## Dashboard Layout Script

`MQL5/Scripts/Tests/TestDashboardLayout.mq5` covers the chart panel's pure presentation rules: status-to-severity mapping (including that an unmapped status renders as a FAULT rather than as healthy), bar fill in pixels against each component's own maximum, the session tag, panel placement for all four corners including a window smaller than the panel, and reason trimming.

Rendering itself - object creation, fonts, colours, paint order - is NOT covered and must be checked visually on a chart. In particular, confirm on first attach that the panel does not overlap the price scale, that no text is clipped at the panel edge, and that the panel background paints over candles rather than behind them.
- The weekend-close entry block.
- Stale-quote rejection against a real feed, including weekend and rollover behaviour.
