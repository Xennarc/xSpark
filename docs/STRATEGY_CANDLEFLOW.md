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

Nine, and most people change two of them.

A setting earns a place in the Inputs tab only if the operator knows something
the code does not. You know your account and your appetite for risk, so those
are settings. Nobody knows what to allow for entry slippage as a percentage of
the smallest producible stop — a number like that can only be copied from a
default, and a number that can only be copied is not a choice, it is a way to
get it wrong.

| Input | Default | What it does |
| --- | --- | --- |
| `InpFlowEnableTrading` | false | Place real trades. Off watches and logs only. |
| `InpFlowRiskPct` | 1.0 | Money risked on one trade, as a percentage of balance. |
| `InpFlowProfitStyle` | Balanced | Whether and when profit is banked as the trade runs. |
| `InpFlowTrailStyle` | Balanced | How much room an open trade is given. |
| `InpFlowMaxDailyDDPct` | 15.0 | Stop opening trades if the account falls this much today. |
| `InpFlowMaxTotalDDPct` | 25.0 | Close everything if the account falls this much. 0 switches it off. |
| `InpFlowMagicNumber` | 770332 | This bot's ID tag. A different one per chart. |
| `InpFlowVerboseLog` | false | Detailed logging, for troubleshooting. |
| `InpFlowClearKillswitchLatch` | false | Clear a latched emergency stop once, then set back to false. |

### The two styles

Both are dropdowns, and every choice is a complete configuration that the test
suite proves is internally consistent. There is no combination of numbers here
that can quietly stop the bot from trading, because there are no numbers.

**`InpFlowProfitStyle`** — whether to take money off the table on the way.

| Choice | What it does |
| --- | --- |
| Off | The trailing stop is the only exit. The strategy's original behaviour. |
| **Balanced** | Bank 40% of the trade at 1.5× the amount risked and 30% at 3×, leaving 30% running. |
| Early | Bank 50% at 1× and 25% at 2×, leaving 25% running. A smoother, smaller curve. |

**`InpFlowTrailStyle`** — how much room the trade is given before the stop acts.

| Choice | What it does |
| --- | --- |
| Candle only | Follow the last finished candle and nothing else. The bare rule. |
| **Balanced** | Follow 3× the typical candle behind the best price, tightening to 1.5× as the trade matures, and protect the entry once it is 1.2× the amount risked in front. |
| Tight | The same shape, brought forward: 2× tightening to 1×, entry protected at 0.8×. |

"The amount risked" is the distance from the entry to the first stop, so "2 × the
amount risked" is twice that distance in your favour.

### The two comparisons worth running

Both are one dropdown change, which is why the preset files that used to exist
for them are gone:

- **Did banking profit help?** `InpFlowProfitStyle` Balanced against Off.
- **Is the trailing stack earning its complexity?** `InpFlowTrailStyle` Balanced
  against Candle only.

Change one, run the same period, compare. Run it on **real ticks**: the
take-profit levels trigger on a tick-resolution price while the trail's
high-water mark only advances on finished candles, so low-resolution modelling
understates the levels.

### What is no longer a setting

Sixty-four inputs were removed. They fall into three groups, and the reasoning
differs for each.

**Measured from the market, not chosen.** The widest spread worth trading
through, how far a price may drift while an order travels, and what counts as a
quiet or wild market are all derived at startup from the instrument's own recent
range. That derivation is exactly what lets one configuration be correct on gold
and on an FX pair without anyone editing anything — so it stayed, and its knobs
went. There is no longer a way to turn it off, and no manual fallback to get
wrong. See ADR-033.

**Fixed, because there was never a second sensible value.** The wick buffer, the
stop floor, one trade at a time, the panel's position and size. These live in
`Strategy/CandleFlow.mqh` beside the rule they belong to.

**Read from the instrument, because they are properties of it.** The weekend
close used to be a Friday hour and minute you typed in. It is now taken from the
symbol's own trading sessions: the bot flattens two hours before that
instrument's last Friday session ends, and does not flatten at all on an
instrument that trades through the weekend. A hard "Friday 20:00" was the gold
answer applied to everything — hours early on a market open until 22:00, and
meaningless on one that never closes. If the broker reports no usable Friday
session the old 20:00 is used and the journal says so, because closing early is
the safe direction to be wrong in.

**Mandatory, because switching them off was never the right answer.** The spread
filter, the broker's minimum-stop-distance check, the free-margin check, the
stale-quote gate and the weekend close can no longer be disabled. Removing a
switch from a safety control does not weaken it; it removes the only way to
weaken it.

## The trailing stop

The trailing stop is the exit for whatever the take-profit ladder leaves running,
and the only exit at all when the ladder is switched off. It is built from four
layers. On each closed candle every enabled layer proposes
a stop, the **most protective** one wins, and the result is then bounded by the
floor and by a one-way ratchet that refuses anything looser than the live stop.

