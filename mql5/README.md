# CISD Model EA (MQL5)

Expert Advisor na MetaTrader 5 przeniesiony ze wskaźnika Pine Script **„CISD Model+ | Authrain Trades”**.
Przygotowany pod **NAS100 (Nasdaq)** z SMT względem **US500**.

## Instalacja
1. W MetaTrader 5: **Plik → Otwórz folder danych**, potem wejdź w `MQL5`.
2. Skopiuj `MQL5/Include/Core/*.mqh` do `MQL5/Include/Core/` (utwórz folder `Core`, jeśli go nie ma).
3. Skopiuj `MQL5/Experts/CISD_Model_EA.mq5` do `MQL5/Experts/`.
4. Otwórz plik w MetaEditorze (F4) i skompiluj (F7).
5. W Market Watch upewnij się, że widać oba symbole. Brokerzy często dodają przyrostki, na przykład `NAS100.cash` i `US500.cash`. W takim przypadku wpisz właściwą nazwę w input **„Symbol skorelowany do SMT”**.
6. Przeciągnij EA na wykres NAS100 i włącz **Algo Trading**.

**Zanim użyjesz prawdziwych pieniędzy:** przetestuj EA w Strategy Testerze (tryb „Every tick based on real ticks”), a potem na koncie demo.

## Jak działa
Logika liczy się wyłącznie na **zamkniętych świecach**. Każda świeca jest przetwarzana raz, w kolejności, tak samo jak Pine przechodzi historię. Przy starcie EA przelicza `InpWarmupBars` świec wstecz, żeby odtworzyć stan wskaźnika: płynność, sesje, FVG i aktywne CISD.

Warunki wejścia:
1. Maszyna stanu CISD wykrywa zmianę charakteru dostarczenia (CISD).
2. W ostatnich 15 świecach było jedno z dwóch:
   - zebrana płynność, czyli sweep pivotu na bieżącym interwale albo na H1;
   - dotknięcie FVG z bieżącego interwału.
3. CISD nie leży bliżej niż 0,75×ATR od innego aktywnego CISD w tym samym kierunku.
4. Ocena z checklisty (sweep, HTF FVG, wolumen, sesja, cel, SMT) wynosi co najmniej `InpMinGradeTrade` (domyślnie B-).
5. Świeca mieści się w oknie handlu 06:00–16:00 czasu Nowego Jorku.

Zarządzanie pozycją:
- **Wejście:** rynkowe po zamknięciu świecy albo zlecenie limit na poziomie CISD, anulowane po `InpLimitExpiryBars` świecach lub gdy setup zostanie unieważniony.
- **SL:** pivot sekwencji plus spread, plus opcjonalny bufor.
- **TP:** najbliższy niezebrany poziom (Asia/London H/L, PDH/PDL, PWH/PWL), jeśli daje RR ≥ 1,5. W przeciwnym razie stałe 1,5R.
- **Pozycje:** maksymalnie 1 naraz. Przeciwny CISD zamyka pozycję i otwiera nową w drugą stronę.
- **Ryzyko:** 1% salda na transakcję. Jeśli nawet minimalny lot przekracza ryzyko, EA pomija wejście.

Warstwa wykonania (`Include/Core`) zawiera:
- weryfikację każdego zlecenia na serwerze;
- ochronę przed zdublowanymi zleceniami;
- uzgadnianie stanu z kontem;
- limit spreadu;
- kontrolę marginu;
- kill-switch dzienny (3%) i całkowity (10%).

## Ustaw przed startem
- **`InpServerToNYHours`**, czyli różnica czasu serwera i Nowego Jorku. U typowego brokera GMT+2/+3 wynosi 7. Sprawdź to u swojego brokera i **skoryguj przy zmianach czasu**: Europa i USA przestawiają zegary w różnych tygodniach.
- **`InpMaxSpreadPoints`**: ustaw według typowego spreadu NAS100 u swojego brokera, w punktach.
- **`InpMagicNumber`**: musi być unikalny, jeśli na koncie działa więcej EA.

## Założenia i różnice wobec oryginału Pine
Te punkty trzeba mieć na uwadze, porównując backtest MT5 z TradingView:

1. **Zamknięte świece.** W Pine CISD potwierdza się na bieżącej świecy, więc na żywo sygnał może się pojawiać i znikać. EA decyduje po zamknięciu świecy i wchodzi na otwarciu następnej.
2. **ATR** jest liczony ręcznie metodą Wildera (RMA), jak `ta.atr`, bo wbudowany `iATR` w MT5 używa zwykłej średniej (SMA).
3. **Wolumen.** Na CFD dostępny jest tylko **wolumen tickowy**. Na TradingView kontrakty futures mają prawdziwy wolumen, więc punkt „Volume” może wypadać inaczej.
4. **Sesje** są przeliczane ze stałym przesunięciem `InpServerToNYHours`. Pine automatycznie uwzględnia zmianę czasu w Nowym Jorku.
5. **Dzień i tydzień dla PDH/PDL/PWH/PWL** wyznaczają świece D1 i W1 brokera (zwykle start o 17:00 NY). TradingView używa sesji giełdy danego symbolu.
6. **Pivoty** muszą być ostro wyższe lub niższe od sąsiednich świec. Przy idealnie równych cenach wynik może się minimalnie różnić od `ta.pivothigh/low`.
7. **SMT** porównuje US500 w momencie danej świecy NAS100; brakującą świecę zastępuje poprzednia, jak `gaps_off`. Zgodnie z kodem oryginału **SMT wpływa tylko na ocenę i nie przepuszcza CISD bez sweepu ani FVG**, choć opis wskaźnika sugeruje inaczej.
8. **SL „Body” = „Wick”.** W oryginale obie opcje dają ten sam poziom (pivot), dlatego EA ma jedną opcję.
9. **Dostarczenie z FVG bieżącego interwału** w oryginale jest zaliczane już na świecy, która tworzy FVG (warunek `low <= top` jest wtedy spełniony od razu). Zachowuję to zachowanie.
10. **Automatycznie dobrane HTF dla FVG** (np. H1/H4 dla wykresu M5) są brane z ostatnich zamkniętych świec HTF, bez repaintu. Dla MN1 sprawdzenie, czy świeca jest zamknięta, jest przybliżone.
11. **Pominięte, bo czysto wizualne lub tylko alertowe:** linie, etykiety, tabele, watermark, „Potential CISD”, wyższe interwały CISD (w oryginale domyślnie wyłączone), alerty TradingView. Zastępuje je dziennik w zakładce „Experts” terminala.
12. **Inputy „Show ...”, które w oryginale sterują logiką, są w EA funkcjonalne:**
    - `Show CISD` → `InpTradingEnabled`;
    - `Show HTF FVGs` → `InpUseHtfFvg`;
    - `Show Session Liquidity` → `InpUseSessionLiq`;
    - `Number of Setups Displayed` → `InpSetupsTracked`;
    - `Max Liquidity Levels` → `InpLiqMaxLevels`.
13. **Zlecenia limit** są typu GTC. Wygasanie po N świecach obsługuje EA, bo nie każdy broker wspiera zlecenia z datą wygaśnięcia.

---

# AlphaX Prime EA (MQL5)

EA przeniesiony ze wskaźnika Pine **„[ALPHAX] PRIME”**. Przygotowany pod **NAS100 na M5** (bias wyższego interwału z M15).
Plik: `MQL5/Experts/AlphaX_Prime_EA.mq5`. Korzysta z tego samego rdzenia `Include/Core` co EA CISD, rozszerzonego o `PM_ClosePartial`. Instalacja i kompilacja wyglądają tak samo jak w EA CISD.

