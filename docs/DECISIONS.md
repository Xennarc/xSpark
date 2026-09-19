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

This change is unit plumbing only. The EA remains XAUUSD-only and M15-only as of this decision - both guards were lifted later by ADR-021 - no threshold value is altered, and no scoring, sizing or exit rule is touched.

## ADR-021 - The Instrument Guard Is Lifted; The Chart Period Guard Is Not

Reason: `XSparkIsXauUsdSymbol` refused every non-gold symbol because every ScoreBot threshold was denominated in a hardcoded gold unit. ADR-020 removed that constant, so the guard no longer protects anything the derivation does not already handle: the ScoreBot point size now comes from the broker specification and fails closed when that specification does not validate. The guard is therefore lifted and the instrument-specific decision moves into the pure `XSparkSelectOperatingPointSize`.

That selector branches deliberately. XAUUSD keeps the ADR-020 regression assertion unchanged - the resolved size must agree with the declared baseline, and the baseline constant is what operates - because that assertion is the proof that the unit migration changed nothing on gold, and lifting the guard must not dilute it. Every other instrument has no declared baseline to compare against, since there is no tested ScoreBot unit for EURUSD, so the spec-validated derivation IS the answer and is trusted when the specification validated cleanly. When resolution fails a denominator is still supplied wherever one exists, because the exit deviation is converted on the killswitch flatten path and a zero there would drop `CTrade` to its 10-point default, which is the hazard ADR-014 exists to prevent: the fallback is the declared gold baseline on XAUUSD and the raw broker point elsewhere. In every such case the size is untrusted, the SafetyManager veto blocks new exposure, and protective management continues.

One branch has no denominator to fall back to. When resolution fails on a non-gold symbol AND `SYMBOL_POINT` is itself not a valid positive number, the selector returns a size of zero, and `ExecutionEngine::Initialize` and `PositionManager::Initialize` both reject a non-positive size, so `OnInit` fails. That is deliberate and is not the case ADR-020 keeps out of `OnInit`: a symbol whose point size the terminal cannot report is one the EA can neither size, normalize, nor set a deviation for, so there is no useful protective management to preserve. It is refused up front rather than run blind.

The chart period guard stays, in a different form. The strategy cannot be evaluated without a multi-timeframe partner, and the partner comes from an explicit table rather than `PeriodSeconds(base) * 4` with a nearest-greater-or-equal search. The arithmetic is correct in the middle of the period list and degenerates at its edges: H8 has no 4x partner and lands on W1, a 21x jump; H12 lands on W1 at 14x; MN1 has nothing above it. A table states what is supported and is auditable against the tested M15 to H1 relationship. An unsupported chart period returns `INIT_PARAMETERS_INCORRECT`, which is the posture the M15 guard already had - a chart the EA cannot analyse at all is refused up front. This does not contradict ADR-020's rule against failing `OnInit`, which is about a runtime fault on a supported configuration, where refusing to initialise would abandon live positions.

Indicator handles, bar timestamps, warm-up bar counts and the accessor names all follow the resolved pair. The accessors were renamed from `ATR14M15` and `EMA50H1` to `ATR14Base` and `EMA50Higher`, and the report fields from `rsi_m15` to `rsi_base`, because a function named `ATR14M15` returning an H4 value on an H4 chart is an actively false name in a safety-critical file.

Two consequences are accepted as Phase 1 limitations rather than fixed here, because fixing either means changing threshold semantics and that is Phase 2's scope. The tested thresholds remain absolute, so `InpATRMinPoints = 80` means 80 pips on an FX pair and blocks every bar where ATR is 5-15 pips. And session weighting reads the hour of the signal bar, which stops discriminating above H1 and is meaningless on D1. Both are documented in the strategy document.

Position ownership is keyed by symbol and Magic Number and not by chart period, so two instances on one symbol at different periods would manage each other's positions and collide on per-position state keys. This is not fixed in code: deriving the Magic Number from the timeframe would orphan every position that exists at upgrade time. It is a deployment rule - one XSpark instance per symbol per account - recorded in the deployment document, because the EA cannot detect the violation from the inside.

## ADR-022 - The Ruin Stop Is Persisted, And Risk Is Sized To The Growth Optimum

