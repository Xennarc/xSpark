# XSpark Improvement Plan

Goal set by the account owner: maximise profitability, higher risk acceptable, the bot
must take better trades.

Status: plan only. No code in this document has been written, compiled or tested.
There is no MetaEditor and no market data in the environment that produced it, so every
number here is arithmetic over source read directly from this repository or over the one
supplied 50-trade Strategy Tester report. Nothing here is a backtest result.

---

## 1. Baseline

Money-mode run, XAUUSDm M15, Exness demo hedging, 10 000 USD, 1:100, every tick based on
real ticks, 2026.09.01 to 2026.09.15, all inputs at defaults.

| Metric | Value |
| --- | --- |
| Net profit | +406.61 USD |
| Profit factor | 1.11 |
| Trades / deals | 50 / 100 |
| Win rate | 36.00 % |
| Average win / loss | 226.80 / -114.87 |
| Payoff ratio | 1.974 |
| Longest losing run | 8 trades, -795.62 USD |
| Maximal equity drawdown | 902.39 USD (7.98 %) |

---

## 2. Diagnosis

The bot does not take mediocre trades because a filter is mis-tuned. It takes them
because nothing in the system can measure trade quality, and because several decision
channels are structurally broken in ways that are wrong regardless of any backtest.

### 2.1 The entry gate does not gate

`raw = pattern + atr + trend + rsi + sr + volume + mtf`, where the `atr` component is the
literal constant `1.0` assigned once the ATR band passes. Every pattern emits a score
above 1.0, so `raw` always exceeds 2.0.

`final = raw * session_weight` is compared against `InpMinScore = 2.0` with `>=`.

| Session weight | Hours (server) | Raw score needed | Binds? |
| --- | --- | --- | --- |
| 1.2 | 12 to 15 | 1.667 | No |
| 1.0 | 7 to 11, 16 to 20 | 2.000 | No |
| 0.6 | 21 to 23, 0 to 6 | 3.333 | Yes |

During London and New York the five confirmation components decide the risk tier and
nothing else. They never decide whether the trade happens. The risk manager re-tests the
same comparison in `IsSignalApproved`, which adds no selectivity.

### 2.2 The risk tier is contaminated by the clock

Tier selection reads the session-weighted score, so identical evidence sizes at 1 % or
2 % purely by hour. At weight 0.6 the maximum reachable final score is `7.5 * 0.6 = 4.5`,
exactly the tier-2 threshold, so tier 3 is arithmetically impossible in Asian hours.

### 2.3 The exit-management stack is dead code

- The partial close triggers at 2.5 R. The broker take-profit sits at `RR * R` with
  `RR <= 3.0`, and `RR > 2.5` requires `ATR14 / ATR50 > 1.1`. For every other trade the
  broker closes the position before the partial condition can become true.
- Break-even executes only inside the `if(ClosePartial(...))` success branch.
- Trailing is gated on `partial_done`.
- The trail distance is `2.0 * ATR14` against a `1.5 * ATR14` stop, so the trail is
  1.333 R wide and is looser than the initial stop.

The repository already says so at `PositionManager.mqh:1429-1434`: "break-even and
trailing stay disabled for this position." 100 deals for 50 trades proves zero partials
fired in the baseline run.

### 2.4 The only ruin stop does not survive a restart

`SafetyManager::Initialize` sets the high-water equity to current equity and clears the
killswitch latch. Both are RAM-only, while the shorter-horizon daily halt is persisted.
The asymmetry is backwards. A recompile, an input change or a VPS reboot silently
re-anchors the ruin stop to the bottom of the hole. The baseline reached 7.98 % against
an 8.0 % limit, roughly two dollars of equity at the worst tick.

### 2.5 Nothing can be measured

There is no `OnTester`, no commission accounting, no MFE or MAE, and no machine-readable
per-trade record. `components.raw`, the only field that separates setup quality from
clock hour, reaches no log line. The exit log sums `DEAL_PROFIT` alone and overwrites the
exit price on every OUT deal, and the same defect exists twice, in
`PositionClosedInHistory` and in `LogClosureIfPossible`.

---

## 3. What the sample licenses

Nothing about entry quality.

| Quantity | Value |
| --- | --- |
| Break-even win rate at payoff 1.974 | 33.62 % |
| Observed win rate | 36.00 % |
| Distance from zero edge | 0.35 standard errors |
| Wilson 95 % interval on win rate | 24.1 % to 49.9 % |

