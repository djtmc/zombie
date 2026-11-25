// Przebieg gry: fale, bossowie co 5. falę, zmiana biomu (rozpad planszy), forteca, koniec gry.
const GAME = {
  gold: 0, wood: 0, fortHp: 100, fortMax: 100, kills: 0, wave: 0, inBiome: 0, state: 'none', timer: 0,
  queue: [], spawnT: 0, time: 0, speed: 1, paused: false, ai: true, boss: null, best: 0, overT: 0,
  fortHit: null
};

function waveHpMul(w) { return 1 + 0.36 * (w - 1) + 0.032 * (w - 1) * (w - 1); }

function composeWave(w) {
  const q = [];
  const unlocked = UNLOCK.filter(u => u[1] <= w).map(u => u[0]);
  const newest = UNLOCK.filter(u => u[1] === w).map(u => u[0]);
  let budget = 12 + w * 7.5;
  const gap = Math.max(0.28, 1.0 - w * 0.03);
  const push = (key) => {
    const def = ZT[key];
    if (def.pack) for (let i = 0; i < def.pack; i++) q.push({ key, delay: i === 0 ? gap : 0.25 });
    else q.push({ key, delay: gap * (def.cost > 3 ? 1.8 : 1) * rr(0.7, 1.3) });
    budget -= def.cost * (def.pack || 1);
  };
  for (const k of newest) for (let i = 0; i < 3; i++) push(k);
  while (budget > 0) {
    // nowsze rodzaje pojawiają się częściej, zwykłe zombie zawsze stanowią trzon fali
    const weights = unlocked.map((k, i) => k === 'walker' ? 3 : 1 + i * 0.15);
    let r = rnd() * weights.reduce((a, b) => a + b, 0), k = unlocked[0];
    for (let i = 0; i < unlocked.length; i++) { r -= weights[i]; if (r <= 0) { k = unlocked[i]; break; } }
    push(k);
  }
  return q;
}

function composeBossWave(w) {
  const boss = MAP.biome.boss;
  const q = [];
  const esc = Math.min(12, 4 + Math.floor(w / 2));
  for (let i = 0; i < esc; i++) q.push({ key: pick(['walker', 'walker', 'runner']), delay: 0.6 });
  q.push({ key: '__cage', delay: 2.5 });
  for (let i = 0; i < esc; i++) q.push({ key: pick(UNLOCK.filter(u => u[1] <= w).map(u => u[0])), delay: 0.9 });
  return q;
}

function startGame() {
  GAME.crumbleT = 0; clearZombies(); clearTowers(false); clearUnits(); FX.parts.length = 0; FX.gparts.length = 0;
  for (const bl of BASE.list) if (bl.m && bl.m.grp.parent) bl.m.grp.parent.remove(bl.m.grp);
  BASE.list = []; BASE.accG = BASE.accW = 0; BASE.caged = null;
  GAME.gold = 240; GAME.wood = 100; GAME.fortHp = GAME.fortMax = 100; GAME.kills = 0; GAME.wave = 0; GAME.inBiome = 0;
  GAME.boss = null; GAME.best = store.get('best', 0);
  Z.seen = new Set();
  $('over').style.display = 'none';
  if (MAP.root) { releaseLights('map'); releaseLights('fort'); disposeMap(); }
  const qb = parseInt(new URLSearchParams(location.search).get('b'), 10);
  newBiome(Number.isFinite(qb) ? qb : Math.floor(rnd() * BIOMES.length));
}

function newBiome(index) {
  GAME.state = 'transition';
  buildMap(index);
  setWeather(MAP.biome.weather);
  banner(MAP.biome.name, MAP.biome.sub);
  sfx('rumble');
  CAM.fit = true;
  MAP.onBuilt = () => {
    cageBoss();
    GAME.state = 'prep';
    GAME.timer = GAME.wave === 0 ? 22 : 18;
  };
}

function callWave() {
  if (GAME.state !== 'prep') return false;
  const bonus = Math.floor(GAME.timer * 2);
  if (bonus > 0) { GAME.gold += bonus; floatGold(bonus); }
  startWave();
  return true;
}

