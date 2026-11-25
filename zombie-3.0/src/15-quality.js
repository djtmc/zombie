// Jakość grafiki: trzy poziomy i tryb automatyczny, który obniża jakość, gdy gra działa za wolno.
const QLEVELS = [
  { name: 'Niska', scale: 0.4, maxW: 760, dpr: 0.5, shadow: 0, shadowEvery: 1, lights: 2, blur: false, glow: false, weather: 250 },
  { name: 'Średnia', scale: 0.5, maxW: 1000, dpr: 0.75, shadow: 1024, shadowEvery: 3, lights: 4, blur: true, glow: false, weather: 500 },
  { name: 'Wysoka', scale: 0.6, maxW: 1400, dpr: 1.5, shadow: 2048, shadowEvery: 1, lights: 8, blur: true, glow: true, weather: 900 }
];
const QUALITY = {
  mode: store.get('quality', 'auto'), cur: 1, frame: 0, acc: 0, n: 0, wait: 4,
  lv() { return QLEVELS[this.cur]; }
};

function applyQuality(i) {
  QUALITY.cur = clamp(i, 0, QLEVELS.length - 1);
  const q = QUALITY.lv();
  // cienie
  G.sun.castShadow = !!q.shadow;
  if (q.shadow && G.sun.shadow.mapSize.x !== q.shadow) {
    G.sun.shadow.mapSize.set(q.shadow, q.shadow);
    if (G.sun.shadow.map) { G.sun.shadow.map.dispose(); G.sun.shadow.map = null; }
  }
  G.renderer.shadowMap.needsUpdate = true;
  // światła punktowe: zbędne wyłączamy całkiem (mniej obliczeń na każdy piksel)
  G.lights.forEach((s, k) => {
    const on = k < q.lights;
    if (on === s.on) return;
    s.on = on;
    if (on) G.scene.add(s.l); else { G.scene.remove(s.l); s.owner = null; s.l.intensity = 0; }
  });
  if (MAP.state === 'live') { releaseLights('map'); releaseLights('fort'); lightMapDecor(); }
  POST.mat.uniforms.uGlow.value = q.glow ? 0.16 : 0;
  if (FX.weather) FX.weather.geometry.setDrawRange(0, q.weather);
  resizeGfx();
  const b = $('bQuality');
  if (b) b.textContent = (QUALITY.mode === 'auto' ? 'Auto · ' : '') + q.name;
}

function initQuality() {
  const start = QUALITY.mode === 'auto' ? (isTouch || (navigator.hardwareConcurrency || 4) <= 4 ? 1 : 2) : QUALITY.mode;
  applyQuality(start);
}

function cycleQuality() {
  // Auto -> Wysoka -> Średnia -> Niska -> Auto
  const order = ['auto', 2, 1, 0];
  QUALITY.mode = order[(order.indexOf(QUALITY.mode) + 1) % order.length];
  store.set('quality', QUALITY.mode);
  QUALITY.acc = 0; QUALITY.n = 0; QUALITY.wait = 4;
  applyQuality(QUALITY.mode === 'auto' ? 1 : QUALITY.mode);
  showNote('Grafika', 'jakość: ' + (QUALITY.mode === 'auto' ? 'automatyczna' : QUALITY.lv().name.toLowerCase()));
}

// Tryb auto: mierzy średni czas klatki co 3 s i obniża jakość, jeśli gra nie trzyma ~30 FPS.
function updateQuality(real) {
  if (QUALITY.mode !== 'auto' || document.hidden) return;
  if (QUALITY.wait > 0) { QUALITY.wait -= real; return; }
  QUALITY.acc += real; QUALITY.n++;
  if (QUALITY.acc < 3) return;
  const avg = QUALITY.acc / QUALITY.n;
  QUALITY.acc = 0; QUALITY.n = 0;
  if (avg > 0.034 && QUALITY.cur > 0) {
    applyQuality(QUALITY.cur - 1);
    QUALITY.wait = 3;
    showNote('Grafika', 'obniżono jakość do: ' + QUALITY.lv().name.toLowerCase() + ', żeby gra działała płynniej.');
  }
}
