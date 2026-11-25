//+------------------------------------------------------------------+
//| CISD_Model_EA.mq5                                                  |
//| Expert Advisor oparty na logice wskaźnika "CISD Model+"           |
//| (Authrain Trades, Pine Script v6) - przeniesiony na MQL5.          |
//|                                                                    |
//| SEKCJA A (ten plik): tłumaczenie sygnału CISD + decyzje wejścia.   |
//| SEKCJA B (Include/Core): wykonanie zleceń, ryzyko, reconciliation. |
//| Zleceń NIE wysyłamy tu bezpośrednio - tylko przez moduły Core/.    |
//|                                                                    |
//| Logika liczona wyłącznie na ZAMKNIĘTYCH świecach (bez repaintu):  |
//| każda świeca jest przetwarzana raz, w kolejności chronologicznej,  |
//| dokładnie tak jak Pine przechodzi kolejne bary historii.           |
//+------------------------------------------------------------------+
#property copyright "CISD Model EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_CISD_BIAS     { BIAS_NEUTRAL = 0, BIAS_BULLISH = 1, BIAS_BEARISH = 2 };
enum ENUM_CISD_GRADE    { GRADE_C = 3, GRADE_BMINUS = 4, GRADE_BPLUS = 5, GRADE_A = 6, GRADE_APLUS = 7 };
enum ENUM_ENTRY_MODE    { ENTRY_MARKET = 0, ENTRY_LIMIT_AT_CISD = 1 };
enum ENUM_TP_MODE       { TP_LIQUIDITY_OR_RR = 0, TP_FIXED_RR = 1 };
enum ENUM_SMT_SENS      { SMT_SENSITIVE = 2, SMT_NORMAL = 5, SMT_STRICT = 10 };
enum ENUM_LOT_MODE      { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ CISD
//====================================================================
input group "=== Sygnał CISD ==="
input bool            InpTradingEnabled     = true;          // Handel włączony (w Pine: "Show CISD" - bramkuje cały sygnał)
input ENUM_CISD_BIAS  InpBias               = BIAS_NEUTRAL;  // Kierunek: Neutral = long i short
input int             InpMaxConfirmBars     = 15;            // Okno (bary) na sweep/FVG przed CISD (min. 12, jak w Pine)
input bool            InpCtfFvgDelivery     = true;          // Uznaj dostarczenie z FVG bieżącego TF jako pochodzenie
input bool            InpCtfSweeps          = true;          // Uznaj sweep pivotów bieżącego TF jako pochodzenie
input int             InpLiqMaxLevels       = 2;             // Ile ostatnich pivotów płynności śledzić na stronę (Pine: Max Liquidity Levels)
input ENUM_TIMEFRAMES InpLiqTF              = PERIOD_H1;     // TF płynności wyższego rzędu (Pine: Liquidity Timeframe)
input bool            InpIgnoreProximity    = true;          // Odrzuć CISD bliżej niż 0.75 ATR od aktywnego CISD w tym samym kierunku
input int             InpSetupsTracked      = 5;             // Ile CISD na stronę pamiętać (Pine: Number of Setups Displayed - wpływa na filtr bliskości)
input bool            InpRemoveInvalidated  = true;          // Usuwaj unieważnione CISD z pamięci (Pine: Hide Invalidated Setups)
input ENUM_CISD_GRADE InpMinGradeStore      = GRADE_C;       // Minimalna ocena, by CISD w ogóle się liczył (Pine: Min Grade to Display)
input ENUM_CISD_GRADE InpMinGradeTrade      = GRADE_BMINUS;  // Minimalna ocena, by OTWORZYĆ pozycję
input int             InpWarmupBars         = 3000;          // Ile świec historii przeliczyć przy starcie (odtworzenie stanu)

input group "=== Kontekst: HTF FVG / sesje / SMT ==="
input bool            InpUseHtfFvg          = true;          // Śledź HTF FVG - punkt "HTF PDA Delivery" (Pine: Show HTF FVGs)
input int             InpFvgPerSide         = 1;             // Ile HTF FVG na stronę i TF śledzić
input bool            InpUseSessionLiq      = true;          // Śledź płynność sesji Asia/London (Pine: Show Session Liquidity)
input string          InpAsiaSession        = "2000-0000";   // Sesja Asia (czas Nowego Jorku, HHMM-HHMM)
input string          InpLondonSession      = "0200-0500";   // Sesja London (czas Nowego Jorku)
input bool            InpUsePDHPDL          = true;          // PDH/PDL jako cele
input bool            InpUsePWHPWL          = true;          // PWH/PWL jako cele
input int             InpServerToNYHours    = 7;             // Przesunięcie: czas serwera minus czas Nowego Jorku (godz.). UWAGA: korekta przy zmianie czasu!
input string          InpSmtSymbol          = "US500";       // Symbol skorelowany do SMT (puste = SMT wyłączone)
input ENUM_SMT_SENS   InpSmtSensitivity     = SMT_NORMAL;    // Czułość SMT (długość pivota)
input int             InpSmtLookback        = 6;             // Ważność SMT (bary) po potwierdzeniu

input group "=== Checklista oceny (grade) ==="
input bool            InpCkSweep            = true;          // Liquidity Sweep
input bool            InpCkPDA              = true;          // HTF PDA Delivery
input bool            InpCkVolume           = true;          // Volume (tick volume > 1.2 x SMA20)
input bool            InpCkSession          = true;          // Session Sweep
input bool            InpCkTargets          = true;          // Clear Targets (RR >= 1.5)
input bool            InpCkSMT              = true;          // SMT

input group "=== Wejście i wyjście ==="
input ENUM_ENTRY_MODE InpEntryMode          = ENTRY_MARKET;  // Market po zamknięciu świecy / Limit na poziomie CISD
input int             InpLimitExpiryBars    = 10;            // Limit: anuluj po tylu świecach bez wypełnienia
input ENUM_TP_MODE    InpTPMode             = TP_LIQUIDITY_OR_RR; // TP: najbliższa płynność (gdy RR>=min) albo stałe RR
input double          InpMinRR              = 1.5;           // Minimalne RR celu płynności (Pine: 1.5)
input double          InpFallbackRR         = 1.5;           // Stałe RR, gdy brak celu płynności / tryb stały
input double          InpSLBufferPoints     = 0;             // Dodatkowy bufor SL w punktach (oprócz spreadu)
input bool            InpReverseOnOpposite  = true;          // Przeciwny CISD zamyka pozycję i otwiera odwrotną
input bool            InpUseTradeWindow     = true;          // Nowe wejścia tylko w oknie czasowym
input string          InpTradeWindow        = "0600-1600";   // Okno handlu (czas Nowego Jorku)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int             InpMagicNumber          = 260401;     // Magic number tej strategii
input double          InpMaxSpreadPoints      = 300;        // Maksymalny spread (punkty) - dopasuj do NAS100 u brokera
input int             InpSlippagePoints       = 50;         // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE   InpLotMode              = LOT_RISK_PERCENT; // % kapitału / stały lot
input double          InpRiskPercentPerTrade  = 1.0;        // % kapitału ryzykowany na transakcję
input double          InpFixedLot             = 0.10;       // Stały lot (gdy tryb = stały)
input int             InpMaxSimultaneousPos   = 1;          // Maks. jednoczesnych pozycji (łącznie ze zleceniem limit)
input double          InpMaxDailyDrawdownPct  = 3.0;        // Kill-switch dzienny (% equity)
input double          InpMaxTotalDrawdownPct  = 10.0;       // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool            InpLogSignals           = true;       // Loguj każdy wykryty CISD i decyzję
input bool            InpLogRejections        = false;      // Loguj odrzucone CISD (powód)

//====================================================================
//  STAŁE Z ORYGINAŁU
//====================================================================
#define PIVOT_LEN     2
#define PROX_ATR      0.75
#define VOL_MULT      1.2
#define ATR_LEN       14
#define VOL_SMA_LEN   20
#define LEG_LOOKBACK  500
#define MAX_SESS_LVLS 24

//====================================================================
//  STRUKTURY STANU (odpowiedniki typów UDT z Pine)
//====================================================================
struct Liq      { double price; bool swept; };
struct SessLvl  { double price; bool isHigh; bool swept; datetime sweptTime; };
struct Fvg      { double top; double bot; bool bull; int tfIdx; };
struct Cisd
{
   double   level;
   double   slPrice;
   bool     bull;
   bool     invalidated;
   int      grade;
   bool     ckSweep, ckPDA, ckVol, ckSession, ckTargets, ckSMT;
   double   target;
   int      bar;
   datetime barTime;
};

//--- tablice stanu
Liq      g_liqBuy[], g_liqSell[];
SessLvl  g_sess[];
Fvg      g_fvgs[];
Cisd     g_cisdBull[], g_cisdBear[];

//--- licznik przetworzonych świec (odpowiednik bar_index)
int      g_bar = -1;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;

//--- ATR (RMA Wildera, jak ta.atr w Pine - iATR w MT5 liczy SMA, więc liczymy sami)
double   g_atr = 0; int g_atrCount = 0; double g_atrSeed = 0;

//--- płynność / sweepy
int      g_lastSweepBuyBar = -10000, g_lastSweepSellBar = -10000;
double   g_htfBSL = EMPTY_VALUE, g_htfSSL = EMPTY_VALUE;
int      g_htfSweepBuyBar = -10000, g_htfSweepSellBar = -10000;
datetime g_htfLiqLastClosed = 0;

//--- sesje
bool     g_inAsiaPrev = false, g_inLondonPrev = false;
double   g_asiaH = EMPTY_VALUE, g_asiaL = EMPTY_VALUE, g_lonH = EMPTY_VALUE, g_lonL = EMPTY_VALUE;
int      g_asiaStart, g_asiaEnd, g_lonStart, g_lonEnd, g_winStart, g_winEnd;
int      g_lastSessSweepBar = -10000;
bool     g_lastSessSweepWasHigh = false;

//--- PDH/PDL/PWH/PWL
double   g_curDayH = EMPTY_VALUE, g_curDayL = EMPTY_VALUE, g_pdh = EMPTY_VALUE, g_pdl = EMPTY_VALUE;
double   g_curWeekH = EMPTY_VALUE, g_curWeekL = EMPTY_VALUE, g_pwh = EMPTY_VALUE, g_pwl = EMPTY_VALUE;
bool     g_pdhSwept = false, g_pdlSwept = false, g_pwhSwept = false, g_pwlSwept = false;
datetime g_dayOpen = 0, g_weekOpen = 0;

//--- FVG
double   g_ctfBullTop = EMPTY_VALUE, g_ctfBullBot = EMPTY_VALUE, g_ctfBearTop = EMPTY_VALUE, g_ctfBearBot = EMPTY_VALUE;
int      g_lastCtfFvgLong = -10000, g_lastCtfFvgShort = -10000;
int      g_lastHtfDeliverLong = -10000, g_lastHtfDeliverShort = -10000;
ENUM_TIMEFRAMES g_fvgTF[2];
datetime g_fvgLastClosed[2];

//--- SMT
bool     g_smtOn = false;
double   g_lastPlPx = EMPTY_VALUE, g_lastCmpPlPx = EMPTY_VALUE, g_lastPhPx = EMPTY_VALUE, g_lastCmpPhPx = EMPTY_VALUE;
int      g_lastBullSmtBar = -10000, g_lastBearSmtBar = -10000;

//--- maszyna stanu CISD
int      g_cmBias = 0;
double   g_cmLevel = EMPTY_VALUE, g_cmPivot = EMPTY_VALUE;
int      g_cmLevelBar = 0, g_cmPivotBar = 0;

//--- wynik bieżącej świecy (nowy CISD do ewentualnego handlu)
bool     g_newBull = false, g_newBear = false;
Cisd     g_sigBull, g_sigBear;

//--- zarządzanie zleceniem limit
int      g_pendingPlacedBar = -1;
double   g_pendingSL = 0;
bool     g_pendingBull = false;

string   EA_VERSION = "1.00";

//--- deklaracje funkcji używanych przed definicją
void AddFvg(bool bull, double top, double bot, int tfIdx);
void LogReject(bool bull, double level, string why);

//====================================================================
//  DOSTĘP DO HISTORII: shift liczony od przetwarzanej świecy
//====================================================================
int g_s = 1; // shift przetwarzanej (zamkniętej) świecy
double O(int k)  { return iOpen(_Symbol, _Period, g_s + k); }
double H(int k)  { return iHigh(_Symbol, _Period, g_s + k); }
double L(int k)  { return iLow(_Symbol, _Period, g_s + k); }
double Cl(int k) { return iClose(_Symbol, _Period, g_s + k); }
long   V(int k)  { return iTickVolume(_Symbol, _Period, g_s + k); }
datetime T(int k){ return iTime(_Symbol, _Period, g_s + k); }
int    CType(int k) { double c = Cl(k), o = O(k); return c > o ? 1 : (c < o ? -1 : 0); }
bool   HasBar(int k) { return g_s + k < Bars(_Symbol, _Period); }

//====================================================================
//  POMOCNICZE: czas Nowego Jorku, sesje, oceny
//====================================================================
int ParseHHMM(string s) { return (int)StringToInteger(StringSubstr(s, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(s, 2, 2)); }
bool ParseSession(string sess, int &startMin, int &endMin)
{
   if(StringLen(sess) != 9 || StringGetCharacter(sess, 4) != '-') return false;
   startMin = ParseHHMM(StringSubstr(sess, 0, 4));
   endMin   = ParseHHMM(StringSubstr(sess, 5, 4));
   return true;
}
int NYMinuteOfDay(datetime serverTime)
{
   MqlDateTime d; TimeToStruct(serverTime - InpServerToNYHours * 3600, d);
   return d.hour * 60 + d.min;
}
bool InSession(datetime serverTime, int startMin, int endMin)
{
   int m = NYMinuteOfDay(serverTime);
   if(endMin > startMin) return m >= startMin && m < endMin;
   return m >= startMin || m < endMin; // sesja przez północ (np. 20:00-00:00)
}
string GradeText(int g) { return g == 7 ? "A+" : g == 6 ? "A" : g == 5 ? "B+" : g == 4 ? "B-" : g == 3 ? "C" : "-"; }
bool IsSet(double v) { return v != EMPTY_VALUE; }

//--- automatyczny dobór HTF dla FVG - jak autoFvgTF1/2 w Pine
void ResolveFvgTFs()
{
   int sec = PeriodSeconds(_Period);
   if(sec <= 60)        { g_fvgTF[0] = PERIOD_M15; g_fvgTF[1] = PERIOD_H1; }
   else if(sec <= 300)  { g_fvgTF[0] = PERIOD_H1;  g_fvgTF[1] = PERIOD_H4; }
   else if(sec <= 900)  { g_fvgTF[0] = PERIOD_H4;  g_fvgTF[1] = PERIOD_D1; }
   else if(sec <= 3600) { g_fvgTF[0] = PERIOD_D1;  g_fvgTF[1] = PERIOD_W1; }
   else                 { g_fvgTF[0] = PERIOD_W1;  g_fvgTF[1] = PERIOD_MN1; }
}

//--- ostatnia ZAMKNIĘTA świeca wyższego TF w chwili zamknięcia świecy bieżącego TF
//    (odpowiednik request.security z lookahead_off na zamkniętych barach)
int HtfLastClosedShift(string sym, ENUM_TIMEFRAMES tf, datetime chartBarClose)
{
   int sh = iBarShift(sym, tf, chartBarClose - 1, false);
   if(sh < 0) return -1;
   datetime o = iTime(sym, tf, sh);
   if(o == 0) return -1;
   if(o + PeriodSeconds(tf) <= chartBarClose) return sh;
   return sh + 1;
}

//====================================================================
//  ATR (RMA) i wolumen
//====================================================================
double g_volSMA = 0; bool g_volSpike = false;
void UpdateAtrVolume()
{
   double tr = H(0) - L(0);
   if(HasBar(1)) tr = MathMax(tr, MathMax(MathAbs(H(0) - Cl(1)), MathAbs(L(0) - Cl(1))));
   if(g_atrCount < ATR_LEN) { g_atrSeed += tr; g_atrCount++; g_atr = (g_atrCount == ATR_LEN) ? g_atrSeed / ATR_LEN : 0; }
   else g_atr = (g_atr * (ATR_LEN - 1) + tr) / ATR_LEN;

   g_volSpike = false;
   if(HasBar(VOL_SMA_LEN - 1))
   {
      double sum = 0;
      for(int k = 0; k < VOL_SMA_LEN; k++) sum += (double)V(k);
      g_volSMA = sum / VOL_SMA_LEN;
      g_volSpike = (double)V(0) > g_volSMA * VOL_MULT;
   }
}

//====================================================================
//  PŁYNNOŚĆ: pivoty bieżącego TF + sweepy
//====================================================================
bool IsPivotHigh(string sym, ENUM_TIMEFRAMES tf, int centerShift, int len)
{
   double c = iHigh(sym, tf, centerShift);
   if(c == 0) return false;
   for(int k = 1; k <= len; k++)
   {
      double a = iHigh(sym, tf, centerShift - k), b = iHigh(sym, tf, centerShift + k);
      if(a == 0 || b == 0 || a >= c || b >= c) return false;
   }
   return true;
}
bool IsPivotLow(string sym, ENUM_TIMEFRAMES tf, int centerShift, int len)
{
   double c = iLow(sym, tf, centerShift);
   if(c == 0) return false;
   for(int k = 1; k <= len; k++)
   {
      double a = iLow(sym, tf, centerShift - k), b = iLow(sym, tf, centerShift + k);
      if(a == 0 || b == 0 || a <= c || b <= c) return false;
   }
   return true;
}

void AddLiq(Liq &arr[], double price)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].price = price; arr[n].swept = false;
   while(ArraySize(arr) > InpLiqMaxLevels) ArrayRemove(arr, 0, 1);
}