Two independent derivations agree on the 0.35: on the win-rate side
`(36.00 - 33.62) / 6.79`, and on the R side `0.0708 / (1.4275 / sqrt(50))`. The
break-even rate sits comfortably inside the confidence interval. A driftless version of
this exact EA, same bars and brackets and costs, reproduces a profit factor of 1.11 a
significant fraction of the time.

**This also kills the most intuitive fix on the table.** The observation that many losers
ran to about +1 R before reversing to a full stop is exactly what a driftless walk
predicts. With barriers at -1 R and +1.974 R, the probability of touching +1 R first is
0.5, and from there the probability of returning to -1 R before the take-profit is
`0.974 / 2.974 = 0.3276`. That is 16.4 % of all trades, about 8 of 50, which is what the
report shows. Arming break-even at those levels gives

```
E[R] = 0.5 * (0.5066 * 1.974) + 0.5 * (-1) = 0.000
```

identical to the 0.000 without it, and then charges an extra spread crossing. Break-even,
trailing and the partial are variance transforms, not edge creators.

**So the honest diagnosis is conditional.** Either the three-candle pattern family carries
directional information greater than its cost, in which case the repairs below let that
information reach money for the first time, or it does not, in which case no filter can
create it and the answer is a different signal rather than a tighter one. At 50 trades
nobody can tell which. The first job is to find out. The second is to make sure the
account survives finding out.

---

## 4. Why the stage order is what it is

Selecting the best of `k` variants on a fixed sample inflates the winner by roughly the
expected maximum of `k` standard normals: 1.16 standard errors at `k = 5`, 1.54 at
`k = 10`, 2.16 at `k = 40`.

At the baseline's 6.79 percentage-point standard error on the win rate, a ten-variant
sweep manufactures a ten-point win-rate improvement out of pure noise. The six design
proposals reviewed for this plan collectively offered more than forty knobs. Sweeping
them now would reliably produce a configuration showing about 48 % win rate and a profit
factor above 2 with literally zero true edge, and it would look exactly like success.

That is the single most likely failure mode of this project. The stage order exists to
make it structurally impossible rather than merely discouraged.

---

## 5. The stages

Every stage ships behind defaults that reproduce current behaviour, and every stage has an
acceptance gate that can fail.

### Stage 1. Durable ruin stop, bounded risk inputs, server-clock diagnostic

| Change | Kind | Risk control |
| --- | --- | --- |
| Persist the total-drawdown high-water mark and latch | code | yes |
| Upper-bound and cross-check every risk input | code | yes |
| Print the consecutive-loss tolerance at startup | code | no |
| Log the server-to-UTC offset and resulting session windows | code | no |
| ADR-020 and deployment notes | docs | no |

Risk inputs are currently checked only for positivity. A fat-finger 20.0 is accepted
silently, and a tier above `InpMaxRiskPct` is flattened rather than rejected.

**Gate.** The baseline window reproduces exactly. A forced latch survives removing and
re-attaching the EA. Both test scripts report zero failures.

**Correction from audit.** Forcing a latch needs equity below a recorded peak. Setting the
limit below current drawdown does nothing, because the high-water mark is seeded to
current equity at initialise. The real procedure is to open a small manual losing position
on demo, set the limit to 0.1, confirm the critical log line, then restart.

### Stage 2. Cost-correct, machine-readable per-trade record

| Change | Kind |
| --- | --- |
| One shared deal accumulator, fixing the same two defects in both places | code |
| MFE and MAE with counterfactual probe levels | code |
| Running maximum spread and maximum spread over risk distance during the position | code |
| Enriched entry record carrying raw score, every component, spread and both ATRs | code |
| Enriched exit record with broker-reported exit cause and R multiple | code |
| Pattern bar geometry: bar1 and bar2 OHLC, wick and body fractions, structural stop candidate in R | code |

This is the change that converts every downstream claim from an opinion into a query.

The bar geometry matters because without it, three deferred hypotheses cannot be tested
offline and would each need another multi-hour tick run.

**Gate.** Trade count, entry times and net profit identical to Stage 1. The sum of net P&L
across exit records equals the tester's total to within rounding. Every exit record
satisfies `mfe_r >= mae_r`. The dropped-closure counter is zero.

