#ifndef XSPARK_TRADE_POSITION_MANAGER_MQH
#define XSPARK_TRADE_POSITION_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/StateStore.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Trade/TradeState.mqh>

class CXSparkPositionManager
{
private:
   bool   m_initialized;
   ulong  m_magic_number;
   string m_symbol;
   bool   m_use_stop_level_validation;
   int    m_managed_position_count;
   string m_last_reason;
   CTrade m_trade;
   CXSparkStateStore m_store;
   XSparkTradeState m_states[];

   int FindStateByTicket(const ulong ticket)
   {
      for(int index = 0; index < ArraySize(m_states); index++)
      {
         if(m_states[index].ticket == ticket)
            return index;
      }

      return -1;
   }

   int FindStateByIdentifier(const long identifier)
   {
      if(identifier == 0)
         return -1;

      for(int index = 0; index < ArraySize(m_states); index++)
      {
         if(m_states[index].identifier == identifier)
            return index;
      }

      return -1;
   }

   string PositionStateKey(const long identifier, const string field_name)
   {
      return StringFormat("p.%I64d.%s", identifier, field_name);
   }

   void PersistState(XSparkTradeState &state)
   {
      if(state.identifier == 0)
         return;

      m_store.Set(PositionStateKey(state.identifier, "d"), (double)state.direction);
      m_store.Set(PositionStateKey(state.identifier, "e"), state.entry);
      m_store.Set(PositionStateKey(state.identifier, "sl"), state.initial_sl);
      m_store.Set(PositionStateKey(state.identifier, "tp"), state.initial_tp);
      m_store.Set(PositionStateKey(state.identifier, "l"), state.initial_lots);
      m_store.Set(PositionStateKey(state.identifier, "pd"), state.partial_done ? 1.0 : 0.0);
      m_store.Set(PositionStateKey(state.identifier, "ts"), state.current_trail_sl);
      m_store.Set(PositionStateKey(state.identifier, "ot"), (double)state.open_time);
      m_store.Set(PositionStateKey(state.identifier, "sc"), state.entry_score);
      m_store.Set(PositionStateKey(state.identifier, "bt"), (double)state.signal_bar_time);
      m_store.Set(PositionStateKey(state.identifier, "pi"), (double)state.pattern_id);
      m_store.Set(PositionStateKey(state.identifier, "rd"), state.initial_risk_distance);
   }

   bool LoadPersistedState(XSparkTradeState &state)
   {
      if(state.identifier == 0)
         return false;

      if(!m_store.Has(PositionStateKey(state.identifier, "l")))
         return false;

      state.direction = (EXSparkSignalDirection)(int)m_store.Get(PositionStateKey(state.identifier, "d"), (double)state.direction);
      state.entry = m_store.Get(PositionStateKey(state.identifier, "e"), state.entry);
      state.initial_sl = m_store.Get(PositionStateKey(state.identifier, "sl"), state.initial_sl);
      state.initial_tp = m_store.Get(PositionStateKey(state.identifier, "tp"), state.initial_tp);
      state.initial_lots = m_store.Get(PositionStateKey(state.identifier, "l"), state.initial_lots);
      state.partial_done = m_store.Get(PositionStateKey(state.identifier, "pd"), 0.0) >= 0.5;
      state.current_trail_sl = m_store.Get(PositionStateKey(state.identifier, "ts"), state.current_trail_sl);
      state.open_time = (datetime)m_store.Get(PositionStateKey(state.identifier, "ot"), (double)state.open_time);
      state.entry_score = m_store.Get(PositionStateKey(state.identifier, "sc"), state.entry_score);
      state.signal_bar_time = (datetime)m_store.Get(PositionStateKey(state.identifier, "bt"), (double)state.signal_bar_time);
      state.pattern_id = (EXSparkScoreBotPatternId)(int)m_store.Get(PositionStateKey(state.identifier, "pi"), (double)state.pattern_id);
      state.pattern_name = XSparkPatternNameFromId(state.pattern_id);
      state.initial_risk_distance = m_store.Get(PositionStateKey(state.identifier, "rd"), state.initial_risk_distance);
      return true;
   }

