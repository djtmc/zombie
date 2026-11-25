//+------------------------------------------------------------------+
//| VolumeBreakout30_EA.mq5                                            |
//| Strategia "Breakout with volume" (reguły z TrendSpider) - NASDAQ.  |
//|                                                                    |
//| Wejście (long, zamknięta świeca TF sygnału, domyślnie M30):         |
//|   close > najwyższy high z 30 poprzednich świec (bez bieżącej)      |
//|   wolumen >= SMA(20) wolumenu x 1.75 (o co najmniej 75% wyżej)      |
//|   close > open                                                      |
//| Wyjście:                                                            |
//|   od 16. świecy: zamknij, gdy zysk < 0.5% ceny                      |
//|   po 60 świecach: zamknij zawsze                                    |
//|   awaryjny SL = 3 x ATR(14) (dodany - oryginał nie ma SL)           |
//|                                                                    |
//| SEKCJA A: sygnał i wyjścia czasowe. SEKCJA B: Include/Core.         |
//+------------------------------------------------------------------+
#property copyright "Volume Breakout 30m EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_LOT_MODE { LOT_RISK_PERCENT = 0, LOT_FIXED = 1 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Sygnał: breakout z wolumenem ==="
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_M30; // TF sygnału (świece liczone na tym TF)
input int             InpRangeLen         = 30;         // Breakout: najwyższy high z N poprzednich świec
input int             InpVolLen           = 20;         // Wolumen: długość SMA
input double          InpVolAbovePct      = 75.0;       // Wolumen co najmniej o X% powyżej SMA
input bool            InpRequireBullBody  = true;       // Wymagaj close > open
input bool            InpAllowShorts      = false;      // Lustrzane shorty (poza oryginalną strategią)

input group "=== Wyjścia ==="
input int             InpEarlyExitBars    = 16;         // Od tej świecy: wyjście, gdy zysk poniżej progu
input double          InpEarlyExitMinPnl  = 0.5;        // Próg zysku (% ceny)
input bool            InpEarlyCheckEveryBar = true;     // true = sprawdzaj każdą świecę od 16.; false = tylko 16.
input int             InpMaxBars          = 60;         // Po tylu świecach wyjście zawsze
input int             InpAtrLen           = 14;         // Awaryjny SL: długość ATR (Wilder)
input double          InpSlAtrMult        = 3.0;        // Awaryjny SL: wielokrotność ATR

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int             InpMagicNumber          = 260405;   // Magic number tej strategii
input double          InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int             InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE   InpLotMode              = LOT_RISK_PERCENT; // % kapitału (od odległości SL) / stały lot
input double          InpRiskPercentPerTrade  = 1.0;      // % kapitału ryzykowany na transakcję
input double          InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input double          InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double          InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool            InpLogSignals           = true;     // Loguj sygnały, wejścia i wyjścia
input bool            InpLogNearMiss          = false;    // Loguj breakouty odrzucone przez wolumen / świecę

string EA_VERSION = "1.00";

//====================================================================
//  WSKAŹNIKI
//====================================================================
//--- ATR Wildera (RMA) na zamkniętych świecach TF sygnału, wartość dla shift 1
double AtrWilder()
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, InpSignalTF, 1, InpAtrLen * 20, r);
   if(n < InpAtrLen + 1) return 0;
   double atr = 0, sum = 0;
   int cnt = 0;
   for(int i = n - 1; i >= 0; i--)
   {
      double tr = r[i].high - r[i].low;
      if(i + 1 < n) tr = MathMax(tr, MathMax(MathAbs(r[i].high - r[i + 1].close), MathAbs(r[i].low - r[i + 1].close)));
      if(cnt < InpAtrLen) { sum += tr; cnt++; atr = sum / cnt; }
      else atr = (atr * (InpAtrLen - 1) + tr) / InpAtrLen;
   }
   return atr;
}

//--- sygnał na ostatniej zamkniętej świecy: +1 long, -1 short, 0 brak
int CheckSignal(string &info)
{
   int need = (int)MathMax(InpRangeLen + 2, InpVolLen + 1);
   if(iBars(_Symbol, InpSignalTF) < need + 5) return 0;

   double c = iClose(_Symbol, InpSignalTF, 1), o = iOpen(_Symbol, InpSignalTF, 1);
   int hiIdx = iHighest(_Symbol, InpSignalTF, MODE_HIGH, InpRangeLen, 2);   // 30 świec sprzed bieżącej
   int loIdx = iLowest(_Symbol, InpSignalTF, MODE_LOW, InpRangeLen, 2);
   if(hiIdx < 0 || loIdx < 0) return 0;
   double rangeHigh = iHigh(_Symbol, InpSignalTF, hiIdx);
   double rangeLow  = iLow(_Symbol, InpSignalTF, loIdx);

   // SMA(20) wolumenu tickowego z bieżącą świecą
   double sum = 0;
   for(int k = 1; k <= InpVolLen; k++) sum += (double)iTickVolume(_Symbol, InpSignalTF, k);
   double sma = sum / InpVolLen;
   double vol = (double)iTickVolume(_Symbol, InpSignalTF, 1);
   bool volOk = sma > 0 && vol >= sma * (1.0 + InpVolAbovePct / 100.0);

   bool brkUp = c > rangeHigh;
   bool brkDn = InpAllowShorts && c < rangeLow;
   info = StringFormat("close=%s high%d=%s low%d=%s vol=%.0f sma=%.0f (x%.2f)", DoubleToString(c, _Digits), InpRangeLen,
                       DoubleToString(rangeHigh, _Digits), InpRangeLen, DoubleToString(rangeLow, _Digits), vol, sma, sma > 0 ? vol / sma : 0);

   if(brkUp && volOk && (!InpRequireBullBody || c > o)) return 1;
   if(brkDn && volOk && (!InpRequireBullBody || c < o)) return -1;
   if(InpLogNearMiss && (brkUp || brkDn)) Print("[VB30] breakout bez potwierdzenia (wolumen/świeca): ", info);
   return 0;
}

