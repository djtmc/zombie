// Wieże: gniazdo karabinu maszynowego, moździerz, wieża Tesli i posterunek z żołnierzami.
// Każda ma 3 poziomy; budowa i rozbudowa odbywa się w rusztowaniu.
const TOWERS = {
  mg: {
    name: 'Gniazdo KM', ic: '🔫', cost: 70, up: [90, 150],
    desc: 'Szybki ogień w najbliższe fortecy zombie. Słaby na opancerzonych.',
    lv: [{ dmg: 7, rate: 6, range: 3.6 }, { dmg: 10, rate: 7.5, range: 3.9 }, { dmg: 14, rate: 9, range: 4.2 }],
    next: ['', 'Podwójna lufa: więcej obrażeń i zasięgu', 'Poczwórne działko: maksymalna siła ognia']
  },
  mortar: {
    name: 'Moździerz', ic: '💣', cost: 110, up: [130, 210],
    desc: 'Pociski obszarowe na duży dystans. Nie strzela blisko siebie.',
    lv: [{ dmg: 45, rate: 0.45, range: 6, splash: 1.2 }, { dmg: 70, rate: 0.5, range: 6.5, splash: 1.4 }, { dmg: 105, rate: 0.55, range: 7, splash: 1.6 }],
    next: ['', 'Cięższe pociski i większy wybuch', 'Podwójna lufa i najszerszy wybuch']
  },
  tesla: {
    name: 'Wieża Tesli', ic: '⚡', cost: 130, up: [150, 240],
    desc: 'Wyładowanie przeskakuje między zombie. Trafia też nieuchwytnych.',
    lv: [{ dmg: 24, rate: 0.8, range: 3.3, chain: 3 }, { dmg: 34, rate: 0.9, range: 3.6, chain: 4 }, { dmg: 48, rate: 1.0, range: 3.9, chain: 6 }],
    next: ['', 'Mocniejsza cewka: +1 przeskok', 'Wieża burzowa: 6 przeskoków']
  },
  post: {
    name: 'Posterunek', ic: '🪖', cost: 90, up: [100, 170],
    desc: 'Żołnierze stają na drodze, zatrzymują zombie i strzelają.',
    lv: [{ n: 2, hp: 90, dmg: 8, rate: 1.4, range: 2.4 }, { n: 3, hp: 130, dmg: 11, rate: 1.6, range: 2.6 }, { n: 3, hp: 200, dmg: 17, rate: 1.9, range: 2.8 }],
    next: ['', 'Trzeci żołnierz i lepsze karabiny', 'Weterani: więcej zdrowia i obrażeń']
  }
};
const TOWER_KEYS = ['mg', 'mortar', 'tesla', 'post'];
const T = { list: [], shells: [], ring: null, shellGeo: null };

