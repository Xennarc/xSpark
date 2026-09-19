# CandleFlow (XSparkFlow)

CandleFlow is XSpark's second strategy and its first single-factor one. It runs
in its own Expert Advisor, `MQL5/Experts/XSparkFlow/XSparkFlow.mq5`, and reuses
every shared component unchanged: safety, risk, sizing, execution, position
management, state persistence and the chart dashboard.

**Nothing in this document is a profitability claim.** CandleFlow has not been
backtested, forward-tested or traded. Trading is disabled by default.

## The rule

One factor, one candle:

- A closed base-timeframe candle that finished **above** its open opens a
  **long**.
- A closed base-timeframe candle that finished **below** its open opens a
  **short**.
- A candle that closed exactly at its open is not a signal.
- **No take-profit.** The trade has one exit: its stop.
- The stop is placed beyond that candle's **far wick** by a buffer — below the
  low for a long, above the high for a short.
- On every later closed candle the stop is **re-anchored** to that candle's far
  wick, plus the same buffer. It can only ever tighten.

That is the whole strategy. There is no score, no pattern library, no trend
filter and no session weighting.

## Changing the timeframe

Attach the EA to the chart period you want the rule to run on. `M30` gives the
30-minute rule; `M5`, `H1` and the rest behave identically on their own candles.
Supported periods are M1, M5, M15, M30, H1, H2 and H4 — the same list XSpark
supports, because each needs a higher-timeframe partner for the indicator cache.

Every distance CandleFlow uses is a multiple of the chart period's own average
range (ATR14), so a configuration that suits M30 needs no edits to run on H1.
That is the point of expressing the buffer and the stop bounds in ATR multiples
rather than in points.

## Settings

| Input | Default | What it does |
| --- | --- | --- |
| `InpFlowBufferATRMult` | 0.10 | Buffer beyond the wick, as a multiple of the average range. The component that rescales automatically across timeframes. |
| `InpFlowBufferRangePct` | 0.0 | Extra buffer as a percentage of the signal candle's own range. |
| `InpFlowBufferPoints` | 0.0 | Extra fixed buffer in strategy points. |
| `InpFlowMinStopATRMult` | 0.25 | Stop floor. A stop closer than this to the fill is widened to it. |
| `InpFlowMaxStopATRMult` | 0.0 | Stop ceiling. A wider stop refuses the entry. 0 disables it. |
| `InpFlowMinBodyATRMult` | 0.0 | Ignore candles whose body is smaller than this. 0 disables it, keeping the rule literally single-factor. |
| `InpFlowUseVolatilityGate` | false | Only enter while the average range is inside the auto-calibrated band. Off by default. |
| `InpFlowRiskPct` | 1.0 | Risk per trade, as a percentage of balance. |
| `InpFlowUseWeekendClose` | true | Flatten this bot's trades before the Friday close. On by default: a position held on a trailing stop with no target carries the weekend gap. |

### A note on the wording in MetaTrader

The Inputs tab shows each setting's trailing comment as its name, so that
comment is the whole user interface. CandleFlow's labels avoid the trade jargon
the identifiers still carry: **"typical candle size"** is ATR, **"the amount
risked"** is R — the distance from entry to the first stop — and **"buy/sell
gap"** is the spread. `tools/check_ea_inputs.py` fails the build on an input
with no label or one past MetaTrader's 63-character limit.

The trailing-stop settings have their own section below.

The three buffer components add together, so `0.10` ATR plus `20`% of the candle
range plus a fixed pad is a valid configuration.

## The trailing stop

CandleFlow has no take-profit, so the trailing stop **is** the strategy's exit.
It is built from four layers. On each closed candle every enabled layer proposes
a stop, the **most protective** one wins, and the result is then bounded by the
floor and by a one-way ratchet that refuses anything looser than the live stop.

| Layer | Input | Default | What it proposes |
| --- | --- | --- | --- |
| Candle anchor | always on | — | the far wick of the last closed candle, plus the buffer |
| Chandelier | `InpFlowTrailATRMult` | **3.0** | this many ATRs back from the best price the trade has seen |
| Tiering | `InpFlowTrailTightenStartR` / `FullR` / `InpFlowTrailTightATRMult` | **1.0 / 4.0 / 1.5** | shrinks the chandelier multiple linearly as the trade matures |
| Breakeven lock | `InpFlowBreakevenAtR` / `InpFlowBreakevenOffsetR` | **1.2 / 0.1** | entry ± offset, once the trade has been that far in front |
| Floor | `InpFlowMinTrailATRMult` | **0.35** | not a proposer — it pushes the winner away from the market if it landed too close |

