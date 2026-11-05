//+------------------------------------------------------------------+
//| AMD_Po3_EA.mq5                                                     |
//| Expert Advisor oparty na wskaźniku "AMD Po3 with Live Edge Stats   |
//| [WillyAlgoTrader]" v2.4.0 (Pine v6) - na MQL5.                     |
//|                                                                    |
//| FSM: IDLE -> ACCUMULATION (kompresja Donchian(20) w dolnym         |
//| percentylu) -> SWEEP_PENDING (wyjście poza granicę) -> MANIP       |
//| (powrót do range w N świec) -> DISTRIBUTION (transakcja            |
//| referencyjna: stop za sweepem + bufor ATR, cel = rozszerzenie fib).|
//| Dodatkowo: wejście w dystrybucji potwierdzone CISD i/lub           |
//| dywergencją RSI.                                                   |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "AMD Po3 EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_PO3_BOUNDARY { BOUND_PIVOT = 0, BOUND_ABSOLUTE = 1 };
enum ENUM_PO3_ENTRY    { ENTRY_REFERENCE = 0, ENTRY_CISD = 1, ENTRY_RSI_DIV = 2, ENTRY_CISD_OR_DIV = 3, ENTRY_CISD_AND_DIV = 4 };
enum ENUM_LOT_MODE     { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Range (akumulacja) ==="
input int               InpMinRangeBars   = 12;          // Min range maturity, bars
input int               InpMaxRangeBars   = 96;          // Max range age, bars
input int               InpCompressionPct = 25;          // Compression threshold, percentile
input int               InpStatWindow     = 200;         // Distribution window, bars
input double            InpRangeTol       = 0.10;        // Boundary expansion tolerance (x szerokość)
input double            InpMinRangeWidthP = 0.15;        // Min range width, % ceny
input ENUM_PO3_BOUNDARY InpBoundaryMode   = BOUND_PIVOT; // Boundary method
input int               InpTrimTailPct    = 15;          // Impulse-tail trim, % szerokości (0 = wył.)

input group "=== Manipulacja (sweep) ==="
input int      InpSweepReturnBars = 6;      // Max bars until return
input bool     InpRequireLiq      = false;  // Wymagaj płynności EQH/EQL przy granicy
input int      InpSweepDepthPct   = 100;    // Soft depth cap, percentyl TR (100 = wył.)
input bool     InpAllowRearm      = true;   // Allow re-arm (double sweep)

input group "=== Dystrybucja / model referencyjny ==="
input int      InpDistTimeout     = 64;     // Distribution timeout, bars
input double   InpStopBufAtr      = 0.4;    // Stop buffer past sweep (x ATR anchor)
input double   InpFibExt          = 1.5;    // Fib extension target

input group "=== Filtry ==="
input bool            InpUseKillzones   = false;       // Killzones (sweep tylko w sesjach)
input int             InpServerToKzHours = 2;          // Czas serwera minus strefa killzone (godz.; UTC: zwykle +2/+3). Korekta przy zmianie czasu!
input string          InpKzLdn          = "0700-1000"; // London killzone (HHMM-HHMM)
input string          InpKzNy           = "1330-1600"; // New York killzone (HHMM-HHMM)
input bool            InpUseHtfBias     = false;       // HTF bias (close vs EMA50)
input ENUM_TIMEFRAMES InpHtfTf          = PERIOD_H4;   // HTF bias timeframe

input group "=== Wejście w dystrybucji ==="
input ENUM_PO3_ENTRY  InpEntryMode      = ENTRY_REFERENCE; // Referencyjne / CISD / dywergencja RSI / CISD lub dyw. / CISD i dyw.
input int             InpConfirmBars    = 10;          // Okno na potwierdzenie (świece od świecy D)
input double          InpMinRRLeft      = 0.5;         // Min. pozostały R:R przy wejściu (od bieżącej ceny)
input int             InpDivRsiLen      = 14;          // Długość RSI dywergencji
input ENUM_TIMEFRAMES InpDivTf          = PERIOD_CURRENT; // TF dywergencji (wykres = sweep vs dołek/szczyt range; inny = pivoty)
input int             InpDivLbL         = 5;           // Inny TF: pivot - świece z lewej
input int             InpDivLbR         = 5;           // Inny TF: pivot - świece z prawej
input int             InpDivRangeLo     = 5;           // Inny TF: min. odstęp pivotów
input int             InpDivRangeHi     = 60;          // Inny TF: maks. odstęp pivotów
input int             InpDivMaxAge      = 20;          // Inny TF: dywergencja ważna przez N świec
input int             InpWarmupBars     = 3000;        // Ile świec historii przeliczyć przy starcie

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260415;   // Magic number tej strategii
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
input bool          InpLogFsm               = false;    // Loguj przejścia FSM (akumulacja, sweep, resety)

//====================================================================
//  STAŁE Z ORYGINAŁU
//====================================================================
#define COOLDOWN_BARS 10
#define RANGE_WIN     20
#define PIVOT_LR      3
#define PIVOT_CAP     60
#define EQ_LOOKBACK   96
#define NA            EMPTY_VALUE
#define ST_IDLE   0
#define ST_ACCUM  1
#define ST_SWEEP  2
#define ST_MANIP  3
#define ST_DIST   4

bool IsNa(double x) { return x == NA; }

struct Hist { double v[]; int cap; int n; int head; };
void   HInit(Hist &h, int cap) { h.cap = MathMax(cap, 1); ArrayResize(h.v, h.cap); h.n = 0; h.head = -1; }
void   HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k < 0 || k >= h.n) return NA; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
struct Rma { int n; double sum; double v; bool ready; };
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }

