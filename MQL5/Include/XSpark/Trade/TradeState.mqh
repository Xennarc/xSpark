#ifndef XSPARK_TRADE_TRADE_STATE_MQH
#define XSPARK_TRADE_TRADE_STATE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Trade/ProfitLadder.mqh>
#include <XSpark/Trade/TrailingStop.mqh>

// How PositionManager moves a stop once a position is live.
//
// The mode belongs to the caller, not to the position: it is a property of the
// strategy that opened the trade, and both modes must be able to coexist on one
// account under different Magic Numbers. Passing it per call keeps PositionManager
// free of strategy configuration.
enum EXSparkTrailMode
{
   XSPARK_TRAIL_ATR_AFTER_PARTIAL = 0, // ScoreBot_v3: partial, break-even, then ATR trail
   XSPARK_TRAIL_CANDLE_ANCHOR = 1      // CandleFlow: no partial, ratchet to a supplied anchor
};

// Accumulated totals for every closing deal of one position.
//
// Two defects motivated this type, and they existed identically in two places:
// the closure walk summed DEAL_PROFIT alone, so commission and swap never
// reached the reported figure and a "net profit" line was really gross; and it
// assigned rather than accumulated the exit price, so a position closed in more
// than one deal - which every partial close produces - reported whichever deal
// the loop happened to see last instead of the volume-weighted average it was
// meant to represent.
//
// Both call sites now share one accumulator, so the two can no longer drift
// apart or be fixed in one place only.
struct XSparkClosureTotals
{
   double   gross_profit;      // DEAL_PROFIT summed
   double   commission;        // DEAL_COMMISSION summed
   double   swap;              // DEAL_SWAP summed
   double   net_profit;        // what actually reached the balance
   double   volume;            // total closed volume
   double   exit_price;        // volume-weighted average across closing deals
   datetime exit_time;         // latest closing deal
   int      deal_count;
   double   price_volume;      // running sum of price * volume, for the weighting
};

void XSparkResetClosureTotals(XSparkClosureTotals &totals)
{
   totals.gross_profit = 0.0;
   totals.commission = 0.0;
   totals.swap = 0.0;
   totals.net_profit = 0.0;
   totals.volume = 0.0;
   totals.exit_price = 0.0;
   totals.exit_time = 0;
   totals.deal_count = 0;
   totals.price_volume = 0.0;
}

// Folds one closing deal into the totals. Takes the deal's fields as values
// rather than a ticket so the arithmetic is testable without MT5 history.
//
// A deal reporting non-positive or non-finite volume still contributes its cash
// components - the money moved regardless - but cannot participate in the price
// weighting, because a zero weight would either divide by zero or silently drop
// the price. In that case the latest price is kept as a fallback, which is the
// old behaviour and is better than nothing when no usable weight exists.
void XSparkAccumulateClosureDeal(XSparkClosureTotals &totals,
                                 const double profit,
                                 const double commission,
                                 const double swap,
                                 const double volume,
                                 const double price,
                                 const datetime deal_time)
{
   if(MathIsValidNumber(profit))
      totals.gross_profit += profit;

   if(MathIsValidNumber(commission))
      totals.commission += commission;

   if(MathIsValidNumber(swap))
      totals.swap += swap;

   totals.net_profit = totals.gross_profit + totals.commission + totals.swap;
   totals.deal_count++;

   if(deal_time > totals.exit_time)
      totals.exit_time = deal_time;

   const bool weightable = MathIsValidNumber(volume) && volume > 0.0 &&
                           MathIsValidNumber(price) && price > 0.0;

   if(weightable)
   {
      totals.volume += volume;
      totals.price_volume += price * volume;
      totals.exit_price = totals.price_volume / totals.volume;
   }
   else if(totals.volume <= 0.0 && MathIsValidNumber(price) && price > 0.0)
   {
      totals.exit_price = price;
   }
}

