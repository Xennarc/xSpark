# Smart Money Concepts (XSparkSMC)

XSparkSMC runs a mechanized reading of a published Pine v5 **indicator** —
"Smart Money Concepts" — as a trading rule. It ships as its own Expert Advisor,
`MQL5/Experts/XSparkSMC/XSparkSMC.mq5`, with its own Magic Number, and reuses
every shared component unchanged: safety, risk, sizing, execution, position
management and state persistence. The rule itself lives in
`MQL5/Include/XSpark/Strategy/SmartMoney.mqh`.

**Nothing in this document is a profitability claim.** No backtest, forward test
or live result is recorded in this repository, and none of the numbers below was
measured. Trading is disabled by default (`InpSmcEnableTrading = false`).

## What was transcribed and what was decided

This is the part to read first, because the honest answer to "turn this
indicator into an EA" is that half of an EA is not in the indicator.

The source **draws and alerts**. It has no entry, no stop, no target and no
position size. So the work divides in two, and the header file marks every line
of the division.

### Transcribed, shape for shape

| Piece | Source behaviour kept |
| --- | --- |
| Leg / pivot detector | `high[size] > ta.highest(size)` — a **one-sided** confirmation window, with nothing to the left of the pivot consulted. Not a symmetric pivot. |
| Two structures | Internal (5 candles) and swing (50 candles) — the published pair, and the Normal swing size — each with its own pivots, its own `crossed` flags and its own BOS/CHoCH bias. |
| The `distinct level` rule | An internal break at exactly the swing pivot's level is not counted as internal structure. |
| Crossover semantics | Pine's `ta.crossover` reads *both* arguments one bar back, so a break is measured against the level that existed when the earlier close printed. |
| Order block | The extreme bar of the leg that broke structure — highest parsed high for a bearish break, lowest parsed low for a bullish one — with ties going to the **oldest** bar. |
| The volatility parse | A bar at least twice the volatility measure has its high and low swapped before the comparison, which deflates one violent candle out of every order block on the chart. |
| Mitigation | A bullish block dies when price trades below its low, a bearish one when price trades above its high, on the high/low source. |
| Trailing extremes | Extended by every bar, re-anchored by every swing pivot; the Strong/Weak High and Low the indicator labels. |
| Equal highs and lows | 3-bar window, 0.1 × volatility threshold. |
| Fair value gaps | Three bars whose outer two do not overlap, with the source's automatic displacement threshold (twice the mean absolute body). |

### Decided here, because the source is silent

| Decision | What was chosen, and why |
| --- | --- |
| Entry | A **limit** at the order block's midpoint. Not the near edge (fills more often at a worse price) and not the far edge (a better price that frequently never trades). |
| When the entry is live | While the block is unmitigated, inside the shelf life the swing size sets (60 candles on Normal), and the structure that created it still points its way. |
| Location filter | Buys only from the **discount** half of the dealing range, sells only from the **premium** half — read off the indicator's own trailing extremes. |
| Stop | Beyond the block's far edge by 20 points. This is not an arbitrary level: it is exactly where the indicator deletes the block, so the stop and the model's own invalidation are the same line. |
| Target | The **draw on liquidity** — the trailing extreme the indicator labels Strong or Weak. A price, not a ratio. |
| Reward ratio | An **output**. Whatever that level implies against the stop, bounded to 1.5–20 so a draw too close to pay for the stop is refused and one very far away is treated as a different trade. |
| Hold time | 96 bars or 48 hours, whichever comes first. |

### Departures from the source, stated rather than hidden

Three, all in the header with the same wording:

1. **Mitigation is compacted.** The published loop removes elements while
   iterating over the same array, which skips the element after each removal —
   so two blocks mitigated by one bar leave one of them on the chart. This
   removes both.
2. **Gap mitigation is symmetric.** In the source a bullish gap survives until
   price passes its *far* edge while a bearish gap dies the moment price touches
   its *near* one, a consequence of the bearish record storing its two edges the
   other way round. For a drawing that is cosmetic. For a rule asking "does this
   imbalance still exist" it is two different questions wearing one name, so both
   sides are read the same way here.
3. **A swapped block is ordered.** The volatility parse can leave a block whose
   stored "high" is below its "low", which draws an upside-down box and is
   meaningless as a zone. The ordered pair is taken.

The confluence filter in the source is **not** implemented, and that is also a
departure. Its published expression (`high - max(close, open) > min(close, open -
low)`) compares a price to a distance; it is off by default in the source, and
mechanizing it faithfully would mechanize a defect.