//--- ta.percentrank: % z poprzednich len wartości <= bieżąca
double PercentRank(Hist &h, int len)
{
   if(h.n < len + 1) return NA;
   double cur = HGet(h, 0);
   if(IsNa(cur)) return NA;
   int c = 0;
   for(int k = 1; k <= len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; if(x <= cur) c++; }
   return 100.0 * c / len;
}
//--- ta.percentile_nearest_rank(src, len, pct)
double NearestRank(Hist &h, int len, double pct)
{
   if(h.n < len) return NA;
   double a[]; ArrayResize(a, len);
   for(int k = 0; k < len; k++) a[k] = HGet(h, k);
   ArraySort(a);
   int rank = (int)MathCeil(pct / 100.0 * len);
   rank = MathMax(1, MathMin(len, rank));
   return a[rank - 1];
}

//====================================================================
//  STAN ALGORYTMU
//====================================================================
int      g_bar = -1, g_bars = 0;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
double   g_tick = 0;
Rma      g_atr; Rma g_rsiUp, g_rsiDn;
Hist     h_atr, h_trf, h_chW, h_rsi;
double   g_trThr = NA, g_prevClose = NA;
int      g_htfHandle = INVALID_HANDLE;
int      g_kzLdnS = 0, g_kzLdnE = 0, g_kzNyS = 0, g_kzNyE = 0;

double   pivHiV[], pivLoV[]; int pivHiB[], pivLoB[];

int    state = ST_IDLE, cycleId = 0, lastEndBar = -100;
double rangeHigh = NA, rangeLow = NA, rangeMid = NA, rangeWidth = NA, tolPx = NA, atrAnchor = NA;
int    rangeStartBar = 0, expiryAnchor = 0, rangeAge = 0;
int    sweepSide = 0, firstSweepSide = 0, sweepBar = 0, sweepExtremeBar = 0;
double sweepExtreme = NA, depthCapPx = NA;
bool   rearmUsed = false;
int    distDir = 0, distStartBar = 0;
double entryPrice = NA, stopPrice = NA, tgtPrice = NA, riskR = NA;
//--- statystyki walk-forward (tylko do logu)
int    tgtN = 0, stopN = 0, timeoutN = 0, ambigN = 0, failN = 0, brkN = 0;
double sumR = 0;

//--- zdarzenia bieżącej świecy
int    ev_dist = 0;        // +1 / -1: dystrybucja otwarta na tej świecy
int    ev_outcome = 0;     // 1 target, -1 stop, 2 timeout, 3 ambiguous
//--- oczekujące wejście potwierdzane (CISD / dywergencja)
bool   pend_active = false;
int    pend_dir = 0, pend_until = 0;
double pend_cisdLevel = NA;
bool   pend_divStruct = false;

string EA_VERSION = "1.00";

void PushPivot(double &vals[], int &bars[], double v, int b)
{
   int n = ArraySize(vals);
   ArrayResize(vals, n + 1); ArrayResize(bars, n + 1);
   vals[n] = v; bars[n] = b;
   if(n + 1 > PIVOT_CAP) { ArrayRemove(vals, 0, 1); ArrayRemove(bars, 0, 1); }
}

double HiAt(int s) { return iHigh(_Symbol, _Period, s); }
double LoAt(int s) { return iLow(_Symbol, _Period, s); }
double OpAt(int s) { return iOpen(_Symbol, _Period, s); }
double ClAt(int s) { return iClose(_Symbol, _Period, s); }
double TickRound(double p) { return MathRound(p / g_tick) * g_tick; }
double TickOut(double p, bool up) { return (up ? MathCeil(p / g_tick) : MathFloor(p / g_tick)) * g_tick; }