| Layer | Balanced | What it proposes |
| --- | --- | --- |
| Candle anchor | always on | the far wick of the last closed candle, plus the buffer |
| Chandelier | **3.0** | this many typical candles back from the best price the trade has seen |
| Tiering | **1.0 / 4.0 / 1.5** | shrinks the chandelier multiple linearly as the trade matures |
| Breakeven lock | **1.2 / 0.1** | entry ± offset, once the trade has been that far in front |
| Floor | **0.35** | not a proposer — it pushes the winner away from the market if it landed too close |

Those are the **Balanced** numbers. Candle only turns every layer off and keeps
the floor; Tight uses 2.0 / 0.5 / 2.5 / 1.0 and locks the entry at 0.8. The
tables live in `Trade/TrailingStop.mqh` as `XSPARK_TRAIL_*`, which is what
`TestTrailingStop.mq5` validates — so a style that would block trading cannot
reach a chart.

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
| 1 | 1.5 × its own initial risk in front | 40% of the **opening** size | 60% |
| 2 | 3.0 × in front | another 30% of the opening size | 30% |
| 3 | off by default | — | — |

The first step is the larger one deliberately. The failure being addressed is a
trade that runs well and then hands it back, and the earlier share is the one a
retrace cannot reach.

Every distance is a multiple of the distance from the entry to the **first** stop,
so the ladder rescales with the instrument and the timeframe exactly as the trail
does. Every percentage is of the volume the position **opened** with, never of
what is left — percentages of a shrinking remainder would bank a different share
of the trade at each step than the one configured, and would never reach zero.

Internally a step is a **budget** rather than a share to close: "bring this
position down to 60% of what it opened with", not "close 40% of it now". In the
ordinary case those are the same order. They differ in the two cases that
matter, and both differences are the point:

- A close the broker **confirmed** but that XSpark never got to record — the
  terminal died in between — is a step with nothing left to do, rather than a
  second 40% off the same trade on restart.
- A step that had to be **skipped** because its share was below the broker's
  minimum volume is made good by the next step, which closes its own share and
  the skipped one together, rather than being lost for the rest of the trade.

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
  first has not been confirmed to have changed. A candle that jumps through
  several levels takes the **furthest** one in a single order — its budget
  already contains every share below it — at the price the market is actually
  at, rather than banking the nearest share now and leaving the rest to a later
  pass at a price that may have retraced.
- **A rejected close backs off.** A crossed trigger stays crossed, so a broker
  that refuses the order would otherwise get one every tick for the rest of the
  trade. After a rejection the step waits 30 seconds, and after five consecutive
  rejections the ladder switches itself off for that position until the EA
  restarts. The trailing stop is unaffected throughout.
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

With a 0.01 minimum lot the shipped ladder fires both of its steps from
**0.03 lots** upward. Below that it banks little or nothing, and the journal
says so once per position.

Shares are normalised **down**, so a small position banks slightly less than
configured and never more — which is the safe direction, because the shortfall
stays open under the trailing stop. Worked through, at a 0.01 minimum and step:

| Opening size | Step 1 closes | Step 2 closes | Banked | Left running |
| --- | --- | --- | --- | --- |
| 0.03 | 0.01 | 0.01 | 67% | 0.01 |
| 0.05 | 0.02 | 0.01 | 60% | 0.02 |
| 0.10 | 0.04 | 0.03 | 70% | 0.03 |
| 1.00 | 0.40 | 0.30 | 70% | 0.30 |

This is also why the first step is 40% rather than 30%: at 0.03 lots a 30%
share rounds to nothing and the step is skipped entirely, where 40% rounds to
0.01 and fires.

### Progress survives a restart

How far up the ladder a position has been banked is persisted alongside the
trail peak, as the R multiple of the highest step already taken. A step
forgotten across a restart would leave money the operator configured to bank
sitting on the trailing stop instead.

A stored value that cannot be trusted — not a number, negative, or past the
ceiling — is read as "every step is already behind us", which makes the ladder
**inert** for that position rather than replaying it. A module that cannot trust
its own record of what it has done to a live position must not cause another
broker operation on the strength of it, and the position keeps its trailing stop
either way.

The persisted value is not what stops a confirmed-but-unrecorded close from
being repeated — the budget arithmetic above is. The two are independent on
purpose: losing the record costs accuracy, never a second close.

If a confirmed close cannot be recorded at all against a position that is still
live, XSpark no longer knows what it has banked. That is the ambiguous state
AGENTS.md rule 24 exists for, so the EA raises its state-recovery latch: new
entries stop, open positions keep being managed, and the panel says so.

### The hard target ships off, and that is the recommendation

A hard broker-side take-profit on the whole remainder is supported by the code
and is **off in every shipped style**. That is not caution about an unproven
feature: a fixed cap on the one part of the trade deliberately left running is
the opposite of what the ladder above it is for. It stays reachable because a
future style may want it — `XSparkProfitLadder.final_target_r` — but no choice
in the Inputs tab turns it on.

