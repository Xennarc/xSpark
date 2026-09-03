#ifndef XSPARK_CORE_SAFETY_MANAGER_MQH
#define XSPARK_CORE_SAFETY_MANAGER_MQH

#include <XSpark/Core/ExecutionMath.mqh>
#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/StateStore.mqh>
#include <XSpark/Core/SymbolMath.mqh>

class CXSparkSafetyManager
{
private:
   bool   m_initialized;
   bool   m_trading_enabled;
   string m_last_reason;
   string m_symbol;
   ulong  m_magic_number;
   int    m_max_open_trades;

   bool   m_use_spread_filter;
   double m_max_spread_points;
   double m_max_spread_atr_pct;

   bool   m_use_total_dd_killswitch;
   double m_max_total_dd_pct;
   double m_runtime_high_water_equity;
   bool   m_total_dd_killswitch_latched;
   double m_total_dd_pct;

   int    m_max_quote_age_seconds;
   long   m_last_quote_age_seconds;

   bool   m_state_recovery_latched;
   string m_state_recovery_reason;

   double m_max_daily_dd_pct;
   bool   m_daily_halt_latched;
   double m_daily_peak_equity;
   double m_daily_dd_pct;
   int    m_daily_day_id;
   bool   m_drawdown_state_valid;

   CXSparkStateStore m_store;

