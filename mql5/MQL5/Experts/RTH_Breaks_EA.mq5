//+------------------------------------------------------------------+
//| RTH_Breaks_EA.mq5                                                  |
//| Expert Advisor oparty na wskaźniku "RTH Breaks + Midnight          |
//| Confluence" v2.1 (Pine Script v6) - przeniesiony na MQL5.          |
//|                                                                    |
//| O 09:30 NY: otwarcie RTH względem zakresu RTH z poprzedniego dnia  |
//| (gap up / gap down / inside) + zgodność otwarcia o północy (MN).   |
//| Handlowane domyślnie tylko oceny HIGH:                              |
//|   Gap Up HIGH   -> long  limitem na pRTH High, wyjście 15:59 NY    |
//|   Gap Down HIGH -> short limitem na pRTH Low,  wyjście 15:59 NY    |
//|   Inside HIGH   -> market o 09:30 w stronę środka, TP = brzeg      |
//|                                                                    |
//| SEKCJA A: klasyfikacja i decyzje. SEKCJA B: Include/Core.           |
//+------------------------------------------------------------------+
#property copyright "RTH Breaks EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_GAP_ENTRY { GAP_LIMIT_AT_LEVEL = 0, GAP_MARKET_AT_OPEN = 1 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Klasyfikacja dnia ==="
input int            InpServerToNYHours  = 7;        // Czas serwera minus czas Nowego Jorku (godz.). Korekta przy zmianie czasu!
input bool           InpTradeModerate    = false;    // Handluj też Gap Down MODERATE (MN neutralny)
input bool           InpTradeReduced     = false;    // Handluj też Inside REDUCED (MN po drugiej stronie środka)
input bool           InpTradeMidlineOnly = false;    // Handluj, gdy brak danych o północy (MIDLINE ONLY)
input bool           InpTradeInside      = true;     // Handluj dni inside
input double         InpMagnetPct        = 20.0;     // Magnes: MN bliżej niż X% zakresu od przeciwnego brzegu = brak biasu
input bool           InpAutoGold         = true;     // Wyłącz magnes na złocie (XAU/GOLD), jak w oryginale

input group "=== Gap Up / Gap Down ==="
input ENUM_GAP_ENTRY InpGapEntry         = GAP_LIMIT_AT_LEVEL; // Wejście: limit na pRTH H/L (retest) / rynkowe o 09:30
input string         InpLimitExpiry      = "1100";   // Limit ważny do (czas NY, HHMM)
input double         InpGapSlRangeFrac   = 0.25;     // SL: ułamek zakresu pRTH za poziomem pRTH H/L
input double         InpGapTpRR          = 0;        // TP na stałym RR (0 = tylko wyjście na zamknięciu RTH)

input group "=== Inside ==="
input double         InpInsideSlBufFrac  = 0.10;     // SL: bufor za środkiem zakresu (ułamek zakresu pRTH)
input double         InpInsideMinRR      = 1.0;      // Minimalne RR do brzegu zakresu, inaczej pomiń

input group "=== Wyjście ==="
input string         InpRthCloseTime     = "1559";   // Zamknij wszystko o (czas NY, HHMM)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int            InpMagicNumber          = 260406;   // Magic number tej strategii
input double         InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int            InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE  InpLotMode              = LOT_RISK_PERCENT; // % kapitału / stały lot
input double         InpRiskPercentPerTrade  = 1.0;      // % kapitału ryzykowany na transakcję
input double         InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input double         InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double         InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool           InpLogDaily             = true;     // Loguj klasyfikację każdego dnia

//====================================================================
//  STAŁE I STAN
//====================================================================
#define RTH_START 570   // 09:30
#define RTH_END   960   // 16:00
int      g_expiryMin = 660, g_closeMin = 959;
bool     g_isGold = false;
int      g_lastTradeDay = 0;     // klucz daty NY ostatniej obsłużonej sesji
string   EA_VERSION = "1.00";

//====================================================================
//  CZAS NOWEGO JORKU
//====================================================================
datetime ToNY(datetime serverTime) { return serverTime - InpServerToNYHours * 3600; }
int NYMin(datetime serverTime) { MqlDateTime d; TimeToStruct(ToNY(serverTime), d); return d.hour * 60 + d.min; }
int NYDow(datetime serverTime) { MqlDateTime d; TimeToStruct(ToNY(serverTime), d); return d.day_of_week; }
int NYDateKey(datetime serverTime) { MqlDateTime d; TimeToStruct(ToNY(serverTime), d); return d.year * 10000 + d.mon * 100 + d.day; }
//--- sesja "0930-1600:23456": pon-pt, czas otwarcia świecy w [09:30, 16:00)
bool InRTH(datetime serverTime)
{
   int dow = NYDow(serverTime);
   if(dow < 1 || dow > 5) return false;
   int m = NYMin(serverTime);
   return m >= RTH_START && m < RTH_END;
}
int ParseHHMM(string s)
{
   if(StringLen(s) != 4) return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, 2)), m = (int)StringToInteger(StringSubstr(s, 2, 2));
   return (h < 0 || h > 23 || m < 0 || m > 59) ? -1 : h * 60 + m;
}

