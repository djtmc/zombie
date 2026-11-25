//+------------------------------------------------------------------+
//| AlphaSignalEngine_EA.mq5                                           |
//| Expert Advisor oparty na wskaźniku "Alpha Signal Engine Pro"       |
//| [MarkitTick] (Pine Script v6) - przeniesiony na MQL5.              |
//|                                                                    |
//| Linia trendu z dynamicznym pasmem ATR (ATR + ruch ceny), filtr     |
//| "flat" (5 warunków + breakout override), sygnał = zmiana           |
//| przefiltrowanego kierunku. Oryginał liczy wszystko z danych        |
//| poprzedniej świecy ([1]) - sygnał znany na otwarciu świecy.        |
//|                                                                    |
//| Handel: odwracanie pozycji (jak alerty oryginału), SL na linii      |
//| trendu z buforem i trailing.                                       |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Alpha Signal Engine EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_DIRECTION { DIR_BOTH = 0, DIR_LONG_ONLY = 1, DIR_SHORT_ONLY = 2 };
enum ENUM_LOT_MODE  { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Volatility Fingerprint ==="
input bool   InpVfEnabled    = false;  // Skalowanie parametrów wg kwartyla ATR%
input int    InpVfLookback   = 300;    // Okno kwartyli ATR%

input group "=== Silnik ==="
input int    InpAtrPeriod    = 14;     // ATR - długość
input double InpBandMult     = 3.0;    // Mnożnik pasma (gamma)
input double InpAtrWeight    = 1.0;    // Waga ATR/close (phi)
input double InpMoveWeight   = 5.0;    // Waga ruchu ceny (tau)
input int    InpEmaSmooth    = 1;      // Wygładzanie połowy pasma (EMA; 1 = brak)
input int    InpWarmupBars   = 3000;   // Ile świec historii przeliczyć przy starcie

input group "=== Filtry (Alpha Filtering Matrix) ==="
input bool   InpStallOn      = true;   // Filtr zatrzymania linii
input double InpStallQ       = 0.05;   //   próg płaskości (x ATR)
input bool   InpSlopeOn      = true;   // Filtr nachylenia
input int    InpSlopeLen     = 5;      //   długość regresji
input double InpSlopeZ       = 0.05;   //   próg nachylenia (x ATR)
input bool   InpVolOn        = true;   // Filtr wolumenu (tickowego)
input int    InpVolLen       = 20;     //   długość SMA wolumenu
input bool   InpRangeOn      = true;   // Filtr zakresu świecy
input int    InpRangeLb      = 100;    //   okno percentyla
input double InpRangePct     = 20.0;   //   percentyl (%)
input bool   InpBpsOn        = true;   // Filtr zmiany linii w bps
input double InpBpsQ         = 1.0;    //   min. zmiana (bps)
input bool   InpBreakoutOn   = true;   // Breakout override
input double InpBreakoutQ    = 1.5;    //   próg (x ATR)

input group "=== Handel ==="
input ENUM_DIRECTION InpDirection    = DIR_BOTH; // Kierunki
input bool   InpEntryAtSignalClose   = false;    // false = wejście na otwarciu świecy sygnału; true = na jej zamknięciu (jak webhook)
input double InpSlBufferAtr          = 0.25;     // SL: bufor za linią trendu (x ATR)
input bool   InpTrailOnLine          = true;     // Trailing SL za linią trendu (tylko w stronę zysku)
input double InpTpRR                 = 0;        // TP na stałym RR (0 = brak)

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260408;   // Magic number tej strategii
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
input bool          InpLogFlatBlocks        = false;    // Loguj zmiany kierunku zablokowane filtrem flat

//====================================================================
//  STAN
//====================================================================
//--- bufor kołowy z percentylem nearest rank (jak ta.percentile_nearest_rank)
struct Ring { double v[]; int cap; int pos; int n; };
void RingInit(Ring &r, int cap) { r.cap = cap; ArrayResize(r.v, cap); r.pos = 0; r.n = 0; }
void RingPush(Ring &r, double x) { r.v[r.pos] = x; r.pos = (r.pos + 1) % r.cap; if(r.n < r.cap) r.n++; }
double RingPct(Ring &r, double p)   // EMPTY_VALUE, dopóki okno niepełne (na w Pine)
{
   if(r.n < r.cap) return EMPTY_VALUE;
   double s[];
   ArrayCopy(s, r.v);
   ArraySort(s);
   int rank = (int)MathCeil(p / 100.0 * r.cap);
   rank = (int)MathMax(1, MathMin(r.cap, rank));
   return s[rank - 1];
}

Ring   g_atrPctBuf, g_pmBuf, g_hlBuf;
double g_atr = 0, g_atrSum = 0; int g_atrCnt = 0; bool g_atrReady = false;
double g_bandHalf = 0; bool g_bandInit = false;
double g_tl[];          // historia linii trendu: [0] = najnowsza
int    g_tlCount = 0;
int    g_direction = 1, g_dispDir = 1;
datetime g_lastProcessedTime = 0;
bool   g_warmup = true;

//--- wynik bieżącego kroku (sygnał dla świecy następującej po przetworzonej)
int      g_signal = 0;          // +1 BUY, -1 SELL
int      g_queued = 0;          // sygnał czekający na zamknięcie świecy (tryb "jak webhook")
datetime g_queuedTime = 0;
double   g_atrNow = 0;
string   EA_VERSION = "1.00";

double TL(int k) { return k < g_tlCount ? g_tl[k] : EMPTY_VALUE; }
void PushTL(double v)
{
   int cap = (int)MathMax(8, InpSlopeLen + 3);
   if(ArraySize(g_tl) < cap) ArrayResize(g_tl, cap);
   for(int i = cap - 1; i > 0; i--) g_tl[i] = g_tl[i - 1];
   g_tl[0] = v;
   if(g_tlCount < cap) g_tlCount++;
}

//--- nachylenie regresji liniowej z n ostatnich wartości linii (od najstarszej do najnowszej)
double RegSlope(int n)
{
   if(g_tlCount < n) return EMPTY_VALUE;
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for(int i = 0; i < n; i++)
   {
      double x = i, y = g_tl[n - 1 - i];
      sx += x; sy += y; sxy += x * y; sxx += x * x;
   }
   double den = n * sxx - sx * sx;
   return den == 0 ? 0 : (n * sxy - sx * sy) / den;
}

//====================================================================
//  KROK SILNIKA: dane zamkniętej świecy j -> wartości Pine dla świecy j+1
//====================================================================
void ProcessBar(int j)
{
   g_signal = 0;
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   double h1 = iHigh(_Symbol, _Period, j), l1 = iLow(_Symbol, _Period, j), c1 = iClose(_Symbol, _Period, j);
   bool hasPrev = j + 1 < Bars(_Symbol, _Period);
   double c2 = hasPrev ? iClose(_Symbol, _Period, j + 1) : c1;

   // ATR (RMA) liczony na świecy j = ta.atr()[1]
   double tr = h1 - l1;
   if(hasPrev) tr = MathMax(tr, MathMax(MathAbs(h1 - c2), MathAbs(l1 - c2)));
   if(!g_atrReady) { g_atrSum += tr; g_atrCnt++; if(g_atrCnt >= InpAtrPeriod) { g_atr = g_atrSum / InpAtrPeriod; g_atrReady = true; } }
   else g_atr = (g_atr * (InpAtrPeriod - 1) + tr) / InpAtrPeriod;
   g_lastProcessedTime = iTime(_Symbol, _Period, j);
   if(!g_atrReady) return;      // w Pine atr = na - linia i sygnały jeszcze nie istnieją
   double atr = g_atr;
   g_atrNow = atr;

   // Volatility Fingerprint (kwartyle ATR%)
   double atrPct = atr / MathMax(c1, tick) * 100.0;
   RingPush(g_atrPctBuf, atrPct);
   double gm = 1, pm = 1, tm = 1;
   if(InpVfEnabled)
   {
      double p25 = RingPct(g_atrPctBuf, 25), p50 = RingPct(g_atrPctBuf, 50), p75 = RingPct(g_atrPctBuf, 75);
      int bucket = atrPct < (p25 == EMPTY_VALUE ? atrPct + 1 : p25) ? 0
                 : atrPct < (p50 == EMPTY_VALUE ? atrPct + 1 : p50) ? 1
                 : atrPct < (p75 == EMPTY_VALUE ? atrPct + 1 : p75) ? 2 : 3;
      gm = bucket == 0 ? 0.70 : bucket == 1 ? 1.00 : bucket == 2 ? 1.40 : 2.00;
      pm = bucket == 0 ? 0.70 : bucket == 1 ? 1.00 : bucket == 2 ? 1.30 : 1.80;
      tm = bucket == 0 ? 0.60 : bucket == 1 ? 1.00 : bucket == 2 ? 1.35 : 1.70;
   }
   double effGam = InpBandMult * gm, effPhi = InpAtrWeight * pm, effTau = InpMoveWeight * tm;
   double effKap = MathMax(1.0, InpEmaSmooth * gm);

   // ruch ceny, ograniczony 95. percentylem ze 100 świec
   double pmRaw = MathAbs(c1 - c2) / MathMax(c2, tick);
   RingPush(g_pmBuf, pmRaw);
   double p95 = RingPct(g_pmBuf, 95);
   double priceMove = MathMin(pmRaw, p95 == EMPTY_VALUE ? pmRaw : p95);

   // dynamiczna połowa pasma (EMA)
   double dynRaw = effGam + (atr / c1) * effPhi + priceMove * effTau;
   double alpha = 2.0 / (effKap + 1.0);
   double rawHalf = dynRaw * atr;
   g_bandHalf = !g_bandInit ? rawHalf : alpha * rawHalf + (1.0 - alpha) * g_bandHalf;
   g_bandInit = true;
   double hl2 = (h1 + l1) / 2.0;
   double upper = hl2 + g_bandHalf, lower = hl2 - g_bandHalf;

   // linia trendu i kierunek (trendLine[1] = poprzednia wartość)
   double tlPrev = TL(0);
   double tl = tlPrev == EMPTY_VALUE ? upper : tlPrev;
   if(tlPrev != EMPTY_VALUE && c1 > tlPrev) { g_direction = 1;  tl = MathMax(lower, tl); }
   else                                     { g_direction = -1; tl = MathMin(upper, tl); }

   // filtry "flat" - na historii linii sprzed tego kroku (trendLine[1], [2])
   double tl1 = TL(0), tl2 = TL(1);
   bool haveTL2 = tl1 != EMPTY_VALUE && tl2 != EMPTY_VALUE;
   bool vtfFlat = InpStallOn && haveTL2 && MathAbs(tl1 - tl2) < atr * InpStallQ * gm;
   double slope = RegSlope(InpSlopeLen);
   bool tifFlat = InpSlopeOn && slope != EMPTY_VALUE && MathAbs(slope) / MathMax(atr, tick) < InpSlopeZ * gm;
   bool lqfFlat = false;
   if(InpVolOn)
   {
      double vol1 = (double)iTickVolume(_Symbol, _Period, j);
      double sma = EMPTY_VALUE;
      if(j + InpVolLen <= Bars(_Symbol, _Period))
      {
         double s = 0;
         for(int k = 0; k < InpVolLen; k++) s += (double)iTickVolume(_Symbol, _Period, j + k);
         sma = s / InpVolLen * gm;
      }
      lqfFlat = vol1 <= (sma == EMPTY_VALUE ? vol1 + 1 : sma);   // nz(..., volume+1): brak danych = flat
   }
   double hlRange = h1 - l1;
   RingPush(g_hlBuf, hlRange);
   bool cdfFlat = false;
   if(InpRangeOn)
   {
      double pc = RingPct(g_hlBuf, InpRangePct);
      cdfFlat = hlRange <= (pc == EMPTY_VALUE ? hlRange + 1 : pc * gm);
   }
   bool bpfFlat = InpBpsOn && haveTL2 && MathAbs(tl1 - tl2) / MathMax(c2, tick) * 10000.0 < InpBpsQ * gm;
   bool breakout = InpBreakoutOn && MathAbs(c1 - c2) > atr * InpBreakoutQ * gm;
   bool flat = (vtfFlat || tifFlat || lqfFlat || cdfFlat || bpfFlat) && !breakout;

   int prevDisp = g_dispDir;
   if(!flat) g_dispDir = g_direction;
   else if(InpLogFlatBlocks && !g_warmup && g_direction != g_dispDir)
      PrintFormat("[ASE] zmiana kierunku zablokowana (stall=%d slope=%d vol=%d range=%d bps=%d)", vtfFlat, tifFlat, lqfFlat, cdfFlat, bpfFlat);

   if(g_dispDir == 1 && prevDisp == -1) g_signal = 1;
   if(g_dispDir == -1 && prevDisp == 1) g_signal = -1;
   PushTL(tl);
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

void TrailStop()
{
   if(!InpTrailOnLine || g_tlCount == 0) return;
   int dir;
   ulong t = MyPosition(dir);
   if(t == 0 || !PositionSelectByTicket(t) || dir != g_direction) return;
   double cur = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double newSL = NormalizeDouble(TL(0) - dir * InpSlBufferAtr * g_atrNow, _Digits);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool better = dir == 1 ? newSL > cur + _Point : (cur == 0 || newSL < cur - _Point);
   bool valid  = dir == 1 ? newSL < tick.bid - minDist : newSL > tick.ask + minDist;
   if(better && valid) PM_ModifyStops(t, newSL, tp);
}

string SigKey() { return StringFormat("ASE_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void HandleSignal(int d, datetime sigTime)
{
   string side = d == 1 ? "BUY" : "SELL";
   if(InpLogSignals) PrintFormat("[ASE] sygnał %s (świeca %s) | linia=%s ATR=%s", side, TimeToString(sigTime), DoubleToString(TL(0), _Digits), DoubleToString(g_atrNow, _Digits));

   // sygnał zawsze zamyka pozycję przeciwną (closelong / closeshort z oryginału)
   int posDir;
   ulong pos = MyPosition(posDir);
   if(pos != 0 && posDir != d)
   {
      PM_CloseAllPositions(InpMagicNumber, d == 1 ? "closeshort" : "closelong");
      if(MyPosition(posDir) != 0) { EE_LogDecision("ASE", "BLOCKED", "Nie udało się zamknąć przeciwnej pozycji"); return; }
   }
   else if(pos != 0) return;

   bool allowed = InpDirection == DIR_BOTH || (InpDirection == DIR_LONG_ONLY && d == 1) || (InpDirection == DIR_SHORT_ONLY && d == -1);
   if(!allowed) return;
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("ASE", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double sl = TL(0) - d * InpSlBufferAtr * g_atrNow;
   if((entry - sl) * d <= 0) sl = entry - d * MathMax(g_atrNow, _Point * 10);   // linia po złej stronie (luka) - awaryjnie 1 ATR
   sl = NormalizeDouble(sl, _Digits);
   double risk = MathAbs(entry - sl);
   double tp = InpTpRR > 0 ? NormalizeDouble(entry + d * risk * InpTpRR, _Digits) : 0;

   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, risk / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;

   string tag = StringFormat("ase_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, tp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s TP=%s", side, vol, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
                               tp == 0 ? "-" : DoubleToString(tp, _Digits)));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpAtrPeriod < 2 || InpSlopeLen < 3 || InpVolLen < 1 || InpRangeLb < 2 || InpVfLookback < 4) return INIT_PARAMETERS_INCORRECT;
   RingInit(g_atrPctBuf, InpVfLookback);
   RingInit(g_pmBuf, 100);
   RingInit(g_hlBuf, InpRangeLb);
   ArrayResize(g_tl, 0); g_tlCount = 0;
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 3);
   for(int j = start; j >= 1; j--) ProcessBar(j);
   g_warmup = false;
   g_queued = 0;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   PrintFormat("Alpha Signal Engine EA %s: przeliczono %d świec | kierunek %s | linia=%s | wejście %s",
               EA_VERSION, start, g_dispDir == 1 ? "byczy" : "niedźwiedzi", DoubleToString(TL(0), _Digits),
               InpEntryAtSignalClose ? "na zamknięciu świecy sygnału" : "na otwarciu świecy sygnału");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(!UT_IsNewBar(_Symbol, PERIOD_CURRENT)) return;

   int lastShift = g_lastProcessedTime > 0 ? iBarShift(_Symbol, _Period, g_lastProcessedTime, false) : 2;
   if(lastShift < 1) return;
   for(int j = lastShift - 1; j >= 1; j--)
   {
      ProcessBar(j);
      if(j != 1) { g_queued = 0; continue; }   // zaległych świec nie handlujemy

      datetime sigBar = iTime(_Symbol, _Period, 0);   // sygnał należy do świecy, która się właśnie otworzyła
      if(InpEntryAtSignalClose)
      {
         // tryb "jak webhook": wykonaj sygnał z poprzedniego kroku (jego świeca właśnie się zamknęła)
         if(g_queued != 0) HandleSignal(g_queued, g_queuedTime);
         g_queued = g_signal; g_queuedTime = sigBar;
      }
      else if(g_signal != 0) HandleSignal(g_signal, sigBar);
      TrailStop();
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