## Jak działa
**Wejście** (zamknięta świeca, wejście na otwarciu następnej):
1. Supertrend (10, ×3) jest w kierunku transakcji, a ta świeca nie jest świecą jego zwrotu.
2. Close przecina EMA9 w kierunku transakcji i leży po właściwej stronie EMA21.
3. Jakość wynosi co najmniej 4/14, nie trwa inna transakcja i minęło 5 świec od ostatniego wejścia.

**Ocena jakości (0–14)** sumuje: trend na bieżącym interwale, bias z M15, ADX ≥ 25, wolumen, rosnący histogram MACD, ułożenie EMA, strefę RSI, świeży squeeze, bliskość Fibonacciego i sesję London/NY (UTC).

**Zarządzanie pozycją:**
- **SL** = 5×ATR × (0,8 + 0,6 × percentyl ATR ze 100 świec), czyli 4–7 ATR.
- **TP1 / TP2 / TP3** = 0,5 / 0,84 / 1,36 × ryzyko. Domyślnie 1/3 pozycji zamyka się na TP1, 1/3 na TP2, a reszta na TP3 (TP po stronie brokera). Gdy wolumen jest za mały na trzy części, całość idzie na TP3.
- **Break-even po TP1** jest opcjonalny i domyślnie wyłączony, jak w oryginale.
- **Limit czasu:** pozycja zamyka się po 300 świecach.
- **Brak odwracania:** w trakcie transakcji nowe sygnały są ignorowane.

## Ustaw przed startem
- `InpServerToUTCHours`: przesunięcie czasu serwera względem UTC, używane **tylko w testerze**. Na koncie live EA liczy je automatycznie z zegara serwera. U typowego brokera to 2 zimą i 3 latem.
- `InpMaxSpreadPoints`: według spreadu NAS100 u Twojego brokera.
- Szeroki SL przy TP3 = 1,36R daje małe loty przy ryzyku 1%. Upewnij się, że minimalny lot u brokera to umożliwia. Jeśli nie, EA pominie wejście i zapisze powód w logu.

## Założenia i różnice wobec oryginału Pine
1. **Wskaźniki są liczone ręcznie, jak w Pine.** Wbudowane funkcje MT5 wygładzają inaczej:
   - ATR i ADX: metoda Wildera (RMA), jak `ta.atr` i `ta.dmi`;
   - linia sygnału MACD: EMA (w `iMACD` jest SMA);
   - odchylenie standardowe w Bollingerze: populacyjne;
   - EMA: start od pierwszej wartości.

   Wszystko liczę z 900 ostatnich świec. Przy EMA200 różnica startu jest pomijalna, ale **pierwsze świece wykresu mogą się minimalnie różnić od TradingView**.
2. **Bias M15** pochodzi z ostatniej zamkniętej świecy M15, jak `[1]` z `lookahead_on` w oryginale. Nie ma repaintu.
3. **Wolumen.** Na CFD dostępny jest tylko wolumen tickowy. Punkt „relVol ≥ 1” może wypadać inaczej niż na kontraktach futures.
4. **TP1 i TP2** EA sprawdza na bieżącej cenie (bid dla longa, ask dla shorta). Oryginał sprawdza high/low zamkniętej świecy i przy jednoczesnym dotknięciu SL i TP w tej samej świecy liczy najpierw SL. W realnym handlu kolejność wyznacza faktyczny ruch ceny.
5. **Poziomy SL/TP** liczę od faktycznej ceny wejścia (ask/bid), a nie od close świecy sygnałowej. Odległości są te same.
6. **Pominięte, bo czysto wizualne:** panel v2/v4, Stochastic, Choppiness, prawdopodobieństwa celów („Target Outlook”), etykiety BUY/SELL (zwroty Supertrendu nie są w oryginale wejściami), sygnały „Watch”, ostrzeżenia o wyczerpaniu ruchu, kolorowanie świec i alerty.

---

# SFX Algo EA (MQL5)

EA przeniesiony ze wskaźnika Pine **„Flux Charts™ - SFX Algo”**. Przygotowany pod **NAS100 na M15** z profilem „Swing Trader”.
Plik: `MQL5/Experts/SFX_Algo_EA.mq5`. Korzysta z rdzenia `Include/Core` (w tym `PM_ClosePartial`).

## Jak działa
- **Trail SFX:** linia trailingowa ATR × mnożnik zależny od czułości (75 → 1,875). Jej zwrot otwiera okno 3 świec na sygnał.
- **Sześciu „ekspertów”:** RSI, MACD, Supertrend, kanał EMA±ATR, EMA fast/slow i nachylenie EMA głosują na kierunek. Ich wagi są uczone algorytmem *multiplicative weights*: kara za każdy błędny głos z ostatnich 45 świec.
- **Sygnał:** udział ważonych głosów w kierunku trailu ≥ Signal Strength (25%) i ocena ≥ 4★ (udział ≥ 60%).
- **TP1/TP2/TP3 i SL:** 4 metody do wyboru, domyślnie Key Levels:
  - TP to trzy kolejne pivoty (długość 8), oddalone od siebie co najmniej o 0,5 ATR;
  - SL to najbliższy przeciwny pivot plus 0,1 ATR (gdy go brak: 2 ATR).
- **Wyjścia:** domyślnie 1/3 pozycji na TP1, 1/3 na TP2, reszta na TP3. Tryb `TP_NONE_ORIGINAL` zachowuje się jak oryginał: trzyma pozycję do SL albo przeciwnego sygnału.
- **Przeciwny sygnał:** zamyka pozycję i otwiera nową w drugą stronę. Sygnał w tym samym kierunku jest ignorowany.
- **Opcje:** AI Sensitivity Optimizer (10 kandydatów czułości), break-even po TP1, okno handlu. Wszystkie domyślnie wyłączone, jak w oryginale.

## Założenia i różnice wobec oryginału Pine
1. **Zamknięte świece.** Oryginał nie czeka na zamknięcie świecy, więc na żywo trail może się zwrócić i cofnąć w jej trakcie. EA decyduje po zamknięciu i wchodzi na otwarciu następnej świecy.
2. **Stan liczony od początku rozgrzewki.** EA liczy stan przyrostowo od `InpWarmupBars` świec wstecz, Pine od początku historii wykresu. Elementy z długą pamięcią mogą się przez to minimalnie różnić od TradingView: wagi ekspertów, wynik optymalizatora AI (start po 200 świecach) i EMA.
3. **Wskaźniki są liczone ręcznie, jak w Pine.** Wbudowane funkcje MT5 wygładzają inaczej:
   - ATR i RSI: metoda Wildera (RMA);
   - linia sygnału MACD: EMA;
   - EMA: start od pierwszej wartości;
   - odchylenie standardowe: populacyjne;
   - Supertrend: według algorytmu `ta.supertrend`.
4. **Poziomy kluczowe** to wszystkie pivoty z pamięci (ostatnie 60 z każdej strony), także już przebite, tak jak w oryginale.
5. **Poziomy TP/SL** liczę od faktycznej ceny wejścia (ask/bid), a nie od close świecy sygnałowej. W metodach Key Levels i Volatility Bands poziomy są bezwzględne, zmienia się tylko punkt odniesienia odległości.
6. **TP1 i TP2** EA sprawdza na bieżącej cenie, a oryginał na high/low świecy.
7. **Auto Stop-Loss jest zawsze włączony.** EA nie handluje bez SL.
8. **Pominięte:** optymalizacja TP po MFE (metoda Dynamic, w oryginale domyślnie wyłączona), aktualizacje oceny po wejściu (tylko etykiety i alerty), dashboard trendów MTF, Gauss Ribbon, Retracement Wave, kolorowanie świec, etykiety, linie realtime, alerty i webhooki.