//====================================================================
//  POZIOMY: pRTH (poprzednia sesja RTH) i otwarcie o północy
//====================================================================
//--- skan świec wstecz od shift 1: wszystkie świece RTH ostatniej zakończonej sesji
bool FindPriorRTH(double &hi, double &lo)
{
   int maxScan = (int)MathMin(Bars(_Symbol, _Period) - 1, 6 * 86400 / PeriodSeconds(_Period) + 10);
   bool found = false;
   int date = 0;
   hi = -DBL_MAX; lo = DBL_MAX;
   for(int s = 1; s <= maxScan; s++)
   {
      datetime t = iTime(_Symbol, _Period, s);
      if(t == 0) break;
      int d = NYDateKey(t);
      if(InRTH(t))
      {
         if(!found) { found = true; date = d; }
         if(d == date)
         {
            hi = MathMax(hi, iHigh(_Symbol, _Period, s));
            lo = MathMin(lo, iLow(_Symbol, _Period, s));
         }
         else break;
      }
      else if(found && d != date) break;
   }
   return found && hi > lo;
}

//--- otwarcie świecy M1 o 00:00 NY bieżącego dnia (z tolerancją do 00:05, gdy brak dokładnej świecy)
double MidnightOpen(datetime rthOpenTime)
{
   datetime ny = ToNY(rthOpenTime);
   MqlDateTime d; TimeToStruct(ny, d);
   d.hour = 0; d.min = 0; d.sec = 0;
   datetime mnServer = StructToTime(d) + InpServerToNYHours * 3600;
   int sh = iBarShift(_Symbol, PERIOD_M1, mnServer, true);
   if(sh < 0)
   {
      sh = iBarShift(_Symbol, PERIOD_M1, mnServer + 5 * 60, false);   // pierwsza świeca do 00:05
      if(sh < 0 || iTime(_Symbol, PERIOD_M1, sh) < mnServer) return EMPTY_VALUE;
   }
   double o = iOpen(_Symbol, PERIOD_M1, sh);
   return o > 0 ? o : EMPTY_VALUE;
}

//====================================================================
//  KLASYFIKACJA (logika z Pine, bez części wizualnej)
//====================================================================
struct DayClass
{
   string scenario;    // GAP UP / GAP DOWN / INSIDE
   string alignment;   // confirms / conflicts / neutral / no MN data
   string conviction;  // HIGH / MODERATE / LOW / SKIP / REDUCED / MAGNET / MIDLINE ONLY
   int    dir;         // 1 long, -1 short, 0 brak biasu
   double hi, lo, mid, open, mn;
};

void Classify(double open, double hi, double lo, double mn, DayClass &c)
{
   double mid = (hi + lo) / 2.0;
   c.hi = hi; c.lo = lo; c.mid = mid; c.open = open; c.mn = mn;
   c.scenario = open > hi ? "GAP UP" : open < lo ? "GAP DOWN" : "INSIDE";
   c.alignment = "neutral";
   bool hasMN = mn != EMPTY_VALUE;
   if(hasMN)
   {
      if(c.scenario == "GAP UP")        c.alignment = mn > hi ? "confirms" : mn < mid ? "conflicts" : "neutral";
      else if(c.scenario == "GAP DOWN") c.alignment = mn < lo ? "confirms" : mn > mid ? "conflicts" : "neutral";
      else                              c.alignment = ((open >= mid) == (mn >= mid)) ? "confirms" : "conflicts";
   }
   if(c.scenario == "GAP UP")        c.conviction = c.alignment == "conflicts" ? "SKIP" : "HIGH";
   else if(c.scenario == "GAP DOWN") c.conviction = c.alignment == "confirms" ? "HIGH" : c.alignment == "neutral" ? "MODERATE" : "LOW";
   else
   {
      c.conviction = c.alignment == "confirms" ? "HIGH" : "REDUCED";
      // magnes: MN przy przeciwnym brzegu neutralizuje bias środka (nie odwraca go); pomijany na złocie
      if(hasMN && !(InpAutoGold && g_isGold))
      {
         double rng = hi - lo;
         if(rng > 0)
         {
            bool above = open >= mid;
            double toHigh = MathAbs(mn - hi) / rng * 100, toLow = MathAbs(mn - lo) / rng * 100;
            if((above && toLow < InpMagnetPct) || (!above && toHigh < InpMagnetPct)) c.conviction = "MAGNET";
         }
      }
   }
   if(!hasMN) { c.alignment = "no MN data"; c.conviction = "MIDLINE ONLY"; }

   if(c.scenario == "GAP UP") c.dir = 1;
   else if(c.scenario == "GAP DOWN") c.dir = -1;
   else c.dir = c.conviction == "MAGNET" ? 0 : (open >= mid ? 1 : -1);
}

