#ifndef XSPARK_TRADE_TRADE_STATE_MQH
#define XSPARK_TRADE_TRADE_STATE_MQH

#include <XSpark/Strategy/ScoreBotTypes.mqh>

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
   bool                   partial_block_logged;   // RAM-only: throttles the "no legal partial" warning
};

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
   state.partial_block_logged = false;
}

#endif
