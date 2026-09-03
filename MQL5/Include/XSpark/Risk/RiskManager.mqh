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
