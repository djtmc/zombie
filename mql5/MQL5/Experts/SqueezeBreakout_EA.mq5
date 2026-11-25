//+------------------------------------------------------------------+
//| SqueezeBreakout_EA.mq5                                             |
//| Expert Advisor oparty na wskaźniku "Squeeze Breakout Signals       |
//| [bitpunk]" (Pine v6) - na MQL5.                                    |
//|                                                                    |
//| Kompresja: 2*stdev(close,20) < 1.5*SMA(TR,20). Po >= 3 ściśniętych |
//| zamknięciach range zostaje zamrożony przy wyjściu z kompresji,     |
//| startuje okno obserwacji 20 świec. Wejścia: pierwsze zamknięcie    |
//| poza krawędzią (breakout, wyznacza kierunek pudełka) oraz retest   |
//| (odejście -> dotknięcie krawędzi +/- 0.25 TR -> zamknięcie za nią).|
//| Dodatkowo: opcjonalny filtr dywergencji RSI na wybranym TF.        |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Squeeze Breakout EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_SQ_RETEST { RETEST_OFF = 0, RETEST_IF_FLAT = 1, RETEST_ADD = 2 };
enum ENUM_SQ_TP     { TPM_RR = 0, TPM_MEASURED_MOVE = 1 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Squeeze Breakout ==="
input int      InpLength        = 20;      // Compression Length
input int      InpMinimumBars   = 3;       // Minimum Compression
input int      InpValidityBars  = 20;      // Range Watch (świece)
input double   InpMaxExtension  = 0.0;     // Max Entry Extension (x TR, 0 = bez limitu)
input double   InpRetestTol     = 0.25;    // Retest Tolerance (x TR)
input bool     InpEntryFilter   = true;    // Retest Close Progress (close retestu dalej niż poprzedni)
input int      InpWarmupBars    = 3000;    // Ile świec historii przeliczyć przy starcie

input group "=== Wejścia ==="
input ENUM_SQ_RETEST InpRetestMode = RETEST_IF_FLAT; // Retest: wył. / tylko bez pozycji / jako dołożenie
input double   InpAddRiskPct    = 0.5;     // Ryzyko dołożenia na retest (% salda)

input group "=== Wyjście ==="
input double   InpSlBufTR       = 0.25;    // SL: przeciwna krawędź pudełka +/- bufor (x zamrożony TR)
input double   InpSlMaxTR       = 4.0;     // Maks. odległość SL od wejścia (x zamrożony TR)
input ENUM_SQ_TP InpTpMode      = TPM_RR;  // TP: RR / zasięg = wysokość pudełka od krawędzi
input double   InpTpRR          = 2.0;     // TP (x odległość SL)
input double   InpTpBoxMult     = 1.0;     // TP zasięgu (x wysokość pudełka)
input bool     InpBreakEvenOn   = false;   // Break-even po osiągnięciu zysku
input double   InpBreakEvenR    = 1.0;     //   próg (x początkowe ryzyko R)
input int      InpBEOffsetPoints = 0;      //   przesunięcie BE w stronę zysku (punkty)

input group "=== Dywergencja RSI (dodatek) ==="
input bool            InpDivOn         = false;          // Wymagaj dywergencji RSI dla wejścia
input ENUM_TIMEFRAMES InpDivTf         = PERIOD_CURRENT; // Interwał dywergencji (domyślnie = wykres)
input int             InpDivRsiLen     = 14;             // Długość RSI dywergencji
input int             InpDivLbL        = 5;              // Pivot: świece z lewej
input int             InpDivLbR        = 5;              // Pivot: świece z prawej (opóźnienie potwierdzenia)
input int             InpDivRangeLo    = 5;              // Min. odstęp między pivotami
input int             InpDivRangeHi    = 60;             // Maks. odstęp między pivotami
input int             InpDivMaxAge     = 30;             // Dywergencja ważna przez N świec interwału dywergencji
input bool            InpDivHidden     = false;          // Uznawaj też dywergencje ukryte (hidden)

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
input int           InpMagicNumber          = 260414;   // Magic number tej strategii
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
input bool          InpLogStructure         = false;    // Loguj zamrożenia pudełek i zdarzenia kontekstowe

//====================================================================
//  NARZĘDZIA
//====================================================================
#define NA EMPTY_VALUE
bool IsNa(double x) { return x == NA; }

struct Hist { double v[]; int cap; int n; int head; };
void   HInit(Hist &h, int cap) { h.cap = MathMax(cap, 1); ArrayResize(h.v, h.cap); h.n = 0; h.head = -1; }
void   HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k < 0 || k >= h.n) return NA; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
double SmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0;
   for(int k = 0; k < len; k++) s += HGet(h, k);
   return s / len;
}
//--- ta.stdev(src, len, true): odchylenie populacyjne
double StdevH(Hist &h, int len)
{
   double m = SmaH(h, len);
   if(IsNa(m)) return NA;
   double q = 0;
   for(int k = 0; k < len; k++) { double d = HGet(h, k) - m; q += d * d; }
   return MathSqrt(q / len);
}

