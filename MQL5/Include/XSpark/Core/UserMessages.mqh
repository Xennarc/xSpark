#ifndef XSPARK_USER_MESSAGES_MQH
#define XSPARK_USER_MESSAGES_MQH

// Presentation only: never replace the raw reasons used by trading gates.
struct XSparkNotice { string title, detail, action; int severity; };

string XSparkReadableInputs(string text)
{
   StringReplace(text, "InpUseContinuationTriggers", "Require a signal that the trend is resuming");
   StringReplace(text, "InpUseStopLevelValidation", "Check broker minimum stop distance");
   StringReplace(text, "InpUseTotalDDKillSwitch", "Use account drawdown emergency stop");
   StringReplace(text, "InpEntryDeviationPoints", "Entry price tolerance (strategy points)");
   StringReplace(text, "InpClearKillswitchLatch", "Reset emergency stop once (then set false)");
   StringReplace(text, "InpUseCupHandlePattern", "Recognize cup and handle (both directions)");
   StringReplace(text, "InpExitDeviationPoints", "Exit price tolerance (strategy points)");
   StringReplace(text, "InpUseHTFStructureGate", "Require agreement with the higher-timeframe trend");
   StringReplace(text, "InpPatternMaxChaseATR", "Maximum entry beyond pattern edge (x average range)");
   StringReplace(text, "InpWeekendCloseMinute", "Friday closing minute (0-59)");
   StringReplace(text, "InpUseT1PullbackBreak", "Use pullback breaks with custom trend entries");
   StringReplace(text, "InpMaxQuoteAgeSeconds", "Maximum price age before refusing (seconds)");
   StringReplace(text, "InpAutoTuneForSymbol", "Automatically adapt to this market");
   StringReplace(text, "InpMaxAccountRiskPct", "Maximum combined risk across the account (%)");
   StringReplace(text, "InpAllowAsianReduced", "Allow Asian-session entries at reduced score");
   StringReplace(text, "InpUseT3MomentumTurn", "Use momentum turns with custom trend entries");
   StringReplace(text, "InpWeekendCloseHour", "Friday closing hour (broker time, 0-23)");
   StringReplace(text, "InpDashboardMarginX", "Panel distance from left/right edge (pixels)");
   StringReplace(text, "InpDashboardMarginY", "Panel distance from top/bottom edge (pixels)");
   StringReplace(text, "InpUsePatternEngine", "Use chart-pattern entry rules");
   StringReplace(text, "InpPartialClosePct", "Portion of trade to close at that point (%)");
   StringReplace(text, "InpUseWeekendClose", "Close this bot's trades before the weekend");
   StringReplace(text, "InpDashboardCorner", "Chart panel corner");
   StringReplace(text, "InpMaxSpreadATRPct", "Maximum spread (% of average range)");
   StringReplace(text, "InpUseSpreadFilter", "Block entries when the spread is too wide");
   StringReplace(text, "InpMarginBufferPct", "Extra margin required (% of order margin)");
   StringReplace(text, "InpMaxSpreadPoints", "Maximum spread (strategy points)");
   StringReplace(text, "InpGateObserveOnly", "Preview changes but keep original entries");
   StringReplace(text, "InpUsePullbackGate", "Require a valid pullback or chart location");
   StringReplace(text, "InpUseFlagPattern", "Recognize bull and bear flags");
   StringReplace(text, "InpPartialTPRatio", "Take some profit at (x initial stop distance)");
   StringReplace(text, "InpLongScoreExtra", "Extra setup score required for buys");
   StringReplace(text, "InpRequireRSITurn", "Also require momentum to turn toward the trade");
   StringReplace(text, "InpQuietMarketPct", "Minimum market movement (% of normal)");
   StringReplace(text, "InpUseMarginCheck", "Check available margin before entering");
   StringReplace(text, "InpEnableTrading", "Allow new trades (false = watch only)");
   StringReplace(text, "InpMaxOpenTrades", "Maximum open trades for this bot (1-10)");
   StringReplace(text, "InpMaxDailyDDPct", "Daily equity drop to pause new trades (%)");
   StringReplace(text, "InpMaxTotalDDPct", "Equity drop to trigger emergency stop (%)");
   StringReplace(text, "InpWildMarketPct", "Maximum market movement (% of normal)");
   StringReplace(text, "InpATRRatioBoost", "Target boost when market movement increases");
   StringReplace(text, "InpRiskPctTier1", "Risk ceiling: score below 4.5 (% of balance)");
   StringReplace(text, "InpRiskPctTier2", "Risk ceiling: score 4.5 to below 5.5 (%)");
   StringReplace(text, "InpRiskPctTier3", "Risk ceiling: score 5.5 and above (%)");
   StringReplace(text, "InpUseHSPattern", "Recognize head and shoulders (both directions)");
   StringReplace(text, "InpATRMultTrail", "Trailing-stop distance (x average range)");
   StringReplace(text, "InpEntrySlipPct", "Entry price tolerance (% of smallest stop)");
   StringReplace(text, "InpSpreadCapPct", "Maximum spread (% of smallest stop)");
   StringReplace(text, "InpATRMinPoints", "Minimum market movement (strategy points)");
   StringReplace(text, "InpATRMaxPoints", "Maximum market movement (strategy points)");
   StringReplace(text, "InpOrderComment", "Trade label shown in account history");
   StringReplace(text, "InpRSIShortMin", "Sell momentum: lowest RSI (0-100)");
   StringReplace(text, "InpRSIShortMax", "Sell momentum: highest RSI (0-100)");
   StringReplace(text, "InpMinSwingATR", "Minimum swing size (x average candle range)");
   StringReplace(text, "InpPullbackMin", "Smallest pullback (0.30 means 30% of move)");
   StringReplace(text, "InpPullbackMax", "Largest pullback (0.80 means 80% of move)");
   StringReplace(text, "InpExitSlipPct", "Exit price tolerance (% of smallest stop)");
   StringReplace(text, "InpMagicNumber", "Unique bot ID (use a different ID per chart)");
   StringReplace(text, "InpEntryStyle", "Entry style");
   StringReplace(text, "InpMaxRiskPct", "Maximum risk per trade (%)");
   StringReplace(text, "InpUsePinBars", "Allow pin bars with chart-pattern entries");
   StringReplace(text, "InpVerboseLog", "Show detailed diagnostic logs");
   StringReplace(text, "InpUseRSIGate", "Require the momentum filter for new entries");
   StringReplace(text, "InpRSILongMin", "Buy momentum: lowest RSI (0-100)");
   StringReplace(text, "InpRSILongMax", "Buy momentum: highest RSI (0-100)");
   StringReplace(text, "InpATRMultSL", "Stop-loss distance (x average range)");
   StringReplace(text, "InpMinLegATR", "Minimum trend move (x average range)");
   StringReplace(text, "InpMinScore", "Minimum setup score (0-9; higher = stricter)");
   StringReplace(text, "InpDropIBR", "Ignore inside-bar candle signals");
   StringReplace(text, "InpMinRR", "Minimum target (x initial stop distance)");
   StringReplace(text, "InpMaxRR", "Maximum target (x initial stop distance)");
   StringReplace(text, "InpDashboardCompact", "Start with a compact chart panel");
   StringReplace(text, "InpDashboardAnimate", "Animate live dashboard activity");
   return text;
}

