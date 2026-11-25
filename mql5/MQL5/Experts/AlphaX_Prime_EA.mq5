//+------------------------------------------------------------------+
//| AlphaX_Prime_EA.mq5                                                |
//| Expert Advisor oparty na logice wskaźnika "[ALPHAX] PRIME"        |
//| (Pine Script v6) - przeniesiony na MQL5.                          |
//|                                                                    |
//| SEKCJA A (ten plik): sygnał wejścia, ocena jakości, poziomy        |
//| SL/TP1/TP2/TP3, zarządzanie częściowymi wyjściami i limitem czasu.|
//| SEKCJA B (Include/Core): wykonanie zleceń, ryzyko, reconciliation.|
//|                                                                    |
//| Wszystkie wskaźniki liczone ręcznie tak jak w Pine (RMA Wildera,   |
//| EMA z inicjalizacją pierwszą wartością, odchylenie populacyjne),   |
//| bo wbudowane iATR/iMACD/iADX w MT5 wygładzają inaczej.             |
//| Decyzja wyłącznie na zamkniętej świecy (shift 1).                  |
//+------------------------------------------------------------------+
#property copyright "AlphaX Prime EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_TP_PLAN { TP_SPLIT_THIRDS = 0, TP_ALL_AT_TP3 = 1, TP_ALL_AT_TP1 = 2 };
enum ENUM_LOT_MODE { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Silnik trendu ==="
input int             InpEmaF        = 9;          // EMA Fast
input int             InpEmaM        = 21;         // EMA Mid
input int             InpEmaS        = 50;         // EMA Slow
input int             InpEmaL        = 200;        // EMA Long
input int             InpStLen       = 10;         // Supertrend - długość ATR
input double          InpStMult      = 3.0;        // Supertrend - mnożnik
input ENUM_TIMEFRAMES InpHtf         = PERIOD_M15; // TF biasu wyższego rzędu (gdy niższy od wykresu - użyty TF wykresu)

input group "=== Momentum i zmienność ==="
input int             InpRsiLen      = 14;         // RSI - długość
input int             InpMacdF       = 12;         // MACD fast
input int             InpMacdS       = 26;         // MACD slow
input int             InpMacdSig     = 9;          // MACD signal
input int             InpAdxLen      = 14;         // ADX - długość
input int             InpBbLen       = 20;         // Squeeze - długość
input double          InpBbMult      = 2.0;        // Squeeze - mnożnik Bollingera
input double          InpKcMult      = 1.5;        // Squeeze - mnożnik Keltnera
input int             InpAtrLen      = 14;         // ATR - długość
input int             InpFibLen      = 50;         // Fib - zasięg swingu (bary)
input double          InpFibTol      = 0.35;       // Fib - tolerancja (x ATR)

input group "=== Sesje (UTC) ==="
input string          InpSessGood    = "0700-2100"; // London + Overlap + New York (UTC) - +1 pkt jakości
input int             InpServerToUTCHours = 2;      // Tester: czas serwera minus UTC (na live liczone automatycznie)

input group "=== Reguły transakcji ==="
input double          InpSlBase      = 5.0;        // Bazowy SL (x ATR), skalowany percentylem zmienności
input double          InpTp1R        = 0.50;       // TP1 (x ryzyko)
input double          InpTp2R        = 0.84;       // TP2 (x ryzyko)
input double          InpTp3R        = 1.36;       // TP3 (x ryzyko)
input ENUM_TP_PLAN    InpTpPlan      = TP_SPLIT_THIRDS; // 1/3 na TP1, 1/3 na TP2, reszta na TP3
input bool            InpBreakEvenAfterTp1 = false; // Przesuń SL na wejście po TP1 (oryginał tego nie robi)
input int             InpMinQuality  = 4;          // Minimalna jakość wejścia (0-14)
input int             InpCooldown    = 5;          // Odstęp między wejściami (bary)
input int             InpMaxBars     = 300;        // Limit czasu transakcji (bary)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int             InpMagicNumber          = 260402;   // Magic number tej strategii
input double          InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int             InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE   InpLotMode              = LOT_RISK_PERCENT; // % kapitału / stały lot
input double          InpRiskPercentPerTrade  = 1.0;      // % kapitału ryzykowany na transakcję
input double          InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input int             InpMaxSimultaneousPos   = 1;        // Maks. jednoczesnych pozycji
input double          InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double          InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool            InpLogSignals           = true;     // Loguj sygnały i decyzje
input bool            InpLogScoreDetails      = false;    // Loguj rozbicie oceny jakości

//====================================================================
//  STAŁE I STAN
//====================================================================
#define WIN          900     // ile świec historii do przeliczenia wskaźników
#define PR_LEN       100     // ta.percentrank(atr, 100)
#define VOL_LEN      20      // średnia wolumenu
#define SQZ_RECENT   3       // squeeze "świeży" przez 3 bary
#define WARM_BARS    100     // Pine: bar_index > 100

double   FIB_R[4] = {0.382, 0.5, 0.618, 0.786};
int      g_sessStart = 0, g_sessEnd = 0;
datetime g_lastEntryTime = 0;     // czas wejścia ostatniej transakcji (cooldown)
string   EA_VERSION = "1.00";

int B2I(bool x) { return x ? 1 : 0; }

//--- migawka wskaźników dla świecy sygnałowej (shift 1)
struct Snap
{
   double close0, close1;
   double emaF0, emaF1, emaM0, emaS0, emaL0;
   double hist0, hist1, hist2, rsi0, adx0, atr0;
   bool   stBull0, stBull1;
   bool   sqzRecent; int sqzFireDir;
   double relVol, volPct, swingHi, swingLo;
   bool   sessGood;
   int    htfBull, htfBear;
   datetime barTime;
};

//====================================================================
//  OBLICZENIA SERII (indeks 0 = najnowsza zamknięta świeca)
//====================================================================
//--- EMA jak ta.ema: start od pierwszej wartości, liczona od najstarszej
void EmaSeries(const double &src[], int n, int len, double &out[])
{
   ArrayResize(out, n);
   double a = 2.0 / (len + 1);
   out[n - 1] = src[n - 1];
   for(int i = n - 2; i >= 0; i--) out[i] = a * src[i] + (1 - a) * out[i + 1];
}

//--- RMA jak ta.rma: start od SMA pierwszych len wartości
void RmaSeries(const double &src[], int n, int len, double &out[])
{
   ArrayResize(out, n);
   ArrayInitialize(out, EMPTY_VALUE);
   if(n < len) return;
   double sum = 0;
   for(int i = n - 1; i >= n - len; i--) sum += src[i];
   out[n - len] = sum / len;
   for(int i = n - len - 1; i >= 0; i--) out[i] = (out[i + 1] * (len - 1) + src[i]) / len;
}

void TrueRange(const MqlRates &r[], int n, double &tr[])
{
   ArrayResize(tr, n);
   for(int i = 0; i < n; i++)
   {
      tr[i] = r[i].high - r[i].low;
      if(i + 1 < n) tr[i] = MathMax(tr[i], MathMax(MathAbs(r[i].high - r[i + 1].close), MathAbs(r[i].low - r[i + 1].close)));
   }
}

//--- RSI jak ta.rsi (RMA zysków i strat)
void RsiSeries(const double &c[], int n, int len, double &out[])
{
   double up[], dn[], ru[], rd[];
   ArrayResize(up, n); ArrayResize(dn, n);
   for(int i = 0; i < n; i++)
   {
      double ch = (i + 1 < n) ? c[i] - c[i + 1] : 0;
      up[i] = MathMax(ch, 0); dn[i] = MathMax(-ch, 0);
   }
   RmaSeries(up, n - 1, len, ru);  // najstarsza świeca nie ma zmiany - pomijamy ją
   RmaSeries(dn, n - 1, len, rd);
   ArrayResize(out, n);
   ArrayInitialize(out, 50);
   for(int i = 0; i < n - 1; i++)
   {
      if(ru[i] == EMPTY_VALUE) continue;
      out[i] = rd[i] == 0 ? 100 : (ru[i] == 0 ? 0 : 100 - 100 / (1 + ru[i] / rd[i]));
   }
}

//--- histogram MACD jak w Pine (sygnał = EMA linii MACD)
void MacdHist(const double &c[], int n, double &hist[])
{
   double ef[], es[], line[], sig[];
   EmaSeries(c, n, InpMacdF, ef);
   EmaSeries(c, n, InpMacdS, es);
   ArrayResize(line, n);
   for(int i = 0; i < n; i++) line[i] = ef[i] - es[i];
   EmaSeries(line, n, InpMacdSig, sig);
   ArrayResize(hist, n);
   for(int i = 0; i < n; i++) hist[i] = line[i] - sig[i];
}

//--- ADX jak ta.dmi
double AdxAt0(const MqlRates &r[], int n, int len)
{
   double tr[], pdm[], mdm[];
   TrueRange(r, n, tr);
   ArrayResize(pdm, n); ArrayResize(mdm, n);
   for(int i = 0; i < n; i++)
   {
      double up = (i + 1 < n) ? r[i].high - r[i + 1].high : 0;
      double dn = (i + 1 < n) ? r[i + 1].low - r[i].low : 0;
      pdm[i] = (up > dn && up > 0) ? up : 0;
      mdm[i] = (dn > up && dn > 0) ? dn : 0;
   }
   double rtr[], rp[], rm[], dx[], adx[];
   RmaSeries(tr, n, len, rtr); RmaSeries(pdm, n, len, rp); RmaSeries(mdm, n, len, rm);
   ArrayResize(dx, n);
   int valid = 0;
   for(int i = 0; i < n; i++)
   {
      if(rtr[i] == EMPTY_VALUE || rtr[i] == 0) { dx[i] = 0; continue; }
      double p = 100 * rp[i] / rtr[i], m = 100 * rm[i] / rtr[i];
      double s = p + m;
      dx[i] = MathAbs(p - m) / (s == 0 ? 1 : s);
      valid++;
   }
   RmaSeries(dx, valid, len, adx);
   return (ArraySize(adx) > 0 && adx[0] != EMPTY_VALUE) ? 100 * adx[0] : 0;
}

//--- Supertrend jak ta.supertrend: zwraca kierunek (-1 = byczy) dla indeksów 0 i 1
void SupertrendDir(const MqlRates &r[], int n, int len, double mult, int &dir0, int &dir1)
{
   double tr[], atr[];
   TrueRange(r, n, tr);
   RmaSeries(tr, n, len, atr);
   double prevUp = 0, prevLo = 0, prevSt = 0; bool started = false;
   dir0 = dir1 = 1;
   for(int i = n - 1; i >= 0; i--)
   {
      if(atr[i] == EMPTY_VALUE) continue;
      double src = (r[i].high + r[i].low) / 2;
      double up = src + mult * atr[i], lo = src - mult * atr[i];
      double prevClose = (i + 1 < n) ? r[i + 1].close : r[i].close;
      int dir;
      if(!started) { dir = 1; started = true; }
      else
      {
         lo = (lo > prevLo || prevClose < prevLo) ? lo : prevLo;
         up = (up < prevUp || prevClose > prevUp) ? up : prevUp;
         if(prevSt == prevUp) dir = r[i].close > up ? -1 : 1;
         else                 dir = r[i].close < lo ? 1 : -1;
      }
      double st = dir == -1 ? lo : up;
      prevUp = up; prevLo = lo; prevSt = st;
      if(i == 1) dir1 = dir;
      if(i == 0) dir0 = dir;
   }
}

//====================================================================
//  SESJA (UTC)
//====================================================================
int ServerToUTCHours()
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return InpServerToUTCHours;
   return (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0);
}
bool ParseSession(string sess, int &startMin, int &endMin)
{
   if(StringLen(sess) != 9 || StringGetCharacter(sess, 4) != '-') return false;
   startMin = (int)StringToInteger(StringSubstr(sess, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 2, 2));
   endMin   = (int)StringToInteger(StringSubstr(sess, 5, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 7, 2));
   return true;
}
bool InSessionUTC(datetime serverTime)
{
   MqlDateTime d; TimeToStruct(serverTime - ServerToUTCHours() * 3600, d);
   int m = d.hour * 60 + d.min;
   if(g_sessEnd > g_sessStart) return m >= g_sessStart && m < g_sessEnd;
   return m >= g_sessStart || m < g_sessEnd;
}