Reason: two changes that only make sense together. The account owner asked for materially faster growth on a small account, which means a larger risk percentage. Raising risk against a ruin stop that did not survive a restart would have been a net reduction in safety, so the persistence lands first and in the same change.

The total-drawdown high-water mark and the killswitch latch were RAM-only, while the shorter-horizon daily halt was persisted. The asymmetry was backwards. `SafetyManager::Initialize` seeded the peak from live equity and cleared the latch, and MT5 reruns `OnInit` on any input change, recompile, reattach or terminal restart. The one control standing between a losing streak and the account was therefore the easiest piece of state in the system to erase, and it erased itself on precisely the action an operator takes when a latched EA has stopped trading: restarting it. The reference run in `IMPROVEMENT_PLAN.md` reached 7.98% against an 8.0% limit, so this was roughly two dollars of equity away from mattering. Both values now live in the same `StateStore` the daily state uses, under keys `tP` and `tL`, written when a new peak is set and when the latch fires.

A persisted latch needs a deliberate way out, and it must not be the restart itself. `InpClearKillswitchLatch` is a dedicated input, default false, that re-anchors the peak and clears the latch with a CRITICAL log line recording that it happened. An input change alone does not clear it, so a routine parameter edit or a VPS reboot cannot silently reset the ruin stop.

On sizing: with the edge measured in `IMPROVEMENT_PLAN.md` - 36% win rate, 1.974 payoff, +0.0706 R per trade - the growth-optimal Kelly fraction is 3.58% of balance per trade, and expected log-growth crosses zero at about 7.2%. That second number is the one that matters and it is not intuitive: above it, a genuinely positive edge still shrinks the account, because compounding is multiplicative and a large loss requires a larger gain to undo. Risk per trade is therefore capped at `XSPARK_MAX_ALLOWED_RISK_PCT` = 10%, which leaves room to size past the optimum deliberately while refusing a fat-fingered entry that would previously have been accepted in silence - the risk inputs were checked only for positivity.

Defaults move to a flat 3.0% per tier with a 3.5% ceiling. Flat, because tier selection reads the session-weighted score, so identical evidence would size differently purely by hour of day, and a larger risk figure amplifies that distortion. The tier inputs remain separate so tiering can be reinstated deliberately.

The drawdown limits move with the risk, because they are not independent of it. At 3.5% per trade, nine consecutive full-stop losses reach 25% and five reach 15%. At the previous 8% total limit, 3.5% risk would have latched on the fifth loss - and the reference run already contained an eight-loss streak, which at a 64% loss rate is roughly the median longest run over fifty trades rather than a tail event. An 8% limit at this risk level would have converted ordinary variance into a permanent stop. Limits are now 25% total and 15% daily, validated so the daily limit is strictly below the total limit, since a daily limit at or above it can never bind.

`XSparkConsecutiveLossesToDrawdown` computes the tolerance and the EA prints it at startup for whatever values are configured, with a WARNING when the killswitch would latch in fewer than six losses. The relationship is logarithmic rather than linear - eight losses at 1% cost 7.73%, not 8% - and getting it wrong by one tells an operator the account survives a loss fewer or more than it does.

This change RAISES risk at the account owner's explicit request. The implication, stated plainly: at these settings a 25% account drawdown is an expected outcome of ordinary variance, not a malfunction, and the killswitch is calibrated to permit it rather than to prevent it. It is not martingale, grid, averaging-down or recovery sizing - risk remains a fixed percentage of balance and is not increased after a loss - so AGENTS.md rule 26 is not engaged. Nothing here establishes that the edge is real; the measured edge remains roughly 0.35 standard errors from zero on fifty trades, and Kelly sizing of an edge that does not exist loses money faster than conservative sizing of the same non-edge.

## ADR-023 - Risk Is Capped At The Account, Not Only Per Trade

Reason: AGENTS.md rule 27 says no strategy may bypass maximum account-level risk limits, and the codebase could not enforce it. `InpMaxRiskPct` is a per-TRADE label. One instance at 3% risks 3%. Three instances on three symbols, each correctly obeying its own 3% cap, risks 9% simultaneously, and nothing anywhere could see that: every exposure check filtered by symbol and Magic Number, so each instance was structurally blind to the other two. Phase 1 made multi-symbol operation possible and ADR-022 raised per-trade risk, which turned a latent gap into a reachable one.

