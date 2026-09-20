# CandleFlow (XSparkFlow)

CandleFlow is XSpark's second strategy and its first single-factor one. It runs
in its own Expert Advisor, `MQL5/Experts/XSparkFlow/XSparkFlow.mq5`, and reuses
every shared component unchanged: safety, risk, sizing, execution, position
management, state persistence and the chart dashboard.

**Nothing in this document is a profitability claim.** No backtest, forward test
or live result is recorded in this repository, and none of the numbers below was
measured. Trading is disabled by default.

## The rule

One factor, one candle:

- A closed base-timeframe candle that finished **above** its open opens a
  **long**.
- A closed base-timeframe candle that finished **below** its open opens a
  **short**.
- A candle that closed exactly at its open is not a signal.
- The stop is placed beyond that candle's **far wick** by a buffer — below the
  low for a long, above the high for a short.
- On every later closed candle the stop is **re-anchored** to that candle's far
  wick, plus the same buffer. It can only ever tighten.
- Part of the trade is **banked at fixed distances** as it runs, and the
  remainder exits on that trailing stop.

That is the whole entry rule. There is no score, no pattern library, no trend
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
| `InpFlowTP1AtR` / `InpFlowTP1ClosePct` | **1.5 / 30** | Bank 30% of the opening size once the trade is 1.5× its own risk in front. |
| `InpFlowTP2AtR` / `InpFlowTP2ClosePct` | **3.0 / 30** | Bank another 30% at 3×. |
| `InpFlowTP3AtR` / `InpFlowTP3ClosePct` | 0.0 / 0.0 | A third step, off by default. |
| `InpFlowFinalTargetR` | 0.0 | A hard broker take-profit for whatever is left. Off by default — see below. |
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

The trailing stop is the exit for whatever the take-profit ladder leaves running,
and the only exit at all when the ladder is switched off. It is built from four
layers. On each closed candle every enabled layer proposes
a stop, the **most protective** one wins, and the result is then bounded by the
floor and by a one-way ratchet that refuses anything looser than the live stop.

| Layer | Input | Default | What it proposes |
| --- | --- | --- | --- |
| Candle anchor | always on | — | the far wick of the last closed candle, plus the buffer |
| Chandelier | `InpFlowTrailATRMult` | **3.0** | this many ATRs back from the best price the trade has seen |
| Tiering | `InpFlowTrailTightenStartR` / `FullR` / `InpFlowTrailTightATRMult` | **1.0 / 4.0 / 1.5** | shrinks the chandelier multiple linearly as the trade matures |
| Breakeven lock | `InpFlowBreakevenAtR` / `InpFlowBreakevenOffsetR` | **1.2 / 0.1** | entry ± offset, once the trade has been that far in front |
| Floor | `InpFlowMinTrailATRMult` | **0.35** | not a proposer — it pushes the winner away from the market if it landed too close |

The trail governs whatever the take-profit ladder has not banked. The two are
independent: the ladder never moves a stop, and the trail never closes volume.

**The whole stack is on by default.** The numbers live in
`Trade/TrailingStop.mqh` as `XSPARK_TRAIL_DEFAULT_*`, which is what the EA's
inputs read and what `TestTrailingStop.mq5` validates — so a default that would
block trading cannot reach a chart.

They were chosen for plausibility, not measured. To find out whether the stack
earns its complexity, run `presets/xauusd-m30-candleflow-plain-trail.set`
against `presets/xauusd-m30-candleflow.set` over the same period: the plain file
turns every layer off and leaves only the candle trail. If the full
configuration does not beat it, turn the layers off rather than tuning them.

## The take-profit ladder

A trailing stop can only act **after** the price has come back. That is the whole
cost of trailing: a trade that runs 6R and turns around is closed once the move
has retraced by the full trail distance, which on the shipped 3.0 ATR chandelier
is a long way. The equity curve rises and then gives a large part of it back, and
the trade is booked well below the best price it ever saw.

The ladder takes money off the table on the way, so the retrace only costs the
part still running.

| Step | Fires when the trade is | Closes | Leaves |
| --- | --- | --- | --- |
| 1 | 1.5 × its own initial risk in front | 30% of the **opening** size | 70% |
| 2 | 3.0 × in front | another 30% of the opening size | 40% |
| 3 | off by default | — | — |

Every distance is a multiple of the distance from the entry to the **first** stop,
so the ladder rescales with the instrument and the timeframe exactly as the trail
does. Every percentage is of the volume the position **opened** with, never of
what is left — percentages of a shrinking remainder would bank a different share
of the trade at each step than the one configured, and would never reach zero.

The arithmetic lives in `Trade/ProfitLadder.mqh`, beside the trailing stop and
for the same reason: taking profit in steps is a property of an open position,
not of an entry rule. `PositionManager` applies it; `CandleFlow.mqh` never sees
it.

### What a step can and cannot do

