# XSpark Agent Instructions

XSpark is a live-money MetaTrader 5 Expert Advisor. Mistakes can cause real financial loss, so safety-critical code in this repository must be treated differently from ordinary application code.

## System Identity

- XSpark is intended to run as a native MT5 Expert Advisor on an Exness MT5 account.
- The production runtime is MT5/MQL5 unless a future requirement explicitly says otherwise.
- Reliability, capital protection, deterministic behavior, testability, maintainability, observability, and low operational complexity are the priorities.
- Profitability is not an acceptance criterion for infrastructure work.

## Engineering Rules

1. Primary production language is MQL5.
2. Never introduce another runtime or external dependency without a clear requirement.
3. Never modify unrelated functionality while implementing a task.
4. Prefer small, reviewable changes over large rewrites.
5. Never silently weaken or remove a risk control.
6. Strategy code must never execute broker orders directly.
7. Strategies produce signals only.
8. Every order must pass through the RiskManager and ExecutionEngine.
9. SafetyManager has authority to prevent all new trading.
10. Safety rules override strategy rules.
11. Every XSpark-managed position must use an explicit Magic Number.
12. Never assume pip size, point size, tick value, lot step, minimum volume, maximum volume, stop level, filling mode, or other instrument characteristics.
13. Retrieve instrument specifications dynamically from MT5.
14. Normalize price and volume correctly for each symbol.
15. Never assume EURUSD-specific behavior applies to metals, JPY pairs, indices, crypto, or other instruments.
16. Every broker operation must inspect and log the actual trade-server result.
17. Do not treat a successful local function return as proof that an order was executed.
18. Prevent duplicate orders caused by repeated ticks or repeated signals.
19. A single logical trading signal must not unintentionally produce multiple entries.
20. Do not trust RAM-only state for important position information.
21. On initialization/restart, reconcile XSpark state against actual MT5 positions and orders.
22. Existing broker-side positions are the source of truth for live exposure.
23. Protective risk controls should fail closed.
24. When an ambiguous or unsafe state is detected, prevent new entries rather than guessing.
25. Never hardcode credentials, account numbers, passwords, API keys, or secrets.
26. No martingale, grid escalation, averaging down, recovery sizing, or unlimited exposure logic may be introduced unless the user explicitly requests it and the risk implications are documented.
27. No strategy may bypass maximum account-level risk limits.
28. New features must preserve backtestability whenever reasonably possible.
29. Avoid using functions during Strategy Tester operation that are unsupported by MT5 testing unless they are safely abstracted or disabled.
30. Code should compile with zero errors before being considered complete.
31. Warnings should also be investigated rather than ignored.
32. If MetaEditor/compiler is unavailable in the Codex environment, explicitly state that compilation was not performed. Never claim compilation success without actually compiling.
32a. `tools/check_ea_call_arity.py` runs in CI and checks that every EA call into a shared component fits that component's signature. It exists because XSparkICT.mq5 shipped two calls that did not, and every other static check in the repository passed on it. Passing this check is not compilation and must never be reported as such: it counts arguments, not types.
33. Never fabricate test results, backtest results, compiler results, performance numbers, or profitability.
34. Profitability is not an acceptance criterion for infrastructure code.
35. Maintain documentation when architectural behavior changes.
36. Prefer clarity over cleverness.
37. Comments should explain why, not narrate obvious code.
38. Keep functions focused.
39. Avoid giant monolithic `.mq5` files.
40. Preserve separation between market state, strategy/signals, risk, position sizing, execution, position management, safety, and logging.
41. Each strategy's Expert Advisor must expose only the inputs its own code path reads. An input is never carried into a new EA because another strategy has one.
42. No input identifier may be declared by more than one Expert Advisor. Give each EA its own input prefix.
43. An input default must never read through another strategy's constant. Declare the strategy's own.
44. Every strategy's Magic Number default belongs in `Core/StrategyIdentity.mqh`, and every EA must refuse to start on a Magic Number another shipped strategy claims.
45. Inputs that only take effect when a switch is on belong in a group with that switch, and the group name must say so.
46. Every input needs a display label a non-trader can act on, within MetaTrader's 63-character limit. Name the thing, not the jargon: "typical candle size", not "ATR"; "the amount risked", not "R"; "buy/sell gap", not "spread".
47. Shipped defaults must be the configuration you would actually recommend, and must pass their own validation. A default that blocks trading or needs editing before first use is a broken default.
48. An input exists only if the operator knows something the code does not. A number that can only be copied from its default is not a choice, it is a way to get it wrong; make it a constant, derive it from the instrument, or fold it into a named choice.
49. Where several numbers describe one behaviour, expose the behaviour rather than the numbers. A named choice whose every value is a tested, internally consistent configuration cannot be misconfigured; a set of free numbers with cross-parameter constraints will be.
50. An enum used as an input is a dropdown: every member needs a label under the same 63-character limit, and its ordinal is a wire format. Add members at the end and never renumber one, because MetaTrader stores the integer and a saved `.set` would silently mean something else.

