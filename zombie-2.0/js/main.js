// =====================================================================
//  ZOMBIE SURVIVAL 3D 2.0 - punkt wejścia
// =====================================================================
import { Renderer, CameraRig } from './render.js';
import { World } from './world.js';
import { Effects } from './effects.js';
import { Audio } from './audio.js';
import { Game } from './game.js';
import { UI } from './ui.js';
import { Input } from './input.js';
import { QUALITY, BRIGHTNESS, MAP } from './config.js';

const SETTINGS_KEY = 'zombie2.settings';
const $ = (id) => document.getElementById(id);

function loadSettings() {
  const def = { quality: 'auto', brightness: 1, volume: 0.7, muted: false, showFps: false };
  try { return { ...def, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') }; } catch (e) { return def; }
}
function saveSettings(s) { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(s)); } catch (e) {} }

function detectQuality() {
  const coarse = matchMedia('(pointer: coarse)').matches;
  const small = Math.max(screen.width, screen.height) < 1000;
  const cv = document.createElement('canvas');
  const gl2 = !!cv.getContext('webgl2');
  if (!gl2) return 'low';
  return coarse || small ? 'medium' : 'high';
}

function fatal(msg) {
  $('loading').classList.add('hidden');
  $('errorText').textContent = msg;
  $('error-screen').classList.remove('hidden');
}