- **It only ever removes exposure.** There is no adding, no re-entry and no
  sizing from a previous outcome. A step cannot increase the risk the entry was
  sized for, which is why it can ship on by default.
- **It can never close the whole position.** The steps may close at most 90%
  between them, and a configuration asking for more is refused at startup. The
  residual is what keeps the trailing stop, the break-even lock and the weekend
  close in charge of the trade.
- **One step per management pass.** Each step is its own broker operation, and a
  pass that sent three of them would size the second and third from a volume the
  first has not been confirmed to have changed. A candle that jumps through every
  level banks one step per pass instead, at whatever the market is then — which
  is at or beyond the level either way, because a trigger is only ever reached
  from the profitable side.
- **The trigger is the exit-side price** — the Bid for a long, the Ask for a
  short — because that is the price the position could actually be closed at.
- **Profit first, then protection, on the same pass.** Banking a step runs a
  reconciliation that can compact the state array and rebind a broker ticket, so
  everything the trail needs is re-resolved afterwards rather than reused. The
  trail still runs: the tick that made the trade enough progress to bank a step
  is the tick its stop most wants ratcheting on.

### A step that cannot be taken is skipped, not forced

MT5 refuses a partial close that is below the symbol's minimum volume or that
would leave a residual below it. A step whose share rounds under either bound is
therefore skipped, logged once, and the whole position simply stays on its
trailing stop.

This is the common case on a small account, not an edge case. With a 0.01
minimum lot the shipped two-step ladder needs roughly **0.03 lots** on the
position before either step can fire. Below that the ladder is inert and the
journal says so once per position.

### Which steps have been banked survives a restart

The set of banked steps is a bitmask persisted per position alongside the trail
peak. A step re-fired after a restart would close the same share of the trade
twice; a step forgotten would leave money the operator configured to bank sitting
on the trailing stop instead. A stored value naming a step this build does not
have is read as "nothing banked", which is safe only because every step is
re-tested against the live price before it can fire — a level the trade has not
reached cannot be re-taken by forgetting it.

It is a bitmask rather than a count because a step that could not be closed does
not block the steps above it, so the banked set is not necessarily a prefix.

### The hard target ships off, and that is the recommendation

`InpFlowFinalTargetR` places a real broker-side take-profit on the whole
remainder. It is off by default, and not out of caution about an unproven
feature: a fixed cap on the one part of the trade that is deliberately left
running is the opposite of what the ladder above it is for. It exists for an
operator who wants an exit that fills while the terminal is closed, and it is
theirs to switch on.

Switching it on is the only setting in the group that reaches the **entry** path.
The execution engine derives the target from the ratio at send time and then
judges the broker-valid result against a band of 0.95× to 1.25× the requested
distance. The band is asymmetric because broker stop-level validation only ever
pushes a take-profit *further* from the market: the lower edge absorbs price
rounding, and the upper edge is the question "is this still the trade that was
intended". A broker that has to push the target past the upper edge refuses the
entry rather than silently retargeting it, and the refusal is made at planning
time so the candle's signal is not consumed first.

With `InpFlowFinalTargetR = 0` the order is sent with `TP = 0` exactly as before,
and the defensive refusal that guarantees it is unchanged.

### Turning the whole thing off

Set `InpFlowTP1AtR` and `InpFlowTP2AtR` to 0 and the strategy is the original
no-target rule, price for price. `presets/xauusd-m30-candleflow-plain-trail.set`
writes all seven settings out as explicit zeros — a `.set` file applies only the
identifiers it lists, so a baseline that omitted them would silently be measuring
the ladder as well as the trail.

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

2. **`PositionManager.ManagePositions`** gained a trailing mode and, within it,
   the take-profit ladder. The default,
   `XSPARK_TRAIL_ATR_AFTER_PARTIAL`, is ScoreBot_v3's existing behaviour —
   partial close, break-even, then an ATR trail. `XSPARK_TRAIL_CANDLE_ANCHOR`
   takes an anchor price per direction from the caller, applies no
   break-even step, and ratchets the stop toward the anchor, tightening only.
   A missing anchor leaves the broker stop exactly where it is. The ladder runs
   inside that mode only, so a ladder handed to ScoreBot_v3's mode is never
   consulted at all.

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
  anchor leaves the stop untouched;
- the take-profit ladder: validation of every refusable configuration, the
  trigger prices in both directions, the banked-step bitmask, and — through the
  real `ManagePositions` source against broker doubles — that a step closes a
  share of the *opening* volume, never fires twice, is restored after a restart,
  is skipped when no legal volume exists, never runs in ScoreBot's trailing mode,
  and never erases a live broker take-profit.

It also compares, as source rather than behaviour, the three key lists that write,
restore and delete per-position state. The portable storage doubles copy whole
structs, so a key missing from one of those lists is invisible to a behavioural
fixture; that is how a pre-existing failure to delete the excursion keys went
unnoticed, and the check now fails the build on it.

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
