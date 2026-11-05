//+------------------------------------------------------------------+
//| BuySellSignalsXL_EA.mq5                                            |
//| Expert Advisor oparty na wskaźniku "Buy/Sell Signals XL" (Pine v6).|
//|                                                                    |
//| Sześć silników sygnału (jeden aktywny): OC, Breakout, Donchian,    |
//| MA Cross, Supertrend, Aroon - każdy z własnymi ustawieniami SL/TP. |
//| Wirtualny stan transakcji 1:1 z Pine (blokady, naprzemienność,     |
//| odwracanie, wyjścia knot/zamknięcie) steruje realnymi pozycjami.   |
//| Wejście zawsze rynkowo na otwarciu świecy po sygnale.              |
//| SEKCJA A: sygnał. SEKCJA B: Include/Core.                           |
//+------------------------------------------------------------------+
#property copyright "Buy/Sell Signals XL EA"
#property version   "1.00"

#include <Core/ExecutionEngine.mqh>
#include <Core/PositionManager.mqh>
#include <Core/RiskManager.mqh>
#include <Core/ReconciliationManager.mqh>
#include <Core/Utils.mqh>

enum ENUM_XL_ENGINE    { ENG_OC = 0, ENG_BREAKOUT = 1, ENG_DONCHIAN = 2, ENG_MA_CROSS = 3, ENG_SUPERTREND = 4, ENG_AROON = 5 };
enum ENUM_XL_SIGDIR    { SIG_ALTERNATE = 0, SIG_ANY = 1, SIG_BUY_ONLY = 2, SIG_SELL_ONLY = 3 };
enum ENUM_XL_SL        { SL_ATR = 0, SL_CANDLE_WICK = 1, SL_CANDLE_BODY = 2, SL_BASE_EDGE = 3, SL_CHANNEL_OPPOSITE = 4,
                         SL_CHANNEL_MIDDLE = 5, SL_SWING = 6, SL_SUPERTREND_LINE = 7, SL_AROON_EXTREME = 8, SL_NONE = 9 };
enum ENUM_XL_TP        { TP_ATR_TARGET = 0, TP_SL_MULTIPLE = 1, TP_BASE_HEIGHT = 2, TP_OPPOSITE_SIGNAL = 3 };
enum ENUM_XL_EXIT      { EXIT_WICK = 0, EXIT_CLOSE = 1 };
enum ENUM_XL_BRK_ENTRY { BRK_CLOSE_ENTRY = 0, BRK_CLOSE_EDGE = 1, BRK_WICK_EDGE = 2 };
enum ENUM_XL_ENTRY     { ENT_CLOSE_ENTRY = 0, ENT_CLOSE_EDGE = 1 };
enum ENUM_XL_BASE      { BASE_FIXED = 0, BASE_VARIABLE = 1 };
enum ENUM_XL_MA        { XMA_SMA = 0, XMA_EMA = 1, XMA_WMA = 2, XMA_HMA = 3, XMA_RMA = 4 };
enum ENUM_XL_SMOOTH    { SM_NONE = 0, SM_SMA = 1, SM_EMA = 2, SM_RMA = 3, SM_WMA = 4, SM_HMA = 5 };
enum ENUM_XL_SRC       { XSRC_CLOSE = 0, XSRC_OPEN = 1, XSRC_HIGH = 2, XSRC_LOW = 3, XSRC_HL2 = 4, XSRC_HLC3 = 5, XSRC_OHLC4 = 6 };
enum ENUM_XL_MAMODE    { MAMODE_DOUBLE = 0, MAMODE_TRIPLE = 1 };
enum ENUM_XL_ARMODE    { AR_CROSSOVER = 0, AR_STRONG_TREND = 1 };
enum ENUM_LOT_MODE     { LOT_RISK_PERCENT = 0, LOT_RISK_MONEY = 1, LOT_FIXED = 2 };

//====================================================================
//  INPUTY - SYGNAŁ
//====================================================================
input group "=== Silnik sygnału ==="
input ENUM_XL_ENGINE InpEngine       = ENG_BREAKOUT; // Silnik (jeden aktywny; kilka silników = kilka instancji z różnym magic)
input int            InpWarmupBars   = 3000;         // Ile świec historii przeliczyć przy starcie

input group "=== OC ==="
input int            InpOcBodyLen    = 50;           // Długość średniego korpusu (i średniego wolumenu)
input double         InpOcBodyMult   = 3.0;          // Min. korpus vs średnia (x)
input double         InpOcVol        = 0.0;          // Min. wolumen vs średnia (x, 0 = wył.)
input ENUM_XL_SIGDIR InpOcSig        = SIG_ALTERNATE;// Kierunek sygnałów
input bool           InpOcNoOvl      = true;         // Ignoruj sygnały, gdy transakcja otwarta
input ENUM_XL_SL     InpOcSl         = SL_CANDLE_WICK; // SL: ATR / knot / korpus / brak
input double         InpOcSlBuf      = 0.0;          // Bufor SL (x ATR)
input ENUM_XL_TP     InpOcTp         = TP_SL_MULTIPLE; // TP: ATR / wielokrotność SL / sygnał przeciwny
input double         InpOcSlMult     = 1.5;          // SL (x ATR) - tryb ATR
input double         InpOcTpMult     = 3.0;          // TP (x ATR) - tryb ATR
input double         InpOcTpRMult    = 1.0;          // TP (x SL) - tryb wielokrotność SL

input group "=== Breakout ==="
input ENUM_XL_BASE      InpBrkBaseMode  = BASE_VARIABLE;   // Baza: stała / zmienna
input int               InpBrkBaseLen   = 10;              // Długość bazy stałej (świece)
input int               InpBrkVarMin    = 5;               // Baza zmienna: min. świec
input int               InpBrkVarMax    = 30;              // Baza zmienna: maks. świec
input double            InpBrkBaseMult  = 2.0;             // Maks. wysokość bazy (x ATR)
input ENUM_XL_BRK_ENTRY InpBrkEntry     = BRK_CLOSE_ENTRY; // Wejście wirtualne: close / krawędź po close / krawędź knotem
input double            InpBrkMinBreak  = 0.0;             // Min. siła wybicia (x ATR)
input double            InpBrkVol       = 0.0;             // Min. wolumen vs średnia (x, 0 = wył.)
input int               InpBrkVolLen    = 50;              // Długość średniego wolumenu
input bool              InpBrkTrend     = false;           // Filtr trendu EMA
input int               InpBrkTrendLen  = 200;             // Długość EMA trendu
input ENUM_XL_SIGDIR    InpBrkSig       = SIG_ALTERNATE;   // Kierunek sygnałów
input bool              InpBrkNoOvl     = true;            // Ignoruj sygnały, gdy transakcja otwarta
input bool              InpBrkNoBaseInTrade = true;        // Baza tylko ze świec po zakończeniu transakcji
input int               InpBrkBaseGap   = 0;               // Odstęp bazy po wyjściu (świece)
input ENUM_XL_SL        InpBrkSl        = SL_BASE_EDGE;    // SL: ATR / przeciwna krawędź bazy
input double            InpBrkSlBuf     = 0.0;             // Bufor SL (x ATR)
input ENUM_XL_TP        InpBrkTp        = TP_BASE_HEIGHT;  // TP: ATR / wielokrotność SL / wysokość bazy
input double            InpBrkSlMult    = 1.5;             // SL (x ATR) - tryb ATR
input double            InpBrkTpMult    = 3.0;             // TP (x ATR) - tryb ATR
input double            InpBrkTpRMult   = 2.0;             // TP (x SL) - tryb wielokrotność SL
input double            InpBrkTpBMult   = 1.0;             // TP (x wysokość bazy)

