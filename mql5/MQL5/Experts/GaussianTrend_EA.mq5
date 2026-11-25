//+------------------------------------------------------------------+
//| GaussianTrend_EA.mq5                                               |
//| Expert Advisor oparty na wskaźniku "Gaussian Filter Trend"         |
//| [QuantAlgo] (Pine Script v6) - przeniesiony na MQL5.               |
//|                                                                    |
//| Linia trendu: filtr Gaussa (4 etapy) + pasmo ATR o szerokości      |
//| adaptowanej przez Efficiency Ratio. Linia stoi, dopóki filtr nie   |
//| wyjdzie poza pasmo; skok w górę = trend byczy, w dół = niedźwiedzi.|
//|                                                                    |
//| Handel: zawsze w rynku (zmiana trendu odwraca pozycję), SL na       |
//| linii trendu z buforem i trailing za linią. Zamknięte świece.      |
//| SEKCJA A: sygnał i trailing. SEKCJA B: Include/Core.                |
//+------------------------------------------------------------------+
#property copyright "Gaussian Trend EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_PRESET    { PRESET_DEFAULT = 0, PRESET_FAST = 1, PRESET_SMOOTH = 2 };
enum ENUM_SRC       { SRC_CLOSE = 0, SRC_HL2 = 1, SRC_HLC3 = 2 };
enum ENUM_DIRECTION { DIR_BOTH = 0, DIR_LONG_ONLY = 1, DIR_SHORT_ONLY = 2 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Filtr Gaussa ==="
input ENUM_PRESET    InpPreset          = PRESET_DEFAULT; // Preset (inny niż Default nadpisuje parametry poniżej)
input ENUM_SRC       InpSource          = SRC_CLOSE;      // Źródło ceny
input int            InpLength          = 14;             // Długość filtra
input int            InpPoles           = 4;              // Liczba biegunów (1-4)

input group "=== Szerokość trendu ==="
input int            InpAtrLength       = 14;             // Długość ATR
input double         InpFixedMult       = 1.5;            // Stały mnożnik (gdy adaptacja wyłączona)
input bool           InpAdaptiveWidth   = true;           // Adaptacyjna szerokość (Efficiency Ratio)
input int            InpEffLength       = 10;             // Okno Efficiency Ratio
input double         InpTrendMult       = 0.8;            // Mnożnik przy wysokiej efektywności (trend)
input double         InpChopMult        = 2.5;            // Mnożnik przy niskiej efektywności (konsolidacja)
input int            InpEffSmooth       = 5;              // Wygładzanie ER (EMA)
input int            InpWarmupBars      = 3000;           // Ile świec historii przeliczyć przy starcie

input group "=== Handel ==="
input ENUM_DIRECTION InpDirection       = DIR_BOTH;       // Kierunki: oba / tylko long / tylko short
input double         InpSlBufferAtr     = 0.25;           // SL: bufor za linią trendu (x ATR)
input bool           InpTrailOnLine     = true;           // Trailing SL za linią trendu (tylko w stronę zysku)
input double         InpTpRR            = 0;              // TP na stałym RR (0 = brak, wyjście na zmianie trendu)
input bool           InpUseTradeWindow  = false;          // Nowe wejścia tylko w oknie czasowym
input string         InpTradeWindow     = "0930-1600";    // Okno handlu (czas NY, HHMM-HHMM)
input int            InpServerToNYHours = 7;              // Czas serwera minus czas NY (dla okna handlu)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int            InpMagicNumber          = 260407;   // Magic number tej strategii
input double         InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int            InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE  InpLotMode              = LOT_RISK_PERCENT; // % kapitału (od odległości SL) / stały lot
input double         InpRiskPercentPerTrade  = 1.0;      // % kapitału ryzykowany na transakcję
input double         InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input double         InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double         InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool           InpLogSignals           = true;     // Loguj zmiany trendu i decyzje
input bool           InpLogTrailing          = false;    // Loguj przesunięcia SL

//====================================================================
//  PARAMETRY EFEKTYWNE (po presecie) I STAN
//====================================================================
int    P_len, P_poles, P_atrLen, P_effLen, P_effSmooth;
double P_fixedMult, P_trendMult, P_chopMult, P_alpha;

double g_stage[4]; bool g_stageInit[4];
double g_atr = 0, g_atrSum = 0; int g_atrCnt = 0; bool g_atrReady = false;
double g_erEma = 0; bool g_erReady = false;
double g_trendLine = 0; bool g_tlInit = false;
int    g_trendDir = 0;
int    g_bar = -1;
datetime g_lastProcessedTime = 0;
bool   g_warmup = true;
int    g_winStart = 0, g_winEnd = 0;

//--- wynik ostatnio przetworzonej świecy
bool   g_turnedBull = false, g_turnedBear = false;
double g_atrNow = 0;
datetime g_sigTime = 0;
string EA_VERSION = "1.00";

//====================================================================
//  POMOCNICZE
//====================================================================
int g_s = 1;
double Src(int k)
{
   int s = g_s + k;
   double h = iHigh(_Symbol, _Period, s), l = iLow(_Symbol, _Period, s), c = iClose(_Symbol, _Period, s);
   return InpSource == SRC_HL2 ? (h + l) / 2.0 : InpSource == SRC_HLC3 ? (h + l + c) / 3.0 : c;
}
bool HasBar(int k) { return g_s + k < Bars(_Symbol, _Period); }

void ApplyPreset()
{
   P_len = InpLength; P_poles = InpPoles; P_atrLen = InpAtrLength; P_fixedMult = InpFixedMult;
   P_effLen = InpEffLength; P_trendMult = InpTrendMult; P_chopMult = InpChopMult; P_effSmooth = InpEffSmooth;
   if(InpPreset == PRESET_FAST)
   { P_len = 8; P_poles = 2; P_atrLen = 10; P_fixedMult = 1.2; P_effLen = 7; P_trendMult = 0.6; P_chopMult = 1.8; P_effSmooth = 3; }
   else if(InpPreset == PRESET_SMOOTH)
   { P_len = 21; P_poles = 4; P_atrLen = 21; P_fixedMult = 2.0; P_effLen = 18; P_trendMult = 1.0; P_chopMult = 3.2; P_effSmooth = 8; }
   // dokładnie jak w oryginale: pow(1.414, 2/poles)
   double beta = (1 - MathCos(2 * M_PI / P_len)) / (MathPow(1.414, 2.0 / P_poles) - 1);
   P_alpha = -beta + MathSqrt(beta * beta + 2 * beta);
}

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
//  PRZETWORZENIE ZAMKNIĘTEJ ŚWIECY (kolejność jak w Pine)
//====================================================================
void ProcessBar(int shift)
{
   g_s = shift;
   g_bar++;
   g_turnedBull = g_turnedBear = false;
   double src = Src(0);

   // filtr Gaussa: 4 kaskadowe etapy, każdy startuje od ceny źródłowej (nz(stage, src))
   double stageIn = src;
   for(int k = 0; k < 4; k++)
   {
      double prev = g_stageInit[k] ? g_stage[k] : src;
      g_stage[k] = P_alpha * stageIn + (1 - P_alpha) * prev;
      g_stageInit[k] = true;
      stageIn = g_stage[k];
   }
   double filtered = P_poles <= 1 ? g_stage[0] : P_poles == 2 ? g_stage[1] : P_poles == 3 ? g_stage[2] : g_stage[3];

   // Efficiency Ratio i jego EMA (na, dopóki brak pełnego okna)
   bool erOk = HasBar(P_effLen);
   if(erOk)
   {
      double net = MathAbs(src - Src(P_effLen));
      double path = 0;
      for(int k = 0; k < P_effLen; k++) path += MathAbs(Src(k) - Src(k + 1));
      double er = path == 0 ? 0.0 : net / path;
      double a = 2.0 / (P_effSmooth + 1);
      if(!g_erReady) { g_erEma = er; g_erReady = true; }
      else g_erEma = a * er + (1 - a) * g_erEma;
   }

   // ATR (RMA Wildera)
   double h = iHigh(_Symbol, _Period, g_s), l = iLow(_Symbol, _Period, g_s);
   double tr = h - l;
   if(HasBar(1)) { double pc = iClose(_Symbol, _Period, g_s + 1); tr = MathMax(tr, MathMax(MathAbs(h - pc), MathAbs(l - pc))); }
   if(!g_atrReady) { g_atrSum += tr; g_atrCnt++; if(g_atrCnt >= P_atrLen) { g_atr = g_atrSum / P_atrLen; g_atrReady = true; } }
   else g_atr = (g_atr * (P_atrLen - 1) + tr) / P_atrLen;

   // linia trendu z martwą strefą
   double prevTL = g_tlInit ? g_trendLine : filtered;
   double tl = prevTL;
   bool widthOk = g_atrReady && (!InpAdaptiveWidth || g_erReady);
   if(widthOk)
   {
      double mult = InpAdaptiveWidth ? P_chopMult + (P_trendMult - P_chopMult) * g_erEma : P_fixedMult;
      double width = g_atr * mult;
      double upper = filtered + width, lower = filtered - width;
      if(upper < tl) tl = upper;
      if(lower > tl) tl = lower;
   }
   int prevDir = g_trendDir;
   if(g_tlInit)
   {
      if(tl > prevTL) g_trendDir = 1;
      else if(tl < prevTL) g_trendDir = -1;
   }
   g_trendLine = tl;
   g_tlInit = true;

   g_turnedBull = g_trendDir == 1 && prevDir != 1;
   g_turnedBear = g_trendDir == -1 && prevDir != -1;
   g_atrNow = g_atrReady ? g_atr : tr;
   g_sigTime = iTime(_Symbol, _Period, g_s);
   g_lastProcessedTime = g_sigTime;
}

//====================================================================
//  POZYCJA
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

//--- trailing: SL za linią trendu, tylko w stronę zysku
void TrailStop()
{
   if(!InpTrailOnLine) return;
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t) || dir != g_trendDir) return;
   double cur = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double newSL = NormalizeDouble(g_trendLine - dir * InpSlBufferAtr * g_atrNow, _Digits);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool better = dir == 1 ? newSL > cur + _Point : (cur == 0 || newSL < cur - _Point);
   bool valid  = dir == 1 ? newSL < tick.bid - minDist : newSL > tick.ask + minDist;
   if(better && valid)
   {
      if(InpLogTrailing) PrintFormat("[GFT] trailing SL %s -> %s", DoubleToString(cur, _Digits), DoubleToString(newSL, _Digits));
      PM_ModifyStops(t, newSL, tp);
   }
}

