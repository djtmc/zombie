// AI dowódca: gra sama od wejścia na stronę. Buduje, rozbudowuje i wzywa fale.
const AI = { t: 0, plan: 0 };

// Ile punktów drogi wieża danego typu obejmie z danego pola (próbkowanie co 0.3).
const COV = new Map();
function coverage(pad, type, lv = 0) {
  const ck = MAP.biomeIndex + ':' + pad.id + type + lv;
  if (COV.has(ck)) return COV.get(ck);
  const v = coverageRaw(pad, type, lv);
  COV.set(ck, v);
  return v;
}
function coverageRaw(pad, type, lv) {
  const r = towerRange(type, lv), p = { x: 0, z: 0 };
  let n = 0;
  for (let s = 1; s < MAP.pathLen - 1.5; s += 0.3) {
    pathAt(s, p);
    const d = dist2(p.x, p.z, pad.x, pad.z);
    if (d <= r * r && (type !== 'mortar' || d > 1.44)) n += type === 'post' ? (s < MAP.pathLen * 0.8 ? 1 : 0.5) : 1;
  }
  if (type === 'post') { pathAt(0, p); let md = 9; for (let s = 0; s < MAP.pathLen; s += 0.2) { pathAt(s, p); md = Math.min(md, dist2(p.x, p.z, pad.x, pad.z)); } if (md > 1.1) return 0; }
  return n;
}

function aiWanted() {
  const w = Math.max(1, GAME.wave + 1);
  const want = { mg: 3, post: w >= 2 ? 2 : 0, mortar: w >= 3 ? 2 : 0, tesla: w >= 4 ? 2 : 0 };
  if (w >= 8) { want.mg = 4; want.tesla = 3; want.mortar = 3; }
  return want;
}

// Zaplecze: najpierw kopalnie i tartaki, potem armaty na placu, koszary, fabryka i unowocześnienia.
function aiCannonSpot() {
  const p = MAP.plac, q = { x: 0, z: 0 }, r = towerRange('cannon', 0);
  let best = null, bs = 0;
  for (let x = p.x0 + 0.5; x <= p.x1 - 0.5; x += 0.5) for (let z = p.z0 + 0.5; z <= p.z1 - 0.5; z += 0.5) {
    const sp = placSpot(x, z);
    if (!sp || !sp.ok) continue;
    let n = 0;
    for (let s = 1; s < MAP.pathLen - 1.5; s += 0.4) { pathAt(s, q); if (dist2(q.x, q.z, sp.x, sp.z) <= r * r) n++; }
    n -= Math.abs(z - MAP.fort.z) * 0.05;
    if (n > bs) { bs = n; best = sp; }
  }
  return best;
}
function aiEconomy() {
  const w = GAME.wave + 1;
  const res = BASE.list.filter(b => BLD[b.type].slot === 'res');
  const mines = res.filter(b => b.type === 'mine').length, saws = res.length - mines;
  const freeRes = SLOTS.filter(s => s.kind === 'res' && !bldAt(s.id));
  const wantRes = Math.min(8, 2 + Math.floor(w * 0.8));
  if (res.length < wantRes && freeRes.length) {
    const type = saws < mines ? 'sawmill' : 'mine';
    if (canPay(BLD[type].cost)) { buildBld(freeRes[0], type); return true; }
    if (res.length < 2) return false;
  }
  const cannons = T.list.filter(t => t.type === 'cannon').length;
  if (w >= 2 && cannons < Math.min(6, 1 + Math.floor(w / 2)) && canPay(TOWERS.cannon.cost) && GAME.gold >= 90) {
    const sp = aiCannonSpot();
    if (sp && placeCannon(sp.x, sp.z)) return true;
  }
  for (const [kind, type, minW] of [['barracks', 'barracks', 3], ['factory', 'factory', 7]]) {
    const s = SLOTS.find(q => q.kind === kind);
    if (w >= minW && !bldAt(s.id)) { if (canPay(BLD[type].cost)) { buildBld(s, type); return true; } if (GAME.wood >= BLD[type].cost.w * 0.6) return false; }
  }
  // unowocześnienia budynków, gdy w skarbcu jest zapas
  let best = null, bc = 1e9;
  for (const bl of BASE.list) { const c = bldUpCost(bl); if (c && bl.build >= 1 && c.g + c.w < bc) { bc = c.g + c.w; best = bl; } }
  if (best && GAME.gold >= bldUpCost(best).g + 120 && GAME.wood >= bldUpCost(best).w) { upgradeBld(best); return true; }
  // armaty: unowocześnij najtańszą
  for (const t of T.list) if (t.type === 'cannon' && t.build >= 1 && t.lv < maxLv(t)) { const c = price(TOWERS.cannon.up[t.lv]); if (GAME.wood >= c.w && GAME.gold >= c.g + 120) { upgradeTower(t); return true; } }
  // wymiana nadmiaru surowców
  if (GAME.wood > 350 && GAME.gold < 120) { exchange('w2g'); return true; }
  if (GAME.gold > 600 && GAME.wood < 60) { exchange('g2w'); return true; }
  return false;
}

function aiStep() {
  if (MAP.state !== 'live' || GAME.state === 'over' || GAME.state === 'transition') return;
  if (aiEconomy()) return;
  const free = MAP.pads.filter(p => !p.tower);
  const count = { mg: 0, post: 0, mortar: 0, tesla: 0 };
  for (const t of T.list) if (t.type in count) count[t.type]++;
  const want = aiWanted();
  // najbardziej brakujący typ
  let type = null, worst = 1e9;
  for (const k of TOWER_KEYS) { if (!want[k]) continue; const r = count[k] / want[k]; if (r < worst) { worst = r; type = k; } }
  const enough = T.list.filter(t => !t.pad.free).length >= Math.min(MAP.pads.length, 4 + GAME.wave);
  if (type && worst < 1 && free.length && !enough) {
    if (!canPay(TOWERS[type].cost)) return;
    let best = null, bs = 0;
    for (const p of free) { const c = coverage(p, type); if (c > bs) { bs = c; best = p; } }
    if (best) { pay(TOWERS[type].cost); spawnTower(best, type); return; }
  }
  // rozbudowa: wieża o największym zasięgu działania i najniższym poziomie
  let up = null, us = -1;
  for (const t of T.list) {
    if (t.pad.free || t.lv >= maxLv(t) || t.build < 1) continue;
    const sc = coverage(t.pad, t.type, t.lv) / (t.lv + 1);
    if (sc > us) { us = sc; up = t; }
  }
  if (up && canPay(TOWERS[up.type].up[up.lv])) { upgradeTower(up); return; }
  // gdy jest złoto, a wszystko rozbudowane - nowa wieża typu o najlepszym pokryciu
  if (free.length && GAME.gold >= 130) {
    let bt = null, lw = 1e9;
    for (const k of TOWER_KEYS) { const r = count[k] / Math.max(1, want[k]); if (r < lw) { lw = r; bt = k; } }
    let best = null, bs = 0;
    for (const p of free) { const c = coverage(p, bt); if (c > bs) { bs = c; best = p; } }
    if (best && pay(TOWERS[bt].cost)) spawnTower(best, bt);
  }
}

function updateAI(dt) {
  if (!GAME.ai) return;
  AI.t -= dt;
  if (AI.t > 0) return;
  AI.t = 0.8;
  aiStep();
  // wezwij falę wcześniej, gdy nie ma już na co wydać złota
  if (GAME.state === 'prep' && GAME.wave > 0 && GAME.timer > 3 && GAME.timer < 13 && GAME.gold < 70 && GAME.wood < 120) callWave();
}