---

# STRB EA (MQL5): Season Timed Range Breakout

EA przeniesiony ze wskaźnika Pine **„Season Timed Range Breakout (STRB)”** (OlympusCipher). Przygotowany pod **NAS100 na M5**.
Plik: `MQL5/Experts/STRB_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Jak działa
- **Trzy okna** (czas Nowego Jorku):

  | Okno | Zakres | Sesja handlowa |
  |---|---|---|
  | NY | 09:30–09:45 | 09:30–16:00 |
  | LON | 04:00–05:00 | 03:00–11:00 |
  | ASIA | 20:00–21:00 | 20:00–04:00 |

  Okna 2 i 3 można wyłączyć. Zamiast okna czasowego zakres może tworzyć „pierwsze N świec” sesji.
- **Breakout:** po zakończeniu zakresu, w trakcie sesji handlowej, świeca **zamyka się** za RH/RL (opcjonalnie: przebija knotem; opcjonalny bufor w tickach). Domyślnie tylko pierwszy breakout na sesję.
- **Opcjonalne filtry** (domyślnie wyłączone): zakres 10–60% dziennego ATR z poprzedniego dnia, względny wolumen ≥ 1,2×, położenie względem VWAP.
- **Poziomy z oryginału** (bezwzględne, liczone od brzegu zakresu):
  - SL = RH − 1,2 × zakres dla longa (albo % ceny);
  - T1/T2/T3 = RH + 0,5 / 1 / 2 × zakres.
- **Wejście:** rynkowe na otwarciu świecy po breakoucie albo **limit na RH/RL** (retest). Zlecenie limit wygasa z końcem sesji okna.
- **Wyjścia:** 1/3 pozycji na T1, 1/3 na T2, reszta na T3. Co zostanie, jest zamykane **na końcu sesji okna**, jak w oryginale. Opcjonalnie EA zamyka pozycję przy nieudanym breakoucie (zamknięcie świecy z powrotem w zakresie).
- **Limit pozycji:** domyślnie 1 łącznie. Opcja: 1 na każde okno (do 3 pozycji, łączne ryzyko do 3%).

## Ustaw przed startem
- `InpServerToNYHours`: różnica czasu serwera i Nowego Jorku. Domyślnie 7. **Koryguj przy zmianach czasu**, bo Europa i USA przestawiają zegary w różnych tygodniach.
- Interwał wykresu musi pasować do okien. Na M5 zakres NY 09:30–09:45 to 3 świece.

## Założenia i różnice wobec oryginału Pine
1. **Wejście.** Oryginał zakłada wejście dokładnie na RH/RL, a EA w trybie rynkowym wchodzi po cenie z otwarcia następnej świecy. Poziomy SL i T1–T3 zostają bezwzględne, więc rzeczywiste RR jest nieco gorsze niż w statystykach wskaźnika. Tryb limit odtwarza wejście na poziomie, ale tylko wtedy, gdy cena wróci do RH/RL.
2. **Wyjścia.** W oryginale trafienia T1–T3 są tylko liczone w statystykach, a transakcja kończy się na SL lub z końcem sesji. Tryb `TP_ORIGINAL_SL_SESSION` odtwarza właśnie to zachowanie.
3. **Strefa czasowa.** Sesje są przeliczane ze stałym przesunięciem `InpServerToNYHours`. Pine automatycznie uwzględnia zmianę czasu w Nowym Jorku.
4. **VWAP** jest liczony od początku dnia brokera (zwykle 17:00 NY) i ważony wolumenem tickowym. Na TradingView kotwicą jest sesja giełdy, a wolumen pochodzi z giełdy. **Wolumen względny** to także wolumen tickowy.
5. **Dzienny ATR** to ATR Wildera ze świec D1 brokera, z ostatniego zamkniętego dnia (140 dni historii).
6. **Pominięte, bo czysto wizualne:** box zakresu, linie i etykiety poziomów, rozciąganie linii, znaczniki STRB, nieudanego breakoutu i retestu, alerty oraz tabela statystyk. Statystyki daje Strategy Tester, na realnych transakcjach.

---

# Volume Breakout 30m EA (MQL5)

EA zbudowany na podstawie reguł strategii „Breakout with volume” z TrendSpider (zrzut ekranu). Przygotowany pod **NASDAQ (NAS100 / US100 / USTEC)**. Sygnały liczy na **M30**, niezależnie od interwału wykresu.
Plik: `MQL5/Experts/VolumeBreakout30_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Reguły
**Wejście (long)**, gdy na zamkniętej świecy M30 spełnione są naraz trzy warunki:
1. Close > najwyższy high z **30 poprzednich** świec (bez bieżącej).
2. Wolumen ≥ SMA(20) wolumenu × **1,75** (o co najmniej 75% wyżej).
3. Close > open.

Wejście następuje na otwarciu kolejnej świecy.

**Wyjście:**
- od **16. świecy** po wejściu: na pierwszym zamknięciu, przy którym zysk wynosi **< 0,5%** ceny (opcja: sprawdzenie tylko na 16. świecy);
- po **60 świecach**: zawsze;
- **awaryjny SL = 3 × ATR(14)** z M30. Dodałem go, bo oryginał nie ma SL. Od jego odległości liczony jest też lot przy ryzyku 1%.

Pozostałe zasady: maksymalnie 1 pozycja, bez TP. Lustrzane shorty są dostępne jako opcja, domyślnie wyłączone.

## Założenia i różnice wobec oryginału
1. **SL.** Oryginał go nie ma, a EA ma zawsze awaryjny SL. Przy 3 ATR uruchamia się rzadko, ale zmienia wynik w dniach z dużym ruchem przeciwko pozycji.
2. **Wolumen.** Na CFD dostępny jest tylko wolumen **tickowy**. TrendSpider na akcjach, ETF i futures używa wolumenu giełdowego, więc filtr wolumenu da trochę inne sygnały.
3. **Średnia wolumenu** SMA(20) obejmuje świecę sygnałową.
4. **Zysk do reguły 16 świec** to (close − cena wejścia) / cena wejścia, w % ceny instrumentu, a nie % konta.
5. **Liczba świec od wejścia** to liczba zamkniętych świec M30, licząc od świecy, na której otwarto pozycję.

---

# RTH Breaks EA (MQL5): RTH Breaks + Midnight Confluence v2.1

