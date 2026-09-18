# V2 implementation and validation status

Source baseline: `3214dcf` (main). This is an experimental entry implementation,
not a profitable or live-approved release. MetaEditor and MT5 are unavailable in
the implementation environment. **No MQL5 compilation or Strategy Tester run has
been performed.** No trade-frequency or profitability result is claimed.

## Implemented

| Plan stage | Implementation |
| --- | --- |
| S0 | Raw OHLC, current/previous/higher RSI, range/ATR on entries and rejected signals; original planned, execution-sized and fill stop distances logged separately. |
| S2 | Pure closed-bar structure, asymmetric plateau handling, alternating magnitude-filtered pivots, overflow refusal, HH/HL and LH/LL classification, base-close invalidation, leg geometry, unbroken opposing-level lookup. Independent 160/80-bar cache; legacy 50-bar warm-up unchanged. Per-bar joint telemetry and compact dashboard status. |
| S2a | Separate commit raises HTF handle readiness to 51 EMA and 15 RSI bars and rejects nonpositive HTF EMA. This can change the first eligible bar. |
| S2b | Opposing XSpark positions refused at the EA gate and before each send attempt. Concurrent risk headroom checked. Drawdown tolerance counts correlated rounds. Account-risk refusals partition this instance's risk and other positions' risk. |
| S3/S3b/S5 | Optional coupled HTF-direction, pullback-location and continuation path. T1 pullback-extreme break, T2 aligned legacy candle, T3 candle/RSI turn. New timing signals use the existing pattern score slot; ceiling remains 9. |
| S4 (gate only) | Optional RSI bounds and turn veto, with distinct inner/outer rejection reasons. Band defaults remain unchanged for measurement; see the explicit experiment below. |
| Supporting controls | Observe-only mode, invalid-combination entry block, timestamp latch persisted before an execution attempt, atomic reservation of existing latch keys. Failures refuse entry. |

The executable strategy remains MQL5. Python/C++ files under `tools/` are local
verification tools only; the EA has no new runtime dependency.

## Decisions where the plan conflicts or lacks evidence

- Section 3.3 permits RANGE reversals and CHoCH; sections 3.2 and 7 prohibit them.
  This implementation blocks RANGE/UNKNOWN and does not add a counter-trend
  exception. A bearish candle is never simply converted to a buy: an aligned
  closed-bar continuation trigger must exist.
- HTF, pullback and continuation switches must be enabled together. Invalid
  combinations, and the S2b headroom fault, block **entries** while position
  reconciliation/management continues. They deliberately do not return
  `INIT_FAILED`, following the plan's protective-management requirement.
- The existing RSI input defaults remain 40–70 for buys and 30–60 for sells.
  Swapping them would change Asian-session legacy trades even in observe mode.
  Apply the proposed 30–60 / 40–70 swap as its own measured experiment after
  recording the S0/S1 control. The constructor and inputs remain consistent.
- `InpMinSwingATR=0.5` is an uncalibrated initial value, not an optimized setting.
- `legs_in_state` counts consecutive directional legs in the accepted pivot
  suffix (six consistently advancing alternating pivots give five legs).
- Confirmed raw fractals use only closed data. The *filtered sequence* can still
  replace its newest same-type pivot with a more extreme confirmed one. Window
  rollover can also change classification. Neither property is a promise that
  an accepted filtered pivot remains immutable forever.
- No continuation trigger means WAIT; frequency is never enforced as a quota.
  Observe telemetry records candidates, not hypothetical executed trades or a
  counterfactual equity curve. Scoring, session, funding, spread, position limits,
  and persistence can still refuse a candidate.

## Duplicate protection and restart behaviour

All continuation triggers, including aligned legacy candles, use one instance:
the base leg's origin pivot time. The persisted high-water timestamp is scoped
by account, symbol, magic, base timeframe and direction. Failed or uncertain
execution still consumes a reserved instance, matching the existing bar guard.

A missing latch cannot establish that an older pattern was never traded. The
first otherwise executable candidate initializes the latch to its **signal bar**
and is refused. A later origin must be newer than that timestamp. This sacrifices
the initial leg after first installation/state loss; record that frequency cost.
Restarting with intact state does not reset it. Never clear a live latch merely
to force more trades. Terminal state is not shared across separate MT5 terminals;
keep the existing unique-magic-per-chart operating rule.

