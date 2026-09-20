#ifndef XSPARK_RISK_POSITION_SIZER_MQH
#define XSPARK_RISK_POSITION_SIZER_MQH

#include <XSpark/Core/SymbolMath.mqh>

// Pure sizing core. Risk cash and the actual stop distance decide the volume,
// so a stop distance that changed between planning and execution produces a
// different volume rather than a different monetary risk.
//
// A volume below the broker minimum is refused rather than rounded up. That
// rule is right for an account where the minimum lot is a small fraction of
// the risk budget, and it is what every caller gets by default.
//
// It is also what makes a very small account untradeable: on a $100 balance a
// 1% budget is $1.00, and 0.01 lot of gold with a $1.50 stop already risks
// $1.50, so the smallest trade the broker allows is refused on every signal.
// The last parameter is the explicit way out. When it is positive, a computed
// volume below the minimum is raised TO THE MINIMUM - never above it - provided
// the money that minimum puts at risk is inside the cap. The raise is stated in
// the reason so it is never silent, the cap bounds it, and the account-level
// risk cap still measures the actual cash of the sized trade afterwards. A
// caller that leaves the cap at zero keeps the refusal exactly as it was.
bool XSparkVolumeFromRiskInputs(const double risk_cash,
                                const double stop_distance,
                                const double tick_size,
                                const double tick_value,
                                const double volume_min,
                                const double volume_max,
                                const double volume_step,
                                double &volume,
                                double &loss_per_lot,
                                string &reason,
                                const double minimum_lot_risk_cap_cash = 0.0)
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
      const bool cap_usable = MathIsValidNumber(minimum_lot_risk_cap_cash) && minimum_lot_risk_cap_cash > 0.0;

      if(cap_usable)
      {
         const double minimum_lot_risk = volume_min * loss_per_lot;

         // The same one-cent tolerance the broker-maximum branch below uses,
         // so a cap that equals the minimum-lot risk to the cent is not
         // refused on floating-point residue.
         if(MathIsValidNumber(minimum_lot_risk) && minimum_lot_risk <= minimum_lot_risk_cap_cash + 0.01)
         {
            volume = volume_min;
            reason = StringFormat("Volume raised to the broker minimum %.8f lots: risk %.2f instead of the %.2f budget, within the %.2f cap for small accounts.",
                                  volume_min,
                                  minimum_lot_risk,
                                  risk_cash,
                                  minimum_lot_risk_cap_cash);
            return true;
         }

         reason = StringFormat("The broker's smallest trade %.8f lots would risk %.2f, above the %.2f cap for small accounts; trade aborted.",
                               volume_min,
                               minimum_lot_risk,
                               minimum_lot_risk_cap_cash);
         return false;
      }

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
   // The small-account policy, as a percentage of balance. Zero - the default
   // every existing EA passes - means a volume below the broker minimum is
   // refused, exactly as before. Held by the sizer rather than by the caller
   // so that planning and the execution engine's send-time re-sizing apply
   // one policy: the engine sizes through this same instance.
   double m_minimum_lot_risk_cap_pct;
   bool   m_last_raised_to_minimum;
   double m_last_actual_risk_cash;

public:
   CXSparkPositionSizer()
   {
      m_initialized = false;
      m_last_reason = "Position sizing is not initialized; no tradable volume is available.";
      m_last_loss_per_lot = 0.0;
      m_last_risk_cash = 0.0;
      m_minimum_lot_risk_cap_pct = 0.0;
      m_last_raised_to_minimum = false;
      m_last_actual_risk_cash = 0.0;
   }

   bool Initialize(const double minimum_lot_risk_cap_pct = 0.0)
   {
      if(!MathIsValidNumber(minimum_lot_risk_cap_pct) || minimum_lot_risk_cap_pct < 0.0)
      {
         m_initialized = false;
         m_last_reason = "The small-account risk cap must be a finite percentage of zero or more.";
         return false;
      }

      m_initialized = true;
      m_minimum_lot_risk_cap_pct = minimum_lot_risk_cap_pct;
      m_last_raised_to_minimum = false;
      m_last_actual_risk_cash = 0.0;
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
      m_last_raised_to_minimum = false;
      m_last_actual_risk_cash = 0.0;

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
                                                    reason,
                                                    balance * m_minimum_lot_risk_cap_pct / 100.0);

      // Diagnostics stay identical to the pre-refactor behaviour: they are only
      // populated once the sizing got as far as computing a loss per lot.
      m_last_loss_per_lot = loss_per_lot;
      m_last_risk_cash = loss_per_lot > 0.0 ? risk_cash : 0.0;
      m_last_reason = reason;

      if(!sized)
      {
         volume = 0.0;
         return false;
      }

      // A raise is the only path on which the sized volume exceeds what the
      // budget alone would have bought, so it is detected from the arithmetic
      // rather than from the wording of the reason.
      m_last_actual_risk_cash = volume * loss_per_lot;
      m_last_raised_to_minimum = loss_per_lot > 0.0 &&
                                 XSparkNormalizeVolumeDown(risk_cash / loss_per_lot, volume_step) < volume_min;

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

   // The budget the last sizing was asked for.
   double LastRiskCash()
   {
      return m_last_risk_cash;
   }

   // The money the last sized volume actually puts at risk. Equal to or below
   // the budget unless the volume was raised to the broker minimum.
   double LastActualRiskCash()
   {
      return m_last_actual_risk_cash;
   }

   bool LastRaisedToMinimum()
   {
      return m_last_raised_to_minimum;
   }

   double MinimumLotRiskCapPct()
   {
      return m_minimum_lot_risk_cap_pct;
   }
};

#endif
