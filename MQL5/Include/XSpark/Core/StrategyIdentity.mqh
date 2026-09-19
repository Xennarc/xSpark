#ifndef XSPARK_CORE_STRATEGY_IDENTITY_MQH
#define XSPARK_CORE_STRATEGY_IDENTITY_MQH

// The one place every shipped strategy's Magic Number default is written down.
//
// Two Expert Advisors that share a Magic Number do not run side by side - they
// manage each other's positions. Every separation XSpark relies on is keyed on
// it: PositionManager reconciles on symbol plus Magic, the per-position state
// store is keyed on account, symbol and Magic, the opposing-exposure check and
// the killswitch flatten both filter the same way. A collision is therefore not
// a configuration preference; it is the ambiguous state AGENTS.md rule 24 says
// to refuse rather than guess at.
//
// Holding the defaults in one header rather than one per strategy is what makes
// a collision detectable at all: a strategy that declared its own number in its
// own file could not know what any other strategy had claimed.
//
// No includes, deliberately. Identity is the most primitive thing in the system
// and must not acquire a dependency on the layers that consume it.

#define XSPARK_SCOREBOT_MAGIC_DEFAULT 770331
#define XSPARK_CANDLEFLOW_MAGIC_DEFAULT 770332

// Names the strategy that ships with this Magic Number, or an empty string when
// the number is not a shipped default. An operator running several instances of
// one strategy on different charts picks their own numbers, and those are not
// claimed by anybody.
string XSparkStrategyClaimingMagic(const ulong magic)
{
   if(magic == XSPARK_SCOREBOT_MAGIC_DEFAULT)
      return "ScoreBot_v3 (XSpark.ex5)";

   if(magic == XSPARK_CANDLEFLOW_MAGIC_DEFAULT)
      return "CandleFlow (XSparkFlow.ex5)";

   return "";
}

// Whether an EA whose own shipped default is own_default may use this Magic
// Number. Refuses zero, and refuses a number another shipped strategy claims.
//
// Fails closed: an EA that cannot prove its exposure is its own must not open
// any. The check costs nothing at runtime and catches the one configuration
// mistake that silently merges two bots into one.
bool XSparkMagicIsAvailable(const ulong magic, const ulong own_default, string &reason)
{
   reason = "";

   if(magic == 0)
   {
      reason = "Magic Number must be explicit and non-zero.";
      return false;
   }

   if(magic == own_default)
      return true;

   const string claimant = XSparkStrategyClaimingMagic(magic);

   if(claimant == "")
      return true;

   reason = StringFormat("Magic Number %I64u is the shipped default of %s. Two Expert Advisors sharing a Magic Number "
                         "manage each other's positions, so this one refuses to start. Use a different number.",
                         magic,
                         claimant);
   return false;
}

#endif
