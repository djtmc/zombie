//+------------------------------------------------------------------+
//| PureMomentum_EA.mq5                                                |
//| Expert Advisor oparty na wskaźniku "Pure Momentum Oscillator"      |
//| (MisinkoMaster, Pine v6) - na MQL5.                                |
//|                                                                    |
//| cd = 2*close - EMA(close,len); cda = WMA(cd,len);                  |
//| change = (cda - cda[1]) / ATR(len).                                |
//| Trend +1 gdy change > próg long, -1 gdy change < próg short.       |
//| Handel: zmiana trendu na zamkniętej świecy, stop-and-reverse,      |
//| SL 2 x ATR, opcjonalny trailing za linią cda.                      |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Pure Momentum EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_LOT_MODE { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Pure Momentum Oscillator ==="
input int      InpLen          = 45;      // Lookback
input double   InpLongThr      = 0.05;    // Próg long (Long Treshhold)
input double   InpShortThr     = -0.05;   // Próg short (Short Treshhold)
input int      InpWarmupBars   = 2000;    // Ile świec historii przeliczyć przy starcie

input group "=== Filtr wejścia ==="
input bool     InpMinSlopeOn   = false;   // Wejście tylko przy |change| >= min. nachylenia
input double   InpMinSlope     = 0.10;    //   min. nachylenie (x ATR na świecę)

input group "=== Handel ==="
input double   InpSlAtr        = 2.0;     // SL (x ATR(len))
input double   InpTpRR         = 0;       // TP na stałym RR (0 = brak, wyjście na przeciwnym sygnale)
input bool     InpTrailOn      = false;   // Trailing SL za linią cda
input double   InpTrailAtr     = 1.0;     //   odległość od linii cda (x ATR)

input group "=== Sesja (czas Nowego Jorku) ==="
input bool     InpSessionFilter    = false;   // Otwieraj tylko w oknie sesji
input string   InpSessStart        = "09:30"; // Początek okna (NY)
input string   InpSessEnd          = "15:55"; // Koniec okna (NY)
input bool     InpFlatAtSessionEnd = true;    // Zamknij wszystko poza oknem (gdy filtr wł.)
input int      InpServerToNYHours  = 7;       // Czas serwera minus czas Nowego Jorku (godz.). Korekta przy zmianie czasu!

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260413;   // Magic number tej strategii
input double        InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int           InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE InpLotMode              = LOT_RISK_PERCENT; // % kapitału (od odległości SL) / stały lot
input double        InpRiskPercentPerTrade  = 1.0;      // % kapitału ryzykowany na transakcję
input double        InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input double        InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double        InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool          InpLogSignals           = true;     // Loguj sygnały i decyzje

//====================================================================
//  NARZĘDZIA
//====================================================================
#define NA EMPTY_VALUE
bool IsNa(double x) { return x == NA; }

struct Hist { double v[]; int cap; int n; int head; };
void   HInit(Hist &h, int cap) { h.cap = MathMax(cap, 1); ArrayResize(h.v, h.cap); h.n = 0; h.head = -1; }
void   HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k < 0 || k >= h.n) return NA; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
//--- ta.wma: waga len dla najnowszej wartości
double WmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0, w = 0;
   for(int k = 0; k < len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; double wt = len - k; s += x * wt; w += wt; }
   return s / w;
}
struct Rma { int n; double sum; double v; bool ready; };
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }

//====================================================================
//  STAN ALGORYTMU
//====================================================================
bool     g_emaOk = false; double g_ema = 0;
Hist     h_cd;
Rma      g_atr;
double   g_prevClose = NA, g_cda = NA, g_prevCda = NA, g_change = NA, g_atrNow = 0;
int      g_trend = 0;
bool     g_flipLong = false, g_flipShort = false;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
int      g_sessStart = 0, g_sessEnd = 0;
string   EA_VERSION = "1.00";

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY
//====================================================================
void ProcessBar(int s)
{
   g_flipLong = g_flipShort = false;
   double h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);

   // EMA(close) od pierwszej wartości, cd = 2*close - EMA, cda = WMA(cd)
   double a = 2.0 / (InpLen + 1);
   if(!g_emaOk) { g_ema = c; g_emaOk = true; } else g_ema = a * c + (1 - a) * g_ema;
   HPush(h_cd, 2 * c - g_ema);
   g_prevCda = g_cda;
   g_cda = WmaH(h_cd, InpLen);

   // ATR(len) Wildera
   double tr = IsNa(g_prevClose) ? h - l : MathMax(h - l, MathMax(MathAbs(h - g_prevClose), MathAbs(l - g_prevClose)));
   g_prevClose = c;
   RmaUpd(g_atr, tr, InpLen);
   g_atrNow = g_atr.ready ? g_atr.v : 0;

   g_change = (!IsNa(g_cda) && !IsNa(g_prevCda) && g_atr.ready && g_atr.v > 0) ? (g_cda - g_prevCda) / g_atr.v : NA;

   // stan trendu (jak var trend w Pine); pierwsze ustawienie ze stanu 0 nie jest sygnałem
   int prev = g_trend;
   if(!IsNa(g_change))
   {
      if(g_change > InpLongThr)  g_trend = 1;
      if(g_change < InpShortThr) g_trend = -1;
   }
   g_flipLong  = prev == -1 && g_trend == 1;
   g_flipShort = prev == 1 && g_trend == -1;
}

