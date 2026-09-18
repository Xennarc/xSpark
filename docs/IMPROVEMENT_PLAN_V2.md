# XSpark Improvement Plan V2 — Structure Gates, Located Entries, Structural Exits

Status: **plan only.** No code in this document has been written, compiled, or tested. There is no MetaEditor and no market data in the environment that produced it. Every number here is arithmetic over source read directly from this repository, or over the 50-trade Strategy Tester report already recorded in `docs/IMPROVEMENT_PLAN.md`. Nothing here is a backtest result. AGENTS.md rules 30, 32 and 33 apply.

This document supplements `docs/IMPROVEMENT_PLAN.md`; it does not replace it. Section 5 reconciles the two.

---

## 1. What the operator reported, and what this plan commits to

After extensive testing the account owner reports four things:

| # | Reported symptom |
| --- | --- |
| (a) | The EA lags. Trades land in the **middle** of a trend with the take-profit too far from the reversal point, or land **exactly at** the reversal point. |
| (b) | Sells execute when RSI is too low; buys when RSI is too high. Entries into exhausted moves. |
| (c) | Pattern recognition is too thin. Wants head & shoulders, double top/bottom, flags and other multi-bar chart patterns. |
| (d) | Trend direction detection is wrong. An uptrend makes higher highs **and** higher lows; a downtrend makes lower highs **and** lower lows. The higher-timeframe trend should be determined from that structure, and lower-timeframe entries should follow it. |

All four are mechanically explainable from source, and the explanations are largely the same defect seen from four sides. This plan commits to:

1. **Naming the root cause with arithmetic, not adjectives.** The entry gate does not gate. Five of seven scoring components are arithmetically incapable of preventing a trade, and under shipped defaults they do not change position size either. That single fact explains (a), (b) and (d) simultaneously, and it is the reason adding patterns for (c) would make things worse rather than better.
2. **Fixing the shape of the decision, not the weights.** Every new market-structure input is a **pre-scoring gate** — a veto. Nothing is added to the score. `XSPARK_SCOREBOT_MAX_SCORE` stays 9.0, the tier constants stay 5.5 and 4.5, and every existing test remains valid.
3. **Shipping every behaviour change default-OFF, one stage at a time, each with a falsifiable expectation written before the run**, and with a stated statistical test that is correct for comparing a *nested subset* of trades against the population it came from.
4. **Making every prose-only sequencing rule mechanical.** A prohibition with no code behind it in an operator-configured EA is documentation, not a control. Section 3.8 turns the three ordering rules in this plan into `OnInit` refusals.
5. **Stating plainly what this plan cannot establish.** It is defect repair. No claim that it makes money is supported by anything in this repository, and several stages may be permanently unfalsifiable on the available sample. Section 8 says so without softening.

**Three experiments that cost nothing and should happen before a line of code is written** are specified in Stage S0. One of them can refute the central premise of the exit work using data the EA already logs.

---

## 2. Diagnosis

Every claim below was read from source at `/home/user/xSpark`. Line references are to the working tree as it stands.

### 2.1 The entry gate does not gate — this is the root defect

`ScoreBotV3.mqh:275-281` sums the score:

```
raw = pattern + atr + trend + rsi + sr + volume + mtf
```

`:282` scales it by the session weight, and `:301` compares it:

```
final_score   = raw * session_weight
threshold_passed = final_score >= effective_threshold
```

`effective_threshold` is `InpMinScore` for sells and `InpMinScore + InpLongScoreExtra` for buys (`ScoringEngine.mqh:64-72`), with defaults 2.0 and 0.0 (`XSpark.mq5:55, 57`).

Two of the seven terms are free:

- `ScoreBotV3.mqh:243` — `report.components.atr = 1.0;` is a **literal**, granted unconditionally once the ATR band check at `:231` passes. It is not a measurement.
- Every pattern scores above 1.0 by construction. A pin requires `lower >= 0.55 * range` (`PatternDetector.mqh:20`, mirror `:32`) and scores `MathMin(2.0, 1.0 + lower/range)` (`:26`, `:38`), so any detected pin is in **[1.55, 2.0]**. Engulfing scores `1.0 + ((body1/body2) - 1) * 0.5` with `body1 > body2` strictly required (`:59`, `:73`), so it is in **(1.0, 2.0]**. Inside-bar breakout is the literal **1.5** (`:103`, `:113`).

Session weights are 1.2 for server hours 12-15, 1.0 for 7-11 and 16-20, and 0.6 otherwise when `InpAllowAsianReduced` is true, which is the default (`ScoringEngine.mqh:18-36`; `XSpark.mq5:96`).

**Full enumeration with `trend = rsi = sr = volume = mtf = 0`:**

| Pattern | raw (`pattern + atr`) | × 1.2 | × 1.0 | × 0.6 |
| --- | --- | --- | --- | --- |
| Pin, minimum | 2.55 | 3.06 **fires** | 2.55 **fires** | 1.53 blocked |
| Pin, maximum | 3.00 | 3.60 **fires** | 3.00 **fires** | 1.80 blocked |
| Engulfing, degenerate | 2.000…1 | 2.40 **fires** | 2.000…1 **fires** | 1.20 blocked |
| Engulfing, maximum | 3.00 | 3.60 **fires** | 3.00 **fires** | 1.80 blocked |
| Inside-bar breakout | 2.50 | 3.00 **fires** | 2.50 **fires** | 1.50 blocked |

`trend`, `rsi`, `sr`, `volume` and `mtf` are **4.5 of the 7.5 maximum raw points — 60 % of the score space — and all 4.5 can be zero on a trade that fires.** During London and New York hours the gate never binds. It binds only at session weight 0.6, where the required raw score is 3.333.

**And under shipped defaults they do not change the position size either.** `XSparkRiskPercentForScore` (`RiskManager.mqh:8-22`) selects among `InpRiskPctTier1/2/3` by the 5.5 and 4.5 thresholds (`ScoreBotTypes.mqh:45-46`) and returns `MathMin(selected, InpMaxRiskPct)`. All three tiers default to 3.0 and the cap to 3.5 (`XSpark.mq5:84-87`), so every branch returns `MathMin(3.0, 3.5) = 3.0`. The tier selection is a three-way branch onto one value.

> **Consequence.** Trend agreement, RSI position, support/resistance proximity, volume and higher-timeframe agreement are computed on every signal bar, logged, rendered on the dashboard — and then affect neither whether the trade happens nor how large it is. They are telemetry. The EA opens a 3 %-of-balance position on the geometry of one closed candle plus a volatility band check.
>
> A single candle carries no information about **where in a swing it sits**. That is why entries are distributed uniformly over a trend instead of concentrated at its start, and it is why "mid-trend" and "at the reversal point" are the same defect viewed from two sides.

This also disposes of the change most likely to be proposed in response to (b): **re-weighting the RSI component changes zero trades and zero dollars.** Only converting a component into a gate, or raising `InpMinScore` above the unaided `pattern + atr` ceiling of 3.60, can alter behaviour at all.

### 2.2 (b) The RSI bands are not merely permissive — they are aimed backwards

RSI enters the scoring decision at exactly four points: the conditions at `ScoreBotV3.mqh:250, 256, 264, 270`, whose only effect is the component assignments at `:251, 257, 265, 271`. There is no `return false`, no `block_reason`, no early exit anywhere in the repository that reads an RSI value. **It is arithmetically impossible for an RSI value to prevent a trade.**

(RSI appears in many other places — `ScoreBotV3.mqh:202-203` populates `report.rsi_base` and `report.rsi_higher`, `Dashboard.mqh:363` renders them, `IndicatorCache.mqh:91, 95, 183, 192, 245-248, 281-284` own the handles and accessors, and `XSpark.mq5:59-62` declare the band inputs. None of those is a decision site, which is the point.)

The bands (`XSpark.mq5:59-62`) are longs `[40, 70]` and shorts `[30, 60]`.

| Property | Value | Consequence |
| --- | --- | --- |
| Overlap | `[40, 60]`, 20 of each 30-point band = 66.7 % | Inside it a BUY and a SELL earn the identical 1.0. Two thirds of each band has zero directional discrimination. |
| Exclusive long tail | `(60, 70]` | Rewards buying what is already high. |
| Exclusive short tail | `[30, 40)` | Rewards selling what is already low. |
| Long band midpoint | 55 (+5 above 50) | Skewed **with** the move. |
| Short band midpoint | 45 (−5 below 50) | Skewed **with** the move. |

**Worked pair.** A bearish pin at RSI 35 in a London hour: `pattern 1.55 + atr 1.0 + rsi 1.0` (35 is inside `[30, 60]`, `:264-265`) `+ trend 1.0` (`:261-262`) = raw 4.55 — a full point of "momentum filter" credit for shorting a market already at RSI 35. The **same** bearish pin at RSI 68, the textbook overbought short, scores `rsi = 0.0` because 68 > `InpRSIShortMax = 60` — and still fires at raw 3.55. The filter penalises the good short by a point and pays for the bad one. The mirror holds for longs: a bullish pin at RSI 32 scores 0.0, the same pin at RSI 68 scores 1.0.

**The `mtf` term compounds it.** `ScoreBotV3.mqh:256-257` pays a BUY 0.5 when `rsi_higher > 50.0 && rsi_base > rsi_higher`; `:270-271` pays a SELL 0.5 when `rsi_higher < 50.0 && rsi_base < rsi_higher`. The second conjunct is satisfied **only when the faster timeframe has run further in the trade's own direction than the slower one** — the definition of arriving late.

| Sell setup | `rsi_base` | `rsi_higher` | `rsi` | `mtf` | total |
| --- | --- | --- | --- | --- | --- |
| Continuation short (rally into a pullback inside a bearish HTF) | 55 | 45 | 1.0 | 0.0 | 1.0 |
| Chase short (already extended) | 35 | 42 | 1.0 | 0.5 | 1.5 |

The chase outscores the pullback by 0.5 — the entire weight of the only higher-timeframe agreement term in the system. The combined `rsi + mtf` reward surface peaks at `rsi_base ≈ 60` for buys and `≈ 40` for sells. That is the operator's finding (b) written as an objective function.

### 2.3 (a), first half — where the lag actually comes from

Four separable sources. Naming them separately is what makes the fix tractable.

**1. Information lag in every context input.** `IndicatorCache.mqh:89-95` creates EMA21, EMA50, RSI14, ATR14, ATR50 on the base timeframe and EMA50 + RSI14 on the higher timeframe. There is no other market-direction input in the codebase. An EMA of period *N* has a centre of mass of *(N−1)/2* bars, so the EMA21/EMA50 relationship at `ScoreBotV3.mqh:247` carries a ~14.5-base-bar differential — 3.6 hours on the tested M15/H1 pair (`ScoreBotTypes.mqh:10-11`). `ema50_higher` has a centre of mass of 24.5 **higher-timeframe** bars, ≈ 24.5 hours on H1, and `CopyBuffer(..., start_pos=1, count=1)` at `IndicatorCache.mqh:191` only advances when an HTF bar closes, so on M15 the same value is reused for four consecutive evaluations.

**2. Location lag.** Nothing anywhere asks where in the swing the price is. There is no such computation in the repository.

**3. Anchor lag — the largest single term.** `ScoreBotV3.mqh:325` sets `entry_reference` from the **live** `market_state.Ask()/Bid()` at the first tick of the bar after the signal bar (`XSpark.mq5:1697-1701`), i.e. approximately `bar1.close` plus spread. For a bullish pin, `close − low = (close − min(open,close)) + lower >= lower >= 0.55 × range`. **The entry is at minimum 0.55 pattern-bar ranges above the rejection low, approaching 1.0 as the pin gets cleaner** — and since the score is `1.0 + lower/range`, the *highest-scoring* pins are exactly the ones whose entry is furthest from the level they supposedly trade. Engulfing is worse: the reference extreme is bar2's low while entry is at bar1's close, with `body1 > body2` enforced.

**4. Confirmation lag.** One bar plus one tick from the last price used to the fill. Irreducible under closed-bar determinism and not worth attacking.

### 2.4 (a), second half — stops and targets never touch market data

| Element | Source | Formula |
| --- | --- | --- |
| Stop | `ScoreBotV3.mqh:326-330` | `entry_reference ∓ InpATRMultSL × ATR14` |
| Target (planning) | `XSpark.mq5:713-717`, recomputed `:762-767` | `entry_reference ± risk_distance × dynamic_rr` |
| Target (execution) | `ExecutionEngine.mqh:184-187` | same, via `XSparkTargetFromRiskDistance` |
| `dynamic_rr` | `ScoringEngine.mqh:38-50` | function of `ATR14/ATR50` only |

No swing high, no swing low, no prior bar extreme, no higher-timeframe level appears in any of these expressions.

**The double-ATR compounding.** Target distance is `InpATRMultSL × ATR14 × RR(ATR14/ATR50)` — ATR14 appears twice, once as the unit and once inside the multiplier. Holding ATR50 = *A*:

| ATR14/ATR50 | `t` | `dynamic_rr` | Target distance |
| --- | --- | --- | --- |
| 0.7 | 0.00 | 1.50 | 1.575 *A* |
| 1.0 | 0.50 | 2.25 | 3.375 *A* |
| 1.3 | 1.00 | 3.00 | 5.850 *A* |

**A 3.71× spread**, widest exactly when volatility has already expanded — which is the same moment the EA finally has a qualifying setup. The system demands the most remaining move precisely when the least remains. That is the mechanism behind "the TP ends up too far from the reversal point."

**`signal.desired_target` is a dead field.** Declared at `StrategyInterface.mqh:16`, reset at `:42`, written as the literal `0.0` at `ScoreBotV3.mqh:332`, and read **nowhere** — a grep across `MQL5/` returns only those three sites. Meanwhile `signal.desired_stop` *is* honoured (`XSpark.mq5:668, 681, 723`; `ExecutionEngine.mqh:126, 132`). The asymmetry is not a design stance; it is an unfinished field, and it is the concrete blocker for any structural target.

**The stop can sit inside the pattern's own rejection wick.** For a bullish pin, the stop is above `bar1.low` whenever `1.5 × ATR14 < 0.55 × range1`, i.e. whenever `range1 > 2.727 × ATR14` — and possibly sooner, since `close − low` frequently exceeds `0.55 × range`. Nothing bounds `range1`: the ATR gate at `ScoreBotV3.mqh:231-240` bounds ATR14 in absolute ScoreBot points and never compares the signal bar's range to it. The trade is then taken out by an ordinary retest of the wick that does not invalidate the pattern at all.

**The RR bounds already bind, and not for the reason they appear to.** `XSpark.mq5:800-811` and `ExecutionEngine.mqh:221-228` both check the realised RR against `[InpMinRR, InpMaxRR]` with a tolerance of `XSPARK_RR_EPSILON = 1e-7` (`ExecutionMath.mqh:12`, used at `:153-154`). An earlier draft of this document called those checks tautological because `dynamic_rr` is clamped into the same band by construction (`ScoringEngine.mqh:48-49`). That is wrong, and the arithmetic is worth setting out exactly, because a structural target inherits it.

The check runs *after* normalisation. `plan.entry_reference` is normalised at `XSpark.mq5:722`, `plan.final_tp` is re-normalised and possibly widened by `XSparkAdjustProtectionLevels` (`SymbolMath.mqh:331-332, 360-368, 382-390`) and that value is written back at `:798`, while `plan.risk_distance` (`:695`) is the raw quote-to-stop distance. So `actual_rr` is a ratio of normalised prices over an unnormalised one.

What saves it most of the time is that the broker quote is already at tick granularity and the adjusted stop is normalised, so `risk_distance` is an exact integer number of ticks — call it *m*. The target displacement is `dynamic_rr × m` ticks, and normalisation is a **no-op exactly when that product is an integer**:

- `InpMaxRR = 3.0` is an integer, so `3m` is always an integer number of ticks. **The upper bound is never displaced and never binds.**
- `InpMinRR = 1.5` is a half-integer, so when *m* is **odd**, `1.5m` lands on a half tick. Normalisation then moves the target by half a tick and displaces `actual_rr` by `0.5 × tick / risk_distance`. On gold at the ATR floor (`risk_distance = 1.5 × 80` ScoreBot points `= 1.20` price, tick `0.01`) that is `0.005 / 1.20 = 0.00417` — about **forty thousand times** the 1e-7 tolerance. The half-tick case is decided by the binary representation of a computed sum, so the direction is not predictable from the inputs; treat it as a coin flip.
- `dynamic_rr` equals `InpMinRR` **exactly** whenever `ATR14/ATR50 <= 0.7`, because `t` is clamped to 0 at `ScoringEngine.mqh:48`. That whole low-volatility population therefore sits on the knife edge, and about half of the odd-*m* half of it is refused with `Final broker-valid RR ... is outside configured 1.50-3.00`. A thin band of interior `dynamic_rr` values within `tick / risk_distance` of either bound is exposed the same way.

So the bounds are a live, unlogged-as-such rejection mechanism today, concentrated on the quietest bars, and the exposure is **inversely proportional to the stop distance** — worst exactly where the stop is tightest. Any structural-target work must either derive the tolerance from the tick size or compare against the constructed target rather than inherit a 1e-7 equality against a half-integer. Section 3.6 Step 4 does the former; Stage S8c ships it.