`XSparkPositionRiskCash` measures the money at risk on one position, and `XSparkAccountRiskWithinCap` decides whether one more would breach `InpMaxAccountRiskPct`. The scan is deliberately NOT filtered by symbol or Magic Number. The account does not care which Expert Advisor or which hand opened a position; a manual trade left open is still money that can be lost, and filtering to XSpark's own magic would reproduce exactly the blindness the cap exists to remove.

The cap fails closed on unknowable risk rather than treating it as zero. A position with no stop loss has unbounded downside, so total account risk becomes unknown, not small. Scoring it zero would let it slip under any cap - the single arithmetic mistake that turns a risk cap into decoration - so an unreadable position or one without a stop blocks new entries until it is resolved.

It is checked after the trade plan is built rather than in the earlier safety gate, because the prospective risk is only knowable once the plan has a volume and a broker-valid stop. A cap checked against an estimate is not a cap. The cost is that the check runs later in the entry path, after sizing work that may be discarded; that is the correct trade, because the alternative is a number that does not mean what it says.

Validation requires the account cap to be at or above the per-trade ceiling. Below it, no entry could ever pass and the EA would scan forever while appearing healthy.

The default is 6%, which permits two concurrent trades at the 3% per-trade default. That is a starting value, not a derived one: it is the total drawdown the operator is willing to have live at one moment, and it should be set deliberately rather than inherited.

## ADR-024 - Slippage Tolerances Are Per-Instrument Inputs, And The Entry One Must Prove It Still Bounds Something

Reason: `XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS` (30) and `XSPARK_CLOSE_DEVIATION_SCORE_POINTS` (100) were compile-time constants with no input override. Both were chosen for gold. ADR-021 lifted the instrument guard, so from that point the EA would attach to any instrument while carrying two gold-shaped risk numbers it could not be told to change. `DEPLOYMENT.md` recorded the consequence as a known Phase 1 limitation; this closes it.

The entry deviation is not a convenience setting. The order is sized against a reference price, and the stop is placed relative to that same reference, so the deviation is exactly the amount by which a permitted fill can push realised risk past selected risk:

```text
realised_risk / selected_risk  <=  1 + deviation / risk_distance
```

One value serves two roles inside the execution engine, as it did when it was a constant, and it is kept as one input because splitting it would be a behaviour change: it is both the plan-staleness gate (reject the send if the market has moved this far from the planned reference since the signal) and the slippage tolerance the accepted order is sent with. Only the second role produces the inequality above, because `RevalidateBeforeSend` re-sizes the volume and re-derives the stop against the refreshed reference before sending - so a stale plan is never sized stale. The residual is the fill slipping away from the reference the order was actually sized against.

What makes the raw number meaningless on its own is that `risk_distance` is instrument-dependent. Its floor is not, however, unknown: the ATR gate refuses to trade below the configured ATR minimum, so the smallest stop a configuration can ever produce is `InpATRMultSL * InpATRMinPoints`. That gives a worst-case overshoot ratio that is decidable from configuration alone, at initialisation, before any trade exists.

At the shipped gold defaults the ratio is `30 / (1.5 * 80)` = 0.25: a permitted fill can realise 125% of selected risk. On an FX major, where a ScoreBot point is a pip and the same 30 stands against a stop near 15 pips, the ratio is 2.0 - the permitted slip is twice the entire stop distance, so a fill can land at or beyond the position it is supposed to protect. The gate stops bounding anything at all.

Two thresholds, chosen on different grounds and deliberately not conflated:

