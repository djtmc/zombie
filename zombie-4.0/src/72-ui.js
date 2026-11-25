// Interfejs: pasek stanu, tablica fali, dowódca, menu budowy i wież, komunikaty.
const UI = { sel: null, selPad: null, selSlot: null, choice: null, sellArm: false, bannerT: 0, noteT: 0, hudT: 0, menuKey: '' };

function banner(big, small) {
  $('bannerBig').textContent = big; $('bannerSmall').textContent = small || '';
  $('banner').style.opacity = 1; UI.bannerT = 3;
}
function showNote(name, text) {
  $('note').innerHTML = '<b>' + name + '</b> · ' + text;
  $('note').style.opacity = 1; UI.noteT = 6;
}
function showBoss(name) { $('boss').style.display = 'block'; $('bossName').textContent = '👑 ' + name; }
function hideBoss() { $('boss').style.display = 'none'; }
function floatGold(n) {
  const el = document.createElement('div');
  el.textContent = '+' + n + ' 💰';
  el.style.cssText = 'position:fixed;left:' + ($('stats').getBoundingClientRect().left + 70) + 'px;top:' + ($('stats').getBoundingClientRect().bottom + 4) + 'px;color:#f2c14e;font-weight:bold;pointer-events:none;transition:all 1.4s;text-shadow:0 2px 0 #000';
  document.body.appendChild(el);
  requestAnimationFrame(() => { el.style.transform = 'translateY(-18px)'; el.style.opacity = 0; });
  setTimeout(() => el.remove(), 1500);
}

function setCommand(ai) {
  GAME.ai = ai;
  $('cmd').className = 'plate ' + (ai ? 'ai' : 'me');
  $('cmdWho').textContent = ai ? '🤖 Dowodzi Tytan' : '🎖️ Dowodzisz Ty';
  $('cmdSub').textContent = ai ? 'Twój Generał' : 'kliknij, by oddać dowodzenie Tytanowi';
  if (!ai) $('title').style.opacity = 0;
}
function takeCommand() { if (GAME.ai) setCommand(false); }

function updateHud(dt) {
  if (UI.bannerT > 0 && (UI.bannerT -= dt) <= 0) $('banner').style.opacity = 0;
  if (UI.noteT > 0 && (UI.noteT -= dt) <= 0) $('note').style.opacity = 0;
  if (GAME.boss) $('bossbar').firstElementChild.style.width = (100 * Math.max(0, GAME.boss.hp) / GAME.boss.max) + '%';
  UI.hudT -= dt;
  if (UI.hudT > 0) return;
  UI.hudT = 0.15;
  $('hp').textContent = Math.ceil(GAME.fortHp);
  $('hpbar').firstElementChild.style.width = (100 * GAME.fortHp / GAME.fortMax) + '%';
  $('gold').textContent = GAME.gold;
  $('wood').textContent = GAME.wood;
  const inc = income();
  $('stats').title = 'Dochód z zaplecza: +' + inc.g.toFixed(1) + ' 💰/s · +' + inc.w.toFixed(1) + ' 🪵/s';
  $('exG').classList.toggle('no', GAME.gold < EXCHANGE.g2w.g);
  $('exW').classList.toggle('no', GAME.wood < EXCHANGE.w2g.w);
  $('kills').textContent = GAME.kills;
  $('waveNo').textContent = Math.max(1, GAME.state === 'prep' ? GAME.wave + 1 : GAME.wave);
  $('biomeName').textContent = MAP.biome ? MAP.biome.name : '';
  let sub = '';
  if (GAME.state === 'prep') sub = (GAME.inBiome === 4 ? '👑 Boss za ' : 'Fala za ') + Math.ceil(GAME.timer) + ' s · wezwij teraz: +' + Math.floor(GAME.timer * 2) + ' 💰';
  else if (GAME.state === 'wave') sub = 'Zombie: ' + (Z.list.filter(e => !e.dead).length + GAME.queue.length) + (GAME.best ? ' · rekord: fala ' + GAME.best : '');
  else if (GAME.state === 'transition') sub = 'Nowa kraina się buduje…';
  else if (GAME.state === 'over') sub = 'Forteca padła';
  $('waveSub').textContent = sub;
  $('wave').classList.toggle('ready', GAME.state === 'prep');
  if (UI.sel || UI.selPad || UI.selSlot) refreshMenu();
}

