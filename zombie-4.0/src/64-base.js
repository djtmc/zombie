// Zaplecze z wersji 2: tartaki, kopalnie złota, koszary i fabryka na stałych miejscach,
// żołnierze i czołgi wychodzący na drogę, wymiana surowców i armaty na placu.
const BLD = {
  sawmill: { name: 'Tartak', ic: '🪚', cost: { w: 25, g: 30 }, slot: 'res', wood: 0.8, up: 'res', desc: 'Daje drewno: +0,8 🪵 na sekundę.' },
  mine: { name: 'Kopalnia złota', ic: '⛏️', cost: { w: 25, g: 40 }, slot: 'res', gold: 0.5, up: 'res', desc: 'Daje złoto: +0,5 💰 na sekundę.' },
  barracks: { name: 'Koszary', ic: '🏰', cost: { w: 150, g: 180 }, slot: 'barracks', unit: 'soldier', every: 30, up: 'barracks', desc: 'Co 30 s wysyła żołnierza na drogę. Żołnierze zatrzymują zombie i strzelają.' },
  factory: { name: 'Fabryka', ic: '⚙️', cost: { w: 320, g: 320 }, slot: 'factory', unit: 'tank', every: 60, up: 'factory', desc: 'Co 60 s produkuje czołg z działem obszarowym.' }
};
const BLD_UP = {
  res: [{ mult: 3, bonus: 0.25, d: '+25% produkcji' }, { mult: 6, bonus: 0.6, d: '+60% produkcji' }, { mult: 12, bonus: 1, d: '+100% produkcji' }],
  barracks: [{ c: { w: 100, g: 100 }, d: 'Produkcja żołnierzy ×2' }, { c: { w: 260, g: 260 }, d: 'Produkcja żołnierzy ×4' }, { c: { w: 550, g: 550 }, d: 'Produkcja żołnierzy ×8' }],
  factory: [{ c: { w: 250, g: 250 }, d: 'Produkcja czołgów ×2' }, { c: { w: 500, g: 500 }, d: 'Produkcja czołgów ×3' }, { c: { w: 900, g: 900 }, d: 'Produkcja czołgów ×4' }]
};
const PROD_MULT = { barracks: [1, 2, 4, 8], factory: [1, 2, 3, 4] };
const RES_BONUS = [0, 0.25, 0.6, 1];
const UNIT = {
  soldier: { hp: 100, dmg: 10, rate: 1.4, range: 2.7, speed: 1.1, cap: 10 },
  tank: { hp: 420, dmg: 40, rate: 0.5, range: 3.6, speed: 0.75, splash: 0.85, cap: 3 }
};
const EXCHANGE = { g2w: { g: 20, w: 10 }, w2g: { w: 10, g: 20 } };
const BASE = { list: [], units: [], accG: 0, accW: 0, caged: null, cageFx: [] };

function bldUpCost(b) {
  const t = BLD_UP[BLD[b.type].up][b.lv];
  if (!t) return null;
  if (t.c) return t.c;
  const c = BLD[b.type].cost;
  return { g: c.g * t.mult, w: c.w * t.mult };
}
function bldAt(slot) { return BASE.list.find(b => b.slot === slot) || null; }
function bldIncome(b) { const d = BLD[b.type], k = 1 + RES_BONUS[b.lv]; return { g: (d.gold || 0) * k, w: (d.wood || 0) * k }; }
function income() { let g = 0, w = 0; for (const b of BASE.list) if (b.build >= 1) { const i = bldIncome(b); g += i.g; w += i.w; } return { g, w }; }

