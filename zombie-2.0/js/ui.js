// =====================================================================
//  INTERFEJS: HUD, pasek budowania, panel budynku, komunikaty, modale
// =====================================================================
import * as THREE from 'three';
import { BUILDINGS, BUILD_ORDER, UNITS, RESOURCE_BONUS, BARRACKS_MULT } from './config.js';

const $ = (id) => document.getElementById(id);
const ICON_PAUSE = '<svg viewBox="0 0 24 24" width="18" height="18"><rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor"/><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor"/></svg>';
const ICON_PLAY = '<svg viewBox="0 0 24 24" width="18" height="18"><path d="M8 5l11 7-11 7z" fill="currentColor"/></svg>';
const fmt = (n) => {
  n = Math.floor(n);
  return n >= 100000 ? (n / 1000).toFixed(0) + 'k' : n >= 10000 ? (n / 1000).toFixed(1) + 'k' : String(n);
};
const costHTML = (c, game) => {
  const p = [];
  if (c.wood) p.push(`<span class="${game && game.wood < c.wood ? 'no' : ''}">${fmt(c.wood)}🪵</span>`);
  if (c.gold) p.push(`<span class="${game && game.gold < c.gold ? 'no' : ''}">${fmt(c.gold)}💰</span>`);
  return p.join(' ') || 'za darmo';
};

export class UI {
  constructor(game, handlers) {
    this.game = game;
    this.h = handlers;
    this.floaters = [];
    this.floaterPool = [];
    this._v = new THREE.Vector3();
    this._lastGold = 0; this._lastWood = 0;
    this._buildBar();
    this._wire();
    game.on('change', () => this.refresh());
    game.on('notify', (t) => this.toast(t));
    game.on('toast', (t) => this.toast(t));
    game.on('announce', (a, b, cls) => this.announce(a, b, cls));
    game.on('floater', (x, y, z, text, color) => this.floater(x, y, z, text, color));
    game.on('select', (b) => this.showBuilding(b));
    game.on('buildMode', (t) => this._buildMode(t));
  }

  // ---------------------------------------------------------------- pasek budowania
  _buildBar() {
    const bar = $('build-bar');
    this.cards = {};
    for (const type of BUILD_ORDER) {
      const def = BUILDINGS[type];
      const el = document.createElement('button');
      el.className = 'bcard' + (def.resource ? ' rescard' : '') + (def.cost.gold >= 500 || type === 'soldier' ? ' special' : '');
      el.innerHTML = `<span class="key">${def.key}</span><span class="cnt"></span><span class="ic">${def.icon}</span><div class="nm">${def.name}</div><div class="cs"></div>`;
      el.addEventListener('click', () => { this.h.unlockAudio(); this.game.selectBuild(type); });
      el.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') this._tooltip(type, el); });
      el.addEventListener('pointerleave', () => $('tooltip').classList.add('hidden'));
      bar.appendChild(el);
      this.cards[type] = el;
    }
  }

  _tooltip(type, el) {
    const def = BUILDINGS[type];
    const t = $('tooltip');
    const rows = [];
    const u = def.unit ? UNITS.soldier : null;
    const hp = def.hp || u?.hp;
    if (hp) rows.push(['❤️ Wytrzymałość', hp]);
    const dmg = def.damage || u?.damage;
    if (dmg) rows.push(['💥 Obrażenia', dmg + (def.splash ? ` (obszar ${def.splash})` : '')]);
    const range = def.range || u?.range;
    if (range) rows.push(['🎯 Zasięg', range]);
    const rate = def.fireRate || u?.fireRate;
    if (rate) rows.push(['⏱️ Strzał co', rate.toFixed(2) + ' s']);
    if (def.woodPerSecond) rows.push(['🪵 Produkcja', `+${def.woodPerSecond}/s`]);
    if (def.goldPerSecond) rows.push(['💰 Produkcja', `+${def.goldPerSecond}/s`]);
    t.innerHTML = `<h4>${def.icon} ${def.name}</h4><div class="desc">${def.desc}</div>` +
      rows.map(([a, b]) => `<div class="st"><span>${a}</span><b>${b}</b></div>`).join('') +
      `<div class="st" style="margin-top:4px"><span>Koszt</span><b>${costHTML(def.cost)}</b></div>`;
    t.classList.remove('hidden');
    const r = el.getBoundingClientRect();
    t.style.left = Math.max(8, Math.min(innerWidth - 240, r.left + r.width / 2 - 115)) + 'px';
    t.style.top = (r.top - t.offsetHeight - 10) + 'px';
  }

