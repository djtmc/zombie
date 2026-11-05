//+------------------------------------------------------------------+
//| SFX_Supertrend221_EA.mq5                                           |
//| Expert Advisor oparty na strategii Pine "Flux Charts - SFX Algo    |
//| [2.2.1]" (strategy(), Pine v6) - na MQL5.                          |
//| Uwaga: to inny skrypt niż "SFX Algo" z SFX_Algo_EA.mq5.            |
//|                                                                    |
//| Supertrend(15, 5) na hl2: crossover close/st = LONG, crossunder =  |
//| SHORT, przeciwny sygnał zamyka i odwraca. TP1-4 = 1.5/3/5/9 x      |
//| ATR(14) ze świecy sygnału (30/30/30/10%), SL = 6 x ATR(14).        |
//| Opcjonalny filtr konsolidacji (ATR(5) vs MA, RSI(7)).              |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "SFX Supertrend 2.2.1 EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_SFX_FILTER { FLT_ATR = 0, FLT_RSI = 1, FLT_ATR_OR_RSI = 2, FLT_ATR_AND_RSI = 3, FLT_NONE = 4,
                       FLT_SIDEWAYS_OR = 5, FLT_SIDEWAYS_AND = 6 };
enum ENUM_SFX_TPSL   { TPSL_ATR = 0, TPSL_PERCENT = 1 };
enum ENUM_SFX_MA     { ATRMA_EMA = 0, ATRMA_SMA = 1 };
enum ENUM_SFX_SLEXEC { SLEXEC_BROKER = 0, SLEXEC_ORIGINAL = 1 };
enum ENUM_LOT_MODE   { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Strategia ==="
input bool            InpLongSide     = true;        // Long Side
input bool            InpShortSide    = true;        // Short Side
input int             InpStPeriod     = 15;          // Supertrend: okres ATR
input int             InpStMult       = 5;           // Supertrend: mnożnik
input ENUM_SFX_FILTER InpFilter       = FLT_NONE;    // Sideways Filtering (domyślnie bez filtra)
input int             InpWarmupBars   = 2000;        // Ile świec historii przeliczyć przy starcie

input group "=== Filtr konsolidacji ==="
input int             InpRsiLen       = 7;           // RSI: długość
input int             InpRsiTop       = 45;          // RSI: TOP Limit
input int             InpRsiBot       = 10;          // RSI: BOT Limit
input int             InpAtrLen       = 5;           // ATR: długość
input ENUM_SFX_MA     InpAtrMaType    = ATRMA_EMA;   // ATR: typ średniej
input int             InpAtrMaLen     = 5;           // ATR: długość średniej

input group "=== TP / SL ==="
input ENUM_SFX_TPSL   InpTpSlType     = TPSL_ATR;    // TP SL Type: ATR(14) / % ceny
input double          InpTp1Atr       = 1.5;         // TP1 (x ATR)
input double          InpTp2Atr       = 3.0;         // TP2 (x ATR)
input double          InpTp3Atr       = 5.0;         // TP3 (x ATR)
input double          InpTp4Atr       = 9.0;         // TP4 (x ATR)
input double          InpSlAtr        = 6.0;         // SL (x ATR)
input double          InpTp1Pct       = 2.0;         // TP1 (%)
input double          InpTp2Pct       = 4.0;         // TP2 (%)
input double          InpTp3Pct       = 6.0;         // TP3 (%)
input double          InpTp4Pct       = 12.0;        // TP4 (%)
input double          InpSlPct        = 3.0;         // SL (%)
input int             InpQty1         = 30;          // Wolumen na TP1 (%)
input int             InpQty2         = 30;          // Wolumen na TP2 (%)
input int             InpQty3         = 30;          // Wolumen na TP3 (%) - reszta na TP4
input ENUM_SFX_SLEXEC InpSlExec       = SLEXEC_BROKER; // SL: stop u brokera / jak oryginał (wyjście po świecy z low za SL)
input double          InpSlEmergencyAtr = 1.0;       // Tryb oryginału: twardy SL o tyle x ATR dalej
input bool            InpBEAfterTp1   = false;       // Break-even po TP1 (oryginał tego nie robi)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260416;   // Magic number tej strategii
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

//====================================================================
//  STAN ALGORYTMU
//====================================================================
Rma      g_atrSt, g_atr14, g_atrF, g_rsiUp, g_rsiDn;
double   g_atrMaEma = NA, g_atrHist[];
double   g_up = NA, g_dn = NA, g_st = NA, g_prevClose = NA;
int      g_trend = 1;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
string   EA_VERSION = "1.00";

//--- wynik ostatnio przetworzonej świecy
bool   g_buySig = false, g_sellSig = false, g_trendOk = false;
double g_sigClose = 0, g_sigAtr = 0, g_lastLow = 0, g_lastHigh = 0, g_lastClose = 0;
double g_rsiNow = NA, g_atraNow = NA, g_atrMaNow = NA;

double Truncate2(double x) { return (double)((long)(x * 100.0)) / 100.0; }

void ProcessBar(int s)
{
   g_buySig = g_sellSig = false;
   double h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);
   g_lastLow = l; g_lastHigh = h; g_lastClose = c;
   bool hasPrev = !IsNa(g_prevClose);
   double pc = g_prevClose;
   double tr = hasPrev ? MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc))) : h - l;
   RmaUpd(g_atrSt, tr, InpStPeriod);
   RmaUpd(g_atr14, tr, 14);
   RmaUpd(g_atrF, tr, InpAtrLen);

   // filtr: ATR(5) vs EMA/SMA(5), RSI(7) obcięty do 2 miejsc
   g_atraNow = g_atrF.ready ? g_atrF.v : NA;
   g_atrMaNow = NA;
   if(!IsNa(g_atraNow))
   {
      double a = 2.0 / (InpAtrMaLen + 1);
      g_atrMaEma = IsNa(g_atrMaEma) ? g_atraNow : a * g_atraNow + (1 - a) * g_atrMaEma;
      int n = ArraySize(g_atrHist);
      ArrayResize(g_atrHist, n + 1); g_atrHist[n] = g_atraNow;
      if(ArraySize(g_atrHist) > InpAtrMaLen) ArrayRemove(g_atrHist, 0, ArraySize(g_atrHist) - InpAtrMaLen);
      if(InpAtrMaType == ATRMA_EMA) g_atrMaNow = g_atrMaEma;
      else if(ArraySize(g_atrHist) == InpAtrMaLen) { double sm = 0; for(int i = 0; i < InpAtrMaLen; i++) sm += g_atrHist[i]; g_atrMaNow = sm / InpAtrMaLen; }
   }
   if(hasPrev) { double ch = c - pc; RmaUpd(g_rsiUp, MathMax(ch, 0), InpRsiLen); RmaUpd(g_rsiDn, MathMax(-ch, 0), InpRsiLen); }
   g_rsiNow = (g_rsiUp.ready && g_rsiDn.ready) ? Truncate2(g_rsiDn.v == 0 ? 100 : (g_rsiUp.v == 0 ? 0 : 100 - 100 / (1 + g_rsiUp.v / g_rsiDn.v))) : NA;

   bool atrOk = !IsNa(g_atraNow) && !IsNa(g_atrMaNow);
   bool rsiOk = !IsNa(g_rsiNow);
   bool c1 = atrOk && g_atraNow >= g_atrMaNow;
   bool c2 = rsiOk && (g_rsiNow > InpRsiTop || g_rsiNow < InpRsiBot);
   bool s1 = atrOk && g_atraNow <= g_atrMaNow;
   bool s2 = rsiOk && g_rsiNow < InpRsiTop && g_rsiNow > InpRsiBot;
   switch(InpFilter)
   {
      case FLT_ATR:          g_trendOk = c1; break;
      case FLT_RSI:          g_trendOk = c2; break;
      case FLT_ATR_OR_RSI:   g_trendOk = c1 || c2; break;
      case FLT_ATR_AND_RSI:  g_trendOk = c1 && c2; break;
      case FLT_SIDEWAYS_OR:  g_trendOk = s1 || s2; break;
      case FLT_SIDEWAYS_AND: g_trendOk = s1 && s2; break;
      default:               g_trendOk = rsiOk && g_rsiNow > 0; break;   // "No Filtering" = RSI > 0
   }

   // Supertrend (hl2, ATR Wildera) jak w Pine
   double stPrev = g_st;
   if(g_atrSt.ready)
   {
      double hl2 = (h + l) / 2;
      double up = hl2 - InpStMult * g_atrSt.v, dn = hl2 + InpStMult * g_atrSt.v;
      double up1 = IsNa(g_up) ? up : g_up, dn1 = IsNa(g_dn) ? dn : g_dn;
      if(hasPrev && pc > up1) up = MathMax(up, up1);
      if(hasPrev && pc < dn1) dn = MathMin(dn, dn1);
      g_trend = (g_trend == -1 && c > dn1) ? 1 : (g_trend == 1 && c < up1) ? -1 : g_trend;
      g_up = up; g_dn = dn;
      g_st = g_trend == 1 ? up : dn;
      if(!IsNa(stPrev) && hasPrev)
      {
         g_buySig  = c > g_st && pc <= stPrev;     // ta.crossover(close, st)
         g_sellSig = c < g_st && pc >= stPrev;     // ta.crossunder(close, st)
      }
   }
   g_sigClose = c;
   g_sigAtr = g_atr14.ready ? g_atr14.v : 0;
   g_prevClose = c;
}

