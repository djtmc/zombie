//+------------------------------------------------------------------+
//| ExecutionEngine.mqh                                               |
//| Warstwa: bezpieczne wykonanie zlecenia + weryfikacja post-exec    |
//| Nie edytuj tego pliku per-strategia - to wspólny, przetestowany   |
//| rdzeń. Logikę sygnału pisz w pliku EA, nie tutaj.                 |
//+------------------------------------------------------------------+
#ifndef __EXECUTION_ENGINE_MQH__
#define __EXECUTION_ENGINE_MQH__

enum ExecutionResult
{
   EXEC_CONFIRMED,   // zlecenie potwierdzone na serwerze
   EXEC_FAILED,      // zlecenie jednoznacznie nieudane (nie retry'uj bez zmiany parametrów)
   EXEC_UNCERTAIN    // brak jednoznacznego potwierdzenia - wymaga reconciliation, NIE retry
};

//--- Cache parametrów symbolu (volume min/max/step, stops level, filling mode).
//    Te wartości praktycznie nie zmieniają się w ciągu sesji handlowej, więc
//    odpytywanie terminala o nie przy KAŻDYM zleceniu jest zbędnym kosztem.
//    Odświeżane raz na godzinę - wystarczająco świeże, a oszczędza mnóstwo wywołań.
struct EE_SymbolSpecs
{
   string   symbol;
   double   volumeMin;
   double   volumeMax;
   double   volumeStep;
   double   point;
   long     stopsLevelPoints;
   int      fillingModeFlags;
   datetime cachedAt;
};

EE_SymbolSpecs g_ee_symbolSpecsCache[];

EE_SymbolSpecs EE_GetCachedSymbolSpecs(string symbol)
{
   int refreshIntervalSec = 3600;

   for(int i = 0; i < ArraySize(g_ee_symbolSpecsCache); i++)
   {
      if(g_ee_symbolSpecsCache[i].symbol == symbol &&
         (TimeCurrent() - g_ee_symbolSpecsCache[i].cachedAt) < refreshIntervalSec)
         return g_ee_symbolSpecsCache[i];
   }

   EE_SymbolSpecs specs;
   specs.symbol           = symbol;
   specs.volumeMin        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   specs.volumeMax        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   specs.volumeStep       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   specs.point            = SymbolInfoDouble(symbol, SYMBOL_POINT);
   specs.stopsLevelPoints = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   specs.fillingModeFlags = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   specs.cachedAt         = TimeCurrent();

   bool updated = false;
   for(int i = 0; i < ArraySize(g_ee_symbolSpecsCache); i++)
   {
      if(g_ee_symbolSpecsCache[i].symbol == symbol) { g_ee_symbolSpecsCache[i] = specs; updated = true; break; }
   }
   if(!updated)
   {
      int size = ArraySize(g_ee_symbolSpecsCache);
      ArrayResize(g_ee_symbolSpecsCache, size + 1);
      g_ee_symbolSpecsCache[size] = specs;
   }

   return specs;
}

//--- Log/alert hooki - podepnij pod swój system logowania (plik/baza/Telegram)
//    Domyślna implementacja pisze do dziennika terminala.
void EE_LogDecision(string refId, string status, string details)
{
   PrintFormat("[EE][%s] %s | %s", refId, status, details);
}
void EE_TriggerAlert(string message)
{
   Print("[ALERT] ", message);
   // TODO: podłącz webhook/Telegram jeśli skonfigurowany w EA
}

