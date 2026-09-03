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
33. Never fabricate test results, backtest results, compiler results, performance numbers, or profitability.
34. Profitability is not an acceptance criterion for infrastructure code.
35. Maintain documentation when architectural behavior changes.
36. Prefer clarity over cleverness.
37. Comments should explain why, not narrate obvious code.
38. Keep functions focused.
39. Avoid giant monolithic `.mq5` files.
40. Preserve separation between market state, strategy/signals, risk, position sizing, execution, position management, safety, and logging.

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
