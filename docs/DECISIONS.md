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

A persisted latch needs a deliberate way out, and it must not be the restart itself. `InpClearKillswitchLatch` is a dedicated input, default false, that clears the latch and re-anchors the peak with a CRITICAL log line recording that it happened. It acts only when there is a latch to clear — see the addendum below for why that qualifier had to be added. An input change alone does not clear it, so a routine parameter edit or a VPS reboot cannot silently reset the ruin stop.

On sizing: with the edge measured in `IMPROVEMENT_PLAN.md` - 36% win rate, 1.974 payoff, +0.0706 R per trade - the growth-optimal Kelly fraction is 3.58% of balance per trade, and expected log-growth crosses zero at about 7.2%. That second number is the one that matters and it is not intuitive: above it, a genuinely positive edge still shrinks the account, because compounding is multiplicative and a large loss requires a larger gain to undo. Risk per trade is therefore capped at `XSPARK_MAX_ALLOWED_RISK_PCT` = 10%, which leaves room to size past the optimum deliberately while refusing a fat-fingered entry that would previously have been accepted in silence - the risk inputs were checked only for positivity.

Defaults move to a flat 3.0% per tier with a 3.5% ceiling. Flat, because tier selection reads the session-weighted score, so identical evidence would size differently purely by hour of day, and a larger risk figure amplifies that distortion. The tier inputs remain separate so tiering can be reinstated deliberately.

The drawdown limits move with the risk, because they are not independent of it. At 3.5% per trade, nine consecutive full-stop losses reach 25% and five reach 15%. At the previous 8% total limit, 3.5% risk would have latched on the fifth loss - and the reference run already contained an eight-loss streak, which at a 64% loss rate is roughly the median longest run over fifty trades rather than a tail event. An 8% limit at this risk level would have converted ordinary variance into a permanent stop. Limits are now 25% total and 15% daily, validated so the daily limit is strictly below the total limit, since a daily limit at or above it can never bind.

`XSparkConsecutiveLossesToDrawdown` computes the tolerance and the EA prints it at startup for whatever values are configured, with a WARNING when the killswitch would latch in fewer than six losses. The relationship is logarithmic rather than linear - eight losses at 1% cost 7.73%, not 8% - and getting it wrong by one tells an operator the account survives a loss fewer or more than it does.

This change RAISES risk at the account owner's explicit request. The implication, stated plainly: at these settings a 25% account drawdown is an expected outcome of ordinary variance, not a malfunction, and the killswitch is calibrated to permit it rather than to prevent it. It is not martingale, grid, averaging-down or recovery sizing - risk remains a fixed percentage of balance and is not increased after a loss - so AGENTS.md rule 26 is not engaged. Nothing here establishes that the edge is real; the measured edge remains roughly 0.35 standard errors from zero on fifty trades, and Kelly sizing of an edge that does not exist loses money faster than conservative sizing of the same non-edge.

### Addendum: the clear input is a one-shot, because a forgotten checkbox is a restart

This ADR persisted the peak precisely so `OnInit` could not erase it, and then handed the clear input the power to erase it on every `OnInit` anyway.

`if(clear_killswitch_latch)` re-anchored the peak to live equity and wrote `tP` whether or not anything was latched. The clear is a plain boolean input the operator sets by hand and the CRITICAL log asks them to set back — which is to say it is exactly the thing that gets left on. MT5 reruns `OnInit` on an input change, a recompile, a chart-period change, a reattach and a terminal restart, so a forgotten `true` re-anchored the ruin stop on every one of them.

The consequence is the ADR's own failure mode with a different trigger. Peak 10,000, equity falls to 8,000, operator changes the chart period: the peak becomes 8,000 and the drawdown reads 0%. Touch the chart again at 7,000 and it re-anchors again. The killswitch can never fire, because the measurement keeps restarting from the bottom of whatever hole the account is in. The original text of this ADR describes that as "the easiest piece of state in the system to erase"; persisting it closed the restart door and left this one open.

So the clear only acts when there is a latch to act on. With nothing latched the persisted peak stands untouched and a WARN says the input is still armed, which also turns a silent mistake into a visible one. Clearing a real latch is unchanged: peak re-anchored on purpose, latch dropped, CRITICAL recorded.

