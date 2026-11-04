//+------------------------------------------------------------------+
//| STRB_EA.mq5                                                        |
//| Expert Advisor oparty na logice wskaźnika "Season Timed Range     |
//| Breakout (STRB)" (OlympusCipher, Pine Script v6) - na MQL5.       |
//|                                                                    |
//| SEKCJA A (ten plik): zakresy 3 okien czasowych, wykrywanie         |
//| breakoutu z filtrami, poziomy SL/T1/T2/T3, wyjścia częściowe,      |
//| zamknięcie na końcu sesji okna.                                    |
//| SEKCJA B (Include/Core): wykonanie zleceń, ryzyko, reconciliation.|
//|                                                                    |
//| Jak w oryginale: wszystko liczone na zamkniętych świecach.         |
//+------------------------------------------------------------------+
#property copyright "STRB EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_RANGE_MODE   { RANGE_SESSION = 0, RANGE_FIRST_N = 1 };
enum ENUM_CONFIRM      { CONFIRM_CLOSE = 0, CONFIRM_WICK = 1 };
enum ENUM_SIGNAL_MODE  { SIG_FIRST_ONLY = 0, SIG_ONCE_PER_SIDE = 1 };
enum ENUM_SL_MODE      { SL_RANGE_MULT = 0, SL_PERCENT = 1 };
enum ENUM_ENTRY_MODE   { ENTRY_MARKET = 0, ENTRY_LIMIT_AT_LEVEL = 1 };
enum ENUM_TP_PLAN      { TP_SPLIT_THIRDS = 0, TP_ALL_AT_T2 = 1, TP_ORIGINAL_SL_SESSION = 2 };
enum ENUM_LOT_MODE     { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Ogólne ==="
input int              InpServerToNYHours = 7;               // Czas serwera minus czas Nowego Jorku (godz.). Korekta przy zmianie czasu!
input ENUM_RANGE_MODE  InpRangeMode       = RANGE_SESSION;   // Zakres: okno czasowe / pierwsze N świec sesji
input int              InpOrbBarCount     = 6;               // Liczba świec (tryb "pierwsze N")
input bool             InpMultiWindow     = true;            // Tryb wielu okien (okna 2 i 3)
input int              InpWarmupBars      = 2000;            // Ile świec historii przeliczyć przy starcie

input group "=== Okno 1 ==="
input string           InpW1Name          = "NY";            // Nazwa
input string           InpW1Range         = "0930-0945";     // Okno zakresu (czas NY, koniec wyłączny)
input string           InpW1Full          = "0930-1600";     // Sesja handlowa (czas NY)

input group "=== Okno 2 ==="
input bool             InpW2On            = true;            // Włącz okno 2
input string           InpW2Name          = "LON";           // Nazwa
input string           InpW2Range         = "0400-0500";     // Okno zakresu
input string           InpW2Full          = "0300-1100";     // Sesja handlowa

input group "=== Okno 3 ==="
input bool             InpW3On            = true;            // Włącz okno 3
input string           InpW3Name          = "ASIA";          // Nazwa
input string           InpW3Range         = "2000-2100";     // Okno zakresu
input string           InpW3Full          = "2000-0400";     // Sesja handlowa

input group "=== Breakout i poziomy ==="
input ENUM_CONFIRM     InpConfirm         = CONFIRM_CLOSE;   // Potwierdzenie: zamknięcie / knot (na zamkniętej świecy)
input ENUM_SIGNAL_MODE InpSignalMode      = SIG_FIRST_ONLY;  // Sygnałów na sesję: tylko pierwszy / raz na stronę
input double           InpBufTicks        = 0;               // Bufor breakoutu (ticki)
input double           InpTgt1            = 0.5;             // Cel 1 (x zakres, 0 = wył.)
input double           InpTgt2            = 1.0;             // Cel 2 (x zakres, 0 = wył.)
input double           InpTgt3            = 2.0;             // Cel 3 (x zakres, 0 = wył.)
input ENUM_SL_MODE     InpSlMode          = SL_RANGE_MULT;   // SL: wielokrotność zakresu / % ceny
input double           InpSlRangeMult     = 1.20;            // SL: wielokrotność zakresu (1.0 = przeciwny brzeg zakresu)
input double           InpSlPct           = 1.0;             // SL: % ceny poziomu wejścia

input group "=== Filtry sygnału ==="
input int              InpAtrLen          = 14;              // Dzienny ATR - długość (z poprzedniego dnia)
input double           InpMinRangeAtr     = 10.0;            // Zakres "wąski" poniżej (% dziennego ATR)
input double           InpMaxRangeAtr     = 60.0;            // Zakres "szeroki" powyżej (% dziennego ATR)
input bool             InpUseRangeFilter  = false;           // Filtr: tylko zakresy normalnej wielkości
input bool             InpUseVolFilter    = false;           // Filtr: względny wolumen (tickowy)
input int              InpVolLen          = 20;              // Średnia wolumenu - długość
input double           InpVolMult         = 1.2;             // Min. względny wolumen (x)
input bool             InpUseVwapFilter   = false;           // Filtr: long nad VWAP, short pod VWAP

input group "=== Wejście i wyjście ==="
input ENUM_ENTRY_MODE  InpEntryMode       = ENTRY_MARKET;    // Rynkowe po breakoucie / limit na poziomie zakresu (retest)
input ENUM_TP_PLAN     InpTpPlan          = TP_SPLIT_THIRDS; // 1/3 na T1, 1/3 na T2, reszta na T3
input bool             InpCloseAtSessionEnd = true;          // Zamknij pozycję na końcu sesji okna (jak w oryginale)
input bool             InpExitOnFailure   = false;           // Zamknij, gdy świeca zamknie się z powrotem w zakresie
input bool             InpPerWindowPositions = false;        // 1 pozycja na okno (zamiast 1 łącznie)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int              InpMagicNumber          = 260404;    // Magic number tej strategii
input double           InpMaxSpreadPoints      = 300;       // Maksymalny spread (punkty)
input int              InpSlippagePoints       = 50;        // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE    InpLotMode              = LOT_RISK_PERCENT; // % kapitału / stały lot
input double           InpRiskPercentPerTrade  = 1.0;       // % kapitału ryzykowany na transakcję
input double           InpFixedLot             = 0.30;      // Stały lot (gdy tryb = stały)
input double           InpMaxDailyDrawdownPct  = 3.0;       // Kill-switch dzienny (% equity)
input double           InpMaxTotalDrawdownPct  = 10.0;      // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool             InpLogSignals           = true;      // Loguj zakresy, sygnały i decyzje
input bool             InpLogFiltered          = false;     // Loguj breakouty odrzucone przez filtry

//====================================================================
//  STAN OKIEN (odpowiednik typu Win z Pine - bez części wizualnej)
//====================================================================
struct Win
{
   string name;
   bool   enabled;
   int    rStart, rEnd, fStart, fEnd;   // minuty doby w czasie NY
   bool   wasInside, wasFull;
   int    cnt;
   double hi, lo;
   bool   hasRange;
   double atrPct;
   bool   done, armed, longFired, shortFired;
   int    dir;
};
Win      g_w[3];
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
string   EA_VERSION = "1.00";

//--- sygnały z ostatnio przetworzonej świecy
bool     g_sigLong[3], g_sigShort[3];
datetime g_sigTime = 0;

//====================================================================
//  CZAS I SESJE
//====================================================================
bool ParseSession(string sess, int &startMin, int &endMin)
{
   if(StringLen(sess) != 9 || StringGetCharacter(sess, 4) != '-') return false;
   startMin = (int)StringToInteger(StringSubstr(sess, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 2, 2));
   endMin   = (int)StringToInteger(StringSubstr(sess, 5, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 7, 2));
   return startMin >= 0 && startMin < 1440 && endMin >= 0 && endMin < 1440;
}
int NYMinute(datetime serverTime)
{
   MqlDateTime d; TimeToStruct(serverTime - InpServerToNYHours * 3600, d);
   return d.hour * 60 + d.min;
}
//--- jak time(tf, session): czas OTWARCIA świecy w sesji, koniec wyłączny, dozwolone przejście przez północ
bool InSess(datetime serverTime, int s, int e)
{
   int m = NYMinute(serverTime);
   if(e > s) return m >= s && m < e;
   return m >= s || m < e;
}

//====================================================================
//  FILTRY: dzienny ATR (poprzedni dzień), względny wolumen, VWAP
//====================================================================
double DailyAtrPrev(datetime barTime)
{
   int ds = iBarShift(_Symbol, PERIOD_D1, barTime, false);
   if(ds < 0) return EMPTY_VALUE;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, PERIOD_D1, ds + 1, InpAtrLen * 10, r); // od poprzedniego (zamkniętego) dnia wstecz
   if(n < InpAtrLen + 1) return EMPTY_VALUE;
   // RMA Wildera jak ta.atr: start od SMA pierwszych len TR, liczone od najstarszego
   double sum = 0, atr = 0;
   int cnt = 0;
   for(int i = n - 1; i >= 0; i--)
   {
      double tr = r[i].high - r[i].low;
      if(i + 1 < n) tr = MathMax(tr, MathMax(MathAbs(r[i].high - r[i + 1].close), MathAbs(r[i].low - r[i + 1].close)));
      if(cnt < InpAtrLen) { sum += tr; cnt++; atr = sum / cnt; }
      else atr = (atr * (InpAtrLen - 1) + tr) / InpAtrLen;
   }
   return cnt >= InpAtrLen ? atr : EMPTY_VALUE;
}