// ---- menu ----
function towerInfo(type, lv) {
  const s = TOWERS[type].lv[lv];
  if (type === 'mg') return 'Obrażenia ' + s.dmg + ' · ' + s.rate + ' strz./s · zasięg ' + s.range;
  if (type === 'mortar') return 'Obrażenia ' + s.dmg + ' · wybuch ' + s.splash + ' · zasięg ' + s.range;
  if (type === 'tesla') return 'Obrażenia ' + s.dmg + ' · przeskoki ' + s.chain + ' · zasięg ' + s.range;
  if (type === 'cannon') return 'Obrażenia ' + s.dmg + (s.n > 1 ? ' ×' + s.n : '') + ' · ' + s.rate + ' strz./s · wybuch ' + s.splash + ' · zasięg ' + s.range;
  return 'Żołnierze ' + s.n + ' · zdrowie ' + s.hp + ' · obrażenia ' + s.dmg;
}
function openPadMenu(pad) {
  UI.selPad = pad; UI.sel = null; UI.selSlot = null; UI.choice = null; UI.sellArm = false; UI.menuKey = '';
  refreshMenu(true);
}
function openSlotMenu(slot) {
  UI.selSlot = slot; UI.sel = null; UI.selPad = null; UI.choice = null; UI.sellArm = false; UI.menuKey = ''; hideRange();
  refreshMenu(true);
}
function openTowerMenu(tw) {
  UI.sel = tw; UI.selPad = null; UI.selSlot = null; UI.sellArm = false; UI.menuKey = '';
  showRange(tw.pad.x, tw.pad.z, towerRange(tw.type, tw.lv));
  refreshMenu(true);
}
function closeMenu() {
  UI.sel = null; UI.selPad = null; UI.selSlot = null; UI.choice = null; UI.sellArm = false;
  $('menu').style.display = 'none'; hideRange(); hl(null);
}
function refreshMenu(place) {
  const m = $('menu');
  let html = '', key = '';
  const res = ' ' + GAME.gold + '/' + GAME.wood;
  if (UI.selPad && UI.selPad.plac) {
    const sp = UI.selPad, d = TOWERS.cannon, ok = sp.ok && canPay(d.cost);
    key = 'plac' + sp.x + ',' + sp.z + ok + res;
    html = '<h4><span>Plac · armaty</span><button class="x" data-a="close">✕</button></h4>';
    html += '<button class="opt' + (ok ? '' : ' no') + '" data-a="cannon"><span class="ic">' + d.ic + '</span><span><span class="nm">5. ' + d.name + '</span><div class="desc">' + d.desc + '<br>' + towerInfo('cannon', 0) + '</div></span><span class="cs">' + fmtCost(d.cost) + '</span></button>';
    if (!sp.ok) html += '<div class="desc">Tu nie zmieścisz armaty: za blisko drogi albo innej armaty.</div>';
    hl(sp.x, sp.z, 0.9, sp.ok);
    showRange(sp.x, sp.z, towerRange('cannon', 0));
  } else if (UI.selSlot) {
    const s = UI.selSlot, bl = bldAt(s.id);
    if (!bl) {
      const types = Object.keys(BLD).filter(k => BLD[k].slot === s.kind);
      key = 's' + s.id + UI.choice + res;
      html = '<h4><span>' + (s.kind === 'res' ? 'Działka przy zamku' : 'Miejsce: ' + BLD[types[0]].name) + '</span><button class="x" data-a="close">✕</button></h4>';
      for (const k of types) {
        const d = BLD[k], ok = canPay(d.cost);
        html += '<button class="opt' + (ok ? '' : ' no') + '" data-a="bld" data-b="' + k + '"><span class="ic">' + d.ic + '</span><span><span class="nm">' + d.name + '</span><div class="desc">' + d.desc + '</div></span><span class="cs">' + fmtCost(d.cost) + '</span></button>';
      }
    } else {
      const d = BLD[bl.type], c = bldUpCost(bl), up = BLD_UP[d.up][bl.lv];
      key = 'S' + s.id + bl.lv + UI.sellArm + res + Math.floor(bl.t) + bl.build;
      html = '<h4><span>' + d.ic + ' ' + d.name + ' · poziom ' + (bl.lv + 1) + '</span><button class="x" data-a="close">✕</button></h4>';
      let info = '';
      if (d.unit) {
        const have = BASE.units.filter(u => u.kind === d.unit && !u.dead).length;
        info = (d.unit === 'tank' ? 'Czołgi' : 'Żołnierze') + ': ' + have + '/' + UNIT[d.unit].cap + ' · ' + PROD_MULT[bl.type][bl.lv] + ' co ' + d.every + ' s · następne za ' + Math.ceil(d.every - bl.t) + ' s';
      } else { const i = bldIncome(bl); info = 'Produkcja: ' + (i.g ? '+' + i.g.toFixed(2).replace(/\.?0+$/, '') + ' 💰/s' : '+' + i.w.toFixed(2).replace(/\.?0+$/, '') + ' 🪵/s'); }
      html += '<div class="desc">' + info + (bl.build < 1 ? '<br>Budowa w toku…' : '') + '</div>';
      if (c) html += '<button class="opt' + (canPay(c) ? '' : ' no') + '" data-a="bup"><span class="ic">⬆️</span><span><span class="nm">Unowocześnij (U)</span><div class="desc">' + up.d + '</div></span><span class="cs">' + fmtCost(c) + '</span></button>';
      else html += '<div class="desc" style="margin:6px 0">Maksymalny poziom</div>';
      html += '<button class="opt" data-a="bsell"><span class="ic">💰</span><span class="nm">' + (UI.sellArm ? 'Na pewno rozebrać?' : 'Rozbierz (X)') + '</span><span class="cs">' + fmtCost({ g: Math.floor(bl.spent.g * 0.5), w: Math.floor(bl.spent.w * 0.5) }, '+') + '</span></button>';
    }
    hl(s.x, s.z, s.size + 0.1, true);
  } else if (UI.selPad) {
    const pad = UI.selPad;
    if (pad.tower) { openTowerMenu(pad.tower); return; }
    key = 'p' + pad.id + UI.choice + res;
    html = '<h4><span>Zbuduj wieżę</span><button class="x" data-a="close">✕</button></h4>';
    TOWER_KEYS.forEach((k, i) => {
      const d = TOWERS[k], ok = canPay(d.cost);
      html += '<button class="opt' + (ok ? '' : ' no') + (UI.choice === k ? ' sel' : '') + '" data-a="b" data-k="' + k + '"><span class="ic">' + d.ic + '</span><span><span class="nm">' + (i + 1) + '. ' + d.name + '</span>' +
        (UI.choice === k ? '<div class="desc">' + d.desc + '<br>' + towerInfo(k, 0) + (isTouch ? '<br><b>Dotknij ponownie, by zbudować</b>' : '') + '</div>' : '') + '</span><span class="cs">' + d.cost + ' 💰</span></button>';
    });
    hl(pad.x, pad.z, 0.92, true);
    if (UI.choice) showRange(pad.x, pad.z, towerRange(UI.choice, 0)); else hideRange();
  } else if (UI.sel) {
    const tw = UI.sel, d = TOWERS[tw.type];
    key = 't' + tw.pad.id + tw.lv + UI.sellArm + res + tw.build;
    html = '<h4><span>' + d.ic + ' ' + d.name + ' · poziom ' + (tw.lv + 1) + '</span><button class="x" data-a="close">✕</button></h4>';
    html += '<div class="desc">' + towerInfo(tw.type, tw.lv) + (tw.kills ? ' · zabitych ' + tw.kills : '') + (tw.build < 1 ? '<br>Budowa w toku…' : '') + '</div>';
    if (tw.lv < maxLv(tw)) {
      const c = d.up[tw.lv], ok = canPay(c);
      html += '<button class="opt' + (ok ? '' : ' no') + '" data-a="up"><span class="ic">⬆️</span><span><span class="nm">' + (d.free ? 'Unowocześnij (U)' : 'Rozbuduj (U)') + '</span><div class="desc">' + d.next[tw.lv + 1] + '<br>' + towerInfo(tw.type, tw.lv + 1) + '</div></span><span class="cs">' + fmtCost(c) + '</span></button>';
    } else html += '<div class="desc" style="margin:6px 0">Maksymalny poziom</div>';
    html += '<button class="opt" data-a="sell"><span class="ic">💰</span><span class="nm">' + (UI.sellArm ? 'Na pewno sprzedać?' : 'Sprzedaj (X)') + '</span><span class="cs">' + fmtCost({ g: Math.floor(tw.spent.g * 0.7), w: Math.floor(tw.spent.w * 0.7) }, '+') + '</span></button>';
    hl(tw.pad.x, tw.pad.z, tw.pad.free ? 0.8 : 0.92, true);
  } else return;
  if (key !== UI.menuKey) { m.innerHTML = html; UI.menuKey = key; }
  m.style.display = 'block';
  if (place || true) placeMenu();
}
function placeMenu() {
  const m = $('menu'), obj = UI.sel ? UI.sel.pad : UI.selPad || UI.selSlot;
  if (!obj) return;
  if (G.W < 640) { m.style.left = '50%'; m.style.top = 'auto'; m.style.bottom = 'calc(58px + env(safe-area-inset-bottom,0px))'; m.style.transform = 'translateX(-50%)'; return; }
  const v = new THREE.Vector3(obj.x, 0.5, obj.z).project(G.camera);
  const sx = (v.x + 1) / 2 * G.W, sy = (1 - v.y) / 2 * G.H;
  const w = m.offsetWidth || 240, h = m.offsetHeight || 200;
  let x = sx + 24, y = sy - h / 2;
  if (x + w > G.W - 8) x = sx - w - 24;
  m.style.transform = 'none'; m.style.bottom = 'auto';
  m.style.left = clamp(x, 8, G.W - w - 8) + 'px';
  m.style.top = clamp(y, 70, G.H - h - 60) + 'px';
}