**And the exit-management stack is dead on most trades.** `dynamic_rr >= InpPartialTPRatio = 2.5` requires `ATR14/ATR50 >= 1.1` — an upper-tail event for two means of the same true-range series. Below it the broker take-profit is hit before the partial trigger at `PositionManager.mqh:1463-1465`, so the partial never fires; break-even is nested **inside** the successful `ClosePartial` branch (`:1482-1534`); and the trail is gated on `partial_done` (`:1556`). A trade that runs to +1.2 R at the real reversal and turns takes the full −1 R, because all three salvage mechanisms are behind a volatility condition unrelated to the trade's progress. `PositionManager.mqh:1545-1551` even logs it in words: *"break-even and trailing stay disabled for this position."* Break-even is additionally requested at the raw fill price (`:1518` passes `m_states[active_index].entry`), so a "break-even" exit is a guaranteed net loss of spread plus commission.

The trail itself is not inert once armed — `PositionManager.mqh:1556-1596` recomputes `bid − InpATRMultTrail × ATR14` on every tick and applies it whenever the `tighter` test at `:1580-1584` passes, so it ratchets from roughly entry + 1.167 R at the 2.5 R arm point up to about entry + 1.667 R by a 3.0 R take-profit. That is half an R of real progressive protection. What kills it at shipped defaults is the arm condition, not the ratchet.

### 2.5 (d) The codebase has no concept of market structure

Trend direction is decided in exactly two expressions in the entire repository:

```
ScoreBotV3.mqh:247   if(ema21_base > ema50_base && bar1.close > ema50_higher)  trend = 1.0;   // BUY
ScoreBotV3.mqh:261   if(ema21_base < ema50_base && bar1.close < ema50_higher)  trend = 1.0;   // SELL
```

The higher-timeframe half is a **level** comparison of a base-timeframe close against a single stale HTF EMA number. It cannot express direction:

- **The HTF slope is not unused — it is unavailable.** `IndicatorCache.mqh:191` copies exactly **one** value (`count = 1`). There is no second value to difference against, so `ema50_higher[0] − ema50_higher[1]` does not exist anywhere in the program. `CopyRates` is called only on the base timeframe (`:175`). **There is no higher-timeframe OHLC in the process at all.**
- `close > ema50_higher` is true of price anywhere above a flat MA inside a range, and it is *most* strongly true at the exhausted end of a move, where price is furthest above the MA. One expression covers trend, range and exhaustion, and it is at its most confident exactly where the operator reports the worst entries.
- The AND at `:247` collapses "the HTF disagrees" and "the HTF is unknown" into the same `trend = 0`. Nothing in the codebase distinguishes *with-HTF* from *against-HTF*; it only distinguishes *with-HTF* from *not-with-HTF*. **"Mostly trade in the direction of the higher timeframe trend" is arithmetically inexpressible in the current design**, because mostly-with-trend requires that against-trend setups be *rejected*, and there is no negative term and no rejection path anywhere outside the session and ATR gates.

**Swing pivots are computed and then thrown away.** `HasSupportResistance` (`ScoreBotV3.mqh:52-97`) runs a genuine 5-bar fractal — candidate at `shift`, two newer neighbours, two older (`:65-69`) — across shifts 3..48, and correctly identifies swing lows (`:76-79`) and swing highs (`:86-89`). It then discards everything a structure classifier needs: it never records the pivot price, shift or time, never collects more than one pivot, and never compares two consecutive pivots of the same type. **Its entire output is `true`/`false`**, feeding a binary `sr = 1.0`.

**And that one output has the wrong sign with respect to trend.** `:81` tests `MathAbs(close1 - candidate.low) <= 0.5 * atr14`. Because the distance is absolute, a close **below** the swing low qualifies identically to one above it — so a BUY is awarded a full confirmation point for the exact event that defines a *lower low*. The scan is also direction-*confirming* only: a BUY scans lows (`:74-83`), a SELL scans highs (`:84-93`), so **the next swing high above a long — the level that caps its profit run — is never enumerated anywhere in the repository.**

### 2.6 (c) The pattern layer is the trade decision, and it has no context

`XSparkDetectScoreBotPattern` (`PatternDetector.mqh:120-137`) receives exactly three candles and nothing else — no cache, no ATR, no swing list, no trend state. A bullish pin at the top of an extended rally is, to this code, indistinguishable from a bullish pin at tested support.

Three concrete detector defects:

| # | Defect | Evidence |
| --- | --- | --- |
| 1 | **The pin cannot distinguish rejection from indecision.** The bullish branch tests only `lower >= 2.0*body`, `body <= 0.35*range`, `lower >= 0.55*range`. The variable `upper` computed at `:15` is never referenced in that branch. Normalise `range = 1.0`: `lower = 0.55`, `body = 0.02`, `upper = 0.43` passes all three, scores 1.55, and fires a directional 3 %-of-balance trade unaided. | `PatternDetector.mqh:15, 18-20, 26` |
| 2 | **The inside-bar breakout triggers against the *inside* bar, not the mother bar.** `:93` establishes `bar2.high < bar3.high`, then `:97` triggers on `bar1.close > bar2.high` — so the "breakout" can be entirely inside bar3's range. The repository's own fixture proves it: mother H = 101.00, inside H = 100.50, breakout C = 100.60. 100.60 > 100.50 passes; 100.60 < 101.00 means price never left the mother bar. | `PatternDetector.mqh:93, 97`; `TestScoreBotV3Logic.mq5:71-75` |
| 3 | **First-match-wins is a silent ranking by array order, and it can return the opposite direction.** Constructible: bar2 O=100.00 C=100.10 H=100.15 L=99.95; bar1 O=100.30 C=99.98 H=100.30 L=98.00. Bearish engulfing holds (score 2.00, SELL) *and* bullish pin holds (score 1.861, BUY). `:126-133` returns the BUY; the SELL is never computed. The repo's guard test is vacuous — in its fixture, bullish engulfing needs `close1 > open2` i.e. `100.20 > 100.40`, which is false, so no competing pattern exists and the ordering is asserted against a case where ordering is irrelevant. | `PatternDetector.mqh:126-133`; `TestScoreBotV3Logic.mq5:81-85` |

Also noted for accuracy: the `body1 > body2` clause in engulfing (`:59`, `:73`) is **mathematically redundant** — from `close1 > open2` and `open1 < close2` it follows that `body1 > body2` — and the score denominator `body2` is bounded only by `body2 <= 0.0` (`:52`), so engulfing a near-doji reaches the 2.0 cap on a body ratio carrying no information.

**The bar budget forecloses multi-bar patterns entirely.** `XSPARK_SCOREBOT_CLOSED_BASE_BARS` is 50 (`IndicatorCache.mqh:6`), feeding one `CopyRates` (`:175`) and `BaseBar`'s bound (`:222`). `HasSupportResistance` already consumes shifts 3..48 and reads `shift+2 = 50` — **zero headroom.** A head-and-shoulders spans 25-60 base bars. There is no higher-timeframe OHLC at all.

### 2.7 Five claims that were checked and **rejected**

Stated because a document whose authority rests on source verification must report what did not survive verification. Claims 4 and 5 arrived from review of the first draft of this plan and did not survive either.

1. **"`ScoreBotV3.mqh:71` uses `return false` where `break` is meant, and is a latent component-killer."** **False.** The loop's only fall-through is `return false` at `:96`, so `break` at `:71` and `return false` at `:71` produce an identical result at every lookback depth. The meaningfully different alternative is `continue`, and it matters only if the window is deepened past what `BaseBar` can serve. This plan does not deepen that window (section 3.2), so the point is moot; it is recorded so nobody re-derives it as a defect.
2. **"The weak HTF handle-readiness check produces a silent one-sided long bias."** **Partially verified.** The asymmetry is real and is verified from source: `IndicatorCache.mqh:158-159` requires `BarsCalculated >= 2` for an EMA of period 50 and an RSI of period 14, while the five base handles each require `XSPARK_SCOREBOT_CLOSED_BASE_BARS + 1 = 51` (`:153-157`). It is also verified that `IndicatorValueIsReady` (`:43-48`) is `MathIsValidNumber(value) && value != EMPTY_VALUE`, so a `0.0` slot passes. What is **not** verified from this repository is that an uncalculated `iMA` buffer slot actually reads `0.0` — that is terminal behaviour I cannot test here, and the `Bars(higher) >= 60` guard at `:146` makes the window narrow in any case. The fix ships as **contract hygiene** (raise the requirement to 51 / 15 and reject a non-positive `ema50_higher` explicitly), not as a proven live bias, and as its own stage (S2a) because it can legitimately change the first tradeable bar.
3. **"`Configure()` takes fourteen arguments."** It takes **fifteen** (`XSpark.mq5:1416-1430`); its own comment at `ScoreBotV3.mqh:341-344` says fourteen and is stale. The comment's *argument* stands and is honoured in section 3: do not extend `Configure()`.
4. **"The RR upper bound already refuses roughly half of all high-volatility setups, because price normalisation displaces `actual_rr` by 0.004-0.008 against a 1e-7 epsilon."** **Half right, and the wrong half is load-bearing.** The bounds do bind and the epsilon is far too tight — that much is confirmed and is now section 2.4. But the mechanism is not generic rounding. The broker quote is already at tick granularity and the adjusted stop is normalised, so `risk_distance` is an exact integer number of ticks and `dynamic_rr × risk_distance` is exactly representable whenever that product is an integer. `InpMaxRR = 3.0` is an integer, so **the upper bound is never displaced and the `ATR14/ATR50 >= 1.3` population is not refused at all.** The exposure is at `InpMinRR = 1.5`, a half-integer, and only when the broker-valid stop distance is an odd number of ticks. Getting this wrong in the other direction would have justified raising `InpMaxRR` — the one change section 3.6 Step 4 refuses.
5. **"The S0 right-tail probe at `InpMinRR = InpMaxRR = 8.0` takes zero trades, because normalisation moves `actual_rr` off 8.0 by more than the epsilon."** **False, for the same reason.** 8.0 is an integer, `8m` ticks is exact, `actual_rr` is 8.0 to within about 4e-13, and both bound checks pass. `InpMaxRR == InpMinRR` is also accepted by validation — `XSpark.mq5:301` rejects only `InpMaxRR < InpMinRR`. The probe works as originally specified. What the review correctly exposed is that this is **not luck and must be stated as a precondition**: an *integer* probe RR is required, and a probe at 7.5 would be displaced on every odd-tick stop. Section 4's S0 now says so.

---

## 3. The design

### 3.1 The one architectural decision: gates, not scores

Every new market-structure input is a **hard pre-scoring veto**, placed alongside the existing session gate (`ScoreBotV3.mqh:222-229`) and ATR gate (`:231-240`). Nothing is added to `raw`, nothing is removed from it, and the session multiplier is not touched.

Three reasons, in order of force:

1. **It is the only shape that can express "mostly trade with the HTF trend."** Mostly-with-trend requires against-trend setups to be *rejected*. The scorer has no negative term and no rejection path (section 2.5).
2. **It is the only shape that changes anything at all.** Under flat tiers, re-weighting moves neither trades nor dollars (section 2.1).
3. **It costs exactly 0.0 of a ceiling that is saturated to 1e-7.** See section 3.8.

**Where the gates run: after pattern detection, not before.** This is a deliberate departure from every reviewed proposal, and it buys three things:

- `XSpark.mq5:1151` journals a rejection only when `report.has_pattern` is true. Running the gates after detection means **the rejection journal keeps working unchanged and the measurement denominator stays identical to today's**. Running them before would silently erase the entire rejected population and require changing the logging predicate — which is exactly the kind of coupled change that invalidates a before/after comparison.
- The structure computation runs only on bars that already carry a pattern. Cheaper, and evaluation is bar-gated anyway (`XSpark.mq5:1697-1701`), so cost is not a concern either way.
- Direction still comes from the pattern, but a pattern whose direction contradicts the HTF structure verdict is refused. For every bar where a pattern exists — which is every bar that can currently trade — the outcome is identical to gate-supplies-direction.

The evaluation chain becomes:

```
  existing: not initialised / cache invalid / bars 1-3 unavailable
  existing: NO PATTERN                              ScoreBotV3.mqh:209-215
  existing: SESSION BLOCKED                         ScoreBotV3.mqh:222-229
  existing: ATR BLOCKED                             ScoreBotV3.mqh:231-240
+ NEW:     PATTERN CONFLICT      (S9)   two detectors disagree on direction
+ NEW:     PATTERN INSTANCE USED (S9)   this multi-bar instance already traded
+ NEW:     HTF STRUCTURE UNKNOWN (S3)   structure data or pivot count insufficient
+ NEW:     HTF RANGE             (S3)   structure computed, says chop
+ NEW:     HTF TREND BLOCKED     (S3)   pattern direction contradicts HTF structure
+ NEW:     RSI EXTENDED/EXHAUSTED(S4)   RSI outside the pullback-depth band
+ NEW:     NO QUALIFYING LEG     (S5)   base leg smaller than InpMinLegATR
+ NEW:     LEG BROKEN            (S5)   retracement > 1.0
+ NEW:     NOT IN PULLBACK ZONE  (S5)   retracement outside [min, max]
+ NEW:     STOP TOO WIDE         (S6)   structural stop implies > InpATRMultSLCap
+ NEW:     NO STRUCTURAL TARGET  (S7)   no level and no measured move available
+ NEW:     RR BELOW MINIMUM      (S7)   structural target gives RR < InpMinRR
  existing: score the seven components, session weight, validity, threshold
```

Each new block writes `report.status` and `report.block_reason` and returns `false`, exactly as the two existing gates do. Each sits behind its own `bool` input and is a no-op when off — which is what makes every stage revertible by flipping one input. **`InpGateObserveOnly` (S3) suspends enforcement for all of S3-S7 while still computing and journalling every verdict**, so the counterfactual population comes out of a single run at zero behavioural risk.

`Configure()` is not extended. It already takes fifteen arguments and its own comment explains why restating unchanged ones to move two is how the wrong value gets passed. A second `ConfigureGates(XSparkGateConfig &cfg)` is added, following the precedent the file itself set with `SetVolatilityBand`.

### 3.2 Market structure module

**New file: `MQL5/Include/XSpark/Strategy/MarketStructure.mqh`.** Free functions over an array of `XSparkCandle`. No class, no carried state, no indicator handle, no cache dependency, **and no terminal global variable** — so the identical code serves the base window and the HTF window, a unit test can feed it literal bars with no terminal, and the verdict stays a pure function of closed bars as AGENTS.md rule 40 requires.

```cpp
enum EXSparkPivotType      { XSPARK_PIVOT_NONE = 0, XSPARK_PIVOT_HIGH = 1, XSPARK_PIVOT_LOW = -1 };
enum EXSparkStructureState { XSPARK_STRUCT_UNKNOWN = 0, XSPARK_STRUCT_UP = 1,
                             XSPARK_STRUCT_DOWN = -1, XSPARK_STRUCT_RANGE = 2 };

#define XSPARK_STRUCTURE_FRACTAL_WING 2      // matches ScoreBotV3.mqh:65-69 exactly
#define XSPARK_STRUCTURE_MAX_PIVOTS   56     // worst case, see below
#define XSPARK_STRUCTURE_TR_PERIOD    14

struct XSparkPivot   { EXSparkPivotType type; double price; int shift; datetime time; bool broken; };

struct XSparkStructure
{
   bool                  valid;
   string                reason;         // why UNKNOWN or invalid, for the journal
   int                   bars_scanned;
   int                   pivot_count;    // strictly alternating, newest first
   XSparkPivot           pivots[XSPARK_STRUCTURE_MAX_PIVOTS];
   EXSparkStructureState state;
   int                   legs_in_state;  // trend maturity: how many legs since the state began
   double                last_high, prev_high, last_low, prev_low;
   int                   last_high_shift, last_low_shift;
   double                scale;          // the mean true range the filter used
   // current leg, for the location gate and structural exits
   double                leg_origin, leg_extreme, leg_range, retracement;
   int                   leg_origin_shift, leg_extreme_shift;
};

bool XSparkBuildStructure(const XSparkCandle &bars[], const int count,
                          const double min_swing, XSparkStructure &out);
double XSparkMeanTrueRange(const XSparkCandle &bars[], const int count, const int period);
bool XSparkNearestOpposingPivot(const XSparkStructure &s, const EXSparkSignalDirection dir,
                                const double beyond_price, XSparkPivot &out);
```

**Step 1 — raw fractal scan.** `bars[]` is series-indexed exactly as `IndicatorCache` sets it, so index *i* is closed shift *i+1*. For every shift *s* from `W+1` to `count − W`:

```
pivot high at s  iff  high[s] >  high[s-j]  for j = 1..W      (STRICT vs NEWER)
                 and  high[s] >= high[s+j]  for j = 1..W      (non-strict vs OLDER)
pivot low  at s  iff  low[s]  <  low[s-j]   for j = 1..W
                 and  low[s]  <= low[s+j]   for j = 1..W
```

The asymmetry replaces the all-strict test at `ScoreBotV3.mqh:76-79, 86-89`, which silently disqualifies a genuine pivot whenever any adjacent bar shares the same extreme — common on metals and on any tick-quantised high. On a plateau of equal highs this rule yields **exactly one** pivot, and it is the **newest** bar of the plateau. Consequence, stated because it is a cost: confirmation is measured from the *end* of a plateau, so a plateau adds its own length to the confirmation delay. That is the conservative direction.

Because the scan starts at `s = W+1`, every candidate has W closed bars to its right. **No pivot in the array can repaint.** A bar satisfying both tests (an outside bar) is recorded as neither, and `bars_scanned`/`reason` surface it — discarding one pivot is cheap, an arbitrary tie-break rule would be a hidden parameter.