   void ClearPersistedState(XSparkTradeState &state)
   {
      if(state.identifier == 0)
         return;

      m_store.Delete(PositionStateKey(state.identifier, "d"));
      m_store.Delete(PositionStateKey(state.identifier, "e"));
      m_store.Delete(PositionStateKey(state.identifier, "sl"));
      m_store.Delete(PositionStateKey(state.identifier, "tp"));
      m_store.Delete(PositionStateKey(state.identifier, "l"));
      m_store.Delete(PositionStateKey(state.identifier, "pd"));
      m_store.Delete(PositionStateKey(state.identifier, "ts"));
      m_store.Delete(PositionStateKey(state.identifier, "ot"));
      m_store.Delete(PositionStateKey(state.identifier, "sc"));
      m_store.Delete(PositionStateKey(state.identifier, "bt"));
      m_store.Delete(PositionStateKey(state.identifier, "pi"));
      m_store.Delete(PositionStateKey(state.identifier, "rd"));
   }

   void RemoveStateAt(const int index)
   {
      const int count = ArraySize(m_states);
      if(index < 0 || index >= count)
         return;

      for(int cursor = index; cursor < count - 1; cursor++)
         m_states[cursor] = m_states[cursor + 1];

      ArrayResize(m_states, count - 1);
   }

   bool PositionMatchesInstance()
   {
      const string symbol = PositionGetString(POSITION_SYMBOL);
      const long magic = PositionGetInteger(POSITION_MAGIC);

      return symbol == m_symbol && magic >= 0 && (ulong)magic == m_magic_number;
   }

   EXSparkSignalDirection PositionDirection()
   {
      const long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
         return XSPARK_SIGNAL_BUY;
      if(type == POSITION_TYPE_SELL)
         return XSPARK_SIGNAL_SELL;
      return XSPARK_SIGNAL_NONE;
   }