//====================================================================
//  BIAS WYŻSZEGO TF (ostatnia zamknięta świeca HTF - jak [1] + lookahead_on)
//====================================================================
bool HtfPoints(datetime chartBarTime, int &bullPts, int &bearPts)
{
   ENUM_TIMEFRAMES tf = (PeriodSeconds(InpHtf) < PeriodSeconds(_Period)) ? _Period : InpHtf;
   int cur = iBarShift(_Symbol, tf, chartBarTime, false);
   if(cur < 0) return false;
   MqlRates hr[];
   ArraySetAsSeries(hr, true);
   int n = CopyRates(_Symbol, tf, cur + 1, WIN, hr); // od poprzedniej (zamkniętej) świecy HTF wstecz
   if(n < InpEmaS * 3) return false;
   double c[];
   ArrayResize(c, n);
   for(int i = 0; i < n; i++) c[i] = hr[i].close;
   double e1[], e2[], rsi[], hist[];
   EmaSeries(c, n, InpEmaM, e1);
   EmaSeries(c, n, InpEmaS, e2);
   RsiSeries(c, n, InpRsiLen, rsi);
   MacdHist(c, n, hist);
   bullPts = B2I(c[0] > e1[0]) + B2I(e1[0] > e2[0]) + B2I(rsi[0] > 50) + B2I(hist[0] > 0);
   bearPts = B2I(c[0] < e1[0]) + B2I(e1[0] < e2[0]) + B2I(rsi[0] < 50) + B2I(hist[0] < 0);
   return true;
}

