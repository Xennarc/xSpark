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

## ADR-006 - Canonical XAU Point Model (superseded by ADR-020)

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

## ADR-013 - Broker Protection Is Verified, Not Assumed

Reason: A `TRADE_RETCODE_DONE` retcode proves the order was accepted; it does not prove the broker applied the stop loss that was sent with it. XSpark reads the live `POSITION_SL` after every confirmed entry, applies the submitted stop when it is missing, keeps retrying on every management pass, and blocks new entries while any XSpark position is unprotected. Recording a stop that the broker never applied would make unprotected exposure look protected.

## ADR-014 - Wider Deviation For Exits Than For Entries

Reason: An entry that cannot be filled inside a tight tolerance can simply be abandoned. An exit cannot. `CTrade` defaults to a 10-point deviation, which for gold is smaller than a typical spread, so a killswitch close could be rejected repeatedly and leave exposure open. XSpark-owned exits use 100 ScoreBot points; closing at a slightly worse price is always better than failing to close.

## ADR-015 - Residual Execution Slippage Is Reported, Not Pre-Compensated

Reason: A market order may fill anywhere inside the configured deviation, so realised risk can exceed the sized risk by up to deviation divided by stop distance. Pre-shrinking the volume for the worst permitted fill would systematically under-size every trade and change tested position sizing, which is out of scope for infrastructure hardening. The realised distance is computed from the actual fill and a WARNING is logged when it exceeds the sized distance, leaving the trade-off visible and the deviation input available to tighten it.

## ADR-016 - Protective Levels Are Validated Against The Close-Side Price

Reason: MT5 measures a position's stop loss and take profit against the price the position would be closed at: the Bid for a long, the Ask for a short. Validating them against the entry side would allow a stop to sit inside the broker stop level by up to one spread, and a long whose stop sits above the Bid would be stopped out the moment it opens. Execution-time validation therefore anchors stop-level checks on the close side, while the risk distance and the target stay anchored on the entry reference, which is the price the position is actually opened at.

## ADR-017 - Hedging Accounts Only

Reason: XSpark's position model is per-trade. Each entry gets its own ticket, its own initial stop and target, its own partial-close size, and its own persisted state record keyed by `POSITION_IDENTIFIER`. A netting account merges same-symbol trades into a single position with a blended open price and summed volume, and can reduce or flip that position on an opposite signal. Under netting, the recorded entry, initial lots and initial risk distance stop describing the live position, so the 2.5R partial trigger, the break-even level and the position-count cap all operate on values the broker no longer holds. `OnInit` therefore rejects any account whose `ACCOUNT_MARGIN_MODE` is not `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` rather than managing exposure it cannot model.

## ADR-018 - Persisted State Is Required Before XSpark Manages A Position

Reason: XSpark's exit logic is expressed in R multiples of the ORIGINAL entry risk. That original risk cannot be recovered from a live position, because `POSITION_SL` may already have been trailed or moved to break-even - where `MathAbs(entry - stop)` is exactly zero. Deriving it from the live stop produced a fabricated R that either disabled management outright or fired the partial at the wrong price.

A position is therefore managed only when a persisted record for its `POSITION_IDENTIFIER` exists AND that record's direction and entry agree with the live position. Otherwise it is adopted, counted against the exposure cap, logged, surfaced on the dashboard as `UNMANAGED EXPOSURE`, and left to the broker-side SL/TP it already carries. A failed load is never written back: doing so would overwrite the only recoverable copy of the original risk and would then match its own live values on the next restart, turning a one-off failure into a permanent and invisible loss of management. Broker state remains authoritative for direction, entry, volume and open time (ADR-005); the state store supplies only the facts MT5 cannot report.

## ADR-019 - Per-Position State Is Swept, Never During OnInit

