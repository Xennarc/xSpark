#ifndef XSPARK_RISK_MANAGER_MQH
#define XSPARK_RISK_MANAGER_MQH

#include <XSpark/Strategy/ScoringEngine.mqh>
#include <XSpark/Strategy/ScoreBotTypes.mqh>
#include <XSpark/Strategy/StrategyInterface.mqh>

double XSparkRiskPercentForScore(const double final_score,
                                 const double tier1_pct,
                                 const double tier2_pct,
                                 const double tier3_pct,
                                 const double max_risk_pct)
{
   double selected = tier1_pct;

   if(final_score >= XSPARK_SCOREBOT_TIER3_THRESHOLD)
      selected = tier3_pct;
   else if(final_score >= XSPARK_SCOREBOT_TIER2_THRESHOLD)
      selected = tier2_pct;

   return MathMin(selected, max_risk_pct);
}

// How many consecutive full-stop losses reach a drawdown limit at a given risk
// percentage. Risk is a fraction of the CURRENT balance, so losses compound
// down rather than subtract linearly: after k losses the balance is
// (1 - f)^k, and the drawdown is 1 - (1 - f)^k.
//
// This exists to be printed at startup. The relationship between risk size and
// how long the account survives an ordinary losing streak is the single number
// an operator most needs before choosing a risk level, and it is not obvious:
// doubling the risk does not halve the tolerance, and the baseline run in
// docs/IMPROVEMENT_PLAN.md already contained an 8-loss streak.
//
// Returns 0 when the inputs cannot produce an answer.
int XSparkConsecutiveLossesToDrawdown(const double risk_pct, const double drawdown_limit_pct,
                                     const int concurrent_positions = 1)
{
   if(!MathIsValidNumber(risk_pct) || !MathIsValidNumber(drawdown_limit_pct))
      return 0;

   if(concurrent_positions < 1 || risk_pct <= 0.0 || risk_pct * concurrent_positions >= 100.0)
      return 0;

   if(drawdown_limit_pct <= 0.0 || drawdown_limit_pct >= 100.0)
      return 0;

   const double f = risk_pct * concurrent_positions / 100.0;
   const double limit = drawdown_limit_pct / 100.0;

   // Smallest k with 1 - (1-f)^k >= limit, i.e. k >= ln(1-limit) / ln(1-f).
   // Both logarithms are negative, so the quotient is positive.
   const double exact = MathLog(1.0 - limit) / MathLog(1.0 - f);
   if(!MathIsValidNumber(exact) || exact <= 0.0)
      return 0;

   return (int)MathCeil(exact - 0.0000001);
}

// A slot setting that consumes the entire cap at nominal sizing will fail
// unpredictably after fills drift. This is admission headroom, not diversification.
bool XSparkConcurrencyHasHeadroom(const int slots, const double tier1, const double tier2,
                                  const double tier3, const double per_trade_cap, const double account_cap)
{
   if(slots < 1 || slots > 2 || !MathIsValidNumber(tier1) || !MathIsValidNumber(tier2) ||
      !MathIsValidNumber(tier3) || !MathIsValidNumber(per_trade_cap) || !MathIsValidNumber(account_cap) ||
      tier1 <= 0.0 || tier2 <= 0.0 || tier3 <= 0.0 || per_trade_cap <= 0.0 || account_cap <= 0.0) return false;
   if(slots == 1) return true;
   const double maximum = MathMin(per_trade_cap, MathMax(tier1, MathMax(tier2, tier3)));
   return slots * maximum <= 0.9 * account_cap;
}

// Money at risk on one open position, in account currency.
//
// AGENTS.md rule 27 says no strategy may bypass maximum account-level risk
// limits, and the codebase could not enforce it: InpMaxRiskPct is a PER-TRADE
// label, not a property of the account. One instance at 3% is 3% at risk. Three
// instances on three symbols, each obeying its own 3% cap, is 9% - and nothing
// anywhere could see that, because each instance only ever looked at its own
// Magic Number.
//
// This measures exposure the way an account experiences it: every open position,
// whatever symbol, whatever Magic Number, whether XSpark opened it or not. A
// manual trade left open is still money that can be lost.
//
// Returns false when the risk is UNKNOWABLE rather than zero. A position with no
// stop loss has unbounded downside, and treating that as zero risk would let it
// pass a cap silently - the one arithmetic mistake that turns a risk cap into
// decoration.
bool XSparkPositionRiskCash(const double entry,
                            const double stop,
                            const double volume,
                            const double tick_size,
                            const double tick_value,
                            double &risk_cash,
                            string &reason)
{
   risk_cash = 0.0;
   reason = "";

   if(!MathIsValidNumber(entry) || !MathIsValidNumber(volume) ||
      entry <= 0.0 || volume <= 0.0)
   {
      reason = "Position entry or volume is unusable.";
      return false;
   }

   if(!MathIsValidNumber(stop) || stop <= 0.0)
   {
      reason = "Position has no stop loss, so its risk is unbounded rather than zero.";
      return false;
   }

   if(!MathIsValidNumber(tick_size) || !MathIsValidNumber(tick_value) ||
      tick_size <= 0.0 || tick_value <= 0.0)
   {
      reason = "Instrument tick specification is unavailable.";
      return false;
   }

   const double distance = MathAbs(entry - stop);
   risk_cash = distance * volume * (tick_value / tick_size);

   if(!MathIsValidNumber(risk_cash) || risk_cash < 0.0)
   {
      risk_cash = 0.0;
      reason = "Computed position risk is not a usable number.";
      return false;
   }

   return true;
}