//====================================================================
//  STAN ALGORYTMU (RangeStudy z Pine)
//====================================================================
Hist h_close, h_tr;
int    g_bar = -1;
double g_prevClose = NA, g_prevScale = NA;
datetime g_lastProcessedTime = 0;
bool   g_warmup = true;
int    g_sessStart = 0, g_sessEnd = 0;
string EA_VERSION = "1.00";

int    st_count = 0, st_episode = 0, st_outsideCount = 0;
bool   st_canStart = true, st_used = false, st_watching = false;
double st_runHigh = NA, st_runLow = NA;
int    st_watchEpisode = -1;
double st_rangeHigh = NA, st_rangeLow = NA, st_frozenScale = NA;
int    st_started = 0, st_breakAt = 0, st_ownerSide = 0, st_retestSide = 0;
bool   st_upperBroken = false, st_lowerBroken = false, st_departed = false, st_failed = false, st_touched = false;
//--- wynik bieżącej świecy
int    st_breakout = 0, st_retest = 0, st_signal = 0, st_kind = 0;
bool   st_replaced = false, st_expired = false;
double st_eventEdge = NA, st_distance = NA;

//--- dane świecy przekazywane do metod
double b_h, b_l, b_c;

void ClearWatch()
{
   st_watching = false; st_watchEpisode = -1; st_retestSide = 0;
   st_touched = false; st_departed = false; st_failed = false;
}

void Lock(double priorScale)
{
   st_used = true;
   if(!IsNa(priorScale) && priorScale > 0)
   {
      st_watching = true; st_watchEpisode = st_episode;
      st_rangeHigh = st_runHigh; st_rangeLow = st_runLow; st_frozenScale = priorScale;
      st_started = g_bar;
      st_upperBroken = false; st_lowerBroken = false; st_ownerSide = 0;
      st_departed = false; st_failed = false; st_retestSide = 0; st_touched = false;
      if(InpLogStructure && !g_warmup)
         PrintFormat("[SQZ] pudełko zamrożone: %s - %s | TR %s", DoubleToString(st_rangeLow, _Digits), DoubleToString(st_rangeHigh, _Digits), DoubleToString(st_frozenScale, _Digits));
   }
}