bool ShouldTrade(const DayClass &c)
{
   if(c.dir == 0) return false;
   string v = c.conviction;
   if(v == "MIDLINE ONLY") return InpTradeMidlineOnly && (c.scenario != "INSIDE" || InpTradeInside);
   if(c.scenario == "GAP UP")   return v == "HIGH";
   if(c.scenario == "GAP DOWN") return v == "HIGH" || (v == "MODERATE" && InpTradeModerate);
   if(!InpTradeInside) return false;
   return v == "HIGH" || (v == "REDUCED" && InpTradeReduced);
}

//====================================================================
//  WYKONANIE
//====================================================================
string DayKey() { return StringFormat("RTHB_%d_%s_lastDay", InpMagicNumber, _Symbol); }
bool DayAlreadyTraded(int day)
{
   if(g_lastTradeDay == day) return true;
   if(MQLInfoInteger(MQL_TESTER)) return false;
   return GlobalVariableCheck(DayKey()) && (int)GlobalVariableGet(DayKey()) >= day;
}
void MarkDayTraded(int day) { g_lastTradeDay = day; if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(DayKey(), day); }

double CalcVolume(double slDist)
{
   if(InpLotMode == LOT_FIXED) return InpFixedLot;
   return RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, slDist / _Point);
}

void ExecuteDay(const DayClass &c, int day)
{
   double rng = c.hi - c.lo;
   int d = c.dir;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(!RM_CanOpenNewPosition(InpMagicNumber, 1) || PM_CountPendingByMagic(InpMagicNumber, _Symbol) > 0) return;

   string tag = StringFormat("rthb_%s_%d", d == 1 ? "L" : "S", day);
   double entry, sl, tp = 0;
   bool useLimit = false;

   if(c.scenario == "INSIDE")
   {
      // market w stronę środka, TP = brzeg zakresu po stronie biasu, SL za środkiem
      entry = d == 1 ? tick.ask : tick.bid;
      tp = d == 1 ? c.hi : c.lo;
      sl = d == 1 ? c.mid - rng * InpInsideSlBufFrac : c.mid + rng * InpInsideSlBufFrac;
      double risk = (entry - sl) * d, reward = (tp - entry) * d;
      if(risk <= 0 || reward <= 0 || reward / risk < InpInsideMinRR)
      { EE_LogDecision(tag, "SKIPPED_RR", StringFormat("RR=%.2f < %.2f", risk > 0 ? reward / risk : 0, InpInsideMinRR)); MarkDayTraded(day); return; }
   }
   else
   {
      double level = d == 1 ? c.hi : c.lo;
      sl = level - d * rng * InpGapSlRangeFrac;
      useLimit = InpGapEntry == GAP_LIMIT_AT_LEVEL;
      entry = d == 1 ? tick.ask : tick.bid;
      if(useLimit)
      {
         bool reachable = d == 1 ? level < tick.ask : level > tick.bid;
         if(reachable) entry = level;
         else useLimit = false;   // cena już przy poziomie - wejście rynkowe
      }
      if((entry - sl) * d <= 0) { EE_LogDecision(tag, "BLOCKED", "Cena już za poziomem SL"); MarkDayTraded(day); return; }
      double risk = MathAbs(entry - sl);
      if(InpGapTpRR > 0) tp = entry + d * risk * InpGapTpRR;
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   entry = NormalizeDouble(entry, _Digits);

   double vol = CalcVolume(MathAbs(entry - sl));
   if(vol <= 0) { MarkDayTraded(day); return; }
   ENUM_ORDER_TYPE mkt = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, mkt)) return;

   ExecutionResult res;
   if(useLimit) res = PM_PlaceLimitOrder(_Symbol, d == 1 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT, vol, entry, sl, tp, InpMagicNumber, tag);
   else         res = PM_OpenPosition(_Symbol, mkt, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %s %s %s vol=%.2f entry=%s SL=%s TP=%s", c.scenario, c.conviction, useLimit ? "LIMIT" : "MARKET",
                               d == 1 ? "LONG" : "SHORT", vol, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                               tp == 0 ? "zamknięcie RTH" : DoubleToString(tp, _Digits)));
   if(res != EXEC_FAILED) MarkDayTraded(day);
}

