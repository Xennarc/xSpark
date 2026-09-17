# ScoreBot_v3 Strategy

ScoreBot_v3 is the first XSpark strategy implementation. It was developed and tested on XAUUSD M15, and since Phase 1 it will run on any symbol and any supported base timeframe. It runs inside the native MT5 Expert Advisor. This document separates the locked tested strategy logic from production safety additions added for live-risk control.

The default configuration is MAX_SHARPE. Reference Python backtest results are unvalidated priors only, not expected returns.

## Identity

- Strategy ID: `ScoreBot_v3`
- Default Magic Number: `770331`
- Default order comment: `ScoreBot_v3`
- Tested symbol: XAUUSD, including broker suffixes/prefixes containing `XAUUSD`
- Tested timeframe pair: M15 base, H1 higher
- Production runtime: native MQL5

The instrument guard is lifted. The EA initializes on any symbol whose broker
specification validates, and on any supported base timeframe.

### Supported timeframes

The base timeframe is the chart period. The multi-timeframe partner comes from
an explicit table rather than arithmetic, because a computed `base x 4` produces
absurd ratios at the edges of the period list (H8 would pair with W1, a 21x
jump) and has no answer at all above D1.

| Base | Higher |
|---|---|
| M1 | M5 |
| M5 | M30 |
| M15 | **H1** (the tested pair) |
| M30 | H2 |
| H1 | H4 |
| H2 | H8 |
| H4 | D1 |

Any other chart period is refused at initialization. That is the same posture
the old M15 guard had: a chart the strategy cannot be evaluated on at all is
refused up front. It is not the runtime-fault case ADR-020 deliberately keeps
out of `OnInit`.

### Phase 1 limitations

Phase 1 makes the EA *run* anywhere. It does not make the tested thresholds
*correct* anywhere. Two consequences are expected, not bugs, and Phase 2's
self-calibrating gates are what resolve them:

- **Thresholds are still absolute.** `InpATRMinPoints = 80` now means 80 pips
  on an FX pair. EURUSD M15 ATR is roughly 5-15 pips, so the ATR gate rejects
  every bar and the dashboard reads `ATR BLOCKED`. `InpMaxSpreadPoints = 50`
  becomes 50 pips, which is far too loose to filter anything. Running a non-gold
  instrument therefore needs the ATR and spread inputs re-entered by hand until
  Phase 2 derives them.
- **The deviation DEFAULTS are gold-scaled, but they are now inputs.**
  `InpEntryDeviationPoints` (default 30) and `InpExitDeviationPoints` (default
  100) can be retuned per instrument like the ATR and spread thresholds. They
  scale with the resolved point size, so on gold they are $0.30 and $1.00
  against an ATR stop of $1.20 or more, and left unchanged on an FX pair they
  become 30 and 100 pips against a stop of roughly 8-25 pips. The EA no longer
  proceeds silently into that state: see the entry drift bound below. See
  ADR-024.

- **Session weighting degrades on high timeframes.** The session weight is taken
  from the hour of the signal bar. On H4 that hour is only ever 0, 4, 8, 12, 16
  or 20, and on D1 it is always the session open hour, so the London/New York
  windows stop discriminating. Above H1 the weighting should be treated as
  meaningless. Phase 2's learned hourly activity profile replaces it.

## ScoreBot Point Normalization

A ScoreBot point is a price quantity, not a broker-native MT5 point. The tested
strategy specified its thresholds in US cents of gold, so for XAUUSD one
ScoreBot point is 0.01 price units.

```text
1 ScoreBot point = 0.01 XAUUSD price units
80 points        = $0.80
800 points       = $8.00
50 points        = $0.50
30 points        = $0.30
```

The size of a ScoreBot point is resolved from the instrument specification at
initialization rather than hardcoded. On XAUUSD it is additionally checked
against the declared baseline `XSPARK_XAUUSD_SCORE_POINT_SIZE`, and the baseline
constant is what operates: that check is the Phase 0 regression assertion and it
survives Phase 1 unchanged. The resolved and declared values are identical at
both quote conventions a broker may use for gold - 2 digits with point 0.01, and
3 digits with point 0.001 - so the resolution changes no threshold on gold.

Other instruments have no declared baseline to check against, so the
spec-validated derivation is the operating size directly. See ADR-020 for the
derivation and ADR-021 for the per-instrument branch.