void UpdateLiquidity()
{
   if(HasBar(2 * PIVOT_LEN))
   {
      if(IsPivotHigh(_Symbol, _Period, g_s + PIVOT_LEN, PIVOT_LEN)) AddLiq(g_liqBuy, H(PIVOT_LEN));
      if(IsPivotLow(_Symbol, _Period, g_s + PIVOT_LEN, PIVOT_LEN))  AddLiq(g_liqSell, L(PIVOT_LEN));
   }
   // sweep: knot przez poziom i zamknięcie z powrotem
   for(int i = ArraySize(g_liqBuy) - 1; i >= 0; i--)
      if(!g_liqBuy[i].swept && H(0) > g_liqBuy[i].price && Cl(0) < g_liqBuy[i].price)
      { g_liqBuy[i].swept = true; g_lastSweepBuyBar = g_bar; }
   for(int i = ArraySize(g_liqSell) - 1; i >= 0; i--)
      if(!g_liqSell[i].swept && L(0) < g_liqSell[i].price && Cl(0) > g_liqSell[i].price)
      { g_liqSell[i].swept = true; g_lastSweepSellBar = g_bar; }

   // płynność wyższego TF (pivot 2/2 na ostatniej zamkniętej świecy HTF)
   datetime closeT = T(0) + PeriodSeconds(_Period);
   int lc = HtfLastClosedShift(_Symbol, InpLiqTF, closeT);
   if(lc >= 0)
   {
      datetime lcTime = iTime(_Symbol, InpLiqTF, lc);
      if(lcTime != g_htfLiqLastClosed)
      {
         g_htfLiqLastClosed = lcTime;
         if(IsPivotHigh(_Symbol, InpLiqTF, lc + 2, 2)) g_htfBSL = iHigh(_Symbol, InpLiqTF, lc + 2);
         if(IsPivotLow(_Symbol, InpLiqTF, lc + 2, 2))  g_htfSSL = iLow(_Symbol, InpLiqTF, lc + 2);
      }
   }
   if(IsSet(g_htfBSL) && H(0) > g_htfBSL && Cl(0) < g_htfBSL) g_htfSweepBuyBar = g_bar;
   if(IsSet(g_htfSSL) && L(0) < g_htfSSL && Cl(0) > g_htfSSL) g_htfSweepSellBar = g_bar;
}

