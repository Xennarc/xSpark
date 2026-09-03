#property strict
#property version     "0.10"
#property description "XSpark Phase 0 Expert Advisor shell. No strategy or trading execution is implemented."

#include <XSpark/Core/Logger.mqh>
#include <XSpark/Core/MarketState.mqh>
#include <XSpark/Core/SafetyManager.mqh>
#include <XSpark/Risk/RiskManager.mqh>
#include <XSpark/Risk/PositionSizer.mqh>
#include <XSpark/Execution/ExecutionEngine.mqh>
#include <XSpark/Trade/PositionManager.mqh>

input ulong InpMagicNumber = 2609030001;

CXSparkLogger          g_logger;
CXSparkMarketState     g_market_state;
CXSparkSafetyManager   g_safety_manager;
CXSparkRiskManager     g_risk_manager;
CXSparkPositionSizer   g_position_sizer;
CXSparkExecutionEngine g_execution_engine;
CXSparkPositionManager g_position_manager;

string XSparkBoolToString(const bool value)
{
   return value ? "true" : "false";
}

string XSparkDeinitReasonToString(const int reason)
{
   switch(reason)
   {
      case REASON_PROGRAM:
         return "program requested removal";
      case REASON_REMOVE:
         return "removed from chart";
      case REASON_RECOMPILE:
         return "recompiled";
      case REASON_CHARTCHANGE:
         return "chart symbol or period changed";
      case REASON_CHARTCLOSE:
         return "chart closed";
      case REASON_PARAMETERS:
         return "input parameters changed";
      case REASON_ACCOUNT:
         return "account changed";
      case REASON_TEMPLATE:
         return "template applied";
      case REASON_INITFAILED:
         return "initialization failed";
      case REASON_CLOSE:
         return "terminal closed";
      default:
         return "unknown";
   }
}

int OnInit()
{
   g_logger.Initialize("XSpark", false);
   g_logger.Info("EA", "Starting XSpark Phase 0 shell");

   if(!g_market_state.Initialize(_Symbol))
   {
      g_logger.Critical("MarketState", "Failed to initialize market state for the chart symbol");
      return INIT_FAILED;
   }

   if(!g_safety_manager.Initialize())
   {
      g_logger.Critical("SafetyManager", "Failed to initialize safety manager");
      return INIT_FAILED;
   }

   if(!g_risk_manager.Initialize())
   {
      g_logger.Critical("RiskManager", "Failed to initialize risk manager");
      return INIT_FAILED;
   }

   if(!g_position_sizer.Initialize())
   {
      g_logger.Critical("PositionSizer", "Failed to initialize position sizer");
      return INIT_FAILED;
   }

   if(!g_execution_engine.Initialize(InpMagicNumber))
   {
      g_logger.Critical("ExecutionEngine", "Failed to initialize execution engine");
      return INIT_FAILED;
   }

   if(!g_position_manager.Initialize(InpMagicNumber))
   {
      g_logger.Critical("PositionManager", "Failed to initialize position manager");
      return INIT_FAILED;
   }

   if(!g_position_manager.Reconcile())
   {
      g_logger.Critical("PositionManager", "Failed to reconcile existing MT5 positions");
      return INIT_FAILED;
   }

   g_logger.Info("EA", StringFormat("Symbol=%s digits=%d point=%s spread_points=%.1f",
                                    g_market_state.SymbolName(),
                                    g_market_state.Digits(),
                                    DoubleToString(g_market_state.PointSize(), g_market_state.Digits()),
                                    g_market_state.SpreadPoints()));

   g_logger.Info("EA", StringFormat("Account login=%s server=%s company=%s trade_allowed=%s",
                                    IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
                                    AccountInfoString(ACCOUNT_SERVER),
                                    AccountInfoString(ACCOUNT_COMPANY),
                                    XSparkBoolToString(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0)));

   g_logger.Info("EA", StringFormat("Terminal build=%s connected=%s terminal_trade_allowed=%s mql_trade_allowed=%s tester=%s optimization=%s",
                                    IntegerToString((long)TerminalInfoInteger(TERMINAL_BUILD)),
                                    XSparkBoolToString(TerminalInfoInteger(TERMINAL_CONNECTED) != 0),
                                    XSparkBoolToString(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_TRADE_ALLOWED) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_TESTER) != 0),
                                    XSparkBoolToString(MQLInfoInteger(MQL_OPTIMIZATION) != 0)));

   g_logger.Warn("SafetyManager", g_safety_manager.LastReason());
   g_logger.Info("PositionManager", StringFormat("XSpark-managed positions detected=%d",
                                                g_position_manager.ManagedPositionCount()));
   g_logger.Info("EA", "Startup complete. Phase 0 trading is disabled.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_logger.Info("EA", StringFormat("Shutdown reason=%s (%d)",
                                    XSparkDeinitReasonToString(reason),
                                    reason));
}

void OnTick()
{
   if(!g_market_state.Refresh())
   {
      g_logger.Warn("MarketState", "Unable to refresh market state on tick");
      return;
   }

   // Phase 0 intentionally accepts ticks without creating signals or orders.
}