function buildOn(pad, k) {
  if (pad && pad.plac) { buildCannonAt(pad); return; }
  if (!pad || pad.tower || pad.free || !canPay(TOWERS[k].cost) || MAP.state !== 'live') { sfx('nope'); return; }
  takeCommand();
  pay(TOWERS[k].cost);
  const tw = spawnTower(pad, k);
  openTowerMenu(tw);
}
function buildCannonAt(sp) {
  const tw = sp && placeCannon(sp.x, sp.z);
  if (!tw) { sfx('nope'); return; }
  takeCommand();
  openTowerMenu(tw);
}
function doBuild(slot, type) {
  if (!slot || MAP.state !== 'live' || !buildBld(slot, type)) { sfx('nope'); return; }
  takeCommand(); UI.menuKey = ''; refreshMenu();
}
function doBldUp(bl) { if (!bl) return; takeCommand(); if (!upgradeBld(bl)) sfx('nope'); UI.menuKey = ''; }
function doBldSell(bl) {
  if (!bl) return;
  if (!UI.sellArm) { UI.sellArm = true; UI.menuKey = ''; refreshMenu(); return; }
  takeCommand(); sellBld(bl); closeMenu();
}
// podświetlenie pola: kwadrat o boku size, czerwony gdy nie da się tu budować
function hl(x, z, size, ok) {
  if (x === null) { T.hl.visible = false; return; }
  T.hl.visible = true; T.hl.position.set(x, 0.14, z); T.hl.scale.set(size / 0.92, 1, size / 0.92);
  T.hl.material.color.set(ok ? 0xffe08a : 0xff5040);
}
function doUpgrade(tw) { if (!tw) return; takeCommand(); if (!upgradeTower(tw)) sfx('nope'); UI.menuKey = ''; }
function doSell(tw) {
  if (!tw) return;
  if (!UI.sellArm) { UI.sellArm = true; UI.menuKey = ''; refreshMenu(); return; }
  takeCommand(); sellTower(tw); closeMenu();
}