  _buildMode(type) {
    for (const [k, el] of Object.entries(this.cards)) el.classList.toggle('selected', k === type);
    $('canvas-wrap').classList.toggle('building', !!type);
    const hint = $('build-hint');
    if (type) {
      const touch = matchMedia('(pointer: coarse)').matches;
      hint.textContent = BUILDINGS[type].slotOnly
        ? '🎯 Wskaż świecącą platformę • Esc - anuluj'
        : touch ? 'Stuknij, by zobaczyć podgląd • stuknij ponownie, by postawić' : 'Kliknij, by postawić • PPM / Esc - anuluj';
      hint.classList.remove('hidden');
    } else hint.classList.add('hidden');
  }

  // ---------------------------------------------------------------- przyciski
  _wire() {
    const h = this.h;
    $('pauseBtn').onclick = () => h.togglePause();
    $('speedBtn').onclick = () => h.toggleSpeed();
    $('soundBtn').onclick = () => h.toggleSound();
    $('settingsBtn').onclick = () => h.openSettings();
    $('waveBtn').onclick = () => { h.unlockAudio(); this.game.callWaveEarly(); };
    document.querySelectorAll('#exchange button').forEach(b => b.onclick = () => this.game.exchange(b.dataset.ex));

    $('bpClose').onclick = () => this.game.deselect();
    $('bpRepair').onclick = () => this.game.selected && this.game.repair(this.game.selected);
    $('bpSell').onclick = () => this.game.selected && this.game.sell(this.game.selected);

    // menu
    this.menuDiff = 2;
    document.querySelectorAll('#diffSelect button').forEach(b => b.onclick = () => {
      this.menuDiff = +b.dataset.diff;
      document.querySelectorAll('#diffSelect button').forEach(x => x.classList.toggle('active', x === b));
      h.click();
    });
    $('newGameBtn').onclick = () => h.newGame(this.menuDiff);
    $('continueBtn').onclick = () => h.continueGame();
    $('helpBtn').onclick = () => this.show('help-modal');
    $('menuSettingsBtn').onclick = () => h.openSettings();
    $('helpClose').onclick = () => { this.hide('help-modal'); h.click(); };

    $('resumeBtn').onclick = () => h.togglePause(false);
    $('pauseSettingsBtn').onclick = () => h.openSettings();
    $('pauseHelpBtn').onclick = () => this.show('help-modal');
    $('quitBtn').onclick = () => h.quitToMenu();

    $('nextLevelBtn').onclick = () => h.nextLevel();
    $('restartBtn').onclick = () => h.newGame(this.game.difficultyIndex);
    $('overMenuBtn').onclick = () => h.quitToMenu();

    document.querySelectorAll('#qualitySeg button').forEach(b => b.onclick = () => h.setQuality(b.dataset.q));
    document.querySelectorAll('#brightSeg button').forEach(b => b.onclick = () => h.setBrightness(+b.dataset.b));
    document.querySelectorAll('#diffSeg button').forEach(b => b.onclick = () => h.setDifficulty(+b.dataset.d));
    $('volume').oninput = (e) => h.setVolume(e.target.value / 100);
    $('fpsToggle').onclick = () => h.toggleFps();
    $('settingsClose').onclick = () => { this.hide('settings-modal'); h.click(); };

    // wszystkie przyciski klikają
    document.addEventListener('click', (e) => { if (e.target.closest('button')) h.unlockAudio(); }, true);
  }

  show(id) { $(id).classList.remove('hidden'); }
  hide(id) { $(id).classList.add('hidden'); }
  isOpen(id) { return !$(id).classList.contains('hidden'); }

