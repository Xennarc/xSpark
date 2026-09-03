# Decision Log

## ADR-001 - Native MQL5 Production Runtime

Reason: Native MQL5 keeps infrastructure minimal, integrates directly with MT5, and is suitable for deployment on the Exness Windows VPS.

## ADR-002 - Strategy/Execution Separation

Reason: Strategies should not possess authority to bypass safety checks, risk controls, sizing rules, or broker execution boundaries.

## ADR-003 - Fail-Closed Safety

Reason: Unknown or ambiguous safety state should prevent new exposure rather than guess.

## ADR-004 - No External Runtime Initially

Reason: A single-trader retail system should remain cheap, simple, and operationally easy to run.

## ADR-005 - Broker State Is Authoritative

Reason: EA RAM state can disappear after restart, crash, recompilation, chart changes, or VPS interruption.

## ADR-006 - Canonical XAU Point Model

Reason: ScoreBot_v3 thresholds were specified in 0.01 XAUUSD price units, while brokers may quote gold with different native point sizes. Strategy thresholds use canonical points and convert to broker-native values only at MT5 boundaries.

## ADR-007 - Analysis Mode Remains Active When Trading Is Disabled

Reason: `InpEnableTrading=false` should allow safe observation of signals, scores, dashboard state, and block reasons without letting orders reach the broker.

## ADR-008 - Exact Broker Position Identification

Reason: Matching a newly executed entry by direction and newest open time is ambiguous once more than one XSpark position can exist. `CTrade::ResultDeal()` plus `DEAL_POSITION_ID` identifies the created position exactly, so strategy state can never be attached to a different XSpark position. A direction/time/volume match survives only as a documented fail-safe fallback for the case where the broker deal exposes no position id.

## ADR-009 - Execution-Time Risk Revalidation

Reason: Planning happens on the closed-bar evaluation price, but the broker fills at the price available at send time. Recomputing stop distance, volume, target, stop-level validity and margin immediately before each send keeps actual monetary risk at the selected risk percentage. The locked ATR stop is never moved to preserve the planned lot size; the volume adapts instead. Movement beyond the configured deviation aborts the entry rather than chasing the market.

## ADR-010 - Fail Closed On Failed State Registration

Reason: A confirmed broker execution that XSpark cannot represent in managed state is a state divergence, not a successful entry. It must never be reported as healthy. The EA logs CRITICAL, latches SafetyManager, reconciles against MT5, and blocks new entries until managed state provably covers live broker exposure, while protective management of existing positions continues.

## ADR-011 - Stale Quote Rejection Is A Production Safety Addition

Reason: A frozen or invalid price feed must not be used to open new exposure. `InpMaxQuoteAgeSeconds` defaults to a conservative 15 seconds for live XAUUSD, where a quiet feed still ticks well inside that window. This gate is production safety, not tested ScoreBot strategy logic: it does not change scoring and it never blocks protective management.

## ADR-012 - Paced Killswitch Flattening

Reason: Flattening must keep retrying until no XSpark exposure remains, but calling the trade server and emitting identical CRITICAL lines on every tick hides the signal it is supposed to raise. Retries and logging are paced, remaining exposure is reported, and completion is logged once. The killswitch itself is unchanged.
