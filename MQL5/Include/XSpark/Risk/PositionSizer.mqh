#ifndef XSPARK_RISK_POSITION_SIZER_MQH
#define XSPARK_RISK_POSITION_SIZER_MQH

class CXSparkPositionSizer
{
private:
   bool   m_initialized;
   string m_last_reason;

public:
   CXSparkPositionSizer()
   {
      m_initialized = false;
      m_last_reason = "Position sizing is not initialized; no tradable volume is available.";
   }

   bool Initialize()
   {
      m_initialized = true;
      m_last_reason = "Phase 0: position sizing is not implemented; no tradable volume is available.";
      return true;
   }

   bool CalculateVolume(const string symbol,
                        const double account_risk_amount,
                        const double entry_price,
                        const double stop_price,
                        double &volume)
   {
      volume = 0.0;

      if(!m_initialized)
      {
         m_last_reason = "Position sizing is not initialized; no tradable volume is available.";
         return false;
      }

      if(symbol == "" || account_risk_amount <= 0.0 || entry_price <= 0.0 || stop_price <= 0.0)
      {
         m_last_reason = "Invalid sizing inputs; no tradable volume is available.";
         return false;
      }

      m_last_reason = "Phase 0: symbol-aware monetary risk sizing is not implemented; no tradable volume is available.";
      return false;
   }

   string LastReason()
   {
      return m_last_reason;
   }
};

#endif
