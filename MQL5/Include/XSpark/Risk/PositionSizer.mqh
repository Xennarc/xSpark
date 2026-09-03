#ifndef XSPARK_RISK_POSITION_SIZER_MQH
#define XSPARK_RISK_POSITION_SIZER_MQH

#include <XSpark/Core/SymbolMath.mqh>

class CXSparkPositionSizer
{
private:
   bool   m_initialized;
   string m_last_reason;
   double m_last_loss_per_lot;
   double m_last_risk_cash;

public:
   CXSparkPositionSizer()
   {
      m_initialized = false;
      m_last_reason = "Position sizing is not initialized; no tradable volume is available.";
      m_last_loss_per_lot = 0.0;
      m_last_risk_cash = 0.0;
   }

   bool Initialize()
   {
      m_initialized = true;
      m_last_reason = "Position sizer initialized.";
      return true;
   }

   bool CalculateVolume(const string symbol,
                        const double risk_pct,
                        const double entry_price,
                        const double stop_price,
                        double &volume)
   {
      volume = 0.0;
      m_last_loss_per_lot = 0.0;
      m_last_risk_cash = 0.0;

      if(!m_initialized)
      {
         m_last_reason = "Position sizing is not initialized; no tradable volume is available.";
         return false;
      }

      if(symbol == "" || risk_pct <= 0.0 || entry_price <= 0.0 || stop_price <= 0.0)
      {
         m_last_reason = "Invalid sizing inputs; no tradable volume is available.";
         return false;
      }

      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      const double risk_cash = balance * risk_pct / 100.0;
      const double stop_distance = MathAbs(entry_price - stop_price);
      const double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);

      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

      const double volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double volume_max = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      const double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(balance <= 0.0 || risk_cash <= 0.0)
      {
         m_last_reason = "Account balance or risk cash is invalid.";
         return false;
      }

      if(stop_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
      {
         m_last_reason = "Stop distance, tick size, or tick value is invalid.";
         return false;
      }

      if(volume_min <= 0.0 || volume_max <= 0.0 || volume_step <= 0.0)
      {
         m_last_reason = "Broker volume constraints are unavailable.";
         return false;
      }

      const double loss_per_lot = stop_distance * (tick_value / tick_size);
      if(loss_per_lot <= 0.0)
      {
         m_last_reason = "Loss per lot is invalid.";
         return false;
      }

      m_last_loss_per_lot = loss_per_lot;
      m_last_risk_cash = risk_cash;

      double raw_lots = risk_cash / loss_per_lot;
      double normalized_lots = XSparkNormalizeVolumeDown(raw_lots, volume_step);

      if(normalized_lots < volume_min)
      {
         m_last_reason = StringFormat("Computed volume %.8f is below broker minimum %.8f; trade aborted.",
                                      normalized_lots,
                                      volume_min);
         return false;
      }

      if(normalized_lots > volume_max)
      {
         normalized_lots = XSparkNormalizeVolumeDown(volume_max, volume_step);
         if(normalized_lots < volume_min)
         {
            m_last_reason = "Broker maximum volume could not be normalized safely.";
            return false;
         }

         const double capped_risk_cash = normalized_lots * loss_per_lot;
         if(capped_risk_cash > risk_cash + 0.01)
         {
            m_last_reason = "Capped broker volume would exceed intended risk cash.";
            return false;
         }

         m_last_reason = StringFormat("Volume capped at broker maximum %.8f while staying within intended risk.",
                                      normalized_lots);
      }
      else
      {
         m_last_reason = StringFormat("Position size calculated: %.8f lots, risk cash %.2f, loss per lot %.2f.",
                                      normalized_lots,
                                      risk_cash,
                                      loss_per_lot);
      }

      volume = normalized_lots;
      return true;
   }

   string LastReason()
   {
      return m_last_reason;
   }

   double LastLossPerLot()
   {
      return m_last_loss_per_lot;
   }

   double LastRiskCash()
   {
      return m_last_risk_cash;
   }
};

#endif
