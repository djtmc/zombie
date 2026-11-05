//+------------------------------------------------------------------+
//| Nebula3_EA.mq5                                                     |
//| Expert Advisor oparty na wskaźniku "Nebula3" (Nebula v3, Pine v5). |
//| Autor wskaźnika projektował go pod NQ na M1.                       |
//|                                                                    |
//| Wejście: Tidal Wave (nowa fala bez nakładania świec) potwierdzona  |
//| sygnałem Ultimate Buy/Sell z ostatnich 4 świec (Strong Buy/Sell).  |
//| Wyjście: suma punktów confluence (7 sygnałów odwrócenia):          |
//| >= 5 częściowa realizacja, >= 7 całość; nowa fala przeciwna.       |
//| Dokładanie: opcjonalnie na "Vodka Shot" / luce wolumenowej.        |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Nebula3 EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_NEB_ENTRY { ENTRY_STRONG = 0, ENTRY_STRONG_AND_BASIC = 1, ENTRY_ULTIMATE = 2 };
enum ENUM_NEB_ADD   { ADD_OFF = 0, ADD_VODKA = 1, ADD_VODKA_AND_PLUS = 2 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Nebula: wejście ==="
input ENUM_NEB_ENTRY      InpEntryMode        = ENTRY_STRONG;   // Sygnał wejścia: Strong / Strong + zwykłe kropki / same Ultimate
input ENUM_APPLIED_VOLUME InpVolumeType       = VOLUME_TICK;    // Wolumen (CFD: tickowy)
input int                 InpWarmupBars       = 3000;           // Ile świec historii przeliczyć przy starcie

input group "=== Tidal Wave / Squeeze ==="
input double   InpAdxThreshold     = 0;       // Próg ADX dla squeeze (oryginał: "ADX Threshold for Tidal Wave")
input int      InpSqzTolerance     = 2;       // Squeeze Tolerance (mniej = czulej)
input double   InpSqzLevel         = 5.0;     // Próg momentum squeeze w punktach ceny (oryginał: 5, skala NQ)

input group "=== Take Profit (confluence) ==="
input int      InpTpPartialCount   = 5;       // Min. punktów confluence: częściowa realizacja
input int      InpTpAllCount       = 7;       // Min. punktów confluence: zamknięcie całości
input double   InpPartialPct       = 50.0;    // Częściowa realizacja (% wolumenu)
input bool     InpTpOnlyInProfit   = false;   // Realizuj tylko, gdy pozycje są na plusie
input bool     InpBEAfterPartial   = true;    // Po częściowej realizacji SL na break-even
input int      InpBEOffsetPoints   = 0;       //   przesunięcie BE w stronę zysku (punkty)
input bool     InpShark2575        = false;   // Shark: reguła RSI 25/75 (oryginał: "Apply 25/75 RSI rule")
input int      InpPvsraLen         = 10;      // PVSRA: okno średniej wolumenu (rekonstrukcja biblioteki)
input double   InpPvsraClimaxMult  = 2.0;     // PVSRA: świeca klimaksowa przy wolumenie >= X x średnia

input group "=== Wyjście i SL ==="
input bool     InpCloseOnOppWave   = true;    // Nowa fala przeciwna zamyka pozycję
input int      InpSlLookback       = 5;       // SL za ekstremum z N świec
input double   InpSlAtrBuffer      = 0.25;    // Bufor SL (x ATR30)
input double   InpSlMinAtr         = 0.5;     // Min. odległość SL (x ATR30)
input double   InpSlMaxAtr         = 3.0;     // Maks. odległość SL (x ATR30)
input double   InpTpRR             = 0;       // Dodatkowy TP na stałym RR (0 = brak)

input group "=== Dokładanie pozycji ==="
input ENUM_NEB_ADD InpAddMode      = ADD_OFF; // Dokładanie: wył. / Vodka Shot / Vodka Shot + luka "+"
input int      InpMaxAdds          = 1;       // Maks. liczba dołożeń do pozycji
input double   InpAddRiskPct       = 0.5;     // Ryzyko dołożenia (% salda, ten sam SL co pozycja)
input bool     InpVodkaSellFix     = false;   // Poprawka literówki Vodka Sell (oryginał sprawdza upwards[2..4])

input group "=== Sesja (czas Nowego Jorku) ==="
input bool     InpSessionFilter    = true;    // Handel tylko w oknie sesji
input string   InpSessStart        = "09:30"; // Początek okna (NY)
input string   InpSessEnd          = "15:55"; // Koniec okna (NY)
input bool     InpFlatAtSessionEnd = true;    // Zamknij wszystko poza oknem sesji
input int      InpServerToNYHours  = 7;       // Czas serwera minus czas Nowego Jorku (godz.). Korekta przy zmianie czasu!

input group "=== Dywergencja RSI (dodatek) ==="
input bool            InpDivOn         = false;          // Wymagaj dywergencji RSI dla wejścia
input ENUM_TIMEFRAMES InpDivTf         = PERIOD_CURRENT; // Interwał dywergencji (domyślnie = wykres)
input int             InpDivRsiLen     = 14;             // Długość RSI dywergencji
input int             InpDivLbL        = 5;              // Pivot: świece z lewej
input int             InpDivLbR        = 5;              // Pivot: świece z prawej (opóźnienie potwierdzenia)
input int             InpDivRangeLo    = 5;              // Min. odstęp między pivotami
input int             InpDivRangeHi    = 60;             // Maks. odstęp między pivotami
input int             InpDivMaxAge     = 15;             // Dywergencja ważna przez N świec interwału dywergencji
input bool            InpDivHidden     = false;          // Uznawaj też dywergencje ukryte (hidden)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260411;   // Magic number tej strategii
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
input bool          InpLogConfluence        = false;    // Loguj każdą świecę z confluence >= progu częściowego

//====================================================================
//  STAŁE Z ORYGINAŁU
//====================================================================
#define V_SQUEEZE   4
#define V_TRAMP     4
#define V_BANDS     2
#define V_LUXREV    3
#define V_EARLYREV  2
#define V_DEADREV   2
#define V_SHARK     2
#define WAVE_UP     1
#define WAVE_DN     2
#define WATCH_LB    35
#define RSI_U_LEN   32
#define RSI_M_LEN   14
#define ATR_LEN     30
#define ATR_MA_LEN  10
#define ATR_MULT    1.5
#define RSI_MA_LEN  24
#define BB_LEN      20
#define BB_MULT     2.0
#define WBB_MULT    2.5
#define KC_MULT     1.5
#define BBW_MIN     0.0015
#define RSI_LOW     25
#define RSI_HIGH    72
#define DER_LEN     12
#define DER_AVG     5
#define VOL_LB      20
#define VOL_AVG_LEN 70
#define WAVE_LB     200
#define HCAP        260
#define NA          EMPTY_VALUE

//====================================================================
//  NARZĘDZIA: historia serii (najnowsza = indeks 0), RMA, RSI
//====================================================================
struct Hist { double v[]; int cap; int n; int head; };
void   HInit(Hist &h, int cap) { h.cap = cap; ArrayResize(h.v, cap); h.n = 0; h.head = -1; }
void   HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k < 0 || k >= h.n) return NA; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
bool   HTrue(Hist &h, int k) { return HGet(h, k) == 1.0; }
double B2D(bool b) { return b ? 1.0 : 0.0; }
bool   IsNa(double x) { return x == NA; }

