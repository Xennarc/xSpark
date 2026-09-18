# Chart recognition and engulfing-first profile

This experimental profile adds actual closed-bar recognition for bull/bear flags,
head and shoulders/inverse head and shoulders, and cup and handle/inverse cup and
handle. It addresses missing pattern recognition, not demonstrated profitability.
Thresholds are initial research definitions, not optimized parameters. Engulfing
priority implements the requested strategy preference; its net edge remains unmeasured.

## Activate the intended experiment

Merging this code alone does **not** change the entry profile. The shipped defaults
scan chart patterns but preserve legacy entries, including legacy pin bars.
`InpUsePinBars=false` applies to the **new** profile only.

1. Compile with MetaEditor using `tools/compile_mt5.ps1` and run the native tests.
2. In **Strategy Tester**, load your baseline settings first, then
   [`tester-pattern-active.set`](../presets/tester-pattern-active.set).
   This partial preset enables simulated trading and switches the new engine on.
   It retains all unspecified settings, including risk, RSI, sessions, stop/target,
   spread limits and sizing. Export the resulting **full** `.set` for reproducibility.
   Do not load these tester presets on a live chart.
3. Confirm the journal says `PATTERN ENTRY PROFILE ACTIVE` at startup and
   `mode=PATTERN ENTRIES ACTIVE` in per-bar `Patterns` records. Configuration faults
   block new entries while existing positions remain managed.
4. For a paired legacy control, use
   [`tester-pattern-observe.set`](../presets/tester-pattern-observe.set) with the same
   data and full settings. It logs the new candidates but executes legacy entries;
   the journal explicitly says `OBSERVE / LEGACY ENTRIES`.

You can also choose **Entry style → Chart patterns and engulfing entries** in
the Inputs tab; it resolves the five entry switches together. See the
[settings guide](INPUT_SETTINGS.md) for labels, units and saved-file behavior.

Equivalent active inputs with **Use saved / custom entry switches** selected: `InpUsePatternEngine=true`,
`InpGateObserveOnly=false`, `InpUseHTFStructureGate=true`,
`InpUsePullbackGate=true`, `InpUseContinuationTriggers=true`.
Flags, H&S and cups have independent recognition switches. Pin bars default off;
if enabled they receive a reduced pattern score of 1 and require a dominant wick.

## Detection rules

All detectors use completed candles only. Both bullish and bearish forms use
mirrored geometry, not separate ad hoc thresholds. Existing market-data validation
must succeed before scanning. Insufficient/invalid structure data is logged as
unavailable, not as evidence that no pattern exists.

| Detector | Implemented conditions |
| --- | --- |
| Strong engulfing | Opposite candle colors; inclusive body coverage (equal adjoining open/close allowed); previous body at least 0.15 ATR, current body at least 0.50 ATR and larger; close in directional outer 35% of range; range no more than 3 ATR. |
| Flag | 3–8-bar impulse of at least 1.5 ATR; 3–10-bar consolidation; body/range efficiency at least 0.50; consolidation width at most half the impulse; 10–50% retracement; flat/counter-direction drift; fresh close above/below consolidation. |
| H&S | Five alternating confirmed pivots; shoulder span 12–60 bars; head prominence at least 0.5 ATR; total height at least 1 ATR; shoulders within 0.5 ATR; balanced widths; limited neckline slope; incoming move; first close through the interpolated neckline. |
| Cup/handle | Two confirmed rims separated by 20–80 bars, within 0.5 ATR; depth at least 2 ATR; central bottom with sustained bottom-quarter dwell; 3–10-bar handle retracting 10–40% of depth; incoming move; fresh rim/handle breakout. Sharp V fixtures are rejected. |

A chart breakout must close more than 0.05 ATR beyond its boundary and no farther
than `InpPatternMaxChaseATR` (default 0.50). The previous close must be on the
unbroken side. Refreshed executable quotes must remain beyond the boundary and
inside the chase bound, checked during trade planning and each execution retry.
These are quote checks, not a promise that broker fills cannot slip.