function initUI() {
  $('menu').addEventListener('click', ev => {
    const b = ev.target.closest('button'); if (!b) return;
    ev.stopPropagation();
    const a = b.dataset.a;
    if (a === 'close') closeMenu();
    else if (a === 'b') {
      const k = b.dataset.k;
      if (isTouch && UI.choice !== k) { UI.choice = k; UI.menuKey = ''; refreshMenu(); }
      else buildOn(UI.selPad, k);
    } else if (a === 'cannon') buildCannonAt(UI.selPad);
    else if (a === 'bld') doBuild(UI.selSlot, b.dataset.b);
    else if (a === 'bup') doBldUp(bldAt(UI.selSlot.id));
    else if (a === 'bsell') doBldSell(bldAt(UI.selSlot.id));
    else if (a === 'up') doUpgrade(UI.sel);
    else if (a === 'sell') doSell(UI.sel);
  });
  $('menu').addEventListener('mouseover', ev => {
    const b = ev.target.closest('button[data-k]');
    if (b && UI.selPad && UI.choice !== b.dataset.k) { UI.choice = b.dataset.k; UI.menuKey = ''; refreshMenu(); }
  });
  $('wave').addEventListener('click', () => { if (GAME.state === 'prep') { takeCommand(); callWave(); } else sfx('nope'); });
  $('cmd').addEventListener('click', () => setCommand(!GAME.ai));
  $('exG').addEventListener('click', ev => { ev.stopPropagation(); takeCommand(); exchange('g2w'); UI.hudT = 0; });
  $('exW').addEventListener('click', ev => { ev.stopPropagation(); takeCommand(); exchange('w2g'); UI.hudT = 0; });
  $('bPause').addEventListener('click', togglePause);
  $('bSpeed').addEventListener('click', cycleSpeed);
  $('bMute').addEventListener('click', toggleMute);
  $('bZoomIn').addEventListener('click', () => zoomAt(0.8));
  $('bZoomOut').addEventListener('click', () => zoomAt(1.25));
  $('bFollow').addEventListener('click', followFight);
  $('bFull').addEventListener('click', () => { const d = document.documentElement; if (document.fullscreenElement) document.exitFullscreen(); else if (d.requestFullscreen) d.requestFullscreen().catch(() => { }); });
  if (!document.documentElement.requestFullscreen) $('bFull').style.display = 'none';
  $('bRestart').addEventListener('click', () => startGame());
  $('bQuality').addEventListener('click', cycleQuality);
  $('bQuality').textContent = (QUALITY.mode === 'auto' ? 'Auto · ' : '') + QUALITY.lv().name;
  $('bMute').textContent = AUDIO.muted ? '🔇' : '🔊';
}
function togglePause() { GAME.paused = !GAME.paused; $('bPause').textContent = GAME.paused ? '▶' : '⏸'; $('bPause').classList.toggle('on', GAME.paused); }
function cycleSpeed() { GAME.speed = GAME.speed >= 3 ? 1 : GAME.speed + 1; $('bSpeed').textContent = GAME.speed + '×'; $('bSpeed').classList.toggle('on', GAME.speed > 1); }
function toggleMute() { setMute(!AUDIO.muted); $('bMute').textContent = AUDIO.muted ? '🔇' : '🔊'; }
