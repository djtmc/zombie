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
