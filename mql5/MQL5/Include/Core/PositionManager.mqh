//+------------------------------------------------------------------+
//| PositionManager.mqh                                               |
//| Warstwa: otwieranie/zamykanie pozycji, trailing stop, break-even  |
//| Cała komunikacja z rynkiem idzie przez ExecutionEngine.           |
//| Nowe EA wywołują TE funkcje, nie piszą OrderSend bezpośrednio.    |
//+------------------------------------------------------------------+
#ifndef __POSITION_MANAGER_MQH__
#define __POSITION_MANAGER_MQH__

#include "ExecutionEngine.mqh"

//--- Otwarcie pozycji z pełną warstwą bezpieczeństwa (walidacja + idempotencja + weryfikacja)
ExecutionResult PM_OpenPosition(string symbol, ENUM_ORDER_TYPE orderType, double volume,
                                 double sl, double tp, int magicNumber, string signalTag,
                                 double maxSpreadPoints = 30, int deviationPoints = 20)
{
   // 1. Kontrola spreadu (ea-execution-safety pkt 7)
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      EE_LogDecision(signalTag, "BLOCKED_NO_TICK", "Nie udało się pobrać aktualnej ceny");
      return EXEC_FAILED;
   }
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double currentSpread = (tick.ask - tick.bid) / point;
   if(currentSpread > maxSpreadPoints)
   {
      EE_LogDecision(signalTag, "BLOCKED_SPREAD", StringFormat("spread=%.1f limit=%.1f", currentSpread, maxSpreadPoints));
      return EXEC_FAILED;
   }

   // 2. Walidacja parametrów (pkt 12,19,20)
   double vol = volume;
   string errorMsg;
   if(!EE_ValidateOrderParams(symbol, vol, 0, sl, tp, orderType, errorMsg))
   {
      EE_LogDecision(signalTag, "BLOCKED_VALIDATION", errorMsg);
      return EXEC_FAILED;
   }

   // 3. Budowa requestu
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.volume    = vol;
   request.type      = orderType;
   request.price     = (orderType == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   request.sl        = sl;
   request.tp        = tp;
   request.magic     = magicNumber;
   request.deviation = deviationPoints;
   request.type_filling = EE_GetSupportedFillingMode(symbol);

   // 4. Idempotency-key i bezpieczne wysłanie (pkt 1,2,3)
   string intentId = EE_GenerateIntentId(magicNumber, signalTag);
   ExecutionResult res = EE_SafeOrderSend(request, intentId, magicNumber);

   // 5. Weryfikacja SL/TP po fakcie (pkt 5) - tylko gdy potwierdzono
   if(res == EXEC_CONFIRMED)
   {
      ulong ticket = PM_FindLatestTicketByMagic(magicNumber, symbol);
      if(ticket > 0 && !EE_VerifyStopsApplied(ticket, sl, tp))
      {
         EE_LogDecision(intentId, "STOPS_CORRECTION_NEEDED", "SL/TP niezastosowane przez brokera - koryguję");
         PM_ModifyStops(ticket, sl, tp);
      }
   }

   return res;
}

//--- Znajdź najświeższy ticket dla danego magic/symbol (pomocnicza do powyższego)
ulong PM_FindLatestTicketByMagic(int magicNumber, string symbol)
{
   datetime latest = 0;
   ulong latestTicket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= latest) { latest = t; latestTicket = ticket; }
   }
   return latestTicket;
}

//--- Modyfikacja SL/TP istniejącej pozycji
bool PM_ModifyStops(ulong ticket, double newSL, double newTP)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = PositionGetString(POSITION_SYMBOL);
   request.sl       = newSL;
   request.tp       = newTP;

   bool sent = OrderSend(request, result);
   EE_LogDecision(IntegerToString(ticket), sent ? "STOPS_MODIFIED" : "STOPS_MODIFY_FAILED",
                  StringFormat("newSL=%.5f newTP=%.5f retcode=%d", newSL, newTP, result.retcode));
   return sent;
}

//--- Zamknięcie pojedynczej pozycji
bool PM_ClosePosition(ulong ticket, string reasonTag = "manual_close")
{
   if(!PositionSelectByTicket(ticket)) return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   MqlTick tick;
   SymbolInfoTick(symbol, tick);

   request.action   = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol   = symbol;
   request.volume   = volume;
   request.type     = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price    = (posType == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   request.deviation = 20;
   request.type_filling = EE_GetSupportedFillingMode(symbol);

   bool sent = OrderSend(request, result);
   EE_LogDecision(IntegerToString(ticket), sent ? "CLOSED" : "CLOSE_FAILED",
                  StringFormat("reason=%s retcode=%d", reasonTag, result.retcode));
   return sent;
}

//--- Zamknięcie wszystkich pozycji danego EA (używane przez kill-switch)
void PM_CloseAllPositions(int magicNumber, string reasonTag = "kill_switch")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      PM_ClosePosition(ticket, reasonTag);
   }
}