double HighestH(Hist &h, int off, int len)
{
   if(h.n < off + len) return NA;
   double m = -DBL_MAX;
   for(int k = off; k < off + len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; m = MathMax(m, x); }
   return m;
}
double LowestH(Hist &h, int off, int len)
{
   if(h.n < off + len) return NA;
   double m = DBL_MAX;
   for(int k = off; k < off + len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; m = MathMin(m, x); }
   return m;
}
double SmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0;
   for(int k = 0; k < len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; s += x; }
   return s / len;
}
//--- ta.stdev (populacyjne, jak w Pine)
double StdevH(Hist &h, int len)
{
   double m = SmaH(h, len);
   if(IsNa(m)) return NA;
   double q = 0;
   for(int k = 0; k < len; k++) { double d = HGet(h, k) - m; q += d * d; }
   return MathSqrt(q / len);
}
//--- ta.wma: waga len dla najnowszej wartości
double WmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0, w = 0;
   for(int k = 0; k < len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; double wt = len - k; s += x * wt; w += wt; }
   return s / w;
}
//--- ta.linreg(src, len, 0): wartość prostej regresji na bieżącej świecy
double LinregH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for(int j = 0; j < len; j++)
   {
      double y = HGet(h, len - 1 - j);
      if(IsNa(y)) return NA;
      sx += j; sy += y; sxy += j * y; sxx += (double)j * j;
   }
   double den = len * sxx - sx * sx;
   if(den == 0) return NA;
   double slope = (len * sxy - sx * sy) / den;
   double icpt = (sy - slope * sx) / len;
   return icpt + slope * (len - 1);
}
bool CrossOver(double a, double b, double pa, double pb)  { return !IsNa(a) && !IsNa(b) && !IsNa(pa) && !IsNa(pb) && a > b && pa <= pb; }
bool CrossUnder(double a, double b, double pa, double pb) { return !IsNa(a) && !IsNa(b) && !IsNa(pa) && !IsNa(pb) && a < b && pa >= pb; }
int  Sgn(double x) { return x > 0 ? 1 : (x < 0 ? -1 : 0); }

struct Rma { int n; double sum; double v; bool ready; };
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }
struct Rsi { Rma up; Rma dn; bool ready; double v; };
void RsiUpd(Rsi &r, double ch, int len)
{
   RmaUpd(r.up, MathMax(ch, 0), len); RmaUpd(r.dn, MathMax(-ch, 0), len);
   r.ready = r.up.ready && r.dn.ready;
   if(r.ready) r.v = r.dn.v == 0 ? 100 : (r.up.v == 0 ? 0 : 100 - 100 / (1 + r.up.v / r.dn.v));
}

//====================================================================
//  STAN ALGORYTMU
//====================================================================
Hist h_o, h_h, h_l, h_c, h_v, h_rng, h_vs;
Hist h_rsiM, h_rsiU, h_sqSrc, h_volAvg, h_vola, h_cPlus, h_cMinus, h_dem, h_sup, h_w1, h_w2;
Hist h_trampDn, h_trampUp, h_weGoUp, h_weGoDn, h_upw, h_dnw, h_plotBuy, h_plotSell;
Hist h_brG, h_brR, h_upClose, h_dnClose;

Rsi  g_rsiM, g_rsiU;
Rma  g_atr30, g_adxTr, g_adxP, g_adxM, g_adxR;
double g_diP = NA, g_diM = NA;
int    g_bSC = 0, g_sSC = 0;                                  // licznik 9 (luxRev)
double g_upperVal = NA, g_lowerVal = NA, g_upClose = NA, g_dnClose = NA;
int    g_cRed = 0, g_cGreen = 0; bool g_posPrev = false, g_negPrev = false;
double g_valPrev = NA;
double g_cFix = NA, g_bo = NA, g_bc = NA, g_LLPrev = NA;
int    g_lastBuyW = -1000000, g_lastSellW = -1000000;
int    g_waveState = 0;                                       // 0 = na
//--- poprzednie wartości do przecięć
double p_lowerBB = NA, p_upperBB = NA, p_rsiU = NA, p_lowerRsi = NA, p_upperRsi = NA, p_rsiBasis = NA, p_rsiMa = NA, p_lowerAtr = NA, p_upperAtr = NA;
//--- sygnały TP z poprzedniej świecy
bool   p_dead = false, p_lux = false, p_tramp = false, p_sqz = false, p_early = false, p_shark = false, p_bands = false;

int      g_bar = -1;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
int      g_sessStart = 0, g_sessEnd = 0;
string   EA_VERSION = "1.00";

//--- wynik ostatnio przetworzonej świecy
bool   g_buyBasic, g_sellBasic, g_buySuper, g_sellSuper, g_waveBuy, g_waveSell;
bool   g_plotBuy, g_plotSell, g_plusBuy, g_plusSell, g_vodkaBuy, g_vodkaSell;
int    g_tpCount = 0;
string g_tpWhy = "";
double g_atrNow = 0;

bool IsRsiPivot(const double &rsi[], int n, int p, bool low);   // deklaracja (definicja niżej)

string Join(string cur, bool cond, string name) { if(!cond) return cur; return cur == "" ? name : cur + ", " + name; }