**Step 2 — one fused pass for alternation and the magnitude filter.** Reviewed proposals specified these as two steps, which is circular: the magnitude test references "the last accepted opposite pivot", which presupposes the alternation the second step produces. One pass, walking raw candidates oldest → newest over a stack of accepted pivots:

```
if stack empty                       -> push
else if candidate.type == top.type   -> if candidate is more extreme, replace top; else discard
else (opposite type)                 -> if |candidate.price - top.price| >= min_swing, push
                                        else discard
```

Terminates, is order-independent given the scan direction, and produces a strictly alternating sequence whose every leg is at least `min_swing`. `min_swing = InpMinSwingATR × scale`, ATR-relative per ADR-026, never an absolute price. Honest limitation: a small counter-swing immediately followed by a large continuation can be absorbed into the preceding pivot. The rule never produces a non-alternating or sub-threshold sequence; it can under-count pivots.

**Overflow is specified, bounded and fail-closed.** `XSPARK_STRUCTURE_MAX_PIVOTS` is **not** a typical-case number. At `W = 2` a strictly alternating pivot can occur every `W + 1 = 3` bars, so the 160-bar base window admits at most `⌊160 / 3⌋ = 53` accepted pivots; 56 is that bound with three slots of headroom, and the 80-bar HTF window needs at most 27. Every push asserts the bound. If a push would exceed it — which the sizing above says cannot happen, which is exactly why it must be checked rather than assumed — `out.valid = false` and `out.reason = "pivot overflow"`, and **every gate refuses.** Silently keeping the oldest 24 pivots, as an earlier sizing would have forced, would let the classifier return UP or DOWN from structure a hundred bars stale: a verdict that *grants* permission from data current price has already invalidated. That is the fail-open direction and AGENTS.md rules 23 and 24 forbid it.

**`scale`** is `XSparkMeanTrueRange(bars, count, 14)` — a simple mean of `max(h−l, |h−prev_c|, |l−prev_c|)`. It is **not** Wilder-smoothed and it is **not** what `iATR` returns; the name must never be shortened to `ATR`. Using it on both windows means the module needs **no indicator handle at all**, which is what makes it a pure function and makes Stage S2 provably inert.

**Step 3 — classification.** Requires at least two highs and two lows among the accepted pivots:

```
UP    iff  last_high > prev_high  AND  last_low > prev_low
DOWN  iff  last_high < prev_high  AND  last_low < prev_low
RANGE otherwise
UNKNOWN when two of either type are not available
```

**No tolerance band is introduced.** Two equal highs give neither UP nor DOWN and therefore RANGE, which is the fail-closed direction, and the magnitude filter has already removed noise pivots. That is one input fewer than every reviewed proposal, at no cost.

`RANGE` and `UNKNOWN` are **distinct first-class states**. Both block. The distinction exists for the journal: RANGE means "structure computed and says chop", UNKNOWN means "not enough confirmed pivots, or the window was unavailable". Conflating them is how a data problem gets read as a market condition.

**`legs_in_state` is free and must be logged.** Walking the accepted pivots back until the HH/HL (or LH/LL) chain breaks gives the index of the current leg within the current trend state at zero additional cost. Without it, "the trade gets placed at the reversal point *of the whole trend*" stays unmeasurable: entering on the second leg of an HTF uptrend and entering on the fifth are indistinguishable in every log line this repository writes. It is telemetry only in this plan — no gate reads it — but the S3 matched-subset test cannot separate those two populations unless S2 recorded it.

**Step 4 — invalidation, evaluated on the base bar.** One reviewed proposal claimed structure invalidation "costs zero bars" while writing the test against the last closed *HTF* bar — which on M15→H1 is up to four base bars stale, and six on M5→M30 and H4→D1. That claim is false as written, and the genuinely zero-lag form is free:

```
if htf.state == UP   and base bar1.close < htf.last_low   -> htf.state = RANGE
if htf.state == DOWN and base bar1.close > htf.last_high  -> htf.state = RANGE
```

The base bar's close is in hand on the evaluation bar. Invalidation is therefore current as of the signal bar, not as of the last HTF close. It can only ever **remove** permission, never grant it, and it adds no input.

**Deliberately excluded: promotion.** A "RANGE + break of the last high + a higher low already in place → UP" rule grants permission *earlier*, which is the unsafe direction, and it needs its own state. Entering a trend state requires the full HH/HL; leaving it is immediate. Asymmetric in the safe direction, zero parameters.

**Deliberately excluded: hysteresis and any carried state.** The structure is recomputed from scratch each evaluation from a fixed window of closed bars, so the verdict is a pure function of `(window, W, min_swing)` — bit-reproducible in the Strategy Tester, identical after a restart, and identical whether the EA attached ten bars ago or ten thousand. This removes an entire class of backtest-versus-live divergence that a stateful classifier with a confirmation counter and a minimum dwell would introduce, and it removes the replay/priming machinery such a classifier needs.

The cost, stated: the verdict is **not monotone in time**. A pivot scrolling out of the window can change the classification with no new price action. Mitigation is the window size plus reporting: the journal records `pivot_count`, `legs_in_state` and the four classifying prices on every bar, so a verdict flip with no new price action is visible rather than mysterious.

**Data plumbing — and why the base indicator window is NOT touched.** Raising `XSPARK_SCOREBOT_CLOSED_BASE_BARS` from 50 is what every reviewed proposal did, and it is what makes their "bit-identical" Stage 0 claims false. That constant feeds **thirteen sites, not the two they counted**: the `Bars(base) >= N + 60` guard at `IndicatorCache.mqh:145`, **five** handle-readiness requirements of `N + 1` at `:153-157`, the `CopyRates` at `:175`, **five** `CopyBuffer` length comparisons at `:181-185`, and `BaseBar`'s bound at `:222`. Raising it to 160 moves the first tradeable bar of any run roughly 110 base bars later and deletes the leading trades of every backtest.

**Ruling: leave it alone.** The structure module gets its own window, its own array and its own validity flag:

```cpp
#define XSPARK_SCOREBOT_STRUCTURE_BASE_BARS   160
#define XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS  80

MqlRates m_structure_base_rates[];      // CopyRates(sym, base,   1, 160, ...)
MqlRates m_structure_higher_rates[];    // CopyRates(sym, higher, 1,  80, ...)
bool     m_structure_valid;             // SEPARATE from m_valid

bool StructureIsValid();
bool StructureBaseBar  (const int closed_shift, XSparkCandle &bar);   // 1..160
bool StructureHigherBar(const int closed_shift, XSparkCandle &bar);   // 1..80
```

The two copies are attempted after the existing ones and set `m_structure_valid` only. `m_valid`, the warm-up guards at `:145-146` and the five base handle requirements are **byte-for-byte unchanged**, so the existing decision path is untouched and the first tradeable bar does not move. A short or `-1` return sets `m_structure_valid = false` with a reason and the structure gates refuse — **never** read as "no HTF trend", which would degrade a gate into a permission.

`CopyRates` on a non-current period needs **no indicator handle** and `start_pos = 1` excludes the forming bar, exactly as the existing HTF `CopyBuffer` at `:191` does. `start_pos = 0` must never be used: a forming bar's high and low move intrabar and a pivot computed on one would repaint. Memory cost of 240 `MqlRates` is under 15 KB.

Separately and independently: add `double RSI14BaseAt(const int closed_shift)`. `IndicatorCache.mqh:183` already copies 50 RSI values and `RSI14Base()` (`:245-248`) exposes only index 0. `CopyATR14BaseHistory` (`:263-269`) is the existing precedent for serving history from a handle the cache already owns. No new handle, no new `CopyBuffer`, no new warm-up requirement.

**Test file `MQL5/Scripts/Tests/TestMarketStructure.mq5`**, all literal bars, no terminal dependency: a clean HH/HL staircase → UP; a clean LH/LL staircase → DOWN; an equal-highs plateau → exactly one pivot, at the newest bar; an outside bar → no pivot; a sub-`min_swing` wiggle → absorbed; equal highs with rising lows → RANGE, not UP; a close through the last low → UP becomes RANGE on that bar; fewer than four pivots → UNKNOWN with a reason string; **a window engineered to produce more than `XSPARK_STRUCTURE_MAX_PIVOTS` raw pivots → `valid == false` with reason `"pivot overflow"`, never UP or DOWN**; a five-leg staircase → `legs_in_state == 5`.

### 3.3 HTF bias gate — finding (d)

`InpUseHTFStructureGate`, default **false**.

| HTF state | BUY | SELL |
| --- | --- | --- |
| `UP` | allowed | **refused** — `HTF TREND BLOCKED` |
| `DOWN` | **refused** — `HTF TREND BLOCKED` | allowed |
| `RANGE` | **refused** — `HTF RANGE` | **refused** — `HTF RANGE` |
| `UNKNOWN` | **refused** — `HTF STRUCTURE UNKNOWN` | **refused** — `HTF STRUCTURE UNKNOWN` |

`UNKNOWN` is a refusal, not an absence of filter. AGENTS.md rules 23 and 24.

This is the owner's sentence implemented literally: *an uptrend makes higher highs and higher lows*, evaluated on the higher timeframe, from data the process does not currently hold.

**It is faster than what it replaces, and it is still not fast.** `ema50_higher` has a ~24.5-HTF-bar centre of mass plus up to one HTF bar of staleness. A `W = 2` fractal confirms a pivot two HTF bars after it forms — up to eight M15 bars on the tested pair — and classification needs four alternating pivots. The base-close invalidation rule removes the exit-side lag entirely, which is the side where being late loses money, but **entry into a trend state still costs two HTF confirmation bars.**

> **Hard sequencing rule, enforced at `OnInit` and not merely written down.** `InpUseHTFStructureGate = true` with `InpUsePullbackGate = false` is **refused** by the input-combination check of section 3.8. "The H1 is up, therefore buy" on a two-pivot-lagged classifier licenses buying an already-established leg — which makes symptom (a) **worse**, not better. The HTF supplies direction only; the base timeframe supplies the price. S3 and S5 are evaluated together as well as separately, and the configuration that would produce the wrong measurement cannot be started.

**No third timeframe, and the reason is lag and observability rather than the partner table.** The table at `ScoreBotTypes.mqh:22-43` terminates at H4→D1 and ADR-021 gives its own reason: H8 has no 4× partner and lands on W1 at 21×. A third tier is *undefined* for **two** of the seven supported base periods — H2→H8→(nothing) and H4→D1→(nothing) — and `TestScoreBotV3Logic.mq5:295-313` asserts those refusals. But that argument is weaker here than it looks, and the honest version must say so: the structure module is a pure function over `MqlRates` and needs **no indicator handle**, so nothing stops a `CopyRates` on H4 while the base is M15. The refusal rests on two other grounds instead. First, lag: a `W = 2` fractal on H4 confirms a pivot eight hours after it forms and needs four such pivots to classify, so a third tier buys a slower verdict for an M15 entry, not a better one. Second, observability: one well-built HTF tier carrying real structure is fully instrumented by the S2/S3 telemetry and its verdict can be checked against the chart; two tiers multiply the joint states the matched-subset test must partition, against a sample that already cannot support the partition it has. It is also worth recording plainly that every supported ratio is an exact integer (5, 6, 4, 4, 4, 4, 6), so an HTF close always coincides with a base close and the base-bar-boundary evaluation can never miss an HTF transition — a property a hand-picked M15/H4 pair would keep but a hand-picked M15/H2 pair would not.

### 3.4 LTF aligned entry — the location gate, finding (a) first half

`InpUsePullbackGate`, default **false**. Computed from the **base** structure.

For a BUY (mirror for a SELL):

```
leg_origin  = last confirmed base swing LOW
leg_extreme = max(high[1 .. leg_origin_shift - 1])          // the run-up since that low
leg_range   = leg_extreme - leg_origin
retracement = (leg_extreme - bar1.close) / leg_range

refuse "NO QUALIFYING LEG"    if leg_range < InpMinLegATR * ATR14      (default 1.5)
refuse "LEG BROKEN"           if retracement > 1.0
refuse "NOT IN PULLBACK ZONE" if retracement outside
                                 [InpPullbackMin, InpPullbackMax]      (0.30, 0.80)
```

Below `InpPullbackMin` the entry is a chase near the leg extreme — which *is* the "middle of a trend, TP too far from the reversal" complaint. Above `InpPullbackMax` the leg is more likely failing than retracing. `retracement > 1.0` means price has closed beyond the leg origin and the premise is gone; that refusal alone removes the entire "entered at the exact reversal point of a leg that had already failed" population.

Note the window is measured against **confirmed swing pivots**, not against a fixed-lookback high/low. `docs/IMPROVEMENT_PLAN.md:334` correctly rejected an earlier anti-chase design because its scan started at the signal bar, putting any new extreme at position 1.0 by construction. A pivot-anchored leg does not have that defect: the leg extreme is a real prior high, and the signal bar's own close is the thing being located within it.

**What this does not fix.** The entry is still a market order at `bar1.close + spread` on the next tick (section 2.3, source 3). The gate removes the *chase* population by refusing to trade at a premium; it does not move the fill to a discount. The pending/limit-order path that would do that is explicitly out of scope — see section 6.

### 3.5 RSI repair — finding (b)

`InpUseRSIGate`, default **false**. Three parts.

**Part 1 — RSI becomes a gate.** The gate runs before the score. The component assignments at `ScoreBotV3.mqh:251` and `:265` are left exactly as they are, so `raw`, the ceiling and every validator are untouched. This is the only shape that changes behaviour at all, because under flat tiers a re-weighted component moves nothing.

**Part 2 — the bands are swapped. No new number is introduced anywhere.**

| Direction | Shipped | Repaired | Midpoint: shipped → repaired |
| --- | --- | --- | --- |
| BUY | `[40, 70]` | `[30, 60]` | 55 → 45 |
| SELL | `[30, 60]` | `[40, 70]` | 45 → 55 |

The fix is literally to exchange the two pairs. The long band stops rewarding strength and starts measuring how far the pullback has come; the short band mirrors it. Once direction comes from HTF structure, RSI's only remaining job is pullback **depth**, so near-symmetric bands overlapping around 50 are correct rather than a defect — a static level cannot express direction and must not be asked to.

For a *mean-reversion* system the correct bands would be roughly longs `[25, 45]` and shorts `[55, 75]`. The shipped bands are neither shape: they are momentum-continuation bands with no trend gate to make continuation meaningful. Naming that is the reason re-tuning the numbers without the HTF gate would not help.

**The outer bounds are inherited, not repaired, and this is named rather than glossed.** Under the pullback-depth reading the *inner* bound of each swapped band does the work: 60 for a BUY stops the long being taken at the top of the leg, 40 for a SELL likewise. The *outer* bound does not follow from that reading at all. A SELL at RSI 75 inside a confirmed HTF downtrend is the deepest counter-rally available — arguably the best short on the chart — and the swapped `[40, 70]` band refuses it. The mirror refuses a BUY at RSI 25. Those two bounds are exhaustion guards carried over from the momentum shape; they are **retained unvalidated**, because removing them is an additional behaviour change with no evidence behind it either way. S4's observe-mode telemetry must record the count refused by the outer bound separately from the count refused by the inner bound, so the question becomes answerable rather than inherited. If the outer-bound population is negligible, the bounds are harmless; if it is large, they are a second hypothesis riding inside the first and must be split out.

**Part 3 — optional turn condition, `InpRequireRSITurn`, default false.** A static level cannot express "the pullback is ending". Requires `RSI14BaseAt(1) > RSI14BaseAt(2)` for a BUY, the mirror for a SELL. Costs nothing: the history is already copied (section 3.2).

**Behaviour-change disclosure.** Swapping the four inputs also changes the `rsi` **component**, because the strategy reads the same members. Arithmetic, **at the shipped `InpMinScore = 2.0` and `InpLongScoreExtra = 0.0`**: removing 1.0 from `raw` can only drop a trade below the threshold when the resulting raw falls under it. At weight 1.2 the raw requirement is 1.667 and at 1.0 it is 2.000, and `pattern + atr >= 2.55` for a pin — so **the swap changes no trade in London or New York hours.** At weight 0.6 the raw requirement is 3.333 and it does change trades. **The band swap is behaviour-changing in Asian hours only** — *at shipped defaults*. That qualifier is load-bearing and section 4's S4 carries it, because at `InpMinScore = 4.0` (section 7, question 5) the required raw is 4.000 at weight 1.0 against a `pattern + atr` ceiling of 3.0, and the `rsi` point becomes decisive in every session.

**`mtf` is left alone, deliberately.** Its sign is wrong (section 2.2) and fixing it is a one-character change. But under flat tiers it moves neither trades nor dollars at weight ≥ 1.0, and once the RSI gate is in front, every trade `mtf` would have rewarded is already vetoed. Deleting or inverting it changes `raw`, which changes Asian-hour trades and drops `max raw` to 7.0 — raising a tier-reachability question for no benefit. It is recorded as a known-wrong telemetry term, to be corrected only in a future change that also decides the tier question. This is scope discipline, not an oversight.

### 3.6 Structure-aware stops and targets — finding (a) second half

