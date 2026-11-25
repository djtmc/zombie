// Jakość grafiki: trzy poziomy + tryb automatyczny.
// Wewnątrz poziomu rozdzielczość dopasowuje się płynnie (w dół i w górę) do wydajności sprzętu.
const QLEVELS = [
  { name: 'Niska', scale: 0.4, maxPix: 200000, dpr: 0.5, shadow: 0, shadowEvery: 1, lights: 2, blur: false, glow: false, weather: 250, detail: false, mist: false },
  { name: 'Średnia', scale: 0.5, maxPix: 420000, dpr: 0.75, shadow: 1024, shadowEvery: 3, lights: 4, blur: true, glow: false, weather: 500, detail: false, mist: false },
  { name: 'Wysoka', scale: 0.6, maxPix: 690000, dpr: 1.5, shadow: 2048, shadowEvery: 1, lights: 8, blur: true, glow: true, weather: 900, detail: true, mist: true }
];
const QUALITY = {
  mode: store.get('quality', 'auto'), cur: 1, res: 1, frame: 0,
  acc: 0, n: 0, slow: 0, fast: 0, hold: 0, back: 12, wait: 3,
  lv() { return QLEVELS[this.cur]; }
};

function applyQuality(i) {
  QUALITY.cur = clamp(i, 0, QLEVELS.length - 1);
  const q = QUALITY.lv();
  G.sun.castShadow = !!q.shadow;
  if (q.shadow && G.sun.shadow.mapSize.x !== q.shadow) {
    G.sun.shadow.mapSize.set(q.shadow, q.shadow);
    if (G.sun.shadow.map) { G.sun.shadow.map.dispose(); G.sun.shadow.map = null; }
  }
  G.renderer.shadowMap.needsUpdate = true;
  G.lights.forEach((s, k) => {
    const on = k < q.lights;
    if (on === s.on) return;
    s.on = on;
    if (on) G.scene.add(s.l); else { G.scene.remove(s.l); s.owner = null; s.l.intensity = 0; }
  });
  if (MAP.state === 'live') { releaseLights('map'); releaseLights('fort'); lightMapDecor(); }
  POST.mat.uniforms.uGlow.value = q.glow ? 0.16 : 0;
  POST.mat.defines = POST.mat.defines || {};
  if (q.mist) POST.mat.defines.MIST = ''; else delete POST.mat.defines.MIST;
  POST.mat.needsUpdate = true;
  setDetail(MAT.v, q.detail); setDetail(MAT.tiles, q.detail);
  if (FX.weather) FX.weather.geometry.setDrawRange(0, q.weather);
  resizeGfx();
  updateQualityButton();
}
function updateQualityButton() {
  const b = $('bQuality');
  if (b) b.textContent = (QUALITY.mode === 'auto' ? 'Auto · ' : '') + QUALITY.lv().name;
}

function initQuality() {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) GU.uWind.value = 0.3;
  const start = QUALITY.mode === 'auto' ? (isTouch || (navigator.hardwareConcurrency || 4) <= 4 ? 1 : 2) : QUALITY.mode;
  applyQuality(start);
}

function cycleQuality() {
  // Auto -> Wysoka -> Średnia -> Niska -> Auto
  const order = ['auto', 2, 1, 0];
  QUALITY.mode = order[(order.indexOf(QUALITY.mode) + 1) % order.length];
  store.set('quality', QUALITY.mode);
  QUALITY.res = 1; QUALITY.slow = QUALITY.fast = 0; QUALITY.hold = 0; QUALITY.back = 12; QUALITY.wait = 3;
  applyQuality(QUALITY.mode === 'auto' ? (isTouch ? 1 : 2) : QUALITY.mode);
  showNote('Grafika', 'jakość: ' + (QUALITY.mode === 'auto' ? 'automatyczna' : QUALITY.lv().name.toLowerCase()));
}

// Co 2 s: średni czas klatki. Wolno (> 22.5 ms) -> mniejsza rozdzielczość, a na dnie (tylko Auto) niższy poziom.
// Szybko (< 18.6 ms) -> większa rozdzielczość, a na szczycie (tylko Auto) wyższy poziom.
// Po każdym obniżeniu czekamy coraz dłużej z ponownym podniesieniem, żeby jakość nie skakała.
function updateQuality(raw) {
  if (document.hidden || raw > 0.25) { QUALITY.acc = 0; QUALITY.n = 0; return; }
  if (QUALITY.wait > 0) { QUALITY.wait -= raw; return; }
  QUALITY.acc += raw; QUALITY.n++;
  if (QUALITY.acc < 2) return;
  const ms = QUALITY.acc / QUALITY.n * 1000;
  QUALITY.hold -= QUALITY.acc;
  QUALITY.acc = 0; QUALITY.n = 0;
  if (ms > 22.5) { QUALITY.slow++; QUALITY.fast = 0; } else { QUALITY.slow = 0; QUALITY.fast = ms < 18.6 ? QUALITY.fast + 1 : 0; }
  const auto = QUALITY.mode === 'auto';
  if (QUALITY.slow >= 2) {
    QUALITY.slow = 0;
    if (QUALITY.res > 0.56) { QUALITY.res = Math.max(0.55, QUALITY.res - 0.15); resizeGfx(); }
    else if (auto && QUALITY.cur > 0) {
      QUALITY.res = 1; applyQuality(QUALITY.cur - 1);
      showNote('Grafika', 'obniżono jakość do: ' + QUALITY.lv().name.toLowerCase() + ', żeby gra działała płynniej.');
    }
    QUALITY.hold = QUALITY.back; QUALITY.back = Math.min(480, QUALITY.back * 2); QUALITY.wait = 1;
  } else if (QUALITY.fast >= 3 && QUALITY.hold <= 0) {
    QUALITY.fast = 0;
    if (QUALITY.res < 0.99) { QUALITY.res = Math.min(1, QUALITY.res + 0.15); resizeGfx(); }
    else if (auto && QUALITY.cur < 2 && !isTouch) { QUALITY.res = 0.7; applyQuality(QUALITY.cur + 1); QUALITY.hold = QUALITY.back; }
  }
}