Were a style to switch it on, it would be the only exit choice reaching the **entry** path.
The execution engine derives the target from the ratio at send time and then
judges the broker-valid result against a band of 0.95× to 1.25× the requested
distance. The band is asymmetric because broker stop-level validation only ever
pushes a take-profit *further* from the market: the lower edge absorbs price
rounding, and the upper edge is the question "is this still the trade that was
intended". A broker that has to push the target past the upper edge refuses the
entry rather than silently retargeting it, and the refusal is made at planning
time so the candle's signal is not consumed first.

With the target at zero — which is every shipped style — the order is sent with
`TP = 0` exactly as before, and the defensive refusal that guarantees it is
unchanged.

### Three consequences you cannot see from the Inputs tab

1. **A banked step lowers the position's live volume**, which `AccountExposure`
   sums, so it frees budget under the account risk cap. That is inert while this
   bot holds one trade at a time, which it now always does. It is
   not martingale — nothing sizes from a previous outcome — but it is a
   behaviour change in an account-level risk control, so it is written down.
2. **A hard target, were a style to set one, puts every entry under a
   reward-ratio band.** A broker whose stop level pushes the target more than 25% past the
   requested distance has the entry refused outright, with the candle's signal
   already spent. The refusal is in the journal; the panel shows the reason.
3. **The Strategy Tester's modelling mode changes the result.** The ladder
   triggers on a tick-resolution exit-side quote, while the trail's peak advances
   only on closed candles. Under "Open prices only" a spike that reaches 3R
   inside a bar and closes back at 0.5R never banks a step at all, so
   **low-resolution modelling understates the ladder**. Run the comparison on
   real ticks or it measures the modelling rather than the change.

### What the ladder costs, honestly

Taking profit in steps does not raise expectancy. It moves money out of the
right tail and into the middle. A long from 100 risking 2.00, with the shipped
1.5R/40% and 3.0R/30%:

| The trade | Without the ladder | With it |
| --- | --- | --- |
| Runs to 6R, trails out at 3.5R | **3.50R** | 0.4(1.5) + 0.3(3.0) + 0.3(3.5) = **2.55R** |
| Runs to 3.5R, gives it all back to the break-even lock | **0.10R** | 0.4(1.5) + 0.3(3.0) + 0.3(0.1) = **1.53R** |

The second row is the shape that was reported. Whether the change is net
positive depends entirely on the give-back distribution in your own data, which
is what the no-targets preset below exists to measure. If total profit falls on a
trend-following rule after adding this, that is the first row happening more
often than the second — not the feature being broken.

### Turning the whole thing off

Set `InpFlowProfitStyle` to Off and the strategy is the original no-target rule,
price for price.

Two presets write all seven settings out as explicit zeros, because a `.set`
file applies only the identifiers it lists and a baseline that omitted them
would silently be measuring the ladder as well as whatever else it changed:

- **`presets/xauusd-m30-candleflow-no-targets.set`** — the full trailing stack,
  ladder off. This is the **only one-file A/B for "did the ladder help"**: it
  differs from `xauusd-m30-candleflow.set` in the take-profit settings and
  nothing else.
- **`presets/xauusd-m30-candleflow-plain-trail.set`** — ladder off *and* every
  trailing layer off. Comparing against this measures four changes at once, so
  it answers a different question: whether the trailing stack earns its
  complexity.

### The floor is not optional

A trailing stop that can land a few points from the bid is a delayed market
order. A narrow candle, or a tightened chandelier late in a move, will do
exactly that, and the spread alone then closes a position whose move was still
intact. The trail floor widens any such candidate back to a survivable distance
from the market, in every style including Candle only.

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

Between the two tiering marks the chandelier
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
same percentage risk. The stop floor widens such a stop to a bound measured
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

The slot limit already blocks a second trade of any direction, and it is now
fixed at one. This check is what holds the rule regardless — it is enforced by
`ExecutionEngine` for every strategy, not only this one.

## Running it next to ScoreBot_v3

Both EAs can run on the same account at the same time. They are separated by
Magic Number — `770331` for XSpark/ScoreBot_v3, `770332` for
XSparkFlow/CandleFlow — and every component that touches broker state filters on
it: position reconciliation, the per-position state store, the trailing stop, the
weekend close and the killswitch flatten. Neither bot can see, modify or close
the other's positions.

The one thing they *do* share is the account. CandleFlow's account risk cap is
checked against **all** open positions, including the other bot's, so it refuses
an entry that would push total open risk past it. CandleFlow's cap is fixed at
6%; ScoreBot's is still an input, so set that one with the combined account in
mind.

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
  trigger prices in both directions, the cumulative shares and the volume budget
  they imply, the persisted progress value, and — through the
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
