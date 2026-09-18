#ifndef XSPARK_ACCOUNT_EXPOSURE_MQH
#define XSPARK_ACCOUNT_EXPOSURE_MQH
#include <XSpark/Risk/RiskManager.mqh>

// Broker snapshot of ALL account positions; unreadable/unprotected exposure refuses.
bool XSparkReadAccountExposure(const string own_symbol, const ulong own_magic,
                                double &open_risk_cash, double &own_risk_cash, double &foreign_risk_cash,
                                int &own_positions, string &reason)
{
   open_risk_cash = 0.0; own_risk_cash = 0.0; foreign_risk_cash = 0.0;
   reason = "";
   own_positions = 0;

   const int total = PositionsTotal();

   for(int index = 0; index < total; index++)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
      {
         reason = "An open position could not be read; account risk is unknown.";
         return false;
      }

      const string position_symbol = PositionGetString(POSITION_SYMBOL);
      double position_risk = 0.0;
      string position_reason = "";

      double tick_value = SymbolInfoDouble(position_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(position_symbol, SYMBOL_TRADE_TICK_VALUE);

      if(!XSparkPositionRiskCash(PositionGetDouble(POSITION_PRICE_OPEN),
                                 PositionGetDouble(POSITION_SL),
                                 PositionGetDouble(POSITION_VOLUME),
                                 SymbolInfoDouble(position_symbol, SYMBOL_TRADE_TICK_SIZE),
                                 tick_value,
                                 position_risk,
                                 position_reason))
      {
         reason = StringFormat("Position %I64u on %s: %s", ticket, position_symbol, position_reason);
         return false;
      }

      open_risk_cash += position_risk;
      if(position_symbol == own_symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == own_magic)
      { own_risk_cash += position_risk; own_positions++; }
      else foreign_risk_cash += position_risk;
   }

   return true;
}

#endif