double BarVolume(int s)
{
   if(InpVolumeType == VOLUME_REAL) { long rv = iRealVolume(_Symbol, _Period, s); if(rv > 0) return (double)rv; }
   return (double)iTickVolume(_Symbol, _Period, s);
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY (kolejność jak w Pine)
//====================================================================
void ProcessBar(int s)
{
   g_bar++;
   double o = iOpen(_Symbol, _Period, s), h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   double v = BarVolume(s);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);

   bool hasPrev = h_c.n > 0;
   double po = HGet(h_o, 0), ph = HGet(h_h, 0), pl = HGet(h_l, 0), pc = HGet(h_c, 0);
   HPush(h_o, o); HPush(h_h, h); HPush(h_l, l); HPush(h_c, c); HPush(h_v, v); HPush(h_rng, h - l);
   bool isGreen = c > o, isRed = c < o;
   double chg = hasPrev ? c - pc : NA;

   // ADX (dirmov) - używany tylko przez squeeze (sigabove19)
   if(hasPrev)
   {
      double dmUp = h - ph, dmDn = pl - l;
      double plusDM = (dmUp > dmDn && dmUp > 0) ? dmUp : 0, minusDM = (dmDn > dmUp && dmDn > 0) ? dmDn : 0;
      double trF = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      RmaUpd(g_adxTr, trF, 14); RmaUpd(g_adxP, plusDM, 14); RmaUpd(g_adxM, minusDM, 14);
      if(g_adxTr.ready && g_adxTr.v > 0) { g_diP = 100 * g_adxP.v / g_adxTr.v; g_diM = 100 * g_adxM.v / g_adxTr.v; }  // fixnan
      if(!IsNa(g_diP)) { double sm = g_diP + g_diM; RmaUpd(g_adxR, MathAbs(g_diP - g_diM) / (sm == 0 ? 1 : sm), 14); }
   }
   double adxVal = g_adxR.ready ? 100 * g_adxR.v : NA;
   bool sigAbove = !IsNa(adxVal) && adxVal > InpAdxThreshold;

   // ATR(30) - ta.atr (pierwsza świeca: high-low)
   double trT = hasPrev ? MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc))) : h - l;
   RmaUpd(g_atr30, trT, ATR_LEN);
   double atr = g_atr30.ready ? g_atr30.v : NA;
   g_atrNow = g_atr30.ready ? atr : 0;

   // deadRev: objęcie przy 50-świecowym ekstremum
   bool buyDSR = false, sellDSR = false;
   if(h_c.n >= 54)
   {
      double ll3 = LowestH(h_l, 0, 3), hh3 = HighestH(h_h, 0, 3);
      bool llC = ll3 < LowestH(h_l, 1, 50) || ll3 < LowestH(h_l, 2, 50) || ll3 < LowestH(h_l, 3, 50);
      bool hhC = hh3 > HighestH(h_h, 1, 50) || hh3 > HighestH(h_h, 2, 50) || hh3 > HighestH(h_h, 3, 50);
      buyDSR  = pc < po && isGreen && c > po && llC;
      sellDSR = pc > po && isRed && c < po && hhC;
   }
   bool deadRev = buyDSR || sellDSR;

   // luxRev: licznik 9 względem close[4]
   int prevB = g_bSC, prevS = g_sSC;
   if(h_c.n >= 5 && c < HGet(h_c, 4)) { g_bSC = g_bSC == 9 ? 1 : g_bSC + 1; g_sSC = 0; }
   else                               { g_sSC = g_sSC == 9 ? 1 : g_sSC + 1; g_bSC = 0; }
   bool luxRev = g_bSC == 9 || (prevB == 8 && g_sSC == 1) || g_sSC == 9 || (prevS == 8 && g_bSC == 1);

   // fraktale (pT = 2) i przebicie zamknięciem
   bool bullf = false, bearf = false;
   if(h_h.n >= 5)
   {
      double H0 = HGet(h_h, 0), H1 = HGet(h_h, 1), H2 = HGet(h_h, 2), H3 = HGet(h_h, 3), H4 = HGet(h_h, 4);
      double L0 = HGet(h_l, 0), L1 = HGet(h_l, 1), L2 = HGet(h_l, 2), L3 = HGet(h_l, 3), L4 = HGet(h_l, 4);
      int dh0 = Sgn(H0 - H1) + Sgn(H1 - H2), dh2 = Sgn(H2 - H3) + Sgn(H3 - H4);
      int dl0 = Sgn(L0 - L1) + Sgn(L1 - L2), dl2 = Sgn(L2 - L3) + Sgn(L3 - L4);
      bullf = dh0 == -2 && dh2 == 2 && H2 == HighestH(h_h, 0, 5);
      bearf = dl0 == 2 && dl2 == -2 && L2 == LowestH(h_l, 0, 5);
   }
   double prevUpper = g_upperVal, prevLower = g_lowerVal;
   if(bullf) g_upperVal = HGet(h_h, 2);
   if(CrossOver(c, g_upperVal, pc, prevUpper)) g_upClose = c;
   if(bearf) g_lowerVal = HGet(h_l, 2);
   if(CrossUnder(c, g_lowerVal, pc, prevLower)) g_dnClose = c;
   HPush(h_upClose, g_upClose); HPush(h_dnClose, g_dnClose);

   // RSI(14) "rsiM" i Bollinger 20/2
   if(hasPrev) RsiUpd(g_rsiM, chg, RSI_M_LEN);
   double rsiM = g_rsiM.ready ? g_rsiM.v : NA;
   HPush(h_rsiM, rsiM);
   double basis = SmaH(h_c, BB_LEN), sd20 = StdevH(h_c, BB_LEN);
   double upperBB = NA, lowerBB = NA, bbw = NA;
   if(!IsNa(basis)) { upperBB = basis + BB_MULT * sd20; lowerBB = basis - BB_MULT * sd20; bbw = basis != 0 ? (upperBB - lowerBB) / basis : NA; }

   // trampolina
   bool trampDn = !IsNa(rsiM) && !IsNa(bbw) && isRed && rsiM <= RSI_LOW && c < lowerBB && bbw > BBW_MIN;
   bool trampUp = !IsNa(rsiM) && !IsNa(bbw) && isGreen && rsiM >= RSI_HIGH && c > upperBB && bbw > BBW_MIN;
   HPush(h_trampDn, B2D(trampDn)); HPush(h_trampUp, B2D(trampUp));
   bool anyDn = false, anyUp = false;
   for(int k = 1; k <= 5; k++) { anyDn = anyDn || HTrue(h_trampDn, k); anyUp = anyUp || HTrue(h_trampUp, k); }
   bool weGoUp = isGreen && anyDn && hasPrev && h > ph;
   bool weGoDn = isRed && anyUp && hasPrev && l < pl;
   HPush(h_weGoUp, B2D(weGoUp)); HPush(h_weGoDn, B2D(weGoDn));
   bool upThrust = weGoUp, dnThrust = weGoDn;
   for(int k = 1; k <= 4; k++) { if(HTrue(h_weGoUp, k)) upThrust = false; if(HTrue(h_weGoDn, k)) dnThrust = false; }
   bool tramp = upThrust || dnThrust;

   // squeeze momentum
   double sqDev = IsNa(sd20) ? NA : KC_MULT * sd20;
   double rangema = SmaH(h_rng, BB_LEN);
   bool sqzOn = false;
   if(!IsNa(basis) && !IsNa(rangema))
      sqzOn = (basis - sqDev) > (basis - rangema * KC_MULT) && (basis + sqDev) < (basis + rangema * KC_MULT);
   double hh20 = HighestH(h_h, 0, BB_LEN), ll20 = LowestH(h_l, 0, BB_LEN);
   double sqSrc = (!IsNa(basis) && !IsNa(hh20)) ? c - ((hh20 + ll20) / 2 + basis) / 2 : NA;
   HPush(h_sqSrc, sqSrc);
   double val = LinregH(h_sqSrc, BB_LEN);
   double valPrev = IsNa(g_valPrev) ? 0 : g_valPrev;          // nz(val[1])
   bool posB = false, negB = false;
   if(!IsNa(val))
   {
      if(val < valPrev && val < InpSqzLevel && !sqzOn) g_cRed++;
      if(val > valPrev && val > InpSqzLevel && !sqzOn) g_cGreen++;
      if(val > valPrev && g_cRed > InpSqzTolerance && val < InpSqzLevel && !g_posPrev && sigAbove) { g_cRed = 0; posB = true; }
      if(val < valPrev && g_cGreen > InpSqzTolerance && val > InpSqzLevel && !g_negPrev && sigAbove) { g_cGreen = 0; negB = true; }
   }
   g_posPrev = posB; g_negPrev = negB; g_valPrev = val;
   bool sqz = posB || negB;

   // PVSRA (rekonstrukcja Traders_Reality_Lib.calcPvsra) i early reversal
   double vs = v * (h - l);
   HPush(h_vs, vs);
   double avgV = SmaH(h_v, InpPvsraLen), hiVs = HighestH(h_vs, 0, InpPvsraLen);
   bool climax = !IsNa(avgV) && !IsNa(hiVs) && (v >= avgV * InpPvsraClimaxMult || vs >= hiVs);
   bool pvsGreen = climax && c > o, pvsRed = climax && !(c > o);
   bool nearUp = false, nearDn = false;
   for(int k = 0; k <= 3; k++)
   {
      double uc = HGet(h_upClose, k), dc = HGet(h_dnClose, k), ck = HGet(h_c, k);
      if(!IsNa(uc) && !IsNa(ck) && ck == uc) nearUp = true;
      if(!IsNa(dc) && !IsNa(ck) && ck == dc) nearDn = true;
   }
   bool earlyRev = (pvsGreen && nearUp) || (pvsRed && nearDn);

   // shark: RSI(14) poza pasmami 30/2
   double basis5 = SmaH(h_rsiM, 30), dev5 = StdevH(h_rsiM, 30);
   bool shark = false;
   if(!IsNa(rsiM) && !IsNa(basis5))
   {
      bool below25 = !InpShark2575 || rsiM < 26, above75 = !InpShark2575 || rsiM > 74;
      shark = (rsiM < basis5 - 2.0 * dev5 && below25) || (rsiM > basis5 + 2.0 * dev5 && above75);
   }

   // Ultimate Buy/Sell: RSI(32) z pasmami, cena z BB 20/2, pasma ATR(30) wokół WMA(10)
   double atrMa = WmaH(h_c, ATR_MA_LEN);
   double upperAtr = (!IsNa(atrMa) && !IsNa(atr)) ? atrMa + atr * ATR_MULT : NA;
   double lowerAtr = (!IsNa(atrMa) && !IsNa(atr)) ? atrMa - atr * ATR_MULT : NA;
   if(hasPrev) RsiUpd(g_rsiU, chg, RSI_U_LEN);
   double rsiU = g_rsiU.ready ? g_rsiU.v : NA;
   HPush(h_rsiU, rsiU);
   double rsiBasis = WmaH(h_rsiU, RSI_U_LEN), rsiDev = StdevH(h_rsiU, RSI_U_LEN);
   double upperRsi = IsNa(rsiBasis) || IsNa(rsiDev) ? NA : rsiBasis + 2.0 * rsiDev;
   double lowerRsi = IsNa(rsiBasis) || IsNa(rsiDev) ? NA : rsiBasis - 2.0 * rsiDev;
   double rsiMa = WmaH(h_rsiU, RSI_MA_LEN);

   bool rsiOver25 = CrossOver(rsiU, 25, p_rsiU, 25), rsiUnder75 = CrossUnder(rsiU, 75, p_rsiU, 75);
   bool buyW  = CrossOver(c, lowerBB, pc, p_lowerBB) || CrossOver(rsiU, lowerRsi, p_rsiU, p_lowerRsi) || rsiOver25 || CrossUnder(h, lowerAtr, ph, p_lowerAtr);
   bool sellW = CrossUnder(c, upperBB, pc, p_upperBB) || CrossUnder(rsiU, upperRsi, p_rsiU, p_upperRsi) || rsiUnder75 || CrossOver(l, upperAtr, pl, p_upperAtr);
   if(buyW) g_lastBuyW = g_bar;
   if(sellW) g_lastSellW = g_bar;
   bool anyBuyW = g_bar - g_lastBuyW < WATCH_LB, anySellW = g_bar - g_lastSellW < WATCH_LB;
   bool buySig  = anyBuyW && (CrossOver(rsiU, rsiBasis, p_rsiU, p_rsiBasis) || rsiOver25 || CrossOver(rsiU, rsiMa, p_rsiU, p_rsiMa));
   bool sellSig = anySellW && (CrossUnder(rsiU, rsiBasis, p_rsiU, p_rsiBasis) || rsiUnder75 || CrossUnder(rsiU, rsiMa, p_rsiU, p_rsiMa));
   bool plotBuy = buySig && !buyW;
   bool plotSell = !plotBuy && sellSig && !sellW;
   if(plotBuy || plotSell) { g_lastBuyW = -1000000; g_lastSellW = -1000000; }   // array.clear()
   HPush(h_plotBuy, B2D(plotBuy)); HPush(h_plotSell, B2D(plotSell));

   // Vodka Shot: skok wolumenu, DER (energia kupujących/sprzedających), potrójna WMA
   double volAvgL = SmaH(h_v, VOL_AVG_LEN);
   HPush(h_volAvg, volAvgL);
   double volSd = StdevH(h_volAvg, VOL_AVG_LEN);
   bool volSpike = false;
   if(!IsNa(volAvgL) && !IsNa(volSd) && volAvgL > 0)
   {
      double volDev = (volAvgL + 1.618034 * volSd) / volAvgL * 11 / 100;
      volSpike = (v / volAvgL) * 0.145898 > volDev;
   }
   double vHi = HighestH(h_v, 0, VOL_LB), vLo = LowestH(h_v, 0, VOL_LB);
   double vola = (!IsNa(vHi) && vHi > vLo) ? (v - vLo) / (vHi - vLo) : NA;
   HPush(h_vola, vola);
   double hh2 = HighestH(h_h, 0, 2), ll2 = LowestH(h_l, 0, 2);
   double Rr = IsNa(hh2) ? NA : (hh2 - ll2) / 2;
   double rsr = (!IsNa(chg) && !IsNa(Rr) && Rr > 0) ? MathMax(MathMin(chg / Rr, 1), -1) : NA;
   if(!IsNa(rsr) && !IsNa(vola)) g_cFix = rsr * vola;           // fixnan
   HPush(h_cPlus, IsNa(g_cFix) ? NA : MathMax(g_cFix, 0));
   HPush(h_cMinus, IsNa(g_cFix) ? NA : -MathMin(g_cFix, 0));
   double avgVola = WmaH(h_vola, DER_LEN), wP = WmaH(h_cPlus, DER_LEN), wM = WmaH(h_cMinus, DER_LEN);
   bool avOk = !IsNa(avgVola) && avgVola != 0;
   HPush(h_dem, (avOk && !IsNa(wP)) ? wP / avgVola : 0);       // nz(dem)
   HPush(h_sup, (avOk && !IsNa(wM)) ? wM / avgVola : 0);       // nz(sup)
   double bcPrev = g_bc;
   double boRaw = WmaH(h_sup, DER_AVG), bcRaw = WmaH(h_dem, DER_AVG);
   if(!IsNa(boRaw)) g_bo = 100 * boRaw;
   if(!IsNa(bcRaw)) g_bc = 100 * bcRaw;
   bool rising = !IsNa(g_bc) && !IsNa(bcPrev) && g_bc - bcPrev > 0;
   bool vaderUp = !IsNa(g_bc) && !IsNa(g_bo) && g_bc > g_bo && rising;
   bool vaderDn = !IsNa(g_bc) && !IsNa(g_bo) && g_bc < g_bo && !rising;
   HPush(h_w1, WmaH(h_c, 7)); HPush(h_w2, WmaH(h_w1, 7));
   double LL = WmaH(h_w2, 7);
   bool upUOk = g_rsiU.up.ready && g_rsiU.up.v != 0;            // "and upU" - liczba jako bool
   bool upwards   = !IsNa(LL) && !IsNa(g_LLPrev) && LL > g_LLPrev && vaderUp && upUOk && isGreen && volSpike;
   bool downwards = !IsNa(LL) && !IsNa(g_LLPrev) && LL < g_LLPrev && vaderDn && isRed && volSpike;
   g_LLPrev = LL;
   HPush(h_upw, B2D(upwards)); HPush(h_dnw, B2D(downwards));
   bool pBuyVodka = upwards && !HTrue(h_upw, 1) && !HTrue(h_upw, 2) && !HTrue(h_upw, 3) && !HTrue(h_upw, 4);
   bool pSellVodka = InpVodkaSellFix
                     ? downwards && !HTrue(h_dnw, 1) && !HTrue(h_dnw, 2) && !HTrue(h_dnw, 3) && !HTrue(h_dnw, 4)
                     : downwards && !HTrue(h_dnw, 1) && !HTrue(h_upw, 2) && !HTrue(h_upw, 3) && !HTrue(h_upw, 4);

   // bands: odrzucenie Bollingera 20/2.5
   bool bands = false;
   if(!IsNa(basis))
   {
      double wU = basis + WBB_MULT * sd20, wL = basis - WBB_MULT * sd20;
      bands = (l <= wL && c >= wL && isRed) || (h >= wU && c < wU && isGreen);
   }

   // confluence TP (bieżąca lub poprzednia świeca)
   g_tpCount = ((deadRev || p_dead) ? V_DEADREV : 0) + ((luxRev || p_lux) ? V_LUXREV : 0) + ((tramp || p_tramp) ? V_TRAMP : 0) +
               ((sqz || p_sqz) ? V_SQUEEZE : 0) + ((earlyRev || p_early) ? V_EARLYREV : 0) + ((shark || p_shark) ? V_SHARK : 0) +
               ((bands || p_bands) ? V_BANDS : 0);
   g_tpWhy = "";
   g_tpWhy = Join(g_tpWhy, deadRev || p_dead, "objęcie@50");
   g_tpWhy = Join(g_tpWhy, luxRev || p_lux, "licznik9");
   g_tpWhy = Join(g_tpWhy, tramp || p_tramp, "trampolina");
   g_tpWhy = Join(g_tpWhy, sqz || p_sqz, "squeeze");
   g_tpWhy = Join(g_tpWhy, earlyRev || p_early, "earlyRev");
   g_tpWhy = Join(g_tpWhy, shark || p_shark, "shark");
   g_tpWhy = Join(g_tpWhy, bands || p_bands, "bands");
   p_dead = deadRev; p_lux = luxRev; p_tramp = tramp; p_sqz = sqz; p_early = earlyRev; p_shark = shark; p_bands = bands;

   // Tidal Wave
   int wsPrev = g_waveState;
   bool noOvG = false, noOvR = false, brG = false, brR = false, gapG = false, gapR = false;
   if(isGreen)
   {
      for(int i = 1; i <= WAVE_LB && i < h_c.n; i++)
      {
         if(HTrue(h_brR, i - 1)) break;                        // brightRed[i] (historia bez bieżącej świecy)
         bool gI = HGet(h_c, i) > HGet(h_o, i), rI = HGet(h_c, i) < HGet(h_o, i);
         if(g_waveState == WAVE_UP && rI) break;
         else if(g_waveState == WAVE_DN && o >= HGet(h_c, i) && gI) { noOvG = true; brG = true; g_waveState = WAVE_UP; break; }
      }
      if(hasPrev && o >= pc && pc > po) { g_waveState = WAVE_UP; brG = true; gapG = true; }
   }
   if(isRed)
   {
      for(int i = 1; i <= WAVE_LB && i < h_c.n; i++)
      {
         if(HTrue(h_brG, i - 1)) break;
         bool gI = HGet(h_c, i) > HGet(h_o, i), rI = HGet(h_c, i) < HGet(h_o, i);
         if(g_waveState == WAVE_DN && gI) break;
         else if(g_waveState == WAVE_UP && o <= HGet(h_c, i) && rI) { noOvR = true; brR = true; g_waveState = WAVE_DN; break; }
      }
      if(hasPrev && pc < po && o < pc) { g_waveState = WAVE_DN; brR = true; gapR = true; }
   }
   HPush(h_brG, B2D(brG)); HPush(h_brR, B2D(brR));

   bool big1Buy = false, big1Sell = false;
   for(int k = 0; k <= 3; k++) { if(HTrue(h_plotBuy, k)) big1Buy = true; if(HTrue(h_plotSell, k)) big1Sell = true; }
   g_waveBuy   = noOvG && wsPrev == WAVE_DN;
   g_waveSell  = noOvR && wsPrev == WAVE_UP;
   g_buyBasic  = !big1Buy && g_waveBuy;
   g_sellBasic = !big1Sell && g_waveSell;
   g_buySuper  = big1Buy && g_waveBuy;
   g_sellSuper = big1Sell && g_waveSell;
   g_plusBuy   = gapG && wsPrev == WAVE_UP;
   g_plusSell  = gapR && wsPrev == WAVE_DN;
   g_vodkaBuy  = pBuyVodka && wsPrev == WAVE_UP;
   g_vodkaSell = pSellVodka && wsPrev == WAVE_DN;
   g_plotBuy = plotBuy; g_plotSell = plotSell;

   // zapamiętanie wartości do przecięć na następnej świecy
   p_lowerBB = lowerBB; p_upperBB = upperBB; p_rsiU = rsiU; p_lowerRsi = lowerRsi; p_upperRsi = upperRsi;
   p_rsiBasis = rsiBasis; p_rsiMa = rsiMa; p_lowerAtr = lowerAtr; p_upperAtr = upperAtr;
}