Resolution happens once, in `OnInit`, and the resolved size is passed to the
strategy, SafetyManager, ExecutionEngine and PositionManager, so no conversion
re-derives it from the terminal. The exit deviation is converted on the
killswitch flatten path, which runs deliberately while the quote feed is
unusable. The broker point size is a separate quantity and is still read at the
call site, unchanged from before.

A size that does not match the baseline blocks every new entry for the rest of
the session, so the dashboard reports `POINT SIZE FAULT` in the alarm colour
rather than a healthy `SCANNING`.

If the size cannot be resolved, or does not match the declared XAUUSD baseline,
the EA does **not** refuse to initialize. Refusing would stop `OnTick`, which
would abandon trailing, break-even, protection repair and the total-drawdown
killswitch while live positions stay open at the broker. Instead the EA falls
back to the declared baseline, logs CRITICAL, and blocks all new entries through
SafetyManager while protective management of existing positions continues.

The implementation converts between ScoreBot points, broker-native points, and
price distance through `SymbolMath.mqh`. Strategy thresholds such as ATR,
spread, and slippage use ScoreBot points first, then convert to broker-native
values for MT5 operations.

## Tested Strategy Logic

### MAX_SHARPE Defaults

- `InpMinScore = 2.0`
- `InpDropIBR = false`
- `InpLongScoreExtra = 0.0`

### EDGE Optional Inputs

EDGE is not the default. It can be selected manually with:

- `InpMinScore = 2.5`
- `InpDropIBR = true`
- `InpLongScoreExtra = 1.0`

### Indicators

All signal decisions use closed bars only.

M15:

- EMA 21
- EMA 50
- RSI 14
- ATR 14
- ATR 50
- OHLC
- tick volume

H1:

- EMA 50
- RSI 14

The EA uses true higher-timeframe indicator handles. It does not approximate higher-timeframe values from base-timeframe indicators.

### Bar Evaluation

Signals are evaluated once per newly opened base-timeframe bar, using the just-closed bar as signal bar 1. On initialization, the EA records the current bar and waits for the next genuine new bar before evaluating a signal.

### Patterns

Patterns operate on closed base-timeframe candles.

Pattern priority:

1. Pin bar
2. Engulfing
3. Inside-bar breakout

First matching pattern wins. No pattern means no score and no trade.

Pin bar:

- Bullish uses the lower wick definition from the specification.
- Bearish uses the upper wick mirror.
- Strength is capped at 2.0.

Engulfing:

- Bullish uses bar 1 versus bearish bar 2.
- Bearish uses the mirrored definition.
- Body division occurs only when bar 2 body is greater than zero.

Inside-bar breakout:

- Mother bar: bar 3
- Inside bar: bar 2
- Breakout bar: bar 1
- Strength: 1.5
- Disabled when `InpDropIBR = true`

### Hard Strategy Gates

Session gate:

- London: `07 <= server hour < 16`
- New York: `12 <= server hour < 21`
- Both sessions: weight 1.2
- One session: weight 1.0
- Neither, Asian reduced allowed: weight 0.6
- Neither, Asian reduced disabled: weight 0.0 and no score

ATR gate:

- ATR14 must be between 80 and 800 ScoreBot points.
- This means `$0.80 <= ATR14 <= $8.00`.

### Scoring

```text
rawScore =
    pattern
  + atr
  + trend
  + rsi
  + sr
  + volume
  + mtf

finalScore = rawScore * sessionWeight
```

Maximum raw score is 7.5. Maximum final score is 9.0. Scores outside 0 to 9 are treated as invalid state.

Components:

- Pattern: pattern strength, max 2.0
- ATR: 1.0 when hard ATR gate passes
- Trend: 1.0 when direction-specific EMA conditions pass
- RSI: 1.0 when direction-specific RSI range passes
- S/R: 1.0 when Close1 is within 0.5 ATR of a qualifying swing
- Volume: capped score from bar1 volume versus mean volume of bars 2-10
- MTF: 0.5 when higher-timeframe and base-timeframe RSI direction conditions pass

### Effective Threshold

```text
effectiveThreshold = InpMinScore + (long ? InpLongScoreExtra : 0)
```

MAX_SHARPE defaults require score >= 2.0 for both directions.

### Exits

Initial stop:

- Long: entry reference Ask minus `InpATRMultSL * ATR14`
- Short: entry reference Bid plus `InpATRMultSL * ATR14`

Dynamic RR:

