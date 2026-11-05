//+------------------------------------------------------------------+
//| LongShortPro_EA.mq5                                                |
//| Expert Advisor oparty na wskaźniku "LongShort PRO v2"              |
//| (Pine Script v6) - przeniesiony na MQL5.                          |
//|                                                                    |
//| Stochastic RSI (%K = SMA3(Stoch14(RSI14))) na 2-7 interwałach.    |
//| LONG: wszystkie interwały WŁAŚNIE weszły w wyprzedanie (%K<long). |
//| SHORT: wszystkie WŁAŚNIE weszły w wykupienie (%K>short).          |
//| Transakcja: SL/TP w % ceny, jedna naraz, sygnały w trakcie         |
//| ignorowane. Wyższe interwały: tylko zamknięte świece.              |
//| SEKCJA A: sygnał i presety. SEKCJA B: Include/Core.                 |
//+------------------------------------------------------------------+
#property copyright "LongShort PRO EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_PRESET   { PRESET_BASE = 0, PRESET_MANUAL = 1, PRESET_GOLD_V1 = 2, PRESET_GOLD_V2 = 3, PRESET_CRYPTO = 4, PRESET_NQ = 5 };
enum ENUM_TRADEDIR { TD_LONG = 1, TD_SHORT = -1, TD_BOTH = 0 };
enum ENUM_CROSS    { CROSS_UP = 0, CROSS_DOWN = 1 };
enum ENUM_LOT_MODE { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Preset ==="
input ENUM_PRESET     InpPreset        = PRESET_NQ;    // Preset (NQ = NAS100, zalecany wykres M30)

input group "=== Manual - interwały ==="
input bool            InpEn1           = false;        // TF 1 = interwał wykresu
input bool            InpEn2           = false;        // TF 2
input ENUM_TIMEFRAMES InpTf2           = PERIOD_M5;
input bool            InpEn3           = false;        // TF 3
input ENUM_TIMEFRAMES InpTf3           = PERIOD_M15;
input bool            InpEn4           = false;        // TF 4
input ENUM_TIMEFRAMES InpTf4           = PERIOD_M30;
input bool            InpEn5           = false;        // TF 5
input ENUM_TIMEFRAMES InpTf5           = PERIOD_H4;
input bool            InpEn6           = false;        // TF 6
input ENUM_TIMEFRAMES InpTf6           = PERIOD_D1;
input bool            InpEn7           = false;        // TF 7
input ENUM_TIMEFRAMES InpTf7           = PERIOD_W1;

input group "=== Base / Manual - sygnał ==="
input ENUM_TRADEDIR   InpDirection     = TD_BOTH;      // Kierunek handlu
input double          InpLongLvl       = 20.0;         // Poziom LONG (%K poniżej)
input double          InpShortLvl      = 80.0;         // Poziom SHORT (%K powyżej)

input group "=== Manual - Direction Filter (gdy kierunek = Both) ==="
input bool            InpDfEnable      = false;        // Włącz filtr kierunku
input ENUM_TIMEFRAMES InpDfTf          = PERIOD_H1;    // Interwał filtra
input double          InpDfLongCross   = 20.0;         // LONG ONLY: przecięcie w górę
input double          InpDfUpperZone   = 80.0;         // BOTH: strefa górna
input double          InpDfShortCross  = 70.0;         // SHORT ONLY: przecięcie w dół
input double          InpDfLowerZone   = 20.0;         // BOTH: strefa dolna

input group "=== Manual - Global Filter (gdy kierunek = Long lub Short) ==="
input bool            InpGfEnable      = false;        // Włącz filtr globalny
input ENUM_TIMEFRAMES InpGfTf          = PERIOD_W1;    // Interwał filtra
input ENUM_CROSS      InpGfStartCond   = CROSS_UP;     // Warunek startu
input double          InpGfStartLvl    = 30.0;         // Poziom startu
input ENUM_CROSS      InpGfStopCond    = CROSS_DOWN;   // Warunek stopu
input double          InpGfStopLvl     = 50.0;         // Poziom stopu

input group "=== Manual / Base - wyjście ==="
input double          InpManualSL      = 5.0;          // Stop Loss (%) - Manual i Base (Base nie ma własnego)
input double          InpManualTP      = 10.0;         // Take Profit (%)

input group "=== GOLD - klasy sygnału ==="
input int             InpGoldMinClass  = 0;            // Min. klasa: 0 = wszystkie, 1 = tylko +/++, 2 = tylko ++

input group "=== Ogólne ==="
input int             InpWarmupBars    = 500;          // Rozgrzewka filtrów kierunku (świece wykresu)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int             InpMagicNumber          = 260409;  // Magic number tej strategii
input double          InpMaxSpreadPoints      = 300;     // Maksymalny spread (punkty)
input int             InpSlippagePoints       = 50;      // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE   InpLotMode              = LOT_RISK_PERCENT; // % kapitału (od odległości SL) / stały lot
input double          InpRiskPercentPerTrade  = 1.0;     // % kapitału ryzykowany na transakcję
input double          InpFixedLot             = 0.30;    // Stały lot (gdy tryb = stały)
input double          InpMaxDailyDrawdownPct  = 3.0;     // Kill-switch dzienny (% equity)
input double          InpMaxTotalDrawdownPct  = 10.0;    // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool            InpLogSignals           = true;    // Loguj sygnały i decyzje
input bool            InpLogStates            = false;   // Loguj stan wszystkich interwałów co świecę

//====================================================================
//  STAŁE (jak w oryginale)
//====================================================================
#define RSI_LEN   14
#define STOCH_LEN 14
#define K_SMOOTH  3
#define CALC_BARS 300

//====================================================================
//  KONFIGURACJA (odpowiednik typu Config z Pine)
//====================================================================
struct Cfg
{
   string          tag;
   bool            supported;
   ENUM_TIMEFRAMES tf[7];
   bool            en[7];
   int             dir;          // 1 long, -1 short, 0 oba
   double          longLvl, shortLvl;
   double          slPct, tpPct;
   bool            graded;
   ENUM_TIMEFRAMES ctxTf;
   double          plusLvl, ppLvl;
   bool            useDf, useGf;
};
Cfg g_c;
int    g_dfState = 0;
bool   g_gfOn = false;
string EA_VERSION = "1.00";

//--- interwał w zapisie Pine -> MT5 ("" = wykres; "-" = wyłączony)
bool TfFromStr(string s, ENUM_TIMEFRAMES &tf)
{
   if(s == "") { tf = _Period; return true; }
   if(s == "1")   { tf = PERIOD_M1;  return true; }
   if(s == "2")   { tf = PERIOD_M2;  return true; }
   if(s == "3")   { tf = PERIOD_M3;  return true; }
   if(s == "5")   { tf = PERIOD_M5;  return true; }
   if(s == "15")  { tf = PERIOD_M15; return true; }
   if(s == "30")  { tf = PERIOD_M30; return true; }
   if(s == "60")  { tf = PERIOD_H1;  return true; }
   if(s == "120") { tf = PERIOD_H2;  return true; }
   if(s == "180") { tf = PERIOD_H3;  return true; }
   if(s == "240") { tf = PERIOD_H4;  return true; }
   if(s == "360") { tf = PERIOD_H6;  return true; }
   if(s == "480") { tf = PERIOD_H8;  return true; }
   if(s == "720") { tf = PERIOD_H12; return true; }
   if(s == "D")   { tf = PERIOD_D1;  return true; }
   if(s == "W")   { tf = PERIOD_W1;  return true; }
   if(s == "M")   { tf = PERIOD_MN1; return true; }
   return false;  // 2D, 3D, 2W, 3M - brak w MT5
}

void SetTfs(string a, string b, string d, string e)
{
   string s[4]; s[0] = a; s[1] = b; s[2] = d; s[3] = e;
   for(int i = 0; i < 7; i++) g_c.en[i] = false;
   for(int i = 0; i < 4; i++)
   {
      if(s[i] == "-") continue;
      ENUM_TIMEFRAMES tf;
      if(!TfFromStr(s[i], tf)) { g_c.supported = false; PrintFormat("Interwał '%s' niedostępny w MT5 - profil nieobsługiwany", s[i]); continue; }
      g_c.tf[i] = tf; g_c.en[i] = true;
   }
}

bool SetProfile(string tag, string a, string b, string d, string e, int dir, double lL, double sL, double sl, double tp, string ctx)
{
   SetTfs(a, b, d, e);
   g_c.tag = tag; g_c.dir = dir; g_c.longLvl = lL; g_c.shortLvl = sL; g_c.slPct = sl; g_c.tpPct = tp;
   g_c.graded = ctx != "";
   if(g_c.graded && !TfFromStr(ctx, g_c.ctxTf)) g_c.graded = false;
   return true;
}

bool GoldV1(int sec)
{
   switch(sec)
   {
      case 60:    return SetProfile("1m",  "", "3",   "5",   "15",  0, 20, 80, 0.18, 0.22, "30");
      case 120:   return SetProfile("2m",  "", "5",   "15",  "30",  0, 20, 80, 0.22, 0.28, "60");
      case 180:   return SetProfile("3m",  "", "5",   "15",  "30",  0, 20, 80, 0.25, 0.32, "60");
      case 300:   return SetProfile("5m",  "", "15",  "30",  "60",  0, 20, 80, 0.30, 0.40, "120");
      case 900:   return SetProfile("15m", "", "30",  "60",  "120", 1, 20, 80, 0.45, 0.55, "240");
      case 1800:  return SetProfile("30m", "", "60",  "120", "240", 1, 20, 80, 0.60, 0.70, "240");
      case 3600:  return SetProfile("1H",  "", "120", "240", "360", 0, 25, 75, 0.80, 1.00, "D");
      case 7200:  return SetProfile("2H",  "", "240", "360", "D",   1, 25, 75, 1.00, 1.20, "D");
      case 10800: return SetProfile("3H",  "", "240", "480", "D",   1, 25, 75, 1.20, 1.40, "W");
      case 14400: return SetProfile("4H",  "", "480", "D",   "W",   1, 25, 75, 1.40, 1.70, "W");
   }
   return false;   // 30s, 45s, 45m - brak w MT5
}

bool GoldV2(int sec)
{
   switch(sec)
   {
      case 60:    return SetProfile("1m",  "", "5",   "15",  "-",  0, 15, 85, 0.14, 0.18, "60");
      case 120:   return SetProfile("2m",  "", "5",   "15",  "60", 0, 20, 80, 0.16, 0.22, "60");
      case 180:   return SetProfile("3m",  "", "15",  "30",  "60", 0, 20, 80, 0.18, 0.27, "120");
      case 300:   return SetProfile("5m",  "", "15",  "60",  "-",  0, 20, 80, 0.22, 0.35, "240");
      case 900:   return SetProfile("15m", "", "60",  "240", "-",  0, 20, 80, 0.35, 0.55, "240");
      case 1800:  return SetProfile("30m", "", "60",  "240", "-",  1, 20, 80, 0.45, 0.75, "D");
      case 3600:  return SetProfile("1H",  "", "240", "D",   "-",  1, 20, 80, 0.60, 1.20, "D");
      case 7200:  return SetProfile("2H",  "", "240", "D",   "-",  0, 25, 75, 0.80, 1.60, "W");
      case 10800: return SetProfile("3H",  "", "360", "D",   "-",  1, 25, 75, 1.00, 1.80, "W");
      case 14400: return SetProfile("4H",  "", "D",   "W",   "-",  1, 25, 75, 1.20, 2.40, "W");
   }
   return false;
}

void ApplyBase(int sec)
{
   if(sec <= 180)        SetTfs("1", "3", "5", "-");
   else if(sec <= 300)   SetTfs("3", "5", "15", "-");
   else if(sec <= 900)   SetTfs("5", "15", "30", "-");
   else if(sec <= 1800)  SetTfs("15", "30", "60", "-");
   else if(sec <= 3600)  SetTfs("30", "60", "120", "-");
   else if(sec <= 7200)  SetTfs("60", "120", "240", "-");
   else if(sec <= 14400) SetTfs("120", "240", "480", "-");
   else if(sec <= 21600) SetTfs("240", "360", "720", "-");
   else if(sec <= 43200) SetTfs("360", "720", "D", "-");
   else if(sec <= 86400) SetTfs("360", "D", "2D", "-");
   else if(sec <= 604800) SetTfs("D", "W", "2W", "-");
   else                  SetTfs("W", "M", "3M", "-");
   g_c.tag = "Scanner"; g_c.dir = (int)InpDirection; g_c.longLvl = InpLongLvl; g_c.shortLvl = InpShortLvl;
   g_c.slPct = InpManualSL; g_c.tpPct = InpManualTP;   // Base nie ma SL/TP - EA nie handluje bez SL
}

void ApplyCrypto(int sec)
{
   if(sec <= 60)         SetProfile("Scalp",    "", "3",   "5",   "15", 0, 20, 80, 0.4, 0.7, "");
   else if(sec <= 300)   SetProfile("Intraday", "", "15",  "30",  "60", 0, 20, 80, 0.5, 0.8, "");
   else if(sec <= 1800)  SetProfile("Session",  "", "60",  "120", "240", 0, 20, 80, 1.2, 2.0, "");
   else if(sec <= 14400) SetProfile("Swing",    "", "240", "720", "D",  0, 20, 80, 3.0, 5.0, "");
   else                  SetProfile("Position", "", "3D",  "W",   "-",  0, 20, 80, 8.0, 15.0, "");
}

void ApplyManual()
{
   g_c.tag = "Custom";
   ENUM_TIMEFRAMES tfs[7]; bool ens[7];
   tfs[0] = _Period; tfs[1] = InpTf2; tfs[2] = InpTf3; tfs[3] = InpTf4; tfs[4] = InpTf5; tfs[5] = InpTf6; tfs[6] = InpTf7;
   ens[0] = InpEn1; ens[1] = InpEn2; ens[2] = InpEn3; ens[3] = InpEn4; ens[4] = InpEn5; ens[5] = InpEn6; ens[6] = InpEn7;
   for(int i = 0; i < 7; i++) { g_c.tf[i] = tfs[i] == PERIOD_CURRENT ? _Period : tfs[i]; g_c.en[i] = ens[i]; }
   g_c.dir = (int)InpDirection; g_c.longLvl = InpLongLvl; g_c.shortLvl = InpShortLvl;
   g_c.slPct = InpManualSL; g_c.tpPct = InpManualTP;
   g_c.useDf = InpDfEnable && InpDirection == TD_BOTH;
   g_c.useGf = InpGfEnable && InpDirection != TD_BOTH;
}

bool BuildConfig()
{
   g_c.supported = true; g_c.graded = false; g_c.useDf = false; g_c.useGf = false;
   g_c.plusLvl = 40; g_c.ppLvl = 25;
   for(int i = 0; i < 7; i++) { g_c.tf[i] = _Period; g_c.en[i] = false; }
   int sec = PeriodSeconds(_Period);
   switch(InpPreset)
   {
      case PRESET_BASE:    ApplyBase(sec); break;
      case PRESET_MANUAL:  ApplyManual(); break;
      case PRESET_GOLD_V1: g_c.supported = GoldV1(sec) && g_c.supported; g_c.plusLvl = 40; g_c.ppLvl = 25; break;
      case PRESET_GOLD_V2: g_c.supported = GoldV2(sec) && g_c.supported; g_c.plusLvl = 45; g_c.ppLvl = 30; break;
      case PRESET_CRYPTO:  ApplyCrypto(sec); break;
      default:             SetProfile("30m", "", "60", "240", "-", 1, 20, 80, 1.0, 2.0, "");   // Nasdaq 100 E-mini
   }
   int n = 0;
   for(int i = 0; i < 7; i++) if(g_c.en[i]) n++;
   if(n == 0) { g_c.supported = false; Print("Brak włączonych interwałów"); }
   if(g_c.slPct <= 0 || g_c.tpPct <= 0) { g_c.supported = false; Print("SL i TP muszą być > 0 - EA nie handluje bez SL"); }
   return g_c.supported;
}

//====================================================================
//  STOCHASTIC RSI (%K) NA ZAMKNIĘTEJ ŚWIECY DOWOLNEGO INTERWAŁU
//====================================================================
//--- ostatnia zamknięta świeca interwału tf w chwili zamknięcia świecy wykresu (closeT)
int LastClosedShift(ENUM_TIMEFRAMES tf, datetime closeT)
{
   int sh = iBarShift(_Symbol, tf, closeT - 1, false);
   if(sh < 0) return -1;
   datetime o = iTime(_Symbol, tf, sh);
   if(o == 0) return -1;
   return (o + PeriodSeconds(tf) <= closeT) ? sh : sh + 1;
}

//--- %K na świecy 'shift' interwału tf (k0) i na poprzedniej (k1); false = brak danych (na)
bool MomK(ENUM_TIMEFRAMES tf, int shift, double &k0, double &k1)
{
   double c[];
   ArraySetAsSeries(c, true);
   int n = CopyClose(_Symbol, tf, shift, CALC_BARS, c);
   if(n < RSI_LEN + STOCH_LEN + K_SMOOTH + 5) return false;
   // RSI Wildera (start od SMA), liczony od najstarszej
   double rsi[]; ArrayResize(rsi, n); ArrayInitialize(rsi, EMPTY_VALUE);
   double au = 0, ad = 0; int cnt = 0;
   for(int i = n - 2; i >= 0; i--)
   {
      double ch = c[i] - c[i + 1], u = MathMax(ch, 0), d = MathMax(-ch, 0);
      if(cnt < RSI_LEN) { au += u; ad += d; cnt++; if(cnt == RSI_LEN) { au /= RSI_LEN; ad /= RSI_LEN; } else continue; }
      else { au = (au * (RSI_LEN - 1) + u) / RSI_LEN; ad = (ad * (RSI_LEN - 1) + d) / RSI_LEN; }
      rsi[i] = ad == 0 ? 100 : (au == 0 ? 0 : 100 - 100 / (1 + au / ad));
   }
   // Stochastic z RSI (14) i SMA(3) - potrzebne dla indeksów 0..K_SMOOTH (k0, k1)
   double st[]; ArrayResize(st, K_SMOOTH + 1);
   for(int i = 0; i <= K_SMOOTH; i++)
   {
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int k = 0; k < STOCH_LEN; k++)
      {
         double r = rsi[i + k];
         if(r == EMPTY_VALUE) return false;
         hi = MathMax(hi, r); lo = MathMin(lo, r);
      }
      if(hi == lo) return false;   // dzielenie przez zero = na w Pine
      st[i] = 100.0 * (rsi[i] - lo) / (hi - lo);
   }
   k0 = (st[0] + st[1] + st[2]) / 3.0;
   k1 = (st[1] + st[2] + st[3]) / 3.0;
   return true;
}

