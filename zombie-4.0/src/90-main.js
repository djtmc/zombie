// Start i pętla gry.
function init() {
  initGfx();
  initPost();
  MAT.ghost = new THREE.MeshBasicMaterial({ color: 0x7dff5a, transparent: true, opacity: 0.28, depthWrite: false });
  initFx();
  initWeather();
  initTowers();
  initQuality();
  computeFit();
  CAM.dist = CAM.fitDist;
  initUI();
  initInput();
  setCommand(false);
  addEventListener('resize', () => { resizeGfx(); computeFit(); });
  startGame();
  setTimeout(() => { $('title').style.opacity = 0; }, 14000);
  if ('wakeLock' in navigator) { const req = () => navigator.wakeLock.request('screen').catch(() => { }); req(); document.addEventListener('visibilitychange', () => { if (!document.hidden) req(); }); }
  let last = performance.now(), time = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    if (now - last < 10.5) return;   // limit ~95 FPS: na ekranach 120/144 Hz oszczędza procesor i baterię
    const raw = (now - last) / 1000;
    let real = Math.min(0.05, raw);
    last = now;
    time += real;
    updateInput(real);
    const steps = GAME.paused ? 0 : GAME.speed;
    for (let i = 0; i < steps; i++) {
      const dt = real;
      layoutAnim(dt);
      updateGame(dt);
      if (MAP.state === 'live') { updateAI(dt); updateTowers(dt); updateZombies(dt); updateBase(dt); }
      updateFx(dt);
      updateLights(dt, time);
    }
    if (GAME.paused) updateLights(0, time);
    updateQuality(raw);
    updateAudio(real);
    placeCamera(real);
    updateHud(real);
    if (UI.sel || UI.selPad || UI.selSlot) placeMenu();
    const bodies = [];
    for (const e of Z.list) bodies.push(e.B);
    for (const t of T.list) for (const s of t.soldiers) bodies.push(s.B);
    for (const u of BASE.units) if (!u.tank) bodies.push(u.B);
    if (BASE.caged) bodies.push(BASE.caged.B);
    drawBodies(bodies);
    GU.uTime.value = time % 1000;
    renderFrame(time);
  }
  requestAnimationFrame(frame);
  window.__z4 = window.__z3 = {
    GAME, MAP, T, Z, CAM, BASE, SLOTS, placeCannon, buildBld, upgradeBld, exchange, padAt: padAtScreen, bench(n) { let t0 = performance.now(); for (let i = 0; i < n; i++) { updateTowers(0.016); updateZombies(0.016); updateFx(0.016); placeCamera(0.016); updateHud(0.016); } const sim = (performance.now() - t0) / n; t0 = performance.now(); const gl = G.renderer.getContext(), px = new Uint8Array(4); G.renderer.info.autoReset = false; G.renderer.info.reset(); for (let i = 0; i < n; i++) { renderFrame(i * 0.016); gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px); } const r = { sim, render: (performance.now() - t0) / n, calls: G.renderer.info.render.calls / n, tris: G.renderer.info.render.triangles / n }; G.renderer.info.autoReset = true; return r; }, setQ(l) { QUALITY.mode = l; applyQuality(l); },
    // hak testowy: symulacja bez renderowania (dt = 0.05 s)
    step(secs) { for (let i = 0; i < secs * 20; i++) { layoutAnim(0.05); updateGame(0.05); if (MAP.state === 'live') { updateAI(0.05); updateTowers(0.05); updateZombies(0.05); updateBase(0.05); } updateFx(0.05); } },
    toScreen(x, z) { const v = new THREE.Vector3(x, 0.2, z).project(G.camera); return [(v.x + 1) / 2 * G.W, (1 - v.y) / 2 * G.H]; },
    fog() { return [G.scene.fog.near, G.scene.fog.far, CAM.dist, CAM.fitDist]; }
  };
}
init();