//--- Walidacja parametrów przed wysłaniem (patrz ea-execution-safety pkt 12,19,20)
bool EE_ValidateOrderParams(string symbol, double &volume, double price, double sl, double tp,
                             ENUM_ORDER_TYPE orderType, string &errorMsg)
{
   EE_SymbolSpecs specs = EE_GetCachedSymbolSpecs(symbol);

   if(volume < specs.volumeMin) { errorMsg = StringFormat("Wolumen %.2f poniżej minimum %.2f", volume, specs.volumeMin); return false; }
   if(volume > specs.volumeMax) { errorMsg = StringFormat("Wolumen %.2f powyżej maksimum %.2f", volume, specs.volumeMax); return false; }
   volume = MathRound(volume / specs.volumeStep) * specs.volumeStep;

   double minStopDistance = specs.stopsLevelPoints * specs.point;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   { errorMsg = "Nie udało się pobrać aktualnej ceny (tick)"; return false; }
   double currentPrice = (orderType == ORDER_TYPE_BUY) ? tick.ask : tick.bid;

   if(sl != 0 && MathAbs(currentPrice - sl) < minStopDistance)
   { errorMsg = StringFormat("SL zbyt blisko ceny (min %.5f)", minStopDistance); return false; }
   if(tp != 0 && MathAbs(currentPrice - tp) < minStopDistance)
   { errorMsg = StringFormat("TP zbyt blisko ceny (min %.5f)", minStopDistance); return false; }

   if(!(bool)SymbolInfoInteger(symbol, SYMBOL_SELECT))
   { errorMsg = "Symbol niewidoczny w Market Watch"; return false; }

   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   { errorMsg = "Handel na tym symbolu jest wyłączony"; return false; }

   return true;
}

//--- Idempotency: unikalny identyfikator zamiaru, zapisywany PRZED wysłaniem
string EE_GenerateIntentId(int magicNumber, string signalTag)
{
   return StringFormat("%d_%d_%s", magicNumber, (int)TimeCurrent(), signalTag);
}

bool EE_IsIntentAlreadyHandled(string intentId)
{
   return FileIsExist("intents\\" + intentId + ".flag");
}
void EE_RegisterIntent(string intentId)
{
   int h = FileOpen("intents\\" + intentId + ".flag", FILE_WRITE|FILE_TXT);
   if(h != INVALID_HANDLE) { FileWrite(h, TimeToString(TimeCurrent())); FileClose(h); }
}

//--- Kody błędów, po których retry bez zmiany parametrów nie ma sensu
bool EE_IsDefinitiveFailure(uint retcode)
{
   return (retcode == TRADE_RETCODE_INVALID_STOPS ||
           retcode == TRADE_RETCODE_NO_MONEY ||
           retcode == TRADE_RETCODE_MARKET_CLOSED ||
           retcode == TRADE_RETCODE_INVALID_VOLUME ||
           retcode == TRADE_RETCODE_INVALID);
}

//--- Weryfikacja istnienia pozycji na serwerze po wysłaniu (source of truth = serwer)
bool EE_VerifyPositionExistsByMagic(int magicNumber, string symbol, double approxVolume)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(MathAbs(PositionGetDouble(POSITION_VOLUME) - approxVolume) < 0.0001) return true;
   }
   return false;
}