The decision lives in `XSparkResolveKillswitchRestore`, a pure function, so all six branches are covered by the portable suite without a terminal — including the operator sequence itself: clear a real latch, then reattach four times while the account falls another 2,000, and assert the peak does not move. Reverting the rule to the old unconditional clear fails three of those assertions, which is how the regression is known to be caught rather than merely described.

This is shared code, so it fixes ScoreBot and CandleFlow together.

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

## ADR-029 - CandleFlow's Trailing Stop Is A Stack, And Its Floor Is A Safety Control

CandleFlow has no take-profit. The trailing stop is not a feature of the strategy, it is the strategy's only exit, and the version that shipped was one line of arithmetic: the far wick of the last closed candle, plus a buffer, ratcheted one way. Three things were wrong with that for a strategy carrying the whole exit on it.

The first is a defect rather than a design limit. `InpFlowMinStopATRMult` bounded the stop distance at ENTRY only; the trail branch validated against the broker's minimum stop level and nothing else. A doji or a narrow inside candle printing near the highs therefore placed the stop at roughly `price - 0.10 x ATR`, which on XAUUSD M30 is about thirty points - the spread, plus ordinary noise. The position was then removed by a tick while the move it was riding was still intact, and the journal would record it as a normal trailing-stop exit. A trailing stop that can sit inside the spread is a delayed market order.

So the floor is now a property of the trail, not of the entry, and it is the one layer that ships on. Widening a candidate away from the market can only ever reduce the chance of being stopped, and the one-way ratchet still refuses anything looser than the live stop, so the floor cannot give back protection the trade has already banked. It is checked in both directions and against a candidate that has landed through the market entirely, which the tiered trail can produce when the peak is far above the current quote.

The second is that anchoring to one candle throws away the room earlier candles earned. The answer chosen here is a chandelier: trail from the best price the position itself has seen, measured on closed candles, wicks included, because that is the price the market actually reached. That peak is per-position state and is persisted, because a terminal restart mid-trade that reset the peak to the current candle would hand back the entire trail in one pass.

It is deliberately NOT the `mfe_price` PositionManager already records. That one is sampled on the exit-side quote at every management pass, so it moves intrabar; a trail built on it would depend on when a tick happened to arrive, which is not reproducible in the Tester and not what "on candle close" means. The peak also advances at most once per candle, keyed on the candle's timestamp, so a tick storm inside one candle cannot ratchet it repeatedly.

The third is that a fixed trail is profit-blind: identical at +0.2R and +8R. Tiering shrinks the chandelier multiple linearly between two R marks, and a breakeven lock pins the stop once the trade has earned a configurable amount. Both key off maturity measured FROM THE PEAK rather than from the live price, and that choice is load-bearing: peak-based maturity is monotonic, so a tier once reached is never given back and a retracement can never loosen the trail. Current-price maturity would let a trade oscillate across a tier boundary and widen its own stop, which is the failure that turns a trailing stop into no stop.

The interpolation is linear rather than stepped for the same reason a tier boundary is a bad place to be: a step means a small price change moves the stop a long way, and every position sitting near that boundary moves together.

The layers compose by taking the most protective candidate rather than by precedence. Precedence would mean choosing, in advance and for every market, whether candle structure or volatility should win - a choice there is no evidence to make. "Whichever is tighter" needs no such claim and cannot be wrong in the direction that matters, since a layer proposing nothing simply does not win.

Everything except the floor ships OFF. CandleFlow's documented rule is the plain candle trail, and turning three new layers on by default would mean the shipped behaviour is not the one the documentation describes. `presets/xauusd-m30-candleflow-advanced.set` carries the whole stack turned on, with the reasoning for each number written next to it.

A refused configuration blocks new entries rather than being ignored. For a strategy whose only exit is this stop, a trailing setting the EA cannot honour is not something to proceed past - and positions already open keep trailing on the last accepted plan, because the alternative is abandoning a live position to fix a configuration error.

