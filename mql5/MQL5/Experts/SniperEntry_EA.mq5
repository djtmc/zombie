//+------------------------------------------------------------------+
//| SniperEntry_EA.mq5                                                 |
//| Expert Advisor oparty na wskaźniku "Sniper Entry/Exit with SL&TP"  |
//| (Pine v6) - na MQL5.                                               |
//|                                                                    |
//| Sygnał: przecięcie EMA 9 / EMA 21 (naprzemienne). R = 1.5 x ATR14, |
//| SL = 1R, TP1-TP5 = 1R..5R. Opcjonalnie: filtr wyniku dashboardu    |
//| (7 warunków: VWAP, RSI, MACD, EMA, ADX, wolumen, RSI z M5) oraz    |
//| wejście na reteście strefy EMA 9-21.                               |
//| Wyjście: drabinka 5 x 20% z przesuwaniem SL o szczebel.            |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Sniper Entry EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_SN_ENTRY  { ENTRY_CROSS = 0, ENTRY_RETEST = 1 };
enum ENUM_SN_FILTER { FILTER_OFF = 0, FILTER_STRONG_BIAS = 1, FILTER_MIN_SCORE = 2 };
enum ENUM_SN_TP     { TP_LADDER = 0, TP_SINGLE = 1 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Sygnał ==="
input int            InpEmaFast      = 9;            // EMA szybka
input int            InpEmaSlow      = 21;           // EMA wolna
input double         InpAtrMult      = 1.5;          // SL ATR Multiplier (R = x ATR14)
input ENUM_SN_ENTRY  InpEntryMode    = ENTRY_CROSS;  // Wejście: na przecięciu / na reteście strefy EMA
input int            InpRetestBars   = 10;           // Retest: maks. świec od przecięcia
input int            InpWarmupBars   = 2000;         // Ile świec historii przeliczyć przy starcie

input group "=== Filtr dashboardu ==="
input ENUM_SN_FILTER InpFilter       = FILTER_OFF;   // Filtr: wył. / bias STRONG w kierunku / min. wynik
input double         InpMinScorePct  = 71.0;         // Min. wynik w kierunku sygnału (% z 7 warunków)

input group "=== Wyjście ==="
input ENUM_SN_TP     InpTpMode       = TP_LADDER;    // TP: drabinka 5 x 20% / jeden TP
input double         InpSingleTpR    = 2.0;          // Jeden TP: poziom (x R)
input bool           InpStepSl       = true;         // Drabinka: po TPk SL na poprzedni szczebel (TP1 -> wejście)

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
input int           InpMagicNumber          = 260417;   // Magic number tej strategii
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
struct Rma { int n; double sum; double v; bool ready; };
void RmaReset(Rma &r) { r.n = 0; r.sum = 0; r.v = 0; r.ready = false; }
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }
struct Ema { bool ok; double v; };
void EmaUpd(Ema &e, double x, int len) { double a = 2.0 / (len + 1); if(!e.ok) { e.v = x; e.ok = true; } else e.v = a * x + (1 - a) * e.v; }

//====================================================================
//  STAN ALGORYTMU
//====================================================================
Ema    g_e9, g_e21, g_e12, g_e26, g_sig;
Rma    g_atr, g_rsiU, g_rsiD, g_tr14, g_pdm, g_mdm, g_adx;
double g_volHist[];
double g_prevClose = NA, g_prevHigh = NA, g_prevLow = NA, g_prevE9 = NA, g_prevE21 = NA;
double g_vwapPV = 0, g_vwapV = 0; int g_vwapDay = -1;
double g_diP = NA, g_diM = NA;
int    g_rsi5Handle = INVALID_HANDLE;
int    g_state = 0;                 // lastSignalState
int    g_bar = -1, g_crossBar = -1000000;
datetime g_lastProcessedTime = 0;
bool   g_warmup = true;
int    g_sessStart = 0, g_sessEnd = 0;
string EA_VERSION = "1.00";

//--- wynik świecy
bool   g_trigBuy = false, g_trigSell = false, g_retestLong = false, g_retestShort = false;
double g_bullPct = 0, g_bearPct = 0, g_atrNow = 0;
bool   g_pendRetest = false; int g_pendDir = 0;

//--- RSI(14) z ostatniej ZAMKNIĘTEJ świecy M5 w chwili zamknięcia świecy wykresu
double Rsi5At(datetime barOpen)
{
   if(g_rsi5Handle == INVALID_HANDLE) return NA;
   datetime closeT = barOpen + PeriodSeconds(_Period);
   int sh = iBarShift(_Symbol, PERIOD_M5, closeT - 1, false);
   if(sh < 0) return NA;
   if(iTime(_Symbol, PERIOD_M5, sh) + PeriodSeconds(PERIOD_M5) > closeT) sh++;
   double b[];
   if(CopyBuffer(g_rsi5Handle, 0, sh, 1, b) != 1) return NA;
   return b[0];
}