### Stage 3. OnTester fitness in R, and a written evidence protocol

The fitness is

```
mean_R - k * stdev_R / sqrt(n)
```

not `n * mean_R - k * stdev_R * sqrt(n)`. The latter factors as `sd * sqrt(n) * (t - k)`,
which increases with `n` at fixed `t`, so it prefers whichever pass trades more at
identical statistical evidence. That is a trade-count maximiser, and it would push every
future sweep toward the loosest possible gate and toward paying more of the one cost known
with confidence to be negative.

Passes below a minimum trade count return a large negative sentinel.

**Correction from audit.** `OnTester()` runs *before* `OnDeinit()`. The drain of positions
still open at end of test must be the first statement of `OnTester()`, not in `OnDeinit`,
or every pass under-counts. Verify the ordering with a one-line print in each handler on
the first run rather than taking either claim on faith.

**Gate.** Journal trade count equals tester trade count, or differs by exactly the
live-at-end count. A deliberate four-pass optimisation populates the Custom column and the
zero-trade pass reads the sentinel.

### Stage 4. The baseline measurement run. No code

This is the decision point and the single most informative action available. It needs no
source change beyond Stages 1 to 3, and no reviewed proposal put it first.

Run the EA over the longest available real-tick history at flat 1 % risk, with the daily
halt and killswitch set wide enough not to censor the sample, then cut the per-trade
record.

**Correction from audit.** Stage 1's own validation rejects `InpMaxDailyDDPct = 100.0`
alongside `InpMaxTotalDDPct = 40.0`, because it rejects a daily limit at or above the total
limit and rejects either at or above 100. Use 39.0 and 40.0, and note that the daily halt
can still censor.

**Add: the right-tail probe run (S4-2b).** One extra pass with
`InpMinRR = InpMaxRR = 8.0` leaves the entry population, stop distance and lot sizing
untouched, because the reward ratio feeds only take-profit construction and the
execution-time bounds check. With Stage 2's MFE in place it yields the *uncensored*
favourable-excursion distribution. Today every winner closed at its take-profit by
construction, so the right tail is completely unobserved. From this single pass the optimal
reward ratio, the break-even arm and the partial level are all choosable counterfactually,
with no sweep and no selection bias. It costs one settings file. This is the highest-value
profitability experiment in the whole plan.

**Gate.** `n >= 500` and mean R above zero and the lower confidence bound above zero.

- **Passes:** the family has a measurable edge. Proceed to Stages 5, 6 and 7.
- **Mean R positive, lower bound not above zero** (the most likely outcome given the
  baseline t of 0.35): neither established nor refuted. Do Stages 5 and 6, hold Stage 7,
  and extend the sample forward on demo rather than re-running the same history.
- **Mean R at or below zero at `n >= 500`:** the entry family does not clear its cost. No
  filter fixes that. The question becomes a different signal or a different timeframe.

### Stage 5. Repair the exit-management path

Make the code do what its documentation claims. Three independent management legs behind
one shared monotone gate: break-even on its own arm, trailing on its own trigger, partial
on a reachability rule that rejects a ratio the take-profit can never allow.

Expected P&L effect is pre-registered as **zero or slightly negative**, per the arithmetic
in section 3. Ship it because the documentation is false, not as profitability work.

**Corrections from audit.**

- Default `InpUsePartialClose = true`, not false. The partial leg is unconditionally live
  today and is unreachable only when the reward ratio is at or below 2.5. Over a multi-year
  window some trades will have a ratio up to 3.0 and will cross 2.5 R, so defaulting it off
  breaks the reproduction gate for a legitimate reason.
- The neutrality claim covers per-trade expected R only. Break-even and trailing shorten
  holding time, which frees the single position slot more often, which changes the trade
  count and therefore total profit. Pre-register trade count alongside mean R and state in
  advance which one the decision turns on.

### Stage 6. Entry-side structural defects, plus exactly one hypothesis

- Fix the `InpLongScoreExtra` session inversion.
- Fix the engulfing score-inflation path by correcting the score rather than vetoing the
  signal.
- Test one entry filter with a mechanism behind it rather than a curve: an H1 trend-regime
  requirement, default off, tested once against a stated threshold.

