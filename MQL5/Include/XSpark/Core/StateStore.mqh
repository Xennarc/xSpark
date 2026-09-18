#ifndef XSPARK_CORE_STATE_STORE_MQH
#define XSPARK_CORE_STATE_STORE_MQH

// MT5 rejects global variable names longer than 63 characters.
#define XSPARK_GLOBAL_VARIABLE_NAME_MAX 63

// Deterministic 64-bit polynomial hash. Only small literals are used so no
// constant has to be widened past the signed range at compile time.
ulong XSparkHash64(const string text)
{
   ulong hash = 0;
   const int length = StringLen(text);

   for(int index = 0; index < length; index++)
      hash = (hash * 1099511628211) ^ (ulong)StringGetCharacter(text, index);

   return hash ^ (ulong)length;
}

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
      const string full = m_prefix + "." + state_name;
      if(StringLen(full) <= XSPARK_GLOBAL_VARIABLE_NAME_MAX)
         return full;

      // A long login/symbol/magic combination can push the readable key past the
      // 63-character limit, where GlobalVariableSet fails silently. Fall back to
      // a deterministic hash so the key stays unique, stable and in range.
      return StringFormat("XS%I64u", XSparkHash64(full));
   }

   // True when Key() returns the readable form, so prefix scans over the terminal's
   // global variables are meaningful for this instance.
   bool KeyIsReadable(const string state_name)
   {
      return StringLen(m_prefix + "." + state_name) <= XSPARK_GLOBAL_VARIABLE_NAME_MAX;
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

   // An absent history cannot prove that an older setup was never traded.
   // Bootstrap to the current signal bar and wait for a genuinely new origin.
   // CAS prevents two attached instances from reserving the same known key.
   bool ReserveNewer(const string state_name, const datetime instance_time,
                     const datetime current_bar_time, string &reason)
   {
      reason = "";
      if(instance_time <= 0 || current_bar_time <= 0 || instance_time > current_bar_time)
      { reason = "Invalid pattern instance timestamp."; return false; }
      const string key = Key(state_name);
      if(!GlobalVariableCheck(key))
      {
         if(!Set(state_name, (double)current_bar_time))
         { reason = "Pattern latch bootstrap failed; entry refused."; return false; }
         GlobalVariablesFlush();
         reason = "Pattern latch initialized; waiting for an origin newer than bootstrap bar.";
         return false;
      }
      double previous = 0.0;
      if(!GlobalVariableGet(key, previous) || !MathIsValidNumber(previous) || previous <= 0.0)
      { reason = "Pattern latch unreadable; entry refused."; return false; }
      if((double)instance_time <= previous)
      { reason = "Pattern instance already consumed or predates latch bootstrap."; return false; }
      if(!GlobalVariableSetOnCondition(key, (double)instance_time, previous))
      { reason = "Pattern reservation failed or changed concurrently; entry refused."; return false; }
      GlobalVariablesFlush();
      return true;
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