//--- Pobierz tickety wszystkich otwartych pozycji danego EA
//    Rezerwujemy tablicę raz z góry (maksymalny możliwy rozmiar) i przycinamy
//    na końcu, zamiast powiększać ją o 1 przy każdej pozycji w pętli -
//    to ostatnie jest wolniejsze przy większej liczbie pozycji na koncie.
int PM_GetOpenPositionsByMagic(int magicNumber, ulong &tickets[])
{
   int totalPositions = PositionsTotal();
   ArrayResize(tickets, totalPositions);
   int count = 0;

   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      tickets[count] = ticket;
      count++;
   }

   ArrayResize(tickets, count);
   return count;
}

//--- Trailing stop - wywołuj cyklicznie (OnTick lub OnTimer)
void PM_ApplyTrailingStop(int magicNumber, double trailingPoints, double minProfitToStartPoints)
{
   ulong tickets[];
   int count = PM_GetOpenPositionsByMagic(magicNumber, tickets);

   for(int i = 0; i < count; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) continue;

      if(posType == POSITION_TYPE_BUY)
      {
         double profitPoints = (tick.bid - openPrice) / point;
         if(profitPoints < minProfitToStartPoints) continue;

         double newSL = tick.bid - trailingPoints * point;
         if(newSL > currentSL + point) // przesuwaj tylko w górę
            PM_ModifyStops(tickets[i], newSL, PositionGetDouble(POSITION_TP));
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profitPoints = (openPrice - tick.ask) / point;
         if(profitPoints < minProfitToStartPoints) continue;

         double newSL = tick.ask + trailingPoints * point;
         if(newSL < currentSL - point || currentSL == 0) // przesuwaj tylko w dół
            PM_ModifyStops(tickets[i], newSL, PositionGetDouble(POSITION_TP));
      }
   }
}

//--- Break-even - przesuń SL na cenę otwarcia (+ offset) po osiągnięciu progu zysku
void PM_ApplyBreakEven(int magicNumber, double triggerPoints, double offsetPoints)
{
   ulong tickets[];
   int count = PM_GetOpenPositionsByMagic(magicNumber, tickets);

   for(int i = 0; i < count; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick)) continue;

      if(posType == POSITION_TYPE_BUY)
      {
         double profitPoints = (tick.bid - openPrice) / point;
         double breakEvenSL = openPrice + offsetPoints * point;
         if(profitPoints >= triggerPoints && currentSL < breakEvenSL)
            PM_ModifyStops(tickets[i], breakEvenSL, PositionGetDouble(POSITION_TP));
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profitPoints = (openPrice - tick.ask) / point;
         double breakEvenSL = openPrice - offsetPoints * point;
         if(profitPoints >= triggerPoints && (currentSL > breakEvenSL || currentSL == 0))
            PM_ModifyStops(tickets[i], breakEvenSL, PositionGetDouble(POSITION_TP));
      }
   }
}


//===================================================================
//  ROZSZERZENIE: zlecenia oczekujące (limit)
//===================================================================

//--- Złożenie zlecenia limit (GTC). Wygasanie po N świecach obsługuje EA
//    przez PM_CancelPendingOrders - nie każdy broker wspiera ORDER_TIME_SPECIFIED.
ExecutionResult PM_PlaceLimitOrder(string symbol, ENUM_ORDER_TYPE orderType, double volume, double price,
                                    double sl, double tp, int magicNumber, string signalTag)
{
   if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT)
   {
      EE_LogDecision(signalTag, "BLOCKED_VALIDATION", "PM_PlaceLimitOrder obsługuje tylko BUY_LIMIT/SELL_LIMIT");
      return EXEC_FAILED;
   }
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   double vol = volume;
   string errorMsg;
   if(!EE_ValidatePendingParams(symbol, vol, price, sl, tp, orderType, errorMsg))
   {
      EE_LogDecision(signalTag, "BLOCKED_VALIDATION", errorMsg);
      return EXEC_FAILED;
   }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action       = TRADE_ACTION_PENDING;
   request.symbol       = symbol;
   request.volume       = vol;
   request.type         = orderType;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.magic        = magicNumber;
   request.type_time    = ORDER_TIME_GTC;
   request.type_filling = ORDER_FILLING_RETURN; // standard dla zleceń oczekujących
   request.comment      = signalTag;

   string intentId = EE_GenerateIntentId(magicNumber, signalTag);
   return EE_SafePendingSend(request, intentId, magicNumber);
}

//--- Liczba zleceń oczekujących danego EA
int PM_CountPendingByMagic(int magicNumber, string symbol)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;
      n++;
   }
   return n;
}

//--- Usunięcie wszystkich zleceń oczekujących danego EA
void PM_CancelPendingOrders(int magicNumber, string symbol, string reasonTag)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action = TRADE_ACTION_REMOVE;
      request.order  = ticket;
      bool sent = OrderSend(request, result);
      EE_LogDecision(IntegerToString(ticket), sent ? "PENDING_CANCELLED" : "PENDING_CANCEL_FAILED",
                     StringFormat("reason=%s retcode=%d", reasonTag, result.retcode));
   }
}

#endif // __POSITION_MANAGER_MQH__