double RelVol(int s)
{
   if(s + InpVolLen >= Bars(_Symbol, _Period)) return EMPTY_VALUE;
   double sum = 0;
   for(int k = 0; k < InpVolLen; k++) sum += (double)iTickVolume(_Symbol, _Period, s + k);
   double avg = sum / InpVolLen;
   return avg > 0 ? (double)iTickVolume(_Symbol, _Period, s) / avg : EMPTY_VALUE;
}

//--- VWAP(hlc3) od początku dnia brokera, ważony wolumenem tickowym
double Vwap(int s)
{
   datetime dayOpen = iTime(_Symbol, PERIOD_D1, iBarShift(_Symbol, PERIOD_D1, iTime(_Symbol, _Period, s), false));
   double pv = 0, v = 0;
   for(int k = s; k < Bars(_Symbol, _Period); k++)
   {
      datetime t = iTime(_Symbol, _Period, k);
      if(t < dayOpen) break;
      double vol = (double)iTickVolume(_Symbol, _Period, k);
      pv += (iHigh(_Symbol, _Period, k) + iLow(_Symbol, _Period, k) + iClose(_Symbol, _Period, k)) / 3.0 * vol;
      v += vol;
   }
   return v > 0 ? pv / v : EMPTY_VALUE;
}

//====================================================================
//  SILNIK OKNA (f_run z Pine) - jedna zamknięta świeca
//====================================================================
void RunWindow(int idx, int s)
{
   g_sigLong[idx] = g_sigShort[idx] = false;
   if(!g_w[idx].enabled) return;

   datetime t = iTime(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s), o = iOpen(_Symbol, _Period, s);
   bool inR = InSess(t, g_w[idx].rStart, g_w[idx].rEnd);
   bool inF = InSess(t, g_w[idx].fStart, g_w[idx].fEnd);

   // licznik świec (tryb "pierwsze N")
   if(inF && !g_w[idx].wasFull) g_w[idx].cnt = 0;
   if(inF) g_w[idx].cnt++;

   bool inside = InpRangeMode == RANGE_SESSION ? inR : (inF && g_w[idx].cnt <= InpOrbBarCount);
   bool rStart = inside && !g_w[idx].wasInside;
   bool rEnd   = !inside && g_w[idx].wasInside;

   // koniec sesji handlowej: sygnały z tego zakresu wygasają
   if(!inF && g_w[idx].wasFull) g_w[idx].armed = false;

   // budowa zakresu
   if(rStart)
   {
      g_w[idx].hi = h; g_w[idx].lo = l; g_w[idx].hasRange = true;
      g_w[idx].atrPct = EMPTY_VALUE;
      g_w[idx].done = false; g_w[idx].armed = false;
      g_w[idx].longFired = false; g_w[idx].shortFired = false; g_w[idx].dir = 0;
   }
   else if(inside && g_w[idx].hasRange)
   {
      g_w[idx].hi = MathMax(g_w[idx].hi, h);
      g_w[idx].lo = MathMin(g_w[idx].lo, l);
   }

   // zakres gotowy
   if(rEnd && g_w[idx].hasRange && !g_w[idx].done)
   {
      g_w[idx].done = true; g_w[idx].armed = true;
      double rng = g_w[idx].hi - g_w[idx].lo;
      double dAtr = DailyAtrPrev(t);
      g_w[idx].atrPct = (dAtr == EMPTY_VALUE || dAtr == 0) ? EMPTY_VALUE : rng / dAtr * 100;
      if(InpLogSignals && !g_warmup)
         PrintFormat("[STRB] %s: zakres gotowy RH=%s RL=%s (%.1f%% dziennego ATR)", g_w[idx].name,
                     DoubleToString(g_w[idx].hi, _Digits), DoubleToString(g_w[idx].lo, _Digits),
                     g_w[idx].atrPct == EMPTY_VALUE ? 0.0 : g_w[idx].atrPct);
   }

   // wykrywanie breakoutu (tylko zakres bieżącej sesji)
   if(g_w[idx].armed && g_w[idx].done && inF && !inside && g_w[idx].hasRange)
   {
      double buf = InpBufTicks * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double upSrc = InpConfirm == CONFIRM_CLOSE ? c : h;
      double dnSrc = InpConfirm == CONFIRM_CLOSE ? c : l;
      bool upOk = upSrc > g_w[idx].hi + buf;
      bool dnOk = dnSrc < g_w[idx].lo - buf;
      if(upOk && dnOk) { upOk = c >= o; dnOk = !upOk; }   // obie strony na jednej świecy: kierunek świecy

      // filtry (odrzucony breakout nie zużywa sygnału sesji)
      bool needVol = InpUseVolFilter, needVwap = InpUseVwapFilter;
      double rv = needVol ? RelVol(s) : EMPTY_VALUE;
      double vw = needVwap ? Vwap(s) : EMPTY_VALUE;
      double ap = g_w[idx].atrPct;
      bool passRange = !InpUseRangeFilter || ap == EMPTY_VALUE || (ap >= InpMinRangeAtr && ap <= InpMaxRangeAtr);
      bool passVol   = !needVol || rv == EMPTY_VALUE || rv >= InpVolMult;
      bool passL     = !needVwap || vw == EMPTY_VALUE || c > vw;
      bool passS     = !needVwap || vw == EMPTY_VALUE || c < vw;
      if(InpLogFiltered && !g_warmup && ((upOk && !(passRange && passVol && passL)) || (dnOk && !(passRange && passVol && passS))))
         PrintFormat("[STRB] %s: breakout odrzucony filtrem (zakres=%d wolumen=%d vwap=%d)", g_w[idx].name, passRange, passVol, upOk ? passL : passS);
      upOk = upOk && passRange && passVol && passL;
      dnOk = dnOk && passRange && passVol && passS;

      bool allowLong  = !g_w[idx].longFired  && (InpSignalMode == SIG_ONCE_PER_SIDE || !g_w[idx].shortFired);
      bool allowShort = !g_w[idx].shortFired && (InpSignalMode == SIG_ONCE_PER_SIDE || !g_w[idx].longFired);
      if(upOk && allowLong)  { g_sigLong[idx] = true;  g_w[idx].longFired = true; }
      if(dnOk && allowShort) { g_sigShort[idx] = true; g_w[idx].shortFired = true; }
      if((g_sigLong[idx] || g_sigShort[idx]) && g_w[idx].dir == 0) g_w[idx].dir = g_sigLong[idx] ? 1 : -1;
   }

   g_w[idx].wasInside = inside;
   g_w[idx].wasFull = inF;
}