//====================================================================
//  SESJE (Asia/London) i PDH/PDL/PWH/PWL
//====================================================================
void PushSess(double px, bool isHigh)
{
   if(!InpUseSessionLiq || !IsSet(px)) return;
   int n = ArraySize(g_sess);
   ArrayResize(g_sess, n + 1);
   g_sess[n].price = px; g_sess[n].isHigh = isHigh; g_sess[n].swept = false; g_sess[n].sweptTime = 0;
   while(ArraySize(g_sess) > MAX_SESS_LVLS) ArrayRemove(g_sess, 0, 1);
}

void TrackSession(bool inNow, bool &inPrev, double &hi, double &lo)
{
   if(inNow && !inPrev) { hi = H(0); lo = L(0); }
   else if(inNow)
   {
      if(!IsSet(hi) || H(0) > hi) hi = H(0);
      if(!IsSet(lo) || L(0) < lo) lo = L(0);
   }
   if(!inNow && inPrev) { PushSess(hi, true); PushSess(lo, false); }
   inPrev = inNow;
}

void UpdateSessions()
{
   datetime t = T(0);
   TrackSession(InSession(t, g_asiaStart, g_asiaEnd), g_inAsiaPrev, g_asiaH, g_asiaL);
   TrackSession(InSession(t, g_lonStart, g_lonEnd), g_inLondonPrev, g_lonH, g_lonL);

   // dzień/tydzień według świec D1/W1 brokera (zwykle 00:00 serwera = 17:00 NY)
   datetime dOpen = iTime(_Symbol, PERIOD_D1, iBarShift(_Symbol, PERIOD_D1, t, false));
   datetime wOpen = iTime(_Symbol, PERIOD_W1, iBarShift(_Symbol, PERIOD_W1, t, false));
   if(dOpen != g_dayOpen)
   {
      if(g_dayOpen != 0) { g_pdh = g_curDayH; g_pdl = g_curDayL; g_pdhSwept = false; g_pdlSwept = false; }
      g_dayOpen = dOpen; g_curDayH = H(0); g_curDayL = L(0);
   }
   else { if(H(0) > g_curDayH) g_curDayH = H(0); if(L(0) < g_curDayL) g_curDayL = L(0); }
   if(wOpen != g_weekOpen)
   {
      if(g_weekOpen != 0) { g_pwh = g_curWeekH; g_pwl = g_curWeekL; g_pwhSwept = false; g_pwlSwept = false; }
      g_weekOpen = wOpen; g_curWeekH = H(0); g_curWeekL = L(0);
   }
   else { if(H(0) > g_curWeekH) g_curWeekH = H(0); if(L(0) < g_curWeekL) g_curWeekL = L(0); }

   if(InpUsePDHPDL && IsSet(g_pdh) && !g_pdhSwept && H(0) > g_pdh) g_pdhSwept = true;
   if(InpUsePDHPDL && IsSet(g_pdl) && !g_pdlSwept && L(0) < g_pdl) g_pdlSwept = true;
   if(InpUsePWHPWL && IsSet(g_pwh) && !g_pwhSwept && H(0) > g_pwh) g_pwhSwept = true;
   if(InpUsePWHPWL && IsSet(g_pwl) && !g_pwlSwept && L(0) < g_pwl) g_pwlSwept = true;

   // sweep poziomów sesji (tu wystarczy samo przebicie, bez zamknięcia z powrotem - jak w Pine)
   for(int i = ArraySize(g_sess) - 1; i >= 0; i--)
   {
      if(g_sess[i].swept) continue;
      bool hit = g_sess[i].isHigh ? H(0) > g_sess[i].price : L(0) < g_sess[i].price;
      if(hit) { g_sess[i].swept = true; g_sess[i].sweptTime = t; g_lastSessSweepBar = g_bar; g_lastSessSweepWasHigh = g_sess[i].isHigh; }
   }
   for(int i = ArraySize(g_sess) - 1; i >= 0; i--)
      if(g_sess[i].swept && g_sess[i].sweptTime > 0 && (t - g_sess[i].sweptTime) > 86400) ArrayRemove(g_sess, i, 1);
}

