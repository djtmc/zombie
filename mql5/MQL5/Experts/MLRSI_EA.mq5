//+------------------------------------------------------------------+
//| MLRSI_EA.mq5                                                       |
//| Expert Advisor oparty na wskaźniku "Machine Learning RSI | AI      |
//| Classification & Ranking" (Zeiierman, Pine v6) - na MQL5.          |
//|                                                                    |
//| 8 cech RSI -> bank pamięci z etykietami (ruch 4 świece naprzód) -> |
//| wagi Fishera -> kNN (k analogów, odległość log(1+|d|)) -> bias.    |
//| ML Supertrend (pasmo zależne od zgodności analogów) + bramki       |
//| trendu / zmienności / konsolidacji -> stance -> Rank i Confidence. |
//| Dodatkowo: opcjonalny filtr dywergencji RSI na wybranym TF.        |
//|                                                                    |
//| Handel: wejście po zamkniętej świecy, SL na linii ML Supertrend    |
//| z trailingiem, odwracanie na przeciwnym sygnale.                   |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "ML RSI EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_SRC      { SRC_CLOSE = 0, SRC_HL2 = 1, SRC_HLC3 = 2, SRC_OHLC4 = 3 };
enum ENUM_LOT_MODE { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== ML Brain ==="
input ENUM_SRC InpPriceSrc     = SRC_CLOSE;  // Źródło ceny dla cech RSI
input int      InpRsiBase      = 14;         // Bazowa długość RSI
input int      InpMemoryDepth  = 500;        // Głębokość pamięci (świece)
input int      InpK            = 8;          // Liczba analogów (k)
input int      InpWarmupBars   = 2000;       // Ile świec historii przeliczyć przy starcie (bank + okna)

input group "=== Sygnały ==="
input int      InpGateRank     = 60;         // Min. Rank
input int      InpGateConf     = 50;         // Min. Confidence
input bool     InpTrendGate    = true;       // Bramka trendu (zgodność z ML Supertrend)
input bool     InpVolBand      = true;       // Bramka zmienności (percentyl ATR)
input int      InpVolBandLo    = 20;         //   min. percentyl ATR
input bool     InpChopFilter   = true;       // Filtr konsolidacji
input double   InpAtrFactor    = 0.5;        // Czułość uczenia (x ATR)

input group "=== Auto Weight Optimizer ==="
input bool     InpAutoWeights  = true;       // Wagi cech z dyskryminantu Fishera
input double   InpAutoSpeed    = 1.0;        // Szybkość adaptacji (EMA)
input double   InpWVal         = 1.0;        // Waga ręczna: wartość RSI (gdy Auto wył.)
input double   InpWSlp         = 1.0;        // Waga ręczna: nachylenie RSI
input double   InpWAcc         = 1.0;        // Waga ręczna: przyspieszenie RSI
input double   InpWMid         = 1.0;        // Waga ręczna: odległość od 50
input double   InpWPct         = 1.0;        // Waga ręczna: percentyl RSI
input double   InpWChn         = 1.0;        // Waga ręczna: zmienność RSI
input double   InpWSpr         = 1.0;        // Waga ręczna: RSI szybki/wolny
input double   InpWReg         = 1.0;        // Waga ręczna: reżim RSI

input group "=== ML Supertrend ==="
input ENUM_SRC InpStSrc        = SRC_HL2;    // Źródło pasm
input double   InpStMult       = 1.5;        // Mnożnik ATR
input double   InpStMlResp     = 1.0;        // Adaptacja ML pasma (0-1)

input group "=== Dywergencja RSI (dodatek) ==="
input bool            InpDivOn         = false;          // Wymagaj dywergencji RSI dla sygnału
input ENUM_TIMEFRAMES InpDivTf         = PERIOD_CURRENT; // Interwał dywergencji (domyślnie = wykres)
input int             InpDivRsiLen     = 14;             // Długość RSI dywergencji
input int             InpDivLbL        = 5;              // Pivot: świece z lewej
input int             InpDivLbR        = 5;              // Pivot: świece z prawej (opóźnienie potwierdzenia)
input int             InpDivRangeLo    = 5;              // Min. odstęp między pivotami
input int             InpDivRangeHi    = 60;             // Maks. odstęp między pivotami
input int             InpDivMaxAge     = 10;             // Dywergencja ważna przez N świec interwału dywergencji
input bool            InpDivHidden     = false;          // Uznawaj też dywergencje ukryte (hidden)

input group "=== Handel ==="
input double   InpTpRR         = 0;          // TP na stałym RR (0 = brak)
input bool     InpTrailOnSt    = true;       // Trailing SL za linią ML Supertrend

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260410;   // Magic number tej strategii
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
input bool          InpLogFlips             = false;    // Loguj zmiany stance odrzucone przez Rank/Confidence

//====================================================================
//  STAŁE Z ORYGINAŁU
//====================================================================
#define WIN_LEN     100
#define SPACING     4
#define HORIZON     4
#define STEP_LEN    3
#define TREND_LEN   50
#define CHOP_CUT    0.5
#define VOL_HI      85
#define AUTO_FLOOR  0.5
#define AUTO_MIN    60
#define ST_ATR_LEN  10
#define SMOOTH_LEN  10
#define COOL_BARS   5
#define NF          8

//====================================================================
//  NARZĘDZIA: historia serii (najnowsza = indeks 0), RMA, EMA
//====================================================================
struct Hist { double v[]; int cap; int n; int head; };
void HInit(Hist &h, int cap) { h.cap = cap; ArrayResize(h.v, cap); h.n = 0; h.head = -1; }
void HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k >= h.n) return EMPTY_VALUE; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
bool HFull(Hist &h, int len) { return h.n >= len; }
double HLowest(Hist &h, int len)  { double m = DBL_MAX;  for(int k = 0; k < len; k++) m = MathMin(m, HGet(h, k)); return m; }
double HHighest(Hist &h, int len) { double m = -DBL_MAX; for(int k = 0; k < len; k++) m = MathMax(m, HGet(h, k)); return m; }
//--- scale01 z Pine: (v - min)/(max - min) w oknie len z bieżącą wartością
double Scale01(Hist &h, int len) { double lo = HLowest(h, len), hi = HHighest(h, len); return hi == lo ? 0.5 : (HGet(h, 0) - lo) / (hi - lo); }
//--- ta.percentrank: % z poprzednich len wartości <= bieżąca
double PercentRank(Hist &h, int len)
{
   double cur = HGet(h, 0); int c = 0;
   for(int k = 1; k <= len; k++) if(HGet(h, k) <= cur) c++;
   return 100.0 * c / len;
}