// Maximum favourable and adverse excursion, tracked on the EXIT-side price.
//
// The exit side is the price the position could actually have been closed at -
// the Bid for a long, the Ask for a short - which is the same side the 2.5R
// partial trigger already measures against. Tracking the entry side instead
// would report an excursion that was never realisable.
//
// Today every winner closes at its take-profit by construction, so the right
// tail of the favourable distribution is completely unobserved. This is what
// makes it observable, and therefore what makes the optimal reward ratio, the
// break-even arm and the partial level choosable from data rather than guessed.
void XSparkUpdateExcursion(const EXSparkSignalDirection direction,
                           const double exit_side_price,
                           double &mfe_price,
                           double &mae_price)
{
   if(!MathIsValidNumber(exit_side_price) || exit_side_price <= 0.0)
      return;

   if(mfe_price <= 0.0 || !MathIsValidNumber(mfe_price))
      mfe_price = exit_side_price;

   if(mae_price <= 0.0 || !MathIsValidNumber(mae_price))
      mae_price = exit_side_price;

   if(direction == XSPARK_SIGNAL_BUY)
   {
      if(exit_side_price > mfe_price)
         mfe_price = exit_side_price;
      if(exit_side_price < mae_price)
         mae_price = exit_side_price;
   }
   else if(direction == XSPARK_SIGNAL_SELL)
   {
      if(exit_side_price < mfe_price)
         mfe_price = exit_side_price;
      if(exit_side_price > mae_price)
         mae_price = exit_side_price;
   }
}

// Converts an excursion price into R multiples of the ORIGINAL entry risk.
// Favourable excursions are positive and adverse ones negative for both
// directions, so mfe_r >= mae_r always holds for a consistent pair.
//
// Returns 0.0 when the original risk distance is unavailable, which is the case
// for a position adopted without persisted state (ADR-018). A fabricated R
// there would be worse than none.
double XSparkExcursionR(const EXSparkSignalDirection direction,
                        const double entry,
                        const double excursion_price,
                        const double risk_distance)
{
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(excursion_price) ||
      !MathIsValidNumber(risk_distance) || risk_distance <= 0.0 ||
      entry <= 0.0 || excursion_price <= 0.0)
   {
      return 0.0;
   }

   const double move = direction == XSPARK_SIGNAL_BUY
                       ? excursion_price - entry
                       : entry - excursion_price;

   return move / risk_distance;
}

// Sentinel returned by the optimisation fitness for a pass with too few trades.
// Large and negative so any such pass sorts below every real result, rather than
// competing with them on a mean computed from a handful of trades.
#define XSPARK_FITNESS_SENTINEL -1000000.0

// Running record of realised R multiples, for the Strategy Tester fitness.
// Streaming sums rather than an array: a pass can produce thousands of trades
// and the only quantities needed are the count, mean and dispersion.
struct XSparkRLedger
{
   int    count;
   double sum_r;
   double sum_r_squared;
   double min_r;
   double max_r;
   // Outcomes counted in CASH, not in R. A time-stop exit two points in front
   // is a positive R and, once commission is netted, a negative trade; a win
   // rate that counted it as a win would flatter exactly the exits a scalper
   // produces most. Recorded by a separate call from the R moments so the R
   // arithmetic above stays what every existing test proves it is. A trade
   // that netted exactly zero is an outcome that is neither a win nor a loss,
   // and it still counts against the rate.
   int    outcomes;
   int    wins;
   int    losses;
};

void XSparkResetRLedger(XSparkRLedger &ledger)
{
   ledger.count = 0;
   ledger.sum_r = 0.0;
   ledger.sum_r_squared = 0.0;
   ledger.min_r = 0.0;
   ledger.max_r = 0.0;
   ledger.outcomes = 0;
   ledger.wins = 0;
   ledger.losses = 0;
}