//====================================================================
//  MIGAWKA WSKAŹNIKÓW DLA ŚWIECY SYGNAŁOWEJ
//====================================================================
bool BuildSnap(Snap &s)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, _Period, 1, WIN, r);  // indeks 0 = shift 1 (zamknięta)
   if(n < MathMax(InpEmaL * 2, WARM_BARS + PR_LEN + 10)) return false;

   double c[], tv[];
   ArrayResize(c, n); ArrayResize(tv, n);
   for(int i = 0; i < n; i++) { c[i] = r[i].close; tv[i] = (double)r[i].tick_volume; }

   double ef[], em[], es[], el[], hist[], rsi[], tr[], atr[], atrK[], kcMid[];
   EmaSeries(c, n, InpEmaF, ef); EmaSeries(c, n, InpEmaM, em);
   EmaSeries(c, n, InpEmaS, es); EmaSeries(c, n, InpEmaL, el);
   MacdHist(c, n, hist);
   RsiSeries(c, n, InpRsiLen, rsi);
   TrueRange(r, n, tr);
   RmaSeries(tr, n, InpAtrLen, atr);
   RmaSeries(tr, n, InpBbLen, atrK);
   EmaSeries(c, n, InpBbLen, kcMid);
   if(atr[0] == EMPTY_VALUE) return false;

   s.barTime = r[0].time;
   s.close0 = c[0]; s.close1 = c[1];
   s.emaF0 = ef[0]; s.emaF1 = ef[1]; s.emaM0 = em[0]; s.emaS0 = es[0]; s.emaL0 = el[0];
   s.hist0 = hist[0]; s.hist1 = hist[1]; s.hist2 = hist[2];
   s.rsi0 = rsi[0]; s.atr0 = atr[0];
   s.adx0 = AdxAt0(r, n, InpAdxLen);

   int d0, d1;
   SupertrendDir(r, n, InpStLen, InpStMult, d0, d1);
   s.stBull0 = d0 < 0; s.stBull1 = d1 < 0;

   // ta.percentrank(atr, 100): % z poprzednich 100 wartości <= bieżąca
   int cnt = 0, tot = 0;
   for(int k = 1; k <= PR_LEN && k < n; k++) { if(atr[k] == EMPTY_VALUE) continue; tot++; if(atr[k] <= atr[0]) cnt++; }
   s.volPct = tot == PR_LEN ? 100.0 * cnt / PR_LEN : 50.0;

   // względny wolumen (tick volume na CFD)
   double vs = 0; for(int k = 0; k < VOL_LEN; k++) vs += tv[k];
   double va = vs / VOL_LEN;
   s.relVol = va > 0 ? tv[0] / va : 1.0;

   // swing dla Fibonacciego (z bieżącą świecą, jak ta.highest/lowest)
   s.swingHi = r[0].high; s.swingLo = r[0].low;
   for(int k = 1; k < InpFibLen && k < n; k++) { s.swingHi = MathMax(s.swingHi, r[k].high); s.swingLo = MathMin(s.swingLo, r[k].low); }

   // squeeze: BB wewnątrz Keltnera; "wystrzał" = koniec squeeze; kierunek wg close vs SMA
   int lastFire = -1; int fireDir = 0;
   bool prevOn = false;
   for(int i = n - InpBbLen; i >= 0; i--)
   {
      double sum = 0, sq = 0;
      for(int k = 0; k < InpBbLen; k++) sum += c[i + k];
      double basis = sum / InpBbLen;
      for(int k = 0; k < InpBbLen; k++) sq += (c[i + k] - basis) * (c[i + k] - basis);
      double dev = InpBbMult * MathSqrt(sq / InpBbLen);           // odchylenie populacyjne jak ta.stdev
      if(atrK[i] == EMPTY_VALUE) { prevOn = false; continue; }
      bool on = (basis + dev) < (kcMid[i] + InpKcMult * atrK[i]) && (basis - dev) > (kcMid[i] - InpKcMult * atrK[i]);
      if(!on && prevOn) { lastFire = i; fireDir = c[i] > basis ? 1 : -1; }
      prevOn = on;
   }
   s.sqzRecent = lastFire >= 0 && lastFire <= SQZ_RECENT;
   s.sqzFireDir = fireDir;

   s.sessGood = InSessionUTC(r[0].time);
   if(!HtfPoints(r[0].time, s.htfBull, s.htfBear)) { s.htfBull = s.htfBear = 0; }
   return true;
}