EA przeniesiony ze wskaźnika Pine **„RTH Breaks + Midnight Confluence” v2.1**. Przygotowany pod **NAS100 na M5** (wymagany interwał M1–M30). US500 i XAUUSD działają jako osobne instancje.
Plik: `MQL5/Experts/RTH_Breaks_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
- **pRTH** to high, low i środek sesji 09:30–16:00 NY (pon–pt) z poprzedniego dnia handlowego. **MN** to otwarcie świecy M1 o 00:00 NY.
- **Na otwarciu świecy 09:30:** gap up (powyżej pRTH H), gap down (poniżej pRTH L) albo inside.
- **Zgodność MN i ocena:**
  - Gap up: HIGH, chyba że MN jest poniżej środka (SKIP).
  - Gap down: HIGH, gdy MN < pRTH L; MODERATE, gdy MN jest neutralny; LOW przy konflikcie.
  - Inside: HIGH, gdy MN jest po tej samej stronie środka co otwarcie; w przeciwnym razie REDUCED.
  - MAGNET (brak biasu): MN bliżej niż 20% zakresu od przeciwnego brzegu. Nie dotyczy złota.
  - Brak danych o północy daje MIDLINE ONLY.

## Handel
- **Domyślnie tylko oceny HIGH.** MODERATE, REDUCED i MIDLINE ONLY są dostępne jako opcje. SKIP, LOW i MAGNET nigdy nie są handlowane.
- **Gap up / gap down:** limit na **pRTH H** (long) lub **pRTH L** (short), czyli wejście na reteście, ważne do 11:00 NY. Opcja: wejście rynkowe o 09:30. SL = 0,25 × zakres pRTH za poziomem. Wyjście o **15:59 NY** (opcjonalnie TP na stałym RR).
- **Inside:** wejście rynkowe o 09:30 w stronę środka zakresu. TP = brzeg zakresu po stronie biasu, SL = środek ± 0,1 × zakres. Gdy RR < 1, EA pomija dzień.
- **Limity:** maksymalnie 1 transakcja dziennie, wszystko zamykane najpóźniej o 15:59 NY. Ryzyko 1% salda, kill-switch dzienny 3% i całkowity 10%.

## Ustaw przed startem
- `InpServerToNYHours`: domyślnie 7. **Koryguj przy zmianach czasu**, bo inaczej 09:30 i północ przesuną się o godzinę.
- W testerze potrzebne są dane M1, z których EA odczytuje otwarcie o północy.

## Założenia i różnice wobec oryginału Pine
1. **Statystyki oryginału** (69–82% itd.) opisują zamknięcie dnia względem pRTH, a nie wynik transakcji. Przewagę EA weryfikuje dopiero backtest. W wariancie z limitem dzień może zamknąć się nad pRTH H, a mimo to trafić wcześniej w SL na reteście.
2. **Sesje** są przeliczane ze stałym przesunięciem serwer–NY. TradingView liczy w strefie Nowego Jorku z automatyczną zmianą czasu.
3. **Otwarcie o północy:** gdy nie ma dokładnej świecy M1 o 00:00 NY, EA bierze pierwszą świecę do 00:05, a w ostateczności przechodzi na MIDLINE ONLY. Pine w takiej sytuacji używa ostatniej znanej wartości.
4. **Sesje skrócone (half-day)** są traktowane jak w Pine: pRTH obejmuje wszystkie świece RTH danego dnia.
5. **Pominięte, bo czysto wizualne:** linie, boxy, etykiety, tabela konfluencji i alerty.

---

# Gaussian Trend EA (MQL5): Gaussian Filter Trend [QuantAlgo]

EA przeniesiony ze wskaźnika Pine **„Gaussian Filter Trend [QuantAlgo]”**. Przygotowany pod **NAS100 na H1** z presetem Default (wg autora do swing tradingu na interwałach od H1 do D1).
Plik: `MQL5/Experts/GaussianTrend_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
- **Filtr Gaussa:** 4 kaskadowe etapy (długość 14, 4 bieguny), z dokładnie tym samym wzorem `pow(1.414, 2/bieguny)` co w oryginale.
- **Pasmo:** ATR(14) × mnożnik. Mnożnik płynie od 2,5 do 0,8 i zależy od Efficiency Ratio(10) wygładzonego przez EMA(5).
- **Linia trendu** stoi w miejscu, dopóki filtr nie wyjdzie poza pasmo. Skok w górę oznacza trend byczy, w dół niedźwiedzi.
- **Presety** Fast Response i Smooth Trend nadpisują parametry, tak jak w oryginale.

## Handel
- **Zawsze w rynku:** zmiana trendu na zamkniętej świecy zamyka pozycję i otwiera nową w przeciwnym kierunku, na otwarciu kolejnej świecy. Opcjonalnie tylko long albo tylko short.
- **SL** na linii trendu z buforem 0,25 × ATR, z **trailingiem za linią**: po każdej świecy SL przesuwa się tylko w stronę zysku. Gdy linia jest po złej stronie ceny (luka), awaryjny SL to 1 × ATR.
- **TP:** brak. Opcja TP na stałym RR. Opcjonalne okno handlu w czasie Nowego Jorku.
- **Ryzyko:** 1% salda liczone od odległości SL, maksymalnie 1 pozycja, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Zamknięte świece.** Oryginał może zmieniać kolor linii w trakcie świecy. EA decyduje po jej zamknięciu.
2. **Rozgrzewka.** Stan filtra liczony jest od `InpWarmupBars` świec wstecz, a nie od początku historii. Filtr i EMA mają krótką pamięć, więc różnica praktycznie znika po kilkudziesięciu świecach.
3. **ATR** liczony jest metodą Wildera (RMA), jak `ta.atr`.
4. **SL, trailing i TP** to elementy dodane w EA, bo oryginał jest wskaźnikiem kierunku i nie definiuje wyjść poza zmianą trendu.
5. **Pominięte, bo czysto wizualne:** gwiazdy, kolory, kolorowanie świec i tła, alerty.

---

# Alpha Signal Engine EA (MQL5): Alpha Signal Engine Pro [MarkitTick]

EA przeniesiony ze wskaźnika Pine **„Alpha Signal Engine Pro [MarkitTick]”**. Przygotowany pod **NAS100 na M15** (autor nie podaje zaleceń).
Plik: `MQL5/Experts/AlphaSignalEngine_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
Oryginał liczy wszystko z danych **poprzedniej, zamkniętej świecy** (`[1]`), więc sygnał świecy t jest znany już na jej otwarciu, bez repaintu.

- **Połowa pasma** = ATR(14) × (3 + ATR/close × 1 + ruch ceny × 5). Ruch ceny to |zmiana close| w %, ograniczona od góry 95. percentylem ze 100 świec. Wartość jest wygładzana EMA (domyślnie 1, czyli bez wygładzania).
- **Linia trendu** opiera się na pasmie wokół hl2 poprzedniej świecy. Kierunek wyznacza close względem poprzedniej linii.
- **Filtr „flat”** blokuje zmianę kierunku, gdy spełniony jest którykolwiek z warunków:
  - linia stoi;
  - nachylenie regresji z 5 wartości jest małe;
  - wolumen ≤ swojej SMA(20);
  - zakres świecy ≤ 20. percentyla ze 100 świec;
  - zmiana linii < 1 bps.

  Wyjątkiem jest ruch większy niż 1,5 ATR („Breakout Override”).
- **BUY / SELL** to zmiana przefiltrowanego kierunku.
- **Volatility Fingerprint** (opcja, domyślnie wyłączona) skaluje parametry według kwartyla ATR% z 300 świec.

## Handel
- **Odwracanie pozycji**, tak jak alerty oryginału (long + closeshort, short + closelong). Opcjonalnie tylko jeden kierunek.
- **Moment wejścia:** domyślnie na **otwarciu świecy sygnału**. Opcja `InpEntryAtSignalClose` odtwarza wejście na jej zamknięciu, tak jak webhook oryginału.
- **SL** na linii trendu z buforem 0,25 × ATR (zwykle około 3 ATR od ceny), z **trailingiem za linią** tylko w stronę zysku. Bez TP (opcja TP na stałym RR).
- **Ryzyko:** 1% salda liczone od odległości SL, maksymalnie 1 pozycja, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Wolumen.** Filtr wolumenu działa na wolumenie **tickowym**, bo na CFD innego nie ma.
2. **Rozgrzewka.** Stan liczony jest od `InpWarmupBars` świec wstecz. Odtwarzam domyślne wartości `nz()` z oryginału: dopóki okna percentyli i SMA wolumenu nie są pełne, filtr flat jest aktywny.
3. **Volatility Fingerprint w filtrze wolumenu:** EA skaluje SMA mnożnikiem z bieżącej świecy, a Pine z poprzedniej. Różnica ma znaczenie tylko przy włączonym VF.
4. **ATR** liczony jest metodą Wildera (RMA), jak `ta.atr`. Percentyle liczone są metodą nearest rank, jak `ta.percentile_nearest_rank`.
5. **SL, trailing i TP** to elementy dodane w EA, bo oryginał nie definiuje wyjść poza sygnałem przeciwnym.
6. **Pominięte, bo czysto wizualne lub alertowe:** dashboard, chmura, kolorowanie świec i ostrzeżenie o nietypowym typie wykresu (EA zawsze używa zwykłych świec), alerty i JSON webhook.

---

# LongShort PRO EA (MQL5): LongShort PRO v2

EA przeniesiony ze wskaźnika Pine **„LongShort PRO v2”**. Domyślnie ustawiony na preset **Nasdaq 100 E-mini**: NAS100 na **M30**, tylko long, interwały M30 + H1 + H4, SL 1% i TP 2%.
Plik: `MQL5/Experts/LongShortPro_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
- **Oscylator:** Stochastic RSI, czyli %K = SMA(3)(Stoch(14) z RSI(14)), liczony osobno na każdym interwale presetu.
- **Stan interwału:** LONG, gdy %K < poziomu LONG (20); SHORT, gdy %K > poziomu SHORT (80); w przeciwnym razie czekanie.
- **Sygnał:** wszystkie włączone interwały **właśnie** stały się zgodne (na poprzedniej świecy jeszcze nie były). Ocena odbywa się na zamkniętej świecy wykresu.
- **Presety:** Base, Manual, GOLD V1, GOLD V2, BTC+ETH, Nasdaq 100 E-mini. Profile dobierane są według interwału wykresu, tak jak w oryginale.
- **Manual:** Direction Filter (przy kierunku Both) i Global Filter (przy Long lub Short). Ich stan jest odtwarzany na historii przy starcie.
- **Klasy GOLD (+, ++)** zależą od %K na interwale kontekstowym. Opcjonalnie można handlować tylko wyższe klasy.