//--- Rdzeń: bezpieczne OrderSend z weryfikacją post-execution
//    NIGDY nie wywołuj OrderSend bezpośrednio w kodzie strategii - zawsze przez tę funkcję.
ExecutionResult EE_SafeOrderSend(MqlTradeRequest &request, string intentId, int magicNumber)
{
   MqlTradeResult result;
   ZeroMemory(result);

   if(EE_IsIntentAlreadyHandled(intentId))
   {
      EE_LogDecision(intentId, "SKIPPED", "Intent już obsłużony - blokada duplikatu");
      return EE_VerifyPositionExistsByMagic(magicNumber, request.symbol, request.volume) ? EXEC_CONFIRMED : EXEC_UNCERTAIN;
   }

   EE_RegisterIntent(intentId);
   bool sent = OrderSend(request, result);

   // Sprawdź NATYCHMIAST - OrderSend w MT5 jest synchroniczny, więc w większości
   // przypadków pozycja już istnieje na serwerze zaraz po powrocie z funkcji.
   // Blokujące Sleep(300) za każdym razem niepotrzebnie zamrażało przetwarzanie
   // ticków przy KAŻDYM zleceniu. Czekamy tylko wtedy, gdy faktycznie trzeba.
   bool existsOnServer = EE_VerifyPositionExistsByMagic(magicNumber, request.symbol, request.volume);

   if(!existsOnServer)
   {
      // Krótkie, narastające próby zamiast jednego sztywnego opóźnienia -
      // łapie przypadki opóźnionej propagacji stanu po stronie serwera,
      // ale nie płaci tej ceny, gdy propagacja była natychmiastowa.
      int retryDelaysMs[] = {50, 100, 150};
      for(int i = 0; i < ArraySize(retryDelaysMs) && !existsOnServer; i++)
      {
         Sleep(retryDelaysMs[i]);
         existsOnServer = EE_VerifyPositionExistsByMagic(magicNumber, request.symbol, request.volume);
      }
   }

   if(existsOnServer)
   {
      EE_LogDecision(intentId, "CONFIRMED", "Pozycja zweryfikowana na serwerze");
      return EXEC_CONFIRMED;
   }

   if(!sent && EE_IsDefinitiveFailure(result.retcode))
   {
      EE_LogDecision(intentId, "FAILED", StringFormat("retcode=%d", result.retcode));
      return EXEC_FAILED;
   }

   EE_LogDecision(intentId, "UNCERTAIN", StringFormat("sent=%d retcode=%d", sent, result.retcode));
   EE_TriggerAlert("EA: niepewny wynik OrderSend dla " + intentId + " - wymaga reconciliation");
   return EXEC_UNCERTAIN;
}

//--- Weryfikacja SL/TP po otwarciu - broker mógł je zignorować przy market execution
bool EE_VerifyStopsApplied(ulong positionTicket, double expectedSL, double expectedTP)
{
   if(!PositionSelectByTicket(positionTicket)) return false;
   double actualSL = PositionGetDouble(POSITION_SL);
   double actualTP = PositionGetDouble(POSITION_TP);
   double pt = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);

   bool slOk = (expectedSL == 0) || (MathAbs(actualSL - expectedSL) < pt);
   bool tpOk = (expectedTP == 0) || (MathAbs(actualTP - expectedTP) < pt);

   if(!slOk || !tpOk)
      EE_LogDecision(IntegerToString(positionTicket), "STOPS_MISMATCH",
                     StringFormat("expected SL=%.5f TP=%.5f, actual SL=%.5f TP=%.5f", expectedSL, expectedTP, actualSL, actualTP));
   return slOk && tpOk;
}

//--- Wykrycie trybu wypełnienia zlecenia obsługiwanego przez brokera/symbol.
//    NIGDY nie zakładaj na sztywno IOC/FOK/RETURN - różni się między brokerami i symbolami.
ENUM_ORDER_TYPE_FILLING EE_GetSupportedFillingMode(string symbol)
{
   EE_SymbolSpecs specs = EE_GetCachedSymbolSpecs(symbol);
   int filling = specs.fillingModeFlags;

   // Preferencja: FOK > IOC > RETURN (RETURN typowy dla exchange execution/kont typu netting z rynkami regulowanymi)
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}


//===================================================================
//  ROZSZERZENIE: zlecenia oczekujące (limit)
//  Te same zasady co dla zleceń rynkowych: walidacja przed wysłaniem,
//  idempotency-key, weryfikacja na serwerze po wysłaniu.
//===================================================================