- **FAULT at ratio >= 1.0** is not a preference. At that point the permitted slip equals the whole stop, realised risk is untethered from selected risk, and the control is inert by construction. This latches a SafetyManager veto on new entries, a CRITICAL log line, and a `DRIFT GATE FAULT` dashboard status, mirroring the point-size fault of ADR-020 exactly - and for the same reason, since both are cases where the arithmetic underneath sizing cannot be trusted.
- **WARN at ratio > 0.20** is a judgement. It sits near, but is deliberately NOT derived from, the headroom between selected risk (3.0%) and the per-trade cap `InpMaxRiskPct` (3.5%), which is 16.7%. The arithmetic does not line up and should not be made to look as though it does: `InpMaxRiskPct` caps SIZED risk, not realised risk, so at the shipped gold defaults a maximum-slip fill realises 3.75% against a 3.5% cap. That is pre-existing behaviour which this change EXPOSES rather than creates - the overshoot was always there, silently, and the EA logged only a post-hoc WARNING once the fill had already happened. The ratio is now reported at startup precisely so an operator can decide whether to lower the deviation before the trade rather than read about it after.

The gold defaults therefore emit a WARNING on every startup. That is intentional and the threshold was not moved to prevent it: 30 points of permitted slip against a 120-point minimum stop really is a 25% realised-risk overshoot, and an operator running live money should be told the number rather than have it tuned out of sight. Nothing about the shipped gold behaviour changes - both inputs default to the former constants, so the values sent to the broker are bit-for-bit what they were.

The fault does NOT use `INIT_FAILED`. Refusing to initialise would abandon any live position to the broker with no XSpark management at all, which is strictly worse than the misconfiguration being caught. New exposure is blocked; protective management of existing positions continues. This is the same reasoning as ADR-020 and follows AGENTS.md rules 9 and 23.

The exit deviation is deliberately NOT subject to the same check, and the asymmetry is the point. On an exit, a tolerance that is too generous costs a slightly worse fill; a tolerance that is too tight gets the close REJECTED and leaves live exposure that XSpark intended to be flat. The failure modes are not symmetric, so an upper bound there would be a risk control pointing the wrong way. Only a non-finite or non-positive value is refused.

This removes no control and weakens none, so AGENTS.md rule 5 is not engaged: two values that could not previously be corrected for the instrument in use can now be corrected, and a configuration in which one of them had silently stopped working now blocks trading instead of proceeding. What it does not do is establish a correct value for any instrument other than gold. Setting these for a new symbol remains an operator decision, and the startup line reports the ratio so that decision can be made against a number rather than a guess.

## ADR-025 - The Panel Treats An Unknown Status As A Fault, Not As Healthy

Reason: the chart panel coloured its status line by testing a known list of bad statuses and letting everything else fall through to green. That list had to be edited by hand every time a status was added anywhere else in the EA, and nothing enforced it. The default for "I do not recognise this" was therefore the one reading an operator must never be given wrongly.

This was not hypothetical. `ACCOUNT RISK` and `DRIFT GATE FAULT` are hard faults that block all new entries, both introduced on open branches, and neither appeared in the panel's list. Whichever merged first would have rendered green on a panel that was, at that moment, reporting a halted EA as healthy. That is the third separate change to touch the same colour expression, which is itself the argument for making it a function.

`XSparkDashboardSeverity` inverts the default. Green is now an explicit closed set - `SCANNING` and `MANAGING` - with idle, blocked and fault tiers enumerated, and everything else mapping to FAULT. Both pending statuses are mapped ahead of their branches so neither can render green whichever order the merges happen in. The reasoning for the default: if a status reaches the panel that nobody mapped, what the panel actually knows is that it does not know what the EA is doing, and there is no reading of that which is green. A false red costs an operator one glance at the journal. A false green costs them the reason they were watching the panel at all.

The same principle governs the bars. `XSparkDashboardBarPixels` returns an EMPTY bar for any value it cannot compute - non-finite, negative, or against a non-positive maximum - rather than a full one, so an unreadable reading can never be mistaken for a maximum reading.

Two presentation defects are fixed alongside it, both cases of the panel showing a true number that read as the wrong thing. The seven score components have different maxima: pattern reaches 2.0, MTF reaches 0.5, the rest reach 1.0. Printed as bare numbers on one line, a maximum MTF reading rendered as `MTF 0.5` and read as low. Each component is now drawn against its own maximum. And the score was printed beside its threshold as two numbers to compare; the score bar now carries a tick at the threshold, so fill past the tick qualifies and fill short of it does not.

Everything here is display. No risk control is read, written, weakened or bypassed, and the two SafetyManager accessors this adds are read-only, existing so drawdown can be drawn against the limit it is spending rather than as a bare percentage. AGENTS.md rule 5 is not engaged. What the change does carry is the ordinary risk of any drawing code: geometry was verified arithmetically against the panel bounds, not visually, so first attach should confirm nothing is clipped or overlapping before the panel is trusted at a glance.

