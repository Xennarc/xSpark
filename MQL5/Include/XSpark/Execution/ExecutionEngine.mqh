#ifndef XSPARK_EXECUTION_ENGINE_MQH
#define XSPARK_EXECUTION_ENGINE_MQH

#include <Trade/Trade.mqh>
#include <XSpark/Core/ExecutionMath.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

#define XSPARK_EXECUTION_MAX_ATTEMPTS 3
#define XSPARK_DEAL_LOOKUP_ATTEMPTS 5
#define XSPARK_DEAL_LOOKUP_WINDOW_SECONDS 300

class CXSparkExecutionEngine
{
private:
   bool   m_initialized;
   ulong  m_magic_number;
   string m_order_comment;
   double m_deviation_canonical_points;
   bool   m_use_stop_level_validation;
   bool   m_use_margin_check;
   double m_margin_buffer_pct;
   double m_min_rr;
   double m_max_rr;
   int    m_max_quote_age_seconds;
   datetime m_last_submitted_signal_bar_time;
   string m_last_reason;
   CTrade m_trade;

   bool RetcodeIsSuccessful(const long retcode)
   {
      return retcode == TRADE_RETCODE_DONE ||
             retcode == TRADE_RETCODE_DONE_PARTIAL;
   }

   bool RetcodeIsTransientPriceFailure(const long retcode)
   {
      return retcode == TRADE_RETCODE_REQUOTE ||
             retcode == TRADE_RETCODE_PRICE_CHANGED ||
             retcode == TRADE_RETCODE_PRICE_OFF;
   }

   datetime ServerTime()
   {
      const datetime server_time = TimeTradeServer();
      return server_time == 0 ? TimeCurrent() : server_time;
   }

   int SymbolDigits(const string symbol)
   {
      return (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   }

   bool SymbolAllowsDirection(const string symbol, const EXSparkSignalDirection direction)
   {
      const long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);

      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED || trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      {
         m_last_reason = "Symbol trade mode does not allow new entries.";
         return false;
      }

      if(direction == XSPARK_SIGNAL_BUY && trade_mode == SYMBOL_TRADE_MODE_SHORTONLY)
      {
         m_last_reason = "Symbol trade mode is short-only; BUY is blocked.";
         return false;
      }

      if(direction == XSPARK_SIGNAL_SELL && trade_mode == SYMBOL_TRADE_MODE_LONGONLY)
      {
         m_last_reason = "Symbol trade mode is long-only; SELL is blocked.";
         return false;
      }

      return true;
   }