double NearestTarget(bool above, double ref)
{
   double best = EMPTY_VALUE;
   for(int i = 0; i < ArraySize(g_sess); i++)
   {
      if(g_sess[i].swept) continue;
      double p = g_sess[i].price;
      if(above && p > ref)  best = !IsSet(best) ? p : MathMin(best, p);
      if(!above && p < ref) best = !IsSet(best) ? p : MathMax(best, p);
   }
   if(above)
   {
      if(InpUsePDHPDL && !g_pdhSwept && IsSet(g_pdh) && g_pdh > ref) best = !IsSet(best) ? g_pdh : MathMin(best, g_pdh);
      if(InpUsePWHPWL && !g_pwhSwept && IsSet(g_pwh) && g_pwh > ref) best = !IsSet(best) ? g_pwh : MathMin(best, g_pwh);
   }
   else
   {
      if(InpUsePDHPDL && !g_pdlSwept && IsSet(g_pdl) && g_pdl < ref) best = !IsSet(best) ? g_pdl : MathMax(best, g_pdl);
      if(InpUsePWHPWL && !g_pwlSwept && IsSet(g_pwl) && g_pwl < ref) best = !IsSet(best) ? g_pwl : MathMax(best, g_pwl);
   }
   return best;
}

//====================================================================
//  FVG: bieżący TF (dostarczenie) i wyższe TF (PDA)
//====================================================================
void UpdateFvgs()
{
   if(HasBar(2))
   {
      if(L(0) > H(2) && Cl(1) > H(2)) { g_ctfBullTop = L(0); g_ctfBullBot = H(2); }
      if(H(0) < L(2) && Cl(1) < L(2)) { g_ctfBearTop = L(2); g_ctfBearBot = H(0); }
   }
   if(IsSet(g_ctfBullBot) && L(0) <= g_ctfBullTop && L(0) >= g_ctfBullBot) g_lastCtfFvgLong = g_bar;
   if(IsSet(g_ctfBearTop) && H(0) >= g_ctfBearBot && H(0) <= g_ctfBearTop) g_lastCtfFvgShort = g_bar;

   if(!InpUseHtfFvg) return;
   datetime closeT = T(0) + PeriodSeconds(_Period);
   for(int k = 0; k < 2; k++)
   {
      ENUM_TIMEFRAMES tf = g_fvgTF[k];
      int lc = HtfLastClosedShift(_Symbol, tf, closeT);
      if(lc < 0) continue;
      datetime lcTime = iTime(_Symbol, tf, lc);
      if(lcTime == g_fvgLastClosed[k]) continue;
      g_fvgLastClosed[k] = lcTime;
      double h0 = iHigh(_Symbol, tf, lc), l0 = iLow(_Symbol, tf, lc);
      double h2 = iHigh(_Symbol, tf, lc + 2), l2 = iLow(_Symbol, tf, lc + 2);
      if(h2 == 0 || l2 == 0) continue;
      if(l0 > h2) AddFvg(true, l0, h2, k);
      if(h0 < l2) AddFvg(false, l2, h0, k);
   }
   for(int i = ArraySize(g_fvgs) - 1; i >= 0; i--)
   {
      if(L(0) <= g_fvgs[i].top && H(0) >= g_fvgs[i].bot)
      { if(g_fvgs[i].bull) g_lastHtfDeliverLong = g_bar; else g_lastHtfDeliverShort = g_bar; }
      bool mitigated = g_fvgs[i].bull ? Cl(0) < g_fvgs[i].bot : Cl(0) > g_fvgs[i].top;
      if(mitigated) ArrayRemove(g_fvgs, i, 1);
   }
}