int ParseSess(string s, int &st, int &en)
{
   string parts[];
   if(StringSplit(s, '-', parts) != 2 || StringLen(parts[0]) != 4 || StringLen(parts[1]) != 4) return -1;
   int a = (int)StringToInteger(parts[0]), b = (int)StringToInteger(parts[1]);
   st = (a / 100) * 60 + a % 100; en = (b / 100) * 60 + b % 100;
   return (st >= 0 && st < 1440 && en >= 0 && en <= 1440) ? 0 : -1;
}
bool InSess(int m, int st, int en) { return st <= en ? (m >= st && m < en) : (m >= st || m < en); }
bool InKillzone(datetime barOpen)
{
   MqlDateTime t; TimeToStruct(barOpen - InpServerToKzHours * 3600, t);
   int m = t.hour * 60 + t.min;
   return InSess(m, g_kzLdnS, g_kzLdnE) || InSess(m, g_kzNyS, g_kzNyE);
}

//--- HTF bias: close i EMA50 z ostatniej ZAMKNIĘTEJ świecy HTF ([1] + lookahead_on)
bool HtfValues(datetime barOpen, double &hc, double &he)
{
   hc = NA; he = NA;
   if(g_htfHandle == INVALID_HANDLE) return false;
   int hs = iBarShift(_Symbol, InpHtfTf, barOpen, false);
   if(hs < 0) return false;
   int prev = hs + 1;
   double b[];
   if(CopyBuffer(g_htfHandle, 0, prev, 1, b) != 1) return false;
   hc = iClose(_Symbol, InpHtfTf, prev); he = b[0];
   return hc > 0 && he > 0;
}

//--- EQH/EQL: >= 2 pivoty w paśmie +/-0.1*szerokości od granicy i od siebie (96 świec)
bool LiquidityBeyond(int side)
{
   int cnt = 0; double tol = 0.10 * rangeWidth, minV = NA, maxV = NA;
   if(side == 1)
      for(int j = 0; j < ArraySize(pivHiV); j++)
         if(pivHiB[j] >= g_bar - EQ_LOOKBACK && MathAbs(pivHiV[j] - rangeHigh) <= tol)
         { cnt++; minV = IsNa(minV) ? pivHiV[j] : MathMin(minV, pivHiV[j]); maxV = IsNa(maxV) ? pivHiV[j] : MathMax(maxV, pivHiV[j]); }
   if(side == -1)
      for(int j = 0; j < ArraySize(pivLoV); j++)
         if(pivLoB[j] >= g_bar - EQ_LOOKBACK && MathAbs(pivLoV[j] - rangeLow) <= tol)
         { cnt++; minV = IsNa(minV) ? pivLoV[j] : MathMin(minV, pivLoV[j]); maxV = IsNa(maxV) ? pivLoV[j] : MathMax(maxV, pivLoV[j]); }
   return cnt >= 2 && !IsNa(minV) && maxV - minV <= tol;
}

void GoIdle(string why)
{
   if(InpLogFsm && !g_warmup && why != "") Print("[Po3] reset: ", why);
   state = ST_IDLE; lastEndBar = g_bar;
}

//--- poziom CISD: open najstarszej świecy w ciągu świec przeciwnych prowadzących do ekstremum sweepu
double CisdLevel(int s, int dir)
{
   int sk = s + (g_bar - sweepExtremeBar);
   bool againstAt = dir == 1 ? ClAt(sk) < OpAt(sk) : ClAt(sk) > OpAt(sk);
   int k = againstAt ? sk : sk + 1;
   int first = -1;
   for(int guard = 0; guard < 20 && k < g_bars; guard++, k++)
   {
      bool against = dir == 1 ? ClAt(k) < OpAt(k) : ClAt(k) > OpAt(k);
      if(!against) break;
      first = k;
   }
   if(first < 0) return dir == 1 ? HiAt(sk) : LoAt(sk);   // brak ciągu: ekstremum świecy sweepu
   return OpAt(first);
}