void ProcessBar(int s)
{
   g_bar++;
   g_trigBuy = g_trigSell = g_retestLong = g_retestShort = false;
   double o = iOpen(_Symbol, _Period, s), h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   double v = (double)iTickVolume(_Symbol, _Period, s);
   datetime t = iTime(_Symbol, _Period, s);
   g_lastProcessedTime = t;
   bool hasPrev = !IsNa(g_prevClose);
   double tr = hasPrev ? MathMax(h - l, MathMax(MathAbs(h - g_prevClose), MathAbs(l - g_prevClose))) : h - l;

   EmaUpd(g_e9, c, InpEmaFast); EmaUpd(g_e21, c, InpEmaSlow);
   EmaUpd(g_e12, c, 12); EmaUpd(g_e26, c, 26);
   double macd = g_e12.v - g_e26.v;
   EmaUpd(g_sig, macd, 9);
   RmaUpd(g_atr, tr, 14);
   g_atrNow = g_atr.ready ? g_atr.v : 0;
   if(hasPrev) { double ch = c - g_prevClose; RmaUpd(g_rsiU, MathMax(ch, 0), 14); RmaUpd(g_rsiD, MathMax(-ch, 0), 14); }
   double rsi = (g_rsiU.ready && g_rsiD.ready) ? (g_rsiD.v == 0 ? 100 : (g_rsiU.v == 0 ? 0 : 100 - 100 / (1 + g_rsiU.v / g_rsiD.v))) : NA;

   // ta.dmi(14, 14)
   if(hasPrev)
   {
      double up = h - g_prevHigh, dn = g_prevLow - l;
      RmaUpd(g_tr14, tr, 14);
      RmaUpd(g_pdm, (up > dn && up > 0) ? up : 0, 14);
      RmaUpd(g_mdm, (dn > up && dn > 0) ? dn : 0, 14);
      if(g_tr14.ready && g_tr14.v > 0) { g_diP = 100 * g_pdm.v / g_tr14.v; g_diM = 100 * g_mdm.v / g_tr14.v; }
      if(!IsNa(g_diP)) { double sm = g_diP + g_diM; RmaUpd(g_adx, MathAbs(g_diP - g_diM) / (sm == 0 ? 1 : sm), 14); }
   }
   double adx = g_adx.ready ? 100 * g_adx.v : NA;

   // SMA(volume, 20)
   int nv = ArraySize(g_volHist);
   ArrayResize(g_volHist, nv + 1); g_volHist[nv] = v;
   if(ArraySize(g_volHist) > 20) ArrayRemove(g_volHist, 0, ArraySize(g_volHist) - 20);
   double volAvg = NA;
   if(ArraySize(g_volHist) == 20) { double sm = 0; for(int i = 0; i < 20; i++) sm += g_volHist[i]; volAvg = sm / 20; }

   // VWAP(hlc3) od początku dnia serwera
   MqlDateTime dt; TimeToStruct(t, dt);
   if(dt.day_of_year != g_vwapDay) { g_vwapDay = dt.day_of_year; g_vwapPV = 0; g_vwapV = 0; }
   double hlc3 = (h + l + c) / 3;
   g_vwapPV += hlc3 * v; g_vwapV += v;
   double vwap = g_vwapV > 0 ? g_vwapPV / g_vwapV : hlc3;

   // wynik dashboardu (7 warunków) - tylko na żywo liczony z RSI M5
   double rsi5 = g_warmup ? NA : Rsi5At(t);
   int b = 0, r = 0;
   b += c > vwap ? 1 : 0;                         r += c < vwap ? 1 : 0;
   b += (!IsNa(rsi) && rsi > 50) ? 1 : 0;         r += (!IsNa(rsi) && rsi < 50) ? 1 : 0;
   b += macd > g_sig.v ? 1 : 0;                   r += macd < g_sig.v ? 1 : 0;
   b += g_e9.v > g_e21.v ? 1 : 0;                 r += g_e9.v < g_e21.v ? 1 : 0;
   b += (!IsNa(adx) && adx > 25 && c > g_e9.v) ? 1 : 0;  r += (!IsNa(adx) && adx > 25 && c < g_e9.v) ? 1 : 0;
   b += (!IsNa(volAvg) && v > volAvg && c > o) ? 1 : 0;  r += (!IsNa(volAvg) && v > volAvg && c < o) ? 1 : 0;
   b += (!IsNa(rsi5) && rsi5 > 50) ? 1 : 0;       r += (!IsNa(rsi5) && rsi5 < 50) ? 1 : 0;
   g_bullPct = b / 7.0 * 100; g_bearPct = r / 7.0 * 100;

   // przecięcie EMA 9/21 i stan naprzemienny
   bool buyCond  = !IsNa(g_prevE9) && g_e9.v > g_e21.v && g_prevE9 <= g_prevE21;
   bool sellCond = !IsNa(g_prevE9) && g_e9.v < g_e21.v && g_prevE9 >= g_prevE21;
   g_trigBuy  = buyCond && g_state <= 0;
   g_trigSell = sellCond && g_state >= 0;
   if(g_trigBuy || g_trigSell) { g_state = g_trigBuy ? 1 : -1; g_crossBar = g_bar; }

   // retest: świeca z low/high w strefie EMA 9-21 po sygnale (świeca przecięcia się nie liczy)
   if(g_bar > g_crossBar && g_bar - g_crossBar <= InpRetestBars)
   {
      g_retestLong  = g_state == 1 && l <= g_e9.v && l > g_e21.v;
      g_retestShort = g_state == -1 && h >= g_e9.v && h < g_e21.v;
   }

   g_prevE9 = g_e9.v; g_prevE21 = g_e21.v;
   g_prevClose = c; g_prevHigh = h; g_prevLow = l;
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
//  PLAN POZYCJI (zmienne globalne terminala, klucz = ticket)
//====================================================================
string GvRoot() { return "SNIPER_" + IntegerToString(InpMagicNumber) + "_"; }
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
   while(t != 0 && guard++ < 5) { if(PM_ClosePosition(t, reason)) GvClear(t); t = MyPosition(dir); }
   return t == 0;
}

