//+------------------------------------------------------------------+
//| Utils.mqh                                                          |
//| Narzędzia wydajnościowe współdzielone przez wszystkie EA na       |
//| tym rdzeniu.                                                       |
//+------------------------------------------------------------------+
#ifndef __UTILS_MQH__
#define __UTILS_MQH__

//--- Wykrycie nowej świecy - dla strategii, których sygnał ma sens raz na bar,
//    nie na każdym ticku. Wywołuj na początku OnTick i pomiń ciężką logikę
//    sygnału (wskaźniki, iteracje), jeśli zwróci false.
//
//    NIE używaj tego, jeśli Twoja strategia faktycznie potrzebuje reakcji
//    na każdy tick (np. scalping na cenie, nie na zamknięciu świecy) - w takim
//    wypadku po prostu nie wywołuj tej funkcji i licz sygnał co tick jak dotychczas.
struct UT_BarTracker
{
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime        lastBarTime;
};

UT_BarTracker g_ut_barTrackers[];

bool UT_IsNewBar(string symbol, ENUM_TIMEFRAMES timeframe)
{
   datetime currentBarTime = iTime(symbol, timeframe, 0);
   if(currentBarTime == 0) return false; // brak danych - bezpieczny fallback

   for(int i = 0; i < ArraySize(g_ut_barTrackers); i++)
   {
      if(g_ut_barTrackers[i].symbol == symbol && g_ut_barTrackers[i].timeframe == timeframe)
      {
         if(g_ut_barTrackers[i].lastBarTime == currentBarTime) return false;
         g_ut_barTrackers[i].lastBarTime = currentBarTime;
         return true;
      }
   }

   // pierwszy raz dla tej pary symbol/timeframe
   UT_BarTracker tracker;
   tracker.symbol = symbol;
   tracker.timeframe = timeframe;
   tracker.lastBarTime = currentBarTime;
   int size = ArraySize(g_ut_barTrackers);
   ArrayResize(g_ut_barTrackers, size + 1);
   g_ut_barTrackers[size] = tracker;
   return true;
}

#endif // __UTILS_MQH__