struct Rma { int n; double sum; double v; bool ready; };
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }
struct Ema { bool ready; double v; };
void EmaUpd(Ema &e, double x, int len) { double a = 2.0 / (len + 1); if(!e.ready) { e.v = x; e.ready = true; } else e.v = a * x + (1 - a) * e.v; }
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
int     g_rsiFastLen, g_rsiSlowLen;
Rsi     g_rsi, g_rsiF, g_rsiS;
Rma     g_atr14, g_stAtr;
Ema     g_emaReg, g_emaRsi5, g_emaTrend, g_emaQuick, g_conv;
Hist    h_src, h_rsi, h_atr, h_slope, h_accel, h_churnSrc, h_churn, h_spread, h_regime;
double  g_feat[5][NF];      // cechy: [0] = bieżąca świeca, [4] = 4 świece temu
int     g_featN = 0;
double  g_bank[][NF + 1];   // bank: bufor kołowy, logiczny indeks 0 = najnowszy wiersz
int     g_bankN = 0, g_bankHead = -1;
double  g_wAuto[NF];
double  g_prevEmaRsi5 = 0; bool g_hasPrevEmaRsi5 = false;
double  g_stLong = 0, g_stShort = 0; bool g_stInit = false; int g_stDir = 1;
int     g_stance = 0, g_stanceAge = 0;
bool    g_chg[4];           // historia stanceChanged: [0] bieżąca
int     g_bar = -1, g_lastEntryBar = -1000000;
datetime g_lastProcessedTime = 0;
bool    g_warmup = true;
double  g_prevSrc = 0; bool g_hasPrevSrc = false;
double  g_prevClose = 0; bool g_hasPrevClose = false;

//--- wynik ostatnio przetworzonej świecy
bool   g_trigLong = false, g_trigShort = false;
double g_rank = 0, g_conf = 0, g_atrNow = 0;
string EA_VERSION = "1.00";

bool IsRsiPivot(const double &rsi[], int n, int p, bool low);   // deklaracja (definicja niżej)