Mechanically, the three positional trailing arguments on `ManagePositions` became one `XSparkTrailPlan` set immediately before each call. The anchors, the closed-candle extremes and the tuning all change together on a candle boundary, and a caller that set some and forgot the rest would trail against a mix of two different candles. ScoreBot_v3's ten-argument call site is unchanged and keeps the default plan, which is its existing ATR-after-partial behaviour.

The arithmetic lives in `Trade/TrailingStop.mqh` rather than in the strategy, because a trailing stop is a property of an open position and PositionManager is what owns open positions. Putting it in the Strategy layer would have forced PositionManager to depend on a strategy header to trail a position it already owns.

No profitability claim is made. The defaults in the advanced preset were chosen for plausibility and have not been measured against anything.

## ADR-030 - The Inputs Tab Is The User Interface, And Defaults Are A Recommendation

Two changes to CandleFlow that are really one change: the settings now say what they do in words a non-trader has, and they arrive set to the configuration we would actually recommend.

### The labels

MetaTrader renders an input's trailing comment as its name in the Inputs tab. There is no tooltip, no help text and no second screen. That comment is the entire user interface, and it was written in the vocabulary of the code rather than of the person reading it: "x average range", "x initial risk", "strategy points", "drawdown", "spread", "deviation". Every one of those is a term you have to already know to act on.

They are now written for someone who does not. ATR became "typical candle size", which is what ATR14 approximately is and which makes "0.10 x typical candle size" mean something on sight. R became "the amount risked", with the group header defining it once as the distance from entry to the first stop. Spread became "buy/sell gap", defined in a comment above the group that uses it. Deviation became "price drift allowed". The identifiers did not change, because presets address inputs by identifier and renaming them would break every saved file again.

Three group headers now carry a short paragraph above them - what the bot does, what the trailing stop is doing, which settings are inert when a switch is off. MetaTrader does not render those, but the file is also read by people, and the person most likely to read it is the one deciding whether a number is safe to change.

The 63-character limit is enforced rather than remembered. `tools/check_ea_inputs.py` now fails the build on an input with no label or with one MetaTrader would truncate, which is the difference between a convention and a rule. A truncated label is worse than a short one, because it reads as a complete sentence that says something slightly wrong.

### The defaults

ADR-029 shipped the chandelier, the tiering and the breakeven lock switched OFF, on the reasoning that turning three new layers on by default would mean the shipped behaviour was not the one the documentation described. That was the right call for one commit and the wrong one to leave in place.

The argument against it is simple: a default that nobody would recommend is not a default, it is a homework assignment. Every operator who installed CandleFlow would have had to find the advanced preset, know to load it, and understand seven settings before the strategy did what it was built to do - and the ones who did not would have run the version with the known weakness, which is the version we would tell them not to run. Documentation is cheaper to change than a user's outcome.

So the stack is on, and the documentation now describes that. The numbers live in `Trade/TrailingStop.mqh` as `XSPARK_TRAIL_DEFAULT_*`, which is simultaneously what the EA's inputs read and what the test suite validates. A default that failed `XSparkValidateTrailTuning` would block every entry on a fresh chart in total silence; it now cannot reach a chart, because the check that would catch it runs against the same constants the inputs use rather than against a copy.

`InpFlowUseWeekendClose` also defaults on. A position held on a trailing stop with no target carries the weekend gap in full, and the stop cannot act across it.

What did NOT change is anything that decides whether to trade. The body filter stays off and the volatility gate stays off, because the entry rule is the thing the strategy is named for and quietly adding filters to it would make the shipped bot a different one from the documented bot. That is the distinction ADR-029 was reaching for, applied where it actually holds: how an open trade is protected is an implementation of the rule, while which candles count IS the rule.

### The preset that replaced the old one

`xauusd-m30-candleflow-advanced.set` had nothing left to say once its contents became the defaults, so it is gone. In its place is `xauusd-m30-candleflow-plain-trail.set`, which turns every layer off and leaves only the candle trail.

That is the more useful file. It is the baseline the full configuration has to beat in the Tester, and the honest instruction attached to it is that if the stack does not beat the plain trail over the same period, the stack should be turned off rather than tuned. A preset that lets you disprove the default is worth more than one that repeats it.