## ADR-026 - Instrument-Scaled Thresholds Are Derived From The Instrument

Reason: a EURUSD M15 run took zero trades. The journal records the cause precisely - a detected pattern and a non-zero session weight, then `pat=0.00 atr=0.00 threshold=0.0000`, which is the signature of the ATR gate returning before scoring ever happens.

Four thresholds are expressed in ScoreBot points, which is the pip of whatever instrument the chart is on: the ATR floor and ceiling, the absolute spread cap, and the two slippage tolerances. The shipped values are gold values. On EURUSD an ATR floor of 80 asks for 80 pips of range on a timeframe whose ATR is nearer 10, so the volatility gate refused every bar for the entire run and the EA reported itself healthy while doing nothing.

`DEPLOYMENT.md` had recorded this and ADR-024 had made one of the four correctable. Neither was enough, and the reason is worth stating plainly: the documentation knew, and the product did not. A limitation an operator must read a checklist to avoid is a defect with a note attached.

It is also not a one-number fix. Setting the ATR floor to a sane 8 pips gives a 12 pip minimum stop against a 30 pip entry deviation - ratio 2.5, which ADR-024 classifies as an inert drift gate, so the SafetyManager would have vetoed every entry and the run would still have taken zero trades. The absolute spread cap would still have been a gold number behind that. The four are not independent and cannot be corrected independently.

So they are derived. The reference is the median ATR14 over up to 500 closed bars of the instrument's own history, and everything else is a percentage of it or of the minimum stop that follows from it. What an operator sets are percentages that mean the same thing on every symbol and every timeframe.

Median, not mean, and the choice is load-bearing: a single volatility spike in the sample would raise the floor and mute the strategy for the rest of the run, which is this same defect arriving by a different route. Samples that are non-finite or non-positive are discarded rather than counted as zero, because `CopyBuffer` returns unset values at the edge of available history and averaging those in biases the reference downward.

Expressing entry slippage as a percentage of the MINIMUM STOP rather than of the ATR is likewise not cosmetic. That ratio is exactly the worst-case realised-risk overshoot ADR-024 defines, so a derived deviation satisfies the drift bound by construction. It is re-checked after derivation regardless, because a bound that is assumed rather than evaluated is not a bound.

The defaults reproduce the shipped gold numbers rather than quietly replacing them. A floor of 60% and a ceiling of 600% applied to a 133.33 reference give exactly 80 and 800, preserving the 10:1 band shape that shipped - which keeps the ceiling what it always was, a guard against extreme bars rather than a routine filter. An entry slippage of 25% of the minimum stop gives exactly the shipped 30 points. Two derived values do move: exit slippage lands at 102 against the shipped 100 and the spread cap at 48 against 50. Both are in the safe direction - a more generous exit tolerance is more likely to fill a close, a tighter spread cap admits fewer expensive entries - and both are stated here rather than presented as neutral.

What this does NOT claim is that the derived numbers are correct for any instrument. They are derived rather than guessed, which is a different and lesser claim. The gold baseline they depart from is fifty trades at roughly 0.35 standard errors from zero, so "preserves the tested behaviour" is a statement about arithmetic, not about edge.

Calibration runs at the first bar where enough history exists, not in `OnInit`. Indicator history is not reliably available at initialisation, particularly in the Strategy Tester, and a calibration built on three bars would be worse than none. It retries on every subsequent bar until it succeeds, so a short history delays trading rather than permanently disabling it. Until it succeeds the entry drift-bound flag stays false and the SafetyManager vetoes new entries, so the window before the first calibration fails closed rather than trading on thresholds nobody verified.

Every component is updated through a checked setter rather than a re-`Initialize`. Re-initialising `PositionManager` would clear the per-position state array and the R ledger, abandoning live positions to the broker; re-initialising `ExecutionEngine` would reset the duplicate signal-bar guard. If any setter refuses a derived value the calibration is abandoned whole, because a configuration where three thresholds moved and one kept its gold default is worse than one that did not calibrate at all.

