#ifndef XSPARK_TRADE_POSITION_MANAGER_MQH
#define XSPARK_TRADE_POSITION_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <XSpark/Core/ExecutionMath.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/StateStore.mqh>
#include <XSpark/Core/SymbolMath.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Trade/TradeState.mqh>

// Flattening keeps retrying until no XSpark exposure remains, but broker
// retries and CRITICAL logging are paced so a latched killswitch cannot flood
// the journal on every tick.
#define XSPARK_FLATTEN_RETRY_INTERVAL_SECONDS 2
#define XSPARK_FLATTEN_LOG_INTERVAL_SECONDS 30
#define XSPARK_PROTECTION_REPAIR_INTERVAL_SECONDS 5

// Exits must not fail on price movement. Closing an XSpark position at a
// slightly worse price is always better than failing to close it, so exit
// operations use a wider tolerance than the 30-point entry deviation.
#define XSPARK_CLOSE_DEVIATION_CANONICAL_POINTS 100.0

class CXSparkPositionManager
{
private:
   bool   m_initialized;
   ulong  m_magic_number;
   string m_symbol;
   bool   m_use_stop_level_validation;
   int    m_managed_position_count;
   string m_last_reason;
   bool   m_last_registration_bound_state;
   bool   m_last_registration_position_closed;
   string m_flatten_campaign_reason;
   datetime m_flatten_last_attempt_time;
   datetime m_flatten_last_log_time;
   int    m_flatten_attempts;
   int    m_flatten_remaining_exposure;
   string m_flatten_last_signature;
   datetime m_last_protection_repair_time;
   CTrade m_trade;
   CXSparkStateStore m_store;
   XSparkTradeState m_states[];

   datetime ServerTimeNow()
   {
      const datetime server_time = TimeTradeServer();
      return server_time == 0 ? TimeCurrent() : server_time;
   }

   int SymbolDigits()
   {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   }

   // A throttle must never be able to stall a safety retry. A server clock that
   // moves backwards releases the throttle instead of holding it.
   bool ThrottleHolds(const datetime last_time, const datetime now, const int interval_seconds)
   {
      const long elapsed = (long)now - (long)last_time;
      return elapsed >= 0 && elapsed < (long)interval_seconds;
   }

   // CTrade defaults to a 10-point deviation, which is far too tight for gold
   // exits. Every XSpark-owned mutation goes through this.
   void PrepareTradeContext()
   {
      m_trade.SetExpertMagicNumber(m_magic_number);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      const double deviation_broker_points =
         XSparkCanonicalPointsToBrokerPoints(m_symbol, XSPARK_CLOSE_DEVIATION_CANONICAL_POINTS);

      if(deviation_broker_points > 0.0)
         m_trade.SetDeviationInPoints((ulong)MathRound(deviation_broker_points));
   }

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

   int CountMatchingPendingOrders()
   {
      int count = 0;

      for(int index = OrdersTotal() - 1; index >= 0; index--)
      {
         const ulong order_ticket = OrderGetTicket(index);
         if(order_ticket == 0 || !OrderSelect(order_ticket))
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         const long order_magic = OrderGetInteger(ORDER_MAGIC);
         if(order_magic < 0 || (ulong)order_magic != m_magic_number)
            continue;

         count++;
      }

      return count;
   }

   // Returns how many live XSpark positions carry the broker position id and
   // reports the first one. Anything other than exactly one match is ambiguous.
   int FindLiveTicketByIdentifier(const long identifier, ulong &ticket)
   {
      ticket = 0;

      if(identifier == 0)
         return 0;

      int matches = 0;
      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong candidate = PositionGetTicket(index);
         if(candidate == 0 || !PositionSelectByTicket(candidate) || !PositionMatchesInstance())
            continue;

         if(!XSparkPositionIdentityMatches(PositionGetInteger(POSITION_IDENTIFIER), identifier))
            continue;

         matches++;
         if(ticket == 0)
            ticket = candidate;
      }