No profitability claim is made. The defaults are plausible, not measured, and neither configuration has been backtested.

## ADR-031 - CandleFlow Banks Profit In Steps, And The Steps Only Ever Remove Exposure

CandleFlow had one exit. The trailing stop was the whole thing, and a trailing stop can only act after the price has already come back — by the full trail distance, which on the shipped 3.0 ATR chandelier is a long way. The consequence is structural rather than a tuning error: a trade that runs a long way and turns around is booked well below the best price it saw, and the equity curve rises and then hands a large part of it back. An operator running it reported exactly that.

Three things could have been done about it. Tightening the trail is the obvious one and the wrong one: it buys back the give-back by being stopped out of the moves that were still intact, which is the failure ADR-029's floor exists to prevent. A single hard take-profit is the second, and it caps the one part of the trade the strategy exists to hold. The third is to take money off the table on the way, in steps, and leave the rest running — which costs the give-back only on the part still open and leaves the open-ended upside untouched.

### The ladder is a property of the position, not of the rule

`Trade/ProfitLadder.mqh` sits beside `Trade/TrailingStop.mqh` for the same reason that one is not in `Strategy/`: taking profit in steps is something that happens to an open position, and `PositionManager` is what owns open positions. `CandleFlow.mqh` never sees the ladder. It gained exactly one field, a reward ratio for the optional hard target, because publishing a reward ratio on a signal is what `StrategyInterface` is already for.

Every step is a multiple of the distance from the entry to that position's **first** stop, and every share is a percentage of the volume the position **opened** with. Percentages of a shrinking remainder were the alternative and are worse in a way that is not obvious until it bites: they bank a different share of the trade at every step than the one configured, and they never reach zero, so the ladder cannot be reasoned about from the Inputs tab.

### Removing exposure is not weakening a risk control

AGENTS.md rule 5 says never silently weaken a risk control, and rule 26 bars recovery sizing. A partial take-profit does neither, and it is worth saying why rather than asserting it. A step only ever closes volume the position already has. It cannot add, cannot re-enter, and cannot size from a previous outcome. The maximum loss of a trade after a step has fired is strictly smaller than it was before. The direction of the change is monotonic and it points the safe way, which is the reason this can ship on by default while a control that could ever increase exposure could not.

What it does change is the *distribution* of outcomes, and that is a strategy question rather than a safety one. It is also the question the operator asked.

### The steps can never close the whole position

At most 90% of a trade may be banked across every step, and a configuration asking for more is refused at startup. This is a real invariant rather than a convenience: the residual is what keeps the trailing stop, the break-even lock and the weekend close in charge of the trade, and it means the only broker operation the ladder can ever cause is a partial close. No per-ticket full-close path was added, and `FlattenManagedExposure` — which loops every position under the Magic Number and latches a campaign shared with the killswitch — is not reachable from here.

One step fires per management pass. Each is its own broker operation, and a pass that sent three would size the second and third from a volume the first had not been confirmed to have changed. A candle that jumps through every level banks one step per pass instead, at whatever the market is then, which is at or beyond the level either way because a trigger is only reached from the profitable side.

### Profit first, then protection, on the same pass

Banking a step runs a reconciliation, and reconciliation compacts the state array and can rebind a broker ticket. The first version of this ended the pass there and let the trail resume on the next tick. That is safe and it is wrong: the tick that made the trade enough progress to bank a step is the tick its stop most wants ratcheting on, and under the Strategy Tester's open-prices modelling "the next tick" is a whole candle later. The step now re-resolves the state row by identifier, re-selects the position, re-reads the live take-profit, and falls through to the trail. A failed re-selection leaves the position alone entirely, because a failed `PositionSelectByTicket` does not clear the terminal's previous selection and the ratchet would otherwise compare against a stranger's stop.

### Which steps were banked is persisted, as a bitmask

A step re-fired after a restart closes the same share of the trade twice. A step forgotten leaves money the operator configured to bank sitting on the trailing stop. Both are the failure `partial_done` was introduced for, and the fix is the same: record it before anything else can fail, and persist it.