//====================================================================
//  DYWERGENCJA RSI (pivoty jak w sekcji "RSI Divergence" oryginału)
//====================================================================
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

bool IsRsiPivot(const double &rsi[], int n, int p, bool low)
{
   if(p - InpDivLbR < 0 || p + InpDivLbL >= n || rsi[p] == EMPTY_VALUE) return false;
   for(int k = 1; k <= InpDivLbR; k++) { double x = rsi[p - k]; if(x == EMPTY_VALUE || (low ? x <= rsi[p] : x >= rsi[p])) return false; }
   for(int k = 1; k <= InpDivLbL; k++) { double x = rsi[p + k]; if(x == EMPTY_VALUE || (low ? x <= rsi[p] : x >= rsi[p])) return false; }
   return true;
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
//  STAN POZYCJI (zmienne globalne terminala, klucz = ticket)
//====================================================================
string GvRoot() { return "NEB3_" + IntegerToString(InpMagicNumber) + "_"; }
string GvPrefix(ulong t) { return GvRoot() + IntegerToString((long)t) + "_"; }
void   GvSet(ulong t, string f, double v) { GlobalVariableSet(GvPrefix(t) + f, v); }
double GvGet(ulong t, string f) { string k = GvPrefix(t) + f; return GlobalVariableCheck(k) ? GlobalVariableGet(k) : EMPTY_VALUE; }
void   GvClear(ulong t) { GlobalVariablesDeleteAll(GvPrefix(t)); }

void GvCleanup()
{
   string root = GvRoot();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, root) != 0) continue;
      string rest = StringSubstr(name, StringLen(root));
      int us = StringFind(rest, "_");
      if(us <= 0) continue;
      ulong t = (ulong)StringToInteger(StringSubstr(rest, 0, us));
      if(t > 0 && !PositionSelectByTicket(t)) GlobalVariableDel(name);
   }
}