      return matches;
   }

   // Documented fail-safe fallback used only when the broker deal did not yield
   // a position id. It refuses any position that is already tracked, that opened
   // before the send, that has the wrong direction, or whose volume does not
   // match what was submitted, so an existing XSpark position can never be
   // mistaken for the new one.
   int FindFallbackTicket(XSparkTradePlan &plan,
                          XSparkExecutionResult &result,
                          ulong &ticket)
   {
      ticket = 0;

      const double volume_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      const double volume_tolerance = volume_step > 0.0 ? volume_step / 2.0 : 0.0;
      // Compare against what the broker actually executed, so a partial fill is
      // still recognisable. The requested volume is only a last resort.
      double submitted_volume = result.fill_volume;
      if(submitted_volume <= 0.0)
         submitted_volume = result.volume;
      if(submitted_volume <= 0.0)
         submitted_volume = result.submitted_volume;

      int matches = 0;
      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong candidate = PositionGetTicket(index);
         if(candidate == 0 || !PositionSelectByTicket(candidate) || !PositionMatchesInstance())
            continue;

         const long identifier = PositionGetInteger(POSITION_IDENTIFIER);
         const bool tracked = FindStateByTicket(candidate) >= 0 || FindStateByIdentifier(identifier) >= 0;

         if(!XSparkFallbackPositionIsAcceptable(plan.direction,
                                                PositionDirection(),
                                                tracked,
                                                (datetime)PositionGetInteger(POSITION_TIME),
                                                result.submit_time,
                                                PositionGetDouble(POSITION_VOLUME),
                                                submitted_volume,
                                                volume_tolerance))
         {
            continue;
         }

         matches++;
         if(ticket == 0)
            ticket = candidate;
      }

      return matches;
   }

   // Builds managed state from broker truth for the identified position and
   // enriches it with the strategy metadata of the plan that created it.
   bool BindStateToTicket(const ulong ticket,
                          XSparkTradePlan &plan,
                          XSparkExecutionResult &result,
                          CXSparkLogger &logger)
   {
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionMatchesInstance())
      {
         m_last_reason = "Execution was confirmed but the identified position is not a live XSpark position.";
         logger.Critical("PositionManager", m_last_reason);
         return false;
      }

      const long identifier = PositionGetInteger(POSITION_IDENTIFIER);
      const EXSparkSignalDirection live_direction = PositionDirection();

      if(live_direction != plan.direction)
      {
         m_last_reason = StringFormat("Identified position ticket=%I64u direction %s does not match executed plan direction %s; refusing to bind state.",
                                      ticket,
                                      XSparkDirectionName(live_direction),
                                      XSparkDirectionName(plan.direction));
         logger.Critical("PositionManager", m_last_reason);
         return false;
      }

      double live_sl = PositionGetDouble(POSITION_SL);
      double live_tp = PositionGetDouble(POSITION_TP);
      const double submitted_sl = result.submitted_sl > 0.0 ? result.submitted_sl : plan.final_sl;
      const double submitted_tp = result.submitted_tp > 0.0 ? result.submitted_tp : plan.final_tp;

      // A confirmed retcode proves the order was accepted, not that the broker
      // applied the protection that was sent with it. Unprotected exposure must
      // never be recorded as protected.
      if(live_sl <= 0.0 && submitted_sl > 0.0)
      {
         logger.Critical("PositionManager",
                         StringFormat("Position ticket=%I64u opened WITHOUT a broker stop; applying the submitted protection %s immediately.",
                                      ticket,
                                      DoubleToString(submitted_sl, SymbolDigits())));

         if(ModifyPositionStops(ticket, submitted_sl, submitted_tp, "Missing protection", logger) &&
            PositionSelectByTicket(ticket) && PositionMatchesInstance())
         {
            live_sl = PositionGetDouble(POSITION_SL);
            live_tp = PositionGetDouble(POSITION_TP);
         }
      }

      XSparkTradeState state;
      XSparkResetTradeState(state);
      state.ticket = ticket;
      state.identifier = identifier;
      state.direction = live_direction;
      state.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      state.initial_sl = live_sl > 0.0 ? live_sl : submitted_sl;
      state.initial_tp = live_tp > 0.0 ? live_tp : submitted_tp;
      state.initial_lots = PositionGetDouble(POSITION_VOLUME);
      state.partial_done = false;
      state.current_trail_sl = state.initial_sl;
      state.open_time = (datetime)PositionGetInteger(POSITION_TIME);
      state.entry_score = plan.score;
      state.signal_bar_time = plan.signal_bar_time;
      state.pattern_id = plan.pattern_id;
      state.pattern_name = plan.pattern_name;
      state.initial_risk_distance = MathAbs(state.entry - state.initial_sl);

      if(live_sl > 0.0 && submitted_sl > 0.0 &&
         MathAbs(live_sl - submitted_sl) > XSparkCanonicalPointsToPrice(1.0))
      {
         logger.Warn("PositionManager",
                     StringFormat("Broker stop %s differs from submitted stop %s on ticket=%I64u; broker value is authoritative.",
                                  DoubleToString(live_sl, SymbolDigits()),
                                  DoubleToString(submitted_sl, SymbolDigits()),
                                  ticket));
      }

      if(state.initial_risk_distance <= 0.0)
      {
         logger.Error("PositionManager",
                      StringFormat("Registered position ticket=%I64u has no usable initial risk distance; partial and trailing management will stay inactive until a stop exists.",
                                   ticket));
      }

      int existing = FindStateByIdentifier(identifier);
      if(existing < 0)
         existing = FindStateByTicket(ticket);

      // On a netting account a second entry merges into an existing position id.
      // Two independent signals then point at one broker position, and binding
      // the new state over the old one would silently reset partial_done and the
      // initial lots of a trade that is already being managed. Detect it from
      // the broker position's own open time and from any state that already
      // claims the identifier for a different signal bar.
      const bool merged_into_existing_position =
         result.submit_time > 0 &&
         state.open_time > 0 &&
         (long)state.open_time + XSPARK_FALLBACK_OPEN_TIME_TOLERANCE_SECONDS < (long)result.submit_time;

      const bool claimed_by_other_signal =
         existing >= 0 &&
         m_states[existing].signal_bar_time != 0 &&
         m_states[existing].signal_bar_time != plan.signal_bar_time;

      if(merged_into_existing_position || claimed_by_other_signal)
      {
         m_last_reason = StringFormat("Broker position identifier=%I64d opened at %s already existed before this entry was submitted at %s; refusing to attach the new trade state to it.",
                                      identifier,
                                      TimeToString(state.open_time, TIME_DATE | TIME_MINUTES),
                                      TimeToString(result.submit_time, TIME_DATE | TIME_MINUTES));
         logger.Critical("PositionManager", m_last_reason);
         return false;
      }

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
      m_last_registration_bound_state = true;

      logger.Info("PositionManager",
                  StringFormat("Registered XSpark trade ticket=%I64u identifier=%I64d deal=%I64u direction=%s entry=%s SL=%s TP=%s lots=%s score=%.2f pattern=%s",
                               state.ticket,
                               state.identifier,
                               result.deal_ticket,
                               XSparkDirectionName(state.direction),
                               DoubleToString(state.entry, SymbolDigits()),
                               DoubleToString(state.initial_sl, SymbolDigits()),
                               DoubleToString(state.initial_tp, SymbolDigits()),
                               DoubleToString(state.initial_lots, 2),
                               state.entry_score,
                               state.pattern_name));

      // The state is recorded so protective management can keep trying, but an
      // unprotected broker position is not a healthy registration.
      if(live_sl <= 0.0)
      {
         m_last_reason = StringFormat("Position ticket=%I64u is live without a broker stop; XSpark exposure is unprotected until the stop is applied.",
                                      ticket);
         logger.Critical("PositionManager", m_last_reason);
         return false;
      }

      return true;
   }

   // An XSpark position must never sit at the broker without a stop. This runs
   // on every management pass and keeps retrying, paced so a broker that keeps
   // rejecting the stop cannot flood the journal.
   void RepairMissingProtection(const datetime server_time, CXSparkLogger &logger)
   {
      if(m_last_protection_repair_time > 0 &&
         ThrottleHolds(m_last_protection_repair_time, server_time, XSPARK_PROTECTION_REPAIR_INTERVAL_SECONDS))
      {
         return;
      }

      bool attempted = false;

      for(int index = 0; index < ArraySize(m_states); index++)
      {
         if(!PositionSelectByTicket(m_states[index].ticket) || !PositionMatchesInstance())
            continue;

         if(PositionGetDouble(POSITION_SL) > 0.0)
            continue;

         const double desired_sl = m_states[index].current_trail_sl > 0.0 ?
                                   m_states[index].current_trail_sl :
                                   m_states[index].initial_sl;

         if(desired_sl <= 0.0)
         {
            logger.Critical("PositionManager",
                            StringFormat("Position ticket=%I64u has no broker stop and no recorded stop to restore.",
                                         m_states[index].ticket));
            continue;
         }

         attempted = true;
         logger.Critical("PositionManager",
                         StringFormat("Position ticket=%I64u is unprotected at the broker; restoring stop %s.",
                                      m_states[index].ticket,
                                      DoubleToString(desired_sl, SymbolDigits())));

         ModifyPositionStops(m_states[index].ticket,
                             desired_sl,
                             PositionGetDouble(POSITION_TP),
                             "Protection repair",
                             logger);
      }

      if(attempted)
         m_last_protection_repair_time = server_time;
   }

   // Proof from broker history that a position id is gone because it closed,
   // not because XSpark failed to find it.
   bool PositionClosedInHistory(const long identifier, double &profit, double &exit_price)
   {
      profit = 0.0;
      exit_price = 0.0;

      if(identifier == 0 || !HistorySelectByPosition(identifier))
         return false;

      bool found = false;
      const int deals = HistoryDealsTotal();

      for(int index = 0; index < deals; index++)
      {
         const ulong deal = HistoryDealGetTicket(index);
         if(deal == 0)
            continue;

         const long entry_type = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_OUT_BY)
            continue;

         profit += HistoryDealGetDouble(deal, DEAL_PROFIT);
         exit_price = HistoryDealGetDouble(deal, DEAL_PRICE);
         found = true;
      }

      return found;
   }

   void ResetFlattenCampaign()
   {
      m_flatten_campaign_reason = "";
      m_flatten_last_attempt_time = 0;
      m_flatten_last_log_time = 0;
      m_flatten_attempts = 0;
      m_flatten_remaining_exposure = 0;
      m_flatten_last_signature = "";
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
      PrepareTradeContext();

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
      PrepareTradeContext();

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
      m_last_registration_bound_state = false;
      m_last_registration_position_closed = false;
      m_last_protection_repair_time = 0;
      ResetFlattenCampaign();
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
      m_last_registration_bound_state = false;
      m_last_registration_position_closed = false;
      m_last_protection_repair_time = 0;
      ResetFlattenCampaign();
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

      // Exposure can also disappear through a broker-side TP or SL while a
      // flatten campaign is open. Close the campaign here so it cannot absorb
      // the next one.
      if(m_flatten_campaign_reason != "" &&
         m_managed_position_count == 0 &&
         CountMatchingPendingOrders() == 0)
      {
         logger.Info("PositionManager",
                     StringFormat("%s ended: no XSpark exposure remains after %d attempt(s).",
                                  m_flatten_campaign_reason,
                                  m_flatten_attempts));
         ResetFlattenCampaign();
      }

      m_last_reason = "Position reconciliation completed against MT5 broker state.";
      return true;
   }

   // Returns true only when the new position was bound from the broker deal's
   // DEAL_POSITION_ID. Any other outcome is reported as a failure so the EA
   // runs reconciliation and blocks new entries until state is consistent.
   bool RegisterNewTrade(XSparkTradePlan &plan,
                         XSparkExecutionResult &result,
                         CXSparkLogger &logger)
   {
      m_last_registration_bound_state = false;
      m_last_registration_position_closed = false;

      if(!m_initialized || !result.confirmed)
      {
         m_last_reason = "Cannot register unconfirmed execution.";
         return false;
      }

      ulong ticket = 0;

      if(result.position_id != 0)
      {
         const bool prebound = result.position_ticket != 0 &&
                               PositionSelectByTicket(result.position_ticket) &&
                               PositionMatchesInstance() &&
                               XSparkPositionIdentityMatches(PositionGetInteger(POSITION_IDENTIFIER),
                                                             result.position_id);

         if(prebound)
            ticket = result.position_ticket;
         else
         {
            const int matches = FindLiveTicketByIdentifier(result.position_id, ticket);

            if(matches != 1)
            {
               ticket = 0;

               double closed_profit = 0.0;
               double closed_exit_price = 0.0;

               if(matches == 0 &&
                  PositionClosedInHistory(result.position_id, closed_profit, closed_exit_price))
               {
                  m_last_registration_position_closed = true;
                  m_last_reason = StringFormat("Broker position id %I64d from deal %I64u closed at %s for P/L %s before state registration; there is nothing left to manage.",
                                               result.position_id,
                                               result.deal_ticket,
                                               DoubleToString(closed_exit_price, SymbolDigits()),
                                               DoubleToString(closed_profit, 2));
                  logger.Warn("PositionManager", m_last_reason);
                  m_managed_position_count = CountMatchingLivePositions();
                  return false;
               }

               m_last_reason = StringFormat("Broker position id %I64d from deal %I64u matched %d live XSpark positions; exact state binding failed.",
                                            result.position_id,
                                            result.deal_ticket,
                                            matches);
               logger.Critical("PositionManager", m_last_reason);
               return false;
            }
         }

         if(!BindStateToTicket(ticket, plan, result, logger))
            return false;

         result.position_ticket = ticket;
         m_last_reason = "New XSpark trade state registered against the exact broker position id.";
         return true;
      }

      m_last_reason = StringFormat("Exact broker position identification failed for deal %I64u; attempting the documented fail-safe fallback.",
                                   result.deal_ticket);
      logger.Critical("PositionManager", m_last_reason);

      const int fallback_matches = FindFallbackTicket(plan, result, ticket);

      if(fallback_matches != 1)
      {
         m_last_reason = StringFormat("Fail-safe fallback matched %d candidate positions for deal %I64u; refusing to attach strategy state by guesswork.",
                                      fallback_matches,
                                      result.deal_ticket);
         logger.Critical("PositionManager", m_last_reason);
         return false;
      }

      if(!BindStateToTicket(ticket, plan, result, logger))
         return false;

      result.position_ticket = ticket;
      m_last_reason = StringFormat("Trade state bound to ticket %I64u by documented fail-safe fallback; broker-exact identification was unavailable.",
                                   ticket);
      logger.Critical("PositionManager", m_last_reason);
      return false;
   }

   // True when the last RegisterNewTrade call attached strategy state to a
   // position, even if it had to use the fail-safe fallback to do so.
   bool LastRegistrationBoundState()
   {
      return m_last_registration_bound_state;
   }

   // True when the exact broker position was identified but had already closed
   // before state could be registered. That is a completed trade, not a state
   // divergence.
   bool LastRegistrationPositionAlreadyClosed()
   {
      return m_last_registration_position_closed;
   }

   bool HasStateForIdentifier(const long identifier)
   {
      return FindStateByIdentifier(identifier) >= 0;
   }

   bool PositionIsLive(const long identifier)
   {
      ulong ticket = 0;
      return FindLiveTicketByIdentifier(identifier, ticket) > 0;
   }

   // Every live XSpark position must be represented in managed state, otherwise
   // exposure exists that XSpark is not protecting deliberately.
   bool ManagedStateCoversLivePositions(string &reason)
   {
      reason = "";

      if(!m_initialized)
      {
         reason = "Position manager is not initialized.";
         return false;
      }

      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionMatchesInstance())
            continue;

         const long identifier = PositionGetInteger(POSITION_IDENTIFIER);

         int index_by_state = FindStateByIdentifier(identifier);
         if(index_by_state < 0)
            index_by_state = FindStateByTicket(ticket);

         if(index_by_state < 0)
         {
            reason = StringFormat("Live XSpark position ticket=%I64u identifier=%I64d has no managed trade state.",
                                  ticket,
                                  identifier);
            return false;
         }

         if(m_states[index_by_state].direction != PositionDirection())
         {
            reason = StringFormat("Managed state for ticket=%I64u identifier=%I64d holds direction %s while the live position is %s.",
                                  ticket,
                                  identifier,
                                  XSparkDirectionName(m_states[index_by_state].direction),
                                  XSparkDirectionName(PositionDirection()));
            return false;
         }

         if(PositionGetDouble(POSITION_SL) <= 0.0)
         {
            reason = StringFormat("Live XSpark position ticket=%I64u identifier=%I64d has no broker stop; exposure is unprotected.",
                                  ticket,
                                  identifier);
            return false;
         }
      }

      reason = "Managed state covers every live XSpark position.";
      return true;
   }

   // A state whose signal bar differs from the one being verified means the
   // broker position is owned by a different XSpark trade, not by this entry.
   bool StateForIdentifierOwnsSignalBar(const long identifier, const datetime signal_bar_time)
   {
      const int index = FindStateByIdentifier(identifier);
      if(index < 0)
         return false;

      if(m_states[index].signal_bar_time == 0)
         return true;

      return m_states[index].signal_bar_time == signal_bar_time;
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

      RepairMissingProtection(server_time, logger);

      for(int index = 0; index < ArraySize(m_states); index++)
      {
         XSparkTradeState state = m_states[index];
         if(!PositionSelectByTicket(state.ticket) || !PositionMatchesInstance())
            continue;

         const double current_volume = PositionGetDouble(POSITION_VOLUME);
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

   // Keeps attempting to remove XSpark-owned exposure until none remains, and
   // never touches another symbol or Magic Number. Broker retries and log
   // output are paced so a latched killswitch does not emit identical CRITICAL
   // lines on every tick while still surfacing what is left.
   void FlattenManagedExposure(const string reason,
                               CXSparkLogger &logger,
                               const bool critical = true)
   {
      if(!m_initialized)
         return;

      // The empty string is the "no campaign" sentinel, so a caller must never
      // be able to supply it as a reason.
      const string campaign_reason = reason == "" ? "Flatten XSpark exposure" : reason;

      const datetime now = ServerTimeNow();
      const int remaining_positions = CountMatchingLivePositions();
      const int remaining_orders = CountMatchingPendingOrders();

      m_flatten_remaining_exposure = remaining_positions + remaining_orders;

      if(m_flatten_remaining_exposure == 0)
      {
         if(m_flatten_campaign_reason != "")
         {
            LogFlattenResult(logger,
                             critical,
                             StringFormat("%s complete: no XSpark exposure remains after %d attempt(s).",
                                          m_flatten_campaign_reason,
                                          m_flatten_attempts));
            ResetFlattenCampaign();
         }

         return;
      }

      // The campaign is keyed on the exposure, not on the caller. A killswitch
      // and a weekend close that overlap must not restart each other's campaign
      // on every tick.
      if(m_flatten_campaign_reason == "")
      {
         m_flatten_campaign_reason = campaign_reason;
         m_flatten_last_log_time = now;
         LogFlattenResult(logger,
                          critical,
                          StringFormat("%s started: %d XSpark position(s) and %d pending order(s) must be removed.",
                                       campaign_reason,
                                       remaining_positions,
                                       remaining_orders));
      }
      else if(m_flatten_last_attempt_time > 0 &&
              ThrottleHolds(m_flatten_last_attempt_time, now, XSPARK_FLATTEN_RETRY_INTERVAL_SECONDS))
      {
         return;
      }

      const string label = campaign_reason == m_flatten_campaign_reason ?
                           m_flatten_campaign_reason :
                           m_flatten_campaign_reason + " / " + campaign_reason;

      m_flatten_last_attempt_time = now;
      m_flatten_attempts++;

      PrepareTradeContext();

      string outcome = "";

      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionMatchesInstance())
            continue;

         const bool local_result = m_trade.PositionClose(ticket);

         outcome += StringFormat("position=%I64u local_result=%s retcode=%I64d description=%s; ",
                                 ticket,
                                 local_result ? "true" : "false",
                                 (long)m_trade.ResultRetcode(),
                                 m_trade.ResultRetcodeDescription());
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

         outcome += StringFormat("order=%I64u local_result=%s retcode=%I64d description=%s; ",
                                 order_ticket,
                                 local_result ? "true" : "false",
                                 (long)m_trade.ResultRetcode(),
                                 m_trade.ResultRetcodeDescription());
      }

      Reconcile(logger);

      const int after_positions = CountMatchingLivePositions();
      const int after_orders = CountMatchingPendingOrders();
      m_flatten_remaining_exposure = after_positions + after_orders;

      if(m_flatten_remaining_exposure == 0)
      {
         LogFlattenResult(logger,
                          critical,
                          StringFormat("%s complete after %d attempt(s): %s",
                                       label,
                                       m_flatten_attempts,
                                       outcome));
         ResetFlattenCampaign();
         return;
      }

      const string signature = StringFormat("%s|%d|%d", outcome, after_positions, after_orders);
      const bool outcome_changed = signature != m_flatten_last_signature;
      const bool log_interval_elapsed = m_flatten_last_log_time == 0 ||
                                        !ThrottleHolds(m_flatten_last_log_time, now, XSPARK_FLATTEN_LOG_INTERVAL_SECONDS);

      if(outcome_changed || log_interval_elapsed)
      {
         LogFlattenResult(logger,
                          critical,
                          StringFormat("%s attempt %d still leaves %d XSpark position(s) and %d pending order(s); retrying. Last results: %s",
                                       label,
                                       m_flatten_attempts,
                                       after_positions,
                                       after_orders,
                                       outcome));
         m_flatten_last_log_time = now;
      }

      m_flatten_last_signature = signature;
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