It is a bitmask rather than a count because a step that could not be closed does not block the steps above it — so the banked set is not necessarily a leading run. A stored value naming a step this build does not have is read as "nothing banked", which is only safe because every step is re-tested against the live price before it can fire.

That new key exposed an older defect. `PersistState` wrote the two excursion keys and `ClearPersistedState` never deleted them, so every closed position left two terminal global variables behind until the once-per-session orphan sweep happened to run. They are deleted now, and the three key lists are compared **as source** by `tools/test_portable_logic.py`: the portable storage doubles copy whole structs, so a key missing from one list is invisible to any behavioural fixture, which is precisely how the omission survived. The build now fails on it.

### The hard target ships off, and that is a recommendation

`InpFlowFinalTargetR` puts a real broker-side take-profit on the remainder, and it defaults to zero. ADR-030 argued that a default nobody would recommend is a homework assignment, and this is not that: a fixed cap on the one part of the trade deliberately left running is the opposite of what the ladder above it is for. It exists for an operator who wants an exit that fills while the terminal is closed, and it is theirs to switch on.

It is also the only setting in the group that reaches the entry path. `ExecutionEngine` already accepted a positive reward ratio; what changed is that XSparkFlow now hands it a real band instead of the placeholder pair. The band is 0.95× to 1.25× the requested distance and it is asymmetric on purpose, because broker stop-level validation only ever pushes a take-profit further from the market: the lower edge absorbs price rounding, the upper edge asks whether this is still the trade that was intended. Equal bounds would have been the natural-looking choice and would have rejected essentially every entry, because the reward-ratio comparison uses a 1e-7 epsilon while price normalisation moves the realised ratio by thousands of times that.

That refusal is now also made at planning time. The engine marks a signal bar consumed before its first send attempt, so a target it would reject discards the candle entirely; refusing it earlier costs the same trade and leaves a reason on the panel instead of a warning in the journal.

With the target at zero the send path is byte-for-byte what it was, and the defensive refusal that guarantees it — "a no-target plan produced a take-profit price" — is untouched.

### The baseline preset had to change or it would have stopped being a baseline

A `.set` file applies only the identifiers it lists. `xauusd-m30-candleflow-plain-trail.set` exists to be the honest comparison for the trailing stack, and left alone it would have silently become "plain trail plus ladder" the moment the ladder defaulted on. It now writes all seven take-profit settings out as explicit zeros. The same applies to any file an operator saved before this change: loading it restores their old trail settings and leaves the ladder at its new defaults, which is worth knowing before a Tester run is read as a comparison.

### What is still unmeasured

The step distances and shares are plausible, not measured, in exactly the sense ADR-029 used the phrase. No backtest, forward test or live result is recorded in this repository, including the one the operator described. The defaults are a recommendation for the failure that was reported; whether they are the right numbers is a question for the Strategy Tester, and the way to ask it is the same A/B the trailing stack already has — the two presets, the same period, both directions of the comparison run rather than assumed.

## ADR-032 - A Take-Profit Step Is A Budget, Not A Share, And A Rejected One Backs Off

ADR-031 shipped the ladder as "close 30% of the opening size at this distance". An adversarial review of that commit found three defects, and two of them turned out to be the same defect wearing different clothes.

### A confirmed close that was never recorded

The window is small and it is real: the broker confirms the partial, and the terminal dies before the progress is written. On restart the record still says nothing was banked, the price is still past the trigger, and a ladder that closes a fixed share takes another 30% off a position that has already given up its first 30%.

The fix is to stop expressing a step as a share to close and start expressing it as a budget: *bring this position down to 70% of what it opened with*. In the ordinary case that is the same order, to the lot. In the crash case the position is already at 70%, the subtraction yields nothing, and the step is a no-op that heals itself. Idempotence is not a property that had to be added on top; it is what the arithmetic already does once it is written the other way round.

The same change removed the third defect for free. A step whose share rounded below the broker's minimum volume used to be lost for the rest of the trade — and at a 0.01 minimum lot a 30% share of anything under about 0.04 lots rounds to nothing, which is an ordinary retail position rather than an edge case. Under a budget, the next step closes its own share and the skipped one together, because it is measured against the live volume rather than against what the previous step was supposed to have done.