Candidate ranking is deterministic: chart + aligned engulfing, standalone strong
engulfing, chart alone, optional pin. Chart + engulfing and standalone engulfing
score 2; chart alone scores 1.5; optional pin scores 1. The contribution uses the
existing pattern slot; no double counting and no increase to the score ceiling.
Equal ranks use stable pattern IDs. This profile does not fall back to legacy IBR,
T1 pullback break or T3 momentum turn when no qualifying pattern exists.

## Recognition is separate from entry

Higher-timeframe UP permits buys and DOWN permits sells. RANGE/UNKNOWN refuses
entries. A recognized counter-trend H&S remains visible but is not traded until
it independently satisfies the directional context. This can reduce frequency.

Standalone candles still require the configured pivot pullback location. Chart
patterns instead require their own validated consolidation/reversal location and
fresh breakout. **This is an explicit strategy change:** a breakout need not sit
inside the generic 30–80% pivot pullback window. Its journal location is
`CONFIRMED CHART BREAKOUT`. The HTF rule, optional RSI veto, score threshold,
sessions, volatility/spread/funding checks, sizing, risk caps and safety gates
continue to apply. Stops, targets, partial exits, break-even and trailing rules
are unchanged; adding detectors does not diagnose losses caused by those rules.

A per-bar `Patterns` record contains mode, all detected names, the qualified
selection, runner-up, location verdict, joint rejection and first chart boundary.
The dashboard draws a cyan dotted line and `DETECTED` label for the latest
recognized chart boundary, removed on the next bar without a chart detection.
It is not a full historical pattern outline or a trade marker. If multiple chart
patterns qualify, the displayed boundary belongs to the first detected chart;
the journal distinguishes this from the selected candidate. MT5 visual QA remains
outstanding. Regular execution logs establish whether an order was actually sent.

Chart instances use the completing pole peak (flag), right shoulder (H&S) or right
rim (cup) timestamp. Persistent latches are scoped by account, symbol, magic,
timeframe, direction and pattern family; standalone candles share the existing
leg latch. The existing per-bar reservation also remains. On first use of a
missing latch, the first eligible instance is conservatively refused and the
signal-bar timestamp recorded. An instance older than that timestamp cannot then
trade. This applies separately to each chart family and costs initial signals;
do not clear live state to force entries. Different families may subsequently
trade distinct instances, subject to existing exposure limits.

## Verification and remaining evidence

`python3 tools/test_portable_logic.py`: **151 passed, 0 failed** (including settings and multi-position checks). The harness adapts
actual production MQL logic into C++ and runs AddressSanitizer/UndefinedBehaviorSanitizer.
Coverage includes both directions of every chart type, invalid/unbroken/extended
shapes, raw-candle H&S pivot discovery, equal-open engulfing, near-doji rejection,
pin suppression, ranking, configuration dependencies, quote bounds, full-strategy
chart eligibility and HTF refusal, and observe-mode legacy parity. The native
`TestChartPatterns.mq5` contains 38 of these checks.

**MetaEditor compilation, native scripts, chart rendering, broker execution and
Strategy Tester profitability were not run here.** Portable checks are not a
substitute. No net return, win rate, trade-frequency gain or profitability is claimed.

Compare active versus observe with identical real ticks, broker symbol, dates,
spread, commission, swap, terminal build and full settings. Keep an untouched
out-of-sample period. Report net P/L, drawdown, trade count, costs and results by
pattern/direction/session, including bootstrap refusals and gate rejections.
Do not repeatedly tune on the evaluation window. To investigate the reported
losses, supply the MT5 report, full `.set`, tester journal and compile log. Entry
quality, costs, stop geometry and exit timing need to be distinguished before
changing risk or increasing frequency. The remaining V2 work is tracked in
[V2_IMPLEMENTATION.md](V2_IMPLEMENTATION.md).