//--- %K wszystkich interwałów dla świecy wykresu 'cs' -> stan zgodności
void Alignment(int cs, bool &longAl, bool &shortAl, string &states)
{
   datetime closeT = iTime(_Symbol, _Period, cs) + PeriodSeconds(_Period);
   int nEn = 0, nL = 0, nS = 0;
   states = "";
   for(int i = 0; i < 7; i++)
   {
      if(!g_c.en[i]) continue;
      nEn++;
      int sh = g_c.tf[i] == _Period ? cs : LastClosedShift(g_c.tf[i], closeT);
      double k0, k1;
      int st = 0;
      if(sh >= 0 && MomK(g_c.tf[i], sh, k0, k1)) st = k0 < g_c.longLvl ? 1 : k0 > g_c.shortLvl ? -1 : 0;
      else k0 = -1;
      if(st == 1) nL++;
      if(st == -1) nS++;
      states += StringFormat("%s=%s(%.1f) ", EnumToString(g_c.tf[i]), st == 1 ? "L" : st == -1 ? "S" : "-", k0);
   }
   longAl = nEn > 0 && nL == nEn;
   shortAl = nEn > 0 && nS == nEn;
}

bool Cross(ENUM_CROSS cond, double cur, double prev, double lvl)
{
   return cond == CROSS_UP ? (prev < lvl && cur >= lvl) : (prev > lvl && cur <= lvl);
}