double SrcOf(ENUM_SRC s, int sh)
{
   double o = iOpen(_Symbol, _Period, sh), h = iHigh(_Symbol, _Period, sh), l = iLow(_Symbol, _Period, sh), c = iClose(_Symbol, _Period, sh);
   return s == SRC_HL2 ? (h + l) / 2 : s == SRC_HLC3 ? (h + l + c) / 3 : s == SRC_OHLC4 ? (o + h + l + c) / 4 : c;
}

int BankPhys(int idx) { int i = g_bankHead - idx; if(i < 0) i += InpMemoryDepth; return i; }
void BankAdd(const double &row[])
{
   g_bankHead = (g_bankHead + 1) % InpMemoryDepth;
   for(int j = 0; j <= NF; j++) g_bank[g_bankHead][j] = row[j];
   if(g_bankN < InpMemoryDepth) g_bankN++;
}

//====================================================================
//  AUTO WEIGHTS (dyskryminant Fishera, jak autoFeatureWeights)
//====================================================================
void AutoWeights(double &imp[])
{
   ArrayResize(imp, NF); ArrayInitialize(imp, 1.0);
   if(g_bankN < AUTO_MIN) return;
   double sB[NF], sBe[NF], qB[NF], qBe[NF];
   ArrayInitialize(sB, 0); ArrayInitialize(sBe, 0); ArrayInitialize(qB, 0); ArrayInitialize(qBe, 0);
   int cB = 0, cBe = 0;
   for(int i = 0; i < g_bankN; i++)
   {
      int p = BankPhys(i);
      double o = g_bank[p][NF];
      if(o == 0) continue;
      bool isB = o > 0;
      for(int j = 0; j < NF; j++)
      {
         double v = g_bank[p][j];
         if(isB) { sB[j] += v; qB[j] += v * v; } else { sBe[j] += v; qBe[j] += v * v; }
      }
      if(isB) cB++; else cBe++;
   }
   if(cB <= 2 || cBe <= 2) return;
   double fish[NF], maxF = 0;
   for(int j = 0; j < NF; j++)
   {
      double mB = sB[j] / cB, mBe = sBe[j] / cBe;
      double vB = MathMax(0.0, qB[j] / cB - mB * mB), vBe = MathMax(0.0, qBe[j] / cBe - mBe * mBe);
      fish[j] = MathPow(mB - mBe, 2) / (vB + vBe + 1e-6);
      maxF = MathMax(maxF, fish[j]);
   }
   for(int j = 0; j < NF; j++) imp[j] = MathMax(AUTO_FLOOR, (maxF > 0 ? fish[j] / maxF : 1.0) * 10.0);
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY (kolejność jak w Pine)
//====================================================================
void ProcessBar(int s)
{
   g_bar++;
   g_trigLong = g_trigShort = false;
   double src = SrcOf(InpPriceSrc, s);
   double h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);

   // RSI (bazowy, szybki, wolny) i ATR
   if(g_hasPrevSrc)
   {
      double ch = src - g_prevSrc;
      RsiUpd(g_rsi, ch, InpRsiBase); RsiUpd(g_rsiF, ch, g_rsiFastLen); RsiUpd(g_rsiS, ch, g_rsiSlowLen);
   }
   g_prevSrc = src; g_hasPrevSrc = true;
   double tr = h - l;
   if(g_hasPrevClose) tr = MathMax(tr, MathMax(MathAbs(h - g_prevClose), MathAbs(l - g_prevClose)));
   RmaUpd(g_atr14, tr, 14);
   RmaUpd(g_stAtr, tr, ST_ATR_LEN);
   double prevClose = g_prevClose; bool hadPrevClose = g_hasPrevClose;
   g_prevClose = c; g_hasPrevClose = true;
   HPush(h_src, src);
   HPush(h_atr, g_atr14.ready ? g_atr14.v : EMPTY_VALUE);
   if(!g_rsi.ready || !g_rsiF.ready || !g_rsiS.ready || !g_atr14.ready) return;

   double rsi = g_rsi.v;
   HPush(h_rsi, rsi);
   EmaUpd(g_emaReg, rsi, 20);
   EmaUpd(g_emaRsi5, rsi, 5);
   EmaUpd(g_emaTrend, src, TREND_LEN);
   EmaUpd(g_emaQuick, src, 5);
   double atr = g_atr14.v;
   g_atrNow = atr;

   // surowe serie cech (do normalizacji scale01 w oknie 100)
   bool rsiHist = HFull(h_rsi, 2 * STEP_LEN + 1);
   double r3 = HGet(h_rsi, STEP_LEN), r6 = HGet(h_rsi, 2 * STEP_LEN);
   if(rsiHist) { HPush(h_slope, rsi - r3); HPush(h_accel, rsi - r3 - (r3 - r6)); }
   if(HFull(h_rsi, 14))
   {
      double m = 0; for(int k = 0; k < 14; k++) m += HGet(h_rsi, k); m /= 14;
      double q = 0; for(int k = 0; k < 14; k++) { double d = HGet(h_rsi, k) - m; q += d * d; }
      HPush(h_churn, MathSqrt(q / 14));
   }
   HPush(h_spread, g_rsiF.v - g_rsiS.v);
   HPush(h_regime, g_emaReg.v - 50.0);

   bool featOk = HFull(h_slope, WIN_LEN) && HFull(h_accel, WIN_LEN) && HFull(h_churn, WIN_LEN) && HFull(h_spread, WIN_LEN) &&
                 HFull(h_regime, WIN_LEN) && HFull(h_rsi, WIN_LEN + 1);
   double cur[NF];
   if(featOk)
   {
      cur[0] = rsi / 100.0;
      cur[1] = Scale01(h_slope, WIN_LEN);
      cur[2] = Scale01(h_accel, WIN_LEN);
      cur[3] = MathAbs(rsi - 50.0) / 50.0;
      cur[4] = PercentRank(h_rsi, WIN_LEN) / 100.0;
      cur[5] = Scale01(h_churn, WIN_LEN);
      cur[6] = Scale01(h_spread, WIN_LEN);
      cur[7] = Scale01(h_regime, WIN_LEN);
      for(int a = 4; a > 0; a--) for(int j = 0; j < NF; j++) g_feat[a][j] = g_feat[a - 1][j];
      for(int j = 0; j < NF; j++) g_feat[0][j] = cur[j];
      if(g_featN < 5) g_featN++;
   }
   else g_featN = 0;

   // bank: cechy sprzed HORIZON świec + etykieta ruchu naprzód
   if(featOk && g_featN > HORIZON && HFull(h_src, HORIZON + 1) && HGet(h_atr, HORIZON) != EMPTY_VALUE)
   {
      double moveFwd = src - HGet(h_src, HORIZON);
      double band = InpAtrFactor * HGet(h_atr, HORIZON);
      double outc = moveFwd > 2 * band ? 3 : moveFwd > band ? 2 : moveFwd > 0 ? 1 : moveFwd < -2 * band ? -3 : moveFwd < -band ? -2 : moveFwd < 0 ? -1 : 0;
      double row[NF + 1];
      for(int j = 0; j < NF; j++) row[j] = g_feat[HORIZON][j];
      row[NF] = outc;
      BankAdd(row);
   }

   // wagi cech
   double w[NF];
   if(InpAutoWeights)
   {
      double raw[];
      AutoWeights(raw);
      for(int j = 0; j < NF; j++) g_wAuto[j] += InpAutoSpeed * (raw[j] - g_wAuto[j]);
      for(int j = 0; j < NF; j++) w[j] = g_wAuto[j];
   }
   else { w[0] = InpWVal; w[1] = InpWSlp; w[2] = InpWAcc; w[3] = InpWMid; w[4] = InpWPct; w[5] = InpWChn; w[6] = InpWSpr; w[7] = InpWReg; }
   double wSum = 0; for(int j = 0; j < NF; j++) wSum += w[j];

   // kNN: co SPACING-ty wiersz, top-k najmniejszych odległości (jak method consider)
   double nGap[]; int nCls[]; int kc = 0;
   ArrayResize(nGap, InpK); ArrayResize(nCls, InpK);
   if(featOk && g_bankN > 1)
   {
      int scanEnd = (int)MathMin(InpMemoryDepth - 1, g_bankN - 1);
      for(int idx = 0; idx <= scanEnd; idx++)
      {
         if(idx % SPACING != 0) continue;
         int p = BankPhys(idx);
         double g = 0;
         for(int j = 0; j < NF; j++) g += w[j] * MathLog(1.0 + MathAbs(cur[j] - g_bank[p][j]));
         int cls = (int)g_bank[p][NF];
         if(kc < InpK) { nGap[kc] = g; nCls[kc] = cls; kc++; }
         else
         {
            int worst = 0; double wg = nGap[0];
            for(int i = 1; i < kc; i++) if(nGap[i] > wg) { wg = nGap[i]; worst = i; }
            if(g < wg) { nGap[worst] = g; nCls[worst] = cls; }
         }
      }
   }

   // głosowanie ważone odległością
   double vTot = 0, vBull = 0, vBear = 0, vScore = 0, gapSum = 0;
   for(int i = 0; i < kc; i++)
   {
      double ww = 1.0 / (1.0 + nGap[i]);
      vTot += ww; vScore += nCls[i] * ww;
      if(nCls[i] > 0) vBull += ww; else if(nCls[i] < 0) vBear += ww;
      gapSum += nGap[i];
   }
   double analog = vTot > 0 ? vScore / vTot : 0.0;
   int bias = analog > 0.15 ? 1 : analog < -0.15 ? -1 : 0;
   double agree = vTot > 0 ? (bias == 1 ? vBull : bias == -1 ? vBear : 0.0) / vTot : 0.0;
   double avgGap = kc > 0 ? gapSum / kc : 0.0;
   double gapTight = MathMax(0.0, MathMin(1.0, 1.0 - avgGap / (wSum * 0.45 + 1e-9)));

   // kontekst
   HPush(h_churnSrc, atr);   // historia ATR(14) do percentylu zmienności
   double atrPct = HFull(h_churnSrc, 101) ? PercentRank(h_churnSrc, 100) : 0;   // na w Pine -> bramka nie przechodzi
   double trendForce = atr > 0 ? MathAbs(g_emaQuick.v - g_emaTrend.v) / atr : 0.0;
   bool chopRaw = trendForce < CHOP_CUT;
   bool chopNow = InpChopFilter ? chopRaw : false;
   bool slopeUp = rsiHist && rsi > r3;
   double oscReg = g_emaReg.v;

   // ML Supertrend
   double convInst = MathMax(-1.0, MathMin(1.0, analog / 1.5));
   EmaUpd(g_conv, convInst, SMOOTH_LEN);
   double mlDrive = MathMax(0.0, MathMin(1.0, MathAbs(g_conv.v) * 0.5 + gapTight * 0.3 + agree * 0.2));
   if(chopNow) mlDrive *= 0.35;
   double adaptMult = InpStMult * (1.0 + InpStMlResp * (1.0 - mlDrive));
   if(g_stAtr.ready)
   {
      double stSrc = SrcOf(InpStSrc, s);
      double upBand = stSrc - adaptMult * g_stAtr.v, dnBand = stSrc + adaptMult * g_stAtr.v;
      double prevL = g_stLong, prevS = g_stShort;
      if(!g_stInit) { g_stLong = upBand; g_stShort = dnBand; g_stDir = 1; g_stInit = true; }
      else
      {
         g_stLong  = (hadPrevClose && prevClose > prevL) ? MathMax(upBand, prevL) : upBand;
         g_stShort = (hadPrevClose && prevClose < prevS) ? MathMin(dnBand, prevS) : dnBand;
         if(g_stDir == -1 && c > prevS) g_stDir = 1;
         else if(g_stDir == 1 && c < prevL) g_stDir = -1;
      }
   }
   bool upTrend = g_stDir == 1, dnTrend = g_stDir == -1;
   bool volHealthy = atrPct >= InpVolBandLo && atrPct <= VOL_HI;
   bool slopeFit = (bias == 1 && slopeUp) || (bias == -1 && !slopeUp);
   bool stretched = (bias == 1 && rsi > 70) || (bias == -1 && rsi < 30);
   bool smoothUp = g_hasPrevEmaRsi5 && g_emaRsi5.v > g_prevEmaRsi5;
   g_prevEmaRsi5 = g_emaRsi5.v; g_hasPrevEmaRsi5 = true;
   bool alignedB = (bias == 1 && upTrend) || (bias == -1 && dnTrend);

   // stance i jego trwałość
   bool gates = (!InpTrendGate || alignedB) && (!InpVolBand || volHealthy) && !chopNow;
   int prevStance = g_stance;
   if(bias == 1 && gates) g_stance = 1;
   else if(bias == -1 && gates) g_stance = -1;
   bool changed = g_stance != prevStance;
   g_stanceAge = changed ? 0 : g_stanceAge + 1;
   bool earlyFlip = changed && (g_chg[0] || g_chg[1] || g_chg[2]);
   g_chg[2] = g_chg[1]; g_chg[1] = g_chg[0]; g_chg[0] = changed;

   // Rank i Confidence
   double rank = 0, conf = 0;
   if(bias != 0)
   {
      double pAgree = 25.0 * agree, pGap = 15.0 * gapTight;
      double pStruct = (slopeFit ? 10.0 : 0.0) + (stretched ? 0.0 : 5.0);
      double pTrend = alignedB ? 10.0 : 0.0;
      double pVol = volHealthy ? 10.0 : atrPct < InpVolBandLo ? 5.0 : 3.0;
      bool regFit = (bias == 1 && oscReg > 55) || (bias == -1 && oscReg < 45);
      double pReg = regFit ? 10.0 : (oscReg >= 45 && oscReg <= 55) ? 4.0 : 6.0;
      double pSmooth = ((bias == 1 && smoothUp) || (bias == -1 && !smoothUp)) ? 5.0 : 0.0;
      double pHold = MathMin(5.0, g_stanceAge);
      double kPen = kc < InpK ? (double)(InpK - kc) / InpK : 0.0;
      double pPen = MathMin(20.0, (chopRaw ? 8.0 : 0.0) + (stretched ? 6.0 : 0.0) + (earlyFlip ? 6.0 : 0.0) + 5.0 * kPen);
      rank = MathMax(0.0, MathMin(100.0, pAgree + pGap + pStruct + pTrend + pVol + pReg + pSmooth + pHold - pPen));
      conf = MathMax(0.0, MathMin(100.0, 40.0 * agree + 25.0 * gapTight + 15.0 * MathMin(1.0, g_stanceAge / 5.0) +
                                         10.0 * (slopeFit ? 1.0 : 0.0) - (earlyFlip ? 15.0 : 0.0) - 10.0 * kPen));
   }
   g_rank = rank; g_conf = conf;

   // sygnały
   bool flipLong = g_stance == 1 && prevStance != 1;
   bool flipShort = g_stance == -1 && prevStance != -1;
   bool qualifies = rank >= InpGateRank && conf >= InpGateConf;
   bool coolOK = g_bar - g_lastEntryBar >= COOL_BARS;
   g_trigLong = flipLong && qualifies && coolOK;
   g_trigShort = flipShort && qualifies && coolOK;
   if(g_trigLong || g_trigShort) g_lastEntryBar = g_bar;
   if((flipLong || flipShort) && !(g_trigLong || g_trigShort) && InpLogFlips && !g_warmup)
      PrintFormat("[MLRSI] stance %s bez sygnału: rank=%.0f conf=%.0f cooldown=%d", flipLong ? "LONG" : "SHORT", rank, conf, coolOK);
}