## Handel
- Wejście rynkowe na otwarciu świecy po sygnale. SL i TP w % od faktycznej ceny wejścia.
- Jedna transakcja naraz. Sygnały w jej trakcie są ignorowane, a wyjście następuje tylko na SL albo TP, jak w oryginale.
- **Base** (oryginał bez SL/TP) oraz **Manual** używają `InpManualSL` / `InpManualTP`. Domyślne 5% / 10% to dla NAS100 bardzo szerokie poziomy, więc warto je dopasować.
- **Ryzyko:** 1% salda liczone od odległości SL, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Wyższe interwały: tylko zamknięte świece.** Oryginał na żywo czyta %K z jeszcze otwartej świecy H1/H4, która może się zmienić przed zamknięciem. Na historii, w tym w tabeli backtestu, używa świec zamkniętych. EA odpowiada historii oryginału: nie ma repaintu, ale sygnał na żywo może się pojawić trochę później niż na TradingView. Opcja „Use Confirmed Filter Candle” filtra kierunku jest zawsze włączona.
2. **Interwały niedostępne w MT5** (30 s, 45 s, 45 min, 2D, 3D, 2W, 3M): profile, które ich wymagają, są oznaczane jako nieobsługiwane i EA na nich nie handluje. Dotyczy to GOLD na 30s/45s/45m, Base na D1 i wyżej oraz BTC+ETH „Position”.
3. **Wielkość pozycji.** Tabela oryginału zakłada pozycję 250% salda, co przy SL 1% oznacza 2,5% ryzyka. EA ryzykuje 1% salda.
4. **Tabela backtestu oryginału** wybiera z ostatnich 10–50 transakcji okno z najwyższym zwrotem, więc jej wynik jest zawyżony. Nie jest przeniesiona. Rzetelny obraz daje raport Strategy Testera z całego okresu.
5. **Kolejność SL/TP w jednej świecy.** Oryginał w statystykach przy jednoczesnym dotknięciu SL i TP liczy najpierw SL. W EA wyjście realizuje broker według faktycznego ruchu ceny.
6. **Pominięte, bo czysto wizualne:** wykres oscylatora, etykiety, boxy SL/TP, tabele statusu i backtestu, alerty.

---

# ML RSI EA (MQL5): Machine Learning RSI | AI Classification & Ranking (Zeiierman)

EA przeniesiony ze wskaźnika Pine **„Machine Learning RSI | AI Classification & Ranking”**, rozszerzony o **opcjonalny filtr dywergencji RSI**. Przygotowany pod **NAS100 na M15** (autor nie podaje zaleceń).
Plik: `MQL5/Experts/MLRSI_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
1. **8 cech RSI(14):** poziom, nachylenie, przyspieszenie, odległość od 50, percentyl, zmienność RSI, różnica RSI(7) i RSI(28) oraz reżim EMA20(RSI). Większość jest normalizowana do 0–1 w oknie 100 świec.
2. **Bank pamięci (500):** każda zamknięta świeca dodaje cechy sprzed 4 świec wraz z etykietą ruchu w tych 4 świecach. Etykieta to klasa od −3 do +3, liczona względem 0,5 × ATR.
3. **Wagi cech** pochodzą z dyskryminantu Fishera (Auto Weight Optimizer). Opcjonalnie można ustawić je ręcznie.
4. **kNN:** 8 najbliższych analogów spośród co 4. wiersza banku, odległość log(1+|Δ|) ważona cechami, głosy ważone odległością. Bias wynosi ±1 przy wyniku |0,15| lub większym.
5. **ML Supertrend:** ATR(10) × 1,5 na hl2. Pasmo zwęża się przy silnej zgodności analogów i rozszerza w konsolidacji.
6. **Stance** zmienia się przy przejściu bramek: trend zgodny z Supertrendem, percentyl ATR 20–85, brak konsolidacji.
7. **Sygnał:** zmiana stance, Rank ≥ 60 i Confidence ≥ 50, z cooldownem 5 świec. Wszystko liczone na zamkniętych świecach.

## Dodatek: filtr dywergencji RSI
- **Włącznik** `InpDivOn`, domyślnie wyłączony. Interwał `InpDivTf`: domyślnie **interwał wykresu** albo dowolny inny.
- **Definicja** jak we wbudowanym „RSI Divergence” na TradingView: pivoty RSI(14) z 5 świecami z lewej i 5 z prawej, odstęp między pivotami 5–60 świec.
  - Bycza: cena ma niższe dno, a RSI wyższe dno.
  - Niedźwiedzia: cena ma wyższy szczyt, a RSI niższy szczyt.
  - Opcjonalnie również dywergencje ukryte.
- **Działanie:** LONG wymaga dywergencji byczej, a SHORT niedźwiedziej, potwierdzonej w ciągu ostatnich `InpDivMaxAge` świec interwału dywergencji (domyślnie 10).
- **Bez repaintu:** dywergencja liczona jest tylko na zamkniętych świecach. Pivot potwierdza się 5 świec po fakcie, więc okno musi być większe od tego opóźnienia.

## Handel
- Wejście rynkowe na otwarciu świecy po sygnale.
- **SL** na linii **ML Supertrend**, z trailingiem tylko w stronę zysku. Gdy linia jest po złej stronie ceny, awaryjny SL to 1 ATR.
- **Przeciwny sygnał** zamyka pozycję i otwiera nową w drugą stronę. Bez TP (opcja TP na stałym RR).
- **Ryzyko:** 1% salda liczone od odległości SL, maksymalnie 1 pozycja, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Rozgrzewka.** Bank, wagi i stany odtwarzane są z `InpWarmupBars` świec (domyślnie 2000), a nie od początku historii wykresu. Bank zawiera zawsze ostatnie 500 wierszy, więc po rozgrzewce jest identyczny. EMA i stany Supertrendu zbiegają się po kilkudziesięciu świecach.
2. **Pierwsze świece historii.** W oryginale cechy z wartością `na` z pierwszych świec trafiają do banku. EA dodaje wiersze dopiero przy pełnych oknach 100 świec. Ma to znaczenie tylko na samym początku historii.
3. **Wskaźniki:** RSI i ATR liczone metodą Wildera, EMA od pierwszej wartości, odchylenie populacyjne, percentrank z poprzednich N wartości, tak jak w Pine.
4. **SL, trailing i odwracanie** to elementy dodane w EA, bo oryginał definiuje tylko sygnały i linię trailing stopu.
5. **Pominięte, bo czysto wizualne:** ML RSI z linią sygnałową i pasmami Bollingera (nie wpływa na sygnał), chmura, kolorowanie świec, kropki zmian Supertrendu, alerty.

---

# Nebula3 EA (MQL5): Nebula v3

EA przeniesiony ze wskaźnika Pine **„Nebula3” (Nebula v3)**. Autor projektował go pod **NQ na M1**, więc EA jest ustawiony pod **NAS100 na M1**.
Plik: `MQL5/Experts/Nebula3_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
1. **Tidal Wave:**
   - Fala wzrostowa zaczyna się, gdy zielona świeca otwiera się na poziomie close wcześniejszej zielonej świecy lub wyżej, a pomiędzy nimi nie było „jasnej” czerwonej. Pętla sprawdza do 200 świec wstecz.
   - Luka wolumenowa przy dwóch zielonych świecach z rzędu (otwarcie ≥ close poprzedniej) też ustawia falę wzrostową.
   - Dla fali spadkowej reguły są lustrzane.