//====================================================================
//  OCENA JAKOŚCI (f_score i f_fib z Pine)
//====================================================================
int FibPoints(const Snap &s, int d)
{
   double rng = s.swingHi - s.swingLo;
   int best = 0;
   if(rng <= 0) return 0;
   double tol = s.atr0 * InpFibTol;
   for(int i = 0; i < 4; i++)
   {
      double fr = FIB_R[i];
      double lvl = d >= 0 ? s.swingHi - fr * rng : s.swingLo + fr * rng;
      if(MathAbs(s.close0 - lvl) <= tol)
      {
         int p = (fr == 0.5 || fr == 0.618) ? 2 : 1;
         if(p > best) best = p;
      }
   }
   return best;
}

int Score(const Snap &s, int d, string &detail)
{
   int ctfN = d > 0 ? B2I(s.close0 > s.emaM0) + B2I(s.emaF0 > s.emaM0) + B2I(s.emaM0 > s.emaS0) + B2I(s.hist0 > 0) + B2I(s.rsi0 > 50)
                    : B2I(s.close0 < s.emaM0) + B2I(s.emaF0 < s.emaM0) + B2I(s.emaM0 < s.emaS0) + B2I(s.hist0 < 0) + B2I(s.rsi0 < 50);
   int htfN = d > 0 ? s.htfBull : s.htfBear;
   bool full = d > 0 ? (s.emaF0 > s.emaM0 && s.emaM0 > s.emaS0 && s.emaS0 > s.emaL0) : (s.emaF0 < s.emaM0 && s.emaM0 < s.emaS0 && s.emaS0 < s.emaL0);
   bool part = !full && (d > 0 ? (s.emaF0 > s.emaM0 && s.emaM0 > s.emaS0) : (s.emaF0 < s.emaM0 && s.emaM0 < s.emaS0));
   bool rsiOk = d > 0 ? (s.rsi0 >= 45 && s.rsi0 <= 68) : (s.rsi0 >= 32 && s.rsi0 <= 55);
   bool momExp = MathAbs(s.hist0) > MathAbs(s.hist1) && MathAbs(s.hist1) > MathAbs(s.hist2);
   bool momOk = momExp && (d > 0 ? s.hist0 > 0 : s.hist0 < 0);
   int fib = FibPoints(s, d);
   bool sqz = s.sqzRecent && s.sqzFireDir == d;

   int q = 0;
   q += ctfN >= 5 ? 2 : ctfN >= 3 ? 1 : 0;
   q += htfN >= 4 ? 2 : htfN == 3 ? 1 : 0;
   q += s.adx0 >= 25 ? 1 : 0;
   q += s.relVol >= 1.0 ? 1 : 0;
   q += momOk ? 1 : 0;
   q += full ? 2 : part ? 1 : 0;
   q += rsiOk ? 1 : 0;
   q += sqz ? 1 : 0;
   q += fib;
   q += s.sessGood ? 1 : 0;
   detail = StringFormat("ctf=%d/5 htf=%d/4 adx=%.1f relVol=%.2f mom=%d stack=%s rsi=%.1f sqz=%d fib=%d sesja=%d",
                         ctfN, htfN, s.adx0, s.relVol, momOk, full ? "full" : part ? "part" : "-", s.rsi0, sqz, fib, s.sessGood);
   return MathMin(q, 14);
}