**Step 1 — make `desired_target` live.** `XSparkTradePlan` gains `desired_target` and `structural_target`. Both consumers use `plan.desired_target` when `structural_target` is true and the value is on the profitable side of the entry, and otherwise fall back to `risk_distance × dynamic_rr` exactly as today: `XSpark.mq5:713-717`, the recompute at `:762-767`, and `ExecutionEngine.mqh:184-187`. **All three must change together or the strategy's target is silently discarded.**

The "profitable side" test must be re-evaluated at `ExecutionEngine.mqh:184` against `current_entry_reference`, not only against `plan.entry_reference`. After up to `m_deviation_score_points` of permitted drift (`:110-122`) an absolute structural target that was valid at planning can be on the wrong side at send time. The explicit rule: if the structural target is not on the profitable side of the refreshed reference, **fall back to `XSparkTargetFromRiskDistance` and log the substitution with both prices**. Leaving it to the RR bound at `:221-228` to catch would turn a recoverable drift into an unexplained refusal.

**Step 2 — structural stop.** `InpUseStructuralStop`, default false. Bar-derived, closed-bar, no live quote:

```
BUY:  raw_stop = MathMin(bar1.low, base.leg_origin) - InpStopBufferATR * ATR14    (0.25)
      distance = entry_reference - raw_stop
      if distance < InpATRMultSLFloor * ATR14  -> distance = floor          (floor 1.0)
      if distance > InpATRMultSLCap   * ATR14  -> REFUSE "STOP TOO WIDE"    (cap   3.0)
      desired_stop = entry_reference - distance
```

The floor is **not** a hedge; it is what keeps the ADR-024 guarantee true by construction (section 3.9). The cap **refuses** rather than clamps, because a clamped stop sits at a price with no structural meaning, and because widening a stop multiplies the target through `TP = RR × risk_distance`.

**The cap must be re-checked after broker adjustment, or the refusal is not a refusal.** `ExecutionEngine.mqh:147-213` runs up to two `XSparkAdjustProtectionLevels` passes that can **widen** the stop to clear `SYMBOL_TRADE_STOPS_LEVEL`, growing `risk_distance` after the strategy-side cap check has already passed. On a symbol with a wide stop level the "refuse rather than clamp" guarantee silently fails. The cap is therefore re-evaluated once the loop stabilises (after `:209-213`) against the final `risk_distance`, and a breach refuses there with the same reason string.

Why the floor is 1.0 and not the 0.6-0.75 the reviewed proposals used: for a bullish pin with `range ≈ 1.5 × ATR14`, `close − low ≈ 0.83 ATR`, plus the buffer gives ≈ 1.08 ATR — above the floor. For a large pin (`range ≈ 3 ATR`) it is ≈ 1.9 ATR. **The floor binds only on small bars, where an ATR-scaled stop is the right answer anyway**, and it holds the realised-risk overshoot degradation to a factor of 1.5 rather than 2.0-2.5.

**Both new multipliers are validated.** `XSpark.mq5:300-308` validates `InpATRMultSL > 0.0` and nothing else; the plan adds two more multipliers, so it adds their checks: `InpATRMultSLFloor > 0.0`, `InpATRMultSLCap >= InpATRMultSLFloor`, and `InpATRMultSLFloor <= InpATRMultSL`. Failure is **Critical-and-block-new-entries**, not `INIT_FAILED`, for the reason given in Step 5. Without `floor > 0` the re-based `XSparkEntryDriftBound` returns FAULT (`ExecutionMath.mqh:279-283`), which is at least fail-closed — but the diagnosis would point at the wrong input.

**Step 3 — structural target, and the ruling that avoids a trap two reviewers found independently.**

The obvious rule — *target = the nearest opposing swing extreme* — is wrong for a continuation trade, in two compounding ways.

*First*, in an uptrend the prior swing high is the level the trend is expected to **exceed**. Targeting it converts a trend-following entry into a range fade and caps every winner at the breakout point.

*Second*, it collides arithmetically with `InpMinRR`. For a long entered at retracement *r* of a base leg of range *D = k × ATR*, with the stop at the leg origin minus a 0.25 ATR buffer and the target at the leg extreme minus a 0.25 ATR buffer:

```
RR(r, k) = (r·k − 0.25) / ((1 − r)·k + 0.25)
```

| retracement *r* | *k* = 2 | *k* = 3 | *k* = 4 | *k* = 6 |
| --- | --- | --- | --- | --- |
| 0.30 | 0.21 | 0.28 | 0.31 | 0.35 |
| 0.40 | 0.38 | 0.46 | 0.51 | 0.56 |
| 0.50 | 0.60 | 0.71 | 0.78 | 0.85 |
| 0.60 | 0.90 | 1.07 | 1.16 | 1.26 |
| 0.70 | 1.35 | 1.61 | 1.76 | 1.93 |
| 0.80 | 2.08 | 2.53 | 2.81 | 3.13 |

Setting `RR = 1.5` and solving gives `r = 0.6 + 0.25/k` exactly: **0.725** at *k* = 2, **0.683** at *k* = 3, **0.6625** at *k* = 4, **0.6417** at *k* = 6. **The stated pullback window `[0.30, 0.80]` would collapse to roughly `[0.66, 0.80]` — the deep-retracement band nearest the leg-break boundary, which is the closest thing to the operator's "trade gets placed at the reversal point" complaint.** The design would fix half of (a) by manufacturing the other half.

**Two reviewers disagreed here and both were right about different things.** One argued that requiring a deep retracement *selects the weakest instances* of the HTF trend, because strong trends produce shallow 23-38 % pullbacks and retracements past 50 % are more typical of failing structure. The other showed the RR floor forces retracements *deeper still*. These are not contradictory: they compound, and together they are the strongest argument against naive structural targeting. The ruling follows from taking both seriously.

**Ruling — three branches, in order, none of them a silent fall-through.**

*Branch 1 — overhead structure.* The structural target is the nearest unbroken opposing level **strictly beyond the current leg extreme**, searched first on the base structure and then on the HTF structure:

```
BUY:  candidates = { nearest unbroken base swing HIGH  > base.leg_extreme,
                     nearest unbroken HTF  swing HIGH  > base.leg_extreme }
      T = MathMin(candidates)
      desired_target = T - InpTargetBufferATR * ATR14                    (0.25)
```

With overhead structure a distance *g* above the leg extreme, `RR = (r·k + g/ATR − 0.25)/((1 − r)·k + 0.25)`. At *k* = 4 with *g* = 2 ATR: *r* = 0.40 → 1.26, *r* = 0.50 → **1.67**, *r* = 0.60 → 2.24. **Overhead structure is what makes mid-pullback entries viable, and its absence is what would otherwise force a deep entry.**

*Branch 2 — no overhead structure: the measured move.* When there is no unbroken opposing level above the leg extreme — a trend making new highs, which is **exactly the regime the HTF gate preferentially selects** — falling through to `risk_distance × dynamic_rr` would hand the majority of the surviving population back to the double-ATR compounding this plan blames for the operator's complaint. That is not acceptable as a default, and an earlier draft of this document did it. Instead the target is the leg projected once from its own origin:

```
BUY:  desired_target = base.leg_extreme + base.leg_range
```

No buffer, because there is no level to stand off from, and **no new input** — both terms are already in `XSparkStructure`. Its reward ratio is `RR = (1+r)·k / ((1−r)·k + 0.25)`:

| retracement *r* | *k* = 1.5 | *k* = 2 | *k* = 4 | *k* = 6 |
| --- | --- | --- | --- | --- |
| 0.30 | **1.500** | 1.576 | 1.705 | 1.753 |
| 0.50 | 2.250 | 2.400 | 2.667 | 2.769 |
| 0.80 | 4.909 → capped | 5.538 → capped | 6.857 → capped | 7.448 → capped |

The value in bold is not a coincidence worth passing over. At the shallowest permitted pullback (`InpPullbackMin = 0.30`) on the smallest qualifying leg (`InpMinLegATR = 1.5`) with the shipped buffer (`InpStopBufferATR = 0.25`), the measured move gives **exactly `InpMinRR = 1.5`**, and the ratio increases monotonically in both *r* and *k* from there. **The measured-move branch therefore does not collapse the pullback window the way the opposing-level branch does** — the whole of `[0.30, 0.80]` survives it. Two caveats, stated rather than buried: the identity assumes the stop is anchored on `leg_origin − 0.25 ATR`, so a `bar1.low` below the leg origin, or the `InpATRMultSLFloor` binding on a small bar, both widen the risk and can push the ratio under `InpMinRR` — in which case Step 4 refuses, which is the designed behaviour and not a hole.

*Branch 3 — neither available.* If the structure is valid but no leg qualifies, there is no target to compute. `InpRequireStructuralTarget` (default **false**) decides: false falls back to the existing `dynamic_rr` target, true refuses with `NO STRUCTURAL TARGET`. Either way **the branch taken is recorded on every trade**, and section 4's S7 pre-registers the frequency, because a mean-R result attributable to a target change on a minority of trades is not a result about targets.

**Step 4 — the RR bounds become real, are tightened rather than loosened, and their tolerance is derived.** One reviewed proposal raised `InpMaxRR` from 3.0 to 6.0 as a **default-on** change, while the structural target that justified it shipped default-off. With structural targets off, the surviving consumer is `XSparkScoreBotDynamicRR`, which saturates at `max_rr` — so that change would place ATR-derived targets **up to twice as far away** in the recommended default configuration. Against an operator complaint that the TP is already too far, that is a straight regression. Rejected.

**Ruling.** `InpMinRR` and `InpMaxRR` keep their defaults of 1.5 and 3.0, and neither is loosened.

| Structural RR | Action |
| --- | --- |
| `< InpMinRR` | **Refuse** the trade, `RR BELOW MINIMUM`. The target is never stretched to meet the ratio. |
| `[InpMinRR, InpMaxRR]` | Use the structural target. |
| `> InpMaxRR` | **Cap** the target at `InpMaxRR × risk_distance` and log the level that was rejected. |

Consequence: **a structural target can only ever move the take-profit closer than the existing configured maximum, never further.** No risk bound is widened, AGENTS.md rule 5 is not engaged, and the operator's complaint is addressed in the direction they described. The cost, stated plainly: `InpMinRR = 1.5` becomes the system's primary trade filter, so a setup whose real runway is 1.2 R is now **rejected** rather than taken with a 1.2 R target. That is arguably correct, but it is a behavioural change inherited by accident unless it is named — so the effective floor on *r* is `max(InpPullbackMin, the r implied by InpMinRR)`, and **the journal records which of the two bound.**

**And the tolerance must be derived from the tick, not inherited.** Section 2.4 established that the existing checks already refuse trades on a half-tick artefact when `dynamic_rr` is a half-integer, because `XSPARK_RR_EPSILON` is 1e-7 while the smallest representable displacement of a normalised target is `tick / risk_distance` — 0.0083 on gold at the ATR floor. A structural target is a bar price, so `dynamic_rr × risk_distance` is no longer even approximately an integer number of ticks and **every** structural trade sits on that knife edge, not just the half-integer ones. `XSparkRRIsWithinBounds` (`ExecutionMath.mqh:146-155`) therefore gains an explicit tolerance argument, and both call sites pass:

```
tolerance = MathMax(XSPARK_RR_EPSILON, tick_size / risk_distance)
```

`tick_size` bounds the total displacement from two independent half-tick roundings, so this is the exact bound, derived rather than chosen. It ships as Stage S8c, alone, because it changes behaviour **today** at shipped defaults and in the direction of *more* trades — the only such change anywhere in this plan.

**Step 5 — the exit stack, which must land with or before Step 3.** Structural targets are frequently *nearer* than the ATR target, which makes the partial at 2.5 R **less** reachable, not more. If Step 3 ships alone, the management stack dies completely. **Four** changes, all strictly stop-tightening:

- **Decouple break-even.** Its own trigger `InpBreakEvenR` (default 1.0) and its own arm, independent of `partial_done`. Placed at `entry ± InpBreakEvenBufferATR × ATR14` (0.10) rather than the raw fill price — `PositionManager.mqh:1518` passes `m_states[active_index].entry` today, so a "break-even" exit is a guaranteed net loss of spread plus commission.
- **Decouple the trail.** This was missing from the first draft of this plan and its absence made S7's own pre-registration unreachable. `PositionManager.mqh:1556` reads `if(m_states[index].partial_done && atr14 > 0.0)`. Since Step 3 makes the partial *less* reachable, decoupling break-even alone leaves the trail deader after S7 than before it, and the motivating failure — "a trade that runs to +1.2 R at the real reversal and turns" — still takes a full −1 R. The trail gets its own arm `InpTrailArmR` (default equal to `InpBreakEvenR`) evaluated against the fill-based R denominator, `XSparkTradeState` gains `trail_armed` and `be_armed`, both are persisted alongside `partial_done` (`PositionManager.mqh:142-143` persist, `:193-194` load, `:281` reset, via `PersistStateChecked` at `:152`), and `:1556` tests `trail_armed`. The ratchet at `:1580-1596` is already correct and is not touched.
- **Validate `InpPartialTPRatio` against `[InpMinRR, InpMaxRR]` — but as a clamp, not as `INIT_FAILED`.** `XSpark.mq5:300-304` checks only `InpPartialTPRatio <= 0.0`, so `3.5` against `InpMaxRR = 3.0` — an entirely reasonable-looking "bank later" edit — silently amputates partial, break-even and trailing on 100 % of trades with no log line. The fix must **not** go into `XSparkValidateInputs`, whose only failure path is `XSpark.mq5:1399-1405 → INIT_FAILED`: an operator already running that configuration with an open position would, on the next reload, get `INIT_FAILED`, `PositionManager` would never initialise, `ReconcileOnInit` would never run, and the live position would lose trailing, break-even, the weekend close and the killswitch flatten. The file already refuses to do this to itself for a strictly more serious fault (`XSpark.mq5:449-450`: *"Deliberately NOT INIT_FAILED. Refusing to initialise would abandon any live position to the broker with no XSpark management at all"*), and AGENTS.md rules 21 and 22 make broker positions the source of truth that must be reconciled at init. Follow that precedent: clamp the effective ratio to `MathMin(InpPartialTPRatio, InpMaxRR)`, log `g_logger.Critical` with the exact clamp, and record the clamped value in the entry journal so it is visible per trade.
- **Unify the R denominator.** The TP is priced off `plan.risk_distance`, a planning-time quote reference (`XSpark.mq5:695`, recomputed `:760`); the partial is priced off `state.initial_risk_distance = MathAbs(POSITION_PRICE_OPEN − initial_sl)` (`PositionManager.mqh:559`, consumed at `:1452`). The inequality runs one way and it is worth writing out, because "the two can differ" does not explain why the partial becomes *unreachable* rather than merely mispriced. For a BUY whose fill slipped adversely by δ, `initial_risk_distance = plan.risk_distance + δ`, so the partial trigger sits at `entry_ref + δ + 2.5(plan.risk_distance + δ)` while the broker TP sits at `entry_ref + 3.0 × plan.risk_distance`. The partial is beyond the TP whenever `3.5δ > 0.5 × plan.risk_distance`, i.e. **whenever the fill slips more than 14.3 % of the planned stop distance** — and ADR-024 records the shipped gold allowance as `30 / (1.5 × 80) = 0.25`, i.e. up to 25 %. At `dynamic_rr` exactly 2.5 *any* adverse slip puts it beyond. Use the **fill-based** denominator — it is the real risk taken — and log both plus their ratio on every entry.

This is `docs/IMPROVEMENT_PLAN.md` Stage 5, extended by the trail decoupling, including its pre-registration of the P&L effect at **zero or slightly negative**. It appears here as a prerequisite, not as new profitability work.

### 3.7 Pattern selection and additions — finding (c)

**Two things must land before any new detector, or the additions make matters worse.**

**(1) Best-of ranking replaces first-match.** Run every enabled detector into `XSparkPatternResult candidates[]`; **discard any candidate whose direction contradicts the HTF structure verdict** (free, given section 3.3, and it dissolves the BUY-pin-during-a-SELL collision at no cost); keep the highest score; tie-break by an explicit named priority constant. If the two highest surviving candidates point in **opposite** directions with scores within `InpPatternConflictTol`, block the bar with `PATTERN CONFLICT`. Record the runner-up id and score in the report so the journal shows when detectors disagreed.

**(2) A pattern instance key, or multi-bar patterns fire every bar.** There are **two** duplicate guards today, both keyed on the signal bar time and both RAM-only: the evaluation-side check at `XSpark.mq5:1122-1130`, and `CXSparkExecutionEngine::CanSubmitSignal` (`ExecutionEngine.mqh:512-523`, state member `m_last_submitted_signal_bar_time` at `:30`) via `XSparkSignalBarIsSubmittable` (`ExecutionMath.mqh:46-65`). The execution-side one is documented at `ExecutionEngine.mqh:709-711` as state that "must survive for the life of the run", and it is deliberately not reset by `SetEntryDeviationScorePoints`. Neither survives a restart, and neither can express *"this pattern instance already traded"*. Every current pattern is a property of bars 1-3 and stops being true as the window slides — its sufficiency today is an accident of that. A double bottom or a neckline break is a property of a 30-200 bar window and stays true on the next bar and the bar after.

`XSparkPatternResult` therefore gains `datetime instance_time` (the completing pivot for structure patterns, the impulse-start bar for a flag, `bar1.time` for the three legacy patterns), the strategy emits it on the signal, and **the EA latches it beside the existing bar dedupe at `XSpark.mq5:1122-1130`, not inside the strategy.** Section 3.2's correctness argument rests on the structure module being a pure function of `(window, W, min_swing)`; a strategy file that reads terminal global variables is no longer a pure function of closed bars, which would weaken both the bit-reproducibility claim and the module separation AGENTS.md rule 40 requires. The strategy reports; the EA remembers. The execution-engine guard stays exactly as it is, as the second opinion.