// ---- modele budynków ----
function bldModel(type, lv, size) {
  const b = new Builder(), g = new Builder();
  const smoke = [];
  if (type === 'sawmill') {
    b.box(0.8, 0.5, 0.6, 0x7a5434, -0.1, 0.06, 0.1);
    b.box(0.92, 0.05, 0.42, 0x5a3a22, -0.1, 0.6, -0.08, 0, 0.55, 0);
    b.box(0.92, 0.05, 0.42, 0x4e321e, -0.1, 0.6, 0.28, 0, -0.55, 0);
    b.box(0.2, 0.32, 0.02, 0x2a1a10, -0.1, 0.06, -0.21);
    for (let i = 0; i < 3 + lv; i++) b.add(new THREE.CylinderGeometry(0.07, 0.07, 0.5, 6), shade(0x8a6038, rr(0.85, 1.1)), 0.42, 0.13 + Math.floor(i / 3) * 0.12, -0.3 + (i % 3) * 0.14, Math.PI / 2, 0, 0);
    b.add(new THREE.CylinderGeometry(0.16, 0.16, 0.02, 12), 0xb8bcc4, 0.35, 0.3, 0.38, Math.PI / 2, 0, 0);
    b.box(0.5, 0.12, 0.2, 0x6a4a2a, 0.3, 0.06, 0.38);
  } else if (type === 'mine') {
    for (let i = 0; i < 6; i++) b.ball(rr(0.18, 0.3), shade(0x6a665e, rr(0.8, 1.1)), rr(-0.35, 0.35), rr(0.1, 0.25), rr(0.05, 0.35), 0, 1, 0.7, 1);
    b.box(0.36, 0.36, 0.06, 0x120e0a, 0, 0.06, -0.12);
    b.box(0.06, 0.42, 0.06, 0x6a4a2a, -0.2, 0.06, -0.15); b.box(0.06, 0.42, 0.06, 0x6a4a2a, 0.2, 0.06, -0.15);
    b.box(0.5, 0.07, 0.08, 0x6a4a2a, 0, 0.46, -0.15);
    for (const sx of [-0.07, 0.07]) b.box(0.025, 0.02, 0.6, 0x5a5a5a, sx, 0.06, -0.45);
    b.box(0.22, 0.14, 0.26, 0x4a4a50, 0, 0.1, -0.5);
    for (let i = 0; i < 3 + lv; i++) g.ball(0.04, 0xffc83a, rr(-0.07, 0.07), 0.26, -0.5 + rr(-0.08, 0.08), 0);
  } else if (type === 'barracks') {
    b.box(1.9, 0.55, 1.1, 0x6a6a52, 0, 0.06, 0.15);
    b.box(2.0, 0.06, 0.66, 0x3e4a2a, 0, 0.58, -0.12, 0, 0.42, 0);
    b.box(2.0, 0.06, 0.66, 0x36422a, 0, 0.58, 0.42, 0, -0.42, 0);
    b.box(0.34, 0.38, 0.03, 0x2a1e14, 0, 0.06, -0.41);
    for (const sx of [-0.6, 0.6]) b.box(0.22, 0.16, 0.03, 0x9ab8c8, sx, 0.3, -0.41);
    b.box(0.04, 1.3, 0.04, 0x8a8a8a, 0.95, 0.06, -0.55);
    b.box(0.34, 0.2, 0.02, 0xb0302a, 1.13, 1.1, -0.55);
    for (let i = 0; i < 6; i++) b.box(0.26, 0.12, 0.15, 0x8a7a55, -0.9 + (i % 3) * 0.26, Math.floor(i / 3) * 0.12 + 0.06, -0.75);
    if (lv >= 1) b.box(0.9, 0.4, 0.8, 0x707058, -0.4, 0.64, 0.2);
    if (lv >= 2) { b.box(0.06, 0.9, 0.06, 0x5a3e28, -0.95, 0.06, -0.6); b.box(0.4, 0.06, 0.4, 0x6a4a30, -0.95, 0.96, -0.6); }
    if (lv >= 3) b.box(0.34, 0.2, 0.02, 0xf2c14e, 1.13, 0.86, -0.55);
  } else if (type === 'factory') {
    b.box(1.95, 0.7, 1.3, 0x7a4a3a, 0, 0.06, 0.1);
    for (let i = 0; i < 3; i++) b.box(0.62, 0.05, 1.32, 0x4a4a52, -0.65 + i * 0.65, 0.88, 0.1, 0, 0, 0.45);
    b.box(0.7, 0.5, 0.03, 0x3a3a40, 0.2, 0.06, -0.56);
    for (let i = 0; i < 5; i++) b.box(0.7, 0.015, 0.035, 0x5a5a62, 0.2, 0.12 + i * 0.09, -0.58);
    const nCh = 1 + Math.min(2, lv);
    for (let i = 0; i < nCh; i++) {
      const x = -0.75 + i * 0.32;
      b.cyl(0.08, 0.11, 1.3, 0x5a3a2a, x, 0.06, 0.45, 8);
      smoke.push([x, 1.4, 0.45]);
    }
    g.box(0.3, 0.12, 0.02, 0xffb050, -0.55, 0.38, -0.56);
    for (let i = 0; i < 4 + lv * 2; i++) b.box(0.18, 0.12, 0.18, 0x4a5a3a, 0.6 + (i % 2) * 0.2, Math.floor(i / 2) * 0.12 + 0.06, -0.8);
  }
  // gwiazdki poziomu nad wejściem
  for (let i = 0; i < lv; i++) g.ball(0.045, 0xffd27a, (i - (lv - 1) / 2) * 0.13, type === 'mine' ? 0.62 : type === 'sawmill' ? 0.84 : type === 'barracks' ? 1.12 : 1.36, -size * 0.25, 0);
  const grp = new THREE.Group();
  const body = b.mesh(); grp.add(body);
  if (g.pos.length) grp.add(g.mesh(MAT.glow, false));
  return { grp, body, smoke };
}