Reason: Positions that close while the EA is not running never reach reconciliation's cleanup path, so their per-position keys accumulate against MT5's global-variable budget until `GlobalVariableSet` begins to fail. The sweep's two liveness tests both trace back to `PositionsTotal()`, directly or through the table reconciliation builds from it, so they are not independent: a terminal whose trade context has not synchronised reports zero positions and every key looks orphaned. Running the sweep in `OnInit` would therefore delete the state of live positions. It runs on the first tick after a valid quote and a completed reconciliation, is skipped while the terminal is disconnected, and reconciliation itself defers pruning under the same condition.

## ADR-020 - The ScoreBot Point Size Is Resolved, Not Hardcoded

Reason: Every ScoreBot threshold - the ATR gate, the spread cap, the entry deviation and the exit deviation - was denominated against `XSPARK_XAU_CANONICAL_POINT_SIZE`, a compile-time 0.01 that is only meaningful for gold. The size is now derived from the instrument specification through the pure `XSparkPipSizeForSpec(digits, point, ...)`, which requires `SYMBOL_POINT` to agree with `10^-SYMBOL_DIGITS` and fails closed when it does not. `SYMBOL_POINT` and `SYMBOL_DIGITS` are independent broker-reported fields, and deriving the threshold size from one while `XSparkNormalizePrice` rounds prices with the other is only sound while the two agree.

On XAUUSD the derivation is not an approximation of the old constant, it is the same double. At 2 digits the derived size is `SYMBOL_POINT` itself, 0.01. At 3 digits it is `0.001 * 10`, a product that is exact in binary64 and carries the identical bit pattern. Both quote conventions a broker may use for gold therefore produce a size bitwise equal to the constant they replace, so no threshold, no gate and no deviation changes on gold. The deterministic tests assert this with exact equality rather than a tolerance, because a tolerance would also pass for a size that silently rescales every threshold.

The resolved size is compared against the declared baseline on the same relative tolerance the resolver already accepts between `SYMBOL_POINT` and `10^-SYMBOL_DIGITS`, and on success the baseline constant itself becomes the operating denominator. Demanding bitwise equality at the assertion while tolerating `1e-6` on the input it was derived from would be internally inconsistent: a specification that passed resolution could still latch a permanent veto. Assigning the baseline rather than the broker-derived double also makes the bit-for-bit neutrality guarantee structural instead of contingent on the broker reporting an exactly representable point. A genuine rescaling is a factor of ten, nine orders of magnitude outside the tolerance, so nothing real is admitted by it.

A size that cannot be resolved, or that is outside that tolerance of the declared XAUUSD baseline, is deliberately NOT an initialization failure. If `OnInit` does not succeed, `OnTick` never runs: trailing, break-even, partial management, protection repair, weekend close and the total-drawdown killswitch all stop while live positions remain open at the broker. That is strictly worse than the mis-scaled thresholds the check exists to catch, and it contradicts the reconciliation posture of ADR-005. The EA instead falls back to the declared baseline - the size that shipped before this change, so exits keep the distance ADR-014 requires - logs CRITICAL, and latches a SafetyManager veto that blocks new exposure while leaving protective management untouched. Because that veto holds for the rest of the session, it has its own dashboard status, `POINT SIZE FAULT`, in the alarm colour: a permanent block on new entries must never render as a healthy green `SCANNING`.

The size is resolved once in `OnInit` and passed to each module rather than read inside a conversion. `Reconcile` runs on every tick, and the exit-deviation conversion executes on the killswitch flatten path, which sits above the market-state validity check precisely so that flattening still runs when the quote feed has dropped. A `SymbolInfoDouble` call inside those conversions could fail at the moment the conversion matters most. For the same reason the broker-point conversion now rejects non-finite results: MQL5 leaves a non-finite-to-`ulong` conversion undefined, and the consumer is the slippage tolerance an order is sent with.

The ScoreBot point size is what this change hoists. The broker point size is a separate quantity and is still read at the conversion call site, exactly as before; hoisting that too would be a behaviour change rather than unit plumbing, so it is out of scope here.

This change is unit plumbing only. The EA remains XAUUSD-only and M15-only, no threshold value is altered, and no scoring, sizing or exit rule is touched.