//--- 09:30: klasyfikacja dnia i ewentualne wejście
void OnRTHOpen()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   int day = NYDateKey(t0);
   double hi, lo;
   if(!FindPriorRTH(hi, lo)) { if(InpLogDaily) Print("[RTHB] brak danych poprzedniej sesji RTH"); return; }
   double open = iOpen(_Symbol, _Period, 0);
   double mn = MidnightOpen(t0);
   DayClass c;
   Classify(open, hi, lo, mn, c);
   bool trade = ShouldTrade(c);
   if(InpLogDaily)
      PrintFormat("[RTHB] %d | %s | MN %s | %s | kierunek %s | pRTH H=%s L=%s mid=%s | open=%s MN=%s | %s",
                  day, c.scenario, c.alignment, c.conviction, c.dir == 1 ? "LONG" : c.dir == -1 ? "SHORT" : "BRAK",
                  DoubleToString(hi, _Digits), DoubleToString(lo, _Digits), DoubleToString(c.mid, _Digits), DoubleToString(open, _Digits),
                  mn == EMPTY_VALUE ? "-" : DoubleToString(mn, _Digits), trade ? "HANDEL" : "bez handlu");
   if(!trade || DayAlreadyTraded(day)) return;
   ExecuteDay(c, day);
}

//--- wygasanie limitu (11:00 NY) i zamknięcie wszystkiego (15:59 NY)
void ManageTime()
{
   datetime now = TimeCurrent();
   int dow = NYDow(now);
   if(dow < 1 || dow > 5) return;
   int m = NYMin(now);
   if(m >= g_expiryMin && PM_CountPendingByMagic(InpMagicNumber, _Symbol) > 0)
      PM_CancelPendingOrders(InpMagicNumber, _Symbol, "limit_expired");
   if(m >= g_closeMin && m < RTH_END + 60)
   {
      ulong tickets[];
      if(PM_GetOpenPositionsByMagic(InpMagicNumber, tickets) > 0) PM_CloseAllPositions(InpMagicNumber, "rth_close");
      if(PM_CountPendingByMagic(InpMagicNumber, _Symbol) > 0) PM_CancelPendingOrders(InpMagicNumber, _Symbol, "rth_close");
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(PeriodSeconds(_Period) > 1800) { Print("RTH Breaks wymaga wykresu M1-M30 (świeca musi otwierać się o 09:30 NY)"); return INIT_PARAMETERS_INCORRECT; }
   g_expiryMin = ParseHHMM(InpLimitExpiry);
   g_closeMin = ParseHHMM(InpRthCloseTime);
   if(g_expiryMin < 0 || g_closeMin < 0) { Print("Błędny format czasu - użyj HHMM, np. 1559"); return INIT_PARAMETERS_INCORRECT; }
   string up = _Symbol; StringToUpper(up);
   g_isGold = StringFind(up, "XAU") >= 0 || StringFind(up, "GOLD") >= 0 || StringFind(up, "GC") >= 0;
   RC_ReconcileState(InpMagicNumber);
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("RTH Breaks EA %s: serwer-NY=%+d h, wejścia gap=%s, limit do %s, zamknięcie %s NY%s",
               EA_VERSION, InpServerToNYHours, InpGapEntry == GAP_LIMIT_AT_LEVEL ? "limit" : "market", InpLimitExpiry, InpRthCloseTime,
               g_isGold ? " | złoto: magnes wyłączony" : "");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct))
   {
      PM_CancelPendingOrders(InpMagicNumber, _Symbol, "kill_switch");
      return;
   }
   ManageTime();
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;

   // pierwsza świeca RTH: bieżąca świeca w RTH, poprzednia nie (albo z innego dnia)
   datetime t0 = iTime(_Symbol, _Period, 0), t1 = iTime(_Symbol, _Period, 1);
   bool rthStart = InRTH(t0) && (!InRTH(t1) || NYDateKey(t1) != NYDateKey(t0));
   if(rthStart && NYMin(t0) < RTH_START + 30) OnRTHOpen();   // tylko gdy świeca otwarcia faktycznie wypada ok. 09:30
}

void OnTimer()
{
   RC_ReconcileState(InpMagicNumber);
   ManageTime();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