function setBldModel(bl) {
  const s = SLOTS[bl.slot];
  if (bl.m && bl.m.grp.parent) bl.m.grp.parent.remove(bl.m.grp);
  if (!MAP.root) return;
  bl.m = bldModel(bl.type, bl.lv, s.size);
  bl.m.grp.position.set(s.x, 0.08, s.z);
  if (s.kind === 'res') bl.m.grp.scale.setScalar(1.05);
  MAP.cols[Math.floor(s.cx)].add(bl.m.grp);
}
// Po zbudowaniu nowej planszy budynki wracają na swoje miejsca (zaplecze się nie zmienia).
function placeBuildingModels() { for (const bl of BASE.list) { bl.m = null; setBldModel(bl); } }

function buildBld(slot, type) {
  if (bldAt(slot.id) || !pay(BLD[type].cost)) return null;
  const bl = { slot: slot.id, type, lv: 0, t: 0, build: 0, spent: price(BLD[type].cost) };
  BASE.list.push(bl);
  setBldModel(bl);
  sfx('build'); puff(slot.x, 0.3, slot.z, 0x8a7a6a, 12, 0.3);
  return bl;
}
function upgradeBld(bl) {
  const c = bldUpCost(bl);
  if (!c || !pay(c)) return false;
  bl.spent.g += c.g || 0; bl.spent.w += c.w || 0;
  bl.lv++; bl.build = 0.3;
  setBldModel(bl);
  sfx('build'); puff(SLOTS[bl.slot].x, 0.4, SLOTS[bl.slot].z, 0x8a7a6a, 12, 0.3);
  return true;
}
function sellBld(bl) {
  GAME.gold += Math.floor(bl.spent.g * 0.5); GAME.wood += Math.floor(bl.spent.w * 0.5);
  if (bl.m && bl.m.grp.parent) bl.m.grp.parent.remove(bl.m.grp);
  BASE.list.splice(BASE.list.indexOf(bl), 1);
  sfx('sell');
}

// ---- armata na placu ----
function placeCannon(x, z) {
  const sp = placSpot(x, z);
  if (!sp || !sp.ok || !canPay(TOWERS.cannon.cost)) return null;
  pay(TOWERS.cannon.cost);
  const pad = { x: sp.x, z: sp.z, cx: clamp(Math.round(sp.x + MW / 2 - 0.5), 0, MW - 1), cz: Math.round(sp.z + MD / 2 - 0.5), id: 'c' + (BASE.cid = (BASE.cid || 0) + 1), free: true, tower: null };
  MAP.cpads.push(pad);
  return spawnTower(pad, 'cannon');
}