void Observe()
{
   int side = b_c > st_rangeHigh ? 1 : (b_c < st_rangeLow ? -1 : 0);
   bool firstBreak = side > 0 ? !st_upperBroken : (side < 0 ? !st_lowerBroken : false);
   if(firstBreak)
   {
      st_breakout = side;
      st_upperBroken = st_upperBroken || side > 0;
      st_lowerBroken = st_lowerBroken || side < 0;
      if(st_ownerSide == 0)
      {
         st_ownerSide = side; st_retestSide = side; st_breakAt = g_bar; st_touched = false;
         double pocket = InpRetestTol * st_frozenScale;
         st_departed = side > 0 ? b_l > st_rangeHigh + pocket : b_h < st_rangeLow - pocket;
      }
   }
   if(st_retestSide != 0 && g_bar > st_breakAt)
   {
      int dir = st_retestSide;
      double edge = dir > 0 ? st_rangeHigh : st_rangeLow;
      double opposite = dir > 0 ? st_rangeLow : st_rangeHigh;
      if(dir * (b_c - opposite) / st_frozenScale <= 0)
      { st_retestSide = 0; st_touched = false; st_failed = true; }
      else
      {
         double pocket = InpRetestTol * st_frozenScale;
         if(st_departed)
         {
            st_touched = st_touched || (b_l <= edge + pocket && b_h >= edge - pocket);
            if(st_touched && dir * (b_c - edge) / st_frozenScale > 0) { st_retest = dir; st_retestSide = 0; st_touched = false; }
         }
         else if(dir > 0 ? b_l > edge + pocket : b_h < edge - pocket) st_departed = true;
      }
   }
   int eventSide = st_retest != 0 ? st_retest : st_breakout;
   if(eventSide != 0)
   {
      st_eventEdge = eventSide > 0 ? st_rangeHigh : st_rangeLow;
      st_distance = eventSide * (b_c - st_eventEdge) / st_frozenScale;
      bool withinCap = InpMaxExtension == 0 || st_distance <= InpMaxExtension;
      if(eventSide == st_ownerSide && withinCap) { st_signal = eventSide; st_kind = st_retest != 0 ? 2 : 1; }
      if(InpLogStructure && !g_warmup)
         PrintFormat("[SQZ] zdarzenie %s %s | odległość %.2f TR%s", eventSide > 0 ? "UP" : "DOWN", st_retest != 0 ? "retest" : "breakout", st_distance,
                     eventSide != st_ownerSide ? " | przeciwne wybicie (range failed)" : withinCap ? "" : " | poza limitem odległości");
   }
}

void StepStudy(bool dataReady, bool compressed, double priorScale, double recentHigh, double recentLow)
{
   st_breakout = 0; st_retest = 0; st_signal = 0; st_kind = 0;
   st_replaced = false; st_expired = false; st_eventEdge = NA; st_distance = NA;
   if(!dataReady)
   {
      ClearWatch();
      st_count = 0; st_outsideCount = 0; st_canStart = true; st_used = false;
      st_runHigh = NA; st_runLow = NA;
      return;
   }
   bool hadWatch = st_watching;
   if(st_watching && g_bar - st_started >= InpValidityBars) { ClearWatch(); st_expired = true; }
   // stara geometria sprawdzana, zanim nowy dojrzały ciąg może ją zastąpić
   if(st_watching) Observe();
   if(compressed)
   {
      if(st_count == 0)
      {
         if(st_canStart) { st_episode++; st_used = false; }
         st_runHigh = b_h; st_runLow = b_l;
      }
      st_canStart = false; st_outsideCount = 0;
      bool priorPrepared = st_count >= InpMinimumBars && !st_used && st_runHigh > st_runLow;
      if(priorPrepared && !hadWatch)
      {
         int earlySide = b_c > st_runHigh ? 1 : (b_c < st_runLow ? -1 : 0);
         if(earlySide != 0) { Lock(priorScale); if(st_watching) Observe(); }
      }
      st_count++;
      if(!st_used)
      {
         st_runHigh = st_count >= InpLength ? recentHigh : MathMax(st_runHigh, b_h);
         st_runLow  = st_count >= InpLength ? recentLow  : MathMin(st_runLow, b_l);
         if(st_watching && st_watchEpisode != st_episode && st_count >= InpMinimumBars && st_runHigh > st_runLow)
         {
            bool overlaps = st_runLow <= st_rangeHigh && st_runHigh >= st_rangeLow;
            if(overlaps) st_used = true;          // ten sam obszar ceny dzieli stare pudełko, termin i limit wejść
            else { ClearWatch(); st_replaced = true; }
         }
         if(!st_watching) { st_rangeHigh = st_runHigh; st_rangeLow = st_runLow; }
      }
   }
   else
   {
      if(st_count >= InpMinimumBars && !st_used && !st_watching && st_runHigh > st_runLow)
      {
         Lock(priorScale);
         if(st_watching) Observe();
      }
      st_count = 0;
      st_outsideCount++;
      if(st_outsideCount >= InpMinimumBars) st_canStart = true;
   }
}

//--- wynik do handlu (świeca shift 1)
int    g_sig = 0, g_kind = 0;
double g_sigRangeHigh = NA, g_sigRangeLow = NA, g_sigScale = NA, g_sigDistance = NA;