input group "=== Donchian ==="
input int            InpDonLen       = 20;               // Długość kanału (i średniego wolumenu)
input ENUM_XL_ENTRY  InpDonEntry     = ENT_CLOSE_ENTRY;  // Wejście wirtualne: close / banda
input double         InpDonVol       = 0.0;              // Min. wolumen vs średnia (x, 0 = wył.)
input ENUM_XL_SIGDIR InpDonSig       = SIG_ALTERNATE;    // Kierunek sygnałów
input bool           InpDonNoOvl     = true;             // Ignoruj sygnały, gdy transakcja otwarta
input ENUM_XL_SL     InpDonSl        = SL_CHANNEL_OPPOSITE; // SL: ATR / przeciwna banda / środek / knot / korpus / brak
input double         InpDonSlBuf     = 0.0;              // Bufor SL (x ATR)
input ENUM_XL_TP     InpDonTp        = TP_SL_MULTIPLE;   // TP: ATR / wielokrotność SL / sygnał przeciwny
input double         InpDonSlMult    = 2.0;              // SL (x ATR) - tryb ATR
input double         InpDonTpMult    = 3.0;              // TP (x ATR) - tryb ATR
input double         InpDonTpRMult   = 0.5;              // TP (x SL) - tryb wielokrotność SL

input group "=== MA Cross ==="
input ENUM_XL_MAMODE InpMaMode       = MAMODE_TRIPLE;    // Tryb: 2 MA (przecięcie) / 3 MA (ułożenie)
input int            InpMaFast       = 9;                // Szybka MA
input int            InpMaMed        = 21;               // Średnia MA (i średni wolumen)
input int            InpMaSlow       = 55;               // Wolna MA (tryb 3 MA)
input ENUM_XL_MA     InpMaType       = XMA_EMA;          // Typ MA
input ENUM_XL_SRC    InpMaSrc        = XSRC_CLOSE;       // Źródło MA
input double         InpMaMinSep     = 0.0;              // Min. siła przecięcia (x ATR)
input bool           InpMaTrend      = false;            // Filtr trendu MA
input int            InpMaTrendLen   = 200;              // Długość MA trendu
input ENUM_XL_ENTRY  InpMaEntry      = ENT_CLOSE_ENTRY;  // Wejście wirtualne: close / cena średniej MA
input double         InpMaVol        = 0.0;              // Min. wolumen vs średnia (x, 0 = wył.)
input ENUM_XL_SIGDIR InpMaSig        = SIG_ALTERNATE;    // Kierunek sygnałów
input bool           InpMaNoOvl      = true;             // Ignoruj sygnały, gdy transakcja otwarta
input ENUM_XL_SL     InpMaSl         = SL_ATR;           // SL: ATR / swing / knot / korpus / brak
input int            InpMaSwingLen   = 5;                // Długość swingu (świece)
input double         InpMaSlBuf      = 0.0;              // Bufor SL (x ATR)
input double         InpMaSlMin      = 1.0;              // Min. odległość SL (x ATR) - swing / knot / korpus
input ENUM_XL_TP     InpMaTp         = TP_SL_MULTIPLE;   // TP: ATR / wielokrotność SL / sygnał przeciwny
input double         InpMaSlMult     = 2.0;              // SL (x ATR) - tryb ATR
input double         InpMaTpMult     = 1.0;              // TP (x ATR) - tryb ATR
input double         InpMaTpRMult    = 1.0;              // TP (x SL) - tryb wielokrotność SL

input group "=== Supertrend ==="
input int            InpStLen        = 10;               // ATR Supertrendu
input double         InpStMult       = 3.0;              // Mnożnik Supertrendu
input ENUM_XL_ENTRY  InpStEntry      = ENT_CLOSE_ENTRY;  // Wejście wirtualne: close / linia
input ENUM_XL_SIGDIR InpStSig        = SIG_ALTERNATE;    // Kierunek sygnałów
input bool           InpStNoOvl      = true;             // Ignoruj sygnały, gdy transakcja otwarta
input ENUM_XL_SL     InpStSl         = SL_SUPERTREND_LINE; // SL: linia / ATR / knot / korpus / brak
input double         InpStSlBuf      = 0.0;              // Bufor SL (x ATR)
input ENUM_XL_TP     InpStTp         = TP_SL_MULTIPLE;   // TP: ATR / wielokrotność SL / sygnał przeciwny
input double         InpStSlMult     = 1.5;              // SL (x ATR) - tryb ATR
input double         InpStTpMult     = 3.0;              // TP (x ATR) - tryb ATR
input double         InpStTpRMult    = 0.5;              // TP (x SL) - tryb wielokrotność SL

input group "=== Aroon ==="
input int            InpArLen        = 14;               // Długość Aroon
input ENUM_XL_ARMODE InpArMode       = AR_CROSSOVER;     // Sygnał: przecięcie / silny trend
input double         InpArStrong     = 70.0;             // Poziom silnego trendu
input ENUM_XL_SMOOTH InpArSmooth     = SM_NONE;          // Wygładzanie linii Aroon
input int            InpArSmLen      = 3;                // Długość wygładzania
input double         InpArVol        = 0.0;              // Min. wolumen vs średnia (x, 0 = wył.)
input int            InpArVolLen     = 50;               // Długość średniego wolumenu
input ENUM_XL_SIGDIR InpArSig        = SIG_ALTERNATE;    // Kierunek sygnałów
input bool           InpArNoOvl      = true;             // Ignoruj sygnały, gdy transakcja otwarta
input ENUM_XL_SL     InpArSl         = SL_ATR;           // SL: ATR / ekstremum Aroon / knot / korpus / brak
input double         InpArSlBuf      = 0.0;              // Bufor SL (x ATR)
input ENUM_XL_TP     InpArTp         = TP_SL_MULTIPLE;   // TP: ATR / wielokrotność SL / sygnał przeciwny
input double         InpArSlMult     = 1.5;              // SL (x ATR) - tryb ATR
input double         InpArTpMult     = 3.0;              // TP (x ATR) - tryb ATR
input double         InpArTpRMult    = 1.0;              // TP (x SL) - tryb wielokrotność SL

input group "=== Stop Loss / Take Profit (wspólne) ==="
input bool           InpUseRisk      = true;             // Enable SL/TP (wył. = stop-and-reverse)
input ENUM_XL_EXIT   InpExitMode     = EXIT_WICK;        // Wyjście: knot (SL/TP u brokera) / zamknięcie świecy
input int            InpAtrLen       = 14;               // Długość ATR
input double         InpEmergencyAtr = 3.0;              // SL awaryjny przy braku SL (x ATR)
input double         InpCloseExtraAtr = 1.0;             // Tryb zamknięcia: twardy SL o tyle ATR dalej

input group "=== Filtr win rate (jak alerty) ==="
input bool           InpWrFilter     = false;            // Handluj tylko przy wysokim WR silnika (wirtualne transakcje)
input int            InpLookback     = 20;               // Liczba ostatnich zamkniętych transakcji
input double         InpWrMin        = 70.0;             // Min. win rate (%)