//====================================================================
//  PLAN POZYCJI (zmienne globalne terminala, klucz = ticket)
//====================================================================
string GvRoot() { return "SFXST_" + IntegerToString(InpMagicNumber) + "_"; }
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

//--- częściowe TP: po dotknięciu TPk pozostały wolumen = start x (1 - suma % do TPk)
void ManagePartials()
{
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t)) return;
   double initVol = GvGet(t, "vol");
   if(initVol == EMPTY_VALUE) return;                  // pozycja bez planu (np. sprzed restartu bez GV)
   double stage = GvGet(t, "stage"); if(stage == EMPTY_VALUE) stage = 0;
   if(stage >= 3) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double px = dir == 1 ? tick.bid : tick.ask;
   int reached = (int)stage;
   for(int k = (int)stage + 1; k <= 3; k++)
   {
      double lvl = GvGet(t, "tp" + IntegerToString(k));
      if(lvl != EMPTY_VALUE && (px - lvl) * dir >= 0) reached = k; else break;
   }
   if(reached <= stage) return;
   double cum = reached >= 1 ? InpQty1 : 0;
   if(reached >= 2) cum += InpQty2;
   if(reached >= 3) cum += InpQty3;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double remainTarget = MathFloor(initVol * (100.0 - cum) / 100.0 / step + 1e-9) * step;
   if(remainTarget < vMin - 1e-9 && reached >= 3) remainTarget = 0;   // ostatnia część za mała - zamknij całość na TP3
   double cur = PositionGetDouble(POSITION_VOLUME);
   double closeVol = cur - remainTarget;
   bool ok = true;
   if(closeVol >= vMin - 1e-9)
   {
      if(remainTarget <= 0) ok = PM_ClosePosition(t, "tp" + IntegerToString(reached));
      else ok = PM_ClosePartial(t, closeVol, "tp" + IntegerToString(reached));
      if(InpLogSignals) PrintFormat("[SFXST] TP%d osiągnięty - zamykam %.2f z %.2f", reached, closeVol, cur);
   }
   else if(reached < 3) return;                         // część poniżej min. lota - łączy się z następnym TP
   if(!ok) return;
   if(!PositionSelectByTicket(t)) { GvClear(t); return; }
   GvSet(t, "stage", reached);
   if(InpBEAfterTp1 && reached >= 1)
   {
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool better = dir == 1 ? (sl == 0 || op > sl + _Point) : (sl == 0 || op < sl - _Point);
      bool valid = dir == 1 ? op < tick.bid - minDist : op > tick.ask + minDist;
      if(better && valid) PM_ModifyStops(t, NormalizeDouble(op, _Digits), tp);
   }
}

