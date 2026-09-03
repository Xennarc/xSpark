# Roadmap

## Status Summary

The repository has moved beyond Phase 0 by implementing the first strategy and several required execution/risk/management components. This does not mean the system is production-approved: MetaEditor compilation, Strategy Tester validation, demo testing, and live smoke testing remain outstanding.

## Phase 0 - Foundation

Implemented: repository, architecture, agent rules, logging, and initial module layout.

## Phase 1 - Market & Account State

Partially implemented: market state, indicator cache, symbol validation, terminal/account trading checks. Further validation is still needed in MetaTrader.

## Phase 2 - Risk Engine

Partially implemented: ScoreBot_v3 risk tiers, max risk cap, persisted daily DD halt, runtime total-DD killswitch entry block. Broader portfolio/correlation rules are not implemented.

## Phase 3 - Position Sizing

Implemented for ScoreBot_v3: balance-based risk cash, actual stop distance, tick size/value, min/max/step volume, below-minimum abort behavior.

## Phase 4 - Execution Engine

Implemented for market entries: CTrade boundary, broker-aware filling, 30 canonical-point deviation, three transient price attempts, retcode inspection, duplicate signal-bar guard. Requires MetaEditor and broker-side validation.

## Phase 5 - Position Reconciliation

Partially implemented: symbol+magic reconciliation, persisted trade state by position identifier, ticket rebind attempt. Ambiguous same-direction matching is logged and not guessed.

## Phase 6 - Position Management

Partially implemented: partial close, breakeven movement, trailing stop, weekend close option, and killswitch flattening for XSpark-owned positions only. Needs hedging-mode Strategy Tester validation.

## Phase 7 - Strategy Framework

Implemented for ScoreBot_v3: strategy modules produce signals and analysis reports only.

## Phase 8 - First Strategy

Implemented: ScoreBot_v3 MAX_SHARPE defaults. EDGE inputs are available manually but not optimized.

## Phase 9 - Backtesting & Validation

Historical test methodology, walk-forward validation, out-of-sample testing, and robustness checks.

## Phase 10 - Demo Deployment

Exness VPS and MT5 demo account deployment.

## Phase 11 - Small Live Deployment

Small-capital live validation with strict limits and close monitoring.