**The whole stack is on by default.** The numbers live in
`Trade/TrailingStop.mqh` as `XSPARK_TRAIL_DEFAULT_*`, which is what the EA's
inputs read and what `TestTrailingStop.mq5` validates — so a default that would
block trading cannot reach a chart.

They were chosen for plausibility, not measured. To find out whether the stack
earns its complexity, run `presets/xauusd-m30-candleflow-plain-trail.set`
against `presets/xauusd-m30-candleflow.set` over the same period: the plain file
turns every layer off and leaves only the candle trail. If the full
configuration does not beat it, turn the layers off rather than tuning them.

### The floor is not optional

A trailing stop that can land a few points from the bid is a delayed market
order. A narrow candle, or a tightened chandelier late in a move, will do
exactly that, and the spread alone then closes a position whose move was still
intact. `InpFlowMinTrailATRMult` widens any such candidate back to a survivable
distance from the market.

Widening can only ever *reduce* the chance of being stopped, and the ratchet
still refuses anything looser than the live stop, so the floor cannot give back
protection the trade has already banked.

### The peak is measured on closed candles

The chandelier trails from the highest high (long) or lowest low (short) the
position has seen since entry, taken from **closed candles only** and stored
per position so a restart mid-trade does not reset it. Wicks count, because
that is the price the market actually reached.

This is deliberately not the `mfe_price` the position manager already tracks:
that one is sampled on the exit-side quote at every management pass, so it moves
intrabar and would make the trail depend on when a tick happened to arrive.

### Maturity is measured from the peak, not the current price

Tiering and the breakeven lock both key off how far the trade has been in front,
in units of its own initial risk. Measuring that from the peak rather than the
live price makes it **monotonic**: a tier once reached is never given back, so a
retracement can never loosen the trail.

Between `InpFlowTrailTightenStartR` and `InpFlowTrailTightenFullR` the chandelier
multiple moves *linearly* from the wide value to the tight one. There is no tier
boundary at which a small price change jumps the stop.

### What a bad configuration does

`XSparkValidateTrailTuning` refuses a tightened multiple wider than the base one,
tiering with no trail to tier, a tiering span too narrow to interpolate across,
and a breakeven offset that gives back more than its own trigger earns. A refused
configuration blocks **new entries** — the trailing stop is the only exit, so a
setting the EA cannot honour is not something to proceed past. Positions already
open keep trailing on the last accepted plan.

### Why there is a stop floor

The buffer alone does not bound the stop distance. A very small candle produces
a very small stop, and a very small stop produces a very large position for the
same percentage risk. `InpFlowMinStopATRMult` widens such a stop to a floor measured
from the fill price. Widening a stop always *reduces* the volume, so the floor
can never increase realised risk — it only prevents the size blow-up.

The floor is also what the auto-calibration measures every derived tolerance
against: it is genuinely the smallest stop this configuration can produce, which
is exactly what the entry-slippage bound in ADR-024 needs.

### Why there is no reversal, and no hedge

Every candle has a direction, so an opposing signal arrives constantly while a
position is open. CandleFlow never opens a trade against a position it is
already holding: the open trade exits on its trailing stop and nothing else.

This is enforced twice, because one check is not enough when the two moments are
seconds apart:

1. When the candle closes, `XSparkFlowEvaluateNewBarCore` refuses the signal if
   any XSparkFlow position on this symbol is on the other side. The panel shows
   `OPPOSING EXPOSURE` and the journal records the refused candle.
2. `ExecutionEngine` re-checks before **every** send attempt, so a position that
   appears between planning and the order reaching the broker still blocks it.

Both read live broker positions rather than XSpark's own state, and both fail
closed: a position that cannot be read refuses the entry rather than assuming
the bot is flat.

The check is scoped to this bot's Magic Number, so ScoreBot_v3 holding an
opposite position on the same symbol does not block CandleFlow. They are
separate bots and each may take its own side.

Note that with `InpFlowMaxOpenTrades = 1` the slot limit already blocks a second
trade of any direction. This check is what holds the rule when that limit is
raised to let same-direction trades stack.

## Running it next to ScoreBot_v3

Both EAs can run on the same account at the same time. They are separated by
Magic Number — `770331` for XSpark/ScoreBot_v3, `770332` for
XSparkFlow/CandleFlow — and every component that touches broker state filters on
it: position reconciliation, the per-position state store, the trailing stop, the
weekend close and the killswitch flatten. Neither bot can see, modify or close
the other's positions.

