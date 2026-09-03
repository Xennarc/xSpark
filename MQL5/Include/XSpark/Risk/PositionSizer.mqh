#ifndef XSPARK_RISK_POSITION_SIZER_MQH
#define XSPARK_RISK_POSITION_SIZER_MQH

#include <XSpark/Core/SymbolMath.mqh>

// Pure sizing core. Risk cash and the actual stop distance decide the volume,
// so a stop distance that changed between planning and execution produces a
// different volume rather than a different monetary risk.
bool XSparkVolumeFromRiskInputs(const double risk_cash,
                                const double stop_distance,
                                const double tick_size,
                                const double tick_value,
                                const double volume_min,
                                const double volume_max,
                                const double volume_step,
                                double &volume,
                                double &loss_per_lot,
                                string &reason)
{
   volume = 0.0;
   loss_per_lot = 0.0;
   reason = "";

   if(risk_cash <= 0.0)
   {
      reason = "Account balance or risk cash is invalid.";
      return false;
   }

   if(stop_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
   {
      reason = "Stop distance, tick size, or tick value is invalid.";
      return false;
   }

   if(volume_min <= 0.0 || volume_max <= 0.0 || volume_step <= 0.0)
   {
      reason = "Broker volume constraints are unavailable.";
      return false;
   }

   loss_per_lot = stop_distance * (tick_value / tick_size);
   if(loss_per_lot <= 0.0)
   {
      reason = "Loss per lot is invalid.";
      return false;
   }

   const double raw_lots = risk_cash / loss_per_lot;
   double normalized_lots = XSparkNormalizeVolumeDown(raw_lots, volume_step);

   if(normalized_lots < volume_min)
   {
      reason = StringFormat("Computed volume %.8f is below broker minimum %.8f; trade aborted.",
                            normalized_lots,
                            volume_min);
      return false;
   }

   if(normalized_lots > volume_max)
   {
      normalized_lots = XSparkNormalizeVolumeDown(volume_max, volume_step);
      if(normalized_lots < volume_min)
      {
         reason = "Broker maximum volume could not be normalized safely.";
         return false;
      }

      const double capped_risk_cash = normalized_lots * loss_per_lot;
      if(capped_risk_cash > risk_cash + 0.01)
      {
         reason = "Capped broker volume would exceed intended risk cash.";
         return false;
      }

      reason = StringFormat("Volume capped at broker maximum %.8f while staying within intended risk.",
                            normalized_lots);
   }
   else
   {
      reason = StringFormat("Position size calculated: %.8f lots, risk cash %.2f, loss per lot %.2f.",
                            normalized_lots,
                            risk_cash,
                            loss_per_lot);
   }

   volume = normalized_lots;
   return true;
}

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

      double loss_per_lot = 0.0;
      string reason = "";
      const bool sized = XSparkVolumeFromRiskInputs(risk_cash,
                                                    stop_distance,
                                                    tick_size,
                                                    tick_value,
                                                    volume_min,
                                                    volume_max,
                                                    volume_step,
                                                    volume,
                                                    loss_per_lot,
                                                    reason);

      // Diagnostics stay identical to the pre-refactor behaviour: they are only
      // populated once the sizing got as far as computing a loss per lot.
      m_last_loss_per_lot = loss_per_lot;
      m_last_risk_cash = loss_per_lot > 0.0 ? risk_cash : 0.0;
      m_last_reason = reason;

      if(!sized)
         volume = 0.0;

      return sized;
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