**Correction from audit.** Rescoring engulfing changes `raw`, and at session weight 0.6 the
gate genuinely does bind. That is 54 to 60 % of baseline trades. So this is a
behaviour-changing scoring fix, not an inert one, and it needs its own pre-registered test
with the expected direction of the trade-set delta stated first.

**The rule that makes this stage worth anything:** a negative result means the input stays
false permanently. It does not mean a different definition gets tried.

### Stage 7. Risk enablement

First the aggregate open-risk cap, which AGENTS.md rule 27 currently cannot enforce because
the declared maximum is a per-trade label rather than a property of the account. Then a
ladder whose drawdown limits scale with the risk instead of being left behind by it.

---

## 6. Risk position

No risk increase in Stages 1 through 6.

Risk is a percentage of account balance, which moves only on closed trades, so `k`
consecutive full-stop losses cost `1 - (1 - f)^k` of the balance.

| Risk per trade | Cost of 8 straight losses | Losses to latch an 8 % killswitch | Limits required to keep today's tolerance |
| --- | --- | --- | --- |
| 1.0 % | 7.73 % | 8.30 | total 8.0, daily 5.0 |
| 1.5 % | 11.39 % | 5.52 | total 11.8, daily 7.4 |
| 2.0 % | 14.93 % | 4.13 | total 15.4, daily 9.8 |
| 3.0 % | 21.63 % | 2.74 | not recommended |

The baseline already contained an 8-loss streak, and at a 64 % loss rate that is roughly
the *median* longest run over 50 trades, not a tail event. At 2 % against an unchanged 8 %
limit, the same ordinary streak latches the killswitch at trade five and the run stops
there. Choosing the 2 % level means accepting roughly a 15.4 % account drawdown before the
ruin stop engages. That number is a choice, and the arithmetic cannot make it.

**A second-order effect worth knowing.** The daily halt binds long before the killswitch.
At 2 % it latches after about 2.5 consecutive losses, and three straight losses at a 64 %
loss rate is routine, so the EA will spend a meaningful fraction of days halted. That
removes every trade after the third loss of a day and biases the surviving population
toward days that started well. A comparison across risk levels then compares different
trade populations rather than different sizings. Record the trade count at every level. If
it moves, the comparison is invalid.

---

## 7. Deliberately not doing

| Item | Why |
| --- | --- |
| Rebuilding the entry decision around a nine-input evidence gate | The diagnosis is right and the remedy is a strategy rewrite wearing a structural-defect label, shipped on by default with nine untested thresholds. |
| Re-basing the risk tier on a weighted quality index | Six continuous sweepable money-axis parameters against an evidence base that cannot distinguish a ten-point win-rate change from noise. It also changes no trade, only dollars. |
| A twenty-field context struct and the regime gates on it | Speculative generality. Two of the gates are individually broken. The anti-chase scan starts at the signal bar, so any new 50-bar extreme lands at range position 1.0 by construction. |
| Tightening the spread cap to 3 % as a shipped default | The barrier-asymmetry identity behind it is correct and belongs in the docs. The default change is not supported. |
| Blocking server hour 0 | Eight trades is not evidence at any confidence. The structural case has merit and becomes testable once Stage 2 records spread during the position. |
| Removing the broker take-profit | The right tail is unobserved until the Stage 4 probe run, and the broker take-profit is the only profit exit that survives the EA being dead or disconnected. |
| Setting `InpMaxOpenTrades = 2` | Doubles cost-paying events per unit time while the bets are not independent: same symbol, same regime, overlapping. |
| Running an optimisation on the 2026.09 fortnight | Mechanically available today and the most damaging single action on the table. |
| Adding any new positive score component | The maximum final score is already exactly 9.0, the validation ceiling. Any new component silently converts the best setups into score-range rejections. |
| A file-sink CSV export from the EA | The journal plus one grep rebuilds the same table. File handles inside an EA that manages live protective stops is the riskiest addition available for marginal convenience. |

**Deferred with a trigger, not rejected:**

- **Structural stop placement.** The stop is derived purely from ATR off the live entry
  reference, discarding `bar1.low` for a bullish pin and bar2's extreme for an engulfing,
  both already in hand, so it routinely sits inside the very level the pattern identifies.
  This is the most interesting idea the plan does not act on, and Stage 2's bar geometry
  makes it testable offline.