function towerModel(type, lv) {
  const b = new Builder(), g = new Builder(), head = new Builder();
  let headY = 0.5, muzzle = [0, 0, 0.5];
  if (type === 'mg') {
    if (lv === 2) { for (const [x, z] of [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]]) b.box(0.07, 0.6, 0.07, 0x5a3e28, x, 0.1, z); b.box(0.8, 0.08, 0.8, 0x6a4a30, 0, 0.7, 0); headY = 0.78; }
    const sy = lv === 2 ? 0.78 : 0.1;
    for (let i = 0; i < 10; i++) { const a = i / 10 * TAU; b.box(0.22, 0.12, 0.14, shade(0x8a7a55, rr(0.85, 1.05)), Math.cos(a) * 0.32, sy, Math.sin(a) * 0.32, -a); }
    for (let i = 0; i < 8; i++) { const a = i / 8 * TAU + 0.3; b.box(0.22, 0.12, 0.14, shade(0x8a7a55, rr(0.85, 1.05)), Math.cos(a) * 0.32, sy + 0.12, Math.sin(a) * 0.32, -a); }
    if (lv < 2) headY = 0.28;
    head.box(0.18, 0.12, 0.26, 0x2e3236, 0, 0, -0.05);
    const nb = lv === 0 ? 1 : lv === 1 ? 2 : 4;
    for (let i = 0; i < nb; i++) { const ox = (i - (nb - 1) / 2) * 0.06; head.box(0.035, 0.035, 0.42, 0x15171a, ox, 0.05 + (i % 2) * 0.03 * (nb > 2), 0.2); }
    if (lv >= 1) head.box(0.3, 0.2, 0.03, 0x4a5058, 0, -0.04, 0.12);
    head.box(0.04, 0.22, 0.04, 0x2a2a2a, 0, -0.22, -0.02);
    muzzle = [0, 0.07, 0.42];
  } else if (type === 'mortar') {
    b.cyl(0.4, 0.44, 0.18, 0x7a756a, 0, 0.1, 0, 10);
    b.cyl(0.3, 0.3, 0.02, 0x3a3630, 0, 0.28, 0, 10);
    for (let i = 0; i < (lv + 1) * 2; i++) b.box(0.18, 0.18, 0.18, 0x5a4a2a, -0.32 + i * 0.1, 0.1, -0.42);
    headY = 0.32;
    const n = lv === 2 ? 2 : 1;
    for (let i = 0; i < n; i++) {
      const ox = n === 1 ? 0 : (i ? 0.1 : -0.1), r = 0.06 + lv * 0.015;
      head.add(new THREE.CylinderGeometry(r, r * 1.15, 0.45 + lv * 0.06, 8), 0x2e3a2a, ox, 0.18, 0.08, 0.8, 0, 0);
    }
    head.box(0.24, 0.05, 0.2, 0x3a3a3a, 0, -0.02, -0.04);
    muzzle = [0, 0.38, 0.25];
  } else if (type === 'tesla') {
    const h = 0.9 + lv * 0.3;
    b.box(0.5, 0.12, 0.5, 0x4a4e55, 0, 0.1, 0);
    for (const [x, z] of [[-0.16, -0.16], [0.16, -0.16], [-0.16, 0.16], [0.16, 0.16]]) b.add(new THREE.CylinderGeometry(0.025, 0.035, h, 4), 0x6a6e75, x * 0.75, 0.22 + h / 2, z * 0.75, x * 0.12, 0, -z * 0.12);
    for (let i = 0; i < 3 + lv; i++) b.add(new THREE.TorusGeometry(0.17 - i * 0.012, 0.03, 4, 10), 0xb87333, 0, 0.35 + i * (h - 0.25) / (3 + lv), 0, Math.PI / 2, 0, 0);
    g.ball(0.11 + lv * 0.02, 0x9fd8ff, 0, 0.3 + h, 0, 1);
    headY = 0.3 + h; muzzle = [0, 0, 0];
  } else {
    b.box(0.7, 0.32, 0.55, lv === 2 ? 0x707068 : 0x55603a, 0, 0.1, 0);
    b.box(0.76, 0.06, 0.61, lv === 2 ? 0x55554f : 0x404a2a, 0, 0.42, 0);
    b.box(0.3, 0.07, 0.03, 0x15140f, 0, 0.3, 0.28);
    b.box(0.03, 0.7, 0.03, 0x3a2a1a, 0.3, 0.42, -0.2);
    b.box(0.22, 0.14, 0.02, 0xb0302a, 0.42, 0.95, -0.2);
    for (let i = 0; i < 4 + lv * 2; i++) b.box(0.2, 0.1, 0.12, 0x8a7a55, -0.35 + (i % 4) * 0.2, 0.1 + Math.floor(i / 4) * 0.1, 0.38);
    headY = 0.5;
  }
  const grp = new THREE.Group();
  const body = b.mesh(); grp.add(body);
  if (g.pos.length) grp.add(g.mesh(MAT.glow, false));
  let hm = null;
  if (head.pos.length) { hm = new THREE.Group(); const m = head.mesh(); hm.add(m); hm.position.y = headY; grp.add(hm); }
  // rusztowanie widoczne podczas budowy
  const sc = new Builder();
  const H = Math.max(0.8, headY + 0.4);
  for (const [x, z] of [[-0.4, -0.4], [0.4, -0.4], [-0.4, 0.4], [0.4, 0.4]]) sc.box(0.04, H, 0.04, 0x9a7a4a, x, 0.1, z);
  for (let y = 0.35; y < H; y += 0.35) { sc.box(0.84, 0.03, 0.03, 0x9a7a4a, 0, y, -0.4); sc.box(0.84, 0.03, 0.03, 0x9a7a4a, 0, y, 0.4); sc.box(0.03, 0.03, 0.84, 0x9a7a4a, -0.4, y, 0); sc.box(0.03, 0.03, 0.84, 0x9a7a4a, 0.4, y, 0); }
  const scaffold = sc.mesh();
  grp.add(scaffold);
  const ice = new THREE.Mesh(new THREE.BoxGeometry(0.9, H + 0.2, 0.9), new THREE.MeshLambertMaterial({ color: 0xbfe8ff, transparent: true, opacity: 0.55 }));
  ice.position.y = (H + 0.2) / 2 + 0.05; ice.visible = false; grp.add(ice);
  return { grp, body, head: hm, muzzle, scaffold, ice, H };
}