   bool TerminalTradeStateIsValid()
   {
      if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
      {
         m_last_reason = "Terminal is not connected.";
         return false;
      }

      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
      {
         m_last_reason = "Terminal trading is not allowed.";
         return false;
      }

      if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
      {
         m_last_reason = "EA trading is not allowed by the terminal.";
         return false;
      }

      if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
      {
         m_last_reason = "Account trading is not allowed.";
         return false;
      }

      const long trade_mode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
      {
         m_last_reason = "Symbol trading is disabled.";
         return false;
      }

      if(trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      {
         m_last_reason = "Symbol trade mode is close-only.";
         return false;
      }

      return true;
   }

   // Telemetry only. Refreshed every tick so the dashboard reports the real
   // quote age even when an earlier safety gate short-circuits the freshness
   // check. The gate itself always re-reads the tick at decision time.
   void UpdateQuoteAge()
   {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
      {
         m_last_quote_age_seconds = 0;
         return;
      }

      const datetime server_time = TimeTradeServer() == 0 ? TimeCurrent() : TimeTradeServer();
      string ignored_reason = "";
      XSparkQuoteAgeIsAcceptable(tick.time,
                                 server_time,
                                 m_max_quote_age_seconds,
                                 m_last_quote_age_seconds,
                                 ignored_reason);
   }

   // Production safety addition: a frozen or invalid feed must never be used to
   // open new exposure. It never blocks management of existing positions.
   bool QuoteIsFresh()
   {
      m_last_quote_age_seconds = 0;

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
      {
         m_last_reason = "Current tick is unavailable; new exposure is blocked.";
         return false;
      }

      const datetime server_time = TimeTradeServer() == 0 ? TimeCurrent() : TimeTradeServer();
      string quote_reason = "";

      if(!XSparkQuoteAgeIsAcceptable(tick.time,
                                     server_time,
                                     m_max_quote_age_seconds,
                                     m_last_quote_age_seconds,
                                     quote_reason))
      {
         m_last_reason = "Stale quote: " + quote_reason;
         return false;
      }

      return true;
   }

public:
   CXSparkSafetyManager()
   {
      m_initialized = false;
      m_trading_enabled = false;
      m_last_reason = "Safety state is unknown; failing closed.";
      m_symbol = "";
      m_magic_number = 0;
      m_max_open_trades = 1;
      m_use_spread_filter = true;
      m_max_spread_points = 50.0;
      m_max_spread_atr_pct = 10.0;
      m_use_total_dd_killswitch = true;
      m_max_total_dd_pct = 8.0;
      m_runtime_high_water_equity = 0.0;
      m_total_dd_killswitch_latched = false;
      m_total_dd_pct = 0.0;
      m_max_quote_age_seconds = 15;
      m_last_quote_age_seconds = 0;
      m_state_recovery_latched = false;
      m_state_recovery_reason = "";
      m_max_daily_dd_pct = 5.0;
      m_daily_halt_latched = false;
      m_daily_peak_equity = 0.0;
      m_daily_dd_pct = 0.0;
      m_daily_day_id = 0;
      m_drawdown_state_valid = false;
   }

   bool Initialize(const string symbol,
                   const ulong magic_number,
                   const bool enable_trading,
                   const int max_open_trades,
                   const bool use_spread_filter,
                   const double max_spread_points,
                   const double max_spread_atr_pct,
                   const bool use_total_dd_killswitch,
                   const double max_total_dd_pct,
                   const double max_daily_dd_pct,
                   const int max_quote_age_seconds,
                   CXSparkLogger &logger)
   {
      if(symbol == "" || magic_number == 0)
      {
         m_last_reason = "SafetyManager requires a symbol and non-zero Magic Number.";
         return false;
      }

      if(max_open_trades < 1)
      {
         m_last_reason = "Max open trades must be at least 1.";
         return false;
      }

      if(max_quote_age_seconds <= 0)
      {
         m_last_reason = "Maximum quote age must be at least 1 second.";
         return false;
      }

      m_initialized = true;
      m_symbol = symbol;
      m_magic_number = magic_number;
      m_trading_enabled = enable_trading;
      m_max_open_trades = max_open_trades;
      m_use_spread_filter = use_spread_filter;
      m_max_spread_points = max_spread_points;
      m_max_spread_atr_pct = max_spread_atr_pct;
      m_use_total_dd_killswitch = use_total_dd_killswitch;
      m_max_total_dd_pct = max_total_dd_pct;
      m_max_daily_dd_pct = max_daily_dd_pct;
      m_max_quote_age_seconds = max_quote_age_seconds;
      m_last_quote_age_seconds = 0;
      m_state_recovery_latched = false;
      m_state_recovery_reason = "";
      m_runtime_high_water_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_total_dd_killswitch_latched = false;
      m_total_dd_pct = 0.0;

      m_store.Initialize((long)AccountInfoInteger(ACCOUNT_LOGIN), m_symbol, m_magic_number);

      const datetime server_time = TimeTradeServer() == 0 ? TimeCurrent() : TimeTradeServer();
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const bool drawdown_ready = RefreshDrawdownState(equity, server_time, logger);

      if(drawdown_ready)
      {
         m_last_reason = m_trading_enabled ? "SafetyManager initialized for trading gates." :
                                            "Trading disabled by input; analysis remains active.";
      }

      return true;
   }

   bool RefreshDrawdownState(const double current_equity,
                             const datetime server_time,
                             CXSparkLogger &logger)
   {
      if(!m_initialized)
      {
         m_last_reason = "Safety state is unknown; failing closed.";
         return false;
      }

      UpdateQuoteAge();

      if(current_equity <= 0.0)
      {
         m_drawdown_state_valid = false;
         m_last_reason = "Current equity is unavailable.";
         return false;
      }

      if(m_runtime_high_water_equity <= 0.0 || current_equity > m_runtime_high_water_equity)
         m_runtime_high_water_equity = current_equity;

      if(m_runtime_high_water_equity > 0.0)
         m_total_dd_pct = ((m_runtime_high_water_equity - current_equity) / m_runtime_high_water_equity) * 100.0;

      if(m_use_total_dd_killswitch &&
         !m_total_dd_killswitch_latched &&
         m_total_dd_pct >= m_max_total_dd_pct)
      {
         m_total_dd_killswitch_latched = true;
         m_last_reason = StringFormat("Total DD killswitch latched at %.2f%% drawdown from runtime high-water equity.",
                                      m_total_dd_pct);
         logger.Critical("SafetyManager", m_last_reason);
      }

      const int day_id = XSparkServerDayId(server_time);
      const double stored_day = m_store.Get("dD", 0.0);

      if((int)stored_day != day_id)
      {
         m_daily_day_id = day_id;
         m_daily_peak_equity = current_equity;
         m_daily_halt_latched = false;
         m_daily_dd_pct = 0.0;
         if(!m_store.Set("dD", (double)day_id) ||
            !m_store.Set("dP", current_equity) ||
            !m_store.Set("dH", 0.0))
         {
            m_drawdown_state_valid = false;
            m_last_reason = "Failed to persist daily drawdown safety state.";
            return false;
         }
      }
      else
      {
         m_daily_day_id = day_id;
         m_daily_peak_equity = m_store.Get("dP", current_equity);
         m_daily_halt_latched = m_store.Get("dH", 0.0) >= 0.5;
      }

      if(current_equity > m_daily_peak_equity)
      {
         m_daily_peak_equity = current_equity;
         if(!m_store.Set("dP", current_equity))
         {
            m_drawdown_state_valid = false;
            m_last_reason = "Failed to persist daily peak equity.";
            return false;
         }
      }

      if(m_daily_peak_equity > 0.0)
         m_daily_dd_pct = ((m_daily_peak_equity - current_equity) / m_daily_peak_equity) * 100.0;

      if(!m_daily_halt_latched && m_daily_dd_pct >= m_max_daily_dd_pct)
      {
         m_daily_halt_latched = true;
         if(!m_store.Set("dH", 1.0))
         {
            m_drawdown_state_valid = false;
            m_last_reason = "Failed to persist daily DD halt latch.";
            return false;
         }
         m_last_reason = StringFormat("Daily DD halt latched at %.2f%% for server day %d.",
                                      m_daily_dd_pct,
                                      m_daily_day_id);
         logger.Critical("SafetyManager", m_last_reason);
      }

      m_drawdown_state_valid = true;
      return true;
   }

   bool CanOpenNewTrades(const int open_positions,
                         const double spread_price,
                         const double atr14_price)
   {
      if(!m_initialized)
      {
         m_last_reason = "Safety state is unknown; failing closed.";
         return false;
      }

      if(!m_trading_enabled)
      {
         m_last_reason = "Trading disabled by input.";
         return false;
      }

      if(m_total_dd_killswitch_latched)
      {
         m_last_reason = "Total DD killswitch is latched.";
         return false;
      }

      if(m_state_recovery_latched)
      {
         m_last_reason = "XSpark state recovery is active: " + m_state_recovery_reason;
         return false;
      }

      if(!TerminalTradeStateIsValid())
         return false;

      if(!m_drawdown_state_valid)
      {
         m_last_reason = "Drawdown safety state is invalid; new entries are blocked.";
         return false;
      }

      if(open_positions >= m_max_open_trades)
      {
         m_last_reason = StringFormat("XSpark open positions %d reached max %d.",
                                      open_positions,
                                      m_max_open_trades);
         return false;
      }

      if(m_daily_halt_latched)
      {
         m_last_reason = "Daily DD halt is latched for the current server day.";
         return false;
      }

      if(!QuoteIsFresh())
         return false;

      if(m_use_spread_filter)
      {
         const double spread_canonical_points = XSparkPriceToCanonicalPoints(spread_price);
         const double max_spread_price = XSparkCanonicalPointsToPrice(m_max_spread_points);

         if(spread_price > max_spread_price)
         {
            m_last_reason = StringFormat("Spread %.2f canonical points exceeds max %.2f.",
                                         spread_canonical_points,
                                         m_max_spread_points);
            return false;
         }

         if(atr14_price > 0.0)
         {
            const double spread_atr_pct = (spread_price / atr14_price) * 100.0;
            if(spread_atr_pct > m_max_spread_atr_pct)
            {
               m_last_reason = StringFormat("Spread %.2f%% of ATR exceeds max %.2f%%.",
                                            spread_atr_pct,
                                            m_max_spread_atr_pct);
               return false;
            }
         }
         else
         {
            m_last_reason = "ATR unavailable for spread filter.";
            return false;
         }
      }

      m_last_reason = "Safety gates allow a new entry.";
      return true;
   }

   // Broker execution succeeded but XSpark could not represent the resulting
   // position in managed state. New entries stay blocked until reconciliation
   // proves the state is consistent again.
   void LatchStateRecovery(const string reason, CXSparkLogger &logger)
   {
      m_state_recovery_reason = reason;

      if(m_state_recovery_latched)
         return;

      m_state_recovery_latched = true;
      logger.Critical("SafetyManager",
                      "State recovery latched; new entries are blocked: " + reason);
   }

   void ClearStateRecovery(CXSparkLogger &logger)
   {
      if(!m_state_recovery_latched)
         return;

      m_state_recovery_latched = false;
      m_state_recovery_reason = "";
      logger.Warn("SafetyManager",
                  "State recovery cleared; XSpark managed state is consistent with broker state again.");
   }

   bool StateRecoveryLatched()
   {
      return m_state_recovery_latched;
   }

   string StateRecoveryReason()
   {
      return m_state_recovery_reason;
   }

   int MaxQuoteAgeSeconds()
   {
      return m_max_quote_age_seconds;
   }

   long LastQuoteAgeSeconds()
   {
      return m_last_quote_age_seconds;
   }

   bool TradingEnabled()
   {
      return m_trading_enabled;
   }

   bool DailyHaltLatched()
   {
      return m_daily_halt_latched;
   }

   bool TotalDDKillSwitchLatched()
   {
      return m_total_dd_killswitch_latched;
   }

   double DailyDDPct()
   {
      return m_daily_dd_pct;
   }

   double TotalDDPct()
   {
      return m_total_dd_pct;
   }

   double DailyPeakEquity()
   {
      return m_daily_peak_equity;
   }

   double RuntimeHighWaterEquity()
   {
      return m_runtime_high_water_equity;
   }

   int MaxOpenTrades()
   {
      return m_max_open_trades;
   }

   string LastReason()
   {
      return m_last_reason;
   }

   /*
      Safety checks implemented for ScoreBot v3:
      - terminal connected
      - account trading allowed
      - EA trading allowed
      - symbol trading allowed
      - spread limit
      - daily loss halt
      - total drawdown killswitch latch
      - XSpark-managed position count limit
      - stale/invalid quote rejection for new exposure (quote age is derived from
        TimeTradeServer(), which MT5 computes from the host clock, so a badly
        skewed VPS clock will block new entries rather than allow them)
      - state-recovery latch after a confirmed entry that could not be registered

      Future checks:
      - market/session restrictions outside strategy score semantics
   */
};

#endif