Global variable reservations use MetaQuotes' atomic
[GlobalVariableSetOnCondition](https://www.mql5.com/en/docs/globals/globalvariablesetoncondition)
then [GlobalVariablesFlush](https://www.mql5.com/en/docs/globals/globalvariablesflush).
Flush exposes no success result, so a power-loss/disk-failure durability guarantee
cannot be established from that API. Broker/terminal restart testing is still
required. Portable mocks test failures of reads, writes and conditional updates,
not the real filesystem or broker.

## Verification actually performed

`python3 tools/test_portable_logic.py` passes **67 assertions** using the actual
pure production MQL source and fixtures through a small C++ syntax/API adapter.
It builds with `-Wall -Wextra -Werror -pedantic`, AddressSanitizer and
UndefinedBehaviorSanitizer. Leak detection is disabled because the managed
runtime uses ptrace. This is **not** an MQL5 compile or an MT5 emulation.

Coverage includes structure symmetry, equal-high RANGE, plateau selection,
outside-bar exclusion, missing/bad data, overflow, leg location, RSI exhaustion,
turns, configuration dependencies, T1/T3, persistence/restart/failure paths,
concurrent risk arithmetic, and observe-mode eligibility/direction/score/stop/
target parity against legacy behaviour, an additive continuation flowing through
the full strategy, and inconsistent-snapshot rejection. Existing MQL test scripts have not run
inside MT5. The new native `TestMarketStructure.mq5` contains 34 of these checks.

## Windows compilation

Install/use the normal MT5 MetaEditor and standard include library, then run:

```powershell
.\tools\compile_mt5.ps1 `
  -MetaEditor 'C:\Program Files\MetaTrader 5\metaeditor64.exe' `
  -TerminalDataPath 'C:\Users\YOUR_NAME\AppData\Roaming\MetaQuotes\Terminal\YOUR_DATA_FOLDER'
```

The helper copies sources and standard includes into a new temporary staging
folder, compiles the EA and **every** test script, and requires a fresh EX5 plus
an explicit **0 errors, 0 warnings** log for each. It never deploys to the running
terminal. Paths must match the installed terminal; use File → Open Data Folder.
The helper itself has not been run on Windows here. It follows MetaQuotes'
[documented command-line flags](https://www.metatrader5.com/en/metaeditor/help/beginning/integration_ide).
Unrecognized/localized summaries fail verification and require manual log review.

## MT5 acceptance sequence

1. Compile all targets. Resolve every error/warning; save compiler/build details.
2. Run all native test scripts in a demo terminal; require zero failed checks.
3. Backtest original `3214dcf`, measurement commit `63142ac`, and this candidate in
   the same terminal session with identical real ticks, broker symbol, dates,
   costs and settings. Keep the new gates off; compare trade identities. S2a may
   affect initial warm-up; isolate that commit if any other difference appears.
4. Enable HTF, pullback and continuation together, retaining
   `InpGateObserveOnly=true`. First keep all existing RSI inputs unchanged.
   Candidate telemetry must not alter the actual legacy trade sequence.
5. Test enforced entries with `InpGateObserveOnly=false`, then the RSI gate and
   its band swap as separate comparisons. `InpRequireRSITurn` is an additional
   experiment. Do not combine a threshold sweep with these tests.
6. Compare trade count with the S1 control's ±20% band, accounting separately for
   bootstrap refusals, unavailable structure, exhausted RSI, missing pullback,
   and missing trigger. If quality and frequency conflict, report both; do not
   loosen a gate until a desired count appears.
7. Validate restarts around reservation/send, corrupt or missing latch state,
   two same-direction slots, opposite-direction refusal, manual/foreign exposure,
   and configuration changes while a position is open. Confirm management continues.
8. Evaluate net results after commission, swap and spread using untouched
   historical windows ending before 2026-09-01 as the plan specifies. Use its
   matched-subset/day-block analysis; no selection or retuning on the holdout.
   Forward-demo results are also required before live deployment.

For Strategy Tester trading tests, explicitly enable `InpEnableTrading` in the
**tester inputs**. Its shipped default remains false. No risk limits were raised,
no lot multiplication or recovery sizing was introduced. Increased opportunity
count is a hypothesis, not a measured result.

## Remaining work and its concrete prerequisites

- **S1 evidence:** actual real-tick report, journals, commission/spread settings,
  server offset, date range and terminal build. No such market data is in the repo.
- **S6/S7 and exit decoupling:** the plan's S0 loser-MFE experiment must first
  support the exit diagnosis. Then structural-stop drift safeguards, targets and
  independent protective management must be implemented/tested together. Existing
  stops/targets/partial/BE/trailing remain unchanged in this PR.
- **S8c RR quantization:** inspect real `Final broker-valid RR` rejections first,
  per S0. The proposed one-tick tolerance has not been applied silently.
- **S8a/S8b and S9:** legacy mother-bar/SR corrections, pattern ranking, flags,
  double tops/bottoms and head-and-shoulders remain separate unimplemented stages.
  Their source predicates and rejection populations need isolated tests and the
  S1/S2 measurement baseline before accepting their effect on trade count.
- **Score-maximum centralization:** the existing constants and checks remain;
  no score ceiling was increased or clamped.

The full V2 plan is not complete. The implementation supplies its measurement,
structure, concurrency controls and opt-in entry path for the first terminal
validation cycle; it does not establish a profitable EA.
