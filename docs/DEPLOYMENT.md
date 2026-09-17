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
- Confirm no CRITICAL "ScoreBot point size" line was logged at startup, and that the dashboard status is not `POINT SIZE FAULT`. The startup `score_point_size=` value reads `0.01000000` on the failure paths too, because the EA falls back to the declared baseline before that line is emitted, so the absence of the CRITICAL is the check that carries the information.
- Confirm XSpark Magic Number.
- Confirm automated trading permissions in MT5.
- Confirm account-level and EA-level risk limits.
- Confirm VPS time, connectivity, and MT5 login state.
- Confirm logs are visible and retained.
- Deploy `.ex5` only after validation is complete.
- Monitor the first production session closely.

## Secrets

Do not commit passwords, account numbers, investor passwords, API keys, VPS credentials, broker credentials, or local configuration containing secrets.