void AddFvg(bool bull, double top, double bot, int tfIdx)
{
   if(top <= bot) return;
   int n = ArraySize(g_fvgs);
   ArrayResize(g_fvgs, n + 1);
   g_fvgs[n].top = top; g_fvgs[n].bot = bot; g_fvgs[n].bull = bull; g_fvgs[n].tfIdx = tfIdx;
   // limit na stronę i TF: usuń najstarsze
   while(true)
   {
      int cnt = 0, oldest = -1;
      for(int i = 0; i < ArraySize(g_fvgs); i++)
         if(g_fvgs[i].bull == bull && g_fvgs[i].tfIdx == tfIdx) { cnt++; if(oldest < 0) oldest = i; }
      if(cnt <= InpFvgPerSide || oldest < 0) break;
      ArrayRemove(g_fvgs, oldest, 1);
   }
}

//====================================================================
//  SMT z symbolem skorelowanym
//====================================================================
double CmpAt(datetime t, bool high)
{
   int sh = iBarShift(InpSmtSymbol, _Period, t, false); // jak gaps_off: ostatnia świeca w chwili t lub przed nią
   if(sh < 0) return EMPTY_VALUE;
   double v = high ? iHigh(InpSmtSymbol, _Period, sh) : iLow(InpSmtSymbol, _Period, sh);
   return v == 0 ? EMPTY_VALUE : v;
}

void UpdateSmt()
{
   if(!g_smtOn) return;
   int len = (int)InpSmtSensitivity;
   if(!HasBar(2 * len)) return;
   datetime pt = T(len);
   if(IsPivotLow(_Symbol, _Period, g_s + len, len))
   {
      double px = L(len), cmp = CmpAt(pt, false);
      if(IsSet(g_lastPlPx) && IsSet(g_lastCmpPlPx) && IsSet(cmp))
         if((px > g_lastPlPx && cmp < g_lastCmpPlPx) || (px < g_lastPlPx && cmp > g_lastCmpPlPx)) g_lastBullSmtBar = g_bar - len;
      g_lastPlPx = px; g_lastCmpPlPx = cmp;
   }
   if(IsPivotHigh(_Symbol, _Period, g_s + len, len))
   {
      double px = H(len), cmp = CmpAt(pt, true);
      if(IsSet(g_lastPhPx) && IsSet(g_lastCmpPhPx) && IsSet(cmp))
         if((px < g_lastPhPx && cmp > g_lastCmpPhPx) || (px > g_lastPhPx && cmp < g_lastCmpPhPx)) g_lastBearSmtBar = g_bar - len;
      g_lastPhPx = px; g_lastCmpPhPx = cmp;
   }
}

//====================================================================
//  MASZYNA STANU CISD (cm_* z Pine)
//====================================================================
//--- ekstremum otwarć bieżącej nogi (seria świec w kolorze bias, zaczynając od bieżącej)
void LegExtremeCurrent(int bias, double &extreme, int &extremeBar)
{
   int tempShift = 0;
   extreme = O(0);
   int ct0 = CType(0);
   if(ct0 != 0 && ct0 == bias)
   {
      for(int i = 1; i <= LEG_LOOKBACK && HasBar(i); i++)
      {
         int ct = CType(i);
         if(ct == 0) continue;
         if(ct != bias) break;
         tempShift = i;
         if(bias == 1) { if(O(i) < extreme) extreme = O(i); }
         else          { if(O(i) > extreme) extreme = O(i); }
      }
   }
   int exShift = 0;
   for(int k = 0; k <= tempShift; k++) if(O(k) == extreme) { exShift = k; break; }
   extremeBar = g_bar - exShift;
}

