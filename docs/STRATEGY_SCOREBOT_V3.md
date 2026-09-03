# ScoreBot_v3 Strategy

ScoreBot_v3 is the first XSpark strategy implementation. It targets XAUUSD on M15 and runs inside the native MT5 Expert Advisor. This document separates the locked tested strategy logic from production safety additions added for live-risk control.

The default configuration is MAX_SHARPE. Reference Python backtest results are unvalidated priors only, not expected returns.

## Identity

- Strategy ID: `ScoreBot_v3`
- Default Magic Number: `770331`
- Default order comment: `ScoreBot_v3`
- Primary symbol: XAUUSD, including broker suffixes/prefixes containing `XAUUSD`
- Primary timeframe: M15
- Production runtime: native MQL5

The EA refuses initialization on non-XAUUSD symbols or non-M15 chart timeframes.

## XAU Point Normalization

ScoreBot canonical XAU points are not broker-native MT5 points.

```text
1 ScoreBot point = 0.01 XAUUSD price units
80 points        = $0.80
800 points       = $8.00
50 points        = $0.50
30 points        = $0.30
```

The implementation converts between canonical ScoreBot points, broker-native points, and price distance through `SymbolMath.mqh`. Strategy thresholds such as ATR, spread, and slippage use canonical ScoreBot points first, then convert to broker-native values for MT5 operations.

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

The EA uses true H1 indicator handles. It does not approximate H1 values from M15 indicators.

### Bar Evaluation

Signals are evaluated once per newly opened M15 bar, using the just-closed M15 bar as signal bar 1. On initialization, the EA records the current M15 bar and waits for the next genuine new bar before evaluating a signal.

### Patterns

Patterns operate on closed M15 candles.

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

- ATR14 must be between 80 and 800 canonical ScoreBot points.
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
- MTF: 0.5 when H1 and M15 RSI direction conditions pass

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
- Uses latest cached closed M15 ATR14
- Distance: `2.0 * ATR14`
- Only tightens SL
- Never modifies TP

## Risk Model

Risk tiers use the final session-weighted score:

- Score >= 5.5: Tier 3
- Score >= 4.5: Tier 2
- Otherwise: Tier 1

Defaults:

- Tier 1: 1.0%
- Tier 2: 1.5%
- Tier 3: 2.0%
- Hard cap: 2.0%

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

- Max spread: 50 canonical ScoreBot points, or $0.50
- Max spread as ATR percentage: 10%

This is an execution gate, not a score component.

### Daily Drawdown Halt

Tracks server trading day. At 5% decline from that day high-water equity:

- New entries are blocked.
- Halt remains latched until next server day.
- Existing position management continues.
- State is persisted using MT5 terminal Global Variables namespaced by account, symbol, and magic.

### Total Drawdown Killswitch

Tracks runtime high-water equity. At 8% decline:

- Killswitch latches.
- XSpark-owned positions for this symbol and Magic Number are closed.
- XSpark-owned pending orders for this symbol and Magic Number are cancelled.
- New entries remain blocked until EA restart/reinitialization.
- Manual trades and other Magic Numbers are not touched.

### Stop-Level Validation

Before initial protection or stop modifications, the EA reads `SYMBOL_TRADE_STOPS_LEVEL`, adjusts invalid SL/TP outward only as needed, and normalizes prices for the symbol.

When initial SL is moved farther away, position sizing uses the actual final stop distance.

### Margin Validation

Before order submission, the EA uses `OrderCalcMargin` and requires free margin to cover calculated margin plus the configured buffer. Default buffer is 20%.

### Weekend Close

Disabled by default. When enabled, it closes only XSpark-owned positions for the chart symbol and Magic Number based on server time.

## Execution Boundary

ScoreBot_v3 does not include `Trade/Trade.mqh`, `CTrade`, `OrderSend`, direct buy/sell calls, direct close calls, or stop modification calls.

Execution authority is split as follows:

- `ExecutionEngine.mqh`: new market entries only
- `PositionManager.mqh`: XSpark-owned closes, partial closes, stop modifications, and pending-order cleanup

Both boundaries filter by symbol and Magic Number where appropriate and inspect trade-server retcodes.
Market-entry, stop-modification, and partial-close mutations are treated as confirmed only on completed trade-server retcodes, not on a local function return alone.

## Implementation Assumptions

### Assumption SBV3-001

S/R price is implemented as M15 bar1 close because the strategy is closed-bar deterministic.

### Assumption SBV3-002

Session classification uses the timestamp/hour of M15 bar1.

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