function spawnTower(pad, type) {
  const tw = { type, lv: 0, pad, cd: rr(0, 0.5), frozen: 0, spent: TOWERS[type].cost, build: 0, soldiers: [], yaw: 0, kills: 0, shots: 0 };
  pad.tower = tw;
  setTowerModel(tw);
  if (type === 'post') initGuardPost(tw);
  T.list.push(tw);
  sfx('build'); puff(pad.x, 0.3, pad.z, 0x8a7a6a, 8, 0.2);
  return tw;
}
function setTowerModel(tw) {
  if (tw.m) { tw.m.grp.parent.remove(tw.m.grp); tw.m.grp.traverse(o => { if (o.geometry) o.geometry.dispose(); }); }
  tw.m = towerModel(tw.type, tw.lv);
  tw.m.grp.position.set(tw.pad.x, 0.12, tw.pad.z);
  if (tw.m.head) tw.m.head.rotation.y = tw.yaw;
  MAP.cols[tw.pad.cx].add(tw.m.grp);
  tw.build = 0;
  tw.buildTime = tw.lv ? 0.9 : 1.3;
}
function upgradeTower(tw) {
  if (tw.lv >= 2) return false;
  const c = TOWERS[tw.type].up[tw.lv];
  if (GAME.gold < c) return false;
  GAME.gold -= c; tw.spent += c; tw.lv++;
  setTowerModel(tw);
  if (tw.type === 'post') { for (const s of tw.soldiers) s.hp = s.max = TOWERS.post.lv[tw.lv].hp; syncSoldiers(tw); }
  sfx('build'); puff(tw.pad.x, 0.4, tw.pad.z, 0x8a7a6a, 10, 0.22);
  return true;
}
function sellTower(tw, refund = 0.7) {
  GAME.gold += Math.floor(tw.spent * refund);
  removeTower(tw);
  sfx('sell');
}
function removeTower(tw) {
  for (const s of tw.soldiers) removeSoldier(s);
  tw.soldiers = [];
  if (tw.m) { tw.m.grp.parent && tw.m.grp.parent.remove(tw.m.grp); }
  tw.pad.tower = null;
  T.list.splice(T.list.indexOf(tw), 1);
  if (UI.sel === tw) closeMenu();
}
function towerStats(tw) { return TOWERS[tw.type].lv[tw.lv]; }
function towerRange(type, lv) { return TOWERS[type].lv[lv].range; }

// ---- cele ----
function bestTarget(x, z, range, minR = 0, skipPhased = true) {
  let best = null, bs = -1;
  const r2 = range * range, m2 = minR * minR;
  for (const e of Z.list) {
    if (e.dead || (skipPhased && e.phased) || e.s < 0.3) continue;
    const d = dist2(e.x, e.z, x, z);
    if (d > r2 || d < m2) continue;
    const sc = e.s + (e.def.boss ? 0.5 : 0);
    if (sc > bs) { bs = sc; best = e; }
  }
  return best;
}

