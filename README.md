# Zombie Survival 3D – Ultimate Edition

Gra przeglądarkowa 3D (Three.js): broń swojej bazy przed kolejnymi falami zombie.

## Jak grać
- Otwórz `index.html` w przeglądarce (najlepiej przez serwer HTTP, np. GitHub Pages lub `python3 -m http.server`).
- Stawiaj budynki z dolnego menu:
  - **Obrona:** mur, duży mur, armata, Wielka Armata
  - **Ekonomia:** kopalnia, tartak (produkują surowce)
  - **Armia:** żołnierz, koszary (rekrutują żołnierzy), fabryka (produkuje czołgi)
- Ulepszaj budynki, przechodź kolejne poziomy i wybierz poziom trudności.
- Kamerę obracasz przeciągając myszą/palcem.

## PWA / offline
Gra działa jako aplikacja (PWA): `manifest.json` + `sw.js`. Po pierwszym uruchomieniu przez HTTP działa offline
i można ją „zainstalować” na telefonie.

> Przy każdej zmianie gry podbij `CACHE_NAME` w `sw.js`, inaczej gracze dostaną starą wersję z cache.

## Pliki
| Plik | Opis |
|------|------|
| `index.html` | Cała gra (HTML + CSS + JS) |
| `sw.js`, `manifest.json` | Service worker i manifest PWA |
| `icon-192.png`, `icon-512.png` | Ikony aplikacji |
| `gosia.html` | Osobny projekt: 30-sekundowy showreel „WOSQ” (animacja na canvasie) |
| `logo.jpg`, `bukiet.jpg`, `prezenty.jpg` | Grafiki używane przez `gosia.html` |

## Zombie Survival 3D 2.0 (`zombie-2.0/`)
Nowa, przepisana od zera wersja: lepsza grafika (bloom, cienie, roślinność, efekty), 3 typy zombie,
pociski z obrażeniami obszarowymi, dźwięk, zapis gry, menu i ustawienia jakości. Działa w pełni offline
(Three.js jest w `zombie-2.0/vendor/`). Uruchom: `zombie-2.0/index.html` przez serwer HTTP.

## Zombie Survival 3D 3.0 (`zombie-3.0/`)
Obrona fortecy na żywej makiecie 3D w klimacie wcześniejszych wersji. Pomysły (samogrająca gra, plansza
rozpadająca się po bossie, wygląd makiety) zaczerpnięte z gry Cinderwatch (licencja MIT), ale kod jest napisany od nowa.

- **Prostokątna plansza** 30×14 pól: zombie idą drogą z lewej strony do fortecy po prawej. Na telefonie
  w pionie kamera obraca się, żeby plansza wypełniała ekran.
- **Tytan, Twój Generał** – AI, które może dowodzić za Ciebie: buduje i rozbudowuje wieże. Na starcie dowodzisz Ty;
  przycisk w prawym górnym rogu (lub `C`) oddaje dowodzenie Tytanowi, a każde Twoje polecenie je odbiera.
- **4 wieże × 3 poziomy:** gniazdo KM, moździerz, wieża Tesli, posterunek z żołnierzami. Budowa w rusztowaniu.
- **12 rodzajów zombie** ze sztuczkami (biegacz, psy, pełzacz, rozdęty, plujący, opancerzony, krzykacz, roj,
  radioaktywny, kolos, Pacjent Zero) i **boss co 5. falę**: Rzeźnik, Lodowy Olbrzym, Królowa Roju.
- **3 krainy:** Zrujnowane Miasto, Zimowa Autostrada, Toksyczne Bagno. Po bossie plansza się rozpada
  i składa nowa, z inną drogą (80% wartości wież wraca do skarbca).
- **Wygląd makiety:** render w obniżonej rozdzielczości, tilt-shift, poświata, dithering, dynamiczne światła
  i pogoda. Wszystkie modele i dźwięki generowane w kodzie, bez plików graficznych.
- **Jakość grafiki** (przycisk w dolnym pasku lub `G`): Niska / Średnia / Wysoka / Auto. Rozdzielczość dopasowuje się
  płynnie do wydajności, a w trybie Auto także poziom. Wysoka dodaje fakturę powierzchni, mgłę przy ziemi oświetloną
  ogniskami i cieniowanie zakamarków. Na każdym poziomie: śnieg osiada na powierzchniach w zimie, drzewa i trzciny
  kołyszą się na wietrze, a kałuże, lód i toksyczne bajora są animowane. Postacie są rysowane instancjami
  (jedno wywołanie na część ciała), a trafione zombie migają.
- **Sterowanie:** klik/dotyk pola = menu budowy, `1`–`4` buduj, `U` rozbuduj, `X` sprzedaj (dwa razy),
  `Spacja` fala wcześniej (bonus złota), `P` pauza, `Tab` szybkość, `M` dźwięk, kółko/szczypanie = zoom,
  przeciąganie/strzałki/WASD = przesuwanie, `F` śledź walkę. Parametr `?b=0|1|2` wybiera krainę startową.

Źródła są w `zombie-3.0/src/`, a `python3 zombie-3.0/tools/build.py` skleja je z three.js
(z `zombie-2.0/vendor/`) w jeden plik `zombie-3.0/index.html`, który działa offline (PWA).

## Zombie Survival 3D 4.0 (`zombie-4.0/`)
Połączenie wersji 2.0 i 3.0: makieta, wieże, bossowie i Tytan z 3.0 oraz gospodarka i budynki z 2.0.

- **Dwa surowce:** złoto 💰 i drewno 🪵. Wymiana w panelu stanu (lub `Q` / `E`): 20 💰 → 10 🪵 i 10 🪵 → 20 💰.
- **Plac przed zamkiem:** wybrukowany prostokąt wokół drogi. Armaty (30 💰 + 40 🪵) stawiasz w dowolnym wolnym
  miejscu placu (klik lub `5`); mają 3 unowocześnienia jak w 2.0: podwójny pocisk, +30% obrażeń, +30% szybkostrzelności.
- **Zaplecze pod planszą:** stałe miejsca na budynki, które zostają po zmianie krainy:
  - **Koszary** obok placu: co 30 s żołnierz wychodzi na drogę (zatrzymuje zombie i strzela), ulepszenia ×2 / ×4 / ×8;
  - **Fabryka** obok koszar: co 60 s czołg z działem obszarowym, ulepszenia ×2 / ×3 / ×4;
  - **8 działek przy zamku** na tartaki (+0,8 🪵/s) i kopalnie złota (+0,5 💰/s), ulepszenia +25% / +60% / +100%.
- **Klatka bossa** przy wejściu zombie: boss krainy czeka w niej od początku i wyrywa się z niej w 5. fali.
- Wieże z 3.0 (KM, moździerz, Tesla, posterunek) dalej stoją na polach przy drodze. Tytan obsługuje też zaplecze,
  armaty i wymianę.

Źródła: `zombie-4.0/src/`, budowanie: `python3 zombie-4.0/tools/build.py`.
