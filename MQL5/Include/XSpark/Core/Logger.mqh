#ifndef XSPARK_CORE_LOGGER_MQH
#define XSPARK_CORE_LOGGER_MQH

enum EXSparkLogLevel
{
   XSPARK_LOG_DEBUG = 0,
   XSPARK_LOG_INFO = 1,
   XSPARK_LOG_WARN = 2,
   XSPARK_LOG_ERROR = 3,
   XSPARK_LOG_CRITICAL = 4
};

class CXSparkLogger
{
private:
   string m_application;
   bool   m_debug_enabled;

   string LevelName(const EXSparkLogLevel level)
   {
      switch(level)
      {
         case XSPARK_LOG_DEBUG:
            return "DEBUG";
         case XSPARK_LOG_INFO:
            return "INFO";
         case XSPARK_LOG_WARN:
            return "WARN";
         case XSPARK_LOG_ERROR:
            return "ERROR";
         case XSPARK_LOG_CRITICAL:
            return "CRITICAL";
         default:
            return "UNKNOWN";
      }
   }

public:
   CXSparkLogger()
   {
      m_application = "XSpark";
      m_debug_enabled = false;
   }

   void Initialize(const string application_name, const bool debug_enabled = false)
   {
      m_application = application_name;
      m_debug_enabled = debug_enabled;
   }

   void Log(const EXSparkLogLevel level, const string component, const string message)
   {
      if(level == XSPARK_LOG_DEBUG && !m_debug_enabled)
         return;

      PrintFormat("%s [%s] [%s] %s",
                  m_application,
                  LevelName(level),
                  component,
                  message);
   }

   void Debug(const string component, const string message)
   {
      Log(XSPARK_LOG_DEBUG, component, message);
   }

   void Info(const string component, const string message)
   {
      Log(XSPARK_LOG_INFO, component, message);
   }

   void Warn(const string component, const string message)
   {
      Log(XSPARK_LOG_WARN, component, message);
   }

   void Error(const string component, const string message)
   {
      Log(XSPARK_LOG_ERROR, component, message);
   }

   void Critical(const string component, const string message)
   {
      Log(XSPARK_LOG_CRITICAL, component, message);
   }
};

#endif