input group "=== Sesja (czas Nowego Jorku) ==="
input bool           InpSessionFilter    = false;        // Otwieraj tylko w oknie sesji
input string         InpSessStart        = "09:30";      // Początek okna (NY)
input string         InpSessEnd          = "15:55";      // Koniec okna (NY)
input bool           InpFlatAtSessionEnd = true;         // Zamknij wszystko poza oknem (gdy filtr wł.)
input int            InpServerToNYHours  = 7;            // Czas serwera minus czas Nowego Jorku (godz.). Korekta przy zmianie czasu!

//====================================================================
//  INPUTY - RISK MANAGER
//====================================================================
input group "=== Risk Manager ==="
input int           InpMagicNumber          = 260412;   // Magic number tej strategii
input double        InpMaxSpreadPoints      = 300;      // Maksymalny spread (punkty)
input int           InpSlippagePoints       = 50;       // Dopuszczalny poślizg (punkty)
input ENUM_LOT_MODE InpLotMode              = LOT_RISK_PERCENT; // % salda / stała kwota / stały lot
input double        InpRiskPercentPerTrade  = 1.0;      // % salda ryzykowany na transakcję
input double        InpRiskMoney            = 100.0;    // Kwota ryzyka na transakcję (waluta konta)
input double        InpFixedLot             = 0.30;     // Stały lot (gdy tryb = stały)
input double        InpMaxDailyDrawdownPct  = 3.0;      // Kill-switch dzienny (% equity)
input double        InpMaxTotalDrawdownPct  = 10.0;     // Kill-switch całkowity (% equity)

//====================================================================
//  INPUTY - LOGI
//====================================================================
input group "=== Logi ==="
input bool          InpLogSignals           = true;     // Loguj sygnały i decyzje
input bool          InpLogVirtual           = false;    // Loguj wyjścia wirtualne bez realnej pozycji

//====================================================================
//  NARZĘDZIA
//====================================================================
#define NA     EMPTY_VALUE
#define NOBAR  (-2147483647)
#define MT_SMA 0
#define MT_EMA 1
#define MT_WMA 2
#define MT_HMA 3
#define MT_RMA 4

bool IsNa(double x) { return x == NA; }

struct Hist { double v[]; int cap; int n; int head; };
void   HInit(Hist &h, int cap) { h.cap = MathMax(cap, 1); ArrayResize(h.v, h.cap); h.n = 0; h.head = -1; }
void   HPush(Hist &h, double x) { h.head = (h.head + 1) % h.cap; h.v[h.head] = x; if(h.n < h.cap) h.n++; }
double HGet(Hist &h, int k) { if(k < 0 || k >= h.n) return NA; int i = h.head - k; if(i < 0) i += h.cap; return h.v[i]; }
double SmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0;
   for(int k = 0; k < len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; s += x; }
   return s / len;
}
double WmaH(Hist &h, int len)
{
   if(h.n < len) return NA;
   double s = 0, w = 0;
   for(int k = 0; k < len; k++) { double x = HGet(h, k); if(IsNa(x)) return NA; double wt = len - k; s += x * wt; w += wt; }
   return s / w;
}

struct Rma { int n; double sum; double v; bool ready; };
void RmaReset(Rma &r) { r.n = 0; r.sum = 0; r.v = 0; r.ready = false; }
void RmaUpd(Rma &r, double x, int len) { if(!r.ready) { r.sum += x; r.n++; if(r.n >= len) { r.v = r.sum / len; r.ready = true; } } else r.v = (r.v * (len - 1) + x) / len; }

//--- uniwersalna średnia jak f_ma / f_smooth w Pine (EMA od pierwszej wartości, RMA od SMA)
struct MaCalc { int type; int len; int half; int sq; bool emaOk; double emaV; Rma r; Hist src; Hist diff; };
void MaInit(MaCalc &m, int type, int len)
{
   m.type = type; m.len = MathMax(1, len);
   m.half = MathMax(1, m.len / 2);
   m.sq = MathMax(1, (int)MathFloor(MathSqrt(m.len)));
   m.emaOk = false; m.emaV = 0; RmaReset(m.r);
   HInit(m.src, m.len + 1); HInit(m.diff, m.sq + 1);
}
double MaUpd(MaCalc &m, double x)
{
   HPush(m.src, x);
   if(m.type == MT_SMA) return SmaH(m.src, m.len);
   if(m.type == MT_WMA) return WmaH(m.src, m.len);
   if(m.type == MT_RMA) { RmaUpd(m.r, x, m.len); return m.r.ready ? m.r.v : NA; }
   if(m.type == MT_HMA)
   {
      double w1 = WmaH(m.src, m.half), w2 = WmaH(m.src, m.len);
      HPush(m.diff, (IsNa(w1) || IsNa(w2)) ? NA : 2 * w1 - w2);
      return WmaH(m.diff, m.sq);
   }
   double a = 2.0 / (m.len + 1);
   if(!m.emaOk) { m.emaV = x; m.emaOk = true; } else m.emaV = a * x + (1 - a) * m.emaV;
   return m.emaV;
}

bool CrossOver(double a, double b, double pa, double pb)  { return !IsNa(a) && !IsNa(b) && !IsNa(pa) && !IsNa(pb) && a > b && pa <= pb; }
bool CrossUnder(double a, double b, double pa, double pb) { return !IsNa(a) && !IsNa(b) && !IsNa(pa) && !IsNa(pb) && a < b && pa >= pb; }

int g_bars = 0;
double Hi(int s)  { return iHigh(_Symbol, _Period, s); }
double Lo(int s)  { return iLow(_Symbol, _Period, s); }
double Op(int s)  { return iOpen(_Symbol, _Period, s); }
double Cl(int s)  { return iClose(_Symbol, _Period, s); }
double Vol(int s) { return (double)iTickVolume(_Symbol, _Period, s); }
//--- ta.highest/ta.lowest(len) liczone od świecy "start" wstecz
double HiH(int start, int len) { if(len < 1 || start + len > g_bars) return NA; int i = iHighest(_Symbol, _Period, MODE_HIGH, len, start); return i < 0 ? NA : Hi(i); }
double LoH(int start, int len) { if(len < 1 || start + len > g_bars) return NA; int i = iLowest(_Symbol, _Period, MODE_LOW, len, start); return i < 0 ? NA : Lo(i); }
double SmaVol(int s, int len)  { if(len < 1 || s + len > g_bars) return NA; double t = 0; for(int k = 0; k < len; k++) t += Vol(s + k); return t / len; }
double SmaBody(int s, int len) { if(len < 1 || s + len > g_bars) return NA; double t = 0; for(int k = 0; k < len; k++) t += MathAbs(Cl(s + k) - Op(s + k)); return t / len; }
bool   VolOk(int s, double mult, int len) { if(mult <= 0) return true; double a = SmaVol(s, len); return !IsNa(a) && Vol(s) >= a * mult; }
double SrcOf(int s, ENUM_XL_SRC t)
{
   double o = Op(s), h = Hi(s), l = Lo(s), c = Cl(s);
   switch(t)
   {
      case XSRC_OPEN:  return o;
      case XSRC_HIGH:  return h;
      case XSRC_LOW:   return l;
      case XSRC_HL2:   return (h + l) / 2;
      case XSRC_HLC3:  return (h + l + c) / 3;
      case XSRC_OHLC4: return (o + h + l + c) / 4;
      default:         return c;
   }
}