  syncSettings(s, qualityLabel) {
    document.querySelectorAll('#qualitySeg button').forEach(b => b.classList.toggle('active', b.dataset.q === s.quality));
    document.querySelectorAll('#brightSeg button').forEach(b => b.classList.toggle('active', +b.dataset.b === s.brightness));
    document.querySelectorAll('#diffSeg button').forEach(b => b.classList.toggle('active', +b.dataset.d === this.game.difficultyIndex));
    $('volume').value = Math.round(s.volume * 100);
    const ft = $('fpsToggle'); ft.textContent = s.showFps ? 'WŁ' : 'WYŁ'; ft.classList.toggle('on', s.showFps);
    $('fps').classList.toggle('hidden', !s.showFps);
    $('soundBtn').textContent = s.muted ? '🔇' : '🔊';
    $('qualityInfo').textContent = `Aktualnie: ${qualityLabel}. Auto obniża jakość, gdy gra zwalnia.`;
  }

  // ---------------------------------------------------------------- HUD
  refresh() {
    const g = this.game;
    const hpk = g.baseHP / g.maxBaseHP;
    $('baseHPText').textContent = `${Math.ceil(g.baseHP)} / ${g.maxBaseHP}`;
    const bar = $('baseHPBar');
    bar.style.width = (hpk * 100) + '%';
    bar.style.backgroundPosition = `${(1 - hpk) * 100}% 0`;
    bar.parentElement.parentElement.classList.toggle('danger', hpk < 0.3);

    const gold = Math.floor(g.gold), wood = Math.floor(g.wood);
    $('gold').textContent = fmt(gold);
    $('wood').textContent = fmt(wood);
    if (gold > this._lastGold + 5) this._bump('gold');
    if (wood > this._lastWood + 5) this._bump('wood');
    this._lastGold = gold; this._lastWood = wood;
    $('goldRate').textContent = g.goldPerSecond ? `+${g.goldPerSecond}/s` : '';
    $('woodRate').textContent = g.woodPerSecond ? `+${g.woodPerSecond}/s` : '';
    $('unitCount').textContent = g.units.length;
    $('tankCount').textContent = g.tanks.length;
    $('kills').textContent = g.kills;

    $('level').textContent = g.level;
    $('wave').textContent = `${g.currentWave}/${g.maxWaves}`;
    $('levelBar').style.width = Math.min(100, g.levelKills / g.levelGoal * 100) + '%';
    $('levelGoalText').textContent = g.bossReleased ? '👑 Pokonaj bossa!' : `${g.levelKills} / ${g.levelGoal} zombie`;
    const alive = g.aliveRegular;
    $('zombieAlive').textContent = alive ? `🧟 ${alive} na mapie` : '';
    const wb = $('waveBtn');
    if (g.bossReleased) { wb.disabled = true; wb.innerHTML = '👑 Boss na polu walki'; }
    else if (g.toSpawn > 0) { wb.disabled = true; wb.innerHTML = `🧟 Nadciąga: ${g.toSpawn}`; }
    else if (!g.canCallWave) { wb.disabled = true; wb.innerHTML = '⚔️ Dokończ falę'; }
    else { wb.disabled = false; wb.innerHTML = `⏩ Fala za <b>${Math.ceil(g.waveCountdown)}</b>s <small>(wezwij teraz)</small>`; }

    for (const [type, el] of Object.entries(this.cards)) {
      const def = BUILDINGS[type];
      const disabled = !g.canAfford(type) || g.limitReached(type);
      el.classList.toggle('disabled', disabled);
      el.querySelector('.cs').innerHTML = costHTML(def.cost, g);
      const cnt = el.querySelector('.cnt');
      if (type === 'wielkaArmata') cnt.textContent = `${g.slotUsed.filter(Boolean).length}/4`;
      else if (def.limit) cnt.textContent = `${g.buildings.filter(b => b.type === type).length}/${def.limit}`;
    }
    const ex = document.querySelectorAll('#exchange button');
    ex[0].disabled = g.gold < 20; ex[1].disabled = g.wood < 10;

    const boss = g.boss;
    const bb = $('boss-bar');
    if (boss && g.bossReleased) {
      bb.classList.remove('hidden');
      $('bossBarFill').style.width = (boss.hp / boss.maxHP * 100) + '%';
      $('bossLevel').textContent = `poz. ${g.level}`;
    } else bb.classList.add('hidden');

    if (g.selected) this._refreshBuilding(g.selected);
  }

