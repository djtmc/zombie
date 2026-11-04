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
