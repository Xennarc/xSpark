# Optimizer setup

## Why this file exists

A 1,024-pass optimization run on XAUUSDm M15 returned **zero trades and zero
profit on every single pass**. Nothing was wrong with the EA. The sweep ranges
were invalid, so the EA refused to start.

Every parameter had been swept from its default to ten times its default
(`InpMaxRR` 3 → 30, `InpPartialClosePct` 50 → 500, `InpMinScore` 2 → 20, and so
on for 58 parameters at once). Most of those values are outside the domains
`OnInit` validates, so the EA logged a critical error and never traded.

Breakdown of that run:

| Rule broken | Passes | Share |
|---|---|---|
| `InpPartialClosePct >= 100` | 909 | 88.8% |
| Risk percent above the 10% hard ceiling | 889 | 86.8% |
| `InpMaxAccountRiskPct` out of range or below the per-trade cap | 692 | 67.6% |
| `InpMinScore > 9` (9 is the maximum score any setup can reach) | 618 | 60.4% |
| `InpMaxDailyDDPct >= InpMaxTotalDDPct` | 287 | 28.0% |
| `InpMaxRR < InpMinRR` | 179 | 17.5% |

Only **2 passes of 1,024** would have initialised at all, and both then hit the
broker volume minimum on a 500 USD deposit - a 4.2 x ATR stop on M15 gold needs
about 0.007 lots at that balance, below the 0.01 minimum, so `PositionSizer`
aborted every trade. Net information from the run: none.

## Valid domains

`OnInit` refuses to start unless all of these hold. An optimizer pass that
violates any one of them contributes nothing.

| Input | Valid range | Notes |
|---|---|---|
| `InpMinScore` | 0 – 9 | 9 = `XSPARK_SCOREBOT_MAX_SCORE`; above it nothing can ever qualify |
| `InpMaxOpenTrades` | 1 – 10 | |
| `InpRiskPctTier1/2/3` | > 0, ≤ 10 | `XSPARK_MAX_ALLOWED_RISK_PCT` |
| `InpMaxRiskPct` | > 0, ≤ 10 | |
| `InpMaxAccountRiskPct` | ≥ `InpMaxRiskPct`, ≤ 30 | must leave room for one trade at the per-trade ceiling |
| `InpMaxDailyDDPct` | > 0, **strictly below** `InpMaxTotalDDPct` | or the daily brake can never fire |
| `InpMaxTotalDDPct` | > 0, < 100 | |
| `InpPartialClosePct` | > 0, **< 100** | it is a percentage of the position |
| `InpPartialTPRatio` | > 0 | |
| `InpATRMultSL`, `InpATRMultTrail` | > 0 | |
| `InpMinRR` | > 0 | |
| `InpMaxRR` | ≥ `InpMinRR` | |
| `InpATRRatioBoost` | > 0.7 | |
| `InpATRMinPoints` | > 0 | |
| `InpATRMaxPoints` | > `InpATRMinPoints` | |
| `InpWildMarketPct` | > `InpQuietMarketPct` | |
| `InpRSILongMin/Max`, `InpRSIShortMin/Max` | 0 – 100, min ≤ max | |
| `InpMaxQuoteAgeSeconds` | ≥ 1 | |
| `InpMagicNumber` | ≠ 0 | |

Four of these are **cross-parameter** constraints - `InpMaxAccountRiskPct` vs
`InpMaxRiskPct`, `InpMaxDailyDDPct` vs `InpMaxTotalDDPct`, `InpMaxRR` vs
`InpMinRR`, `InpATRMaxPoints` vs `InpATRMinPoints`. Sweeping either side of a
pair independently produces invalid combinations even when both ranges look
sensible on their own. Prefer holding one side fixed.

## Never optimize risk

Leave `InpRiskPctTier1/2/3`, `InpMaxRiskPct` and `InpMaxAccountRiskPct` **fixed**
during optimization, and set them from the account's own risk budget instead.

The optimizer maximises a result metric over a single history. Risk per trade is
the parameter with the largest effect on final balance, so the optimizer will
always push it toward - and past - the growth-optimal fraction, and then report
whichever oversized setting happened to survive that particular sequence. That
is precisely the failure the first reference run recorded: 3% per trade across
five correlated positions peaked at 88,835 USD from 5,000 and ended at 570.

Sizing is decided from the measured edge, not discovered by search.

## Sweep a few parameters, not all of them

The void run varied 58 parameters. Even had every pass been valid, the space is
roughly 10^82 combinations and 1,024 samples cannot characterise it; the best
pass would describe noise in the sample, not behaviour of the strategy.

Sweep **two to four related parameters at a time**, with everything else pinned
to a known-good baseline, so a result can be attributed to something. Stop when
a result stops making mechanical sense.

`presets/optimize-stage1-exits.set` is a worked example: exit geometry only,
risk pinned, every combination valid by construction.

## Validate out of sample

The optimizer's best pass is an upper bound on that history, not an estimate of
future behaviour. Optimize on part of the period and confirm on the rest, or on
a different year, before trusting a setting. A parameter that only works in the
window it was fitted to is a fitting artifact.

## Account size and timeframe

Both matter before a sweep is worth running. Risk in dollars for a
minimum-volume XAUUSD trade equals the stop distance in dollars, so wide stops
on a small deposit push required volume below `SYMBOL_VOLUME_MIN` and
`PositionSizer` aborts - silently, from the optimizer's point of view, as a pass
with zero trades. M15 makes this worse than M5 because ATR is larger.

A pass reporting zero trades is a configuration problem, not a result. If a
whole optimization returns zeroes, check `OnInit` validation and the volume
floor before changing anything about the strategy.