Four features of the indicator are **display only** and are absent rather than
skipped: the boxes and labels themselves, the multi-timeframe previous
day/week/month levels, the fair-value-gap timeframe selector, and the
premium/discount zone bands (the concept is used; the 5% band drawing is not).

## State is rebuilt, never carried

Pine keeps structure state from the first bar of the chart. An Expert Advisor
cannot: it restarts, it reconnects, and RAM state that survives neither is state
that silently differs between a tester pass and a live run.

So every bar this model **replays** the indicator over a fixed window of 160
closed bars, oldest to newest, in the indicator's own per-bar order, and reads
the answer off the end. The per-bar order is load-bearing: trailing extremes are
extended before a new pivot can re-anchor them, structures are read before breaks
are tested against them, and blocks are mitigated *after* the bar that created
them — so a block the market immediately traded through never survives its own
bar.

Two consequences, both deliberate:

- The same window always gives the same answer, on any terminal, after any
  restart, in the tester and live. There is nothing to reconcile.
- **Structure older than the window does not exist.** A swing pivot that has
  scrolled off is gone, and the bias is whatever the window shows. This is the
  price of determinism and it is paid knowingly.

It is also what makes a limit entry workable without stored state. The
retracement into an order block almost never happens on the bar that broke
structure, so the setup has to stay live for many bars. Because the whole state
is rebuilt each bar, that patience costs nothing: the same block is re-derived,
and the entry is asked for again, until it fills, the block is mitigated, the
structure flips, or the block ages out.

One trade per break, not one per bar: the signal is keyed on the **structure
break's** timestamp rather than on the bar being evaluated, so the execution
engine's duplicate-submission guard counts setups rather than candles.

A stopped-out setup cannot re-fire, and that falls out of the geometry rather
than from a flag: the stop sits beyond the block's far edge, so price reaching
it has also mitigated the block, and the next replay does not contain it.

## Every indicator setting, and what became of it

The published indicator has about forty settings. This is all of them, and where
each one went. Read it as the answer to "did you actually port the thing" —
nothing below is omitted because it was missed.

### Became a lever

| Indicator setting | Lever here |
| --- | --- |
| Internal Order Blocks / Swing Order Blocks (which to show) | `InpSmcStructure` — which structure's breaks to trade |
| Bullish / Bearish Structure = All, BOS, CHoCH | `InpSmcBreakType` — reversals, continuations, or both |
| Show Swings Points length (50) | `InpSmcSwingSize` — how big a swing counts as structure |
| Premium/Discount Zones on/off, Fair Value Gaps on/off | `InpSmcSelectivity` — how much must line up before entering |

### Became a constant, at the indicator's own published value

| Indicator setting | Value here | Why it is not a lever |
| --- | --- | --- |
| Order Block Filter (Atr / Cumulative Mean Range) | cumulative mean range | The indicator's own note recommends the mean range "when a low amount of data is available", and a 160-candle window cannot hold a 200-period ATR. One correct answer, not a choice. |
| Order Block Mitigation (Close / High/Low) | High/Low | In the indicator this decides when a box stops being drawn. Here that same level is the **stop**, and a zone price has already traded through is not an entry at any price — so High/Low, its own default, is the only reading consistent with the stop. |
| EQH/EQL Bars Confirmation (3), Threshold (0.1) | 3 and 0.1 | Numbers that can only be copied from their defaults. Here they affect one line of the journal, not an entry. |
| Fair Value Gaps → Auto Threshold | on | The source's default, and the only setting that makes the gap test scale-free. |
| Internal structure length (hard-coded 5 in the source) | moves with `InpSmcSwingSize` | Kept at 5 on the Normal size, scaled with the swing on the other two so the internal structure stays roughly a tenth of the swing. |

### Not implemented, and why

| Indicator setting | Why |
| --- | --- |
| Mode (Historical/Present), Style (Colored/Monochrome), Color Candles | Drawing. This EA draws nothing. |
| Show Internal Structure, Show Swing Structure, Show Strong/Weak High/Low, Show Swings Points (the checkboxes) | Visibility toggles. The model always computes all of it; there is nothing to hide. |
| All label sizes, all colours, Extend FVG | Presentation. |
| Confluence Filter | Off in the source, and its published expression (`high - max(close, open) > min(close, open - low)`) compares a price to a distance. Mechanizing it faithfully would mechanize a defect. |
| Fair Value Gaps → Timeframe | A second chart period's gaps, drawn on this one. The model reads one chart period. |
| Highs & Lows MTF (Daily, Weekly, Monthly + styles and colours) | Drawn levels from other chart periods. A genuine addition would be to use them as a draw-on-liquidity target; that is new behaviour, not a setting. |
| Premium / Equilibrium / Discount zone colours, and the 5% band geometry | Presentation. The *concept* is a lever (`InpSmcSelectivity`); the bands are a drawing. |