//--- filtry kierunku (stan zależny od historii przecięć) - aktualizacja na świecy wykresu cs
void UpdateFilters(int cs)
{
   datetime closeT = iTime(_Symbol, _Period, cs) + PeriodSeconds(_Period);
   double k0, k1;
   if(g_c.useDf)
   {
      int sh = LastClosedShift(InpDfTf, closeT);
      if(sh >= 0 && MomK(InpDfTf, sh, k0, k1))
      {
         if(Cross(CROSS_UP, k0, k1, InpDfLongCross)) g_dfState = 1;
         if(Cross(CROSS_DOWN, k0, k1, InpDfShortCross)) g_dfState = -1;
         if(k0 > InpDfUpperZone) g_dfState = 0;
         if(k0 < InpDfLowerZone) g_dfState = 0;
      }
   }
   if(g_c.useGf)
   {
      int sh = LastClosedShift(InpGfTf, closeT);
      if(sh >= 0 && MomK(InpGfTf, sh, k0, k1))
      {
         if(Cross(InpGfStartCond, k0, k1, InpGfStartLvl)) g_gfOn = true;
         if(Cross(InpGfStopCond, k0, k1, InpGfStopLvl)) g_gfOn = false;
      }
   }
}

//--- klasa sygnału GOLD (0, 1 = "+", 2 = "++") z interwału kontekstowego
int SignalClass(bool isLong, int cs)
{
   if(!g_c.graded) return 0;
   datetime closeT = iTime(_Symbol, _Period, cs) + PeriodSeconds(_Period);
   int sh = LastClosedShift(g_c.ctxTf, closeT);
   double k0, k1;
   if(sh < 0 || !MomK(g_c.ctxTf, sh, k0, k1)) return 0;
   if(isLong) return (k0 <= g_c.ppLvl && k0 > k1) ? 2 : k0 <= g_c.plusLvl ? 1 : 0;
   return (k0 >= 100.0 - g_c.ppLvl && k0 < k1) ? 2 : k0 >= 100.0 - g_c.plusLvl ? 1 : 0;
}