//--- ekstremum otwarć poprzedniej nogi w kolorze bias (szukanie od świecy 1 wstecz)
void LegExtremePrevious(int bias, double &extreme, int &extremeBar)
{
   bool found = false;
   int maxShift = 1;
   extreme = EMPTY_VALUE;
   for(int j = 1; j <= LEG_LOOKBACK && HasBar(j); j++)
   {
      int ct = CType(j);
      if(ct == 0) continue;
      bool matches = (ct == bias);
      if(!found)
      {
         if(matches) { found = true; maxShift = j; extreme = O(j); }
      }
      else
      {
         if(!matches) break;
         maxShift = j;
         if(bias == 1) { if(O(j) < extreme) extreme = O(j); }
         else          { if(O(j) > extreme) extreme = O(j); }
      }
   }
   int exShift = maxShift;
   for(int k = 1; k <= maxShift; k++) if(O(k) == extreme) { exShift = k; break; }
   extremeBar = g_bar - exShift;
}

//--- zwraca: +1 = bycze CISD na tej świecy, -1 = niedźwiedzie, 0 = brak; level/sl wypełniane
int UpdateCisdMachine(double &firedLevel, double &firedSL)
{
   if(g_cmBias == 0 && g_bar > 10)
   {
      int seed = CType(0);
      if(seed == 0) for(int k = 1; k <= 50 && HasBar(k); k++) { seed = CType(k); if(seed != 0) break; }
      if(seed != 0)
      {
         g_cmBias = seed;
         LegExtremeCurrent(seed, g_cmLevel, g_cmLevelBar);
         g_cmPivot = seed == 1 ? H(0) : L(0);
         g_cmPivotBar = g_bar;
      }
   }
   if(g_cmBias == 0) return 0;

   int ct = CType(0);
   if(g_cmBias == 1 && H(0) > g_cmPivot)
   {
      g_cmPivot = H(0); g_cmPivotBar = g_bar;
      if(ct == 1) LegExtremeCurrent(1, g_cmLevel, g_cmLevelBar); else LegExtremePrevious(1, g_cmLevel, g_cmLevelBar);
   }
   else if(g_cmBias == -1 && L(0) < g_cmPivot)
   {
      g_cmPivot = L(0); g_cmPivotBar = g_bar;
      if(ct == -1) LegExtremeCurrent(-1, g_cmLevel, g_cmLevelBar); else LegExtremePrevious(-1, g_cmLevel, g_cmLevelBar);
   }

   bool bullFlip = g_cmBias == -1 && IsSet(g_cmLevel) && Cl(0) > g_cmLevel;
   bool bearFlip = g_cmBias == 1  && IsSet(g_cmLevel) && Cl(0) < g_cmLevel;
   int fired = 0;
   if(bullFlip || bearFlip)
   {
      firedLevel = g_cmLevel;
      firedSL    = g_cmPivot; // w Pine "Wick" i "Body" dają ten sam poziom (pivot sekwencji)
      fired      = bullFlip ? 1 : -1;
      int nb = fired;
      g_cmBias = nb;
      LegExtremeCurrent(nb, g_cmLevel, g_cmLevelBar);
      g_cmPivot = nb == 1 ? H(0) : L(0);
      g_cmPivotBar = g_bar;
   }
   return fired;
}

//====================================================================
//  WALIDACJA I OCENA CISD
//====================================================================
int GateWindow() { return (int)MathMax(InpMaxConfirmBars, 12); }

bool ProximityBlocked(const Cisd &arr[], double level)
{
   if(!InpIgnoreProximity || g_atr <= 0) return false;
   for(int i = 0; i < ArraySize(arr); i++)
      if(!arr[i].invalidated && MathAbs(arr[i].level - level) < g_atr * PROX_ATR) return true;
   return false;
}

int GradeSetup(bool sw, bool pda, bool vol, bool sess, bool tgt, bool smt)
{
   int en = 0, hits = 0;
   if(InpCkSweep)   { en++; hits += sw   ? 1 : 0; }
   if(InpCkPDA)     { en++; hits += pda  ? 1 : 0; }
   if(InpCkVolume)  { en++; hits += vol  ? 1 : 0; }
   if(InpCkSession) { en++; hits += sess ? 1 : 0; }
   if(InpCkTargets) { en++; hits += tgt  ? 1 : 0; }
   if(InpCkSMT)     { en++; hits += smt  ? 1 : 0; }
   double r = en == 0 ? 0.0 : (double)hits / en;
   return r >= 0.95 ? 7 : r >= 0.80 ? 6 : r >= 0.65 ? 5 : r >= 0.45 ? 4 : r >= 0.25 ? 3 : 0;
}

void PushCisd(Cisd &arr[], const Cisd &c)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = c;
   while(ArraySize(arr) > InpSetupsTracked) ArrayRemove(arr, 0, 1);
}