//====================================================================
//  PARAMETRY AKTYWNEGO SILNIKA
//====================================================================
ENUM_XL_SL     SlSel()   { switch(InpEngine) { case ENG_OC: return InpOcSl; case ENG_BREAKOUT: return InpBrkSl; case ENG_DONCHIAN: return InpDonSl; case ENG_MA_CROSS: return InpMaSl; case ENG_AROON: return InpArSl; default: return InpStSl; } }
ENUM_XL_TP     TpSel()   { switch(InpEngine) { case ENG_OC: return InpOcTp; case ENG_BREAKOUT: return InpBrkTp; case ENG_DONCHIAN: return InpDonTp; case ENG_MA_CROSS: return InpMaTp; case ENG_AROON: return InpArTp; default: return InpStTp; } }
double         SlBufS()  { switch(InpEngine) { case ENG_OC: return InpOcSlBuf; case ENG_BREAKOUT: return InpBrkSlBuf; case ENG_DONCHIAN: return InpDonSlBuf; case ENG_MA_CROSS: return InpMaSlBuf; case ENG_AROON: return InpArSlBuf; default: return InpStSlBuf; } }
double         SlMultS() { switch(InpEngine) { case ENG_OC: return InpOcSlMult; case ENG_BREAKOUT: return InpBrkSlMult; case ENG_DONCHIAN: return InpDonSlMult; case ENG_MA_CROSS: return InpMaSlMult; case ENG_AROON: return InpArSlMult; default: return InpStSlMult; } }
double         TpMultS() { switch(InpEngine) { case ENG_OC: return InpOcTpMult; case ENG_BREAKOUT: return InpBrkTpMult; case ENG_DONCHIAN: return InpDonTpMult; case ENG_MA_CROSS: return InpMaTpMult; case ENG_AROON: return InpArTpMult; default: return InpStTpMult; } }
double         TpRMultS(){ switch(InpEngine) { case ENG_OC: return InpOcTpRMult; case ENG_BREAKOUT: return InpBrkTpRMult; case ENG_DONCHIAN: return InpDonTpRMult; case ENG_MA_CROSS: return InpMaTpRMult; case ENG_AROON: return InpArTpRMult; default: return InpStTpRMult; } }
ENUM_XL_SIGDIR SigDirS() { switch(InpEngine) { case ENG_OC: return InpOcSig; case ENG_BREAKOUT: return InpBrkSig; case ENG_DONCHIAN: return InpDonSig; case ENG_MA_CROSS: return InpMaSig; case ENG_AROON: return InpArSig; default: return InpStSig; } }
bool           NoOvlS()  { switch(InpEngine) { case ENG_OC: return InpOcNoOvl; case ENG_BREAKOUT: return InpBrkNoOvl; case ENG_DONCHIAN: return InpDonNoOvl; case ENG_MA_CROSS: return InpMaNoOvl; case ENG_AROON: return InpArNoOvl; default: return InpStNoOvl; } }

bool SlAllowed(ENUM_XL_SL m)
{
   switch(InpEngine)
   {
      case ENG_OC:         return m == SL_ATR || m == SL_CANDLE_WICK || m == SL_CANDLE_BODY || m == SL_NONE;
      case ENG_BREAKOUT:   return m == SL_ATR || m == SL_BASE_EDGE;
      case ENG_DONCHIAN:   return m == SL_ATR || m == SL_CHANNEL_OPPOSITE || m == SL_CHANNEL_MIDDLE || m == SL_CANDLE_WICK || m == SL_CANDLE_BODY || m == SL_NONE;
      case ENG_MA_CROSS:   return m == SL_ATR || m == SL_SWING || m == SL_CANDLE_WICK || m == SL_CANDLE_BODY || m == SL_NONE;
      case ENG_SUPERTREND: return m == SL_ATR || m == SL_SUPERTREND_LINE || m == SL_CANDLE_WICK || m == SL_CANDLE_BODY || m == SL_NONE;
      default:             return m == SL_ATR || m == SL_AROON_EXTREME || m == SL_CANDLE_WICK || m == SL_CANDLE_BODY || m == SL_NONE;
   }
}
bool TpAllowed(ENUM_XL_TP m) { return InpEngine == ENG_BREAKOUT ? m != TP_OPPOSITE_SIGNAL : m != TP_BASE_HEIGHT; }

//====================================================================
//  STAN ALGORYTMU
//====================================================================
ENUM_XL_SL g_sl; ENUM_XL_TP g_tp; ENUM_XL_SIGDIR g_sig;
bool   g_hasSl, g_hasTp, g_riskOn, g_bothExits, g_closeMode, g_alternate, g_noOverlap;
double g_slBuf, g_slMult, g_tpMult, g_tpRMult;

int      g_bar = -1;
datetime g_lastProcessedTime = 0;
bool     g_warmup = true;
int      g_sessStart = 0, g_sessEnd = 0;
string   EA_VERSION = "1.00";

Rma    g_atr;
//--- Supertrend (ta.supertrend)
Rma    g_stAtr; double g_stUp = NA, g_stLo = NA, g_stVal = NA; int g_stDir = 0; bool g_stPrevReady = false;
//--- MA Cross
MaCalc g_maF, g_maM, g_maS, g_maT;
double p_fast = NA, p_med = NA; bool p_alUp = false, p_alDn = false;
//--- Aroon
MaCalc g_arSU, g_arSD;
double p_arUp = NA, p_arDn = NA; bool p_arSB = false, p_arSS = false;
//--- Breakout: EMA trendu
bool   g_brkEmaOk = false; double g_brkEma = 0;

//--- wirtualna transakcja (stan jak w Pine)
int    v_dir = 0; bool v_in = false;
double v_entry = NA, v_sl = NA, v_tp = NA;
int    v_lastSig = NOBAR, v_lastExit = NOBAR;
double g_pnls[];      // P/L % ostatnich zamkniętych transakcji wirtualnych
int    g_vTrades = 0; // łącznie zamkniętych

//--- wynik ostatnio przetworzonej świecy
bool   r_buy = false, r_sell = false;
int    r_exit = 0;                        // 1 = TP, -1 = SL (wirtualnie, na tej świecy)
double r_lvlBuy = NA, r_lvlSell = NA;     // poziomy SL (bez trybu ATR)
double r_baseH = NA, r_atr = NA;

void RecordPnl(double pnl)
{
   int n = ArraySize(g_pnls);
   ArrayResize(g_pnls, n + 1);
   g_pnls[n] = pnl;
   if(ArraySize(g_pnls) > InpLookback) ArrayRemove(g_pnls, 0, ArraySize(g_pnls) - InpLookback);
   g_vTrades++;
}
double WinRate(int &cnt)
{
   cnt = ArraySize(g_pnls);
   if(cnt == 0) return 0;
   int w = 0;
   for(int i = 0; i < cnt; i++) if(g_pnls[i] > 0) w++;
   return 100.0 * w / cnt;
}

//--- f_varBase: najdłuższy ciąg świec przed sygnałem (min..cap) o wysokości <= rangeCap
void VarBase(int s, int minLen, int capLen, double rangeCap, double &bHi, double &bLo, int &bN)
{
   bHi = NA; bLo = NA; bN = 0;
   if(IsNa(rangeCap)) return;
   int lim = MathMin(capLen, g_bars - s - 1);
   if(lim < minLen) return;
   double rHi = Hi(s + 1), rLo = Lo(s + 1);
   for(int k = 1; k <= lim; k++)
   {
      rHi = MathMax(rHi, Hi(s + k));
      rLo = MathMin(rLo, Lo(s + k));
      if(rHi - rLo > rangeCap) break;
      if(k >= minLen) { bHi = rHi; bLo = rLo; bN = k; }
   }
}