//====================================================================
//  STAN TRANSAKCJI (zmienne globalne terminala - przeżywa restart)
//====================================================================
string GvPrefix(ulong ticket) { return "APX_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString((long)ticket) + "_"; }
string GvKey(ulong ticket, string field) { return GvPrefix(ticket) + field; }
void   GvSet(ulong ticket, string f, double v) { GlobalVariableSet(GvKey(ticket, f), v); }
double GvGet(ulong ticket, string f) { return GlobalVariableCheck(GvKey(ticket, f)) ? GlobalVariableGet(GvKey(ticket, f)) : EMPTY_VALUE; }
void   GvClear(ulong ticket) { GlobalVariablesDeleteAll(GvPrefix(ticket)); }

ulong MyPosition()
{
   ulong tickets[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol) return tickets[i];
   return 0;
}

//--- dzielenie wolumenu na części TP1/TP2/TP3
void SplitVolume(double total, double &v1, double &v2)
{
   v1 = v2 = 0;
   if(InpTpPlan != TP_SPLIT_THIRDS) return;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double third = MathFloor(total / 3.0 / step + 1e-9) * step;
   if(third >= mn && total - 2 * third >= mn - 1e-9) { v1 = third; v2 = third; }
   else EE_LogDecision("APX", "SPLIT_SKIPPED", StringFormat("wolumen %.2f za mały na 3 części - całość na TP3", total));
}

//--- częściowe wyjścia TP1/TP2 i break-even - sprawdzane na każdym ticku
void ManagePartials()
{
   ulong t = MyPosition();
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double tp1 = GvGet(t, "tp1");
   if(tp1 == EMPTY_VALUE) return; // pozycja bez zapisanego planu (np. otwarta ręcznie)
   bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
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
         if(InpLogSignals) PrintFormat("[APX] TP1 osiągnięty @%s", DoubleToString(px, _Digits));
         if(InpBreakEvenAfterTp1 && PositionSelectByTicket(t))
         {
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            if(isBuy ? sl < entry : (sl > entry || sl == 0)) PM_ModifyStops(t, entry, PositionGetDouble(POSITION_TP));
         }
      }
   }
   if(r2 && !h2 && PositionSelectByTicket(t))
   {
      bool ok = v2 <= 0 || PM_ClosePartial(t, v2, "TP2");
      if(ok) { GvSet(t, "h2", 1); if(InpLogSignals) PrintFormat("[APX] TP2 osiągnięty @%s", DoubleToString(px, _Digits)); }
   }
}