bool TryCreateCisd(bool bull, double level, double sl, Cisd &out)
{
   int W = GateWindow();
   bool allows = bull ? InpBias != BIAS_BEARISH : InpBias != BIAS_BULLISH;
   if(!allows) return false;

   bool swept = bull ? ((InpCtfSweeps && g_bar - g_lastSweepSellBar <= W) || (g_bar - g_htfSweepSellBar <= W))
                     : ((InpCtfSweeps && g_bar - g_lastSweepBuyBar <= W)  || (g_bar - g_htfSweepBuyBar <= W));
   bool fvg   = InpCtfFvgDelivery && (bull ? g_bar - g_lastCtfFvgLong <= W : g_bar - g_lastCtfFvgShort <= W);
   bool smt   = g_smtOn && (bull ? g_bar - g_lastBullSmtBar <= InpSmtLookback + (int)InpSmtSensitivity
                                 : g_bar - g_lastBearSmtBar <= InpSmtLookback + (int)InpSmtSensitivity);
   // UWAGA: w oryginale SMT NIE przepuszcza CISD bez sweepu/FVG (wpływa tylko na ocenę) - zachowujemy to
   if(!(swept || fvg)) { LogReject(bull, level, "brak sweepu płynności i dostarczenia z FVG"); return false; }
   bool blocked = bull ? ProximityBlocked(g_cisdBull, level) : ProximityBlocked(g_cisdBear, level);
   if(blocked) { LogReject(bull, level, "zbyt blisko aktywnego CISD (0.75 ATR)"); return false; }

   bool pda  = bull ? g_bar - g_lastHtfDeliverLong <= W : g_bar - g_lastHtfDeliverShort <= W;
   bool sess = g_bar - g_lastSessSweepBar <= W && (bull ? !g_lastSessSweepWasHigh : g_lastSessSweepWasHigh);
   double tgt = NearestTarget(bull, Cl(0));
   double dist = MathAbs(level - sl);
   bool clear = IsSet(tgt) && dist > 0 && MathAbs(tgt - level) / dist >= InpMinRR;

   out.level = level; out.slPrice = sl; out.bull = bull; out.invalidated = false;
   out.grade = GradeSetup(swept, pda, g_volSpike, sess, clear, smt);
   out.ckSweep = swept; out.ckPDA = pda; out.ckVol = g_volSpike; out.ckSession = sess; out.ckTargets = clear; out.ckSMT = smt;
   out.target = tgt; out.bar = g_bar; out.barTime = T(0);

   if(out.grade < (int)InpMinGradeStore) { LogReject(bull, level, "ocena " + GradeText(out.grade) + " poniżej minimum"); return false; }
   if(bull) PushCisd(g_cisdBull, out); else PushCisd(g_cisdBear, out);
   return true;
}

void MaintainCisd(Cisd &arr[])
{
   for(int i = ArraySize(arr) - 1; i >= 0; i--)
   {
      bool killed = arr[i].bull ? Cl(0) < arr[i].slPrice : Cl(0) > arr[i].slPrice;
      if(killed && !arr[i].invalidated)
      {
         arr[i].invalidated = true;
         if(InpRemoveInvalidated) ArrayRemove(arr, i, 1);
      }
   }
}

void LogReject(bool bull, double level, string why)
{
   if(InpLogRejections && !g_warmup)
      PrintFormat("[CISD] odrzucony %s @%s: %s", bull ? "LONG" : "SHORT", DoubleToString(level, _Digits), why);
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY (kolejność jak w Pine)
//====================================================================
void ProcessBar(int shift)
{
   g_s = shift;
   g_bar++;
   g_newBull = g_newBear = false;

   UpdateAtrVolume();
   UpdateLiquidity();
   UpdateSessions();
   UpdateFvgs();
   UpdateSmt();

   double lvl = 0, sl = 0;
   int fired = UpdateCisdMachine(lvl, sl);
   if(InpTradingEnabled)
   {
      if(fired == 1)  g_newBull = TryCreateCisd(true, lvl, sl, g_sigBull);
      if(fired == -1) g_newBear = TryCreateCisd(false, lvl, sl, g_sigBear);
   }
   MaintainCisd(g_cisdBull);
   MaintainCisd(g_cisdBear);
   g_lastProcessedTime = T(0);
}

//====================================================================
//  HANDEL (SEKCJA A -> wywołania modułów Core/)
//====================================================================
string SigKey() { return StringFormat("CISD_%d_%s_lastSig", InpMagicNumber, _Symbol); }

bool SignalAlreadyTraded(datetime barTime)
{
   // w testerze nie używamy zmiennych globalnych terminala - kolejny przebieg testu zablokowałby sygnały
   if(MQLInfoInteger(MQL_TESTER)) return false;
   return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= barTime;
}
void MarkSignalTraded(datetime barTime) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)barTime); }

int CountMyPositions(int &dir)
{
   ulong tickets[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   dir = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol)
         dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   return n;
}

double CalcVolume(double slDistPoints)
{
   if(InpLotMode == LOT_FIXED) return InpFixedLot;
   return RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, slDistPoints);
}