//====================================================================
//  POZYCJA
//====================================================================
ulong MyPosition()
{
   ulong tickets[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, tickets);
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tickets[i]) && PositionGetString(POSITION_SYMBOL) == _Symbol) return tickets[i];
   return 0;
}

//--- wyjścia czasowe, sprawdzane na zamknięciu świecy TF sygnału
void ManageTimeExits()
{
   ulong t = MyPosition();
   if(t == 0 || !PositionSelectByTicket(t)) return;
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   int passed = iBarShift(_Symbol, InpSignalTF, opened, false);   // świece zamknięte od świecy wejścia
   if(passed < 0) return;
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double c = iClose(_Symbol, InpSignalTF, 1);
   double pnlPct = entry > 0 ? (c - entry) / entry * 100.0 * (isBuy ? 1 : -1) : 0;

   string reason = "";
   if(passed >= InpMaxBars) reason = StringFormat("max_bars (%d świec, wynik %.2f%%)", passed, pnlPct);
   else if(passed >= InpEarlyExitBars && (InpEarlyCheckEveryBar || passed == InpEarlyExitBars) && pnlPct < InpEarlyExitMinPnl)
      reason = StringFormat("early_exit (%d świec, wynik %.2f%% < %.2f%%)", passed, pnlPct, InpEarlyExitMinPnl);
   if(reason == "") return;
   if(InpLogSignals) Print("[VB30] wyjście czasowe: ", reason);
   PM_ClosePosition(t, reason);
}

//--- idempotencja sygnału (poza testerem)
string SigKey() { return StringFormat("VB30_%d_%s_lastSig", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

void OpenTrade(int d, string info)
{
   datetime sigTime = iTime(_Symbol, InpSignalTF, 1);
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("VB30", "SKIPPED_DUPLICATE", "Sygnał z tej świecy już obsłużony"); return; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return;
   if(!RM_CanOpenNewPosition(InpMagicNumber, 1)) return;

   double atr = AtrWilder();
   if(atr <= 0) { EE_LogDecision("VB30", "BLOCKED", "Brak danych do ATR"); return; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double entry = d == 1 ? tick.ask : tick.bid;
   double slDist = InpSlAtrMult * atr;
   double sl = NormalizeDouble(entry - d * slDist, _Digits);

   double vol = InpLotMode == LOT_FIXED ? InpFixedLot : RM_CalculateLotSizeByRiskStrict(_Symbol, InpRiskPercentPerTrade, slDist / _Point);
   if(vol <= 0) return;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return;

   string tag = StringFormat("vb30_%s_%d", d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, sl, 0, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s vol=%.2f entry=%s SL=%s (%.1f x ATR=%s) | %s", d == 1 ? "LONG" : "SHORT", vol,
                               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), InpSlAtrMult, DoubleToString(atr, _Digits), info));
   if(res != EXEC_FAILED) MarkSignalTraded(sigTime);
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   if(InpRangeLen < 1 || InpVolLen < 1 || InpMaxBars < 1 || InpSlAtrMult <= 0) return INIT_PARAMETERS_INCORRECT;
   RC_ReconcileState(InpMagicNumber);
   UT_IsNewBar(_Symbol, InpSignalTF);
   EventSetTimer(15);
   PrintFormat("Volume Breakout EA %s: TF=%s, breakout %d świec, wolumen >= SMA%d x %.2f, wyjścia %d/%d świec, SL %.1f x ATR%d",
               EA_VERSION, EnumToString(InpSignalTF), InpRangeLen, InpVolLen, 1.0 + InpVolAbovePct / 100.0,
               InpEarlyExitBars, InpMaxBars, InpSlAtrMult, InpAtrLen);
   if(StringFind(_Symbol, "NAS") < 0 && StringFind(_Symbol, "US100") < 0 && StringFind(_Symbol, "USTEC") < 0 && StringFind(_Symbol, "NDX") < 0)
      Print("Uwaga: strategia była przygotowana pod NASDAQ (NAS100/US100/USTEC) - bieżący symbol: ", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(!UT_IsNewBar(_Symbol, InpSignalTF)) return;

   // najpierw wyjścia czasowe (zamknięcie świecy), potem ewentualne nowe wejście
   ManageTimeExits();

   string info = "";
   int sig = CheckSignal(info);
   if(sig == 0) return;
   if(InpLogSignals) PrintFormat("[VB30] sygnał %s | %s", sig == 1 ? "LONG" : "SHORT", info);
   if(MyPosition() != 0) { if(InpLogSignals) Print("[VB30] pominięty: pozycja już otwarta"); return; }
   OpenTrade(sig, info);
}

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