The persisted progress value is therefore no longer load-bearing for safety. It records how far up the ladder the trade has been so the steps are not re-offered; losing it costs accuracy, never a second close. It is a high-water R multiple rather than the bitmask ADR-031 used, because the steps are strictly ascending and one number then says which of them are behind the trade. An unreadable value is read as *every step is already behind us*, which makes the ladder inert rather than replaying it — a module that cannot trust its own record of what it has done to a live position must not cause another broker operation on the strength of it.

### One order per pass, but the furthest step

The scan now runs from the top of the ladder down and takes the furthest step the price has reached, rather than the nearest unbanked one. Because a step's budget already contains every share below it, a candle that gaps through two levels banks both shares in one order at the price the market is actually at — instead of banking the lower share now and leaving the upper one to a later pass, at a price that may have retraced in the meantime. It is still exactly one broker operation per management pass, which is the property that mattered.

### A rejected close is not retried on the next tick

A crossed trigger stays crossed. A broker that refuses the partial therefore used to get one `PositionClosePartial` per tick for the rest of the trade, which is the order-spam failure AGENTS.md rules 18 and 19 are about, arriving through an exit path rather than an entry one. A step now waits thirty seconds after a rejection and switches itself off for that position after five consecutive ones. Nothing is recorded as banked by a rejection, the trailing stop keeps running throughout, and a restart clears the latch because it rebuilds every record from broker truth.

### When the bot no longer knows what it banked

If a close is confirmed and the managed record for a position that is still live cannot be found afterwards, XSpark has caused a broker operation it cannot account for. That is the ambiguous state rule 24 exists for, and it now raises the existing state-recovery latch: new entries stop, open positions stay managed, the panel says so.

The discrimination is the whole value of it. A record that vanished because the position *closed* is a consistent outcome — reconciliation pruned it, the closure was logged, its state was cleared — and latching there would block trading on every ordinary stop-out that happened to coincide with a step. The check is therefore "is the position still live", not "did the lookup fail".

### What this costs, and the number that is not in the tests

Taking profit in steps does not raise expectancy; it moves money out of the right tail and into the middle. On a trade that runs to 6R and trails out at 3.5R the shipped ladder returns 2.55R instead of 3.50R. On a trade that runs to 3.5R and hands it all back to the break-even lock it returns 1.53R instead of 0.10R. The second shape is the one that was reported, and whether the change is net positive depends entirely on the give-back distribution in the operator's own data.

`presets/xauusd-m30-candleflow-no-targets.set` exists so that can be measured in one comparison: it is the shipped preset with the four take-profit settings zeroed and nothing else changed. The plain-trail preset is not that baseline — it also strips the chandelier, the tightening and the break-even lock, so comparing against it measures four changes at once.

One caveat belongs with it rather than buried in the code. The ladder triggers on a tick-resolution exit-side quote while the trail's peak advances only on closed candles, so under "Open prices only" modelling a spike that reaches a level inside a bar and closes back below it never banks anything. Low-resolution modelling systematically understates the ladder, and a comparison run that way measures the modelling rather than the change.

### Addendum: the shipped split is 40/30, not 30/30

The operator who reported the give-back trades roughly 0.03 to 0.10 lots and asked for the defaults weighted toward banking rather than toward running. Both point the same way, which is why the first step is the larger one.

The trade-off argument is the ordinary one: the earlier share is the share a retrace cannot reach, so moving weight into it protects more of the reported failure and costs more of the right tail. The lot-size argument is arithmetic and would have been invisible without asking. At a 0.01 minimum lot a 30% share of 0.03 lots normalises down to zero and the first step is skipped entirely; 40% normalises to 0.01 and fires. The budget model means the skipped share is not lost — the second step takes it — but a step that never fires is still a step the operator configured and did not get.

Shares are normalised down throughout, so a small position banks slightly less than configured and never more. The shortfall stays open under the trailing stop, which is the safe direction to round in.

## ADR-033 - CandleFlow Exposes Nine Settings, Because The Other Sixty-Four Were Not Choices

