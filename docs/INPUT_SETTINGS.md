# Configuring XSpark

The Inputs tab now starts with everyday choices and groups detailed tuning below
`Advanced`. Every setting has a readable label. You can collapse groups in the
Strategy Tester by double-clicking their headings.

## Quick setup in Strategy Tester

1. Under **Start here**, choose **Entry style → Chart patterns and engulfing
   entries** to test the new pattern engine. This sets the five required entry
   switches together. You do not need to configure the custom switches below.
2. Set **Allow new trades** to `true` for simulated orders. With `false`, new
   entries are blocked; existing positions still receive protective management.
   Changing entry style never enables trading by itself.
3. Review **Risk and account limits**, **Maximum open trades for this bot**, and
   **Minimum setup score**. A higher score is stricter, not a guaranteed better
   return. The three risk rows apply to different score ranges; use the same
   percentage in all three if you want a fixed risk percentage across scores.
4. Under **Chart patterns**, choose which formations to recognize. Pin bars are
   off by default in the chart-pattern style. Engulfing is built into that style.
5. Review **Stops and taking profit** and **Trading hours**. Keep automatic market
   adaptation on unless you intend to supply symbol-specific manual limits.
6. Confirm the journal says `PATTERN ENTRY PROFILE ACTIVE`, then export the full
   `.set` to save the exact configuration you tested.

The supplied `presets/tester-pattern-active.set` and
`presets/tester-pattern-observe.set` now select the corresponding entry style.
They are partial presets and enable simulated trading: use only in Strategy
Tester, and review the retained risk/exit settings before running.

With more than one trade slot, the EA now reduces per-entry risk as needed to
share 90% of the account risk cap across the slots. It no longer blocks all entries
just because the requested percentages would fill the cap. See
[multiple-trade sizing and management](MULTIPLE_TRADES.md) for examples and limits.

## What the entry styles mean

| Entry style | What happens |
| --- | --- |
| Use saved / custom entry switches | Uses the five switches in group 13 exactly as set. This is the default for compatibility with existing settings. |
| Original candle entries | Uses the original candle-entry rules. Chart recognition is still logged. Original pin-bar behavior remains. |
| Preview chart patterns (original entries) | Evaluates the new pattern rules but keeps original entries. If new trades are allowed, these are original-strategy trades; preview does not mean trading is disabled. |
| Chart patterns and engulfing entries | Uses qualified chart patterns and strong engulfing, with the required trend and entry-location checks enabled together. |

The last three choices override **only** the five custom entry switches. Their
visible saved values are not rewritten; they are ignored until you choose the
saved/custom style again. Pattern toggles, optional momentum filters, thresholds,
risk limits, stops and trading permission remain your chosen values. Invalid
combinations elsewhere still block new entries and explain why in the journal.

The momentum filter's hard veto applies only to enforced entries, not original
entries or preview. Its RSI limits still contribute to the existing setup score.
If you require momentum to turn, also enable the momentum filter.

To retain the earlier experimental trend-pullback strategy, use the saved/custom
style, turn preview off, enable the three trend/location/resumption switches and
leave chart-pattern entry rules off. The advanced pullback-break and momentum-turn
switches apply to that custom strategy; they are not fallback entries in the
chart-pattern style.

## Units and limits in plain language

- **Average range** means ATR on the trading timeframe, not a daily range. A stop
  multiplier of 1.5 means 1.5 times that range. Minimum swing size instead uses the
  structure window's average true candle range, including gaps.
- **Initial stop distance** measures the original entry-to-stop gap. A target
  multiple of 2 means twice that gap, not twice your account balance. Partial
  profit closes the stated portion once price reaches its configured multiple.
- **Risk per trade** uses account balance. The score bands are below 4.5,
  4.5 to below 5.5, and 5.5 or above. The account limit includes other symbols
  and other bots; the maximum-open-trades input applies to this bot instance.
- **Equity drop** includes floating P/L. Daily drawdown uses that broker day's
  peak equity; the emergency stop uses the persisted account equity peak. These
  are not simple sums of closed losing trades. Resetting the emergency stop is a
  deliberate recovery action; return its switch to `false` after use.
- **Pullback fractions** remain fractions for compatibility: `0.30` means 30%,
  not `30`. Chart breakouts use their own validated location instead of this
  candle-entry pullback interval.
- **Broker time** drives the weekend closing hour. The close applies to positions
  managed by this bot. The existing weekend window also prevents new entries.
- **Price tolerance** is the permitted entry/exit price movement, not a guaranteed
  fill. Automatic values use the smallest configured stop; manual values use
  strategy points. Extra margin is a percentage of the order's required margin.
- **Strategy points** are the EA's symbol-aware price units, not necessarily MT5
  `_Point`. The journal reports the resolved size. Manual movement, spread and
  price-tolerance limits apply only with automatic adaptation off. Both the
  absolute spread cap and average-range spread cap still apply when the spread
  filter is enabled.

## Saved settings and validation

All 70 existing input identifiers, types and default values are retained. Only
their displayed labels and order changed; `Entry style` is the one new input
(`InpEntryStyle`: 0 saved/custom, 1 original, 2 preview, 3 chart-pattern entries).
Before loading an older `.set` that has no entry-style key, explicitly select
**Use saved / custom entry switches** or reset inputs first. Partial presets may
retain values from the current Inputs dialog, including entry style.

Readable labels use the established comment syntax and the dropdown uses named
enumeration choices described in the official
[MQL5 input documentation](https://www.mql5.com/en/docs/basis/variables/inputvariables).
Labels stay within the documented 63-character limit. Grouping organizes the
native dialog; it does not dynamically hide irrelevant fields.

Validation: 151 portable checks pass, including nine entry-style resolver checks;
a source comparison confirms all 70 prior input definitions/defaults are preserved
and all 71 displayed labels are present, unique and within the length limit.
MetaEditor compilation and visual verification of the Inputs dialog remain
outstanding. No risk defaults or trade-frequency/profitability claims changed.
The previous auto-adaptation, risk and execution rationale remains documented in
ADRs 022, 024 and 026 in `docs/DECISIONS.md`.

## Chart panel

The panel now has **Start with a compact chart panel** and **Animate live dashboard
activity** in the display group. **Less / Expand** changes the view on the chart.
See the [dashboard guide](DASHBOARD.md) for live activity, trade totals and messages.