//--- dywergencja strukturalna: RSI na ekstremum sweepu vs RSI na dołku/szczycie range przed sweepem
bool StructDivergence(int s, int dir)
{
   int count = sweepBar - rangeStartBar;
   if(count < 1) return false;
   int startSh = s + (g_bar - (sweepBar - 1));
   if(startSh + count > g_bars) return false;
   int idx = dir == 1 ? iLowest(_Symbol, _Period, MODE_LOW, count, startSh) : iHighest(_Symbol, _Period, MODE_HIGH, count, startSh);
   if(idx < 0) return false;
   int refBar = g_bar - (idx - s);
   double rsiExt = HGet(h_rsi, g_bar - sweepExtremeBar), rsiRef = HGet(h_rsi, g_bar - refBar);
   if(IsNa(rsiExt) || IsNa(rsiRef)) return false;
   if(dir == 1) return sweepExtreme < LoAt(idx) && rsiExt > rsiRef;
   return sweepExtreme > HiAt(idx) && rsiExt < rsiRef;
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY (FSM jak w Pine)
//====================================================================
void ProcessBar(int s)
{
   g_bar++;
   g_bars = Bars(_Symbol, _Period);
   ev_dist = 0; ev_outcome = 0;
   double o = OpAt(s), h = HiAt(s), l = LoAt(s), c = ClAt(s);
   datetime t = iTime(_Symbol, _Period, s);
   g_lastProcessedTime = t;
   bool hasPrev = s + 1 < g_bars;
   double pc = hasPrev ? ClAt(s + 1) : NA;

   // ATR(14) (nz -> TR), TR(false) dla percentyla, RSI
   double tr = hasPrev ? MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc))) : h - l;
   RmaUpd(g_atr, tr, 14);
   double atr14 = MathMax(g_atr.ready ? g_atr.v : tr, g_tick);
   HPush(h_atr, atr14);
   double trThrPrev = g_trThr;
   if(hasPrev) HPush(h_trf, tr);
   g_trThr = InpSweepDepthPct < 100 ? NearestRank(h_trf, InpStatWindow, InpSweepDepthPct) : NA;
   if(hasPrev)
   {
      double ch = c - pc;
      RmaUpd(g_rsiUp, MathMax(ch, 0), InpDivRsiLen); RmaUpd(g_rsiDn, MathMax(-ch, 0), InpDivRsiLen);
   }
   double rsi = (g_rsiUp.ready && g_rsiDn.ready) ? (g_rsiDn.v == 0 ? 100 : (g_rsiUp.v == 0 ? 0 : 100 - 100 / (1 + g_rsiUp.v / g_rsiDn.v))) : NA;
   HPush(h_rsi, rsi);

   // Donchian(20), percentyl szerokości
   double hi20 = NA, lo20 = NA;
   if(s + RANGE_WIN <= g_bars)
   {
      hi20 = HiAt(iHighest(_Symbol, _Period, MODE_HIGH, RANGE_WIN, s));
      lo20 = LoAt(iLowest(_Symbol, _Period, MODE_LOW, RANGE_WIN, s));
   }
   double chW = IsNa(hi20) ? NA : hi20 - lo20;
   HPush(h_chW, chW);
   double pctRank = PercentRank(h_chW, InpStatWindow);

   // pivoty 3/3 potwierdzone na tej świecy (pivot na s+3)
   double ph = NA, pl = NA;
   int p = s + PIVOT_LR;
   if(p + PIVOT_LR < g_bars)
   {
      bool isH = true, isL = true;
      for(int k = 1; k <= PIVOT_LR; k++)
      {
         if(!(HiAt(p) > HiAt(p - k) && HiAt(p) > HiAt(p + k))) isH = false;
         if(!(LoAt(p) < LoAt(p - k) && LoAt(p) < LoAt(p + k))) isL = false;
      }
      if(isH) { ph = HiAt(p); PushPivot(pivHiV, pivHiB, ph, g_bar - PIVOT_LR); }
      if(isL) { pl = LoAt(p); PushPivot(pivLoV, pivLoB, pl, g_bar - PIVOT_LR); }
   }
   bool warmedUp = g_bar >= InpStatWindow + RANGE_WIN;
   bool inKZ = InKillzone(t);

   double tolBand = IsNa(tolPx) ? 0 : tolPx;
   bool insideRng  = !IsNa(rangeHigh) && c <= rangeHigh && c >= rangeLow;
   bool breachHigh = !IsNa(rangeHigh) && h > rangeHigh + tolBand;
   bool breachLow  = !IsNa(rangeLow)  && l < rangeLow - tolBand;

   //=== T1: IDLE -> ACCUMULATION
   if(state == ST_IDLE)
   {
      if(warmedUp && c > 0 && !IsNa(pctRank) && pctRank <= InpCompressionPct && chW >= InpMinRangeWidthP / 100 * c && g_bar - lastEndBar >= COOLDOWN_BARS)
      {
         int winLast = RANGE_WIN - 1;
         double tHi = hi20, tLo = lo20;
         if(InpTrimTailPct > 0)
         {
            bool keepTrim = true;
            while(keepTrim && winLast > InpMinRangeBars)
            {
               double hi2 = h, lo2 = l;
               for(int i = 0; i <= winLast - 1; i++) { hi2 = MathMax(hi2, HiAt(s + i)); lo2 = MathMin(lo2, LoAt(s + i)); }
               if((tHi - tLo) - (hi2 - lo2) > InpTrimTailPct / 100.0 * (tHi - tLo)) { winLast--; tHi = hi2; tLo = lo2; }
               else keepTrim = false;
            }
         }
         int candStart = g_bar - winLast;
         double candHigh = tHi, candLow = tLo;
         if(InpBoundaryMode == BOUND_PIVOT)
         {
            double bestHi = NA, bestLo = NA;
            for(int j = 0; j < ArraySize(pivHiV); j++) if(pivHiB[j] >= candStart) bestHi = IsNa(bestHi) ? pivHiV[j] : MathMax(bestHi, pivHiV[j]);
            for(int j = 0; j < ArraySize(pivLoV); j++) if(pivLoB[j] >= candStart) bestLo = IsNa(bestLo) ? pivLoV[j] : MathMin(bestLo, pivLoV[j]);
            if(!IsNa(bestHi)) candHigh = bestHi;
            if(!IsNa(bestLo)) candLow = bestLo;
         }
         double candW = candHigh - candLow;
         if(candW >= InpMinRangeWidthP / 100 * c && c <= candHigh && c >= candLow)
         {
            rangeStartBar = candStart; expiryAnchor = candStart;
            rangeHigh = candHigh; rangeLow = candLow; rangeWidth = candW;
            tolPx = candW * InpRangeTol; rangeMid = (candHigh + candLow) / 2;
            rangeAge = winLast;
            atrAnchor = HGet(h_atr, winLast + 1);
            if(IsNa(atrAnchor)) atrAnchor = atr14;
            rearmUsed = false; firstSweepSide = 0;
            cycleId++;
            state = ST_ACCUM;
            if(InpLogFsm && !g_warmup) PrintFormat("[Po3] akumulacja #%d: %s - %s (%d świec)", cycleId, DoubleToString(rangeLow, _Digits), DoubleToString(rangeHigh, _Digits), winLast);
         }
      }
   }
   //=== T2 / T3: ACCUMULATION
   else if(state == ST_ACCUM)
   {
      rangeAge = g_bar - rangeStartBar;
      if(g_bar - expiryAnchor > InpMaxRangeBars) GoIdle("EXPIRED");
      else if(breachHigh && breachLow) GoIdle("NEWS BAR");
      else if(breachHigh || breachLow)
      {
         int side = breachHigh ? 1 : -1;
         if(rangeAge < InpMinRangeBars) GoIdle("przebicie przed dojrzałością");
         else
         {
            bool sameSideBlock = rearmUsed && side == firstSweepSide;
            bool kzOK = !InpUseKillzones || inKZ;
            double capPx = InpSweepDepthPct >= 100 ? NA : (IsNa(trThrPrev) ? g_trThr : trThrPrev);
            double excurs = side == 1 ? h - rangeHigh : rangeLow - l;
            bool dpOK = IsNa(capPx) || excurs <= capPx;
            bool liqOK = !InpRequireLiq || LiquidityBeyond(side);
            if(kzOK && dpOK && liqOK && !sameSideBlock)
            {
               sweepSide = side; sweepBar = g_bar;
               sweepExtreme = side == 1 ? h : l; sweepExtremeBar = g_bar;
               depthCapPx = capPx;
               if(firstSweepSide == 0) firstSweepSide = side;
               state = ST_SWEEP;
               if(InpLogFsm && !g_warmup) PrintFormat("[Po3] SWEEP %s @ %s", side == 1 ? "HIGH" : "LOW", DoubleToString(sweepExtreme, _Digits));
               if(insideRng) state = ST_MANIP;      // powrót na tej samej świecy (knot)
            }
            else if(!insideRng) GoIdle("przebicie odfiltrowane, close poza range");
         }
      }
      else
      {
         if(InpBoundaryMode == BOUND_ABSOLUTE)
         {
            double newHi = MathMin(MathMax(rangeHigh, h), rangeHigh + tolBand);
            double newLo = MathMax(MathMin(rangeLow, l), rangeLow - tolBand);
            if(newHi != rangeHigh || newLo != rangeLow) { rangeHigh = newHi; rangeLow = newLo; rangeWidth = rangeHigh - rangeLow; rangeMid = (rangeHigh + rangeLow) / 2; }
         }
         else
         {
            if(!IsNa(ph) && g_bar - PIVOT_LR >= rangeStartBar && ph > rangeHigh && ph <= rangeHigh + tolBand) { rangeHigh = ph; rangeWidth = rangeHigh - rangeLow; rangeMid = (rangeHigh + rangeLow) / 2; }
            if(!IsNa(pl) && g_bar - PIVOT_LR >= rangeStartBar && pl < rangeLow && pl >= rangeLow - tolBand)   { rangeLow = pl;  rangeWidth = rangeHigh - rangeLow; rangeMid = (rangeHigh + rangeLow) / 2; }
         }
      }
   }
   //=== T4: SWEEP_PENDING
   else if(state == ST_SWEEP)
   {
      double prevExt = sweepExtreme;
      sweepExtreme = sweepSide == 1 ? MathMax(sweepExtreme, h) : MathMin(sweepExtreme, l);
      if(sweepExtreme != prevExt) sweepExtremeBar = g_bar;
      bool oppBreach = sweepSide == 1 ? l < rangeLow - tolBand : h > rangeHigh + tolBand;
      double curExc = sweepSide == 1 ? sweepExtreme - rangeHigh : rangeLow - sweepExtreme;
      bool depthBust = !IsNa(depthCapPx) && curExc > depthCapPx;
      if(oppBreach) GoIdle("2-SIDE");
      else if(depthBust) { brkN++; GoIdle("TOO DEEP"); }
      else if(g_bar - sweepBar > InpSweepReturnBars) { brkN++; GoIdle("BREAKOUT"); }
      else if(insideRng) state = ST_MANIP;
   }
   //=== T7: DISTRIBUTION -> wynik (od następnej świecy po otwarciu)
   else if(state == ST_DIST)
   {
      if(g_bar - distStartBar >= 1)
      {
         bool hitT = distDir == 1 ? h >= tgtPrice : l <= tgtPrice;
         bool hitS = distDir == 1 ? l <= stopPrice : h >= stopPrice;
         bool timedOut = g_bar - distStartBar >= InpDistTimeout;
         if(hitT || hitS || timedOut)
         {
            double rr;
            if(hitT && hitS) { ambigN++; stopN++; rr = -1.0; ev_outcome = 3; }
            else if(hitT) { tgtN++; double ex = distDir == 1 ? MathMax(tgtPrice, o) : MathMin(tgtPrice, o); rr = MathAbs(ex - entryPrice) / riskR; ev_outcome = 1; }
            else if(hitS) { stopN++; double ex = distDir == 1 ? MathMin(stopPrice, o) : MathMax(stopPrice, o); rr = distDir * (ex - entryPrice) / riskR; ev_outcome = -1; }
            else { timeoutN++; rr = distDir * (c - entryPrice) / riskR; ev_outcome = 2; }
            sumR += rr;
            if(InpLogFsm && !g_warmup) PrintFormat("[Po3] wynik cyklu #%d: %s %.2fR", cycleId, ev_outcome == 1 ? "TARGET" : ev_outcome == 2 ? "TIMEOUT" : ev_outcome == 3 ? "AMBIGUOUS" : "STOP", rr);
            GoIdle("");
            pend_active = false;
         }
      }
   }

   //=== T5: MANIPULACJA POTWIERDZONA -> DYSTRYBUCJA (na tej samej świecy)
   if(state == ST_MANIP)
   {
      int dir = sweepSide == -1 ? 1 : -1;
      double hc = NA, he = NA;
      bool htfNa = false;
      if(InpUseHtfBias) htfNa = !HtfValues(t, hc, he);
      bool htfOK = !InpUseHtfBias || (!htfNa && (dir == 1 ? hc > he : hc < he));
      if(htfOK)
      {
         distDir = dir;
         entryPrice = c;
         double fibLeg = dir == 1 ? rangeHigh - sweepExtreme : sweepExtreme - rangeLow;
         tgtPrice = TickRound(dir == 1 ? rangeHigh + (InpFibExt - 1.0) * fibLeg : rangeLow - (InpFibExt - 1.0) * fibLeg);
         double stopRaw = dir == 1 ? sweepExtreme - InpStopBufAtr * atrAnchor : sweepExtreme + InpStopBufAtr * atrAnchor;
         stopPrice = TickOut(stopRaw, dir == -1);
         riskR = MathMax(MathAbs(entryPrice - stopPrice), g_tick);
         bool rewardOK = dir == 1 ? tgtPrice - entryPrice >= g_tick : entryPrice - tgtPrice >= g_tick;
         if(!rewardOK) { failN++; GoIdle("cel za wejściem (M ✗)"); }
         else
         {
            distStartBar = g_bar;
            state = ST_DIST;
            ev_dist = dir;
            // dane do wejścia potwierdzanego
            pend_active = InpEntryMode != ENTRY_REFERENCE;
            pend_dir = dir; pend_until = g_bar + InpConfirmBars;
            pend_cisdLevel = CisdLevel(s, dir);
            pend_divStruct = StructDivergence(s, dir);
         }
      }
      else if(htfNa) GoIdle("brak danych HTF");
      else if(InpAllowRearm && !rearmUsed)
      {
         rearmUsed = true; expiryAnchor = g_bar; state = ST_ACCUM;
         if(InpLogFsm && !g_warmup) Print("[Po3] HTF odrzuca kierunek - re-arm, czekam na sweep drugiej strony");
      }
      else { failN++; GoIdle("FAILED (HTF)"); }
   }
   g_prevClose = c;
}

