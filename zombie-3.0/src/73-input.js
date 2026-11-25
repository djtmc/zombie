// Sterowanie: mysz, dotyk (przeciąganie, szczypanie, podwójne dotknięcie) i klawiatura.
const IN = { ptrs: new Map(), drag: false, sx: 0, sy: 0, pinch: 0, lastTap: 0, hoverPad: null, keys: new Set(), zoomedIn: false };

function padAtScreen(x, y) { const g = camGround(x, y); return g ? nearestPad(g.x, g.z, 0.7) : null; }

function onTap(x, y) {
  unlockAudio();
  const now = performance.now();
  const g = camGround(x, y);
  const pad = padAtScreen(x, y);
  if (!pad && now - IN.lastTap < 320 && g) {
    // podwójne dotknięcie: przybliż w to miejsce / oddal
    if (CAM.dist > CAM.fitDist * 0.7) { CAM.dist = CAM.fitDist * 0.45; CAM.tx = g.x; CAM.tz = g.z; CAM.follow = false; CAM.fit = false; clampCam(); }
    else followFight();
    IN.lastTap = 0; return;
  }
  IN.lastTap = now;
  if (pad) {
    if (pad.tower) openTowerMenu(pad.tower); else openPadMenu(pad);
    sfx('click');
  } else closeMenu();
}

function initInput() {
  const cv = G.renderer.domElement;
  cv.addEventListener('pointerdown', e => {
    cv.setPointerCapture(e.pointerId);
    IN.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (IN.ptrs.size === 1) { IN.drag = false; IN.sx = e.clientX; IN.sy = e.clientY; }
    if (IN.ptrs.size === 2) { const p = [...IN.ptrs.values()]; IN.pinch = Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y); IN.drag = true; }
  });
  cv.addEventListener('pointermove', e => {
    const prev = IN.ptrs.get(e.pointerId);
    if (!prev) { // najechanie myszą
      const pad = padAtScreen(e.clientX, e.clientY);
      IN.hoverPad = pad;
      cv.style.cursor = pad ? 'pointer' : 'grab';
      if (!UI.sel && !UI.selPad) {
        if (pad) { T.hl.visible = true; T.hl.position.set(pad.x, 0.14, pad.z); if (pad.tower) showRange(pad.x, pad.z, towerRange(pad.tower.type, pad.tower.lv)); else hideRange(); }
        else { T.hl.visible = false; hideRange(); }
      }
      return;
    }
    if (IN.ptrs.size === 2) {
      IN.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
      const p = [...IN.ptrs.values()], d = Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y);
      if (IN.pinch > 0) zoomAt(IN.pinch / d, (p[0].x + p[1].x) / 2, (p[0].y + p[1].y) / 2);
      IN.pinch = d;
      return;
    }
    if (!IN.drag && Math.hypot(e.clientX - IN.sx, e.clientY - IN.sy) > 7) IN.drag = true;
    if (IN.drag) {
      const a = camGround(prev.x, prev.y), b = camGround(e.clientX, e.clientY);
      if (a && b) panBy(a.x - b.x, a.z - b.z);
    }
    IN.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  });
  const up = e => {
    const had = IN.ptrs.has(e.pointerId);
    IN.ptrs.delete(e.pointerId);
    if (had && IN.ptrs.size === 0 && !IN.drag) onTap(e.clientX, e.clientY);
    if (IN.ptrs.size < 2) IN.pinch = 0;
  };
  cv.addEventListener('pointerup', up);
  cv.addEventListener('pointercancel', e => { IN.ptrs.delete(e.pointerId); });
  cv.addEventListener('pointerleave', () => { if (!UI.sel && !UI.selPad) { T.hl.visible = false; hideRange(); } });
  cv.addEventListener('wheel', e => { e.preventDefault(); zoomAt(Math.exp(e.deltaY * 0.0012), e.clientX, e.clientY); }, { passive: false });
  cv.addEventListener('contextmenu', e => e.preventDefault());
  document.addEventListener('gesturestart', e => e.preventDefault());

  addEventListener('keydown', e => {
    unlockAudio();
    const k = e.key;
    if (k === 'Tab') { e.preventDefault(); cycleSpeed(); return; }
    if (k === ' ') { e.preventDefault(); if (GAME.state === 'prep') { takeCommand(); callWave(); } return; }
    if (k >= '1' && k <= '4') {
      const pad = UI.selPad || (IN.hoverPad && !IN.hoverPad.tower ? IN.hoverPad : null);
      if (pad) buildOn(pad, TOWER_KEYS[+k - 1]);
      return;
    }
    const lk = k.toLowerCase();
    if (lk === 'u') doUpgrade(UI.sel || (IN.hoverPad && IN.hoverPad.tower));
    else if (lk === 'x') { if (UI.sel) doSell(UI.sel); }
    else if (lk === 'c') setCommand(!GAME.ai);
    else if (lk === 'm') toggleMute();
    else if (lk === 'p') togglePause();
    else if (lk === 'g') cycleQuality();
    else if (lk === 'f' || k === '0') followFight();
    else if (k === '+' || k === '=') zoomAt(0.8);
    else if (k === '-' || k === '_') zoomAt(1.25);
    else if (k === 'Escape') closeMenu();
    else IN.keys.add(lk);
  });
  addEventListener('keyup', e => IN.keys.delete(e.key.toLowerCase()));
  addEventListener('blur', () => IN.keys.clear());
}

function updateInput(dt) {
  const s = CAM.dist * 0.6 * dt;
  let dx = 0, dz = 0;
  if (IN.keys.has('arrowleft') || IN.keys.has('a')) dx -= s;
  if (IN.keys.has('arrowright') || IN.keys.has('d')) dx += s;
  if (IN.keys.has('arrowup') || IN.keys.has('w')) dz -= s;
  if (IN.keys.has('arrowdown') || IN.keys.has('s')) dz += s;
  if (dx || dz) {
    if (CAM.fit) CAM.fit = false;
    // klawisze działają w osiach ekranu, niezależnie od obrotu kamery
    const c = Math.cos(CAM.yaw), sn = Math.sin(CAM.yaw);
    panBy(dx * c + dz * sn, -dx * sn + dz * c);
  }
}