//====================================================================
//  PRZETWORZENIE JEDNEJ ZAMKNIĘTEJ ŚWIECY (kolejność jak w Pine)
//====================================================================
void ProcessBar(int s)
{
   g_bar++;
   g_bars = Bars(_Symbol, _Period);
   g_lastProcessedTime = iTime(_Symbol, _Period, s);
   r_buy = r_sell = false; r_exit = 0;
   double o = Op(s), h = Hi(s), l = Lo(s), c = Cl(s);
   bool hasPrev = s + 1 < g_bars;
   double pc = hasPrev ? Cl(s + 1) : NA;

   double tr = hasPrev ? MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc))) : h - l;
   RmaUpd(g_atr, tr, InpAtrLen);
   double atr = g_atr.ready ? g_atr.v : NA;
   double bufD = IsNa(atr) ? 0.0 : g_slBuf * atr;

   bool rawBull = false, rawBear = false;
   double entBuy = c, entSell = c, lvlBuy = NA, lvlSell = NA, consHi = NA, consLo = NA;
   bool isMA = InpEngine == ENG_MA_CROSS, isBrk = InpEngine == ENG_BREAKOUT;
   double stValPrev = g_stVal;
   int    stDirPrev = g_stDir;

   //--- OC
   if(InpEngine == ENG_OC)
   {
      double body = MathAbs(c - o), avgB = SmaBody(s, InpOcBodyLen);
      double bHi1 = hasPrev ? MathMax(Op(s + 1), Cl(s + 1)) : NA, bLo1 = hasPrev ? MathMin(Op(s + 1), Cl(s + 1)) : NA;
      bool vOk = VolOk(s, InpOcVol, InpOcBodyLen);
      bool sizeOk = !IsNa(avgB) && body >= avgB * InpOcBodyMult;
      rawBull = !IsNa(bHi1) && c > o && c > bHi1 && sizeOk && vOk;
      rawBear = !IsNa(bLo1) && c < o && c < bLo1 && sizeOk && vOk;
   }
   //--- Donchian (bandy z poprzednich świec)
   if(InpEngine == ENG_DONCHIAN)
   {
      double upB = HiH(s + 1, InpDonLen), loB = LoH(s + 1, InpDonLen);
      double midB = (IsNa(upB) || IsNa(loB)) ? NA : (upB + loB) / 2;
      bool vOk = VolOk(s, InpDonVol, InpDonLen);
      rawBull = !IsNa(upB) && c > upB && vOk;
      rawBear = !IsNa(loB) && c < loB && vOk;
      if(InpDonEntry == ENT_CLOSE_EDGE) { entBuy = IsNa(upB) ? c : upB; entSell = IsNa(loB) ? c : loB; }
      if(g_sl == SL_CHANNEL_OPPOSITE) { lvlBuy = (IsNa(loB) ? l : loB) - bufD; lvlSell = (IsNa(upB) ? h : upB) + bufD; }
      if(g_sl == SL_CHANNEL_MIDDLE)   { lvlBuy = (IsNa(midB) ? entBuy : midB) - bufD; lvlSell = (IsNa(midB) ? entSell : midB) + bufD; }
   }
   //--- MA Cross
   if(isMA)
   {
      double px = SrcOf(s, InpMaSrc);
      double fM = MaUpd(g_maF, px), sM = MaUpd(g_maM, px);
      bool tri = InpMaMode == MAMODE_TRIPLE;
      double s3 = tri ? MaUpd(g_maS, px) : NA;
      double tM = InpMaTrend ? MaUpd(g_maT, px) : NA;
      bool vOk = VolOk(s, InpMaVol, InpMaMed);
      bool sepOk = InpMaMinSep <= 0 || (!IsNa(atr) && !IsNa(fM) && !IsNa(sM) && MathAbs(fM - sM) >= atr * InpMaMinSep);
      bool xUp = CrossOver(fM, sM, p_fast, p_med), xDn = CrossUnder(fM, sM, p_fast, p_med);
      bool alUp = !IsNa(fM) && !IsNa(sM) && !IsNa(s3) && fM > sM && sM > s3;
      bool alDn = !IsNa(fM) && !IsNa(sM) && !IsNa(s3) && fM < sM && sM < s3;
      bool trUp = !InpMaTrend || (!IsNa(tM) && c > tM), trDn = !InpMaTrend || (!IsNa(tM) && c < tM);
      rawBull = (tri ? alUp && !p_alUp : xUp) && vOk && sepOk && trUp;
      rawBear = (tri ? alDn && !p_alDn : xDn) && vOk && sepOk && trDn;
      p_fast = fM; p_med = sM; p_alUp = alUp; p_alDn = alDn;
      if(InpMaEntry == ENT_CLOSE_EDGE) { double me = MathMax(l, MathMin(h, IsNa(sM) ? c : sM)); entBuy = me; entSell = me; }
      if(g_sl == SL_SWING)
      {
         double swL = LoH(s, InpMaSwingLen), swH = HiH(s, InpMaSwingLen);
         lvlBuy = IsNa(swL) ? NA : swL - bufD; lvlSell = IsNa(swH) ? NA : swH + bufD;
      }
   }
   //--- Supertrend (ta.supertrend: hl2, ATR Wildera)
   if(InpEngine == ENG_SUPERTREND)
   {
      RmaUpd(g_stAtr, tr, InpStLen);
      if(g_stAtr.ready)
      {
         double hl2 = (h + l) / 2, up = hl2 + InpStMult * g_stAtr.v, lo = hl2 - InpStMult * g_stAtr.v;
         double pLo = IsNa(g_stLo) ? 0 : g_stLo, pUp = IsNa(g_stUp) ? 0 : g_stUp;
         lo = (lo > pLo || !hasPrev || pc < pLo) ? lo : pLo;
         up = (up < pUp || !hasPrev || pc > pUp) ? up : pUp;
         int dn;
         if(!g_stPrevReady) dn = 1;
         else if(stValPrev == pUp) dn = c > up ? -1 : 1;
         else dn = c < lo ? 1 : -1;
         g_stVal = dn == -1 ? lo : up; g_stDir = dn; g_stLo = lo; g_stUp = up;
      }
      g_stPrevReady = g_stAtr.ready;
      rawBull = g_stDir < 0 && stDirPrev > 0;
      rawBear = g_stDir > 0 && stDirPrev < 0;
      if(InpStEntry == ENT_CLOSE_EDGE) { double se = MathMax(l, MathMin(h, IsNa(stValPrev) ? c : stValPrev)); entBuy = se; entSell = se; }
      if(g_sl == SL_SUPERTREND_LINE && !IsNa(g_stVal)) { lvlBuy = g_stVal - bufD; lvlSell = g_stVal + bufD; }
   }
   //--- Aroon
   if(InpEngine == ENG_AROON)
   {
      double arUp = NA, arDn = NA;
      if(s + InpArLen + 1 <= g_bars)
      {
         int ih = iHighest(_Symbol, _Period, MODE_HIGH, InpArLen + 1, s), il = iLowest(_Symbol, _Period, MODE_LOW, InpArLen + 1, s);
         double rawU = 100.0 * (InpArLen + (s - ih)) / InpArLen, rawD = 100.0 * (InpArLen + (s - il)) / InpArLen;
         if(InpArSmooth == SM_NONE) { arUp = rawU; arDn = rawD; }
         else { arUp = MaUpd(g_arSU, rawU); arDn = MaUpd(g_arSD, rawD); }
      }
      bool vOk = VolOk(s, InpArVol, InpArVolLen);
      bool sB = !IsNa(arUp) && arUp >= InpArStrong && arDn <= 100.0 - InpArStrong;
      bool sS = !IsNa(arUp) && arDn >= InpArStrong && arUp <= 100.0 - InpArStrong;
      if(InpArMode == AR_CROSSOVER) { rawBull = CrossOver(arUp, arDn, p_arUp, p_arDn) && vOk; rawBear = CrossOver(arDn, arUp, p_arDn, p_arUp) && vOk; }
      else { rawBull = sB && !p_arSB && vOk; rawBear = sS && !p_arSS && vOk; }
      p_arUp = arUp; p_arDn = arDn; p_arSB = sB; p_arSS = sS;
      if(g_sl == SL_AROON_EXTREME)
      {
         double aH = HiH(s, InpArLen), aL = LoH(s, InpArLen);
         lvlBuy = IsNa(aL) ? NA : aL - bufD; lvlSell = IsNa(aH) ? NA : aH + bufD;
      }
   }
   //--- Breakout (konsolidacja + świeża baza)
   if(isBrk)
   {
      bool varB = InpBrkBaseMode == BASE_VARIABLE;
      if(InpBrkTrend) { double a = 2.0 / (InpBrkTrendLen + 1); if(!g_brkEmaOk) { g_brkEma = c; g_brkEmaOk = true; } else g_brkEma = a * c + (1 - a) * g_brkEma; }
      double fixHi = HiH(s + 1, InpBrkBaseLen), fixLo = LoH(s + 1, InpBrkBaseLen);
      int capLen = varB ? MathMax(InpBrkVarMax, InpBrkVarMin) : 0;
      if(v_lastSig != NOBAR) capLen = MathMin(capLen, g_bar - v_lastSig - 1);
      if(InpBrkNoBaseInTrade && g_riskOn)
         capLen = v_in ? 0 : (v_lastExit == NOBAR ? capLen : MathMax(0, MathMin(capLen, g_bar - v_lastExit - 1 - InpBrkBaseGap)));
      double vHi, vLo; int vN;
      VarBase(s, InpBrkVarMin, capLen, IsNa(atr) ? NA : atr * InpBrkBaseMult, vHi, vLo, vN);
      consHi = varB ? vHi : fixHi;
      consLo = varB ? vLo : fixLo;
      bool isBase = varB ? vN > 0 : (!IsNa(fixHi) && !IsNa(fixLo) && !IsNa(atr) && fixHi - fixLo <= atr * InpBrkBaseMult);
      double brkBuf = IsNa(atr) ? 0.0 : InpBrkMinBreak * atr;
      bool fresh = varB || ((v_lastSig == NOBAR || g_bar - v_lastSig > InpBrkBaseLen) &&
                            (!(InpBrkNoBaseInTrade && g_riskOn) || (!v_in && (v_lastExit == NOBAR || g_bar - v_lastExit > InpBrkBaseLen + InpBrkBaseGap))));
      bool wickM = InpBrkEntry == BRK_WICK_EDGE;
      bool upBr = !IsNa(consHi) && (wickM ? h : c) > consHi + brkBuf;
      bool dnBr = !IsNa(consLo) && (wickM ? l : c) < consLo - brkBuf;
      bool both = upBr && dnBr;
      bool vOk = InpBrkVol <= 0 || VolOk(s, InpBrkVol, InpBrkVolLen);
      rawBull = isBase && fresh && upBr && (!both || c > o) && (!InpBrkTrend || c > g_brkEma) && vOk;
      rawBear = isBase && fresh && dnBr && (!both || c < o) && (!InpBrkTrend || c < g_brkEma) && vOk;
      if(InpBrkEntry != BRK_CLOSE_ENTRY && !IsNa(consHi)) { entBuy = consHi + brkBuf; entSell = consLo - brkBuf; }
      if(g_sl == SL_BASE_EDGE && !IsNa(consLo)) { lvlBuy = consLo - bufD; lvlSell = consHi + bufD; }
   }
   //--- wspólne poziomy SL ze świecy
   if(g_sl == SL_CANDLE_WICK) { lvlBuy = l - bufD; lvlSell = h + bufD; }
   if(g_sl == SL_CANDLE_BODY) { lvlBuy = o - bufD; lvlSell = o + bufD; }

   double minD = isMA && !IsNa(atr) ? InpMaSlMin * atr : 0.0;
   double slBuyPx = NA, slSellPx = NA;
   if(g_hasSl)
   {
      if(g_sl == SL_ATR) { if(!IsNa(atr)) { slBuyPx = entBuy - atr * g_slMult; slSellPx = entSell + atr * g_slMult; } }
      else if(isMA) { if(!IsNa(lvlBuy)) slBuyPx = MathMin(lvlBuy, entBuy - minD); if(!IsNa(lvlSell)) slSellPx = MathMax(lvlSell, entSell + minD); }
      else { slBuyPx = lvlBuy; slSellPx = lvlSell; }
   }
   bool needStop = InpUseRisk && g_hasSl;
   bool okBuy  = !isBrk || !needStop || (!IsNa(slBuyPx) && slBuyPx < entBuy);
   bool okSell = !isBrk || !needStop || (!IsNa(slSellPx) && slSellPx > entSell);

   //--- blokady (Supertrend: wyjście na tej samej świecy nie blokuje zmiany kierunku)
   bool stSlPre = false, stTpPre = false;
   if(InpEngine == ENG_SUPERTREND && InpUseRisk && v_in)
   {
      stSlPre = g_hasSl && !IsNa(v_sl) && (g_closeMode ? (v_dir == 1 ? c <= v_sl : c >= v_sl) : (v_dir == 1 ? l <= v_sl : h >= v_sl));
      stTpPre = g_hasTp && !IsNa(v_tp) && !stSlPre && (g_closeMode ? (v_dir == 1 ? c >= v_tp : c <= v_tp) : (v_dir == 1 ? h >= v_tp : l <= v_tp));
   }
   bool blk = g_noOverlap && g_riskOn && v_in && !(stSlPre || stTpPre);
   bool buy  = rawBull && !(blk && (g_bothExits || v_dir == 1))  && (!g_alternate || v_dir != 1)  && okBuy  && g_sig != SIG_SELL_ONLY;
   bool sell = rawBear && !(blk && (g_bothExits || v_dir == -1)) && (!g_alternate || v_dir != -1) && okSell && g_sig != SIG_BUY_ONLY;

   //--- 1) wyjście wirtualne SL/TP (przy jednoczesnym dotknięciu najpierw SL)
   if(InpUseRisk && v_in)
   {
      bool slHit = g_hasSl && !IsNa(v_sl) && (g_closeMode ? (v_dir == 1 ? c <= v_sl : c >= v_sl) : (v_dir == 1 ? l <= v_sl : h >= v_sl));
      bool tpHit = g_hasTp && !IsNa(v_tp) && !slHit && (g_closeMode ? (v_dir == 1 ? c >= v_tp : c <= v_tp) : (v_dir == 1 ? h >= v_tp : l <= v_tp));
      if(slHit || tpHit)
      {
         double exitPx = g_closeMode ? c : (slHit ? v_sl : v_tp);
         RecordPnl(v_dir * (exitPx - v_entry) / v_entry * 100);
         v_in = false; v_lastExit = g_bar;
         r_exit = slHit ? -1 : 1;
      }
   }
   //--- 2) nowy sygnał: zamknięcie (odwrócenie) i nowa transakcja
   if(buy || sell)
   {
      if(v_in) RecordPnl(v_dir * (c - v_entry) / v_entry * 100);
      v_dir = buy ? 1 : -1;
      v_lastSig = g_bar;
      v_entry = v_dir == 1 ? entBuy : entSell;
      v_in = true;
      v_sl = !g_hasSl ? NA : (v_dir == 1 ? slBuyPx : slSellPx);
      double riskD = IsNa(v_sl) ? NA : MathAbs(v_entry - v_sl);
      double tpD = g_tp == TP_ATR_TARGET ? (IsNa(atr) ? NA : atr * g_tpMult)
                 : g_tp == TP_BASE_HEIGHT ? ((IsNa(consHi) || IsNa(consLo)) ? NA : (consHi - consLo) * InpBrkTpBMult)
                 : (IsNa(riskD) ? NA : riskD * g_tpRMult);
      v_tp = (!g_hasTp || IsNa(tpD)) ? NA : v_entry + v_dir * tpD;
      r_buy = buy; r_sell = !buy;
   }
   r_lvlBuy = lvlBuy; r_lvlSell = lvlSell; r_atr = atr;
   r_baseH = (IsNa(consHi) || IsNa(consLo)) ? NA : consHi - consLo;
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
//  HANDEL
//====================================================================
int MyPositions(ulong &out[], int &dir)
{
   ulong all[];
   int n = PM_GetOpenPositionsByMagic(InpMagicNumber, all);
   ArrayResize(out, 0);
   dir = 0;
   for(int i = 0; i < n; i++)
   {
      if(!PositionSelectByTicket(all[i]) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = all[i];
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   }
   return ArraySize(out);
}

bool CloseMine(string reason)
{
   ulong tk[]; int dir;
   int n = MyPositions(tk, dir);
   for(int i = 0; i < n; i++) PM_ClosePosition(tk[i], reason);
   return MyPositions(tk, dir) == 0;
}

string SigKey() { return StringFormat("XLSIG_%d_%s", InpMagicNumber, _Symbol); }
bool SignalAlreadyTraded(datetime bt) { if(MQLInfoInteger(MQL_TESTER)) return false; return GlobalVariableCheck(SigKey()) && (datetime)GlobalVariableGet(SigKey()) >= bt; }
void MarkSignalTraded(datetime bt) { if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(SigKey(), (double)bt); }

double LotFor(double slDist)
{
   if(InpLotMode == LOT_FIXED) return InpFixedLot;
   double pct = InpRiskPercentPerTrade;
   if(InpLotMode == LOT_RISK_MONEY)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal <= 0) return 0;
      pct = InpRiskMoney / bal * 100.0;
   }
   return RM_CalculateLotSizeByRiskStrict(_Symbol, pct, slDist / _Point);
}

