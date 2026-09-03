#ifndef XSPARK_EXECUTION_ENGINE_MQH
#define XSPARK_EXECUTION_ENGINE_MQH

#include <Trade/Trade.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

class CXSparkExecutionEngine
{
private:
   bool   m_initialized;
   ulong  m_magic_number;
   string m_order_comment;
   double m_deviation_canonical_points;
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

public:
   CXSparkExecutionEngine()
   {
      m_initialized = false;
      m_magic_number = 0;
      m_order_comment = XSPARK_SCOREBOT_COMMENT_DEFAULT;
      m_deviation_canonical_points = XSPARK_SCOREBOT_DEVIATION_CANONICAL_POINTS;
      m_last_submitted_signal_bar_time = 0;
      m_last_reason = "Execution engine is not initialized; broker execution is disabled.";
   }

   bool Initialize(const ulong magic_number,
                   const string order_comment = XSPARK_SCOREBOT_COMMENT_DEFAULT,
                   const double deviation_canonical_points = XSPARK_SCOREBOT_DEVIATION_CANONICAL_POINTS)
   {
      if(magic_number == 0)
      {
         m_last_reason = "Magic Number must be explicit and non-zero.";
         return false;
      }

      m_initialized = true;
      m_magic_number = magic_number;
      m_order_comment = order_comment;
      m_deviation_canonical_points = deviation_canonical_points;
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
      if(signal_bar_time <= 0)
      {
         m_last_reason = "Signal bar time is invalid.";
         return false;
      }

      if(m_last_submitted_signal_bar_time == signal_bar_time)
      {
         m_last_reason = "Duplicate signal-bar submission blocked.";
         return false;
      }

      return true;
   }

   bool ExecuteApprovedPlan(XSparkTradePlan &plan,
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

      m_last_submitted_signal_bar_time = plan.signal_bar_time;

      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(plan.symbol);

      const double deviation_broker_points = XSparkCanonicalPointsToBrokerPoints(plan.symbol,
                                                                                 m_deviation_canonical_points);
      m_trade.SetDeviationInPoints((ulong)MathRound(deviation_broker_points));

      for(int attempt = 1; attempt <= 3; attempt++)
      {
         MqlTick tick;
         if(!SymbolInfoTick(plan.symbol, tick))
         {
            m_last_reason = StringFormat("Unable to refresh tick before send attempt %d.", attempt);
            logger.Error("ExecutionEngine", m_last_reason);
            return false;
         }

         bool local_result = false;
         const double send_price = plan.direction == XSPARK_SIGNAL_BUY ? tick.ask : tick.bid;
         if(plan.direction == XSPARK_SIGNAL_BUY)
            local_result = m_trade.Buy(plan.volume, plan.symbol, send_price, plan.final_sl, plan.final_tp, m_order_comment);
         else
            local_result = m_trade.Sell(plan.volume, plan.symbol, send_price, plan.final_sl, plan.final_tp, m_order_comment);

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
                                  DoubleToString(send_price, (int)SymbolInfoInteger(plan.symbol, SYMBOL_DIGITS)),
                                  DoubleToString(result.price, (int)SymbolInfoInteger(plan.symbol, SYMBOL_DIGITS)),
                                  DoubleToString(result.volume, 2)));

         if(RetcodeIsSuccessful(result.retcode))
         {
            result.confirmed = true;
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

      m_last_reason = "Execution failed after 3 transient price attempts.";
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