//--- pozycje tej strategii na bieżącym symbolu; dir = kierunek, main = najstarsza pozycja
int MyPositions(ulong &out[], int &dir, ulong &mainTicket)
{
   ulong all[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, all);
   ArrayResize(out, 0);
   dir = 0; mainTicket = 0;
   long oldest = LONG_MAX;
   for(int i = 0; i < n; i++)
   {
      if(!PositionSelectByTicket(all[i]) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = all[i];
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      long tm = PositionGetInteger(POSITION_TIME_MSC);
      if(tm < oldest) { oldest = tm; mainTicket = all[i]; }
   }
   return ArraySize(out);
}

bool CloseMine(string reason)
{
   ulong tk[]; int dir; ulong mainT;
   int n = MyPositions(tk, dir, mainT);
   for(int i = 0; i < n; i++)
      if(PM_ClosePosition(tk[i], reason)) GvClear(tk[i]);
   return MyPositions(tk, dir, mainT) == 0;
}

void MoveToBreakEven(ulong t)
{
   if(!PositionSelectByTicket(t)) return;
   int d = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double openP = PositionGetDouble(POSITION_PRICE_OPEN), cur = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double be = NormalizeDouble(openP + d * InpBEOffsetPoints * _Point, _Digits);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool better = d == 1 ? (cur == 0 || be > cur + _Point) : (cur == 0 || be < cur - _Point);
   bool valid  = d == 1 ? be < tick.bid - minDist : be > tick.ask + minDist;
   if(better && valid) PM_ModifyStops(t, be, tp);
   else if(InpLogSignals && better) PrintFormat("[Nebula3] BE pominięty dla #%I64u: cena po złej stronie poziomu wejścia", t);
}

void PartialTakeProfit(const ulong &tk[], int n)
{
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   for(int i = 0; i < n; i++)
   {
      ulong t = tk[i];
      if(GvGet(t, "part") != EMPTY_VALUE || !PositionSelectByTicket(t)) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double part = vol * InpPartialPct / 100.0;
      bool done = true;
      if(part >= vMin - 1e-9 && vol - part >= vMin - 1e-9) done = PM_ClosePartial(t, part, "tp_partial_confluence");
      else if(InpLogSignals) PrintFormat("[Nebula3] #%I64u: wolumen %.2f za mały na częściową realizację - tylko BE", t, vol);
      if(!done) continue;
      GvSet(t, "part", 1);
      if(InpBEAfterPartial) MoveToBreakEven(t);
   }
}

//====================================================================
//  HANDEL
//====================================================================
string SigKey(string kind) { return StringFormat("NEB3SIG_%d_%s_%s", InpMagicNumber, _Symbol, kind); }
bool SignalAlreadyTraded(string kind, datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey(kind)) && (datetime)GlobalVariableGet(SigKey(kind)) >= bt; }
void MarkSignalTraded(string kind, datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(kind), (double)bt); }

