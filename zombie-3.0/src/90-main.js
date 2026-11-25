// Start i pętla gry.
function init() {
  initGfx();
  initPost();
  MAT.ghost = new THREE.MeshBasicMaterial({ color: 0x7dff5a, transparent: true, opacity: 0.28, depthWrite: false });
  initFx();
  initWeather();
  initTowers();
  resizeGfx();
  computeFit();
  CAM.dist = CAM.fitDist;
  initUI();
  initInput();
  setCommand(true);
  addEventListener('resize', () => { resizeGfx(); computeFit(); });
  startGame();
  setTimeout(() => { $('title').style.opacity = 0; }, 14000);
  if ('wakeLock' in navigator) { const req = () => navigator.wakeLock.request('screen').catch(() => { }); req(); document.addEventListener('visibilitychange', () => { if (!document.hidden) req(); }); }
  let last = performance.now(), time = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    let real = Math.min(0.05, (now - last) / 1000);
    last = now;
    time += real;
    updateInput(real);
    const steps = GAME.paused ? 0 : GAME.speed;
    for (let i = 0; i < steps; i++) {
      const dt = real;
      layoutAnim(dt);
      updateGame(dt);
      if (MAP.state === 'live') { updateAI(dt); updateTowers(dt); updateZombies(dt); }
      updateFx(dt);
      updateLights(dt, time);
    }
    if (GAME.paused) updateLights(0, time);
    updateAudio(real);
    placeCamera(real);
    updateHud(real);
    if (UI.sel || UI.selPad) placeMenu();
    renderFrame(time);
  }
  requestAnimationFrame(frame);
  window.__z3 = {
    GAME, MAP, T, Z, CAM, padAt: padAtScreen,
    // hak testowy: symulacja bez renderowania (dt = 0.05 s)
    step(secs) { for (let i = 0; i < secs * 20; i++) { layoutAnim(0.05); updateGame(0.05); if (MAP.state === 'live') { updateAI(0.05); updateTowers(0.05); updateZombies(0.05); } updateFx(0.05); } },
    fog() { return [G.scene.fog.near, G.scene.fog.far, CAM.dist, CAM.fitDist]; }
  };
}
init();