// ---- wymiana ----
function exchange(dir) {
  const e = EXCHANGE[dir];
  if (dir === 'g2w' && GAME.gold >= e.g) { GAME.gold -= e.g; GAME.wood += e.w; sfx('coin'); return true; }
  if (dir === 'w2g' && GAME.wood >= e.w) { GAME.wood -= e.w; GAME.gold += e.g; sfx('coin'); return true; }
  sfx('nope'); return false;
}

// ---- jednostki ----
function tankModel() {
  const b = new Builder(), t = new Builder();
  b.box(0.46, 0.14, 0.7, 0x4a5a32, 0, 0.08, 0);
  for (const sx of [-1, 1]) { b.box(0.12, 0.14, 0.76, 0x22221e, sx * 0.27, 0.02, 0); for (let i = 0; i < 4; i++) b.add(new THREE.CylinderGeometry(0.05, 0.05, 0.13, 8), 0x3a3a34, sx * 0.27, 0.08, -0.27 + i * 0.18, 0, 0, Math.PI / 2); }
  b.box(0.4, 0.05, 0.2, 0x3e4c2a, 0, 0.22, -0.26);
  t.box(0.32, 0.14, 0.34, 0x52623a, 0, 0, 0);
  t.add(new THREE.CylinderGeometry(0.035, 0.04, 0.5, 8), 0x2a2e26, 0, 0.07, 0.38, Math.PI / 2, 0, 0);
  t.box(0.08, 0.05, 0.08, 0x2a2e26, -0.08, 0.14, -0.06);
  const grp = new THREE.Group();
  grp.add(b.mesh());
  const tur = new THREE.Group(); tur.add(t.mesh()); tur.position.y = 0.22; grp.add(tur);
  return { grp, tur };
}

function spawnUnit(kind, bl) {
  const s = SLOTS[bl.slot], st = UNIT[kind];
  const u = {
    kind, tank: kind === 'tank', hp: st.hp, max: st.hp, dead: false, block: null, cd: rr(0, 1), phase: rr(0, 6), yaw: Math.PI,
    x: s.door.x + rr(-0.2, 0.2), z: s.door.z + 0.3, state: 'march', lat: rr(-0.28, 0.28), deadT: 0
  };
  // punkt wejścia na drogę: najbliższy punkt ścieżki od bramy w płocie
  let best = 0, bd = 1e9; const p = { x: 0, z: 0 };
  for (let ss = 0.5; ss < MAP.pathLen - 1.5; ss += 0.15) { pathAt(ss, p); const d = dist2(p.x, p.z, s.door.x, s.door.z - 1); if (d < bd) { bd = d; best = ss; } }
  u.us = best;
  // pozycja obrony: rozłożone wzdłuż drogi między środkiem planszy a placem
  const n = BASE.units.filter(o => o.kind === kind).length;
  u.hold = MAP.pathLen * clamp((u.tank ? 0.72 : 0.62) - (n % 7) * 0.045 + rr(-0.02, 0.02), 0.25, 0.85);
  if (u.tank) { const m = tankModel(); u.m = m; u.B = { root: m.grp, flash: 0 }; G.scene.add(m.grp); }
  else { u.B = makeBody(getRig('soldier', SOLDIER_LOOK, 0)); u.B.root.scale.setScalar(0.56); }
  u.B.root.position.set(u.x, 0.06, u.z);
  BASE.units.push(u);
  sfx('march');
  return u;
}
function removeUnit(u) {
  if (u.block) { u.block.blockedBy = null; u.block = null; }
  if (u.m) G.scene.remove(u.m.grp);
  BASE.units.splice(BASE.units.indexOf(u), 1);
}
function clearUnits() { for (const u of BASE.units.slice()) removeUnit(u); }
// wszyscy, których zombie mogą atakować: żołnierze posterunków i jednostki z zaplecza
function guards() {
  const a = [];
  for (const t of T.list) for (const s of t.soldiers) a.push(s);
  for (const u of BASE.units) a.push(u);
  return a;
}