//--- drabinka: po TPk pozostaje start x (1 - 0.2k); SL przesuwany na poziom k-1 (0 = wejście)
void ManageLadder()
{
   if(InpTpMode != TP_LADDER) return;
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double initVol = GvGet(t, "vol"), entry = GvGet(t, "entry"), R = GvGet(t, "R");
   if(initVol == EMPTY_VALUE || entry == EMPTY_VALUE || R == EMPTY_VALUE) return;
   double stage = GvGet(t, "stage"); if(stage == EMPTY_VALUE) stage = 0;
   if(stage >= 4) return;                                  // TP5 u brokera
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double px = dir == 1 ? tick.bid : tick.ask;
   int reached = (int)stage;
   for(int k = (int)stage + 1; k <= 4; k++) if((px - (entry + dir * k * R)) * dir >= 0) reached = k; else break;
   if(reached <= stage) return;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double remainTarget = MathFloor(initVol * (1.0 - 0.2 * reached) / step + 1e-9) * step;
   if(remainTarget < vMin - 1e-9) remainTarget = 0;        // reszta poniżej min. lota - zamknij całość
   double cur = PositionGetDouble(POSITION_VOLUME), closeVol = cur - remainTarget;
   if(closeVol >= vMin - 1e-9)
   {
      bool ok = remainTarget <= 0 ? PM_ClosePosition(t, "tp" + IntegerToString(reached)) : PM_ClosePartial(t, closeVol, "tp" + IntegerToString(reached));
      if(!ok) return;
      if(InpLogSignals) PrintFormat("[SNIPER] TP%d (%.1fR) - zamykam %.2f z %.2f", reached, (double)reached, closeVol, cur);
   }
   if(!PositionSelectByTicket(t)) { GvClear(t); return; }
   GvSet(t, "stage", reached);
   if(InpStepSl)
   {
      double newSl = NormalizeDouble(entry + dir * (reached - 1) * R, _Digits);
      double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool better = dir == 1 ? (sl == 0 || newSl > sl + _Point) : (sl == 0 || newSl < sl - _Point);
      bool valid = dir == 1 ? newSl < tick.bid - minDist : newSl > tick.ask + minDist;
      if(better && valid) PM_ModifyStops(t, newSl, tp);
   }
}