> **The latch is persisted through `StateStore`, and a failed persist refuses the entry.** AGENTS.md rules 18, 19 and 20. `CXSparkStateStore::Set` (`StateStore.mqh:69-72`) returns `GlobalVariableSet(...) > 0` — it **can fail**, and `PositionManager` already recognises this class of failure and routes it through `PersistStateChecked` (`:152`, used at `:1505`, `:1532`). Three rules, all of which must hold:
> - The latch is written **before** the entry is attempted, and a failed write **refuses the entry** with an explicit block reason. Logging it and proceeding would produce multiple entries from one logical signal on the next bar and every bar the pattern remains true.
> - The stored value is the `instance_time` itself, not a boolean. On reload an absent key must not be read as "not yet fired" for an instance older than the current bar; carrying the timestamp makes the comparison absolute rather than relative to process lifetime.
> - This is on S9's **refuse to ship if** list alongside the first multi-bar detector.

**Defect fixes to the existing three detectors.**

- **Pin opposite-wick constraint.** Add `upper <= InpPinOppositeWickMax * lower` for the bullish branch and the mirror for bearish. **The admissible window is fixed by the repository's own fixtures.** The canonical pin fixture (`TestScoreBotV3Logic.mq5:52`, `O=100.00 H=101.00 L=98.70 C=100.20`) has `lower = 1.30`, `upper = 0.80`, so preserving it requires `T >= 0.80/1.30 = 0.61538`. The two-sided doji counterexample has `lower = 0.55`, `upper = 0.43`, so rejecting it requires `T < 0.43/0.55 = 0.78182`. The window is therefore **[0.61538, 0.78182)**, exclusive at the top — a value of 0.782 would admit 0.7819, which accepts the doji the constraint exists to reject. **Default 0.65**, which is *not* the strictest value in the window (0.61538 is) but a small deliberate margin above it, so that a bar geometrically identical to the shipped fixture is not sitting exactly on the boundary where a tick of rounding decides. Worth recording either way: the repository's reference "pin bar" is a bar whose opposite wick is 62 % of its rejection wick, which is itself informative about how loose the current definition is.
- **Inside-bar breakout triggers against the mother bar.** `bar1.close > bar3.high` / `< bar3.low` instead of bar2's extremes. **The fixture at `TestScoreBotV3Logic.mq5:71-79` must change in the same commit, and that diff is the visible evidence of the fix.**
- **Engulfing:** remove the provably redundant `body1 > body2` clause (`:59`, `:73`), and floor the denominator with `body2 >= InpEngulfMinBody2ATR * ATR14` (default 0.15), because the score reaches its 2.0 cap on a body ratio of 3.0 and engulfing a near-doji reaches that ratio on no information.

**New detectors.** All share the existing `pattern` slot, all `MathMin(2.0, ...)`, so `pattern` max stays 2.0 and the ceiling never moves. Each behind its own input, each default **OFF**, each shipped one at a time.

| Pattern | Input | Bars | Free thresholds | Verdict |
| --- | --- | --- | --- | --- |
| **Bull/bear flag** | `InpUseFlagPattern` | 10-20 | 4 | **Ship first.** Needs no pivots, fits the window, and is *continuation* — which is what (d) asks for. |
| **Double top/bottom** | `InpUseDoublePattern` | 15-40 | 2 | **Ship second.** Best evidence-to-complexity ratio of the pivot set; the depth filter is what stops it degenerating into "any range". |
| **Head & shoulders** | `InpUseHSPattern` | 25-60 | 2 (+ neckline interpolation) | **Ship last, default off.** The owner asked for it by name and the pivot series makes it cheap. Five free pivots and three tolerances mean a large fraction of any noisy swing sequence can be labelled an H&S; **every tolerance loosened to "find more" is a fitted parameter.** This is the item most likely to be retired. |
| **Quasimodo** | — | 20-50 | 1 | **Not shipped.** Noted because it is a pure pivot-sequence predicate with a single equality tolerance and no ratio folklore, making it strictly *more* specifiable than H&S. It is the replacement to consider if H&S is retired. |
| **Triangles / wedges** | — | — | ≥ 5 | **Refused.** The specification *is* the curve fit: which pivots, how many, minimum least-squares fit quality, what counts as converging, how close to the apex is too close. Nothing in this repository's evidence base can set any of them. |
| **Three-drive** | — | — | ≥ 3 | **Refused.** Fibonacci tolerances (0.786 / 1.27 / 1.618 ± x) between five to seven pivots. The ratios are not derivable from anything; picking the tolerance is choosing how many trades you get. |

Flag definition (no pivots required): impulse of *N* ∈ [3,8] consecutive closed bars with net move ≥ `InpFlagImpulseATR × ATR14` (1.5) and aggregate body/range ≥ `InpFlagBodyFrac` (0.50); consolidation of *m* ∈ [3,10] bars with total range ≤ `InpFlagCompression × impulse_range` (0.50) and retracement ≤ `InpFlagMaxRetrace` (0.50); trigger is a close beyond the consolidation boundary in the impulse direction. *N* and *m* bounds are constants, not inputs.

**`InpMinSwingATR` couples S3 and S9, and the two are not independently falsifiable.** The double-top and head-and-shoulders detectors read the **same accepted pivot series** the classifier reads — deliberately, so the system carries exactly one definition of what counts as a swing, rather than two that can drift apart. The consequence must be stated rather than discovered: a neckline retracement smaller than `min_swing` is absorbed by the alternation rule, so a shoulder merges into the head and the pattern becomes undetectable. **Any change to `InpMinSwingATR` invalidates every prior per-detector result**, and S9's expectations are conditional on the value fixed in S3. Giving the detectors a second, separately-named minimum would break the coupling at the cost of a second definition and a thirty-fifth input; that trade is refused.

> **Two honest statements about (c).**
>
> **Adding patterns does not reduce lag — it increases it.** A `W = 2` fractal confirms a pivot two closed bars after it forms, and a five-pivot H&S inherits that floor five times. The only non-lagging trigger any of these has is the break bar, which is by definition after the move started. **The pattern additions answer (c) on its own terms and must not be sold as a fix for (a).**
>
> **Under this design a pattern cannot create a trade on its own.** Every gate still applies. The blast radius of a false positive is therefore a wrong risk tier and a wasted candidate, not a wrong trade — which is the only condition under which adding detectors is safe at all. Under today's arithmetic each new detector would be another *standalone trade trigger*, so shipping patterns before the gates would be strictly negative. **That argument is conditional on inputs that default to off, so section 3.8 makes the configuration it depends on an `OnInit` requirement rather than a sentence in a document.**

### 3.8 The score-ceiling decision, and the input-combination guard

**`XSPARK_SCOREBOT_MAX_SCORE` stays at 9.0. `XSPARK_SCOREBOT_TIER3_THRESHOLD` stays at 5.5. `XSPARK_SCOREBOT_TIER2_THRESHOLD` stays at 4.5. No component is added, none is removed, and the session multiplier is not moved. In every stage.**

The ceiling is saturated to 1e-7, verified against `Dashboard.mqh:327-333`:

| Component | Max | Source |
| --- | --- | --- |
| pattern | 2.0 | `PatternDetector.mqh:26, 38, 65, 79` — all `MathMin(2.0, …)` |
| atr | 1.0 | `ScoreBotV3.mqh:243` — literal |
| trend | 1.0 | `ScoreBotV3.mqh:248, 262` |
| rsi | 1.0 | `ScoreBotV3.mqh:251, 265` |
| sr | 1.0 | `ScoreBotV3.mqh:254, 268` |
| volume | 1.0 | `ScoringEngine.mqh:61` — `MathMin(1.0, …)` |
| mtf | 0.5 | `ScoreBotV3.mqh:257, 271` |
| **max raw** | **7.5** | |
| **× max session weight 1.2** | **9.0000** | `ScoringEngine.mqh:26-27` |

`XSparkScoreBotScoreIsValid` (`ScoringEngine.mqh:74-77`) accepts up to `9.0 + 1e-7`. A breach becomes `status = "SCANNING"` at `ScoreBotV3.mqh:284-290` and is escalated to `g_logger.Error` at `XSpark.mq5:1154-1155`. **A single new 0.5-point component would send the best London/NY-overlap setups to 9.6 and turn the strongest setups into logged faults while mediocre ones keep trading.** `docs/IMPROVEMENT_PLAN.md:340` named this trap; a veto costs exactly 0.0 of the ceiling, so that refusal is **satisfied** by this design, not overridden.

**The one-line fix that must never be made is `MathMin(score, 9.0)`.** It converts a detected invalid state into an accepted trade and violates AGENTS.md rule 23. The engine must keep failing closed at `ScoreBotV3.mqh:284-290` and at the duplicate in `RiskManager.mqh:237-241`. A comment at the call site should say so.

**A protective guard so this cannot rot** (adds no behaviour, ships default-on):

Define **one** set of named per-component maximum constants in `ScoringEngine.mqh`, and have the sum, `Dashboard.mqh:327-333` (which hardcodes them today), the `OnInit` threshold validation at `XSpark.mq5:276-291`, **and the `RiskManager.mqh:237` duplicate check** all read those constants — one definition, so the ceiling cannot drift from the arithmetic by editing any one of the four. A plan that creates a fifth definition of the ceiling while arguing against drift has defeated itself.

```cpp
double XSparkScoreBotMaxReachableRaw();     // sum of the named constants
double XSparkScoreBotMaxReachableFinal();   // × XSPARK_MAX_SESSION_WEIGHT
```

At `OnInit`: assert `MaxReachableFinal() <= XSPARK_SCOREBOT_MAX_SCORE + 1e-7`, CRITICAL otherwise; validate `InpMinScore` and `InpMinScore + InpLongScoreExtra` against `MaxReachableFinal()` rather than against the macro (`XSpark.mq5:276-291` compares against the macro today); and log max reachable raw, max reachable final at each of the three session weights, and whether `InpMinScore`, 4.5 and 5.5 are reachable at each. This is the guard that closes the ADR-026 failure class — *"a EURUSD M15 run took zero trades … the EA reported itself healthy while doing nothing"* — where a threshold that cannot be reached passes validation and the EA scans forever.

**Honest limit of that guard**, because one reviewer was right to flag it: a sum of maxima proves only that the threshold is not *trivially* unreachable. It does not prove any single bar can simultaneously attain several maxima. It is worth adding; it is not a completeness proof.

**The input-combination guard, in the same `OnInit` block.** Three checks, each Critical-and-block-new-entries (the `XSpark.mq5:449-450` posture, not `INIT_FAILED`, so a live position keeps its management):

1. `InpUseHTFStructureGate && !InpUsePullbackGate` → refuse, naming section 3.3. "The H1 is up, therefore buy" on a two-pivot-lagged classifier is the configuration risk 6.2.1 calls prohibited, and prose does not survive a merge.
2. Any of `InpUseFlagPattern`, `InpUseDoublePattern`, `InpUseHSPattern` true while `InpUseHTFStructureGate` or `InpUsePullbackGate` is false → refuse, naming section 3.7. The safety argument for adding detectors — *"the blast radius of a false positive is a wrong risk tier, not a wrong trade"* — is entirely conditional on gates that default to off. Without them an operator who enables one detector gets a new standalone 3 %-of-balance trigger with no log line.
3. `InpUseStructuralTarget && !InpUseBreakEvenDecoupled` → refuse, naming section 3.6 Step 5. A nearer target with the management stack still behind `partial_done` is strictly worse than today.

These land **with** the stage they protect — in S3's, S9's and S7's change sets respectively — not as a follow-up.

**`InpMinScore` stays at 2.0.** The gates remove the trades a higher floor would remove, and more, for better-stated reasons. But the arithmetic is worth recording because it is available to the operator **today with no code at all**: the unaided ceiling is `(pattern 2.0 + atr 1.0) × 1.2 = 3.60`, so **4.0 is the smallest round value a candle shape plus the volatility-band constant provably cannot clear at any session weight.** The cost is that at weight 0.6 the raw requirement becomes 6.67 of a possible 7.5, which effectively ends Asian-session trading — and that it invalidates the S4 and S8b pre-registrations as written (section 7, question 5). It is offered in section 7 as a one-input mitigation, not as part of the default path.

### 3.9 Safety interactions that must land in the same commit as the change that breaks them

**ADR-024, and the ruling that avoids both a 2.5× silent weakening and a 33 % silent weakening in the opposite direction.**

`XSparkEntryDriftBound` (`ExecutionMath.mqh:262-333`) computes `min_risk_distance_score_points = atr_mult_sl × atr_min_score_points` at `:291` and `overshoot_ratio = deviation_score_points / that` at `:299`, faulting at ratio ≥ 1.0 (`:307`) and warning above 0.20 (`:38-39`, `:318`). Its entire premise is that **no trade can have a stop tighter than `InpATRMultSL × InpATRMinPoints`**. A structural stop breaks that premise.

It is called at **two** sites, not one: `XSpark.mq5:437-442` at init with manual inputs, and `XSpark.mq5:1050-1055` after every calibration with the derived values, where a FAULT returns `false` and blocks (`:1061-1065`).

One reviewed proposal's remedy — recompute the bound from the new floor — is a **weakening presented as a strengthening.** On gold defaults (deviation 30, `InpATRMultSL` 1.5, `InpATRMinPoints` 80) the ratio is `30 / 120 = 0.25`. Recomputed from a 0.6 floor it becomes `30 / 48 = 0.625`: a 2.5× degradation of the realised-risk guarantee, described as "strictly stronger than today". Against a 1.0 floor it is `30 / 80 = 0.375`, still 1.5× worse.

**Ruling — re-base the *definition*, but add a second derived field rather than editing `AutoTune.mqh:199`.** The first draft of this plan said to re-base `AutoTune.mqh:199` itself when `InpUseStructuralStop` is true. That is wrong, and it is wrong in the one direction ADR-024 explicitly documents as forbidden. `result.min_stop_points` at `:199` is the base for **three** derived thresholds, not one:

```
AutoTune.mqh:199   result.min_stop_points       = result.atr_min_points * atr_mult_sl;
AutoTune.mqh:200   result.entry_deviation_points = result.min_stop_points * (entry_deviation_pct / 100.0);
AutoTune.mqh:201   result.exit_deviation_points  = result.min_stop_points * (exit_deviation_pct  / 100.0);
AutoTune.mqh:202   result.spread_cap_points      = result.min_stop_points * (spread_cap_pct      / 100.0);
```

`exit_deviation_points` is pushed into `PositionManager` at `XSpark.mq5:1036` via `SetExitDeviationScorePoints`, and `PrepareTradeContext()` (`PositionManager.mqh:76-90`) converts it into `m_trade.SetDeviationInPoints(...)`. `PrepareTradeContext()` is called at `:1694`, immediately before the `m_trade.PositionClose(ticket)` loop at `:1702-1704` — **the flatten campaign that executes the total-drawdown killswitch and the weekend close.** At gold defaults (`InpExitSlipPct = 85`, `InpSpreadCapPct = 40`, min stop 120) that is an exit tolerance of 102 points and a spread cap of 48. Re-based on a 1.0 floor they become 68 and 32: the emergency flatten is submitted with **a third less slippage room**, in exactly the fast-market conditions that latch the killswitch, and the spread cap silently narrows the admitted trade population, contaminating every S6/S7 before-and-after comparison. ADR-024 says this in words at `docs/DECISIONS.md:170`: *"On an exit, a tolerance that is too generous costs a slightly worse fill; a tolerance that is too tight gets the close REJECTED and leaves live exposure that XSpark intended to be flat… an upper bound there would be a risk control pointing the wrong way."* AGENTS.md rules 5, 9 and 10.

**Corrected ruling.** `AutoTune.mqh:199` is **not touched**. A separate field is added:

```
result.structural_min_stop_points = result.atr_min_points *
                                    (use_structural_stop ? atr_mult_sl_floor : atr_mult_sl);
```

and it is used in **exactly two places**: `AutoTune.mqh:200` (`entry_deviation_points`) and both `XSparkEntryDriftBound` call sites (`XSpark.mq5:437-442`, `:1050-1055`). Lines `:201` and `:202` keep reading `result.min_stop_points` on `InpATRMultSL`, so `exit_deviation_points` and `spread_cap_points` are **byte-for-byte unchanged whether the structural stop is on or off**. `TestAutoTune.mq5` gains an assertion that says so.

| Mode | Today | Bound re-based only | **This plan** |
| --- | --- | --- | --- |
| Auto-tune on (default), entry bound | 0.25 by construction | 0.375 (floor 1.0) | **0.25 by construction** — the entry allowance shrinks with the stop |
| Auto-tune on, exit tolerance | 102 pts | 68 pts (silently) | **102 pts, unchanged** |
| Auto-tune on, spread cap | 48 pts | 32 pts (silently) | **48 pts, unchanged** |
| Auto-tune off, manual 30 pts | 0.25 | 0.375 | **0.375, and the operator is told loudly at init** |

ADR-026's invariant — *"a derived deviation satisfies the drift bound by construction"* — is preserved rather than broken. In manual mode the guarantee genuinely degrades and the correct response is a louder warning, not a quieter bound.