void XSparkRLedgerAdd(XSparkRLedger &ledger, const double r)
{
   if(!MathIsValidNumber(r))
      return;

   if(ledger.count == 0 || r < ledger.min_r)
      ledger.min_r = r;

   if(ledger.count == 0 || r > ledger.max_r)
      ledger.max_r = r;

   ledger.count++;
   ledger.sum_r += r;
   ledger.sum_r_squared += r * r;
}

// One closed trade's outcome, judged on what actually reached the balance:
// profit plus commission plus swap. Positive is a win, negative a loss, and
// exactly zero is neither. An unusable number is not an outcome at all.
void XSparkRLedgerRecordOutcome(XSparkRLedger &ledger, const double net_cash)
{
   if(!MathIsValidNumber(net_cash))
      return;

   ledger.outcomes++;

   if(net_cash > 0.0)
      ledger.wins++;
   else if(net_cash < 0.0)
      ledger.losses++;
}

// Share of recorded outcomes that made money, as a fraction of ALL of them. A
// scratch counts against the rate rather than being dropped from it, because
// a rate that ignored scratches would flatter a strategy whose break-even
// lock turns winners into zeros. Zero when nothing is recorded.
double XSparkRLedgerWinRate(XSparkRLedger &ledger)
{
   if(ledger.outcomes <= 0)
      return 0.0;

   return (double)ledger.wins / (double)ledger.outcomes;
}

double XSparkRLedgerMean(XSparkRLedger &ledger)
{
   if(ledger.count <= 0)
      return 0.0;

   return ledger.sum_r / (double)ledger.count;
}

// Sample standard deviation, n-1. Undefined below two observations, where zero
// is returned so the fitness degrades to the mean rather than to a NaN.
double XSparkRLedgerStdDev(XSparkRLedger &ledger)
{
   if(ledger.count < 2)
      return 0.0;

   const double n = (double)ledger.count;
   const double variance = (ledger.sum_r_squared - (ledger.sum_r * ledger.sum_r) / n) / (n - 1.0);

   if(!MathIsValidNumber(variance) || variance <= 0.0)
      return 0.0;

   return MathSqrt(variance);
}

// Optimisation fitness: mean_R - k * stdev_R / sqrt(n).
//
// NOT n * mean_R - k * stdev_R * sqrt(n). That alternative factors as
// sd * sqrt(n) * (t - k), which INCREASES with n at a fixed t statistic, so it
// prefers whichever pass trades more at identical statistical evidence. It is a
// trade-count maximiser, and it would push every future sweep toward the loosest
// possible gate and toward paying more of the one cost known with confidence to
// be negative.
//
// The form used here is the mean penalised by its own standard error, so a pass
// is rewarded for evidence rather than for activity.
double XSparkRLedgerFitness(XSparkRLedger &ledger, const double k, const int min_trades)
{
   if(ledger.count < min_trades || ledger.count <= 0)
      return XSPARK_FITNESS_SENTINEL;

   const double mean = XSparkRLedgerMean(ledger);
   const double standard_error = XSparkRLedgerStdDev(ledger) / MathSqrt((double)ledger.count);
   const double fitness = mean - k * standard_error;

   if(!MathIsValidNumber(fitness))
      return XSPARK_FITNESS_SENTINEL;

   return fitness;
}