   bool AddOrUpdateSelectedPosition(const ulong ticket, CXSparkLogger &logger)
   {
      if(!PositionSelectByTicket(ticket) || !PositionMatchesInstance())
         return false;

      XSparkTradeState state;
      XSparkResetTradeState(state);
      state.ticket = ticket;
      state.identifier = PositionGetInteger(POSITION_IDENTIFIER);
      state.direction = PositionDirection();
      state.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      state.initial_sl = PositionGetDouble(POSITION_SL);
      state.initial_tp = PositionGetDouble(POSITION_TP);
      state.initial_lots = PositionGetDouble(POSITION_VOLUME);
      state.partial_done = false;
      state.current_trail_sl = state.initial_sl;
      state.open_time = (datetime)PositionGetInteger(POSITION_TIME);
      state.entry_score = 0.0;
      state.signal_bar_time = 0;
      state.pattern_id = XSPARK_PATTERN_NONE;
      state.pattern_name = XSparkPatternNameFromId(state.pattern_id);
      state.initial_risk_distance = MathAbs(state.entry - state.initial_sl);

      const int by_ticket = FindStateByTicket(ticket);
      if(by_ticket >= 0)
      {
         m_states[by_ticket].identifier = state.identifier;
         return true;
      }

      const int by_identifier = FindStateByIdentifier(state.identifier);
      if(by_identifier >= 0)
      {
         m_states[by_identifier].ticket = ticket;
         return true;
      }

      LoadPersistedState(state);

      const int size = ArraySize(m_states);
      ArrayResize(m_states, size + 1);
      m_states[size] = state;
      PersistState(m_states[size]);

      logger.Info("PositionManager",
                  StringFormat("Reconciled XSpark position ticket=%I64u identifier=%I64d direction=%s volume=%s entry=%s",
                               state.ticket,
                               state.identifier,
                               XSparkDirectionName(state.direction),
                               DoubleToString(state.initial_lots, 2),
                               DoubleToString(state.entry, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
      return true;
   }

   int CountMatchingLivePositions()
   {
      int count = 0;
      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         if(PositionMatchesInstance())
            count++;
      }

      return count;
   }

   bool ModifyPositionStops(const ulong ticket,
                            const double new_sl,
                            const double new_tp,
                            const string action,
                            CXSparkLogger &logger)
   {
      if(!PositionSelectByTicket(ticket) || !PositionMatchesInstance())
      {
         m_last_reason = "Position modify target is no longer an XSpark-managed position.";
         return false;
      }

      const double old_sl = PositionGetDouble(POSITION_SL);
      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      const bool local_result = m_trade.PositionModify(ticket, new_sl, new_tp);
      const long retcode = (long)m_trade.ResultRetcode();
      const string description = m_trade.ResultRetcodeDescription();

      logger.Info("PositionManager",
                  StringFormat("%s modify ticket=%I64u local_result=%s retcode=%I64d description=%s oldSL=%s newSL=%s TP=%s",
                               action,
                               ticket,
                               local_result ? "true" : "false",
                               retcode,
                               description,
                               DoubleToString(old_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                               DoubleToString(new_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                               DoubleToString(new_tp, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         m_last_reason = action + " stop modification confirmed.";
         return true;
      }

      m_last_reason = action + " stop modification rejected: " + description;
      return false;
   }

   bool ClosePartial(const ulong ticket,
                     const double volume,
                     CXSparkLogger &logger)
   {
      if(!PositionSelectByTicket(ticket) || !PositionMatchesInstance())
      {
         m_last_reason = "Partial-close target is no longer an XSpark-managed position.";
         return false;
      }

      const double volume_before = PositionGetDouble(POSITION_VOLUME);
      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      const bool local_result = m_trade.PositionClosePartial(ticket, volume);
      const long retcode = (long)m_trade.ResultRetcode();
      const string description = m_trade.ResultRetcodeDescription();

      logger.Info("PositionManager",
                  StringFormat("Partial close ticket=%I64u local_result=%s retcode=%I64d description=%s before=%s closed=%s",
                               ticket,
                               local_result ? "true" : "false",
                               retcode,
                               description,
                               DoubleToString(volume_before, 2),
                               DoubleToString(volume, 2)));

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         double remaining_volume = 0.0;
         if(PositionSelectByTicket(ticket) && PositionMatchesInstance())
            remaining_volume = PositionGetDouble(POSITION_VOLUME);

         logger.Info("PositionManager",
                     StringFormat("Partial confirmed ticket=%I64u volume_before=%s volume_closed=%s remaining_volume=%s",
                                  ticket,
                                  DoubleToString(volume_before, 2),
                                  DoubleToString(volume, 2),
                                  DoubleToString(remaining_volume, 2)));
         m_last_reason = "Partial close confirmed.";
         return true;
      }

      m_last_reason = "Partial close rejected: " + description;
      return false;
   }

   double LegalPartialCloseVolume(const double initial_volume,
                                  const double current_volume,
                                  const double close_pct)
   {
      const double volume_min = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      const double volume_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(initial_volume <= 0.0 || current_volume <= 0.0 || close_pct <= 0.0 ||
         volume_min <= 0.0 || volume_step <= 0.0)
      {
         return 0.0;
      }

      const double desired = initial_volume * close_pct / 100.0;
      const double close_volume = XSparkNormalizeVolumeDown(desired, volume_step);

      if(close_volume < volume_min || close_volume >= current_volume)
         return 0.0;

      return close_volume;
   }

   void LogClosureIfPossible(XSparkTradeState &state, CXSparkLogger &logger)
   {
      datetime to_time = TimeTradeServer();
      if(to_time == 0)
         to_time = TimeCurrent();

      datetime from_time = state.open_time > 0 ? state.open_time - 60 : to_time - 86400 * 30;
      if(!HistorySelect(from_time, to_time))
      {
         logger.Info("PositionManager",
                     StringFormat("Position ticket=%I64u no longer live; history selection failed.", state.ticket));
         return;
      }

      double profit = 0.0;
      double exit_price = 0.0;
      bool found = false;

      const int deals = HistoryDealsTotal();
      for(int index = 0; index < deals; index++)
      {
         const ulong deal = HistoryDealGetTicket(index);
         if(deal == 0)
            continue;

         if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_symbol)
            continue;

         const long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
         if(magic < 0 || (ulong)magic != m_magic_number)
            continue;

         const long position_id = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(state.identifier != 0 && position_id != state.identifier)
            continue;

         const long entry_type = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_OUT_BY)
         {
            profit += HistoryDealGetDouble(deal, DEAL_PROFIT);
            exit_price = HistoryDealGetDouble(deal, DEAL_PRICE);
            found = true;
         }
      }

      if(found)
      {
         logger.Info("PositionManager",
                     StringFormat("Closed XSpark position identifier=%I64d entry=%s exit=%s P/L=%s",
                                  state.identifier,
                                  DoubleToString(state.entry, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                                  DoubleToString(exit_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                                  DoubleToString(profit, 2)));
      }
      else
      {
         logger.Info("PositionManager",
                     StringFormat("Position ticket=%I64u identifier=%I64d no longer live; closure deal not found.",
                                  state.ticket,
                                  state.identifier));
      }
   }

public:
   CXSparkPositionManager()
   {
      m_initialized = false;
      m_magic_number = 0;
      m_symbol = "";
      m_use_stop_level_validation = true;
      m_managed_position_count = 0;
      m_last_reason = "Position manager is not initialized.";
   }

   bool Initialize(const string symbol,
                   const ulong magic_number,
                   const bool use_stop_level_validation = true)
   {
      if(symbol == "" || magic_number == 0)
      {
         m_last_reason = "PositionManager requires a symbol and non-zero Magic Number.";
         return false;
      }

      m_initialized = true;
      m_symbol = symbol;
      m_magic_number = magic_number;
      m_use_stop_level_validation = use_stop_level_validation;
      m_managed_position_count = 0;
      ArrayResize(m_states, 0);
      m_store.Initialize((long)AccountInfoInteger(ACCOUNT_LOGIN), m_symbol, m_magic_number);
      m_trade.SetExpertMagicNumber(m_magic_number);
      m_last_reason = "Position manager initialized.";
      return true;
   }

   bool Reconcile(CXSparkLogger &logger)
   {
      if(!m_initialized)
      {
         m_last_reason = "Position manager is not initialized.";
         return false;
      }

      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);

         if(ticket == 0)
            continue;

         if(!PositionSelectByTicket(ticket))
            continue;

         if(!PositionMatchesInstance())
            continue;

         AddOrUpdateSelectedPosition(ticket, logger);
      }

      for(int state_index = ArraySize(m_states) - 1; state_index >= 0; state_index--)
      {
         bool still_live = false;

         if(PositionSelectByTicket(m_states[state_index].ticket) && PositionMatchesInstance())
            still_live = true;

         if(!still_live && m_states[state_index].identifier != 0)
         {
            const int total_after = PositionsTotal();
            int match_count = 0;
            ulong matched_ticket = 0;

            for(int live_index = 0; live_index < total_after; live_index++)
            {
               const ulong candidate_ticket = PositionGetTicket(live_index);
               if(candidate_ticket == 0 || !PositionSelectByTicket(candidate_ticket) || !PositionMatchesInstance())
                  continue;

               if(PositionDirection() != m_states[state_index].direction)
                  continue;

               const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
               if(MathAbs(entry - m_states[state_index].entry) <= XSparkCanonicalPointsToPrice(1.0))
               {
                  match_count++;
                  matched_ticket = candidate_ticket;
               }
            }

            if(match_count == 1)
            {
               logger.Warn("PositionManager",
                           StringFormat("Rebinding XSpark state from ticket=%I64u to ticket=%I64u after broker ticket change.",
                                        m_states[state_index].ticket,
                                        matched_ticket));
               m_states[state_index].ticket = matched_ticket;
               PersistState(m_states[state_index]);
               still_live = true;
            }
            else if(match_count > 1)
            {
               logger.Error("PositionManager",
                            StringFormat("Ambiguous rebind for identifier=%I64d; preserving state and refusing to guess.",
                                         m_states[state_index].identifier));
               still_live = true;
            }
         }

         if(!still_live)
         {
            LogClosureIfPossible(m_states[state_index], logger);
            ClearPersistedState(m_states[state_index]);
            RemoveStateAt(state_index);
         }
      }

      m_managed_position_count = CountMatchingLivePositions();
      m_last_reason = "Position reconciliation completed against MT5 broker state.";
      return true;
   }

   bool RegisterNewTrade(XSparkTradePlan &plan,
                         XSparkExecutionResult &result,
                         CXSparkLogger &logger)
   {
      if(!m_initialized || !result.confirmed)
      {
         m_last_reason = "Cannot register unconfirmed execution.";
         return false;
      }

      const int total_positions = PositionsTotal();
      ulong best_ticket = 0;
      datetime best_time = 0;

      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionMatchesInstance())
            continue;

         if(PositionDirection() != plan.direction)
            continue;

         const datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
         if(open_time >= best_time)
         {
            best_ticket = ticket;
            best_time = open_time;
         }
      }

      if(best_ticket == 0 || !PositionSelectByTicket(best_ticket))
      {
         m_last_reason = "Execution was confirmed but matching live position was not found.";
         logger.Warn("PositionManager", m_last_reason);
         return false;
      }

      XSparkTradeState state;
      XSparkResetTradeState(state);
      state.ticket = best_ticket;
      state.identifier = PositionGetInteger(POSITION_IDENTIFIER);
      state.direction = plan.direction;
      state.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      state.initial_sl = plan.final_sl;
      state.initial_tp = plan.final_tp;
      state.initial_lots = PositionGetDouble(POSITION_VOLUME);
      state.partial_done = false;
      state.current_trail_sl = plan.final_sl;
      state.open_time = (datetime)PositionGetInteger(POSITION_TIME);
      state.entry_score = plan.score;
      state.signal_bar_time = plan.signal_bar_time;
      state.pattern_id = plan.pattern_id;
      state.pattern_name = plan.pattern_name;
      state.initial_risk_distance = MathAbs(state.entry - plan.final_sl);

      const int existing = FindStateByTicket(best_ticket);
      if(existing >= 0)
         m_states[existing] = state;
      else
      {
         const int size = ArraySize(m_states);
         ArrayResize(m_states, size + 1);
         m_states[size] = state;
      }

      PersistState(state);
      m_managed_position_count = CountMatchingLivePositions();
      m_last_reason = "New XSpark trade state registered.";

      logger.Info("PositionManager",
                  StringFormat("Registered XSpark trade ticket=%I64u identifier=%I64d direction=%s entry=%s SL=%s TP=%s lots=%s score=%.2f pattern=%s",
                               state.ticket,
                               state.identifier,
                               XSparkDirectionName(state.direction),
                               DoubleToString(state.entry, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                               DoubleToString(state.initial_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                               DoubleToString(state.initial_tp, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                               DoubleToString(state.initial_lots, 2),
                               state.entry_score,
                               state.pattern_name));
      return true;
   }

   void ManagePositions(const double bid,
                        const double ask,
                        const double atr14,
                        const double partial_tp_ratio,
                        const double partial_close_pct,
                        const double atr_mult_trail,
                        const bool use_weekend_close,
                        const int weekend_close_hour,
                        const int weekend_close_minute,
                        CXSparkLogger &logger)
   {
      if(!m_initialized)
         return;

      Reconcile(logger);

      datetime server_time = TimeTradeServer();
      if(server_time == 0)
         server_time = TimeCurrent();

      if(use_weekend_close && ShouldWeekendClose(server_time, weekend_close_hour, weekend_close_minute))
      {
         FlattenManagedExposure("Weekend close", logger, false);
         return;
      }

      for(int index = 0; index < ArraySize(m_states); index++)
      {
         XSparkTradeState state = m_states[index];
         if(!PositionSelectByTicket(state.ticket) || !PositionMatchesInstance())
            continue;

         const double current_volume = PositionGetDouble(POSITION_VOLUME);
         const double current_sl = PositionGetDouble(POSITION_SL);
         const double current_tp = PositionGetDouble(POSITION_TP);
         const double risk_distance = state.initial_risk_distance > 0.0 ?
                                      state.initial_risk_distance :
                                      MathAbs(state.entry - state.initial_sl);

         if(risk_distance <= 0.0)
            continue;

         const double exit_side_price = state.direction == XSPARK_SIGNAL_BUY ? bid : ask;

         if(!state.partial_done)
         {
            bool partial_triggered = false;

            if(state.direction == XSPARK_SIGNAL_BUY)
               partial_triggered = exit_side_price >= state.entry + partial_tp_ratio * risk_distance;
            else if(state.direction == XSPARK_SIGNAL_SELL)
               partial_triggered = exit_side_price <= state.entry - partial_tp_ratio * risk_distance;

            if(partial_triggered)
            {
               const double close_volume = LegalPartialCloseVolume(state.initial_lots,
                                                                   current_volume,
                                                                   partial_close_pct);

               if(close_volume > 0.0)
               {
                  logger.Info("PositionManager",
                              StringFormat("Partial trigger ticket=%I64u trigger_price=%s current_volume=%s close_volume=%s",
                                           state.ticket,
                                           DoubleToString(exit_side_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                                           DoubleToString(current_volume, 2),
                                           DoubleToString(close_volume, 2)));

                  if(ClosePartial(state.ticket, close_volume, logger))
                  {
                     Reconcile(logger);

                     int active_index = FindStateByIdentifier(state.identifier);
                     if(active_index < 0)
                        active_index = FindStateByTicket(state.ticket);

                     if(active_index >= 0 &&
                        PositionSelectByTicket(m_states[active_index].ticket) &&
                        PositionMatchesInstance())
                     {
                        m_states[active_index].partial_done = true;
                        PersistState(m_states[active_index]);

                        const double live_sl = PositionGetDouble(POSITION_SL);
                        const double live_tp = PositionGetDouble(POSITION_TP);

                        double adjusted_sl = 0.0;
                        double ignored_tp = 0.0;
                        string adjust_reason = "";
                        if(XSparkAdjustProtectionLevels(m_symbol,
                                                        m_states[active_index].direction,
                                                        exit_side_price,
                                                        m_states[active_index].entry,
                                                        0.0,
                                                        m_use_stop_level_validation,
                                                        adjusted_sl,
                                                        ignored_tp,
                                                        adjust_reason))
                        {
                           const bool tighter = m_states[active_index].direction == XSPARK_SIGNAL_BUY ?
                                                (live_sl == 0.0 || adjusted_sl > live_sl) :
                                                (live_sl == 0.0 || adjusted_sl < live_sl);

                           if(tighter && ModifyPositionStops(m_states[active_index].ticket, adjusted_sl, live_tp, "BE", logger))
                           {
                              m_states[active_index].current_trail_sl = adjusted_sl;
                              PersistState(m_states[active_index]);
                           }
                        }
                     }

                     continue;
                  }
               }
               else
               {
                  logger.Warn("PositionManager",
                              StringFormat("No legal partial-close volume for ticket=%I64u initial=%s current=%s pct=%.2f.",
                                           state.ticket,
                                           DoubleToString(state.initial_lots, 2),
                                           DoubleToString(current_volume, 2),
                                           partial_close_pct));
               }
            }
         }

         if(m_states[index].partial_done && atr14 > 0.0)
         {
            const double trail_distance = atr_mult_trail * atr14;
            double candidate_sl = 0.0;

            if(state.direction == XSPARK_SIGNAL_BUY)
               candidate_sl = bid - trail_distance;
            else if(state.direction == XSPARK_SIGNAL_SELL)
               candidate_sl = ask + trail_distance;

            double adjusted_sl = 0.0;
            double ignored_tp = 0.0;
            string adjust_reason = "";

            if(candidate_sl > 0.0 &&
               XSparkAdjustProtectionLevels(m_symbol,
                                            state.direction,
                                            exit_side_price,
                                            candidate_sl,
                                            0.0,
                                            m_use_stop_level_validation,
                                            adjusted_sl,
                                            ignored_tp,
                                            adjust_reason))
            {
               const double live_sl = PositionGetDouble(POSITION_SL);
               const bool tighter = state.direction == XSPARK_SIGNAL_BUY ?
                                    adjusted_sl > live_sl :
                                    (live_sl == 0.0 || adjusted_sl < live_sl);

               if(tighter && ModifyPositionStops(state.ticket, adjusted_sl, current_tp, "Trail", logger))
               {
                  logger.Info("PositionManager",
                              StringFormat("Trail updated ticket=%I64u oldSL=%s newSL=%s ATR=%s",
                                           state.ticket,
                                           DoubleToString(live_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                                           DoubleToString(adjusted_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                                           DoubleToString(atr14, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
                  m_states[index].current_trail_sl = adjusted_sl;
                  PersistState(m_states[index]);
               }
            }
         }
      }
   }

   bool ShouldWeekendClose(const datetime server_time,
                           const int close_hour,
                           const int close_minute)
   {
      MqlDateTime parts;
      TimeToStruct(server_time, parts);

      if(parts.day_of_week == 6 || parts.day_of_week == 0)
         return true;

      if(parts.day_of_week != 5)
         return false;

      if(parts.hour > close_hour)
         return true;

      return parts.hour == close_hour && parts.min >= close_minute;
   }

   void LogFlattenResult(CXSparkLogger &logger,
                         const bool critical,
                         const string message)
   {
      if(critical)
         logger.Critical("PositionManager", message);
      else
         logger.Info("PositionManager", message);
   }

   void FlattenManagedExposure(const string reason,
                               CXSparkLogger &logger,
                               const bool critical = true)
   {
      if(!m_initialized)
         return;

      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionMatchesInstance())
            continue;

         const bool local_result = m_trade.PositionClose(ticket);
         const long retcode = (long)m_trade.ResultRetcode();
         const string description = m_trade.ResultRetcodeDescription();

         LogFlattenResult(logger,
                          critical,
                          StringFormat("%s close ticket=%I64u local_result=%s retcode=%I64d description=%s",
                                       reason,
                                       ticket,
                                       local_result ? "true" : "false",
                                       retcode,
                                       description));
      }

      for(int order_index = OrdersTotal() - 1; order_index >= 0; order_index--)
      {
         const ulong order_ticket = OrderGetTicket(order_index);
         if(order_ticket == 0 || !OrderSelect(order_ticket))
            continue;

         const string order_symbol = OrderGetString(ORDER_SYMBOL);
         const long order_magic = OrderGetInteger(ORDER_MAGIC);

         if(order_symbol != m_symbol || order_magic < 0 || (ulong)order_magic != m_magic_number)
            continue;

         const bool local_result = m_trade.OrderDelete(order_ticket);
         const long retcode = (long)m_trade.ResultRetcode();
         const string description = m_trade.ResultRetcodeDescription();

         LogFlattenResult(logger,
                          critical,
                          StringFormat("%s delete pending order=%I64u local_result=%s retcode=%I64d description=%s",
                                       reason,
                                       order_ticket,
                                       local_result ? "true" : "false",
                                       retcode,
                                       description));
      }

      Reconcile(logger);
   }

   int CountEntryDealsSince(const datetime from_time, const datetime to_time)
   {
      if(!HistorySelect(from_time, to_time))
         return 0;

      int count = 0;
      const int deals = HistoryDealsTotal();

      for(int index = 0; index < deals; index++)
      {
         const ulong deal = HistoryDealGetTicket(index);
         if(deal == 0)
            continue;

         if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_symbol)
            continue;

         const long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
         if(magic < 0 || (ulong)magic != m_magic_number)
            continue;

         if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            count++;
      }

      return count;
   }

   int TradesToday()
   {
      datetime now = TimeTradeServer();
      if(now == 0)
         now = TimeCurrent();

      return CountEntryDealsSince(XSparkServerDayStart(now), now);
   }

   int TradesLast24Hours()
   {
      datetime now = TimeTradeServer();
      if(now == 0)
         now = TimeCurrent();

      return CountEntryDealsSince(now - 86400, now);
   }

   int ManagedPositionCount()
   {
      return m_managed_position_count;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