function boot() {
  const settings = loadSettings();
  let quality = settings.quality === 'auto' ? detectQuality() : settings.quality;

  let renderer;
  try { renderer = new Renderer($('canvas-wrap')); }
  catch (e) { fatal('Twoja przeglądarka nie obsługuje WebGL. Spróbuj Chrome, Firefox, Edge lub Safari.'); return; }

  const scene = renderer.scene;
  const world = new World(scene, QUALITY[quality]);
  const effects = new Effects(scene, QUALITY[quality]);
  const audio = new Audio();
  audio.setVolume(settings.volume);
  audio.setMuted(settings.muted);
  const game = new Game({ scene, world, effects, audio });
  const rig = new CameraRig(renderer.camera);

  let state = 'menu';         // menu | playing | over
  let paused = false;
  let speed = 1;

  const applyQuality = (key) => {
    quality = key;
    world.buildDecor(QUALITY[key]);
    effects.setQuality(QUALITY[key]);
    for (const r of [game.zombieRig, game.soldierRig, game.tankRig]) r.setShadows(QUALITY[key].shadows);
    renderer.applyQuality(key);
    effects.setScale(renderer.pointScale);
  };
  renderer.onResize = () => effects.setScale(renderer.pointScale);

  const modalOpen = () => ['pause-modal', 'settings-modal', 'help-modal', 'level-modal', 'over-modal'].some(id => ui.isOpen(id));
  const sync = () => ui.syncSettings(settings, QUALITY[quality].name + (settings.quality === 'auto' ? ' (auto)' : ''));

  const handlers = {
    unlockAudio: () => audio.unlock(),
    click: () => audio.click(),
    newGame(diff) {
      audio.unlock(); audio.click();
      for (const id of ['over-modal', 'level-modal', 'pause-modal']) ui.hide(id);
      game.reset(diff);
      game.save();
      state = 'playing'; paused = false; speed = 1;
      ui.setPauseIcon(false); ui.setSpeed(1);
      rig.targetX = MAP.baseX - 30;
      ui.showHud();
      ui.announce('POZIOM 1', `${game.diff.name} • przygotuj obronę!`, 'good');
      input.enabled = true;
    },
    continueGame() {
      audio.unlock(); audio.click();
      if (!game.load()) { ui.toast('Nie udało się wczytać zapisu'); return; }
      state = 'playing'; paused = false; speed = 1;
      ui.setPauseIcon(false); ui.setSpeed(1);
      ui.showHud();
      ui.announce(`POZIOM ${game.level}`, 'Wczytano zapis gry', 'good');
      input.enabled = true;
    },
    togglePause(force) {
      if (state !== 'playing' || ui.isOpen('level-modal')) return;
      paused = force ?? !paused;
      ui.setPauseIcon(paused);
      if (paused) ui.show('pause-modal'); else ui.hide('pause-modal');
      audio.click();
    },
    toggleSpeed() {
      speed = speed === 1 ? 2 : speed === 2 ? 3 : 1;
      ui.setSpeed(speed);
      audio.click();
    },
    toggleSound() {
      settings.muted = !settings.muted;
      audio.setMuted(settings.muted);
      saveSettings(settings); sync();
    },
    openSettings() { sync(); ui.show('settings-modal'); audio.click(); },
    quitToMenu() {
      for (const id of ['pause-modal', 'over-modal', 'level-modal']) ui.hide(id);
      state = 'menu'; paused = false;
      game.cancelBuild(); game.deselect();
      game.reset(game.difficultyIndex);
      ui.showMenu(Game.hasSave(), Game.savedInfo(), Game.best());
    },
    nextLevel() {
      ui.hide('level-modal');
      game.nextLevel();
      game.paused = false;
      ui.announce(`POZIOM ${game.level}`, `${game.levelGoal} zombie • ${game.maxWaves} ${game.maxWaves === 1 ? 'fala' : game.maxWaves < 5 ? 'fale' : 'fal'}`, 'good');
      ui.toast('💾 Gra zapisana');
    },
    setQuality(q) {
      settings.quality = q; saveSettings(settings);
      applyQuality(q === 'auto' ? detectQuality() : q);
      sync();
    },
    setBrightness(i) {
      settings.brightness = i; saveSettings(settings);
      renderer.setExposure(BRIGHTNESS[i].exposure); sync();
    },
    setVolume(v) { settings.volume = v; audio.setVolume(v); saveSettings(settings); },
    toggleFps() { settings.showFps = !settings.showFps; saveSettings(settings); sync(); },
    setDifficulty(i) { game.setDifficulty(i); sync(); },
    escape() {
      if (ui.isOpen('settings-modal')) { ui.hide('settings-modal'); return; }
      if (ui.isOpen('help-modal')) { ui.hide('help-modal'); return; }
      if (game.buildType) { game.cancelBuild(); return; }
      if (game.selected) { game.deselect(); return; }
      if (state === 'playing') handlers.togglePause();
    },
  };

  const ui = new UI(game, handlers);
  const input = new Input(renderer.renderer.domElement, rig, renderer.camera, game, handlers);
  input.enabled = false;

  game.on('camShake', (v) => rig.addShake(v));
  game.on('levelComplete', (d) => { game.paused = true; game.cancelBuild(); ui.showLevelComplete(d); });
  game.on('gameOver', (d) => {
    state = 'over';
    game.cancelBuild(); game.deselect();
    rig.addShake(1.5);
    setTimeout(() => ui.showGameOver(d), 1200);
  });

  applyQuality(quality);
  renderer.setExposure(BRIGHTNESS[settings.brightness].exposure);
  sync();
  ui.showMenu(Game.hasSave(), Game.savedInfo(), Game.best());

  // pauza po przełączeniu karty
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && state === 'playing' && !paused && !modalOpen()) handlers.togglePause(true);
  });

  // ------------------------------------------------------------- PĘTLA
  let last = performance.now();
  let uiTimer = 0, fpsTimer = 0, frames = 0, menuT = 0;
  let lowFpsStrikes = 0, playTime = 0;

  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;

    const running = state === 'playing' && !paused && !modalOpen();
    if (running) {
      for (let i = 0; i < speed; i++) game.update(dt);
      playTime += dt;
    } else if (state === 'menu') {
      menuT += dt;
      rig.targetX = Math.sin(menuT * 0.06) * (MAP.halfW - 20);
      rig.targetZoom = 0.95;
    }

    input.update(dt);
    rig.update(dt);
    world.update(dt);
    effects.update(running || state !== 'playing' ? dt * (running ? speed : 1) : 0);
    game.updateVisuals();
    audio.listenerX = rig.x;
    renderer.damageFlash = Math.max(renderer.damageFlash, (game.baseFlash || 0) * 0.5);
    ui.updateFrame(renderer.camera, dt);

    uiTimer += dt;
    if (uiTimer > 0.1 && state !== 'menu') { uiTimer = 0; ui.refresh(); }

    renderer.render(dt);

    // FPS + automatyczna jakość
    frames++; fpsTimer += dt;
    if (fpsTimer >= 2) {
      const fps = Math.round(frames / fpsTimer);
      ui.setFps(fps, QUALITY[quality].name);
      if (settings.quality === 'auto' && running && playTime > 6 && quality !== 'low') {
        lowFpsStrikes = fps < 34 ? lowFpsStrikes + 1 : 0;
        if (lowFpsStrikes >= 2) {
          lowFpsStrikes = 0;
          const next = quality === 'high' ? 'medium' : 'low';
          applyQuality(next);
          ui.toast(`⚙️ Obniżono jakość grafiki: ${QUALITY[next].name}`);
          sync();
        }
      }
      frames = 0; fpsTimer = 0;
    }
  }
  requestAnimationFrame(frame);

  $('loading').classList.add('hidden');
  window.__zombie = { game, renderer, rig, world, effects, ui, handlers }; // do debugowania w konsoli
}

try { boot(); }
catch (e) { console.error(e); fatal('Nie udało się uruchomić gry: ' + e.message); }

if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(err => console.warn('SW:', err)));
}
