# Multiple trades: configuration fix and validation

## Why two slots stopped all entries

The old startup check required `slots * maximum nominal risk <= 90% of account cap`.
With the shipped 3% risk tiers and 6% account cap, selecting two slots meant
`2 * 3% = 6%`, above the 5.4% allocation limit. This set the shared V2 configuration
flag to false even on an empty account, so **every** new entry was refused as
`V2 CONFIG BLOCKED`. It was not a missing market signal.

## Current behavior

**Maximum open trades for this bot** accepts 1–10 on the already-required hedging
account. Existing risk percentages act as ceilings. For more than one slot, the
risk manager calculates:

`per-entry ceiling = min(maximum risk per trade, 90% * account risk cap / slots)`

The selected score-tier percentage is capped at that ceiling; a lower tier is
never raised. The startup journal reports the resolved ceiling and dashboard
risk uses the actual reduced percentage. One-slot sizing retains its previous
behavior. No new input is needed and no account limit is increased.

With the existing 3% tiers, 3.5% per-trade maximum and 6% account cap:

| Maximum trades | Nominal risk per entry | Full allocation |
| --- | --- | --- |
| 1 | 3.00% | 3.00% |
| 2 | 2.70% | 5.40% |
| 3 | 1.80% | 5.40% |
| 5 | 1.08% | 5.40% |
| 10 | 0.54% | 5.40% |

These illustrate the implementation, not recommended risk settings or measured
returns. Existing positions are not resized when this input changes.

The EA still needs a **new, independently eligible signal** to use another slot.
It does not open all slots from one signal, remove pattern/bar duplicate guards,
permit opposing XSpark positions, or add recovery/grid sizing. Trade count is a
ceiling, not a quota. Small accounts can still fail the broker minimum-lot check
when the reduced budget cannot fund a valid order.

## Checks at each order attempt

The planning check still measures all open account positions, including other
symbols, other bots and manual positions. The execution boundary now repeats the
shared exposure read after refreshing price, stops and volume on **every retry**:

- The current symbol/magic count must still be below the selected slot limit.
- Current account risk plus the resized order must fit the account cap.
- Unreadable positions or positions without stops refuse admission.
- Existing direction, quote-age, price-drift, stop geometry and margin checks remain.

This closes the gap where the plan could pass but exposure changed before a
retry. A quote-based check cannot guarantee a fill price or prevent gap losses.
It does not serialize unrelated EAs or separate terminals opening at exactly the
same moment. Retain unique bot IDs per chart; cross-terminal simultaneous entry
and broker-specific execution still require validation.

## Separate management state for every trade

PositionManager already iterated a snapshot of position IDs, used per-ID stored
state and sent partial closes/stop changes by ticket. The snapshot loop preserves
coverage when a close causes the state array to shrink during management.

A dangerous recovery fallback was still present: a closed trade could be rebound
to another same-direction position with an almost identical entry price. That
fallback is removed. Rebinding now requires the exact broker position identifier;
a changed ticket preserves that position's own stop/partial state. A ticket with
a mismatching identifier cannot overwrite or manage another trade's state.
Incomplete broker enumeration preserves state rather than pruning it as closed.

MetaQuotes documents that the [position identifier remains stable across its
lifetime while a ticket can change](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties).
No entry-price proximity is used as a substitute for that identity.

## Validation

`python3 tools/test_portable_logic.py`: **151 passed, 0 failed** with address and
undefined-behavior sanitizers. New checks include 16 concurrent-risk cases and
14 broker-double cases exercising actual production reconciliation and management
methods, plus the shared account exposure reader. Coverage includes:

- Two/three/ten-slot allocation, signal sizing, lower tiers and actual dashboard risk.
- Second-slot admission, third-entry refusal, foreign exposure and missing stops.
- Two same-price trades with separate identities; closing one removes only its state.
- Ticket changes, unreadable snapshots, disconnection and identity mismatch.
- Independent partial profits, break-even and trailing for two positions.
- Restart restoration and not skipping the second position when the first closes.

The doubles replace broker execution, persistence and protection normalization;
they are **not** MT5 emulation. Native `TestConcurrentRisk.mq5` provides the 16
pure sizing/admission checks for terminal execution. MetaEditor compilation,
native scripts and live-broker/Strategy Tester multi-position behavior were not
run here. Required terminal acceptance: zero-error/zero-warning build, then paired
1/2/3-slot real-tick tests, restart with two positions open, partial/BE/trailing on
each, a saturated slot limit, account-cap refusal with foreign exposure, and
per-ticket closes without state transfer. Do not change multiple strategy inputs
while comparing these runs.
