//+------------------------------------------------------------------+
//| ReconciliationManager.mqh                                         |
//| Warstwa: stan lokalny to tylko cache. Serwer jest źródłem prawdy. |
//| Wywołuj RC_ReconcileState() w OnInit oraz cyklicznie w OnTimer.   |
//+------------------------------------------------------------------+
#ifndef __RECONCILIATION_MANAGER_MQH__
#define __RECONCILIATION_MANAGER_MQH__

#include "ExecutionEngine.mqh"

bool RC_ArrayContainsUlong(const ulong &arr[], ulong value)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value) return true;
   return false;
}

//--- Lokalny rejestr ticketów - plik prosty (jeden ticket per linia)
void RC_SaveLocalTicketRegistry(int magicNumber, const ulong &tickets[])
{
   string filename = StringFormat("registry_%d.txt", magicNumber);
   int h = FileOpen(filename, FILE_WRITE|FILE_TXT);
   if(h == INVALID_HANDLE) return;
   for(int i = 0; i < ArraySize(tickets); i++)
      FileWrite(h, IntegerToString(tickets[i]));
   FileClose(h);
}

void RC_LoadLocalTicketRegistry(int magicNumber, ulong &tickets[])
{
   ArrayResize(tickets, 0);
   string filename = StringFormat("registry_%d.txt", magicNumber);
   if(!FileIsExist(filename)) return;

   int h = FileOpen(filename, FILE_READ|FILE_TXT);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) > 0)
      {
         int size = ArraySize(tickets);
         ArrayResize(tickets, size + 1);
         tickets[size] = (ulong)StringToInteger(line);
      }
   }
   FileClose(h);
}

//--- Główna pętla reconciliation - serwer nadpisuje stan lokalny, zawsze
void RC_ReconcileState(int magicNumber)
{
   int totalPositions = PositionsTotal();
   ulong serverTickets[];
   ArrayResize(serverTickets, totalPositions);
   int serverCount = 0;

   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      serverTickets[serverCount] = ticket;
      serverCount++;
   }
   ArrayResize(serverTickets, serverCount);

   ulong localTickets[];
   RC_LoadLocalTicketRegistry(magicNumber, localTickets);

   // Pozycje, które EA "myślał" że ma, a serwer ich nie widzi (np. zamknięte przez SL/TP)
   for(int i = 0; i < ArraySize(localTickets); i++)
   {
      if(!RC_ArrayContainsUlong(serverTickets, localTickets[i]))
      {
         EE_LogDecision(IntegerToString(localTickets[i]), "RECONCILE_CLOSED_EXTERNALLY",
                        "Pozycja zamknięta poza EA (SL/TP/ręcznie) - aktualizuję stan lokalny");
      }
   }

   // Pozycje na serwerze, o których EA nie wiedział - WYMAGA UWAGI
   for(int i = 0; i < ArraySize(serverTickets); i++)
   {
      if(!RC_ArrayContainsUlong(localTickets, serverTickets[i]))
      {
         EE_LogDecision(IntegerToString(serverTickets[i]), "RECONCILE_UNKNOWN_POSITION",
                        "Pozycja na serwerze nieznana lokalnie - możliwy duplikat lub pozycja z poprzedniej sesji");
         EE_TriggerAlert(StringFormat("EA: nieznana pozycja na koncie - ticket %d - WERYFIKACJA RĘCZNA", serverTickets[i]));
      }
   }

   // Serwer zawsze wygrywa - nadpisz stan lokalny
   RC_SaveLocalTicketRegistry(magicNumber, serverTickets);
}


//===================================================================
//  ROZSZERZENIE: rejestracja pozycji otwartej przez EA
//  Bez tego każda nowa pozycja EA byłaby przy najbliższym
//  RC_ReconcileState oznaczona jako "nieznana" (fałszywy alarm).
//  Wywołuj z OnTradeTransaction po potwierdzonym deal'u wejścia.
//===================================================================
void RC_RegisterTicket(int magicNumber, ulong ticket)
{
   ulong tickets[];
   RC_LoadLocalTicketRegistry(magicNumber, tickets);
   if(RC_ArrayContainsUlong(tickets, ticket)) return;
   int n = ArraySize(tickets);
   ArrayResize(tickets, n + 1);
   tickets[n] = ticket;
   RC_SaveLocalTicketRegistry(magicNumber, tickets);
   EE_LogDecision(IntegerToString(ticket), "REGISTERED", "Pozycja EA dopisana do rejestru lokalnego");
}

#endif // __RECONCILIATION_MANAGER_MQH__