string SigKey() { return StringFormat("GFT_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void HandleFlip(int d)
{
   string side = d == 1 ? "LONG" : "SHORT";
   if(InpLogSignals) PrintFormat("[GFT] zmiana trendu: %s | linia=%s ATR=%s", side, DoubleToString(g_trendLine, _Digits), DoubleToString(g_atrNow, _Digits));

   // zmiana trendu zawsze zamyka pozycję przeciwną
   int posDir;
   ulong pos = MyPosition(posDir);
   if(pos != 0 && posDir != d)
   {
      PM_CloseAllPositions(InpMagicNumber, "trend_flip");
      if(MyPosition(posDir) != 0) { EE_LogDecision("GFT", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   }
   else if(pos != 0) return;   // już w tym kierunku

   bool allowed = InpDirection == DIR_BOTH || (InpDirection == DIR_LONG_ONLY && d == 1) || (InpDirection == DIR_SHORT_ONLY && d == -1);
   if(!allowed) return;
   if(InpUseTradeWindow && !InTradeWindow(g_sigTime)) { if(InpLogSignals) Print("[GFT] wejście pominięte: poza oknem handlu"); return; }
   if(SignalAlreadyTraded(g_sigTime)) { EE_LogDecision("GFT", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = g_trendLine - d * InpSlBufferAtr * g_atrNow;
   if((entry - sl) * d <= 0) sl = entry - d * MathMax(g_atrNow, _Point * 10);   // linia po złej stronie ceny (luka) - awaryjnie 1 ATR
   sl = NormalizeDouble(sl, _Digits);
   double risk = MathAbs(entry - sl);
   double tp = InpTpRR > 0 ? NormalizeDouble(entry + d * risk * InpTpRR, _Digits) : 0;

   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;

   string tag = StringFormat("gft_%s_%d", d == 1 ? "L" : "S", (int)g_sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s TP=%s", side, vol, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                               tp == 0 ? "-" : DoubleToString(tp, _Digits)));
   if(res != EXEC_FAILED) MarkSignalTraded(g_sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpLength < 2 || InpPoles < 1 || InpPoles > 4 || InpAtrLength < 1 || InpEffLength < 2 || InpEffSmooth < 1) return INIT_PARAMETERS_INCORRECT;
   if(!ParseSession(InpTradeWindow, g_winStart, g_winEnd)) { Print("Błędny format okna handlu - użyj HHMM-HHMM"); return INIT_PARAMETERS_INCORRECT; }
   ApplyPreset();
   for(int k = 0; k < 4; k++) { g_stage[k] = 0; g_stageInit[k] = false; }
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu filtra i linii trendu z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Gaussian Trend EA %s: przeliczono %d świec | dł. %d, bieguny %d, ATR %d, ER %d | trend teraz: %s | linia=%s",
               EA_VERSION, start, P_len, P_poles, P_atrLen, P_effLen, g_trendDir == 1 ? "byczy" : g_trendDir == -1 ? "niedźwiedzi" : "brak",
               DoubleToString(g_trendLine, _Digits));
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
         if(g_turnedBull) HandleFlip(1);
         else if(g_turnedBear) HandleFlip(-1);
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