- **A scheduled-news blackout.** Three independent trader reviews called it the
  highest-value filter that is defined in advance rather than fitted. It is out only
  because the MQL5 calendar's Strategy Tester behaviour cannot be verified from here.
- **Entry price itself.** Every entry is a market order on the first tick of the bar after
  the signal, at whatever the open is, paying full spread at a price that may already be
  extended by the pattern bar's own move. A retracement or limit entry shrinks the stop
  distance, which raises R per unit of adverse excursion and cuts spread as a fraction of
  R. That is arithmetically the largest single lever on R available, larger than any score
  filter, and it is the change most directly aimed at the stated goal of better trades. It
  needs a pending-order path in the execution engine, which is real work, but it becomes
  measurable for free once Stage 2 lands.

---

## 8. Open questions for the account owner

1. **Commission structure.** Spread-only on an Exness Standard account, or a real per-lot
   per-side charge on a Raw or Zero account? The latter roughly doubles per-trade cost drag
   and would change the sign of several conclusions. One minute in the symbol
   specification.
2. **Trade server GMT offset.** If the server runs at UTC+3, the code's "London and New
   York overlap" window at server hours 12 to 16 is actually 09:00 to 13:00 UTC, which is
   London morning with New York shut, and the genuine overlap falls elsewhere entirely.
   Must be read on a live chart, not in the tester.
3. **Real-tick history depth for XAUUSDm.** This sizes the whole programme. At roughly five
   trades a day, two years decides the question and six months does not.
4. **How much drawdown do you actually accept?** Roughly 15.4 % at 2 % per trade, 11.8 % at
   1.5 %. Decide before the ladder runs, not from which level looked best.
5. **If Stage 4 returns positive mean R with a lower bound not above zero**, hold Stage 7 as
   specified, or proceed at 1.5 % while the sample accumulates? Holding is statistically
   correct. Proceeding is a defensible risk-tolerance choice.
6. **Do you want event-risk handling** despite the calendar dependency?
7. **Are you willing to let a pre-registered hypothesis stay dead?** This is the one rule
   preventing the plan from degenerating into the curve-fitting it exists to avoid.

---

## 9. Honest caveats

- No compilation was performed and none is possible in the environment that produced this.
  Every code change described is unverified source. AGENTS.md rules 30 and 32 require that
  to be stated rather than assumed.
- Every confidence interval and streak probability here assumes independent trades. M15
  gold clusters by day, session and volatility regime. The baseline's 8-loss run against a
  3-win run is the visible shape of that. Effective sample size is below the trade count,
  every interval is wider than stated, and every required sample size is larger.
- The standard deviation of R used throughout (1.4275) comes from a two-point model
  assuming every winner returns exactly 1.974 R. Real dispersion is strictly larger, so
  every sample-size figure here is an underestimate. Rebuild the power arithmetic from
  measured values once Stage 2 lands.
- MFE and MAE are biased toward zero by about one tick, because MT5 fills broker-side stops
  and targets before dispatching the tick handler. They are meaningless under 1-minute OHLC
  modelling. Real ticks are mandatory for any run they are read from.
- Any out-of-sample window used later must **end before 2026.09.01**. That fortnight
  generated every hypothesis in this document and is burned.
- This plan delivers no P&L movement until Stage 7, and Stage 7 is gated on Stage 4. That
  is a real cost. Raising risk is an input-only change available today, but doing it before
  Stage 1 means raising size behind a ruin stop that does not survive a restart, on an edge
  no measurement has confirmed.
- The measurement layer this plan builds is also a better overfitting machine than the one
  it replaces. Screening twenty binary cuts on 300 trades produces an expected
  best-of-twenty inflation of roughly 1.87 standard errors on a null effect. Pre-register
  the cuts.
- Live stop slippage is unmodelled. A target is a limit order and cannot fill adversely. A
  stop can. Expect live R to be slightly worse than backtested R, on the loser population
  only.
- Nothing in the codebase looks at the spread after entry. A long's stop sits on the bid,
  so a flare at rollover or on a tier-one release can liquidate positions the mid never
  reached.
- Every "reproduces exactly" gate needs a same-session control run of the unmodified build
  immediately before the comparison. Otherwise a tick-cache or terminal-build difference is
  attributed to the change.
- There is no continuous integration and no assertion framework. The two test scripts print
  pass or fail and exit normally either way. A human has to read the output.