void ProcessBar(int s)
{
   for(int i = 0; i < 3; i++) RunWindow(i, s);
   g_sigTime = iTime(_Symbol, _Period, s);
   g_lastProcessedTime = g_sigTime;
}

//====================================================================
//  STAN POZYCJI / ZLECEŃ (zmienne globalne terminala, klucz = ticket)
//  Identyfikator pozycji w MT5 = ticket zlecenia otwierającego, więc
//  plan zapisany przy zleceniu limit działa też po jego wypełnieniu.
//====================================================================
string GvPrefix(ulong t) { return "STRB_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString((long)t) + "_"; }
void   GvSet(ulong t, string f, double v) { GlobalVariableSet(GvPrefix(t) + f, v); }
double GvGet(ulong t, string f) { string k = GvPrefix(t) + f; return GlobalVariableCheck(k) ? GlobalVariableGet(k) : EMPTY_VALUE; }
void   GvClear(ulong t) { GlobalVariablesDeleteAll(GvPrefix(t)); }

int CountMine(int winIdx)   // winIdx < 0 = wszystkie okna; liczy pozycje i zlecenia oczekujące
{
   int n = 0;
   ulong tickets[];
   int np = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < np; i++)
   {
      if(!PositionSelectByTicket(tickets[i]) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(winIdx < 0 || (int)GvGet(tickets[i], "win") == winIdx) n++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t) || OrderGetInteger(ORDER_MAGIC) != InpMagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(winIdx < 0 || (int)GvGet(t, "win") == winIdx) n++;
   }
   return n;
}