// Whether adding one more position's risk would keep total open risk inside the
// account-level cap. Balance-relative, because that is the denominator every
// per-trade percentage already uses.
bool XSparkAccountRiskWithinCap(const double open_risk_cash,
                                const double prospective_risk_cash,
                                const double balance,
                                const double max_account_risk_pct,
                                double &projected_pct,
                                string &reason)
{
   projected_pct = 0.0;
   reason = "";

   if(!MathIsValidNumber(balance) || balance <= 0.0)
   {
      reason = "Account balance is unavailable, so account risk cannot be bounded.";
      return false;
   }

   if(!MathIsValidNumber(max_account_risk_pct) || max_account_risk_pct <= 0.0)
   {
      reason = "Account risk cap is not configured.";
      return false;
   }

   if(!MathIsValidNumber(open_risk_cash) || !MathIsValidNumber(prospective_risk_cash) ||
      open_risk_cash < 0.0 || prospective_risk_cash < 0.0)
   {
      reason = "Open or prospective risk is not a usable number.";
      return false;
   }

   projected_pct = ((open_risk_cash + prospective_risk_cash) / balance) * 100.0;

   if(!MathIsValidNumber(projected_pct))
   {
      projected_pct = 0.0;
      reason = "Projected account risk is not a usable number.";
      return false;
   }

   if(projected_pct > max_account_risk_pct)
   {
      reason = StringFormat("Projected account risk %.2f%% would exceed the %.2f%% cap "
                            "(%.2f already at risk across all open positions).",
                            projected_pct,
                            max_account_risk_pct,
                            open_risk_cash);
      return false;
   }

   return true;
}

class CXSparkRiskManager
{
private:
   bool   m_initialized;
   string m_last_reason;
   double m_tier1_pct;
   double m_tier2_pct;
   double m_tier3_pct;
   double m_max_risk_pct;

public:
   CXSparkRiskManager()
   {
      m_initialized = false;
      m_last_reason = "Risk state is unknown; execution is blocked.";
      m_tier1_pct = 1.0;
      m_tier2_pct = 1.5;
      m_tier3_pct = 2.0;
      m_max_risk_pct = 2.0;
   }

   bool Initialize(const double tier1_pct = 1.0,
                   const double tier2_pct = 1.5,
                   const double tier3_pct = 2.0,
                   const double max_risk_pct = 2.0)
   {
      if(tier1_pct <= 0.0 || tier2_pct <= 0.0 || tier3_pct <= 0.0 || max_risk_pct <= 0.0)
      {
         m_last_reason = "Risk percentages must be positive.";
         return false;
      }

      m_initialized = true;
      m_tier1_pct = tier1_pct;
      m_tier2_pct = tier2_pct;
      m_tier3_pct = tier3_pct;
      m_max_risk_pct = max_risk_pct;
      m_last_reason = "Risk manager initialized.";
      return true;
   }

   bool IsSignalApproved(XSparkSignal &signal, double &risk_pct)
   {
      risk_pct = 0.0;

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

      if(signal.score < signal.effective_threshold)
      {
         m_last_reason = "Score is below the effective threshold.";
         return false;
      }

      if(!XSparkScoreBotScoreIsValid(signal.score))
      {
         m_last_reason = "Signal score is outside the valid 0-9 range.";
         return false;
      }

      risk_pct = XSparkRiskPercentForScore(signal.score,
                                           m_tier1_pct,
                                           m_tier2_pct,
                                           m_tier3_pct,
                                           m_max_risk_pct);

      if(risk_pct <= 0.0 || risk_pct > m_max_risk_pct)
      {
         m_last_reason = "Selected risk percentage is invalid.";
         risk_pct = 0.0;
         return false;
      }

      m_last_reason = StringFormat("Risk approved at %.2f%%.", risk_pct);
      return true;
   }

   double SelectedRiskPercentForScore(const double final_score)
   {
      return XSparkRiskPercentForScore(final_score,
                                       m_tier1_pct,
                                       m_tier2_pct,
                                       m_tier3_pct,
                                       m_max_risk_pct);
   }

   string LastReason()
   {
      return m_last_reason;
   }

   /*
      Future responsibilities beyond ScoreBot v3:
      - broader account drawdown policy
      - symbol-specific exposure aggregation
      - correlated exposure if later required
      - portfolio-level margin and concentration limits
   */
};

#endif