XSparkFlow shipped with 73 inputs for a rule that is "the candle closed up, so buy". The operator's complaint was that this is too complicated, and that a strategy this simple has no business adapting to markets. Both halves are right, but they are right for different reasons, and the second one is easy to act on wrongly.

### The test an input has to pass

Does the operator know something the code does not?

They know their account, and how much of it they are willing to lose. They have an opinion about whether to take money off the table on the way or let a trade run. Those are choices, and they survive.

Nobody knows what to allow for entry slippage as a percentage of the smallest stop the configuration can produce. Nobody chooses to tighten a trailing stop linearly from 3.0 average ranges to 1.5 between 1 and 4 times the amount risked. Those numbers could only ever be copied from their own defaults, and a number that can only be copied is not a choice - it is a way to get it wrong. Sixty-four of them failed that test.

### "No need to adapt to markets" does not mean "stop measuring the market"

This is the part that would have been easy to get wrong. Freezing a spread cap or a slippage allowance as an absolute number of points is precisely what rules 12, 13 and 15 forbid, and what ADR-026 exists to prevent: a gold-derived tolerance applied to an FX pair is wrong by two orders of magnitude.

What the operator was objecting to was never the measuring. It was being asked about it. So the per-instrument derivation stays, and every knob on it is gone: the percentages that shape it are constants, the switch that disabled it is gone, and the manual-override path is gone with it. That path turned out to be worse than unused - XSparkFlow never established the entry-drift bound outside calibration, so an operator who switched auto-tune off got an EA that could not trade at all. Removing it removed a trap.

Every distance the rule itself uses was already a multiple of the instrument's own average range, so freezing those multiples leaves the adaptation completely intact. The thing that must never be frozen is a distance; a multiple is safe.

### Fourteen numbers became two questions

The trailing stop was seven inputs and the take-profit ladder was seven more. Each set describes one behaviour, and each was, in its own documentation's words, chosen for plausibility rather than measured. They are now two dropdowns - how much room to give a trade, and whether to bank profit as it runs - and each choice is a table that the test suite proves is internally consistent.

That is simpler, and it is also safer in a way that is worth stating plainly. Before, an operator could type a tightened multiple wider than the base one, or a ladder with a hole in it, and get an EA that validated the configuration, refused it, and blocked every entry. The validators still run - they now guard against a bad edit to a preset table reaching a live chart - but no combination reachable from the Inputs tab can fail them. The failure mode was removed rather than defended against.

`docs/OPTIMIZATION.md` is the other half of this argument. It records a 1,024-pass sweep in which only two passes would have initialised at all, because the ranges violated cross-parameter constraints that looked sensible one at a time. Four such constraints are named there. Collapsing free numbers into named choices removes the whole class: a dropdown cannot be swept outside its own domain.

### Removing a switch from a safety control strengthens it

The spread filter, the broker's minimum-stop-distance check, the free-margin check, the stale-quote gate and the weekend close each had a boolean that turned them off. None of those booleans had a defensible "off" setting. They are gone, and the controls are now mandatory. Rule 5 says never silently weaken a risk control; this is the opposite, and it is worth being explicit that deleting a switch and deleting a control are not the same act.

The total-drawdown killswitch was folded the same way in the first version of this reduction - the boolean gone, zero on the percentage meaning off. That one was wrong, and the addendum at the end of this ADR says why it was put back.

### Freezing a number forces you to justify it, and one did not survive that

The entry-slippage share was 25%. The derivation makes the permitted drift exactly that percentage of the smallest stop, and `XSparkEntryDriftBound` warns above 20% because a fill that drifts that far has spent a fifth of its own stop before the trade starts. So every calibrated start logged a warning - which is how a warning stops being read.

While it was an input that was arguably the operator's problem. As a constant it is ours, and the answer is to tighten it to 20. Verified against the production derivation rather than by reading: at a reference range of 133 points, 25% gives a ratio of 0.25 and a warning on every start; 20% gives 0.20 and a clean one.

### The preset files are gone

All three CandleFlow `.set` files were deleted rather than trimmed. With nine settings, seven of which are their own defaults, a file that writes them down is the complexity being removed rather than a cure for it - and MetaTrader silently ignores keys an EA no longer declares, so a trimmed file would have looked like it was configuring something while doing nothing.

