# Roadmap

## Phase 0 - Foundation

Repository, architecture, agent rules, logging, and skeleton modules.

## Phase 1 - Market & Account State

Reliable symbol, account, terminal, and environment state.

## Phase 2 - Risk Engine

Hard account-level risk limits and fail-closed enforcement.

## Phase 3 - Position Sizing

Symbol-aware monetary risk sizing using MT5 instrument specifications.

## Phase 4 - Execution Engine

Safe order submission, trade-server result verification, rejection logging, filling mode handling, and duplicate protection.

## Phase 5 - Position Reconciliation

Startup recovery and live state synchronization against MT5 broker positions and orders.

## Phase 6 - Position Management

Stops, targets, break-even handling, trailing behavior, and controlled position closure.

## Phase 7 - Strategy Framework

Signal creation interfaces and strategy lifecycle boundaries.

## Phase 8 - First Strategy

First strategy only after infrastructure is validated. Strategy implementation must preserve safety and risk boundaries.

## Phase 9 - Backtesting & Validation

Historical test methodology, walk-forward validation, out-of-sample testing, and robustness checks.

## Phase 10 - Demo Deployment

Exness VPS and MT5 demo account deployment.

## Phase 11 - Small Live Deployment

Small-capital live validation with strict limits and close monitoring.