```text
ratio = ATR14 / ATR50
t = clamp((ratio - 0.7) / (InpATRRatioBoost - 0.7), 0, 1)
RR = InpMinRR + t * (InpMaxRR - InpMinRR)
```

Defaults produce `1.5 <= RR <= 3.0`.

Partial:

- Trigger: 2.5R using exit-side price
- Close amount: 50% of initial lots, floored to broker lot step
- If no legal partial amount exists, no fabricated partial is sent
- After successful partial, SL moves to entry subject to broker stop rules
- TP remains unchanged

Known tested quirk: when dynamic RR is below 2.5, hard TP occurs before the partial trigger. This is intentional.

Trailing:

- Active only after partial is done
- Uses latest cached closed base-timeframe ATR14
- Distance: `2.0 * ATR14`
- Only tightens SL
- Never modifies TP

## Risk Model

Risk tiers use the final session-weighted score:

- Score >= 5.5: Tier 3
- Score >= 4.5: Tier 2
- Otherwise: Tier 1

Defaults:

- Tier 1: 3.0%
- Tier 2: 3.0%
- Tier 3: 3.0%
- Hard cap: 3.5%
- Absolute ceiling refused at initialization: 10.0%

The tiers are flat by default. Tier selection reads the session-weighted score,
so identical evidence would size differently purely by the hour of day, and a
larger risk figure amplifies that distortion. The inputs remain separate so
tiering can be reinstated deliberately.

3.58% is the growth-optimal (Kelly) fraction for the edge measured in
`IMPROVEMENT_PLAN.md`. Growth per trade peaks there and falls away above it,
crossing zero near 7.2% - above which a genuinely positive edge still shrinks
the account, because compounding is multiplicative. Sizing larger trades faster
toward ruin, not toward profit. See ADR-022.

Position sizing uses account balance, selected risk percentage, actual final stop distance, and dynamic symbol specifications:

- tick size
- loss-appropriate tick value when available
- fallback tick value
- min volume
- max volume
- volume step

If the computed volume is below broker minimum, the trade is aborted. The EA does not increase size to minimum lot when doing so would exceed intended risk.

## Production Safety Additions

These controls were not part of the original tested core strategy and do not alter ScoreBot scoring.

### Trading Disabled Default

`InpEnableTrading = false` by default. Analysis and dashboard updates continue, but eligible signals cannot reach ExecutionEngine.

### Spread Filter

Enabled by default:

- Max spread: 50 ScoreBot points, or $0.50
- Max spread as ATR percentage: 10%

This is an execution gate, not a score component.

### Daily Drawdown Halt

Tracks server trading day. At 15% decline from that day high-water equity:

- New entries are blocked.
- Halt remains latched until next server day.
- Existing position management continues.
- State is persisted using MT5 terminal Global Variables namespaced by account, symbol, and magic.

### Total Drawdown Killswitch

Tracks **persisted** high-water equity. At 25% decline:

- Killswitch latches.
- XSpark-owned positions for this symbol and Magic Number are closed.
- XSpark-owned pending orders for this symbol and Magic Number are cancelled.
- Manual trades and other Magic Numbers are not touched.

The high-water mark and the latch are persisted to the same state store as the
daily halt, under keys `tP` and `tL`. They survive a restart, a recompile, an
input change and a VPS reboot. Previously both were RAM-only, so `OnInit`
re-anchored the peak to live equity and cleared the latch - meaning the ruin
stop reset itself on exactly the action an operator takes when a latched EA has
stopped trading.

Clearing a latch is therefore deliberate and separate from restarting: set
`InpClearKillswitchLatch = true`, attach, confirm the CRITICAL line that records
the reset, then set it back to false.

The limit is sized against the configured risk rather than chosen to feel small.
At 3.5% per trade, nine consecutive full-stop losses reach 25%. The former 8%
limit would have latched on the fifth, and the reference run already contained
an eight-loss streak - roughly the median longest run over fifty trades at a 64%
loss rate, not a tail event. The startup log prints the exact tolerance for
whatever values are configured, and warns when it falls below six losses.

### Stop-Level Validation

Before initial protection or stop modifications, the EA reads `SYMBOL_TRADE_STOPS_LEVEL`, adjusts invalid SL/TP outward only as needed, and normalizes prices for the symbol.

When initial SL is moved farther away, position sizing uses the actual final stop distance.

### Margin Validation

Before order submission, the EA uses `OrderCalcMargin` and requires free margin to cover calculated margin plus the configured buffer. Default buffer is 20%.

### Weekend Close

