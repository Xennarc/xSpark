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