void ProcessBar(int s)
{
   g_bar++;
   g_sig = 0; g_kind = 0;
   b_h = iHigh(_Symbol, _Period, s); b_l = iLow(_Symbol, _Period, s); b_c = iClose(_Symbol, _Period, s);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);
   double tr = IsNa(g_prevClose) ? b_h - b_l : MathMax(b_h - b_l, MathMax(MathAbs(b_h - g_prevClose), MathAbs(b_l - g_prevClose)));
   HPush(h_close, b_c); HPush(h_tr, tr);
   double deviation = StdevH(h_close, InpLength);
   double scale = SmaH(h_tr, InpLength);
   double recentHigh = NA, recentLow = NA;
   int ih = iHighest(_Symbol, _Period, MODE_HIGH, InpLength, s), il = iLowest(_Symbol, _Period, MODE_LOW, InpLength, s);
   if(ih >= 0 && il >= 0) { recentHigh = iHigh(_Symbol, _Period, ih); recentLow = iLow(_Symbol, _Period, il); }
   bool pricesReady = b_h >= b_l && b_c >= b_l && b_c <= b_h;
   bool dataReady = !IsNa(deviation) && !IsNa(scale) && scale > 0 && pricesReady && !IsNa(recentHigh);
   bool compressed = dataReady && 2.0 * deviation < 1.5 * scale;

   StepStudy(dataReady, compressed, g_prevScale, recentHigh, recentLow);

   bool entryPass = !InpEntryFilter || st_kind != 2 || (!IsNa(g_prevClose) && st_signal * (b_c - g_prevClose) > 0);
   if(st_signal != 0 && entryPass)
   {
      g_sig = st_signal; g_kind = st_kind;
      g_sigRangeHigh = st_rangeHigh; g_sigRangeLow = st_rangeLow; g_sigScale = st_frozenScale; g_sigDistance = st_distance;
   }
   else if(st_signal != 0 && InpLogSignals && !g_warmup) Print("[SQZ] retest odfiltrowany: close bez postępu względem poprzedniego");
   g_prevClose = b_c;
   g_prevScale = scale;
}

//====================================================================
//  DYWERGENCJA RSI (pivoty jak we wbudowanym "RSI Divergence")
//====================================================================
bool IsRsiPivot(const double &rsi[], int n, int p, bool low)
{
   if(p - InpDivLbR < 0 || p + InpDivLbL >= n || rsi[p] == EMPTY_VALUE) return false;
   for(int k = 1; k <= InpDivLbR; k++) { double x = rsi[p - k]; if(x == EMPTY_VALUE || (low ? x <= rsi[p] : x >= rsi[p])) return false; }
   for(int k = 1; k <= InpDivLbL; k++) { double x = rsi[p + k]; if(x == EMPTY_VALUE || (low ? x <= rsi[p] : x >= rsi[p])) return false; }
   return true;
}