//====================================================================
//  SESJA (czas Nowego Jorku)
//====================================================================
int ParseHHMM(string s)
{
   string parts[];
   if(StringSplit(s, ':', parts) != 2) return -1;
   int hh = (int)StringToInteger(parts[0]), mm = (int)StringToInteger(parts[1]);
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59) return -1;
   return hh * 60 + mm;
}
bool InSession(datetime serverTime)
{
   if(!InpSessionFilter) return true;
   MqlDateTime t;
   TimeToStruct(serverTime - InpServerToNYHours * 3600, t);
   int m = t.hour * 60 + t.min;
   return g_sessStart <= g_sessEnd ? (m >= g_sessStart && m < g_sessEnd) : (m >= g_sessStart || m < g_sessEnd);
}

//====================================================================
//  HANDEL
//====================================================================
ulong MyPosition(int &dir)
{
   ulong tickets[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   dir = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol)
      { dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; return tickets[i]; }
   return 0;
}

bool CloseMine(string reason)
{
   int dir;
   ulong t = MyPosition(dir);
   int guard = 0;
   while(t != 0 && guard++ < 5) { PM_ClosePosition(t, reason); t = MyPosition(dir); }
   return t == 0;
}

void TrailStop()
{
   if(!InpTrailOn || IsNa(g_cda) || g_atrNow <= 0) return;
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double cur = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double newSL = NormalizeDouble(g_cda - dir * InpTrailAtr * g_atrNow, _Digits);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool better = dir == 1 ? newSL > cur + _Point : (cur == 0 || newSL < cur - _Point);
   bool valid  = dir == 1 ? newSL < tick.bid - minDist : newSL > tick.ask + minDist;
   if(better && valid) PM_ModifyStops(t, newSL, tp);
}

string SigKey() { return StringFormat("PMO_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void HandleFlip(int d)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   string side = d == 1 ? "LONG" : "SHORT";
   if(InpLogSignals) PrintFormat("[PMO] zmiana trendu -> %s | change %.3f | cda %s", side, g_change, DoubleToString(g_cda, _Digits));

   // stop-and-reverse: przeciwna pozycja zamykana zawsze, nawet gdy nowe wejście odpadnie na filtrze
   int posDir;
   ulong pos = MyPosition(posDir);
   if(pos != 0 && posDir != d)
   {
      if(!CloseMine("reverse_on_opposite")) { EE_LogDecision("PMO", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   }
   else if(pos != 0) { if(InpLogSignals) Print("[PMO] pominięty: pozycja w tym kierunku już otwarta"); return; }

   if(InpMinSlopeOn && MathAbs(g_change) < InpMinSlope)
   { if(InpLogSignals) PrintFormat("[PMO] wejście pominięte: |change| %.3f < %.3f", MathAbs(g_change), InpMinSlope); return; }
   if(!InSession(iTime(_Symbol, _Period, 0))) { if(InpLogSignals) Print("[PMO] wejście pominięte: poza oknem sesji"); return; }
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("PMO", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(g_atrNow <= 0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = NormalizeDouble(entry - d * InpSlAtr * g_atrNow, _Digits);
   double risk = MathAbs(entry - sl);
   double tp = InpTpRR > 0 ? NormalizeDouble(entry + d * risk * InpTpRR, _Digits) : 0;
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string tag = StringFormat("pmo_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s TP=%s ATR=%s change=%.3f", side, vol, DoubleToString(entry, _Digits),
                               DoubleToString(sl, _Digits), tp == 0 ? "-" : DoubleToString(tp, _Digits), DoubleToString(g_atrNow, _Digits), g_change));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpLen < 2 || InpSlAtr <= 0 || InpWarmupBars < 300) return INIT_PARAMETERS_INCORRECT;
   g_sessStart = ParseHHMM(InpSessStart); g_sessEnd = ParseHHMM(InpSessEnd);
   if(g_sessStart < 0 || g_sessEnd < 0) { Print("PMO: błędny format godzin sesji (HH:MM)"); return INIT_PARAMETERS_INCORRECT; }
   HInit(h_cd, InpLen + 1);
   g_atr.n = 0; g_atr.sum = 0; g_atr.v = 0; g_atr.ready = false;
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu trendu z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Pure Momentum EA %s: przeliczono %d świec | trend %s | change %s | progi %.3f / %.3f",
               EA_VERSION, start, g_trend == 1 ? "UP" : g_trend == -1 ? "DOWN" : "brak",
               IsNa(g_change) ? "-" : DoubleToString(g_change, 3), InpLongThr, InpShortThr);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpSessionFilter && InpFlatAtSessionEnd && !InSession(TimeCurrent()))
   {
      int d;
      if(MyPosition(d) != 0) { if(InpLogSignals) Print("[PMO] koniec okna sesji - zamykam pozycję"); CloseMine("session_end"); }
   }
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1)
      {
         if(g_flipLong) HandleFlip(1);
         else if(g_flipShort) HandleFlip(-1);
         TrailStop();
      }
   }
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