**Plus a per-trade assertion — sited where it can actually bind.** An init-time bound derived from inputs is no longer sufficient once the stop is data-derived. The first draft placed the assertion in `XSparkPrepareTradePlan`, where it cannot do the job: that function computes `risk_distance` from `g_market_state.Ask()/Bid()` at planning time, while the order is sent from `ExecutionEngine`, which refreshes the quote and recomputes its own `risk_distance = XSparkRiskDistance(plan.direction, current_entry_reference, adjusted_sl)` at `ExecutionEngine.mqh:167`, after up to `m_deviation_score_points` of drift (`:110-122`) and up to two broker stop-level passes (`:147-213`). With a structural stop, `adjusted_sl` is an absolute bar-derived price, so price drifting toward the stop shrinks the execution-time risk distance **directly** — and the planning-time assertion would have passed on a distance that no longer exists. Since this assertion is the **sole compensating control** for breaking the ADR-024 premise, a decorative placement is not acceptable.

**The binding site is `ExecutionEngine`, immediately after `:167`:** compute `ratio = XSparkScorePointsToPrice(m_deviation_score_points, m_score_point_size) / risk_distance` and `return false` with an explicit reason when `ratio >= XSPARK_DRIFT_RATIO_FAULT`. The `XSparkPrepareTradePlan` check may stay as a cheap early-out, but **S6's refuse-to-ship checklist names the `ExecutionEngine` site**, not the planning-time one.

**The `sr` component is not touched.** `HasSupportResistance` stays exactly as it is and keeps feeding `report.components.sr`. Its `MathAbs` sign bug is real — and it is the one component that touches real swing data while rewarding entry *against* structure — but fixing it changes `raw`, which changes trades at session weight 0.6 and nowhere else (same arithmetic as section 3.5, same `InpMinScore` caveat). It therefore gets its own stage with its own expectation (S8b), rather than riding along inside a stage whose input is off. One reviewed proposal rewrote `sr` while its gate shipped default-off, which silently breaks the "revert by flipping one input" property; that is rejected.

**`RiskManager::IsSignalApproved` is left structurally intact, and its new branch is gated on the gate.** Every one of its five branches (`RiskManager.mqh:215-258`) is unreachable at its only call site (`XSpark.mq5:1196`): the initialisation check is unreachable because `OnInit` returns `INIT_FAILED` on failure; the `SIGNAL_NONE` check is unreachable because the detector only ever sets BUY or SELL; the score-vs-threshold check at `:231-235` re-tests the identical comparison already made at `ScoreBotV3.mqh:301` whose result gates the call; the validity check at `:237-241` duplicates `:284-290`; and `risk_pct` is always 3.0. It is nonetheless a fail-closed second opinion whose branches become reachable the moment anyone un-flattens the tiers, so removing it would be deleting a control to tidy up.

It gains **one** reachable branch, and the first draft's version of it was exactly inverted. *"Refuse when the recorded HTF verdict is UNKNOWN or contradicts the direction"* vetoes **100 % of trades while `InpUseHTFStructureGate` is default-OFF**: with the gate off the strategy computes no verdict, the field holds the enum zero value `XSPARK_STRUCT_UNKNOWN`, `IsSignalApproved` is called unconditionally at `XSpark.mq5:1196`, and a false return blocks at `:1197-1203`. The EA would stop trading entirely in this plan's own recommended default configuration, and the failure would read as a RiskManager rejection rather than a missing gate. When the gate is *on*, S3 has already vetoed UNKNOWN, so the branch is unreachable anyway.

**Corrected form.** `XSparkSignal` (`StrategyInterface.mqh:11-35`, reset at `:37-61`) gains **two** fields, `EXSparkStructureState htf_state` and `bool htf_gate_active`, both written in `ScoreBotV3::Evaluate` and both reset in `XSparkResetSignal`; `htf_state` is also copied onto `XSparkTradePlan` for the entry journal. The branch is then:

```
if(signal.htf_gate_active &&
   (signal.htf_state == XSPARK_STRUCT_UNKNOWN || contradicts(signal.htf_state, signal.direction)))
   refuse;
```

Defence in depth per AGENTS.md rule 10, and inert by construction when the gate is off. S3 pre-registers the corresponding expectation: **with `InpUseHTFStructureGate = false` the trade set is identical to the S2 control run.**

### 3.10 Parameter budget — counted honestly

Every reviewed proposal understated this by a factor of two to three, and `docs/IMPROVEMENT_PLAN.md:332` refused a nine-input gate on exactly this ground. The count below includes hard-coded constants, because a constant in a header is just as fittable as an input and is *harder* to audit. It also includes `InpGateObserveOnly` and `InpTrailArmR`, which an earlier draft of this table omitted.

**New EA inputs, by stage:**

| Stage | Inputs | Names |
| --- | --- | --- |
| S0 | 0 | (struct fields and journal columns only) |
| S2 / S2a | 0 | (constants only) |
| S3 | 3 | `InpUseHTFStructureGate`, `InpMinSwingATR`, `InpGateObserveOnly` |
| S4 | 2 | `InpUseRSIGate`, `InpRequireRSITurn` — **plus four existing inputs whose defaults swap; no new numeric value** |
| S5 | 4 | `InpUsePullbackGate`, `InpMinLegATR`, `InpPullbackMin`, `InpPullbackMax` |
| S6 | 4 | `InpUseStructuralStop`, `InpStopBufferATR`, `InpATRMultSLFloor`, `InpATRMultSLCap` |
| S7 | 3 | `InpUseStructuralTarget`, `InpTargetBufferATR`, `InpRequireStructuralTarget` |
| S8 | 3 | `InpUseBreakEvenDecoupled` + `InpBreakEvenR`, `InpBreakEvenBufferATR`, `InpTrailArmR` — counted as 3 because the decoupling flag and `InpBreakEvenR` ship as one switch |
| S8c | 0 | (derived tolerance, no input) |
| S9 | 15 | `InpUsePatternRanking`, `InpPatternConflictTol`, `InpPinOppositeWickMax`, `InpEngulfMinBody2ATR` (4), `InpUseFlagPattern` + 4 (5), `InpUseDoublePattern` + 2 (3), `InpUseHSPattern` + 2 (3) |
| **Total** | **34** | **19 outside the pattern library, 15 inside it** |

**Hard-coded constants that are also choices:** `XSPARK_STRUCTURE_FRACTAL_WING` (2, matching the existing scan), `XSPARK_SCOREBOT_STRUCTURE_BASE_BARS` (160), `XSPARK_SCOREBOT_STRUCTURE_HIGHER_BARS` (80), `XSPARK_STRUCTURE_MAX_PIVOTS` (56, derived from the window and the wing), `XSPARK_STRUCTURE_TR_PERIOD` (14), the flag detector's *N* ∈ [3,8] and *m* ∈ [3,10] windows (four numbers), the double-pattern separation bounds (two numbers), and the seven-element pattern priority ordering. **Twelve more choices, on top of the thirty-four.**

**And one category that is not a parameter but is the likeliest place a stage ships a defect.** Every new field on `XSparkScoreBotReport`, `XSparkTradePlan`, `XSparkSignal`, `XSparkPatternResult` and `XSparkTradeState` needs a line in `XSparkResetScoreBotReport` (`ScoreBotTypes.mqh:253-277`), `XSparkResetTradePlan` (`:279-304`), `XSparkResetSignal` (`StrategyInterface.mqh:37-61`), `XSparkResetPatternResult`, and `XSparkResetTradeState` (`PositionManager.mqh:281` region). A field added to a struct and missed in its reset reads as stale data from the previous bar — which on a gate field means last bar's verdict authorising this bar's trade. **Every stage's checklist carries the reset line as an explicit item.**

Three parameters were removed relative to the reviewed proposals by deriving or eliminating them rather than exposing them: the structure classification tolerance (eliminated — strict inequality plus the magnitude filter, with RANGE as the fail-closed fallback), the RSI band values (eliminated — the existing four values are swapped, not replaced), and the structural RR bounds (eliminated — `InpMinRR`/`InpMaxRR` are reused with cap-not-widen semantics). Two more were avoided in this revision: the no-overhead target uses `leg_extreme + leg_range`, both already in `XSparkStructure`, rather than a projection multiple; and the RR tolerance is derived from `tick_size / risk_distance` rather than exposed. `InpPinOppositeWickMax` is *constrained* to a window fixed by the repository's own fixtures, with the default chosen inside it.

**This is still more surface than `docs/IMPROVEMENT_PLAN.md` section 7 wanted, and the section-7 objection is not defeated by arithmetic.** It is answered only by discipline: everything default-off, one stage at a time, pre-registered, never swept, retired permanently on a negative result. If that discipline is not held, this becomes the refused thing.

---

## 4. Staged rollout

Dependency order. Every behaviour-changing stage ships **default-OFF** and carries a falsifiable expectation written **before** the run. Per `docs/IMPROVEMENT_PLAN.md` Stage 6's rule, kept verbatim: **a negative result means the input stays false permanently; it does not mean a different definition gets tried.** No continuous sweeps anywhere — at most three pre-registered candidate values per threshold — because the best-of-*k* inflation arithmetic at `IMPROVEMENT_PLAN.md:135-146` (1.16 SE at *k* = 5, 2.16 at *k* = 40, against a 6.79-point standard error) survives the operator's report entirely.

### The statistical test, specified once and applied to every gate stage

Every gate produces a **nested subset** of the baseline trade set. "Mean R went up" is not a result on a nested subset: drawing a random subset of the same size from the same population produces a spread of means, and with 50 baseline trades at `sd(R) = 1.4275` that spread is wide enough that *some* gate configuration will always appear to win.

> **The null is the distribution of mean R over random subsets of the same size drawn from the same trade population.** For a gate that removes *m* of *n* trades, resample *n − m* trades without replacement from the *n*, 10 000 times, and locate the gate's realised mean R in that distribution. It requires no extra tester runs — the journal plus a short script is enough — and it is the only test that distinguishes "this gate selected better trades" from "this gate selected fewer trades".

**Observe mode.** Stages S3 through S7 each ship behind `InpGateObserveOnly` first: the verdict is computed and journalled but does **not** veto. One run then yields the baseline *and* the exact counterfactual population, at zero behavioural risk, and the subset test above can be run on a single pass.

---

### S0 — Measurement and three zero-code experiments. **No behaviour change. Default ON.**

| Field | Value |
| --- | --- |
| **Changes** | Carry bar geometry and a second RSI value through the structs, then log them on both the entry record (`XSpark.mq5:816-841`) and the rejection record (`:562-589`). Add `RSI14BaseAt(shift)` to the cache. |
| **Files** | `XSpark.mq5`, `IndicatorCache.mqh`, **`ScoreBotTypes.mqh`, `ScoreBotV3.mqh`** |
| **Sub-steps** | The first draft listed two files and was unbuildable: `XSparkLogSignalRejection` takes only `XSparkScoreBotReport &report` (`XSpark.mq5:562-564`) and that struct (`ScoreBotTypes.mqh:118-142`) has no bar OHLC and no second RSI value; `XSparkLogEntry` takes only `XSparkTradePlan` and `XSparkExecutionResult`, and `XSparkTradePlan` (`:144-169`) carries no RSI, no bar geometry and no ATR14. So: **(1)** add `double bar1_open/high/low/close; double rsi_base_prev;` to `XSparkScoreBotReport` and zero them in `XSparkResetScoreBotReport` (`:253-277`); **(2)** populate them in `ScoreBotV3::Evaluate` immediately after the `BaseBar(1..3)` fetch at `ScoreBotV3.mqh:189-206`, i.e. **before** the `NO PATTERN` return at `:209-215`, so rejected bars carry geometry too; **(3)** copy them onto `XSparkTradePlan` (fields plus zeroing in `XSparkResetTradePlan`, `:279-304`) in `XSparkPrepareTradePlan` alongside the existing component copies at `XSpark.mq5:732-741`. Note that `report.rsi_base` and `report.rsi_higher` already exist (`:135-136`, populated at `ScoreBotV3.mqh:202-203`) — what is missing is the geometry, the previous RSI and the two risk distances. |
| **Journal columns added** | raw `rsi_base`, raw `rsi_higher`, `RSI14BaseAt(2)`, bar1 O/H/L/C, `range1 / ATR14`, the planned risk distance (`plan.risk_distance`) and the fill-based one (`MathAbs(realised_entry − plan.final_sl)`, already computed at `XSpark.mq5:846-849`) and their ratio. |
| **Why first** | `report.rsi_base` is populated and reaches the dashboard, but neither log line records it — only the 0-or-1 component at `:581`. **The journal can say `rsi=1.00` and cannot say whether it was 31 or 59.** The operator's clearest empirical claim is currently unmeasurable, and no band may move before it is. |
| **Expectation** | Trade set identical to a same-session control run of the unmodified build. |
| **Revert if** | Any trade differs. That would mean a logging change leaked into a decision. |

**Three experiments that need no code at all and should run before S1:**

1. **Grep `MFE_R` on losing trades** from the operator's existing runs. It is already logged on every close (`PositionManager.mqh:927-934, 948`). If loser `MFE_R` clusters between roughly 0.8 R and 1.5 R while targets sat at 2.25-4.5 × ATR14, the target diagnosis is confirmed empirically and the `IMPROVEMENT_PLAN.md:345-349` deferral is spent. **If it does not, the premise behind S6 and S7 is refuted and they should not be built.**
2. **Grep the existing journals for `Final broker-valid RR`.** That string is emitted at `XSpark.mq5:804-809` and its execution-side twin at `ExecutionEngine.mqh:223-227`. Section 2.4 predicts a non-empty population concentrated on bars where `ATR14/ATR50 <= 0.7`, i.e. where `dynamic_rr` sits exactly on `InpMinRR = 1.5`. **This costs one grep and it is the direct empirical test of the half-integer artefact**: if the string never appears, section 2.4's mechanism is refuted and S8c should not be built; if it appears and the matching bars are the low-volatility ones, S8c is confirmed against live data before any code is written.
3. **The right-tail probe**: `InpMinRR = InpMaxRR = 8.0`. `dynamic_rr` collapses to 8.0 on every bar (`ScoringEngine.mqh:44-49` returns `min_rr` when `t = 0` and `min_rr + t·0` otherwise), and `InpMaxRR == InpMinRR` is accepted by validation — `XSpark.mq5:301` rejects only `InpMaxRR < InpMinRR`. **Precondition, and it is not optional: the probe RR must be an integer.** The bound checks tolerate only `XSPARK_RR_EPSILON = 1e-7`, and a normalised target is displaced by up to `tick / risk_distance` (≈ 0.008 on gold) whenever `RR × (risk_distance / tick)` is not an integer. 8.0 is an integer, so `8m` ticks is exact and `actual_rr` is 8.0 to within about 4e-13; **a probe at 7.5 would be refused on every odd-tick stop and would return an empty journal that reads as a market condition rather than a configuration error.** Three consumers read the same two inputs and all three are satisfied by an integer: `XSpark.mq5:804` reads `InpMinRR`/`InpMaxRR` directly; `XSpark.mq5:1426-1427` feeds `m_min_rr`/`m_max_rr` inside `ScoreBotV3` and therefore `dynamic_rr`; `XSpark.mq5:1483-1484` feeds `ExecutionEngine.mqh:222`. **One refinement to the old plan's description:** the probe is not exit-neutral — with the TP at 8 R the 2.5 R partial becomes reachable on every trade that gets there, so read **MFE** from this pass (a price excursion, unaffected by volume) and do **not** compare its P&L to the baseline's.

These are the cheapest actions in this entire document.

### S1 — The baseline measurement run. **No code.**