bool DivergenceFound(bool bull, string &info)
{
   ENUM_TIMEFRAMES tf = InpDivTf == PERIOD_CURRENT ? _Period : InpDivTf;
   datetime closeT = iTime(_Symbol, _Period, 1) + PeriodSeconds(_Period);
   int sh = iBarShift(_Symbol, tf, closeT - 1, false);
   if(sh < 0) return false;
   if(iTime(_Symbol, tf, sh) + PeriodSeconds(tf) > closeT) sh++;       // tylko zamknięte świece interwału
   int need = InpDivMaxAge + InpDivLbR + InpDivRangeHi + InpDivLbL + 2;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, tf, sh, need + 300, r);
   if(n < need + InpDivRsiLen + 5) return false;
   double rsi[]; ArrayResize(rsi, n); ArrayInitialize(rsi, EMPTY_VALUE);
   double au = 0, ad = 0; int cnt = 0;
   for(int i = n - 2; i >= 0; i--)
   {
      double ch = r[i].close - r[i + 1].close;
      double u = MathMax(ch, 0), d = MathMax(-ch, 0);
      if(cnt < InpDivRsiLen) { au += u; ad += d; cnt++; if(cnt < InpDivRsiLen) continue; au /= InpDivRsiLen; ad /= InpDivRsiLen; }
      else { au = (au * (InpDivRsiLen - 1) + u) / InpDivRsiLen; ad = (ad * (InpDivRsiLen - 1) + d) / InpDivRsiLen; }
      rsi[i] = ad == 0 ? 100 : (au == 0 ? 0 : 100 - 100 / (1 + au / ad));
   }
   for(int cb = 0; cb < InpDivMaxAge; cb++)
   {
      int p = cb + InpDivLbR;
      if(!IsRsiPivot(rsi, n, p, bull)) continue;
      for(int q = p + 1; q <= p + InpDivRangeHi && q + InpDivLbL < n; q++)
      {
         if(!IsRsiPivot(rsi, n, q, bull)) continue;
         int dist = q - p;
         if(dist < InpDivRangeLo) break;
         bool regular, hidden;
         if(bull) { regular = r[p].low < r[q].low && rsi[p] > rsi[q];   hidden = r[p].low > r[q].low && rsi[p] < rsi[q]; }
         else     { regular = r[p].high > r[q].high && rsi[p] < rsi[q]; hidden = r[p].high < r[q].high && rsi[p] > rsi[q]; }
         if(regular || (InpDivHidden && hidden))
         {
            info = StringFormat("%s %s na %s: pivot %s vs %s (RSI %.1f vs %.1f)", regular ? "zwykła" : "ukryta", bull ? "bycza" : "niedźwiedzia",
                                EnumToString(tf), TimeToString(r[p].time), TimeToString(r[q].time), rsi[p], rsi[q]);
            return true;
         }
         break;   // tylko poprzedni pivot (jak valuewhen(..., 1))
      }
   }
   return false;
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
int MyPositions(ulong &out[], int &dir)
{
   ulong all[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, all);
   ArrayResize(out, 0);
   dir = 0;
   for(int i = 0; i < n; i++)
   {
      if(!PositionSelectByTicket(all[i]) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = all[i];
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   }
   return ArraySize(out);
}

bool CloseMine(string reason)
{
   ulong tk[]; int dir;
   int n = MyPositions(tk, dir);
   for(int i = 0; i < n; i++) PM_ClosePosition(tk[i], reason);
   return MyPositions(tk, dir) == 0;
}

//--- break-even: dopóki SL jest po stratnej stronie wejścia, R = |wejście - SL|
void ManageBreakEven()
{
   if(!InpBreakEvenOn) return;
   ulong tk[]; int dir;
   int n = MyPositions(tk, dir);
   if(n == 0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   for(int i = 0; i < n; i++)
   {
      if(!PositionSelectByTicket(tk[i])) continue;
      int d = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(sl == 0 || (op - sl) * d <= 0) continue;                 // już na BE lub wyżej
      double R = MathAbs(op - sl);
      double px = d == 1 ? tick.bid : tick.ask;
      if((px - op) * d < InpBreakEvenR * R) continue;
      double be = NormalizeDouble(op + d * InpBEOffsetPoints * _Point, _Digits);
      bool valid = d == 1 ? be < tick.bid - minDist : be > tick.ask + minDist;
      if(valid) PM_ModifyStops(tk[i], be, tp);
   }
}

string SigKey(int kind) { return StringFormat("SQZ_%d_%s_k%d", InpMagicNumber, _Symbol, kind); }
bool SignalAlreadyTraded(int kind, datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey(kind)) && (datetime)GlobalVariableGet(SigKey(kind)) >= bt; }
void MarkSignalTraded(int kind, datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(kind), (double)bt); }

