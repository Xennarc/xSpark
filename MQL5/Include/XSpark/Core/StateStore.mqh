#ifndef XSPARK_CORE_STATE_STORE_MQH
#define XSPARK_CORE_STATE_STORE_MQH

class CXSparkStateStore
{
private:
   string m_prefix;

public:
   CXSparkStateStore()
   {
      m_prefix = "XSpark";
   }

   void Initialize(const long account_login, const string symbol, const ulong magic_number)
   {
      m_prefix = StringFormat("X.%I64d.%s.%I64u", account_login, symbol, magic_number);
   }

   string Key(const string state_name)
   {
      return m_prefix + "." + state_name;
   }

   bool Has(const string state_name)
   {
      return GlobalVariableCheck(Key(state_name));
   }

   double Get(const string state_name, const double default_value = 0.0)
   {
      const string key = Key(state_name);
      if(!GlobalVariableCheck(key))
         return default_value;

      return GlobalVariableGet(key);
   }

   bool Set(const string state_name, const double value)
   {
      return GlobalVariableSet(Key(state_name), value) > 0;
   }

   void Delete(const string state_name)
   {
      const string key = Key(state_name);
      if(GlobalVariableCheck(key))
         GlobalVariableDel(key);
   }
};

int XSparkServerDayId(const datetime server_time)
{
   MqlDateTime parts;
   TimeToStruct(server_time, parts);
   return (parts.year * 10000) + (parts.mon * 100) + parts.day;
}

datetime XSparkServerDayStart(const datetime server_time)
{
   MqlDateTime parts;
   TimeToStruct(server_time, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
}

#endif