function updateUnit(u, dt) {
  const st = UNIT[u.kind];
  if (u.B.flash > 0) u.B.flash = Math.max(0, u.B.flash - dt * 6);
  if (u.dead) {
    if (u.deadT === 0 && u.tank) { explosion(u.x, u.z, 0.9); shake(0.2); }
    u.deadT += dt;
    if (!u.tank) { u.B.root.rotation.z = Math.min(1.5, u.B.root.rotation.z + dt * 5); if (u.deadT > 1.5) u.B.root.position.y -= dt * 0.2; }
    else if (chance(dt * 6)) puff(u.x, 0.3, u.z, 0x2a2622, 1, 0.2);
    if (u.deadT > (u.tank ? 4 : 2.5)) removeUnit(u);
    return;
  }
  // blokowanie zombie (jak żołnierze posterunku)
  const br = u.tank ? 0.5 : 0.36;
  if (u.block && (u.block.dead || dist2(u.block.x, u.block.z, u.x, u.z) > 1.3)) { u.block.blockedBy = null; u.block = null; }
  if (!u.block && u.state !== 'march') {
    for (const e of Z.list) {
      if (e.dead || e.blockedBy || e.def.noBlock || e.exit) continue;
      if (dist2(e.x, e.z, u.x, u.z) < br * br) { u.block = e; e.blockedBy = u; break; }
    }
  }
  // cel
  let tgt = u.block;
  if (!tgt) {
    let bd = st.range * st.range;
    for (const e of Z.list) { if (e.dead || e.phased || e.s < 0.3) continue; const dd = dist2(e.x, e.z, u.x, u.z); if (dd < bd) { bd = dd; tgt = e; } }
  }
  // ruch: marsz z bramy do drogi, potem po drodze do pozycji obrony; stój, gdy jest cel
  let moving = false, tx = u.x, tz = u.z;
  if (u.state === 'march') {
    pathAt(u.us, _p);
    tx = _p.x - _p.dz * u.lat; tz = _p.z + _p.dx * u.lat;
    const dx = tx - u.x, dz = tz - u.z, d = Math.hypot(dx, dz);
    if (d < 0.08) u.state = 'road';
    else { const v = Math.min(d, st.speed * dt); u.x += dx / d * v; u.z += dz / d * v; moving = true; u.yaw = Math.atan2(dx, dz); }
  } else if (!tgt && !u.block) {
    const ds = u.hold - u.us;
    if (Math.abs(ds) > 0.05) { u.us += Math.sign(ds) * Math.min(Math.abs(ds), st.speed * dt); moving = true; }
    pathAt(u.us, _p);
    const nx = _p.x - _p.dz * u.lat, nz = _p.z + _p.dx * u.lat;
    if (moving) u.yaw = Math.atan2(nx - u.x, nz - u.z) || u.yaw;
    u.x = nx; u.z = nz;
  }
  if (tgt) u.yaw = Math.atan2(tgt.x - u.x, tgt.z - u.z);
  u.cd -= dt;
  if (tgt && u.cd <= 0) {
    u.cd = 1 / st.rate * rr(0.85, 1.15);
    const mx = u.x + Math.sin(u.yaw) * (u.tank ? 0.5 : 0.35), mz = u.z + Math.cos(u.yaw) * (u.tank ? 0.5 : 0.35);
    if (u.tank) {
      tracer(mx, 0.3, mz, tgt.x, 0.2, tgt.z, 0xffb060, 0.08);
      explosion(tgt.x, tgt.z, st.splash * 0.7);
      flash(0xffb060, 5, 3, mx, 0.4, mz, 0.08);
      puff(mx, 0.3, mz, 0xa09888, 3, 0.15);
      const r2 = st.splash * st.splash;
      for (const e of Z.list) if (!e.dead && !e.phased && dist2(e.x, e.z, tgt.x, tgt.z) < r2) hurt(e, st.dmg, 'blast', null);
      sfx('cannon');
    } else {
      tracer(mx, 0.38, mz, tgt.x, 0.25 * tgt.sc, tgt.z, 0xffe0a0, 0.05);
      hurt(tgt, st.dmg, 'bullet', null);
      sfx('rifle');
    }
  }
  u.B.root.position.set(u.x, u.tank ? 0.02 : 0.08, u.z);
  if (u.tank) {
    const body = Math.atan2(_p.dx, _p.dz);
    if (moving) u.B.root.rotation.y = lerpAng(u.B.root.rotation.y, u.state === 'march' ? u.yaw : (u.hold < u.us ? body + Math.PI : body), dt * 4);
    u.m.tur.rotation.y = lerpAng(u.m.tur.rotation.y, u.yaw - u.B.root.rotation.y, dt * 6);
  } else {
    u.phase += dt * (moving ? 9 : 2);
    u.B.root.rotation.y = u.yaw;
    animBody(u.B, 'soldier', u.phase, moving);
  }
}
function lerpAng(a, b, k) { let d = b - a; while (d > Math.PI) d -= TAU; while (d < -Math.PI) d += TAU; return a + d * Math.min(1, k); }