//--- realne wejście; SL/TP od faktycznej ceny wejścia (poziomy SL z Pine bez zmian, TP przeliczany)
bool OpenReal(int d)
{
   datetime sigTime = iTime(_Symbol, _Period, 1);
   if(SignalAlreadyTraded(sigTime)) { EE_LogDecision("XL", "SKIPPED_DUPLICATE", "Sygnał już obsłużony"); return false; }
   if(!RM_IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints)) return false;
   if(IsNa(r_atr) || r_atr <= 0) { if(InpLogSignals) Print("[XL] pominięty: brak ATR"); return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   double entry = d == 1 ? tick.ask : tick.bid;
   bool useSl = InpUseRisk && g_hasSl;
   double slLogic = NA, tpLogic = NA;
   if(useSl)
   {
      if(g_sl == SL_ATR) slLogic = entry - d * r_atr * g_slMult;
      else
      {
         double lvl = d == 1 ? r_lvlBuy : r_lvlSell;
         if(IsNa(lvl)) { if(InpLogSignals) Print("[XL] pominięty: brak poziomu SL"); return false; }
         if(InpEngine == ENG_MA_CROSS) lvl = d == 1 ? MathMin(lvl, entry - InpMaSlMin * r_atr) : MathMax(lvl, entry + InpMaSlMin * r_atr);
         slLogic = lvl;
      }
      if((entry - slLogic) * d <= 0)
      {
         if(InpLogSignals) PrintFormat("[XL] pominięty: cena %s już za poziomem SL %s", DoubleToString(entry, _Digits), DoubleToString(slLogic, _Digits));
         return false;
      }
   }
   double riskD = useSl ? MathAbs(entry - slLogic) : NA;
   if(InpUseRisk && g_hasTp)
   {
      double tpD = g_tp == TP_ATR_TARGET ? r_atr * g_tpMult
                 : g_tp == TP_BASE_HEIGHT ? (IsNa(r_baseH) ? NA : r_baseH * InpBrkTpBMult)
                 : (IsNa(riskD) ? NA : riskD * g_tpRMult);
      if(!IsNa(tpD) && tpD > 0) tpLogic = entry + d * tpD;
   }
   double brokerSl = !useSl ? entry - d * InpEmergencyAtr * r_atr
                   : g_closeMode ? slLogic - d * InpCloseExtraAtr * r_atr : slLogic;
   double brokerTp = (g_closeMode || IsNa(tpLogic)) ? 0 : tpLogic;
   brokerSl = NormalizeDouble(brokerSl, _Digits);
   if(brokerTp > 0) brokerTp = NormalizeDouble(brokerTp, _Digits);

   double vol = LotFor(MathAbs(entry - brokerSl));
   if(vol <= 0) return false;
   ENUM_ORDER_TYPE type = d == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!RM_HasSufficientMargin(_Symbol, vol, type)) return false;
   string tag = StringFormat("xl%d_%s_%d", (int)InpEngine, d == 1 ? "L" : "S", (int)sigTime);
   ExecutionResult res = PM_OpenPosition(_Symbol, type, vol, brokerSl, brokerTp, InpMagicNumber, tag, InpMaxSpreadPoints, InpSlippagePoints);
   EE_LogDecision(tag, res == EXEC_CONFIRMED ? "ENTRY_OK" : res == EXEC_FAILED ? "ENTRY_FAILED" : "ENTRY_UNCERTAIN",
                  StringFormat("%s %s vol=%.2f entry=%s SL=%s%s TP=%s%s ATR=%s", EnumToString(InpEngine), d == 1 ? "LONG" : "SHORT", vol,
                               DoubleToString(entry, _Digits), DoubleToString(brokerSl, _Digits),
                               !useSl ? " (awaryjny)" : g_closeMode ? " (twardy; logiczny " + DoubleToString(slLogic, _Digits) + ")" : "",
                               IsNa(tpLogic) ? "-" : DoubleToString(tpLogic, _Digits), g_closeMode && !IsNa(tpLogic) ? " (na zamknięciu)" : "",
                               DoubleToString(r_atr, _Digits)));
   if(res == EXEC_FAILED) return false;
   MarkSignalTraded(sigTime);
   // wirtualna transakcja przejmuje realne poziomy, żeby wyjścia wirtualne i u brokera się pokrywały
   v_entry = entry; v_sl = useSl ? slLogic : NA; v_tp = tpLogic;
   return true;
}