`InpAutoTuneForSymbol` turns the whole thing off and restores the manual values exactly. One consequence worth stating for anyone optimising: with auto-tune on, the four manual inputs are ignored, so sweeping them does nothing. Their labels say so. The percentages are the knobs to sweep instead.

Separately and with no behavioural effect, all 52 inputs now carry plain-language labels. MT5 renders an input's trailing comment as its name in the dialog, so this needed no renaming: variable names, `.set` files and existing optimisation configs are untouched.

## ADR-027 - A Second Strategy Ships As A Second EA, Not A Second Mode

CandleFlow is a single-factor rule: the direction of the closed candle decides the trade, there is no take-profit, and the stop re-anchors to the far wick of each later candle. Nothing about it resembles ScoreBot_v3's scored, gated, partial-then-trail lifecycle. The choice was whether to add it as a mode inside XSpark.mq5 or as a separate Expert Advisor over the same components.

It is a separate EA, `XSparkFlow.mq5`, for three reasons.

The first is blast radius. XSpark.mq5 is a live-money entry path with 52 inputs and a lifecycle that has been reasoned about one branch at a time. Adding a strategy selector to it means every existing input acquires a second meaning - "applies only in mode A" - and every existing branch acquires a second reader. The units that would have to be re-verified are the ones that are hardest to test and most expensive to get wrong.

The second is that both must be able to run at once. Two EAs on two charts with two Magic Numbers is the arrangement the components were already built for: `PositionManager` reconciles on symbol and Magic, the state store is keyed on account, symbol and Magic, and `XSparkDirectionIsUnopposed` and the flatten campaign both filter the same way. A mode switch inside one EA would have made running both simultaneously a new feature rather than an existing property.

The third is that it keeps the modularity claim honest. If a strategy can only be swapped by editing the EA that hosts the incumbent, the boundary is a convention rather than an interface. CandleFlow reuses SafetyManager, RiskManager, PositionSizer, AccountExposure, ExecutionEngine, PositionManager, StateStore, IndicatorCache, MarketState, SymbolMath, AutoTune and Dashboard without modifying any of their behaviour, which is the actual test of whether the separation holds.

Two shared components gained a capability rather than a change.

`ExecutionEngine` now accepts a plan with no target. The signal is `dynamic_rr <= 0`, which no ScoreBot_v3 plan can produce, and the effect is that the order is sent with `TP = 0` and the reward-ratio bounds are skipped - there is no target for them to bound. Every other execution-time control is untouched, and this is worth being explicit about because "skips a validation" reads like a weakened control: the stop must still be on the protective side of the close-side quote, entry drift is still bounded by the deviation gate, the volume is still re-derived from the refreshed quote and the broker-adjusted stop, and margin and the account risk cap are still re-checked immediately before the send. The reward ratio bounds the *target*, and realised risk does not depend on it. A no-target plan that somehow arrives carrying a target price is refused rather than sent, because nothing in that path has validated that price.

`PositionManager.ManagePositions` gained a trailing mode and two anchor prices, all three defaulted so the existing call site and the existing behaviour are bit-for-bit unchanged. `XSPARK_TRAIL_CANDLE_ANCHOR` applies no partial close and no break-even step and ratchets the stop toward a caller-supplied anchor. The ratchet is one-way by construction - a candidate that is not tighter than the live stop is discarded - and a missing anchor leaves the broker stop exactly where it is, because a stop that cannot be tightened must stay put rather than disappear. The mode is passed per call rather than stored, so one PositionManager instance never holds another strategy's configuration.

The anchor is recomputed by the strategy, not by PositionManager. This keeps the rule in the strategy layer where it can be tested without a broker, and keeps PositionManager free of any knowledge of candles.

CandleFlow carries one control that is not in the user's rule. A stop is placed a buffer beyond the candle's wick, and the buffer does not bound the stop *distance*: a thin candle yields a thin stop, and a thin stop yields a large position for the same percentage risk. `InpMinStopATRMult` widens such a stop to a floor measured from the fill. Widening a stop always reduces the volume, so the floor cannot increase realised risk - it only prevents the size blow-up - and it is mandatory rather than optional because it is also the "smallest stop this configuration can produce" that every auto-tuned tolerance is derived against. An optional ceiling refuses an outsized candle rather than sizing it down to nothing; it is off by default.