//====================================================================
//  HANDEL
//====================================================================
bool HasMyPosition()
{
   ulong tickets[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol) return true;
   return false;
}

string SigKey() { return StringFormat("LSP_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void OpenTrade(int d, string tag)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("LSP", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(!RM_CanOpenNewPosition(InpMagicNumber, 1)) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = NormalizeDouble(entry * (1.0 - d * g_c.slPct / 100.0), _Digits);
   double tp = NormalizeDouble(entry * (1.0 + d * g_c.tpPct / 100.0), _Digits);
   double risk = MathAbs(entry - sl);
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string t = StringFormat("lsp_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, t, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(t, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s (-%.2f%%) TP=%s (+%.2f%%)", tag, vol, DoubleToString(entry, _Digits),
                               DoubleToString(sl, _Digits), g_c.slPct, DoubleToString(tp, _Digits), g_c.tpPct));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
}

void OnNewBar()
{
   UpdateFilters(1);
   bool lNow, sNow, lPrev, sPrev;
   string stNow, stPrev;
   Alignment(1, lNow, sNow, stNow);
   Alignment(2, lPrev, sPrev, stPrev);
   if(InpLogStates) Print("[LSP] ", stNow);

   bool allowLong  = g_c.dir != -1 && (!g_c.useDf || g_dfState >= 0) && (!g_c.useGf || g_gfOn);
   bool allowShort = g_c.dir != 1  && (!g_c.useDf || g_dfState <= 0) && (!g_c.useGf || g_gfOn);
   bool longSig  = g_c.supported && allowLong && lNow && !lPrev;
   bool shortSig = g_c.supported && allowShort && sNow && !sPrev;
   if(!longSig && !shortSig) return;

   int d = longSig ? 1 : -1;
   int cls = SignalClass(longSig, 1);
   string tag = (d == 1 ? "LONG" : "SHORT") + (g_c.graded ? (cls == 2 ? "++" : cls == 1 ? "+" : "") : "");
   if(InpLogSignals) PrintFormat("[LSP] sygnał %s | %s", tag, stNow);
   if(g_c.graded && cls < InpGoldMinClass) { if(InpLogSignals) Print("[LSP] pominięty: klasa poniżej minimum"); return; }
   if(HasMyPosition()) { if(InpLogSignals) Print("[LSP] pominięty: trwa transakcja (jak w oryginale)"); return; }
   OpenTrade(d, tag);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(!BuildConfig()) Print("LongShort PRO: profil nieobsługiwany na tym interwale/symbolu - EA nie będzie handlował");
   RC_ReconcileState(InpMagicNumber);
   // rozgrzewka stanu filtrów kierunku (zależą od wcześniejszych przecięć)
   if(g_c.useDf || g_c.useGf)
   {
      int start = (int)MathMin(InpWarmupBars, Bars(_Symbol, _Period) - 3);
      for(int s = start; s >= 1; s--) UpdateFilters(s);
   }
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   string tfs = "";
   for(int i = 0; i < 7; i++) if(g_c.en[i]) tfs += EnumToString(g_c.tf[i]) + " ";
   PrintFormat("LongShort PRO EA %s: preset %s/%s | interwały: %s| kierunek %s | poziomy %.0f/%.0f | SL %.2f%% TP %.2f%%%s",
               EA_VERSION, EnumToString(InpPreset), g_c.tag, tfs, g_c.dir == 1 ? "LONG" : g_c.dir == -1 ? "SHORT" : "OBA",
               g_c.longLvl, g_c.shortLvl, g_c.slPct, g_c.tpPct, g_c.graded ? " | klasy z " + EnumToString(g_c.ctxTf) : "");
   if(InpPreset == PRESET_NQ && PeriodSeconds(_Period) != 1800) Print("Uwaga: preset Nasdaq zalecany na wykresie M30");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;
   OnNewBar();
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