function updateTowers(dt) {
  for (const tw of T.list) {
    const m = tw.m;
    if (tw.build < 1) {
      tw.build = Math.min(1, tw.build + dt / tw.buildTime);
      const k = smooth(tw.build);
      m.body.scale.y = 0.05 + 0.95 * k;
      if (m.head) { m.head.visible = tw.build > 0.7; }
      m.grp.children.forEach(c => { if (c.material === MAT.glow) c.visible = tw.build > 0.9; });
      m.scaffold.visible = tw.build < 1;
      if (chance(dt * 8)) sparks(tw.pad.x + rr(-0.3, 0.3), rr(0.2, m.H), tw.pad.z + rr(-0.3, 0.3), 2, 0xffd27a);
      if (tw.build >= 1) sfx('built');
      continue;
    }
    if (tw.frozen > 0) { tw.frozen -= dt; m.ice.visible = tw.frozen > 0; continue; }
    const st = towerStats(tw);
    tw.cd -= dt;
    if (tw.type === 'post') { updatePost(tw, dt); continue; }
    const tgt = bestTarget(tw.pad.x, tw.pad.z, st.range, tw.type === 'mortar' ? 1.2 : 0, tw.type !== 'tesla');
    if (m.head && tgt) {
      const want = Math.atan2(tgt.x - tw.pad.x, tgt.z - tw.pad.z);
      let d = want - tw.yaw; while (d > Math.PI) d -= TAU; while (d < -Math.PI) d += TAU;
      tw.yaw += clamp(d, -8 * dt, 8 * dt); m.head.rotation.y = tw.yaw;
    }
    if (tw.type === 'tesla') m.grp.children[1] && (m.grp.children[1].scale.setScalar(1 + Math.sin(GAME.time * 9 + tw.pad.id) * 0.08));
    if (!tgt || tw.cd > 0) continue;
    tw.cd = 1 / st.rate;
    const hx = tw.pad.x, hz = tw.pad.z, hy = 0.12 + (m.head ? m.head.position.y : m.H);
    if (tw.type === 'mg') {
      const sx = hx + Math.sin(tw.yaw) * m.muzzle[2], sz = hz + Math.cos(tw.yaw) * m.muzzle[2], sy = hy + m.muzzle[1];
      tracer(sx, sy, sz, tgt.x + rr(-0.1, 0.1), 0.25 * tgt.sc, tgt.z + rr(-0.1, 0.1), 0xffd27a, 0.05);
      sparks(sx, sy, sz, 1, 0xffe08a);
      if ((tw.shots = (tw.shots || 0) + 1) % 3 === 0) flash(0xffc060, 3, 3, sx, sy + 0.1, sz, 0.06);
      hurt(tgt, st.dmg, 'bullet', tw);
      sfx('mg');
    } else if (tw.type === 'mortar') {
      const T0 = 1.1;
      const p = pathAt(Math.min(MAP.pathLen, tgt.s + tgt.speedNow * T0), { x: 0, z: 0 });
      const sx = hx + Math.sin(tw.yaw) * 0.25, sz = hz + Math.cos(tw.yaw) * 0.25;
      const shell = new THREE.Mesh(T.shellGeo, MAT.v);
      shell.castShadow = true;
      G.scene.add(shell);
      T.shells.push({ m: shell, x0: sx, z0: sz, y0: hy + 0.35, x1: p.x, z1: p.z, t: 0, T: T0, st, tw });
      puff(sx, hy + 0.4, sz, 0x9a9488, 4, 0.18);
      flash(0xffb060, 5, 3, sx, hy + 0.5, sz, 0.1);
      if (m.head) m.head.position.y -= 0.05;
      sfx('mortar');
    } else if (tw.type === 'tesla') {
      let cur = tgt, px = hx, py = hy, pz = hz, dmg = st.dmg;
      const hit = new Set();
      for (let i = 0; i < st.chain && cur; i++) {
        bolt(px, py, pz, cur.x, 0.28 * cur.sc, cur.z);
        hurt(cur, dmg, 'shock', tw);
        sparks(cur.x, 0.4, cur.z, 3, 0x9fd8ff);
        hit.add(cur);
        px = cur.x; py = 0.28 * cur.sc; pz = cur.z; dmg *= 0.82;
        let nb = null, nd = 1.9 * 1.9;
        for (const e of Z.list) { if (e.dead || hit.has(e)) continue; const d = dist2(e.x, e.z, px, pz); if (d < nd) { nd = d; nb = e; } }
        cur = nb;
      }
      flash(0x8fd0ff, 8, 4.5, hx, hy, hz, 0.15);
      sfx('zap');
    }
  }
  // pociski moździerza
  for (let i = T.shells.length - 1; i >= 0; i--) {
    const s = T.shells[i];
    s.t += dt;
    const k = s.t / s.T;
    const x = lerp(s.x0, s.x1, k), z = lerp(s.z0, s.z1, k), y = lerp(s.y0, 0.1, k) + Math.sin(k * Math.PI) * 3.2;
    s.m.position.set(x, y, z);
    if (chance(0.6)) puff(x, y, z, 0x6a6660, 1, 0.09);
    if (k >= 1) {
      G.scene.remove(s.m); T.shells.splice(i, 1);
      explosion(s.x1, s.z1, s.st.splash * 0.8);
      sfx('boom');
      shake(0.12);
      const r2 = s.st.splash * s.st.splash;
      for (const e of Z.list) {
        if (e.dead || e.phased) continue;
        const d = dist2(e.x, e.z, s.x1, s.z1);
        if (d < r2) hurt(e, s.st.dmg * (1 - 0.5 * Math.sqrt(d / r2)), 'blast', s.tw);
      }
    }
  }
  for (const tw of T.list) if (tw.m.head && tw.type === 'mortar') tw.m.head.position.y = lerp(tw.m.head.position.y, 0.32, 0.1);
}