// ---- klatka bossa ----
function cageBoss() {
  const c = MAP.cage, key = MAP.biome.boss;
  const B = makeBody(getRig(key, ZT[key].look, MAP.biome.zombieTint));
  B.root.scale.multiplyScalar(0.8);
  B.root.position.set(c.x, 0.16, c.z);
  B.root.rotation.y = c.faceYaw;
  BASE.caged = { B, key, phase: 0, roar: rr(4, 9), rattle: 0 };
}
function breakCage() {
  const c = MAP.cage;
  if (!c || c.broken) return null;
  c.broken = true;
  // krata od strony drogi unosi się do góry jak brona, boss wychodzi przez otwór
  c.lift = { sd: c.sides[c.front], t: 0 };
  c.sides[c.front].children[0].rotation.set(0, 0, 0);
  banner('BOSS SIĘ UWOLNIŁ!', 'Krata klatki się podnosi · ' + ZT[MAP.biome.boss].name + ' wychodzi na drogę');
  puff(c.x, 0.5, c.z, 0x6a5a4a, 10, 0.3);
  shake(0.4); sfx('cage'); sfx('roar');
  const key = BASE.caged ? BASE.caged.key : MAP.biome.boss;
  BASE.caged = null;
  const e = spawnZombie(key, 0);
  // boss czeka, aż krata się uniesie, przechodzi przez otwór i idzie na najbliższy punkt drogi
  const a = c.faceYaw;
  e.x = c.x; e.z = c.z; e.s = c.exitS;
  e.exit = { s: c.exitS, wait: 1.3, gate: { x: c.x + Math.sin(a) * (c.W + 0.6), z: c.z + Math.cos(a) * (c.W + 0.6) } };
  e.B.root.position.set(e.x, 0.16, e.z);
  e.B.root.rotation.y = a;
  return e;
}
// Po każdej fali boss nadweręża klatkę: kolejna ściana krat wygina się na zewnątrz.
function damageCage(stage) {
  const c = MAP.cage;
  if (!c || c.broken || !BASE.caged) return;
  const sd = c.sides[(c.front + stage) % 4]; // krata wyjściowa zostaje prosta
  sd.children[0].rotation.x = 0.12 + stage * 0.05;
  sd.children[0].rotation.z = (stage % 2 ? 1 : -1) * 0.08;
  sparks(sd.position.x + c.x, 1.2, sd.position.z + c.z, 10, 0xffd27a);
  puff(c.x, 0.4, c.z, 0x6a5a4a, 6, 0.25);
  BASE.caged.rattle = 1.2;
  sfx('cage'); sfx('roar'); shake(0.25);
}
function updateCage(dt) {
  const cb = BASE.caged;
  if (cb && MAP.cage && !MAP.cage.broken) {
    cb.phase += dt * 1.5;
    cb.roar -= dt;
    if (cb.roar <= 0) {
      cb.roar = rr(7, 13); cb.rattle = 0.8;
      if (GAME.state !== 'wave' || GAME.inBiome >= 4) sfx('roar');
    }
    if (cb.rattle > 0) {
      cb.rattle -= dt;
      for (const sd of MAP.cage.sides) if (!sd.userData.roof) sd.children[0].position.x = Math.sin(GAME.time * 60) * 0.03 * cb.rattle;
      cb.B.armL.rotation.x = -2.2; cb.B.armR.rotation.x = -2.2;
      cb.B.root.rotation.y = MAP.cage.faceYaw + Math.sin(GAME.time * 20) * 0.08;
    } else {
      cb.B.root.rotation.y = MAP.cage.faceYaw + Math.sin(cb.phase * 0.3) * 0.5;
      animBody(cb.B, 'shamble', cb.phase, true, 0.2);
    }
  }
  const L = MAP.cage && MAP.cage.lift;
  if (L && L.t < 2.2) {
    L.t += dt;
    const k = smooth(clamp((L.t - 0.2) / 1.6, 0, 1));
    L.sd.position.y = 0.16 + k * (MAP.cage.H + 0.3);
    L.sd.children[0].position.x = k < 1 ? Math.sin(GAME.time * 45) * 0.015 : 0;
    if (k > 0 && k < 1 && chance(dt * 12)) sparks(L.sd.position.x + MAP.cage.x, MAP.cage.H + 0.5, L.sd.position.z + MAP.cage.z, 2, 0xffd27a);
  }
  for (let i = BASE.cageFx.length - 1; i >= 0; i--) {
    const sd = BASE.cageFx[i], v = sd.userData.v;
    v.y -= 9.8 * dt;
    sd.position.x += v.x * dt; sd.position.y += v.y * dt; sd.position.z += v.z * dt;
    sd.rotation.x += v.r * dt;
    if (sd.position.y < -6) { sd.visible = false; BASE.cageFx.splice(i, 1); }
  }
}