struct XSparkTradeState
{
   ulong                  ticket;
   long                   identifier;
   EXSparkSignalDirection direction;
   double                 entry;
   double                 initial_sl;
   double                 initial_tp;
   double                 initial_lots;
   bool                   partial_done;
   double                 current_trail_sl;
   datetime               open_time;
   double                 entry_score;
   datetime               signal_bar_time;
   EXSparkScoreBotPatternId pattern_id;
   string                 pattern_name;
   double                 initial_risk_distance;
   double                 mfe_price;              // best exit-side price seen while open
   double                 mae_price;              // worst exit-side price seen while open
   // Best CLOSED-CANDLE extreme since entry, which is what a chandelier trail
   // measures from. Deliberately separate from mfe_price: that one is sampled
   // per management pass on the exit-side quote, so it moves intrabar and would
   // make a candle-close trail depend on when a tick happened to arrive.
   double                 trail_peak;
   datetime               trail_peak_time;        // the candle the peak was last advanced on
   // The largest take-profit step this position has already banked, in the same
   // R multiples the steps are configured in. Zero means none. Persisted,
   // because a step forgotten across a restart would leave money the operator
   // configured to bank sitting on the trailing stop instead.
   //
   // It records progress rather than a set of steps because the steps are
   // strictly ascending, so one number says which of them are behind the trade.
   // The step ARITHMETIC is what stops a confirmed-but-unrecorded close from
   // being replayed, not this field; see XSparkProfitLadderTargetRemaining.
   double                 profit_high_water_r;
   bool                   partial_block_logged;   // RAM-only: throttles the "no legal partial" warning
   // RAM-only: throttles the "no legal volume for this take-profit step"
   // warning. Once a trigger price is crossed it stays crossed, so an
   // unconditional warning would repeat on every tick for the rest of the trade.
   bool                   profit_block_logged;
   // RAM-only backoff after a broker rejects a take-profit close. A crossed
   // trigger stays crossed, so without these the same rejected order would be
   // sent again on every tick for the rest of the trade.
   datetime               profit_retry_after;     // no attempt before this server time
   int                    profit_reject_count;    // consecutive rejections; latches the ladder off
};

// What the caller wants done to open stops on this pass.
//
// Passed as one object rather than as more positional arguments: the candle
// anchors, the closed-candle extremes and the tuning all change together, and a
// caller that set some of them and forgot the rest would trail against a mix of
// two different candles.
struct XSparkTrailPlan
{
   int      mode;                // EXSparkTrailMode
   double   anchor_long;         // candle anchor for a long, zero when absent
   double   anchor_short;
   bool     closed_candle_ready; // true once the closed-candle extremes below are trustworthy
   double   closed_high;
   double   closed_low;
   datetime closed_time;         // identifies the candle, so one candle updates a peak once
   double   atr;
   XSparkTrailTuning tuning;
   // Scaled profit taking for the same position on the same pass. It travels
   // with the trail for the same reason the anchors and the closed-candle
   // extremes do: both decide what happens to one open trade on one pass, and a
   // caller that set one and forgot the other would manage the trade by halves.
   // An empty ladder is the strategy's original behaviour and costs nothing.
   XSparkProfitLadder ladder;
};

void XSparkResetTrailPlan(XSparkTrailPlan &plan)
{
   plan.mode = XSPARK_TRAIL_ATR_AFTER_PARTIAL;
   plan.anchor_long = 0.0;
   plan.anchor_short = 0.0;
   plan.closed_candle_ready = false;
   plan.closed_high = 0.0;
   plan.closed_low = 0.0;
   plan.closed_time = 0;
   plan.atr = 0.0;
   XSparkResetTrailTuning(plan.tuning);
   XSparkResetProfitLadder(plan.ladder);
}

void XSparkResetTradeState(XSparkTradeState &state)
{
   state.ticket = 0;
   state.identifier = 0;
   state.direction = XSPARK_SIGNAL_NONE;
   state.entry = 0.0;
   state.initial_sl = 0.0;
   state.initial_tp = 0.0;
   state.initial_lots = 0.0;
   state.partial_done = false;
   state.current_trail_sl = 0.0;
   state.open_time = 0;
   state.entry_score = 0.0;
   state.signal_bar_time = 0;
   state.pattern_id = XSPARK_PATTERN_NONE;
   state.pattern_name = "NO PATTERN";
   state.initial_risk_distance = 0.0;
   state.mfe_price = 0.0;
   state.mae_price = 0.0;
   state.trail_peak = 0.0;
   state.trail_peak_time = 0;
   state.profit_high_water_r = 0.0;
   state.partial_block_logged = false;
   state.profit_block_logged = false;
   state.profit_retry_after = 0;
   state.profit_reject_count = 0;
}

#endif