   // Recomputes the whole risk chain against the price we are about to trade at.
   // The ATR-derived stop stays where the strategy put it; the volume adapts so
   // the monetary risk stays at the selected risk percentage.
   bool RevalidateBeforeSend(XSparkTradePlan &plan,
                             CXSparkPositionSizer &sizer,
                             const double current_entry_reference,
                             double &send_sl,
                             double &send_tp,
                             double &send_volume,
                             double &send_risk_distance,
                             double &send_rr,
                             string &reason)
   {
      send_sl = 0.0;
      send_tp = 0.0;
      send_volume = 0.0;
      send_risk_distance = 0.0;
      send_rr = 0.0;
      reason = "";

      if(current_entry_reference <= 0.0)
      {
         reason = "Refreshed broker quote is invalid.";
         return false;
      }

      double drift = 0.0;
      const double max_drift_price = XSparkCanonicalPointsToPrice(m_deviation_canonical_points);

      if(!XSparkEntryDriftIsWithinTolerance(plan.entry_reference,
                                            current_entry_reference,
                                            max_drift_price,
                                            drift))
      {
         reason = StringFormat("Entry moved %.2f canonical points from the planned reference; permitted execution tolerance is %.2f.",
                               XSparkPriceToCanonicalPoints(drift),
                               m_deviation_canonical_points);
         return false;
      }

      if(!XSparkStopIsOnProtectiveSide(plan.direction, current_entry_reference, plan.theoretical_sl))
      {
         reason = "Price moved through the locked ATR stop before execution.";
         return false;
      }

      double candidate_sl = plan.theoretical_sl;
      double risk_distance = 0.0;
      double volume = 0.0;
      double final_sl = 0.0;
      double final_tp = 0.0;
      bool   stable = false;

      // Broker stop-level validation can move the stop once, which changes the
      // real stop distance, the volume and the target. Two bounded passes only.
      for(int pass = 1; pass <= 2 && !stable; pass++)
      {
         double adjusted_sl = 0.0;
         double ignored_tp = 0.0;
         string adjust_reason = "";

         if(!XSparkAdjustProtectionLevels(plan.symbol,
                                          plan.direction,
                                          current_entry_reference,
                                          candidate_sl,
                                          0.0,
                                          m_use_stop_level_validation,
                                          adjusted_sl,
                                          ignored_tp,
                                          adjust_reason))
         {
            reason = adjust_reason;
            return false;
         }

         risk_distance = XSparkRiskDistance(plan.direction, current_entry_reference, adjusted_sl);
         if(risk_distance <= 0.0)
         {
            reason = "Execution-time stop distance is invalid.";
            return false;
         }

         if(!sizer.CalculateVolume(plan.symbol,
                                   plan.risk_pct,
                                   current_entry_reference,
                                   adjusted_sl,
                                   volume))
         {
            reason = sizer.LastReason();
            return false;
         }

         const double target = XSparkTargetFromRiskDistance(plan.direction,
                                                            current_entry_reference,
                                                            risk_distance,
                                                            plan.dynamic_rr);
         if(target <= 0.0)
         {
            reason = "Execution-time target could not be derived from the locked reward ratio.";
            return false;
         }

         string pair_reason = "";
         if(!XSparkAdjustProtectionLevels(plan.symbol,
                                          plan.direction,
                                          current_entry_reference,
                                          adjusted_sl,
                                          target,
                                          m_use_stop_level_validation,
                                          final_sl,
                                          final_tp,
                                          pair_reason))
         {
            reason = pair_reason;
            return false;
         }

         if(MathAbs(final_sl - adjusted_sl) <= XSPARK_PRICE_EPSILON)
            stable = true;
         else
            candidate_sl = final_sl;
      }

      if(!stable)
      {
         reason = "Broker stop-level validation remained unstable at execution time.";
         return false;
      }

      const double realized_rr = XSparkRealizedRR(current_entry_reference, final_tp, risk_distance);
      if(!XSparkRRIsWithinBounds(realized_rr, m_min_rr, m_max_rr))
      {
         reason = StringFormat("Execution-time broker-valid RR %.4f is outside configured %.2f-%.2f.",
                               realized_rr,
                               m_min_rr,
                               m_max_rr);
         return false;
      }

      if(m_use_margin_check)
      {
         double required_margin = 0.0;
         double free_margin = 0.0;
         string margin_reason = "";

         if(!HasSufficientMargin(plan.symbol,
                                 plan.direction,
                                 volume,
                                 current_entry_reference,
                                 m_margin_buffer_pct,
                                 required_margin,
                                 free_margin,
                                 margin_reason))
         {
            reason = margin_reason;
            return false;
         }
      }

      send_sl = final_sl;
      send_tp = final_tp;
      send_volume = volume;
      send_risk_distance = risk_distance;
      send_rr = realized_rr;
      reason = "Execution-time risk revalidation passed.";
      return true;
   }

   // Binds the confirmed entry to the exact broker position using the deal that
   // the trade server actually produced.
   void ResolveExecutedPosition(const string symbol,
                                XSparkExecutionResult &result,
                                CXSparkLogger &logger)
   {
      if(result.deal_ticket == 0)
      {
         logger.Error("ExecutionEngine",
                      "Trade server confirmed execution without a deal ticket; exact position identification is unavailable.");
         return;
      }

      bool deal_selected = false;

      for(int attempt = 1; attempt <= XSPARK_DEAL_LOOKUP_ATTEMPTS && !deal_selected; attempt++)
      {
         if(HistoryDealSelect(result.deal_ticket))
         {
            deal_selected = true;
            break;
         }

         const datetime now = ServerTime();
         HistorySelect(now - XSPARK_DEAL_LOOKUP_WINDOW_SECONDS, now + XSPARK_DEAL_LOOKUP_WINDOW_SECONDS);

         if(HistoryDealSelect(result.deal_ticket))
            deal_selected = true;
      }

      if(!deal_selected)
      {
         logger.Error("ExecutionEngine",
                      StringFormat("Deal %I64u could not be selected from MT5 history; exact position identification is unavailable.",
                                   result.deal_ticket));
         return;
      }

      result.position_id = HistoryDealGetInteger(result.deal_ticket, DEAL_POSITION_ID);
      result.fill_price = HistoryDealGetDouble(result.deal_ticket, DEAL_PRICE);
      result.fill_volume = HistoryDealGetDouble(result.deal_ticket, DEAL_VOLUME);
      result.fill_time = (datetime)HistoryDealGetInteger(result.deal_ticket, DEAL_TIME);
      result.position_id_exact = result.position_id != 0;

      if(!result.position_id_exact)
      {
         logger.Error("ExecutionEngine",
                      StringFormat("Deal %I64u exposes no DEAL_POSITION_ID; exact position identification is unavailable.",
                                   result.deal_ticket));
         return;
      }

      const int total_positions = PositionsTotal();
      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         const long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic < 0 || (ulong)magic != m_magic_number)
            continue;

