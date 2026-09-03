#ifndef XSPARK_CORE_SAFETY_MANAGER_MQH
#define XSPARK_CORE_SAFETY_MANAGER_MQH

class CXSparkSafetyManager
{
private:
   bool   m_initialized;
   bool   m_trading_enabled;
   string m_last_reason;

public:
   CXSparkSafetyManager()
   {
      m_initialized = false;
      m_trading_enabled = false;
      m_last_reason = "Safety state is unknown; failing closed.";
   }

   bool Initialize()
   {
      m_initialized = true;
      m_trading_enabled = false;
      m_last_reason = "Phase 0: live trading is disabled until safety checks are implemented.";
      return true;
   }

   bool CanOpenNewTrades()
   {
      if(!m_initialized)
      {
         m_last_reason = "Safety state is unknown; failing closed.";
         return false;
      }

      if(!m_trading_enabled)
      {
         m_last_reason = "Phase 0: live trading is disabled until safety checks are implemented.";
         return false;
      }

      m_last_reason = "Safety checks are incomplete; failing closed.";
      return false;
   }

   string LastReason()
   {
      return m_last_reason;
   }

   /*
      Future checks belong here before any new exposure can be allowed:
      - terminal connected
      - account trading allowed
      - EA trading allowed
      - symbol trading allowed
      - stale quote detection
      - spread limit
      - daily loss limit
      - drawdown limit
      - position count limit
      - market/session restrictions
   */
};

#endif