// ---- posterunek i żołnierze ----
function initGuardPost(tw) {
  // punkt zbiórki: najbliższy punkt drogi
  let best = 0, bd = 1e9; const p = { x: 0, z: 0 };
  for (let s = 0; s < MAP.pathLen; s += 0.1) { pathAt(s, p); const d = dist2(p.x, p.z, tw.pad.x, tw.pad.z); if (d < bd) { bd = d; best = s; } }
  tw.rallyS = best;
  pathAt(best, p);
  tw.rally = { x: p.x, z: p.z, dx: p.dx, dz: p.dz };
  syncSoldiers(tw);
}
function syncSoldiers(tw) {
  const st = towerStats(tw);
  while (tw.soldiers.length < st.n) tw.soldiers.push(makeSoldier(tw, tw.soldiers.length));
}
function makeSoldier(tw, i) {
  const B = makeBody(getRig('soldier', SOLDIER_LOOK, 0));
  B.root.scale.setScalar(0.56);
  G.scene.add(B.root);
  const s = { tw, i, B, x: tw.pad.x, z: tw.pad.z, hp: towerStats(tw).hp, max: towerStats(tw).hp, cd: rr(0, 1), dead: false, respawn: 0, block: null, phase: rr(0, 6), yaw: 0 };
  B.root.position.set(s.x, 0.12, s.z);
  return s;
}
function removeSoldier(s) { G.scene.remove(s.B.root); if (s.block) { s.block.blockedBy = null; s.block = null; } }
function soldierSpot(tw, i) {
  const n = tw.soldiers.length, off = (i - (n - 1) / 2) * 0.32;
  return { x: tw.rally.x - tw.rally.dz * off - tw.rally.dx * 0.15, z: tw.rally.z + tw.rally.dx * off - tw.rally.dz * 0.15 };
}
function updatePost(tw, dt) {
  const st = towerStats(tw);
  for (const s of tw.soldiers) {
    if (s.dead) {
      s.respawn -= dt;
      if (s.respawn <= 0) { s.dead = false; s.hp = s.max = st.hp; s.x = tw.pad.x; s.z = tw.pad.z; s.B.root.visible = true; s.B.root.rotation.set(0, 0, 0); }
      else if (s.B.root.visible) { s.B.root.rotation.z = Math.min(1.5, s.B.root.rotation.z + dt * 5); s.B.root.position.y -= dt * 0.1; if (s.respawn < 6) s.B.root.visible = false; }
      continue;
    }
    // blokowanie: zatrzymaj zombie, które podejdzie blisko
    if (s.block && (s.block.dead || dist2(s.block.x, s.block.z, s.x, s.z) > 1.2)) { s.block.blockedBy = null; s.block = null; }
    if (!s.block) {
      for (const e of Z.list) {
        if (e.dead || e.blockedBy || e.def.noBlock || e.def.boss && tw.soldiers.some(o => o.block === e)) continue;
        if (dist2(e.x, e.z, s.x, s.z) < 0.36) { s.block = e; e.blockedBy = s; break; }
      }
    }
    const spot = s.block ? { x: s.block.x - s.block.dirx * 0.38, z: s.block.z - s.block.dirz * 0.38 } : soldierSpot(tw, s.i);
    const dx = spot.x - s.x, dz = spot.z - s.z, d = Math.hypot(dx, dz);
    const moving = d > 0.05;
    if (moving) { const v = Math.min(d, 1.4 * dt); s.x += dx / d * v; s.z += dz / d * v; }
    // ostrzał
    s.cd -= dt;
    let tgt = s.block;
    if (!tgt) {
      let bd = st.range * st.range;
      for (const e of Z.list) { if (e.dead || e.phased) continue; const dd = dist2(e.x, e.z, s.x, s.z); if (dd < bd) { bd = dd; tgt = e; } }
    }
    let yaw = moving ? Math.atan2(dx, dz) : s.yaw;
    if (tgt) yaw = Math.atan2(tgt.x - s.x, tgt.z - s.z);
    s.yaw = yaw;
    if (tgt && s.cd <= 0) {
      s.cd = 1 / st.rate * rr(0.85, 1.15);
      const mx = s.x + Math.sin(yaw) * 0.35, mz = s.z + Math.cos(yaw) * 0.35;
      tracer(mx, 0.38, mz, tgt.x, 0.25 * tgt.sc, tgt.z, 0xffe0a0, 0.05);
      hurt(tgt, st.dmg, 'bullet', tw);
      sfx('rifle');
    }
    s.phase += dt * (moving ? 9 : 2);
    s.B.root.position.set(s.x, 0.12, s.z);
    s.B.root.rotation.y = yaw;
    animBody(s.B, 'soldier', s.phase, moving);
  }
}
function hurtSoldier(s, dmg) {
  if (s.dead) return;
  s.hp -= dmg;
  blood(s.x, 0.45, s.z, 3, 0x7a1010);
  if (s.hp <= 0) {
    s.dead = true; s.respawn = 9;
    if (s.block) { s.block.blockedBy = null; s.block = null; }
    sfx('scream');
  }
}