Disabled by default. When enabled, it closes only XSpark-owned positions for the chart symbol and Magic Number based on server time.

### Stale Quote Rejection

`InpMaxQuoteAgeSeconds` defaults to 15 seconds. This is a production safety addition, not tested ScoreBot strategy logic.

Before any new exposure is approved, SafetyManager reads the current tick and compares its timestamp against server time:

- A tick timestamp of zero or an unreadable tick blocks new entries.
- A quote older than the configured maximum blocks new entries.
- A quote dated more than 5 seconds ahead of server time is treated as invalid and blocks new entries.

The gate applies to new exposure only. Score, pattern detection, dashboard analysis, and protective management of existing positions are unaffected.

Quote age is measured against `TimeTradeServer()`, which MT5 derives from the host clock and the server offset. A badly skewed VPS clock therefore blocks new entries rather than allowing stale ones, and the block is logged as a WARNING so the cause is visible. Keep the VPS clock synchronised.

### Execution-Time Risk Revalidation

Trade planning happens on the closed-bar evaluation price. The price the broker actually trades at can differ, so ExecutionEngine recomputes the entire risk chain immediately before every order send:

1. Refresh the broker tick and reject a stale or invalid quote.
2. Take the current entry reference: Ask for BUY, Bid for SELL.
3. Abort when the entry reference has drifted from the planned reference by more than `InpEntryDeviationPoints` (default 30 ScoreBot points). The market is never chased.
4. Keep the locked ATR stop where the strategy placed it. Abort when price has already moved through it.
5. Re-run broker stop-level validation against the close-side price (Bid for a long, Ask for a short), which is the side MT5 measures protective levels against.
6. Recompute the actual stop distance from the current entry reference and the broker-valid stop.
7. Recompute the volume from that actual distance so the monetary risk stays at the selected risk percentage.
8. Recompute TP from the actual distance and the locked dynamic RR.
9. Abort when the resulting broker-valid RR falls outside `InpMinRR` to `InpMaxRR`.
10. Re-run margin validation with the recomputed volume.

The theoretical ATR stop is never moved to preserve the originally planned lot size. Risk percentage is the constraint and the volume adapts.

### Exact Post-Execution Position Identification

After a confirmed entry, ExecutionEngine reads `CTrade::ResultDeal()`, selects that deal from MT5 history, and takes `DEAL_POSITION_ID`, `DEAL_PRICE`, `DEAL_VOLUME`, and `DEAL_TIME`. The position id binds the trade state to the exact broker position.

A same-direction match is only a documented fail-safe fallback. It is used solely when the broker deal exposes no position id, it does not use newest-open-time, and it refuses any candidate that is already tracked, has the wrong direction, opened before the send, or whose executed volume does not match. A broker position that already existed before the send is refused outright.

### Broker Protection Verification

A confirmed retcode means the order was accepted, not that the broker applied the stop that was sent with it. After a confirmed entry the EA reads the live `POSITION_SL`. If it is missing, the submitted stop is applied immediately, the condition is logged CRITICAL, and registration is reported as failed until a stop exists. Every management pass re-attempts protection repair for any XSpark position found without a broker stop, and new entries stay blocked while any XSpark exposure is unprotected.

Exit operations use a wider deviation, `InpExitDeviationPoints` (default 100 ScoreBot points), than entries. Closing at a slightly worse price is always preferable to failing to close, so this one is deliberately NOT bounded from above: a tolerance too small to fill leaves live exposure XSpark meant to be flat.

### Weekend Close Entry Block

When `InpUseWeekendClose` is enabled, new entries are refused inside the weekend-close window. Previously the EA could open a position that PositionManager would flatten on the same tick.

### Residual Execution Slippage

The configured deviation is accepted execution tolerance, so a market order can still fill up to `InpEntryDeviationPoints` away from the price the volume was sized from. With a fixed absolute stop this makes the realised entry-to-stop distance, and therefore the realised monetary risk, larger than the sized figure. The EA does not pre-shrink the volume for this, because that would change tested position sizing; instead it computes the realised distance from the actual fill and logs a WARNING whenever realised risk exceeds the sized risk. Reduce `InpEntryDeviationPoints` if this residual is unacceptable for a given account.

**The entry drift bound.** How large that residual can get is decidable before any trade exists. The stop is placed relative to the same reference the volume was sized against, so

```text
realised_risk / selected_risk  <=  1 + InpEntryDeviationPoints / risk_distance
```