string SigKey() { return StringFormat("SNIPERSIG_%d_%s", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

bool FilterPass(int d)
{
   double mine = d == 1 ? g_bullPct : g_bearPct, other = d == 1 ? g_bearPct : g_bullPct;
   if(InpFilter == FILTER_STRONG_BIAS) return mine - other >= 40;
   if(InpFilter == FILTER_MIN_SCORE) return mine >= InpMinScorePct;
   return true;
}

void OpenTrade(int d, string why)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(!InSession(iTime(_Symbol, _Period, 0))) { if(InpLogSignals) Print("[SNIPER] pominięty: poza oknem sesji"); return; }
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("SNIPER", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(g_atrNow <= 0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double R = g_atrNow * InpAtrMult;
   double sl = NormalizeDouble(entry - d * R, _Digits);
   double tp = NormalizeDouble(entry + d * (InpTpMode == TP_LADDER ? 5.0 : InpSingleTpR) * R, _Digits);
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, R / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string tag = StringFormat("sniper_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s (%s) vol=%.2f entry=%s SL=%s TP=%s R=%s | bull %.0f%% / bear %.0f%%", d == 1 ? "LONG" : "SHORT", why, vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), DoubleToString(R, _Digits), g_bullPct, g_bearPct));
   if(res == EXEC_FAILED) return;
   MarkSignalTraded(sigTime);
   int pd;
   ulong t = MyPosition(pd);
   if(t != 0 && PositionSelectByTicket(t))
   {
      GvSet(t, "vol", PositionGetDouble(POSITION_VOLUME));
      GvSet(t, "entry", PositionGetDouble(POSITION_PRICE_OPEN));
      GvSet(t, "R", R);
      GvSet(t, "stage", 0);
   }
}

void OnBarClosed()
{
   int dir;
   ulong t = MyPosition(dir);
   int cross = g_trigBuy ? 1 : (g_trigSell ? -1 : 0);
   if(cross != 0)
   {
      if(InpLogSignals) PrintFormat("[SNIPER] przecięcie EMA %d/%d -> %s | bull %.0f%% / bear %.0f%%", InpEmaFast, InpEmaSlow, cross == 1 ? "BUY" : "SELL", g_bullPct, g_bearPct);
      g_pendRetest = false;
      // przeciwne przecięcie zawsze zamyka pozycję
      if(t != 0 && dir != cross) { CloseMine("opposite_cross"); t = MyPosition(dir); }
      bool pass = FilterPass(cross);
      if(!pass) { if(InpLogSignals) Print("[SNIPER] sygnał odrzucony przez filtr dashboardu"); return; }
      if(InpEntryMode == ENTRY_RETEST) { g_pendRetest = true; g_pendDir = cross; if(InpLogSignals) Print("[SNIPER] czekam na retest strefy EMA"); return; }
      if(t == 0) OpenTrade(cross, "przecięcie");
      return;
   }
   // tryb retestu
   if(g_pendRetest)
   {
      if(g_bar - g_crossBar > InpRetestBars || g_state != g_pendDir) { g_pendRetest = false; if(InpLogSignals) Print("[SNIPER] brak retestu w oknie"); return; }
      bool hit = g_pendDir == 1 ? g_retestLong : g_retestShort;
      if(hit && t == 0) { g_pendRetest = false; OpenTrade(g_pendDir, "retest EMA"); }
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpEmaFast < 1 || InpEmaSlow <= InpEmaFast || InpAtrMult <= 0 || InpSingleTpR <= 0 || InpWarmupBars < 300) return INIT_PARAMETERS_INCORRECT;
   g_sessStart = ParseHHMM(InpSessStart); g_sessEnd = ParseHHMM(InpSessEnd);
   if(g_sessStart < 0 || g_sessEnd < 0) { Print("SNIPER: błędny format godzin sesji (HH:MM)"); return INIT_PARAMETERS_INCORRECT; }
   g_rsi5Handle = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   if(g_rsi5Handle == INVALID_HANDLE) return INIT_FAILED;
   ZeroMemory(g_e9); ZeroMemory(g_e21); ZeroMemory(g_e12); ZeroMemory(g_e26); ZeroMemory(g_sig);
   RmaReset(g_atr); RmaReset(g_rsiU); RmaReset(g_rsiD); RmaReset(g_tr14); RmaReset(g_pdm); RmaReset(g_mdm); RmaReset(g_adx);
   ArrayResize(g_volHist, 0);
   RC_ReconcileState(InpMagicNumber);
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Sniper Entry EA %s: przeliczono %d świec | stan %s | wejście %s | filtr %s | TP %s",
               EA_VERSION, start, g_state == 1 ? "BUY" : g_state == -1 ? "SELL" : "brak", EnumToString(InpEntryMode), EnumToString(InpFilter), EnumToString(InpTpMode));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_rsi5Handle != INVALID_HANDLE) IndicatorRelease(g_rsi5Handle);
}

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpSessionFilter && InpFlatAtSessionEnd && !InSession(TimeCurrent()))
   {
      int d;
      if(MyPosition(d) != 0) { if(InpLogSignals) Print("[SNIPER] koniec okna sesji - zamykam pozycję"); CloseMine("session_end"); }
   }
   ManageLadder();
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