void HandleSignal()
{
   int d = g_sig;
   string side = d == 1 ? "LONG" : "SHORT", what = g_kind == 2 ? "retest" : "breakout";
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(InpLogSignals) PrintFormat("[SQZ] sygnał %s %s | pudełko %s - %s | odległość %.2f TR", side, what,
                                 DoubleToString(g_sigRangeLow, _Digits), DoubleToString(g_sigRangeHigh, _Digits), g_sigDistance);
   if(g_kind == 2 && InpRetestMode == RETEST_OFF) { if(InpLogSignals) Print("[SQZ] retest pominięty: wejścia na reteście wyłączone"); return; }

   ulong tk[]; int posDir;
   int n = MyPositions(tk, posDir);
   bool isAdd = false;
   if(n > 0 && posDir == d)
   {
      if(g_kind == 2 && InpRetestMode == RETEST_ADD && n < 2) isAdd = true;
      else { if(InpLogSignals) Print("[SQZ] pominięty: pozycja w tym kierunku już otwarta"); return; }
   }
   if(!InSession(iTime(_Symbol, _Period, 0))) { if(InpLogSignals) Print("[SQZ] pominięty: poza oknem sesji"); return; }
   if(InpDivOn)
   {
      string info = "";
      if(!DivergenceFound(d == 1, info)) { if(InpLogSignals) Print("[SQZ] pominięty: brak dywergencji RSI w oknie"); return; }
      if(InpLogSignals) Print("[SQZ] dywergencja: ", info);
   }
   if(n > 0 && posDir != d && !CloseMine("reverse_on_opposite")) { EE_LogDecision("SQZ", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   if(SignalAlreadyTraded(g_kind, sigTime)) { EE_LogDecision("SQZ", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double tr = g_sigScale;
   double sl = d == 1 ? g_sigRangeLow - InpSlBufTR * tr : g_sigRangeHigh + InpSlBufTR * tr;
   bool capped = false;
   if((entry - sl) * d > InpSlMaxTR * tr) { sl = entry - d * InpSlMaxTR * tr; capped = true; }
   if((entry - sl) * d <= 0) { if(InpLogSignals) Print("[SQZ] pominięty: cena już za poziomem SL"); return; }
   sl = NormalizeDouble(sl, _Digits);
   double risk = MathAbs(entry - sl);
   double tp = entry + d * risk * InpTpRR;
   if(InpTpMode == TPM_MEASURED_MOVE)
   {
      double edge = d == 1 ? g_sigRangeHigh : g_sigRangeLow;
      double mm = edge + d * (g_sigRangeHigh - g_sigRangeLow) * InpTpBoxMult;
      if((mm - entry) * d > 0) tp = mm;
      else if(InpLogSignals) Print("[SQZ] zasięg pudełka już osiągnięty - TP na RR");
   }
   tp = NormalizeDouble(tp, _Digits);
   double riskPct = isAdd ? InpAddRiskPct : InpRiskPercentPerTrade;
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, riskPct, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string tag = StringFormat("sqz_%s_%s_%d", what, d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %s%s vol=%.2f entry=%s SL=%s%s TP=%s TR=%s", side, what, isAdd ? " (dołożenie)" : "", vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), capped ? " (limit 4 TR)" : "",
                               DoubleToString(tp, _Digits), DoubleToString(tr, _Digits)));
   if(res != EXEC_FAILED) MarkSignalTraded(g_kind, sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpLength < 5 || InpMinimumBars < 2 || InpValidityBars < 1 || InpRetestTol < 0 || InpSlMaxTR <= 0 || InpTpRR <= 0 || InpWarmupBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   g_sessStart = ParseHHMM(InpSessStart); g_sessEnd = ParseHHMM(InpSessEnd);
   if(g_sessStart < 0 || g_sessEnd < 0) { Print("SQZ: błędny format godzin sesji (HH:MM)"); return INIT_PARAMETERS_INCORRECT; }
   HInit(h_close, InpLength + 1); HInit(h_tr, InpLength + 1);
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie maszyny stanów z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - InpLength - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Squeeze Breakout EA %s: przeliczono %d świec | %s | kompresja %d świec | retest %s | dywergencja %s",
               EA_VERSION, start,
               st_watching ? StringFormat("obserwacja pudełka %s - %s (%d/%d)", DoubleToString(st_rangeLow, _Digits), DoubleToString(st_rangeHigh, _Digits), g_bar - st_started, InpValidityBars) : "brak aktywnego pudełka",
               st_count, EnumToString(InpRetestMode),
               InpDivOn ? "wł. (" + EnumToString(InpDivTf == PERIOD_CURRENT ? _Period : InpDivTf) + ")" : "wył.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpSessionFilter && InpFlatAtSessionEnd && !InSession(TimeCurrent()))
   {
      ulong tk[]; int d;
      if(MyPositions(tk, d) > 0) { if(InpLogSignals) Print("[SQZ] koniec okna sesji - zamykam pozycje"); CloseMine("session_end"); }
   }
   ManageBreakEven();
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1 && g_sig != 0) HandleSignal();
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