2. **Ultimate Buy / Sell:**
   - RSI(32) przecina WMA(32), WMA(24) albo poziom 25/75.
   - W ciągu 35 świec wcześniej musi wystąpić sygnał „watch”: close przecina BB 20/2, RSI przecina swoje pasma 2σ, RSI przecina 25/75, high lub low przecina pasmo ATR(30) × 1,5 wokół WMA(10).
3. **Sygnały wejścia:**
   - **Strong Buy / Strong Sell** to nowa fala z sygnałem Ultimate w ciągu ostatnich 4 świec.
   - **Buy / Sell** (kropka) to nowa fala bez sygnału Ultimate.
4. **Dokładanie:**
   - **Vodka Shot:** rosnąca potrójna WMA(7), przewaga energii DER, skok wolumenu.
   - **„+”:** luka w trakcie fali.
5. **Confluence TP:** suma punktów z 7 sygnałów na bieżącej lub poprzedniej świecy, maksymalnie 19 punktów.

   | Sygnał | Punkty |
   |---|---|
   | squeeze momentum | 4 |
   | trampolina | 4 |
   | licznik 9 | 3 |
   | objęcie przy 50-świecowym ekstremum | 2 |
   | early reversal (świeca PVSRA + przebicie fraktala) | 2 |
   | shark | 2 |
   | odrzucenie BB 20/2,5 | 2 |

   **Próg ≥ 5 oznacza częściową realizację, ≥ 7 pełną.** Sygnał działa po stronie bieżącej fali.

## Handel
- **Wejście** rynkowe na otwarciu świecy po sygnale. Domyślnie tylko **Strong Buy / Strong Sell**. Opcje: Strong + kropki albo same Ultimate.
- **SL** za ekstremum z 5 świec ± 0,25 × ATR(30), w granicach 0,5–3 ATR. Bez TP (opcja TP na stałym RR).
- **Wyjścia:**
  - Confluence ≥ 5 zamyka 50% każdej pozycji raz, a SL przechodzi na **break-even**.
  - Confluence ≥ 7 zamyka całość.
  - **Nowa fala przeciwna** zamyka pozycję.
  - Przeciwny sygnał wejścia odwraca pozycję.
- **Okno sesji:** 09:30–15:55 czasu NY. Poza nim EA nie otwiera pozycji i zamyka otwarte. Przesunięcie serwer–NY wynosi domyślnie +7 h, `InpServerToNYHours`. **Skoryguj je przy zmianie czasu.**
- **Dokładanie** (domyślnie wyłączone):
  - na Vodka Shot albo Vodka Shot + „+”;
  - maksymalnie 1 dołożenie z ryzykiem 0,5%;
  - SL taki sam jak pozycji głównej.
- **Ryzyko:** 1% salda liczone od odległości SL, kill-switch dzienny 3% i całkowity 10%.
- **Opcjonalny filtr dywergencji RSI:** pivoty RSI(14) 5/5, odstęp 5–60 świec, interwał do wyboru. Domyślnie wyłączony.

## Założenia i różnice wobec oryginału Pine
1. **Brak kodu biblioteki `TradersReality/Traders_Reality_Lib/2`.** Kolor świecy PVSRA jest odtworzony według standardowej definicji: świeca klimaksowa przy wolumenie ≥ 2 × SMA(10) albo gdy wolumen × zakres jest najwyższy z 10 świec. Wpływa to tylko na sygnał early reversal (2 z 19 punktów confluence).
2. **Wolumen:** na CFD jest tylko wolumen tickowy (`InpVolumeType`). Od wolumenu zależą PVSRA, Vodka Shot i DER.
3. **Zamienione nazwy w oryginale.** W kodzie Pine tytuły znaczników i alertów TP są zamienione miejscami. EA stosuje opisy inputów: 5 punktów to częściowa realizacja, 7 pełna.
4. **Zachowane osobliwości oryginału:**
   - Vodka Sell sprawdza `upwards[2..4]` zamiast `downwards[2..4]` (opcjonalna poprawka `InpVodkaSellFix`);
   - warunek `upU` jest liczbą użytą jako bool;
   - próg squeeze 5 jest wyrażony w punktach ceny NQ (`InpSqzLevel`; na innym instrumencie trzeba go dopasować).
5. **Rozgrzewka:** stany fali, liczniki squeeze i okna watch odtwarzane są z `InpWarmupBars` świec (domyślnie 3000). Liczniki squeeze w oryginale narastają od początku historii, więc mogą się nieznacznie różnić tuż po starcie.
6. **Wskaźniki:** RSI, ATR i ADX liczone metodą Wildera, odchylenie populacyjne, `ta.linreg`, WMA i `fixnan` tak jak w Pine.
7. **Elementy dodane w EA:** SL, break-even, zamykanie na fali przeciwnej, okno sesji i dokładanie. Oryginał tylko pokazuje sugestie.
8. **Pominięte, bo czysto wizualne:**
   - chmura McGinley / FVMA i 15 trybów kolorowania świec;
   - poziomy sesji, strefy squeeze, linie luk;
   - EMA 9/21, HEMA, dashboard, etykiety, alerty.

---

# Buy/Sell Signals XL EA (MQL5)