void HandleSignal(const Cisd &c)
{
   string side = c.bull ? "LONG" : "SHORT";
   if(InpLogSignals)
      PrintFormat("[CISD] %s %s | ocena %s | poziom %s SL %s | sweep=%d PDA=%d vol=%d sesja=%d cel=%d SMT=%d",
                  TimeToString(c.barTime), side, GradeText(c.grade), DoubleToString(c.level, _Digits), DoubleToString(c.slPrice, _Digits),
                  c.ckSweep, c.ckPDA, c.ckVol, c.ckSession, c.ckTargets, c.ckSMT);

   if(c.grade < (int)InpMinGradeTrade) { if(InpLogSignals) Print("[CISD] pominięty: ocena poniżej progu handlu"); return; }
   if(InpUseTradeWindow && !InSession(c.barTime, g_winStart, g_winEnd)) { if(InpLogSignals) Print("[CISD] pominięty: poza oknem handlu"); return; }
   if(SignalAlreadyTraded(c.barTime)) { EE_LogDecision("CISD", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }

   // przeciwna pozycja / zlecenie: zamknij i odwróć albo zignoruj sygnał
   int dir = 0;
   int nOpen = CountMyPositions(dir);
   int pend = PM_CountPendingByMagic(InpMagicNumber, _Symbol);
   int want = c.bull ? 1 : -1;
   if(nOpen > 0 && dir != want)
   {
      if(!InpReverseOnOpposite) { if(InpLogSignals) Print("[CISD] pominięty: otwarta przeciwna pozycja"); return; }
      PM_CloseAllPositions(InpMagicNumber, "reverse_on_opposite_cisd");
      nOpen = CountMyPositions(dir);
      if(nOpen > 0) { EE_LogDecision("CISD", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji - brak odwrócenia"); return; }
   }
   if(pend > 0 && (g_pendingBull != c.bull || InpReverseOnOpposite))
   {
      PM_CancelPendingOrders(InpMagicNumber, _Symbol, "new_cisd_signal");
      g_pendingPlacedBar = -1;
      pend = PM_CountPendingByMagic(InpMagicNumber, _Symbol);
   }
   if(nOpen + pend >= InpMaxSimultaneousPos) { EE_LogDecision("CISD", "BLOCKED_MAX_POSITIONS", "Limit pozycji/zleceń"); return; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double spread = tick.ask - tick.bid;
   double buf = InpSLBufferPoints * _Point;
   // SL: pivot sekwencji + spread (short zamyka się po Ask, long po Bid)
   double sl = c.bull ? c.slPrice - spread - buf : c.slPrice + spread + buf;

   bool useLimit = (InpEntryMode == ENTRY_LIMIT_AT_CISD);
   double entry = c.bull ? tick.ask : tick.bid;
   if(useLimit)
   {
      bool reachable = c.bull ? c.level < tick.ask : c.level > tick.bid;
      if(reachable) entry = c.level;
      else { useLimit = false; EE_LogDecision("CISD", "LIMIT_TO_MARKET", "Cena już na poziomie CISD - wejście rynkowe"); }
   }
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;

   double tp = 0;
   bool liqOk = InpTPMode == TP_LIQUIDITY_OR_RR && IsSet(c.target) &&
                (c.bull ? c.target > entry : c.target < entry) && MathAbs(c.target - entry) / risk >= InpMinRR;
   if(liqOk) tp = c.target;
   else      tp = c.bull ? entry + risk * InpFallbackRR : entry - risk * InpFallbackRR;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   double vol = CalcVolume(risk / _Point);
   if(vol <= 0) return;

   ENUM_ORDER_TYPE mktType = c.bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, mktType)) return;

   string tag = StringFormat("cisd_%s_%d", c.bull ? "L" : "S", (int)c.barTime);
   ExecutionResult res;
   if(useLimit)
   {
      res = PM_PlaceLimitOrder(_Symbol, c.bull ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT, vol, entry, sl, tp, InpMagicNumber, tag);
      if(res == EXEC_CONFIRMED) { g_pendingPlacedBar = g_bar; g_pendingSL = c.slPrice; g_pendingBull = c.bull; }
   }
   else
      res = PM_OpenPosition(_Symbol, mktType, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);

   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %s vol=%.2f entry=%s SL=%s TP=%s (%s) ocena=%s", useLimit ? "LIMIT" : "MARKET", side, vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                               liqOk ? "płynność" : StringFormat("%.1fR", InpFallbackRR), GradeText(c.grade)));
   // EXEC_UNCERTAIN też oznaczamy jako obsłużony - ponowienie mogłoby zdublować pozycję
   if(res != EXEC_FAILED) MarkSignalTraded(c.barTime);
}

//--- zlecenie limit: anuluj po wygaśnięciu lub gdy setup unieważniony (zamknięcie za SL)
void ManagePending()
{
   if(PM_CountPendingByMagic(InpMagicNumber, _Symbol) == 0) { g_pendingPlacedBar = -1; return; }
   if(g_pendingPlacedBar < 0) return;
   bool expired = g_bar - g_pendingPlacedBar >= InpLimitExpiryBars;
   bool invalid = g_pendingBull ? Cl(0) < g_pendingSL : Cl(0) > g_pendingSL;
   if(expired || invalid)
   {
      PM_CancelPendingOrders(InpMagicNumber, _Symbol, expired ? "limit_expired" : "cisd_invalidated");
      g_pendingPlacedBar = -1;
   }
}

//--- zlecenie limit sprzed restartu: przejmij je (SL z zlecenia jako poziom unieważnienia)
void AdoptExistingPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      g_pendingBull = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT;
      g_pendingSL = OrderGetDouble(ORDER_SL);
      g_pendingPlacedBar = g_bar;
      EE_LogDecision(IntegerToString(ticket), "PENDING_ADOPTED", "Zlecenie limit sprzed restartu - wygasanie liczone od teraz");
      return;
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(!ParseSession(InpAsiaSession, g_asiaStart, g_asiaEnd) || !ParseSession(InpLondonSession, g_lonStart, g_lonEnd) ||
      !ParseSession(InpTradeWindow, g_winStart, g_winEnd))
   {
      Print("Błędny format sesji - użyj HHMM-HHMM, np. 0600-1600");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSetupsTracked < 1 || InpLiqMaxLevels < 1 || InpFvgPerSide < 1 || InpFallbackRR <= 0)
      return INIT_PARAMETERS_INCORRECT;

   ResolveFvgTFs();
   g_fvgLastClosed[0] = g_fvgLastClosed[1] = 0;

   g_smtOn = false;
   if(StringLen(InpSmtSymbol) > 0)
   {
      if(SymbolSelect(InpSmtSymbol, true) && iBars(InpSmtSymbol, _Period) > 0) g_smtOn = true;
      else PrintFormat("SMT wyłączone: symbol '%s' niedostępny u brokera (sprawdź nazwę, np. US500.cash)", InpSmtSymbol);
   }

   // stan z serwera ZANIM cokolwiek zrobimy
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu wskaźnika z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   if(start < 50) { Print("Za mało historii do odtworzenia stanu CISD - czekam na dane"); }
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT); // zainicjuj detektor nowej świecy
   AdoptExistingPending();

   EventSetTimer(15);
   PrintFormat("CISD EA %s: przeliczono %d świec, FVG HTF=%s/%s, SMT=%s, aktywne CISD L/S=%d/%d",
               EA_VERSION, start, EnumToString(g_fvgTF[0]), EnumToString(g_fvgTF[1]), g_smtOn ? InpSmtSymbol : "wył.",
               ArraySize(g_cisdBull), ArraySize(g_cisdBear));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   // kill-switch ZAWSZE pierwszy
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct))
   {
      PM_CancelPendingOrders(InpMagicNumber, _Symbol, "kill_switch");
      return;
   }
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;

   // przetwórz wszystkie świece zamknięte od ostatniego razu (zwykle jedną)
   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int s = lastShift - 1; s >= 1; s--)
   {
      ProcessBar(s);
      ManagePending();
      // handlujemy tylko sygnałem z NAJŚWIEŻSZEJ zamkniętej świecy (bez zaległych)
      if(s == 1)
      {
         if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
         if(g_newBull) HandleSignal(g_sigBull);
         if(g_newBear) HandleSignal(g_sigBear);
      }
   }
}

void OnTimer()
{
   RC_ReconcileState(InpMagicNumber);
}

//--- rejestracja pozycji EA w rejestrze reconciliation (także po wypełnieniu limitu)
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