## Settings

Fourteen, and most people change two of them.

A setting earns a place in the Inputs tab only if the operator knows something
the code does not. You know your account, your broker's commission and your
appetite for risk, so those are settings. Nobody knows better than the code what
counts as a pivot, how wide a stop buffer should be, or where the liquidity is —
so the swing length, the internal length, the equal-high threshold, the
volatility multiple, the stop buffer and the reward bounds are all constants in
the header, at the source's own published values.

| Input | Default | What it does |
| --- | --- | --- |
| `InpSmcEnableTrading` | false | Place real trades. Off watches and logs only. |
| `InpSmcRiskPct` | 1.0 | Money risked on one trade, as a percentage of balance. |
| `InpSmcStructure` | Internal break, swing must agree | Which structure's breaks to trade. |
| `InpSmcBreakType` | Both | Reversals, continuations, or both. |
| `InpSmcSwingSize` | Normal | How big a swing counts as structure. |
| `InpSmcSelectivity` | Balanced | How much must line up before entering. |
| `InpSmcCommissionPerLot` | 0.0 | Commission per 1.0 lot both ways, in account money. |
| `InpSmcMinLotRiskCapPct` | 3.0 | How much the broker's smallest trade may risk on a small account. |
| `InpSmcMaxDailyDDPct` | 6.0 | Stop opening trades if the account falls this much today. |
| `InpSmcUseTotalDDKillSwitch` | true | Emergency stop: close everything on a big account fall. |
| `InpSmcMaxTotalDDPct` | 20.0 | The fall that sets it off. |
| `InpSmcMagicNumber` | 770335 | This bot's ID tag. A different one per chart. |
| `InpSmcVerboseLog` | false | Detailed logs, for troubleshooting. |
| `InpSmcClearKillswitchLatch` | false | Clear the emergency stop once, then set back to false. |

### The four strategy dropdowns

All four are **named choices**, not numbers: every value is a configuration that
is internally consistent on its own, so there is no combination to get wrong. A
dropdown that moves three numbers together exists precisely so that a fast swing
with a slow memory — which is not a faster version of this rule, it is a
different rule — cannot be assembled from the Inputs tab.

**`InpSmcStructure` — which structure's breaks to trade**

- *Internal break, the swing trend must agree* (default). Under this setting a
  buy is only ever taken toward a **Weak High**, which is the extreme the
  indicator's own swing bias says is likely to be taken. That is not a
  coincidence; it is why this is the default.
- *Internal break alone* — more trades, no trend filter.
- *Swing break alone* — far fewer trades.

**`InpSmcBreakType` — reversals, continuations, or both**

The indicator's All / BOS / CHoCH filter. There it decides which labels are
drawn; here it decides which breaks are traded, which is the same distinction
doing real work.

- *Both* (default).
- *Reversals only* — a change of character is the **first** break against the
  prior bias: the turn, taken early and wrong more often.
- *Continuations only* — a break of structure extends a bias that already
  exists: later, and in the direction the market has already chosen.

**`InpSmcSwingSize` — how big a swing counts as structure**

One choice, three numbers: the swing length, the internal length, and how long
an order block stays enterable.

| Value | Swing | Internal | Block shelf life | Replay candles left |
| --- | --- | --- | --- | --- |
| Fast | 20 | 3 | 30 | 139 |
| Normal (default) | 50 | 5 | 60 | 109 |
| Slow | 65 | 8 | 70 | 94 |

That last column is the one to look at, and it is why there is no slower choice.
The window is fixed at 160 closed candles, and a swing pivot is only confirmed
once `swing_length` newer candles have printed past it — so a bigger swing buys
**fewer** candles to find one in. The dealing range needs a swing high *and* a
swing low, so on Slow the model can spend long stretches reporting
`RANGE UNKNOWN`. The EA prints that arithmetic on its first bar and warns when
the window is tight for the chosen size, rather than letting the funnel reveal
it a week later. Slow is offered because it is the indicator's own axis, not
because it is recommended.

**`InpSmcSelectivity` — how much must line up**

The indicator's Premium/Discount Zones and Fair Value Gaps switches, folded into
one dial because they are the same question asked twice.

- *Balanced* (default) — enter only from the discount half for a buy and the
  premium half for a sell.
- *Strict* — that, **and** the leg must have left an unfilled price gap.
- *Permissive* — enter the block wherever it sits in the range. This is the
  setting that turns the `WRONG HALF` funnel counter off, and it is also the one
  that lets a buy be taken at the top of a range.