function initTowers() {
  T.shellGeo = new Builder().ball(0.08, 0x2a2a2a, 0, 0, 0, 0).geometry();
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.96, 1, 48), new THREE.MeshBasicMaterial({ color: 0xffe08a, transparent: true, opacity: 0.6, depthWrite: false, toneMapped: false }));
  ring.rotation.x = -Math.PI / 2; ring.visible = false;
  const disc = new THREE.Mesh(new THREE.CircleGeometry(1, 48), new THREE.MeshBasicMaterial({ color: 0xffe08a, transparent: true, opacity: 0.08, depthWrite: false, toneMapped: false }));
  ring.add(disc); disc.position.z = -0.001;
  G.scene.add(ring);
  T.ring = ring;
  const hl = new THREE.Mesh(new THREE.BoxGeometry(0.92, 0.04, 0.92), new THREE.MeshBasicMaterial({ color: 0xffe08a, transparent: true, opacity: 0.35, depthWrite: false, toneMapped: false }));
  hl.visible = false; G.scene.add(hl); T.hl = hl;
}
function showRange(x, z, r) { T.ring.visible = true; T.ring.position.set(x, 0.16, z); T.ring.scale.setScalar(r); }
function hideRange() { T.ring.visible = false; }
function clearTowers(refund) {
  for (const tw of T.list.slice()) { if (refund) GAME.gold += Math.floor(tw.spent * refund); removeTower(tw); }
  for (const s of T.shells) G.scene.remove(s.m);
  T.shells = [];
}
