#ifndef XSPARK_RISK_MANAGER_MQH
#define XSPARK_RISK_MANAGER_MQH

#include <XSpark/Strategy/StrategyInterface.mqh>

class CXSparkRiskManager
{
private:
   bool   m_initialized;
   string m_last_reason;

public:
   CXSparkRiskManager()
   {
      m_initialized = false;
      m_last_reason = "Risk state is unknown; execution is blocked.";
   }

   bool Initialize()
   {
      m_initialized = true;
      m_last_reason = "Phase 0: risk rules are not implemented; execution is blocked.";
      return true;
   }

   bool IsSignalApproved(XSparkSignal &signal)
   {
      if(!m_initialized)
      {
         m_last_reason = "Risk state is unknown; execution is blocked.";
         return false;
      }

      if(signal.direction == XSPARK_SIGNAL_NONE)
      {
         m_last_reason = "No tradable signal was provided.";
         return false;
      }

      m_last_reason = "Phase 0: account-level risk rules are not implemented; execution is blocked.";
      return false;
   }

   string LastReason()
   {
      return m_last_reason;
   }

   /*
      Future responsibilities:
      - risk per trade
      - max daily loss
      - account drawdown
      - maximum simultaneous exposure
      - maximum positions
      - margin checks
      - symbol-specific exposure
      - correlated exposure if later required
   */
};

#endif