void OnBarClosed()
{
   ulong tk[]; int rd;
   int n = MyPositions(tk, rd);

   // wyjście wirtualne SL/TP zamyka realną pozycję (tryb zamknięcia; w trybie knota zwykle zrobił to już broker)
   if(r_exit != 0)
   {
      if(n > 0)
      {
         if(InpLogSignals) Print("[XL] wyjście ", r_exit == 1 ? "TP" : "SL", " (", g_closeMode ? "zamknięcie świecy" : "knot", ") - zamykam pozycję");
         CloseMine(r_exit == 1 ? "virtual_tp" : "virtual_sl");
      }
      else if(InpLogVirtual) Print("[XL] wirtualne wyjście ", r_exit == 1 ? "TP" : "SL", " (brak realnej pozycji)");
      n = MyPositions(tk, rd);
   }

   // nowy sygnał
   if(r_buy || r_sell)
   {
      int d = r_buy ? 1 : -1;
      int cnt; double wr = WinRate(cnt);
      if(InpLogSignals) PrintFormat("[XL] sygnał %s (%s) | WR wirtualny %.0f%% z %d", d == 1 ? "BUY" : "SELL", EnumToString(InpEngine), wr, cnt);
      if(n > 0)
      {
         if(!CloseMine(rd == d ? "signal_exit" : "reverse_on_opposite")) { EE_LogDecision("XL", "BLOCKED", "Nie udało się zamknąć poprzedniej pozycji"); return; }
         n = 0;
      }
      bool ok = true;
      if(!InSession(iTime(_Symbol, _Period, 0))) { ok = false; if(InpLogSignals) Print("[XL] realne wejście pominięte: poza oknem sesji"); }
      if(ok && InpWrFilter && (cnt < InpLookback || wr < InpWrMin))
      {
         ok = false;
         if(InpLogSignals) PrintFormat("[XL] realne wejście pominięte: filtr WR (%.0f%% z %d, wymagane %.0f%% z %d)", wr, cnt, InpWrMin, InpLookback);
      }
      if(ok) OpenReal(d);
      n = MyPositions(tk, rd);
   }

   // realna pozycja bez odpowiednika w stanie wirtualnym (np. po restarcie) - zamknij
   if(n > 0 && (!v_in || v_dir != rd))
   {
      if(InpLogSignals) Print("[XL] pozycja niezgodna ze stanem silnika - zamykam");
      CloseMine("state_sync");
   }
}