// ---- pętla zaplecza ----
function updateBase(dt) {
  const live = GAME.state === 'wave' || GAME.state === 'prep';
  for (const bl of BASE.list) {
    const m = bl.m;
    if (bl.build < 1) {
      bl.build = Math.min(1, bl.build + dt / 1.4);
      if (m) m.body.scale.y = 0.05 + 0.95 * smooth(bl.build);
      const s = SLOTS[bl.slot];
      if (chance(dt * 10)) sparks(s.x + rr(-0.4, 0.4), rr(0.2, 0.7), s.z + rr(-0.4, 0.4), 2, 0xffd27a);
      if (bl.build >= 1) sfx('built');
      continue;
    }
    if (!live) continue;
    const d = BLD[bl.type];
    if (d.gold || d.wood) {
      const inc = bldIncome(bl);
      BASE.accG += inc.g * dt; BASE.accW += inc.w * dt;
      if (bl.type === 'mine' && chance(dt * 0.6)) sparks(SLOTS[bl.slot].x, 0.35, SLOTS[bl.slot].z - 0.45, 2, 0xffd040);
      if (bl.type === 'sawmill' && chance(dt * 0.5)) puff(SLOTS[bl.slot].x + 0.35, 0.35, SLOTS[bl.slot].z + 0.38, 0xc8a878, 2, 0.08);
    }
    if (d.unit) {
      bl.t += dt;
      if (bl.t >= d.every) {
        bl.t = 0;
        let n = PROD_MULT[bl.type][bl.lv];
        const have = BASE.units.filter(u => u.kind === d.unit && !u.dead).length;
        n = Math.min(n, UNIT[d.unit].cap - have);
        for (let i = 0; i < n; i++) { const u = spawnUnit(d.unit, bl); u.z += i * 0.35; u.x += (i % 2 ? 0.3 : -0.3) * (i > 0); }
      }
      if (m && m.smoke.length && chance(dt * 3)) {
        const sp = pick(m.smoke), s = SLOTS[bl.slot];
        puff(s.x + sp[0], sp[1] + 0.1, s.z + sp[2], 0x5a5450, 1, 0.16);
      }
    }
  }
  if (BASE.accG >= 1) { const k = Math.floor(BASE.accG); GAME.gold += k; BASE.accG -= k; }
  if (BASE.accW >= 1) { const k = Math.floor(BASE.accW); GAME.wood += k; BASE.accW -= k; }
  for (let i = BASE.units.length - 1; i >= 0; i--) updateUnit(BASE.units[i], dt);
  updateCage(dt);
}
