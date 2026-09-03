#ifndef XSPARK_TRADE_POSITION_MANAGER_MQH
#define XSPARK_TRADE_POSITION_MANAGER_MQH

class CXSparkPositionManager
{
private:
   bool   m_initialized;
   ulong  m_magic_number;
   int    m_managed_position_count;
   string m_last_reason;

public:
   CXSparkPositionManager()
   {
      m_initialized = false;
      m_magic_number = 0;
      m_managed_position_count = 0;
      m_last_reason = "Position manager is not initialized.";
   }

   bool Initialize(const ulong magic_number)
   {
      if(magic_number == 0)
      {
         m_last_reason = "Magic Number must be explicit and non-zero.";
         return false;
      }

      m_initialized = true;
      m_magic_number = magic_number;
      m_managed_position_count = 0;
      m_last_reason = "Position manager initialized.";
      return true;
   }

   bool Reconcile()
   {
      if(!m_initialized)
      {
         m_last_reason = "Position manager is not initialized.";
         return false;
      }

      m_managed_position_count = 0;
      const int total_positions = PositionsTotal();

      for(int index = 0; index < total_positions; index++)
      {
         const ulong ticket = PositionGetTicket(index);

         if(ticket == 0)
            continue;

         if(!PositionSelectByTicket(ticket))
            continue;

         const long position_magic = PositionGetInteger(POSITION_MAGIC);

         if(position_magic >= 0 && (ulong)position_magic == m_magic_number)
            m_managed_position_count++;
      }

      m_last_reason = "Position reconciliation completed against MT5 broker state.";
      return true;
   }

   int ManagedPositionCount()
   {
      return m_managed_position_count;
   }

   string LastReason()
   {
      return m_last_reason;
   }

   /*
      Future responsibilities:
      - identifying XSpark-managed positions by Magic Number
      - filtering broker positions and orders
      - startup/restart reconciliation
      - stop management
      - target management
      - break-even logic
      - trailing logic
      - position closure
   */
};

#endif
