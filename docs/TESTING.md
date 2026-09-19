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

Compile both Expert Advisors and the test scripts:

```text
MQL5/Experts/XSpark/XSpark.mq5
MQL5/Experts/XSparkFlow/XSparkFlow.mq5
MQL5/Scripts/Tests/TestScoreBotV3Logic.mq5
MQL5/Scripts/Tests/TestExecutionHardening.mq5
MQL5/Scripts/Tests/TestCandleFlow.mq5
MQL5/Scripts/Tests/TestStrategyIdentity.mq5
```

`tools/compile_mt5.ps1` compiles both EAs and every script under
`MQL5/Scripts/Tests`.

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

## Auto-Tune Script

`MQL5/Scripts/Tests/TestAutoTune.mq5` covers deriving the instrument-scaled thresholds: median robustness against a volatility spike and against the unset values `CopyBuffer` returns at the edge of history, the gold-shaped case reproducing the shipped 80/800/30 exactly, the EURUSD-shaped case that motivated the change, scale invariance across a 1000x range, that a derived entry slippage is never an inert drift gate, and every unusable input failing closed.

Reading real ATR history, and whether the derived numbers actually produce trades on a given symbol, are Strategy Tester questions and are NOT covered here.

## Dashboard Layout Script

The `ManagePositions` fixtures in `tools/portable_position_tests.hpp` also cover `XSparkDirectionIsUnopposed`, which is what stops either strategy from opening a trade against a position it already holds: that a held long admits another long but refuses a short and vice versa, that a flat bot may take either side, that another bot's or another symbol's opposite position is not this bot's exposure, and that an unreadable position refuses rather than assuming flat.

`python3 tools/check_ea_inputs.py` enforces per-strategy input isolation across every Expert Advisor: that no input identifier is declared by two EAs, that every declared input is actually read by its own EA, that each EA's Magic Number default comes from the `StrategyIdentity` registry, and that no EA takes a default from another strategy's constants. It is source analysis, not a compiler, and it runs in CI ahead of the logic suites. `MQL5/Scripts/Tests/TestStrategyIdentity.mq5` covers the registry itself: that the shipped Magic Numbers differ, that each strategy accepts its own and refuses the other's by name, that zero is refused, and that an operator's own unclaimed number stays usable on any strategy.

`MQL5/Scripts/Tests/TestCandleFlow.mq5` covers the CandleFlow rules: candle direction including the doji and body-filter cases, the three-component wick buffer, the anchor arithmetic in both directions, and the stop floor and ceiling - including a price that has already moved through the anchor, which the floor rescues and which refuses outright when no floor is configured. The one-way ratchet itself is covered by the `ManagePositions` fixtures in `tools/portable_position_tests.hpp`, long and short, together with the case where a missing anchor must leave the broker stop untouched.

`MQL5/Scripts/Tests/TestDashboardLayout.mq5` covers the chart panel's pure presentation rules: status-to-severity mapping (including that an unmapped status renders as a FAULT rather than as healthy), bar fill in pixels against each component's own maximum, the session tag, panel placement for all four corners including a window smaller than the panel, and reason trimming.

`TestDashboardExperience.mq5` additionally checks readable notices, configuration
versus waiting states, countdown boundaries and wrapping. The portable runner
`python3 tools/test_dashboard.py` runs both scripts and production drawing methods
with chart-object doubles (145 assertions). It checks object reuse, throttling,
compact toggling, stale feeds, position rows, cleanup and readable logger output.
Font doubles exercise 100–300% display scaling, narrow charts, font substitution,
incorrect reported DPI, label overlap, empty-field visibility and metric failure
recovery. Checks also require readable point sizes, panel growth on high-DPI
displays, immediate +/− resizing and bounded size preferences. See
`DashboardText.mqh` for the native measurement adapter.
The existing trading logic runner has 151 assertions. Both run in CI.

Native rendering, fonts, colours and paint order are NOT validated by these
doubles and must be checked visually on a chart. See [dashboard acceptance](DASHBOARD.md#validation). In particular, confirm on first attach that the panel does not overlap the price scale, that no text is clipped at the panel edge, and that the panel background paints over candles rather than behind them.
- The weekend-close entry block.
- Stale-quote rejection against a real feed, including weekend and rollover behaviour.

## V2 entry validation

See [V2_IMPLEMENTATION.md](V2_IMPLEMENTATION.md) for the stage matrix, portable
logic checks, Windows compile helper, observe-mode control, persistence tests
and outstanding MT5 acceptance sequence. Portable test success is not a native
compiler result or a profitability result.

## Backtest conventions: the drawdown killswitch

`InpUseTotalDDKillSwitch=false` in a Strategy Tester report is a **deliberate
testing choice, not a misconfiguration and not a bug.** The killswitch latches
permanently once total drawdown crosses `InpMaxTotalDDPct`, which ends the run
early and truncates the sample. Long-horizon tests are run with it off so the
strategy is measured over the full period rather than up to its first deep
drawdown. The mechanism itself is verified separately and works as designed.

When reading a report, keep the two apart:

- **Test runs.** The killswitch may legitimately be off. Treat the drawdown
  figures as the strategy's unmanaged drawdown - that is the point of the run.
  A 99% drawdown in such a report describes the sizing, not a broken rail.
- **Live and preset defaults.** The killswitch stays on. Every shipped preset in
  `presets/` sets `InpUseTotalDDKillSwitch=true`, and the EA's own default is
  `true`.

Do not "fix" a test preset by re-arming the killswitch, and do not read its
absence in a report as evidence of a defect. Equally, do not carry a test
preset's killswitch setting into a live preset.

Related: `OnInit` logs how many consecutive full-stop rounds latch the killswitch
at the configured risk, and warns when that count falls below
`XSPARK_MIN_LOSS_STREAK_TOLERANCE`. That warning is a sizing signal and is worth
reading even on runs where the killswitch is disabled.
