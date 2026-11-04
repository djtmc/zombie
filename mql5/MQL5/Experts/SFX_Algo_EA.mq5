//+------------------------------------------------------------------+
//| SFX_Algo_EA.mq5                                                    |
//| Expert Advisor oparty na logice wskaźnika "Flux Charts - SFX Algo"|
//| (Pine Script v6) - przeniesiony na MQL5.                          |
//|                                                                    |
//| SEKCJA A (ten plik): trail SFX, ważenie 6 "ekspertów", silnik      |
//| sygnału z oceną gwiazdkową, poziomy TP1-3/SL (4 metody),           |
//| zarządzanie częściowymi wyjściami.                                 |
//| SEKCJA B (Include/Core): wykonanie zleceń, ryzyko, reconciliation.|
//|                                                                    |
//| Stan liczony przyrostowo, świeca po świecy (jak Pine), wyłącznie   |
//| na zamkniętych świecach. Przy starcie odtwarzany z historii.       |
//+------------------------------------------------------------------+
#property copyright "SFX Algo EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_TIME_WEIGHT { TW_RECENT = 0, TW_MIXED = 1, TW_LONGTERM = 2 };
enum ENUM_TRADE_STYLE { STYLE_SCALPER = 0, STYLE_DAY = 1, STYLE_SWING = 2 };
enum ENUM_TPSL_METHOD { METHOD_DYNAMIC = 0, METHOD_KEY_LEVELS = 1, METHOD_VOL_BANDS = 2, METHOD_SIGNAL_RATING = 3 };
enum ENUM_TP_UNIT     { UNIT_PCT = 0, UNIT_ATR = 1 };
enum ENUM_RISK_TOL    { RISK_LOW = 0, RISK_MEDIUM = 1, RISK_HIGH = 2 };
enum ENUM_TP_PLAN     { TP_SPLIT_THIRDS = 0, TP_ALL_AT_TP3 = 1, TP_ALL_AT_TP1 = 2, TP_NONE_ORIGINAL = 3 };
enum ENUM_LOT_MODE    { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Algorytm SFX ==="
input int              InpSensitivity     = 75;              // Czułość (1-100) - wyższa = więcej sygnałów
input int              InpSignalStrength  = 25;              // Siła sygnału (0-100) - min. % ważonych głosów
input ENUM_TIME_WEIGHT InpTimeWeighting   = TW_RECENT;       // Okno uczenia wag ekspertów
input int              InpMinStars        = 4;               // Minimalna ocena gwiazdkowa (1-5)
input ENUM_TRADE_STYLE InpStyle           = STYLE_SWING;     // Profil: długości wewnętrzne algorytmu
input bool             InpAiOptimizer     = false;           // AI Sensitivity Optimizer (10 kandydatów czułości)
input int              InpWarmupBars      = 3000;            // Ile świec historii przeliczyć przy starcie

input group "=== TP / SL ==="
input ENUM_TPSL_METHOD InpMethod          = METHOD_KEY_LEVELS; // Metoda wyznaczania TP i SL
input double           InpTp1Val          = 0.5;             // Dynamic: TP1
input ENUM_TP_UNIT     InpTp1Unit         = UNIT_PCT;        // Dynamic: jednostka TP1 (% zysku / ATR)
input double           InpTp2Val          = 1.5;             // Dynamic: TP2
input ENUM_TP_UNIT     InpTp2Unit         = UNIT_PCT;        // Dynamic: jednostka TP2
input double           InpTp3Val          = 3.0;             // Dynamic: TP3
input ENUM_TP_UNIT     InpTp3Unit         = UNIT_PCT;        // Dynamic: jednostka TP3
input ENUM_RISK_TOL    InpRiskTolerance   = RISK_MEDIUM;     // Dynamic: tolerancja ryzyka (szerokość SL)
input ENUM_TP_PLAN     InpTpPlan          = TP_SPLIT_THIRDS; // 1/3 na TP1, 1/3 na TP2, reszta na TP3
input bool             InpBreakEvenAfterTp1 = false;         // SL na wejście po TP1 (oryginał tego nie robi)
input bool             InpReverseOnOpposite = true;          // Przeciwny sygnał zamyka pozycję i odwraca
input bool             InpUseTradeWindow  = false;           // Nowe wejścia tylko w oknie czasowym
input string           InpTradeWindow     = "0600-1600";     // Okno handlu (czas Nowego Jorku)
input int              InpServerToNYHours = 7;               // Czas serwera minus czas Nowego Jorku (godz.)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int              InpMagicNumber          = 260403;    // Magic number tej strategii
input double           InpMaxSpreadPoints      = 300;       // Maksymalny spread (punkty)
input int              InpSlippagePoints       = 50;        // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE    InpLotMode              = LOT_RISK_PERCENT; // % kapitału / stały lot
input double           InpRiskPercentPerTrade  = 1.0;       // % kapitału ryzykowany na transakcję
input double           InpFixedLot             = 0.30;      // Stały lot (gdy tryb = stały)
input int              InpMaxSimultaneousPos   = 1;         // Maks. jednoczesnych pozycji
input double           InpMaxDailyDrawdownPct  = 3.0;       // Kill-switch dzienny (% equity)
input double           InpMaxTotalDrawdownPct  = 10.0;      // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool             InpLogSignals           = true;      // Loguj sygnały i decyzje
input bool             InpLogFlips             = false;     // Loguj zwroty trailu odrzucone przez filtr

//====================================================================
//  STAŁE I PARAMETRY POCHODNE
//====================================================================
#define AI_CANDIDATES 10
#define AI_WARMUP     200
#define PIVOT_MEMORY  60
#define N_EXPERTS     6
#define ETA           0.4

int    P_atrLen, P_rsiLen, P_fastLen, P_slowLen, P_midLen, P_stLen, P_wmWindow, P_vbLen, P_vbSmooth, P_pivLen;
double P_riskMult;
int    g_winStart = 0, g_winEnd = 0;
string EA_VERSION = "1.00";

//====================================================================
//  PRZYROSTOWE WSKAŹNIKI (semantyka Pine)
//====================================================================
//--- RMA jak ta.rma: start od SMA pierwszych len wartości
struct Rma { int n; double sum; double v; bool ready; };
void RmaUpdate(Rma &r, double x, int len)
{
   if(!r.ready)
   {
      r.sum += x; r.n++;
      if(r.n >= len) { r.v = r.sum / len; r.ready = true; }
      return;
   }
   r.v = (r.v * (len - 1) + x) / len;
}
//--- EMA jak ta.ema: start od pierwszej (prawidłowej) wartości
struct Ema { bool ready; double v; };
void EmaUpdate(Ema &e, double x, int len)
{
   double a = 2.0 / (len + 1);
   if(!e.ready) { e.v = x; e.ready = true; return; }
   e.v = a * x + (1 - a) * e.v;
}
//--- f_trail z Pine
struct Trail { double up; double dn; int dir; bool hasUp; };
void TrailInit(Trail &t) { t.up = 0; t.dn = 0; t.dir = 1; t.hasUp = false; }
void TrailUpdate(Trail &t, double factor, bool atrOk, double atr, double hl2, double close, bool hasPrevClose, double prevClose)
{
   if(!atrOk) { t.hasUp = false; return; }   // ATR = na -> pasma na, kierunek bez zmian
   double upBase = hl2 - factor * atr, dnBase = hl2 + factor * atr;
   double prevUp = t.hasUp ? t.up : upBase;
   double prevDn = t.hasUp ? t.dn : dnBase;
   t.up = (hasPrevClose && prevClose > prevUp) ? MathMax(upBase, prevUp) : upBase;
   t.dn = (hasPrevClose && prevClose < prevDn) ? MathMin(dnBase, prevDn) : dnBase;
   t.hasUp = true;
   if(t.dir == -1 && close > prevDn) t.dir = 1;
   else if(t.dir == 1 && close < prevUp) t.dir = -1;
}
//--- ta.supertrend
struct Supertrend { double prevUp; double prevLo; double prevSt; bool prevAtrOk; int dir; };

//====================================================================
//  STAN ALGORYTMU
//====================================================================
Rma        g_atr, g_stAtr, g_rsiU, g_rsiD;
Ema        g_emaF, g_emaS, g_macdSig, g_chBasis, g_vbE1, g_vbBasis, g_vbDev;
Trail      g_trail, g_sub, g_ai[AI_CANDIDATES];
Supertrend g_st;
double     g_aiScore[AI_CANDIDATES];
double     g_aiBestSens;
int        g_chDir = 1;
double     g_prevChBasis = 0; bool g_hasPrevChBasis = false;
double     g_prevAtr = 0; bool g_prevAtrOk = false;
int        g_prevPred[N_EXPERTS];
double     g_logBuf[][N_EXPERTS];   // bufor kołowy log-czynników [pozycja][ekspert]
int        g_logPos = 0, g_logCount = 0;
int        g_prevTrailDir = 0; bool g_hasPrevTrailDir = false;
int        g_pendDir = 0, g_pendBar = 0;
double     g_res[], g_sup[];        // poziomy kluczowe (najnowszy pierwszy)
int        g_bar = -1;
datetime   g_lastProcessedTime = 0;
bool       g_warmup = true;

//--- wynik ostatnio przetworzonej świecy
bool     g_buy = false, g_sell = false;
int      g_rating = 0;
double   g_atrNow = 0, g_subUp = 0, g_subDn = 0; bool g_subOk = false;
double   g_vbUpIn, g_vbUpMid, g_vbUpOut, g_vbLoIn, g_vbLoMid, g_vbLoOut; bool g_vbOk = false;
datetime g_sigTime = 0;

//====================================================================
//  DOSTĘP DO HISTORII (shift od przetwarzanej świecy)
//====================================================================
int g_s = 1;
double O(int k)  { return iOpen(_Symbol, _Period, g_s + k); }
double H(int k)  { return iHigh(_Symbol, _Period, g_s + k); }
double L(int k)  { return iLow(_Symbol, _Period, g_s + k); }
double Cl(int k) { return iClose(_Symbol, _Period, g_s + k); }
datetime T(int k){ return iTime(_Symbol, _Period, g_s + k); }
bool HasBar(int k) { return g_s + k < Bars(_Symbol, _Period); }

double SensFactor(double sens) { return 0.5 + (100.0 - sens) / 100.0 * 5.5; }
int Rating(double frac) { return (int)MathMax(1, MathMin(5, 1 + (int)MathFloor(frac * 5.0))); }

//====================================================================
//  PARAMETRY POCHODNE (jak w Pine)
//====================================================================
void DeriveParams()
{
   double sm = InpStyle == STYLE_SCALPER ? 0.7 : InpStyle == STYLE_SWING ? 1.5 : 1.0;
   int baseWindow = InpTimeWeighting == TW_RECENT ? 30 : InpTimeWeighting == TW_MIXED ? 75 : 150;
   P_atrLen   = (int)MathMax(2, MathRound(10 * sm));
   P_rsiLen   = (int)MathMax(2, MathRound(14 * sm));
   P_fastLen  = (int)MathMax(2, MathRound(12 * sm));
   P_slowLen  = (int)MathMax(P_fastLen + 1, MathRound(26 * sm));
   P_midLen   = (int)MathMax(5, MathRound(50 * sm));
   P_stLen    = (int)MathMax(2, MathRound(10 * sm));
   P_wmWindow = (int)MathMax(5, MathRound(baseWindow * sm));
   P_vbLen    = (int)MathMax(20, MathRound(100 * sm));
   P_vbSmooth = (int)MathMax(2, MathRound(P_vbLen * 0.3));
   P_pivLen   = (int)MathMax(3, MathRound(5 * sm));
   P_riskMult = InpRiskTolerance == RISK_LOW ? 0.75 : InpRiskTolerance == RISK_HIGH ? 1.5 : 1.0;
}

void ResetState()
{
   ZeroMemory(g_atr); ZeroMemory(g_stAtr); ZeroMemory(g_rsiU); ZeroMemory(g_rsiD);
   ZeroMemory(g_emaF); ZeroMemory(g_emaS); ZeroMemory(g_macdSig); ZeroMemory(g_chBasis);
   ZeroMemory(g_vbE1); ZeroMemory(g_vbBasis); ZeroMemory(g_vbDev);
   TrailInit(g_trail); TrailInit(g_sub);
   for(int i = 0; i < AI_CANDIDATES; i++) { TrailInit(g_ai[i]); g_aiScore[i] = 0; }
   g_aiBestSens = InpSensitivity;
   g_st.prevUp = 0; g_st.prevLo = 0; g_st.prevSt = 0; g_st.prevAtrOk = false; g_st.dir = 1;
   g_chDir = 1; g_hasPrevChBasis = false; g_prevAtrOk = false;
   for(int k = 0; k < N_EXPERTS; k++) g_prevPred[k] = 0;
   ArrayResize(g_logBuf, P_wmWindow);
   ArrayInitialize(g_logBuf, 0);
   g_logPos = 0; g_logCount = 0;
   g_hasPrevTrailDir = false; g_pendDir = 0; g_pendBar = 0;
   ArrayResize(g_res, 0); ArrayResize(g_sup, 0);
   g_bar = -1;
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY
//====================================================================
void PushLevel(double &arr[], double v)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   for(int i = n; i > 0; i--) arr[i] = arr[i - 1];   // unshift: najnowszy na początku
   arr[0] = v;
   if(ArraySize(arr) > PIVOT_MEMORY) ArrayResize(arr, PIVOT_MEMORY);
}

bool IsPivotHigh(int center, int len)
{
   double c = iHigh(_Symbol, _Period, center);
   for(int k = 1; k <= len; k++)
   {
      double a = iHigh(_Symbol, _Period, center - k), b = iHigh(_Symbol, _Period, center + k);
      if(a == 0 || b == 0 || a >= c || b >= c) return false;
   }
   return true;
}
bool IsPivotLow(int center, int len)
{
   double c = iLow(_Symbol, _Period, center);
   for(int k = 1; k <= len; k++)
   {
      double a = iLow(_Symbol, _Period, center - k), b = iLow(_Symbol, _Period, center + k);
      if(a == 0 || b == 0 || a <= c || b <= c) return false;
   }
   return true;
}

void ProcessBar(int shift)
{
   g_s = shift;
   g_bar++;
   g_buy = g_sell = false;

   double h = H(0), l = L(0), c = Cl(0);
   bool hasPrev = HasBar(1);
   double pc = hasPrev ? Cl(1) : c;
   double hl2 = (h + l) / 2.0;

   // ATR (RMA) - wspólny dla trailu, kanału i optymalizatora
   double tr = h - l;
   if(hasPrev) tr = MathMax(tr, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
   RmaUpdate(g_atr, tr, P_atrLen);
   bool atrOk = g_atr.ready;
   double atr = g_atr.v;

   // AI Sensitivity Optimizer (przed trailem, jak w Pine)
   if(InpAiOptimizer && atrOk && g_bar > 0)
   {
      double barRet = pc != 0 ? c / pc - 1.0 : 0.0;
      double flipCost = c != 0 ? 0.25 * atr / c : 0.0;
      double decay = 1.0 - 1.0 / MathMax(50.0, P_wmWindow * 4.0);
      int best = -1; double bestVal = 0;
      for(int i = 0; i < AI_CANDIDATES; i++)
      {
         int pDir = g_ai[i].dir;
         TrailUpdate(g_ai[i], SensFactor(10.0 * (i + 1)), true, atr, hl2, c, hasPrev, pc);
         g_aiScore[i] = g_aiScore[i] * decay + pDir * barRet - (g_ai[i].dir != pDir ? flipCost : 0.0);
         if(best < 0 || g_aiScore[i] > bestVal) { bestVal = g_aiScore[i]; best = i; }
      }
      if(g_bar >= AI_WARMUP && best >= 0) g_aiBestSens = 10.0 * (best + 1);
   }
   double effSens = (InpAiOptimizer && g_bar >= AI_WARMUP) ? g_aiBestSens : InpSensitivity;
   double factor = SensFactor(effSens);

   // trail główny i pod-trend (SL metody Dynamic)
   TrailUpdate(g_trail, factor, atrOk, atr, hl2, c, hasPrev, pc);
   TrailUpdate(g_sub, factor * 0.5, atrOk, atr, hl2, c, hasPrev, pc);
   int trailDir = g_trail.dir;
   g_subOk = g_sub.hasUp; g_subUp = g_sub.up; g_subDn = g_sub.dn;

   // RSI
   bool rsiOk = false; double rsi = 0;
   if(hasPrev && g_bar > 0)
   {
      double ch = c - pc;
      RmaUpdate(g_rsiU, MathMax(ch, 0), P_rsiLen);
      RmaUpdate(g_rsiD, MathMax(-ch, 0), P_rsiLen);
      if(g_rsiU.ready && g_rsiD.ready)
      {
         rsiOk = true;
         rsi = g_rsiD.v == 0 ? 100 : (g_rsiU.v == 0 ? 0 : 100 - 100 / (1 + g_rsiU.v / g_rsiD.v));
      }
   }
   // MACD (EMA fast/slow + sygnał EMA 9) - te same EMA służą ekspertowi p5
   EmaUpdate(g_emaF, c, P_fastLen);
   EmaUpdate(g_emaS, c, P_slowLen);
   double macd = g_emaF.v - g_emaS.v;
   EmaUpdate(g_macdSig, macd, 9);

   // Supertrend(3, stLen)
   RmaUpdate(g_stAtr, tr, P_stLen);
   if(g_stAtr.ready)
   {
      double upB = hl2 + 3.0 * g_stAtr.v, loB = hl2 - 3.0 * g_stAtr.v;
      loB = (loB > g_st.prevLo || (hasPrev && pc < g_st.prevLo)) ? loB : g_st.prevLo;
      upB = (upB < g_st.prevUp || (hasPrev && pc > g_st.prevUp)) ? upB : g_st.prevUp;
      int dir;
      if(!g_st.prevAtrOk) dir = 1;
      else if(g_st.prevSt == g_st.prevUp) dir = c > upB ? -1 : 1;
      else dir = c < loB ? 1 : -1;
      g_st.prevSt = dir == -1 ? loB : upB;
      g_st.prevUp = upB; g_st.prevLo = loB; g_st.dir = dir;
   }
   g_st.prevAtrOk = g_stAtr.ready;

   // kanał EMA ± ATR
   EmaUpdate(g_chBasis, c, P_midLen);
   if(atrOk)
   {
      if(c > g_chBasis.v + atr) g_chDir = 1;
      else if(c < g_chBasis.v - atr) g_chDir = -1;
   }

   // predykcje 6 ekspertów (na = porównanie fałszywe, jak w Pine)
   int p[N_EXPERTS];
   p[0] = (rsiOk && rsi >= 50) ? 1 : -1;
   p[1] = macd >= g_macdSig.v ? 1 : -1;
   p[2] = (g_stAtr.ready && g_st.dir < 0) ? 1 : -1;
   p[3] = g_chDir;
   p[4] = g_emaF.v >= g_emaS.v ? 1 : -1;
   p[5] = g_chBasis.v >= (g_hasPrevChBasis ? g_prevChBasis : g_chBasis.v) ? 1 : -1;

   // multiplicative weights: kara za błędną predykcję z POPRZEDNIEJ świecy
   double move = c - pc;
   int outcome = move > 0 ? 1 : move < 0 ? -1 : 0;
   double prevAtr = g_prevAtrOk ? g_prevAtr : 0;
   double lossMag = prevAtr > 0 ? MathMin(1.0, 0.5 + 0.5 * MathAbs(move) / prevAtr) : 0.5;
   for(int k = 0; k < N_EXPERTS; k++)
   {
      bool wrong = g_prevPred[k] != 0 && outcome != 0 && g_prevPred[k] != outcome;
      g_logBuf[g_logPos][k] = wrong ? MathLog(1.0 - ETA * lossMag) : 0.0;
   }
   g_logPos = (g_logPos + 1) % P_wmWindow;
   if(g_logCount < P_wmWindow) g_logCount++;

   double lw[N_EXPERTS], lwMax = -DBL_MAX;
   for(int k = 0; k < N_EXPERTS; k++)
   {
      double s = 0;
      if(g_logCount >= P_wmWindow) for(int j = 0; j < P_wmWindow; j++) s += g_logBuf[j][k]; // math.sum = na, dopóki okno niepełne
      lw[k] = s;
      lwMax = MathMax(lwMax, s);
   }
   double wSum = 0, bullW = 0;
   for(int k = 0; k < N_EXPERTS; k++)
   {
      double w = MathExp(lw[k] - lwMax);
      wSum += w;
      if(p[k] == 1) bullW += w;
   }
   double bullFrac = wSum > 0 ? bullW / wSum : 0.5;

   // silnik sygnału: zwrot trailu otwiera okno 3 świec
   bool flip = g_hasPrevTrailDir && trailDir != g_prevTrailDir;
   if(flip) { g_pendDir = trailDir; g_pendBar = g_bar; }
   double dirFrac = trailDir == 1 ? bullFrac : 1.0 - bullFrac;
   int rating = Rating(dirFrac);
   bool inWindow = g_pendDir != 0 && trailDir == g_pendDir && g_bar - g_pendBar <= 3;
   bool passes = inWindow && dirFrac * 100.0 >= InpSignalStrength && rating >= InpMinStars;
   g_buy = passes && g_pendDir == 1;
   g_sell = passes && g_pendDir == -1;
   if(flip && !passes && InpLogFlips && !g_warmup)
      PrintFormat("[SFX] zwrot trailu %s - ocena %d★ (%.0f%%) poniżej filtra", trailDir == 1 ? "w górę" : "w dół", rating, dirFrac * 100);
   if(passes || (g_pendDir != 0 && !inWindow)) g_pendDir = 0;
   g_rating = rating;

   // poziomy kluczowe (pivoty potwierdzone pivLen świec po fakcie)
   if(HasBar(2 * P_pivLen))
   {
      if(IsPivotHigh(g_s + P_pivLen, P_pivLen)) PushLevel(g_res, H(P_pivLen));
      if(IsPivotLow(g_s + P_pivLen, P_pivLen))  PushLevel(g_sup, L(P_pivLen));
   }

   // Volatility Bands: EMA(EMA(hlc3)) i EMA(stdev(hlc3))
   double hlc3 = (h + l + c) / 3.0;
   EmaUpdate(g_vbE1, hlc3, P_vbLen);
   EmaUpdate(g_vbBasis, g_vbE1.v, P_vbSmooth);
   if(HasBar(P_vbLen - 1))
   {
      double sum = 0, sq = 0;
      for(int k = 0; k < P_vbLen; k++) sum += (H(k) + L(k) + Cl(k)) / 3.0;
      double mean = sum / P_vbLen;
      for(int k = 0; k < P_vbLen; k++) { double d = (H(k) + L(k) + Cl(k)) / 3.0 - mean; sq += d * d; }
      EmaUpdate(g_vbDev, MathSqrt(sq / P_vbLen), P_vbSmooth);
   }
   g_vbOk = g_vbDev.ready;
   if(g_vbOk)
   {
      double b = g_vbBasis.v, d = g_vbDev.v;
      g_vbUpIn = b + d * 1.5; g_vbUpMid = b + d * 2.25; g_vbUpOut = b + d * 3.0;
      g_vbLoIn = b - d * 1.5; g_vbLoMid = b - d * 2.25; g_vbLoOut = b - d * 3.0;
   }

   // zapamiętaj wartości "poprzedniej świecy"
   for(int k = 0; k < N_EXPERTS; k++) g_prevPred[k] = p[k];
   g_prevChBasis = g_chBasis.v; g_hasPrevChBasis = true;
   g_prevAtr = atr; g_prevAtrOk = atrOk;
   g_prevTrailDir = trailDir; g_hasPrevTrailDir = true;
   g_atrNow = atrOk ? atr : c * 0.01;
   g_sigTime = T(0);
   g_lastProcessedTime = T(0);
}

//====================================================================
//  POZIOMY TP/SL (f_keyLevels, f_dynDist, f_sanitize z Pine)
//====================================================================
void SortAsc(double &a[]) { ArraySort(a); }

void KeyLevels(int dir, double entry, double unit, double &t1, double &t2, double &t3, double &sl)
{
   double dists[];
   int nPool = dir == 1 ? ArraySize(g_res) : ArraySize(g_sup);
   ArrayResize(dists, 0);
   for(int i = 0; i < nPool; i++)
   {
      double v = dir == 1 ? g_res[i] : g_sup[i];
      double dv = (v - entry) * dir;
      if(dv > unit * 0.25) { int n = ArraySize(dists); ArrayResize(dists, n + 1); dists[n] = dv; }
   }
   SortAsc(dists);
   double d1 = EMPTY_VALUE, d2 = EMPTY_VALUE, d3 = EMPTY_VALUE, lastD = 0;
   int found = 0;
   for(int i = 0; i < ArraySize(dists) && found < 3; i++)
   {
      if(dists[i] - lastD >= unit * 0.5)
      {
         found++;
         if(found == 1) d1 = dists[i]; else if(found == 2) d2 = dists[i]; else d3 = dists[i];
         lastD = dists[i];
      }
   }
   double stepD = unit * 1.5;
   if(d1 == EMPTY_VALUE) d1 = stepD;
   if(d2 == EMPTY_VALUE) d2 = d1 + stepD;
   if(d3 == EMPTY_VALUE) d3 = d2 + stepD;
   double sd = EMPTY_VALUE;
   int nSl = dir == 1 ? ArraySize(g_sup) : ArraySize(g_res);
   for(int i = 0; i < nSl; i++)
   {
      double v = dir == 1 ? g_sup[i] : g_res[i];
      double dv = (entry - v) * dir;
      if(dv > unit * 0.25) sd = sd == EMPTY_VALUE ? dv : MathMin(sd, dv);
   }
   sd = sd == EMPTY_VALUE ? unit * 2.0 : sd + unit * 0.1;
   t1 = entry + d1 * dir; t2 = entry + d2 * dir; t3 = entry + d3 * dir; sl = entry - sd * dir;
}

double DynDist(double val, ENUM_TP_UNIT unit, double entry, double atr) { return unit == UNIT_PCT ? entry * val / 100.0 : val * atr; }

void ComputeLevels(int d, double entry, double &t1, double &t2, double &t3, double &sl)
{
   double unit = g_atrNow;
   if(InpMethod == METHOD_DYNAMIC)
   {
      t1 = entry + d * DynDist(InpTp1Val, InpTp1Unit, entry, unit);
      t2 = entry + d * DynDist(InpTp2Val, InpTp2Unit, entry, unit);
      t3 = entry + d * DynDist(InpTp3Val, InpTp3Unit, entry, unit);
      double subRef = d == 1 ? g_subUp : g_subDn;
      double subDist = !g_subOk ? unit * 1.5 : MathMax((entry - subRef) * d, unit * 0.25);
      sl = entry - d * subDist * P_riskMult;
   }
   else if(InpMethod == METHOD_KEY_LEVELS) KeyLevels(d, entry, unit, t1, t2, t3, sl);
   else if(InpMethod == METHOD_VOL_BANDS && g_vbOk)
   {
      t1 = d == 1 ? g_vbUpIn : g_vbLoIn;
      t2 = d == 1 ? g_vbUpMid : g_vbLoMid;
      t3 = d == 1 ? g_vbUpOut : g_vbLoOut;
      sl = d == 1 ? g_vbLoOut : g_vbUpOut;
   }
   else // Signal Rating (także awaryjnie, gdy pasma jeszcze niegotowe)
   {
      double rUnit = unit * (0.6 + 0.3 * g_rating);
      t1 = entry + d * rUnit; t2 = entry + d * rUnit * 2.0; t3 = entry + d * rUnit * 3.0;
      sl = entry - d * unit * (2.5 - 0.25 * g_rating);
   }
   // f_sanitize: kolejność TP1 < TP2 < TP3 i minimalne odstępy
   double u = MathMax(unit, _Point);
   double d1 = MathMax((t1 - entry) * d, u * 0.25);
   double d2 = MathMax((t2 - entry) * d, d1 + u * 0.25);
   double d3 = MathMax((t3 - entry) * d, d2 + u * 0.25);
   double ds = MathMax((entry - sl) * d, u * 0.25);
   t1 = NormalizeDouble(entry + d * d1, _Digits);
   t2 = NormalizeDouble(entry + d * d2, _Digits);
   t3 = NormalizeDouble(entry + d * d3, _Digits);
   sl = NormalizeDouble(entry - d * ds, _Digits);
}

//====================================================================
//  STAN POZYCJI (zmienne globalne terminala - przeżywa restart)
//====================================================================
string GvPrefix(ulong t) { return "SFX_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString((long)t) + "_"; }
void   GvSet(ulong t, string f, double v) { GlobalVariableSet(GvPrefix(t) + f, v); }
double GvGet(ulong t, string f) { string k = GvPrefix(t) + f; return GlobalVariableCheck(k) ? GlobalVariableGet(k) : EMPTY_VALUE; }
void   GvClear(ulong t) { GlobalVariablesDeleteAll(GvPrefix(t)); }

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

void SplitVolume(double total, double &v1, double &v2)
{
   v1 = v2 = 0;
   if(InpTpPlan != TP_SPLIT_THIRDS) return;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double third = MathFloor(total / 3.0 / step + 1e-9) * step;
   if(third >= mn && total - 2 * third >= mn - 1e-9) { v1 = third; v2 = third; }
   else EE_LogDecision("SFX", "SPLIT_SKIPPED", StringFormat("wolumen %.2f za mały na 3 części - całość na TP3", total));
}

//--- TP1/TP2 (częściowe wyjścia) i break-even - na każdym ticku
void ManagePartials()
{
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double tp1 = GvGet(t, "tp1");
   if(tp1 == EMPTY_VALUE) return;
   bool isBuy = dir == 1;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double px = isBuy ? tick.bid : tick.ask;
   double tp2 = GvGet(t, "tp2"), v1 = GvGet(t, "v1"), v2 = GvGet(t, "v2");
   bool h1 = GvGet(t, "h1") == 1, h2 = GvGet(t, "h2") == 1;
   bool r2 = isBuy ? px >= tp2 : px <= tp2;
   bool r1 = r2 || (isBuy ? px >= tp1 : px <= tp1);

   if(r1 && !h1)
   {
      bool ok = v1 <= 0 || PM_ClosePartial(t, v1, "TP1");
      if(ok)
      {
         GvSet(t, "h1", 1);
         if(InpLogSignals) PrintFormat("[SFX] TP1 osiągnięty @%s", DoubleToString(px, _Digits));
         if(InpBreakEvenAfterTp1 && PositionSelectByTicket(t))
         {
            double entry = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
            if(isBuy ? sl < entry : (sl > entry || sl == 0)) PM_ModifyStops(t, entry, PositionGetDouble(POSITION_TP));
         }
      }
   }
   if(r2 && !h2 && PositionSelectByTicket(t))
   {
      bool ok = v2 <= 0 || PM_ClosePartial(t, v2, "TP2");
      if(ok) { GvSet(t, "h2", 1); if(InpLogSignals) PrintFormat("[SFX] TP2 osiągnięty @%s", DoubleToString(px, _Digits)); }
   }
}

//--- idempotencja sygnału (poza testerem)
string SigKey() { return StringFormat("SFX_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

bool ParseSession(string sess, int &startMin, int &endMin)
{
   if(StringLen(sess) != 9 || StringGetCharacter(sess, 4) != '-') return false;
   startMin = (int)StringToInteger(StringSubstr(sess, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 2, 2));
   endMin   = (int)StringToInteger(StringSubstr(sess, 5, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 7, 2));
   return true;
}
bool InTradeWindow(datetime serverTime)
{
   MqlDateTime d; TimeToStruct(serverTime - InpServerToNYHours * 3600, d);
   int m = d.hour * 60 + d.min;
   if(g_winEnd > g_winStart) return m >= g_winStart && m < g_winEnd;
   return m >= g_winStart || m < g_winEnd;
}

//====================================================================
//  OBSŁUGA SYGNAŁU
//====================================================================
void HandleSignal(int d)
{
   string side = d == 1 ? "BUY" : "SELL";
   if(InpLogSignals) PrintFormat("[SFX] sygnał %s %d★ na świecy %s", side, g_rating, TimeToString(g_sigTime));
   if(SignalAlreadyTraded(g_sigTime)) { EE_LogDecision("SFX", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }

   int posDir;
   ulong pos = MyPosition(posDir);
   if(pos != 0 && posDir == d) { if(InpLogSignals) Print("[SFX] pominięty: trwa pozycja w tym samym kierunku"); return; }
   if(pos != 0 && posDir != d)
   {
      if(!InpReverseOnOpposite) { if(InpLogSignals) Print("[SFX] pominięty: otwarta przeciwna pozycja"); return; }
      PM_CloseAllPositions(InpMagicNumber, "reverse_on_opposite_sfx");
      if(MyPosition(posDir) != 0) { EE_LogDecision("SFX", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   }
   if(InpUseTradeWindow && !InTradeWindow(g_sigTime)) { if(InpLogSignals) Print("[SFX] pominięty: poza oknem handlu"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(!RM_CanOpenNewPosition(InpMagicNumber, InpMaxSimultaneousPos)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double t1, t2, t3, sl;
   ComputeLevels(d, entry, t1, t2, t3, sl);
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;

   double brokerTP = InpTpPlan == TP_ALL_AT_TP1 ? t1 : InpTpPlan == TP_NONE_ORIGINAL ? 0 : t3;
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   double v1, v2;
   SplitVolume(vol, v1, v2);

   string tag = StringFormat("sfx_%s_%d", d == 1 ? "L" : "S", (int)g_sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, brokerTP, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %d★ vol=%.2f entry=%s SL=%s TP1=%s TP2=%s TP3=%s metoda=%s", side, g_rating, vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(t1, _Digits),
                               DoubleToString(t2, _Digits), DoubleToString(t3, _Digits), EnumToString(InpMethod)));
   if(res == EXEC_FAILED) return;
   MarkSignalTraded(g_sigTime);
   if(res == EXEC_CONFIRMED)
   {
      ulong t = PM_FindLatestTicketByMagic(InpMagicNumber, _Symbol);
      if(t > 0 && InpTpPlan != TP_NONE_ORIGINAL)
      {
         GvClear(t);
         GvSet(t, "tp1", t1); GvSet(t, "tp2", t2);
         GvSet(t, "v1", v1);  GvSet(t, "v2", v2);
         GvSet(t, "h1", 0);   GvSet(t, "h2", 0);
      }
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpSensitivity < 1 || InpSensitivity > 100 || InpMinStars < 1 || InpMinStars > 5) return INIT_PARAMETERS_INCORRECT;
   if(!ParseSession(InpTradeWindow, g_winStart, g_winEnd)) { Print("Błędny format okna handlu - użyj HHMM-HHMM"); return INIT_PARAMETERS_INCORRECT; }
   DeriveParams();
   ResetState();
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu algorytmu z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("SFX Algo EA %s: przeliczono %d świec | ATR %d, RSI %d, MACD %d/%d, okno wag %d, pivoty %d | czułość %.0f%s | metoda %s",
               EA_VERSION, start, P_atrLen, P_rsiLen, P_fastLen, P_slowLen, P_wmWindow, P_pivLen,
               InpAiOptimizer ? g_aiBestSens : (double)InpSensitivity, InpAiOptimizer ? " (AI)" : "", EnumToString(InpMethod));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpTpPlan == TP_SPLIT_THIRDS || InpBreakEvenAfterTp1) ManagePartials();
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;

   // przetwórz wszystkie świece zamknięte od ostatniego razu; handluj tylko najświeższą
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1)
      {
         if(g_buy) HandleSignal(1);
         else if(g_sell) HandleSignal(-1);
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