Rules 41 to 46, and 50, are enforced by `tools/check_ea_inputs.py`, which runs in CI. Rule 32a is enforced by `tools/check_ea_call_arity.py`, alongside it.

## Change Workflow

For every future implementation task:

1. Inspect relevant existing code.
2. Identify affected modules.
3. Make the smallest reasonable change.
4. Validate the change.
5. Report what changed.
6. Report what was actually tested.
7. Report anything that could not be tested.
8. Update documentation when appropriate.

Never claim more validation than actually occurred.

## Strategy Input Isolation

MetaTrader applies a `.set` file by input IDENTIFIER, not by which EA wrote it. Two Expert Advisors that declare the same identifier are one careless "Load" away from cross-configuring each other, silently and with no warning anywhere. When the shared identifier is the Magic Number the consequence is not cosmetic: both bots then manage the same broker positions, which defeats position reconciliation, the per-position state store, the opposing-exposure check, the weekend close and the killswitch flatten simultaneously.

So a strategy's settings are part of that strategy, not of the platform:

- Each EA declares its own inputs under its own prefix. `XSpark.mq5` keeps the bare `Inp` prefix for `.set` compatibility with everything already shipped; `XSparkFlow.mq5` uses `InpFlow`. A new strategy takes a new prefix.
- An EA exposes an input only if its own code reads it. "The other strategy has one" is not a reason, and neither is "it might be useful later".
- Defaults are declared by the strategy that uses them. An input whose default reads through another strategy's constant silently changes when that strategy is retuned.
- Conditional inputs are grouped with the switch that enables them, so an operator can see what turning the switch off makes inert.
- Labels are written for someone who does not know the terminology. MetaTrader shows the trailing comment as the input's name, so that comment is the entire user interface: it has to say what the setting does in words the reader already has.
- Defaults are the recommended configuration, not the inert one. Shipping a feature switched off so that nothing changes is a reasonable step while it is unproven, but it is a step, not a destination.
- The Inputs tab is a cost, not a feature. Every setting is a decision pushed onto someone with less context than the code has, a combination that has to be validated, and a dimension an optimizer can sweep out of its own valid domain. `docs/OPTIMIZATION.md` records what that costs at scale: a 1,024-pass run where only two passes would have initialised at all. Ask of each one what the operator knows that the code does not, and remove it when the answer is nothing.

`tools/check_ea_inputs.py` enforces the mechanical parts of this and runs in CI. It is source analysis, not a compiler.

## Trading Safety Boundaries

- Strategies may create signal objects only.
- Strategies must not include `Trade/Trade.mqh`, use `CTrade`, call `OrderSend`, or call broker execution methods.
- SafetyManager and RiskManager may veto any proposed exposure.
- ExecutionEngine is the only future broker execution boundary.
- PositionManager must reconcile against MT5 positions and orders after initialization/restart.
- Unknown safety state means no new trades.

## Repository Discipline

- Keep MQL5 source files under `MQL5/Experts` and `MQL5/Include`.
- Keep generated binaries, logs, local settings, credentials, and broker-specific secrets out of Git.
- Keep documentation current when behavior, module responsibilities, deployment workflow, or safety assumptions change.