The two comparisons those files existed for are now one dropdown change each: profit taking Balanced against Off, and the trail Balanced against Candle only.

### What this costs

An operator who wants a trail between Balanced and Tight can no longer have one. That is a real loss and it is the intended trade: the space between two tested configurations is not a place anyone had information to aim at, and every point in it was also a point where the pair of cross-parameter constraints could be violated. If a future measurement says a fourth style is worth having, it is added at the end of the enum - never in the middle, because MetaTrader stores an enum input as its integer and renumbering would silently reinterpret every saved file.

Nothing here has been compiled or backtested. The numbers behind each style are the ones that shipped, unchanged except for the entry-slippage tightening above, and they remain plausible rather than measured.

### Addendum: the weekend close is read from the instrument, not typed in

The first version of this reduction froze the Friday close at 20:00 for every symbol, which replaced an input the operator could get right with a constant that is wrong on most instruments. It is hours early on a market that trades until 22:00, and it is meaningless on one that never closes — a position flattened every Friday evening for a gap that does not exist.

That is rule 15 exactly: the gold answer applied to metals, indices and crypto alike. Freezing a number is only legitimate when there is one right answer; when the right answer is a property of the instrument, the instrument is what should be asked.

So it is now derived. `SymbolInfoSessionTrade` gives the symbol's own Friday sessions, the bot flattens two hours before the last one ends, and a symbol reporting a Saturday or Sunday session has the weekend close switched off entirely. The terminal call lives in the EA and the decision lives in a pure function in `Strategy/CandleFlow.mqh`, which is what lets every branch — including the instruments this repository has never run on — be tested without a trade server.

An unreadable session falls back to the old 20:00 and logs that it did. Closing early costs a few hours of a market that is about to shut; closing late costs the gap, and the stop cannot act across it.

One detail worth recording because it is invisible from the call site: `PositionManager::ShouldWeekendClose` bounds-checks nothing, so an hour above 23 would silently never fire on a Friday. The derivation therefore validates its own output and falls back rather than passing a value that would disable the control without saying so.

### Addendum: the killswitch keeps its own switch, because off is a state you return from

Folding the killswitch's boolean into its percentage looked like the same move as deleting the spread filter's switch. It is not, and the difference is what the operator does next.

The controls whose switches were deleted have no defensible "off". The killswitch does: a year-long backtest. It closes the account out partway through a losing stretch and leaves the rest of the period untraded, so an operator judging a full year on the Strategy Tester switches it off, sees the whole equity curve, and switches it back on for live trading. That is a round trip, and it is the normal way this bot gets evaluated.

A percentage where zero means off cannot make that round trip without losing something. Switching off overwrites the level, so switching back on means retyping it - a level that has now never been validated against anything, chosen from memory, on the way to a live account. One setting that reads as one thing is really two states and a number the operator has to carry between them.

So there are two settings again: `InpFlowUseTotalDDKillSwitch` says whether the control runs, `InpFlowMaxTotalDDPct` says at what level, and the level is required to be a usable level even while the switch is off. Turning the switch back on cannot reveal a configuration nobody checked. Off is expressed once, by the switch, and the group is named so the Inputs tab says which setting the switch makes inert.

Two things follow that are worth stating because neither is obvious from the call site.

Switching the killswitch off does not clear a latch. The enable flag guards the *setting* of the latch; the restore from persisted state is unconditional, and so is the entry block the latch produces. That is deliberate - a latch records that equity really did fall that far, which is a fact about the account rather than about the setting - but it used to be silent, and an operator whose emergency stop reads "off" staring at an EA that will not enter deserves a line saying so. `SafetyManager::Initialize` now logs that case as CRITICAL and names the setting that clears it. On the Strategy Tester the question does not arise: the terminal's global variables are emulated per run, so a test starts with no latch to restore.

The daily loss limit is deliberately not given the same switch. It resets at each broker day rather than latching for the run, so it dents a year-long equity curve without truncating it, and unlike the killswitch it has no "off" an operator returns from. It stays mandatory.