  _bump(id) {
    const el = $(id).parentElement;
    el.classList.remove('bump'); void el.offsetWidth; el.classList.add('bump');
  }

  // ---------------------------------------------------------------- panel budynku
  showBuilding(b) {
    const p = $('building-panel');
    if (!b) { p.classList.add('hidden'); return; }
    p.classList.remove('hidden');
    this._panelKey = null;
    this._refreshBuilding(b);
  }

  _refreshBuilding(b) {
    const g = this.game, def = BUILDINGS[b.type];
    $('bpIcon').textContent = def.icon;
    $('bpName').textContent = def.name;
    $('bpLevel').textContent = def.upgrades ? `Poziom ulepszeń: ${b.upgradeLevel}/3` : 'Bez ulepszeń';
    $('bpHP').style.width = (b.hp / b.maxHP * 100) + '%';
    const st = [['❤️ HP', `${Math.ceil(b.hp)} / ${b.maxHP}`]];
    if (b.type === 'cannon') {
      const lvl = b.upgradeLevel;
      st.push(['💥 Obrażenia', Math.round(def.damage * (lvl >= 2 ? 1.2 : 1)) + (lvl >= 1 ? ' ×2' : '')]);
      st.push(['⏱️ Strzał co', (def.fireRate * (lvl >= 3 ? 0.8 : 1)).toFixed(2) + ' s']);
      st.push(['🎯 Zasięg', def.range]);
    } else if (def.range) {
      st.push(['💥 Obrażenia', def.damage], ['⏱️ Strzał co', def.fireRate + ' s'], ['🎯 Zasięg', def.range]);
    }
    if (def.resource) {
      const base = def.woodPerSecond || def.goldPerSecond;
      st.push(['📦 Produkcja', `${Math.round(base * (1 + RESOURCE_BONUS[b.upgradeLevel]))} ${def.woodPerSecond ? '🪵' : '💰'}/s`]);
    }
    if (def.produce) {
      const n = def.produce === 'soldier' ? BARRACKS_MULT[b.upgradeLevel] : 1;
      st.push(['🏭 Produkcja', `${n} ${def.produce === 'soldier' ? '🪖' : '🛡️'} / ${def.interval}s`]);
      st.push(['⏳ Następne za', Math.ceil(def.interval - b.productionTimer) + ' s']);
    }
    $('bpStats').innerHTML = st.map(([a, v]) => `<span>${a}</span><b>${v}</b>`).join('');

    const tiers = g.upgradeInfo(b);
    const key = tiers ? tiers.map(t => `${t.owned}${t.available}${t.affordable}`).join() + b.upgradeLevel : 'none';
    if (key !== this._panelKey) {
      this._panelKey = key;
      const up = $('bpUpgrades');
      up.innerHTML = '';
      if (tiers) {
        for (const t of tiers) {
          const row = document.createElement('div');
          row.className = 'tier' + (t.owned ? ' owned' : '');
          row.innerHTML = `<div><div>Etap ${t.level}: ${t.desc}</div><div class="cost">${costHTML(t.cost, g)}</div></div>`;
          const btn = document.createElement('button');
          btn.textContent = t.owned ? '✔' : 'Kup';
          btn.disabled = t.owned || !t.available || !t.affordable;
          btn.onclick = () => g.buyUpgrade(b, t.level);
          row.appendChild(btn);
          up.appendChild(row);
        }
      }
    }
    const rc = g.repairCost(b);
    const rep = $('bpRepair');
    rep.disabled = b.hp >= b.maxHP || g.wood < rc.wood || g.gold < rc.gold;
    rep.innerHTML = b.hp >= b.maxHP ? '🔧 Sprawny' : `🔧 Napraw <small>${costHTML(rc)}</small>`;
    const sv = g.sellValue(b);
    $('bpSell').innerHTML = `💸 Sprzedaj <small>+${costHTML(sv)}</small>`;
  }