//--- Walidacja zlecenia oczekującego: cena zlecenia i SL/TP muszą być
//    odsunięte o co najmniej stops level (od ceny bieżącej i od ceny zlecenia)
bool EE_ValidatePendingParams(string symbol, double &volume, double orderPrice, double sl, double tp,
                              ENUM_ORDER_TYPE orderType, string &errorMsg)
{
   EE_SymbolSpecs specs = EE_GetCachedSymbolSpecs(symbol);

   if(volume < specs.volumeMin) { errorMsg = StringFormat("Wolumen %.2f poniżej minimum %.2f", volume, specs.volumeMin); return false; }
   if(volume > specs.volumeMax) { errorMsg = StringFormat("Wolumen %.2f powyżej maksimum %.2f", volume, specs.volumeMax); return false; }
   volume = MathRound(volume / specs.volumeStep) * specs.volumeStep;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) { errorMsg = "Nie udało się pobrać aktualnej ceny (tick)"; return false; }

   double minDist = specs.stopsLevelPoints * specs.point;
   bool isBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);

   if(orderType == ORDER_TYPE_BUY_LIMIT  && orderPrice > tick.ask - minDist) { errorMsg = "Buy limit nie jest poniżej ceny Ask (z marginesem stops level)"; return false; }
   if(orderType == ORDER_TYPE_SELL_LIMIT && orderPrice < tick.bid + minDist) { errorMsg = "Sell limit nie jest powyżej ceny Bid (z marginesem stops level)"; return false; }

   if(sl == 0) { errorMsg = "Zlecenie bez SL jest niedozwolone"; return false; }
   if(isBuy  && sl >= orderPrice - minDist) { errorMsg = "SL buy limit zbyt blisko lub po złej stronie ceny zlecenia"; return false; }
   if(!isBuy && sl <= orderPrice + minDist) { errorMsg = "SL sell limit zbyt blisko lub po złej stronie ceny zlecenia"; return false; }
   if(tp != 0 && MathAbs(tp - orderPrice) < minDist) { errorMsg = "TP zbyt blisko ceny zlecenia"; return false; }

   if(!(bool)SymbolInfoInteger(symbol, SYMBOL_SELECT)) { errorMsg = "Symbol niewidoczny w Market Watch"; return false; }
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
   { errorMsg = "Handel na tym symbolu jest wyłączony"; return false; }
   return true;
}

//--- Czy na serwerze istnieje zlecenie oczekujące o tych parametrach
bool EE_VerifyPendingExists(int magicNumber, string symbol, ENUM_ORDER_TYPE orderType, double price)
{
   double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != orderType) continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price) < pt) return true;
   }
   return false;
}

//--- Bezpieczne wysłanie zlecenia oczekującego z weryfikacją post-execution
ExecutionResult EE_SafePendingSend(MqlTradeRequest &request, string intentId, int magicNumber)
{
   MqlTradeResult result;
   ZeroMemory(result);

   if(EE_IsIntentAlreadyHandled(intentId))
   {
      EE_LogDecision(intentId, "SKIPPED", "Intent już obsłużony - blokada duplikatu zlecenia oczekującego");
      return EE_VerifyPendingExists(magicNumber, request.symbol, request.type, request.price) ? EXEC_CONFIRMED : EXEC_UNCERTAIN;
   }

   EE_RegisterIntent(intentId);
   bool sent = OrderSend(request, result);

   bool exists = EE_VerifyPendingExists(magicNumber, request.symbol, request.type, request.price);
   if(!exists)
   {
      int retryDelaysMs[] = {50, 100, 150};
      for(int i = 0; i < ArraySize(retryDelaysMs) && !exists; i++)
      {
         Sleep(retryDelaysMs[i]);
         exists = EE_VerifyPendingExists(magicNumber, request.symbol, request.type, request.price);
      }
   }
   if(exists)
   {
      EE_LogDecision(intentId, "PENDING_CONFIRMED", StringFormat("Zlecenie oczekujące na serwerze, cena=%.5f", request.price));
      return EXEC_CONFIRMED;
   }
   if(!sent && EE_IsDefinitiveFailure(result.retcode))
   {
      EE_LogDecision(intentId, "PENDING_FAILED", StringFormat("retcode=%d", result.retcode));
      return EXEC_FAILED;
   }
   EE_LogDecision(intentId, "PENDING_UNCERTAIN", StringFormat("sent=%d retcode=%d", sent, result.retcode));
   EE_TriggerAlert("EA: niepewny wynik zlecenia oczekującego " + intentId + " - wymaga weryfikacji");
   return EXEC_UNCERTAIN;
}

#endif // __EXECUTION_ENGINE_MQH__