//====================================================================
//  ZDARZENIA EA
//====================================================================
int OnInit()
{
   g_sl = SlSel(); g_tp = TpSel(); g_sig = SigDirS();
   if(!SlAllowed(g_sl)) { Print("XL: wybrany tryb SL nie jest dostępny dla silnika ", EnumToString(InpEngine)); return INIT_PARAMETERS_INCORRECT; }
   if(!TpAllowed(g_tp)) { Print("XL: wybrany tryb TP nie jest dostępny dla silnika ", EnumToString(InpEngine)); return INIT_PARAMETERS_INCORRECT; }
   g_sessStart = ParseHHMM(InpSessStart); g_sessEnd = ParseHHMM(InpSessEnd);
   if(g_sessStart < 0 || g_sessEnd < 0) { Print("XL: błędny format godzin sesji (HH:MM)"); return INIT_PARAMETERS_INCORRECT; }
   if(InpAtrLen < 1 || InpLookback < 1 || InpWarmupBars < 300 || InpEmergencyAtr <= 0) return INIT_PARAMETERS_INCORRECT;

   g_slBuf = SlBufS(); g_slMult = SlMultS(); g_tpMult = TpMultS(); g_tpRMult = TpRMultS();
   g_noOverlap = NoOvlS();
   g_alternate = g_sig == SIG_ALTERNATE;
   g_hasSl = g_sl != SL_NONE;
   g_hasTp = g_tp != TP_OPPOSITE_SIGNAL && !(g_tp == TP_SL_MULTIPLE && !g_hasSl);
   g_riskOn = InpUseRisk && (g_hasSl || g_hasTp);
   g_bothExits = g_hasSl && g_hasTp;
   g_closeMode = InpExitMode == EXIT_CLOSE;

   RmaReset(g_atr); RmaReset(g_stAtr);
   MaInit(g_maF, (int)InpMaType, InpMaFast); MaInit(g_maM, (int)InpMaType, InpMaMed);
   MaInit(g_maS, (int)InpMaType, InpMaSlow); MaInit(g_maT, (int)InpMaType, InpMaTrendLen);
   int smType = InpArSmooth == SM_SMA ? MT_SMA : InpArSmooth == SM_EMA ? MT_EMA : InpArSmooth == SM_RMA ? MT_RMA : InpArSmooth == SM_WMA ? MT_WMA : MT_HMA;
   int smLen = InpArSmooth == SM_HMA ? MathMax(2, InpArSmLen) : InpArSmLen;
   MaInit(g_arSU, smType, smLen); MaInit(g_arSD, smType, smLen);
   ArrayResize(g_pnls, 0);
   RC_ReconcileState(InpMagicNumber);

   // odtworzenie stanu silnika i wirtualnych transakcji z historii (bez handlu)
   g_warmup = true;
   int bars = Bars(_Symbol, _Period);
   int start = (int)MathMin(InpWarmupBars, bars - 2);
   for(int s = start; s >= 1; s--) ProcessBar(s);
   g_warmup = false;
   UT_IsNewBar(_Symbol, PERIOD_CURRENT);
   EventSetTimer(15);
   int cnt; double wr = WinRate(cnt);
   double net = 1; for(int i = 0; i < cnt; i++) net *= 1 + g_pnls[i] / 100;
   PrintFormat("XL EA %s: silnik %s | przeliczono %d świec | transakcji wirtualnych %d | ostatnie %d: WR %.0f%%, net %+.2f%% | stan: %s | SL %s, TP %s, wyjście %s",
               EA_VERSION, EnumToString(InpEngine), start, g_vTrades, cnt, wr, (net - 1) * 100,
               v_in ? (v_dir == 1 ? "LONG" : "SHORT") : "płasko", EnumToString(g_sl), EnumToString(g_tp), EnumToString(InpExitMode));
   if(!InpUseRisk || !g_hasSl) PrintFormat("Uwaga: brak SL w logice silnika - u brokera ustawiany SL awaryjny %.1f x ATR", InpEmergencyAtr);
   ulong tk[]; int rd;
   if(MyPositions(tk, rd) > 0 && (!v_in || v_dir != rd)) Print("Uwaga: otwarta pozycja niezgodna z odtworzonym stanem silnika - zostanie zamknięta na zamknięciu świecy");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()
{
   if(RM_CheckKillSwitch(InpMagicNumber, InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct)) return;
   if(InpSessionFilter && InpFlatAtSessionEnd && !InSession(TimeCurrent()))
   {
      ulong tk[]; int rd;
      if(MyPositions(tk, rd) > 0) { if(InpLogSignals) Print("[XL] koniec okna sesji - zamykam pozycje"); CloseMine("session_end"); }
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

void OnTimer() { RC_ReconcileState(InpMagicNumber); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      RC_RegisterTicket(InpMagicNumber, (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
}