EA przeniesiony ze wskaźnika Pine **„Buy/Sell Signals XL”**. Przygotowany pod **NAS100 na M15**, pierwszy interwał ze skanera autora.
Plik: `MQL5/Experts/BuySellSignalsXL_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Silniki (jeden aktywny, `InpEngine`, domyślnie Breakout)
| Silnik | Sygnał BUY (SELL lustrzanie) | SL / TP domyślnie |
|---|---|---|
| OC | korpus ≥ 3 × średnia z 50, close powyżej korpusu poprzedniej świecy | knot / 1 × SL |
| Breakout | close nad ciasną bazą (zmienna 5–30 świec, wysokość ≤ 2 ATR), świeża baza | przeciwna krawędź bazy / 1 × wysokość bazy |
| Donchian | close nad najwyższym high z 20 poprzednich świec | przeciwna banda / 0,5 × SL |
| MA Cross | pierwsze ułożenie EMA 9 > 21 > 55 (lub przecięcie 2 MA) | 2 × ATR / 1 × SL |
| Supertrend | zmiana kierunku Supertrendu (10, 3) | linia Supertrendu / 0,5 × SL |
| Aroon | Aroon Up przecina Aroon Down (14) lub początek silnego trendu | 1,5 × ATR / 1 × SL |

Każdy silnik ma własną grupę ustawień, tak jak w oryginale. Kilka silników naraz uruchamiasz jako osobne instancje EA z różnym `InpMagicNumber`.

## Logika (1:1 z Pine)
- **Wirtualny stan transakcji** liczony na zamkniętych świecach:
  - wyjścia SL/TP z knota albo z zamknięcia; przy jednoczesnym dotknięciu najpierw SL;
  - tryby kierunku: naprzemiennie, każdy sygnał, tylko BUY, tylko SELL;
  - blokada sygnałów przy otwartej transakcji (Supertrend: wyjście na tej samej świecy nie blokuje);
  - odwracanie na sygnale;
  - w Breakout reguły świeżej bazy i odstępu po wyjściu.
- **Kolejność jak w Pine:** sygnał liczony jest ze stanu sprzed świecy, potem wyjście SL/TP, potem nowa transakcja.
- **Wskaźniki:** ATR Wildera (14), `ta.supertrend` na hl2, MA typu SMA/EMA/WMA/HMA/RMA (EMA od pierwszej wartości, RMA od SMA), Aroon z `highestbars` / `lowestbars`.

## Handel
- **Wejście** zawsze rynkowo na otwarciu świecy po sygnale.
- **SL** to poziom z Pine (krawędź bazy, banda, linia, knot, swing…) albo ATR liczony od faktycznej ceny wejścia. **TP** liczony od faktycznej ceny wejścia. Jeśli cena jest już za poziomem SL, wejście jest pomijane.
- Po otwarciu stan wirtualny przejmuje realne poziomy, więc wyjścia wirtualne i u brokera się pokrywają.
- **Tryb wyjścia `Wick`:** SL i TP fizycznie u brokera.
- **Tryb `Close`:** SL i TP sprawdzane na zamknięciu świecy, a u brokera stoi twardy SL o `InpCloseExtraAtr` ATR dalej.
- **Brak SL** (`SL_NONE` lub `Enable SL/TP` wyłączone): logika bez stopu jak w Pine, ale u brokera zawsze stoi SL awaryjny 3 × ATR.
- **Filtr win rate (opcja, domyślnie wyłączony):** realne wejście tylko przy WR ≥ 70% z 20 ostatnich transakcji wirtualnych, tak jak w alertach oryginału.
- **Okno sesji NY (opcja, domyślnie wyłączone):** przesunięcie serwer–NY wynosi domyślnie +7 h.
- **Ryzyko:** 1% salda albo stała kwota (`Risk per trade`) liczone od odległości SL, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Tryby wejścia „Edge” domyślnie wyłączone.** Wskaźnik w trybie Edge zakłada wejście po cenie krawędzi, choć sygnał potwierdza się dopiero na zamknięciu świecy. Zawyża to wyniki.
   - W EA tryby Edge wpływają tylko na wirtualne statystyki i na wymóg Breakout, by SL był po stratnej stronie wejścia.
   - Realne wejście jest zawsze rynkowe. Zlecenia stop na krawędzi nie są dodane.
2. **Statystyki wskaźnika nie są dowodem przewagi.** Domyślne TP 0,5–1 × SL dają wysoki win rate przy słabym stosunku zysku do ryzyka. Filtr WR wybiera to, co ostatnio „wyszło”.
3. **Rozgrzewka:** stan silnika i wirtualne transakcje odtwarzane są z `InpWarmupBars` świec (domyślnie 3000). Realna pozycja niezgodna z odtworzonym stanem (np. po restarcie) jest zamykana na zamknięciu świecy.
4. **HMA:** długości `len/2` i `sqrt(len)` zaokrąglane w dół. **Aroon:** przy remisie ekstremów decyduje kolejność `iHighest` / `iLowest`.
5. **Wolumen:** tickowy. Filtry wolumenu są domyślnie wyłączone, jak w oryginale.
6. **Pominięte, bo czysto wizualne lub analityczne:** Engine Scanner i Symbols Scanner (wiele interwałów i symboli), info box, kalkulator pozycji, linie, etykiety, strefy, alerty, świece Heikin Ashi.

---

# Pure Momentum EA (MQL5): Pure Momentum Oscillator (MisinkoMaster)

EA przeniesiony ze wskaźnika Pine **„Pure Momentum Oscillator”**. Przygotowany pod **NAS100 na M15** (autor nie podaje zaleceń).
Plik: `MQL5/Experts/PureMomentum_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine)
1. **cd** = 2 × close − EMA(close, 45), czyli close z korektą opóźnienia.
2. **cda** = WMA(cd, 45), wygładzona linia ceny.
3. **change** = (cda − cda[1]) / ATR(45), czyli nachylenie linii w jednostkach ATR.
4. **Trend** przechodzi na +1, gdy change > 0,05, i na −1, gdy change < −0,05. Pomiędzy progami stan się nie zmienia.
5. **Sygnał** to zmiana trendu na zamkniętej świecy. Pierwsze ustawienie trendu ze stanu 0 nie jest sygnałem.

## Handel
- Wejście rynkowe na otwarciu świecy po zmianie trendu. **Stop-and-reverse:** przeciwny sygnał zawsze zamyka pozycję.
- **SL** 2 × ATR(45). TP brak (opcja TP na stałym RR).
- Opcjonalny **trailing** za linią cda ± 1 × ATR, tylko w stronę zysku.
- Opcjonalny filtr min. nachylenia |change| przy wejściu. Odpada tylko nowe wejście, zamknięcie przeciwnej pozycji następuje zawsze.
- Opcjonalne okno sesji NY. Ryzyko 1% salda od odległości SL, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **SL, trailing, filtr nachylenia i sesja** to elementy dodane w EA. Oryginał podaje tylko kierunek.
2. **Wskaźniki:** EMA od pierwszej wartości, WMA z wagą len dla najnowszej świecy, ATR Wildera, tak jak w Pine. Stan trendu odtwarzany jest z `InpWarmupBars` świec (domyślnie 2000).
3. **Próg 0,05 ATR na świecę jest niski.** W konsolidacji należy się spodziewać serii odwróceń.
4. **Pominięte, bo czysto wizualne:** wygładzone świece (oda/hda/lda), kolorowanie, wypełnienia, linie progów, nieużywany import biblioteki `ta`.

---

# Squeeze Breakout EA (MQL5): Squeeze Breakout Signals [bitpunk]