//====================================================================
//  DYWERGENCJA RSI NA INNYM TF (pivoty jak we wbudowanym "RSI Divergence")
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
   ENUM_TIMEFRAMES tf = InpDivTf;
   datetime closeT = iTime(_Symbol, _Period, 1) + PeriodSeconds(_Period);
   int sh = iBarShift(_Symbol, tf, closeT - 1, false);
   if(sh < 0) return false;
   if(iTime(_Symbol, tf, sh) + PeriodSeconds(tf) > closeT) sh++;
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
         if(q - p < InpDivRangeLo) break;
         bool regular = bull ? (r[p].low < r[q].low && rsi[p] > rsi[q]) : (r[p].high > r[q].high && rsi[p] < rsi[q]);
         if(regular)
         {
            info = StringFormat("%s na %s: pivot %s vs %s (RSI %.1f vs %.1f)", bull ? "bycza" : "niedźwiedzia", EnumToString(tf),
                                TimeToString(r[p].time), TimeToString(r[q].time), rsi[p], rsi[q]);
            return true;
         }
         break;
      }
   }
   return false;
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
   int dir; ulong t = MyPosition(dir); int guard = 0;
   while(t != 0 && guard++ < 5) { PM_ClosePosition(t, reason); t = MyPosition(dir); }
   return t == 0;
}