//====================================================================
//  DYWERGENCJA RSI (pivoty jak we wbudowanym "RSI Divergence")
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
   // RSI Wildera dla całego okna (indeks 0 = najnowsza zamknięta świeca)
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
   // pivot RSI w punkcie p (ostro niższy/wyższy od lbL świec z lewej i lbR z prawej)
   for(int cb = 0; cb < InpDivMaxAge; cb++)             // świeca potwierdzenia pivota
   {
      int p = cb + InpDivLbR;
      if(!IsRsiPivot(rsi, n, p, bull)) continue;
      // poprzedni pivot (najbliższy starszy)
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
   for(int k = 1; k <= InpDivLbR; k++) { double v = rsi[p - k]; if(v == EMPTY_VALUE || (low ? v <= rsi[p] : v >= rsi[p])) return false; }
   for(int k = 1; k <= InpDivLbL; k++) { double v = rsi[p + k]; if(v == EMPTY_VALUE || (low ? v <= rsi[p] : v >= rsi[p])) return false; }
   return true;
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

void TrailStop()
{
   if(!InpTrailOnSt || !g_stInit) return;
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double cur = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double newSL = NormalizeDouble(dir == 1 ? g_stLong : g_stShort, _Digits);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool better = dir == 1 ? newSL > cur + _Point : (cur == 0 || newSL < cur - _Point);
   bool valid  = dir == 1 ? newSL < tick.bid - minDist : newSL > tick.ask + minDist;
   if(better && valid) PM_ModifyStops(t, newSL, tp);
}

string SigKey() { return StringFormat("MLRSI_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void HandleSignal(int d)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   string side = d == 1 ? "LONG" : "SHORT";
   if(InpLogSignals) PrintFormat("[MLRSI] sygnał %s | rank %.0f conf %.0f | ST=%s", side, g_rank, g_conf, DoubleToString(d == 1 ? g_stLong : g_stShort, _Digits));

   if(InpDivOn)
   {
      string info = "";
      if(!DivergenceFound(d == 1, info)) { if(InpLogSignals) Print("[MLRSI] pominięty: brak dywergencji RSI w oknie"); return; }
      if(InpLogSignals) Print("[MLRSI] dywergencja: ", info);
   }

   int posDir;
   ulong pos = MyPosition(posDir);
   if(pos != 0 && posDir != d)
   {
      PM_CloseAllPositions(InpMagicNumber, "reverse_on_opposite");
      if(MyPosition(posDir) != 0) { EE_LogDecision("MLRSI", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   }
   else if(pos != 0) { if(InpLogSignals) Print("[MLRSI] pominięty: pozycja w tym kierunku już otwarta"); return; }
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("MLRSI", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = d == 1 ? g_stLong : g_stShort;
   if(!g_stInit || (entry - sl) * d <= 0) sl = entry - d * MathMax(g_atrNow, _Point * 10);   // linia po złej stronie - awaryjnie 1 ATR
   sl = NormalizeDouble(sl, _Digits);
   double risk = MathAbs(entry - sl);
   double tp = InpTpRR > 0 ? NormalizeDouble(entry + d * risk * InpTpRR, _Digits) : 0;
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string tag = StringFormat("mlrsi_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s TP=%s rank=%.0f conf=%.0f", side, vol, DoubleToString(entry, _Digits),
                               DoubleToString(sl, _Digits), tp == 0 ? "-" : DoubleToString(tp, _Digits), g_rank, g_conf));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpRsiBase < 2 || InpMemoryDepth < 80 || InpK < 1 || InpK > 64) return INIT_PARAMETERS_INCORRECT;
   g_rsiFastLen = (int)MathMax(2, MathRound(InpRsiBase / 2.0));
   g_rsiSlowLen = InpRsiBase * 2;
   ZeroMemory(g_rsi); ZeroMemory(g_rsiF); ZeroMemory(g_rsiS); ZeroMemory(g_atr14); ZeroMemory(g_stAtr);
   ZeroMemory(g_emaReg); ZeroMemory(g_emaRsi5); ZeroMemory(g_emaTrend); ZeroMemory(g_emaQuick); ZeroMemory(g_conv);
   HInit(h_src, HORIZON + 2); HInit(h_atr, HORIZON + 2); HInit(h_rsi, WIN_LEN + 2);
   HInit(h_slope, WIN_LEN); HInit(h_accel, WIN_LEN); HInit(h_churn, WIN_LEN); HInit(h_spread, WIN_LEN); HInit(h_regime, WIN_LEN);
   HInit(h_churnSrc, 101);
   ArrayResize(g_bank, InpMemoryDepth);
   g_bankN = 0; g_bankHead = -1; g_featN = 0;
   ArrayInitialize(g_wAuto, 1.0);
   for(int i = 0; i < 4; i++) g_chg[i] = false;
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie banku pamięci i stanów z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("ML RSI EA %s: przeliczono %d świec | bank %d/%d wierszy | ML Supertrend %s | stance %d | dywergencja %s",
               EA_VERSION, start, g_bankN, InpMemoryDepth, g_stDir == 1 ? "w górę" : "w dół", g_stance,
               InpDivOn ? "wł. (" + EnumToString(InpDivTf == PERIOD_CURRENT ? _Period : InpDivTf) + ")" : "wył.");
   if(g_bankN < AUTO_MIN) Print("Uwaga: za mało historii - bank pamięci niepełny, sygnały mogą być słabe");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      if(s == 1)
      {
         if(g_trigLong) HandleSignal(1);
         else if(g_trigShort) HandleSignal(-1);
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
