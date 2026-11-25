// Zombie: ruch po drodze, zdolności specjalne, obrażenia, śmierć i bossowie.
const Z = { list: [], spits: [], hpMul: 1, goldMul: 1, seen: new Set() };
const _p = { x: 0, z: 0, dx: 1, dz: 0 };

function spawnZombie(key, s = 0, opts = {}) {
  const def = ZT[key];
  const B = makeBody(getRig(key, def.look, MAP.biome ? MAP.biome.zombieTint : 0));
  const hpMul = def.boss ? Z.hpMul * 1.0 : Z.hpMul;
  const e = {
    key, def, B, s, hp: def.hp * hpMul, max: def.hp * hpMul, dead: false, deathT: 0,
    x: 0, z: 0, dirx: 1, dirz: 0, phase: rr(0, 6), sc: (def.look.size || 1), blockedBy: null,
    speedVar: rr(0.9, 1.1), speedNow: def.speed, cd: rr(0, 1), abil: rr(1, 3), lastHit: 0, phaseT: rr(0, 4), phased: false,
    lat: rr(-0.25, 0.25) * (def.boss ? 0.3 : 1), rise: opts.rise ? 1 : 0, summoned: 0
  };
  pathAt(s, _p); e.x = _p.x; e.z = _p.z;
  B.root.position.set(e.x, opts.rise ? -0.6 : 0, e.z);
  Z.list.push(e);
  if (!Z.seen.has(key) && def.intro) { Z.seen.add(key); showNote(def.name, def.intro); }
  if (def.boss) { GAME.boss = e; showBoss(def.name); sfx('roar'); }
  return e;
}

function setGhost(e, on) {
  e.phased = on;
  e.B.ghost = on;
}

function hurt(e, dmg, kind, src) {
  if (e.dead) return;
  if (e.phased && kind !== 'shock') return;
  if (e.def.armor && (kind === 'bullet')) dmg *= 1 - e.def.armor;
  e.hp -= dmg; e.lastHit = GAME.time; e.B.flash = 1;
  if (kind === 'bullet' && chance(0.4)) blood(e.x, 0.25 * e.sc, e.z, 2, 0x5a1a10);
  if (e.def.armor && kind === 'bullet' && chance(0.3)) sparks(e.x, 0.4, e.z, 1, 0xffffff);
  if (e.def.summon && !e.summoned && e.hp < e.max * 0.66 || e.def.summon && e.summoned === 1 && e.hp < e.max * 0.33) {
    e.summoned++;
    for (let i = 0; i < 6; i++) spawnZombie('runner', Math.max(0, e.s - rr(0.3, 1.5)));
    sfx('roar'); puff(e.x, 0.5, e.z, 0x6a0d0a, 10, 0.3);
  }
  if (e.hp <= 0) kill(e, kind, src);
}

function kill(e, kind, src) {
  e.dead = true; e.deathT = 0;
  if (e.blockedBy) { e.blockedBy.block = null; e.blockedBy = null; }
  if (e.phased) setGhost(e, false);
  GAME.gold += Math.round(e.def.gold * Z.goldMul);
  GAME.kills++;
  if (src) src.kills = (src.kills || 0) + 1;
  const skin = e.def.look.skin;
  if (kind === 'blast' || e.def.explode) gibs(e.x, e.z, skin, 12); else blood(e.x, 0.3 * e.sc, e.z, 8, 0x5a0d0a);
  sfx(e.def.boss ? 'bossdie' : 'die');
  if (e.def.explode) {
    explosion(e.x, e.z, 1.1, 0x9aff4a);
    sfx('boom');
    const r2 = e.def.explode * e.def.explode;
    for (const t of T.list) for (const s of t.soldiers) if (!s.dead && dist2(s.x, s.z, e.x, e.z) < r2) hurtSoldier(s, 45);
    for (const o of Z.list) if (o !== e && !o.dead && dist2(o.x, o.z, e.x, e.z) < r2) hurt(o, 25, 'blast', null);
  }
  if (e.def.split) for (let i = 0; i < e.def.split; i++) spawnZombie('mini', Math.max(0, e.s + rr(-0.4, 0.2)));
  if (e.key === 'queen') for (let i = 0; i < 10; i++) spawnZombie('mini', Math.max(0, e.s + rr(-1.2, 0.3)));
  if (e.def.boss) { GAME.boss = null; hideBoss(); shake(0.5); explosion(e.x, e.z, 1.6, 0xff6a3a); }
}

function nearestSoldier(x, z, r) {
  let best = null, bd = r * r;
  for (const t of T.list) for (const s of t.soldiers) { if (s.dead) continue; const d = dist2(s.x, s.z, x, z); if (d < bd) { bd = d; best = s; } }
  return best;
}