### Commission is not optional on a commission account

The commission feeds two things: the cost floor on the stop, and the **minimum
width an order block must have to be worth entering**. A block whose midpoint is
inside the spread is not a zone. Leaving `InpSmcCommissionPerLot` at zero on an
account that charges commission under-counts both.

## What the journal tells you

Two lines print after the first bar and again on every broker day:

- the **cost line** — spread plus commission as a share of the widest stop this
  chart period allows, the win rate a trade with no edge would show at the
  nearest draw this bot will take, and whether the chart period is FEASIBLE at
  the current cost;
- the **minimum-lot line** — what the broker's smallest trade risks at the widest
  stop, and whether the small-account cap will let it through.

Then, every broker day, the **funnel**: one counter per place the sequence can
stop, so a run that takes no trades says *which* condition the market never
produced instead of going silent.

```text
NO STRUCTURE  BLOCK EXPIRED  STRUCTURE FLIPPED  AGAINST SWING  WRONG BREAK TYPE
BLOCK TOO THIN  NO IMBALANCE  RANGE UNKNOWN  WRONG HALF  NO DRAW
DRAW TOO CLOSE  DRAW TOO FAR  COST BLOCKED  SPREAD BLOCKED  SIZE BLOCKED
SIGNAL  ENTERED  OTHER
```

Four of these are worth knowing about in advance, because each one names a
**setting** rather than a market:

- `AGAINST SWING` — `InpSmcStructure` is keeping the bot flat, not the market.
- `WRONG BREAK TYPE` — `InpSmcBreakType` is.
- `WRONG HALF` — `InpSmcSelectivity` is.
- `RANGE UNKNOWN` — `InpSmcSwingSize` is too slow for the 160-candle window.

And one is a quirk of the geometry: `NO DRAW` is effectively unreachable while
the premium/discount filter is on, because an entry in discount is by definition
below the top of the dealing range. The filter and the draw check are not
independent conditions.

## Exits

Every trade sees the same exits, and there are only three:

- the broker-side **stop**, beyond the order block's far edge;
- the broker-side **target**, derived by the execution engine from the ratio the
  draw on liquidity implied;
- the **hold time**, 96 bars or 48 hours, whichever binds first, deferred while
  the spread is wider than a quarter of the typical candle so a time stop coming
  due across the rollover does not pay the rollover spread.

Plus the weekend backstop, read from the symbol's own Friday session rather than
assumed. There is no trailing stop, no partial close, and no separate
"structure broke against me" exit — the stop already sits where the setup is
invalidated, so a second invalidation would only be the first one arriving late.

## What is tested, and what that proves

`MQL5/Scripts/Tests/TestSmartMoney.mq5` holds 138 deterministic checks, run in
CI through `tools/test_portable_logic.py` and runnable inside MetaTrader as a
script. They cover the leg detector, the volatility measure, the rings and
mitigation, fair value gaps, the order block search including its tie rule and
its volatility parse, the full replay against a 160-bar fixture whose structure
is known by construction, equal highs and lows, every refusal path in the rule,
the configuration validator, every value of every dropdown (including that each
swing size fits the structure window and leaves enough replay to be able to
produce a swing at all), the cost and stop arithmetic, the Wilson bound, the
hold time, the weekend backstop, and the strategy object end to end.

**None of that measures an edge.** A rule that fires exactly where it was
designed to fire is a correct rule, not a profitable one. These tests say the
indicator is faithfully transcribed and the trade built on it behaves as
described. Only out-of-sample testing can say whether it is worth trading.

CI does **not** compile MQL5. `tools/test_portable_logic.py` transpiles the
headers to C++ and compiles them with `-Wall -Wextra -Werror`;
`tools/check_ea_inputs.py` and `tools/check_ea_call_arity.py` are source
analysis. Compilation in MetaEditor is a separate step and has not been
performed for this strategy.

## Reading the tester result

`OnTester` reports **expectancy**, not the win rate, and that follows from the
model rather than from taste. The target is the draw on liquidity, so every trade
carries its own reward ratio and there is no single break-even win rate to test a
proportion against: 40% wins is losing at 1.5R and winning at 4R. Mean R against
zero is the only question the sample can actually answer.

The win rate and its 95% Wilson lower bound are still printed, as description.
They are deliberately not turned into a verdict.

Below 30 outcomes the verdict is `EXPECTANCY NOT TESTABLE`. Above it, either
`EXPECTANCY NOT DISTINGUISHABLE FROM ZERO` or `EXPECTANCY ABOVE ZERO AT 95%`.
Read that line, not the equity curve.