function startWave() {
  GAME.wave++;
  GAME.inBiome++;
  Z.hpMul = waveHpMul(GAME.wave);
  Z.goldMul = 1 / (1 + 0.035 * (GAME.wave - 1));
  const boss = GAME.inBiome === 5;
  GAME.queue = boss ? composeBossWave(GAME.wave) : composeWave(GAME.wave);
  GAME.spawnT = 0.5;
  GAME.state = 'wave';
  if (boss) banner('FALA ' + GAME.wave + ' · BOSS', ZT[MAP.biome.boss].name);
  else banner('FALA ' + GAME.wave, MAP.biome.name);
  sfx(boss ? 'horn2' : 'horn');
}

function endWave() {
  const bonus = 20 + GAME.wave * 3;
  GAME.gold += bonus; floatGold(bonus);
  GAME.wood += 10 + GAME.wave * 2;
  if (GAME.wave > GAME.best) { GAME.best = GAME.wave; store.set('best', GAME.best); }
  if (GAME.inBiome >= 5) {
    // boss pokonany: plansza się rozpada, wieże wracają do skarbca, nowa kraina
    GAME.state = 'transition';
    banner('Kraina oczyszczona', 'Plansza się rozpada · 80% wartości wież i armat wraca · zaplecze zostaje');
    GAME.fortHp = Math.min(GAME.fortMax, GAME.fortHp + 30);
    GAME.crumbleT = 2.5;
  } else {
    GAME.state = 'prep';
    GAME.timer = 15;
  }
}

GAME.fortHit = function (dmg, e) {
  if (GAME.state === 'over') return;
  GAME.fortHp = Math.max(0, GAME.fortHp - dmg);
  explosion(MAP.fort.x - 1.6, MAP.fort.z, 0.6, 0xff5a3a);
  shake(0.25); sfx('hit');
  if (GAME.fortHp <= 0) gameOver();
};

function gameOver() {
  GAME.state = 'over'; GAME.overT = 0;
  if (GAME.wave > GAME.best) { GAME.best = GAME.wave; store.set('best', GAME.best); }
  for (let i = 0; i < 6; i++) setTimeout(() => explosion(MAP.fort.x + rr(-1.5, 1.5), MAP.fort.z + rr(-2, 2), 1.2), i * 220);
  shake(0.8); sfx('bossdie');
  $('overText').innerHTML = 'Dotarłeś do fali <b>' + GAME.wave + '</b> · zabitych zombie: <b>' + GAME.kills + '</b><br>Najlepszy wynik: fala <b>' + GAME.best + '</b>' + (GAME.ai ? '<br><small>Tytan zacznie od nowa za chwilę</small>' : '');
  setTimeout(() => { if (GAME.state === 'over') $('over').style.display = 'flex'; }, 1400);
}

function updateGame(dt) {
  GAME.time += dt;
  if (GAME.state === 'prep') {
    GAME.timer -= dt;
    if (GAME.timer <= 0) startWave();
  } else if (GAME.state === 'wave') {
    if (GAME.queue.length) {
      GAME.spawnT -= dt;
      while (GAME.queue.length && GAME.spawnT <= 0) {
        const it = GAME.queue.shift();
        if (it.key === '__cage') breakCage(); else spawnZombie(it.key, rr(0, 0.3));
        GAME.spawnT += GAME.queue.length ? GAME.queue[0].delay : 0;
      }
    } else if (!Z.list.some(e => !e.dead)) endWave();
  } else if (GAME.state === 'transition' && GAME.crumbleT > 0) {
    GAME.crumbleT -= dt;
    if (GAME.crumbleT <= 0) {
      clearTowers(0.8); clearZombies(); clearUnits(); closeMenu();
      sfx('rumble'); shake(0.6);
      crumbleMap();
      MAP.onFallen = () => { GAME.inBiome = 0; newBiome(MAP.biomeIndex + 1); };
    }
  } else if (GAME.state === 'over') {
    GAME.overT += dt;
    if (GAME.ai && GAME.overT > 7) startGame();
  }
}