The one thing they *do* share is the account. `InpFlowMaxAccountRiskPct` is checked
against **all** open positions, including the other bot's, so each EA refuses an
entry that would push total open risk past its own cap. Set both caps with the
combined account in mind.

Use a different Magic Number again if you want two CandleFlow instances on
different charts. Either EA refuses to start on a Magic Number the other one
ships with, so the arrangement cannot be broken by a typo.

### Settings do not cross between them

MetaTrader applies a `.set` file by input identifier, so two EAs that named an
input the same way would silently configure each other. They do not share a
single name: XSparkFlow's inputs all carry the `InpFlow` prefix, XSpark's keep
the bare `Inp` prefix its existing presets rely on. Loading a ScoreBot_v3 preset
into XSparkFlow now changes nothing at all, and vice versa.

This is a repository rule rather than a one-off (AGENTS.md rules 41-45), and
`tools/check_ea_inputs.py` enforces it in CI for every EA added later.

## What it reuses, and what it changed

Reused with no change at all:

- `SafetyManager` — trading switch, spread filter, stale-quote gate, daily
  drawdown halt, total-drawdown killswitch, state-recovery latch.
- `RiskManager`, `PositionSizer`, `AccountExposure` — per-trade risk, volume
  from stop distance, account-level risk cap.
- `IndicatorCache`, `MarketState`, `SymbolMath`, `AutoTune` — closed-bar data,
  instrument specifications, and the per-instrument calibration of the
  volatility band, spread cap and slippage tolerances.
- `Dashboard` — the same panel, fed the same report structure.
- `StateStore` and the reconciliation half of `PositionManager` — per-position
  state that survives a restart, and broker state as the source of truth.

Two shared components gained an additive, default-off capability:

1. **`ExecutionEngine`** now accepts a *no-target plan*. A plan whose
   `dynamic_rr` is not positive is sent with `TP = 0`, and the reward-ratio
   bounds are skipped because there is no target to bound. Every other
   execution-time control is unchanged: the stop must still be on the protective
   side, entry drift is still bounded, the volume is still re-derived from the
   refreshed quote, and margin and the account cap are still re-checked before
   the send. ScoreBot_v3 always supplies a positive ratio, so its path is
   untouched.

2. **`PositionManager.ManagePositions`** gained a trailing mode. The default,
   `XSPARK_TRAIL_ATR_AFTER_PARTIAL`, is ScoreBot_v3's existing behaviour —
   partial close, break-even, then an ATR trail. `XSPARK_TRAIL_CANDLE_ANCHOR`
   takes an anchor price per direction from the caller, applies no partial and
   no break-even step, and ratchets the stop toward the anchor, tightening only.
   A missing anchor leaves the broker stop exactly where it is.

`RiskManager` grades exposure by score and CandleFlow has no score, so every
signal presents the same fixed value and XSparkFlow sets all three risk tiers to
the same percentage. The tier lookup therefore cannot change the answer, and the
one risk percentage an operator sets is the one that is used.

## What the dashboard shows

The panel is the shared one. CandleFlow fills the report it renders with the
single-factor equivalents: the pattern name reads `Bullish Close` or
`Bearish Close`, the mode reads `SINGLE FACTOR`, the entry location reads
`CANDLE CLOSE`, and the detected level is the candle anchor. The score bar shows
the fixed signal score; it is not a quality measure and should not be read as
one.

## Testing

`python3 tools/test_portable_logic.py` compiles the CandleFlow rules and the
anchor-trailing path of `PositionManager` through the C++ adapter and runs them:

- candle direction, including the doji and body-filter cases;
- the three-component wick buffer;
- the anchor arithmetic in both directions;
- the stop floor and ceiling, including a price that has already moved through
  the anchor;
- the one-way ratchet in the manager loop, long and short, and that a missing
  anchor leaves the stop untouched.

This is **not** an MQL5 compiler and it does not emulate MT5. Native compilation
is done with `tools/compile_mt5.ps1` on Windows, and broker behaviour must be
validated in the Strategy Tester and on a demo account.

## Before enabling it

1. Compile natively in MetaEditor.
2. Run the Strategy Tester on real ticks for the symbol and period you intend to
   use. Expect far more trades than ScoreBot_v3 produces: nearly every candle is
   a signal, and the only thing keeping the bot flat is that a position is
   already open.
3. Watch it on a demo account long enough to see the trailing stop re-anchor
   across several candles.
4. Only then consider `InpEnableTrading=true`, and start at the preset's 1% risk.