int EntrySignal()
{
   if(InpEntryMode == ENTRY_STRONG) return g_buySuper ? 1 : (g_sellSuper ? -1 : 0);
   if(InpEntryMode == ENTRY_STRONG_AND_BASIC) return (g_buySuper || g_buyBasic) ? 1 : ((g_sellSuper || g_sellBasic) ? -1 : 0);
   return g_plotBuy ? 1 : (g_plotSell ? -1 : 0);
}

string SignalName(int d)
{
   if(InpEntryMode == ENTRY_ULTIMATE) return d == 1 ? "Ultimate Buy" : "Ultimate Sell";
   if(d == 1) return g_buySuper ? "Strong Buy" : "Buy";
   return g_sellSuper ? "Strong Sell" : "Sell";
}

//--- otwarcie pozycji; slFixed > 0 = SL dołożenia (ten sam co pozycja główna)
bool OpenTrade(int d, string kind, double riskPct, double slFixed, ulong mainTicket)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(SignalAlreadyTraded(kind, sigTime)) { EE_LogDecision("Nebula3", "SKIPPED_DUPLICATE", kind + ": sygnał już obsłużony"); return false; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl;
   if(slFixed > 0) sl = slFixed;
   else
   {
      if(g_atrNow <= 0) return false;
      double ext = d == 1 ? LowestH(h_l, 0, InpSlLookback) : HighestH(h_h, 0, InpSlLookback);
      if(IsNa(ext)) return false;
      sl = ext - d * InpSlAtrBuffer * g_atrNow;
      double dist = (entry - sl) * d;
      if(dist < InpSlMinAtr * g_atrNow) sl = entry - d * InpSlMinAtr * g_atrNow;
      else if(dist > InpSlMaxAtr * g_atrNow) sl = entry - d * InpSlMaxAtr * g_atrNow;
   }
   sl = NormalizeDouble(sl, _Digits);
   double risk = (entry - sl) * d;
   if(risk <= 0) { if(InpLogSignals) Print("[Nebula3] pominięty ", kind, ": SL po złej stronie ceny"); return false; }
   double tp = (InpTpRR > 0 && slFixed <= 0) ? NormalizeDouble(entry + d * risk * InpTpRR, _Digits) : 0;
   if(slFixed > 0 && mainTicket > 0 && PositionSelectByTicket(mainTicket)) tp = PositionGetDouble(POSITION_TP);
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, riskPct, risk / _Point);
   if(vol <= 0) return false;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return false;
   string tag = StringFormat("neb3_%s_%s_%d", kind, d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s TP=%s ATR30=%s confluence=%d", d == 1 ? "LONG" : "SHORT", vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), tp == 0 ? "-" : DoubleToString(tp, _Digits),
                               DoubleToString(g_atrNow, _Digits), g_tpCount));
   if(res != EXEC_FAILED) MarkSignalTraded(kind, sigTime);
   return res != EXEC_FAILED;
}