//--- zamknij pozycje i usuń zlecenia danego okna
void CloseWindow(int winIdx, string reason)
{
   ulong tickets[];
   int np = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < np; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol && (int)GvGet(tickets[i], "win") == winIdx)
         if(PM_ClosePosition(tickets[i], reason)) GvClear(tickets[i]);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t) || OrderGetInteger(ORDER_MAGIC) != InpMagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)GvGet(t, "win") != winIdx) continue;
      MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
      rq.action = TRADE_ACTION_REMOVE; rq.order = t;
      bool sent = OrderSend(rq, rs);
      EE_LogDecision(IntegerToString(t), sent ? "PENDING_CANCELLED" : "PENDING_CANCEL_FAILED", "reason=" + reason);
      if(sent) GvClear(t);
   }
}

//--- TP1/TP2 (częściowe wyjścia) - na każdym ticku, dla wszystkich pozycji EA
void ManagePartials()
{
   ulong tickets[];
   int np = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   if(np == 0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   for(int i = 0; i < np; i++)
   {
      ulong t = tickets[i];
      if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double tp1 = GvGet(t, "tp1"), tp2 = GvGet(t, "tp2");
      if(tp1 == EMPTY_VALUE && tp2 == EMPTY_VALUE) continue;
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double px = isBuy ? tick.bid : tick.ask;
      bool r2 = tp2 != EMPTY_VALUE && (isBuy ? px >= tp2 : px <= tp2);
      bool r1 = r2 || (tp1 != EMPTY_VALUE && (isBuy ? px >= tp1 : px <= tp1));
      if(r1 && GvGet(t, "h1") != 1)
      {
         double v1 = GvGet(t, "v1");
         if(v1 <= 0 || v1 == EMPTY_VALUE || PM_ClosePartial(t, v1, "T1")) GvSet(t, "h1", 1);
      }
      if(r2 && GvGet(t, "h2") != 1 && PositionSelectByTicket(t))
      {
         double v2 = GvGet(t, "v2");
         if(v2 <= 0 || v2 == EMPTY_VALUE || PM_ClosePartial(t, v2, "T2")) GvSet(t, "h2", 1);
      }
   }
}

//--- nieudany breakout: zamknięcie świecy z powrotem za poziomem wejścia
void CheckFailures(int s)
{
   if(!InpExitOnFailure) return;
   double c = iClose(_Symbol, _Period, s);
   ulong tickets[];
   int np = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < np; i++)
   {
      ulong t = tickets[i];
      if(!PositionSelectByTicket(t) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double lvl = GvGet(t, "lvl");
      if(lvl == EMPTY_VALUE) continue;
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if(isBuy ? c < lvl : c > lvl)
      {
         EE_LogDecision(IntegerToString(t), "FAILED_BREAKOUT", "Świeca zamknęła się z powrotem w zakresie - zamykam");
         if(PM_ClosePosition(t, "failed_breakout")) GvClear(t);
      }
   }
}

//--- idempotencja sygnału (poza testerem)
string SigKey(int w) { return StringFormat("STRB_%d_%s_%d_lastSig", InpMagicNumber, _Symbol, w); }
bool SignalAlreadyTraded(int w, datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey(w)) && (datetime)GlobalVariableGet(SigKey(w)) >= bt; }
void MarkSignalTraded(int w, datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(w), (double)bt); }

