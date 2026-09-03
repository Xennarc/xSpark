#ifndef XSPARK_CORE_MARKET_STATE_MQH
#define XSPARK_CORE_MARKET_STATE_MQH

class CXSparkMarketState
{
private:
   string   m_symbol;
   double   m_bid;
   double   m_ask;
   double   m_point;
   int      m_digits;
   datetime m_server_time;
   bool     m_initialized;

public:
   CXSparkMarketState()
   {
      m_symbol = "";
      m_bid = 0.0;
      m_ask = 0.0;
      m_point = 0.0;
      m_digits = 0;
      m_server_time = 0;
      m_initialized = false;
   }

   bool Initialize(const string symbol)
   {
      if(symbol == "")
         return false;

      m_symbol = symbol;
      m_initialized = true;

      return Refresh();
   }

   bool Refresh()
   {
      if(!m_initialized || m_symbol == "")
         return false;

      if(!SymbolSelect(m_symbol, true))
         return false;

      m_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_server_time = TimeTradeServer();

      if(m_server_time == 0)
         m_server_time = TimeCurrent();

      if(m_bid <= 0.0 || m_ask <= 0.0 || m_point <= 0.0 || m_digits < 0)
         return false;

      return true;
   }

   string SymbolName()
   {
      return m_symbol;
   }

   double Bid()
   {
      return m_bid;
   }

   double Ask()
   {
      return m_ask;
   }

   double PointSize()
   {
      return m_point;
   }

   int Digits()
   {
      return m_digits;
   }

   datetime ServerTime()
   {
      return m_server_time;
   }

   double SpreadPoints()
   {
      if(m_point <= 0.0)
         return 0.0;

      return (m_ask - m_bid) / m_point;
   }
};

#endif