void OnBarClosed()
{
   datetime nowBar = iTime(_Symbol, _Period, 0);
   bool inSess = InSession(nowBar);
   int sig = EntrySignal();

   if(InpLogSignals)
   {
      string s = "";
      s = Join(s, g_buySuper, "Strong Buy"); s = Join(s, g_sellSuper, "Strong Sell");
      s = Join(s, g_buyBasic, "Buy"); s = Join(s, g_sellBasic, "Sell");
      s = Join(s, g_plotBuy, "Ultimate Buy"); s = Join(s, g_plotSell, "Ultimate Sell");
      s = Join(s, g_vodkaBuy, "Vodka Long"); s = Join(s, g_vodkaSell, "Vodka Short");
      if(InpAddMode == ADD_VODKA_AND_PLUS) { s = Join(s, g_plusBuy, "+Long"); s = Join(s, g_plusSell, "+Short"); }
      bool tpLog = InpLogConfluence && g_tpCount >= InpTpPartialCount;
      if(s != "" || tpLog)
         PrintFormat("[Nebula3] %s | fala %s | confluence %d (%s)%s", s == "" ? "-" : s,
                     g_waveState == WAVE_UP ? "UP" : g_waveState == WAVE_DN ? "DOWN" : "-", g_tpCount, g_tpWhy == "" ? "-" : g_tpWhy,
                     inSess ? "" : " | poza sesją");
   }

   // wyjścia
   ulong tk[]; int dir; ulong mainT;
   int n = MyPositions(tk, dir, mainT);
   if(n > 0)
   {
      if(InpCloseOnOppWave && ((dir == 1 && g_waveSell) || (dir == -1 && g_waveBuy)))
      {
         if(InpLogSignals) Print("[Nebula3] nowa fala przeciwna - zamykam pozycje");
         CloseMine("opposite_wave");
      }
      else
      {
         bool tpSide = (dir == 1 && g_waveState == WAVE_UP) || (dir == -1 && g_waveState == WAVE_DN);
         double profit = 0;
         for(int i = 0; i < n; i++) if(PositionSelectByTicket(tk[i])) profit += PositionGetDouble(POSITION_PROFIT);
         bool profitOk = !InpTpOnlyInProfit || profit > 0;
         if(tpSide && profitOk && g_tpCount >= InpTpAllCount)
         {
            if(InpLogSignals) PrintFormat("[Nebula3] confluence %d >= %d (%s) - zamykam całość", g_tpCount, InpTpAllCount, g_tpWhy);
            CloseMine("tp_all_confluence");
         }
         else if(tpSide && profitOk && g_tpCount >= InpTpPartialCount)
         {
            if(InpLogSignals) PrintFormat("[Nebula3] confluence %d >= %d (%s) - częściowa realizacja", g_tpCount, InpTpPartialCount, g_tpWhy);
            PartialTakeProfit(tk, n);
         }
      }
      n = MyPositions(tk, dir, mainT);
   }

   // wejście / odwrócenie
   if(sig != 0)
   {
      if(!inSess) { if(InpLogSignals) Print("[Nebula3] sygnał ", SignalName(sig), " pominięty: poza oknem sesji"); return; }
      if(n > 0 && dir == sig) { if(InpLogSignals) Print("[Nebula3] sygnał ", SignalName(sig), " pominięty: pozycja w tym kierunku już otwarta"); }
      else
      {
         if(InpDivOn)
         {
            string info = "";
            if(!DivergenceFound(sig == 1, info)) { if(InpLogSignals) Print("[Nebula3] pominięty: brak dywergencji RSI w oknie"); return; }
            if(InpLogSignals) Print("[Nebula3] dywergencja: ", info);
         }
         if(n > 0 && !CloseMine("reverse_on_opposite")) { EE_LogDecision("Nebula3", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
         if(InpLogSignals) Print("[Nebula3] wejście: ", SignalName(sig));
         OpenTrade(sig, "entry", InpRiskPercentPerTrade, 0, 0);
         return;
      }
   }

   // dokładanie
   if(InpAddMode == ADD_OFF || n == 0 || !inSess || mainT == 0) return;
   bool addSig = dir == 1 ? (g_vodkaBuy || (InpAddMode == ADD_VODKA_AND_PLUS && g_plusBuy))
                          : (g_vodkaSell || (InpAddMode == ADD_VODKA_AND_PLUS && g_plusSell));
   if(!addSig) return;
   double adds = GvGet(mainT, "adds");
   if(adds == EMPTY_VALUE) adds = 0;
   if(adds >= InpMaxAdds) { if(InpLogSignals) Print("[Nebula3] dołożenie pominięte: osiągnięto limit"); return; }
   if(!PositionSelectByTicket(mainT)) return;
   double mainSL = PositionGetDouble(POSITION_SL);
   if(mainSL <= 0) { if(InpLogSignals) Print("[Nebula3] dołożenie pominięte: pozycja główna bez SL"); return; }
   // licznik na tickecie pozycji głównej - działa też na koncie netting, gdzie dołożenie scala się z pozycją
   if(OpenTrade(dir, "add", InpAddRiskPct, mainSL, mainT)) GvSet(mainT, "adds", adds + 1);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   g_sessStart = ParseHHMM(InpSessStart);
   g_sessEnd = ParseHHMM(InpSessEnd);
   if(g_sessStart < 0 || g_sessEnd < 0) { Print("Nebula3: błędny format godzin sesji (HH:MM)"); return INIT_PARAMETERS_INCORRECT; }
   if(InpTpPartialCount < 1 || InpTpAllCount < InpTpPartialCount || InpPartialPct <= 0 || InpPartialPct >= 100 ||
      InpSlLookback < 1 || InpSlLookback > 200 || InpSlMinAtr <= 0 || InpSlMaxAtr < InpSlMinAtr || InpPvsraLen < 2 || InpWarmupBars < 300)
      return INIT_PARAMETERS_INCORRECT;

   HInit(h_o, HCAP); HInit(h_h, HCAP); HInit(h_l, HCAP); HInit(h_c, HCAP); HInit(h_v, HCAP); HInit(h_rng, BB_LEN + 1);
   HInit(h_vs, InpPvsraLen + 1); HInit(h_rsiM, 31); HInit(h_rsiU, RSI_U_LEN + 1); HInit(h_sqSrc, BB_LEN + 1);
   HInit(h_volAvg, VOL_AVG_LEN + 1); HInit(h_vola, DER_LEN + 1); HInit(h_cPlus, DER_LEN + 1); HInit(h_cMinus, DER_LEN + 1);
   HInit(h_dem, DER_AVG + 1); HInit(h_sup, DER_AVG + 1); HInit(h_w1, 8); HInit(h_w2, 8);
   HInit(h_trampDn, 7); HInit(h_trampUp, 7); HInit(h_weGoUp, 6); HInit(h_weGoDn, 6); HInit(h_upw, 6); HInit(h_dnw, 6);
   HInit(h_plotBuy, 5); HInit(h_plotSell, 5); HInit(h_brG, WAVE_LB + 2); HInit(h_brR, WAVE_LB + 2);
   HInit(h_upClose, 5); HInit(h_dnClose, 5);
   ZeroMemory(g_rsiM); ZeroMemory(g_rsiU); ZeroMemory(g_atr30); ZeroMemory(g_adxTr); ZeroMemory(g_adxP); ZeroMemory(g_adxM); ZeroMemory(g_adxR);
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanów (fala, liczniki squeeze, okna watch) z historii - bez handlu
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Nebula3 EA %s: przeliczono %d świec | fala %s | wejście %s | dokładanie %s | sesja NY %s-%s %s (serwer-NY %+d h) | dywergencja %s",
               EA_VERSION, start, g_waveState == WAVE_UP ? "UP" : g_waveState == WAVE_DN ? "DOWN" : "brak",
               EnumToString(InpEntryMode), EnumToString(InpAddMode), InpSessStart, InpSessEnd, InpSessionFilter ? "wł." : "wył.",
               InpServerToNYHours, InpDivOn ? "wł. (" + EnumToString(InpDivTf == PERIOD_CURRENT ? _Period : InpDivTf) + ")" : "wył.");
   if(_Period != PERIOD_M1) Print("Uwaga: Nebula3 projektowano pod M1 (NQ). Na innym interwale progi mogą wymagać dopasowania.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpSessionFilter && InpFlatAtSessionEnd && !InSession(TimeCurrent()))
   {
      ulong tk[]; int dir; ulong mainT;
      if(MyPositions(tk, dir, mainT) > 0)
      {
         if(InpLogSignals) Print("[Nebula3] koniec okna sesji - zamykam pozycje");
         CloseMine("session_end");
      }
   }
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1) OnBarClosed();
   }
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); GvCleanup(); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