This is `docs/IMPROVEMENT_PLAN.md` **Stage 4**, unchanged, and it is a hard prerequisite for any profitability claim made anywhere in this plan. Longest available real-tick history, flat risk, drawdown limits set wide enough not to censor the sample (39.0 / 40.0, per that plan's own audit correction), then cut the per-trade record. Gate: `n >= 500`, mean R above zero, lower confidence bound above zero.

**Nothing below S1 may be described as improving profitability until S1 has run.** Everything below S1 may still be described as repairing a defect, because the defects are provable from source.

### S2 — Structure module and data window. **Pure infrastructure. No behaviour change. Default ON (nothing consumes it).**

| Field | Value |
| --- | --- |
| **Changes** | New `MarketStructure.mqh` (pure functions, no handles, no globals). New `m_structure_base_rates[160]`, `m_structure_higher_rates[80]`, `m_structure_valid`, `StructureBaseBar`, `StructureHigherBar`, `StructureIsValid`, `RSI14BaseAt`. New report fields + journal line + dashboard row. `TestMarketStructure.mq5`. **The HTF handle-readiness raise is NOT in this stage — see S2a.** |
| **Files** | `MarketStructure.mqh` (new), `IndicatorCache.mqh`, `ScoreBotTypes.mqh`, `ScoreBotV3.mqh`, `Dashboard.mqh`, `TestMarketStructure.mq5` (new) |
| **Journal line** | `state`, `pivot_count`, `legs_in_state`, the four classifying prices (`last_high`, `prev_high`, `last_low`, `prev_low`), `scale`, and **`leg_origin`, `leg_extreme`, `leg_range`, `retracement`, `leg_origin_shift`**. The leg fields are not optional: S5 says its window is chosen from telemetry rather than guessed, and without them there is no telemetry to choose from. `legs_in_state` is what separates "entered on the 2nd leg of an HTF uptrend" from "entered on the 5th" when S3's matched-subset test runs. |
| **Inertness** | `XSPARK_SCOREBOT_CLOSED_BASE_BARS` is **not** changed, so `m_valid`, the `Bars(base) >= 110` guard at `IndicatorCache.mqh:145` and the five `N + 1` handle requirements at `:153-157` are byte-for-byte unchanged and the first tradeable bar does not move. The structure copies set only `m_structure_valid`, which nothing yet reads. |
| **Expectation** | Trade set identical to a control run. Additionally: after warm-up, `state == UNKNOWN` on under 10 % of evaluated bars; `valid == false` with reason `"pivot overflow"` on zero bars; no pivot in the array ever changes after it is first reported. |
| **Revert if** | Trades differ (a leak); or UNKNOWN exceeds 10 % (the window or `InpMinSwingATR` is wrong and must be fixed before anything depends on it); or a reported pivot later changes (a repaint bug — the scan bound is wrong); or overflow occurs at all (the `XSPARK_STRUCTURE_MAX_PIVOTS` derivation is wrong). |

### S2a — HTF handle-readiness contract hygiene. **Shipped alone, default ON.**

| Field | Value |
| --- | --- |
| **Changes** | `IndicatorCache.mqh:158-159`: raise `HandleIsReady(m_ema50_higher_handle, 2)` to 51 and `HandleIsReady(m_rsi14_higher_handle, 2)` to 15. Add an explicit rejection of a non-positive `ema50_higher`. |
| **Why its own stage** | This is the only part of the structure work that **can legitimately change behaviour**, because it changes `RefreshClosedData`'s pass/fail during history synchronisation and therefore the first tradeable bar. Bundling it into S2 makes S2's "trade set identical" expectation ambiguous between a readiness change and a structure-window leak, and an ambiguous revert signal on an infrastructure stage is how a real leak gets attributed to the safe change. Section 2.7 claim 2 is the reasoning for the change itself. |
| **Expectation** | Trades differ, if at all, **only at the start of a run**, by the leading trades that were taken on an under-calculated HTF buffer. No mid-run trade changes. |
| **Revert if** | Any mid-run trade differs. |

### S3 — HTF structure direction gate. **Default OFF.** Observe mode first.

| Field | Value |
| --- | --- |
| **Changes** | `InpUseHTFStructureGate`, `InpMinSwingATR`, `InpGateObserveOnly`. Three new block statuses. `htf_state` and `htf_gate_active` on `XSparkSignal` (`StrategyInterface.mqh:11-35`) with matching lines in `XSparkResetSignal` (`:37-61`), copied onto `XSparkTradePlan` for the entry journal. The gated `RiskManager::IsSignalApproved` branch (section 3.9). **The `InpUseHTFStructureGate && !InpUsePullbackGate` `OnInit` refusal (section 3.8) lands in this stage.** |
| **Expectations** | With `InpUseHTFStructureGate = false`: **trade set identical to the S2 control run** — this is the check that the RiskManager branch is correctly gated and not vetoing everything. With the gate enforcing: trades whose direction contradicts the HTF structure verdict → **exactly 0** (true by construction; a correctness check on the implementation, not a result). Trade count down materially. **Mean R above the matched-subset null at the 90th percentile or better**, at the largest `n` available. |
| **Revert if** | The gate-off trade set is not identical (the defence-in-depth branch is mis-gated); or the trade count falls by less than 20 % when enforcing (the gate is not binding — a bug); or mean R does not clear the matched-subset null. |
| **Hard constraint** | **Enforced at `OnInit`, not in prose.** `InpUseHTFStructureGate` cannot be enabled without `InpUsePullbackGate`. S3 and S5 are evaluated together as well as separately; judging S3 alone and concluding "the trend filter made it worse" would be a correct measurement of an incomplete change. |

### S4 — RSI gate and band swap. **Gate default OFF; band swap default ON.**

| Field | Value |
| --- | --- |
| **Changes** | `InpUseRSIGate`, `InpRequireRSITurn`. `InpRSILongMin/Max` 40/70 → 30/60 and `InpRSIShortMin/Max` 30/60 → 40/70. Observe-mode telemetry separates the inner-bound and outer-bound refusal counts (section 3.5). |
| **Expectations** | With the gate on: accepted BUYs with `rsi_base > 60` and accepted SELLs with `rsi_base < 40` → **exactly 0**. From the band swap alone (gate off), **given `InpMinScore = 2.0` and `InpLongScoreExtra = 0.0`**: **no trade changes in server hours 7-20; trades change only at session weight 0.6**, by the population where the `rsi` component flipped and `raw` crossed 3.333. |
| **Revert if** | Any trade changes outside session weight 0.6 from the swap alone — **at shipped `InpMinScore`/`InpLongScoreExtra`**. That would falsify the arithmetic in section 3.5 and means something else moved. |
| **Pre-registration precondition** | The control run and the comparison run **must both use the shipped `InpMinScore` and `InpLongScoreExtra` defaults.** If `InpMinScore` has been raised — and section 7 question 5 actively invites the operator to raise it to 4.0 — the expectation above is false and the Revert-if would fire on a *correct* result, permanently retiring a provable fix under this plan's own "a negative result means the input stays false permanently" rule. At `InpMinScore = 4.0` the required raw is `4.0 / session_weight` = 4.000 at weight 1.0 and 3.333 at weight 1.2, against a `pattern + atr` ceiling of 3.0, so the `rsi` point becomes decisive across all sessions. **Recompute the expectation from `required_raw = InpMinScore / session_weight` against the 3.0 ceiling before the run, or do not run it.** |
| **Note** | The band swap is default-ON because the current orientation is a **provable defect**, not a hypothesis, and because it introduces no new numeric value. Of the two default-ON behaviour changes that *remove* trades, it is deliberately the one with the smallest and most precisely predicted blast radius. |

### S5 — Location / pullback gate. **Default OFF.** Observe mode first.

| Field | Value |
| --- | --- |
| **Changes** | `InpUsePullbackGate`, `InpMinLegATR`, `InpPullbackMin`, `InpPullbackMax`. Three new block statuses. |
| **Expectations** | Median retracement at entry rises from whatever S2's leg telemetry recorded to above 0.40. **Mean `MAE_R` falls** — that is the arithmetic this change is built on (entries sit closer to their invalidation) and it is the metric that decides. Trade count down materially. |
| **Revert if** | Mean `MAE_R` does not fall. |
| **Note** | `InpPullbackMin` and `InpPullbackMax` are **chosen from S2/S3 observe-mode telemetry**, not shipped as guesses, which is why S2's journal line carries `leg_origin`, `leg_extreme`, `leg_range` and `retracement`. The 0.30/0.80 defaults in this document are a starting window, and the `r`-versus-realised-MFE distribution recorded in S2 is what sets them. At most three pre-registered candidate pairs. |

### S6 — Structural stop, **with the ADR-024 repair in the same commit. Default OFF.**

| Field | Value |
| --- | --- |
| **Changes** | `InpUseStructuralStop`, `InpStopBufferATR`, `InpATRMultSLFloor`, `InpATRMultSLCap`, plus their validation (section 3.6 Step 2). New `result.structural_min_stop_points` in `AutoTune.mqh` used at `:200` and at **both** `XSparkEntryDriftBound` call sites (`XSpark.mq5:437`, `:1050`), with `:199`, `:201` and `:202` untouched. Per-trade drift assertion **inside `ExecutionEngine` after `:167`**. Cap re-check after the stop-level loop stabilises (`ExecutionEngine.mqh:209-213`). |
| **Expectations** | Mean `risk_distance` falls. Lot size rises proportionally for the same risk percentage — **this is stated because it is a consequence nobody may discover later**: a 25 % tighter stop is a 33 % larger position, which raises margin consumption, raises absolute slippage cost per adverse point, and interacts with the ADR-023 account cap. The stop-hit-on-a-wick-retest population shrinks. **`exit_deviation_points` and `spread_cap_points` are byte-identical between the S6-off and S6-on runs** — the AutoTune startup line at `AutoTune.mqh:227-230` prints both, so this is a one-line check. |
| **Revert if** | Mean `risk_distance` does not fall (the leg definition is wrong); or the entry drift ratio at init differs from the values in section 3.9; or **either of the exit tolerance and the spread cap moved.** |
| **Refuse to ship if** | The floor, the separate `structural_min_stop_points` field, both re-based drift-bound call sites, the untouched `AutoTune.mqh:199/:201/:202`, the `TestAutoTune.mq5` assertion, **the `ExecutionEngine`-sited per-trade assertion**, the post-adjustment cap re-check and the two new multiplier validations are not all in the same commit. Splitting them leaves a fail-closed control inert or a flatten campaign under-tolerant. This is a checklist item, not a follow-up. |

### S7 — Structural target, **with the exit repair. Default OFF.**

| Field | Value |
| --- | --- |
| **Changes** | `InpUseStructuralTarget`, `InpTargetBufferATR`, `InpRequireStructuralTarget`. `plan.desired_target` consumed at `XSpark.mq5:713-717`, `:762-767` and `ExecutionEngine.mqh:184-187`, with the profitable-side re-test against `current_entry_reference`. Three-branch target rule including the measured-move branch. Cap-not-widen RR semantics. **Break-even decoupled from `partial_done`; trail decoupled from `partial_done` via `InpTrailArmR` and `trail_armed` at `PositionManager.mqh:1556`.** `InpPartialTPRatio` clamped (not `INIT_FAILED`) into `[InpMinRR, InpMaxRR]`. R denominator unified on the fill-based value. The `InpUseStructuralTarget && !InpUseBreakEvenDecoupled` `OnInit` refusal. |
| **Expectations** | Realised RR stops being degenerate (today it equals `dynamic_rr` by construction). The gap between loser `MFE_R` and target R closes. **The fraction of closed trades whose journal shows at least one trail modification rises above the baseline** — this is what the trail decoupling is for and it is separately checkable. Partial, break-even and trail fire on the large majority of trades instead of only when `ATR14/ATR50 >= 1.1`. **Win rate rises and mean winner R falls — both are mechanically certain once targets move nearer, so neither is evidence on its own. Net mean R is the only metric that decides.** |
| **Target-branch pre-registration** | S2/S3 observe mode records `structural_target_found` and the candidate distance on every bar, so the no-overhead fraction is **measured before S7 is built**. S7 then records which of the three branches each accepted trade resolved to. **Revert-if: if fewer than 50 % of accepted trades resolve to a non-`dynamic_rr` target, S7 changed the target on a minority of trades and its mean-R result is not attributable to the target change.** |
| **Revert if** | Loser `MFE_R` does not move, in which case the targets were not the binding constraint and `IMPROVEMENT_PLAN.md:345-349` was right to defer. Or the trail-modification fraction does not rise, in which case the decoupling did not land. |
| **Sequencing** | S6 and S7 are evaluated **together** as well as separately: because `TP = RR × risk_distance` today, whatever sets the stop also sets the target, and measuring them apart measures nothing. The exit repair must land **with or before** the structural target, or nearer targets kill the management stack outright (section 3.6, Step 5), which is why the `OnInit` refusal exists. |

### S8 — Three isolated correctness fixes, each with its own pre-registration, each shipped alone.

- **S8a — inside-bar breakout triggers against the mother bar.** Default ON. Fixture at `TestScoreBotV3Logic.mq5:71-79` updated in the same commit; that diff is the evidence. Expectation: the IBR trade population shrinks by exactly the set whose breakout close never left bar3's range, identifiable in the journal from S0's bar geometry.
- **S8b — the `sr` `MathAbs` sign fix** (`ScoreBotV3.mqh:81, 91`). Default ON, **shipped alone.** Expectation, **at shipped `InpMinScore`/`InpLongScoreExtra`**: no trade changes in server hours 7-20; trades change only at session weight 0.6, by the population where `sr` was awarded for a close on the wrong side of the level and `raw` crossed 3.333. The same `InpMinScore` precondition as S4 applies and must be checked before the run.
- **S8c — the RR bound tolerance is derived from the tick.** Default ON, **shipped alone**, `XSparkRRIsWithinBounds` gains an explicit tolerance and both call sites pass `MathMax(XSPARK_RR_EPSILON, tick_size / risk_distance)` (section 3.6 Step 4). Expectation: the trades that change are **exactly** those the S0 experiment-2 grep already identified — the ones refused with `Final broker-valid RR ... is outside configured`, concentrated on bars where `ATR14/ATR50 <= 0.7` and the broker-valid stop distance is an odd number of ticks. **This is the only change in this plan that is default-ON and *adds* trades rather than removing them**, and that is stated rather than buried: the current behaviour makes two arithmetically identical setups trade or not trade depending on where a price rounds, which is an artefact and not a filter. Revert if the changed population is not the one the grep predicted — that would mean the half-integer mechanism is not what is happening and section 2.4 is wrong.

### S9 — Patterns. Each detector default OFF, shipped one at a time.

| Field | Value |
| --- | --- |
| **Order** | ranking + conflict block + instance latch + pin/engulfing fixes + the `OnInit` gates-required refusal → flag → double top/bottom → head & shoulders |
| **Expectations** | The ranking change alone: the only trades that change are bars where two detectors fired, identifiable from the recorded runner-up. The pin fix: trades removed are exactly those whose `upper/lower > 0.65`. Each new detector: trade count up by the detected population, with realised R recorded separately by `pattern_id`. |
| **Revert if** | A detector's trades show materially worse mean R than the flag baseline — it stays off permanently. |
| **Refuse to ship if** | The instance latch is not persisted through `StateStore`, or a failed persist does not **refuse the entry**, or the stored value is a boolean rather than the `instance_time` itself, or the `OnInit` refusal of a detector without its gates is missing. All four land with the first multi-bar detector (section 3.7). |
| **Honest limits** | At a plausible 1-2 structurally-filtered double bottoms or H&S per month on M15, per-pattern `n` over two years is roughly 30, giving `SE(mean R) ≈ 0.26` against a baseline effect of +0.07. **No per-pattern profitability verdict is reachable at that sample size, and none will be claimed.** Separately: every per-detector result is conditional on the `InpMinSwingATR` value fixed in S3, and changing it invalidates all of them (section 3.7). |

### Out of scope, with entry conditions — see section 6

Pending/limit entries, session-weight restructuring, `mtf` deletion, tier re-enablement, scheduled-news blackout.

---

## 5. Reconciliation with `docs/IMPROVEMENT_PLAN.md`

### Where the old plan was right and stays right

**Its two strongest refusals survive the operator's report intact.**

- **`:340`, "Adding any new positive score component."** Confirmed exactly by section 3.8: max final is 9.0 = the validation ceiling, with 1e-7 of slack. This plan **satisfies** that refusal rather than arguing around it — every structural input is a veto costing 0.0 of ceiling. **The obvious reading of "add market structure" is "add a structure score", and that is the one shape that must not be used.**
- **`:135-146`, the best-of-*k* selection-inflation arithmetic.** No qualitative field report can overturn it. A ten-variant sweep of new pattern and structure thresholds would manufacture an apparent ten-point win-rate gain out of noise and would look exactly like success. Section 4 inherits the no-sweep rule and adds the matched-subset null, which the old plan did not specify and which is required because gates produce nested populations.
- **Measurement precedes change.** Stage S0 and S1 here are that principle, unmodified. The old plan's insistence that the 50-trade baseline sits 0.35 standard errors from zero edge — so the sample cannot rank one threshold against another — is correct and constrains everything below.
- **`:333`, re-basing the risk tier on a weighted quality index.** Still refused, and this plan strengthens the case: under flat tiers it changes no trade, only dollars, and the tier constants are a risk control under AGENTS.md rule 5.
- **`:338`, `InpMaxOpenTrades = 2`.** Still refused, unchanged.
- **`:339`, optimising on the 2026.09 fortnight.** Still the most damaging single action available. Any out-of-sample window must **end before 2026.09.01**.

### What the operator's evidence legitimately changes

It changes the **status of three items**, not the evidence bar.

| Old-plan position | What changes | Why |
| --- | --- | --- |
| **`:332`** — rebuilding the entry decision around a nine-input evidence gate was refused as "a strategy rewrite wearing a structural-defect label, shipped on by default with nine untested thresholds." | **Partially superseded.** The objection had two halves: the *shipping posture* and the *threshold count*. This plan honours the posture completely — everything default-off, one stage at a time, pre-registered, retired on a negative, and with the two ordering rules that make the posture meaningful now enforced at `OnInit` rather than written down. It does **not** defeat the count objection: section 3.10 admits 34 new inputs plus 12 constants, which is more than nine, not fewer. What the operator's report adds is that the entry-gate arithmetic of section 2.1 is a **provable structural defect**, not a hypothesis, so the work no longer needs Stage 4 to be *justified* — only to justify any profitability claim about it. That distinction is the whole of the change. |
| **`:334`** — a twenty-field context struct and regime gates on it, refused as speculative generality, with the specific note that the anti-chase scan started at the signal bar so any new extreme landed at position 1.0 by construction. | **The specific criticism is adopted, not evaded.** Section 3.4's leg is anchored on a *confirmed swing pivot*, not on a fixed-lookback window including the signal bar, which is precisely the defect that note identified. The generality objection also stands and is answered by scope: one HTF trend enum from one already-supported timeframe partner, not a twenty-field struct. |
| **`:345-349`** — structural stop placement, "the most interesting idea the plan does not act on", deferred **with a trigger** pending offline testability. | **The trigger has fired**, and cheaply. The deferral's own test condition is answerable **today** with a grep: `MFE_R` is already logged on every close. Section 4's S0 experiment 1 spends the deferral or refutes it, with no code and no tick run. Additionally, a bar-derived structural stop is *more* reproducible offline than the current one, which is built from the live `market_state.Ask()/Bid()` — so it strengthens the evidence programme rather than complicating it. |
| **`:350-352`** — a scheduled-news blackout, deferred because "the MQL5 calendar's Strategy Tester behaviour cannot be verified from here", and called by three independent trader reviews "the highest-value filter that is defined in advance rather than fitted." | **Still deferred, and the operator's report makes it more relevant, not less.** News spikes are a plausible generator of exactly the "placed at the reversal point" population in finding (a), and unlike every threshold in this document the blackout window is defined by a calendar rather than fitted to a sample. The deferral's stated reason is nonetheless unchanged: `MqlCalendarValue` behaviour under the Strategy Tester still cannot be verified in this environment, and a filter that silently returns nothing in the tester while blocking in live is a backtest-versus-live divergence of exactly the kind section 3.2 spends effort to avoid. **Entry condition, stated so it is not lost:** one live-chart observation of whether `CalendarValueHistory` returns non-empty results under "Every tick based on real ticks" on the operator's terminal decides it. That is a five-minute check on a live chart, it is not something this repository can answer, and it belongs in section 7's open questions rather than in a stage. |
| **`:353-360`** — entry price itself, "arithmetically the largest single lever on R available, larger than any score filter", deferred pending a pending-order path. | **Still deferred, and the assessment is endorsed.** Section 3.4 captures part of that lever with **zero** execution-boundary change, by refusing to trade at a premium rather than by placing an order at a discount. The pending-order path stays out of scope for the reasons in section 6, which are safety reasons the old plan did not enumerate. |

### One correction to the old plan's own text

`IMPROVEMENT_PLAN.md:68-69` says the trail is 1.333 R wide and "is looser than the initial stop." True. The additional point is **narrower than an earlier draft of this document claimed**, and the correction is worth making precisely because the earlier draft got it wrong in the direction that flattered it. Once armed, the trail *does* ratchet: `PositionManager.mqh:1556-1596` recomputes `bid − InpATRMultTrail × ATR14` on every tick and applies any candidate that passes the `tighter` test at `:1580-1584`, so the protected level rises from roughly entry + 1.167 R at the 2.5 R arm point to about entry + 1.667 R by a 3.0 R take-profit — half an R of real progressive protection and a real floor under a post-partial reversal. Calling it "inert by construction" misstates what S7's exit repair is replacing. What makes it dead at shipped defaults is not the ratchet but the **arm condition**: `partial_done`, which needs `dynamic_rr >= 2.5`, i.e. `ATR14/ATR50 >= 1.1`. Below that the broker take-profit closes the position first and the trail never arms at all. That is why section 3.6 Step 5 decouples the arm and leaves the ratchet alone.

### What has *not* changed in the evidence position

Nothing in the repository. The baseline is still the 50-trade run at 0.35 standard errors from zero edge. No `n >= 500` run is recorded anywhere in `docs/`. `docs/ROADMAP.md` still lists backtesting and validation as future work. **The operator's four observations are mechanism claims with no trade count, win rate or mean R attached: strong evidence about mechanism, no evidence about effect size.**

---

## 6. Risks, tradeoffs, and what this plan deliberately does not do

### 6.1 Deliberately not doing

| Item | Why |
| --- | --- |
| **Pending / limit entries** | This is the largest R lever available, and it is **out of scope on safety grounds**, not cost grounds. Three shipped risk controls are blind to pending orders. `InpMaxOpenTrades` is tested against `g_position_manager.ManagedPositionCount()` (`XSpark.mq5:1174`), which counts **positions**. The account cap is built by `XSparkOpenAccountRiskCash`, which iterates `PositionsTotal()` (`:609`). Two consecutive signals could each place a limit order while zero positions exist; both fill; `InpMaxOpenTrades = 1` and `InpMaxAccountRiskPct = 6.0` are both breached with **no log line and no veto**. Worse, only the total-drawdown killswitch flattens — the daily-DD halt, spread filter, quote-age gate and drift fault all block *new entries at the entry path*, which is airtight today only because entry **is** `OrderSend`. A limit placed at bar close can fill after any of those latch. That is a fail-**open** path in a system whose ADRs are built on failing closed. **Entry conditions for a future stage:** (i) the exposure count feeding `CanOpenNewTrades` becomes positions **plus** `CountMatchingPendingOrders()` — which already exists at `PositionManager.mqh:388-409`; (ii) the account risk cap counts pending exposure; (iii) every XSpark pending order is cancelled whenever any safety veto latches; (iv) `ORDER_TIME_SPECIFIED` expiry is treated as the **primary** control, because `OnDeinit` is not guaranteed on a crash or power loss; (v) `ReconcileOnInit` adopts or cancels orphaned XSpark pendings by magic number. |
| **Moving the session weight out of the score** | It is a real defect. At a typical raw of 3.0, moving hour 11 → 12 adds +0.60 and hour 20 → 21 subtracts −1.20 — both exceed `mtf` entirely and the latter exceeds any single confirmation component. **The clock moves the score more than any fact about the market does.** It is also inverted on H2/H4 bases: the 04:00 H4 bar *contains* the 07:00 London open and scores 0.6, while the 20:00 H4 bar is almost entirely post-London and scores 1.0. It is nonetheless **orthogonal to all four reported symptoms**, and moving it touches the threshold, the tier mapping and the dashboard at once. Recorded here; scheduled nowhere. |
| **Deleting or inverting `mtf`** | Its sign is wrong and the fix is one character. Under flat tiers it moves nothing at weight ≥ 1.0, the RSI gate already vetoes every trade it would reward, and deleting it drops max raw to 7.0, opening a tier-reachability question for no benefit. Section 3.5. |
| **Re-basing `XSPARK_SCOREBOT_MAX_SCORE` or the tier constants** | Rebasing upward without moving 4.5/5.5 makes tier 3 easier to reach and **silently raises risk per trade** — the direction AGENTS.md rules 5 and 27 forbid doing quietly. Normalising to 0-1 makes both thresholds permanently unreachable, killing the tiering mechanism with no log line, and leaves `InpMinScore = 2.0` passing validation while being unreachable forever — ADR-026's exact failure. |
| **A third bias timeframe** | Section 3.3, on lag and observability grounds rather than on the partner table alone. |
| **A separate `min_swing` for the pattern detectors** | Section 3.7. It would break the S3/S9 coupling at the cost of a second definition of "swing" in a system whose correctness argument rests on having one. The coupling is disclosed instead. |
| **Triangles, wedges, three-drive** | Section 3.7. |
| **Raising `XSPARK_SCOREBOT_CLOSED_BASE_BARS`** | Section 3.2. It touches **thirteen** sites, not two, and moves the first tradeable bar of every backtest. |
| **A scheduled-news blackout** | Section 5. Deferred on an unchanged technical ground with a five-minute entry condition, not refused. |
| **Everything on `IMPROVEMENT_PLAN.md`'s existing section 7 list** | Unchanged unless explicitly reconciled in section 5, which now covers all four of its deferred-with-a-trigger items rather than three. |

### 6.2 Risks

1. **HTF structure is still lagging, and S3 alone makes symptom (a) worse.** Two HTF confirmation bars plus four pivots to classify. The base-close invalidation removes the exit-side lag entirely, which is the half that matters most, but the entry side keeps its floor. **S5 is the mitigation, and the S3-without-S5 ordering is now refused at `OnInit` rather than prohibited in prose** — which is the difference between a rule and a hope, because a prose rule survives exactly until the first merge that drops it.
2. **The acceptance gate may be unreachable, and this plan does not solve it.** S3 plus S5 plausibly remove 60-85 % of trades. Against `IMPROVEMENT_PLAN.md:245`'s `n >= 500` requirement that needs roughly 1 500-3 000 baseline trades, which at the stated ~5 trades/day is 300-600 trading days, and the available real-tick history depth for XAUUSDm is an open question (section 7). Observe mode extracts the counterfactual from a single run and the matched-subset null is the right test, but neither manufactures sample. **The honest position is that several gate stages may never be falsifiable on profitability and therefore ship on structural-correctness grounds with profitability explicitly unclaimed** — which is what AGENTS.md rule 34 already says about infrastructure.
3. **The gates are correlated, so the trade set collapses faster than the individual rejection rates suggest.** HTF-up, a pullback in the lower half of the leg, and RSI below 60 are three ways of describing similar market states. **Record the joint verdict in observe mode, not three separate counts.**
4. **The location gate may select the weakest instances of the HTF trend.** Strong trends produce shallow 23-38 % pullbacks; retracements past 50 % are more typical of failing structure. `InpPullbackMax` is meant to bound that, but the boundary between "deep pullback" and "failing leg" is exactly what nobody can set from this evidence base. This is why the window is chosen from S2/S3 telemetry rather than shipped as a guess, and why S5's decision metric is `MAE_R` rather than mean R. The measured-move target branch (section 3.6 Step 3) is what keeps the *shallow* end of the window viable, so if that branch is dropped this risk returns in full.
5. **Statelessness costs monotonicity.** Section 3.2. A pivot scrolling out of the window can change the verdict with no new price action. Accepted in exchange for eliminating an entire class of backtest-versus-live divergence.
6. **The structural stop is the most dangerous change here.** It silently invalidates a fail-closed control unless the floor, the separate `structural_min_stop_points` field, both re-based drift-bound call sites, the untouched exit and spread derivations, the `ExecutionEngine`-sited per-trade assertion and the post-adjustment cap re-check all land together. Anyone who later tightens the floor "to get better R", or who "simplifies" `structural_min_stop_points` back into `min_stop_points`, re-breaks it — and the second of those breaks the killswitch flatten's slippage tolerance, not the entry gate.
7. **`InpMinRR` flips from decoration to primary filter, and its tolerance was wrong before this plan touched it.** Sections 2.4 and 3.6 Step 4. S8c is a behaviour change on the default configuration and the only one in this plan that adds trades.
8. **Head & shoulders is the most fittable construct in the plan**, and it is the item most likely to be re-tuned instead of retired.
9. **Thirty-four inputs plus twelve constants** against an evidence base of 50 trades. Section 3.10. The mitigation is discipline, which is a promise, not a property of the design — except for the three ordering rules, which section 3.8 turns into properties.
10. **Tighter stops mean larger positions.** S6. Stated so it is not discovered.
11. **`InpMinSwingATR` is a single number that sets both the trend classification and what the pivot-based detectors can see.** Section 3.7. Every S9 per-detector result is conditional on the value fixed in S3, and no S9 result survives a later change to it.

---

## 7. Open questions for the account owner

The first four are carried forward from `docs/IMPROVEMENT_PLAN.md` section 8 because they are still unanswered and still size the whole programme.

1. **Commission structure.** Spread-only on an Exness Standard account, or a real per-lot per-side charge on a Raw or Zero account? The latter roughly doubles per-trade cost drag and would change the sign of several conclusions. One minute in the symbol specification.
2. **Trade server GMT offset.** If the server runs at UTC+3, the coded "overlap" hours 12-15 are 09:00-12:00 UTC — London morning with New York shut. Since the session weight is the largest single input to the entry decision (section 6.1), it may also be pointed at the wrong hours. Must be read on a live chart, not in the tester.
3. **Real-tick history depth for XAUUSDm.** This decides whether risk 6.2.2 is a scheduling problem or a wall.
4. **How much drawdown do you actually accept?** Unchanged from the old plan, and S6 makes it sharper: tighter stops mean larger positions for the same risk percentage.
5. **Do you want the cheap partial mitigation now — and do you understand what it costs the measurement programme?** Raising `InpMinScore` from 2.0 to **4.0** is a single already-validated input and requires no code. It makes "one candle shape fires a 3 %-of-balance trade" arithmetically impossible (the unaided ceiling is 3.60). It does **not** address any of the four symptoms — it removes weak *candles*, and you are describing wrong *locations* — and at session weight 0.6 it effectively ends Asian-session trading. **It also invalidates the S4 and S8b pre-registrations exactly as written**, because both predict "no trade changes in server hours 7-20" and that prediction depends on `InpMinScore = 2.0`; at 4.0 the required raw is 4.000 at weight 1.0 against a `pattern + atr` ceiling of 3.0, so the single `rsi` or `sr` point becomes decisive in every session. If you take this mitigation, S4's and S8b's expectations must be recomputed from `required_raw = InpMinScore / session_weight` **before** their runs, or a correct result will trip a Revert-if and permanently retire a provable fix. Available today; your call.
6. **When the HTF structure is RANGE or UNKNOWN, do you want zero trades, or today's behaviour?** This plan chooses zero, fail-closed. That is a real reduction in activity for a state that will occur often. An `InpAllowCounterTrend` escape hatch is deliberately **not** offered, because "mostly with the trend" with an exception input is how the exception becomes the rule.
7. **Which do you want first if you can only have one?** The evidence says S6+S7 (stops and targets) is the larger lever on R and S3+S5 (structure and location) is the more direct answer to what you described. They are independent. S0's `MFE_R` grep will tell us which, this week, for free.
8. **Does `CalendarValueHistory` return non-empty results in your Strategy Tester under "Every tick based on real ticks"?** This is a five-minute check on a live chart and it is the entire entry condition for the scheduled-news blackout (`IMPROVEMENT_PLAN.md:350-352`), which three independent reviews called the highest-value filter that is defined in advance rather than fitted, and which is directly relevant to finding (a). Nothing in this repository can answer it.
9. **Are you willing to let a pre-registered hypothesis stay dead?** Carried forward verbatim from the old plan, because it is the one rule preventing this programme from degenerating into the curve-fitting it exists to avoid — and this plan has more knobs than the one it supplements.

---

## 8. Honest caveats

- **No compilation was performed and none is possible in the environment that produced this document.** Every code change described is unverified source. AGENTS.md rules 30 and 32 require that to be stated rather than assumed.
- **No backtest was run by the author.** Every forward-looking number in section 4 — trade-count deltas, `MAE_R` direction, `MFE_R` clustering, the predicted `Final broker-valid RR` population — is a **pre-registered expectation**, not a measurement. AGENTS.md rule 33.
- **Nothing here is a profitability claim.** Every structural defect named in section 2 is wrong independently of any backtest; every claim that fixing it earns money requires the S1 measurement run, which has not happened. The 50-trade baseline sits 0.35 standard errors from zero edge and cannot rank one threshold against another.
- **Reduced trade frequency is an expected and intended consequence, not a side effect.** The gates only subtract; S8c is the single exception and it adds back only an artefact population. A plausible 60-85 % reduction is the price of selectivity, it slows every subsequent measurement, and it will make the EA look broken on a live chart for stretches. **Anyone who is not prepared for that should not enable the gates.** The dashboard rows and block statuses specified in S2 exist for exactly this reason: an EA that refuses four out of five previously-taken setups with no visible reason gets switched off by its operator.
- **Every threshold default in this document is a starting point with a stated validation route, not a tuned answer.** Three are genuinely derived (`InpPinOppositeWickMax` from a window fixed by the repository's own fixtures; `XSPARK_STRUCTURE_MAX_PIVOTS` from the window size and the fractal wing; the RR tolerance from the tick size), one is bounded by the repository's own arithmetic (`InpMinScore = 4.0` from the unaided pattern ceiling), one is a pure swap of existing values (the RSI bands), and the rest are guesses that must be set from measurement before they are trusted.
- **The RSI outer bounds are retained without a justification under the new interpretation**, and section 3.5 says so rather than presenting the swap as a complete repair.
- **Every confidence interval and streak probability assumes independent trades.** M15 gold clusters by day, session and volatility regime. Effective sample size is below the trade count, every interval is wider than stated, and every required sample size is larger.
- **MFE and MAE are biased toward zero by about one tick** and are meaningless under 1-minute OHLC modelling. Real ticks are mandatory for any run they are read from.
- **HTF series in the Strategy Tester are generated from base data**, so HTF pivots — and therefore the structure verdict — will differ between "Every tick based on real ticks" and "Open prices only". The base path already has this property, so this introduces no new *class* of non-determinism, but every structure-sensitive run must declare its modelling mode.
- **Any out-of-sample window must end before 2026.09.01.** That fortnight generated every hypothesis in `docs/IMPROVEMENT_PLAN.md` and is burned.
- **Every "reproduces exactly" gate needs a same-session control run of the unmodified build immediately before the comparison**, or a tick-cache or terminal-build difference gets attributed to the change.
- **There is no continuous integration and no assertion framework.** The test scripts print pass or fail and exit normally either way. A human has to read the output.
- **This document's own credibility rests on source verification, so five claims that circulated in review and did not survive it are recorded in section 2.7 rather than quietly dropped.** Two of them were in the first draft of this document and were wrong in the direction that flattered it: the assertion that the RR bounds "cannot fail" (they bind, at the `InpMinRR` half-integer, and the correction is now section 2.4) and the assertion that the trail is "inert by construction" (it ratchets; only its arm is dead, and the correction is now in section 5). Two more arrived from review of that draft and are wrong in the opposite direction: the RR upper bound does **not** bind, because 3.0 is an integer, and the `InpMinRR = InpMaxRR = 8.0` probe does **not** take zero trades, for the same reason. The fifth — the `return false` / `break` "defect" at `ScoreBotV3.mqh:71` — is not a defect at all.