//====================================================================
//  OBSŁUGA SYGNAŁU BREAKOUTU
//====================================================================
void HandleSignal(int w, int d)
{
   string side = d == 1 ? "LONG" : "SHORT";
   double hi = g_w[w].hi, lo = g_w[w].lo, rng = hi - lo;
   if(InpLogSignals) PrintFormat("[STRB] %s: breakout %s (RH=%s RL=%s)", g_w[w].name, side, DoubleToString(hi, _Digits), DoubleToString(lo, _Digits));
   if(rng <= 0) return;
   if(SignalAlreadyTraded(w, g_sigTime)) { EE_LogDecision("STRB", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }
   if(CountMine(InpPerWindowPositions ? w : -1) > 0) { if(InpLogSignals) Print("[STRB] pominięty: limit pozycji (", InpPerWindowPositions ? "na okno" : "łącznie", ")"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;

   // poziomy z oryginału: wejście = brzeg zakresu, SL i cele względem niego
   double level = d == 1 ? hi : lo;
   double slDist = InpSlMode == SL_RANGE_MULT ? rng * InpSlRangeMult : level * InpSlPct / 100.0;
   double sl = NormalizeDouble(level - d * slDist, _Digits);
   double t1 = InpTgt1 > 0 ? NormalizeDouble(level + d * rng * InpTgt1, _Digits) : EMPTY_VALUE;
   double t2 = InpTgt2 > 0 ? NormalizeDouble(level + d * rng * InpTgt2, _Digits) : EMPTY_VALUE;
   double t3 = InpTgt3 > 0 ? NormalizeDouble(level + d * rng * InpTgt3, _Digits) : EMPTY_VALUE;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   bool useLimit = InpEntryMode == ENTRY_LIMIT_AT_LEVEL;
   double entry = d == 1 ? tick.ask : tick.bid;
   if(useLimit)
   {
      bool reachable = d == 1 ? level < tick.ask : level > tick.bid;
      if(reachable) entry = level;
      else { useLimit = false; EE_LogDecision("STRB", "LIMIT_TO_MARKET", "Cena już na poziomie zakresu - wejście rynkowe"); }
   }
   if(d == 1 ? sl >= entry : sl <= entry) { EE_LogDecision("STRB", "BLOCKED", "SL po złej stronie ceny wejścia"); return; }

   // TP po stronie brokera
   double brokerTP = 0;
   if(InpTpPlan == TP_SPLIT_THIRDS) brokerTP = t3 != EMPTY_VALUE ? t3 : t2 != EMPTY_VALUE ? t2 : t1 != EMPTY_VALUE ? t1 : 0;
   else if(InpTpPlan == TP_ALL_AT_T2) brokerTP = t2 != EMPTY_VALUE ? t2 : t3 != EMPTY_VALUE ? t3 : t1 != EMPTY_VALUE ? t1 : 0;
   if(brokerTP != 0 && (d == 1 ? brokerTP <= entry : brokerTP >= entry))
   { EE_LogDecision("STRB", "BLOCKED", "Cena już za docelowym TP - brak sensownego wejścia"); return; }

   double risk = MathAbs(entry - sl);
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE mkt = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, mkt)) return;

   // podział na T1 / T2 / T3 - tylko gdy wszystkie trzy cele są włączone
   double v1 = 0, v2 = 0;
   if(InpTpPlan == TP_SPLIT_THIRDS && t1 != EMPTY_VALUE && t2 != EMPTY_VALUE && t3 != EMPTY_VALUE)
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double third = MathFloor(vol / 3.0 / step + 1e-9) * step;
      if(third >= mn && vol - 2 * third >= mn - 1e-9) { v1 = third; v2 = third; }
      else EE_LogDecision("STRB", "SPLIT_SKIPPED", StringFormat("wolumen %.2f za mały na 3 części - całość na T3", vol));
   }

   string tag = StringFormat("strb%d_%s_%d", w + 1, d == 1 ? "L" : "S", (int)g_sigTime);
   ExecutionResult res;
   if(useLimit) res = PM_PlaceLimitOrder(_Symbol, d == 1 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT, vol, entry, sl, brokerTP, InpMagicNumber, tag);
   else         res = PM_OpenPosition(_Symbol, mkt, vol, sl, brokerTP, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %s %s vol=%.2f entry=%s SL=%s T1=%s T2=%s T3=%s", g_w[w].name, useLimit ? "LIMIT" : "MARKET", side, vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                               t1 == EMPTY_VALUE ? "-" : DoubleToString(t1, _Digits), t2 == EMPTY_VALUE ? "-" : DoubleToString(t2, _Digits),
                               t3 == EMPTY_VALUE ? "-" : DoubleToString(t3, _Digits)));
   if(res == EXEC_FAILED) return;
   MarkSignalTraded(w, g_sigTime);
   if(res != EXEC_CONFIRMED) return;

   // zapisz plan pod ticketem pozycji (rynek) lub zlecenia (limit = późniejszy identyfikator pozycji)
   ulong t = 0;
   if(useLimit)
   {
      for(int i = OrdersTotal() - 1; i >= 0 && t == 0; i--)
      {
         ulong ot = OrderGetTicket(i);
         if(ot != 0 && OrderSelect(ot) && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol &&
            MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - entry) < _Point) t = ot;
      }
   }
   else t = PM_FindLatestTicketByMagic(InpMagicNumber, _Symbol);
   if(t == 0) return;
   GvClear(t);
   GvSet(t, "win", w);
   GvSet(t, "lvl", level);
   if(InpTpPlan == TP_SPLIT_THIRDS && v1 > 0)
   {
      GvSet(t, "tp1", t1); GvSet(t, "tp2", t2);
      GvSet(t, "v1", v1);  GvSet(t, "v2", v2);
      GvSet(t, "h1", 0);   GvSet(t, "h2", 0);
   }
}

