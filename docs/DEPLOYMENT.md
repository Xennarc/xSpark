# Deployment

XSpark is intended to be developed locally, reviewed through Git, compiled in MetaEditor, validated in MT5 Strategy Tester, and then deployed to an Exness Windows VPS when ready.

## Development Workflow

```text
Codex
|
GitHub
|
MetaEditor
|
MT5 Strategy Tester
|
compiled .ex5
```

## Production Target

```text
Exness VPS
|
Windows
|
MT5
|
XSpark.ex5
|
Exness trading server
```

The VPS is production infrastructure, not the primary development environment.

## Future Deployment Checklist

- Confirm repository branch and commit being deployed.
- Compile from source in MetaEditor.
- Record compiler errors and warnings.
- Run the relevant MT5 Strategy Tester checks.
- Confirm account type: demo or live.
- Confirm symbol list and broker specifications.
- Confirm no CRITICAL "ScoreBot point size" line was logged at startup, and that the dashboard status is not `POINT SIZE FAULT`. Do not read the startup `score_point_size=` value as the check: on XAUUSD it reads `0.01000000` on the failure paths too, because the EA falls back to the declared baseline before that line is emitted, and on other instruments it reports whichever denominator was selected. The absence of the CRITICAL line is what carries the information. On a non-XAUUSD symbol also confirm the reported size is the pip you expect for that instrument (0.0001 for a 5-digit FX major, 0.01 for a 3-digit JPY cross).
- Confirm XSpark Magic Number.
- Confirm only ONE XSpark instance is attached per symbol per account. Positions are owned by symbol and Magic Number, not by chart period, so two instances on the same symbol with different chart periods will manage each other's positions and collide on per-position state keys. The EA cannot detect this from the inside; it is an operational rule.
- Confirm the chart period is one of the supported base timeframes (M1, M5, M15, M30, H1, H2, H4).
- On a non-XAUUSD symbol, confirm the ATR and spread inputs have been set for that instrument. The shipped defaults are XAUUSD values and will block every bar on an FX pair.
- Understand that retuning the inputs does NOT retune the execution and exit deviations. `XSPARK_SCOREBOT_DEVIATION_SCORE_POINTS` (30) and `XSPARK_CLOSE_DEVIATION_SCORE_POINTS` (100) are compile-time constants with no input override, so on an FX pair they are 30 and 100 pips against a stop of roughly 8-25 pips. The entry drift gate is therefore inert and a permitted fill can put realised risk several times over the selected risk percentage, logged only as a WARNING. This is a Phase 1 limitation; changing it needs a code change.
- Confirm automated trading permissions in MT5.
- Confirm account-level and EA-level risk limits.
- Confirm VPS time, connectivity, and MT5 login state.
- Confirm logs are visible and retained.
- Deploy `.ex5` only after validation is complete.
- Monitor the first production session closely.

## Secrets

Do not commit passwords, account numbers, investor passwords, API keys, VPS credentials, broker credentials, or local configuration containing secrets.