function updateZombies(dt) {
  // aura krzykaczy
  for (const e of Z.list) e.aura = 1;
  for (const a of Z.list) if (!a.dead && a.def.aura) {
    const r2 = a.def.aura * a.def.aura;
    for (const e of Z.list) if (e !== a && !e.dead && dist2(e.x, e.z, a.x, a.z) < r2) e.aura = 1.45;
  }
  for (let i = Z.list.length - 1; i >= 0; i--) {
    const e = Z.list[i], d = e.def, B = e.B;
    if (B.flash > 0) B.flash = Math.max(0, B.flash - dt * 7);
    if (e.dead) {
      e.deathT += dt;
      const k = Math.min(1, e.deathT / 0.45);
      B.root.rotation.x = -k * 1.45;
      if (e.deathT > 2.2) B.root.position.y -= dt * 0.35;
      if (e.deathT > 3.2) Z.list.splice(i, 1);
      continue;
    }
    if (e.rise > 0) { e.rise -= dt * 1.2; B.root.position.y = -e.rise * 0.6; if (chance(0.4)) puff(e.x, 0.05, e.z, 0x4a3a2a, 1, 0.12); continue; }
    // zdolności
    if (d.phase) {
      e.phaseT += dt;
      const ph = (e.phaseT % 4) > 2.6;
      if (ph !== e.phased) { setGhost(e, ph); if (ph) sfx('phase'); }
    }
    if (d.regen && GAME.time - e.lastHit > 1) e.hp = Math.min(e.max, e.hp + d.regen * Z.hpMul * dt);
    e.abil -= dt;
    if (d.raise && e.abil <= 0) {
      e.abil = 5;
      for (let k = 0; k < 2; k++) spawnZombie('walker', Math.max(0, e.s - rr(0.4, 1.2)), { rise: true });
      puff(e.x, 0.4, e.z, 0xff3a3a, 6, 0.15); sfx('raise');
    }
    if (d.freeze && e.abil <= 0) {
      e.abil = 7;
      let n = 0;
      for (const t of T.list) if (dist2(t.pad.x, t.pad.z, e.x, e.z) < 3.5 * 3.5) { t.frozen = 3; n++; }
      burst(e.x, 0.8, e.z, 30, { sp: 4, up: 3, life: 0.8, size: 0.1, color: [0xd8f4ff, 0x9fd8ff], glow: true, grav: 3 });
      flash(0x9fe8ff, 12, 5, e.x, 1.5, e.z, 0.4); sfx('freeze');
      if (n) showNote('Zamrożenie!', n + ' wież zamarzło na 3 sekundy.');
    }
    if (d.brood && e.abil <= 0) {
      e.abil = 6;
      for (let k = 0; k < 3; k++) spawnZombie('mini', Math.max(0, e.s - rr(0.2, 0.8)));
      puff(e.x, 0.4, e.z, 0xb6ff6a, 8, 0.2); sfx('raise');
    }
    // boss miażdży żołnierzy, obok których przechodzi
    if (d.boss) {
      e.cd -= dt;
      if (e.cd <= 0 && nearestSoldier(e.x, e.z, 0.9)) {
        e.cd = 1.5;
        for (const t of T.list) for (const s of t.soldiers) if (!s.dead && dist2(s.x, s.z, e.x, e.z) < 0.9) hurtSoldier(s, 60);
        shake(0.15); sfx('smash'); puff(e.x, 0.1, e.z, 0x6a5a4a, 6, 0.25);
      }
    }
    // walka z żołnierzem
    let moving = true;
    if (e.blockedBy) {
      moving = false;
      e.cd -= dt;
      if (e.cd <= 0) {
        e.cd = d.boss ? 1.5 : 1;
        hurtSoldier(e.blockedBy, d.dmg * 2.5);
      }
    } else if (d.spit) {
      const s = nearestSoldier(e.x, e.z, 2.6);
      if (s) {
        moving = false;
        e.cd -= dt;
        if (e.cd <= 0) {
          e.cd = 1.8;
          Z.spits.push({ x0: e.x, z0: e.z, x1: s.x, z1: s.z, t: 0, T: 0.7, s });
          sfx('spit');
        }
      }
    }
    // ruch
    let sp = d.speed * e.speedVar * e.aura;
    if (d.enrage) sp *= 1 + (1 - e.hp / e.max) * 1.1;
    e.speedNow = moving ? sp : 0;
    if (moving) e.s += sp * dt;
    pathAt(e.s, _p);
    // lekkie przesunięcie w bok, żeby tłum nie szedł gęsiego
    const tx = _p.x - _p.dz * e.lat, tz = _p.z + _p.dx * e.lat;
    if (moving) { e.dirx = _p.dx; e.dirz = _p.dz; }
    e.x = tx; e.z = tz;
    B.root.position.x = e.x; B.root.position.z = e.z;
    let yaw = Math.atan2(e.dirx, e.dirz);
    if (e.blockedBy) yaw = Math.atan2(e.blockedBy.x - e.x, e.blockedBy.z - e.z);
    B.root.rotation.y = yaw;
    e.phase += dt * sp * (d.gait === 'dog' ? 9 : d.gait === 'run' ? 8 : 6) / Math.max(0.5, e.sc) * (moving ? 1 : 0.4) + (moving ? 0 : dt * 2);
    animBody(B, d.gait, e.phase, moving, d.boss ? 0.2 : 0.3);
    // dotarcie do fortecy
    if (e.s >= MAP.pathLen - 1.4) {
      GAME.fortHit(d.dmg, e);
      e.dead = true; e.deathT = 3.2;
      if (e.def.boss) { GAME.boss = null; hideBoss(); }
      if (e.blockedBy) { e.blockedBy.block = null; e.blockedBy = null; }
    }
  }
  // kwas plujących
  for (let i = Z.spits.length - 1; i >= 0; i--) {
    const p = Z.spits[i];
    p.t += dt;
    const k = p.t / p.T;
    const x = lerp(p.x0, p.x1, k), z = lerp(p.z0, p.z1, k), y = 0.5 + Math.sin(k * Math.PI) * 1.2;
    spawnPart({ x, y, z, vx: 0, vy: 0, vz: 0, life: 0.25, size: 0.09, color: 0x8aff3a, glow: true, grav: 0 });
    if (k >= 1) {
      Z.spits.splice(i, 1);
      puff(p.x1, 0.2, p.z1, 0x8aff3a, 5, 0.15);
      if (!p.s.dead && dist2(p.s.x, p.s.z, p.x1, p.z1) < 0.6) hurtSoldier(p.s, 12);
    }
  }
}

function clearZombies() {
  Z.list = []; Z.spits = [];
  GAME.boss = null; hideBoss();
}
