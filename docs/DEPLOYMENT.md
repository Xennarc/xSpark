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
- On a non-XAUUSD symbol, set `InpEntryDeviationPoints` and `InpExitDeviationPoints` for that instrument. They are in ScoreBot points (the pip: 0.01 on gold, 0.0001 on a 5-digit FX major, 0.01 on a 3-digit JPY cross) and ship with the gold values, 30 and 100. Left at those on an FX pair they are 30 and 100 PIPS against a stop of roughly 8-25 pips.
- Read the startup `entry drift bound` line. The entry deviation is the amount by which a permitted fill can push realised risk past selected risk, and what makes it a bound is its size relative to the smallest stop the configuration can produce (`InpATRMultSL * InpATRMinPoints`). `INERT` means a fill can land at or beyond its own stop; new entries are blocked and the dashboard reads `DRIFT GATE FAULT` until the deviation, the ATR floor or the stop multiple is corrected. Correcting any of the three clears it.
- Expect a WARNING on this line at the shipped gold defaults. 30 points against a 120-point minimum stop is a 25% realised-risk overshoot, so a permitted fill can realise up to 125% of selected risk. Concretely: at 3.0% selected risk a maximum-slip fill realises 3.75%, which is past the 3.5% `InpMaxRiskPct` cap - because that input caps SIZED risk, not realised risk. This is not new behaviour and this change does not cause it; the overshoot was always present and was only ever logged after the fill. It is now reported at startup so you can decide before funding rather than after. Lowering `InpEntryDeviationPoints` tightens realised risk at the cost of more rejected entries.
- Do NOT tighten `InpExitDeviationPoints` to match the entry value. An exit tolerance that is too small gets the close REJECTED and leaves live exposure XSpark intended to be flat, which is the opposite of a risk control. Generosity there is protective and is intentionally unbounded.
- Confirm automated trading permissions in MT5.
- Confirm account-level and EA-level risk limits.
- Read the startup line reporting the consecutive-loss tolerance, and confirm the number is one you are willing to sit through. It states how many consecutive full-stop losses latch the killswitch and the daily halt at the configured risk. A WARNING on that line means ordinary variance will latch the killswitch.
- Confirm `InpClearKillswitchLatch` is **false**. The killswitch latch and the drawdown high-water mark now survive restarts, so leaving this input true would re-anchor the ruin stop on the next restart.
- After a killswitch latch: do not simply restart. Restarting preserves the latch by design. Review why it fired, then set `InpClearKillswitchLatch` true, attach, confirm the CRITICAL line reporting the reset, and set it back to false.
- At the shipped defaults (3.0% per trade, 25% total, 15% daily) a 25% account drawdown is a permitted outcome of ordinary variance, not a fault. Confirm that is the drawdown you intend to accept before funding the account.
- Confirm VPS time, connectivity, and MT5 login state.
- Confirm logs are visible and retained.
- Deploy `.ex5` only after validation is complete.
- Monitor the first production session closely.

## Secrets

Do not commit passwords, account numbers, investor passwords, API keys, VPS credentials, broker credentials, or local configuration containing secrets.