void XSparkSetNotice(XSparkNotice &n, const int severity, const string title, const string detail, const string action)
{ n.severity=severity; n.title=title; n.detail=detail; n.action=action; }

void XSparkExplain(const string status, const string reason, XSparkNotice &n, const string component = "")
{
   string key = status + " " + reason;
   StringToLower(key);
   // Startup/configuration errors precede session/spread words inside their reasons.
   if(StringFind(key, "requires a hedging account") >= 0)
   { XSparkSetNotice(n, 4, "Use a hedging account", "This account merges trades together; XSpark needs separate positions.", "Select an MT5 hedging account before attaching this EA."); return; }
   if(StringFind(key, "not a supported xspark base timeframe") >= 0)
   { XSparkSetNotice(n, 4, "Choose a supported chart timeframe", "This chart period cannot be paired with the EA's trend timeframe.", "Use M1, M5, M15, M30, H1, H2 or H4."); return; }
   if(StringFind(key, "magic number must") >= 0)
   { XSparkSetNotice(n, 4, "Set a unique bot ID", "The bot ID cannot be zero; it identifies this EA's positions.", "Choose a nonzero Unique bot ID that is not shared by another chart."); return; }
   if(StringFind(key, "rsi input ranges are invalid") >= 0)
   { XSparkSetNotice(n, 4, "Check your momentum ranges", "Buy and sell momentum ranges must stay between 0 and 100.", "Set each lowest RSI at or below its corresponding highest RSI."); return; }
   if(StringFind(key, "atr/exit inputs are invalid") >= 0)
   { XSparkSetNotice(n, 4, "Check stops and profit settings", "A market-range, stop, target or partial-close setting is outside its limits.", "Use positive distances, ordered min/max values, and a close portion between 0 and 100%."); return; }
   if(StringFind(key, "risk inputs are invalid") >= 0)
   { XSparkSetNotice(n, 4, "Risk percentages must be positive", "A risk tier, per-trade limit or daily loss limit is zero or negative.", "Review Risk and account limits; use Allow new trades to pause entries."); return; }
   if(StringFind(key, "risk per trade above") >= 0)
   { XSparkSetNotice(n, 4, "Risk exceeds the built-in ceiling", "A configured per-trade risk percentage exceeds the EA's hard limit.", "Reduce the risk tiers and per-trade maximum to the limit in the details."); return; }
   if(StringFind(key, "production-control inputs are invalid") >= 0)
   { XSparkSetNotice(n, 4, "Check spread and account limits", "Spread and total-loss limits must be positive; the margin buffer cannot be negative.", "Review market costs, account limits and broker checks in Inputs."); return; }
   if(StringFind(key, "inputs are invalid") >= 0 || StringFind(key, "input ranges are invalid") >= 0 ||
      StringFind(key, "must be") >= 0 || StringFind(key, "time is invalid") >= 0 ||
      StringFind(key, "percentage must") >= 0 || StringFind(key, "percentages must") >= 0)
   { XSparkSetNotice(n, 4, "Check the highlighted settings", XSparkReadableInputs(reason), "Review these values in Inputs; the technical details give the limits."); return; }
   if(StringFind(key, "calibration failed") >= 0 || StringFind(key, "threshold was refused") >= 0 || StringFind(key, "derived entry slippage") >= 0)
   { XSparkSetNotice(n, 4, "Market adaptation could not finish", "The calculated market limits are not safe to use for new entries.", "Check symbol details and adaptation settings in the Experts log."); return; }
   if(StringFind(key, "state recovery resolved") >= 0)
   { XSparkSetNotice(n, 0, "Trade records are synchronized", "The saved trade records now match the broker positions.", "The EA will evaluate entries on the next closed candle."); return; }
   if(StringFind(key, "position closed before state registration") >= 0)
   { XSparkSetNotice(n, 2, "The filled trade has already closed", "The broker confirmed the entry and its position is no longer open.", "Review the entry and exit in Account History."); return; }
   if(status == "KILLSWITCH" || StringFind(key, "killswitch is latched") >= 0 || StringFind(key, "killswitch latched") >= 0)
   { XSparkSetNotice(n, 4, "Emergency stop is active", "The account drawdown limit has been reached. New entries are stopped.", "Review the account and open trades before resetting the stop."); return; }
   if(StringFind(key, "dd halt") >= 0 || StringFind(key, "daily dd halt") >= 0 || StringFind(key, "daily loss") >= 0)
   { XSparkSetNotice(n, 3, "Paused for the broker day", "The daily equity-loss limit has been reached.", "Wait for the next broker day; existing positions remain managed."); return; }
   if(StringFind(key, "unmanaged exposure") >= 0 || StringFind(key, "no trustworthy entry risk") >= 0 || StringFind(key, "no matching persisted state") >= 0)
   { XSparkSetNotice(n, 4, "A trade needs attention", "Original trade records are missing; some exit management is unavailable.", "Check its broker stop and restore the matching saved state."); return; }
   if(StringFind(key, "state recovery") >= 0 || StringFind(key, "registration failed") >= 0 || StringFind(key, "state is inconsistent") >= 0 || StringFind(key, "identity differs") >= 0 || StringFind(key, "different broker identifier") >= 0 || StringFind(key, "ambiguous") >= 0)
   { XSparkSetNotice(n, 4, "Checking open-trade records", "The EA cannot yet match its records to the broker positions.", "Keep broker stops in place; check the Experts log if this persists."); return; }
   if(StringFind(key, "not connected") >= 0 || StringFind(key, "disconnected") >= 0)
   { XSparkSetNotice(n, 3, "Broker connection lost", "Fresh prices and broker confirmations are unavailable.", "Check the MT5 connection. Broker-held stops remain with the broker."); return; }
   if(StringFind(key, "stale quote") >= 0 || StringFind(key, "prices stopped") >= 0 || StringFind(key, "quote unavailable") >= 0 || StringFind(key, "stale or invalid quote") >= 0 || StringFind(key, "refresh tick before") >= 0 || StringFind(key, "current tick is unavailable") >= 0 || StringFind(key, "refresh market state") >= 0)
   { XSparkSetNotice(n, 3, "Waiting for fresh prices", "The price feed is missing or too old for a new entry.", "Check the connection and market hours; entries wait for fresh quotes."); return; }
   if(StringFind(key, "terminal trading is not allowed") >= 0 || StringFind(key, "ea trading is not allowed") >= 0)
   { XSparkSetNotice(n, 3, "Algo Trading is switched off", "MT5 has not given this EA permission to trade.", "Check the Algo Trading button and the EA trading permissions."); return; }
   if(StringFind(key, "account trading is not allowed") >= 0)
   { XSparkSetNotice(n, 4, "Account trading is restricted", "The broker account is not permitting orders.", "Check your login and account permissions with the broker."); return; }
   if(StringFind(key, "close-only") >= 0 || StringFind(key, "symbol trading is disabled") >= 0 || StringFind(key, "trade mode") >= 0)
   { XSparkSetNotice(n, 3, "This market is not accepting entries", "The broker currently restricts trading in this symbol.", "Check the symbol trading session and broker permissions."); return; }
   if(StringFind(key, "v2 config blocked") >= 0 || StringFind(key, "requires htf") >= 0 || StringFind(key, "require htf") >= 0 || StringFind(key, "requires pullback") >= 0 || StringFind(key, "require the rsi gate") >= 0 || StringFind(key, "requires the rsi gate") >= 0 || StringFind(key, "pattern profile requires") >= 0 || StringFind(key, "invalid entry style") >= 0)
   { XSparkSetNotice(n, 4, "Check your entry settings", "Some entry switches cannot work together in this combination.", "Choose an Entry style preset, or review the custom entry switches."); return; }
   if(StringFind(key, "point size fault") >= 0 || StringFind(key, "point size is not trusted") >= 0 || StringFind(key, "point specification") >= 0 || StringFind(key, "tick specification") >= 0 || StringFind(key, "volume constraints") >= 0)
   { XSparkSetNotice(n, 4, "Market details are unavailable", "The EA cannot safely calculate this instrument's prices or volume.", "Refresh the symbol in Market Watch and inspect the broker details."); return; }
   if(StringFind(key, "drift gate fault") >= 0 || StringFind(key, "drift gate is inert") >= 0 || StringFind(key, "entry drift bound") >= 0)
   { XSparkSetNotice(n, 4, "Price tolerance needs attention", "The allowed price movement is too large for the configured stop.", "Use automatic market adaptation or review manual price limits."); return; }
   if(StringFind(key, "account risk") >= 0 || StringFind(key, "projected account risk") >= 0 || StringFind(key, "risk cap") >= 0)
   { XSparkSetNotice(n, 3, "Account risk budget is full", "Another entry would exceed the shared risk limit, or risk is unknown.", "Wait for exposure to reduce; check that every account trade has a stop."); return; }
   if(StringFind(key, "maximum open trades reached") >= 0 || StringFind(key, "reached max") >= 0)
   { XSparkSetNotice(n, 2, "All trade slots are in use", "This bot is already at its selected number of open trades.", "Existing positions are managed; another entry waits for a free slot."); return; }
   if(StringFind(key, "below broker minimum") >= 0 || StringFind(key, "below the minimum") >= 0 || StringFind(key, "minimum volume") >= 0)
   { XSparkSetNotice(n, 3, "Budget is below the smallest trade", "The allowed risk cannot fund the broker's minimum trade size.", "Check account size, slot count and symbol minimum volume."); return; }
   if(StringFind(key, "free margin") >= 0 || StringFind(key, "not enough money") >= 0)
   { XSparkSetNotice(n, 3, "Not enough available margin", "The broker requires more free margin for this order.", "Check leverage, open exposure and the margin buffer."); return; }
   if(StringFind(key, "spread blocked") >= 0 || StringFind(key, "spread filter") >= 0 || StringFind(key, "spread ") >= 0)
   { XSparkSetNotice(n, 3, "Waiting for a lower spread", "The difference between buy and sell prices exceeds the entry limit.", "The EA will check again; no action is needed to force an entry."); return; }
   if(StringFind(key, "atr blocked") >= 0 || StringFind(key, "outside 80") >= 0 || StringFind(key, "volatility band") >= 0)
   { XSparkSetNotice(n, 2, "Market movement is outside your range", "Recent price movement does not meet the selected market limits.", "Wait for conditions to change, or review market adaptation settings."); return; }
   if(StringFind(key, "session blocked") >= 0 || StringFind(key, "session weight is zero") >= 0 || StringFind(key, "weekend close") >= 0)
   { XSparkSetNotice(n, 2, "Outside trading hours", "New entries are paused by the selected session or weekend rule.", "Check broker time and the Trading hours settings."); return; }
   if(StringFind(key, "opposing exposure") >= 0)
   { XSparkSetNotice(n, 2, "An opposite trade is already open", "A new order would oppose this bot's existing position.", "Wait for that position to close; opposing entries are intentionally blocked."); return; }
   if(StringFind(key, "pattern instance used") >= 0 || StringFind(key, "already reserved") >= 0 || StringFind(key, "duplicate") >= 0 || StringFind(key, "already evaluated") >= 0 || StringFind(key, "newer instance") >= 0 || StringFind(key, "bootstrap") >= 0)
   { XSparkSetNotice(n, 2, "This setup has already been handled", "The EA is preventing repeat entries from the same signal or saved setup.", "Wait for a new eligible setup; do not clear trade records to force entry."); return; }
   if(StringFind(key, "pattern entry invalid") >= 0 || StringFind(key, "entry moved") >= 0 || StringFind(key, "price moved through") >= 0 || StringFind(key, "execution tolerance") >= 0)
   { XSparkSetNotice(n, 2, "Price has moved away from the setup", "The entry is now outside its allowed price or breakout range.", "The EA skips this entry and waits for a fresh setup."); return; }
   if(StringFind(key, "htf structure unknown") >= 0 || StringFind(key, "structure data") >= 0 || StringFind(key, "history") >= 0 || StringFind(key, "bars are unavailable") >= 0 || StringFind(key, "bar is unavailable") >= 0 || StringFind(key, "timestamp is unavailable") >= 0 || StringFind(key, "calibration is waiting") >= 0 || StringFind(key, "calibrate this market") >= 0 || StringFind(key, "barscalculated") >= 0 || StringFind(key, "copybuffer") >= 0)
   { XSparkSetNotice(n, 2, "Loading market history", "The EA needs more valid candles before it can complete its checks.", "Keep the chart connected and allow history to load."); return; }
   if(StringFind(key, "htf range") >= 0)
   { XSparkSetNotice(n, 2, "Waiting for a clear trend", "The higher timeframe is moving sideways.", "The EA will wait for a directional trend before entering."); return; }
   if(StringFind(key, "no qualifying leg") >= 0 || StringFind(key, "not in pullback zone") >= 0 || StringFind(key, "leg broken") >= 0 || StringFind(key, "invalid retracement") >= 0)
   { XSparkSetNotice(n, 2, "Waiting for a suitable entry area", "The current move has not reached a valid pullback location.", "Wait for a new pullback or a confirmed chart-pattern breakout."); return; }
   if(StringFind(key, "wait for continuation") >= 0 || StringFind(key, "no qualified pattern") >= 0 || StringFind(key, "no pattern") >= 0 || StringFind(key, "pattern conflict") >= 0)
   { XSparkSetNotice(n, 0, "Scanning for the next setup", "No eligible pattern is confirmed on the latest closed candle.", "The EA checks again when the next trading candle closes."); return; }
   if(StringFind(key, "rsi inner") >= 0 || StringFind(key, "rsi outer") >= 0 || StringFind(key, "rsi not turning") >= 0)
   { XSparkSetNotice(n, 2, "Waiting for momentum to agree", "Momentum does not yet meet your selected entry filter.", "Wait for the next candle; review Momentum settings only if intended."); return; }
   if(StringFind(key, "rsi unavailable") >= 0 || StringFind(key, "rsi history") >= 0)
   { XSparkSetNotice(n, 2, "Waiting for momentum data", "The momentum indicator is not ready.", "Allow market history to load before expecting new entries."); return; }
   if(StringFind(key, "score below") >= 0)
   { XSparkSetNotice(n, 0, "Setup is not strong enough yet", "The latest setup scored below your minimum entry score.", "The EA keeps scanning for a setup that passes your threshold."); return; }
   if(StringFind(key, "stop distance is invalid") >= 0 || StringFind(key, "stop-level validation remained") >= 0 || StringFind(key, "no stop loss") >= 0 || StringFind(key, "unprotected") >= 0 || StringFind(key, "protection failed") >= 0 || StringFind(key, "protection is missing") >= 0)
   { XSparkSetNotice(n, 4, "Check trade protection", "A stop could not be confirmed or placed safely.", "Check the position's broker stop and symbol stop-distance rules."); return; }
   if(StringFind(key, "broker-valid rr") >= 0 || StringFind(key, "reward-ratio") >= 0 || StringFind(key, "reward ratio") >= 0)
   { XSparkSetNotice(n, 2, "Target does not fit the stop", "The broker-adjusted stop and target fall outside the selected ratio.", "Review Stops and taking profit; this entry is skipped."); return; }
   if(StringFind(key, "failed to persist") >= 0 || StringFind(key, "write failed") >= 0 || StringFind(key, "read failed") >= 0 || StringFind(key, "reservation failed") >= 0)
   { XSparkSetNotice(n, 4, "Trade records could not be saved", "The EA cannot safely confirm its stored trade or safety state.", "Check terminal storage and the Experts log; do not delete live records."); return; }
   if(StringFind(key, "requote") >= 0 || StringFind(key, "price_changed") >= 0 || StringFind(key, "price_off") >= 0 || StringFind(key, "transient price") >= 0)
   { XSparkSetNotice(n, 3, "Broker prices changed during entry", "The order could not be confirmed at the permitted price.", "The EA uses bounded retries; wait for its final order result."); return; }
   if(StringFind(key, "retcode") >= 0 || StringFind(key, "execution failure") >= 0 || StringFind(key, "order rejected") >= 0 || StringFind(key, "broker rejected") >= 0)
   { XSparkSetNotice(n, 4, "Broker request was not confirmed", "The trade server returned a rejection or an uncertain result.", "Check the broker response below and confirm positions in the Trade tab."); return; }
   if(StringFind(key, "trading disabled") >= 0 || StringFind(key, "analysis only") >= 0 || StringFind(key, "watch only") >= 0)
   { XSparkSetNotice(n, 2, "Watching the market", "New orders are disabled; analysis and existing-position management continue.", "Enable Allow new trades only when you intend this EA to place orders."); return; }
   if(StringFind(key, "managing") >= 0 || StringFind(key, "entry confirmed") >= 0 || StringFind(key, "broker execution confirmed") >= 0)
   { XSparkSetNotice(n, 1, "Managing open trades", "The EA is monitoring each position and its configured exit rules.", "Keep the terminal connected for EA-managed exits."); return; }
   if(StringFind(key, "signal eligible") >= 0 || StringFind(key, "safety gates allow") >= 0)
   { XSparkSetNotice(n, 0, "Setup passed the signal checks", "Risk, execution and trading-permission checks still decide whether to enter.", "Check the entry result; a qualified setup is not a confirmed trade."); return; }
   if(StringFind(key, "waiting for next") >= 0 || StringFind(key, "waiting for the next") >= 0 || StringFind(key, "initialized current bar") >= 0)
   { XSparkSetNotice(n, 0, "Waiting for the candle to close", "Entries use completed candles; the current candle is still forming.", "Live positions continue to be monitored between entry checks."); return; }
   // Unknown messages remain visible as attention required, never healthy.
   XSparkSetNotice(n, 4, "Something needs attention",
                    reason == "" ? "The EA has not supplied a recognized status yet." : XSparkReadableInputs(reason),
                    "Open the Experts log for details" + (component == "" ? "." : " from " + component + "."));
}
#endif