//--- limit czasu transakcji
void CheckTimeout()
{
   ulong t = MyPosition();
   if(t == 0 || !PositionSelectByTicket(t)) return;
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   int bars = iBarShift(_Symbol, _Period, opened, false);
   if(bars >= InpMaxBars)
   {
      EE_LogDecision(IntegerToString(t), "TIMEOUT", StringFormat("%d barów w transakcji - zamykam", bars));
      if(PM_ClosePosition(t, "timeout")) GvClear(t);
   }
}

//--- czas ostatniego wejścia z historii (cooldown po restarcie)
datetime LastEntryFromHistory()
{
   datetime last = 0;
   if(!HistorySelect(TimeCurrent() - 60 * 86400, TimeCurrent())) return 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      if(t > last) last = t;
   }
   return last;
}

//--- idempotencja sygnału (poza testerem)
string SigKey() { return StringFormat("APX_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime barTime)
{
   if(MQLInfoInteger(MQL_TESTER)) return false;
   return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= barTime;
}
void MarkSignalTraded(datetime barTime) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)barTime); }

//====================================================================
//  SYGNAŁ I WEJŚCIE (raz na zamkniętą świecę)
//====================================================================
void OnNewBar()
{
   CheckTimeout();

   Snap s;
   if(!BuildSnap(s)) return;

   bool stFlipUp = s.stBull0 && !s.stBull1;
   bool stFlipDn = !s.stBull0 && s.stBull1;
   bool longTrig  = s.stBull0 && !stFlipUp && s.close0 > s.emaF0 && s.close1 <= s.emaF1 && s.close0 > s.emaM0;
   bool shortTrig = !s.stBull0 && !stFlipDn && s.close0 < s.emaF0 && s.close1 >= s.emaF1 && s.close0 < s.emaM0;
   if(!longTrig && !shortTrig) return;

   // w trakcie transakcji oryginał nie wchodzi ponownie (brak odwracania)
   if(MyPosition() != 0) { if(InpLogSignals) Print("[APX] wyzwalacz pominięty: trwa transakcja"); return; }
   int barsSince = g_lastEntryTime > 0 ? iBarShift(_Symbol, _Period, g_lastEntryTime, false) : 100000;
   if(barsSince < InpCooldown) { if(InpLogSignals) PrintFormat("[APX] wyzwalacz pominięty: cooldown (%d/%d)", barsSince, InpCooldown); return; }

   string dL = "", dS = "";
   int qL = Score(s, 1, dL), qS = Score(s, -1, dS);
   bool tradeLong  = longTrig && qL >= InpMinQuality;
   bool tradeShort = shortTrig && qS >= InpMinQuality && !tradeLong;
   int q = longTrig ? qL : qS;
   if(InpLogSignals) PrintFormat("[APX] wyzwalacz %s | jakość %d/14 (min %d)", longTrig ? "LONG" : "SHORT", q, InpMinQuality);
   if(InpLogScoreDetails) Print("[APX] ", longTrig ? dL : dS);
   if(!tradeLong && !tradeShort) return;

   if(SignalAlreadyTraded(s.barTime)) { EE_LogDecision("APX", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(!RM_CanOpenNewPosition(InpMagicNumber, InpMaxSimultaneousPos)) return;

   int d = tradeLong ? 1 : -1;
   double slMult = InpSlBase * (0.8 + 0.6 * s.volPct / 100.0);
   double risk = slMult * s.atr0;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d > 0 ? tick.ask : tick.bid;
   double sl  = NormalizeDouble(entry - d * risk, _Digits);
   double tp1 = NormalizeDouble(entry + d * risk * InpTp1R, _Digits);
   double tp2 = NormalizeDouble(entry + d * risk * InpTp2R, _Digits);
   double tp3 = NormalizeDouble(entry + d * risk * InpTp3R, _Digits);
   double brokerTP = InpTpPlan == TP_ALL_AT_TP1 ? tp1 : tp3;

   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;

   double v1, v2;
   SplitVolume(vol, v1, v2);

   string tag = StringFormat("apx_%s_%d", d > 0 ? "L" : "S", (int)s.barTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, brokerTP, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s (%.2f ATR) TP1=%s TP2=%s TP3=%s jakość=%d/14",
                               d > 0 ? "LONG" : "SHORT", vol, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), slMult,
                               DoubleToString(tp1, _Digits), DoubleToString(tp2, _Digits), DoubleToString(tp3, _Digits), q));
   if(res == EXEC_FAILED) return;
   MarkSignalTraded(s.barTime);
   g_lastEntryTime = TimeCurrent();

   if(res == EXEC_CONFIRMED)
   {
      ulong t = PM_FindLatestTicketByMagic(InpMagicNumber, _Symbol);
      if(t > 0) // plan zapisujemy zawsze - potrzebny też dla break-even
      {
         GvClear(t);
         GvSet(t, "tp1", tp1); GvSet(t, "tp2", tp2);
         GvSet(t, "v1", v1);   GvSet(t, "v2", v2);
         GvSet(t, "h1", 0);    GvSet(t, "h2", 0);
      }
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(!ParseSession(InpSessGood, g_sessStart, g_sessEnd)) { Print("Błędny format sesji - użyj HHMM-HHMM"); return INIT_PARAMETERS_INCORRECT; }
   if(InpTp1R <= 0 || InpTp2R < InpTp1R || InpTp3R < InpTp2R) { Print("TP muszą rosnąć: TP1 <= TP2 <= TP3"); return INIT_PARAMETERS_INCORRECT; }

   RC_ReconcileState(InpMagicNumber);
   g_lastEntryTime = LastEntryFromHistory();
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("AlphaX Prime EA %s: HTF=%s, sesja %s UTC (serwer-UTC=%+d h), plan TP=%s",
               EA_VERSION, EnumToString(InpHtf), InpSessGood, ServerToUTCHours(), EnumToString(InpTpPlan));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   // kill-switch ZAWSZE pierwszy
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;

   // TP1/TP2 na bieżącej cenie (jak sprawdzanie high/low w oryginale)
   if(InpTpPlan == TP_SPLIT_THIRDS || InpBreakEvenAfterTp1) ManagePartials();

   if(UT_IsNewBar(_Symbol, PERIOD_CURRENT)) OnNewBar();
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_IN) RC_RegisterTicket(InpMagicNumber, posId);
   else if(!PositionSelectByTicket(posId)) GvClear(posId); // pozycja zamknięta (SL/TP3/limit czasu) - usuń jej plan
}