and the smallest risk distance the configuration can ever produce is fixed by the ATR gate at `InpATRMultSL * InpATRMinPoints`. `OnInit` computes that ratio and reports it:

| Configuration | Min stop | Ratio | Outcome |
|---|---|---|---|
| Gold defaults: 30, 1.5, 80 | 120 pts | 0.25 | WARN - a fill can realise 125% of selected risk |
| FX pair left on gold values: 30, 1.5, 10 | 15 pips | 2.00 | **FAULT** - permitted slip is twice the whole stop |
| FX set for the instrument: 2, 1.5, 10 | 15 pips | 0.13 | OK |

A ratio at or above 1.0 means a permitted fill can land at or beyond the position's own stop, so the gate bounds nothing. That is a `DRIFT GATE FAULT`: a CRITICAL log line and a SafetyManager veto on new entries, with protective management of existing positions unaffected. Above 0.20 it warns. The gold defaults therefore warn on every startup, and the threshold is deliberately not set to hide that - the 25% overshoot is real and an operator should see the number.

### State Recovery

If broker execution is confirmed but the resulting position cannot be bound exactly, the EA logs CRITICAL, latches SafetyManager into a state-recovery condition, reconciles against MT5, and verifies that every live XSpark position is represented in managed state.

While the state stays inconsistent:

- New entries are blocked.
- Protective management of live broker positions continues.
- Dashboard status reads `STATE RECOVERY` rather than `MANAGING`.

The latch clears only after reconciliation proves that every live XSpark position has managed state, with a matching direction, a broker stop in place, and — for the position this entry created — ownership by this entry's signal bar rather than by a different XSpark trade.

## Execution Boundary

ScoreBot_v3 does not include `Trade/Trade.mqh`, `CTrade`, `OrderSend`, direct buy/sell calls, direct close calls, or stop modification calls.

Execution authority is split as follows:

- `ExecutionEngine.mqh`: new market entries only
- `PositionManager.mqh`: XSpark-owned closes, partial closes, stop modifications, and pending-order cleanup

Both boundaries filter by symbol and Magic Number where appropriate and inspect trade-server retcodes.
Market-entry, stop-modification, and partial-close mutations are treated as confirmed only on completed trade-server retcodes, not on a local function return alone.

### Adopted Positions Without Persisted State

A position XSpark adopts without a matching persisted record receives no partial, break-even or trailing management; it runs on the SL/TP the broker already holds (see ADR-018). The condition is never silent: the dashboard reports `UNMANAGED EXPOSURE` in the alarm colour, with a count, for as long as any such position is open, and that status is derived on every render so it cannot latch or be overwritten.

### State Store Hygiene

Per-position state is keyed by account, symbol, Magic Number and `POSITION_IDENTIFIER`. Keys that would exceed MT5's 63-character name limit fall back to a deterministic hash of the same logical key. Orphaned records are swept on the first tick after a valid quote and a completed reconciliation, never during `OnInit` (see ADR-019).

## Implementation Assumptions

### Assumption SBV3-001

S/R price is implemented as base-timeframe bar1 close because the strategy is closed-bar deterministic.

### Assumption SBV3-002

Session classification uses the timestamp/hour of base-timeframe bar1. Above H1 this stops discriminating; see the Phase 1 limitations.

### Assumption SBV3-003

If a bar simultaneously qualifies as bullish and bearish pin, bullish evaluation has deterministic precedence.

### Assumption SBV3-004

If broker stop-level adjustment would force final TP beyond the configured RR bounds, the entry is blocked to preserve the strategy's min/max RR rule.

## Omitted Features

Adaptive threshold is not implemented because the tested configuration has adaptive threshold off.

Time stop is not implemented because the tested strategy did not use one and no tested duration has been specified.

## Reference Python Backtest Caveats

MAX_SHARPE reference:

- 87 trades / 60 days
- About 1.23 trades/day
- Win rate: 46.0%
- PF: 1.63
- Net: +37.9%
- Max DD: 6.05%
- Sharpe: 4.38

EDGE reference:

- About 1 trade/day
- Win rate: 43.5%
- PF: 1.68
- Net: +31.7%

These values are unvalidated priors. They are not expected returns and are not acceptance criteria.

The Python harness used GC=F, 60 days, approximated H1 values, fixed $0.30 spread, bar-level fills, max 1 position, and balance sizing. The EA uses Exness XAUUSD, true H1 indicators, broker spreads, tick execution, and MT5 symbol/account properties.