`RiskManager` grades exposure by score and CandleFlow has no score. Rather than add a no-score path to a risk control, every CandleFlow signal presents the same fixed score and the EA sets all three risk tiers to the same percentage, so the tier lookup cannot change the answer. The risk percentage an operator sets is the one that is used.

CandleFlow does not reverse on an opposing candle. Every candle has a direction, so an opposing signal arrives constantly while a position is open; it is refused by the existing opposing-exposure check and the open trade exits on its trailing stop alone. Reversing would be a different strategy, and adding it as a default-on behaviour would mean the shipped rule is not the one described.

No profitability claim is made or implied. CandleFlow has not been backtested, forward-tested or traded, and it ships with trading disabled.

## ADR-028 - A Strategy's Settings Belong To That Strategy

Reported from the terminal: opening XSparkFlow's Inputs tab showed ScoreBot_v3's settings. The cause is not cosmetic and the fix is not a UI change.

MetaTrader applies a `.set` file by input IDENTIFIER. It does not record, or care, which Expert Advisor wrote the file. XSparkFlow shipped with 45 inputs, 37 of which were byte-identical in name to XSpark's, because the EA was written by starting from the existing one and deleting what did not apply. Loading any ScoreBot preset into XSparkFlow therefore applied 37 values silently: `InpEnableTrading`, `InpMaxRiskPct`, `InpMaxOpenTrades` - and `InpMagicNumber`.

That last one is the whole defect. Every separation between the two bots is keyed on the Magic Number: PositionManager reconciles on symbol plus Magic, the per-position state store is keyed on account, symbol and Magic, and the opposing-exposure check, the weekend close and the killswitch flatten all filter the same way. A preset that set XSparkFlow's Magic Number to 770331 would not have produced an error anywhere. It would have produced two Expert Advisors managing one set of positions, each trailing the other's stops, on a live account.

Three changes, in increasing order of how much they actually prevent.

Namespacing is the one that closes the hole. XSparkFlow's inputs now all carry an `InpFlow` prefix. MetaTrader ignores an identifier the target EA does not declare, so a ScoreBot preset loaded into XSparkFlow now changes nothing at all - not "warns", not "is discouraged": has no effect. XSpark keeps the bare `Inp` prefix, because `docs/INPUT_SETTINGS.md` promised existing `.set` identifiers would be preserved and every shipped preset depends on it. The cost is that the CandleFlow preset had to be rewritten; it had never been run, so nothing was lost.

A registry makes the collision detectable. Each strategy previously declared its own Magic Number default in its own header, which means no strategy could know what any other had claimed. `Core/StrategyIdentity.mqh` now owns all of them, and both EAs refuse to initialise on a number another shipped strategy claims. This catches the case namespacing cannot - an operator typing 770331 into XSparkFlow's Magic Number box by hand. An operator's own number, claimed by nobody, stays usable by any strategy, because running several instances of one strategy on different charts is the reason that input is exposed at all.

A CI check makes it a rule rather than a habit. `tools/check_ea_inputs.py` fails the build when any input identifier is declared by two EAs, when a declared input is never read by its own EA, when a Magic Number default does not come from the registry, or when an input default reads through a different strategy's constant. That last rule caught a real instance: XSparkFlow's entry tolerance defaulted to `XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS`, so retuning ScoreBot would have moved CandleFlow's default for reasons having nothing to do with CandleFlow. Both strategies now declare their own, numerically identical today and independent from here.

The check is source analysis and knows nothing about MQL5 semantics. It cannot prove an input is *meaningful*, only that something reads it - so the rule that an EA exposes only what its own code path uses stays a review obligation, with the checker catching the crude half.

One grouping change followed from the same review. XSparkFlow's ATR band sat under "Manual limits - only when auto-adapt is off", which was true but misleading: the band is read only by the volatility filter, which ships off. It now sits in a group with that filter, so an operator can see that turning the filter off makes both numbers inert.

What this does NOT do is make the two bots independent of each other. They still share an account, and `InpFlowMaxAccountRiskPct` is still measured across all open positions including the other bot's. That coupling is deliberate and is the one that should exist.