EA przeniesiony ze wskaźnika Pine **„Squeeze Breakout Signals [bitpunk]”**, rozszerzony o **opcjonalny filtr dywergencji RSI**. Przygotowany pod **NAS100 na M15** (autor nie podaje zaleceń).
Plik: `MQL5/Experts/SqueezeBreakout_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine, maszyna stanów `RangeStudy`)
1. **Kompresja:** 2 × stdev(close, 20) < 1,5 × SMA(TR, 20). Odchylenie jest populacyjne, a TR pierwszej świecy to high − low.
2. **Epizod:** potrzeba ≥ 3 kolejnych ściśniętych zamknięć. Range to high/low ciągu, a po 20 świecach okno przesuwa się. Nowy epizod może się zacząć dopiero po 3 nieściśniętych zamknięciach.
3. **Zamrożenie:**
   - Następuje przy pierwszym zamknięciu poza kompresją albo przy zamknięciu poza range jeszcze w trakcie kompresji. Świeca zdarzenia nie poszerza krawędzi.
   - Zamrażane są krawędzie i TR z poprzedniej świecy.
   - Startuje okno obserwacji 20 świec.
4. **Breakout:** pierwsze zamknięcie poza krawędzią wyznacza kierunek pudełka. Opcjonalnie wejście jest ograniczone limitem odległości (`InpMaxExtension`). Wybicie przeciwne to tylko kontekst.
5. **Retest:**
   - cena musi najpierw odejść: cała świeca poza krawędzią ± 0,25 TR;
   - potem dotknąć tej strefy;
   - na koniec zamknąć się za krawędzią;
   - filtr postępu: close retestu dalej niż poprzedni close;
   - retest unieważnia zamknięcie na przeciwnej krawędzi.
6. **Kompresje:** nakładająca się kompresja dzieli stare pudełko, a rozłączna je zastępuje.

## Dodatek: filtr dywergencji RSI
- Włącznik `InpDivOn` (domyślnie wyłączony). Interwał `InpDivTf`: domyślnie interwał wykresu albo dowolny inny.
- **Definicja:** pivoty RSI(14) 5/5, odstęp 5–60 świec, opcjonalnie dywergencje ukryte.
- **Działanie:** LONG wymaga dywergencji byczej, a SHORT niedźwiedziej, potwierdzonej w ciągu `InpDivMaxAge` świec (domyślnie 30, czyli mniej więcej czas trwania kompresji). Liczone tylko na zamkniętych świecach.

## Handel
- Wejście rynkowe na otwarciu świecy po sygnale.
- **Breakout** zawsze. **Retest** tylko bez otwartej pozycji (opcje: wyłączony albo dołożenie z ryzykiem 0,5%).
- Przeciwny sygnał z nowego pudełka odwraca pozycję.
- **SL** na przeciwnej krawędzi pudełka ± 0,25 × zamrożony TR, maksymalnie 4 TR od wejścia.
- **TP** na RR 2,0 albo na zasięgu równym wysokości pudełka od krawędzi.
- Opcjonalny break-even po 1R.
- Opcjonalne okno sesji NY.
- **Ryzyko:** 1% salda od odległości SL, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **SL, TP, BE, odwracanie, sesja i dywergencja** to elementy dodane w EA. Oryginał podaje tylko punkty wejścia.
2. **Rozgrzewka:** stan odtwarzany jest z `InpWarmupBars` świec (domyślnie 3000). Licznik epizodów różni się od oryginału, ale na sygnały wpływa tylko jego zmiana, nie wartość.
3. **Pominięte, bo czysto kontekstowe lub wizualne:** sondy knotem, pudełka, wypełnienia, poświaty, panel statusu, wartości w oknie danych, alerty, motyw kolorów.

---

# AMD Po3 EA (MQL5): AMD Po3 with Live Edge Stats [WillyAlgoTrader] v2.4.0

EA przeniesiony ze wskaźnika Pine **„AMD Po3 with Live Edge Stats”**, rozszerzony o **wejście w dystrybucji potwierdzane CISD i/lub dywergencją RSI**. Przygotowany pod **NAS100 na M15**; autor stroi model pod M15.
Plik: `MQL5/Experts/AMD_Po3_EA.mq5`. Korzysta z rdzenia `Include/Core`.

## Logika (1:1 z Pine, FSM na zamkniętych świecach)
1. **IDLE → akumulacja:**
   - warunki: szerokość Donchiana(20) w dolnych 25% (percentrank z 200 świec), szerokość ≥ 0,15% ceny, 10 świec przerwy po poprzednim cyklu;
   - z okna usuwany jest ogon poprzedniego impulsu (trim 15%);
   - granice pochodzą z pivotów 3/3 w oknie albo z surowego high/low;
   - tolerancja granic (10% szerokości) zamrażana jest przy narodzinach range.
2. **Akumulacja:**
   - wygaśnięcie po 96 świecach;
   - „news bar” (przebicie obu granic) to reset;
   - przebicie przed dojrzałością (12 świec) to reset;
   - filtry sweepu: killzony, limit głębokości z percentyla TR (domyślnie wyłączony), płynność EQH/EQL, blokada tej samej strony po re-armie;
   - w trybie pivot granice „oddychają” na nowych pivotach w paśmie tolerancji.
3. **Sweep:**
   - ekstremum śledzi najgłębszy punkt;
   - przebicie przeciwnej granicy to stan 2-SIDE;
   - zbyt głęboki sweep to TOO DEEP;
   - brak powrotu w 6 świec to BREAKOUT;
   - **powrót zamknięciem do range to potwierdzona manipulacja** (także na tej samej świecy).
4. **Dystrybucja (model referencyjny):**
   - **wejście** = close świecy D;
   - **stop** = ekstremum sweepu ∓ 0,4 × ATR z okresu przed range, zaokrąglony na zewnątrz do ticka;
   - **cel** = rozszerzenie Fibonacciego 1,5 nogi manipulacji (0 = szczyt sweepu, 1 = przeciwna granica);
   - wymagany jest co najmniej tick zysku;
   - opcjonalny bias HTF (close vs EMA50 z ostatniej zamkniętej świecy HTF): odrzucenie daje re-arm na sweep drugiej strony albo FAILED.
5. **Wynik cyklu** (od świecy po D):
   - target, stop, timeout po 64 świecach;
   - dotknięcie obu poziomów na jednej świecy liczy się jako stop (AMBIGUOUS).

## Wejście w dystrybucji (`InpEntryMode`)
| Tryb | Wejście |
|---|---|
| Referencyjne (domyślne) | rynkowo na otwarciu świecy po D |
| CISD | close za open najstarszej świecy w ciągu świec przeciwnych prowadzących do ekstremum sweepu (dla longa: ciąg świec spadkowych) |
| Dywergencja RSI | na TF wykresu: ekstremum sweepu vs dołek/szczyt range przed sweepem (bycza: niższy dołek ceny, wyższe RSI(14)); na innym TF: pivoty 5/5 jak w poprzednich EA |
| CISD lub dywergencja / CISD i dywergencja | kombinacje powyższych |

Potwierdzenie musi nastąpić w ciągu `InpConfirmBars` świec od D (domyślnie 10), zanim cykl się zakończy. Stop i cel zostają jak w modelu.

## Handel
- **SL i TP** to poziomy modelu, fizycznie u brokera. Timeout i każdy koniec wirtualnego cyklu zamykają pozycję.
- **Pozostały R:R** od bieżącej ceny musi wynosić ≥ `InpMinRRLeft` (domyślnie 0,5).
- **Ryzyko:** 1% salda od odległości SL, maksymalnie 1 pozycja, kill-switch dzienny 3% i całkowity 10%.

## Założenia i różnice wobec oryginału Pine
1. **Killzony** liczone są z czasu serwera przesuniętego o `InpServerToKzHours` (domyślnie +2 względem UTC). **Skoryguj przy zmianie czasu.**
2. **Bias HTF:** EMA50 z `iMA` na HTF. Inicjalizacja EMA w MT5 różni się od Pine, ale wynik zbiega się po historii.
3. **Statystyki „Live Edge Stats”** EA wypisuje tylko w logu przy starcie (z `InpWarmupBars` świec, domyślnie 3000). To wynik na historii, a nie dowód przewagi. Liczy się Avg R, nie target rate.
4. **CISD i dywergencja** to dodatki EA. Oryginał wchodzi zawsze na świecy D.
5. **Pominięte, bo wizualne:** pudełka, linie, etykiety, dashboard, watermark, alerty.