         if(!XSparkPositionIdentityMatches(PositionGetInteger(POSITION_IDENTIFIER), result.position_id))
            continue;

         result.position_ticket = ticket;
         break;
      }

      if(result.position_ticket == 0)
      {
         logger.Warn("ExecutionEngine",
                     StringFormat("Broker position id %I64d from deal %I64u is not live; it may already be closed.",
                                  result.position_id,
                                  result.deal_ticket));
      }

      logger.Info("ExecutionEngine",
                  StringFormat("Resolved execution deal=%I64u order=%I64u position_id=%I64d position_ticket=%I64u fill_price=%s fill_volume=%s",
                               result.deal_ticket,
                               result.order_ticket,
                               result.position_id,
                               result.position_ticket,
                               DoubleToString(result.fill_price, SymbolDigits(symbol)),
                               DoubleToString(result.fill_volume, 2)));
   }

public:
   CXSparkExecutionEngine()
   {
      m_initialized = false;
      m_magic_number = 0;
      m_order_comment = XSPARK_SCOREBOT_COMMENT_DEFAULT;
      m_deviation_canonical_points = XSPARK_SCOREBOT_DEVIATION_CANONICAL_POINTS;
      m_use_stop_level_validation = true;
      m_use_margin_check = true;
      m_margin_buffer_pct = 20.0;
      m_min_rr = 1.5;
      m_max_rr = 3.0;
      m_max_quote_age_seconds = 15;
      m_last_submitted_signal_bar_time = 0;
      m_last_reason = "Execution engine is not initialized; broker execution is disabled.";
   }

   bool Initialize(const ulong magic_number,
                   const string order_comment,
                   const double deviation_canonical_points,
                   const bool use_stop_level_validation,
                   const bool use_margin_check,
                   const double margin_buffer_pct,
                   const double min_rr,
                   const double max_rr,
                   const int max_quote_age_seconds)
   {
      if(magic_number == 0)
      {
         m_last_reason = "Magic Number must be explicit and non-zero.";
         return false;
      }

      if(deviation_canonical_points <= 0.0)
      {
         m_last_reason = "Execution deviation tolerance must be positive.";
         return false;
      }

      if(min_rr <= 0.0 || max_rr < min_rr)
      {
         m_last_reason = "Execution reward-ratio bounds are invalid.";
         return false;
      }

      if(margin_buffer_pct < 0.0 || max_quote_age_seconds <= 0)
      {
         m_last_reason = "Execution margin buffer or maximum quote age is invalid.";
         return false;
      }

      m_initialized = true;
      m_magic_number = magic_number;
      m_order_comment = order_comment;
      m_deviation_canonical_points = deviation_canonical_points;
      m_use_stop_level_validation = use_stop_level_validation;
      m_use_margin_check = use_margin_check;
      m_margin_buffer_pct = margin_buffer_pct;
      m_min_rr = min_rr;
      m_max_rr = max_rr;
      m_max_quote_age_seconds = max_quote_age_seconds;
      m_last_submitted_signal_bar_time = 0;
      m_trade.SetExpertMagicNumber(m_magic_number);
      m_last_reason = "Execution engine initialized.";
      return true;
   }

   bool ValidateInitialProtection(const XSparkTradePlan &plan,
                                  const bool use_stop_level_validation,
                                  double &adjusted_sl,
                                  double &adjusted_tp,
                                  string &reason)
   {
      if(!m_initialized)
      {
         m_last_reason = "Execution engine is not initialized; broker execution is disabled.";
         reason = m_last_reason;
         return false;
      }

      return XSparkAdjustProtectionLevels(plan.symbol,
                                          plan.direction,
                                          plan.entry_reference,
                                          plan.final_sl,
                                          plan.final_tp,
                                          use_stop_level_validation,
                                          adjusted_sl,
                                          adjusted_tp,
                                          reason);
   }

   bool HasSufficientMargin(const string symbol,
                            const EXSparkSignalDirection direction,
                            const double volume,
                            const double price,
                            const double margin_buffer_pct,
                            double &required_margin,
                            double &free_margin,
                            string &reason)
   {
      required_margin = 0.0;
      free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      reason = "";

      if(!m_initialized)
      {
         reason = "Execution engine is not initialized; margin cannot be validated.";
         m_last_reason = reason;
         return false;
      }

      if(symbol == "" || volume <= 0.0 || price <= 0.0)
      {
         reason = "Invalid margin-check inputs.";
         m_last_reason = reason;
         return false;
      }

      ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY;
      if(direction == XSPARK_SIGNAL_SELL)
         order_type = ORDER_TYPE_SELL;
      else if(direction != XSPARK_SIGNAL_BUY)
      {
         reason = "Margin check requires BUY or SELL direction.";
         m_last_reason = reason;
         return false;
      }

      double raw_margin = 0.0;
      if(!OrderCalcMargin(order_type, symbol, volume, price, raw_margin))
      {
         reason = StringFormat("OrderCalcMargin failed with error %d.", GetLastError());
         m_last_reason = reason;
         return false;
      }

      required_margin = raw_margin * (1.0 + margin_buffer_pct / 100.0);

      if(free_margin < required_margin)
      {
         reason = StringFormat("Free margin %.2f is below required buffered margin %.2f.",
                               free_margin,
                               required_margin);
         m_last_reason = reason;
         return false;
      }

      reason = "Margin check passed.";
      m_last_reason = reason;
      return true;
   }

   bool CanSubmitSignal(const datetime signal_bar_time)
   {
      string reason = "";
      if(!XSparkSignalBarIsSubmittable(m_last_submitted_signal_bar_time, signal_bar_time, reason))
      {
         m_last_reason = reason;
         return false;
      }

      return true;
   }

   bool ExecuteApprovedPlan(XSparkTradePlan &plan,
                            CXSparkPositionSizer &sizer,
                            XSparkExecutionResult &result,
                            CXSparkLogger &logger)
   {
      XSparkResetExecutionResult(result);

      if(!m_initialized)
      {
         m_last_reason = "Execution engine is not initialized; broker execution is disabled.";
         return false;
      }

      if(plan.direction == XSPARK_SIGNAL_NONE || plan.volume <= 0.0)
      {
         m_last_reason = "No executable direction and volume were provided.";
         return false;
      }

      if(!SymbolAllowsDirection(plan.symbol, plan.direction))
         return false;

      if(!CanSubmitSignal(plan.signal_bar_time))
         return false;

      // The signal bar is consumed before the first send attempt on purpose: a
      // bar that reached the broker boundary must never be retried, even when
      // revalidation or the send itself later aborts.
      m_last_submitted_signal_bar_time = plan.signal_bar_time;

      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(plan.symbol);

      const double deviation_broker_points = XSparkCanonicalPointsToBrokerPoints(plan.symbol,
                                                                                 m_deviation_canonical_points);
      m_trade.SetDeviationInPoints((ulong)MathRound(deviation_broker_points));

      const int digits = SymbolDigits(plan.symbol);

      for(int attempt = 1; attempt <= XSPARK_EXECUTION_MAX_ATTEMPTS; attempt++)
      {
         MqlTick tick;
         if(!SymbolInfoTick(plan.symbol, tick))
         {
            m_last_reason = StringFormat("Unable to refresh tick before send attempt %d.", attempt);
            logger.Error("ExecutionEngine", m_last_reason);
            return false;
         }

         long quote_age = 0;
         string quote_reason = "";
         if(!XSparkQuoteAgeIsAcceptable(tick.time, ServerTime(), m_max_quote_age_seconds, quote_age, quote_reason))
         {
            m_last_reason = StringFormat("Stale or invalid quote before send attempt %d: %s",
                                         attempt,
                                         quote_reason);
            logger.Warn("ExecutionEngine", m_last_reason);
            return false;
         }

         // Normalized once so the drift check, the sizing distance, the value
         // sent to the broker and the recorded result all use the same price.
         const double current_entry_reference =
            XSparkNormalizePrice(plan.symbol,
                                 plan.direction == XSPARK_SIGNAL_BUY ? tick.ask : tick.bid);

         double send_sl = 0.0;
         double send_tp = 0.0;
         double send_volume = 0.0;
         double send_risk_distance = 0.0;
         double send_rr = 0.0;
         string revalidation_reason = "";

         if(!RevalidateBeforeSend(plan,
                                  sizer,
                                  current_entry_reference,
                                  send_sl,
                                  send_tp,
                                  send_volume,
                                  send_risk_distance,
                                  send_rr,
                                  revalidation_reason))
         {
            m_last_reason = StringFormat("Execution-time risk revalidation aborted the entry on attempt %d: %s",
                                         attempt,
                                         revalidation_reason);
            logger.Warn("ExecutionEngine", m_last_reason);
            return false;
         }

         logger.Info("ExecutionEngine",
                     StringFormat("Attempt %d revalidated planned_entry=%s send_entry=%s planned_SL=%s send_SL=%s planned_TP=%s send_TP=%s planned_lots=%s send_lots=%s risk_distance=%.2f canonical points RR=%.4f risk_pct=%.2f",
                                  attempt,
                                  DoubleToString(plan.entry_reference, digits),
                                  DoubleToString(current_entry_reference, digits),
                                  DoubleToString(plan.final_sl, digits),
                                  DoubleToString(send_sl, digits),
                                  DoubleToString(plan.final_tp, digits),
                                  DoubleToString(send_tp, digits),
                                  DoubleToString(plan.volume, 2),
                                  DoubleToString(send_volume, 2),
                                  XSparkPriceToCanonicalPoints(send_risk_distance),
                                  send_rr,
                                  plan.risk_pct));

         result.submit_time = ServerTime();
         result.submitted_entry_reference = current_entry_reference;
         result.submitted_sl = send_sl;
         result.submitted_tp = send_tp;
         result.submitted_volume = send_volume;
         result.actual_risk_distance = send_risk_distance;
         result.actual_rr = send_rr;

         bool local_result = false;
         if(plan.direction == XSPARK_SIGNAL_BUY)
            local_result = m_trade.Buy(send_volume, plan.symbol, current_entry_reference, send_sl, send_tp, m_order_comment);
         else
            local_result = m_trade.Sell(send_volume, plan.symbol, current_entry_reference, send_sl, send_tp, m_order_comment);

         result.retcode = (long)m_trade.ResultRetcode();
         result.retcode_description = m_trade.ResultRetcodeDescription();
         result.order_ticket = m_trade.ResultOrder();
         result.deal_ticket = m_trade.ResultDeal();
         result.price = m_trade.ResultPrice();
         result.volume = m_trade.ResultVolume();

         logger.Info("ExecutionEngine",
                     StringFormat("Attempt %d local_result=%s retcode=%I64d description=%s order=%I64u deal=%I64u requested_price=%s result_price=%s volume=%s",
                                  attempt,
                                  local_result ? "true" : "false",
                                  result.retcode,
                                  result.retcode_description,
                                  result.order_ticket,
                                  result.deal_ticket,
                                  DoubleToString(current_entry_reference, digits),
                                  DoubleToString(result.price, digits),
                                  DoubleToString(result.volume, 2)));

         if(RetcodeIsSuccessful(result.retcode))
         {
            result.confirmed = true;

            // The plan now carries what was actually submitted so logging,
            // annotation and state registration never use stale planning values.
            plan.entry_reference = current_entry_reference;
            plan.final_sl = send_sl;
            plan.final_tp = send_tp;
            plan.volume = send_volume;
            plan.risk_distance = send_risk_distance;

            ResolveExecutedPosition(plan.symbol, result, logger);

            m_last_reason = "Broker execution confirmed by trade-server retcode.";
            return true;
         }

         if(!RetcodeIsTransientPriceFailure(result.retcode))
         {
            m_last_reason = StringFormat("Permanent or non-retriable execution failure: %I64d %s.",
                                         result.retcode,
                                         result.retcode_description);
            return false;
         }
      }

      m_last_reason = StringFormat("Execution failed after %d transient price attempts.",
                                   XSPARK_EXECUTION_MAX_ATTEMPTS);
      return false;
   }

   ulong MagicNumber()
   {
      return m_magic_number;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