  // ---------------------------------------------------------------- komunikaty
  toast(text) {
    const box = $('toasts');
    const el = document.createElement('div');
    el.className = 'toast';
    el.textContent = text;
    box.prepend(el);
    while (box.children.length > 4) box.lastChild.remove();
    setTimeout(() => el.remove(), 3700);
  }

  announce(big, small = '', cls = '') {
    const box = $('announce');
    box.innerHTML = '';
    const el = document.createElement('div');
    el.className = 'ann ' + cls;
    el.innerHTML = `<div class="big">${big}</div><div class="small">${small}</div>`;
    box.appendChild(el);
    clearTimeout(this._annT);
    this._annT = setTimeout(() => el.remove(), 2700);
  }

  floater(x, y, z, text, color = '#fff') {
    if (this.floaters.length > 24) return;
    const el = this.floaterPool.pop() || document.createElement('div');
    el.className = 'floater';
    el.textContent = text;
    el.style.color = color;
    $('floaters').appendChild(el);
    this.floaters.push({ el, x, y, z, t: 0 });
  }

  updateFrame(camera, dt) {
    const v = this._v;
    for (let i = this.floaters.length - 1; i >= 0; i--) {
      const f = this.floaters[i];
      f.t += dt;
      if (f.t > 1.3) { f.el.remove(); this.floaterPool.push(f.el); this.floaters.splice(i, 1); continue; }
      v.set(f.x, f.y + f.t * 1.8, f.z).project(camera);
      const sx = (v.x * 0.5 + 0.5) * innerWidth, sy = (-v.y * 0.5 + 0.5) * innerHeight;
      f.el.style.transform = `translate(${sx}px, ${sy}px) translate(-50%, -50%) scale(${1 + Math.max(0, 0.3 - f.t)})`;
      f.el.style.opacity = Math.min(1, (1.3 - f.t) * 2.5);
    }
  }

  setFps(fps, quality) { $('fps').textContent = `${fps} FPS • ${quality}`; }
  setPauseIcon(p) { $('pauseBtn').innerHTML = p ? ICON_PLAY : ICON_PAUSE; $('pauseBtn').classList.toggle('active', p); }
  setSpeed(s) { $('speedBtn').textContent = `×${s}`; $('speedBtn').classList.toggle('active', s > 1); }

  showMenu(hasSave, info, best) {
    this.show('menu');
    $('hud').classList.add('hidden');
    $('continueBtn').classList.toggle('hidden', !hasSave);
    if (info) $('continueInfo').textContent = `(poziom ${info.level}, ${info.difficulty})`;
    $('bestText').textContent = best ? `🏆 Rekord: poziom ${best}` : '';
  }
  showHud() { this.hide('menu'); $('hud').classList.remove('hidden'); this.refresh(); }

  showLevelComplete({ level, kills, reward }) {
    $('lcLevel').textContent = level;
    $('lcKills').textContent = kills;
    $('lcReward').textContent = reward ? `+${reward.wood} 🪵 +${reward.gold} 💰` : '-';
    const next = level + 1;
    const extra = next === 3 ? ' Uwaga: pojawią się Biegacze!' : next === 5 ? ' Uwaga: nadchodzą Osiłki!' : '';
    $('lcNext').textContent = `Poziom ${next}: ${next * 10} zombie.${extra} Gra zapisze się automatycznie.`;
    this.show('level-modal');
  }

  showGameOver(d) {
    const s = d.stats;
    const t = Math.floor(s.time);
    $('overStats').innerHTML = [
      ['🏆 Poziom', d.level], ['💀 Zabici', d.kills], ['🌊 Fala', `${d.wave}/${d.maxWaves}`],
      ['⏱️ Czas', `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`], ['🏗️ Zbudowano', s.built], ['👑 Bossowie', s.bosses],
      ['🥇 Rekord', `poziom ${d.best}`],
    ].map(([a, b]) => `<div><span>${a}</span><b>${b}</b></div>`).join('');
    this.show('over-modal');
  }
}