//--- koniec sesji okna: zamknij jego pozycje (jak "finish" przy końcu sesji w oryginale)
void CheckSessionEnds()
{
   datetime t0 = iTime(_Symbol, _Period, 0), t1 = iTime(_Symbol, _Period, 1);
   for(int w = 0; w < 3; w++)
   {
      if(!g_w[w].enabled) continue;
      bool wasIn = InSess(t1, g_w[w].fStart, g_w[w].fEnd);
      bool isIn  = InSess(t0, g_w[w].fStart, g_w[w].fEnd);
      if(wasIn && !isIn)
      {
         // zlecenia limit wygasają zawsze; pozycje - zgodnie z ustawieniem
         if(InpCloseAtSessionEnd) CloseWindow(w, "session_end");
         else
         {
            // tylko zlecenia oczekujące
            for(int i = OrdersTotal() - 1; i >= 0; i--)
            {
               ulong t = OrderGetTicket(i);
               if(t == 0 || !OrderSelect(t) || OrderGetInteger(ORDER_MAGIC) != InpMagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
               if((int)GvGet(t, "win") != w) continue;
               MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
               rq.action = TRADE_ACTION_REMOVE; rq.order = t;
               if(OrderSend(rq, rs)) GvClear(t);
            }
         }
         if(InpLogSignals) PrintFormat("[STRB] %s: koniec sesji handlowej", g_w[w].name);
      }
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
bool InitWindow(int i, string name, bool en, string rng, string full)
{
   g_w[i].name = name;
   g_w[i].enabled = en;
   g_w[i].wasInside = false; g_w[i].wasFull = false; g_w[i].cnt = 0;
   g_w[i].hasRange = false; g_w[i].done = false; g_w[i].armed = false;
   g_w[i].longFired = false; g_w[i].shortFired = false; g_w[i].dir = 0;
   g_w[i].atrPct = EMPTY_VALUE;
   if(!ParseSession(rng, g_w[i].rStart, g_w[i].rEnd) || !ParseSession(full, g_w[i].fStart, g_w[i].fEnd))
   { PrintFormat("Okno %s: błędny format sesji - użyj HHMM-HHMM", name); return false; }
   return true;
}

int OnInit()
{
   if(PeriodSeconds(_Period) >= 86400) { Print("STRB działa tylko na interwałach śróddziennych (M1-H12)"); return INIT_PARAMETERS_INCORRECT; }
   if(!InitWindow(0, InpW1Name, true, InpW1Range, InpW1Full) ||
      !InitWindow(1, InpW2Name, InpMultiWindow && InpW2On, InpW2Range, InpW2Full) ||
      !InitWindow(2, InpW3Name, InpMultiWindow && InpW3On, InpW3Range, InpW3Full))
      return INIT_PARAMETERS_INCORRECT;

   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu okien z historii (bez handlu) - EA wie, czy breakout tej sesji już był
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("STRB EA %s: przeliczono %d świec | okna: %s%s%s | serwer-NY=%+d h",
               EA_VERSION, start, g_w[0].name, g_w[1].enabled ? ", " + g_w[1].name : "", g_w[2].enabled ? ", " + g_w[2].name : "", InpServerToNYHours);
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
   if(InpTpPlan == TP_SPLIT_THIRDS) ManagePartials();
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;

   CheckSessionEnds();

   // przetwórz świece zamknięte od ostatniego razu; handluj tylko sygnałem z najświeższej
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1)
      {
         CheckFailures(s);
         for(int w = 0; w < 3; w++)
         {
            if(g_sigLong[w])  HandleSignal(w, 1);
            if(g_sigShort[w]) HandleSignal(w, -1);
         }
      }
   }
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN) RC_RegisterTicket(InpMagicNumber, posId);
   else if(!PositionSelectByTicket(posId)) GvClear(posId);
}
