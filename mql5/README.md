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