string SigKey() { return StringFormat("PO3_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

bool OpenReal(int d, string why)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   int pd;
   if(MyPosition(pd) != 0) { if(InpLogSignals) Print("[Po3] pominięty: pozycja już otwarta"); return false; }
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("Po3", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return false; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = NormalizeDouble(stopPrice, _Digits), tp = NormalizeDouble(tgtPrice, _Digits);
   double risk = (entry - sl) * d, reward = (tp - entry) * d;
   if(risk <= 0 || reward <= 0) { if(InpLogSignals) Print("[Po3] pominięty: cena już za stopem lub celem"); return false; }
   if(reward / risk < InpMinRRLeft) { if(InpLogSignals) PrintFormat("[Po3] pominięty: pozostały R:R %.2f < %.2f", reward / risk, InpMinRRLeft); return false; }
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return false;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return false;
   string tag = StringFormat("po3_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s (%s) vol=%.2f entry=%s SL=%s TP=%s R:R=%.2f | sweep %s, cykl #%d", d == 1 ? "LONG" : "SHORT", why, vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), reward / risk,
                               sweepSide == 1 ? "HIGH" : "LOW", cycleId));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
   return res != EXEC_FAILED;
}

void OnBarClosed()
{
   int pd;
   ulong pos = MyPosition(pd);
   // wynik wirtualnego cyklu zamyka realną pozycję (timeout; TP/SL zwykle zrobił już broker)
   if(ev_outcome != 0 && pos != 0)
   {
      if(InpLogSignals) Print("[Po3] koniec cyklu (", ev_outcome == 1 ? "target" : ev_outcome == 2 ? "timeout" : "stop", ") - zamykam pozycję");
      CloseMine(ev_outcome == 2 ? "timeout" : "cycle_end");
   }

   if(ev_dist != 0 && InpLogSignals)
      PrintFormat("[Po3] DIST %s | entry ref %s | stop %s | cel %s | R:R %.2f%s", ev_dist == 1 ? "▲ UP" : "▼ DOWN",
                  DoubleToString(entryPrice, _Digits), DoubleToString(stopPrice, _Digits), DoubleToString(tgtPrice, _Digits),
                  MathAbs(tgtPrice - entryPrice) / riskR, rearmUsed ? " | double sweep" : "");
   if(ev_dist != 0 && InpEntryMode == ENTRY_REFERENCE) { OpenReal(ev_dist, "referencyjne"); return; }

   // wejście potwierdzane: CISD / dywergencja RSI w oknie od świecy D
   if(!pend_active) return;
   if(state != ST_DIST || g_bar > pend_until)
   {
      if(InpLogSignals) Print("[Po3] potwierdzenie nie nastąpiło w oknie - brak wejścia w tym cyklu");
      pend_active = false;
      return;
   }
   double c1 = iClose(_Symbol, _Period, 1);
   bool cisdOk = pend_dir == 1 ? c1 > pend_cisdLevel : c1 < pend_cisdLevel;
   bool divOk;
   string divInfo = "";
   if(InpDivTf == PERIOD_CURRENT || InpDivTf == _Period) { divOk = pend_divStruct; divInfo = "sweep vs ekstremum range"; }
   else divOk = (InpEntryMode == ENTRY_CISD) ? false : DivergenceFound(pend_dir == 1, divInfo);
   bool go = InpEntryMode == ENTRY_CISD ? cisdOk
           : InpEntryMode == ENTRY_RSI_DIV ? divOk
           : InpEntryMode == ENTRY_CISD_OR_DIV ? (cisdOk || divOk)
           : (cisdOk && divOk);
   if(!go) return;
   string why = (cisdOk ? "CISD " + DoubleToString(pend_cisdLevel, _Digits) : "") + (cisdOk && divOk ? " + " : "") + (divOk ? "dywergencja RSI (" + divInfo + ")" : "");
   pend_active = false;
   OpenReal(pend_dir, why);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpMinRangeBars < 8 || InpMaxRangeBars < InpMinRangeBars || InpStatWindow < 50 || InpSweepReturnBars < 1 || InpDistTimeout < 1 ||
      InpFibExt < 1.0 || InpConfirmBars < 0 || InpWarmupBars < 500)
      return INIT_PARAMETERS_INCORRECT;
   if(ParseSess(InpKzLdn, g_kzLdnS, g_kzLdnE) < 0 || ParseSess(InpKzNy, g_kzNyS, g_kzNyE) < 0)
   { Print("Po3: błędny format killzone (HHMM-HHMM)"); return INIT_PARAMETERS_INCORRECT; }
   if(InpUseHtfBias)
   {
      if(PeriodSeconds(InpHtfTf) < PeriodSeconds(_Period)) { Print("Po3: TF biasu HTF musi być >= TF wykresu"); return INIT_PARAMETERS_INCORRECT; }
      g_htfHandle = iMA(_Symbol, InpHtfTf, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(g_htfHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   g_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0) g_tick = _Point;
   HInit(h_atr, RANGE_WIN + 5); HInit(h_trf, InpStatWindow + 1); HInit(h_chW, InpStatWindow + 2);
   HInit(h_rsi, InpMaxRangeBars + InpSweepReturnBars + RANGE_WIN + 50);
   g_atr.n = 0; g_atr.sum = 0; g_atr.v = 0; g_atr.ready = false;
   g_rsiUp = g_atr; g_rsiDn = g_atr;
   ArrayResize(pivHiV, 0); ArrayResize(pivHiB, 0); ArrayResize(pivLoV, 0); ArrayResize(pivLoB, 0);
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie FSM z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - RANGE_WIN - 10);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   int closed = tgtN + stopN + timeoutN;
   string ph = state == ST_IDLE ? "IDLE" : state == ST_ACCUM ? "ACCUMULATION" : state == ST_SWEEP ? "SWEEP?" : "DISTRIBUTION";
   PrintFormat("AMD Po3 EA %s: przeliczono %d świec | faza %s | cykle %d: target %d, stop %d (amb %d), timeout %d | avg R %s | failed/breakout %d/%d | wejście %s",
               EA_VERSION, start, ph, closed, tgtN, stopN, ambigN, timeoutN, closed > 0 ? DoubleToString(sumR / closed, 2) : "-", failN, brkN, EnumToString(InpEntryMode));
   if(_Period != PERIOD_M15) Print("Uwaga: model jest strojony pod M15 (wg dashboardu oryginału)");
   int pd;
   if(MyPosition(pd) != 0 && (state != ST_DIST || pd != distDir)) Print("Uwaga: otwarta pozycja niezgodna z odtworzonym stanem FSM - zarządza nią SL/TP u brokera");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_htfHandle != INVALID_HANDLE) IndicatorRelease(g_htfHandle);
}

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1) OnBarClosed();
      else if(ev_outcome != 0) { int pd; if(MyPosition(pd) != 0) CloseMine("cycle_end_catchup"); }
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