string SigKey() { return StringFormat("SFXSTSIG_%d_%s", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void OpenTrade(int d)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("SFXST", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   double cb = g_sigClose, a = g_sigAtr;
   if(InpTpSlType == TPSL_ATR && a <= 0) return;
   double tp[4], sl;
   if(InpTpSlType == TPSL_ATR)
   {
      tp[0] = cb + d * a * InpTp1Atr; tp[1] = cb + d * a * InpTp2Atr; tp[2] = cb + d * a * InpTp3Atr; tp[3] = cb + d * a * InpTp4Atr;
      sl = cb - d * a * InpSlAtr;
   }
   else
   {
      tp[0] = cb * (1 + d * InpTp1Pct / 100); tp[1] = cb * (1 + d * InpTp2Pct / 100); tp[2] = cb * (1 + d * InpTp3Pct / 100); tp[3] = cb * (1 + d * InpTp4Pct / 100);
      sl = cb * (1 - d * InpSlPct / 100);
   }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   if((entry - sl) * d <= 0 || (tp[0] - entry) * d <= 0) { if(InpLogSignals) Print("[SFXST] pominięty: cena już za SL lub TP1"); return; }
   double atrRef = a > 0 ? a : MathAbs(entry - sl) / 6.0;
   double brokerSl = InpSlExec == SLEXEC_ORIGINAL ? sl - d * InpSlEmergencyAtr * atrRef : sl;
   brokerSl = NormalizeDouble(brokerSl, _Digits);
   double brokerTp = NormalizeDouble(tp[3], _Digits);
   double risk = MathAbs(entry - brokerSl);
   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;
   string tag = StringFormat("sfxst_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, brokerSl, brokerTp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s%s TP1-4=%s/%s/%s/%s ATR14=%s", d == 1 ? "LONG" : "SHORT", vol, DoubleToString(entry, _Digits),
                               DoubleToString(sl, _Digits), InpSlExec == SLEXEC_ORIGINAL ? " (twardy " + DoubleToString(brokerSl, _Digits) + ")" : "",
                               DoubleToString(tp[0], _Digits), DoubleToString(tp[1], _Digits), DoubleToString(tp[2], _Digits), DoubleToString(tp[3], _Digits),
                               DoubleToString(a, _Digits)));
   if(res == EXEC_FAILED) return;
   MarkSignalTraded(sigTime);
   int pd;
   ulong t = MyPosition(pd);
   if(t != 0 && PositionSelectByTicket(t))
   {
      GvSet(t, "vol", PositionGetDouble(POSITION_VOLUME));
      GvSet(t, "stage", 0);
      GvSet(t, "sl", sl);
      for(int k = 0; k < 3; k++) GvSet(t, "tp" + IntegerToString(k + 1), tp[k]);
   }
}

void OnBarClosed()
{
   int dir;
   ulong t = MyPosition(dir);
   // wyjście: przeciwny crossover (zawsze, także gdy strona przeciwna wyłączona)
   if(t != 0 && ((dir == 1 && g_sellSig) || (dir == -1 && g_buySig)))
   {
      if(InpLogSignals) Print("[SFXST] przeciwne przecięcie Supertrendu - zamykam pozycję");
      CloseMine("opposite_cross");
      t = MyPosition(dir);
   }
   // tryb oryginału: low/high świecy za SL -> wyjście rynkowe po zamknięciu świecy
   if(t != 0 && InpSlExec == SLEXEC_ORIGINAL)
   {
      double sl = GvGet(t, "sl");
      if(sl != EMPTY_VALUE && ((dir == 1 && g_lastLow < sl) || (dir == -1 && g_lastHigh > sl)))
      {
         if(InpLogSignals) Print("[SFXST] świeca przebiła SL - wyjście rynkowe (jak w oryginale)");
         CloseMine("sl_on_close");
         t = MyPosition(dir);
      }
   }
   // wejście
   int d = g_buySig ? 1 : (g_sellSig ? -1 : 0);
   if(d == 0) return;
   bool sideOk = d == 1 ? InpLongSide : InpShortSide;
   if(InpLogSignals) PrintFormat("[SFXST] sygnał %s | ST %s | RSI(7) %s | filtr %s", d == 1 ? "LONG" : "SHORT", DoubleToString(g_st, _Digits),
                                 IsNa(g_rsiNow) ? "-" : DoubleToString(g_rsiNow, 2), g_trendOk ? "ok" : "odrzuca");
   if(!sideOk || !g_trendOk) return;
   if(t != 0 && dir == d) { if(InpLogSignals) Print("[SFXST] pominięty: pozycja w tym kierunku już otwarta"); return; }
   if(t != 0 && !CloseMine("reverse_on_opposite")) { EE_LogDecision("SFXST", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   OpenTrade(d);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpStPeriod < 1 || InpStMult < 1 || InpQty1 + InpQty2 + InpQty3 > 100 || InpQty1 < 0 || InpQty2 < 0 || InpQty3 < 0 || InpWarmupBars < 300)
      return INIT_PARAMETERS_INCORRECT;
   RmaReset(g_atrSt); RmaReset(g_atr14); RmaReset(g_atrF); RmaReset(g_rsiUp); RmaReset(g_rsiDn);
   ArrayResize(g_atrHist, 0);
   RC_ReconcileState(InpMagicNumber);
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("SFX Supertrend 2.2.1 EA %s: przeliczono %d świec | trend %s | ST %s | filtr %s | TP/SL %s | SL %s",
               EA_VERSION, start, g_trend == 1 ? "UP" : "DOWN", IsNa(g_st) ? "-" : DoubleToString(g_st, _Digits),
               EnumToString(InpFilter), EnumToString(InpTpSlType), EnumToString(InpSlExec));
   int pd;
   ulong t = MyPosition(pd);
   if(t != 0 && GvGet(t, "vol") == EMPTY_VALUE) Print("Uwaga: otwarta pozycja bez zapisanego planu TP1-3 - zarządzają nią SL/TP4 u brokera i przeciwny sygnał");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   ManagePartials();
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
