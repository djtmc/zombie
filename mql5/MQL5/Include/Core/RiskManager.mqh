//+------------------------------------------------------------------+
//| RiskManager.mqh                                                   |
//| Warstwa: ile handlować, nie jak technicznie wysłać zlecenie.      |
//| Position sizing oparty na ryzyku, kill-switch, kontrola marginu.  |
//+------------------------------------------------------------------+
#ifndef __RISK_MANAGER_MQH__
#define __RISK_MANAGER_MQH__

#include "ExecutionEngine.mqh"
#include "PositionManager.mqh"

//--- Position sizing: wielkość pozycji wyliczona z % ryzyka i odległości SL
//    To ZASTĘPUJE stały lot - każdy sygnał ma to samo realne ryzyko % niezależnie
//    od tego, jak szeroki jest jego SL.
double RM_CalculateLotSizeByRisk(string symbol, double riskPercent, double slDistancePoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (riskPercent / 100.0);

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(slDistancePoints <= 0 || tickValue <= 0) return 0;

   double valuePerPoint = (tickValue / tickSize) * point;
   double lot = riskAmount / (slDistancePoints * valuePerPoint);

   // zaokrąglenie do kroku wolumenu
   double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / stepVol) * stepVol; // w dół, żeby nie przekroczyć zadanego ryzyka

   double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   lot = MathMax(minVol, MathMin(maxVol, lot));

   return lot;
}

//--- Kontrola marginu przed otwarciem (nie po - pkt 13 ea-execution-safety)
bool RM_HasSufficientMargin(string symbol, double volume, ENUM_ORDER_TYPE orderType, double marginBufferPct = 20.0)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(symbol, SYMBOL_BID);
   double requiredMargin;
   if(!OrderCalcMargin(orderType, symbol, volume, price, requiredMargin))
   {
      EE_LogDecision(symbol, "MARGIN_CALC_FAILED", "Nie udało się obliczyć wymaganego marginu");
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double requiredWithBuffer = requiredMargin * (1.0 + marginBufferPct / 100.0);

   if(freeMargin < requiredWithBuffer)
   {
      EE_LogDecision(symbol, "INSUFFICIENT_MARGIN",
                     StringFormat("wymagane=%.2f (z buforem), dostępne=%.2f", requiredWithBuffer, freeMargin));
      return false;
   }
   return true;
}

//--- Stan dzienny do liczenia drawdown - zapisuj balance na starcie dnia
double RM_GetOrSetDailyStartBalance()
{
   static double dailyStart = 0;
   static datetime dailyStartDate = 0;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));

   if(dailyStartDate != today)
   {
      dailyStart = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyStartDate = today;
   }
   return dailyStart;
}

//--- Globalna flaga blokady handlu (kill-switch) - trwała do ręcznego resetu
bool RM_TradingBlocked = false;

//--- Kill-switch: wywołuj jako PIERWSZĄ rzecz w OnTick, przed logiką sygnału
bool RM_CheckKillSwitch(int magicNumber, double maxDailyDrawdownPct, double maxTotalDrawdownPct)
{
   if(RM_TradingBlocked) return true;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyStartBalance = RM_GetOrSetDailyStartBalance();

   double dailyDrawdownPct = (dailyStartBalance - equity) / dailyStartBalance * 100.0;
   double totalDrawdownPct = (balance - equity) / balance * 100.0;

   if(dailyDrawdownPct >= maxDailyDrawdownPct || totalDrawdownPct >= maxTotalDrawdownPct)
   {
      EE_LogDecision("KILL_SWITCH", "TRIGGERED",
                     StringFormat("dailyDD=%.2f%% totalDD=%.2f%%", dailyDrawdownPct, totalDrawdownPct));
      EE_TriggerAlert("EA: KILL-SWITCH AKTYWOWANY - zamykam wszystkie pozycje, blokuję nowe zlecenia");

      PM_CloseAllPositions(magicNumber, "kill_switch");
      RM_TradingBlocked = true;
      return true;
   }
   return false;
}

//--- Reset blokady kill-switcha - wywołuj tylko ręcznie/świadomie, nigdy automatycznie
void RM_ResetKillSwitch()
{
   RM_TradingBlocked = false;
   EE_LogDecision("KILL_SWITCH", "RESET", "Blokada handlu zdjęta ręcznie");
}

//--- Kontrola spreadu (osobna funkcja - używana też przez PositionManager, ale
//    dostępna tu jako samodzielny check przed nawet rozważeniem sygnału)
bool RM_IsSpreadAcceptable(string symbol, double maxSpreadPoints)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) return false;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double currentSpreadPoints = (tick.ask - tick.bid) / point;

   if(currentSpreadPoints > maxSpreadPoints)
   {
      EE_LogDecision(symbol, "SPREAD_TOO_WIDE", StringFormat("aktualny=%.1f limit=%.1f", currentSpreadPoints, maxSpreadPoints));
      return false;
   }
   return true;
}

//--- Limit jednoczesnych pozycji (per magic number)
bool RM_CanOpenNewPosition(int magicNumber, int maxSimultaneousPositions)
{
   ulong tickets[];
   int count = PM_GetOpenPositionsByMagic(magicNumber, tickets);
   if(count >= maxSimultaneousPositions)
   {
      EE_LogDecision(IntegerToString(magicNumber), "BLOCKED_MAX_POSITIONS",
                     StringFormat("otwarte=%d limit=%d", count, maxSimultaneousPositions));
      return false;
   }
   return true;
}


//===================================================================
//  ROZSZERZENIE: wariant ŚCISŁY position sizingu
//  RM_CalculateLotSizeByRisk podnosi wynik do minimalnego lota, co przy
//  szerokim SL może przekroczyć zadane ryzyko. Ta wersja zwraca 0, jeśli
//  nawet minimalny lot ryzykuje więcej niż (riskPercent * tolerance).
//===================================================================
double RM_CalculateLotSizeByRiskStrict(string symbol, double riskPercent, double slDistancePoints, double tolerance = 1.10)
{
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(slDistancePoints <= 0 || tickValue <= 0 || tickSize <= 0) return 0;

   double riskAmount    = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0);
   double valuePerPoint = (tickValue / tickSize) * point;
   double minVol        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double riskAtMinLot  = slDistancePoints * valuePerPoint * minVol;

   if(riskAtMinLot > riskAmount * tolerance)
   {
      EE_LogDecision(symbol, "BLOCKED_RISK_MIN_LOT",
                     StringFormat("min lot %.2f ryzykuje %.2f > dozwolone %.2f", minVol, riskAtMinLot, riskAmount));
      return 0;
   }
   return RM_CalculateLotSizeByRisk(symbol, riskPercent, slDistancePoints);
}

#endif // __RISK_MANAGER_MQH__
